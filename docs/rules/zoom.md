# Zoom

- Zoom belongs to the annotator, not the editor. A pinch, a two-finger double tap and a wheel over
  the editor go straight to `AnnotationController` through `onZoomGesture`, with the trackpad's
  phases: a pinch and a wheel with cmd or ctrl held zoom, and a plain wheel pans a magnified
  picture. The zoom keys, cmd+plus/minus/0, and a double-click on empty space with the select tool
  are the core's to recognise, because it knows the tool and what is under the pointer, and it sends
  them as a `ZoomRequest` through `onZoom`. While typing, the editor sends the caret's rect in image
  px through `onReveal` whenever it moves, and the zoom pans a magnified picture just far enough to
  show it, since a text wraps at the image's edge and not the frame's.

  The rules are one pure value, `AnnotatorZoom` (`Sources/AnnotatorZoom.swift`, its inputs and effects in
  `AnnotatorZoom+Types.swift`), held by
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
  visible screen less the strip the recent stack keeps with a margin beside it, and less the
  toolbar and its two margins along the bottom (`Zoom.room`). All three margins are
  `annotationToolbarGap`. So the frame stops the same distance from the stack as from the toolbar,
  and the toolbar that distance above the Dock. Against the menu bar and the screen's left edge the
  frame keeps no margin. `Zoom.split` divides the level in one place,
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
  that same turn. The toolbar moves in that turn too (`AnnotatorToolbar.follow`, given the middle of the bar's top edge and the zoom's fitted frame, and a no-op for a bar placed under another frame, so a tick before a swap's `place` cannot make the bar jump). Its top edge is
  `annotationToolbarGap` below the frame's bottom edge, or below the fitted frame's when that is
  lower (`Zoom.barTop`). So a frame growing down carries the bar with it, the same gap between them,
  and a pull below the fit leaves the bar where it opened. Once the frame's bottom edge reaches the
  bottom of its room, the bar rests the same gap above the bottom of the visible screen, the Dock's
  top when the Dock is there. The frame's bottom edge stops there, and the sides that have not
  filled the room keep growing. The bar is never over the image, and zooming out brings it back
  along the same path. The zoom counts the bar as `AnnotatorToolbar.height` tall: a message field
  that grows past the bar while it is typed in hangs over the image, as it does over the screen,
  and the frame stays where it is.

  The room is taken again when it changes while an image is open: a Dock that appears, hides or
  moves, or a screen that changes resolution or arrangement. Each of those posts
  `NSApplication.didChangeScreenParametersNotification`, and `ThumbnailController.screensChanged`
  hands the annotator the new fitted frame and room, worked out as an opening does
  (`AnnotationController.refit`). The zoom takes them as `.refit` (`AnnotatorZoom.refit`). A zoomed
  image keeps its magnification on screen, the picture's points per pixel, up to the new room's cap,
  with the same part of it in the middle. An image at the fit stays at the fit, and a pull below
  the fit lets go. Each side of the frame then grows to the new room or stops at it, as at any
  level, so the frame is never under the Dock or off the visible screen, and Cmd+0 comes home to
  the new fit. The frame, the picture and the bar move there on a step's spring, scaled by the
  motion setting (`refitTween`). Each tick draws them that part of the way from where they were
  drawn to where the rules put them now (`AnnotatorZoom.Placement.blended`), so the move starts
  from what is on screen and a zoom during it bends into it. On the way the frame's edges are
  rounded inward to the pixel grid, so the picture still covers it. The bar is placed under the new
  fitted frame first, and the ticks carry it there, sideways too. The window grows to cover the new
  visible frame and the frame's old place, and keeps that size until the next image. So after a
  Dock moves to the side the frame touches, the frame's shadow can lie over the Dock's edge until
  then. A frame that
  lands on another screen moves at once. The stack narrows to each tick through `onFrame`, as it
  does for a zoom, and the card flies home from the new fitted frame (`onRefit`). A change during
  the flight in waits until the flight's image has gone (`.lifted`), lifted once the editor is
  ready or dropped, since that image is drawn over the window where the flight put it. Once the
  card has started home, a change does nothing. A close during a re-fit lets it land beside the
  close's fit, and the window comes down once both have (`fitBeforeHide`). A change that moves
  neither the fit nor the room asks for nothing, since a screen change posts several
  notifications.

  The texts are drawn again for the
  new zoom once the picture has stayed put for `EditorView.restDelay`. The state report's `annotator.zoomLevel` is the one number,
  `annotator.zoom` and `annotator.canvasZoom` its two halves per direction, `annotator.zoomAnchor`
  the point the window grows away from, `annotator.zoomCenter` the middle of the visible part, and
  `annotator.room` the rect the frame may grow within, the bar's room already taken off.
