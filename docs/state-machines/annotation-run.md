# The annotation run: the transitions and the run

The annotation run decides which image is in the annotator (the editor window), what is flying, and what opens next. A pure reducer (`AnnotationRun`) holds a pure transition table (`AnnotatorTransition`), and `ThumbnailController` and `AnnotationController` carry out the effects they return.

### AnnotatorTransition (explicit)

Owner: `AnnotatorTransition.swift`, held privately by `AnnotationRun.transition` (`AnnotationRun.swift`). Tests: `AnnotatorTransitionTests.testRandomSequencesKeepTheInvariants`, `AnnotatorTransitionTests.testRequestingTheImageParkingForASwapOpensItAgainAfterThePark`, `AnnotatorTransitionTests.testRemovingTheFileParkingForASwapHidesItAndOpensNothing` ([issue 8](issues.md#issue-8)).

Decides how the annotator moves between images and when it closes. `AnnotationRun` is the only sender (`forward`, `AnnotationRun.swift`).

An `Opening` (`AnnotatorTransition.swift`) is one image sent to the annotator. Its `id` is its identity (`==` and `hash` use only `id`). Its `key` can change by rename, and `paged` is set by `.page`.

**States** (`Phase`)

- `idle`.
- `flyingOut(o)`: `prepare` was sent and the card is travelling. The window is ordered in at alpha 0, nobody has seen it, and no zoom is possible.
- `annotating(o)`: `shown(o)` came and the window is up.
- `parking(o, then: Next)`: the editor is parking `o`'s drawing. `Next` is `annotate(o2)` (a swap), `close` (Esc or Send), `finish` (Done), `dismiss` or `remove`.

**Transitions** (`—` means ignored, returns `[]`)

| State | Event | Next state | Effects |
|---|---|---|---|
| `idle` | `annotate(o2)` | `flyingOut(o2)` | `prepare(o2)` |
| `flyingOut(o)` | `annotate(o2)`, same key | — | — |
| `flyingOut(o)` | `annotate(o2)`, other key | `flyingOut(o2)` | `abandon(o)`, `returnCard(o)`, `prepare(o2)` |
| `annotating(o)` | `annotate(o2)`, same key | — | — |
| `annotating(o)` | `annotate(o2)`, other key | `parking(o, annotate(o2))` | `park(o)` |
| `parking(o, annotate)` | `annotate(o2)` | retargets the swap to `o2` | — |
| `parking(o, close)` | `annotate(o2)` | same key: stays `close`. Other key: `annotate(o2)` | — |
| `parking(o, finish)` | `annotate(o2)` | same key: —. Other key: `annotate(o2)` | — |
| `parking(o, dismiss or remove)` | `annotate(o2)` | — (a dismissal keeps winning) | — |
| `flyingOut(o)` | `shown(s)` | `s == o`: `annotating(o)`. Else — | `show` |
| other states | `shown` | — | — |
| `parking(o, N)` | `parked(p)`, `p == o` | `N = annotate(o2)`: `flyingOut(o2)`. `close`: `idle`. `finish`: `idle`. `dismiss` or `remove`: `idle` | `annotate`: `returnCard(o, copied: false)`, `prepare(o2)`. `close`: `returnCard(o, false)`. `finish`: `returnCard(o, true)`. `dismiss`/`remove`: `hideAnnotator` |
| any other state | `parked`, or a `parked` for another opening | — | — |
| `flyingOut(o)` | `close` | `idle` | `abandon(o)`, `returnCard(o, false)` (same turn) |
| `annotating(o)` | `close` | `parking(o, close)` | `park(o)` |
| `parking(o, annotate(o2))` | `close` | `parking(o, close)` (**fixed**, [run-2](findings.md#run-2)) | — |
| `parking(o, close, finish, dismiss or remove)` | `close` | — | — |
| `flyingOut(o)`, `annotating(o)` | `finish` | `parking(o, finish)` | `park(o)` |
| `parking(o, any N)` | `finish` | — (ignored in every `N`) | — |
| `flyingOut(o)`, `annotating(o)`, `parking` | `dismiss` | `parking(o, dismiss)` | `park(o)`, except none from `parking` |
| `flyingOut(o)`, `annotating(o)` | `remove(r)`, `r == o.key` | `parking(o, remove)` | `park(o)` |
| `flyingOut(o)`, `annotating(o)` | `remove(r)`, other key | — | — |
| `parking(o, annotate(o2))` | `remove(r)`, `r == o2.key` | `parking(o, close)` | — |
| `parking(o, close or finish)` | `remove(r)`, `r == o.key` | `parking(o, remove)` | — |
| `parking(o, annotate(o2))` | `remove(r)`, `r == o.key` | `parking(o, remove)`: the annotator hides and nothing opens (**fixed**, [run-3](findings.md#run-3)) | — |
| `parking(o, dismiss or remove)` | `remove` | — | — |
| not `idle` | `newShot(n)` | unchanged | `join(n)` (the controller ignores `.join` under `dismiss` and `remove`, `ThumbnailController.swift`) |
| not `idle` | `renamed(old, new)` | unchanged, `o` re-keyed (also the `o2` in `annotate(o2)`) | — |

`heading` is the image a page moves on from: `o` in `flyingOut` and `annotating`, `o2` in `parking(_, annotate(o2))`, else nil.

**Invariants**

- A `prepare` is never emitted while a park is in flight. Checked by: `AnnotatorTransitionTests.testRandomSequencesKeepTheInvariants`.
- At most one park is in flight, and `park` and `abandon` name the prepared opening. Checked by: the same test.
- An answer naming another opening changes nothing. Checked by: the same test and the guards and.
- `annotating` implies the image was prepared. A dismissal ends `idle` with everything hidden. Checked by: the same test.
- A close takes effect over a swap that is parking. Checked by: `AnnotationRunTests.testACancelDuringASwapsParkClosesInsteadOfOpeningTheNextImage` (**fixed**, [run-2](findings.md#run-2)). A close or a finish during any other park is ignored: the park already ends the image.
- `returnCard` is never emitted for a file that no longer exists. Checked by: `AnnotatorTransitionTests.testRemovingTheFileParkingForASwapHidesItAndOpensNothing` for the swap's park (**fixed**, [run-3](findings.md#run-3)); nothing else checks it.

**Late and concurrent answers**

- `shown` and `parked` naming a past opening: dropped by the opening compare.
- `close` or `annotate` while `flyingOut`: answered in the same turn with `abandon` and `returnCard`.
- A swap back to the same key while parking: reopens it after the park (`AnnotatorTransitionTests.testRequestingTheImageParkingForASwapOpensItAgainAfterThePark`).
- A removed swap target turns the swap into a close.

### AnnotationRun (explicit, composite)

Owner: `AnnotationRun.swift`, held in `ThumbnailController.run` (`ThumbnailController.swift`); only `handle` writes it. Tests: `AnnotationRunTests.testRandomSequencesKeepTheInvariants` (in `AnnotationRunTests+Sequences.swift`), `AnnotationRunTests.testAFileGoneFromTheQueueSkipsNoNumber`, `AnnotationRunTests.testADismissalEndsTheRunAndSaysWhetherAHandEndedIt`, `AnnotationRunTests.testACancelDuringASwapsParkClosesInsteadOfOpeningTheNextImage` and `AnnotationRunTests.testRemovingTheOpenFileDuringASwapsParkEndsTheRun` ([issue 8](issues.md#issue-8)).

Owns the list of files to annotate and how a hand ended the run. It wraps the transition, adds the queue, and emits `endRun` once per run. `ThumbnailController` sends the events.

**States**: the properties together (`AnnotationRun.swift`).

- `transition`: the phase above.
- `minted`: the last opening id. Never reset.
- `lift: Lift`: `loaded`, `takesPresses`, `arrived`, `lifted`. Reset at each `prepare`.
- `queue`, `total`, `opened`, `fromQueue`: the list and its counters.
- `uncopied: Opening?`: Done's copy, or the drawing's save, failed while this opening parked.
- `ending: RunEnding?`: how a hand ended the run. Reported once by `endRun`.

**Events** and senders (`ThumbnailController.swift`)

- `annotate([key])`: `startAnnotating`, and a card click while active.
- `page(key, isRepeat)`: `page(_:isRepeat:)`, from the editor's Left and Right.
- `shown(o)`, `arrived(o)`: flight closures in `perform(.prepare)`.
- `parked(o)`: `perform(.park)`.
- `loaded(o)`: `editorLoaded`. `takesPresses(o)`: `annotatorTakesEvents`.
- `cancel(RunEnding)`: `annotationEnded` (Esc, Cmd+W, bar close, a click outside over lone thumbnails, decode failure) and `CornerPresentation` `.closeEditor` as `.shortcut`.
- `undo`: `ThumbnailController+History.draw(nil)`, an Undo or a Redo closing the annotator over the stack.
- `sent`: `annotationSent`. `finish`: `annotationFinished(quick: false)`. From `slideOut`, `dismiss(reason.runEnding)`: `dismiss(.finished)` for quick Done, `dismiss(.clickedAway)` for a click outside while the stack shows, `dismiss(nil)` otherwise.
- `remove([key])`. `renamed`. `selectionChanged`. `failed(o)`: `showFailed`, from `showNotCopied(in:)` and `showNotSaved` (`ThumbnailController+Notices.swift`). `newShot`: `show`.

**Transitions** (the run's own change, then the transition's result `T`)

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `annotate(keys)` | `queue = keys.dropFirst()`, `total`, `opened = 1`, `fromQueue = nil` (set even when `T` ignores the annotate), then `T.annotate(mint(first))` | as `T` |
| any | `page(key)` | refused unless `takesPage`: `heading != nil`, and a repeat also needs `annotating` and `lift.lifted`. Else as `annotate([key], paged)` | as `T` |
| any | `loaded`, `takesPresses`, `arrived` for `o == opening` | sets that `Lift` flag | `takesPresses` adds `handOverPresses`, `arrived` adds `landed`; `liftFlight` once when all three are in |
| any | `shown`, `parked` | as `T` | as `T` |
| any | `cancel(how)` | `ending = how` if active; `queue = []` always, then `T.close` ([run-1](findings.md#run-1), [run-2](findings.md#run-2)) | as `T` |
| any | `undo` | `queue = []`, `ending` unset, then `T.close` | as `T`; `endRun(nil)`, so the corner hands no keys back |
| any | `sent` | `ending = .sent` if active; queue kept, then `T.close` | as `T` |
| any | `finish` | `ending = .finished` if active; queue kept, then `T.finish` ([run-4](findings.md#run-4)) | as `T` |
| any | `dismiss(e)` | `ending = e` if `e` is set and active; `queue = []`, then `T.dismiss` | as `T` |
| any | `remove(keys)` | drops them from `queue` (`total` is not reduced, [run-6](plausible-findings-run-to-toolbar.md#run-6)); if the open key is removed, `queue = []`, then one `T.remove` per key ([run-3](findings.md#run-3)) | as `T` |
| any | `renamed` | re-keys `queue`, `fromQueue`, `uncopied` and `T` | — |
| active, list not ended | `selectionChanged` | removes, then appends the added keys | `queued` |
| active, list ended (`total == 0`: Esc, a dismissal or the open file going) | `selectionChanged` | — (**fixed**, [run-1](findings.md#run-1)) | — |
| idle | `selectionChanged` | — | — |
| `parking(o, finish)` | `failed(o)` | `uncopied = o` | — |
| other | `failed` | — | — |

After every `T` result:

- `.prepare` resets `uncopied` and `lift`.
- `.returnCard` drops the Copied mark if `uncopied == opening`.
- `.hideAnnotator` calls `endQueue`.
- When the transition goes from active to idle, `continueOrEnd` opens `queue.first` (`next`, then annotate) or emits `endRun(ending)` and clears `ending`. `reduce` also clears `ending` whenever a `prepare` is left after the files that cannot open are passed over (**fixed**, [run-4](findings.md#run-4)).
- `reduce` asks `opens(key)` for the last `prepare`. When the file cannot open it deletes that `prepare` and `next`, and `cannotOpen` resets the transition to `idle` and calls `continueOrEnd`.

**Invariants**

- The queue is empty whenever idle and right after a cancel or dismiss. `endRun` comes exactly when the run goes idle, once per run. Nothing opens while a dismissal ends the run. Every opening is new. A flight lifts once. Handover, landed and lift name the opening in the editor. A file that does not open is never prepared. A failed copy leaves its card unmarked. A page replaces the queue. A repeat in flight changes nothing. Checked by: `AnnotationRunTests.testRandomSequencesKeepTheInvariants`.
- Once Esc, a dismissal or the open file going empties the queue, nothing refills it before the park ends. Checked by: `AnnotationRunTests.testACardSelectedWhileEscParksQueuesNothing` (**fixed**, [run-1](findings.md#run-1)).
- `ending` describes only the image it was set for (comment). Checked by: `AnnotationRunTests.testAHandoverForgetsHowTheImageBeforeEnded` (**fixed**, [run-4](findings.md#run-4)).
- `place ... of total` stays inside `1...total`. Checked by: the random test. `total` is not reduced when a queued file is removed, so the log says "2 of 3" for two files (`AnnotationRunTests.testAFileGoneFromTheQueueSkipsNoNumber` asserts it); log only ([run-6](plausible-findings-run-to-toolbar.md#run-6)).

**Late and concurrent answers**

- Any run event naming a past opening: dropped.
- A file that stops reading before it opens: `cannotOpen`.
- A session-ending event clears the queue before a park can answer in the same turn.
- `uncopied` is matched by opening id.
- A rename re-keys the queue.
- A flight dropped before it arrives sends no `arrived`, so `lift.lifted` stays false and a held Left/Right stops repeating. No guard ([run-5](plausible-findings-run-to-toolbar.md#run-5)).

### EventHold (explicit)

Owner: `AnnotationRun.swift`, held by `ThumbnailController.hold`. Tests: `AnnotatorTransitionTests.testRandomSequencesKeepTheInvariants`.

Runs events in order. An event sent while another is being handled waits its turn. State: `held: [Event]` and `handling: Bool`.

**States**: idle (`handling == false`) and draining (`handling == true`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| idle | `send` | draining, then idle when `held` is empty | runs the event, then every held event in FIFO order |
| draining | `send` | draining | appends to `held` |

**Invariants**

- No event runs inside another. Checked by: `AnnotatorTransitionTests.testRandomSequencesKeepTheInvariants` ("a held event runs in the loop that holds it").

**Late and concurrent answers**

- A same-turn `parked` from `hide` at zoom 1 (`fitBeforeHide` calls `done()` at once, `AnnotationController.swift`): held until the current event ends.
- `loaded` from a cached decode inside `prepare` (`AnnotationController.swift`): held.
- A failed `open` calling `cancel()` inside `prepare`: held.
