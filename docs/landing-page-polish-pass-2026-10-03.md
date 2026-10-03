# Landing page: polish pass on the demos (2026-10-03)

A second pass over the two interactive demos on the landing page, for smoothness and for how they
read. The earlier pass is `docs/landing-page-interaction-pass-2026-10-02.md`.

## What was wrong

1. **Taking a screenshot stalled the page.** The press cut the capture out of the page image and
   encoded it twice, as a JPEG for the card and a PNG for the clipboard, on the main thread. The
   press held it for 78 ms on a Mac and 123 ms in a phone-sized window.
2. **The stack's slide-in dropped frames.** A card offscreen is not drawn, so each card's
   screenshot was decoded only as it slid in. One frame in three was held during the slide-in.
3. **Every animation frame forced a layout.** The stage read its own size inside the frame, after
   the frame had moved the cards. In act two that cost 12 ms in one frame.
4. **A symbol's first appearance cost a frame.** The first time ⌘, ↩ or ⎿ was laid out, the
   browser looked for a font that has it: 13 ms in the frame the editor opened, and 10 ms in the
   frame Claude's first ⎿ line appeared.
5. **The selection drag and the "show me" box ran on frame counts.** On a 120 Hz display they ran
   at twice the speed.
6. **A card stopped on its way into the editor broke the editor.** Esc did nothing during the
   flight. A click outside, or scrolling away, sent the card home while it was still flying out,
   so two copies flew at once. The editor then opened on arrival and stayed open over the stack.
   The page also says an interrupted flight turns around in mid-air, which the demo did not do.
7. **The hint button stuttered between steps.** It stood empty for a moment and flashed the old
   words in bold. Its new words also faded in cut off while it grew.
8. **The closed toolbar stayed in the tab order,** since it was hidden only by its opacity.

## What changes

1. **The captures are made ahead of time.** Once the page is idle, each of the three captures is
   cut out, encoded once as a PNG and decoded. The press only starts the selection, and the same
   PNG is the card's picture and the clipboard's file.
2. **Every picture is decoded when it is made** (`img.decode()`), so a card that slides in, and a
   flight, have their screenshot ready.
3. **The stage keeps its size from its resize observer.** On a wide screen the camera, which only
   a phone's square stage uses, no longer animates.
4. **The symbols are laid out early.** Each toolbar is laid out, hidden, when its stage is built,
   and a hidden keycap and ⎿ sit beside the hints and in the terminal.
5. **The selection drag and the "show me" box go by the clock** (`tween`).
6. **A flight on its way into the editor turns around.** Esc, a click outside, or scrolling away
   sends the same flight back with its speed, and the card lands in its slot, as in the app. A
   spring retargeted mid-flight keeps its velocity, so the turn needs no extra motion.
7. **The hint resizes first, then changes its words.** The button springs to its new width while
   the old words fade out, and the new words fade in at that width. When it becomes a line of
   text, its background fades with the old words. When it becomes a button again, its background
   comes back with the new words. Its words stay on one line while it resizes.
8. **The closed toolbar is hidden** with `visibility`, after its fade.

## What was measured

Chrome traces and 60 fps recordings of both acts, driven by agent-browser at 1440 by 900 and at
iPhone 15 size.

| | Before | After |
| --- | --- | --- |
| Longest main-thread task, act one, Mac | 78 ms | under 12 ms |
| Longest main-thread task, act one, phone | 123 ms | under 12 ms |
| Longest main-thread task, act two | 13 ms | under 12 ms |
| Script time over act one, Mac | 119 ms | 17 ms |
| Script time over act two | 126 ms | 25 ms |
| Held frames in the stack's slide-in | 4 | 0 |

Compositor draws stayed under 0.5 ms at the 95th percentile. The recordings still hold a frame
here and there in act two, with no main-thread or compositor task behind it. The recorder's own
capture is the likely cause.

Esc pressed during the flight into the editor turns the card around. Afterwards the editor, its
toolbar and the dim are down, and no card is hidden. With Reduce Motion on, both acts still run
to their last step.
