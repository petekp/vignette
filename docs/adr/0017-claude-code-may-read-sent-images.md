# Turning on Claude Code lets it read sent images without asking

A Claude Code session opens a sent image itself, and a session not allowed to read it stops on a
permission prompt that Vignette cannot see. So turning Claude Code on, in setup or the Agents tab,
adds one `Read` rule for Vignette's request images to Claude Code's own settings, and turning it
off removes the rule. Someone who turns Claude Code on has chosen to send it images, and letting
it read them is part of that choice.

## Considered options

- Leaving the rule off by default.
- A skill's `allowed-tools`, which made Claude Code ask to use the skill instead.

Sources: AGENTS.md, commit f773f9c.
