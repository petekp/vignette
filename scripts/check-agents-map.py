#!/usr/bin/env python3
import fnmatch
import pathlib
import re
import sys


def map_patterns(text):
    patterns = set()
    for token in re.findall(r"`([^`\n]+)`", text):
        name = token.removeprefix("Sources/")
        if not re.fullmatch(r"[A-Za-z0-9_+.*?\[\]-]+", name):
            continue
        if name.endswith((".swift", ".metal")) or any(char in name for char in "*?"):
            patterns.add(name)
    return sorted(patterns)


def main():
    repo = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parent.parent)
    patterns = map_patterns((repo / "AGENTS.md").read_text())
    files = sorted(path for path in (repo / "Sources").rglob("*") if path.is_file())
    unnamed = [path for path in files
               if not any(fnmatch.fnmatchcase(path.name, pattern) for pattern in patterns)]
    for path in unnamed:
        print(f"{path.relative_to(repo)}: no filename or glob in AGENTS.md names this file", file=sys.stderr)
    if unnamed:
        print(f"agents map: {len(unnamed)} unnamed file(s)", file=sys.stderr)
        return 1
    print("agents map: every Sources file is named in AGENTS.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
