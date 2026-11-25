#!/usr/bin/env python3
"""Fails when a state-machine map in `docs/state-machines/` cites a source line number.

A map names a symbol and the file it is in (`docs/state-machines.md`). A line number drifts with
every edit: by 2026-11-25 about 1,700 had, many pointing past the end of their file. This reads
these forms of citation, in code spans too: a colon and a number after a name or alone
(`Foo.swift:123`, `LiveAsksTests:984`, `:~915`, `Foo.swift:7, 13`), `L123`, `line 123` or
`lines 12-30`, a bare number of three digits or more before a comma, a closing parenthesis or the
line's end (`set at 805 and 747`, `release`, `1580-1587`), and a number of two digits or more
alone in parentheses (`guard (854)`, `(77-83)`). A colon between two numbers, as in a time or a
ratio, is not read. A count written the same way, such as `batch (30)`, is read as a citation too:
write `30 cards` instead.

`DATED` names the files that cite lines on purpose, each with why: the findings and the issues
cite lines at the commit `findings.md` names. A file there that no longer exists fails too, so the
list stays true. `scripts/build.sh --test` runs this before the build. Pass a repository folder
to check another checkout. Exit status 1 lists each problem as `file:line: ...`.
"""
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
MAPS = "docs/state-machines"

LINE_NUMBER = re.compile(
    r"(?<![\w:])[\w+.-]*(?<!\d):~?\d+"
    r"|\bL\d+\b"
    r"|\b[Ll]ines? \d+"
    r"|(?<![\w.~:/#-])\d{3,}(?:-\d+)?(?=\)|,|;|$| and \d)"
    r"|\(\d{2,}(?:-\d+)?[):]"
)

DATED = {
    "findings.md": "cites lines at commit 358d988 unless a finding names another, as its opening says",
    "issues.md": "each issue cites the lines of the finding it fixes, at that finding's commit",
}
DATED_PATTERN = "plausible-findings-*.md"
DATED_PATTERN_WHY = "plausible findings cite lines at the commit findings.md names"


def line_numbers(text):
    """`(line, citation)` for each line-number citation in a map."""
    for number, line in enumerate(text.split("\n"), 1):
        for match in LINE_NUMBER.finditer(line):
            yield number, match.group(0)


def main():
    repo = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else HERE.parent)
    folder = repo / MAPS
    dated = set(DATED) | {path.name for path in folder.glob(DATED_PATTERN)}
    problems, maps = [], 0
    for path in sorted(folder.glob("*.md")):
        if path.name in dated:
            continue
        maps += 1
        for line, citation in line_numbers(path.read_text()):
            problems.append(f"{path.relative_to(repo)}:{line}: `{citation}` is a line number, and a map "
                            "names a symbol and its file only, because line numbers drift; name the "
                            "function, type or test instead")
    for name in sorted(DATED):
        if not (folder / name).exists():
            problems.append(f"scripts/check-map-line-numbers.py: {MAPS}/{name} may cite lines but does "
                            "not exist; take it out of DATED")
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(f"map line numbers: {len(problems)} problem(s)", file=sys.stderr)
        return 1
    print(f"map line numbers: none in {maps} maps")
    return 0


if __name__ == "__main__":
    sys.exit(main())
