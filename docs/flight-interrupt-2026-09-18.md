# Turning the flight to the annotator around (2026-09-18)

Pete: "make the thumbnail -> annotator transition interruptible."

The card flies from its slot in the stack to the annotator's frame while the annotator loads the
image behind a hidden window. This note says what an Esc or a click on another card did during that
flight, what it does now, and what the camera saw.

The measurements were made on the web editor, which the native editor replaced on 2026-09-22.
"What it did" and "What the camera saw" are that history. The reducer's branch and the flight's
turnaround are unchanged; what `abandon` does, and what the editor is left holding, are written
here for the native editor.

## What it did

`prepare` sends the card out and the reducer sits in `flyingOut` until the flight's `arrived`
callback sends `shown`. Every way of ending a session from there — `close`, another `annotate`,
`dismiss`, `remove` — went to `parking` and asked the page to park its draft. The card turned
around only when the page answered.

On the driven sequence the page answered in 2-3 ms, so the card did turn around at once:

```
21:43:49.364 [transition] annotate(Screenshot t1.png from stack) -> flyingOut(…) effects=prepare(…)
21:43:49.540 [transition] close -> parking(Screenshot t1.png then close) effects=park(…)
21:43:49.543 [transition] parked -> idle effects=returnCard(…)
```

That 3 ms is not a promise. The page runs `park`, `export`, `build` and `setView` one at a time, so
an Esc during a Copy Drawing waits behind the whole rendering, and `hide` gives the page
`exportTimeout` — 15 seconds — before it comes down anyway. The card is in the air for all of it.
A park was also being asked for something that cannot exist: the window never came up, so nobody
saw that image and nobody could draw on it.

## What it does now

`flyingOut` has its own branch in the reducer. `close` and an `annotate` of another key answer in
the same turn:

| event in `flyingOut(a)` | effects |
| --- | --- |
| `close`, from the stack | `abandon(a)`, `returnCard(a)` |
| `close`, from a lone thumbnail | `abandon(a)`, `hideAnnotator` |
| `annotate(b)` | `abandon(a)`, `returnCard(a)`, `prepare(b)` |

`abandon` is `AnnotationController.abandon()`: the editor parks the drawing and stores it, and the
window, which was never shown, is taken down with no fit-out. It stores the drawing because the
editor holds the keys from `prepare`, so a key pressed during the flight can change it. It skips the
fit-out because no zoom can have happened: the zoom keys are ignored until the window is up. With
nothing changed, the stored drawing is written back as it was.

The flight home carries the drawing as it was parked. `ThumbnailController` keeps the parked marks
on `.abandon`, as it does on `.park`, so a mark deleted during the flight out is gone from the card
that comes back. Before that fix the flight home showed the drawing it left with, and the deleted
text vanished only at the lift.

`returnCard` re-aims the flight that is already in the air. `TransitionLayer.fly` on an id it
already holds keeps the frame, puts the old path in `previousPath` and animates `blend` back to 1,
so the card crosses from one bow to the other and keeps its velocity into the new target. A swap is
two flights, one each way, the same pair the annotation queue's handover runs.

`dismiss` and `remove` still park. `ThumbnailController.dismiss` aims this same flight at the
card's offscreen slot before it sends the event, and `hideAnnotator` would end that flight; the
park keeps the card in the layer until the column has slid out.

`finish` also still parks. The editor holds the keys from `prepare`, so Return can finish before
the window is up; the drawing is parked as usual and the card comes back marked copied.

### Why a branch rather than a park that answers at once

`AnnotationController.hide` could have answered immediately for a window that never came up, and
the reducer would not have changed. When this was written, two reasons stood against it. The
turnaround would still have been a callback the web page's own state could delay, which is the
failure this item is about. And `parked` would then have arrived inside the `send` that emitted
`park`, re-entering the effect loop that the annotation queue's handover runs in.

The native editor parks synchronously, so a park now does answer inside that `send`, and
`ThumbnailController.send` holds the answer until the event that asked for it is done. The branch
stays because it skips the fit-out, which a window nobody saw cannot need.

## What the camera saw

60 fps over `-R 60,300,760,560`, the region that holds the annotator frame's left edge. Per frame,
the column of the strongest left-to-right brightness rise is that edge; the frame's own left edge
rests at capture column 131.0 (global x 126).

**Interrupted 175 ms in, before the change** (`captures/before-int200.mov`). The card's leading edge
swept in to column 514 — global x 317, still 191 points short of the frame — and reversed there:
961, 944, 771, 626, **514**, 548, 689, 885, out of the region.

**Interrupted 175 ms in, after the change** (`captures/i29-int200.mov`): 1370, 1232, 944, 771,
**645**, 661, 779, 955, out. Same shape, turned 66 points sooner, and `[transition] close -> idle
effects=abandon returnCard` is one line with no park between it and the card coming home.

**Interrupted 511 ms in**, deep in the flight (`captures/i29-int550.mov`): the edge reached the
frame and its overshoot — 142, 133, 127, 124, 122, **121.1, 121.1**, 122, 124, 125 — and then
reversed two frames after the `close`: 213, 401, 642, 903, 1161, out. It comes back from where the
spring had carried it, without stopping there.

**The window never came up.** `show` is the only thing that orders it in, and the `[transition]`
lines carry no `show` in any of these runs; `annotator.windowVisible` read `false` in the `[state]`
taken after each.

**A swap 173 ms in** (`vignette://annotate` of a second fixture):

```
21:51:16.573 [transition] annotate(Screenshot t1.png from stack) -> flyingOut(…) effects=prepare(…)
21:51:16.746 [transition] annotate(Screenshot t2.png from stack) -> flyingOut(Screenshot t2.png)
             effects=abandon(Screenshot t1.png) returnCard(Screenshot t1.png) prepare(Screenshot t2.png)
21:51:17.391 [transition] shown -> annotating(Screenshot t2.png) effects=show
```

Afterwards `stack.cards` held t1 with `out: false` — home in its slot — and t2 out, in the annotator.

**A draft survives.** On the web editor, a rectangle was drawn on the fixture and parked
(`[draft] parked Screenshot t1.png`, `[drafts] 21`). Reopening that card and cancelling 136 ms into
the flight logged `close -> idle effects=abandon returnCard` and no `[draft]` line at all; the card
still read `draft: true` and the store still held it. The native editor's `abandon` writes the
drawing instead, so the same sequence now logs `[drawing] parked`, and the drawing is the one the
card had unless a key changed it during the flight.

**`ui.motion: 0`.** `expandDuration` is 0, so the flight lands in the turn after it starts and
`flyingOut` is over before a cancel or a second annotate can reach it: both went through
`annotating` and the park, as they did before, and both landed at once
(`annotate -> flyingOut`, `shown -> annotating`, `close -> parking`, `parked -> idle`, all inside
36 ms).

## What the editor is left holding

A decode or a colour sample that answers after its image was abandoned is dropped:
`AnnotationController.open` counts opens in `openGeneration`, and each answer checks it. A flight's
image is lifted only for the key the reducer says is `annotating` (`ThumbnailController.editorLoaded`),
and every `prepare` clears `loadedKeys` for the key it opens, so the next annotate of an abandoned
key waits for its own `loaded`.
