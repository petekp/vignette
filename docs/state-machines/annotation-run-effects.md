# The annotation run: effects, window and focus

This file continues [The annotation run: the transitions and the run](annotation-run.md), which has the area's introduction and terms.

### ThumbnailController, the run's effect layer (implicit)

Owner: `ThumbnailController.swift` (`handle`) (`perform`). Tests: none.

Carries out the run's effects and keeps the stack, the dim and the keys in step with it.

**States**: the properties that together say "an annotation is on screen".

- `run`. `sessionCard`, the card the run has open: set in `perform(.prepare)`, nil at `.endRun`. `annotating` is `run.isActive ? sessionCard : nil`.
- `annotationFrame`, `parkedMarks`, `captureOrigin`, `flightPress`.
- `model.annotating` and `flights.staysUp`: flipped together at the end of `handle` when `model.annotating != run.isActive`, which sends `keys.send(.editorOpened)` or `.editorClosed(ending)` with the `ending` from this batch's `endRun`.
- `model.outCards` holds the session card's id from `.prepare` until `returnCard` arrives (`:~915`) or `.hideAnnotator`; a card that leaves with a dismissed column keeps it until the slide-out's completion empties `outCards`.
- `dim`: shown at `.prepare`, hidden only at `.endRun`.
- `model.slidingOut` (set, reset and in `present`).

**Transitions** (effect, guard, result)

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `.prepare` | `sessionCard` set, card in `outCards`, dim shown, `parkedMarks` cleared | returns silently when the stack has no card for the key (not reachable, `opens` made the card first) |
| any | `.show` | — | `onAnnotatorShow`; a lone card alone in the corner leaves the panel |
| any | `.park` | `parkedMarks = annotatorMarks()` | `onAnnotatorHide` then `send(.parked(opening))` |
| any | `.abandon` | `parkedMarks` set | `onAnnotatorAbandon` |
| any | `.returnCard` | card home | needs `sessionCard.key == opening.key`; re-inserts the card when the panel lacks it (`returnCard`) ([run-3](findings.md#run-3)) |
| any | `.hideAnnotator` | `parkedMarks = nil` | with `leavingWithColumn` naming the card and the stack not visible, flies the image to its slot's place off the screen; otherwise ends the flight; clears `leavingWithColumn` |
| any | `.endRun` | `sessionCard = nil` | `dim.hide()` |
| any | `.landed`, `.liftFlight` | — | each needs `sessionCard` |
| any | `.handOverPresses` | — | `flightPress.ready(key)` |
| any | `.join`, `.next`, `.queued` | — | `.join` is a no-op; the others only log |

**Invariants**

- The editor is open exactly while the run is (comment). Checked by: nothing; the reducer tests cover only `endRun` once per run.
- `parkedMarks` is consumed by `homeFlightMarks` and cleared at `.prepare` and `.hideAnnotator`. A stale value is used only when its `drawing.key` matches the card. Checked by: nothing.

**Late and concurrent answers**

- `slideOut` turns every card still flying home offscreen, records the annotator's card and its slot's place off the screen in `leavingWithColumn`, and sends `.dismiss`. The flight starts at `.hideAnnotator`, in the same turn at zoom 1 and after the fit-out when zoomed. A stack presented again before then makes `visible` true, and `.hideAnnotator` ends the flight instead.
- `handle` runs `makeRoom` once for a batch, so a swap is one column.
- `flightPress.ended` for an image no longer in the editor.
- `perform(.park)` sends by opening id, so the reducer drops a late `parked`.
- A rename updates `sessionCard` before `send(.renamed)`, so `returnCard`'s key compare holds.
- `annotate(_:from:)` calls `startAnnotating` after the capture's decode with no check that anything changed, and `captureOrigin` survives an ignored annotate until the next `prepare` of that key ([run-7](plausible-findings-run-to-toolbar.md#run-7)).

### AnnotationController session (implicit)

Owner: `AnnotationController.swift`. Tests: none (needs AppKit).

The annotator window and editor for the image the run opened. It is reused; the run's effects drive it.

**States**: the properties together.

- `current: Screenshot?`: set in `prepare`, nil in `hide` and `abandon`. `opened: Opening?`. `opening` is `current == nil ? nil : opened`.
- `windowUp` (true after `show`, false at `prepare`), `editorUntouched`.
- `eventProbe: Timer?`, `outsideClick`, `removal` (`WindowRemoval`), `titleReveal`, `inkMeasurement`. The zoom properties belong to the flights area.

Phases, derived:

1. Closed: `current == nil`, window hidden or absent.
2. Prepared: `current != nil`, `windowUp == false`, alpha 0, keys held.
3. Shown: `windowUp == true`, `outsideClick` running unless the corner is the stack, `eventProbe` running until it answers.
4. Hiding: `current == nil` while `fitBeforeHide` is pending (zoomed only).
5. Removing: `removal` pending (`hideWindows`); the window is still ordered in.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `prepare` | Prepared | cancels `removal`; resets `windowUp`, `editorUntouched`, zoom and title reveal (`.opened` / `.closed`) |
| Prepared | `prepare` with an unreadable image | Prepared | calls `cancel()`, so `onClosed(.back)` reaches the run as `.cancel`, held until the batch ends |
| Prepared | `show` | Shown | needs `current != nil` |
| Closed | `show` | — (ignored) | — |
| `current != nil` | `cancel(how)` | — | `onClosed(how)` only; hides nothing |
| `current == nil` | `cancel` | — (ignored) | — |
| any | `hide(then:)` | Hiding (zoomed) or Removing | `current = nil`, `park()`, `fitBeforeHide`, then `hideWindows` and `then()` |
| `current != nil` | `abandon` | Removing | `zoom.reduce(.close)`, `current = nil`, `park()`, `hideWindows()` |
| `current != nil` and `opened == opening` | `renamed` | — | re-keys `current` |
| Hiding | `renamed` | — (ignored; `opened` keeps the old key, so the flight home loses the title, `takeTitle(of:)`) ([run-8](plausible-findings-run-to-toolbar.md#run-8)) | — |
| any | `landed` | — | sets the shadow, `revealTitle(.landed)`; not guarded by opening or `current` |

**Invariants**

- `hide` is called once per `prepare` (comment). Checked by: nothing in the controller; the run emits one `park` or `abandon` per opening.
- The window and editor are reused, and the last image's `removal` must not take them (comment). Checked by: `removal.cancel()`.
- `eventProbe` never answers for an opening that ended. Checked by: the compare and `stopProbe()` in `hide` and `abandon`.
- `landed()`, `onClosed`, `onFinished` and `onSend` rely on `current != nil` meaning "the run's current opening". That holds because `hide` clears `current` in the call that begins the park, and the run emits `prepare` only after `parked`. Checked by: nothing.

**Late and concurrent answers**

- The `loaded` decode: dropped unless `self.opening == opening`.
- The `eventProbe` answer: compares `opening`; gives up after 0.5 s.
- The `revealTitle` 0.5 s wait: compares `opened == opening` and `current != nil`.
- The ink `Task`: compares `inkMeasurement` and `current != nil`. `measureTitleInk` returns early without bumping it when the next image has no title, so a stale answer lands on a `.closed` reveal with no visible effect.
- `offerTyping`: needs `windowUp`, `editorUntouched` and `current != nil`.
- `fitBeforeHide`: answers once (`answered`) from the tween or its 0.3 s deadline.
- Esc during the zoomed fit-out: dropped by `cancel`'s `current != nil` guard.
- `dropped:` closure of a flight: calls `onAnnotatorLanded` with no opening compare (`ThumbnailController.swift`); `TitleReveal` ignores a late `landed` once closed.

### TitleReveal (explicit)

Owner: `AgentTitle.swift`. Tests: none. Driven by `AnnotationController.revealTitle`.

Decides when an image's title fades in: after the flight lands and its ink is known.

**States**: `flying(inkKnown)`, `waiting(since)`, `shown`, `closed`. Inputs: `opened`, `inkKnown`, `landed`, `waitEnded`, `closed`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `opened` | `flying(false)` | — |
| any | `closed` | `closed` | — |
| `flying` | `inkKnown` | `flying(true)` | — |
| `waiting` | `inkKnown` | `shown` | `.show(waited)` |
| `flying(true)` | `landed` | `shown` | `.show(0)` |
| `flying(false)` | `landed` | `waiting` | `.waitForInk` |
| `waiting` | `waitEnded` | `shown` | `.showInAppearanceInk` |
| anything else | any | — (the `default` row) | — |

**Invariants**

- A late `landed`, `inkKnown` or `waitEnded` after `closed` is ignored. Checked by: the `default` row; no test.

**Late and concurrent answers**

- The wait timer compares the opening id: `AnnotationController.swift`.
- `inkKnown` for the previous image after `closed`: ignored.

### WindowRemoval (implicit)

Owner: `WindowRemoval.swift`. Tests: none.

Takes the annotator window down after the flight home covers the frame. State: `generation`, `link`, `left`, `remove`.

**States**: idle, started (waiting for the next main turn), counting (display link running, `left` refreshes to go).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `start` | started | cancels first; next main turn runs `hide`, installs a display link, runs `remove` after 3 refreshes |
| started or counting | `cancel` | idle | bumps `generation`, kills the link, drops `remove` |

**Invariants**

- A removal cancelled before its main-queue hop runs neither `hide` nor `remove`. Checked by: the `generation` compare.

**Late and concurrent answers**

- A display link that never fires (display asleep): `remove` never runs and the editor's image stays held until the next `prepare`. No guard.

### OutsideClick (implicit)

Owner: `OutsideClick.swift`. Tests: none.

Reports a click outside the annotator. State: `monitor: Any?`. The annotator starts it in `show` (`AnnotationController+ShowingAndHiding.swift`) unless the corner is the stack, whose own watch then decides a click outside (`show(watchesClickOutside:)`, passed `!keys.isStack` by the run's `.show` effect), and stops it in `hide` and `abandon`; `start` replaces an earlier monitor. The handler ignores clicks before `watching` (`settling` 0.15 s, `OutsideClick.swift`) and checks the window under the cursor first.

### FocusReturn (implicit)

Owner: `FocusReturn.swift`. Tests: none.

Remembers where the focus goes back to. State: `previousApp` and a weak `ownWindow`. `sessionStarting` records a titled key window (only if Vignette is active); an app activation clears `ownWindow` and sets `previousApp`; `restore` prefers a visible `ownWindow` and does not clear it, so it persists until another app activates. `CornerKeys` calls it on `.restoreFocus` after `editorClosed(ending)`.
