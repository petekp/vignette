# Requests, replies and the screenshots folder: requests and replies

A request is one Send of a drawing to an agent session, and a reply is the drawing the agent sends back. This area covers the request record, the grace wait before the line leaves, the reply import that turns a reply into a card, and the folder bookkeeping (watcher, writes, caches) that keeps cards, drawings and requests in step with the files on disk. No random-sequence test exists in this area: every test is a table or a hand-written sequence.

Terms used below. A request's **line** is the text Vignette submits to the agent client. The **grace** is the wait of `ui.sendGraceSeconds` between Send and the line leaving. A **receipt** is the file the reply helper polls for the app's answer to one reply attempt. An **inventory** is one folder listing with the time it was observed (`observedAt`).

### Record.Status (explicit)

Owner: `ScreenshotRequestRecords.swift:30`, advanced by `ScreenshotRequests.swift`. Tests: `ScreenshotRequestsTests.testEveryLateSubmissionOutcomeLeavesClearTerminal`, `testALaunchLeavesALineTheClientHasNotAnsweredAlone`, `testQuitDoesNotWaitLongerThanItsLimitForASlowClient`, `testARequestStillPreparedAtLaunchIsClearedBecauseItsLineIsGone`, `testALaunchReplacingACopyLeavesItsWaitingSendsAlone`.

The durable record of one send. `ScreenshotRequests` writes it; the client's answer moves it.

**States**: `prepared` (stored, line not handed over), `uncertain` (handed over, no answer, also the end state of a call that never answered), `submitted` (client accepted or queued), `failed` (client refused, or the destination changed), `cleared` (terminal, takes no replies).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| none | `send` (`ScreenshotRequests.swift:272`) | `prepared` | record stored before the image leaves the editor |
| `prepared` | `handOver` (`:371-377`), from `run(.submit)` (`:333`) or `releaseHeld` (`:448`) | `uncertain` | `handedOver` set before the line leaves |
| `prepared`, `uncertain` | outcome accepted or queued (`recordOutcome` `:391`, via `finishSubmission` `:385` or `releaseHeld` `:464`) | `submitted` | `delivered` called |
| `prepared`, `uncertain` | outcome uncertain | `uncertain` | `delivered` called |
| `prepared`, `uncertain` | outcome not submitted or destination changed | `failed` | `delivered` called |
| `submitted` | outcome uncertain or failed | `uncertain` or `failed` (downgrade, not guarded) | `delivered` called |
| `failed` | outcome accepted, uncertain, failed | `submitted`, `uncertain`, `failed` | `delivered` called |
| any but `cleared` | `clear(_:)` (`:806`): `run(clear:)` `:764`, the 50-request admission `:290`, `load` of a `prepared` record `:131`, `.discard` `:341` | `cleared` | see [Clearing and cleanup](screenshots-folder.md#clearing-and-cleanup-implicit) |
| `cleared` | any outcome | — (status and detail kept) | `delivered` is still called (`:387`, `:393`) |
| `cleared` | `clear` again | — | returns true; `cleanup` replays |
| `uncertain`, `submitted`, `failed`, `cleared` | `run(.submit)` | — (refused, `:333`) | — |
| any but `cleared` | `renamed` (`:223-226`) | same status, new `sourceKey` | record rewritten from the in-memory status ([requests-3](plausible-findings-requests-to-live-ink.md#requests-3)) |

A failed admission in `send` sets `cleared` with a detail (`:297-299`).

**Invariants**

- `cleared` is terminal and a late outcome never reopens it. Checked by: `testEveryLateSubmissionOutcomeLeavesClearTerminal`.
- A record is `uncertain` on disk before the line leaves, so `load` never clears a delivered line as unsent. Checked by: `testALaunchLeavesALineTheClientHasNotAnsweredAlone`, `testQuitDoesNotWaitLongerThanItsLimitForASlowClient`; comment at `:371-372`.
- `prepared` on disk at a normal launch means the line never went, so `load` clears it (`:129-133`). Checked by: `testARequestStillPreparedAtLaunchIsClearedBecauseItsLineIsGone`.
- In-memory status equals on-disk status. Checked by: nothing. A launch that replaced a running copy can hold a stale `prepared` and write it back over the old copy's `uncertain` or `submitted` ([requests-3](plausible-findings-requests-to-live-ink.md#requests-3)).
- `finishSubmission` runs once per request. Checked by: nothing.

**Late and concurrent answers**

- Outcome after a clear: status and detail are kept, `delivered` still runs, guard at `ScreenshotRequests.swift:393`.
- Quit before the client answers: `handOver` stores `uncertain` first (`:371-379`); `releaseHeld` waits up to 2 s (`:460-463`).
- A launch that replaces a running copy leaves its waiting sends alone (`load(clearingUnsent:)`, `:129`).

### SendGrace (explicit)

Owner: `SendGrace.swift:6`. Tests: `SendGraceTests.testACancelledSendIsDiscardedAndItsTimerDoesNothing`, `testAClearTakesAWaitingSendAndItsTimerDoesNothing`, `testTheLineGoesOnceWhenTheDeadlineComes`, `testATimerThatRunsEarlyArmsAgainForWhatIsLeft`, `testCancellingSeveralDiscardsThemInSendOrder`, `testQuitSubmitsEveryWaitInSendOrderOnce`, `testQuitHandsAWaitingSendOverOnceWithoutTouchingCards`.

A pure reducer that holds each send's line until its deadline. `ScreenshotRequests.run(_:)` (`:324`) feeds it events and runs its effects.

**States**: per request id, absent or `Wait(line, deadline, length, sequence)` in `waiting` (`SendGrace.swift:17`). `nextSequence` orders sends. The clock is `systemUptime` (`:89`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| absent | `.sent`, grace > 0 (`ScreenshotRequests.swift:319`) | waiting | `.arm` |
| absent | `.sent`, grace <= 0 | absent | `.submit` now |
| waiting | `.due`, at >= deadline | absent | `.submit` (waited) |
| waiting | `.due`, early | waiting | `.arm` for what is left |
| waiting | `.cancelled(requests:)` (`unsend(file:)` `:425`: Don't send, `vignette://unsend` `AppDelegate.swift:557`, `fileRemoved` `:162`) | absent | `.discard`; every wait of the file, in send order |
| waiting | `.cleared` (`clear(_:)` `:809`) | absent | `.dropped` |
| waiting | `.quit` (`releaseHeld` `:448`) | absent, all waits | `.submit` each, in send order |
| absent | `.due`, `.cancelled`, `.cleared`, `.quit` | — | — (stale, ignored; a cancel after hand-over is refused, no `.discard`) |

How `ScreenshotRequests.run` treats effects: `.arm` schedules a timer; `.submit` first checks `requests[id].status == .prepared`, then logs, calls `callbacks.released` (only when waited) and `submit`; `.discard` calls `clear` then `callbacks.cancelled`; `.dropped` calls `callbacks.cancelled` only.

**Invariants**

- A request is in `waiting` only while its record is `prepared`. Checked by: the re-check in `run(.submit)` at `ScreenshotRequests.swift:333`.
- A stale or doubled timer does nothing. Checked by: `SendGrace.swift:51`, `testACancelledSendIsDiscardedAndItsTimerDoesNothing`, `testAClearTakesAWaitingSendAndItsTimerDoesNothing`.
- The deadline never moves; an early timer re-arms. Checked by: `testATimerThatRunsEarlyArmsAgainForWhatIsLeft`.
- A cancel takes every waiting send of the file, in send order. Checked by: `testCancellingSeveralDiscardsThemInSendOrder`.
- Quit hands every wait over once, in order. Checked by: `testQuitSubmitsEveryWaitInSendOrderOnce`.
- After `.discard` or `.dropped` the record is `cleared`. Checked by: nothing. `clear` sends `.cleared` before its write (`:809`), and `defer { run(stopped) }` runs even if the write throws (comment `:807-808`, pinned by `testClearWriteFailureKeepsStateAndOwnedFiles`). A failed clear still stops the wait and tells the card "cancelled" while the record stays `prepared`.
- A deleted file cancels its waiting send, a removal held back by `FolderWrites` included (**fixed**, [requests-1](findings.md#requests-1)).

**Late and concurrent answers**

- `.due` after cancel, clear or quit: ignored, `SendGrace.swift:51`.
- Timer owner gone: `[weak self]`, `ScreenshotRequests.swift:328`.
- The cancel path clears through `clear`, whose `.cleared` event is then a no-op (`SendGrace.swift:63`).

### Send bookkeeping (implicit)

Owner: `AppDelegate.swift:74` (`sentShots`), `ScreenshotRequests.swift:79` (`sendGrace`), `:81` (`watchedTurns`). Tests: `ScreenshotRequestsTests.testARenamedFileIsCancelledByItsNewName`.

Three tables that must agree about one send: which card it was sent from, which record it belongs to, and whether its wait is armed.

**States**: `sentShots[request id]` (`AppDelegate.swift:74`), `requests[id].sourceKey`, `sendGrace.waiting[id]` (`SendGrace.swift:17`), `watchedTurns` (`ScreenshotRequests.swift:81`). Together: no entry; waiting (all four set); handed over (`sentShots` still set until the answer).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| none | `requests.send` returns (`submit`) | `sentShots[id]` set | same main turn |
| waiting | rename (`renameCards` `AppDelegate.swift:501`, `ScreenshotRequests.renamed` `:223`) | same, new key | Don't send reaches the renamed card |
| waiting or handed over | `delivered` (`AppDelegate.swift:1308`) or `cancelled` (`:1323`) | `sentShots[id]` removed | — |
| waiting | `released` (`:1318`) | — | reads only |
| waiting | `handOver` (`ScreenshotRequests.swift:366`), `.discard`, `.dropped` | `watchedTurns[id]` removed | — |
| waiting | `.submit` skipped by the `prepared` guard (`:333`) | `watchedTurns[id]` kept | harmless leak |

**Invariants**

- `delivered` finds its `sentShots` entry because the client answer always hops through `DispatchQueue.main.async` (`ScreenshotRequests.swift:357`). Checked by: the hop. A missing client would run `finishSubmission` inside `send` (`:359`) before the entry is set; the app registers both clients (`AppDelegate.swift:65`), so only a test with a missing client reaches it.

**Late and concurrent answers**

- Rename during the grace: both tables follow it, see Transitions.
- File removed during the grace: `fileRemoved` (`:161`) cancels, whether the removal is immediate or held back for a newer listing (**fixed**, [requests-1](findings.md#requests-1)).

### Reply.Stage (explicit)

Owner: `ScreenshotRequestRecords.swift:71`. Tests: `ScreenshotRequestsTests.testAnImportStoppedBeforePublicationLeavesNoVisibleFile`, `testAnUnknownManagedNameIsHiddenRatherThanTreatedAsACapture`, `testAReplyIsNeverACaptureEvenAfterItIsPublished`, `testAReplyTheCommandPreparesIsAcceptedAndItsRetryMakesNoSecondCard`, `testTheSameReplyIdWithOtherBytesIsRefusedAndLeavesTheFirstAlone`, `testAClearWhileMarksAreAddedCancelsTheImportInsteadOfPublishingIt`, `testLoadReplaysClearCleanupAndCannotPublishAnUncancelledReply`, `testDeletingAPublishedReplyIsARemovalAndNotARebuild`.

The durable record of one reply, from the app accepting its bytes to its card existing. Written by `ScreenshotRequests`.

**States**: `accepted`, `reserved`, `published`, `shown`, `failed`, `cancelled`. Flags beside the stage: `deleted`, `renamedTo`, `needsOutputCleanup`, `errorCode`, `notDrawn`, `destination`. Fail codes: `reserve-failed`, `destination-unknown`, `payload-unreadable`, `destination-changed`, `copy-failed`, `draft-store-failed`, `draft-failed`, `publish-failed`, `request-cleared`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| none | `accept` (`:513-557`) | `accepted` | payload stored, receipt written |
| `accepted` | reserve (`publishCard` `:648-653`) | `reserved` (or `failed` `reserve-failed`) | `destination` fixed |
| `reserved` | reserve again (recovery) | kept | continues from the reserve |
| `reserved` | `commit`, only if `stillReserved` (`:696-703`, `:720`) | `published` | agent attributes written, card presented |
| `accepted` | live ink answer drawn (`publish` `:630-636`) | `shown` | — |
| `accepted`, `reserved` | `fail` (`:731`) | `failed` or `cancelled` | — |
| any but `published` | `cleanup` (`:821-854`) | `cancelled` | `needsOutputCleanup` set; output at `destination` removed (`reserved`) |
| `shown` | `cleanup` | stays `shown`, as `published` does (**fixed**, [requests-2](findings.md#requests-2)) | — |
| `cancelled` | live answer's capture fails after a clear (`:629`, `:648`) | `reserved` | stale copy overwrites the record ([requests-4](plausible-findings-requests-to-live-ink.md#requests-4)) |
| `cancelled` | `cleanup` | — (skipped, `:824`) | — |
| `published` | `cleanup` | — (untouched, `:823`) | the file is the person's |
| `published` | file removed (`fileRemoved`, `reconcile` `:161-171`, `:176-180`) | `published`, `deleted` true | — |
| `published` | file renamed (`renamed` `:217-222`) | `published`, `renamedTo` set or cleared | — |

Every `write(Reply)` calls `refreshReceipts` (`:908`), so each accepted attempt's receipt follows the stage. `Reply.publication` (`ScreenshotRequestRecords.swift:113`) maps `deleted` to `removed`; `accepted` and `reserved` to `pending`; `published` and `shown` to `ready`; `failed` to `failed`; `cancelled` to `cancelled`.

**Invariants**

- Nothing is a card until `published`: `isVisible` (`:145`) fails closed for any managed name without a `published` record. Checked by: `testAnImportStoppedBeforePublicationLeavesNoVisibleFile`, `testAnUnknownManagedNameIsHiddenRatherThanTreatedAsACapture`, `testAReplyIsNeverACaptureEvenAfterItIsPublished`.
- One reply id gives at most one card; the same id with the same digest is answered from its record. Checked by: `testAReplyTheCommandPreparesIsAcceptedAndItsRetryMakesNoSecondCard`, `testTheSameReplyIdWithOtherBytesIsRefusedAndLeavesTheFirstAlone`.
- A cleared request never publishes. Checked by: `testAClearWhileMarksAreAddedCancelsTheImportInsteadOfPublishingIt`, `testLoadReplaysClearCleanupAndCannotPublishAnUncancelledReply`.
- A published file is the person's: clear never removes it, and a deletion is a removal, not a rebuild. Checked by: the guard at `:823`, `testDeletingAPublishedReplyIsARemovalAndNotARebuild`.
- `cancelled` is terminal. Checked by: nothing ([requests-4](plausible-findings-requests-to-live-ink.md#requests-4)).
- A `shown` reply stays `shown` after a clear. Checked by: `ScreenshotRequestsClearingTests.testAClearedRequestWhoseAnswerLiveInkDrewStaysDrawnAndIsPrunedAfterAWeek` (**fixed**, [requests-2](findings.md#requests-2)).

**Late and concurrent answers**

- The same reply twice: serialized on the main actor and answered from the record (`:521-531`); the id from another request is refused (`:522`, `testAReplyIdFromAnotherRequestIsRefused`).

### Reply import pipeline (implicit)

Owner: `ScreenshotRequests.swift:606` (`importNext`), `:625` (`publish`), `:643` (`publishCard`), `:696` (`commit`). Tests: `ScreenshotRequestsTests.testRecoveryPublishesOneCompleteDrawingAfterInstallationWasInterrupted`, `testChangingFoldersDoesNotPruneAPublishedReplyInTheOriginalFolder`, `testAReservedReplyWithoutLocationFailsAfterStartupReadiness`.

Turns accepted replies into cards, one at a time. The app drives it from `accept`, `load` and `reconcile`.

**States**: the properties `pendingImports` (`:72`, FIFO of reply ids), `importing` (`:73`, one import at a time), `publicationReady` (`:75`, set by the first `reconcile`, `:174`), `replies[id].stage`, `requests[id].takesReplies`, the file at `reply.destination`, the stored drawing, and the outstanding `callbacks.installDrawing` and `callbacks.presentLive`. Together they are: idle (`importing` false), importing (`importing` true until the `done` callback, `:614-620`).

**Transitions** (what a quit or crash after each step leaves)

| After step | On disk | Next launch |
|---|---|---|
| helper attempt, before `write(reply)` (`:552`) | maybe `payloads/<id>.png`, no record | helper times out, retries the same bundle, accepted fresh |
| `write(reply)` `accepted` (`:552`), before receipt | record | `load` adds it to `pendingImports` (`:124`); a helper retry gets "already accepted" (`:521`) |
| reserve (`:648-653`) | `reserved` and `destination` | `load` re-queues it (`:124`); `publishCard` skips the reserve (`:648`) |
| PNG copy (`:671`) | hidden PNG in the watch folder | rewritten atomically, same bytes |
| `installDrawing` (`:678`) | drawing at the destination's key | `Drawings.installReply` reuses a complete checkpoint (`Drawings.swift:177`) |
| `commit` writes `published` (`:702`), before `Agent.record` (`:705-706`) | published | card exists without agent badge or title ([requests-8](plausible-findings-requests-to-live-ink.md#requests-8)) |
| `callbacks.present` (`:708`) | published | the watcher already lists the file |

**Invariants**

- Imports are serial. A path that never calls `done` stalls every later import. All paths in `publishCard` call it; `presentLive` and `installDrawing` are trusted to answer exactly once (`LiveNoteCards.answer` answers `done(nil)` when the note is gone, `LiveNoteCards.swift:179`). Checked by: nothing.
- The reserved name is excluded from every listing until `published`. Checked by: the comment at `:623-624`, and the Reply.Stage tests.
- `stillReserved` re-reads the stage and the request after every async hop. Checked by: the guards at `:682` and `:697`.
- A reply is published in the folder it was reserved in, even if the watch folder changes; `shot(at:)` (`:712`) keys it by its real path. `reconcile` and `prune` need `confirmsAbsence`, which needs the inventory's folder to be the file's folder (`ScreenshotWatcher.swift:41`), so such a reply is never marked deleted and its request never pruned. Checked by: `testChangingFoldersDoesNotPruneAPublishedReplyInTheOriginalFolder`, `testAReservedReplyWithoutLocationFailsAfterStartupReadiness`.

**Late and concurrent answers**

- Clear during `installDrawing`: `stillReserved` (`:682`, `:720`) stops the import; an install failure after a clear is not reported as a failure (`:682` before `:683`).
- A live ink answer whose capture fails after a clear: the nil branch republishes a stale copy (`:629`, [requests-4](plausible-findings-requests-to-live-ink.md#requests-4)).
- Watch folder gone: the reply fails `destination-changed` (`:666-670`).
- `importNext` for a request cleared before the import began: skipped (`:608-613`).
