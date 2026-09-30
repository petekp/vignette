# Keeping a test copy out of the person's agent folders (2026-09-29)

Status: a proposal. Nothing here is built.

## What happened

A test copy of Vignette, launched with scratch settings, installed its own plugin
(`vignette@vignette-demo`) into the real `~/.claude` and kept it up to date at every launch after.
Claude Code then loaded two Vignette plugins in every session. It was found and removed on
2026-09-29.

## Why it happened

`VIGNETTE_SETTINGS` moves a test copy's settings file and Apple's screenshot defaults to scratch
places. It does not move the agent folders. Every launch of any copy runs `AgentPlugins.launch`
against the real `~/.claude` and `~/.codex`:

1. It installs the plugin wherever the skill from before the plugin is (`<root>/skills/vignette`).
   Pete's `~/.claude/skills/vignette` is a link, and a link is never removed. So every copy with its
   own URL scheme finds it and installs `vignette@<its scheme>`.
2. It updates any plugin of its own id that is already installed.

Two other paths can reach the real folders from a test copy:

- **Closing setup:** the last page's switches start on, and closing the window installs the plugin.
  A fresh scratch settings file shows setup.
- **The Agents tab:** a switch or the Claude read rule, pressed in a test copy.

A fresh scratch settings file also starts with `launchAtLogin` on, so closing setup registers the
test copy as a login item.

## Proposal

**A test launch has no agent folders.** When `VIGNETTE_SETTINGS` is set, `AgentPlugin.roots`
returns none, unless the launch also moves the home folder with `CFFIXED_USER_HOME`. Then the roots
are that scratch home's, as today.

- This closes every path at once: the launch step, setup and the Agents tab all ask `roots`.
- The launch still writes the marketplace into the test copy's own Application Support. The trailer
  needs it, and it installs the stage copy's plugin into its own Claude Code config itself
  (`drive.install_plugin`).
- A test of the plugin install keeps working: launch with `CFFIXED_USER_HOME`, as
  `docs/claude-code-without-herdr-2026-09-27.md` already does.
- One log line at launch says so: `[plugin] test launch: no agent folders; launch with
  CFFIXED_USER_HOME to test them`.
- A test launch does not register a login item either, and logs that it did not.

It follows the rule `VIGNETTE_SETTINGS` already sets for Apple's defaults: a test launch never
writes what the person's own install owns.

**One permanent test**, in `AgentPluginTests`: `roots` with `VIGNETTE_SETTINGS` set returns none,
and with `CFFIXED_USER_HOME` as well returns that home's. It catches a change to `roots` or its
callers that brings the real folders back. No existing test covers the environment.

**AGENTS.md** gets one line in "The loop": a test copy never touches the agent folders, and a test
of the plugin needs `CFFIXED_USER_HOME`.

## Rejected

- **Only a rule for testers to remember** (always launch with `CFFIXED_USER_HOME`). That rule
  already existed for plugin tests, and this happened anyway. It also moves the log, which every
  driving script reads.
- **Only skip the migration for copies other than the real app.** A plugin already installed
  would still be updated, and setup and the Agents tab would still reach the real folders.
