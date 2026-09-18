# The stack makes room for the annotator (2026-09-17)

The annotator used to be fitted into the whole visible screen and zoomed into the whole visible
screen, and the recent stack sat on top of that. On a 1512-point display a wide screenshot already
fitted to a frame whose right edge lay over the panel, and a zoom took the frame the rest of the
way across it. This is the rule that keeps the two apart.

## The rule

One number says how wide the stack is drawn: `StackLayout.widthScale`, 1 at rest and never below
`ui.stackMinScale`. It scales the cards (`drawn`) and the column, with the right edge fixed, so a
narrow stack is the same stack in the same corner. Nothing else scales: the spacing, the insets,
the corners and the shadows are the same at any width, so a card in the stack still casts the same
shadow as the same card in flight.

The rect the annotator fits and grows within is the visible frame less the strip the stack keeps
for itself at its narrowest — the screen margin, the card box at `ui.stackMinScale`, and
`ui.stackGap` beside it (`annotatorRoom`). That rect is `AnnotationController.growthLimit`, the one
place that says how far the frame may grow, so the fit at open and every zoom step respect it and
the frame can never reach the cards.

Between the two ends the stack follows the frame: whenever the annotator's frame moves, the stack
takes the widest value at which the column's left edge still clears the frame's right edge by the
gap, clamped to the minimum (`widthScale(clearing:visibleFrame:)`). Growing the frame narrows the
stack; shrinking it lets the stack back out.

Only the recent stack does this. A lone thumbnail leaves the panel when the annotator opens, and an
annotation with no stack showing is fitted and grown in the whole visible frame, as before.

## Why it is set where it is

- **The width is set before a batch of transition effects runs, not inside them.** Every flight is
  aimed at a slot the width decides. A swap emits `returnCard` and `prepare` in one batch: the
  returning card must be aimed at the column the new image leaves, and the card leaving must fly
  from the slot it is drawn in now. `send` sets the width once, up front, and hands `perform` the
  slot the leaving card had.
- **A zoom sets the width straight, without a spring of its own.** The frame is the live value of
  the zoom's spring; a stack that sprang towards it would be behind it, and a frame that has grown
  would be over a card that has not moved yet. Opening, closing and swapping do spring
  (`ui.relayoutDuration`, motion scaled), because there the frame arrives in one step.
- **The width is quantised to hundredths, rounded down.** A zoom moves the frame at every display
  refresh, and the column would otherwise be laid out again for a fifth of a point. A hundredth is
  under two points of a card's width. Rounding down means the gap the stack keeps is never smaller
  than the one asked for.
- **The panel is always the size the stack needs at rest.** It is transparent outside the column,
  so a narrow stack simply draws in part of it, and no window is resized while a zoom moves. It
  also means the panel is ready for the stack's full width the moment it comes back.
- **`Card.size` stays the size at rest.** The scale is applied in one place, `drawn`, so a stack
  that narrows and comes back does not re-measure a card or decode its thumbnail again.

## The numbers

`ui.stackMinScale` is 0.5 (bounds 0.3 to 1) and `ui.stackGap` is 24 points. Both have a slider in
the tweak panel, under Cards.

Measured on a 1512 x 982 display with the tuned card box (`cardMaxWidth` 188, `screenMargin` 17) and
a 1500 x 300 screenshot:

| | frame's right edge | stack's width | leftmost card | clear screen between them |
|---|---|---|---|---|
| room | 1377 | — | — | — |
| fitted, at open | 1312 | 0.84 | 1337 | 25 |
| zoom level 1.04 | 1337 | 0.71 | 1362 | 25 |
| zoom level 1.08 | 1364 | 0.57 | 1388 | 24 |
| zoom level 1.10 and past it | 1377 | 0.50 | 1401 | 24 |

The window stops growing at level 1.104 on this image, where the frame is exactly the room; past
that the magnification takes over and the stack stays at its narrowest.
