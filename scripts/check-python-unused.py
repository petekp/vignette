#!/usr/bin/env python3
"""Fails when pyflakes reports a problem in the Python under `media/` or `scripts/e2e/`: an unused
import or assignment, an undefined name, a redefinition and the rest of what pyflakes reads.

It runs `python3 -m pyflakes` when that Python has pyflakes, and otherwise `uvx pyflakes` at the
version `PYFLAKES` names, which uv downloads once and keeps. When neither is there this fails and
says how to get one, since a check that skips passes without reading anything.
`scripts/build.sh --test` runs this before the build. Pass a repository folder to check another
checkout. Exit status 1 lists each problem as `file:line:column: ...`.
"""
import importlib.util
import pathlib
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
FOLDERS = ["media", "scripts/e2e"]
PYFLAKES = "pyflakes==4.1.0"


def pyflakes_command():
    if importlib.util.find_spec("pyflakes"):
        return [sys.executable, "-m", "pyflakes"]
    uvx = shutil.which("uvx")
    if uvx:
        return [uvx, PYFLAKES]
    return None


def main():
    repo = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else HERE.parent)
    command = pyflakes_command()
    if not command:
        print("python unused: pyflakes is not installed and uvx is not on PATH, so media/ and "
              "scripts/e2e/ were not checked; install uv (`brew install uv`) or pyflakes "
              "(`python3 -m pip install pyflakes`)", file=sys.stderr)
        return 1
    result = subprocess.run(command + FOLDERS, cwd=repo, capture_output=True, text=True)
    if result.returncode != 0:
        print((result.stdout + result.stderr).strip(), file=sys.stderr)
        print("python unused: pyflakes found the problems above", file=sys.stderr)
        return 1
    print(f"python unused: none in {', '.join(FOLDERS)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
