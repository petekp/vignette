# The toolbar and destinations: destinations and connections

This file continues [The toolbar and destinations: the toolbar](toolbar.md), which has the area's introduction and terms.

### SessionListing (implicit)

Owner: `SessionListing.swift`. Tests: `AgentConnectionTests` listing tests.

Asks each agent connection for its sessions and delivers lists to the toolbar. `AppDelegate.listDestinations` calls `list(including:completion:)`; `refreshKeptLists()` is called from `AppDelegate.swift`.

**States**: `kept: [Source: [AgentDestination]]`; `asking: [Source: [callbacks]]`; per `list` call, a local `Answers` (`lists`, `fresh`, `herdr`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| a client has a kept list | `list` | — | delivers once at once, then asks every source |
| no kept list | `list` | — | asks every source; delivers on each fresh answer |
| source not in `asking` | `ask` without id | `asking[source]` set | runs the job |
| source in `asking` | `ask` without id | callback appended | joins the running job |
| any | `ask` with id (the thread the Codex app shows) | — | own job, not joined, not kept |
| job answers | main-thread answer | `kept[source]` set when `keepsList` even if the list is empty ([toolbar-2](plausible-findings-run-to-toolbar.md#toolbar-2)); `asking[source]` cleared | all waiters called; `answers.lists`, `fresh`, `herdr` set; `deliver()` sends `complete` (every client has a list) and `fresh` (every list is fresh) |

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

Starts one listing for the open image, gated by the opening. It reads the `annotator.opening`, takes the capture's window owners once (`CaptureOrigin.windows(of:)`), calls `beginDestinations`, which answers the kept pick's session while it holds, and, if `FocusReturn.shared.previousApp` is the Codex app and the capture does not show another app more (`DestinationChoice.appRuleApplies`), reads the shown thread off the main thread (`AgentApp.shownThread`). When the capture sets the app aside, it lists with no `cameFrom`. It then calls `sessions.list`, asking Codex for the kept Codex thread and the shown thread by id, both in one listing. Both now live in `AppDelegate+Send.swift`.

**States**: the captured `opening`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| opening current | off-main thread read returns | — | main re-checks the opening, then `sessions.list` |
| opening current | each `deliver` | — | re-checks, then `destinationsAnswered` |
| opening ended | either hop | — | dropped |

**Invariants**

- The `previousApp` read happens once per `prepare`. Checked by: the call order in `refreshDestinations`.

**Late and concurrent answers**

- Both hops compare the opening id: guards at `AppDelegate+Send.swift` and.

### DestinationChoice (pure functions, no state)

Owner: `DestinationChoice.swift`. Tests: `DestinationChoiceTests`; Send's rules in `ToolbarOfferTests`, the herdr test in `AgentConnectionTests`, and reading the focus in `HerdrFocusTests`.

`choose(_:for:)` is a pure function of `Candidates` and `Asker`. It has no states. Send's pick order is `.kept`, `.app`, `.pane`, `.tab`, else first by `newestFirst`. An answer is `decided` when it is complete or any session is marked. A kept Codex list that lacks the shown thread forces `complete = false`. With a kept pick (`Asker.send`'s `kept`), a list that has its session marks it `.kept`; a list without it is undecided until every client has answered afresh, and then the usual order picks. `keptIsGone` is set only when the kept session's agent listed other sessions, since a failed listing answers none. `KeptPick.holds(at:)` is the 10-minute window; its owner is `AnnotationController.keptPick` ([toolbar.md](toolbar.md#kept-pick-annotationcontrollerkeptpick-implicit)). `replacesList` is the rule every menu that holds a session list applies to each answer, the editor's (`AnnotatorToolbar.Model.answered`) and the note's (`LiveNotePopover.setSessions`): an incomplete answer never replaces a complete list, even a fresher one, since it lacks every session of a client still to answer. Checked by: `ToolbarOfferTests.testASwapKeepsTheTargetOnTheBarUntilTheNextImagesSettles`, `DestinationChoiceTests.testALiveNoteKeepsItsWholeListAndItsTargetOverALaterPartialAnswer`.

### ClaudeCodeConnection: submit, preflight, start (implicit)

Owner: `AgentConnection.swift`; inbox reads `ClaudeInbox.swift`. Tests: `ClaudeSessionStartTests.testASendToASessionThatIsNotRunningStartsItThenWritesTheLineIntoItsInbox`, `ClaudeSessionStartTests.testAStartThatFailsOrNeverComesUpSendsNothing`, `AgentConnectionTests+Started`.

Takes a line for a Claude Code session. A running session is listed, checked by a preflight, then written. A startable row is started in a new Herdr tab, polled for its inbox, then written. A Claude Code process has an inbox folder; its monitor touches an `alive` file, and `isLive` means touched within 10 s.

**States**: for a running session: listed, preflighted, written. For a startable row: requested, joined (waiting on a start of the same session already under way), launched, polling, then up, failed or timed out (45 s), then written. The start code is in `ClaudeSessionStart.swift`, and the starts under way are in `SessionStartsUnderWay`, which every copy of the connection shares.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| listed | `submit` to a destination with `start != nil` | refused | — |
| listed | `submit`, inbox holds exactly this session now (`listedInbox(of:) ?? liveInbox(holding:)`) | written | aside file, then rename (`write`) |
| listed | `submit`, inbox does not hold it | `.destinationChanged` | "cleared" if another running inbox lists it in `past`, else "closed" |
| requested | `startSession` (`ClaudeSessionStart.swift`), id not a UUID | failed | nothing reaches the shell (`new:<folder>` rows) |
| requested | `startSession`, a start of this session under way | joined | no launch; waits for that start's answer (**fixed**, [toolbar-3](findings.md#toolbar-3)) |
| requested | `startSession`, none under way, `liveInbox(holding:)` already live | up | no launch |
| requested | `startSession` otherwise | launched | `before` = inbox folder names now; `launch` (`herdr-app status`, `hc run`) |
| launched | launch returns `.failed` | `.notStarted` | — |
| launched | launch returns `.timedOut` (`hc run` gave no answer in 10 s) | polling | logged; the terminal may have started |
| launched | launch started | polling | `look` every 0.25 s via `later` |
| polling | `look` finds the first folder not in `before` whose `session` equals the id and which `isLive` | up, then written | every joined send gets the same inbox and writes its own line |
| polling | `now - began >= 45` | timed out | nothing sent, by this send or any joined one |
| any read | `liveInboxes()` | — | deletes an inbox folder whose pid is not running |

**Invariants**

- A line is written only if the inbox still holds that exact session immediately before the write (`AddressGuard.preflight`). Checked by: the guard.
- A second send after the inbox is live does not launch again. Checked by: `ClaudeSessionStartTests.testASendToASessionThatIsNotRunningStartsItThenWritesTheLineIntoItsInbox`.
- One start runs per session at a time: a send to a session already starting joins that start (`SessionStartsUnderWay`). Checked by: `ClaudeSessionStartTests.testASecondSendWhileItsSessionIsStillStartingJoinsThatStart` (**fixed**, [toolbar-3](findings.md#toolbar-3)).

**Late and concurrent answers**

- `/clear` before the write: caught by the preflight.
- A session resumed by hand after it was listed: caught.
- Only folders created since the launch are polled.
- Open windows by design (comment on `AddressGuard.preflight`): `/clear` between the preflight and `write`, and between `look` success and `write`.
- Left behind: a started `claude` after the 45 s timeout, in its tab.

### HerdrLauncher.start (implicit)

Owner: `HerdrLauncher` in `SessionStarts.swift` (`start`, and the rename in `name`). Tests: the `HerdrLauncher` tests in `ClaudeSessionStartTests`.

Runs `claude` in a new terminal in the project's folder, in a new tab of the space the Herdr window shows, and names the tab. It runs on a pool thread only; the rename runs later, on its own.

**States**: not started; space read; running; timed out; failed. Apart from these, the tab: unnamed, then named or given up.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| not started | no Herdr app or no `hc` | failed | — |
| not started | `herdr-app status` (10 s timeout) fails, or names no `space` | failed | nothing started |
| not started | `status` names a space | space read | a new `tb<32 hex>` tab id |
| space read | `hc run --bg` fails or answers no `address` | failed | — |
| space read | `hc run` answers a terminal | running | the rename is scheduled |
| space read | `hc run` gives no answer in 10 s | timed out | the rename is scheduled; the terminal may have started |
| unnamed | `herdr-app do tab.rename` succeeds | named | — |
| unnamed | it fails, under 5 s since the start | unnamed | tried again in 0.5 s |
| unnamed | it fails at 5 s | given up | `[send] tab <id> not named`; the start still counts |

**Invariants**

- No terminal is started without `herdr.space`, which would hide it. Checked by: `ClaudeSessionStartTests.testWithoutASpaceOrWhenHcRefusesNothingStartsAndAFailedRenameIsNoFailedStart`.
- Every word of the command is its own argument. Checked by: `ClaudeSessionStartTests.testTheSessionRunsInANewTabOfTheSpaceTheWindowShowsWithEveryWordItsOwnArgument`.

**Late and concurrent answers**

- Two calls run two launches. `ClaudeCodeConnection` now makes one call per session start, however many sends wait on it (**fixed**, [toolbar-3](findings.md#toolbar-3)).

### CodexConnection: discover and submit (implicit)

Owner: `CodexConnection.swift` (`discover`, `submit`). Tests: `CodexConnectionTests`, `AppServerTests`.

Lists Codex threads and queues a line to one. Both are linear.

**States**: discover: asked, then answered or empty. Submit: sent, then a `SubmissionOutcome`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| discover | no binary | `[]` | — |
| discover | `converse` fails (no process, timeout, parse) | `[]`, the same as "no threads" ([toolbar-2](plausible-findings-run-to-toolbar.md#toolbar-2)) | — |
| discover | `converse` answers | threads | with ids, appends each read thread that is absent, in the order of the ids |
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

- `Subprocess.run` sends SIGTERM once (`Subprocess.swift`) then waits for exit. A child that ignores it holds the pool thread and the completion. `codex` as shipped does not.

### AppServer.converse (implicit)

Owner: `AppServer.swift`. Tests: `AppServerTests.testAConversationReturnsWhenItsAnswersHaveArrivedAndNotBefore`, `testAConversationEndsOnAnErrorAnswer`, `testAConversationWithNoProcessIsEmpty`.

Runs one `codex app-server` process per call and reads its answers.

**States**: spawned; collecting lines (a readability handler, `state` under an unfair lock); done.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| spawned | `process.run()` throws | done | returns `[]` |
| collecting | `answers >= wanted`, or EOF, or 8 s | done | handler cleared; `terminate()` if running; stdin closed (the server exits on EOF); returns the lines that arrived |
| collecting | an error answer | done | as above |

**Invariants**

- No path leaves the process running after `run()` returns without `terminate()` and a stdin close. Checked by: `testAConversationReturnsWhenItsAnswersHaveArrivedAndNotBefore`. A server that ignores both stays until it exits on EOF.
- A partial conversation yields partial data. A timeout and an empty store both give no threads ([toolbar-2](plausible-findings-run-to-toolbar.md#toolbar-2)). Checked by: nothing.

**Late and concurrent answers**

- Lines after done are dropped: the handler is cleared.

### AppServerSession (implicit; live ink's)

Owner: `AppServerSession.swift`. Tests: none listed. Live ink uses it; the live ink mappers should read it too.

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

Owner: `SendOverlay.swift`. Tests: none (needs SwiftUI `@State`).

Plays a send notice's states on a card in order. The notice's own state comes from outside (`SendNotice`).

**States**: `@State` `landed`, `shown: SendNotice.State?`, `since`, `logoArrived`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `onChange(of: notice.state)`, from `inGrace` | `shown` steps through `[sending, X]` | one `DispatchQueue.main.asyncAfter` per step from `SendNotice.steps(from:to:)` (`CardNotices.swift`): 0.45 s hold per step, plus the logo glide when leaving grace |
| any | `onChange`, from another state | `shown = X` after the remaining sending hold | as above |
| before any step has fired | render | shows `notice.state` (`shown ?? notice.state`) | — |

**Invariants**

- The card shows the notice's states in order. Checked by: nothing. Steps queued by an earlier change are not cancelled ([toolbar-5](plausible-findings-run-to-toolbar.md#toolbar-5)).

**Late and concurrent answers**

- An earlier change's queued step can fire after a later change's and overwrite `shown`, guard none ([toolbar-5](plausible-findings-run-to-toolbar.md#toolbar-5)).
