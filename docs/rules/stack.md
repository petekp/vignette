# The stack

- The stack runs to the bottom of the screen and steps around the Dock. `StackLayout.area` builds
  one `StackArea` from the screen: `bounds` takes its sides and top from `visibleFrame` and its
  bottom from the screen's own `frame`; `safeBottom` is the height AppKit reserves for a bottom
  Dock, but only when the Dock's tiles reach into the column's strip of the screen. The column sits
  above the Dock, the newest card rests `ui.screenMargin` above its top edge, and the mask and the
  hair of alpha that catches clicks are lifted by the same number, so a click on a Dock icon under
  the column still reaches the Dock. The tiles' rect is Accessibility's (`Dock.tiles`, the Dock
  process's one `AXList`): `CGWindowListCopyWindowInfo` reports the Dock's window as the whole
  screen on macOS 15. Untrusted for Accessibility, the Dock is taken to span the whole edge.
  `annotatorRoom` and `annotationFrame` keep reading `visibleFrame`: the annotator must not go
  under the Dock. `docs/stack-dock-2026-09-18.md` has the numbers.
- A presentation keeps to one screen, and `ThumbnailController` pins that screen's display number
  (`pinnedDisplay`), never its `NSScreen`. AppKit makes new `NSScreen` objects when the screens
  change, a Dock that moves or hides included, and an old object keeps the visible frame it had.
  `screen` looks up the current object for the pinned display each time, so the stack, the dim and
  the annotator's re-fit read the visible frame as it is now. `AnnotationController` does the same
  with `zoomDisplay`. `scripts/check-screen-stores.py` fails any other stored `NSScreen` outside
  its `ALLOWED` list. That list names `TransitionLayer.screen` (`TransitionLayer.swift:71`), which
  reads only `frame` and is set again before every flight and swallow.
- A card in the stack and the same card in flight have to cast the same shadow. The column is
  masked with a fade over the panel's inset at each end (`StackView.column`), and the bottom fade
  starts below the newest card's shadow: solid for `StackLayout.cardShadowRoom` and fading over the
  rest of the inset. `StackLayout.inset` is therefore at least that room plus `shadowFade`, so a
  shadow bigger than `ui.panelInset` grows the panel around the column instead of being cut off.
  The flight's shadow is cast by the clipped image, before the ring, for the same reason.
- A card dragged out of the stack hands over to its drag image, and the drag image to the pour at a
  drop (`DropLanding`), with nothing changing in between. `DragSourceView.lift` draws the drag image
  with `CardView`'s views and modifiers: corners, shadow, marks and resting border, at the card's
  scale on screen and on its device pixels, in a clear margin that holds the shadow. The pour bends
  that same bitmap at that frame and draws no corners or shadow of its own. On screen the card casts
  one shadow from its image and matte together, and `ImageRenderer` casts one from each, so `lift`
  composites them first (`compositingGroup`). Compared through the window server, with the card
  pressed and a drawing on it, the two differ by 0.2 to 0.6 levels of 255 on average. The rest is
  one-pixel edge rows and a shadow up to 7 levels lighter beside the card. The drag image carries no
  hover dim and no buttons, so a press fades both off the card (`CardView.showsButtons`).
- The backdrop's progressive blur is a stack of masked NSVisualEffectViews with different radii.
  By default there is one, whose mask fades a single blur in from the strip's left edge, and no top
  fade, so the strip's top edge is crisp.
  The private CAFilter variableBlur ignores its mask when the backdrop renders in the window
  server on macOS 15, and a bare CABackdropLayer renders black. Do not retry. The band masks are
  one-pixel-tall bitmaps stretched to the strip, cached for the current width and band count;
  shading a drawing-handler image at the strip's full height on every show was measurably slow.
  A band mask carries no cap insets: NSVisualEffectView measures `capInsets.top` from the bottom
  and stretches the wrong row, which hid the blur. The strip ends at the menu
  bar's bottom edge, `visibleFrame.maxY` of its screen, which is also the column's top, and one
  gradient mask on the panel's content layer fades the blur and the tint in over its first
  `backdropTopFadeHeight` points. At 0 the content layer has no mask at all. Whether a layer mask
  over the effect views keeps their blur in the window server has not been checked on screen, so 0
  is the way back to a strip that certainly blurs. With the menu bar hidden the
  strip reaches the screen's top, and the menu bar slides down over it.
- Stitching from the stack is one motion, not a file appearing later. `ThumbnailController.stitched`
  takes the cards the image was made from out of the column, holds a slot for the new card at the
  bottom, and hands both to `TransitionLayer.converge`: the pieces fly into that slot while the
  finished image fades in under them. Both sets of cards sit in `model.forming` while their image is
  in the transition layer, so a slot keeps its place and draws nothing, and the image is never on
  screen twice. The watcher reports the file a moment later as usual; the card is already there, so
  `insert` ignores it, and with `annotateOnCapture` on that same report flies the new card into the
  annotator. With the stack closed (a `vignette://stitch` from a script) the stitched card comes up
  as the lone thumbnail with the Copied notice. Dismissing the stack mid-converge ends the pieces'
  flights with it, and the stitched card comes up the same way, so a stitch never finishes in
  silence. `Stitch.compose` lays the pieces out for the model that
  will read the result: it tries every column count and keeps the one that survives a vision
  model's resize best (`readerScale`, Anthropic's standard tier: a long edge of 1568 px and 1568
  patches of 28 px). The gap and the badges are fractions of the piece they are on,
  `ui.stitchLongSide` caps the output, and `[stitch] ok` reports the composed size and that scale.
  Each piece carries its drawing, the editor's own for the image open in it and the stored one
  otherwise, and `Drawing.draw` draws it into the piece's pixels as Done does, off the main thread.
  The stitch is a new image with no drawing of its own. `docs/stitch-2026-09-17.md` has the numbers;
  separate images are better when the model has to read the text.
- A sideways two-finger swipe over the corner moves the column with the fingers, and a release
  toward the screen's edge closes it (`StackSwipe`, a pure value, tested in
  `Tests/StackSwipeTests.swift`; `StackSwipeDriver` runs it). Each gesture locks to one axis once it
  has moved 3 pt, so a vertical scroll stays the column's scroll as it was. The column follows the
  fingers one to one toward the edge and resists away from it, never past `ui.swipeStretch` nor past
  the panel's room for the shadows (`StackLayout.pullRoom`). A
  release closes when it moves toward the edge at `ui.swipeSpeed` or more, or when the column is past
  `ui.swipeDistance` and is not moving back at that speed; any other release, and a cancelled
  gesture, springs back. The release speed is the fingers' movement over the last 80 ms, and it
  carries into the spring. Momentum after a sideways gesture moves nothing, a mouse wheel (no phase)
  only scrolls, and a gesture that began before the corner was there only scrolls. Fingers put down
  on a column springing back catch it. The fingers move the column whatever `ui.motion` says; the
  springs use `relayoutDuration` and `slideOutDuration` from `Settings.motionUI`. The close is
  `dismiss(by: .swipe)`, which `[stack] dismissed by=swipe` logs and which gives the focus back as a
  click outside does. A selection does not stop it: the strip leaves with the column, as it does on a
  click outside. Nothing swipes while the annotator has a card or a card is being dragged out: a sideways
  gesture then scrolls by its small vertical part. On the
  close, `StackModel.swipeExit` carries the whole column, strip included, on one spring
  (`model.swipe`) in place of the slide-out's staggered one per card, and stays on until the column
  is back at 0, so a corner that comes up mid-exit springs back from where it is. While `model.swipe`
  is not 0 the lone thumbnails draw the panel's hair of alpha, so the scroll events keep reaching the
  panel as the card moves out from under the pointer. `[state]` gives the offset as `stack.swipe`.
- The stack panel is non-activating but can become key (`ThumbnailPanel.acceptsKeys`). Never
  call `NSApp.activate` for it; the user's app must stay frontmost. A `.help` tooltip never
  shows in the stack: AppKit shows a window's tooltips only while its app is active, unless the
  window sets `allowsToolTipsWhenApplicationIsInactive`, which the panel does not. Text the user
  must see there is drawn, like a greyed strip row's reason (`UnavailableReason`).
- The app the focus goes back to is the app that was in front when Vignette took the keys, so
  closing Vignette leaves the screen as Vignette found it. `FocusReturn` follows every activation
  of a regular app other than Vignette and System Settings. It does not judge how that app came
  forward, by the person's hand or on its own: macOS does not say, and a wrong guess sends the
  person to an app they had left (`docs/focus-return-codex-2026-11-18.md`). Each hand-back logs
  `[focus] <reason>: returned to <app>, in front since <time>`, the time that app last became
  active, or `in front when Vignette launched`. The hand-back is the only time Vignette brings
  another app forward on its own; the rest open what the person asked for.
  `scripts/check-app-activation.py` holds that.
- `CornerPresentation`, a pure reducer, decides four things about the corner. It decides whether
  the corner shows lone thumbnails or the stack, and when the panel takes the keys and gives them
  up. It decides when the backdrop and the watch for a click outside are on. And it decides when
  the focus goes back (`FocusReturn.restore`): to the Vignette window the session began in, when
  that was Settings, setup or the tweaks, and otherwise to the app before Vignette. `CornerKeys`
  runs its effects. It holds the panel's keys, the backdrop and the `OutsideClick` privately, so
  `ThumbnailController` can only send it events (`keys.send`). `acceptsKeys` can be set only in
  `CornerKeys.swift`. Every event with effects logs one `[corner] <event> -> <mode> effects=…`
  line. `Tests/CornerPresentationTests.swift` has the table and a random-sequence test of the
  invariants. Esc, a click outside and a swipe away reach it as dismissals. Esc clears a selection first, and the
  controller does that itself. The editor is open to it exactly while the annotation run is active: the controller
  sends `editorOpened` and `editorClosed` on that edge, with the run's `RunEnding`.

  The rule is that the backdrop goes with the keys. The stack has both, and lone thumbnails have
  neither. `CornerKeys` shows the backdrop and starts the watch for a click outside whenever an
  event makes the stack, and stops both whenever one ends it, so no effect can split them. A card that arrives on its own, from a capture or an agent's push, never takes a key
  from the app the person is typing in. Only a hand makes the stack: the shortcut, a selection in
  the corner (`.selected`), or Esc out of the editor while other cards are in the corner. That Esc
  makes them the stack once the card lands (`cardLanded`). Becoming the stack by any of these takes
  the screen from live ink (`onTakesScreen`), and the corner's own cards becoming it logs
  `[stack] corner became the stack`.

  The shortcut takes the keys at the press, before the folder is listed (`holdKeys`), so an Esc
  pressed while the stack is still coming closes it. It brings the panel up if the panel is down.
  The panel can be down while the corner still counts as lone thumbnails, as after a lone card's
  editor closes. `[stack] keys held` logs the press. The next `[stack] keys … after=<ms>` line gives
  the time from the press until the stack, with its cards, takes the keys. A zoomed editor springs
  back to the fit before it closes, so the listing can finish first; the stack then focuses a card
  only once the opened card lands. Over lone thumbnails, or over a stack the corner became, the shortcut keeps
  the cards on screen and brings the older ones in above them (`StackEntrance`). The next press
  closes it.

  While a card is in the annotator the panel gives up the keys so typing reaches the editor. It
  gives them up at `editorOpened`, which `perform(.prepare)` sends right after the annotator's
  window has taken them, so the keys pass from one to the other instead of being nobody's for the
  length of the flight. `RunEnding` says how the run ended, and so where the keys go next. The
  shortcut keeps them for the stack. Any other hand sends the focus back, and a stack takes the
  keys again when the card lands.
- Which card a key acts on is one variable, `model.focused`. The stack focuses the newest card the
  moment it takes keys (the `takeKeys` effect), or the card back from the annotator, so arrows, Space
  and Return act on a card without a first click. While the stack has the keys and no card is in
  the annotator, the pointer moves the focus too: moving onto a card focuses it, and leaving it
  leaves the focus there. While the wheel moves the column, the hover and the focus stay; 0.15 s
  after it stops, the card under the pointer takes both (`docs/hover-hold-2026-10-30.md`). A
  shortcut runs on the selection, else on the focused card (`targetCards`). The ring shows the
  focus: accent on a selected card, white on a focused one. It grows out of the card's resting
  border and back into it, and the selection circle fades in with it.
- Thumbnails in the corner show the selection circle once there are two or more of them
  (`StackModel.offersSelection`), except while one is in the annotator. Selecting there makes the
  corner the stack with the cards it holds: every move of the selecting drag sends `.selected`, and
  the reducer takes the first. The stack takes the keys and the backdrop, a click outside closes
  it, and it stops timing out.
- The panel widens to the left while cards are selected, to hold the selection strip
  (`StackLayout.stripPlacement` places it, `panelSize(viewport:showsStrip:reveal:)` makes the room:
  the icon column, the gap to the cards, and the room the labels grow into, whether they are out or
  not). Its right edge never moves, so the cards stay where they are. The gap to the cards is
  `ui.selectionStripGap`, measured from the widest selected card (`docs/selection-strip-2026-09-18.md`).
  Only the column carries the hair of alpha that catches clicks and scrolls; the strip's side of
  the panel stays clear, so a click there still reaches the window underneath.
- The strip's labels are out for as long as a selection exists, whichever hand built it: a selection
  is the moment the rows' names and shortcuts are wanted, and a strip that folded back to icons when
  the pointer moved onto a card read as the strip losing interest. Each row draws its shortcut after
  the label from `ShotAction.Key.glyphs`, and `stripReveal(rows:)` measures both, so the panel's
  room holds them. Copy on a card still reveals on hover and grows to the right from an icon that
  does not move; the strip keeps its right edge and grows to the left, so a label never covers a
  card. A row is one button, icon and label together. The strip stands aside while the annotator has
  an image, since it hangs inside the room the frame may grow into: the two places that ask for its
  placement refuse (`ThumbnailController.stripFrame` and `StackView.stripPlacement`), never
  `showsStrip`, which sizes the panel, because the panel's window is not resized while a card is in
  the annotator. The selection is untouched and the strip springs back when the annotator closes.
  `[state] stack.strip` is the grown frame, null while a card is in the annotator.
- The recent stack narrows to make room for the annotator. One number says how wide it is drawn:
  `StackLayout.widthScale`, 1 at rest and never below `ui.stackMinScale`. The cards are drawn at
  that width (`drawn`) and the column with them; their right edge does not move. The panel is always
  the size the stack needs at rest, and transparent outside the column, so nothing has to be resized
  while the stack narrows; the scroll follows the column's height so the same cards stay in view and
  the column comes back to the same place. The rect the annotator fits and grows within is the
  visible frame less the strip the stack keeps at its narrowest, and a gap beside it
  (`annotatorRoom`), so the frame can never reach the cards however far a zoom grows it. The gap is
  `ui.annotationToolbarGap`, the margin the toolbar keeps from the frame and from the bottom of the
  screen, so a zoomed frame stops the same distance from the widest card as from the toolbar. The
  widest card is as wide as the column, so the column's edge is that card's edge. The hair of alpha
  that catches clicks and scrolls beside the cards reaches the panel's inset (19 pt by default) left of the
  column, but while a card is in the annotator no further than that gap (`catchReach`), since the
  stack's panel is above the annotator and would take the presses on the frame's edge. In between,
  every time the annotator's frame moves the stack takes the widest value that still clears it by
  the gap (`widthScale(clearing:visibleFrame:)`). Opening and closing spring it through
  `ui.relayoutDuration`; a zoom sets it straight, in the same turn as the frame. Only the recent
  stack does this: a lone thumbnail alone in the corner leaves the panel when the annotator opens,
  one of several keeps its slot and the corner does not narrow, and a `vignette://annotate` with no
  stack showing gets the whole visible frame.
  `docs/stack-room-2026-09-17.md` has the numbers, and `docs/stack-narrowing-2026-09-23.md` what a
  frame of the narrowing costs and the options for making it cheaper.
- Cmd+Z and Shift+Cmd+Z in the stack undo and redo Delete and Stitch. `docs/rules/undo-timeline.md` has
  their rules.
- The column reaching back past its first `recentCount` to older screenshots, and building only
  the cards near the view, have their own rules in `docs/rules/stack-column.md`. Read it before
  changing `StackView.swift`, `OlderShots.swift`, `CardPictures.swift`,
  `ScreenshotWatcher+Older.swift`, `StackLayout+Slots.swift` or `ThumbnailController+Older.swift`.
- A card joining the open stack is not animated as a layout change. `ThumbnailController.shiftUp`
  changes the layout and grows the panel with animations off, lifts every card that was there back
  to where it was drawn (`StackModel.lift`), and springs the part of each lift still drawn
  (`StackModel.liftFraction`) to 0 on the next turn. The panel
  grows at its top edge at once, and SwiftUI animates in coordinates whose origin is that edge, so
  an animated insert moved the cards half a slot in one frame and carried the new card along with
  the column. The new card slides on the lone thumbnail's spring, after `CardView.insertLead`, so it
  reaches the column's width only once the card above has cleared its slot.
  `docs/stack-insert-2026-09-26.md` has the frames.
- A card's thumbnail fills the card, so a screenshot whose shape differs from the card's box hangs
  outside the card's frame, and the clip that hides it does not shrink the hit area. The
  `contentShape` in `CardView` holds each card's hover and clicks to its own frame; without it a
  hovered card, whose slot `zIndex` raises for its hover scale, takes them from the card below.
