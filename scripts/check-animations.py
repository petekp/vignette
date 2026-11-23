#!/usr/bin/env python3
"""Fails when code in `Sources/` that is not on the allowed list animates on an eased or linear curve.

Every SwiftUI animation is a spring made by `Anim.spring`, and the AppKit tweens use `Tween`'s spring
curve, so an interrupted motion keeps its velocity and blends into its new target instead of
jumping. A few motions ease on purpose; `docs/rules/flights-and-presses.md` names them.

These are counted, outside comments and strings:

- `CAMediaTimingFunction(`, whether by name or by control points. Core Animation has no spring
  timing function, so every one is a Bezier curve. A name inside its parentheses, such as
  `.easeOut`, is part of that one count.
- A SwiftUI or Core Animation curve named as a member: `.easeIn`, `.easeOut`, `.easeInOut`,
  `.easeInEaseOut`, `.linear` and `.timingCurve`, written bare (`.easeOut(duration:)`) or after
  `Animation`. `.linear(duration: 0)` is not counted: it makes the change at once, with no motion.
  A member of another expression, such as `InkContrast.linear(` or a chain continued on the next
  line, is not a curve.
- `UnitCurve.` followed by one of those curves, SwiftUI's curve as a function of time.
- `kCAMediaTimingFunction` constants.

An animation that sets no curve still has one: a `CABasicAnimation` is linear, and an
`NSAnimationContext` group without a `timingFunction` takes AppKit's default. This check does not
see those.

`ALLOWED` gives each file that may ease how many of these it makes, and why. A file whose count
differs fails too, so a new curve needs a new reason and the list stays true. `scripts/build.sh
--test` runs this before the build. Pass a repository folder to check another checkout. Exit
status 1 lists each problem as `file:line: ...` or `file: ...`.
"""
import importlib.util
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("agent_folders", HERE / "check-agent-folders.py")
agent_folders = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent_folders)

TIMING_FUNCTION = re.compile(r"\bCAMediaTimingFunction\s*\(")
CURVE_NAMES = r"(?:easeInOut|easeInEaseOut|easeIn|easeOut|linear|timingCurve)\b"
CURVE_MEMBER = re.compile(r"\.\s*" + CURVE_NAMES)
ANIMATION_TYPE = re.compile(r"\bAnimation\s*$")
ENDS_AN_EXPRESSION = re.compile(r"[\w)\]?!]")
KEYWORDS_BEFORE_A_VALUE = {"return", "case", "in", "else", "throw", "try", "await", "yield"}
UNIT_CURVE = re.compile(r"\bUnitCurve\s*\.\s*" + CURVE_NAMES)
CA_CONSTANT = re.compile(r"\bkCAMediaTimingFunction\w+")
AT_ONCE = re.compile(r"\s*\(\s*duration\s*:\s*0(?:\.0*)?\s*\)")

ALLOWED = {
    "Anim.swift": (5,
        "`swiftUI` gives the card slide-in the curve `ui.slideInCurve` names, and the setting "
        "offers easeOut, easeInOut and linear beside its default, spring, for a person who wants "
        "one; `reaches` finds when the eased ones arrive"),
    "AnnotatorToolbar.swift": (4,
        "`words` and `nameSwap`: words giving way to others in one place fade out quickly and in a "
        "moment later"),
    "MarkLayers.swift": (1, "`drawOn`: a mark draws itself on as a hand draws"),
    "MenuBarIntro.swift": (3, "the menu bar intro's pill, its width and its sheen"),
    "LiveInkOverlay.swift": (9, "live ink's Core Animation layers"),
    "LiveInkHand.swift": (2, "live ink's Core Animation layers: a stroke's draw-on and its going away"),
    "LiveInkLight.swift": (3, "live ink's Core Animation layers: the light's draw-on"),
    "LiveFocus.swift": (1, "live ink's Core Animation layers: the focus lens fading in"),
    "LiveAnswerActions.swift": (2,
        "live ink's Core Animation layers: the buttons dropping into place on their layer; and the "
        "panel that holds an answer's buttons fading in with that drop"),
    "HangingPopover.swift": (2, "live ink's popovers' fades: a popover fading with its mark, and back in"),
    "LiveNotePopover.swift": (1, "live ink's popovers' fades: `fadeAway`, a closing popover (ADR 0027)"),
    "LiveReplyPopover.swift": (1, "live ink's popovers' fades: `close`, a closing popover (ADR 0027)"),
    "LiveNoteContent.swift": (1,
        "`layOut`: the note's target and its return key move to their row on an ease-out, inside "
        "the note's popover, while `fit` springs the popover's height"),
}


def closing_paren(code, open_index):
    """The index just past the parenthesis that closes the one at `open_index`."""
    depth, i = 0, open_index
    while i < len(code):
        depth += {"(": 1, ")": -1}.get(code[i], 0)
        i += 1
        if depth == 0:
            break
    return i


def is_curve_member(code, dot):
    """Whether the `.` at `dot` starts a curve written bare or after `Animation`, rather than a
    member of whatever expression comes before it, such as `InkContrast.linear(`."""
    before = code[:dot].rstrip()
    if not before or ANIMATION_TYPE.search(before):
        return True
    last = before[-1]
    if len(before) == dot:
        return not ENDS_AN_EXPRESSION.match(last)
    if last in "?!":
        return True
    if re.match(r"\w", last):
        return re.search(r"\w+$", before).group(0) in KEYWORDS_BEFORE_A_VALUE
    return last not in ")]"


def curves(text):
    """The line of each eased or linear curve in the code, outside comments and strings."""
    code = agent_folders.code_only(text)
    inside_timing_function = []
    for match in TIMING_FUNCTION.finditer(code):
        inside_timing_function.append((match.end(), closing_paren(code, match.end() - 1)))
        yield agent_folders.line_of(text, match.start())
    for match in CURVE_MEMBER.finditer(code):
        if any(start <= match.start() < end for start, end in inside_timing_function):
            continue
        if not is_curve_member(code, match.start()):
            continue
        if match.group(0).endswith("linear") and AT_ONCE.match(code, match.end()):
            continue
        yield agent_folders.line_of(text, match.start())
    for pattern in (UNIT_CURVE, CA_CONSTANT):
        for match in pattern.finditer(code):
            yield agent_folders.line_of(text, match.start())


def main():
    repo = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else HERE.parent)
    problems, seen = [], {}
    for path in sorted(repo.glob("Sources/**/*.swift")):
        lines = sorted(curves(path.read_text()))
        if not lines:
            continue
        seen[path.name] = len(lines)
        allowed = ALLOWED.get(path.name)
        if allowed is None:
            for line in lines:
                problems.append(f"{path.relative_to(repo)}:{line}: an eased or linear curve; an interrupted "
                                "motion on it jumps instead of keeping its velocity. Use Anim.spring or "
                                "Tween, or add the file to ALLOWED in scripts/check-animations.py with why "
                                "it eases")
        elif allowed[0] != len(lines):
            problems.append(f"{path.relative_to(repo)}: {len(lines)} eased or linear curve(s), lines "
                            f"{', '.join(map(str, lines))}; ALLOWED in scripts/check-animations.py says "
                            f"{allowed[0]}. Give the new curve its reason there, or correct the count")
    for name in sorted(set(ALLOWED) - set(seen)):
        problems.append(f"scripts/check-animations.py: {name} is allowed to ease but has no eased or "
                        "linear curve; take it out of ALLOWED")
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(f"animations: {len(problems)} problem(s)", file=sys.stderr)
        return 1
    print(f"animations: {sum(seen.values())} eased or linear curve(s) in {len(seen)} allowed file(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
