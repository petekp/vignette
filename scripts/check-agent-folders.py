#!/usr/bin/env python3
"""Fails when agent-folder code can fall back to the person's own home or environment.

A function in `Sources/AgentPlugin*.swift` takes its home folder and environment as arguments.
A default that reads the process's home or environment lets a test that leaves the argument out
reach the person's real `~/.claude`, `~/.codex` or `~/.agents`. That covers a parameter's default
and a non-static `var` or `let` initializer, which is also the default of a struct's memberwise
init. The app reads its own through `AgentPlugin.appHome`, `appEnvironment` and the `app...` entry
points in `AgentPluginFolders.swift`, so those names count as the process's too. A test names every
folder: it never builds `AgentPlugins()` or reads `AgentPlugin.app...` or the static `claudeRoot`.

`scripts/build.sh --test` runs this before the build. Pass a repository folder to check another
checkout. Exit status 1 lists each problem as `file:line: ...`.
"""
import pathlib
import re
import sys

# Matched with every space removed.
PROCESS_VALUE = re.compile(r"ProcessInfo\.processInfo\.environment|NSHomeDirectory\(\)|homeDirectoryForCurrentUser"
                           r"|URL\.homeDirectory\b|\bapp(?:Home|Environment)\b")

# Defaults that stay, by file and declaration name, each with the code that still relies on it.
ALLOWED = {
    ("AgentPlugin.swift", "root"): "CodexConnection.swift's isLoaded(_:codexHome:) calls it without an environment",
}

DECLARATION = re.compile(r"\b(?:func\s+(\w+)|(init)[?!]?|(subscript))\s*")
MODIFIER = r"(?:private|fileprivate|internal|public|open|package|final|lazy|weak|unowned|nonisolated|override|static|class)(?:\(set\))?\s+"
PROPERTY = re.compile(r"^[ \t]*(?:@\w+(?:\([^)]*\))?\s+)*((?:" + MODIFIER + r")*)(?:var|let)\s+(\w+)", re.M)
TEST_READS = [
    (re.compile(r"\bAgentPlugins\s*(?:\.\s*init\s*)?\(\s*\)"), "AgentPlugins() is the app's own, on the person's folders; name home, environment and personHome"),
    (re.compile(r"\bAgentPlugin\s*\.\s*app\w+"), "the app's own folders; pass a scratch home and environment instead"),
    (re.compile(r"\bAgentPlugin\s*\.\s*claudeRoot\b(?!\s*\()"), "the app's own Claude Code folder; call claudeRoot(home:environment:personHome:)"),
]
OPENING = {"(": 1, "[": 1, "{": 1, ")": -1, "]": -1, "}": -1}


def code_only(text, keep_strings=False):
    """Blanks comments and the literal text of strings, keeping each string's interpolations and
    every newline, so a value inside `\\( )` is still seen and line numbers hold. With
    `keep_strings`, strings stay as written. Every character keeps its index either way."""
    out, i, n = [], 0, len(text)

    def blank(s):
        return re.sub(r"[^\n]", " ", s)

    def literal(s):
        return s if keep_strings else blank(s)

    while i < n:
        if text.startswith("//", i):
            end = text.find("\n", i)
            end = n if end < 0 else end
            out.append(blank(text[i:end]))
            i = end
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            end = n if end < 0 else end + 2
            out.append(blank(text[i:end]))
            i = end
        elif text[i] == '"':
            close = '"""' if text.startswith('"""', i) else '"'
            out.append(close)
            i += len(close)
            while i < n and not text.startswith(close, i) and not (close == '"' and text[i] == "\n"):
                if text.startswith("\\(", i):
                    depth, j = 1, i + 2
                    while j < n and depth:
                        depth += {"(": 1, ")": -1}.get(text[j], 0)
                        j += 1
                    out.append(text[i:j] if keep_strings else "  " + text[i + 2:j - 1] + " ")
                    i = j
                elif text[i] == "\\":
                    out.append(literal(text[i:i + 2]))
                    i += 2
                else:
                    out.append(literal(text[i]))
                    i += 1
            if text.startswith(close, i):
                out.append(close)
                i += len(close)
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def balanced(text, start, pairs):
    """The index after the bracket that closes the one at `start`."""
    depth, i = 0, start
    while i < len(text):
        c = text[i]
        if not (c == ">" and text[i - 1] == "-"):
            depth += pairs.get(c, 0)
        i += 1
        if depth == 0:
            return i
    return i


def top_level_split(text, separator):
    parts, depth, last = [], 0, 0
    for i, c in enumerate(text):
        if c == ">" and text[i - 1:i] == "-":
            continue
        depth += {**OPENING, "<": 1, ">": -1}.get(c, 0)
        if c == separator and depth == 0:
            parts.append((last, text[last:i]))
            last = i + 1
    parts.append((last, text[last:]))
    return parts


def reads_process(expression):
    found = PROCESS_VALUE.search(re.sub(r"\s+", "", expression))
    return found.group(0) if found else None


def line_of(text, index):
    return text.count("\n", 0, index) + 1


def defaults(text):
    """`(line, declaration name, parameter or property, value)` for each default that reads the process."""
    for match in DECLARATION.finditer(text):
        name = match.group(1) or match.group(2) or match.group(3)
        i = match.end()
        if i < len(text) and text[i] == "<":
            i = balanced(text, i, {"<": 1, ">": -1})
            while i < len(text) and text[i].isspace():
                i += 1
        if i >= len(text) or text[i] != "(":
            continue
        end = balanced(text, i, OPENING)
        params = text[i + 1:end - 1]
        for offset, param in top_level_split(params, ","):
            pieces = top_level_split(param, "=")
            value = len(pieces) > 1 and reads_process(param[pieces[1][0]:])
            if value:
                label = param.split(":")[0].split()[-1] if ":" in param else param.strip()
                yield line_of(text, i + 1 + offset + len(param) - len(param.lstrip())), name, label, value
    for match in PROPERTY.finditer(text):
        if re.search(r"\b(?:static|class)\b", match.group(1)):
            continue
        rest = text[match.end():]
        pieces = top_level_split(rest[:balanced_statement(rest)], "=")
        value = len(pieces) > 1 and reads_process(rest[pieces[1][0]:balanced_statement(rest)])
        if value:
            yield line_of(text, match.start(2)), match.group(2), match.group(2), value


def balanced_statement(text):
    """The length of a declaration's remainder: up to the first newline outside brackets."""
    depth = 0
    for i, c in enumerate(text):
        depth += OPENING.get(c, 0)
        if c == "\n" and depth <= 0:
            return i
    return len(text)


def main():
    repo = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parent.parent)
    problems, used = [], set()
    for path in sorted(repo.glob("Sources/AgentPlugin*.swift")):
        for line, name, label, value in defaults(code_only(path.read_text())):
            if (path.name, name) in ALLOWED:
                used.add((path.name, name))
                continue
            problems.append(f"Sources/{path.name}:{line}: {name}'s `{label}` defaults to {value}; take it as an argument, "
                            "and read the app's own only in an app entry point")
    for path in sorted(repo.glob("Tests/**/*.swift")):
        text = code_only(path.read_text())
        for pattern, why in TEST_READS:
            for match in pattern.finditer(text):
                problems.append(f"{path.relative_to(repo)}:{line_of(text, match.start())}: {match.group(0)} is {why}")
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
