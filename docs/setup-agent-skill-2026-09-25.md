# The agent skill in the setup window (2026-09-25)

Status: approved 2026-09-25, not built. It is built together with `docs/settings-polish-2026-09-25.md`.

The setup window will offer Vignette's skill for each coding agent it finds, switched on, and
install it when the window closes. Pete asked for this on 2026-09-25, after the request line
stopped carrying the reply helper (`docs/request-line-2026-09-25.md`).

## Why now

- **Replies now need the skill.** The line Send puts in a session names only the image. The skill
  tells the agent where the helper and the ticket are. An agent without it can read the drawing but
  cannot answer with one.
- **Today the skill waits for the second launch.** The first launch belongs to the setup window,
  which covers only the shortcut. The next launch opens Settings at Agents, once, and nothing is
  installed until the person presses Install for each agent (`AppDelegate.offerAgentSkill`). A
  person who closes that window has no replies, and nothing says why.
- **Setup is where people connect their tools.** Asking there, with the rest of setup, is the one
  moment the person expects the question.

## What the person sees

A new section in the setup window, between the shortcut and Launch at login. It shows one row for
each agent directory Vignette finds (`SkillInstaller.statuses`), in the order the Agents tab uses:

- **An agent without the skill:** a switch with the agent's name, on.
- **An agent that has it:** the agent's name and "Installed", with no switch. Setup only adds;
  removing stays in the Agents tab.
- **No agent found:** no section. There is nothing to decide.

Under the rows, one line. Draft, to go through `refine-prose` before it ships:

> Installs Vignette's skill in your coding agents, so they can show you images and answer your
> drawings with drawings of their own.

The switches are on because the person installed Vignette to work with those agents, and a switch
they can see is still their choice. An agent directory from a one-time trial gets a skill folder it
never reads, which costs nothing.

## When it installs

When the window closes, for every row whose switch is on. That is when the window applies Launch at
login too, so both of its switches work the same way, and flipping a switch back and forth writes
nothing under `~/.claude` or `~/.codex` until the person is done. The install goes through
`AppDelegate.installAgentSkill`, which logs a `[skill]` line per copy and shows a toast for one
that failed. The `[setup] done` line gains the agents chosen.

Closing the window also records the offer as made (`agentSkill` becomes `off`), so the next launch
does not open Settings at Agents to ask again.

## What stays

- **The second-launch offer,** for a settings file that finished setup before this change and never
  had its second launch. Setup now records the offer, so a new install never reaches it.
- **The Agents tab,** as the place to install, update and remove later. Its rows become switches,
  the same rows the setup window shows (`docs/settings-polish-2026-09-25.md`, item 11).
- **Launch keeps copies current:** it rewrites a copy that differs from the bundle, installs nothing
  new, and removes nothing.

## Changes

1. `SetupView`: the agents section. The rows come from `SkillInstaller.statuses(home:)`, read once
   when the window opens. The switches start on and live in the window's own state.
2. `SetupWindowController`: takes an `install: ([URL]) -> Void` from `AppDelegate`, as it takes
   `hasScreenshots`. `windowWillClose` installs into the roots switched on, sets `agentSkill` to
   `off`, and adds `skill=<agents>` to `[setup] done`.
3. `AppDelegate`: passes `installAgentSkill` in. The launch order is unchanged: setup on a first
   launch, `startAgentSkill` otherwise.
4. The Agents tab's line, as above.
5. `AGENTS.md`: the setup rule no longer says the skill offer waits for the next launch, and the
   skill rule says setup installs it.

## Checks

- **Unit tests.** `SkillInstallerTests` already covers the install itself: a fresh copy, a rewrite,
  links, and two agents sharing one folder. No new permanent test: the new code is a list of
  switches and one call.
- **Live, on the demo copy only.** Its scratch settings get `"setup": "unasked"`, so it opens the
  setup window. The install must not reach Pete's own `~/.claude` or `~/.codex`, so the demo runs
  with `HOME` set to a scratch folder holding empty `.claude` and `.codex`. Whether
  `homeDirectoryForCurrentUser` follows `HOME` is not checked yet. If it does not, the live check
  waits for Pete's go-ahead, since it would write into his real agent folders.
- **What to look at:** the window with both rows on, a capture of it, closing it, the `[skill]
  installed` lines, both skill folders on disk, and a second launch that opens no Settings window.

## Decided

**People who already closed the offer** are left alone. Their settings say `agentSkill: off`, and
some have no skill, so replies do not work for them until they install it in the Agents tab.
Vignette shipped on 2026-09-24, so very few people are in this state. Pete approved the plan with
this recommendation in it.
