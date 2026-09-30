# For agents

The agent features are secondary and experimental. They come as a plugin for Claude Code and Codex
that ships inside the app. The plugin carries a skill that teaches the agent the `vignette://`
contract: push an image with `add`, draw on it with `marks=`, read `<name>-annotated.png` back, and
answer a drawing with one of its own. For Claude Code, the plugin also delivers what Send sends. The
skill's text is at `skills/vignette/SKILL.md` in the repo, and the marks format is in
[commands.md](commands.md).

## Installing

Setup's last page offers the plugin when this Mac has `~/.claude` or `~/.codex`, with a switch for
each agent. Setup installs the ones left on when it closes. A settings file from before that page,
or a setup closed before reaching it, gets the offer once, as the Settings window at the Agents
section. `agentSkill` in settings.json records only that the offer was made. The Agents tab lists
every agent found on this Mac with a switch that adds or removes the plugin.
`open -g vignette://install-skill` installs it for every agent from a script.

Each agent installs the plugin with its own command-line tool, from a copy of the plugin the app
writes to `~/Library/Application Support/<bundle id>/agent-plugin`:

| | Claude Code | Codex |
|---|---|---|
| Install | `claude plugin marketplace add`, then `claude plugin install vignette@vignette --scope user` | `codex plugin marketplace add`, then `codex plugin add` |
| Needs | the `claude` command | the `codex` command |

Vignette looks for each command where its installer puts it, then in the folders nvm, fnm, Volta,
Bun, pnpm, asdf and mise put a global command in, then on your login shell's `PATH`. The shell is
asked once at launch, in the background. Without the command, the switch is off and says which
command is missing. A Claude Code session
that was already open when you installed the plugin needs `/reload-plugins` before it can take a
drawing.

A launch updates an installed plugin when the app carries a different version of it. It installs
nothing new, with one exception: an agent that has the skill from before the plugin gets the plugin
in its place. The old skill folder is then removed. A link is left where it is, since it is your
own arrangement.

## Receiving a drawing in Claude Code

Each running Claude Code session with the plugin has an inbox folder under
`~/Library/Application Support/<bundle id>/claude-sessions/`. Send writes one line into it, and the
plugin's monitor hands the line to the session between turns, as an event named "Drawing from
Vignette". A session that is busy gets it when its turn ends. Closing the session removes its inbox,
and the session leaves Send's menu.

This works in any terminal. herdr is optional. When it runs, Send starts on the session in herdr's
focused pane. Otherwise Send starts on the session used last.

The line names the drawing's path, which is outside the session's project. Claude Code's auto mode
asks once, the first time, whether it may read outside the working directories. Setup and the
Agents tab offer a read rule for `~/.claude/settings.json` that lets Claude Code open sent drawings
without asking in the other modes.
