# A pushed text mark wraps inside the image and is sized for it (2026-09-19)

Pete, on the first real push from an agent (2026-09-18): "your text got cut off. how can we avoid
that?"

The push was `[add] ok Agent strip labels, gap to the card.png agent=claude marks=3`: a rectangle,
an arrow, and a text at `x` 0.30 on a 900 x 1087 screenshot. The sentence was "16 pt between strip
and card now. Enough? Circle what to change."

Two separate defects were in that one line.

## The text ran off the right edge

`build` created the text shape with no `w`, so tldraw kept `autoSize: true` and laid the sentence
out as one line that grows to the right. Measured on the canvas, with the image 450 points wide:
the text started at 135 and was **830.9 points wide**, so its right edge was at **2.146** of the
image. Everything past 1.0 was cut off, because the export and the card's preview both take
tldraw's SVG within the image's bounds.

This is the defect Pete saw. On its own it explains the whole of it.

## The size did not follow the image

`DEFAULT_SIZE` gives a text shape a fixed 24 points whatever the image is. In fractions of the
image's width that is:

| image | canvas | font at `DEFAULT_SIZE` | as a fraction of the width |
|---|---|---|---|
| 900 x 1087 crop | 450 x 543.5 | 24 pt | 5.33% |
| 5120 x 3325 capture | 2560 x 1662.5 | 24 pt | 0.93% |

The same sentence was **5.7 times larger** relative to the crop than to the capture. It did not
cause the cut-off, but it is why the crop's version was also unreadably large.

## The rule

A pushed text's font size is a fraction of the image's width, `PUSHED_TEXT_SIZE` in
`web/src/config.ts`, **0.022**. The shape carries that as tldraw's `scale`, which multiplies both
the font and the wrap width, so `props.w` is the box divided by the scale and `w * scale` is the box
on the canvas. The two ends of the same sentence after the change:

| image | scale | box | lines | right edge |
|---|---|---|---|---|
| 900 x 1087 crop | 0.4125 | 0.679 of the width | 2 | 0.979 |
| 5120 x 3325 capture | 2.3467 | 0.679 of the width | 2 | 0.979 |

The same fraction of either image, which is what "reads the same on a crop and a full capture"
means: an image is looked at as a whole, in a card, in the annotator, or in an exported PNG, so a
mark that is the same fraction of it is the same size to the eye.

It does not follow the screenshot's own content. A 900-pixel crop of a Retina screen shows its UI
text at about 26 image pixels; the rule gives the annotation 20. On a full capture the annotation is
the larger of the two. Nothing in a PNG says how big its content was on the screen it came from, so
no rule reading pixel sizes can match both.

## The box

`w` on a text mark is the box its words wrap in, a fraction of the image like every other number,
and it is optional. Without it the box is the room between `x` and the right edge less
`PUSHED_TEXT_MARGIN` (0.02 of the width), and never narrower than `PUSHED_TEXT_MIN_WIDTH` (0.15 of
the width): a mark at `x` 0.92 would otherwise wrap into a column too narrow to hold a word. A `w`
the mark does name is used as it stands.

The box is then pulled back inside the image, to the same margin on every side. How tall it is
depends on where the words wrap and how wide the font draws them, neither of which the agent that
sent the mark can know, so the box is measured after it exists rather than predicted. A box with no
room to spare rests against the top left margin: the start of the text is what has to show. A mark
at `x` 0.92, `y` 0.90 lands at 0.831, 0.765, with its bottom edge on the margin at 0.983.

Only text is pulled. An agent chooses a rectangle's or an arrow's box itself and may mean it to sit
against an edge; a text mark's box is the page's to compute.

## The measurement needs the font

tldraw measures text with the font it will be drawn in. A page that has not drawn text yet has not
loaded that font and measures the fallback instead, which put the first pull-back of every launch a
few per cent wrong — enough that the test caught a box 5% past the bottom edge. `build` therefore
awaits `editor.fonts.loadRequiredFontsForCurrentPage()` before it measures.

What that costs the canvas borrow, measured on the 5120-pixel capture with the three marks
(`[web] TIMING` on an instrumented build, removed before the commit):

| push | pull-back | colours | rendering | `add` in all |
|---|---|---|---|---|
| first after launch, with text | 5 ms | 260 ms | 551 ms | 844 ms |
| same marks, warm | 2 ms | 272 ms | 314 ms | 608 ms |
| the same without the text mark | 0 ms | 261 ms | 252 ms | 527 ms |

The pull-back and its font wait are 0 to 5 ms. The font itself is served from `web/dist` on the
loopback server, and `render` already waited 250 ms for it later in the same build
(`waitForEmbeddedFonts`), so the wait moved earlier rather than being added. A build is still
refused while anything else owns the canvas, and this does not make that likelier.

## The colour heuristic

It runs on the box the mark is drawn in, so a wrapped text is sampled over the pixels it really
covers instead of over a one-line box that ran off the image. Verified on a fixture with a red band
across it: the same sentence over the band came out **yellow**, and over the dark terminal below it
**red**.
