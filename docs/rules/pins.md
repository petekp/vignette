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
  and `MarkRendering` draws them with `Pin.draw`, from the same paths. On a card and in flight a
  pin has its own look (`PinShading`): a gradient, a white hairline and a soft shadow. In the
  editor it is gel (below). A rendering keeps the marks' white edge. `MarkLayers` clusters them as
  `PinPlacement` does at the drawing's own size. A card's teardrops scale with its picture, as a
  rendering's do, and a flight shows the card's clusters. A flight between a card and the editor
  scales each pin about its tip on every frame (`MarkLayers.PinGrowth`), so its size on screen
  moves from the card's to the editor's `ui.pinSize` as the picture's zoom does, and lands at the
  editor's size. The way home shrinks it back the same way.
- A PNG rendering draws pins as `Drawing.renderedTeardrops` places them, since its reader cannot
  hover. It outlines every area in its pin's colour. A body that would overlap an earlier pin's
  body or a piece number tries its other orientations, then moves clear, and a line in the pin's
  colour joins it to its place. Copy (Done, Cmd+C), Copy Drawing, a drag and a stitch's first copy
  render `Rendering.Layout.withComments`. A drawing with pins then gets its comments listed below
  a wide screenshot or right of a tall one (`CommentList`), and the clipboard's text is each path
  followed by its pins' words (`Pin.clipboardWords`). The list's area is capped, so a rendering's
  memory stays bounded: the pins past the cap become one line saying how many did not fit. Send
  renders `.picture`, the screenshot's size, and its line carries the words.
- Each comment has an `id` (`Pin.Comment.id`), written in the drawing file, its history and a
  request's `pins.json`. An edit of its words keeps it. A paste, a duplicate or a stitch gives the
  copy's comments new ones (`Pin.Comment.copied`). A comment from a file without ids reads with
  `Pin.Comment.standInID`, made from its pin's id and its place in the list, and `EditorHistory.basis`
  leaves comment ids out, so such a file keeps its history (`docs/drawing-file.md`).
- A stitch makes its pieces' pins its own. They are renumbered from 1 in piece order and get new
  ids, and so do their comments, since each piece keeps its own (`Stitch.Composition.pins`). The stitch's drawing holds them
  and where each piece wears its number, and is written before its card appears. Its first copy
  is the rendering with the list, and the card's Copied notice waits for that rendering. A stitch
  of pieces with pins is refused when a piece could not be read or the pins number over 99, and a
  card says why (`Stitch.refusal`). A stitch without pins writes a drawing holding only its
  `pieceNumbers`, so a pin added later turns away from them, and copies its picture as before.
  That file counts as a drawing in `Drawings.keys`, so a rename and the sweep carry it, but it
  reads as no drawing (`Drawing.isFiled`, `DrawingStore.readNumbering`).
- The editor draws pins itself, above the marks, in view coordinates (`EditorPins`), so a teardrop
  is `ui.pinSize` screen pt across at every zoom and on a screenshot of any size, as easy to see
  and to hit on a 5K capture as on a small crop (`EditorCore.pinSide`). Copy, Send and Stitch keep
  the drawing's size, `ui.pinSize` drawing pt. The editor's `MarkLayers` keeps them in its drawing
  but draws none (`drawsPins`), so a flight made from the editor's marks carries them. The core places them (`EditorCore.pinPlacement`, `PinPlacement`): pins whose
  bodies overlap past `ui.clusterOverlap` of their width draw as one cluster, except the selected,
  the open and a new one. The core needs the visible rect for Shift+Return, and the view sends it
  (`viewChanged`) before each `zoomChanged`. A pin is
  selected, moved, nudged and deleted with the marks, by its `id` in `selection`. A plain click on
  a pin with a number opens its popover and selects it, with any tool, and a click on the open pin
  closes it (`pinPress`, `Click.open`). A new pin, numbered 0, opens so only with the Comment
  tool. A Shift- or Cmd-click adds the pin to the selection or takes it out without opening it, a
  drag moves it, and a double-click opens it with any tool. Over the picture
  the Comment tool's pointer is the crosshair with a small pin in the person's colour up and to its
  right (`Cursor.comment`), so it is not taken for a shape tool's. The toolbar's Comment tool shows
  the teardrop's outline, a template image as wide and heavy as the symbols beside it
  (`AnnotatorToolbarView.commentIcon`). A drag that sizes an area keeps
  the plain crosshair.
- A cluster and the toolbar's Pins button open one list, an `NSMenu` a turn later, under the
  capsule or the button (`EditorView.showPinList`, `pinListItem`). A pick, a turn later again, goes through `openFromList`: `EditorPinUI.onReveal` pans to its teardrop and area, or `onZoom(.fit)`
  when they are larger than `EditorCore.visible`, then the composer opens. The controller closes the
  list when another image opens or the editor leaves (`closePinList`). The bar shows the button while
  `Model.pinCount`, which `EditorPinUI.onCount` sets, is above 0, and Tab reaches it after the tools.
  Its badge counts the open pins (`Model.openPinCount`), and is a checkmark when every pin is
  resolved. The list puts the resolved pins after the open ones, under a Resolved heading, their
  titles in the secondary label colour.
- A new pin has number 0 and is left out of every hand-over (`drawingForHost`) until its first
  comment gives it `nextPin`. The editor opens with the file's `nextPin` and `pieceNumbers` even
  when the file reads as no drawing (`AnnotationController.storedNumbering`), so a number a
  deleted pin had is not given again while the file lasts. The popover by a pin is an
  `NSPopover` (`PinPopover`) that sends `ComposerInput`; the core owns its state
  (`EditorCore.Composer`) and says when it opens, changes or closes (`.composer`). The popover is
  a window of its own and outlives the editor's unless the core closes it: every way the editor
  leaves its image parks the core, and `park` posts the draft and reports the close
  (`reportComposer`) before it stops reporting. It opens to the
  right of the teardrop, or to its left when the screen has no room. An area pin with no room on the
  right hangs it under its area, or over it when there is no room under it, from the teardrop's
  column, so the area stays in view (`PinPopoverPlace`). That side is kept while the popover is
  open. Its post button posts as
  Return does, and works only while the field holds words. A press on a handle of the open pin's
  area resizes it with the popover open (`keepsComposer`); the resize is its own undo step, the
  composer's edit begins again after it (`resumeComposerEdit`), and the field takes the keys back with its caret or selection where it was (`PinPopover.takeKeys`).
- The popover's comments are in the system's face, an agent's as a person's. Each starts with a line
  holding its writer's avatar, the one the hover card shows (`PinHoverCard.paint`, `Pin.Comment.writer`),
  their name in the label colour, "You" or the agent's capitalized, and how long ago they wrote in the
  secondary label colour. The time is said as of when the popover opened and holds still while it is
  open; a comment with no time (`Pin.Comment.at`) shows none. The words start under the avatar's
  left edge, and the trash button sits at the end of the top line. The person's avatar is their macOS
  account picture (`CBIdentity`), or their initial on `ui.personColor` when the account has none.
  An agent's is what its pin wears (`PinFace`) on its pin's colour: its logo, the first letter of its
  name, or `Agent.fallbackSymbol` when it gave no name, in the words' colour and at the pin's
  `ui.pinLogoSize`. Claude's is its white logo on its orange. The popover is
  macOS's own, with nothing behind its content: a view of our own under the content is not clipped
  to the popover's shape, so its arrow and body part ways. The field's placeholder is in the field's
  font and the secondary label colour. The post button is centred on the field's last line
  (`PinPopover.composerRow`), so one line of words, the placeholder and the caret sit on the
  popover's centre line with the button. The field grows a line at a time as its words wrap, measured
  from the field editor's layout while it is edited, up to `ui.pinComposerLines` lines, past which
  it scrolls (`PinPopover.wrappedHeight`).
- Each comment in the popover has its own Delete, for the person's and an agent's alike: a trash
  button at its trailing edge, shown while the pointer is on the comment, Delete Comment in its
  contextual menu, the Delete key on the comment when Full Keyboard Access focuses it, and a
  VoiceOver action (`CommentRow`). It sends `ComposerInput.delete`, which empties the comment as an
  edit would, so it is one "Delete" undo step and the pin goes with its only comment.
- When the editor lands on a screenshot with numbered pins, the lowest-numbered open pin's popover
  opens (`ComposerInput.openFirst`, from `AnnotationController.landed`), unless a popover, a drag or
  typing is under way, or every pin is resolved. It does not select the pin, and it opens without the keys
  (`Composer.takesKeys` false; `PinPopover.show` gives the key back to the editor's window). So
  the tool letters, Delete and the arrows act on the drawing as they would with no popover. None of
  its views takes the focus (`PinPopover.holdNoFocus`), so with Full Keyboard Access on no comment
  shows a focus ring until the person moves into the popover. The
  field takes the keys when the person clicks into it. Esc closes an open popover before it closes
  the editor.
- An agent's pins come with `pins=` on `add` and `show` (`AgentPins.swift`, format in `docs/commands.md`),
  as its marks come with `marks=`: new pins, or answers added to the person's pins as the agent's
  comments. `AgentPin.join` turns them into the pins as they will be: new ones placed in px inside
  the image and numbered from `nextPin`, answers found by number or `id` among the numbered pins.
  Each comment holds the time of the call (`Pin.Comment.at`), and the session `session=` names and
  its name, `from=` (`Pin.Comment.session` and `sessionName`, from `AgentAuthor`). A name the
  session list gives after the comments joined is given to every comment of that session that has
  none, in the stored drawing, in the editor's when it is open there, and in their undo and redo
  steps (`Drawings.name`, `EditorCore.name`), as no step of its own. A person's edit of an agent's
  comment makes it theirs, without a session. `AgentPin.problem` refuses a list
  that names a pin the drawing lacks or overflows 99, before anything is shown or written. With
  `show` as with `add`, they join the drawing at once, as one undo step with the marks.
- Who wrote a pin's first comment is its maker (`Pin.maker`, `PinMaker`), and decides its colour
  everywhere, renderings included. A person's pin is in `ui.personColor`. An agent's is in its
  brand's colour (`Agent.brandColors`): Claude's is the fill of `claude.svg`, `#d97757`, and
  Codex's is black, as its one-colour logo is. Another agent's pin is in `ui.agentColor`.
  `MarkStyle.painting` swaps the brand in for the agents' colour, so every drawer keeps taking
  `.agent`. On screen (`PinFace`), a person's pin wears its number. An agent's pin wears its logo
  in the words' colour, or the first letter of its name when the bundle has no logo for it, or
  `Agent.fallbackSymbol` when it gave no name. A person's pin an agent answered also wears a dot
  in that agent's colour with its logo, on the rim across from the tip (`Pin.answeringAgent`).
  Copy, Send and Stitch draw a number on every pin and no dot, so the picture matches the "Pin 3:"
  in the words beside it. A pin's row in a menu shows no dot either. A cluster keeps its numbers, in its pins' one maker's colour.
- In the editor, the pointer resting on a pin with a number grows it into a card (`PinHoverCard`),
  while no popover, menu or drag is under way. The card is the teardrop widened, its rim included,
  in the popover's glass: the tip stays its square corner and the other corners keep the teardrop's
  radius. Its top line is laid out as a comment's top line in the popover: the first writer's
  avatar, their name and how long ago, muted. Under it are the first comment's first line and the
  replies. A selected pin's ring is left off while its card shows, since the card covers the teardrop
  the ring goes round. A press on the card is a press on its pin's teardrop, which the card
  covers: a click opens the popover with any tool and a drag moves the pin. The card's panel takes
  the presses on the pixels it draws and hands them to the editor through `EditorView.take`
  (`PinCardRoom`, `EditorView.relay`), and a press on the card's shadow lands where it is. The second
  press of a double-click on the card is dropped, so it does not land on what was under the card.
  A press, an open popover or a parked editor takes the card away at once; during a press the panel
  stays, clear, until the release. The card stays while the pointer is on the pin or on the card,
  and goes back into its teardrop when it leaves both. A pin that was clicked grows no card again
  until the pointer has left it (`EditorPinUI.pressedPin`), so closing its popover does not bring the
  card straight back. VoiceOver reads the pin instead of the card. The card's width is `ui.pinHoverWidth`
  and it grows over `ui.pinHoverDuration`, which the motion setting scales. The card draws in a
  borderless panel of its own, a child of the editor's window at the
  toolbar's level, above the stack's column. So it reaches past the picture's frame over whatever is
  beside the editor, as the popover does. It grows the way the teardrop faces and turns back on an axis
  only where the screen's visible frame has no room that way. The glass blurs what is behind the panel.
- In the editor a pin is live ink's gel in its colour, the person's red or the agent's brand
  (`PinGel`, `InkGel.metal`). One gel layer holds every pin, outline and cluster of the editor,
  each shape carrying its own colour, so many pins cost one drawing a frame. What it wears is drawn over it (`PinLayer` without its body) and casts
  `ui.pinGelFaceShadow`. Its top rises from a `ui.pinGelBevel` bevel into a dome `ui.pinGelDome` of
  half its side across, and the pointer's light glints only on the bevel. A flat top lit from right
  above turned white and hid the number, and a glint on the dome crossed it. The dome shades the
  face, darker away from the light, by `ui.pinGelShade`, so the pin reads as round, and its edge is
  `ui.pinGelEdge` opaque over dark content, where live ink's translucent edge left the pin soft and
  let the content show through. Over light content its edge turns to its own colour at
  `ui.pinGelDeep`, chosen from the picture's brightness under it (`EditorPins.backdrop`). It draws
  on live ink's clock (`InkClock`), so it is lit from the pointer, and drifts and comes to rest as
  live ink does. An area's outline is a gel rod `ui.pinGelRod` wide in its pin's colour, one shape
  with its pin, or on its own while the pin is in a cluster. It shows only while its pin is hovered,
  selected, being placed or open (`EditorCore.outlinedPins`), and a closed area pin draws none at
  rest. The pin being placed and the open one keep their gel drifting (`EditorCore.activePins`)
  at the motion setting, so Reduce Motion stills it. The hover card and the popover have a gel rim
  `ui.pinGelRim` wide in the pin's colour (`PinGelRim`). The popover's follows the popover's outline,
  its arrow included: the rim covers the popover's frame and reads the outline from the shape layer
  AppKit draws the popover's glass with, and moves when that path changes (`PinGelRim.Edge.popover`).
  Before macOS 26 AppKit draws no such layer, and the popover has no rim, since a box round the body
  alone did not match the popover's shape. Cards, flights, Copy, Send and Stitch keep the flat pin, so
  a pin changes material as it lands in the editor and as it leaves. A rendering draws the area as
  a solid rectangle mark.
- A resolved pin's ask is done (`Pin.resolved`, `Pin.Resolution`). It keeps its number, place and
  comments, and is grey, the system grey `#8e8e93` (`PinShading.resolvedColor`): in the editor's
  gel, on cards and in flights, in its popover's and hover card's rims, and in menus. It clusters
  only with resolved pins, so a cluster is all grey or all in colour (`PinPlacement`). Under an
  open pin's field the popover has Resolve, which says Reply and Resolve while the field holds
  words. Either is one "Resolve" undo step, the words posted in it (`ComposerInput.resolve`). A
  resolved pin's popover opens on "Resolved by Claude, 1 min. ago" with Reopen
  (`PinResolveControls`), its comments in the secondary label colour, its field's placeholder
  "Reply to reopen". Reopen is one "Reopen" step, after any draft is posted. A new comment reopens
  the pin in its own step, since it asks again. The hover card adds "Resolved by …" after the
  replies. VoiceOver says "resolved" after a resolved pin's name, and offers Resolve or Reopen as an
  action on the pin. The canvas has no contextual menu, so neither is in one.
- Copy (Done, Cmd+C), Copy Drawing, a drag, a stitch's first copy and Send leave resolved pins out
  (`Drawing.handedOver`). A rendering, the clipboard's words, Send's line and `pins.json` then hold
  only open pins, and a drawing with no marks whose pins are all resolved copies the screenshot
  itself. Copied items pasted inside Vignette (`CopiedItems`) and a stitch's drawing keep resolved
  pins resolved.
- An agent resolves a pin with `"resolve": true` on an answer in `pins=`, or with `--resolve` on a
  reply, naming pins its `--comments` answer. The pin is then resolved by that agent, at the time of
  its comment (`AgentAuthor.resolution`, `Pin.answered`). An answer without it reopens a resolved
  pin. A new pin takes no `resolve`.
