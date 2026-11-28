# Gemini CLI

Part of [Gemini CLI and Antigravity as agents Vignette can send to](../gemini-antigravity-2026-11-27.md).

Sources are the docs that ship inside the installed 0.70.0 package, in
`@google/gemini-cli/bundle/docs/`, which match the binary. Code references are to the `main`
branch of github.com/google-gemini/gemini-cli, read 2026-11-27.

| Capability | What Gemini CLI offers | Source |
| --- | --- | --- |
| List running sessions | Nothing lists running sessions. Past sessions are files in `~/.gemini/tmp/<project>/chats/session-<time>-<id>.jsonl`, per project. The first line holds `sessionId`, `projectHash`, `startTime`, `lastUpdated` and `kind`. The display name is the AI summary when there is one, else the first user message. No format guarantee, and the format moved from one JSON file to append-only JSONL in 2026. A plugin hook could record running sessions, as Vignette's Claude Code plugin does | `docs/cli/session-management.md`; `packages/core/src/services/chatRecordingTypes.ts`; `packages/cli/src/utils/sessionUtils.ts`; local file on this Mac |
| Deliver a line mid-session | No channel from outside. There is no monitor, inbox, socket or IPC into an interactive session. `AfterAgent` returning `decision: "deny"` sends its `reason` to the agent as a new prompt, but only when a turn ends, and it marks the turn's answer as rejected. `BeforeAgent` can append context, only to a prompt the person typed. No hook fires while the session is idle | `docs/hooks/reference.md` (0.70.0) |
| IDE companion channel | Ruled out. An IDE runs an MCP server that the CLI connects to as a client, found through `$TMPDIR/gemini-ide-<uid>/gemini-ide-server-<pid>-<port>.json`. The server may send `ide/contextUpdate` (open files, cursor, selection) and answer `openDiff` and `closeDiff`. None of these is a user message or starts a turn, and the CLI connects only when `/ide` is on and its folder is inside the IDE's workspace | `docs/ide-integration/ide-companion-spec.md` (0.70.0) |
| Deliver through the terminal | Herdr's `hc send <terminal> <text>` pastes text and presses Enter, waits while the person has an unfinished draft, and takes `--if idle`. Herdr's app lists `gemini` as an agent it recognises | `hc send --help`; `herdr-app` binary |
| Turn state | Hooks `BeforeAgent` and `AfterAgent` mark a turn's start and end. Every hook gets `session_id`, `transcript_path` and `cwd` on stdin | `docs/hooks/reference.md` |
| Focus | Only through Herdr, as for Claude Code | `HerdrFocus` |
| Start a session | `gemini --resume <id>` and `gemini --session-id <uuid>`, which Herdr can run as it runs `claude --resume` | `gemini --help` (0.70.0) |
| Push cards back | An extension carries skills (`skills/<name>/SKILL.md`) and hooks (`hooks/hooks.json`). The session id reaches hooks only, as `GEMINI_SESSION_ID` and `$GEMINI_SESSION_ID` in the command. A shell command the agent runs gets `GEMINI_CLI=1` and no session id. A `SessionStart` hook can put the id into history with `additionalContext` | `docs/extensions/reference.md`; `docs/hooks/index.md`; `packages/core/src/hooks/hookRunner.ts`; installed bundle |
| Install | `gemini extensions install <path>` copies the extension; `gemini extensions link <path>` links it. Changes apply after a restart | `docs/extensions/reference.md` |
| Open sent images | `read_file` reads images; `@path` attaches a file. A path in a message reaching the model as an image is *unverified* | `docs/tools/file-system.md` |
| ACP (`gemini --acp`) | JSON-RPC over stdio to a process the client starts. `loadSession` rebuilds a session from disk in that process. It cannot reach a session open in a terminal | `docs/cli/acp-mode.md`; `packages/cli/src/acp/acpSessionManager.ts` |

Releases ship weekly. v0.70.0 came out on 2026-11-19 and v0.71.1 on 2026-11-24, per
github.com/google-gemini/gemini-cli/releases, read 2026-11-27.

## First step and full parity

The first step is pushes only. The skill goes into a Gemini CLI extension. A `SessionStart` hook
puts the session id into the conversation, so the agent can push `agent=gemini&session=<id>`.
Reply on such a card would need delivery, which this step does not have.

Delivery would need one of these:

- Herdr's `hc send` into the terminal running that session, found through an extension hook that
  records each process's session, as the Claude Code plugin's `turn.sh` does. It needs Herdr. It
  types into a terminal, which the rule in `docs/rules/send.md` ("A destination is an agent
  session, never the terminal displaying it") forbids today.
- `AfterAgent` with `decision: "deny"`, which delivers only when a turn ends and tells the
  agent its answer was rejected. It cannot reach an idle session.

Full parity also needs turn state from `BeforeAgent` and `AfterAgent` hooks, a session list built
from those hooks, and starts through `gemini --session-id`. Gemini CLI ships weekly, and its
session file format changed this year.
