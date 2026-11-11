# Flights and presses

- A flight does not run down a straight line. `FlightCurve` bows it to one side and swells the card,
  both peaking in the middle and nothing at the ends, so the card still leaves and lands exactly
  where the layout puts it, `4t(1 - t)`. The amounts are `ui.flightArc` (a fraction of the path's length),
  `ui.flightArcMax` (the bow's cap in points), and `ui.flightDepth`; the motion scale multiplies the
  first and the third, so `motion: 0` and Reduce Motion give a straight line. The side of the bow
  belongs to the line rather than the direction of travel, so a flight that turns around mid-air
  keeps bowing the same way; `TransitionLayer`'s `Bow` blends between a flight's old and new paths,
  so a flight re-aimed in mid-air crosses from one bow to the other instead of stepping sideways.
  A flight also carries a `Look` (corner, shadow opacity, radius, y, the ring's inset, and whether
  the picture fills the frame as a card's does or spans its width as the editor's does) animated
  from `.annotator(ui)` to `.card(ui)`; `AnnotationController` reads the annotator window's frame
  shadow from the same `Look.annotator`, so the two ends cannot drift apart. The fitted frame is
  on whole points with the image's shape (`StackLayout.annotationFrame`), and the editor spans its
  width with the picture pinned to the top, so the picture the flight centres there is less than
  half a point taller or shorter than the frame, and moves under a quarter of a point as the editor
  takes over. `dropShadow(id:)` zeroes a flight's shadow
  in the same run-loop turn the card appears or the annotator turns its own shadow on, so the
  shadow is never drawn twice and never missing for a frame.
- Nothing takes a flight's place until it has arrived; the annotator hides behind it before then. A
  spring's tail runs well past its nominal duration, so anything put at the exact target on a timer
  steps by what the spring still had to go. Every flight moves by `ui.flightTiming` (`FlightTiming`),
  and each choice is a SwiftUI spring, so a flight re-aimed in mid-air keeps its velocity. The
  default, `quickSpring`, has a bounce of 0.07 over 0.65 of `ui.expandDuration`, tuned to first
  reach its target when `spring` does (0.27 s at the default 0.35 s). It passes the target by 0.04%
  of the path, under half a point across a laptop's screen. `spring` has `Anim.flightBounce` over
  the whole duration and passes by 0.6%, about 7 points that shrink back over its last 0.2 s.
  `springNoBounce` never passes it and covers it only at 0.57 s. `fly` answers on `arrived` once
  the flight is within half a point of the target (`Anim.settle`), and no sooner than 50 ms, three
  refreshes at 60 Hz, after it covers the target, with the flight put exactly on it in that turn:
  the card retakes its slot, and the annotator takes the shadow back
  (`AnnotationController.landed`). The flight into the editor lifts at the last of three moments,
  which reach `AnnotationRun` as events for the opening and come back as `liftFlight`: `arrived`,
  which `lift(id:)` waits for itself; the editor's `loaded`; and its window taking presses
  (`takesPresses`). The wait for `loaded` matters at motion 0, where the
  flight can arrive before the image, and lifting it then would show an empty editor;
  `docs/native-editor-2026-09-23.md` has the timings. The wait for presses keeps the flight over the
  window until the window takes presses itself, so a press there never falls through to the app
  behind. `fly` answers a second time, earlier, when the flight covers its target: at
  `Anim.passesTarget`, or once it is within half a point of it if that comes first, as it does for
  the spring with no bounce and for most flights on the quick spring (0.26 s on a 1,210 pt path). The landing comes at least three refreshes later, which the flight
  home needs to put the stack's panel on screen first (`docs/exit-panel-2026-11-01.md`). From the
  moment a bouncing spring first reaches its target the flight's rect contains the target on every
  side. A spring with no bounce is still up to half a point short then, which uncovers only the same
  picture underneath. So the
  annotator's window comes up there, with its own shadow off (`AnnotationController.show`), hidden
  behind the flight image until `arrived`. That is what makes the editor take the pointer the moment
  the card looks still: the toolbar and the outside-click monitor start with the window, and a
  shadow is the one thing that would show, because it falls outside the frame it is cast from. The
  keys come earlier: `prepare` orders the window in at alpha 0 and makes it key, so a tool key or
  Esc pressed during the flight already reaches the editor. Presses come later: the window server
  passes every press through a window at alpha 0, and starts giving the window its presses 6 to
  39 ms after `show` sets alpha 1, or up to 97 ms under load. Nothing announces that moment, so
  `AnnotationController.probeEvents` asks the window server every millisecond from `show` whether a
  press at the frame's centre reaches the window, looking through this app's windows above it. It
  gives up after 0.5 s. `[annotate] takes events after=<n>ms reached=true|false` reports the answer,
  and `reached=false` means it gave up. Until then the flight takes the presses (the next rule).
  Done or Esc is accepted between the two moments, so the `arrived` callback is guarded on the key,
  not the phase. A flight can also go without arriving, and a third callback, `dropped`, runs then,
  so the window never keeps a shadow that is switched off. The window is at the fitted frame by then
  whatever the zoom was: `hide` springs the level back to 1 first and comes down once that has
  arrived (`AnnotationController.fitBeforeHide`). `docs/shadow-2026-09-17.md` and
  `docs/handover-2026-09-18.md` have the frames and what each moment cost.

  The way home is the same handover the other way round. The flight starts at the editor's frame,
  the editor's frame is hidden in the commit that starts the flight moving, and its window is ordered
  out three display refreshes later (`AnnotationController`'s `Removal`). The window server takes a
  window down at once, so ordered out in the turn the flight was added, the window left the frame
  empty for 4 to 9 frames before the flight showed. The flight starts from the editor's own decode,
  from Thumbnailer's cache: a lone thumbnail's flight images are dropped when its stack hides, and
  its card's picture showed for one blurred frame. `docs/e2e-2026-09-26.md` has the frames.
- The flight layer takes the presses on a flying card or a swallow rect, and nothing else; the matte
  rule below says why nothing else reaches it. Its content view, `PressCatcher`, takes each press
  with its drags and its release, and `FlightPress` decides where they go. Its comment and
  `FlightPressTests` have the cases. In short, a press on the card flying into the editor is held
  until the editor's window takes presses, then handed to the editor (`AnnotationController.take`,
  `EditorView.take`), and a press on any other flight is swallowed up to its release. A held event
  lands on the point of the picture that was under the pointer when it happened (`FlightSpotView`);
  after the handover, the pointer's place on screen decides. Marks drawn before the flight lifts
  appear when it lifts. A press handed over onto the text being typed goes to the text
  (`pressText`). The text view cannot track that press itself, because its tracking loop would read
  the drag and the release from the event queue, where they are the flight layer's, in that window's
  coordinates. So such a press cannot drag selected text to move it. A double-click handed over does
  not zoom before the landing (`docs/rules/zoom.md`).

  For `NSEvent.doubleClickInterval` after a click opens a card in the editor, or swaps the editor to
  one, the layer also swallows presses on that card's slot, as the hovered card drew it, before any
  flight over it (`ThumbnailController.swallowSecondClick(on:)`,
  `TransitionLayer.swallowPresses(in:for:on:)`). The `SwallowRect` is drawn with the column's hair
  of alpha, so the window server gives the layer the presses there, above the stack. Opening a card
  narrows the stack away from its slot and can slide the card above into it, so without this the
  second click of a double-click reached the app behind the narrowed stack, or opened the card that
  slid into the slot. Return and URL opens have no click and swallow nothing.

  The layer orders out once it has no flights, no swallow rects and no press down
  (`orderOutIfIdle`), because the window server sends a press's drag and release to the window that
  took the press. `watchRelease` ends a press whose release never arrives, from the button's own
  state, and logs `[flight] release missed`. The layer stays up while the editor is open, and a lone
  card's panel goes on screen under it once the flight home covers the slot
  (`docs/exit-panel-2026-11-01.md`). A pointer over a flight gives the stack a hover
  exit, so a card landing from the editor takes its hover from where the pointer is
  (`ThumbnailController.hover(landing:)`). `docs/flight-press-2026-09-23.md` has the measurements
  and the two limits that remain: the window server's lag of 6 to about 30 ms, and a press at
  motion 0 that passed through, which needs no fix.
- "Click outside" detection goes through `OutsideClick`. A plain global mouse monitor also
  reports clicks on this app's own floating windows, so the topmost window under the cursor is
  checked first. The stack and the annotator each own one; the monitor's token never leaves that
  file. The annotator's ignores clicks for `outsideClickSettling` after its window is ordered in:
  the window server does not report the new window under the cursor for a few milliseconds, and a
  press inside the frame then reads as outside. That is a race, not motion, so the scale does not
  touch it.
- A screenshot's transparent pixels are never see-through. The annotator's frame, a card
  (`StackView`) and a flight (`TransitionLayer`) paint `Config.matte`, `#1a1a1a`, behind the image,
  so nothing changes when one takes over from another. The matte is also what routes the annotator's
  clicks. Its window spans the screen's visible frame and is clear outside the frame, and the window
  server gives a press to a window only where its pixel is not clear. So every press on the frame
  reaches the editor, and a click outside it reaches the app behind, where the annotator's
  `OutsideClick` sees it and closes the editor. A shadow passes presses too: asked about points from
  1 to 64 pt outside a card, the window server named the window behind every time, for a layer
  shadow like the annotator's and a SwiftUI shadow like a flight's. So the annotator's shadow and a
  flight's are click-through. All of this holds for the annotator and the flight layer only while
  `ignoresMouseEvents` is never set on either: set either way, the window takes or passes every
  press, whatever its pixels.
