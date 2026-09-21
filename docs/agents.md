# For agents

The app ships a skill that teaches a coding agent the `vignette://` contract: push an image with
`add`, draw on it with `marks=`, read `<name>-annotated.png` back. It lives in
`skills/vignette/SKILL.md`, ships in the bundle, and the app is what installs it, because the app
is the only thing that knows which commands its version has.

On the first launch that finds `~/.claude` or `~/.codex`, Vignette opens Settings at the Agents
section and asks once. The window comes up without taking the keyboard from what you are doing, the
answer is recorded as `agentSkill` in settings.json, and the question never comes back. Turning the toggle on copies the skill into `~/.claude/skills/vignette` and
`~/.codex/skills/vignette`; turning it off removes those copies. A later launch rewrites a copy
that is older than the app. `open -g vignette://install-skill` does the same from a script.

The installer only ever touches a copy it made. It writes `.vignette-skill.json` beside the skill
naming the build that wrote it, and anything at that path without one, including a link to your own
copy, is left alone and answered with `not-ours`.

An agent directory whose `skills` is itself a link is skipped whole, with `linked-root`: writing
through the link would put the skill inside whatever that link points at, which on this Mac is a git
repository. Move the skill there by hand if you want it.
