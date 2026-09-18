# Brief: zoom with a native stand-in during the gesture, the page only at rest

The decision and the design are item 17 in TODOS.md. This is the working brief for whoever
builds it: the reasoning, the order of work, and the acceptance bar. It assumes the loop and the
rules in AGENTS.md, including the ones for driving a build while the user is at the Mac.

## Why this design
Three passes on 2026-09-17 tuned the current zoom and it still reads as janky. The frame is a
Swift layer in the app process; the picture is composited by WebKit's content process; between
relayouts the picture is a stretched bitmap of the web view. Two drawers with no shared frame
clock cannot be perfectly aligned, and a stretched bitmap cannot be crisp. Photos and Quick Look
scale a native image layer during the gesture and never show a web view mid-motion. Do that.
`docs/zoom-2026-09-17.md` describes the current design and how it was measured; the Round 3
section of `docs/run-2026-09-17-daytime.md` has the review of it.

## Build
1. Measure the current build once with the methods in `docs/zoom-2026-09-17.md` (a
   trackpad-shaped cmd+wheel stream through the page's wheel handler, a 60 fps recording of the
   frame's edge and of a stroke inside the picture, and `[state]` reads) so the after has a before.
2. The stand-in. On the first zoom input while the page is at rest, put a native layer tree over
   the web view inside `frameView`: the screenshot at native pixels (decoded through `Thumbnailer`
   so it is decoded off the main thread and counted in its budget), the annotation overlay
   (below), the rounded mask, and the shadow the frame already draws. The zoom spring's tick sets
   the frame's rect and the stand-in's transform from `Zoom.split` in one transaction. The web
   view stays in place, covered, never hidden: WebKit pauses frame callbacks for a hidden view,
   and the paint confirmation below needs them.
3. At rest. When the spring arrives, resize the web view to the frame, send the page the exact
   camera for (frame, level) through one function both sides share, and wait for the page to
   answer that it painted at that camera and size (two animation frames after applying it).
   Then crossfade the stand-in out over a short motion-scaled time; with motion 0 a hard swap.
   Measure the swap: no stroke or edge may move by more than a pixel between the last stand-in
   frame and the first page frame, and the overlay band's brightness may not step.
4. The overlay. Add a page call that renders the annotations alone on a transparent canvas at a
   given pixel size (`render` in `App.tsx` already layers tldraw's SVG of the annotations on a
   canvas; this is that without the screenshot) and sends the PNG back. Export after `loaded`
   and after each change, debounced behind the `draft` message, through the page's one-at-a-time
   queue; cap the long side (a `Config` constant near `previewMaxPixel`); keep one per image,
   freed when the annotator hides; use the last one if a new one is still rendering; no shapes
   means no overlay and a stand-in of the screenshot alone. Bridge changes bump `PROTOCOL` and
   `bridgeProtocolVersion` together.
5. Inputs. Pinch, cmd+wheel, keyboard steps, smart zoom, and cmd+0 all drive the same spring as
   now; the gesture and step durations stay. Esc, Done, and a swap from a zoomed state keep the
   rule that the window springs home to the fitted frame first, then hides. With the stand-in,
   the picture that springs home is native, so check that the flight image and the stand-in agree
   at level 1.
6. Delete what the stand-in replaces: `scaleWebView` and the layer transform, the relayout cover,
   `uncoverWhenPainted`, the deadline, and the AGENTS.md sentences about them. Rewrite the zoom
   bullet and the memory bullet (the overlay's size, count, and lifetime). Add a dated section to
   `docs/zoom-2026-09-17.md` saying what changed and why, or replace it.
7. Tests: `ZoomTests` for the (frame, level) to camera mapping used by both sides; `RenderTests`
   for the overlay export (transparent outside the strokes, coloured inside, the right pixel
   size); the random-sequence test in `AnnotatorTransitionTests` still passes untouched.

## Acceptance
- Driven: frame and picture edges agree in every recorded frame during a stream; the swap at
  rest is invisible by the measure in step 3; a zoom during an overlay export shows the previous
  overlay, not a blank; `[state]` at rest reports level, window, camera, and `page.inner`
  consistent with the mapping; cancel and Done from a zoomed state show no step; `ui.motion: 0`
  lands every step at once; `[state] memory` before and after ten gestures differs by no more
  than one overlay.
- By hand, at the end: pinch and Cmd+scroll on a trackpad track the fingers with no visible lag,
  no misalignment between picture and frame, crisp throughout, and nothing visible when the page
  takes over at rest. A real pinch and smart zoom cannot be synthesized, so this is the test that
  counts.

## Report
The before measurements, the decisions made beyond item 17 and why, the after measurements,
what could not be verified, open questions, and the commits.
