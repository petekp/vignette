#!/usr/bin/env python3
"""Fails when code outside `ScreenLink.swift` makes a display link with `displayLink(target:`.

A display's link stops with the display. A link made on `NSScreen.main` stops ticking when that
display is unplugged, and whatever it drives freezes where it was. `ScreenLink` moves its link to
the main screen of the moment whenever the screens change. Use it for anything not tied to one
screen.

`ALLOWED` names the files whose links are tied to one screen on purpose, each with why. A file
there that no longer makes a link fails too, so the list stays true. Comments and strings are not
read. `scripts/build.sh --test` runs this before the build. Pass a repository folder to check
another checkout. Exit status 1 lists each problem as `file:line: ...`.
"""
import importlib.util
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("agent_folders", HERE / "check-agent-folders.py")
agent_folders = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent_folders)

THE_ONE_PLACE = "ScreenLink.swift"
DISPLAY_LINK = re.compile(r"\bdisplayLink\s*\(\s*target\s*:")

ALLOWED = {
    "PointerField.swift":
        "draws over one screen and steps at that screen's refresh; LiveInkOverlay.fit(to:) places it "
        "again, with a new link, whenever the screens change",
    "WindowRemoval.swift":
        "counts refreshes of the display that shows the window's replacement, so the window goes only "
        "once that display has drawn it; if that display is unplugged within those three refreshes, "
        "the window is not removed",
    "StackSwipeDriver.swift":
        "steps the swipe's spring at the refresh of the display the stack is drawn on "
        "(ThumbnailController.screen); a spring under way when that display is unplugged stops with it",
    "StackSweep.swift":
        "steps the drag-select's auto-scroll at the refresh of the display the stack is drawn on "
        "(ThumbnailController.screen); an auto-scroll under way when that display is unplugged stops "
        "with it",
}


def display_links(text):
    """The line of each `displayLink(target:` in the code, outside comments and strings."""
    code = agent_folders.code_only(text)
    for match in DISPLAY_LINK.finditer(code):
        yield agent_folders.line_of(text, match.start())


def main():
    repo = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else HERE.parent)
    problems, allowed_seen = [], set()
    for path in sorted(repo.glob("Sources/**/*.swift")):
        if path.name == THE_ONE_PLACE:
            continue
        for line in display_links(path.read_text()):
            if path.name in ALLOWED:
                allowed_seen.add(path.name)
                continue
            problems.append(f"{path.relative_to(repo)}:{line}: a display link made outside ScreenLink stops "
                            "with its display; use ScreenLink, or add the file to ALLOWED in "
                            "scripts/check-display-links.py with why it is tied to one screen")
    for name in sorted(set(ALLOWED) - allowed_seen):
        problems.append(f"scripts/check-display-links.py: {name} is allowed a display link but makes none; "
                        "take it out of ALLOWED")
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(f"display links: {len(problems)} problem(s)", file=sys.stderr)
        return 1
    print(f"display links: ScreenLink, and {len(allowed_seen)} allowed file(s) tied to one screen")
    return 0


if __name__ == "__main__":
    sys.exit(main())
