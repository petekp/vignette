# Pins

A pin is a numbered teardrop that holds comments, at a point or over an area of a screenshot. The
rest of the editor's and the drawings' rules are in `editor-and-drawings.md`.

- A pin is drawn above every mark, as a teardrop whose tip is its point, or the corner of its area
  where the drag that made it ended (`Pin.Corner`, stored as `corner`), mirrored by a resize that
  takes a side past the opposite one. Its body goes up and to the right, or up and to the left from
  a bottom-left corner, so it stays outside the area (`Pin.leansLeft`). Where that body and its
  edge would cross the picture's top edge it goes below the tip, and where they would cross a side
  edge it goes to the other side. A body those edges would put inside its own area turns the first
  other way that keeps it out. A cluster opens to the side its first teardrop faces. The
  orientation is worked out each time from the picture at the drawing's own size and is never
  stored, so every drawer agrees (`PinTeardrop.facing`). A body that would cover a stitch's piece
  number turns away from it (`Drawing.pieceNumbers`). `MarkLayers` shows pins with `PinLayer`
  and `MarkRendering` draws them with `Pin.draw`, from the same paths. On screen a pin has its own
  look (`PinShading`): a gradient, a white hairline and a soft shadow, the same in the editor, on a
  card and in flight. A rendering keeps the marks' white edge. `MarkLayers` clusters them as
  `PinPlacement` does at the drawing's own size. A card's teardrops scale with its picture, so that
  is the editor's rule at the card's size, and a flight shows the card's clusters.
- A PNG rendering draws pins as `Drawing.renderedTeardrops` places them, since its reader cannot
  hover. It outlines every area in its pin's colour. A body that would overlap an earlier pin's
  body or a piece number tries its other orientations, then moves clear, and a line in the pin's
  colour joins it to its place. Copy (Done, Cmd+C), Copy Drawing, a drag and a stitch's first copy
  render `Rendering.Layout.withComments`. A drawing with pins then gets its comments listed below
  a wide screenshot or right of a tall one (`CommentList`), and the clipboard's text is each path
  followed by its pins' words (`Pin.clipboardWords`). The list's area is capped, so a rendering's
  memory stays bounded: the pins past the cap become one line saying how many did not fit. Send
  renders `.picture`, the screenshot's size, and its line carries the words.
- A stitch makes its pieces' pins its own. They are renumbered from 1 in piece order and get new
  ids, since each piece keeps its own (`Stitch.Composition.pins`). The stitch's drawing holds them
  and where each piece wears its number, and is written before its card appears. Its first copy
  is the rendering with the list, and the card's Copied notice waits for that rendering. A stitch
  of pieces with pins is refused when a piece could not be read or the pins number over 99, and a
  card says why (`Stitch.refusal`). A stitch without pins writes a drawing holding only its
  `pieceNumbers`, so a pin added later turns away from them, and copies its picture as before.
  That file counts as a drawing in `Drawings.keys`, so a rename and the sweep carry it, but it
  reads as no drawing (`Drawing.isFiled`, `DrawingStore.readNumbering`).
- The editor draws pins itself, above the marks, in view coordinates (`EditorPins`), so a teardrop
  keeps the size it has at the fit zoom whatever the zoom; `EditorPicture` leaves them out of
  `MarkLayers`. The core places them (`EditorCore.pinPlacement`, `PinPlacement`): pins whose
  bodies overlap past `ui.clusterOverlap` of their width draw as one cluster, except the selected,
  the open and a new one. The core needs the fit zoom and the visible rect for that and for
  Shift+Return, and the view sends both (`viewChanged`) before each `zoomChanged`. A pin is
  selected, moved, nudged and deleted with the marks, by its `id` in `selection`.
- A cluster and the toolbar's Pins button open one list, an `NSMenu` a turn later, under the
  capsule or the button (`EditorView.showPinList`, `pinListItem`). A pick, a turn later again, goes through `openFromList`: `EditorPinUI.onReveal` pans to its teardrop and area, or `onZoom(.fit)`
  when they are larger than `EditorCore.visible`, then the composer opens. The controller closes the
  list when another image opens or the editor leaves (`closePinList`). The bar shows the button while
  `Model.pinCount`, which `EditorPinUI.onCount` sets, is above 0, and Tab reaches it after the tools.
- A new pin has number 0 and is left out of every hand-over (`drawingForHost`) until its first
  comment gives it `nextPin`. The editor opens with the file's `nextPin` and `pieceNumbers` even
  when the file reads as no drawing (`AnnotationController.storedNumbering`), so a number a
  deleted pin had is not given again while the file lasts. The popover by a pin is an
  `NSPopover` (`PinPopover`) that sends `ComposerInput`; the core owns its state
  (`EditorCore.Composer`) and says when it opens, changes or closes (`.composer`). It opens to the
  right of the teardrop, or to its left when the screen has no room. Its post button posts as
  Return does, and works only while the field holds words. A press on a handle of the open pin's
  area resizes it with the popover open (`keepsComposer`); the resize is its own undo step, the
  composer's edit begins again after it (`resumeComposerEdit`), and the field takes the keys back.
- In the editor an area's outline is dashed in its pin's colour inside a white edge, one width on
  screen at every zoom (`AreaOutline`). Its dashes march while the pin is being placed or is open
  (`EditorCore.marchingPins`), at `ui.pinAreaSpeed` times the motion setting, so Reduce Motion
  stills them. A rendering draws the area as a solid rectangle mark.
