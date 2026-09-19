# The stack runs to the bottom of the screen (2026-09-18)

The recent stack was laid out inside the screen's `visibleFrame`, which stops at the Dock's top
edge across the whole width of the screen. The Dock is in the middle; the stack is in the
bottom-right corner. So on a Mac with a bottom Dock the column ended a Dock's height above the
bottom of the screen with nothing under it, and that much less of it was on screen.

Now the column is laid out in the screen's full height below the menu bar, and it keeps a safe area
only where the Dock really is.

## The rule

`StackArea` is where the stack may draw on a screen, and `StackLayout.area(visibleFrame:screenFrame:dock:)`
is the only place it is built.

- `bounds` takes its sides and its top from the visible frame, so the menu bar and a Dock on the
  left or right keep their room, and its bottom from the screen's own bottom edge.
- `safeBottom` is the room a Dock under the column keeps at that edge. It is the height AppKit
  already reserves (`visibleFrame.minY - frame.minY`), and it is zero unless the Dock's tiles reach
  into the column's own strip of the screen — the card box at rest, inside the screen margin.

Everything follows from those two numbers:

- The panel's bottom edge is the screen's, less the difference between the inset and the margin.
  Its height is the column box plus the safe area, so the window runs down to the screen's edge and
  the column sits in the part of it above the Dock.
- The newest card rests `screenMargin` above the Dock's top edge, the way it rests `screenMargin`
  above the screen's bottom edge when there is no Dock under it (`cardFrame`, `safeBottom`).
- The viewport — how much column is on screen — is the area's height less the safe area and the two
  margins. With no Dock under the column that is a Dock's height more than before.
- The strip follows the column, since `stripFrame` is measured from the same panel bottom plus the
  same safe area, and `stripPlacement` already keeps it inside the viewport.
- The mask keeps its shape and is lifted by the safe area. The Dock's room below it draws nothing,
  so a card scrolled down fades out at the Dock's top edge instead of covering the Dock.
- The hair of alpha that makes the column catch clicks and scrolls is lifted the same way, so a
  click on a Dock icon under the column still reaches the Dock. The panel is at `.statusBar`
  (level 25) and the Dock at 20, so nothing else keeps it off.

`annotatorRoom` and `annotationFrame` still read `visibleFrame`: the annotator must not go under the
Dock, whatever the stack does. The backdrop strip already covered the screen's full height.

## Where the Dock's rect comes from

AppKit says how much room the Dock takes along the bottom edge but not how wide it is or where
along the edge it sits, and the stack only has to step around a Dock its own column is over.

`CGWindowListCopyWindowInfo` does not answer it. On macOS 15 the Dock's layer-20 window is the whole
screen — measured here, `(0, 0, 1512, 982)` while the tiles were 966 points wide — so its bounds say
nothing about the tiles.

The Accessibility API does. The Dock process has a single `AXList` child and it is the row of tiles;
`Dock.tiles()` reads its position and size and converts them to AppKit points. That needs the app
trusted for Accessibility, which is the trust the modifier-tap hotkey already needs. Untrusted, or
if the Dock does not answer inside the 0.25 s messaging timeout, `tiles()` is nil and the Dock is
taken to span the whole edge — which is the room AppKit reserves, and so exactly the old layout.

The read costs 0.34 ms (median of 40, warm), so it is taken once per layout pass and kept in
`ThumbnailController.area`: the panel, the cards and the strip are then placed from one reading.

Only the horizontal extent comes from there. The safe area's height is AppKit's, so it cannot
change while a tile grows under the cursor: the `AXList` widens with magnification but keeps its top
and its height, and `visibleFrame` reserves the resting height either way. A magnified tile
therefore still grows up past the room it is given and is drawn behind the newest card, as before.

## The numbers

Measured on the built-in display, 1512 x 982 points, with the tuned tweaks (`cardMaxWidth` 188,
`screenMargin` 17, `panelInset` 19) and twelve fixtures. Frames are `[state]`, in global top-left
points.

| | Dock clear of the column | Dock under the column | Dock hidden | Dock on the left |
| --- | --- | --- | --- | --- |
| `tilesize` | 51 | 72 | 72 | 72 |
| the tiles (`Dock.tiles`, top-left) | `(273, 906, 966, 66)` | `(90, 885, 1332, 87)` | `(90, 982, 1332, 87)` | `(10, 77, 60, 865)` |
| `screen.visibleFrame` | `[0, 38, 1512, 872]` | `[0, 38, 1512, 851]` | `[0, 38, 1512, 944]` | `[67, 38, 1445, 944]` |
| `stack.safeBottom` | 0 | 93 | 0 | 0 |
| `stack.viewport` | 910 | 817 | 910 | 910 |
| `stack.panel` | `[1288, 36, 226, 948]` | `[1288, 36, 226, 948]` | `[1288, 36, 226, 948]` | `[1288, 36, 226, 948]` |
| the newest card | `[1307, 845, 188, 120]` | `[1307, 752, 188, 120]` | `[1307, 845, 188, 120]` | `[1307, 845, 188, 120]` |

The column's strip of the screen is x 1307 to 1495, so the 966-point Dock ends 68 points short of it and
the 1332-point one reaches 115 points into it. Where it does, the newest card's bottom edge is at
872, which is 17 points — the screen margin — above the Dock's top edge at 889. Where it does not,
the card's bottom edge is at 965, the same 17 points above the screen's bottom edge at 982. The
panel's own bottom edge is 984 in every reading: two points past the screen's edge, the inset less
the margin.

Inside `visibleFrame`, which is where the column used to be laid out, the same twelve fixtures give
a viewport of 838 and a newest card at `[1307, 773, 188, 120]` whatever the Dock's width. (Computed
from `min(content, visibleFrame.height - margin * 2)`; the old build was not run in this round.)

**A card scrolled down fades out at the Dock's top edge.** With the Dock under the column and
`stack.scroll` 42, the newest card's frame is `[1307, 794, 188, 120]`: its bottom edge is 914, which
is 25 points below the Dock's top. The capture shows the card ending at that edge, with the Dock
whole below it.

**The Dock's room catches nothing.** With the cursor at (1400, 940), inside the Dock and under the
column, a 20-step scroll left `stack.scroll` at 42. Thirty points higher, on the column, the same
scroll took it to 72.

**The strip and the toast keep the same margin.** Beside the newest card alone, `stack.strip` is
`[1256, 744, 35, 128]` — its bottom edge 872, level with the card's. A "Copied to clipboard" toast
with no stack showing sits in a panel `[1288, 813, 226, 171]` and ends at 872 too.

**Magnification.** With `magnification` on, the tiles' rect grows sideways under the cursor —
`(90, 885, 1332, 87)` became `(16, 885, 1480, 87)` — but keeps its top and its height, and
`stack.safeBottom` stayed 93. So a magnified tile still grows up past the room AppKit reserves and
is drawn behind the newest card, as it was before this change. The one cost is that a Dock whose
resting right edge is just short of the column can gain the safe area while the cursor is on it,
until the next layout pass.
