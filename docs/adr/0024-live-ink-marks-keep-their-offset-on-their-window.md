# Live ink marks keep their offset on their window

A live ink mark drawn on a window keeps its offset from the window's top-left. A scroll, a change
to the page and a resize leave it where it is on the window. It moves with the window, windows in
front cover it, it fades out as the window minimises and back when the window returns, and it goes
when the window closes. An answer's marks keep their offsets on the window they were placed on in
the same way.

When a window shrinks past a mark's point, the mark fades out and stays hidden until the window
grows over that point again. The point is a loop's or a box's centre, an arrow's head, or a note's
tag. A reply is a popover and may hang past the window's edge, so it stays.

Until this decision, a mark was pinned to the content under it. Vignette found that content through
Accessibility, a terminal's lines, or a patch of the window's pixels. The mark hid while the content
scrolled or the window resized, and came back on its content once the content was still. Pete asked
on 2026-10-24 to drop that and position marks relative to their window. The tracking polled other
apps through Accessibility and captured windows while they moved for as long as a mark was on the
screen. In Chromium apps it also waited for positions the app reported late.

## Considered options

- Following the content, as step 3 built it (`docs/live-ink-step3-2026-10-05.md`). Marks hid on
  every scroll and could stay lost.
- Following the content only in apps that report positions on every frame. That gives two
  behaviours, and Chromium apps would still not follow.
- After a shrink, leaving a mark past the window's edge drawn over whatever is beside the window, or
  cutting it off at the edge. The first draws ink over something it was not drawn on. The second
  leaves part of a loop or an arrow showing.

Source: `docs/live-ink.md`, `docs/live-ink-step3-2026-10-05.md`. The last commit with the content
tracking is `89cbc3b` on `live-ink`.
