# Flights and zoom: zoom and panels

This file continues [Flights and zoom: flights](flights.md), which has the area's introduction and terms.

### AnnotatorZoom (explicit)

Owner: `AnnotatorZoom.swift`, held as `zoom` in `AnnotationController` and run by `AnnotationController+Zoom.swift` (`run`). Tests: `AnnotatorZoomTests` (the reducer, plus a 1000-seed random run through a spring that ticks, turns and arrives), `ZoomTests` (geometry).

A pure reducer for the annotator's zoom. It decides what each zoom input does and which spring to run; the controller turns events into inputs and runs the spring on a `Tween`.

**States** (`Phase`, in `AnnotatorZoom+Types.swift`): `closed` (initial only), `flying`, `landed`, `closing`. Other fields: `level`, `target`, `aim`, `pan`, `camera`, `center`, `frame`, `fitted`, `room`, and for a re-fit `placed` (what the last effect drew), `waitingFit`, `flightLifted`, `refitFrom` and `refitProgress`.

Events (`Input`, in `AnnotatorZoom+Types.swift`) and senders:

- `prepare(fitted:room:)`: `AnnotationController.swift`.
- `landed`: `AnnotationController.swift`, called from `ThumbnailController.swift` (flight `dropped`) and (`.landed` effect) through `AppDelegate.swift`.
- `zoomIn`, `zoomOut`, `fit`, `smart`: `zoomRequested` (`AnnotationController+Zoom.swift`) from `editor.onZoom` (`AnnotationController.swift`).
- `pinch`, `smart`, `wheel`, `lift`, `pan`: `zoomGesture` (`AnnotationController+Zoom.swift`) from `editor.onZoomGesture`.
- `reveal`: `AnnotationController.swift`.
- `tick`: the `zoomTween` apply.
- `arrived`: the `animate` completion (`AnnotationController+Zoom.swift`).
- `close`: `fitBeforeHide` and `abandon`.
- `refit(fitted:room:bar:)`: `AnnotationController.refit`, from `ThumbnailController.screensChanged` on `didChangeScreenParametersNotification` (`AppDelegate`).
- `refitTick`: the `refitTween` apply.
- `lifted`: `AnnotationController.lifted`, from `ThumbnailController`'s `.liftFlight` effect and a dropped flight.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `prepare` | `flying` | reset except `edge` and `pixelScale`; `level = 1`, `frame = fitted` |
| any | `tick(level)` | same | `place(frame, picture)`; no phase check |
| any | `close` | `closing` | `spring(to: 1)` if `level` or `target` is off 1, else nil. `closed` becomes `closing` too. Nothing ever sets `closed` again ([flights-4](plausible-findings-run-to-toolbar.md#flights-4)) |
| `flying` | `landed` | `landed` | |
| `landed`, `closing`, `closed` | `landed` | — | acts only in `flying` |
| `flying`, `closing`, `closed` | any zoom, pan, reveal, lift or arrived input | — | refused: nil (guard) |
| `landed` | `zoomIn`, `zoomOut`, `fit`, `smart`, `pinch`, `wheel` | `landed` | `.spring` effect; `target` moved; `aim` and `pan` aimed |
| `landed` | `lift`, `arrived` | `landed` | if `target < 1`, spring back to 1 (the hand let go); else — |
| `landed` | `pan`, `reveal` | `landed` | `.movePicture` or nil; `.place` during a re-fit |
| `flying`, or `landed` before `lifted` | `refit` | same | kept in `waitingFit`; nil |
| `flying` | `landed` | `landed` | the kept re-fit, as below, if `lifted` came first |
| any | `lifted` | same | `flightLifted = true`; in `landed`, the kept re-fit, as below |
| `landed` | `refit` | `landed` | nil if the fit, room and bar are unchanged; else `fitted`, `room` and `bar` taken, `level = target` scaled to keep `level * fitted.width` (1 at or below the fit, capped), aimed at rest, `refitFrom = placed`, `.refit(seconds:)` |
| `closing`, `closed` | `refit` | — | nil |
| any | `refitTick(t)` | same | while `refitFrom` is set: `.place`, `t` of the way from `refitFrom` to the rules' placement; `refitFrom` cleared at 1 |
| `landed` | `close` during a re-fit | `closing` | `waitingFit` cleared; `refitFrom` kept, so its ticks still blend beside the fit's spring, if any |

**Invariants**

- Nothing zooms before landing. Checked by: `AnnotatorZoomTests.testNothingZoomsBeforeTheFlightLands`.
- Nothing zooms once closing, and the close springs to 1. Checked by: `testTheCardLeavesFromTheFittedFrameAndNothingZoomsOnTheWay` and the random test's `check`.
- Keys and wheel notches stop at the fit; only a hand goes below it, down to `minLevel`. Checked by: `testAKeyOrAMouseWheelsNotchStopsAtTheFit`, `testOnlyAHandPullsBelowTheFitAndNoFurtherThanHalfOfIt`.
- A pull springs back on `lift`, and on `arrived` for a hand that stopped without lifting. Checked by: `testAPullSpringsBackWhenTheFingersLift`, `testAPullSpringsBackWhenTheSpringCatchesUpWithAHandThatStopped`.
- The frame stays in the room and on the pixel grid, the picture covers the frame, and `window * camera == level`. Checked by: `testRandomSequencesKeepTheRules`.
- `prepare` resets level, frame and center, and keeps `edge`. Checked by: `testTheNextImageOpensAtItsFitWithTheSameEdgePull`.
- `closed` is re-entered after a close. Checked by: nothing; it is not ([flights-4](plausible-findings-run-to-toolbar.md#flights-4)).
- `zoom.phase` agrees with the run's phase. Checked by: nothing.
- A re-fit starts from what is drawn, keeps the picture's size, ends inside the new room with the bar above the Dock, keeps the picture covering the frame and the bar under it on the way, and caps the level at the new room's cap. Checked by: `testARoomThatShrinksAndGrowsMidZoomKeepsTheMagnificationAndTheFrameInside`, `testARoomThatShrinksUnderAZoomAtTheCapTakesTheNewCap`.
- An image at the fit stays at the fit. Checked by: `testAnImageAtTheFitStaysAtTheFit`.
- A re-fit waits for the landing and the flight's image to go, in either order, and is dropped by a close. Checked by: `testARoomThatChangesBeforeTheFlightsImageHasGoneWaitsForIt`.
- A close mid-re-fit starts from the frame on screen and ends on the new fitted frame. Checked by: `testACloseDuringARefitLetsItLandOnTheNewFittedFrameWithoutAJump`.

**Late and concurrent answers**

- Zoom input before `landed`: refused by the `phase == .landed` guard.
- Zoom input after `close`: refused by the same guard. A pinch whose `lift` was lost is recovered by `.arrived`, which re-fits any `target < 1`. A hand that releases Cmd mid-scroll sends `.pan` instead of `.lift` (`AnnotationController+Zoom.swift`) and is recovered the same way.
- `landed` after `close`: ignored.
- Re-entrancy: `run` finishes `zoom.reduce` before acting on the effect (`AnnotationController+Zoom.swift`), so `moveFrame` calling back into the editor (`onReveal`) cannot overlap a mutation of `zoom`.
- Motion 0: `zoomTween.animate` with duration 0 calls `set` and the completion at once, so `.arrived` is sent inside `animate` and can issue a nested `animate` (the spring-back). It ends because the nested one targets 1.

### Zoom glue: `fitBeforeHide` and `hideWindows` (implicit)

Owner: `AnnotationController.swift` (`fitBeforeHide`) and (`hideWindows`); also `hide(then:)`, `abandon()`, `prepare`. Tests: none.

Brings the zoom back to the fitted size before the annotator's window comes down, so the card flies home from the fitted frame. The run's `.park` drives it.

**States**: `zoomTween` ticking or not; the local `answered` flag; `zoom.phase`; `removal` (`WindowRemoval.generation`, `link`; `WindowRemoval.swift`); `window`; `current`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| open | `hide(then:)` | closing | `current = nil`, `park()`, `fitBeforeHide`: `zoom.reduce(.close)` |
| closing | `.close` gave no spring and no re-fit is on its way, or no window | closed | `done()` now |
| closing | a re-fit on its way | waiting | `refitTween.animate(to: 1, …)`, beside the fit's spring if any; `done` once each has arrived |
| closing | `.close` gave a spring | waiting | `zoomTween.animate(… completion: once)`, plus a deadline `asyncAfter(motionScaled(seconds) + 0.3)` that calls `once` |
| waiting | spring arrives or deadline fires, first of the two | closed | `once` runs `done` once: `hideWindows()`, then the caller's completion (the run's `.parked`) |
| waiting | the other of the two | closed | `answered` stops a second `done` |
| closed | `hideWindows` | — | `zoomTween.stop()`, `refitTween.stop()`, `toolbar.hideSoon()`, `shadowOpacity = 0`, `removal.start(…)` (hide the frame view on the next main turn, `orderOut` after 3 display refreshes) |
| any | `prepare` | open | `removal.cancel()`, `zoom` gets `.prepare`, `zoomTween.set(1)` |

**Invariants**

- `hide` is called once per `prepare`, by the reducer (a code comment says so). Checked by: nothing.
- The deadline covers a spring that never arrives (a code comment says so). Checked by: nothing.

**Late and concurrent answers**

- A spring that never ticks (dead display link): the deadline calls `once`, then `hideWindows` stops the tween.
- Reduce Motion or motion 0: `animate` answers inside the call.
- A removal's late `hide` or `remove` after a new `prepare`: dropped by the `generation` compare (`WindowRemoval.swift`); `cancel`.
- Another writer to `zoomTween` during a close would drop `once`, and the window would wait for the deadline ([flights-3](plausible-findings-run-to-toolbar.md#flights-3)).

### DimPanel (implicit)

Owner: `DimPanel.swift`. Used by `ThumbnailController.swift` (`dim.show`, at `.prepare`) and (`dim.hide`, at `.endRun`). Tests: none. The written contract is `docs/scrim-fade-2026-10-31.md`.

The scrim behind the annotator. It fades in and out on a spring.

**States**: `isVisible`, `generation`, `fadeCount`, `spring`, and the layer opacity animation under the key `"fade"`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| hidden | `show` | fading in | `generation += 1`, `orderFront`, `fade(to: 1, fromNothing: true)` |
| fading in, shown | `show` | fading in | restarts from the spring's current value; settings re-applied |
| fading in, shown | `hide` | fading out | at the end, `orderOut` only if `generation == gen` |
| fading out | `show` | fading in | `generation` bumped, so the hide's `orderOut` is dropped; the fade turns around from where it is |
| fading out | `hide` | fading out | the second hide replaces the animation; the first completion runs and fails the generation compare |
| hidden | `hide` | hidden | `fade` finds value 0 and does not animate; completion runs at once; `orderOut` of an off-screen panel |

**Invariants**

- The scrim is never fully opaque (`alphaValue = 0.995`). Checked by: nothing.
- A hide never orders out a panel that a later `show` raised. Checked by: the `generation` compare.

**Late and concurrent answers**

- A superseded fade's `CATransaction` completion runs when its animation is removed. It writes the final alpha only if `fadeCount == thisFade` and orders out only if `generation` matches.

### BackdropPanel (implicit)

Owner: `BackdropPanel.swift`. Driven by `CornerKeys.swift` (`show`) and (`hide`). Tests: none.

The blurred backdrop behind the stack. It fades with one `Tween` and slides with another.

**States**: `alpha` Tween, `slide` Tween, `isVisible`, `strip`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| hidden | `show` | visible | `slide.set(0)`, `orderFront`, alpha tween to 1, slide tween to 1 |
| visible | `show` | visible | tweens retarget; the pending hide's completion is replaced, so the hide cannot `orderOut` (`Tween.animate`) ([flights-3](plausible-findings-run-to-toolbar.md#flights-3)) |
| visible | `hide` | hiding | tweens to 0; alpha's completion orders out if `alphaValue == 0` |
| hidden | `hide` | hidden | `animate` with `target == value` runs `set` and the completion at once (`orderOut` again) |

**Invariants**

- A later `show` cancels an earlier `hide`'s `orderOut`. It relies on `Tween` replacing the completion on retarget. Checked by: nothing. ([flights-3](plausible-findings-run-to-toolbar.md#flights-3))

**Late and concurrent answers**

- The slide may still be moving after `orderOut`: the next `show` resets it with `slide.set(0)` only when `!isVisible`.
