# The annotation run: effects, window and focus

This file continues [The annotation run: the transitions and the run](annotation-run.md), which has the area's introduction and terms.

### ThumbnailController, the run's effect layer (implicit)

Owner: `ThumbnailController.swift:734` (`handle`), `:790` (`perform`). Tests: none.

Carries out the run's effects and keeps the stack, the dim and the keys in step with it.

**States**: the properties that together say "an annotation is on screen".

- `run` `:75`. `sessionCard` `:77`, the card the run has open: set in `perform(.prepare)` `:797`, nil at `.endRun` `:871`. `annotating` `:78` is `run.isActive ? sessionCard : nil`.
- `annotationFrame` `:79`, `parkedMarks` `:82`, `captureOrigin` `:145`, `flightPress` `:84`.
- `model.annotating` and `flights.staysUp`: flipped together at the end of `handle` when `model.annotating != run.isActive` (`:757-765`), which sends `keys.send(.editorOpened)` or `.editorClosed(ending)` with the `ending` from this batch's `endRun`.
- `model.outCards` holds the session card's id from `.prepare` (`:803`) until `returnCard` arrives (`:~915`) or `.hideAnnotator` (`:856`).
- `dim`: shown at `.prepare` (`:808`), hidden only at `.endRun` (`:872`).
- `model.slidingOut` (set `:704`, reset `:716` and in `present`).

**Transitions** (effect, guard, result)

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `.prepare` | `sessionCard` set, card in `outCards`, dim shown, `parkedMarks` cleared | returns silently when the stack has no card for the key (`:794`; not reachable, `opens` made the card first) |
| any | `.show` | — | `onAnnotatorShow`; a lone card alone in the corner leaves the panel (`:838-843`) |
| any | `.park` | `parkedMarks = annotatorMarks()` | `onAnnotatorHide` then `send(.parked(opening))` (`:845`) |
| any | `.abandon` | `parkedMarks` set | `onAnnotatorAbandon` (`:847`) |
| any | `.returnCard` | card home | needs `sessionCard.key == opening.key` (`:852`); re-inserts the card when the panel lacks it (`returnCard`, `:888-900`) ([run-3](findings.md#run-3)) |
| any | `.hideAnnotator` | `parkedMarks = nil` | ends the flight unless the column is sliding out with that card in it (`:855-858`) |
| any | `.endRun` | `sessionCard = nil` | `dim.hide()` |
| any | `.landed`, `.liftFlight` | — | each needs `sessionCard` (`:874`, `:882`) |
| any | `.handOverPresses` | — | `flightPress.ready(key)` (`:880`) |
| any | `.join`, `.next`, `.queued` | — | `.join` is a no-op; the others only log |

**Invariants**

- The editor is open exactly while the run is (comment `:754`). Checked by: nothing; the reducer tests cover only `endRun` once per run.
- `parkedMarks` is consumed by `homeFlightMarks` (`:985`) and cleared at `.prepare` (`:809`) and `.hideAnnotator`. A stale value is used only when its `drawing.key` matches the card (`:988`). Checked by: nothing.

**Late and concurrent answers**

- `slideOut` sets `model.slidingOut` and aims the flight offscreen before sending `.dismiss`, so a same-turn park keeps that flight: `:704`, `:855`.
- `handle` runs `makeRoom` once for a batch, so a swap is one column: `:741-748`.
- `flightPress.ended` for an image no longer in the editor: `:750-752`.
- `perform(.park)` sends by opening id, so the reducer drops a late `parked`.
- A rename updates `sessionCard` before `send(.renamed)`, so `returnCard`'s key compare holds: `:501-507`.
- `annotate(_:from:)` calls `startAnnotating` after the capture's decode with no check that anything changed (`:324-338`), and `captureOrigin` (`:343`) survives an ignored annotate until the next `prepare` of that key ([run-7](plausible-findings-run-to-toolbar.md#run-7)).

### AnnotationController session (implicit)

Owner: `AnnotationController.swift:8`. Tests: none (needs AppKit).

The annotator window and editor for the image the run opened. It is reused; the run's effects drive it.

**States**: the properties together.

- `current: Screenshot?` `:48`: set in `prepare` (`:163`), nil in `hide` and `abandon` (`:476`, `:462`). `opened: Opening?` `:56`. `opening` `:594` is `current == nil ? nil : opened`.
- `windowUp` `:64` (true after `show`, false at `prepare`), `editorUntouched` `:62`.
- `eventProbe: Timer?` `:51`, `outsideClick` `:49`, `removal` `:53` (`WindowRemoval`), `titleReveal` `:90`, `inkMeasurement` `:86`. The zoom properties belong to the flights area.

Phases, derived:

1. Closed: `current == nil`, window hidden or absent.
2. Prepared: `current != nil`, `windowUp == false`, alpha 0, keys held.
3. Shown: `windowUp == true`, `outsideClick` running, `eventProbe` running until it answers.
4. Hiding: `current == nil` while `fitBeforeHide` is pending (zoomed only).
5. Removing: `removal` pending (`hideWindows`, `:514`); the window is still ordered in.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `prepare` (`:161`) | Prepared | cancels `removal` (`:170`); resets `windowUp`, `editorUntouched`, zoom and title reveal (`.opened` / `.closed`) |
| Prepared | `prepare` with an unreadable image | Prepared | calls `cancel()` (`:206-210`), so `onClosed(.back)` reaches the run as `.cancel`, held until the batch ends |
| Prepared | `show` | Shown | needs `current != nil` (`:354`) |
| Closed | `show` | — (ignored) | — |
| `current != nil` | `cancel(how)` | — | `onClosed(how)` only; hides nothing |
| `current == nil` | `cancel` | — (ignored, `:664`) | — |
| any | `hide(then:)` | Hiding (zoomed) or Removing | `current = nil`, `park()`, `fitBeforeHide`, then `hideWindows` and `then()` |
| `current != nil` | `abandon` | Removing | `zoom.reduce(.close)`, `current = nil`, `park()`, `hideWindows()` |
| `current != nil` and `opened == opening` | `renamed` | — | re-keys `current` |
| Hiding | `renamed` | — (ignored; `opened` keeps the old key, so the flight home loses the title, `takeTitle(of:)` `:487`) ([run-8](plausible-findings-run-to-toolbar.md#run-8)) | — |
| any | `landed` (`:440`) | — | sets the shadow, `revealTitle(.landed)`; not guarded by opening or `current` |

**Invariants**

- `hide` is called once per `prepare` (comment `:468`). Checked by: nothing in the controller; the run emits one `park` or `abandon` per opening.
- The window and editor are reused, and the last image's `removal` must not take them (comment `:168`). Checked by: `removal.cancel()` at `:170`.
- `eventProbe` never answers for an opening that ended. Checked by: the compare at `:393` and `stopProbe()` in `hide` and `abandon`.
- `landed()`, `onClosed`, `onFinished` and `onSend` rely on `current != nil` meaning "the run's current opening". That holds because `hide` clears `current` in the call that begins the park, and the run emits `prepare` only after `parked`. Checked by: nothing.

**Late and concurrent answers**

- The `loaded` decode: dropped unless `self.opening == opening`, `:217`.
- The `eventProbe` answer: compares `opening`, `:393`; gives up after 0.5 s.
- The `revealTitle` 0.5 s wait: compares `opened == opening` and `current != nil`, `:321`.
- The ink `Task`: compares `inkMeasurement` and `current != nil`, `:296`. `measureTitleInk` returns early without bumping it when the next image has no title (`:282`), so a stale answer lands on a `.closed` reveal with no visible effect.
- `offerTyping`: needs `windowUp`, `editorUntouched` and `current != nil`, `:377`.
- `fitBeforeHide`: answers once (`answered`, `:509`) from the tween or its 0.3 s deadline.
- Esc during the zoomed fit-out: dropped by `cancel`'s `current != nil` guard, `:664`.
- `dropped:` closure of a flight: calls `onAnnotatorLanded` with no opening compare (`ThumbnailController.swift:836`); `TitleReveal` ignores a late `landed` once closed.

### TitleReveal (explicit)

Owner: `AgentTitle.swift:106`. Tests: none. Driven by `AnnotationController.revealTitle` (`:316`).

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

- The wait timer compares the opening id: `AnnotationController.swift:321`.
- `inkKnown` for the previous image after `closed`: ignored.

### WindowRemoval (implicit)

Owner: `WindowRemoval.swift:9`. Tests: none.

Takes the annotator window down after the flight home covers the frame. State: `generation`, `link`, `left`, `remove`.

**States**: idle, started (waiting for the next main turn), counting (display link running, `left` refreshes to go).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `start` | started | cancels first; next main turn runs `hide`, installs a display link, runs `remove` after 3 refreshes (`:11-12`, `:40-46`) |
| started or counting | `cancel` | idle | bumps `generation`, kills the link, drops `remove` |

**Invariants**

- A removal cancelled before its main-queue hop runs neither `hide` nor `remove`. Checked by: the `generation` compare at `:22`.

**Late and concurrent answers**

- A display link that never fires (display asleep): `remove` never runs and the editor's image stays held until the next `prepare`. No guard.

### OutsideClick (implicit)

Owner: `OutsideClick.swift:12`. Tests: none.

Reports a click outside the annotator. State: `monitor: Any?`. The annotator starts it in `show` (`AnnotationController.swift:366`) and stops it in `hide` and `abandon`; `start` replaces an earlier monitor. The handler ignores clicks before `watching` (`settling` 0.15 s, `OutsideClick.swift:22`) and checks the window under the cursor first.

### FocusReturn (implicit)

Owner: `FocusReturn.swift:6`. Tests: none.

Remembers where the focus goes back to. State: `previousApp` and a weak `ownWindow`. `sessionStarting` records a titled key window (only if Vignette is active); an app activation clears `ownWindow` and sets `previousApp`; `restore` prefers a visible `ownWindow` and does not clear it, so it persists until another app activates. `CornerKeys` calls it on `.restoreFocus` after `editorClosed(ending)`.
