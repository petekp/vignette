#!/usr/bin/env python3
"""Fails when code outside `Identity.swift` builds a path into the app's own `Library` folders.

`Identity` builds the app's Application Support, Caches and WebKit folders from `Launch.dataHome`,
which keeps a test launch out of the person's own app's folders whatever its bundle id. A path that
joins `Library` with the app's bundle id anywhere else starts from the home folder instead, so a
test copy with the shipped bundle id would read, change or remove the person's own app's data.
Use `Identity.applicationSupportURL`, `cachesURL` or `webKitURL`, or add the folder to `Identity`.

A statement is flagged when it holds a string naming `Library` and the app's bundle id
(`bundleID` or `bundleIdentifier`). `scripts/build.sh --test` runs this before the build. Pass a
repository folder to check another checkout. Exit status 1 lists each problem as `file:line: ...`.
"""
import importlib.util
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("agent_folders", HERE / "check-agent-folders.py")
agent_folders = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent_folders)

THE_ONE_PLACE = "Identity.swift"
LIBRARY = re.compile(r'"[^"\n]*\bLibrary\b')
BUNDLE_ID = re.compile(r"\bbundleID\b|\bbundleIdentifier\b")


PARENTHESES = {"(": 1, "[": 1, ")": -1, "]": -1}


def statements(code):
    """`(start, end)` of each statement in comment-free code: up to a newline outside parentheses
    and square brackets that the next line does not continue with a `.`."""
    start, depth = 0, 0
    for i, c in enumerate(code):
        depth = max(depth + PARENTHESES.get(c, 0), 0)
        if c == "\n" and depth == 0 and not code[i + 1:].lstrip(" \t").startswith("."):
            yield start, i
            start = i + 1
    yield start, len(code)


def app_library_paths(text):
    """The line of each statement that joins `Library` with the app's bundle id."""
    code = agent_folders.code_only(text)
    with_strings = agent_folders.code_only(text, keep_strings=True)
    for start, end in statements(code):
        statement = with_strings[start:end]
        if LIBRARY.search(statement) and BUNDLE_ID.search(statement):
            yield agent_folders.line_of(text, start + len(statement) - len(statement.lstrip()))


def main():
    repo = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else HERE.parent)
    problems = []
    for path in sorted(repo.glob("Sources/**/*.swift")):
        if path.name == THE_ONE_PLACE:
            continue
        for line in app_library_paths(path.read_text()):
            problems.append(f"{path.relative_to(repo)}:{line}: a path into Library with the app's bundle id; "
                            "use Identity's folders, which keep a test launch out of the person's own app's data")
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(f"app data paths: {len(problems)} problem(s)", file=sys.stderr)
        return 1
    print("app data paths: every one comes from Identity")
    return 0


if __name__ == "__main__":
    sys.exit(main())
