# Live ink: one material for the line, its joins and its head (2026-10-13)

Status: built on `live-ink`.

A mark in live ink is one soft shape. The line, the places it turns, and an arrow's head are lit as
one surface, with one glow and one shadow.

## What was wrong

- **The arrowhead was a separate piece.** It was a flat triangle with sharp corners and its own
  lighting, laid over the end of the line. Its shading did not follow the line's, and the line
  stopped at its base with a seam.
- **A rectangle's corners glared.** The line was a strip of quads, each lit from its own direction
  along the line. At a corner of 4 pt the quads pinched and overlapped, and the highlight jumped to
  a white streak round the turn.

## How it is drawn now

Two passes in `InkGel.metal`, driven by `InkMarkLayer.encode`:

1. **The field pass.** Each segment of the line is a capsule, a segment with round ends whose half
   width runs from the hand's width at one end to its width at the other. An arrow's head is its
   triangle with its corners rounded. For every pixel near the mark, the pass writes the distance to
   the nearest piece's edge, the half width there, and the shimmer's place along the line. The depth
   test keeps the nearest piece, so the result is the distance to the edge of the whole shape.
2. **The light pass.** It lights that shape as one surface. How deep a pixel is inside the shape
   gives the rod's profile: round across a line, and flat on top where the shape is wider than the
   line, as inside the head. The direction the distance grows in gives the surface's tilt. The glow
   and the shadow come from the same distance outside the shape.

The field is read a few pixels either side for the light's tilt, so a tight turn bends the
highlight smoothly. The glow's direction is read further out and averaged, so it blends where two
parts of the shape are equally near, as in a rectangle's inner corner.

Each layer keeps its own field, the size of its drawing. The depth buffer is only needed inside the
field pass, so on Apple's GPUs it takes no memory. Both passes draw only the triangles round the
mark, so the cost follows the line's length, not the layer's area. `SettledLine` still lays the
pen's line out once as it settles, and each event lays out only its last few points.

## The head

- Its corners are rounded by 0.6 of the line's half width where it meets the head, so its tip and
  corners read as soft as the line. `InkGel.headRounding` holds the share.
- It casts the glow and the shadow as the line does, since it is part of the same shape.
- While a hand-drawn arrow eases onto its shape, the head grows out of the line's end, where before
  it faded in over it.

## Verified

In the `vignette-e2e` VM, with Pete's ink values, on the ink samples and on a scribble drawn with
the pen:

- The arrow's line runs into its head with no seam, and the highlight carries on round the head's
  edge. The head's corners are round.
- A rectangle's corners turn with a small soft highlight where there was a white streak, and the
  band keeps its width round the turn.
- A loop whose end crosses its start merges into one band there.
- The pen's sharp turns are round and unbroken, and the scribble is one colour along its length.
- The glow inside a rectangle's corner is even, with no streak along the diagonal.

GPU time of both passes for one frame, on an Apple M4 Max at 2x, measured in a unit test that drew
each line 60 times through the same pipelines and read the command buffer's GPU times:

| Line | Layer, px | Median | Slowest |
| --- | --- | --- | --- |
| 500 pt | 1200 × 400 | 0.13 ms | 0.21 ms |
| 12,000 pt, across the screen | 3400 × 2000 | 0.63 ms | 0.73 ms |
| 40,000 pt, dense | 3400 × 2000 | 1.45 ms | 1.63 ms |

A frame at 120 Hz has 8.3 ms. The cost grows with the line's length, as the passes only draw round
the mark. The CPU work per pointer event is unchanged.
