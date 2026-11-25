#!/usr/bin/env python3
"""Fails when the site's or the demo's JavaScript (`site/`, `site/demo/`) has an unused import,
variable, function or parameter.

It runs `deno lint` with only its `no-unused-vars` rule, ignoring any deno config. The rule takes
a name that starts with `_` as unused on purpose. The inline script in `site/index.html` is not
read. CSS is not read either: the demo builds class names in template strings, so a selector that
looks unused may be used.

Deno is not part of macOS. When `deno` is not on PATH this fails and says how to install it,
since a check that skips passes without reading anything. `scripts/build.sh --test` runs this
before the build. Pass a repository folder to check another checkout. Exit status 1 lists each
problem as `file:line:column: ...`.
"""
import os
import pathlib
import re
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
FOLDER = "site"
COMPACT = re.compile(r"^file://(.+?): line (\d+), col (\d+) - (.*)$")


def main():
    repo = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else HERE.parent)
    deno = shutil.which("deno")
    if not deno:
        print("site js: deno is not installed, so the site's JavaScript was not checked; install it "
              "with `brew install deno`", file=sys.stderr)
        return 1
    result = subprocess.run(
        [deno, "lint", "--no-config", "--compact", "--rules-tags=", "--rules-include=no-unused-vars",
         str(repo / FOLDER)],
        capture_output=True, text=True, env={**os.environ, "NO_COLOR": "1"})
    if result.returncode != 0:
        for line in (result.stdout + result.stderr).splitlines():
            found = COMPACT.match(line)
            if found:
                path, row, column, message = found.groups()
                path = pathlib.Path(path).resolve().relative_to(repo.resolve())
                print(f"{path}:{row}:{column}: {message}", file=sys.stderr)
            elif line.strip() and not line.startswith(("Found ", "Checked ")):
                print(line, file=sys.stderr)
        print("site js: unused names above; remove each, or start its name with _ when it must "
              "stay, as an unused parameter before a used one", file=sys.stderr)
        return 1
    checked = result.stderr.strip().splitlines()[-1:] or ["checked"]
    print(f"site js: no unused names ({checked[0].lower()})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
