# The toolbar stays put across a swap (2026-09-19)

Pete: "when in the annotator, if the user switches between images, let's try to keep the tldraw
controls stable between images and just have it translate up or down depending on the height of the
incoming image, as opposed to rendering brand new control element each time."

## What it did

The bar is a native panel placed under the annotator's window by `prepare` and taken down with the
window by `hideWindows`. A swap is a park and then a new session, so the bar faded out with the
window that was going and rose again with the one that came. Recorded at 60 fps over the bar's Done
button while a queue of three handed over (below), it was **gone for 24 frames — 0.40 s — with no
pixel of it on screen**, and then faded in at the next image's place.

## What it does now

`AnnotatorToolbar.place(below:gap:)` slides the panel when the bar is already up, instead of setting
its frame outright: one `Tween` spring per direction, so a move retargeted part way through keeps
its velocity into the new place. The spring's duration is
`Anim.passesTarget(ui.expandDuration, bounce: 0.15)` — the moment the incoming card's flight first
covers the annotator's frame, which since `docs/handover-2026-09-18.md` is when that window comes
up. So the bar arrives with the window. The motion scale is inside `motionUI`, so `ui.motion: 0`
puts the bar at the next place in the same turn, with no fade.

The exit waits. `hideWindows` asks through `hideSoon`, which schedules the fade one turn of the run
loop later; the next `place` cancels it. That one turn is enough for every swap the app can make,
because the park's answer and the next `prepare` are in the same turn:

- A click on another card: `annotating(a)` takes `annotate(b)`, parks, and the page's answer runs
  `hideWindows` and then, inside the same block, `parked -> flyingOut(b)` with `returnCard(a)` and
  `prepare(b)`.
- The annotation queue: `parked -> idle` with `returnCard(a)`, and `ThumbnailController.send` sends
  the next `annotate` after that batch's effects, in the same call.

So the reducer says nothing about "a session follows this one", and does not need to: the two
sequences that swap already emit their `prepare` before the run loop turns. A new effect or a flag
on `park` would have had to be answered in `AnnotationController` anyway, and the queue's handover —
which the reducer knows nothing about, on purpose — would still not have been covered by it.

What is left to do when the bar really goes: `hideWindows` detaches the panel from the window before
ordering the window out, because AppKit orders a child window out with its parent. The panel then
floats on its own until either `hideSoon` takes it down or `show` makes it a child of the next
window. Its tool state follows the incoming image as before, from the page's `tool` message.

`[state] annotator.toolbar` is the panel's frame in the state report, or null when it is off screen,
which is how the numbers below were taken.

## Driven and measured

Three grid fixtures with different heights, so the bar has somewhere to move: 600 x 1800 px fitted
at `[639, 98, 234, 699]`, 1200 x 900 fitted at `[370, 158, 771, 579]`, and 2800 x 600 fitted at
`[60, 298, 1392, 299]`. The bar's panel is 278 x 100 points and its place is 9 points
(`ui.annotationToolbarGap`) below each frame, so the first swap moves it 60 points up.

**A queue of three, ended with the real Return key each time** (`annotate?file=a&file=b&file=c`,
`[transition] finish -> parking -> parked` then `[annotate] next … 2 of 3`). Recorded at 60 fps over
a 100 x 340 point region holding the Done button, reading the top row of accent-coloured pixels per
frame, before the change and after it. Times are from the first frame in which the bar moves or
goes:

| after | before: bar's top row | after: bar's top row |
| --- | --- | --- |
| 0.000 s | gone | 496 |
| 0.033 s | gone | 438 |
| 0.067 s | gone | 438 |
| 0.100 s | gone | 426 |
| 0.150 s | gone | 402 |
| 0.200 s | gone | 394 |
| 0.250 s | gone | 390 |
| 0.300 s | gone | 388 |
| 0.383 s | gone | 388 |
| 0.400 s | 413, fading in | 386 |
| 0.450 s | 391 | 386 |
| 0.550 s | 386 | 386 |

Resting place before the swap: 506 in both. Destination: 386. Before, the bar is absent for 24
consecutive frames and its accent pixels go from 6187 to 0 and back through 432, 571, 2894, 5917 —
a fade out and a fade in. After, the count stays at about 6250 for every frame of the move (two
frames dip to 5455 and 4021, which is the flying card crossing the button: the flight layer is at
`.statusBar`, above the bar), and the bar's top row walks 506, 496, 482, 452, 438, 430, 426, 420,
410, 402, 398, 396, 394, 392, 390, 388, 386 without turning around.

**The same swap, sampled through `[state] annotator.toolbar`** at eight delays across eight runs,
each timed against its own `[transition] annotate(… medium …)` line. The panel's top-left y, from
778 to 718:

| after `annotate` | `annotator.toolbar` | `annotator.windowVisible` |
| --- | --- | --- |
| 89 ms | `[617, 752, 278, 100]` | false |
| 139 ms | `[617, 735, 278, 100]` | false |
| 168 ms | `[617, 730, 278, 100]` | false |
| 213 ms | `[617, 724, 278, 100]` | false |
| 286 ms | `[617, 720, 278, 100]` | false |
| 373 ms | `[617, 719, 278, 100]` | true |
| 459 ms | `[617, 718, 278, 100]` | true |
| 608 ms | `[617, 718, 278, 100]` | true |

The panel is on screen at every one of them, moving, while no annotator window is. On the build
before the change the same probe reports the panel off screen for the whole of that stretch.

**A capture of the moment between two images**, 140 ms after the Return: before, the bar is a ghost
at a few per cent opacity with the card in flight above it; after, it is fully drawn, every button
in place, already part way to the next image's height. Both crops are in the run's captures.

**A click on another card** (`[transition] annotate(… medium … from stack) -> parking(… tall … then
annotate) … parked -> flyingOut(… medium …)`): the bar reads `[550, 774, 278, 100]` 150 ms in, with
`windowVisible` false, and `[550, 718, 278, 100]` once the window is up. The x does not move here:
the fitted frame is centred in the room and the room does not change inside a session. It moves
sideways between a session with the recent stack open and one without — 550 against 617 on this
screen — which is the case the sideways half of the spring is for.

**`ui.motion: 0`**: the bar is at the next image's place within one probe of the Return
(`[617, 778, …]` before, `[617, 718, …]` after) with the window already up, and nothing fades.

**The end of a session**: after Esc, `annotator.toolbar` is null, and the last Done of a queue takes
the bar's accent pixels from 6248 to under 300 over the following frames. Nothing keeps it up.
