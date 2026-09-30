# Keeping a test copy out of the person's agent folders (2026-09-29)

Status: built on 2026-09-29.

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

## What was built

**A test launch never gets the person's own agent folders.** When `VIGNETTE_SETTINGS` is set,
`AgentPlugin.roots` leaves out `~/.claude` and `~/.codex` of the home folder in the user database
(`AgentPlugin.personHome`). `CFFIXED_USER_HOME` moves the app's home folder but not that one, so a
launch with a scratch home gets the scratch home's folders, as before. A `CLAUDE_CONFIG_DIR` or
`CODEX_HOME` that names one of the person's folders is left out too.

- This closes every path at once: the launch step, setup and the Agents tab all ask `roots`.
- The launch still writes the marketplace into the test copy's own Application Support. The trailer
  needs it, and it installs the stage copy's plugin into its own Claude Code config itself
  (`drive.install_plugin`).
- A test of the plugin install keeps working: launch with `CFFIXED_USER_HOME`, as
  `docs/claude-code-without-herdr-2026-09-27.md` already does.
- The launch logs one line for each folder it left out:
  `[plugin] test launch: left /Users/<you>/.claude alone; launch with CFFIXED_USER_HOME to test the plugin`.
- A test launch does not register a login item either, and logs
  `[login] test launch: not registered`. macOS would open the copy at login without
  `VIGNETTE_SETTINGS`, on the person's own settings file.

It follows the rule `VIGNETTE_SETTINGS` already sets for Apple's defaults: a test launch never
writes what the person's own install owns.

**One permanent test**, `testATestLaunchNeverGetsThePersonsOwnAgentFolders` in `AgentPluginTests`:
the person's folders are left out of a test launch, a scratch home's are not, and a config folder
named in the environment is still the person's. It catches a change to `roots` that brings the real
folders back. No existing test covered the environment.

**AGENTS.md** has a line in "The loop": a test copy never touches the agent folders, and a test
of the plugin needs `CFFIXED_USER_HOME`.

## Verified

- All 405 unit tests pass.
- The stage copy, launched with scratch settings on this Mac, logged the line for `~/.claude` and
  `~/.codex` and installed nothing. `claude plugin list` still showed only `vignette@vignette`.

## Rejected

- **Only a rule for testers to remember** (always launch with `CFFIXED_USER_HOME`). That rule
  already existed for plugin tests, and this happened anyway. It also moves the log, which every
  driving script reads.
- **Only skip the migration for copies other than the real app.** A plugin already installed
  would still be updated, and setup and the Agents tab would still reach the real folders.
