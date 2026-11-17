# A send Codex holds in its queue, 2026-11-16

This is the measured detail behind C7 in `docs/codex-issues.md`, at CLI 0.169.0-alpha.11.1 and app
26.1111. C4 there covers a thread no engine has open. This note covers a thread an engine has open.

**What happens.** A send to a Codex thread goes into Codex's queue. Codex runs it only once the
thread is idle and its last turn ended normally. Until then the card says "Sent to *session*". The
line can wait in three ways:

- A turn is running. The line runs as its own turn right after it.
- A turn waits on one of Codex's dialogs. The line runs after the person answers and the turn ends.
- The thread's last turn was stopped, by the person cancelling a dialog or pressing Stop. The line
  waits with no time limit. It runs only after the person's next message has run, behind it. This
  holds even when the thread was stopped long before the send.

**The dialogs, as of CLI 0.169.0-alpha.11.1 and app 26.1111.** The app-server asks its client for
these (`ServerRequest` in `codex app-server generate-json-schema`):

- A command approval (`item/commandExecution/requestApproval`), for a command that asks to leave
  the sandbox, a command no rule allows under `untrusted`, or network access.
- A file change approval (`item/fileChange/requestApproval`).
- A question the agent asks (`item/tool/requestUserInput`). The `request_user_input` tool is offered
  only in Plan mode unless `default_mode_request_user_input` is on, which is off by default. An MCP
  tool's approval reaches the person the same way.
- An MCP server's elicitation (`mcpServer/elicitation/request`).
- A permissions request (`item/permissions/requestApproval`), from `request_permissions_tool`, off
  by default.

On this Mac, `approvals_reviewer = "guardian_subagent"` sends approvals to Codex's auto reviewer
rather than to Pete, and `~/.codex/rules/default.rules` allows `mkdir`, `curl` and others outright.
So the dialogs Pete meets are mostly Plan-mode questions and MCP prompts. With `approvalsReviewer:
"user"`, a command that asks to leave the sandbox stops the turn for the person.

**What the queue does.** This is from the source at `rust-v0.169.0-alpha.11.1`
(`codex-rs/ext/queue/src/service.rs`), and the live runs below agree with it.

- An engine starts a queued line only on a thread it has loaded and that is idle
  (`start_turn_if_idle`). A turn waiting on a dialog is running, so the line waits. It never goes
  into the waiting turn.
- When a turn ends normally, `on_thread_idle` starts the first queued line.
- When a turn ends by interruption (`ThreadIdleCause::Interrupted`), nothing starts. The thread's
  `AgentStatus` stays `Interrupted` until a turn ends normally. While it does, a new line's dispatch
  task returns at once, and `wake_if_loaded` does nothing. The owning engine still reports the
  thread as `idle` in `thread/status/changed`.
- A thread loaded again from its rollout starts as `Interrupted` when its last turn was
  (`core/src/session/mod.rs`, `InitialHistory::Resumed`). So the stop survives a restart of the
  engine. This was read in the source, not run.
- Cancelling a dialog interrupts the turn, which was run live. The app's Stop calls
  `turn/interrupt`, which was read in the app's bundle and run live from a client of our own.
- `codex queue` answers the same in every case: exit 0 and `Queued message <id> for thread <id>`.

The live runs used an app-server of our own with `approvalsReviewer: "user"`, and Vignette's exact
`codex queue` command. Logs are in the investigation's `.scratch/dialog-test/`, which is not
committed.

| Run | The line waited | Then |
| --- | --- | --- |
| Command approval, accepted | 42 s, still queued at every 10 s check | The approved turn ended 6.7 s after the answer. The line's turn started 20 ms later. |
| Plan-mode question, answered | 33 s, still queued | The answered turn ended 5.3 s later. The line's turn started 1.0 s after that. |
| Command approval, cancelled (two runs) | 41 s before the cancel, and 45 s after it | Nothing ran. In the second run, a second `codex queue` 20 s after the cancel released nothing. A message from the person then ran, and both lines after it, in order. In the first run, nothing followed the cancel. The line was still queued 7.5 minutes after the send, when its engine had already exited. |
| An idle thread whose last turn was stopped with `turn/interrupt`, then a send 5 s later | 50 s, still queued at every check | Nothing ran. The line was deleted. |

**What can be seen from outside the engine.** Vignette is not the engine that holds the thread, so
it sees only what that engine leaves on disk or in the queue.

| Source | What it shows while the line waits | Reliable? |
| --- | --- | --- |
| The owning engine's `thread/status/changed` | `active` with `waitingOnApproval` or `waitingOnUserInput` during a dialog. `idle` after a stop. | Exact for a dialog, but only the engine's own client hears it, and the app's engine is private. It does not show a stop. |
| `thread/read` from Vignette's own server | `notLoaded` | No. The status is that server's own memory. |
| The lock file | Present | It says loaded, not waiting. |
| The rollout | For a dialog, an open turn whose last tool call has no output yet. A question is a `function_call` named `request_user_input`. An approval is a tool call whose input asks `require_escalated`, here inside code mode's `exec`. For a stop, the last turn ends with `turn_aborted`. | A question or a stop, yes. An approval, a hint only: a long command looks the same, an `untrusted` approval carries no marker, and the dialog events themselves are never written (`rollout/src/policy.rs`). |
| `thread/queue/list` from Vignette's own server | The line, by the id `codex queue` printed, until an engine takes it | Yes, whoever holds the thread. It answered in 0.2 to 1.0 s in this session's checks, whose output was not saved. It is marked experimental and needs `experimentalApi` in `initialize`. |
| The Codex app's log | Nothing about dialogs. It logs responses to the app's own requests, such as `thread/queue/list`, and no request from the engine. | No. |

`thread/queue/delete` from Vignette's own server removed a queued line by that id, and no engine ran
it. An archived thread refuses both calls until it is unarchived.

**What the Codex app shows.** The app's bundle lists the queue above the composer as queued
follow-ups (`composer.queuedMessage.*`). Each has Steer ("Submit without interrupting the model"),
Edit and Delete. After an interrupt it says "Queue paused because you interrupted", with Resume,
which calls `thread/queue/start`. This was read in the bundle's strings and code. Whether a line
Vignette queued shows in that list was not checked by eye.

**What the card says today.** A send to a loaded thread reads `accepted`, so the card shows "Sent to
*session*" with a green check (`CodexConnection.submit`). Only a thread with no lock file reads
`queued`. All three ways of waiting look the same as a line that ran.

**What the card could say.** Each row is what Vignette sees at that moment, and the reason changes
when that does. They follow `docs/voice.md`. The table there defines "Queued for" as a thread no
engine has open, so it would change with the code.

| What Vignette sees | Headline | Reason |
| --- | --- | --- |
| The line is queued and a turn is running | Queued for *session* | Codex reads it when its current turn ends. |
| The running turn's last call is a question with no answer | Queued for *session* | Codex is waiting for your answer, then reads this. |
| The line is queued and the last turn was stopped | Queued for *session* | Codex reads it after your next message there. |
| Codex took the line | Sent to *session* | |

**Options.**

1. Watch every Codex send until Codex takes it. This is recommended. A send to a loaded thread
   starts as queued, and the card follows `thread/queue/list`. The card turns to Sent once the line
   leaves the queue. The rollout supplies the reason. While the line waits, the card keeps a Don't
   send button, which removes the line with `thread/queue/delete`.
   - Cost: an app-server process per send for `thread/read`, which today only live ink notes pay
     (`LiveNoteCards` sets `watchingTurn`). Further queue reads while the line waits. A new notice
     state, and the voice.md rows.
   - Rollout reading needs new work in `CodexRollout.swift`. `CodexTurns.sending` starts a new
     watch at the file's end, after the open turn's `task_started` and tool call. `RolloutTurns`
     does not read tool calls. It ignores a `turn_aborted` when it has no open turn. So the reader
     needs the last turn's start, its last tool call and how it ended.
   - It depends on the experimental queue calls and on the rollout's form.
2. The same, but reading only the rollout. The card turns to Sent when the line shows up as a user
   message, which `RolloutTurns` already hears. It uses no experimental call. But it cannot offer
   Don't send, and it cannot tell a line Codex dropped from one still waiting.
3. Hold the line in Vignette until the thread is idle. I rejected this. Codex's queue already
   holds it, keeps it across a quit, and shows it in the app. A hold in Vignette would hide the line
   from the app, and Vignette still could not see a dialog or a stop.
4. Steer the line into the waiting turn. Vignette cannot do this. `turn/steer` goes to the engine
   that holds the thread, and the app's engine is private. A steer would also wait on the dialog.

**Not verified.**

- The Codex app's own view of a line Vignette queued, and whether its Resume starts it.
- The CLI's interactive session after a stop.
- The stop surviving an engine restart, which was read in the source only.
- An MCP elicitation and a file change approval. The source treats them as the same wait.
- An approval the auto reviewer handles, which waits for the reviewer and not the person.
