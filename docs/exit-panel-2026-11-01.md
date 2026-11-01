# The corner's panel on a lone card's return (2026-11-01)

A lone card alone in the corner leaves the panel when the editor opens. When it comes home, the
corner's panel goes on screen once the flight home first reaches the card's slot, directly under
the flight layer. Ordered in earlier, in the exit's first turn, the panel left the image without
its shadow for a frame or more.

## What happens when the editor closes

- **First turn.** The editor's shadow goes to 0, and the flight home is added to the flight layer,
  above the editor's frame. The return lays the corner's panel out, with the card's slot drawn empty
  (`outCards`), and leaves it off screen (`present`'s `ordersPanel`).
- **Second turn.** The editor's frame is hidden, and the flight starts moving.
- **`covered`.** The flight's spring first reaches the slot. `orderPanelIn` orders the panel in,
  directly under the layer (`TransitionLayer.orderBelow`). The slot is still drawn empty, so
  nothing appears.
- **`arrived`.** The card takes its slot in the panel, and the flight is lifted a turn later.

The flight layer stays up, clear, while the editor is open (`staysUp`), so it is not ordered in
during the first turn either. Ordered in then, it reached the screen up to 2 frames after the
editor's change from that turn (`docs/agent-title-2026-10-28.md`). A stack presented while the
editor is open goes in directly under the layer (`orderIn`). One presented otherwise goes to the
front, and the next flight or swallow rect brings the layer back above every window at its level
(`showPanel`).

## Why not in the first turn

These were measured on 2026-10-31 in the `vignette-e2e` VM, on recordings of Done by the Return key
on a lone card, with the layer staying up. A marker square in the editor's window and one in the
flight layer turned white in the first turn and black in the second.

- **With the panel ordered in during the first turn,** directly under the layer, the layer skipped
  the first turn in 10 of 12 takes. In each of them the image's shadow was missing.
- **With the ordering moved 0.15 s later,** the layer skipped it in 0 of 12. Both windows showed
  the first turn in the same frame in 12 of 12.
- **The ordering alone is enough.** In an exit that flies the card off the screen and never touches
  the panel, ordering an empty panel under the layer in the first turn made the layer skip in 11 of
  13 takes, against 2 of 14 without it.
- **A longer first turn is not.** 5 ms of busy main thread in that turn made the layer skip in 1 of
  13, against 2 of 14.

## Why at `covered`

Three conditions decide the moment.

1. **The display has shown both exit turns.** The second turn ran 11.6 to 22.6 ms after the first in
   those takes, sometimes more than a frame at 60 Hz. An ordering before the first turn's frame
   reaches the display can still hold it back. `WindowRemoval` waits 3 refreshes for a commit to be
   shown, for the same reason.
2. **The card moves slowly.** If the ordering holds the layer for a frame, the card stops and then
   catches up by its speed. In the first five frames of the flight the card moved a median 50 pt a
   frame. At `covered` it moves about 2.7 pt a frame on a 700 pt flight.
3. **The landing is at least 3 refreshes away.** At the landing the card and its shadow pass from
   the layer to the panel in one commit, so the panel has to be on screen by then. At the default
   `ui.expandDuration`, `covered` comes 0.279 s after the flight starts and `arrived` 0.46 to 0.50 s
   after, 11 to 14 refreshes later at 60 Hz.

No other moment meets all three. The second turn fails the first condition. Three refreshes after
it, the card still moves about 84 pt a frame. `arrived` fails the third.

## While the panel waits

- `[state] stack.visible` reads true for about 0.28 s while the panel is off screen.
  `stack.panelOnScreen` says whether the panel's window is up.
- A capture puts the panel on screen at once: `insert` and `shiftUp` order it in after their
  layout. So does the shortcut: `toggleRecent` orders it in before `CornerKeys` sees the press,
  since `CornerKeys` takes a panel off screen for an empty corner.
- A dismissal sets `visible` to false, so `covered` orders nothing. Opening the card again replaces
  the flight home, whose `covered` then never runs. A new column orders the panel itself.

## What is not measured

- **The fix itself was not recorded.** The numbers above come from the VM, on builds with the
  ordering moved by a fixed 0.15 s. Pete judges the fix by eye on his own Mac.
- **Motion 0 and Reduce Motion.** `covered` and `arrived` then run right after the second turn, so
  the first and third conditions fail. The fix may not stop the missing shadow there, and may make
  the landing worse.
- **120 Hz.** It doubles the refreshes between `covered` and `arrived` and halves the card's speed
  a frame, which makes the second and third conditions easier.
