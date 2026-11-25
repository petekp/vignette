# Flights and zoom: flights

A flight is a card (or picture) animated across the screen on a spring, drawn by one shared panel. This area holds the layer that draws flights and takes presses over them, the reducer that decides what a press does, the spring that drives most motion, the annotator's zoom, and the two panels that fade in behind the stack.

All files are in `Sources/`.

### TransitionLayer flights (implicit)

Owner: `TransitionLayer.swift`, one instance at `ThumbnailController.swift`. Tests: none. Nothing constructs `TransitionLayer`. `MotionTests.testAFlightHandsOverOnlyOnceItIsThere` and `MotionTests.testAFlightCoversItsTargetFromTheMomentItReachesIt` test the timing helpers only.

The layer holds a set of flights. `ThumbnailController` starts, re-aims, lifts and ends them; timers inside the layer report arrival.

**States**: a flight has no state enum. These properties together make it:

- `model.flights: [Flight]`. A flight is in the array or not.
- `Flight.generation`, taken from `nextGeneration` in `start`. Never reused. `converge`'s resting result flight keeps generation 0.
- `Flight.dropped: (() -> Void)?`. Set by `start`, cleared on arrival.
- `Flight.path`, `previousPath`, `blend`: the bow of the path. `start` sets `blend = 0`; the async block of `fly` animates it to 1.
- `Flight.look`, `frame`, `opacity`, `caption`, `leavingAnnotator`.
- `arrivedFlights: Set<UUID>`: the spring settled on its target.
- `pendingLift: Set<UUID>`: a lift was asked before arrival.
- `model.swallowRects`: each lives until its own `asyncAfter` removes it or `endAll` empties the array.

Flight states these make: `absent` (not in `model.flights`), `flying` (in it, not in `arrivedFlights`), `flying+liftPending` (`flying` and in `pendingLift`), `arrived` (in `arrivedFlights`, `dropped` is nil).

Events and senders:

- `fly(id:…)`: `ThumbnailController.swift` (`slideOut`) (card to annotator) (`returnCard`) (`flyAway`), and `converge`.
- `converge(…)`: `ThumbnailController.swift` (stitch).
- `lift(id:)`: `ThumbnailController.swift` (`.liftFlight`).
- `end(id:)`: `ThumbnailController.swift`, and here.
- `endAll(except:)`: `ThumbnailController.swift` (`present`).
- `dropShadow(id:)`: `ThumbnailController.swift`, and here.
- `setImage(id:)`: `FlightImages.swift`.
- `swallowPresses(in:for:on:)`: `ThumbnailController.swift`.
- Timers: the three `DispatchQueue.main` hops in `fly` and the swallow rect expiry.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| absent | `fly` | flying | `start` appends the flight with a new `generation`; `showPanel`; an async hop commits the start, then animates to the target |
| absent | `converge` | resting result flight (opacity 0, generation 0) plus flying pieces | the result id is removed first; pieces fly with `arrived: land, dropped: land` |
| flying, arrived | `fly` (same id) | flying (new generation) | new image and marks (old marks cleared if different), `path`/`previousPath`, `blend = 0`, `dropped` replaced (may become nil); `arrivedFlights` and `pendingLift` cleared. The old `covered`, `arrived` and `dropped` are never called |
| any | second `fly` in the same turn as the first | second generation wins | the first hop sees a `generation` mismatch and returns |
| flying | cover timer, `isCurrent` | flying | `covered()` |
| flying | arrival timer, `isCurrent` | arrived | frame and look snapped without animation; inserted in `arrivedFlights`; `dropped = nil`; `arrived()`; then `end` if in `pendingLift` |
| flying | either timer fires and the flight is absent or has another generation | unchanged | ignored |
| flying | `lift` | flying+liftPending | `pendingLift.insert` |
| arrived | `lift` | absent | `end` |
| absent | `lift` | absent | ignored (guard) |
| flying | `end`, `endAll` | absent | marks cleared, flight removed, `orderOutIfIdle`, then `dropped` called ([flights-1](plausible-findings-run-to-toolbar.md#flights-1)) |
| arrived | `end`, `endAll` | absent | no `dropped` (filter) |

**Invariants**

- The panel is up whenever a flight, a swallow rect, `staysUp` or a held press exists (comments). Checked by: nothing.
- `ignoresMouseEvents` is never set on the panel (a code comment says so). Checked by: nothing.
- A flight's `dropped` runs only if the flight did not arrive, and at most once. Checked by: the filter and `dropped = nil`; no test.
- `arrived` runs once the bouncing spring is within 0.5 pt of its target (`arrivalTolerance`; `Anim.settle`), and for the other timings 50 ms after `covered` (`FlightTiming.settles`, `TransitionLayer+Timing.swift`). Checked by: `MotionTests.testAFlightHandsOverOnlyOnceItIsThere` (timing helper only).
- `covered` runs before `arrived`, at least 50 ms before for every timing but motion 0 (a code comment says so); `FlightTiming.covers` is `min(settle, passesTarget)` for the bouncing spring, `Anim.settle` for the spring with no bounce, and 50 ms past the duration for a curve (`TransitionLayer+Timing.swift`). Checked by: `MotionTests.testAFlightCoversItsTargetFromTheMomentItReachesIt` (timing helpers only).
- No two live flights share a generation. Checked by: `nextGeneration`; no test.

**Late and concurrent answers**

- A timer for a flight that was re-aimed or removed: ignored by `isCurrent(id, gen)` (used), by the `generation == gen` check in the first hop and by the index lookup.
- Two `fly` calls in one turn: the second `start` bumps `generation`, so the first hop returns.
- A reused id: generations never repeat (a code comment says so).
- `covered` and `arrived` due at the same instant (motion 0): `covered` is scheduled first and the deadlines come from two successive `.now()` calls, so the order holds.
- A lift asked before arrival: held in `pendingLift`, run, cleared on re-aim.
- A `dropped` handler that re-enters the layer: `end(where:)` removes first and calls handlers after; `converge`'s `land` defers a turn.
- Dismissing during a converge: dropped pieces still answer `land`; the result flight is uncovered only if its generation is still the resting one.
- Zero-duration motion: `FlightTiming.covers` and `FlightTiming.settles` return 0 (`TransitionLayer+Timing.swift`), so both timers run next turn. Every `FlightTiming.animation(0)` is `.linear(duration: 0)` (`TransitionLayer+Timing.swift`, and `Anim.spring` at `Anim.swift` for a spring).

### TransitionLayer panel and press (implicit)

Owner: `TransitionLayer.swift`. Tests: none.

The layer's one panel and the press it is holding. `PressCatcher` hands each mouse event to `pressed`; `FlightPress` decides where the press goes.

**States**:

- `panel.isVisible`. Shown by `showPanel`, taken down by `orderOutIfIdle`. `orderIn` and `orderBelow` only order other windows relative to it.
- `staysUp`, set by `ThumbnailController.swift` (`flights.staysUp = run.isActive`).
- `pressDown`, `pressedFlight`, `releaseWatch`, `screen`.

**Transitions**

Panel:

| State | Event | Next state | Effects |
|---|---|---|---|
| hidden | `fly`, `converge`, `swallowPresses` | visible | `showPanel` sets the frame to `screen.frame` and calls `orderFrontRegardless` |
| visible | `end`, `endAll`, rect expiry, `released`, `staysUp = false` | hidden if `!staysUp && flights.isEmpty && swallowRects.isEmpty && !pressDown` | otherwise stays up |
| visible | `showPanel` for another screen | visible, frame moves to that screen | existing flights and swallow rects keep frames local to the earlier screen ([flights-2](plausible-findings-run-to-toolbar.md#flights-2)) |

Press:

| State | Event | Next state | Effects |
|---|---|---|---|
| up | `leftMouseDown` | down | `pressedFlight` is nil if a swallow rect covers the point, else the topmost flight under it; `watchRelease` starts; `.pressed` reported |
| down | `leftMouseDragged` | down | `.dragged` reported |
| down | `leftMouseUp` | up | `released`: timer cancelled, `orderOutIfIdle`, `.released` reported |
| down | timer: the button reads up on 2 ticks | up | logs `[flight] release missed`, calls `released` |
| up | `leftMouseUp` | up | ignored by `guard pressDown` |
| up | extra `leftMouseDragged` | up | still reported with `pressedFlight` nil; `FlightPress` ignores it in `idle` (`FlightPress.swift`) |
| down | `leftMouseDown` | down | state overwritten, old watch invalidated; nothing is done for the lost first press |

**Invariants**

- A swallow rect always clears: expiry is an unconditional `asyncAfter` and `endAll` empties them. Checked by: nothing.
- The panel stays up while a press is down, even after its swallow rect expired. Checked by: the `!pressDown` term.

**Late and concurrent answers**

- A release that never arrives: `watchRelease` ends the press from the button's own state; the real release, if it comes late, is ignored.
- A release after the flight is gone: `fraction(of:on:)` returns nil; `FlightPress` takes events with `picture` nil.

### FlightPress (explicit)

Owner: `FlightPress.swift`, instance `flightPress` at `ThumbnailController.swift`. Tests: `FlightPressTests.testAPressBeforeTheEditorCanTakeItIsHeldThenHandedOverInOrder`, `testAPressOnceTheEditorCanTakeItGoesAtOnce`, `testAPressReleasedDuringTheFlightIsHandedOverWhole`, `testAPressOnAnyOtherFlightIsSwallowedToItsRelease`, `testAPressBesideThePictureIsSwallowed`, `testAPressHeldForAnImageThatTurnsBackGoesNowhere`, `testAPressHandedOverStopsWhenTheImageLeavesTheEditor`, `testAnAnswerForAnotherImageHandsNothingOver`, `testAPointOnTheFlightIsItsPlaceOnThePicture`.

A pure reducer. It decides whether a press on a flight is held until the editor can take it, handed to the editor, or swallowed.

**States** (`State`): `idle`; `holding(key:events:)`; `handing(key:)`; `swallowing`.

Events and senders: `press(_:into:ready:)` (`ThumbnailController.swift`), `move(_:)`, `ready(_:)` (on `.handOverPresses`), `rename(from:to:)`, `ended(_:)`.

**Transitions** (k is the key, ev the held events)

| State | `press` | `move` | `ready(k)` | `ended(k)` | `rename` |
|---|---|---|---|---|---|
| `idle` | no key or no picture: `swallowing`. `ready`: `handing`, returns the event. Else `holding`, returns [] | returns [] | — | — | — |
| `holding(k, ev)` | state replaced by the new press; the old press's events are lost | appends; on `.released` stays `holding` | k matches: `idle` if the last event is `released`, else `handing`; returns all events. Other key: [] | k matches: `idle` if the last event is `released`, else `swallowing` | key replaced |
| `handing(k)` | replaced | returns the event with `picture` nil; `released` goes to `idle` | no change, [] | k matches: `swallowing` | key replaced |
| `swallowing` | replaced | returns []; `released` goes to `idle` | [] | — | — |

**Invariants**

- A press held for a key is handed over in order and once. Checked by: `FlightPressTests.testAPressBeforeTheEditorCanTakeItIsHeldThenHandedOverInOrder`, `testAPressReleasedDuringTheFlightIsHandedOverWhole`.
- A press on any other flight is swallowed to its release. Checked by: `testAPressOnAnyOtherFlightIsSwallowedToItsRelease`, `testAPressBesideThePictureIsSwallowed`.
- A held or handed press stops when its image leaves. Checked by: `testAPressHeldForAnImageThatTurnsBackGoesNowhere`, `testAPressHandedOverStopsWhenTheImageLeavesTheEditor`, `testAnAnswerForAnotherImageHandsNothingOver`.
- `rename` carries the key to the new file name (`docs/rules/capture.md`). Checked by: nothing; no test calls `rename`.

**Late and concurrent answers**

- A second `ready`: hands nothing over (pattern match).
- An `ended` for a key not held: ignored.
- A flight removed while its press is held: the reducer is told only by `ThumbnailController.send`, which ends the press when `keyInEditor` stops matching after any event (`ThumbnailController.swift`). Later events carry `picture` nil (`TransitionLayer.swift`).

### Tween (implicit)

Owner: `Tween.swift`. Tests: `MotionTests.testSpringStepNeverPassesItsTargetHoweverLateTheTickIs`, `MotionTests.testSpringTweenSettlesWithoutOvershootAndReversesFromWhereItIs`. Nothing runs a `Tween` against a run loop.

A critically damped spring on one number. Users in this area: `zoomTween` (`AnnotationController.swift`) and `BackdropPanel.alpha`/`slide` (`BackdropPanel.swift`). Other users: the toolbar's `slideX`/`slideY`, `HangingPopover`, `fade` (`AnnotationController.swift`), `EditorView.swift`, `LiveNoteContent.swift`.

**States**: `spring: (target, omega, lastTick)?`, `link`/`timer`, `velocity`, `completion`, `value`. Idle: `spring == nil` and no link. Ticking: `spring != nil` with a link or timer.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `animate(to:duration:completion:)` with `duration <= 0` or `target == value` | idle | `completion` stored; `set(target)` stops ticking and applies; the new completion is called directly. The stored copy is not cleared |
| idle | `animate`, positive duration, new target | ticking | spring started; display link on `NSScreen.main`, or a 1/60 timer |
| ticking | `animate` | ticking | `completion` replaced; the old one is dropped without being called ([flights-3](plausible-findings-run-to-toolbar.md#flights-3)); link and `lastTick` kept |
| ticking | tick settles (`abs(value - target) < 0.001 && abs(velocity) < 0.01`) | idle | value snapped, `apply`, `completion` taken and called once |
| ticking | `set(x)` | idle | no completion call; `completion` not cleared ([flights-3](plausible-findings-run-to-toolbar.md#flights-3)) |
| ticking | `stop()` | idle | no `apply`; `completion = nil` |

**Invariants**

- A late tick lands where the spring really is. Checked by: `MotionTests.testSpringStepNeverPassesItsTargetHoweverLateTheTickIs`.
- A reversal keeps velocity. Checked by: `MotionTests.testSpringTweenSettlesWithoutOvershootAndReversesFromWhereItIs`.
- A completion does not run exactly once per `animate`: it is dropped on retarget, `set` and `stop`. Callers that need exactly-once add their own guard (`fitBeforeHide`). ([flights-3](plausible-findings-run-to-toolbar.md#flights-3))

**Late and concurrent answers**

- `animate` called from inside a completion: works, because `spring` and `completion` are nil before the call.
- A tick after `stop`: cannot run, the link is invalidated.
