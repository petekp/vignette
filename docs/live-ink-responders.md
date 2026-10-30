# Live ink's responders

A responder is an agent Vignette keeps running to answer live ink on the screen. There are two:
Claude Code's and Codex's. Each sees only what an ask sends it and has no tools. ADR 0026 records
why Codex answers too. `docs/live-ink.md` has the rest of live ink's rules, and
`docs/live-ink-setup.md` says what a note says when an agent cannot answer.

| Part | Where |
| --- | --- |
| Both responders: which can answer, the conversation, what each has been sent | `LiveResponders.swift` |
| What both share: one ask at a time, the limits, the idle stop, stopping one turn | `LiveResponder.swift` |
| Claude Code's process | `ClaudeDriver.swift` |
| Codex's process, its switches and its isolation check | `CodexDriver.swift`, `CodexIsolation.swift` |
| Codex's sign-in | `CodexSignIn.swift` |
| The note's target and its menu | `LiveNoteTarget.swift`, `LiveNotePopover.swift` |

## Which one answers

- A note's target starts on the first of these (`LiveNotePopover.start`):
  1. The session the note before it was sent to.
  2. The responder picked by hand on this note.
  3. The responder the last ask went to, until the ink is cleared (`LiveResponders.conversing`).
  4. The responder of the agent used last, among those that can answer
     (`DestinationChoice.responder`). This is the same rule Send uses for "used last".
  5. The first running session, since only a person starts one.
  6. The first responder, which then says why it cannot answer.
- So a conversation never moves to the other agent by itself. The target menu lists both
  responders above the sessions, as "Claude, on the screen" and "Codex, on the screen", so a person
  can aim one note at the other. A reply from an answer's button or its Reply field goes to the
  agent that gave the answer.
- Codex is offered unless its check found no `codex`. A responder that is not installed or not
  signed in cannot be picked. Its row says why in its tooltip, and under its name on macOS 14.4 and
  later. One whose process stopped can be picked, and starts again at the next ask.
- A note aimed at a responder that cannot answer says why. When the other can answer, the note then
  names it: "Codex can answer instead."
- The responder the note is aimed at starts as the first stroke moves
  (`LiveInk.prepareResponderForStroke`). A note to a session starts no process.

## Claude Code's

- `ClaudeDriver` runs one `claude -p` process in stream-json mode, with `--safe-mode --tools ""`,
  its own system prompt, and `--json-schema` for the answer (`LiveAnswer.schema`, fixed text that
  lists `say` first, the field that streams in as the reply). Started plainly, the process
  registered itself as a session in Vignette's inbox and could read files, so those flags are the
  isolation.
- The process stops before any screen content is sent unless its `init` line lists no tool but
  `StructuredOutput` and no MCP server. Its warm-up ask ($0.001 to $0.01) checks that line and
  caches the prompt. `docs/live-ink-ask-cost-2026-10-06.md` has what an ask costs and why.
- It runs on Claude's 5-minute prompt cache (`CLAUDE_CODE_PROMPT_CACHE_TTL=5m`). An ask after the
  cache ends would write the whole conversation again, so the process stops 4.5 minutes after its
  last request (`LiveResponder.idleLimit`). It also stops when the ink is cleared or live ink is
  turned off, and starts a new conversation after 12 asks.
- Esc stops one turn and keeps the conversation. `interrupt()` writes a `control_request` with
  `subtype` `interrupt`, which ends the turn within milliseconds and keeps the process (measured on
  Claude Code 2.1.302). The turn then ends with a `result` that has `is_error` true and `subtype`
  `error_during_execution`, which is not an answer or a failure. Its deltas and its result are
  dropped, and nothing new is sent until the result arrives. The process stops if that takes more
  than 3 s. The warm-up is never interrupted.
- In a test launch it runs only the `claude` that `VIGNETTE_CLAUDE` names, since any other runs on
  the person's account. `scripts/e2e/fake_claude.py` stands in for it.

## Codex's

- `CodexDriver` runs one `codex app-server` on a Codex home of Vignette's own,
  `live-ink/codex-home` under Application Support, and never on the person's. Codex sends its
  home's `AGENTS.md` to the model on every turn, whatever its config says.
- The server takes every switch in `CodexIsolation.arguments`, which turn off its features, and a
  model catalog from `codex debug models` with the fields that add tools taken out
  (`CodexIsolation.strippedCatalog`). An unknown feature name stops the server at once, and the
  responder reports it.
- After `initialize`, `account/read` must name an account. Then `model/list` picks the model:
  `gpt-6-astra` when it is offered, else the account's default, at `low` effort.
- The warm-up is the isolation check. Its thread's model provider is `vignette_check`, a listener
  on localhost inside Vignette (`CodexCheckProvider`). The real thread opens only when the request
  that listener receives has `tools: []` and nothing in its input but Vignette's prompt and the
  warm-up (`CodexIsolation.refusal`). The real thread is `ephemeral`, with the system prompt as
  its base instructions, and gets a warm-up of its own.
- Each ask is one `turn/start` with the pictures as `data:` URLs and the strict answer schema
  (`LiveAnswer.strictSchema`). The answer streams in as `item/agentMessage/delta`.
- Esc sends `turn/interrupt`. The idle stop, the conversation's 12 asks and the interrupt's 3 s are
  the same as Claude Code's.
- In a test launch it runs only the `codex` that `VIGNETTE_CODEX` names.
  `scripts/e2e/fake_codex.py` stands in for it. Its `app-server` answers `account/read` as signed in
  when its home has an `auth.json`, and its isolation check posts a request to the provider as
  Codex does.

## Codex's sign-in

- Vignette's Codex home is signed in once, through Codex's browser login. `CodexLogin` starts a
  `codex app-server` in that home, asks `account/login/start` with type `chatgpt`, and opens the
  page it answers. The sign-in ends when the server reports `account/login/completed`, after 10
  minutes, or when it is cancelled. Stopping the server ends the login and frees its port.
- Codex serves the login's callback on `127.0.0.1:1455`. When something holds that port, Codex
  sends it a `GET /cancel`, which would end another Codex login waiting there. So `CodexLogin` does
  not start while 1455 is taken, and says why.
- Codex keeps the sign-in in `auth.json` in that home and renews it there. Vignette pins the file
  store (`CodexSignIn.arguments`), so `CodexSignIn.isSignedIn` can tell whether the home is signed
  in from the file, without starting Codex. Only whether the refresh token is there is read.
- Nothing in the interface starts `CodexLogin` yet.

## In `[state]`

- `liveInk.noteTarget` is `responder claude`, `responder codex` or `session`, or null with no note.
- `liveInk.responders` has `conversing`, the agent the last ask went to, and for each agent its
  process's `state`, `conversation`, `answered`, `waiting`, the `reason` it failed, and its
  check's `availability`.
- `[live-ink] responder ready|notInstalled|signedOut agent=<client>` logs each check's answer.
