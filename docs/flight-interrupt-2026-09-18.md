# Turning the flight to the annotator around (2026-09-18)

Pete: "make the thumbnail -> annotator transition interruptible."

The card flies from its slot in the stack to the annotator's frame while the annotator loads the
image behind a hidden window. This note says what an Esc or a click on another card did during that
flight, what it does now, and what the camera saw.

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

`abandon` is `AnnotationController.abandon()`: the page lets the image go, the canvas is reset, the
stand-in's session ends and the window — which was never ordered in — is taken down. Nothing is
written, so the stored draft the page was told to load is exactly as it was.

`returnCard` re-aims the flight that is already in the air. `TransitionLayer.fly` on an id it
already holds keeps the frame, puts the old path in `previousPath` and animates `blend` back to 1,
so the card crosses from one bow to the other and keeps its velocity into the new target. A swap is
two flights, one each way, the same pair the annotation queue's handover runs.

`dismiss` and `remove` still park. `ThumbnailController.dismiss` aims this same flight at the
card's offscreen slot before it sends the event, and `hideAnnotator` would end that flight; the
park keeps the card in the layer until the column has slid out.

`finish` also still parks. Done renders on the page, so it cannot come from a window that never
appeared; if it ever does, there is a rendering and the draft behind it is worth storing.

### Why a branch rather than a park that answers at once

`AnnotationController.hide` could have answered immediately for a window that never came up, and
the reducer would not have changed. Two reasons against it. The turnaround would still be a
callback the page's own state can delay, which is the failure this item is about. And `parked`
would then arrive inside the `send` that emitted `park`, re-entering the effect loop that the
annotation queue's handover runs in. The branch says the rule where it belongs: a session nobody
saw has nothing to store.

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

**A swap 173 ms in** (`shotnote://annotate` of a second fixture):

```
21:51:16.573 [transition] annotate(Screenshot t1.png from stack) -> flyingOut(…) effects=prepare(…)
21:51:16.746 [transition] annotate(Screenshot t2.png from stack) -> flyingOut(Screenshot t2.png)
             effects=abandon(Screenshot t1.png) returnCard(Screenshot t1.png) prepare(Screenshot t2.png)
21:51:17.391 [transition] shown -> annotating(Screenshot t2.png) effects=show
```

Afterwards `stack.cards` held t1 with `out: false` — home in its slot — and t2 out, in the annotator.

**A draft survives.** A rectangle was drawn on the fixture and parked (`[draft] parked Screenshot
t1.png`, `[drafts] 21`). Reopening that card and cancelling 136 ms into the flight logged
`close -> idle effects=abandon returnCard` and no `[draft]` line at all; the card still read
`draft: true` and the store still held it.

**`ui.motion: 0`.** `expandDuration` is 0, so the flight lands in the turn after it starts and
`flyingOut` is over before a cancel or a second annotate can reach it: both went through
`annotating` and the park, as they did before, and both landed at once
(`annotate -> flyingOut`, `shown -> annotating`, `close -> parking`, `parked -> idle`, all inside
36 ms).

## What the page is left holding

`loadImageQuietly` puts the image on the canvas at once but reports `loaded` from a double
`requestAnimationFrame`, and WebKit pauses frames while the window is hidden. An abandoned load
therefore leaves that callback pending; it fires the next time the annotator window appears and
posts a `loaded` for a key that is no longer in the annotator, which the log shows as a stale
`[annotate] loaded <n>ms` beside the real one. `pageLoaded` lifts a flight only for the key the
reducer says is `annotating`, and `prepare` clears `loadedKeys` for the key it opens, so the next
annotate starts clean. `abandon` clears that key too.
