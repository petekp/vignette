# Stitch layout for the model that reads it (2026-09-27)

Pete: "let's re-evaluate the stitch layout algorithm and see if we can find a better approach, while
factoring in what image models would find easiest to work with."

This is a proposal. Nothing in `Sources/` or `Tests/` has changed.

## Recommendation

Make three changes, in this order.

1. **Aim the layout at Claude Code on a current model, not at the standard tier.** Claude Code
   shrinks a pasted or read image to 2000 px on its long side. The model then applies the
   high-resolution tier's limit of 4784 visual tokens. `Stitch.readerScale` models the standard
   tier instead, which only Claude Haiku 4.5 and models before Claude 4.7 still use.
2. **Replace the uniform grid with rows that wrap in reading order.** Each piece keeps its own
   pixels. Each row is only as tall as its own tallest piece and only as wide as its own pieces. A
   whole layout can also turn 90 degrees and become columns. Today every column is as wide as its
   widest piece and every row as tall as its tallest, so one full-screen capture among crops leaves
   a large empty cell. For pieces that are all the same size, nothing changes.
3. **Say when the stitch is too small to read.** If the smallest UI text would reach the model
   under 10 px tall, say so when the stitch is made, and point to copying the images separately.
   No layout rescues three full-screen captures: their text reaches Claude Code at 7.3 px as a
   stitch and at 14.6 px as separate images.

What this changes:

- **For the person:** a stitch of mixed sizes becomes more compact, with less empty space around
  small crops. A stitch that a model can't read comes with a warning, so the person can choose
  separate images before pasting.
- **For the model:** text in mixed-size stitches arrives up to a third larger. Examples: 7.8 px to
  10.3 px for a mix of five, and 18.4 px to 22.0 px for a window with three crops. Badge 1 still
  sits at the top left, and the numbers still run in reading order.

Rejected:

- **Justified gallery rows.** They shrink the pieces that matter most.
- **Masonry.** It breaks reading order for at most 1 px of gain.
- **Scaling each piece by its DPI.** The file doesn't say what the display was.

Details for each are below.

## What the readers do

Retrieved 2026-09-27. Every size below counts pixels in the file.

| Reader | What it does to an image | Source |
| --- | --- | --- |
| Claude, standard tier (Haiku 4.5, models before Claude 4.7) | Fits the image within a long edge of 1568 px and 1568 tokens of 28 x 28 px | Anthropic vision docs |
| Claude, high-resolution tier (Claude 4.7 and later: Opus 5.5, Sonnet 5, Fable 5.1) | Fits the image within a long edge of 2576 px and 4784 tokens | Anthropic vision docs |
| Claude Code, before the model sees it | Scales a pasted image, or one opened with Read, to 2000 px on its long side | Claude Code changelog v2.1.126, t3code issue #13647 (2026-09-25) |
| Claude API, more than 20 images in one request | Rejects any image over 2000 px on a side | Anthropic vision docs |
| OpenAI, patch models (gpt-5.x, gpt-6-astra), `detail: high` | Allows up to 2500 patches of 32 x 32 px, with no separate limit on the long edge | OpenAI images and vision guide |
| Gemini 3 | Gives each image a fixed budget: 1120 tokens by default, 2240 at `ultra_high` | Gemini media resolution docs, updated 2026-09-23 |

Anthropic's resize rule is exact and published: a binary search for the largest size that fits
both limits, rounding half to even. My model of it reproduces the docs' examples:

| Input | Docs say | Model gives |
| --- | --- | --- |
| 1920 x 1080 on the standard tier | 1456 x 819 | 1456 x 819 |
| 3840 x 2160 on the high-resolution tier | 2576 x 1449 | 2576 x 1449 |
| 1075 x 1520 on the standard tier | 924 x 1307 | 924 x 1307 |

**Claude Code's reader is effectively a 2000 px square.** An image 2000 px long stays under 4784
tokens until its short side passes about 1850 px. So for Claude Code the long edge is almost always
the limit, and the best composition is close to square. The standard tier's best shape is about
2 : 1. OpenAI's best shape is any shape, because only the area counts. Where these disagree, the
layout should follow Claude Code, because that is where Vignette's skill and Send deliver.

Gemini 3 documents its token budgets but not the pixel sizes behind them, so it isn't modelled
here.

## What the research says

- **Text under about 8 px is not read.** Balakrishnan et al. (Cisco, ICLR 2026 workshop, arXiv
  2604.12371, 2026-04-15) rendered text at 6 to 28 px on a 1024 x 1024 image. They tested GPT-4o,
  Claude Sonnet 4.5, Mistral-Large-3 and Qwen3-VL-4B, and measured whether each model followed the
  text. The rate was "near-zero at 6px" and rose steeply to a plateau at 10 to 12 px: "The critical
  threshold appears to be around 8–10px, where VLMs begin reliably reading the embedded text." A
  font size in px is the em, so it matches this doc's "text px". The 10 px threshold below comes
  from this study.
- **Closed models read a composite worse than separate images.** RealBench (arXiv 2509.17421,
  2025-09-22): "closed-source models supporting multi-image input generally perform worse on
  composite images than when directly inputting multiple individual images." MIRB (arXiv
  2406.12742, June 2024) found the same, as the 2026-09-17 note says. Das et al. (arXiv 2601.07812,
  2026-01-12) found open models about equal or slightly better on grids. They traced multi-image
  losses to sequence length, not to the number of images.
- **Numbered labels are the right way to name pieces.** Anthropic's guidance for several images is
  to label each one (`Image 1:`, `Image 2:`). Inside a single image, the badge does that job, and
  it matches the number on the card's selection circle. Set-of-Mark prompting (Yang et al., arXiv
  2310.11441, 2023-10) showed that numbers drawn on regions let GPT-4V refer to them reliably. So
  keep the badges as they are.
- **Vendors say to make text bigger.** Anthropic: "If the image contains important text, make sure
  it's legible and not too small," and consider pre-resizing or cropping. OpenAI: "Enlarge text
  within the image to improve readability."

## How the current layout does

The inputs are realistic sets of 2 to 8 pieces:

- full-screen captures on this Mac (3024 x 1964) and on a 16-inch Mac (3456 x 2234)
- browser windows (1760 x 1080)
- tall narrow captures (700 x 2200, 800 x 2000)
- small crops (400 to 1000 px)

Text is 11 pt UI text on a 2x capture, so 22 px in the file. Each column in the table below is the
text height the model sees after both resizes: the stitch's own 4096 px cap (`ui.stitchLongSide`),
then the reader's. Under 10 px, the model is unlikely to read it.

| Set | Claude Code, current | Claude Code, wrapped rows | Claude Code, justified rows | Claude Code, masonry | Claude Code, separate images | Standard tier, current | Standard tier, wrapped rows | Standard tier, separate images | OpenAI high, current | OpenAI high, wrapped rows | Empty area, current | Empty area, wrapped rows |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2 full screens 3024x1964 | 10.9 | 10.9 | 10.9 | 10.9 | 14.6 | 6.8 | 6.8 | 10.0 | 9.7 | 9.7 | 5% | 5% |
| 3 full screens 3456x2234 | 6.4 | 6.4 | 6.4 | 6.4 | 12.7 | 4.9 | 4.9 | 8.7 | 7.0 | 7.0 | 5% | 5% |
| 4 windows 1760x1080 | 12.3 | 12.3 | 12.3 | 12.3 | 22.0 | 8.6 | 8.6 | 17.5 | 12.3 | 12.3 | 5% | 5% |
| 6 windows 1760x1080 | 12.2 | 12.2 | 12.2 | 12.2 | 22.0 | 7.0 | 7.0 | 17.5 | 10.1 | 10.1 | 4% | 4% |
| full screen + crop 600x400 | 12.0 | **14.4** | 7.3 | 14.4 | 14.6 | 9.0 | 8.9 | 10.0 | 12.9 | 12.9 | 15% | 16% |
| full screen + tall 800x2000 | 11.4 | 11.4 | 11.2 | 11.4 | 14.6 | 8.6 | 8.6 | 10.0 | 12.4 | 12.4 | 4% | 4% |
| 3 tall 700x2200 | 19.4 | 19.4 | 19.4 | 19.4 | 20.0 | 11.1 | 11.1 | 15.7 | 16.0 | 16.0 | 4% | 4% |
| mix of 5 (full screen, window, tall, two crops) | 7.8 | **10.3** | 4.3 | 9.1 | 14.6 | 6.1 | 6.5 | 10.0 | 8.7 | 9.3 | 33% | 23% |
| 8 crops 560 to 1000 wide | 18.2 | **19.8** | 16.8 | 19.3 | 22.0 | 11.4 | 11.4 | 22.0 | 16.4 | 16.4 | 27% | 28% |
| window + 3 crops | 18.4 | **22.0** | 17.8 | 18.3 | 22.0 | 12.2 | **14.0** | 17.5 | 17.6 | **20.1** | 32% | 12% |

The table shows four things:

- **For pieces of one size, the current grid is already the best layout.** Every alternative ties.
- **All the gains are on mixed sizes,** where a column as wide as its widest piece wastes a third of
  the picture.
- **No layout rescues many full-screen captures.** The piece count is what shrinks the text.

Here is text height in Claude Code with wrapped rows, by piece count:

| Pieces of one kind | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|
| full screen 3024x1964 | 10.9 | 7.3 | 7.1 | 6.9 | 6.9 | 5.5 | 5.5 |
| half screen 1512x1964 | 14.1 | 11.0 | 11.0 | 9.5 | 9.5 | 7.3 | 7.3 |
| window 1760x1080 | 19.8 | 13.2 | 12.3 | 12.2 | 12.2 | 9.9 | 9.9 |

- **On the standard tier, most stitches fall below 10 px.** Anyone pasting into Haiku gets
  unreadable text from almost any stitch of full screens.

## The alternatives, and why each won or lost

- **Rows that wrap in reading order (recommended).** Pieces go left to right and wrap to a new row,
  keeping their own pixels. The same search runs a second time turned 90 degrees, as columns that
  wrap top to bottom, and the better of the two wins. On ties, rows win, since rows are the usual
  reading order. The wrap width is chosen by trying every width a run of consecutive pieces could
  make, and scoring each layout with Claude Code's reader, then the standard tier. This greedy
  search matched an exhaustive search of every row break, and of every two-level nesting, on all
  ten sets. It scales to any number of pieces, where an exhaustive search does not (2^(n-1)
  layouts). Deeper nesting, such as a row whose cells are columns of rows, gained another 0.6 px
  on two sets. It isn't worth a reading order that has to be explained.
- **Justified rows (rejected).** A photo gallery scales every piece in a row to one height and
  every row to one width. That leaves no empty space, but it scales each piece differently, so the
  smallest text shrinks. With a full screen and a 600 x 400 crop, the crop is scaled up to fill the
  width, and the full screen's text drops from 14.4 px to 7.3 px. A model needs the smallest text
  to be readable, not a tidy picture.
- **Masonry (rejected).** Each piece goes into the shortest column. That gained 0.5 px over
  wrapped rows on one set and lost on the others. It also breaks reading order: badge 3 can sit
  above badge 2.
- **Scaling each piece so its text matches (rejected for now).** A 1x capture from an external
  display, beside a 2x one, has half-size text. Laying pieces out in points would bring the 1x
  piece's text from 10.8 px to 14.5 px and the 2x piece's from 21.6 px to 14.5 px. But the file
  can't say which display a capture came from. The six most recent captures in Pete's folder, all
  taken on a Retina display, report `dpiWidth: 72`. Without a reliable scale this would guess.
- **Pre-resizing to the reader's size (rejected).** Drawing the stitch at exactly 2000 px would
  save one resample. The stitch is also a file the person keeps, and the 2026-09-17 note's reason
  for `ui.stitchLongSide` still holds.
- **A gap of one patch after the resize (not tested).** After Claude Code's resize, the current
  gap is often under one 28 px patch, so one patch can straddle two screenshots. No study measures
  whether that matters. Leave it unless a real model test shows it does.

## Implementation sketch

`Sources/Stitch.swift`:

- **Replace the reader.** Change `readerLongSide`, `readerTokens` and `readerScale(_:)` to model
  Claude Code: scale to a long edge of 2000, then fit within 2576 px and 4784 tokens, using
  Anthropic's binary search. Keep a standard-tier function to break ties. Say in the comment which
  client and tier these numbers come from, since Claude Code's 2000 px is a client behaviour that
  can change.
- **Replace the layout search.** Swap `layout(_:)` and `layout(_:columns:gap:)` for the wrap
  search.
  - For each orientation, and each candidate width, fill rows in order and record every piece's
    frame.
  - Pieces sit at the top of their row and rows start at the left edge, so piece 1 is always at
    the top left.
  - Keep `gap(for:)` and `badgeDiameter(for:)` as they are.
  - `Layout.columns` becomes a description of the rows, such as `rows 1/3`.
- **Report text size.** Add `textHeight`, the smallest 22 px text as it reaches the reader, to
  `Composition`.

`Sources/AppDelegate.swift`, in `finishStitch`:

- Log the new fields: `[stitch] ok … rows=1/3 textPx=22.0 readerScale=…`. This changes a log line
  that scripts can read, so it needs Pete's approval. `columns=` goes.
- When `textHeight` is under 10, add a line to the stitch's feedback. The draft copy needs a
  refine-prose pass and Pete's approval. Draft: "Stitched 3 images, copied. The text may be too
  small for a model to read; copy them as separate images instead."

`Tests/StitchTests.swift`:

- `testTheLayoutMatchesTheTableItWasChosenFrom`: the table changes. It will pin the layout and
  scale for the new reader.
- A new case for mixed sizes: a window with three crops gives rows of 1 then 3, with no piece
  scaled. This catches the failure the current grid has.
- A reading-order check: frames run left to right and then down, and piece 1 is at the top left.
  This matters because the search now reorders rows and columns.
- `testPiecesAreDrawnInOrderEachWithItsOwnBadge` and the drawing test stay as they are, since
  pieces are still drawn at their own scale.

Risks:

- **Stitches of equal pieces keep their shape, but the numbers change.** The reported
  `readerScale` changes because the reader changes.
- **The reader model can drift.** If Claude Code stops capping at 2000 px, the layout is still
  valid but no longer tuned. The reader limits are constants in one place.
- **Rows of different widths leave an uneven right edge.** That looks less tidy than a grid. It is
  the cost of the space the grid wastes.
- **The converge animation is unaffected.** `ThumbnailController.stitched` flies the pieces into
  the finished card's slot and reads no piece frames from the layout.

## Not measured

- **No real model read a stitch here.** The 10 px threshold comes from one study that measured
  instruction-following, not transcription. Before the warning ships, the check is: stitch a few
  real sets, paste each into Claude Code, and ask for the text of a named control.
- **Gemini's pixel budget isn't published,** so Gemini isn't in the table.

## Sources

All retrieved 2026-09-27.

- Anthropic, [Vision](https://platform.claude.com/docs/en/build-with-claude/vision) and
  [Coordinates and bounding boxes](https://platform.claude.com/docs/en/build-with-claude/vision-coordinates):
  tiers, the resize rule and its reference implementation, the 20-image rule, quality guidance.
- OpenAI, [Images and vision](https://developers.openai.com/api/docs/guides/images-vision): the
  32 px patch scheme, 2500 patches at `detail: high`, the small-text limitation.
- Google, [Image understanding](https://ai.google.dev/gemini-api/docs/image-understanding) and
  [Media resolution](https://ai.google.dev/gemini-api/docs/media-resolution) (updated 2026-09-23):
  258-token tiles, and Gemini 3's 280, 560, 1120 and 2240 token budgets.
- Claude Code: [issue #55192](https://github.com/anthropics/claude-code/issues/55192) quoting the
  v2.1.126 changelog ("images are now downscaled on paste"), and
  [t3code issue #13647](https://github.com/pingdotgg/t3code/issues/13647) (2026-09-25): "Claude Code
  scales images down to 2000px when they come with the first message of a turn or from its Read
  tool."
- Balakrishnan, Mendapara, Garg, [Reading Between the Pixels](https://arxiv.org/abs/2604.12371),
  2026-04-15: font size thresholds for four VLMs.
- [RealBench](https://arxiv.org/abs/2509.17421), 2025-09-22: closed models read composites worse
  than separate images.
- Das et al., [More Images, More Problems?](https://arxiv.org/abs/2601.07812), 2026-01-12: open
  models on grids, and sequence length as the cause of multi-image losses.
- [MIRB](https://arxiv.org/abs/2406.12742), 2024-06: concatenated images score worse for most
  models.
- Yang et al., [Set-of-Mark prompting](https://arxiv.org/abs/2310.11441), 2023-10: numbered marks
  for referring to regions.
- `docs/stitch-2026-09-17.md`: the current design and the reasons for the gap, the badge and
  `ui.stitchLongSide`.
