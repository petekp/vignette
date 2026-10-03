# Landing page: interaction pass (2026-10-02)

A pass over the page's microinteractions for speed, smoothness and touch. The page and its plan are
described in `docs/landing-page-2026-10-02.md`.

## What was wrong

1. **A flight repainted its picture on every frame.** A card flying into the editor or back changed
   its `left`, `top`, `width` and `height` each frame, and so did the picture inside it. The browser
   redrew the screenshot and its marks, notes included, at each new size, about 20 times a flight.
   Its shadow was also a new `box-shadow` each frame.
2. **The ring on a hint's target repainted the target.** It animated `outline-offset`, which is
   paint, so the card under it was redrawn on every frame while the ring was up.
3. **On a phone, scrolling closed the demo.** A press outside the stage closed the stack or the
   editor on `pointerdown`. A finger that starts a scroll sends one, so scrolling past an open demo
   closed it.
4. **Hover styles stuck after a tap.** iOS keeps `:hover` on the last thing tapped, so the hint and
   Download stayed lifted.
5. **Presses gave no feedback on iOS.** Safari applies `:active` only when the page listens for
   touches.
6. **The hint jumped between widths** when its text changed.
7. **Offscreen work went on.** The trailer kept decoding while scrolled away, and the ring and the
   spinner kept animating.
8. **Touch details:** the grey tap flash on buttons, and the long-press menu on the stage's images.

## What changes

1. **Flights move with transforms.** The flight, its shadow and its picture are laid out once, at
   the size they have in the editor, and each frame sets only a `transform`: the flight's
   translate and scale, the picture's own scale against it so it is never stretched, and the
   corner radius against the scale so the corners stay round. The shadow is a separate layer cast
   at the editor's size: scaled down to the card, its blur and offset shrink with it, which is the
   card's own look, and its opacity carries the rest. The picture and its marks are drawn once
   and moved by the GPU.
2. **The ring is a composited layer.** It is an element added inside the target, around it, that
   animates only `transform` and `opacity`. A card's clip moves to an inner layer, so the ring can
   sit outside the card. It grows in when it appears, then breathes: two animations, one after the
   other, switched on `animationend`.
3. **Touch closes the demo only on a tap.** For touch and pen, the press outside counts at `click`,
   which a scroll never sends. The mouse keeps `pointerdown`, as the app does.
4. **Hover styles apply only where the pointer can hover** (`@media (hover: hover)`).
5. **The page listens for touches,** so `:active` works on iOS.
6. **The hint springs to its new width,** and its label and keys cross-fade.
7. **A stage out of view pauses its animations, and the trailer pauses** until it is back in view.
8. **No tap flash, and no long-press menu** on the stage.

## What was measured

Chrome traces of the page, driven by agent-browser at 1440 by 900.

- **The ring costs nothing while it waits.** One idle second with a ring up recalculated style 130
  times before the change and 0 after. Two things had kept it on the main thread: a `var()` in its
  keyframes, and listing the grow-in and the breathing as two animations at once, even after the
  grow-in had ended. Each one alone was enough.
- **A flight no longer lays out each frame.** Over one flight into the editor, layout fell from
  about 1.4 ms to about 0.1 ms in two of three runs. Paint and raster stayed about the same: Chrome
  already scaled the old flight's picture on the GPU. The change matters more where redrawing the
  marks' SVG text is slow, which Safari has not been measured for.
- **Frame intervals showed nothing either way.** Headless Chrome holds frames to its own vsync, and
  a dropped frame came at random in both versions.

Touch was checked with synthetic pointer events: a touch that turns into a scroll leaves the stack
open, a tap outside closes it, and a mouse press outside closes it at once.

In Safari on the iOS Simulator (iPhone 16), the square stage, its camera framing and the hint
render as in Chrome. The simulator cannot post taps, so touch there is still unchecked by hand.
