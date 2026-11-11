#!/usr/bin/env python3
"""Fails when agent-folder code can fall back to the person's own home or environment.

A function in `Sources/AgentPlugin*.swift` takes its home folder and environment as arguments.
A default of `ProcessInfo.processInfo.environment`, `NSHomeDirectory()` or
`homeDirectoryForCurrentUser` lets a test that leaves the argument out reach the person's real
`~/.claude`, `~/.codex` or `~/.agents`. The app reads its own through `AgentPlugin.appHome`,
`appEnvironment` and the `app...` entry points in `AgentPluginFolders.swift`. A test builds
`AgentPlugins` with every folder named, never with `AgentPlugins()`, the app's own.

`scripts/build.sh --test` runs this before the build. Pass a repository folder to check another
checkout. Exit status 1 lists each problem as `file:line: ...`.
"""
import pathlib
import re
import sys

PROCESS_VALUES = ("ProcessInfo.processInfo.environment", "NSHomeDirectory()", "homeDirectoryForCurrentUser")

# Defaults that stay, by file and function name, each with the code that still relies on it.
ALLOWED = {
    ("AgentPlugin.swift", "root"): "CodexConnection.swift's isLoaded(_:codexHome:) calls it without an environment",
}

DECLARATION = re.compile(r"\b(?:func\s+(\w+)|(init))\s*(?:<[^>]*>)?\s*\(")
NO_ARGUMENT_PLUGINS = re.compile(r"\bAgentPlugins\s*\(\s*\)")


def without_comments(text):
    """Blanks `//` comments and string literals, keeping every newline, so line numbers hold."""
    out, i, n = [], 0, len(text)
    while i < n:
        if text.startswith("//", i):
            end = text.find("\n", i)
            end = n if end < 0 else end
            out.append(" " * (end - i))
            i = end
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            end = n if end < 0 else end + 2
            out.append(re.sub(r"[^\n]", " ", text[i:end]))
            i = end
        elif text[i] == '"':
            j = i + 1
            while j < n and text[j] != '"' and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            out.append('"' + " " * (j - i - 1) + ('"' if j < n and text[j] == '"' else ""))
            i = j + 1 if j < n and text[j] == '"' else j
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def parameters(text, start):
    """The parameter list's text from the character after `(`, and where it ends."""
    depth, i = 1, start
    while i < len(text) and depth:
        depth += {"(": 1, "[": 1, "{": 1, ")": -1, "]": -1, "}": -1}.get(text[i], 0)
        i += 1
    return text[start:i - 1], i


def top_level_split(text, separator):
    parts, depth, last = [], 0, 0
    for i, c in enumerate(text):
        if c == ">" and text[i - 1:i] == "-":
            continue
        depth += {"(": 1, "[": 1, "{": 1, "<": 1, ")": -1, "]": -1, "}": -1, ">": -1}.get(c, 0)
        if c == separator and depth == 0:
            parts.append((last, text[last:i]))
            last = i + 1
    parts.append((last, text[last:]))
    return parts


def defaults(path):
    text = without_comments(path.read_text())
    for match in DECLARATION.finditer(text):
        name = match.group(1) or match.group(2)
        params, _ = parameters(text, match.end())
        for offset, param in top_level_split(params, ","):
            pieces = top_level_split(param, "=")
            if len(pieces) < 2:
                continue
            default = param[pieces[1][0]:]
            for value in PROCESS_VALUES:
                if value in default:
                    start = match.end() + offset + len(param) - len(param.lstrip())
                    line = text.count("\n", 0, start) + 1
                    label = param.split(":")[0].split()[-1] if ":" in param else param.strip()
                    yield line, name, label, value


def main():
    repo = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parent.parent)
    problems = []
    used = set()
    for path in sorted(repo.glob("Sources/AgentPlugin*.swift")):
        for line, name, label, value in defaults(path):
            if (path.name, name) in ALLOWED:
                used.add((path.name, name))
                continue
            problems.append(f"Sources/{path.name}:{line}: {name}'s `{label}` defaults to {value}; take it as an argument, "
                            "or read the app's own through AgentPlugin.appHome and appEnvironment in an app entry point")
    for path in sorted(repo.glob("Tests/**/*.swift")):
        text = without_comments(path.read_text())
        for match in NO_ARGUMENT_PLUGINS.finditer(text):
            line = text.count("\n", 0, match.start()) + 1
            problems.append(f"{path.relative_to(repo)}:{line}: AgentPlugins() is the app's own, on the person's folders; "
                            "name home, environment and personHome")
    for file, name in sorted(set(ALLOWED) - used):
        problems.append(f"scripts/check-agent-folders.py: {file} {name} no longer has such a default; remove it from ALLOWED")
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(f"agent folders: {len(problems)} problem(s)", file=sys.stderr)
        return 1
    print("agent folders: no defaults to the person's own")
    return 0


if __name__ == "__main__":
    sys.exit(main())
