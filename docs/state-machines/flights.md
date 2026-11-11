# Flights and zoom: flights

A flight is a card (or picture) animated across the screen on a spring, drawn by one shared panel. This area holds the layer that draws flights and takes presses over them, the reducer that decides what a press does, the spring that drives most motion, the annotator's zoom, and the two panels that fade in behind the stack.

All line numbers are in `Sources/`.

### TransitionLayer flights (implicit)

Owner: `TransitionLayer.swift:11`, one instance at `ThumbnailController.swift:46`. Tests: none. Nothing constructs `TransitionLayer`. `MotionTests.testAFlightHandsOverOnlyOnceItIsThere` and `MotionTests.testAFlightCoversItsTargetFromTheMomentItReachesIt` test the timing helpers only.

The layer holds a set of flights. `ThumbnailController` starts, re-aims, lifts and ends them; timers inside the layer report arrival.

**States**: a flight has no state enum. These properties together make it:

- `model.flights: [Flight]` (`:48`). A flight is in the array or not.
- `Flight.generation` (`:33`), taken from `nextGeneration` (`:79`) in `start` (`:325`). Never reused. `converge`'s resting result flight keeps generation 0 (`:269`).
- `Flight.dropped: (() -> Void)?` (`:37`). Set by `start` (`:336`, `:339`), cleared on arrival (`:236`).
- `Flight.path`, `previousPath`, `blend` (`:28-32`): the bow of the path. `start` sets `blend = 0`; the async block of `fly` animates it to 1 (`:216`).
- `Flight.look`, `frame`, `opacity`, `caption`, `leavingAnnotator` (`:13-26`).
- `arrivedFlights: Set<UUID>` (`:73`): the spring settled on its target.
- `pendingLift: Set<UUID>` (`:74`): a lift was asked before arrival.
- `model.swallowRects` (`:49`): each lives until its own `asyncAfter` removes it (`:416-420`) or `endAll` empties the array (`:388`).

Flight states these make: `absent` (not in `model.flights`), `flying` (in it, not in `arrivedFlights`), `flying+liftPending` (`flying` and in `pendingLift`), `arrived` (in `arrivedFlights`, `dropped` is nil).

Events and senders:

- `fly(id:…)` (`:190`): `ThumbnailController.swift:693` (`slideOut`), `:826` (card to annotator), `:905` (`returnCard`), `:939` (`flyAway`), and `converge` (`:299`).
- `converge(…)` (`:259`): `ThumbnailController.swift:565` (stitch).
- `lift(id:)` (`:370`): `ThumbnailController.swift:882` (`.liftFlight`), `:913`.
- `end(id:)` (`:376`): `ThumbnailController.swift:479, 686, 696, 858, 900, 941`, and `:283`, `:294` here.
- `endAll(except:)` (`:381`): `ThumbnailController.swift:1317` (`present`).
- `dropShadow(id:)` (`:363`): `ThumbnailController.swift:876, 911`, and `:288` here.
- `setImage(id:)` (`:355`): `FlightImages.swift:60`.
- `swallowPresses(in:for:on:)` (`:406`): `ThumbnailController.swift:959`.
- Timers: the three `DispatchQueue.main` hops in `fly` (`:208`, `:220`, `:227`) and the swallow rect expiry (`:410`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| absent | `fly` | flying | `start` appends the flight (`:339`) with a new `generation`; `showPanel`; an async hop commits the start, then animates to the target |
| absent | `converge` | resting result flight (opacity 0, generation 0) plus flying pieces | the result id is removed first (`:266`); pieces fly with `arrived: land, dropped: land` |
| flying, arrived | `fly` (same id) | flying (new generation) | new image and marks (old marks cleared if different, `:330`), `path`/`previousPath`, `blend = 0`, `dropped` replaced (may become nil); `arrivedFlights` and `pendingLift` cleared (`:321-322`). The old `covered`, `arrived` and `dropped` are never called |
| any | second `fly` in the same turn as the first | second generation wins | the first hop sees a `generation` mismatch and returns (`:209`) |
| flying | cover timer, `isCurrent` | flying | `covered()` (`:220-223`) |
| flying | arrival timer, `isCurrent` | arrived | frame and look snapped without animation (`:229-234`); inserted in `arrivedFlights`; `dropped = nil`; `arrived()`; then `end` if in `pendingLift` (`:238`) |
| flying | either timer fires and the flight is absent or has another generation | unchanged | ignored (`:221`, `:228`) |
| flying | `lift` | flying+liftPending | `pendingLift.insert` (`:378`) |
| arrived | `lift` | absent | `end` (`:378`) |
| absent | `lift` | absent | ignored (`:377` guard) |
| flying | `end`, `endAll` | absent | marks cleared, flight removed, `orderOutIfIdle`, then `dropped` called (`:395-400`) ([flights-1](plausible-findings-run-to-toolbar.md#flights-1)) |
| arrived | `end`, `endAll` | absent | no `dropped` (`:395` filter) |

**Invariants**

- The panel is up whenever a flight, a swallow rect, `staysUp` or a held press exists (comments `:417-418`, `:437-439`). Checked by: nothing.
- `ignoresMouseEvents` is never set on the panel (comment `:8-9`). Checked by: nothing.
- A flight's `dropped` runs only if the flight did not arrive, and at most once. Checked by: the filter at `:389` and `dropped = nil` at `:236`; no test.
- `arrived` runs once the bouncing spring is within 0.5 pt of its target (`arrivalTolerance`, `:77`; `Anim.settle`), and for the other timings 50 ms after `covered` (`FlightTiming.settles`, `TransitionLayer+Timing.swift:34`). Checked by: `MotionTests.testAFlightHandsOverOnlyOnceItIsThere` (timing helper only).
- `covered` runs before `arrived`, at least 50 ms before for every timing but motion 0 (comment `:219`); `FlightTiming.covers` is `min(settle, passesTarget)` for the bouncing spring, `Anim.settle` for the spring with no bounce, and 50 ms past the duration for a curve (`TransitionLayer+Timing.swift:46`). Checked by: `MotionTests.testAFlightCoversItsTargetFromTheMomentItReachesIt` (timing helpers only).
- No two live flights share a generation. Checked by: `nextGeneration` (`:79`, `:325`); no test.

**Late and concurrent answers**

- A timer for a flight that was re-aimed or removed: ignored by `isCurrent(id, gen)` (`:251`, used at `:221`, `:228`), by the `generation == gen` check in the first hop (`:209`) and by the index lookup (`:228`).
- Two `fly` calls in one turn: the second `start` bumps `generation` (`:325`), so the first hop returns at `:209`.
- A reused id: generations never repeat (comment `:323-326`).
- `covered` and `arrived` due at the same instant (motion 0): `covered` is scheduled first (`:219`) and the deadlines come from two successive `.now()` calls, so the order holds.
- A lift asked before arrival: held in `pendingLift` (`:372`), run at `:238`, cleared on re-aim (`:322`).
- A `dropped` handler that re-enters the layer: `end(where:)` removes first and calls handlers after (`:390-394`); `converge`'s `land` defers a turn (`:281`).
- Dismissing during a converge: dropped pieces still answer `land` (`:300`); the result flight is uncovered only if its generation is still the resting one (`:287-288`, `:292-293`).
- Zero-duration motion: `FlightTiming.covers` and `FlightTiming.settles` return 0 (`TransitionLayer+Timing.swift:47`, `:35`), so both timers run next turn. Every `FlightTiming.animation(0)` is `.linear(duration: 0)` (`TransitionLayer+Timing.swift:27`, and `Anim.spring` at `Anim.swift:24` for a spring).

### TransitionLayer panel and press (implicit)

Owner: `TransitionLayer.swift:11`. Tests: none.

The layer's one panel and the press it is holding. `PressCatcher` (`:468-470`) hands each mouse event to `pressed` (`:97`); `FlightPress` decides where the press goes.

**States**:

- `panel.isVisible` (`:82`). Shown by `showPanel` (`:435`), taken down by `orderOutIfIdle` (`:419`). `orderIn` and `orderBelow` only order other windows relative to it.
- `staysUp` (`:66`), set by `ThumbnailController.swift:756` (`flights.staysUp = run.isActive`).
- `pressDown` (`:62`), `pressedFlight` (`:61`), `releaseWatch` (`:70`), `screen` (`:71`).

**Transitions**

Panel:

| State | Event | Next state | Effects |
|---|---|---|---|
| hidden | `fly`, `converge`, `swallowPresses` | visible | `showPanel` sets the frame to `screen.frame` and calls `orderFrontRegardless` (`:440-443`) |
| visible | `end`, `endAll`, rect expiry, `released`, `staysUp = false` | hidden if `!staysUp && flights.isEmpty && swallowRects.isEmpty && !pressDown` (`:420`) | otherwise stays up |
| visible | `showPanel` for another screen | visible, frame moves to that screen (`:440-442`) | existing flights and swallow rects keep frames local to the earlier screen ([flights-2](plausible-findings-run-to-toolbar.md#flights-2)) |

Press:

| State | Event | Next state | Effects |
|---|---|---|---|
| up | `leftMouseDown` | down | `pressedFlight` is nil if a swallow rect covers the point, else the topmost flight under it (`:102`); `watchRelease` starts; `.pressed` reported (`:105`) |
| down | `leftMouseDragged` | down | `.dragged` reported (`:107`) |
| down | `leftMouseUp` | up | `released`: timer cancelled, `orderOutIfIdle`, `.released` reported (`:115-125`) |
| down | timer: the button reads up on 2 ticks (`:149-150`) | up | logs `[flight] release missed`, calls `released` |
| up | `leftMouseUp` | up | ignored by `guard pressDown` (`:116`) |
| up | extra `leftMouseDragged` | up | still reported with `pressedFlight` nil (`:107`); `FlightPress` ignores it in `idle` (`FlightPress.swift:61`) |
| down | `leftMouseDown` | down | state overwritten, old watch invalidated (`:144`); nothing is done for the lost first press |

**Invariants**

- A swallow rect always clears: expiry is an unconditional `asyncAfter` (`:410`) and `endAll` empties them (`:382`). Checked by: nothing.
- The panel stays up while a press is down, even after its swallow rect expired. Checked by: the `!pressDown` term at `:420`.

**Late and concurrent answers**

- A release that never arrives: `watchRelease` (`:143`) ends the press from the button's own state; the real release, if it comes late, is ignored (`:116`).
- A release after the flight is gone: `fraction(of:on:)` returns nil (`:174`); `FlightPress` takes events with `picture` nil (`:130`).

### FlightPress (explicit)

Owner: `FlightPress.swift:10`, instance `flightPress` at `ThumbnailController.swift:84`. Tests: `FlightPressTests.testAPressBeforeTheEditorCanTakeItIsHeldThenHandedOverInOrder`, `testAPressOnceTheEditorCanTakeItGoesAtOnce`, `testAPressReleasedDuringTheFlightIsHandedOverWhole`, `testAPressOnAnyOtherFlightIsSwallowedToItsRelease`, `testAPressBesideThePictureIsSwallowed`, `testAPressHeldForAnImageThatTurnsBackGoesNowhere`, `testAPressHandedOverStopsWhenTheImageLeavesTheEditor`, `testAnAnswerForAnotherImageHandsNothingOver`, `testAPointOnTheFlightIsItsPlaceOnThePicture`.

A pure reducer. It decides whether a press on a flight is held until the editor can take it, handed to the editor, or swallowed.

**States** (`State`, `:29`): `idle`; `holding(key:events:)`; `handing(key:)`; `swallowing`.

Events and senders: `press(_:into:ready:)` (`:49`; `ThumbnailController.swift:411`), `move(_:)` (`:59`; `:414`), `ready(_:)` (`:80`; `:880` on `.handOverPresses`), `rename(from:to:)` (`:87`; `:506`), `ended(_:)` (`:97`; `:751`).

**Transitions** (k is the key, ev the held events)

| State | `press` | `move` | `ready(k)` | `ended(k)` | `rename` |
|---|---|---|---|---|---|
| `idle` | no key or no picture: `swallowing`. `ready`: `handing`, returns the event. Else `holding`, returns [] | returns [] (`:62`) | — | — | — |
| `holding(k, ev)` | state replaced by the new press; the old press's events are lost | appends; on `.released` stays `holding` | k matches: `idle` if the last event is `released`, else `handing`; returns all events. Other key: [] | k matches: `idle` if the last event is `released`, else `swallowing` | key replaced |
| `handing(k)` | replaced | returns the event with `picture` nil; `released` goes to `idle` | no change, [] | k matches: `swallowing` | key replaced |
| `swallowing` | replaced | returns []; `released` goes to `idle` | [] | — | — |

**Invariants**

- A press held for a key is handed over in order and once. Checked by: `FlightPressTests.testAPressBeforeTheEditorCanTakeItIsHeldThenHandedOverInOrder`, `testAPressReleasedDuringTheFlightIsHandedOverWhole`.
- A press on any other flight is swallowed to its release. Checked by: `testAPressOnAnyOtherFlightIsSwallowedToItsRelease`, `testAPressBesideThePictureIsSwallowed`.
- A held or handed press stops when its image leaves. Checked by: `testAPressHeldForAnImageThatTurnsBackGoesNowhere`, `testAPressHandedOverStopsWhenTheImageLeavesTheEditor`, `testAnAnswerForAnotherImageHandsNothingOver`.
- `rename` carries the key to the new file name (`docs/rules/capture.md`). Checked by: nothing; no test calls `rename`.

**Late and concurrent answers**

- A second `ready`: hands nothing over (pattern match at `:81`).
- An `ended` for a key not held: ignored (`:103`).
- A flight removed while its press is held: the reducer is told only by `ThumbnailController.send`, which ends the press when `keyInEditor` stops matching after any event (`ThumbnailController.swift:750-752`). Later events carry `picture` nil (`TransitionLayer.swift:127`, `:171`).

### Tween (implicit)

Owner: `Tween.swift:9`. Tests: `MotionTests.testSpringStepNeverPassesItsTargetHoweverLateTheTickIs`, `MotionTests.testSpringTweenSettlesWithoutOvershootAndReversesFromWhereItIs`. Nothing runs a `Tween` against a run loop.

A critically damped spring on one number. Users in this area: `zoomTween` (`AnnotationController.swift:84`) and `BackdropPanel.alpha`/`slide` (`BackdropPanel.swift:18-20`). Other users: the toolbar's `slideX`/`slideY`, `HangingPopover`, `fade` (`AnnotationController.swift:801`), `EditorView.swift:492`, `LiveNoteContent.swift:43`.

**States**: `spring: (target, omega, lastTick)?` (`:14`), `link`/`timer` (`:11-12`), `velocity` (`:15`), `completion` (`:17`), `value` (`:10`). Idle: `spring == nil` and no link. Ticking: `spring != nil` with a link or timer.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `animate(to:duration:completion:)` with `duration <= 0` or `target == value` | idle | `completion` stored (`:47`); `set(target)` stops ticking and applies; the new completion is called directly (`:48`). The stored copy is not cleared |
| idle | `animate`, positive duration, new target | ticking | spring started; display link on `NSScreen.main`, or a 1/60 timer |
| ticking | `animate` | ticking | `completion` replaced (`:47`); the old one is dropped without being called ([flights-3](plausible-findings-run-to-toolbar.md#flights-3)); link and `lastTick` kept (`:53`) |
| ticking | tick settles (`abs(value - target) < 0.001 && abs(velocity) < 0.01`) | idle | value snapped, `apply`, `completion` taken and called once (`:86-90`) |
| ticking | `set(x)` | idle | no completion call; `completion` not cleared ([flights-3](plausible-findings-run-to-toolbar.md#flights-3)) |
| ticking | `stop()` | idle | no `apply`; `completion = nil` (`:67-71`) |

**Invariants**

- A late tick lands where the spring really is. Checked by: `MotionTests.testSpringStepNeverPassesItsTargetHoweverLateTheTickIs`.
- A reversal keeps velocity. Checked by: `MotionTests.testSpringTweenSettlesWithoutOvershootAndReversesFromWhereItIs`.
- A completion does not run exactly once per `animate`: it is dropped on retarget, `set` and `stop`. Callers that need exactly-once add their own guard (`fitBeforeHide`). ([flights-3](plausible-findings-run-to-toolbar.md#flights-3))

**Late and concurrent answers**

- `animate` called from inside a completion: works, because `spring` and `completion` are nil before the call (`:87-89`).
- A tick after `stop`: cannot run, the link is invalidated (`:39-42`).
