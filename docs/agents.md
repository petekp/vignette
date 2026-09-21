# For agents

The agent feature is secondary and experimental. It is a skill that teaches Claude Code or Codex
the `vignette://` contract: push an image with `add`, draw on it with `marks=`, read
`<name>-annotated.png` back. The skill's text is at `skills/vignette/SKILL.md` in the repo, and it
ships in the app bundle. The marks format is in [commands.md](commands.md).

## Installing

The first launch that finds `~/.claude` or `~/.codex` opens Settings at the Agents section and asks
once. The answer is recorded as `agentSkill` in settings.json, which holds `unasked`, `on`, or
`off`. On copies the skill into `~/.claude/skills/vignette` and `~/.codex/skills/vignette`. Off
removes those copies. A later launch rewrites a copy that is older than the app.
`open -g vignette://install-skill` does the same from a script.

## What the installer will not touch

The installer only touches a copy it made. It writes `.vignette-skill.json` beside the skill, naming
the build that wrote it. Anything at that path without that marker is left alone and answered with
`not-ours`, including a link to your own copy.

A `skills` directory that is itself a link is skipped whole, with `linked-root`. Writing through the
link would put the skill wherever the link points, which is not where you asked for it. Move the
skill there by hand if you want it.
