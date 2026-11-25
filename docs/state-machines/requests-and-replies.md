# Requests, replies and the screenshots folder: requests and replies

A request is one Send of a drawing to an agent session, and a reply is the drawing the agent sends back. This area covers the request record, the grace wait before the line leaves, the reply import that turns a reply into a card, and the folder bookkeeping (watcher, writes, caches) that keeps cards, drawings and requests in step with the files on disk. No random-sequence test exists in this area: every test is a table or a hand-written sequence.

Terms used below. A request's **line** is the text Vignette submits to the agent client. The **grace** is the wait of `ui.sendGraceSeconds` between Send and the line leaving. A **receipt** is the file the reply helper polls for the app's answer to one reply attempt. An **inventory** is one folder listing with the time it was observed (`observedAt`).

### Record.Status (explicit)

Owner: `ScreenshotRequestRecords.swift`, advanced by `ScreenshotRequests.swift`. Tests: `ScreenshotRequestsTests.testEveryLateSubmissionOutcomeLeavesClearTerminal`, `testALaunchLeavesALineTheClientHasNotAnsweredAlone`, `testQuitDoesNotWaitLongerThanItsLimitForASlowClient`, `testARequestStillPreparedAtLaunchIsClearedBecauseItsLineIsGone`, `testALaunchReplacingACopyLeavesItsWaitingSendsAlone`.

The durable record of one send. `ScreenshotRequests` writes it; the client's answer moves it.

**States**: `prepared` (stored, line not handed over), `uncertain` (handed over, no answer, also the end state of a call that never answered), `submitted` (client accepted or queued), `failed` (client refused, or the destination changed), `cleared` (terminal, takes no replies).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| none | `send` (`ScreenshotRequests.swift`) | `prepared` | record stored before the image leaves the editor, with `image.png`, and `pins.json` when the drawing has pins |
| `prepared` | `handOver`, from `run(.submit)` or `releaseHeld` | `uncertain` | `handedOver` set before the line leaves |
| `prepared`, `uncertain` | outcome accepted or queued (`recordOutcome`, via `finishSubmission` or `releaseHeld`) | `submitted` | `delivered` called |
| `prepared`, `uncertain` | outcome uncertain | `uncertain` | `delivered` called |
| `prepared`, `uncertain` | outcome not submitted or destination changed | `failed` | `delivered` called |
| `submitted` | outcome uncertain or failed | `uncertain` or `failed` (downgrade, not guarded) | `delivered` called |
| `failed` | outcome accepted, uncertain, failed | `submitted`, `uncertain`, `failed` | `delivered` called |
| any but `cleared` | `clear(_:)`: `run(clear:)`, the 50-request admission, `load` of a `prepared` record, `.discard` | `cleared` | see [Clearing and cleanup](screenshots-folder.md#clearing-and-cleanup-implicit) |
| `cleared` | any outcome | — (status and detail kept) | `delivered` is still called |
| `cleared` | `clear` again | — | returns true; `cleanup` replays |
| `uncertain`, `submitted`, `failed`, `cleared` | `run(.submit)` | — (refused) | — |
| any but `cleared` | `renamed` | same status, new `sourceKey` | record rewritten from the in-memory status ([requests-3](plausible-findings-requests-to-live-ink.md#requests-3)) |

A failed admission in `send` sets `cleared` with a detail.

**Invariants**

- `cleared` is terminal and a late outcome never reopens it. Checked by: `testEveryLateSubmissionOutcomeLeavesClearTerminal`.
- A record is `uncertain` on disk before the line leaves, so `load` never clears a delivered line as unsent. Checked by: `testALaunchLeavesALineTheClientHasNotAnsweredAlone`, `testQuitDoesNotWaitLongerThanItsLimitForASlowClient`; comment.
- `prepared` on disk at a normal launch means the line never went, so `load` clears it. Checked by: `testARequestStillPreparedAtLaunchIsClearedBecauseItsLineIsGone`.
- In-memory status equals on-disk status. Checked by: nothing. A launch that replaced a running copy can hold a stale `prepared` and write it back over the old copy's `uncertain` or `submitted` ([requests-3](plausible-findings-requests-to-live-ink.md#requests-3)).
- `finishSubmission` runs once per request. Checked by: nothing.

**Late and concurrent answers**

- Outcome after a clear: status and detail are kept, `delivered` still runs, guard at `ScreenshotRequests.swift`.
- Quit before the client answers: `handOver` stores `uncertain` first; `releaseHeld` waits up to 2 s.
- A launch that replaces a running copy leaves its waiting sends alone (`load(clearingUnsent:)`).

### SendGrace (explicit)

Owner: `SendGrace.swift`. Tests: `SendGraceTests.testACancelledSendIsDiscardedAndItsTimerDoesNothing`, `testAClearTakesAWaitingSendAndItsTimerDoesNothing`, `testTheLineGoesOnceWhenTheDeadlineComes`, `testATimerThatRunsEarlyArmsAgainForWhatIsLeft`, `testCancellingSeveralDiscardsThemInSendOrder`, `testQuitSubmitsEveryWaitInSendOrderOnce`, `testQuitHandsAWaitingSendOverOnceWithoutTouchingCards`.

A pure reducer that holds each send's line until its deadline. `ScreenshotRequests.run(_:)` feeds it events and runs its effects.

**States**: per request id, absent or `Wait(line, deadline, length, sequence)` in `waiting` (`SendGrace.swift`). `nextSequence` orders sends. The clock is `systemUptime`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| absent | `.sent`, grace > 0 (`ScreenshotRequests.swift`) | waiting | `.arm` |
| absent | `.sent`, grace <= 0 | absent | `.submit` now |
| waiting | `.due`, at >= deadline | absent | `.submit` (waited) |
| waiting | `.due`, early | waiting | `.arm` for what is left |
| waiting | `.cancelled(requests:)` (`unsend(file:)` in `ScreenshotRequests+Unsend.swift`: Don't send and `vignette://unsend`; `unsend(request:)`: a live ink note; `unsendEverySend(of:)`: `fileRemoved`) | absent | `.discard`; every wait of the file, or the note's, in send order |
| waiting | `.cleared` (`clear(_:)`) | absent | `.dropped` |
| waiting | `.quit` (`releaseHeld`) | absent, all waits | `.submit` each, in send order |
| absent | `.due`, `.cancelled`, `.cleared`, `.quit` | — | — (stale, ignored; a cancel after hand-over is refused, no `.discard`) |

How `ScreenshotRequests.run` treats effects: `.arm` schedules a timer; `.submit` first checks `requests[id].status == .prepared`, then logs, calls `callbacks.released` (only when waited) and `submit`; `.discard` calls `clear` then `callbacks.cancelled`; `.dropped` calls `callbacks.cancelled` only.

**Invariants**

- A request is in `waiting` only while its record is `prepared`. Checked by: the re-check in `run(.submit)` at `ScreenshotRequests.swift`.
- A stale or doubled timer does nothing. Checked by: `SendGrace.swift`, `testACancelledSendIsDiscardedAndItsTimerDoesNothing`, `testAClearTakesAWaitingSendAndItsTimerDoesNothing`.
- The deadline never moves; an early timer re-arms. Checked by: `testATimerThatRunsEarlyArmsAgainForWhatIsLeft`.
- A cancel takes every waiting send of the file, in send order. Checked by: `testCancellingSeveralDiscardsThemInSendOrder`.
- Quit hands every wait over once, in order. Checked by: `testQuitSubmitsEveryWaitInSendOrderOnce`.
- After `.discard` or `.dropped` the record is `cleared`. Checked by: nothing. `clear` sends `.cleared` before its write, and `defer { run(stopped) }` runs even if the write throws (comment, pinned by `testClearWriteFailureKeepsStateAndOwnedFiles`). A failed clear still stops the wait and tells the card "cancelled" while the record stays `prepared`.
- A deleted file cancels its waiting send, a removal held back by `FolderWrites` included (**fixed**, [requests-1](findings.md#requests-1)).

**Late and concurrent answers**

- `.due` after cancel, clear or quit: ignored, `SendGrace.swift`.
- Timer owner gone: `[weak self]`, `ScreenshotRequests.swift`.
- The cancel path clears through `clear`, whose `.cleared` event is then a no-op (`SendGrace.swift`).

### Send bookkeeping (implicit)

Owner: `AppDelegate.swift` (`sentShots`), `ScreenshotRequests.swift` (`sendGrace`) (`watchedTurns`). Tests: `ScreenshotRequestsTests.testARenamedFileIsCancelledByItsNewName`.

Three tables that must agree about one send: which card it was sent from, which record it belongs to, and whether its wait is armed.

**States**: `sentShots[request id]` (`AppDelegate.swift`), `requests[id].sourceKey`, `sendGrace.waiting[id]` (`SendGrace.swift`), `watchedTurns` (`ScreenshotRequests.swift`). Together: no entry; waiting (all four set); handed over (`sentShots` still set until the answer).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| none | `requests.send` returns (`submit`) | `sentShots[id]` set | same main turn |
| waiting | rename (`renameCards` `AppDelegate.swift`, `ScreenshotRequests.renamed`) | same, new key | Don't send reaches the renamed card |
| waiting or handed over | `delivered` (`AppDelegate.swift`) or `cancelled` | `sentShots[id]` removed | — |
| waiting | `released` | — | reads only |
| waiting | `handOver` (`ScreenshotRequests.swift`), `.discard`, `.dropped` | `watchedTurns[id]` removed | — |
| waiting | `.submit` skipped by the `prepared` guard | `watchedTurns[id]` kept | harmless leak |

**Invariants**

- `delivered` finds its `sentShots` entry because the client answer always hops through `DispatchQueue.main.async` (`ScreenshotRequests.swift`). Checked by: the hop. A missing client would run `finishSubmission` inside `send` before the entry is set; the app registers both clients (`AppDelegate.swift`), so only a test with a missing client reaches it.

**Late and concurrent answers**

- Rename during the grace: both tables follow it, see Transitions.
- File removed during the grace: `fileRemoved` cancels, whether the removal is immediate or held back for a newer listing (**fixed**, [requests-1](findings.md#requests-1)).

### Reply.Stage (explicit)

Owner: `ScreenshotRequestRecords.swift`. Tests: `ScreenshotRequestsTests.testAnImportStoppedBeforePublicationLeavesNoVisibleFile`, `testAnUnknownManagedNameIsHiddenRatherThanTreatedAsACapture`, `testAReplyIsNeverACaptureEvenAfterItIsPublished`, `testAReplyTheCommandPreparesIsAcceptedAndItsRetryMakesNoSecondCard`, `testTheSameReplyIdWithOtherBytesIsRefusedAndLeavesTheFirstAlone`, `testAClearWhileMarksAreAddedCancelsTheImportInsteadOfPublishingIt`, `testLoadReplaysClearCleanupAndCannotPublishAnUncancelledReply`, `testDeletingAPublishedReplyIsARemovalAndNotARebuild`.

The durable record of one reply, from the app accepting its bytes to its card existing. Written by `ScreenshotRequests`.

**States**: `accepted`, `reserved`, `published`, `shown`, `failed`, `cancelled`. Flags beside the stage: `deleted`, `renamedTo`, `needsOutputCleanup`, `errorCode`, `notDrawn`, `destination`. Fail codes: `reserve-failed`, `destination-unknown`, `payload-unreadable`, `destination-changed`, `copy-failed`, `draft-store-failed`, `draft-failed`, `publish-failed`, `request-cleared`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| none | `accept` | `accepted` | payload stored, receipt written |
| `accepted` | reserve (`publishCard`) | `reserved` (or `failed` `reserve-failed`) | `destination` fixed |
| `reserved` | reserve again (recovery) | kept | continues from the reserve |
| `reserved` | `commit`, only if `stillReserved` | `published` | agent attributes written, card presented |
| `accepted` | live ink answer drawn (`publish`) | `shown` | — |
| `accepted`, `reserved` | `fail` | `failed` or `cancelled` | — |
| any but `published` | `cleanup` | `cancelled` | `needsOutputCleanup` set; output at `destination` removed (`reserved`) |
| `shown` | `cleanup` | stays `shown`, as `published` does (**fixed**, [requests-2](findings.md#requests-2)) | — |
| `cancelled` | live answer's capture fails after a clear | `reserved` | stale copy overwrites the record ([requests-4](plausible-findings-requests-to-live-ink.md#requests-4)) |
| `cancelled` | `cleanup` | — (skipped) | — |
| `published` | `cleanup` | — (untouched) | the file is the person's |
| `published` | file removed (`fileRemoved`, `reconcile`) | `published`, `deleted` true | — |
| `published` | file renamed (`renamed`) | `published`, `renamedTo` set or cleared | — |

Every `write(Reply)` calls `refreshReceipts`, so each accepted attempt's receipt follows the stage. `Reply.publication` (`ScreenshotRequestRecords.swift`) maps `deleted` to `removed`; `accepted` and `reserved` to `pending`; `published` and `shown` to `ready`; `failed` to `failed`; `cancelled` to `cancelled`.

**Invariants**

- Nothing is a card until `published`: `isVisible` fails closed for any managed name without a `published` record. Checked by: `testAnImportStoppedBeforePublicationLeavesNoVisibleFile`, `testAnUnknownManagedNameIsHiddenRatherThanTreatedAsACapture`, `testAReplyIsNeverACaptureEvenAfterItIsPublished`.
- One reply id gives at most one card; the same id with the same digest is answered from its record. Checked by: `testAReplyTheCommandPreparesIsAcceptedAndItsRetryMakesNoSecondCard`, `testTheSameReplyIdWithOtherBytesIsRefusedAndLeavesTheFirstAlone`.
- A cleared request never publishes. Checked by: `testAClearWhileMarksAreAddedCancelsTheImportInsteadOfPublishingIt`, `testLoadReplaysClearCleanupAndCannotPublishAnUncancelledReply`.
- A published file is the person's: clear never removes it, and a deletion is a removal, not a rebuild. Checked by: the guard, `testDeletingAPublishedReplyIsARemovalAndNotARebuild`.
- `cancelled` is terminal. Checked by: nothing ([requests-4](plausible-findings-requests-to-live-ink.md#requests-4)).
- A `shown` reply stays `shown` after a clear. Checked by: `ScreenshotRequestsClearingTests.testAClearedRequestWhoseAnswerLiveInkDrewStaysDrawnAndIsPrunedAfterAWeek` (**fixed**, [requests-2](findings.md#requests-2)).

**Late and concurrent answers**

- The same reply twice: serialized on the main actor and answered from the record; the id from another request is refused (`testAReplyIdFromAnotherRequestIsRefused`).

### Reply import pipeline (implicit)

Owner: `ScreenshotRequests.swift` (`importNext`) (`publish`) (`publishCard`) (`commit`). Tests: `ScreenshotRequestsTests.testRecoveryPublishesOneCompleteDrawingAfterInstallationWasInterrupted`, `testChangingFoldersDoesNotPruneAPublishedReplyInTheOriginalFolder`, `testAReservedReplyWithoutLocationFailsAfterStartupReadiness`.

Turns accepted replies into cards, one at a time. The app drives it from `accept`, `load` and `reconcile`.

**States**: the properties `pendingImports` (FIFO of reply ids), `importing` (one import at a time), `publicationReady` (set by the first `reconcile`), `replies[id].stage`, `requests[id].takesReplies`, the file at `reply.destination`, the stored drawing, and the outstanding `callbacks.installDrawing` and `callbacks.presentLive`. Together they are: idle (`importing` false), importing (`importing` true until the `done` callback).

**Transitions** (what a quit or crash after each step leaves)

| After step | On disk | Next launch |
|---|---|---|
| helper attempt, before `write(reply)` | maybe `payloads/<id>.png`, no record | helper times out, retries the same bundle, accepted fresh |
| `write(reply)` `accepted`, before receipt | record | `load` adds it to `pendingImports`; a helper retry gets "already accepted" |
| reserve | `reserved` and `destination` | `load` re-queues it; `publishCard` skips the reserve |
| PNG copy | hidden PNG in the watch folder | rewritten atomically, same bytes |
| `installDrawing` | drawing at the destination's key | `Drawings.installReply` reuses a complete checkpoint (`Drawings.swift`) |
| `commit` writes `published`, before `Agent.record` | published | card exists without agent badge or title ([requests-8](plausible-findings-requests-to-live-ink.md#requests-8)) |
| `callbacks.present` | published | the watcher already lists the file |

**Invariants**

- Imports are serial. A path that never calls `done` stalls every later import. All paths in `publishCard` call it; `presentLive` and `installDrawing` are trusted to answer exactly once (`LiveNoteCards.answer` answers `done(nil)` when the note is gone, `LiveNoteCards.swift`). Checked by: nothing.
- The reserved name is excluded from every listing until `published`. Checked by: the comment, and the Reply.Stage tests.
- `stillReserved` re-reads the stage and the request after every async hop. Checked by: the guards and.
- A reply is published in the folder it was reserved in, even if the watch folder changes; `shot(at:)` keys it by its real path. `reconcile` and `prune` need `confirmsAbsence`, which needs the inventory's folder to be the file's folder (`ScreenshotWatcher.swift`), so such a reply is never marked deleted and its request never pruned. Checked by: `testChangingFoldersDoesNotPruneAPublishedReplyInTheOriginalFolder`, `testAReservedReplyWithoutLocationFailsAfterStartupReadiness`.

**Late and concurrent answers**

- Clear during `installDrawing`: `stillReserved` stops the import; an install failure after a clear is not reported as a failure.
- A live ink answer whose capture fails after a clear: the nil branch republishes a stale copy ([requests-4](plausible-findings-requests-to-live-ink.md#requests-4)).
- Watch folder gone: the reply fails `destination-changed`.
- `importNext` for a request cleared before the import began: skipped.
