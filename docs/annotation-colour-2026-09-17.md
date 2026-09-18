# The colour a mark is drawn in (2026-09-17)

Pete: "Hide the colour palette by default and draw in red only. Then look into a heuristic that
picks a different colour from the background under the drawn shape, so a minimum contrast ratio is
always met (red on a red or dark-red region would switch), without the user choosing."

Two things landed. The toolbar's swatches are off (`SHOW_COLORS` in `web/src/config.ts`), so the
page sends an empty colour list in `ready` and the bar is tools, one divider, Done. And the page
picks each mark's colour from the pixels it covers, so red is what a mark is unless red is what it
sits on.

The pick lives in `web/src/contrast.ts`. It has to: the page holds the screenshot, and the host
never sees the pixels.

## The measure is a colour distance, not a contrast ratio

A WCAG contrast ratio is computed from relative luminance alone, and luminance cannot tell the two
cases apart. Red `#e03131` on dark grey `#3c3c3c` is a ratio of **2.44**; the same red on dark red
`#7a1212` is **2.42**. The first is what everyone annotates with; the second is the case Pete wants
switched. No threshold on that number separates them.

CIELAB does. The measure is the CIE76 distance in CIELAB (`ΔE`, the straight line between two
colours in a space where equal steps look about equally different), and the threshold is
`MIN_COLOR_DISTANCE = 55` in `config.ts`. Every candidate against representative backgrounds:

| background | red | yellow | light-blue | white | violet | red, WCAG |
|---|---|---|---|---|---|---|
| `white #ffffff` | 93 | 77 | 56 | 4 | 97 | 4.51 |
| `light grey #d8d8d8` | 87 | 74 | 50 | 10 | 91 | 3.17 |
| `mid grey #808080` | 79 | 79 | 48 | 42 | 82 | 1.14 |
| `dark grey #3c3c3c` | 82 | 93 | 63 | 71 | 85 | 2.44 |
| `near black #1a1a1a` | 88 | 104 | 74 | 87 | 91 | 3.86 |
| `red #e03131` | 0 | 70 | 114 | 91 | 94 | 1.00 |
| `dark red #7a1212` | 36 | 78 | 98 | 87 | 86 | 2.42 |
| `orange #f76707` | 31 | 46 | 128 | 93 | 121 | 1.48 |
| `pink #ffb3b3` | 58 | 65 | 66 | 34 | 79 | 2.65 |
| `blue #1971c2` | 110 | 128 | 23 | 70 | 59 | 1.11 |

Red clears 55 on every grey and on white, and fails on red (0), dark red (36), and orange (31).
The threshold has room either side: the largest value it must reject is 36 and the smallest it must
accept is 58 (pink). The WCAG column is there to show what the same rows look like under the
measure that could not be used.

## The candidates

`CANDIDATES` in `config.ts`, in order: `red`, `yellow`, `light-blue`, `white`, `violet`. The first
one far enough from the pixels under the mark wins, so red is the answer unless it is not.
Yellow and white carry the dark and red backgrounds; light-blue carries the warm ones (it is the
only candidate that clears 55 over orange); violet is the fallback for a light blue-grey region.

The hexes are tldraw's **dark theme** strokes, which is what the editor draws: `App.tsx` sets
`colorScheme: 'dark'`. That also rules out `black` as a candidate — in that theme tldraw renders
`black` as `#f2f2f2`, a near-white four units from `white`, so it would add nothing. If the editor
ever draws in the light theme these hexes have to change with it, or the measure is judging a
colour the user never sees.

## The sample

`prepareSample` decodes the screenshot once per load into an offscreen canvas whose long side is
320 px and keeps the pixels. Three reasons for 320: the downscale blends text into its background,
which is what a mark is drawn across rather than the glyphs; one decode costs a few milliseconds;
and 320 x 200 pixels is 256 KB held for the length of one image.

A pick samples what the mark's ink covers, not what its bounding box spans. The box is the same
rectangle for a diagonal arrow and for the rectangle drawn between the same two corners, and the
arrow touches almost none of it: a red banner in a corner of that box would turn an arrow that runs
nowhere near it yellow. So the sample follows the shape (`Area` in `contrast.ts`):

- **a line** for an arrow — 41 points along it, each with one to either side, a strip
  `LINE_BAND` (1% of the screenshot's long side) wide, taken from the arrow's own ends through its
  page transform rather than from its box;
- **a border band** for a shape drawn with no fill — the grid, keeping the points within
  `BORDER_BAND` (15% of the shorter side) of an edge, which is where the stroke is. A box too small
  for a band keeps the whole grid;
- **the whole box** for anything filled, and for text, which covers its box closely enough.

Either way the points are at most a 20 x 20 grid, expressed as fractions of the image and clamped
to it.

The score for a candidate is **not** its distance from the mean colour of the sample. A mean is a
colour that need not appear anywhere in the picture: black and white average to a grey that is
nothing like either, and a mark drawn across both would be coloured for a background that is not
there. The score is the distance the closest tenth of the sampled pixels are within (`TOLERANCE =
0.1`). So at most a tenth of what a mark covers may be nearer to its colour than the threshold, and
a stray red pixel under a mark drawn on white does not move it off red.

## When it runs

- When a mark is created, and again when the user has finished moving or resizing it. Both arrive
  through the store listener, which notes the marks a change touched.
- The picks run on the same 300 ms quiet period as the draft, and never while `editor.inputs
  .isPointing`: a drag is one motion, not its frames, and the colour is decided for where the mark
  ends up.
- Before a `park` and before a Done rendering, so the stored draft, the card's preview, and the
  copied PNG all carry the colour the user saw.
- For a mark an agent pushed with `add?marks=` and no `color`, inside `build`, before the snapshot
  is taken. A mark that names a colour keeps it.

## Whose colour it is

A colour the user picked is the user's: `setColor` marks those shapes `meta.colorChosen`, and the
heuristic never touches them again. So does a pushed mark that named a colour. Everything else is
the heuristic's for as long as it lives.

The `ready` message carries two colour lists for this reason: `colors`, the swatches the toolbar
shows, which is empty while the palette is hidden, and `markColors`, every colour the page can draw
a mark in (`MARK_COLORS`). `add?marks=` checks a mark's `color` against the second. Against the
first, hiding the palette refused every coloured push with `invalid-marks unknown color "red"; the
editor has` and nothing after it. The protocol went to 8 with that field.

The pick is applied **outside undo history** (`editor.run(fn, { history: 'ignore' })`). The colour
belongs to where the mark is, not to an edit of its own: one Cmd+Z removes the mark or puts it back
where it was, rather than taking two presses to undo one action, and the undo itself is a change
the listener notes, so the mark is coloured again for where it lands.

## What it does not do

- It judges the band, not the stroke. A rectangle's border band is 15% of its shorter side, which
  is many times the stroke's own width, so an outline running along a red line on a white card
  stays red: nine tenths of the band is white.
- It has no dark candidate. In tldraw's dark theme nothing in the palette is dark, so a mark over a
  pale washed-out region gets violet, the darkest thing available, at `ΔE` 59 over pink.
- It does not re-pick when the image behind the mark changes, because it cannot: one screenshot is
  one image for the life of a draft.
- `MIN_COLOR_DISTANCE`, `SAMPLE_LONG_SIDE`, `GRID`, `TOLERANCE`, `BORDER_BAND`, and `LINE_BAND`
  are page constants, not settings keys: they are the heuristic, not a preference, and a user who
  wants a colour has the palette (`SHOW_COLORS`).

## Verified

Fixture `Screenshot quadrants.png`, 1200 x 800: white top left, red `#e03131` top right, dark grey
`#3c3c3c` bottom left, dark red `#7a1212` bottom right. Four rectangles created through
`shotnote://eval`, one over each quadrant, every one of them created `red`. What came back, with
each candidate's distance from the pixels under the mark:

```
15,15 | red    | red=93.2 yellow=76.5 light-blue=56.3 white=4.2  violet=97.2
65,15 | yellow | red=0    yellow=70.1 light-blue=114.4 white=91  violet=94.3
15,65 | red    | red=82.2 yellow=93.1 light-blue=62.5 white=70.5 violet=85.1
65,65 | yellow | red=35.8 yellow=78   light-blue=98.3 white=87.5 violet=86.3
```

Red over white and over dark grey; yellow over red (where red scores 0) and over dark red (35.8,
under the threshold). Moving the mark on white onto the red block turned it yellow, 300 ms after
the move. The toolbar showed four tools, one divider, and Done, with no swatches.

## The palette is gone (2026-09-18)

Pete: "you can delete the palette code." `SHOW_COLORS` had only ever been `false`, so the whole
swatch path was unreachable: the page sent an empty `colors` list in `ready`, the toolbar's swatch
block never rendered, its button was the only caller of `onColor`, and `onColor` was the only
constructor of `PageAPI.setColor`. A live wire with nothing at either end.

What went: `SHOW_COLORS`, the `COLORS` list, `MARK_COLORS`, `colors` in the `ready` message on both
sides of the bridge, `PageAPI.setColor` and the page's receiver, and the toolbar's `colors`,
`onColor` and swatch block. The protocol went to 11.

One colour list is left, `CANDIDATES`. It was always the same list: `MARK_COLORS` merged `COLORS`
into it, and every id in `COLORS` was already in `CANDIDATES`, so the merge could never add
anything. It is the heuristic's order, what an agent's `marks=` may name, and — its first entry —
what a fresh image opens on. The `ready` message still carries it as `markColors`, which is what
`add?marks=` checks a colour against.

`meta.colorChosen` stays. A mark an agent pushed with a colour still sets it, and the heuristic
still leaves those marks alone. Only the user's half of that guard went with `setColor`.

To bring a palette back: a swatch list in `ready` (or a subset of `CANDIDATES` named in
`config.ts`), a `setColor` call on the page that writes `colorChosen` the way the deleted one did,
and the swatch block and its divider in `AnnotatorToolbar`.
