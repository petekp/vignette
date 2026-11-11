# The long column

The rest of the stack's rules are in `docs/rules/stack.md`.

- The recent stack reaches back past its first `recentCount` cards, to the oldest file in the
  folder. A scroll toward older cards that brings the view within 1.5 viewports of the column's top
  asks for the next `recentCount` screenshots older than the oldest card (`OlderShots`,
  `ThumbnailController+Older.swift`). Up arrow on the top card asks too, and the focus moves on to
  the first new card once the chunk is in. The order is the index's, read by
  `ScreenshotWatcher.older(after:top:shown:limit:)` on a background queue, which also looks up each
  file's header. The main thread never lists the folder: it runs the person's filter
  (`AppDelegate.isShown`), then makes the chunk's cards and lays out the column. The first chunk
  starts after the top card, so a card that joined the bottom with an old date moves nothing. Each
  later chunk starts after the last file the one before took (`ScreenshotWatcher.Place`, a date and
  a name), so a file removed meanwhile does not move it. Every change to `StackModel.scroll` is
  checked on the next turn (`StackModel.scrolled`), so a drag-select's auto-scroll loads chunks too.
- A chunk joins the column in one update with animations off, as `present` changes it. The scroll
  counts from the newest card, so the cards in view do not move while the column grows at its top.
  The new cards slide in from the screen's edge, staggered from the lowest, as cards entering above
  a column do. `[stack] older cards=<n> column=<n>` logs each chunk, with `reached-oldest` on the one
  that reached the oldest file. After it nothing more loads, and nothing on screen says there is
  more. Only the stack the shortcut opened loads older cards; the corner's own cards made into the
  stack by a selection are the latest captures and nothing more. Showing a new column starts over
  (`newColumn`): the next shortcut opens the newest `recentCount`, and a chunk still being read is
  dropped. Once a chunk is asked for, a new capture no longer drops the oldest card
  (`OlderShots.columnLimit`), since the oldest are the cards the person scrolled to. Cmd+A selects
  every card in the column, chunks included, and nothing that is not loaded. A column longer than
  100 cards and `recentCount` lets pictures go far from the view (`CardPictures`, the memory rule). `[state]
  stack.older` gives `loading`, `reachedOldest` and `added`. Only the newest `recentCount` cards
  decode their pictures into `Thumbnailer`'s cache (`ThumbnailController.cachesPicture`): a chunk's
  cards, a restored picture and a settings change's decode past them go outside it, so scrolling
  back through the folder does not push the newest cards' pictures out before the next open.
- The column builds a card only while its slot is within one viewport of the view (`CardColumn` in
  `StackView.swift`, `StackLayout.cards(meeting:sizes:lifts:)`). Every other card keeps its slot in
  the `VStack` as an empty frame of its size, so each card sits where a column of built cards puts
  it and `StackLayout.cardFrame` holds for every card, built or not. The view is read at the
  scroll, the lift and the width drawn in each frame, which SwiftUI hands the column while they
  animate (`Animatable`), so a spring that carries the column far, a stitch's or a capture's,
  builds the cards on its way before they come into view. A capture's lifts are one fraction that
  springs (`StackModel.liftFraction`), and the column draws each card its lift times that fraction
  below its slot, so a card built in mid-spring starts where the others are. A removal's relayout
  is a layout animation the column cannot read, so `ThumbnailController.removeCards(where:)` keeps
  built every card whose slot passes through the view while it runs (`StackModel.carried`).
  `StackModel.keptBuilt` keeps a card built wherever it is: in the annotator or a stitch, pressed,
  dragged out, hovered, focused, entering, showing a notice, carried by a removal, or carrying a
  drag-select's gesture (`sweepCard`). A card is built and let go with no transition, out of view. The slot carries the hover's `zIndex` and the insert and remove
  transitions. A slide-out staggers from the lowest card in view (`CardView.place`), so a column
  scrolled far up leaves at once. A frame of the scroll or the narrowing costs the cards built,
  about twenty, and an empty slot per card beyond: 2.4 ms and 6.1 ms at 300 cards
  (`docs/stack-narrowing-2026-09-23.md`).
