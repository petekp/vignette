# Live ink: asks and responders: responders and note cards

This file continues [Live ink: asks and responders: asks](live-ink-asks.md), which has the area's introduction and terms.

### LiveResponders (implicit)

Owner: `LiveResponders.swift:9`. Tests: none.

Owns one `LiveResponder` per agent and remembers what picture each has been sent.

**States**: `all[client]`; `conversing` (set at each `ask`, 83; reset by `stop`); `pictures[client]` = (conversation number, subject, text signature, line ids sent). `content(of:)` (110) records the picture as sent when the ask is written (`LiveResponder.sendNext` calls `ask.content`). Hooks: `status.onCodexSignIn`, `status.onCodexSigningOut`, `willTerminate`.

**Invariants**

- A follow-up about the same window and text sends no picture, and the answer may name only lines already sent (`linesSent`, 126). Holds because `pictures` is keyed by the responder's `conversation` number, which changes with every new process. Checked by: nothing.
- `cancel()` goes to every agent. Safe because only one ask is ever with a responder. Checked by: nothing.

### ClaudeDriver (implicit)

Owner: `ClaudeDriver.swift:8`. Tests: none.

Speaks Claude Code's streaming JSON through a `JSONLinesProcess`.

**States**: `process`, `report`, `warmingUp`, `sawInit`, `partial`. The warm-up result moves it to `ready`; the first output and deltas append to `partial`; a `result` line gives `answered` or `turnFailed`. `interrupt()` writes a control request; its end is a `result` line. `send` resets `partial`.

**Invariants**

- `sawInit` (tools list empty) must be true before `ready`, else `refused(.onceBinaryChanges)`. Checked by: nothing.

### JSONLinesProcess (implicit)

Owner: `JSONLinesProcess.swift:6`. Tests: none.

A child process read and written as lines. Lines hop to the main thread with `DispatchQueue.main.async` and check `relay.onLine` there. `stop()` nils both callbacks, terminates, and closes stdin on the writer queue.

**Late and concurrent answers**

- A write to a dead process: SIGPIPE is disabled, the error is logged and `onEnd` reports, `JSONLinesProcess.swift:44, 82`.
- A line in flight when `stop()` runs: dropped because `relay.onLine` is nil (75-80).

### CodexDriver and CodexRun (explicit phase inside an implicit machine)

Owner: `CodexDriver.swift:16`; the run is `CodexRun` at `CodexDriver.swift:108`, with `Phase` at line 111. Tests: none.

Runs a Codex thread through a local provider and `AppServerSession`.

**States**: `Phase`: `starting`, `checking(thread, model)`, `warming(thread)`, `ready(thread)`. Other state: `turn` (id from `turn/started`), `interruptOnStart`, `firstTurn`, `partial`, `usage`, `lastError`, `check` (local provider), `session`, `catalogClaim`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| `starting` | `launch` (main hop after provider port and catalog), `initialized`, `listed`, `thread/start` reply | `checking` | — |
| `checking` | `checked` reads the provider's recorded request bodies; any refusal | stops | `.refused(.onceBinaryChanges)` |
| `checking`, no ask waiting | `checked` clean | `warming` (a second thread) | warm-up turn |
| `checking`, ask waiting (`askWaiting()`) | `checked` clean | `ready` | warm-up skipped, `firstTurn = true`, `report(.ready)`; a failed first turn fails the start (`firstTurnFailed`) |
| `warming` | `turn/completed` | `ready` | `report(.ready)` |
| `ready` | `turn/started`, deltas, `turn/completed` on the ask thread | `ready` | `answerSoFar`, `answered` or `turnFailed` |
| any | `ended` | — | reported to the responder |

**Invariants**

- Only the ask thread's `turn/completed` completes asks (`notified`, `case .ready(let thread) where onThread == thread`, `CodexDriver.swift:338`). Checked by: nothing.
- `send` does nothing unless `phase == .ready` (`guard case .ready`, 161). `LiveResponder` only sends after `.ready`. Checked by: nothing.

**Late and concurrent answers**

- After stop: `run` is dropped; every callback is weak (`WeakRun`, `[weak self]`).
- A stopped start's catalog write: `CatalogClaim` withdraws it under one lock (`CodexIsolation.swift:62-80`).
- The provider's `ready` fires once: `Once` (`CodexDriver.swift:245-256`).

### ResponderStatus (implicit)

Owner: `ResponderStatus.swift:7`. Tests: none.

Tells Settings, Setup and note waits which agents can answer, and runs Codex sign-in and sign-out.

**States**: `availability[client]` (`checking`, `ready`, `notInstalled`, `signedOut`); `signIn` (`idle`, `waiting`, `signingOut`, `failed(reason)`); `login`; `claudeAsked`, `claudeAsking`.

**Events**: `check` (off-thread read, then a main-thread write, lines 79-84; sent when live ink turns on, when a note opens, when Settings appears or becomes key, and by Setup's 0.5 s poll, `SetupWindow.swift:427,453`), `startSignIn`, `cancelSignIn`, `signOut`, the login outcome.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| `login == nil` | `startSignIn` | `waiting` | starts `CodexLogin`; with `login != nil` it does nothing |
| `waiting` | signed in | `idle` | `availability[.codex] = .ready`, `onCodexSignIn(true)` calls the responder's `restart(whenIdle:)` |
| `waiting` | cancelled | `idle` | — |
| `waiting` | failed | `failed(reason)` | — |
| any | `signOut` | `signingOut` | `onCodexSigningOut()` calls `LiveResponder.stop(failingAsks: true)` at once (**fixed**, [asks-1](findings.md#asks-1)); logout runs off-thread (up to 15 s) |
| `signingOut` | logout done | `idle` | `availability = .signedOut`, `onCodexSignIn(false)` |
| any | `check` result lands | — | `availability[client] = found`, unconditionally (line 84). A check that read before a sign-in or sign-out can overwrite its result ([asks-5](plausible-findings-requests-to-live-ink.md#asks-5)) |

**Invariants**

- Only one login at a time. Checked by: the `login == nil` guard.
- A check result is not ordered against a sign-in result. Checked by: nothing ([asks-5](plausible-findings-requests-to-live-ink.md#asks-5)).

### CodexLogin (implicit)

Owner: `CodexSignIn.swift:36`. Tests: none.

One Codex sign-in or sign-out process. **States**: `done` (completion, once), `session`, `loginID`, `limit` timer (15 s to start, 10 min for the sign-in).

**Invariants**

- `finish` is the one exit. It clears `done` first, so cancel, completion, process end and the timer cannot report twice. Checked by: the `guard let done` at `CodexSignIn.swift:147`.

**Late and concurrent answers**

- A notification for a login id that is not the current one: ignored by `notified` (162).
- Port 1455 taken: refused before starting (81).
- A test launch on the person's own home: `CodexSignIn.defaultHome` is nil (`Launch.isOnPersonsHome`), so it fails before starting, "no Codex home in a test launch" (80).

### LiveNoteCards (implicit)

Owner: `LiveNoteCards.swift:7`. Tests: none (the pure parts are tested under `NoteCardWait`).

Glue between `ScreenshotRequests` and `NoteCardGroups`. After a person sends a live-ink note to a session, it watches the session's turn, then draws the result: a look at the window again, a result card, "Done", or the session's own reply.

**States**: `notes[request]` (`Note`: shot, destination, title, window, ink, `before`, `resultCard`), `waits` (`NoteCardGroups`), `timer` (0.5 s; started on `.watchTurn`, stops itself when nothing is watched, line 257), `readingTurns` (one read in flight), `hold` (`EventHold<Input>`, 48).

**Events**: `Input` (line 22): `.event(NoteCardGroups.Input)`, `.looked(...)`, `.answer(record, answer, done)`. Callbacks from `ScreenshotRequests` (wired at `AppDelegate.swift:1293-1325`): `released` (only for a send that had a grace), `cancelled` (Don't send, or the request cleared while held), `delivered` (once the client answered), `presentLive` (a reply with a `LiveAnswer`; replies import one at a time and `done` must be called once or the import queue stalls).

`EventHold.send` (`AnnotationRun.swift:282`) appends the input; if one is being handled it returns, else it drains in order. An event sent from inside a handler runs after the current one finishes. Direct calls (`released`, `cancelled`, `delivered`, `unsend`) first read or mutate `notes`, then queue.

**Transitions**: `handle` (171) maps the input, runs the actions, drops notes whose wait is gone (186) and clears `before` for notes no longer watching or looking again (187-190).

**Invariants**

- `done` of `.answer` is called exactly once on every path (`handle` 177, `runNote` 241-250, `drawFresh`, `drawOnResultCard`). Checked by: nothing.
- A note whose `.sent` is still in `hold` is not registered: `delivered` reads `waits[request]?.delivered` before the queued events (153-160), and `handle`'s prune ignores unregistered notes (`registered`, 182). Checked by: the guards.
- A window capture held in `Note.resultCard` is released when the note is pruned, but pruning runs only at the end of `handle`, so after the last note it can stay in memory ([asks-3](plausible-findings-requests-to-live-ink.md#asks-3)). Checked by: nothing.
- A reply that arrives while the result card is being written goes on the sent picture, not the result card ([asks-4](plausible-findings-requests-to-live-ink.md#asks-4)). Checked by: nothing.

**Late and concurrent answers**

- `.answer` for a note that is not registered or is gone: `done(nil)` (177).
- A result card for a group whose lead note is gone: `guard … let lead = notes[ids[0]]` returns (199).
- Overlapping turn-read ticks: `readingTurns` (262).

### NoteCardWait (explicit)

Owner: `LiveNoteCardWait.swift:5`, with `Phase` at line 6. Tests: `NoteCardWaitTests.testAnyOrderOfEventsEndsTheWaitOnce` (166), `testAHeldNoteWatchesNoTurnUntilItsLineIsReleased`, `testACancelledHeldNoteIsNeverWaitedFor`, `testANoteIsForgottenOnlyOnceDeliveredAndOver`, `testAFailedDeliveryEndsTheWaitSilently`, and the tests at `NoteCardWaitTests:275-535`.

The wait of one sent note. It decides when the note's turn is over and what to draw.

**States**: `Phase`: `unsent` (initial, never stored), `watching(TurnWatch)`, `unwatched(sent)`, `lookingAgain`, `resultCard(made)`, `over`. Flag `delivered`.

**Events**: `sent`, `delivered(failed)`, `turn(turn, replied)`, `lookedAgain(outcome)`, `cardFailed`, `answer`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| `unsent` | `sent`, route reports turns | `watching` | `watchTurn` |
| `unsent` | `sent`, route does not | `unwatched` | `stopWaiting` |
| `watching` | `turn` `.stillWaiting` | — | — |
| `watching` | `turn` `.ended`, no before-picture | `over` | `turnEnded`, and `replyIsTheResult` or `sayDone` |
| `watching` | `turn` `.ended`, with before-picture | `lookingAgain` | `turnEnded`, `lookAgain` |
| `watching` | `turn` `.stoppedWaiting` | `over` | `stopWaiting` (+ `replyIsTheResult` if replied) |
| `lookingAgain` | `lookedAgain` replied | `over` | reply |
| `lookingAgain` | `lookedAgain` `cardMade` | `resultCard` | — |
| `lookingAgain` | `lookedAgain` `noCard` | `over` | `sayDone` |
| `resultCard` | `cardFailed` | `over` | `sayDone` |
| `watching`, `unwatched`, `lookingAgain`, `resultCard` | `delivered(failed: true)` | `over` | none (silent) |
| any | `delivered` | `delivered = true` | — |
| `over` | `delivered(failed)` | — (ignored) | — |
| `watching`, with window | `answer` | `watching` | `drawReplyOnFreshCapture` |
| `watching` without window, `lookingAgain`, `over` | `answer` | unchanged | `drawReplyOnSentPicture` |
| `resultCard`, within 30 min | `answer` | `resultCard` | `drawReplyOnResultCard` |
| `resultCard`, later | `answer` | `over` | `drawReplyOnSentPicture` |
| `unwatched`, within 3 min | `answer` | `unwatched` | fresh capture if there is a window, else sent picture |
| `unwatched`, later | `answer` | `over` | `drawReplyOnSentPicture` |

`isFinished(at:)` (89) needs `delivered`. `over` is finished at once, `unwatched` after 3 min, `resultCard` after 30 min. `lookingAgain` is never finished.

**Invariants**

- A note ends once, with a card, Done or the reply, after one look. Checked by: `testAnyOrderOfEventsEndsTheWaitOnce` (single wait only).
- A held note watches no turn until released, and a cancelled held note is never waited for. Checked by: `testAHeldNoteWatchesNoTurnUntilItsLineIsReleased`, `testACancelledHeldNoteIsNeverWaitedFor`.
- One look and one card per turn end; notes sent minutes apart end together; a reply is its own result. Checked by: the tests at `NoteCardWaitTests:275-535`.
- `drawReplyOnResultCard` only after a card exists. Checked by: the random test, which asserts `madeCard` equals phase `resultCard`. That is weaker than the need (the card file exists), see [asks-4](plausible-findings-requests-to-live-ink.md#asks-4).
- Nothing bounds `lookingAgain` in time. Checked by: nothing.

**Late and concurrent answers**

- Delivery before or after the end, in either order: `testANoteIsForgottenOnlyOnceDeliveredAndOver` and the random test.

### TurnWatch (implicit)

Owner: `LiveNoteCardWait.swift:180`, `read` at line 208. Tests: `LiveInkTests.testATurnSeenToStartEndsOnceItHasBeenIdleTwoSeconds`, `testABusyMomentBetweenTurnsStartsTheIdleSpellOver`.

Decides from readings of a session (`waiting`, `busy`, `idle`, or nil when it cannot tell) whether its turn has ended.

**States**: `seenBusy`, `idleSince`, `since`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | reading `waiting` | `seenBusy`, `idleSince`, `since` reset | `.stillWaiting` |
| any | reading `busy` | `seenBusy = true`, `idleSince` cleared | `.stillWaiting` |
| `seenBusy` | reading `idle` | `idleSince ?? now` | `.ended` after 2 s idle |
| any | reading nil | no change (falls to the limits case) | after 3 min with no turn seen, or 30 min busy or waiting: `.stoppedWaiting` |

**Invariants**

- A nil reading does not reset an idle spell, so `idle, nil, idle` can end the turn without 2 s of continuous idle ([asks-7](plausible-findings-requests-to-live-ink.md#asks-7)). Checked by: nothing.

### NoteCardGroups (explicit)

Owner: `LiveNoteCardGroups.swift:7`. Tests: `NoteCardWaitTests` (as above), `testANoteWhoseSendFailedDuringTheLookIsLeftOut`.

Holds the waits of all sent notes and decides which note makes the result card when several end together.

**States**: `held[request]` (in its grace, not yet a wait), `entries[request]` (a `NoteCardWait` plus session, window and sequence).

**Events** (`Input`): `sent`, `held`, `released`, `cancelled`, `delivered`, `turns`, `looked`, `cardFailed`, `answer`. Each is routed to the entry's `NoteCardWait`. `looked` resolves one maker (the first changed, unreplied, compared member), one `makeResultCard`, and a `sayDone` for each other note made quiet except the newest (`sayingDoneOnce`, 155). Finished entries are pruned at the end of every `handle` (149).

**Invariants**

- A held note is not in `entries`, so `.turns` skips it (111). Checked by: `testAHeldNoteWatchesNoTurnUntilItsLineIsReleased`.
- Entries are pruned only when an input arrives, so a finished `resultCard` can outlive its 30 min until then ([asks-3](plausible-findings-requests-to-live-ink.md#asks-3)). Checked by: nothing.

**Late and concurrent answers**

- A line released twice: `held.removeValue` (91).
- A reading for a note that ended since the tick started: `guard … entry.wait.isWatching` (111).
- A `lookedAgain` for a note whose send failed during the look: the `looking` filter on `isLookingAgain` (127), `testANoteWhoseSendFailedDuringTheLookIsLeftOut`.

### RolloutTurns and CodexTurns (implicit)

Owner: `CodexRollout.swift:16` (`RolloutTurns`) and `CodexRollout.swift:101` (`CodexTurns`). Tests: `CodexRolloutTests` (not mapped in detail).

Reads a Codex session's rollout file to say whether the session is waiting, busy or idle, for `TurnWatch`.

**States**: per thread `Watch`: `turns` (`RolloutTurns`: `pending` lines, `openTurn`, `openTurnHeard`, `owesBusy`, `unreadable`), `path`, `offset`, `partial`, `grew`, `asked`, `askAfter`, `loaded`, `quietTurn`.

**Events**: `sending(line)`, `unsent(line)`, `turn(of:)` (every 0.5 s tick, off the main thread), rollout lines. `reading()` gives `waiting` (a line not yet seen), `busy`, `idle`, or nil when unreadable. Unreadable stays nil until restart, so `.idle` never comes after it.

### LiveNotePopover (implicit)

Owner: `LiveNotePopover.swift:26`. Tests: none.

The note panel a person types into. Created at `showNote` (`LiveInk.swift:616`).

**States**: flags `revealed`, `sent`, `closing`, `handingOver`, `standsAside`, `menuOpen`, `opened`, plus `inkOpacity`, `target`, `handPick`, `candidates`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| created | `reveal` | `revealed` | fade in |
| `revealed` | `send` (Return) with words | `sent` | letter fades, keys returned |
| `revealed` | `send` with empty words | `closing` | `dismiss` |
| `revealed` | `send` with words, no ink, not by the pointer (`mayAsk`) | `revealed` | beep |
| `sent` | `handOver(when:)` | `closing`, `handingOver` | delayed `ready`, then close |
| `handingOver` | `fadeAway` | `closing`, `handingOver = false` | closes; the delayed `ready` does not run (392, `guard handingOver` at 380) |
| any | `dismiss` | `closing` | closes |
| `closing` or `sent` | `put`, `takeKeys`, `send`, `hang`, `follow`, `standAside` | — (ignored) | — |

**Invariants**

- Exactly one of `handOver`, `fadeAway`, `dismiss` ends the note. Checked by: the `closing`/`sent` guards.
- During `sent`, Esc and Return do not reach the note: `LiveInk` already set `note = nil` (`letGoOfNotePanel`, `LiveInk.swift:626`), so Esc goes to `cancelAsk` when Esc has a step. An `onAsk` failure calls `fadeAway` (631). Checked by: nothing.
