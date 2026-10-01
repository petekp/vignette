# The zoom's rules leave the window controller

`AnnotatorZoom`, a pure value, owns the annotator's zoom rules: what each input does to the zoom
level, where the frame grows, and which part of the image is in view. `AnnotationController` turns
events into inputs, runs the spring the zoom asks for, sends back each of the spring's ticks, and
puts the frame and the picture where the zoom says. `Zoom.swift` stays the geometry.

## Why

The geometry in `Zoom.swift` is tested. The rules that drive it are private methods of
`AnnotationController`, beside the window, the event probe and the toolbar, and have no tests:

- A key or a mouse wheel's notch stops at the fitted size. Only a hand pulls below it.
- A pull below the fit springs back when the fingers lift, or when the spring arrives.
- Nothing zooms before the flight has landed.
- A double tap zooms in two times, or back to the fit from anywhere above it.
- A pan or a reveal moves only a picture magnified past its frame.
- The window fits again before the card flies home.

Five zoom fixes each changed `AnnotationController` and added no test of it: c134590, 607a4ae,
fcfd328, f67164e and 05e784c. Twelve of the controller's fields are the zoom's.

## The interface

```swift
struct AnnotatorZoom {
    enum Input {
        case prepare(fitted: CGRect, room: CGRect)   // an image opens in `fitted`; the frame grows within `room`
        case landed                                    // the flight put the image down
        case zoomIn, zoomOut, fit                      // Cmd+Plus, Cmd+Minus, Cmd+0
        case smart(at: CGPoint?)                       // a two-finger double tap, or a double-click on empty space
        case pinch(by: CGFloat, at: CGPoint?)          // a pinch's magnification
        case wheel(points: CGFloat, at: CGPoint?, fingers: Bool)   // a scroll with Cmd or Ctrl held
        case lift                                      // the fingers left the trackpad
        case pan(by: CGVector)                         // a plain scroll, in points
        case reveal(CGRect, image: CGSize)             // the caret, in image px
        case tick(CGFloat)                             // the spring's level now
        case arrived                                   // the spring reached its target
        case close                                     // the card is about to fly home
    }
    enum Effect {
        case spring(to: CGFloat, seconds: Double)      // carry the level there
        case place(frame: CGRect, picture: CGRect)     // a tick: the frame and the picture in it
        case movePicture(CGRect)                       // a pan: the frame stays
    }
    mutating func reduce(_ input: Input) -> Effect?
    var edge: EdgePull                                 // ui.zoomEdgeBandPoints and ui.zoomEdgePull
    var phase, level, window, camera, center, anchor, room, frame, picture { get }
}
```

A cursor is a fraction of the frame, x from the left and y from the top. Nil means the middle.

A spring's seconds are the zoom's own. The controller scales them by the motion setting, so motion 0
and Reduce Motion still land a step at once. The controller keeps the `Tween`, so the spring keeps
the display link it already has.

## What stays in the controller

- Decoding events: a wheel's lines into points, a trackpad's phases into `fingers` and `lift`, and
  ignoring momentum after the lift.
- Turning a point in the window into a fraction of the frame.
- The `Tween`, the motion scale, and `moveFrame`, the one place the frame's rect is set.
- `fitBeforeHide`: it runs the close's spring with its own completion, and a deadline, so the window
  comes down even if the spring never reports arriving.

## Behaviour

The same, except for two edges. Both make one rule hold everywhere: the zoom moves only between the
landing and the close.

- **A gesture before the landing does nothing.** Before, only the keys and the double-click waited
  for the landing. A pinch or a scroll could not reach the frame then anyway, because the flight
  covers it.
- **An input during the fit before the card flies home does nothing.** Before, a pinch in those
  0.2 s aimed the spring somewhere else and took its completion. The window then came down at the
  deadline at whatever size it had.

`[state]` keeps its keys and adds `annotator.zoomPhase`: closed, flying, landed or closing.

## Tests

`Tests/AnnotatorZoomTests.swift`:

- One sequence per rule above.
- Random sequences, 1000 seeds, through a fake spring that ticks part of the way, retargets, and
  arrives. Invariants:
  - nothing moves outside the landed phase, except the close's own fit;
  - a key or a notch never aims below the fit, and a hand never below half of it;
  - nothing aims past the cap;
  - a lift or an arrival below the fit springs back to it;
  - every tick's frame stays in the room;
  - the frame's growth times the magnification is the level, per side;
  - the picture covers the frame;
  - a tick at level 1 is the fitted frame;
  - a pan moves only a magnified picture.

`ZoomTests` keep testing the geometry.

An end-to-end scenario, `zoom_keys`, under `--input`. It opens an image with a click and waits for
the landing. Then it checks three things. Cmd+Minus at the fit moves nothing. Cmd+Plus twice grows
the frame to level 1.5625. Cmd+0 brings it back to the fitted frame. No scenario zooms today.

## Verification

1. `scripts/build.sh --test` in the worktree, then `lsregister -u` on the built app. All 423 tests
   pass.
2. Two mutation checks, each restored afterwards. With the key's floor at the fit removed, the key
   test and the random test fail. With the landing's guard removed, the landing test and the random
   test fail.
3. `scripts/e2e/e2e.py run`: every scenario without input passes. One run in ten had
   `annotate_open` open the editor without the agent's two marks. That scenario does not zoom, and
   nothing in its log says why.
4. `scripts/e2e/e2e.py run --input`, which posts keys, so it runs with Pete's go-ahead.
