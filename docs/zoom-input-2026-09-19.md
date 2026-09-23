# Zoom input and the placed page, 2026-09-19

What was measured before and after the zoom's input path and its page hand-over were changed, and
why each change is shaped the way it is. Every number here is from a synthetic cmd+wheel stream
of CGEvents at 60 Hz aimed at 0.3 of the frame's width, on a 900 x 560 fixture with a black bar
at its left edge, recorded with `screencapture -x -v` at 60 fps around the frame and read back
per frame as the leftmost and rightmost bright column (retina pixels). The build before is
b741d27; the runs were made with the recent stack closed and open, on a scratch settings file.

This note is history in part. It was measured on the web editor, which the native editor replaced
on 2026-09-22. The anchor fix, the display-link fix and the phase handling still hold: the native
editor hands a pinch and a wheel to `AnnotationController` through `EditorView.onZoomGesture`, and
the same code runs from there. What the note says about the web process's input path, the page
laid out at the room, and the stand-in describes the web editor only.

## The glitch: a zoom-out stepped sideways at the fit

Zooming out from 1.75 through the fitted size, the frame's left edge moved, per 60 fps frame:

| frame | left edge | change | right edge | change |
| --- | --- | --- | --- | --- |
| 183 | 147 | +9 | 1977 | -10 |
| 184 | 231 | **+84** | 2027 | **+50** |
| 185 | 243 | +12 | 1985 | -42 |
| 186 | 196 | **-47** | 1909 | **-76** |
| 187 | 203 | +7 | 1899 | -10 |

Both edges moving the same way is the frame sliding, not shrinking: 40 points to the right and
back within three frames, exactly at the crossing (widths 1830, 1796, 1742, 1713 against a fit of
1718). The stack open beside it gave the same shape (+56/+20 then -9/-51). Keyboard steps never
showed it.

The cause was `Zoom.anchor(holding:)`: below the fit the anchor was worked out to hold the
cursor's point against the frame on screen, which divides the cursor's displacement by the shrink.
A zoom-out from a grown frame passes that shrink through zero, so the anchor swung from 0.5 to
about -2 and back over consecutive ticks (reconstructed from the frames: 0.48, -0.38, -1.95,
-0.57, 0.13). The fix (5c50df4) keeps the frame on the line it is already on below the fit: the
room's line for a zoom-out that runs through the fit, the cursor's for a pull from rest, and home
from a pull is the same line back. After it every move through the fit is symmetric (left +32,
right -32), with the stack closed and open.

## The uneven steps: one display link per input

With the glitch gone, a steady wheel still moved the frame unevenly. Per 60 fps frame, on the
steady part of a zoom-out (the web-process input path, stack open):

    51 60 19 34 54 29 17

Two causes, both removed:

- `Tween.animate` stopped and recreated its `CADisplayLink` on every retarget, and a gesture
  retargets it at every input. A link made anew fires its first tick at an arbitrary part of the
  refresh, and `lastTick` restarted at the input, so the spring's first step after each input was
  a fraction of a frame long. It now keeps its link and its last tick and only moves the target.
- The wheel crossed into the web process and back: WebKit, then JavaScript coalescing to one
  message per page frame, then a message to the host. That is one to two frames of latency, and
  the messages bunched (two in one refresh, none in the next), which the old tracking spring's
  comment already acknowledged. The wheel with cmd or ctrl held is now taken in
  `AnnotationWebView.scrollWheel`, as the pinch already was in `magnify`.

The same zoom-out on the new path, stack open:

    46 44 47 50 38

and the zoom-in 41 55 67 66 30 (against 50 25 39 52 52 42 30 before). What remains is the spring
catching up, not alternation.

## Phases: the pull releases, a notch stops at the fit

A DOM wheel event has no begin or end, so on the old path a wheel never released the pull below
the fit: it only snapped back when the tracking spring happened to arrive, and the next tick
pulled again. The native event carries the trackpad's `phase` and `momentumPhase`:

- `ended` or `cancelled` releases the pull, as the pinch's end does.
- Momentum after the lift is ignored, so the zoom stops where the hand did.
- A mouse wheel has no phases: each notch is a step (the step spring) and stops at the fit.
- A key stops at the fit too. Cmd+minus at the fit no longer shrinks and springs back.

Measured on the final build, `[state] annotator.zoomLevel`: a mouse wheel out from the fit 1.0000;
cmd+minus from the fit 1.0000; a trackpad wheel out read mid-gesture 0.6399 with the stand-in up,
and 1.0000 after the lift with the stand-in down; a mouse wheel in 1.4918 and out past the fit
1.0000.

## The page is laid out once, at the room

History: the web editor only. The native editor has no page and no stand-in; `moveFrame` sets the
frame and the picture inside it in one turn.

Before, every rest resized the WKWebView to the frame's size (rounded up to whole points), then
sent the view and waited for the resize to reach the web process (`waited` frames) before the
page could paint. A WKWebView resize is a relayout in another process, and a trackpad with
momentum rests many times per gesture.

Now the web view is laid out once per image at the whole room the frame may grow within
(`pagePlace`), and the frame moves over it. At each rest the page is moved back so it stays put
on screen (an origin change, no resize) and `setView` carries two rects in the page's own points:
the frame's, where the page puts its `.editor` element, and the image's, which is the stand-in's
own `Zoom.picture`. The page places the editor and sets the camera in one turn, so one paint
carries both, and the stand-in and the page show one rect by construction: `Zoom.pageRatio` and
the base-zoom arithmetic are gone with the protocol bump to 14. `load` carries the same frame, so
the image opens fitted to it.

Hand-overs on the final build: `view 47ms`, `37ms`, `39ms`, `64ms`, against 39 to 64 ms before;
the cost was never the paint but the resize's round trip and its class of mismatches. The one
mismatch that remains is the frame's rounding of the image's shape: the stand-in stretches the
picture to the frame and the page scales it evenly, so they differ by under a point at the fit
and that times the magnification above it (measured: 2 px at 2.7x). The mismatch line's tolerance
is that, so it fires for a real disagreement only.

## An input that moves nothing

This still holds; the stand-in it mentions is gone.

A notch out at the fit, or cmd+0 at rest, used to raise the stand-in and hand the picture
straight back (one of those hand-overs took 483 ms behind the page's other work). `zoom` now
works out the target first and returns when it is the one the spring is already at.

## Not measured

A real trackpad, still: every stream here is synthetic, with the phases set on the events. The
stack open beside the annotator did not add dropped frames in any recording, and an Instruments
trace with it open showed no Core Animation commit over 8.3 ms during a zoom (main thread at
120 Hz), so the stack's relayout per hundredth of its width is not where the time goes.
