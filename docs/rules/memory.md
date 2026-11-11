# Memory

- Memory is bounded where images are held. `Thumbnailer` keeps decoded images under `budgetBytes`,
  least recently used out first, and screen-size flight decodes are dropped whenever the stack
  hides. Every image that reaches a card, a flight or the editor is decoded before it gets there
  (`Thumbnailer`), in the colour space of the screen it will be shown on (`space:`, from
  `NSScreen.colorSpace`). Core Animation does any work left at the first commit that shows an
  image, on the main thread: it decodes an `NSImage(data:)`, and it converts an image in any other
  colour space. That conversion cost 21 ms for a 3024 by 1964 sRGB image, and 0.05 ms once
  `Thumbnailer.converted(_:to:)` had redrawn it. A capture from the same display is already in that
  space; an agent's push, a stitch or a capture from another display can be in another. The redraw
  is 8-bit, so a deeper image is left as it is. A cache entry records the space it was decoded in,
  and a lookup in another space misses. Renderings and stitches read the file
  itself, so their output does not change. The editor shows the screenshot decoded no larger than
  the visible screen in device pixels, which is the same decode a flight asks for and is counted in
  the thumbnail cache's budget (both ask `Thumbnailer.screenPixels(on:)` and the screen's colour
  space); `editor.clear()` lets it and the marks' layers go when the annotator hides, and
  `removeCards` lets a card's marks go when it leaves the column. A card holds its own picture, out
  of the cache's reach, so a column of more than 100 cards lets the pictures of cards more than four
  viewports from the view go, 30 at a time, and takes them back within two: from the cache, or
  decoded on the thumbnail queue and given to the cards in one change (`CardPictures`). A card in
  the annotator, in a stitch, pressed, dragged, hovered or focused keeps its picture. Text bitmaps are capped by their
  owner's plan (the `MarkLayers` rule in `docs/rules/editor-and-drawings.md`), and renderings run one at a time (`RenderingQueue`). A
  stitch decodes one piece at a time and draws at the capped output size.
