# A pushed text mark wraps inside the image and is sized for it (2026-09-19)

Pete, on the first real push from an agent (2026-09-18): "your text got cut off. how can we avoid
that?"

The push was `[add] ok Agent strip labels, gap to the card.png agent=claude marks=3`: a rectangle,
an arrow, and a text at `x` 0.30 on a 900 x 1087 screenshot. The sentence was "16 pt between strip
and card now. Enough? Circle what to change."

Two separate defects were in that one line.

This note was written for the web editor, which the native editor replaced on 2026-09-22. The rule
and its numbers carried over to Swift, in `Sources/AgentMarks.swift` and `TextLayout` in
`Sources/MarkGeometry.swift`, and the sections below name the Swift constants. What the note says
about tldraw, the canvas and the web page's font is history.

## The text ran off the right edge

History: the web editor. `build` created the text shape with no `w`, so tldraw kept
`autoSize: true` and laid the sentence out as one line that grows to the right. Measured on the canvas, with the image 450 points wide:
the text started at 135 and was **830.9 points wide**, so its right edge was at **2.146** of the
image. Everything past 1.0 was cut off, because the export and the card's preview both take
tldraw's SVG within the image's bounds.

This is the defect Pete saw. On its own it explains the whole of it.

## The size did not follow the image

History: the web editor. `DEFAULT_SIZE` gives a text shape a fixed 24 points whatever the image is. In fractions of the
image's width that is:

| image | canvas | font at `DEFAULT_SIZE` | as a fraction of the width |
|---|---|---|---|
| 900 x 1087 crop | 450 x 543.5 | 24 pt | 5.33% |
| 5120 x 3325 capture | 2560 x 1662.5 | 24 pt | 0.93% |

The same sentence was **5.7 times larger** relative to the crop than to the capture. It did not
cause the cut-off, but it is why the crop's version was also unreadably large.

## The rule

A pushed text's font size is a fraction of the image's width, `AgentMark.textSize`, **0.022**. The
text's size in points is that many pixels divided by the drawing's point scale, so the letters are
the same fraction of the image whatever the display. The two ends of the same sentence after the
change, as measured on the web editor:

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
`TextLayout.margin` (0.02 of the width), and never narrower than `TextLayout.minimumRoom` (0.15 of
the width): a mark at `x` 0.92 would otherwise wrap into a column too narrow to hold a word. A `w`
the mark does name is used as it stands.

How tall the box turns out depends on where the words wrap and how wide the font draws them,
neither of which the agent that sent the mark can know, so the box is measured after it exists
rather than predicted, and then fitted in two steps.

**Widened until the height fits.** A narrow box and a long sentence make a column taller than the
picture, which the margin cannot cure by moving it. The box's area is roughly what the sentence
needs at its font size, so the width the height wants is about `w * h / room height`; wrapping is
discrete, so that estimate is measured again and repeated, up to `AgentMark.textFitPasses` (4) times. The
width stops at the room's own — the widest a box can be and still sit inside the image.

**Then moved inside.** To the margin on every side where there is room to spare. Where there is
not, the box goes against the image's own edge in that direction instead: a caption asked for at
`w` 1.0 already fits the image exactly, and moving it in by the margin would push its far end out.
Each direction decides on its own. A mark at `x` 0.92, `y` 0.90 lands at 0.831, 0.765, with its
bottom edge on the margin at 0.983.

**A sentence with no room even at the full width** is a real limit of the picture, not something
the app can fix. The box is left as wide as it can be, so the most of it shows, and the app writes
one `[marks] text too long for <name>: mark N is cut off at its edge` line. `[add]` still
answers `ok`, because the marks did land; the log line is what says one of them is cut. Without it
the agent that pushed the mark has no way to know, and that was the defect: a 205-character
sentence at `x` 0.88 on a 2800 x 600 image made a column **2.6 times the image's height**, ending at
2.69 of it, and the command said `ok`.

The margin is `TextLayout.margin` of the image's **width** on all four edges, so the inset is the
same number of points all round rather than the same fraction of two sides of different lengths.
On a wide short image that leaves proportionally less of the height, which is exactly why the
height is bounded rather than trusted.

Only text is widened. An agent chooses a rectangle's or an arrow's box itself and may mean it to
sit against an edge; a text mark's box is the app's to compute. On the web editor only text was
moved inside, too. The native editor moves every mark inside the image (`Mark.placed`), because no
mark may leave it; a rectangle already inside keeps its box.

## The measurement needs the font

History: the web editor. The native editor measures with Core Text and the system font, which is
always loaded. tldraw measures text with the font it will be drawn in. A page that has not drawn
text yet has not loaded that font and measures the fallback instead, which put the first pull-back of every launch a
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
