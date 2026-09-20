# Shipping the agent skill with the app (2026-09-18)

Someone who downloads Vignette needs their coding agent to learn the `vignette://` contract. The
app is the only thing they are guaranteed to have, and the only thing that knows which commands its
version supports. So the app carries the skill and installs it.

## What ships

`skills/vignette/SKILL.md` is the skill's home in the repo and a folder resource in the bundle
(project.yml), beside `LICENSE-tldraw.md`. A folder, not a single file, so a second file can join it
without touching the installer. `SkillInstaller.bundled` finds it; `Bundle.main` has no such folder
in the test bundle, which is why every function takes its source and roots as parameters.

## Roots and the marker

A root is a coding agent's own directory: `~/.claude`, `~/.codex`. A root that is not there means
that agent is not installed. The skill lands in `<root>/skills/vignette`, which is where both read
skills from.

Writing into another tool's directory is the whole risk, so the installer only ever touches a copy
it made. It writes `.vignette-skill.json` beside the skill, holding the app name, version, and
build. Anything at the skill's path without that marker is `not-ours`: never written, never removed.
`state(of:)` reads the path with `attributesOfItem`, which does not follow links, so a symlink to
someone's own copy is foreign even when the copy at the other end has a marker. That is the case on
the machine this was written on: `~/.claude/skills` is a link into a git repository, and a hand-made
`skills/vignette` link inside it is what the rule protects.

A copy of ours is rewritten when the marker's build differs or the files differ from the bundle's,
so a newer app refreshes the skill at launch and an edited copy is put back. Equal on both counts is
`unchanged`, and the launch says nothing at all: `[skill]` lines are only for what changed.

## The setting and the offer

One key, `agentSkill`, with three values: `unasked`, `on`, `off`. Three values rather than a bool
plus an `offered` flag, because a pair can say two things at once ("installed but never offered")
and the file should read as one answer to one question.

`on` installs at every launch and keeps the copy current. `off` removes what it installed, the
moment the toggle goes off and again at the next launch, so an answer typed into the file while the
app was closed still takes effect. Only a copy with our marker goes. `unasked` plus at least one
agent directory makes the offer, once.

The offer is the Settings window at the Agents section, not a toast with a button. The toast
(`FeedbackToast` in `StackView.swift`) is text in a capsule that fades after `ui.toastSeconds`, with
no room for a control and no time to click one; giving it a button is a change to the stack's
layout, not to this feature. Making the offer records `off` straight away, so the question is asked
once whatever the user does with the window, and the toggle in front of them is the answer.

The offer costs one `NSApp.activate`, which is the app taking focus — the one place in Vignette that
does so deliberately outside the annotator. It happens at most once per machine.

## The command

`vignette://install-skill` installs into every agent directory and sets `agentSkill` to `on`, so
later launches keep the copy current. It needs no `debug`: a script on a fresh machine is exactly
who it is for. `&root=<dir>` installs into that one directory and leaves the setting alone; that
needs `debug`, and it is how this was verified live without writing into the real `~/.claude` or
`~/.codex`.

One line answers, as every command does: `[install-skill] ok <path>=installed <path>=unchanged`, or
`error not-ours <path>=not-ours`. `not-ours` is a new `CommandError` case. The state report carries
`app.agentSkill`: the setting, and the paths where a copy of ours is sitting.
