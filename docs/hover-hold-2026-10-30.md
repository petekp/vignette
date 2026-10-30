# The hover holds while the wheel scrolls the stack (2026-10-30)

While the wheel moves the recent stack's column, the hover and the focus stay on the card that had
them. Once the column has stood still for 0.15 s, the card under the pointer takes both.

## Why

With the pointer resting on the column, each card that passed under it took the hover and gave it
up a moment later. Each change ran one or two card bodies and their springs: the card's scale, its
dim and buttons, its selection circle, and the focus ring that follows the hover. In a Release
build, the main thread was busy for 77% of a scroll with the pointer over the cards, and for 19%
with the pointer beside them (the measurements below). On 2026-10-29, the same scroll kept a Debug
build busy 70% of the time. Turning motion off split that: about 45 points were the springs, 8 the
hover changes themselves and 17 the scroll.

## How it works

- `ThumbnailController.scroll(_:)` handles the wheel. When an event moves the column, `holdHover`
  sets `StackModel.holdsHover` and starts the 0.15 s timer again.
- While `holdsHover` is set, `CardView`'s `onHover` writes nothing. SwiftUI's reports of the cards
  passing under the pointer change no state.
- When the timer fires, `hoverAfterWheel` clears the flag and tests the pointer against each card's
  frame, the way `hover(landing:)` tests one card, provided the pointer is over one of this app's
  windows. The card it finds takes the hover. In a gap between cards, no card has it. The focus
  follows the hover through `model.onHover`, as it follows the pointer.
- The drag-select's auto-scroll, the arrow keys' scroll and `hover(landing:)` do not hold the
  hover.

## When the scroll ends

The hold ends once the column has not moved for 0.15 s. The rule is the same for every device:

- A mouse wheel's events carry no phase, and neither do the events `scripts/input.sh scroll`
  posts. A quiet interval is the only end every device gives, and the only one the VM can drive.
- A trackpad's lift and the start of its momentum come in separate events. Chromium waits up to
  100 ms after the lift for momentum to begin
  (`max_time_between_phase_ended_and_momentum_phase_began_`, in
  `content/browser/renderer_host/input/mouse_wheel_phase_handler.h`). 0.15 s is longer, so momentum
  keeps the hold.
- The interval counts from the last event that moved the column. When momentum carries the column
  to its end and keeps arriving, the hold still ends 0.15 s after the column stops.
- WebKit waits 100 ms, or 250 ms when its page is slow to answer, before it sends the fake mouse
  move a scroll triggers (`fakeMouseMoveShortInterval` and `fakeMouseMoveLongInterval`, in
  `Source/WebCore/page/EventHandler.cpp`).

What the hold costs:

- The hover and the focus reach the card under the pointer 0.15 s after the column stops.
- `prefetchFlightImage` runs when the hover arrives. A click within 0.15 s of the scroll's end
  flies with the thumbnail's decode.
- Return within 0.15 s of the scroll's end acts on the card that had the focus before the scroll.

## Measured

Measured in the `vignette-e2e` VM on Release end-to-end copies, with temporary counters added to
both builds. Before is 9d9921a. After is this change, built from the same `Sources/` before this
note's numbers were added. There were 4 runs per build, alternating before and after, one launch
each. Each run opens the stack on 30 screenshots and scrolls it 1000 pt 4 times with the pointer
over the cards. A scroll is 50 events with a 16 ms pause between them. The VM's sleeps ran about
5 ms long, so a scroll took about 1 s. Busy is the share of the time the main run loop was awake.
Each figure is the mean of the 4 run means, with the range of the run means.

| Pointer over the cards, during the scroll | Before | After |
| --- | --- | --- |
| Main thread busy | 76.7% (75.8 to 77.8) | 22.7% (21.8 to 23.8) |
| Display-link callbacks a refresh late, per second | 6.8 (5.7 to 7.8) | 1.3 (0.9 to 1.6) |
| Hover changes per scroll | 14 | 0 |
| Card bodies per scroll | 16.3 | 0 |
| Busy per scroll, with the 0.8 s after it | 989 ms (986 to 991) | 393 ms (377 to 405) |

In the 0.8 s after each scroll, the after build made its one hover change and ran 2 card bodies.
The main thread was busy for 143 ms (133 to 150) there, against 131 ms (127 to 138) before, when
the springs started during the scroll were still running.

- The hover reached the card under the pointer 151 to 152 ms after the last scroll event, in all
  16 scrolls.
- 8 checks, 2 cases repeated in 4 runs: the hover and the focus read mid-scroll were on the card
  hovered before the scroll. After the scroll, both were on the card whose frame holds the
  pointer. That frame is the one `hoverAfterWheel` tests. Before the change, SwiftUI's own hover
  agreed with it in 8 of 8 checks.
- One process posted two bursts 55 ms apart: the hover moved once, at the end, in both pairs that
  moved the column. A third moved nothing, because the column was at its end. With 255 ms between
  the bursts, it moved twice in 3 of 3.
- With the pointer beside the cards, busy was 19.0% before and 19.1% after, a difference of 0.2
  points (95% interval ±0.6). With the pointer walking the still column, it was 28.5% before and
  27.8% after, a difference of -0.7 (±1.1). Each hover change still ran 1.5 card bodies.

## Not checked

- A real trackpad's phases and momentum. The VM posts pixel scroll events with no phase.
- A mouse wheel's line deltas, the other branch of `scroll(_:)`.
- A settle with the pointer in a gap between cards. In every check it was at least 34 pt inside a
  card.
- Any Mac but the VM, which draws at 60 Hz on a paravirtual GPU.
- Why a scroll over the cards, with the hold, is still 3.6 points busier than one beside them.
