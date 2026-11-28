# What Vignette needs from an agent

Part of [Gemini CLI and Antigravity as agents Vignette can send to](../gemini-antigravity-2026-11-27.md).

| Capability | What it does today | Code |
| --- | --- | --- |
| List running sessions | The target menu and live ink's note list sessions with a title, project, last use and a working row | `SessionListing`, `AgentConnection.destinations`, `ClaudeCodeConnection`, `CodexConnection`, `AppServer` |
| Deliver a line mid-session | A Send, a Reply or a pin comment becomes one line the session reads between turns | `AgentConnection.submit`, `ClaudeInbox` (plugin inbox and monitor), `CodexConnection` (`codex queue`), `CodexQueue` (`QueueWatch`) |
| Check the address | A destination is the conversation, never the terminal. Codex refuses an unknown thread; Claude Code is checked just before the write | `AgentAddress`, `AddressGuard` |
| Report the outcome | Sent, queued, uncertain or failed, with a reason on the card | `SubmissionOutcome`, `CardNotices`, `ScreenshotRequests.recordOutcome` |
| Know when a turn runs and ends | The menu's working row, the pin popover's "Claude is working" row, live ink's result card | `AgentConnection.turn`, `reportsTurns`, `CommentTurnWatch`, plugin `turn.sh`, `CodexRollout` |
| Take a queued line back | Don't send on a queued line | `AgentConnection.look`, `withdraw`, `CodexQueue` |
| Know where you came from | Send starts on the session the person was in | `HerdrFocus`, `AgentApp.shownThread`, `DestinationChoice` |
| Start a session | Continue last session or New session for a project with none running | `StartableSessions`, `SessionStart`, `HerdrLauncher` |
| Push cards back | The agent runs `vignette://add`, `show`, `pins=` and `reply` with `agent=` and `session=` | `skills/vignette/SKILL.md`, `Agent.pushOrigin`, `Agent.attribute(for:)` |
| Install the skill | The app installs the plugin that carries the skill, and for Claude Code the inbox | `AgentPlugin`, `AgentPlugins`, `PluginHost`, `agent-plugin/` |
| Open sent images | The session opens the image path itself, so its permission must allow it | `ClaudeReadRule` |
| Name and logo | The label, the card's tab, the pin's badge | `AgentClient.label`, `AgentLogos`, `Resources/agents/*.svg` |

The agent push needs the agent to know its own session id. Claude Code has
`CLAUDE_CODE_SESSION_ID` and Codex has `CODEX_THREAD_ID` in their shells.

`AgentClient` has two cases, `claude` and `codex`. 38 files in `Sources/` name it, and 7
have `case .codex` branches. `LiveResponders` and `ResponderStatus` loop over
`AgentClient.allCases`, so a third case also becomes a live ink responder unless that loop is
narrowed. `Agent.attribute(for:)` stores a pushed session as `<bundle id>.session` for Claude Code
and `<bundle id>.thread` for Codex. Those names are a contract on files in people's folders, so a
third agent gets a new attribute name.

## What is installed on this Mac

| Thing | Version | Where |
| --- | --- | --- |
| Antigravity app (`com.google.antigravity`) | 2.36.0, released 2026-11-27 | `/Applications/Antigravity.app`, data in `~/.gemini/antigravity` |
| Antigravity IDE (`com.google.antigravity-ide`) | 2.8.0 | `/Applications/Antigravity IDE.app`, data in `~/.gemini/antigravity-ide` |
| Antigravity CLI (`agy`) | 1.5.18 | `~/.local/bin/agy`, data in `~/.gemini/antigravity-cli` |
| Gemini CLI | 0.70.0 | `~/.vite-plus/bin/gemini` (a vite-plus shim), data in `~/.gemini/tmp` |
| Herdr | `hc` 0.1.22, `herdr-app` 0.1.18 | `~/.local/bin` |

The app's server is its language server, `Contents/Resources/bin/language_server`, and it was
running. It holds a lock file in `~/.gemini/antigravity/presence/<conversation id>.lock`
for the conversation it has loaded, as Codex's engine holds `thread-writer-locks`.
