# A card joining the open stack (2026-09-26)

Pete found the entrance of a new capture into an open stack mushy next to a lone thumbnail's, and
saw the new card collide with the cards above it. He asked for the lone thumbnail's spring and for
the cards above to clear the way at least as fast as the new card arrives.

## What was wrong

Measured on 60 fps recordings of the stage copy, with solid-colour captures so each card's box
could be read from every frame.

- **The wrong spring.** The new card slid on `insertDuration` (0.5 s, no bounce) with the column's
  move-in transition on top, instead of the lone thumbnail's `slideInCurve` (0.75 s, bounce 0.15).
- **A collision.** The new card reaches the column's width once it is less than its own width from
  rest, which is early in its slide. It overlapped the card above for about 100 ms.
- **A jump.** The cards above moved 62 pt, half the 124 pt slot, in one frame. The insert animated
  the layout while the panel grew at its top edge at once. SwiftUI interpolates in coordinates whose
  origin is the panel's top-left corner, so the two disagreed.
- **A drift.** The new card moved about 6 pt vertically while it slid in, 20 pt with the shift at
  0.5 s, because it rode the column's animated geometry.

## What it does now

- `ThumbnailController.shiftUp` changes the layout and grows the panel with animations off. Every
  card that was there is lifted back to where it was drawn (`StackModel.lift`), so nothing moves
  in that update. On the next turn the lifts spring to 0 on `shiftUpDuration`, 0.3 s with no
  bounce.
- The new card slides on the lone thumbnail's spring. It starts after `CardView.insertLead`: the
  time the shift's spring takes to clear the new card's height, less the time the slide takes to
  reach the column's width. That is 91 ms for a 138 by 114 card at the defaults.
- A card that joins while the others are still rising adds its slot to where they are drawn
  (`liftLeft`), so two captures at once do not jump.
- The oldest card, when the column is full, leaves on the next turn, once the column is moving.
- The selection strip takes the selected cards' lift.

## Measured after

| Case | Result |
| --- | --- |
| One capture | The new card's x path matches the lone thumbnail's within 2 pt in every frame. Its y does not change. It settles about 720 ms after it appears. |
| Collision | None in any frame. The card above is 1 to 4 pt clear when the new card reaches the column's width. |
| The cards above | They rise with no jump. The largest step is 16 pt in a frame. |
| Two captures 12 ms apart | The cards rise two slots with no jump. There is one small hitch, steps of 28, 25, then 37 pt, where the second insert restarts the spring from rest. |
| A full column | The oldest card rises into the top fade and is gone over 4 frames. |
| A selection | The strip rises with the cards, with no jump. |

## Settings files

Every `ui` key is written to settings.json, so a file written before this change held
`insertDuration` at 0.5, and a changed default never reached it. At 0.5 the new card waits 220 ms
instead of 91 ms, and first shows about 300 ms after the cards start to shift instead of 166 ms.
The key is now `shiftUpDuration`, since it no longer times the card's slide. A file without it
takes the default, and the app's next rewrite of the file drops `insertDuration`.
