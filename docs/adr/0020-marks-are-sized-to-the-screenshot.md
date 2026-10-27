# Marks are sized to the screenshot

A drawing records a mark scale when it is made: 1 on a capture of the whole screen, less on a
smaller one. The drawing's `pointScale` now means px per drawing point, the screen's backing scale
times the mark scale, and the file adds `markScale`, left out at 1. The format's version stays 1.
Every place that draws a mark already converts through `pointScale` alone, so the editor, cards,
flights, renderings and stitches agree without a change, and an older build that reads a new file
draws its marks at the new size. A note sized for the whole screen covered a fifth of a 300 by
200 pt crop's height with one line.

## Considered options

- A separate mark scale beside an unchanged `pointScale`. The sources read `pointScale` in 133
  places across 12 files, and each would need the second number. An older build would draw new
  files at full size.
- A scale worked out from the image each time a mark is drawn. A drawing would change size when it
  reopened on another display or after the rule changed.
- Raising the format's version. An older build would then refuse every new file instead of drawing
  it at the right size.

Sources: `docs/mark-scale-2026-10-27.md`, commit 570360e.
