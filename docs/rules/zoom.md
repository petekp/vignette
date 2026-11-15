# Zoom

- Zoom belongs to the annotator, not the editor. A pinch, a two-finger double tap and a wheel over
  the editor go straight to `AnnotationController` through `onZoomGesture`, with the trackpad's
  phases: a pinch and a wheel with cmd or ctrl held zoom, and a plain wheel pans a magnified
  picture. The zoom keys, cmd+plus/minus/0, and a double-click on empty space with the select tool
  are the core's to recognise, because it knows the tool and what is under the pointer, and it sends
  them as a `ZoomRequest` through `onZoom`. While typing, the editor sends the caret's rect in image
  px through `onReveal` whenever it moves, and the zoom pans a magnified picture just far enough to
  show it, since a text wraps at the image's edge and not the frame's.

  The rules are one pure value, `AnnotatorZoom` (`Sources/AnnotatorZoom.swift`), held by
  `AnnotationController`. The controller turns events into its inputs: a wheel's lines into points,
  the trackpad's phases into a hand and a lift, and a point in the window into a fraction of the
  frame. It runs the spring the zoom asks for on a `Tween`, scaled by the motion setting, sends each
  tick back, and puts the frame and the picture where the answer says. Nothing zooms until the
  flight has landed or once the card has started home: the editor takes keys from `prepare` and
  presses handed over from the flight, a zoom before the landing would grow the window under a
  flight image still at the fitted frame, and the card flies home from the fitted frame. The
  zoom's phase is `annotator.zoomPhase` in the state report: closed, flying, landed or closing.
  Add a sequence to `AnnotatorZoomTests` before changing a rule; its random-sequence test checks
  the invariants through a spring that ticks part of the way, turns, and arrives.

  All of them move one number, the level: how far the image is magnified past the frame it opened
  in. The picture is magnified uniformly by that level, so the image is never stretched. The frame
  is not: each of its sides grows with the level until that side fills the room it was given, the
  visible screen less the strip the recent stack keeps, and less the toolbar and its two margins
  along the bottom (`Zoom.room`). `Zoom.split` divides the level in one place,
  one division per side, so `window * camera` is the level in each direction. Zooming out stops at
  the fitted size. Only a hand pulls below it, with a short pull that springs back when the fingers
  lift; a key or a mouse wheel's notch stops at the fit. Zoom's springs are in code rather than the
  tweaks, but the motion scale still shortens them. `Sources/Zoom.swift` is the geometry. Its
  comments, and those on `AnnotatorZoom.aimFrame`, `aimPan` and `Tween`, say how the spring, the
  anchors and the edge pull work, and `docs/zoom-input-2026-09-19.md` has the measurements behind
  the anchor. `docs/annotator-zoom-2026-10-01.md` has the design of `AnnotatorZoom`.

  One process draws the frame and the picture, so a zoom step is one commit. `moveFrame` is the only
  place the frame's rect is set. In one run loop turn it sets the frame from `Zoom.frame` and the
  picture inside it from `Zoom.picture`, and hands the editor its new size and picture together
  (`EditorView.setSize(_:picture:)`), so the marks, the overlay and the text being typed follow in
  that same turn. The toolbar moves in that turn too (`AnnotatorToolbar.follow`). Its top edge is
  `annotationToolbarGap` below the frame's bottom edge, or below the fitted frame's when that is
  lower (`Zoom.barTop`). So a frame growing down carries the bar with it, the same gap between them,
  and a pull below the fit leaves the bar where it opened. Once the frame's bottom edge reaches the
  bottom of its room, the bar rests the same gap above the bottom of the visible screen, the Dock's
  top when the Dock is there. The frame's bottom edge stops there, and the sides that have not
  filled the room keep growing. The bar is never over the image, and zooming out brings it back
  along the same path. The zoom counts the bar as `AnnotatorToolbar.height` tall: a message field
  that grows past the bar while it is typed in hangs over the image, as it does over the screen,
  and the frame stays where it is. The room is set when the image opens, so a Dock that appears or
  moves while it is open changes nothing until the next image. The texts are drawn again for the
  new zoom once the picture has stayed put for `EditorView.restDelay`. The state report's `annotator.zoomLevel` is the one number,
  `annotator.zoom` and `annotator.canvasZoom` its two halves per direction, `annotator.zoomAnchor`
  the point the window grows away from, `annotator.zoomCenter` the middle of the visible part, and
  `annotator.room` the rect the frame may grow within, the bar's room already taken off.
