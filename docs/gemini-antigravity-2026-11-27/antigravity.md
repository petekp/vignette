# Antigravity

Part of [Gemini CLI and Antigravity as agents Vignette can send to](../gemini-antigravity-2026-11-27.md).

Sources are the docs app 2.36.0 ships in `~/.gemini/antigravity/builtin/skills/`, the docs pages
and changelog on antigravity.google, read 2026-11-27, and read-only checks on this Mac.

Google sells four surfaces that share `~/.gemini`: the Antigravity app ("Antigravity 2.0",
desktop, Electron), the Antigravity CLI `agy`, the IDE, and a Python SDK at 0.1.x, per
antigravity.google/docs/overview. The changelog lists 53 app releases since 2.0.1 on 2026-05-19,
lately every 1 to 3 days.

| Capability | What the Antigravity app offers | Source |
| --- | --- | --- |
| List running sessions | The app's language server serves `product.v1.ConversationService` over Connect HTTP+JSON. `ListConversations` returns each conversation's id (a UUID), title or summary, project, `runState` and `updateTime`, newest first, and leaves out archived and sub-agent conversations. Called read-only on this Mac: it answered with three conversations, one `RUN_STATE_RUNNING`. Without the token it answers 401. The app's `conversation_summaries.db` (SQLite) holds the same rows with `workspace_uris`, `status` and `last_user_input_time` | shipped `conversations/SKILL.md`; changelog 2.35.0 (2026-11-23); local call |
| Find the server | Inside the app, an agent's shell gets `ANTIGRAVITY_LS_ADDRESS` and `ANTIGRAVITY_CSRF_TOKEN`. From outside, the only place found is `~/.gemini/antigravity/daemon/hub_<port>.json`, which holds `pid`, `httpPort`, `httpsPort`, `lsVersion` and `csrfToken`. On this Mac its `pid` was the app's own `language_server`, so the file belongs to the app, not the IDE or `agy`. A file left by an earlier run would need its `pid` checked. Undocumented for outside apps. A 2.35.0 fix stopped "file tools or sandboxed commands" from reading "internal session connection files", so Google treats such files as internal | local files; shipped `conversations/SKILL.md`; changelog 2.35.0 |
| Deliver a line mid-session | `agentapi send-message [--title=<title>] <conversation id> <text>`, "Sends a message to an existing conversation" (sidecars page). Its own help says "Send messages to another conversation or yourself" and suggests it for "async notifications", so it may arrive as a titled message from another conversation rather than as the person's words. `agentapi` is a two-line script that runs `language_server agentapi`. Google documents it for sidecars, which get it on their PATH. How it finds the server from another process is *unverified*: the server binary names `ANTIGRAVITY_LS_ADDRESS` and `ANTIGRAVITY_CSRF_TOKEN`, so Vignette would probably pass the hub file's values in those. Whether it starts a turn, and whether a message to a running conversation waits in the app's queue, are *unverified*: checking either sends a prompt. The app does queue a message typed during a turn and sends it when the turn ends (changelog 2.35.0 and earlier) | antigravity.google/docs/sidecars; `agentapi send-message --help`; changelog |
| Turn state | `GetConversation` returns `runState`: `RUN_STATE_IDLE`, `RUN_STATE_RUNNING` or `RUN_STATE_CANCELLING`. Plugin hooks `SessionStart`, `PreInvocation`, `PostInvocation` and `Stop` get `conversationId` | shipped `conversations/SKILL.md`; shipped `agy-customizations/docs/hooks.md` |
| Take a queued line back | Nothing documented. The language server has `SendAllQueuedMessages` and `DeleteAgentMessage` RPCs in its binary, which are internal | `strings` on `language_server` |
| Focus | The app registers `antigravity://`. Which conversation its window shows was not found: not in `window_state.json`, `app_storage.json` or the presence locks. Its accessibility tree was not checked | local files; Info.plist |
| Start a session | `ConversationService.CreateConversation` and `agentapi new-conversation` start one with a prompt. Not needed for a first step | shipped `conversations/SKILL.md` |
| Push cards back | An agent's shell gets `ANTIGRAVITY_CONVERSATION_ID`, so the skill can push `agent=antigravity&session=$ANTIGRAVITY_CONVERSATION_ID`. Plugins carry `skills/`, `rules/`, `hooks.json` and `mcp_config.json`. `agy plugin install <local path>` installs one, and `agy plugin import claude` converts a Claude Code plugin's skills, commands, MCP servers and four hook events. Claude Code monitors have no Antigravity counterpart. App 2.36.0 also reads skills in `~/.agents/skills` | shipped `agy-customizations/docs/plugins.md`; antigravity.google/docs/plugins; changelog 2.36.0 |
| Open sent images | A message is text. The agent would open the image path with its file tools. The app's Non-Workspace File Access setting (allow, ask, deny) applies to a path outside the project, as Claude Code's permission prompt does. Grants such as `read_file(/abs/path)` exist. Whether its file tool shows a PNG to the model is *unverified* | shipped `antigravity_guide/references/app.md`; antigravity.google/docs/sidecars |
| Deliver through the CLI | `agy -p "<text>" --conversation <id> --output-format stream-json` resumes a conversation by id and sends a real user prompt. Its stream has `step_update` events and a `result` per turn. Each send is a new process that Vignette starts. What it does to a conversation the app has loaded, whose lock the app's server holds, is *unverified* | antigravity.google/docs/cli/headless; `agy --help` |
| Turn-end hooks | `PostInvocation` can inject a `userMessage` step and `Stop` can return `continue` with a reason. Both run only inside a turn, like Gemini CLI's hooks, so neither reaches an idle conversation | shipped `agy-customizations/docs/hooks.md` |
| ACP (`agy acp`), SDK | Each runs a process Vignette would start. Neither reaches a conversation the app has open, as far as the docs say | antigravity.google/docs/cli/acp, /sdk/overview |

The Antigravity CLI (`agy`) in a terminal keeps its own data in `~/.gemini/antigravity-cli`.
Whether a running `agy` serves the same `ConversationService` is *unverified*: no `agy` was
running, and its `daemon` folder was empty.

## The live check, the first step and full parity

The first step is one live check. With Pete's yes, send one test message with
`agentapi send-message` to a throwaway conversation, and record:

- whether it starts a turn on an idle conversation, or waits until someone opens it;
- whether the agent and the app show it as the person's message, or as a titled message from
  another conversation;
- what it does when the conversation is running: queued for the turn's end, refused, or mixed in;
- what it answers for an unknown or archived id, which decides whether the address guard is
  runtime-enforced or needs a check just before sending;
- whether it runs from a process the app did not start, given the hub file's address and token.

If any answer rules it out, run the same check on `agy -p --conversation <id>`.

If the check passes, the build is Send, Reply and pin comments to a conversation the app has open,
and pushes from it.

- `AntigravityConnection`, a third `AgentConnection`. It reads `hub_<port>.json` and checks its
  `pid`, lists through `ListConversations`, reads `runState` for `turn(of:)`, and submits with
  `agentapi send-message`.
- A third `AgentClient` case, its label, logo, attribute name, and live ink left out of
  `allCases` loops until it is a responder.
- The skill's push lines for `agent=antigravity`, and an install into Antigravity through
  `agy plugin install` or a skill folder.
- Outcome when the app is closed: no server answers, so the send fails with a reason. Codex
  keeps a line on disk until a thread opens; Antigravity would not.

Size, as an estimate: the connection is a few hundred lines, smaller than the Codex route
(`CodexConnection`, `AppServer`, `AppServerSession`, `CodexQueue` and `CodexRollout` are 1,159
lines together). The third case touches the 7 files with `case .codex` branches and the menus,
setup and settings rows that name the two agents.

Full parity adds these:

- Don't send on a queued line.
- Send starting on the conversation the app shows.
- Starting a conversation for a project.
- A read permission for the requests folder.
- Live ink answers through `agy -p --output-format stream-json --json-schema`.
- `agy` sessions in terminals.

The app covers people who work in the Antigravity app. People who run `agy` in a terminal, as
Vignette's Claude Code users run `claude`, are not covered until a running `agy` is shown to serve
the same API.
