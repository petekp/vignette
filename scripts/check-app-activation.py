#!/usr/bin/env python3
"""Fails when code in `Sources/` that is not on the allowed list brings another app forward.

Vignette brings another app forward in one case of its own: when one of its windows closes, it hands
the focus back to the app that was in front when it opened (`FocusReturn.restore`). Everything else
that brings an app forward is something the person asked for, such as opening a file or a System
Settings pane. Send never brings the destination's app forward (`docs/rules/send.md`).

These calls are counted, outside comments and strings unless noted:

- `.activate(`, `.activateWithOptions(` or `.activateIgnoringOtherApps(` on anything but Vignette
  itself (`NSApp`, `NSApplication.shared`, `NSRunningApplication.current`). A declaration such as
  `func activate()` is not a call.
- `openApplication(` and `launchApplication(`, which launch an app and bring it forward.
- `NSWorkspace.shared.open(`, which opens a file or URL in its app and brings that app forward.
- `"/usr/bin/open"`, found in strings, which runs `open` in a process of its own.

`ALLOWED` gives each file that may make these calls how many it makes, and why each brings an app
forward. A file whose count differs fails too, so a new call needs a new reason and the list stays
true. `scripts/build.sh --test` runs this before the build. Pass a repository folder to check
another checkout. Exit status 1 lists each problem as `file:line: ...` or `file: ...`.
"""
import importlib.util
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("agent_folders", HERE / "check-agent-folders.py")
agent_folders = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent_folders)

ACTIVATE = re.compile(r"([\w.]*?)\s*\.\s*(?:activate|activateWithOptions|activateIgnoringOtherApps)\s*\(")
VIGNETTE_ITSELF = {"NSApp", "NSApplication.shared", "NSRunningApplication.current"}
LAUNCH = re.compile(r"\b(?:openApplication|launchApplication)\s*\(")
WORKSPACE_OPEN = re.compile(r"\bNSWorkspace\s*\.\s*shared\s*\.\s*open\s*\(")
OPEN_TOOL = re.compile(r'"/usr/bin/open"')

ALLOWED = {
    "FocusReturn.swift": (1,
        "the hand-back: when a Vignette window closes, `restore` activates the app that was in front "
        "when Vignette opened, so the screen is left as Vignette found it"),
    "AppLocation.swift": (1,
        "relaunches Vignette itself from /Applications after the person agrees to move it there"),
    "SettingsWindow.swift": (4,
        "brings forward macOS's own Accessibility alert when it is already up, behind Settings; opens "
        "System Settings at Files and Folders or at Accessibility, and opens the log, each from a "
        "button the person pressed"),
    "AppDelegate.swift": (4,
        "the Open action opens the chosen screenshots in their app; the menu opens the screenshot "
        "folder, the log, and System Settings at Files and Folders; each is the person's own request"),
    "ProblemReport.swift": (1, "opens the problem report form in the browser when the person asks to report one"),
    "Microphone.swift": (1, "opens System Settings at the Microphone or Speech Recognition pane for the person to grant it"),
    "ScreenRecording.swift": (1, "opens System Settings at Screen Recording for the person to grant it"),
    "CodexSignIn.swift": (1, "opens Codex's sign-in page in the browser when the person signs in to Codex"),
    "ReplyCommand.swift": (1,
        "runs `open -g -a <app>` to hand an agent's reply to the Vignette that asked for it; `-g` keeps "
        "that app in the background"),
    "AnnotationController.swift": (1,
        "`toolbar.activate()` is the annotator toolbar's own method, which opens the toolbar for typing; "
        "it brings no app forward"),
}


def calls(text):
    """The line of each call that may bring another app forward."""
    code = agent_folders.code_only(text)
    for match in ACTIVATE.finditer(code):
        if match.group(1) not in VIGNETTE_ITSELF:
            yield agent_folders.line_of(text, match.start())
    for pattern in (LAUNCH, WORKSPACE_OPEN):
        for match in pattern.finditer(code):
            yield agent_folders.line_of(text, match.start())
    for match in OPEN_TOOL.finditer(agent_folders.code_only(text, keep_strings=True)):
        yield agent_folders.line_of(text, match.start())


def main():
    repo = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else HERE.parent)
    problems, seen = [], {}
    for path in sorted(repo.glob("Sources/**/*.swift")):
        lines = sorted(calls(path.read_text()))
        if not lines:
            continue
        seen[path.name] = len(lines)
        allowed = ALLOWED.get(path.name)
        if allowed is None:
            for line in lines:
                problems.append(f"{path.relative_to(repo)}:{line}: this call can bring another app forward; "
                                "Vignette brings an app forward only to hand the focus back or on the "
                                "person's own request. Add the file to ALLOWED in "
                                "scripts/check-app-activation.py with why, if it is one of those")
        elif allowed[0] != len(lines):
            problems.append(f"{path.relative_to(repo)}: {len(lines)} call(s) that can bring an app forward, "
                            f"lines {', '.join(map(str, lines))}; ALLOWED in scripts/check-app-activation.py "
                            f"says {allowed[0]}. Give the new call its reason there, or correct the count")
    for name in sorted(set(ALLOWED) - set(seen)):
        problems.append(f"scripts/check-app-activation.py: {name} is allowed to bring an app forward but "
                        "makes no such call; take it out of ALLOWED")
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(f"app activation: {len(problems)} problem(s)", file=sys.stderr)
        return 1
    print(f"app activation: {sum(seen.values())} call(s) in {len(seen)} allowed file(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
