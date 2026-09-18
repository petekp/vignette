# The gap beside the selection strip (2026-09-18)

The strip of bulk actions sits to the left of the selected cards. `StackLayout.stripPlacement`
puts it there: its right edge is the widest selected card's left edge, less `ui.selectionStripGap`.
Beside a wide card that gap was 8 points, which read as touching.

## What changed

`ui.selectionStripGap` is 16 points. Nothing else moved. The panel makes the room
(`panelSize(viewport:showsStrip:reveal:)` adds the icon column, the gap and the reveal), so it is
8 points wider while the strip shows; its right edge is fixed, so the cards do not move.

## Why the gap and not the column's widest card

The other way to spend the same change is to measure the strip from the widest card in the column
rather than the widest selected one. That keeps the strip still while the selection changes.

The gap is what Pete named, and measuring from the column does not change it: the widest card would
still be exactly `selectionStripGap` away. So the number had to rise either way, and measuring from
the column only adds a cost. A card that is at the minimum side is 68 points narrower than a full
one here, so the strip would hang that far off a narrow selected card, with nothing between them.
The strip says which cards it acts on by being beside them.

The step it would have removed is small in kind: the strip already moves vertically on every
selection change, it moves through `ui.relayoutDuration` like everything else, and the sideways
distance is the difference in card width, 68 points on the fixtures below — the same before and
after.

## The numbers

Measured on a 1512 x 982 display with the tuned tweaks (`cardMaxWidth` 188, `cardMinSide` 120,
`panelInset` 19, `screenMargin` 17, `buttonSize` 27, `buttonSpacing` 4) and two fixtures: a
900 x 560 shot, whose card is 188 x 120, and a 300 x 800 shot, whose card is 120 x 153. Frames are
`[state] stack.strip`, in global top-left points.

| selected | gap 8 | gap 16 |
|---|---|---|
| the wide card | [1264, 765, 35, 128] | [1256, 765, 35, 128] |
| the tall card | [1332, 623, 35, 128] | [1324, 623, 35, 128] |
| both | [1264, 688, 35, 128] | [1256, 688, 35, 128] |
| panel | [1197, 591, 317, 321] | [1189, 591, 325, 321] |

The cards are at [1307, 773, 188, 120] and [1375, 610, 120, 153] in every reading. With both
selected, the clear screen between the strip and the wide card goes from 8 to 16 points, and
beside the narrow card, which the strip does not hug, from 76 to 84.
