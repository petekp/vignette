# Live ink: asks and responders: asks

An ask is one question a person puts to an agent about their live ink: the ink, an optional note and a picture of the screen. This area covers the reducer that tracks every ask, the glue that runs it, the per-agent responders that talk to Claude Code and Codex, and the note cards that wait for a session's reply.

### LiveAsks (explicit)

Owner: `LiveAsks.swift`, a value held as `LiveInk.asks` (`LiveInk.swift`) and driven only by `reduce` (`LiveAsks.swift`). Tests: `LiveAsksTests.testRandomSequencesKeepTheInvariants`, `testAReplyAndAnAnswerFromADismissedAskAreDropped`, `testAPacketFromAClearedAskIsDroppedAndTheNextAskTakesItsOwn`, `testEscStopsTheNewestAskFirstAndTheResponderOnlyForTheOneItHas`, `testStoppingASessionAskWithdrawsItsNoteIfItIsStoredAfterAll`, `testStoppingASessionAskBeforeItsPacketSendsNothing`, `testAnErasedMarkLosesItsRolesAndItsFinish`, `testAnOverlappingFinishIsEndedByTheFirstTimer`, `testAFinishAfterAClearDoesNothing`.

Tracks every ask from the moment ink is sent until its answer is closed. `LiveInk` sends it events and runs the effects it returns. An ask goes either to a responder (an agent process Vignette runs) or, for a `toSession` ask, to a session through Send.

**States**: each ask has `Ask.Phase` (`LiveAsks.swift`):
- `looking`: the packet (ink, note, picture) is being taken.
- `waiting`: has its packet, queued behind an earlier responder ask.
- `asking`: with the responder, or pending in it.
- `answered`, `failed`: settled. They stay until closed. `isUnderWay` is the first three.

Per ask also: `toSession` (never waits and is never sent to the responder; its phase stays `looking` from `begin` until `sentToSession`, `failed`, `cancelled` or `cleared`), `fresh`, `sentOnRelease` (sent by `liveInkSendWhenQuiet`; never on a follow-up), `spot` (the pointer, for an ask with no ink; `[state]` `atPointer`), `about`, `say`, `leader`, `actions`, `picked`, `draft`, `findings`, `reason`, `picture`.
Per mark (`Record`): `roles` (`asked`, `noteInk`), `answer: Ask.ID?`, `finishing`. A record with no roles is deleted.
Side tables: `picks[askID]` (the answer a picked button was picked under, plus `aside`), `withdrawn` (session asks Esc stopped before their send was stored), `lastID` (never reset, so ids are never reused, not even after `cleared`; above every ask's id, though a stopped follow-up puts its answer back after newer asks, so `newest` can have a lower id. Checked by: `testAStoppedFollowUpPutsItsAnswerLastAndNoEarlierAskIsAfterTheLastIdGiven` and the random-sequence test).

**Events** (`Event`) and senders:
- `begin`: `LiveInk.ask` (`LiveInk.swift`).
- `drew`: `LiveInk.stroked`. `noteDiscarded`: `discardNote`.
- `removed`: `LiveInk.remove` (tap-erase, pick, `removeAnswer`, `dropFocus`, step advance, `finished`). `windowGone`: `forget`.
- `arrived(.packetCame)`: `send`, `share`. `.replyCame`: `showSay`. `.answerCame`: `answered`. `.failed`: `failed`. `.sentToSession`: the `sendNote` completion.
- `pictureSent`: the responder's `content` closure. `conversed`: `ask`, `say`. `streamed`: `showSay`. `answered`: `answered`. `drafted`: the actions panel. `replyRedrawn`: `restoreAnswer`, `notice`. `answerShown`: `clicked`, focus code.
- `dismissed`: the ×. `cancelled`: `cancelAsk` (`LiveInk+Escape.swift`). Esc sends `dismissed` for `newestAnswerToClose(inSight:)`: the newest settled ask with a non-leaving answer mark among `LiveInk.marksInSight`, the marks on the active Space. `finished`: the finish timer. `cleared`: `endConversation`.

**Transitions**

`reduce` always appends `sendNext`. Anything not listed is ignored with no effects.

| State | Event | Next state | Effects |
|---|---|---|---|
| (new) | `begin` | `looking` | `ended(...)` for a follow-up's replaced answer (`began`); with `at` a pointer, or following an answer to such an ask, `began` with no ink and `spot` set; `refused(.noInk)` with `restore` when following |
| `looking`, responder ask | `packetCame` | `waiting` | `sendNext` may then make it `asking` with `send(id)` |
| `looking`, session ask | `packetCame` | `looking` | `share(about)` |
| `waiting`, `asking`, `answered`, `failed`, ended | `packetCame` | — (ignored) | — |
| `asking` | `replyCame` | `asking` | optional `setAside`, then `showReply` |
| `asking` | `answerCame` | `asking` until LiveInk sends `answered` | optional `removeAnswer`, then `drawAnswer` |
| any present ask | `answered` | `answered`, `picked = nil` | no phase check; LiveInk sends it only right after a taken `answerCame` |
| under way, follow-up | `failed` | `answered` (old answer put back) | `restore` |
| under way, not a follow-up | `failed` | `failed` | `removeAnswer`, `notice` or `say` |
| session `looking` | `sentToSession` | ended | `finish(about ∪ ink − otherAsks ∪ answer, .dismissed)` |
| any present ask | `dismissed` | ended | `interrupt` only if `asking`; `finish(answer ∪ about − others ∪ aside)` |
| under way | `cancelled` | ended, or restored | `interrupt` only if `asking`; `removeAnswer`; `reopenNote` if ink is given back, or `remove` of that ink when `sentOnRelease`; session ask: id into `withdrawn` |
| settled | `cancelled`, `failed`, `replyCame`, `answerCame`, `packetCame` | — (ignored) | — |
| any | `removed`, `windowGone`, `finished` | marks lose roles; settled asks with no answer mark left end (`endAnswersWithNoMarks`); asks under way stay | — |
| any | `cleared` | every ask ended | `ended(id)` for each; `picks` emptied; roles, answers, finishing dropped; `withdrawn` and `lastID` kept; no `interrupt` |

**Invariants**

- Each ask that leaves the list says `ended` first, oldest first, but a follow-up an answer is put back in place of: its `restore` names it (`followUp`) and ends it. Checked by: `testRandomSequencesKeepTheInvariants` (`LiveAsksTests:984`).
- Asks go to the responder one at a time, in order, each only when `waiting`. Checked by: the same test.
- What comes back for an ask no longer under way changes nothing. Checked by: the same test, `testAReplyAndAnAnswerFromADismissedAskAreDropped`, `testAPacketFromAClearedAskIsDroppedAndTheNextAskTakesItsOwn`.
- `interrupt` is emitted only for the ask the responder has. Checked by: the same test, `testEscStopsTheNewestAskFirstAndTheResponderOnlyForTheOneItHas`.
- Esc on an ask sent on release gives no ink back to the note: its new ink is removed. Checked by: `LiveAsksSentOnReleaseTests`.
- An ask with no ink has a `spot`, the point its picture is taken under, and an ask following its answer keeps it and takes no ink, even with other ink asked about on screen. `drawnInk` gives its picture and message none of the person's ink, which `LiveInk.ask`, `send` and `share` all go through. Esc on it opens no note. Without a pointer, no ink is still refused. Checked by: `LiveAsksWithoutInkTests`.
- A session ask Esc stopped has its first arrival swallowed and a stored note withdrawn. Checked by: `testStoppingASessionAskWithdrawsItsNoteIfItIsStoredAfterAll`, `testStoppingASessionAskBeforeItsPacketSendsNothing`.
- An erased mark loses its roles and its finish; asks under way are unchanged. Checked by: `testAnErasedMarkLosesItsRolesAndItsFinish`.
- Overlapping finish timers: the first ends the marks. Checked by: `testAnOverlappingFinishIsEndedByTheFirstTimer`, `testAFinishAfterAClearDoesNothing`.
- Ids strictly increase. Checked by: `testRandomSequencesKeepTheInvariants`.
- Every ask ends by answer, failure, stop or clear. Checked by: `LiveResponderTests.testAnAskUnderWayWhenTheSignInGoesFailsOnce` for the sign-out (**fixed**, [asks-1](findings.md#asks-1)). The test model drops a responder-held ask only on `clear` (`LiveAsksTests:1817`), so it assumes the responder drops one no other way.
- Erasing the reply mark of an ask under way: the ask keeps `say`, and the next `replyCame` draws it again. Checked by: nothing ([asks-6](plausible-findings-requests-to-live-ink.md#asks-6)).

**Late and concurrent answers**

- A packet, reply, answer or failure after the ask ended, was dismissed, stopped or cleared: dropped, the `isUnderWay` guard in `LiveAsks.swift` and the phase guards.
- A late arrival for a stopped session ask: swallowed by `withdrawn.remove(id)`. If its send is stored later, the reducer emits `.withdraw` and `LiveInk.swift` withdraws the note.
- Two follow-up picks on one answer: the answered ask leaves `asks` at `begin`, so the second `respond` fails its `asks.ask(id)` (`LiveInk.swift`).
- A stale `finished` timer: `guard ids.contains(where: finishing != nil)`.
- A draft for a reply the panel was not made for: the `.drafted` guard.
- A failed follow-up puts the old answer back only while its reply is among `shown`.

### LiveInk ask glue (implicit)

Owner: `LiveInk.swift`; effects run in `run`. Tests: none (`LiveInk` is not instantiated in unit tests).

Runs the effects `LiveAsks` returns and keeps per-ask tables that must agree with `asks.asks`.

**States**: `LiveAsks` plus these tables:
- `held[id]` (`LiveInk.swift`): what to send the responder. Set in `send`, consumed in `sendHeld`, cleared in `release`.
- `answerers[id]`: agent and display name. Set at `began`, cleared in `release`. A restored answer takes its follow-up's in `restoreAnswer`.
- `handing[id]` (note panel waiting to hand over) and `handingTo[id]` (the conversation mark it will become): set in `LiveInk.swift`, cleared by `letGoOfNote` (from `release`, `failed`, `share`) or the handover closure.
- `dismissButton`, `dismissing`: the × for one ask. Cleared in `release` and `hideDismissButton`.
- `actionsPanels[id]`: buttons per answered ask. Made in `showActions`, removed by `hideActions` (also from `release`, `removeAnswer`, `setAside`, `restoreAnswer`).
- Step tour (an answer that points at targets one step at a time): `steps`, `stepsAsk`, `stepsWindow`, `stepsOnTheirWindows`, `stepTargets`, `stepClicks` (`LiveInk.swift`), `stopSteps`, `clicked`, and the delayed advance closure (`stepPause`).
- `prepared`: a prefetched packet for the note's ink. Set in `prefetch`, used and cleared in `ask`, cancelled in `endConversation` and by the next `prefetch`.
- The Task started in `ask` builds the packet and calls `send`, `share` or `failed`. It is never cancelled when the ask ends; every use re-checks the reducer.

**Transitions** (effects of `run`)

| State | Event | Next state | Effects |
|---|---|---|---|
| any | effect `ended(id)` | tables for `id` cleared | `release`: `held`, `answerers`, note fade, ×, tour, buttons |
| follow-up stopped or failed | effect `restore(followUp: F)` | answer back, F's tables cleared | `restoreAnswer`: the answer takes `answerers[F]`, then `release(F)` |
| `waiting` | effect `send(id)` | `asking` | `sendHeld` calls `responders.ask`; a failure calls `failed` |
| `asking` | effect `interrupt` | — | `responders.cancel()` (all agents) |
| marks settled | effect `finish(ids)` | — | `finish`: `showMarks`, then `asyncAfter(finishDuration)` sends `.finished` |
| step answer showing | click on the step's target | next step after 0.35 s | the advance closure removes the done marks and draws the next step. A second click inside the pause skips a step, and Esc or × inside it still draws the next step ([asks-2](plausible-findings-requests-to-live-ink.md#asks-2)) |

**Invariants**

- Every ask that leaves the list releases `held`, `answerers`, `handing`, `handingTo`, ×, buttons and its tour (`release`). Checked by: reducer-level `ended` ordering only.
- After `.send(id)`, `held[id]` and `answerers[id]` exist (a code comment says so). A miss would leave the ask `asking` forever. Checked by: nothing.
- `sendNote` is always set in the app (`AppDelegate.swift`); `share` returns without ending the ask if it were nil (`LiveInk.swift`). Unreachable now.
- The step advance closure only runs for a tour still held. Checked by: nothing ([asks-2](plausible-findings-requests-to-live-ink.md#asks-2)).

**Late and concurrent answers**

- A packet for an ask no longer `looking`: `send` guard; `share` takes `.share` only if the reducer still has the ask.
- A reply or answer after dismissal: every callback starts with `guard answerers[id]` (`showSay`, `answered`, `say`, `sendHeld`), then the reducer's guard.
- The handover closure after the ask ended or failed: `handingTo[id] == reply.id` and `asks.ask(id)?.say` checks.
- A second click on ×: the second `.dismissed(id)` finds no ask.
- `respond` after the answer was replaced: `asks.ask(id)` is nil.
- Clear: `endConversation` runs `letGoOfTour`, `.cleared`, `responders.stop()`, and cancels `prepared`.

### LiveResponder (implicit)

Owner: `LiveResponder.swift`, one per agent. Tests: none.

Runs one agent process and sends it one ask at a time. `LiveResponders` owns one per agent; `LiveInk` reaches it through `sendHeld`.

**States**: these properties together form the state.
- `state` (`State`, `LiveResponder.swift`): `stopped`, `starting`, `ready`, `asking`, `failed(reason)`.
- `current` (ask sent), `pending` (ask not yet sent), `interrupting` (turn of a cancelled ask not yet ended), `restartDue`, `starts` (counter), `held` (isolation refusal for one binary), `askTimer`, `idleTimer`, `conversation`, `answered`, `lastSay`.

Valid combinations: `asking` implies `current != nil` or `interrupting`; `current != nil` implies `asking`; `pending != nil` implies not `stopped` once `ask` returns; `interrupting` implies the process is running.

**Events** and senders:
- `ask(Ask)`: `LiveResponders.ask` from `LiveInk.sendHeld`. `prepare()`: `LiveResponders.prepare` at note open (`LiveInk.swift`).
- `cancel()`: `LiveResponders.cancel` from `LiveAsks.Effect.interrupt`.
- `stop()`: `LiveResponders.stop` from `endConversation`, app quit (`LiveResponders.swift`), and for Codex `ResponderStatus.onCodexSigningOut` (`LiveResponders.swift`).
- `restart(whenIdle:)`: `ResponderStatus.changed(signedIn:)` through `onCodexSignIn` (`LiveResponders.swift`).
- Driver `ResponderEvent`s through `handle`: `ready`, `startFailed`, `refused`, `output`, `answerSoFar`, `answered`, `turnFailed`, `firstTurnFailed`, `ended`.
- Timers: `askTimer` (45 s for an ask, 3 s for an interrupt; `armTimer`), `idleTimer` (4.5 min; `renewIdle`). A binary-lookup `Task` in `start`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| idle, `answered >= 12` | `ask(A)` | `stopped` | `stop()` first (a new conversation), then `pending = A` |
| any | `ask(A)` | `failed` becomes `stopped` | `pending = A` (overwrites a pending ask without telling it), `prepare`, `sendNext` |
| not running, not `failed` | `prepare` | `starting` | timers, binary `Task`; running: `restartIfIdle` |
| `starting` | binary found | — | `launch`: not found or refused: `refuse`, `failed`, `pending` and `current` get `onAnswer(.failure)`; else `driver.start`, `conversation += 1` |
| `starting` | `ready` | `ready` | `restartIfIdle`, `sendNext` (`pending` becomes `current`, state `asking`, `driver.send`, `armTimer`) |
| other | `ready` | — (ignored) | — |
| `asking` | `answerSoFar` | — | `current.onSay` if not interrupting and the text changed |
| `asking` | `answered`, `turnFailed` | `ready` | `turnEnded`: an interrupted turn is swallowed (`interrupting = false`); else `current = nil`, `onAnswer`; then `restartIfIdle`, `sendNext` |
| any | `firstTurnFailed` | `failed` | `current` failed, then `startFailed` (also fails `pending`) |
| any | `startFailed`, `refused`, `ended` | `failed` | `shutDown(failure, .failed)`: `current` and `pending` get `onAnswer(.failure)` |
| `asking` | `cancel()` | stays `asking` | `pending = nil`; if `current`: `current = nil`, `interrupting = true`, `driver.interrupt()`, 3 s timer. No answer, no failure |
| any | `askTimer` 45 s | `stopped` | `shutDown(timeout, .stopped)`: `current` and `pending` failed |
| `interrupting` | `askTimer` 3 s | — | `interruptUnanswered`: `stop()`, then `ask(pending)` again |
| any | `idleTimer` | `stopped` | `stop()` only if no `current` or `pending` |
| any | `stop()` | `stopped` | `shutDown(nil, …)`: `current` and `pending` dropped with no answer and no failure |
| any | `stop(failingAsks: true)` | `stopped` | `current` and `pending` each fail with the driver's `couldNotAnswer` (**fixed**, [asks-1](findings.md#asks-1)) |
| any | `restart(whenIdle:)` | — | sets `restartDue`; acts when `current == nil`, not `interrupting`, not `starting`: `shutDown(nil, .stopped)` then `ask(pending)` |

**Invariants**

- One ask at a time (`LiveResponder.swift`). Holds only because `LiveAsks.sendNext` sends one; `ask` itself overwrites `pending`. Checked by: nothing here; `LiveAsks` random test covers the sender.
- A `stop()` gives the ask under way or pending no answer and no failure. That is right for `endConversation`, which clears `LiveAsks` first, and for the idle stop and the conversation limit, which hold no ask. The sign-out, which tells `LiveAsks` nothing, stops with `failingAsks` (**fixed**, [asks-1](findings.md#asks-1)). Checked by: `LiveResponderTests.testAnAskUnderWayWhenTheSignInGoesFailsOnce`.
- A command found after a stop starts nothing. Checked by: the guard `start == starts, running`.
- A driver reports nothing after its own stop. Checked by: `ClaudeDriver.stop` setting `report = nil`; `JSONLinesProcess.stop` clearing `relay.onLine` and `relay.onEnd`; `CodexDriver.stop` dropping `run`, whose callbacks are weak.

**Late and concurrent answers**

- Cancel while the ask is still pending (warm-up): `pending = nil`, `guard current != nil`.
- Cancel, then the next ask: it waits in `pending` until the interrupted turn ends (`sendNext` needs `state == .ready`), or 3 s pass and a new process starts.
- The interrupted turn's own answer or failure is swallowed; its stream is ignored (`guard !interrupting`).
- Stop during binary lookup: the `starts` check. Restart during start or interrupt waits: `restartIfIdle` guard.
- Late events from a killed process: relay cleared (`JSONLinesProcess.swift`).
- Codex asked to interrupt before the turn id is known: `interruptOnStart` (`CodexDriver.swift`).
- Timeout and interrupt share `askTimer`; each arm replaces the last.
