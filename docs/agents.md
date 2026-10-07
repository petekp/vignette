# For agents

The agent features are secondary and experimental. They come as a plugin for Claude Code and Codex
that ships inside the app. The plugin carries a skill that teaches the agent the `vignette://`
contract: push an image with `add`, draw on it with `marks=`, read its returned rendering path, and
answer a drawing with one of its own. For Claude Code, the plugin also delivers what Send sends. The
skill's text is at `skills/vignette/SKILL.md` in the repo, and the marks format is in
[commands.md](commands.md).

When a drawing has marks, the editor's Copy writes `<name>-<result-id>-annotated.png` beside the
screenshot and logs its absolute path in the JSON `files=` array. `copy-annotated` returns the same
field. Read that path; a long source name may be shortened. Each completed result stays until the
person deletes it.

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
| Needs | the `claude` command | the `codex` command, or the Codex app, which carries one |

Vignette looks for each command where its installer puts it, then in the folders nvm, fnm, Volta,
Bun, pnpm, asdf and mise put a global command in, then on your login shell's `PATH`. The shell is
asked once at launch, in the background. Without the command, the switch is off and says which
command is missing. A Claude Code session
that was already open when you installed the plugin needs `/reload-plugins` before it can take a
drawing.

A launch updates an installed plugin when the app carries a different version of it, or a changed
copy of the same version. It installs
nothing new, with one exception: an agent that has the skill from before the plugin gets the plugin
in its place. The old skill folder is then removed. A link is left where it is, since it is your
own arrangement.

## Receiving a drawing in Claude Code

Each running Claude Code process with the plugin has an inbox folder under
`~/Library/Application Support/<bundle id>/claude-sessions/<pid>/`. The inbox records the agent
session the process runs now. Send writes one line into it, and the plugin's monitor hands the line
to the session between turns, as an event named "Drawing from Vignette". A session that is busy
gets it when its turn ends. When Claude Code quits, its inbox is removed and the session leaves
Send's menu.

`/clear` and `/resume` give the process another session. Send checks that the inbox still holds the
chosen session just before it writes. When it does not, the card says the session ended or was
cleared, and nothing goes to the new session.

This works in any terminal. herdr is optional. When the Codex app was in front before Vignette,
Send starts on the thread the app shows. Otherwise, when herdr runs, Send starts on the session in
herdr's focused pane. Otherwise Send starts on the session used last.

The line names the drawing's path, which is outside the session's project, so Claude Code may ask
before it reads the drawing. Turning Claude Code on, in setup or the Agents tab, adds one rule to
`~/.claude/settings.json` that lets Claude Code open sent drawings without asking:
`Read(~/Library/Application Support/<bundle id>/requests/*/image.png)`. Turning Claude Code off
removes it. While the plugin is in, the Agents tab has a switch for the rule alone.

## Receiving a drawing in Codex

Codex needs no inbox. Send names a Codex thread by its id and hands the line to
`codex queue --thread <id>`. A thread that the Codex app or a Codex CLI session has open takes it
within about 10 seconds. A thread nobody has open keeps it until someone opens the thread, and the
card says the drawing is queued.
