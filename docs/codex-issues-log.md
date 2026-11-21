# Codex issues: progress log

The progress on the issues in `docs/codex-issues.md`, newest first.

## 2026-11-21, C8: Codex pushes with no thread

- Reading why Send's start was wrong when the Codex app was in front found 9 of 116 Codex pushes
  with no `session=` (11-13 to 11-20). Added C8. C7's status now names its merge, 1d5bdef.

## 2026-11-18, X2: the browser agent's right-click menu (app 26.1111.21308)

- Pete was pulled into Codex with a context menu open, several times within minutes. WindowServer's
  log showed Codex taking the keys from the front app 13 times, each after a right-click in the
  in-app browser by thread `01a1ec12`. Five times Pete went to Codex within seconds of a menu.
  Vignette's 10 hand-backs to Codex that day each went to Codex because Codex had been in front.
  Added X2.
  `docs/focus-return-codex-2026-11-18.md` has the diagnosis and the proposal.

## 2026-11-16, the queue watch (branch codex-queued)

- Built C7's fix: the queue watch, the Queued tab with Don't send on hover, and Don't send through
  `thread/queue/delete`. Live checks on a scratch thread named "Vignette queue watch probe", made in
  `.scratch/live/work`, with one short turn: `thread/queue/list` on a queued line, `thread/queue/delete`
  answering true then false, an archived thread refusing both, and a missing thread. The thread was
  emptied and archived.
- Pete confirmed that the Codex app lists a thread's queued lines above the composer, with Steer,
  Edit, Delete, and Resume after Stop. A line deleted there is read as removed: gone from the queue
  and missing from the thread's history.

## 2026-11-16, Codex dialogs and queued sends (CLI 0.169.0-alpha.11.1, app 26.1111)

- Read the queue's source at `rust-v0.169.0-alpha.11.1` and ran five live checks from an
  app-server of our own, each queuing a line with `codex queue`. Four held a dialog open. One
  stopped a turn first. A send to a thread whose last turn was stopped waits until the person's
  next message, with or without a dialog. C7 has the summary, and
  `docs/codex-queued-sends-2026-11-16.md` has the findings and the options.
- The test threads were made in `.scratch/dialog-test/work` and named "Vignette dialog test (…)".
  They were emptied of queued lines and archived. There were seven threads, two of which ran
  without a dialog, and about eleven short turns on `gpt-6.1-terra`.
- Not checked yet: how the Codex app shows a line Vignette queued. That needs Pete at the app.

## 2026-10-30, Codex responder and result cards (CLI 0.165.0-alpha.1.2)

Building the Codex responder and Codex result cards found these on 0.165. Each was checked against
a real `codex` on a scratch Codex home.

- **The spike's switches no longer leave a turn with no tools.** The catalog's `gpt-6` entries have
  `tool_mode: "code_mode_only"` and `multi_agent_version: "v2"`, which add code-mode tools (`exec`,
  `wait`) and collaboration tools (`spawn_agent` and others). `use_responses_lite: true` carries
  tools inside `input` as an `additional_tools` item. The catalog Vignette writes
  (`CodexIsolation.strippedCatalog`) sets `apply_patch_tool_type` and `tool_mode` null,
  `multi_agent_version` to `"disabled"`, `experimental_supported_tools` to `[]` and
  `use_responses_lite` to false. With it, the warm-up's request has `tools: []`, `instructions: ""`,
  and only the prompt and the warm-up in `input`.
- **An unknown feature name stops the server:** `Error: Unknown feature flag: <name>`, exit 1.
- **`CODEX_HOME/AGENTS.md` is always sent,** as a user message, whatever `project_doc_max_bytes`
  says, even for an untrusted project (`app-server/src/message_processor.rs`,
  `core/src/agents_md.rs`). So the responder runs on a Codex home of Vignette's own. With an
  `AGENTS.md` put in that home, the isolation check refused the server before anything reached the
  model.
- **`-c mcp_servers={}` merges rather than replaces** the configured servers.
  `-c mcp_servers.<name>.enabled=false` turns one off.
- **A second server's `thread/read` names the rollout of a thread another engine holds** (`path`).
  The live file is `sessions/<y>/<m>/<d>/rollout-<time>-<id>.jsonl`.
- **A queued line is a `response_item` message with role `user`** in the rollout, with no
  `turn_id`, between that turn's `task_started` and its end. Two lines queued together were two
  turns, each holding its line as it was sent.
- **`model/list` answers with no sign-in:** 9 models, `gpt-6-astra` among them.
- **`auth.json` is still written in place** (`FileAuthStorage::save` opens it for truncation), guarded
  by a mutex inside one process only.
- **Signed out, a turn on the default provider** goes to `api.openai.com` and fails with 401 after
  about 15 s of retries.
- **A token login is not for other apps.** `account/login/start` with type `chatgptAuthTokens` is
  marked "[UNSTABLE] FOR OPENAI INTERNAL USE ONLY - DO NOT USE" in the schema, and the binary
  carries an off switch: "Access token login is disabled. Use API key login instead." So the
  responder's home is signed in through the browser login (type `chatgpt`), and never with the
  person's tokens (ADR 0026).
- **The browser login answers an `authUrl` at `auth.openai.com` and a `loginId`,** and serves its
  callback on `127.0.0.1:1455`. When something holds 1455, Codex sends it a `GET /cancel`, then
  after 2 to 4 s serves on 1457. With 1457 taken too, it answers error -32603 "failed to start
  login server: Port 127.0.0.1:1457 is already in use" after 6 s. Another Codex login waiting on
  1455 would be cancelled, so `CodexLogin` does not start while that port is taken.
- **Stopping the app-server ends its login.** The port and the process were gone, and no
  `auth.json` was written.
- **The sign-in is kept in `CODEX_HOME/auth.json` by default.** A keychain store keys its entry by
  a hash of the `CODEX_HOME` path. Vignette pins the file store with
  `-c cli_auth_credentials_store="file"`, so it can tell whether its home is signed in without
  starting Codex.
- **A live check answered 3 asks about a made-up image,** on a scratch home signed in by token for
  that one run. The first answer took 13.6 s from a cold start: 0.47 s for the isolation check and
  6.2 s for the warm-up. The next two took 3.4 and 4.5 s, with the first word at about 2.8 s. No
  process but three short `git` runs started under the server. The person's `auth.json` was
  unchanged.
- **A real browser sign-in through `CodexLogin`** on a scratch home took Pete 71 s. `auth.json`
  was written there only. The isolation check passed in 1.06 s, and the first ask answered in
  8.45 s. `account/logout` took 1.48 s and removed `auth.json`, and the port and server were gone.
- **A rollout in a changed form now reads as no turn.** A turn that ends with no user message the
  reader can parse while a sent line waits, or a root turn that starts before the open one ended,
  makes `RolloutTurns` unreadable, so the card stops waiting after 3 minutes. A turn open with
  nothing written for 3 minutes is only logged, since real work can be that quiet.

## 2026-10-25, live ink spike (CLI 0.164.0-alpha.11.1)

A spike measured Codex as a live ink responder and looked for a way to see a Codex turn end.
These facts add to the ones above.

- **The rollout file reports a turn's end across processes.** The thread store's `threads` row,
  `thread/read`'s status and a second server's notifications do not. The engine that has the
  thread appends `event_msg` lines `task_started`, then `task_complete` or `turn_aborted`, each
  with the `turn_id`, within 1 ms of its own `turn/completed`. The Codex app's engine writes them
  too: across 129 of Pete's rollouts, the file was written 0 to 26 ms after the line's timestamp.
- **A queued line becomes its own turn.** In 3 of 3 runs the engine took a `codex queue` line
  9.46 to 9.47 s after it was queued. The rollout holds the line as that turn's user message.
- **`thread/read` gives the thread's rollout path** as `path`, marked unstable. A long thread is
  split into segments: older ones are compressed as `.jsonl.zst`, and `path` names the live
  `<id>_<segment id>.jsonl`. `thread/list`'s items are the same `Thread` type in the 0.165 schema
  (`codex app-server generate-json-schema`), `path` included. Whether a `useStateDbOnly` listing
  fills it was not checked. Vignette reads the thread just before a watched send, since a kept
  listing can be minutes old.
- **`turn/start`'s `outputSchema` is sent as strict `json_schema`.** Every property must be in
  `required`, with the optional ones nullable.
- **A ChatGPT account refuses `gpt-5.5`** ("not supported when using Codex with a ChatGPT
  account").
- **An `app-server` turn can be held to no tools and no instructions but the caller's.** The
  report lists the switches. `apply_patch` comes from the model catalog and goes only with a
  `model_catalog_json` whose `apply_patch_tool_type` is null.

## 2026-10-01, night

- Ran the end-to-end suite with input: 18 scenarios, 90 checks, all passing, including
  `send_and_reply_codex`, `send_codex_thread_gone` and `send_codex_queued`. The queued card's clock
  was drawn white on its white ring; it is orange now.
- Ran the live checks against ChatGPT.app (C1, C2, C4, C5), above. The test thread "Reply ready"
  took one more message and answered it.
- Softened every send, reply and copy message, and recorded them with the rules they follow in
  `docs/voice.md`. Pete asked for words that are clear, short and humble, with a deep underlying
  optimism.

## 2026-10-01, evening

- Researched with three agents: the Codex source at 0.159.2, ChatGPT.app's files and processes on
  this Mac, and what changed in Codex and its plugins. The findings are under "How Codex works" and
  "What changed in Codex plugins".
- Fixed C2, C3, C4 and C6, and C1 in code. Unit tests pass. The end-to-end run without input
  passed, 48 checks.
- Added the end-to-end scenarios `send_codex_thread_gone` and `send_codex_queued`. Both post keys
  and have not run.
- Waiting on Pete for three things. The first is approval to depend on the Codex app's log for C1.
  The second is a live run of about three minutes that brings the Codex app forward, opens the
  editor over it and sends one message to the test thread "Reply ready". The third is the `--input`
  end-to-end run.

## 2026-10-01

- Tested Vignette live against the real CLI and the Codex app, and found C1 to C6 and X1
  (`docs/codex-live-test-2026-10-01.md`). The whole loop works with a CLI session and with the app:
  a drawing sent from Vignette reached the session, and its reply came back as a card.
- Added a fake codex to the end-to-end tests, and the scenarios `send_target_codex` and
  `send_and_reply_codex`. `send_and_reply_codex` posts keys and has not run yet.
