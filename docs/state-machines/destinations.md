# The toolbar and destinations: destinations and connections

This file continues [The toolbar and destinations: the toolbar](toolbar.md), which has the area's introduction and terms.

### SessionListing (implicit)

Owner: `SessionListing.swift:6`. Tests: `AgentConnectionTests` listing tests (about lines 714-860).

Asks each agent connection for its sessions and delivers lists to the toolbar. `AppDelegate.listDestinations` calls `list(shown:completion:)` (`:42`); `refreshKeptLists()` (`:80`) is called from `AppDelegate.swift:196,387,1489`.

**States**: `kept: [Source: [AgentDestination]]` (`:107`); `asking: [Source: [callbacks]]` (`:110`); per `list` call, a local `Answers` (`lists`, `fresh`, `herdr`) (`:85`, `:43`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| a client has a kept list | `list` | — | delivers once at once (`:65`), then asks every source |
| no kept list | `list` | — | asks every source; delivers on each fresh answer |
| source not in `asking` | `ask` without id | `asking[source]` set | runs the job |
| source in `asking` | `ask` without id | callback appended | joins the running job (`:141`) |
| any | `ask` with id (the thread the Codex app shows) | — | own job, not joined, not kept (`:134-139`) |
| job answers | main-thread answer (`:123-155`) | `kept[source]` set when `keepsList` (`:149`) even if the list is empty ([toolbar-2](plausible-findings-run-to-toolbar.md#toolbar-2)); `asking[source]` cleared | all waiters called; `answers.lists`, `fresh`, `herdr` set; `deliver()` sends `complete` (every client has a list) and `fresh` (every list is fresh) |

**Invariants**

- A kept list answers at once and every client is asked afresh; startable rows never hold back; a second ask joins; an ask with an id runs alone and is not kept; herdr decides with Claude's first answer. Checked by: the `AgentConnectionTests` listing tests.
- A failed job does not replace a good kept list. Checked by: nothing ([toolbar-2](plausible-findings-run-to-toolbar.md#toolbar-2)).
- A job always returns, so `asking[source]` clears. Checked by: nothing. A child that ignored SIGTERM would leave later asks for that source waiting.

**Late and concurrent answers**

- Callbacks are `@MainActor` and capture `self` weakly. A stale answer is dropped by the caller's opening compare.
- Two overlapping `list` calls (a swap) each have their own `Answers`.
- A joined ask carries the herdr focus read when the first caller's job ran, up to about 70 ms old.

### AppDelegate.refreshDestinations and listDestinations (implicit)

Owner: `AppDelegate+Send.swift`. Tests: none.

Starts one listing for the open image, gated by the opening. It reads the `annotator.opening`, calls `beginDestinations`, which answers the kept pick's session while it holds, and, if `FocusReturn.shared.previousApp` is the Codex app, reads the shown thread off the main thread (`AgentApp.shownThread`). It then calls `sessions.list`, with the kept Codex thread's id in place of the shown thread's when there is one. Both now live in `AppDelegate+Send.swift`.

**States**: the captured `opening`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| opening current | off-main thread read returns | — | main re-checks the opening (`:96`), then `sessions.list` |
| opening current | each `deliver` | — | re-checks (`:113`), then `destinationsAnswered` |
| opening ended | either hop | — | dropped |

**Invariants**

- The `previousApp` read happens once per `prepare`. Checked by: the call order in `refreshDestinations`.

**Late and concurrent answers**

- Both hops compare the opening id: guards at `AppDelegate+Send.swift:96` and `:113`.

### DestinationChoice (pure functions, no state)

Owner: `DestinationChoice.swift`. Tests: `DestinationChoiceTests`; Send's rules in `ToolbarOfferTests` and the herdr test in `AgentConnectionTests`.

`choose(_:for:)` is a pure function of `Candidates` and `Asker`. It has no states. Send's pick order is `.kept`, `.app`, `.pane`, `.tab`, else first by `newestFirst`. An answer is `decided` when it is complete or any session is marked. A kept Codex list that lacks the shown thread forces `complete = false`. With a kept pick (`Asker.send`'s `kept`), a list that has its session marks it `.kept`; a list without it is undecided until every client has answered afresh, and then `keptIsGone` is set and the usual order picks. `KeptPick.holds(at:)` is the 10-minute window; its owner is `AnnotationController.keptPick` ([toolbar.md](toolbar.md#kept-pick-annotationcontrollerkeptpick-implicit)).

### ClaudeCodeConnection: submit, preflight, start (implicit)

Owner: `AgentConnection.swift:195`; inbox reads `ClaudeInbox.swift:23-52`. Tests: `SessionStartsTests.testASendToASessionThatIsNotRunningStartsItThenWritesTheLineIntoItsInbox`, `SessionStartsTests.testAStartThatFailsOrNeverComesUpSendsNothing`, `AgentConnectionTests+Started`.

Takes a line for a Claude Code session. A running session is listed, checked by a preflight (`:405`), then written (`:443`). A startable row is started in a herdr tab, polled for its inbox, then written. A Claude Code process has an inbox folder; its monitor touches an `alive` file, and `isLive` means touched within 10 s.

**States**: for a running session: listed, preflighted, written. For a startable row: requested, joined (waiting on a start of the same session already under way), launched, polling, then up, failed or timed out (45 s), then written. The start code is in `ClaudeSessionStart.swift`, and the starts under way are in `SessionStartsUnderWay`, which every copy of the connection shares.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| listed | `submit` to a destination with `start != nil` | refused (`:410`) | — |
| listed | `submit`, inbox holds exactly this session now (`listedInbox(of:) ?? liveInbox(holding:)`, `:416`) | written | aside file, then rename (`write`) |
| listed | `submit`, inbox does not hold it | `.destinationChanged` | "cleared" if another running inbox lists it in `past`, else "closed" |
| requested | `startSession` (`:270`), id not a UUID | failed | nothing reaches the shell (`new:<folder>` rows) |
| requested | `startSession`, a start of this session under way | joined | no launch; waits for that start's answer (**fixed**, [toolbar-3](findings.md#toolbar-3)) |
| requested | `startSession`, none under way, `liveInbox(holding:)` already live | up | no launch |
| requested | `startSession` otherwise | launched | `before` = inbox folder names now; `launch` (herdr `tab create`, `pane run`) |
| launched | launch returns `.failed` | `.notStarted` | — |
| launched | launch started | polling | `look` (`:288`) every 0.25 s via `later` |
| polling | `look` finds the first folder not in `before` whose `session` equals the id and which `isLive` | up, then written | every joined send gets the same inbox and writes its own line |
| polling | `now - began >= 45` | timed out | nothing sent, by this send or any joined one |
| any read | `liveInboxes()` (`:329`) | — | deletes an inbox folder whose pid is not running |

**Invariants**

- A line is written only if the inbox still holds that exact session immediately before the write (`AddressGuard.preflight`, `:405`). Checked by: the guard.
- A second send after the inbox is live does not launch again. Checked by: `SessionStartsTests.testASendToASessionThatIsNotRunningStartsItThenWritesTheLineIntoItsInbox`.
- One start runs per session at a time: a send to a session already starting joins that start (`SessionStartsUnderWay`). Checked by: `SessionStartsTests.testASecondSendWhileItsSessionIsStillStartingJoinsThatStart` (**fixed**, [toolbar-3](findings.md#toolbar-3)).

**Late and concurrent answers**

- `/clear` before the write: caught by the preflight.
- A session resumed by hand after it was listed: caught at `:274`.
- Only folders created since the launch are polled (`:293`).
- Open windows by design (comment on `AddressGuard.preflight`, `:26`): `/clear` between the preflight and `write`, and between `look` success and `write`.
- Left behind: a tab when `pane run` fails after `tab create` (`SessionStarts.swift:213`), and a started `claude` after the 45 s timeout.

### HerdrLauncher.start (implicit)

Owner: `SessionStarts.swift:190-216` (`start` at `:204`). Tests: `SessionStartsTests` (about lines 153-195).

Opens a herdr tab in the project's folder and runs `claude` there. It runs on a pool thread only.

**States**: not started; tab created; pane running; failed.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| not started | `tab create` (10 s timeout) fails | failed | — |
| not started | `tab create` succeeds | tab created | ids parsed |
| tab created | `pane run` fails | failed | the tab stays; no retry |
| tab created | `pane run` succeeds | pane running | — |

**Invariants**

- A failed run leaves no tab. Checked by: nothing; the tab stays on failure after `tab create`.

**Late and concurrent answers**

- Two calls run two launches. `ClaudeCodeConnection` now makes one call per session start, however many sends wait on it (**fixed**, [toolbar-3](findings.md#toolbar-3)).

### CodexConnection: discover and submit (implicit)

Owner: `CodexConnection.swift` (`discover` `:56`, `submit` `:123`). Tests: `CodexConnectionTests`, `AppServerTests`.

Lists Codex threads and queues a line to one. Both are linear.

**States**: discover: asked, then answered or empty. Submit: sent, then a `SubmissionOutcome`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| discover | no binary | `[]` | — |
| discover | `converse` fails (no process, timeout, parse) | `[]`, the same as "no threads" ([toolbar-2](plausible-findings-run-to-toolbar.md#toolbar-2)) | — |
| discover | `converse` answers | threads | with `shown`, appends the read thread if absent |
| submit | no binary | `noAgent` | — |
| submit | `watchingTurn` | — | reads the rollout through another app-server first |
| submit | `codex queue` not run | `sendFailed` | `Subprocess.run` with a 25 s watchdog |
| submit | `codex queue` `timedOut` | `.uncertain` | the watchdog has sent SIGTERM, so no late answer arrives |
| submit | status != 0 | `failure(...)` | — |
| submit | status 0, no writer lock | `.queued` | — |
| submit | status 0, writer lock held | `.accepted` | — |

**Invariants**

- Only a thread UUID is addressed; the engine refuses an unknown UUID. Checked by: `codex queue --thread` (`AddressGuard.runtimeEnforced`).
- A timed out send is reported as uncertain. Checked by: `CodexConnectionTests`.

**Late and concurrent answers**

- `Subprocess.run` sends SIGTERM once (`Subprocess.swift:39`) then waits for exit (`:43`). A child that ignores it holds the pool thread and the completion. `codex` as shipped does not.

### AppServer.converse (implicit)

Owner: `AppServer.swift:138`. Tests: `AppServerTests.testAConversationReturnsWhenItsAnswersHaveArrivedAndNotBefore`, `testAConversationEndsOnAnErrorAnswer`, `testAConversationWithNoProcessIsEmpty`.

Runs one `codex app-server` process per call and reads its answers.

**States**: spawned; collecting lines (a readability handler, `state` under an unfair lock); done.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| spawned | `process.run()` throws | done | returns `[]` (`:150`) |
| collecting | `answers >= wanted`, or EOF, or 8 s | done | handler cleared; `terminate()` if running; stdin closed (the server exits on EOF); returns the lines that arrived |
| collecting | an error answer | done | as above |

**Invariants**

- No path leaves the process running after `run()` returns without `terminate()` and a stdin close. Checked by: `testAConversationReturnsWhenItsAnswersHaveArrivedAndNotBefore`. A server that ignores both stays until it exits on EOF.
- A partial conversation yields partial data. A timeout and an empty store both give no threads ([toolbar-2](plausible-findings-run-to-toolbar.md#toolbar-2)). Checked by: nothing.

**Late and concurrent answers**

- Lines after done are dropped: the handler is cleared.

### AppServerSession (implicit; live ink's)

Owner: `AppServerSession.swift:10`. Tests: none listed. Live ink uses it; the live ink mappers should read it too.

A long-lived app-server process with request ids.

**States**: running (`process` set); stopped (`process == nil`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| running | `stop()` | stopped | `process` nilled; `replies` cleared |
| running | process ends | stopped | `replies` cleared; `onEnd` called |
| stopped | `call` | stopped | stores its reply closure; writes nothing (`process?.write`) |

**Invariants**

- Every `call` is answered or cleared. Checked by: nothing; a `call` after `stop()` is never answered or cleared.

**Late and concurrent answers**

- `ready` never fires if `stop()` precedes the handshake answer. Whether any caller can `call` after `stop` is unchecked.

### SendOverlay notice animation (implicit)

Owner: `SendOverlay.swift:12`. Tests: none (needs SwiftUI `@State`).

Plays a send notice's states on a card in order. The notice's own state comes from outside (`SendNotice`).

**States**: `@State` `landed`, `shown: SendNotice.State?`, `since`, `logoArrived`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `onChange(of: notice.state)` (`:70`), from `inGrace` | `shown` steps through `[sending, X]` | one `DispatchQueue.main.asyncAfter` per step from `SendNotice.steps(from:to:)` (`CardNotices.swift:39`): 0.45 s hold per step, plus the logo glide when leaving grace |
| any | `onChange`, from another state | `shown = X` after the remaining sending hold | as above |
| before any step has fired | render | shows `notice.state` (`shown ?? notice.state`) | — |

**Invariants**

- The card shows the notice's states in order. Checked by: nothing. Steps queued by an earlier change are not cancelled ([toolbar-5](plausible-findings-run-to-toolbar.md#toolbar-5)).

**Late and concurrent answers**

- An earlier change's queued step can fire after a later change's and overwrite `shown`, guard none (`:84-93`) ([toolbar-5](plausible-findings-run-to-toolbar.md#toolbar-5)).
