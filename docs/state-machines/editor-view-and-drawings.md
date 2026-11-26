# The editor and drawings: the view, drawings and rendering

This file continues [The editor and drawings: the core](editor-core.md), which has the area's introduction and terms.

### EditorView session (implicit)

Owner: `EditorView.swift`. Tests: `EditorViewTests` (park, join, late-bitmap, typing tests).

The view owns the timers, the text view being typed, and the hand-over to the host. It runs `core.reduce` to completion before it runs any effect.

**States**: `core.isOpen`; `handOverTimer`; `restTimer`, `zoomMoving`; `typingField`; `lingering`; `settling: Tween?`; `heldKeys`; `heldArrows`; `textPress`; `revealPending`; `settingSize`; `placedPicture`. Together they make four phases:

- Closed: `core.isOpen == false`; after `park`, `picture.marks.isParked`. Bitmaps already on screen stay; none arrives.
- Open: `core.isOpen`.
- Typing: `typingField != nil`. It equals `core.typing != nil` after each effect run.
- Lingering: `lingering != nil`. The ended session's text view stays over its text until the text's bitmap is drawn or the text is gone (`settleLingering`). `settling != nil` while the tag springs to balanced lines (`settleLines`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `open` | Open | `stopTimers`, `heldArrows = []`, new `MarkLayers` through `picture.open`, core `.open`, `dropLingering`. If the core refuses: logs `[editor] error open-refused`, stays Closed. |
| Open | `park()` | Closed | Runs the core's non-hand-over effects, `refresh`, `picture.park()`; returns the drawing. Idempotent: returns nil when not open. |
| Closed after `park` | `clear()` | Closed, reset | No change if `core.isOpen`. Else `stopTimers`, `dropLingering`, `core = EditorCore()`, picture parked and reopened empty. |
| Open | `.beginTyping(id)` | Typing | New `TypingField` unless the id is the same; its text view becomes first responder. |
| Typing | `.endTyping` | Lingering | `typingField = nil` first, first responder back to the view, `lingering = field`. |
| Typing | text view resigns to another responder | Typing or Open | `onResign` sends `.typingEnded` only if `typingField === field`. |
| Lingering | text drawn or mark gone | Open | `dropLingering` (`onTextDrawn`, `refresh`). |
| Open | zoom or size step | Open | `pictureMoved` sets `zoomMoving`, re-arms `restTimer`. At rest, `zoomCameToRest` re-hovers and redraws texts. |
| Open | `applyTweaks` | Open | `.tweaksChanged` then `.rescaled`. Typing and lingering fields are restyled, with no check for a composition. ([editor-3](plausible-findings-run-to-toolbar.md#editor-3)) |
| Typing | Cmd+Z | Typing | `performKeyEquivalent` takes it before `typingKey`'s composition check; `undo` calls `field.undo.undo()` when `canUndo`. ([editor-4](plausible-findings-run-to-toolbar.md#editor-4)) |
| Typing | text view `onChange` | Typing | Sends `.typingChanged` with no check that the field is still `typingField`. ([editor-5](plausible-findings-run-to-toolbar.md#editor-5)) |

**Invariants**

- `typingField` mirrors `core.typing`. Checked by: nothing.
- `park` returns its drawing and never sends it through `onHandOver`. Checked by: `EditorViewTests.testParkAnswersAtOnceWithTheDrawingAndIgnoresInputAfterwards`.
- `join` returns its drawing and sends nothing through `onHandOver`. Checked by: `EditorViewTests.testAJoinAnswersWithTheDrawingAndHandsNothingOver`.

**Late and concurrent answers**

- A timer after `park`: `park` runs `.cancelTimer`; `timerFired` is dropped by `isOpen`; `zoomCameToRest` guards `isOpen`.
- A timer after reopen: `open` calls `stopTimers`; so does `clear`.
- `finishForHost` inside `park` may emit `.scheduleTimer`; the `.cancelTimer` that follows (`EditorCore.swift`) leaves no timer.
- Re-entrancy: text-view tracking inside `.passPressToText` runs timers in common run-loop modes. A nested `timerFired` cannot overlap a reduce, because `handle` finishes `core.reduce` before it runs effects.
- `onResign` of a field that already ended (`makeFirstResponder(self)` inside `.endTyping`): ignored by the identity guard.
- A composition owns every key: `typingKey` refuses while `hasMarkedText()`; `placeTypingField` does not restyle during one.
- `revealCaretSoon` reads `typingField` after the turn, so a session that ended gives no reveal.
- A late image decode: `setImage` has no guard of its own; `AnnotationController.open` drops it by comparing openings (`AnnotationController.swift`).

### MarkLayers text bitmap (implicit, one per text mark)

Owner: `MarkLayers.swift`; the editor's plan is `EditorPicture.plan` (`EditorLayers.swift`). Tests: `EditorViewTests.testABitmapThatArrivesAfterItsTextMovedIsNotShown`, `EditorViewTests.testNoBitmapIsShownAfterParkOrOnAnotherImage`, `CardMarksTests`.

Each text mark's words are drawn off the main thread into a bitmap and shown on a layer. The editor, cards and flights each own a plan of what to ask for.

**States**: per `Text` record (`MarkLayers.swift`): `drawn`, `detailDrawn` (what the layers show); `wantWhole`, `wantDetail` (what the plan asks for); `pending: (part, target)?` (one draw on its way); `wanted: Wanted` (what the queue may still draw); `slid`. Per layer: `isParked`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| no `pending`, `want != drawn` | `show` calls `schedule` | `pending = (part, target)` | Draw queued on `queue`. |
| `pending` | queue turn | draw runs, or is skipped | Skipped when `wanted` no longer holds the target. Else a `recent` cache hit, else a scaled copy, else a full draw. |
| `pending` | draw arrives (`arrived`) | `pending = nil` | Dropped when parked, the record is gone, or the identity differs. Else the bitmap is stored only if `target == wantWhole` or `wantDetail`; then `update` and `schedule` the next. A draw that returned nil is recorded as drawn. ([editor-8](plausible-findings-run-to-toolbar.md#editor-8)) |
| any | `park` | parked | `isParked = true`, `wanted = []`, `pending = nil`. No bitmap arrives after. `show` is a no-op after. |
| any | `clear` | cleared | `park`, then all layers and records dropped. |
| mark renamed by a reload | `show` calls `renamed` | record under the new id | `pending = nil`, so the old draw's answer finds no record at `texts[old]` and is dropped. |
| typing | `plan` | whole hidden | `wantWhole = nil` (`EditorLayers.swift`). A draw on its way is dropped in `arrived`, since its target is not `wantWhole`. |

**Invariants**

- A bitmap is shown only while its text still wants exactly that target (a code comment says so). Checked by: `EditorViewTests.testABitmapThatArrivesAfterItsTextMovedIsNotShown`, `testNoBitmapIsShownAfterParkOrOnAnotherImage`.
- A text holds at most two bitmaps, a whole and a detail (comment at `EditorLayers.swift`). Checked by: `CardMarksTests` (a card's bitmap size only, `testACardsTextBitmapHasNoMorePixelsThanTheCard`).
- `drawn != nil` implies the whole layer shows that target. Checked by: nothing; a failed draw breaks it. ([editor-8](plausible-findings-run-to-toolbar.md#editor-8))

**Late and concurrent answers**

- A draw answering after its text moved, was parked, or was renamed: dropped in `arrived`.
- The `Recent` cache holds surfaces weakly.

### TypingField (implicit)

Owner: `EditorTextView.swift`. Tests: `EditorViewTests` (typing tests).

The text view for a note being typed. Its states are those of the EditorView session's Typing and Lingering phases. Extra properties: `settled`, `balanced`, `balancedColor`, `tag`. Its only operations are `place`, `settle`, `follow`, `setStyle` and `recolor`. `onChange` has no identity guard. ([editor-5](plausible-findings-run-to-toolbar.md#editor-5))

### Drawings (implicit, per screenshot key)

Owner: `Drawings.swift`; files in `DrawingStore.swift`. Tests: `DrawingStoreTests`, including `testALoadThatBeganBeforeAWriteDoesNotAnswer`.

`Drawings` is the one writer of a screenshot's stored drawing. A `ScreenshotKey` (see `docs/glossary.md`) names the screenshot.

**States**, per key: the stored file, which holds a drawing, marks or pins (`keys`), a message (`messages`), or both, on disk; `revisions[key]`; `changedAt[key]`; the editor's open drawing for that key (`open`, a weak `OpenDrawing`); loads in flight.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `write(d)`, `d` not empty | stored | Refused when the screenshot file is gone. Else the file is written atomically, `keys.insert`, `revisions += 1`, `onChange(key, d)`. |
| any | `write(d)`, `d.isEmpty` | no file, or a file with only a message | File removed when it holds no message, whatever its `nextPin`, else written with no marks or pins. Version 2 when it holds pins, a `nextPin` over 1 or a pin step, else 1; a higher `nextPin` in the file is kept. If the key was known: `keys.remove`, `revisions += 1`, `onChange(key, nil)`. |
| any | `handOver(d, message:, history:)` | stored with `message` and the editor's `history` | As `write`, which leaves the history out; a message keeps the file when `d` is empty, and `messages` follows it. Refused when the screenshot file is gone and there is a mark or a message. |
| any | `keepMessage(words, for: d, history:)` | the file's marks as stored, its message `words`, the editor's `history` | `DrawingStore.writeMessage`, which numbers the history by `d`'s marks and pins (`basis`); until the next hand-over writes them, a read drops the history: a file with no drawing holds the words when there is none; no drawing and no words remove it. `messages` follows, `changedAt` set; no `revisions` change and no `onChange`. Refused when the screenshot file is gone and `words` is not empty. |
| key in `keys` or `messages` | `remove` | no file | Only if `changedAt <= observedAt`. Removes the file, `changed(key, nil)`. |
| key in `keys` or `messages` | `sweep` | no file | Only with an inventory that confirms absence and `changedAt <= observedAt`. |
| key in `keys` or `messages`, or editor open | `rename(old, new)` | stored under `new` | Store rewrites under `new`, message included; then `open?.rekey`; `onChange(old, nil)`, `onChange(new, d)`. If the store throws, returns before `rekey`, and the open editor keeps the old key, so its later writes are refused. ([editor-2](plausible-findings-run-to-toolbar.md#editor-2)) Then `revisions[old] = nil`, which reads as 0 again. ([editor-9](plausible-findings-run-to-toolbar.md#editor-9)) |
| editor open for key | `add` | stored, open drawing joined | `open.join(made)` returns the joined drawing; `write(joined, history: open.history(of:), "saved")`. Throws `writeFailed` if the write is refused. |
| no editor | `add` | stored, its history one step longer | Read the stored drawing (or a new one) and its history, append the marks, take the pins (`Drawing.taking`), record one `agentMarks` step holding both, `write(.., history:, "built")`. Checked by: `testAgentsMarksJoinTheStoredDrawing`. |
| any | `load(keys)` | — | Records `revisions` now; reads on `loads`; on the main thread, drops each key whose revision changed. |

**Invariants**

- `keys` mirrors the files with a drawing, marks or pins, this build can read, and `messages` those with a message: the launch scan, then every write and remove. Checked by: `DrawingFileTests.testKeysListTheDrawingsThisBuildCanRead`, `testAMessageIsKeptBesideTheMarksAndWithoutThem`, `DrawingMessageTests.testAMessageFollowsARenameAndGoesWithItsScreenshot`.
- The open editor's drawing wins over the stored one for `current(of:)`. Checked by: `testTheDrawingNowIsTheOpenOneOverTheStoredOne`.
- A load never answers older than a write. Checked by: `testALoadThatBeganBeforeAWriteDoesNotAnswer`.
- A rename moves the stored file and the open drawing. Checked by: `testARenamedScreenshotKeepsItsDrawingUnderTheNewKey`, `testTheOpenDrawingFollowsARenameAndItsLaterWritesLandUnderTheNewKey`. A failing store is not tested. ([editor-2](plausible-findings-run-to-toolbar.md#editor-2))
- One write per agent push. Checked by: `testAPushToTheOpenDrawingWritesWhatTheJoinAnswersOnce`.
- A file from a newer build is never written or removed (`DrawingStore.swift`). Checked by: `testANewerVersionIsReadAsNoDrawingAndNeverOverwritten`.
- A read never moves a file; only the launch scan does (`DrawingStore.swift`). Checked by: `testAFileThatDoesNotParseIsSetAsideByTheLaunchScanOnly`.
- `rename` calls `onChange(new, drawing)` with the editor's live drawing while the file holds the stored one until the next hand-over. Checked by: nothing.

**Late and concurrent answers**

- A load that began before a write or remove: its answer for that key is dropped by the revisions compare.
- A hand-over after the screenshot was trashed: refused.
- A removal or sweep with an inventory older than the last change: refused by `observedAt` against `changedAt`.

### Rendering and clipboard promise (implicit)

Owner: `RenderingQueue.swift`, `PendingRendering`, `Clipboard.swift`, `RenderingProvider` (`Clipboard.swift`), `DragItems.swift`. Tests: `RenderingPromiseTests`, for the promised item and a drag's file made from kept bytes; none for the queue's ordering.

Done, Cmd+C, Copy Drawing and a card drag render a drawing to a PNG on one serial queue, with its pins' comments listed beside the picture (`Rendering.Layout.withComments`). The clipboard holds a promise of the PNG until the rendering finishes. A card drag renders its PNG before the drag, from the hover or the press, and writes only the file when the drag begins.

**States**

- `PendingRendering`: pending, then finished(output) once. `finish` is idempotent (`RenderingQueue.swift`). `wait(timeout:)`, `isDone` and `whenDone` read it.
- Queue: each `render` adds one job to `firstJobs` or `jobs` under `lock` and enqueues one block. A block runs whichever job is next, `firstJobs` first. The block count always equals the job count.
- Clipboard: `copyRendering` clears the pasteboard, writes one item (the path and its pins' words as text now; PNG, TIFF and file URL promised), and records `changeCount`.
- `DragItems`: `kept`, the PNGs rendered for drags, newest last, finished or not, each under its key (screenshot, drawing, text style, mark style); `ahead`, the one rendering `prepare` started that has not finished; `wanted`, the first 3 cards with drawings that `prepare` named last (`preparedAhead`). `StackModel.prepareDrag` names the hovered or pressed card first, then the rest of the selection a drag from it carries.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `render(.first)` | queued ahead | Overtakes jobs not yet started. Senders: Done (`finishAnnotation`, AppDelegate), Cmd+C with nothing selected (`copyDrawing`). |
| any | `render(.inTurn)` | queued behind | Jobs of one order run in request order. Senders: Copy Drawing (`copyAnnotated`, completing through `finishCopyAnnotated`), drag (`DragItems.rendering(for:)` `DragItems.swift`, as bytes). |
| any | `resultURL` fails | finished (failed) | Finishes at once without queuing (`RenderingQueue.swift`). |
| no `ahead`, or `ahead` finished | `prepare(cards)` (hover or press on a card) | `ahead` = the first wanted key not kept | Renders that key's PNG in turn and keeps it. Nothing when every wanted key is kept. |
| `ahead` pending | `prepare(cards)` | `ahead` unchanged | Only `wanted` changes. When `ahead` finishes, `trim` runs and the next wanted key starts. |
| any | drag begins (`items(for:)`) | file pending | Takes the kept PNG for each card's key, or renders one in turn (every card past the first 3 with drawings in a selection), and calls `file(from:beside:)`, which names the file now and writes it on its own queue once the PNG exists (`RenderingQueue.swift`). A kept PNG that failed is rendered again. |
| kept over 32 MB | `trim` (after `prepare` and each rendering) | oldest finished entries dropped | Pending entries and the wanted keys' entries stay, so a wanted PNG is never dropped and rendered again. |
| pending | job runs | finished | Reads the screenshot file now, so a trash or rename before this fails as `unreadableImage`; the card says Not copied. |
| clipboard promised | paste before finish | waits | `RenderingProvider` waits up to 5 s on the main thread (`Clipboard.swift`); gives nothing if the rendering failed. |
| clipboard promised | rendering fails | clipboard cleared, or kept | Cleared only if `changeCount` is unchanged (`Clipboard.swift`). |
| dragged item | rendering fails | path text stays | Only logged ("the drop gets no image for it", `DragItems.swift`). The string set at `Clipboard.swift` stays on the item. ([editor-6](plausible-findings-run-to-toolbar.md#editor-6)) |
| Copy Drawing | last rendering done | files on clipboard | `finishCopyAnnotated` calls `Clipboard.copyFiles(urls)` with no `changeCount` check. ([editor-7](plausible-findings-run-to-toolbar.md#editor-7)) |

**Invariants**

- The later of Done's and Cmd+C's clipboards wins; the earlier one's failure does not clear the later (guard `Clipboard.swift`). Checked by: nothing.
- When the last `.inTurn` rendering of a Copy Drawing is done, all of them are (serial queue, FIFO within an order; `finishCopyAnnotated` uses `wait(timeout: 0)` on each). Checked by: nothing; no test mixes orders.

**Late and concurrent answers**

- A late failure against a newer clipboard: guard at `Clipboard.swift`.
- A paste before the rendering finishes: waits, `Clipboard.swift`. Each answer logs `[clipboard] gave` or `[drag] gave` with how long the main thread waited.
- A drop target that asks during the drag: answers from the kept PNG when it was ready (`[drag] cards=… ready=…`), else waits as a paste does.
- Copy Drawing finishing after the person copied something else: overwrites it. ([editor-7](plausible-findings-run-to-toolbar.md#editor-7))

### DragSourceView press (implicit)

Owner: `DragSourceView.swift`, with `StackModel.drag(_:_:)` (`StackModel.swift`). Tests: none.

**States**: `downPoint`, `dragging`; in the model, `pressedCard` and `draggedCard`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | mouse down | `downPoint` set, `dragging = false` | `onPress(true)`. |
| pressed | drag past 5 pt, no items | `dragging = true` | `onPress(false)`. |
| pressed | drag past 5 pt | `dragging = true`, `draggedCard` set, `pressedCard` cleared | `items()` (writes the files from kept PNGs), `onDrag(.began)`, begins a drag session. The card keeps the press scale while it is dragged. |
| pressed, not dragging | mouse up | idle | `onPress(false)`, `onClick()`. |
| dragging | mouse up | `dragging` stays true | Swallowed by the session. |
| dragging | session ends | `draggedCard` cleared | `onDrag(.ended(pointerOnCard:))`: the card springs back from the press scale. The hover is cleared when the pointer is off the card and the hover is not held. |

**Invariants**

- `dragging` is reset only by the next mouse down. Checked by: nothing.
