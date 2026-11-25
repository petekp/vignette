# Requests, replies and the screenshots folder: cleanup and the folder

This file continues [Requests, replies and the screenshots folder: requests and replies](requests-and-replies.md), which has the area's introduction and terms.

### Clearing and cleanup (implicit)

Owner: `ScreenshotRequests.swift` (`clear(_:)`) (`cleanup(_:inventory:)`) (`prune`) (`pendingCleanupWrites`). Tests: `ScreenshotRequestsTests.testClearWriteFailureKeepsStateAndOwnedFiles`, `testLoadReplaysClearCleanupAndCannotPublishAnUncancelledReply`, `testAQueuedInventoryCannotRemoveANewerPublishedReply`.

Ends a request: commits the terminal state, cancels its replies, removes their unpublished output, and later removes the request's folder.

**States**: `requests[id].status == .cleared`, each reply's `stage`, `errorCode` and `needsOutputCleanup`, `publicationReady`, and `pendingCleanupWrites` (reply ids whose cancelled state is not yet written).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| open request | `clear` | `cleared` committed first | payloads removed after; a failed write keeps state and files |
| cleared request, `publicationReady` false | `cleanup` | — | output removal waits |
| cleared request, `publicationReady` true | `cleanup` | replies `cancelled` | output removed; a failed removal counts as done only if `inventory.confirmsAbsence` |
| cleared for 7 days (`clearedKept`) | `prune` | request folder removed | only if no reply has `needsOutputCleanup` and every published reply's absence is confirmed |
| cleared, a reply is `shown` | `cleanup` | reply left `shown` | `prune` removes the request after a week (**fixed**, [requests-2](findings.md#requests-2)) |

**Invariants**

- The terminal state is committed before payloads are removed. Checked by: `testClearWriteFailureKeepsStateAndOwnedFiles`.
- An inventory older than a publication cannot remove it (`publishedAt <= observedAt`). Checked by: `testAQueuedInventoryCannotRemoveANewerPublishedReply`.
- An interrupted cleanup replays at the next launch or `reconcile`. Checked by: `testLoadReplaysClearCleanupAndCannotPublishAnUncancelledReply`.
- Clearing a request with a `shown` reply. Checked by: `ScreenshotRequestsClearingTests` (**fixed**, [requests-2](findings.md#requests-2)).

**Late and concurrent answers**

- A cleanup interrupted mid-way is tracked in `pendingCleanupWrites` and replayed.

### Admission limit (implicit)

Owner: `ScreenshotRequests.swift` (`send`) (`maxLiveRequests`). Tests: `ScreenshotRequestsTests.testAdmissionFailureDoesNotAccumulatePreparedRequestsOrClearOldPayloads`, `testClearWriteFailureKeepsStateAndOwnedFiles`.

Caps the open requests. `send` drives it.

**States**: the count of records whose status is not `cleared`: under 50, exactly 50, over 50.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| over 50 | `send` | unchanged | refused |
| exactly 50 | `send` | new request stored, oldest cleared | the oldest goes through `clear` |
| exactly 50 | `send`, clear of the oldest fails | the new request removed again, or marked `cleared` if that fails | send refused |
| under 50 | `send` | stored | — |

**Invariants**

- A failed admission leaves no extra `prepared` request and clears no older payload. Checked by: `testAdmissionFailureDoesNotAccumulatePreparedRequestsOrClearOldPayloads`.
- A failed clear of the oldest request still ends its wait if it was waiting (`clear` sends `.cleared` before its write). Checked by: nothing; reaching it needs 50 open requests inside the grace.

**Late and concurrent answers**

- The oldest request mid-import is cancelled through the same `clear` (`stillReserved`).

### FolderWrites pending adds (implicit)

Owner: `FolderWrites.swift` (`pendingAdds`). Tests: `FolderWritesTests.testAReportBeforeTheMarksJoinPresentsOnceAfterThem`, `testMarksJoiningBeforeTheReportWaitForIt`, `testALiveCardWaitsForItsReportAndItsMarks`.

Holds a card Vignette just wrote into the watch folder until both the watcher has reported it and any agent marks have joined. `FolderWrites.swift` owns the class.

**States**: `pendingAdds[ScreenshotKey]` holds one `PendingAdd{annotate, addingMarks, waiting}` per file Vignette put in the folder. `waiting` means the watcher has reported the file.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| none | `add` or `writeCard` | pending | `waiting` set at once only for a file already in the folder |
| pending, `addingMarks` | marks joined or `ready` | `addingMarks` false | `presentAdd` |
| pending | `arrived` (from the watcher's `onNew`) | `waiting` set | `presentAdd` |
| pending, no marks owed, `waiting` set | `presentAdd` | removed | `callbacks.present` |
| pending | `takeBack`, `discard`, copy failure | removed | — |

**Invariants**

- A card appears once, after both the watcher's report and the marks. Checked by: the three tests above.
- An entry whose report never comes (watcher gone, folder changed, file deleted first) stays for good. Checked by: nothing; harmless memory.

**Late and concurrent answers**

- The report before the marks, or the marks before the report: both orders present once (tests above).
- A file `putBack` returned from the Trash (`UndoTimeline`) is held in `pendingPutBacks` beside these: `arrived` swallows its report, since its card is already back, and the file leaving again (`left`) drops it. A put-back the watcher never saw leave and come back has no report, so its entry stays until the file leaves. Checked by: `FolderWritesTests.testAFilePutBackFromTheTrashIsNoCaptureAndHoldsBackOlderRemovals`.

### FolderWrites held-back reports (implicit)

Owner: `FolderWrites.swift` (`writtenAt`) (`deferredRemovals`) (`deferredRenames`). Tests: `FolderWritesTests.testARemovalFromAnOlderListingWaitsForANewerOne`, `testAnUnconfirmedRemovalWaitsForALaterListing`, `testARenameFromAnOlderListingWaitsForANewerOneAndComesBeforeTheSweep`, `testAnAddHoldsBackRemovalsFromAnOlderListing`.

Holds back a removal or rename reported by a listing older than the app's own last write, until a newer listing confirms it.

**States**: `writtenAt` (set by `add`, `writeCard`, `published`; not by `writeStitch` or `trash`), `deferredRemovals`, `deferredRenames`. Per report: current (`writtenAt <= observedAt`) or older (`writtenAt > observedAt`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| current | `removed(keys, inventory)` | — | confirmed keys: `left` (cards, drawings, `fileRemoved`); unconfirmed keys deferred and a rescan asked |
| older | `removed` | keys in `deferredRemovals` | — |
| current | `renamed(renames, inventory)` | — | `rename` now; does not flush `deferredRenames` ([requests-5](plausible-findings-requests-to-live-ink.md#requests-5)) |
| older | `renamed` | in `deferredRenames` | — |
| older | `listed(inventory)` | — | rescan asked only |
| current | `listed(inventory)` | deferreds applied | flush `deferredRenames`, `sweepDrawings`, `reconcileRequests`, then the confirmed deferred removals leave through `left`: cards, drawings and `fileRemoved` (**fixed**, [requests-1](findings.md#requests-1)) |
| any | `trash` | — | `left(..., .infinity)` at once |

`rename` sends a rename to a name every listing hides (`callbacks.isVisible`) as a removal. Other renames go to `renameCards`, `renameDrawings`, `renameRequests`, in that order.

**Invariants**

- A held-back report applies once a newer listing confirms it. Checked by: the four tests above.
- A deferred removal reaches every party a direct one reaches. Checked by: `FolderWritesTests.testARemovalFromAnOlderListingWaitsForANewerOne` (**fixed**, [requests-1](findings.md#requests-1)).
- Renames apply in watcher order. Checked by: nothing ([requests-5](plausible-findings-requests-to-live-ink.md#requests-5)).
- Deferred keys from a previous watch folder stay. Harmless leak.

**Late and concurrent answers**

- A removal reported by a listing older than the last write is applied by the next newer listing (`listed`).

### ScreenshotWatcher (implicit, with explicit pieces)

Owner: `ScreenshotWatcher.swift`. Tests: `ScreenshotWatcherTests.testAHeldRenameWaitsForTheDeliveryOfItsOwnScan`, `testADeliveryTakesTheRenamesAnEarlierDeliveryLeft`, `testARenameOfANameWhoseArrivalIsUndeliveredIsARemoval`, `testAQueuedInventoryIsNotDeliveredAfterItsDirectoryDisappears`, `testAReplacementDirectoryReceivesLaterArrivals`, `testAnIndexedFolderThatDisappearsKeepsItsFiles`, `testAFolderThatAppearsLaterIsListedAndThenWatched`, `testTheFirstSuccessfulListingAfterRefusalIsSilent`.

Watches the screenshots folder and reports arrivals, removals, renames and inventories to the app. Confined state (`source`, `directoryID`, `generation`, `openError`, `retryDue`) lives on `queue`; the rest is in `State` under `state`.

**States**: `Availability`: `available`, `missing`, `refused`, `unavailable`. Each `scan` sets it from `read(folder)`; `start()` also sets denied from the open errno. Beside it: `scans` (scan number), `pending[name]` (an `Arrival{id, generation}`), `present`, `held` (`HeldRenames`), `missingSince`.

**Transitions**: one scan, in order.

| Step | Event | Next state | Effects |
|---|---|---|---|
| 1 `scan` (queue) | directory source event, `rescan(reason:)`, 2 s `retryLater` timer, launch | directory ID changed: source replaced, `held` reset | read a listing; on failure set availability, `missingSince`, retry |
| 2 under the lock | listing read | `scans` bumped; pending arrivals of another generation dropped; `pending` keeps names still present | first listing only indexes; renames paired by `held.hold(..., undelivered:)`; `added` minus rename targets |
| 3 main queue | delivery | generation changed: dropped; directory ID or access changed: dropped, rescan asked; else `held.deliver(through: scanNumber, ...)` and `present = inventory.names` | `onRenamed`, `onInventory`, `onRemoved`, in that order |
| 4 arrivals | each added name gets an `Arrival` | `waitUntilComplete` polls every 0.1 s up to 100 times; then `onNew` on the main queue if generation, `pending[name] == arrival` and directory ID still match | else `retryArrival`; never stable: logged `never-stable`, forgotten from the index, found again by the next event or stack open |

`HeldRenames` is an array of `(scan, from, to)`. `hold(pairs, scan:, undelivered:)` drops pairs whose `from` has an undelivered arrival, because the app never heard of that name; it leaves as a removal plus an arrival. `deliver(through:)` returns held pairs with `scan <= n`, removes them, and returns `removed`: names that left `present`, minus rename sources, limited to candidates.

**Invariants**

- A held rename waits for the delivery of its own scan. Checked by: `testAHeldRenameWaitsForTheDeliveryOfItsOwnScan`.
- A later delivery takes the renames an earlier one left (`<=`). Checked by: `testADeliveryTakesTheRenamesAnEarlierDeliveryLeft`.
- An undelivered arrival's rename is a removal. Checked by: `testARenameOfANameWhoseArrivalIsUndeliveredIsARemoval`.
- A queued inventory is not delivered after its directory disappears. Checked by: `testAQueuedInventoryIsNotDeliveredAfterItsDirectoryDisappears`, the guard.
- The first listing after a refusal, or of a folder that appears later, is silent. Checked by: `testTheFirstSuccessfulListingAfterRefusalIsSilent`, `testAFolderThatAppearsLaterIsListedAndThenWatched`, `testAnIndexedFolderThatDisappearsKeepsItsFiles`.
- A positive file lookup protects a name an old listing lacks (`Inventory.confirmsAbsence`). Checked by: the lookup.
- The check and the clear are one atomic step. Checked by: nothing; they are two lock acquisitions in one main-queue block, so a scan between them sees `pending[name]` set and treats a rename of that name as removal plus arrival, then `onNew` still fires for the old name. The window is microseconds.

**Late and concurrent answers**

- Delivery for a scan whose directory was swapped: dropped, rescan asked.
- An arrival superseded by a newer scan: `pending[name] != arrival` ends the poll and the delivery.
- Callbacks of an old watcher after `startWatching` runs again: the `watcherGeneration` guard at `AppDelegate.swift`.
- After `never-stable`, `pending[name]` stays set until the next scan replaces it.

### Thumbnailer (implicit)

Owner: `Thumbnailer.swift`; all state under `lock`. Tests: none.

A decoded-image cache with a byte budget, plus the lookups the main thread is allowed to make. `ThumbnailController` drives it.

**States**: `cache[path]` (one `Entry{modified, maxPixel, space, image, bytes}` per path), `order` (least recently used first), `bytes`, `budget`, `headers[path]` (valid while the modification date matches).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `lookUp(url)` | — | placeholder (`isDataless`, lstat flag): `.notDownloaded(kept header)`; else `.read(header)` or `.unreadable`; never reads a placeholder on the main thread |
| any | `download(url, completion:)` | — | header read on the concurrent queue (downloads the file), then `completion` on the main queue with the header or nil; no de-duplication, no cancellation (callers `ThumbnailController.swift`) |
| any | `image(at:maxPixel:space:)` | entry inserted | decode, convert, then `insert`; `insert` replaces any entry for the path, so the last finished decode wins whatever its size |
| entry present | `cached` | — | served only if `entry.maxPixel >= maxPixel`, same space, `entry.modified == modified(url)` now |
| over budget | `insert` | oldest entries evicted (`evict`) | — |

**Invariants**

- Bytes stay at or under `budget`, except for the newest entry. Checked by: `evict`.
- A cached entry's pixels are the file's pixels at `entry.modified`. Checked by: nothing. `image(at:)` decodes before it reads the date, so a file replaced in between is cached under the new date with the old pixels ([requests-6](plausible-findings-requests-to-live-ink.md#requests-6)).
- A renamed placeholder is downloaded. Checked by: nothing ([requests-7](plausible-findings-requests-to-live-ink.md#requests-7)).

**Late and concurrent answers**

- A download completion for a card that left the column does nothing: the `loadCard` closure checks `model.cards.contains`; `reshape` re-finds the card by id and refuses cards in the annotator or forming (`ThumbnailController.swift`).
- A file that disappeared reads as a nil header, so `download` completes with nil.

### CaptureOrigin (implicit)

Owner: `CaptureOrigin.swift`. Tests: none.

Finds the screen rect a capture was taken from, for the flight into the editor. Its `CaptureRect.locate` is pure; this machine is the monitor and poll that feed it.

**States**: `monitors`, `poll: Timer?`, `pollUntil`, `wasDown`, `press`, `drag`. Together: idle (no poll), polling (30 Hz until `pollUntil`), holding a drag (after release, until used or 3 s old).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| idle | ⌘⇧ flags change (`flagsChanged`) | polling for 15 s | — |
| polling | flags change again | `pollUntil` extended | — |
| polling | `tick` | — | records press and release into `press`, `drag` |
| polling | past `pollUntil` and button up (`stopPolling`) | idle | `drag` kept |
| holding a drag | `rect(of:pixels:)` | `drag` cleared | the rect is used once |

**Invariants**

- A drag is used once and expires: bounded by `dragLifetime` (3 s) and `arrivedAt >= drag.at` in `locate`. Checked by: those two checks.
- The `recorded` metadata path is bounded by file age (`recordedLifetime`, 10 s). Checked by: that check.
- `rect(of:)` is asked for any presented screenshot with `annotate`, an agent push included (`AppDelegate.swift`), so a cancelled capture drag of nearly the same size within 3 s could give a push a flight origin. Checked by: nothing; visual only.

**Late and concurrent answers**

- A drag outlives `stopPolling` on purpose, so a capture file that arrives after the poll stopped still finds it.

### ReplyCommand and ReplyProtocol (explicit by order)

Owner: `ReplyCommand.swift` (`run`) (`send`). Tests: `ReplyProtocolTests` (parsing and paths only); the app side is covered by the Reply.Stage tests.

The reply helper is the app's own binary, run in a separate process by an agent. It sends one frozen reply bundle and waits for the app's receipt.

**States**: the helper's steps, in order: load the ticket and check its issuer; `prepare` a frozen bundle with a new reply id (or `reread` it for `--retry`); `writeAttempt` with a new attempt id; `dispatch` through `open -g -a <app> vignette://reply?file=…`; `waitForReceipt`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| `waitForReceipt` | receipt `accepted` | exit 0 | for an answer, waits again while `publication == .pending` |
| `waitForReceipt` | receipt `rejected` | exit 2 | — |
| `waitForReceipt` | no receipt before the timeout | exit 3 `unconfirmed` | prints a retry command |
| `waitForReceipt` | dispatch exit 0 but no receipt, or a receipt for another attempt | keeps waiting, then exit 3 | receipts are keyed on request, reply, attempt, digest, protocol (`answers`) |

App side, per attempt: `readAttempt` (ids, path, version, digest shape), look up the request, check the ticket secret, look up an existing reply by id (same digest returns the record's state), check `takesReplies`, `readBundle`, check the digest, store the payload, `write(reply)`, add to `pendingImports`, write the receipt, `importNext`. Any `Problem` writes a `rejected` receipt, except an unauthorized attempt that would overwrite an existing receipt (`reject`).

**Invariants**

- A retry is the same bytes under the same reply id, so it cannot become a second card. Checked by: `ScreenshotRequestsTests.testAReplyTheCommandPreparesIsAcceptedAndItsRetryMakesNoSecondCard`.
- A retry after a clear finds no bundle and says the request was cleared. A clear removes the `submissions` folder (`cleanup`, `ScreenshotRequests.swift`; message at `ReplyCommand.swift`). Checked by: nothing named.

**Late and concurrent answers**

- A clear removes the attempt envelope before the app reads it: the envelope is refused, the helper is unconfirmed, and its retry is refused with the cleared message.
- A receipt for another attempt is ignored (`ReplyCommand.answers`).
