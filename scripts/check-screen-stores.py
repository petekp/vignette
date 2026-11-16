#!/usr/bin/env python3
"""Fails when a type in `Sources/` stores an `NSScreen`: a `let` or `var` property whose type is
`NSScreen`, `NSScreen?` or a collection of them, or whose value is set from an `NSScreen`.

AppKit makes new `NSScreen` objects when the screens change, a Dock that moves or hides included,
and an old object keeps the `visibleFrame` it had. A type that keeps one reads that old frame.
Keep the display number (`NSScreen.displayNumber`) and look the screen up at each use, as
`ThumbnailController.pinnedDisplay` does. Local variables, parameters, computed properties and
closures that return a screen are not stored screens and are not read.

`ALLOWED` names the stored screens that read only `frame` or the scale and are set again at each
use, each with why. A name there that is no longer a stored screen fails too, so the list stays
true. Comments and strings are not read. `scripts/build.sh --test` runs this before the build.
Pass a repository folder to check another checkout. Exit status 1 lists each problem as
`file:line: ...`.
"""
import importlib.util
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("agent_folders", HERE / "check-agent-folders.py")
agent_folders = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent_folders)

TYPE_HEADER = re.compile(r"\b(?:class|struct|enum|extension|actor)\b")
PROPERTY = re.compile(r"^\s*(?:[@\w()]+\s+)*?(?:let|var)\s+(\w+)\s*(?::\s*([^={]+?))?\s*(=.*)?(\{.*)?$")
SCREEN = re.compile(r"\bNSScreen\b")

ALLOWED = {
    ("TransitionLayer.swift", "screen"):
        "reads only `frame`, and `showPanel(on:)` sets it before every flight and swallow, so the "
        "full-screen layer is sized from the screen it was just shown on; `frame` does not change "
        "with the Dock",
}


def stored_screens(text):
    """`(line, property name)` for each stored property that holds an NSScreen, outside comments."""
    code = agent_folders.code_only(text)
    stack, header = [], ""
    for number, line in enumerate(code.split("\n"), 1):
        in_types = all(stack)
        if in_types and SCREEN.search(line):
            found = PROPERTY.match(line)
            if found:
                name, declared, value, body = found.groups()
                holds_screen = bool(declared and SCREEN.search(declared) and "->" not in declared) \
                    or bool(not declared and value and SCREEN.search(value))
                if holds_screen and not (body and not value and "didSet" not in body and "willSet" not in body):
                    yield number, name
        for char in line:
            if char == "{":
                stack.append(bool(TYPE_HEADER.search(header)))
                header = ""
            elif char == "}":
                if stack:
                    stack.pop()
                header = ""
            elif char == ";":
                header = ""
            else:
                header += char
        header += " "


def main():
    repo = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else HERE.parent)
    problems, allowed_seen = [], set()
    for path in sorted(repo.glob("Sources/**/*.swift")):
        for line, name in stored_screens(path.read_text()):
            key = (path.name, name)
            if key in ALLOWED:
                allowed_seen.add(key)
                continue
            problems.append(f"{path.relative_to(repo)}:{line}: `{name}` stores an NSScreen, and AppKit "
                            "replaces its screens when they change, so its visibleFrame goes stale; keep "
                            "the display number (NSScreen.displayNumber) and look the screen up at each "
                            "use, or add it to ALLOWED in scripts/check-screen-stores.py with why it is safe")
    for file, name in sorted(set(ALLOWED) - allowed_seen):
        problems.append(f"scripts/check-screen-stores.py: {file} is allowed a stored `{name}` but has "
                        "none; take it out of ALLOWED")
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(f"screen stores: {len(problems)} problem(s)", file=sys.stderr)
        return 1
    print(f"screen stores: none, and {len(allowed_seen)} allowed that read only frame or scale")
    return 0


if __name__ == "__main__":
    sys.exit(main())
