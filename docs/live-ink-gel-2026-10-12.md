# Live ink: the person's lines as adaptive ice (2026-10-12)

Status: built (`InkGel.swift`, `InkGel.metal`). Its look is in the tweak panel's Live ink gel
section.

The person's live ink is a lit rod of light in place of red. Over dark content it is luminous ice:
a white middle falling to a cool blue at its edge, with a glow. Over light content a deep blue
sheath grows in from its edge. So the line stands out on any window.

## Scope

- **What changes:** only the lines on screen. That means the person's ink (`InkMarkLayer`) and the
  pen while it draws.
- **What stays the same:** the image sent to the agent. It draws marks with the shared renderer
  (`LivePacket.draw` calls `Mark.draw`), so it stays red. The skill's "red marks are the user's"
  stays true.
- **The agent's light:** unchanged. It keeps one hue, a core and a bloom.
- **The question's note pill:** stays red. Changing it is a follow-up.

## Why this look

Pete rejected two earlier directions. Rainbow hues swept along the line were "way too rainbowy". A
pale opal gel with a thin-film sheen read as "childlike". He asked for something futuristic and
tasteful, and said contrast with the content below would decide it.

So the lab measured each candidate's contrast over the backgrounds ink lands on. The measure is the
WCAG contrast ratio: the best ratio within 8 px of the line's middle, against the same pixel without
ink, with the median taken along the line. A single colour cannot clear 3:1 on both white and black.
Every single-tone material fell to about 2 on white, light grey, mid grey or yellow. Adaptive ice
clears 3.5 everywhere:

| Background | White | Light grey | Mid grey | Grey .46 | Grey .40 | Blue | Yellow | Green | Photo | Dark grey | Black |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Lab | 10.9 | 10.2 | 4.5 | 3.6 | 4.2 | 3.7 | 8.6 | 5.6 | 4.2 | 14.4 | 20.0 |
| App, in the VM | 12.4 | 11.3 | 4.2 | 4.5 | 5.7 | 3.5 | 9.2 | 6.0 | 4.1 | 16.7 | 20.1 |

## How it adapts

- **The brightness map.** `InkBackdrop` captures each display, without Vignette's own windows, when
  inking starts (the chord press) and after an answer is drawn, since the agent may have changed the
  window. While ink is on the screen it captures again 0.3 s after the person's last click, scroll or
  key, or when another app comes forward, so ink over a window that changed takes the colour that
  stands out there. Each capture lights macOS's purple screen recording indicator for a few seconds,
  so nothing captures on a timer: a change nobody caused, such as a video playing under the ink, is
  read at the next interaction. Each capture is drawn down to a grid of 8 pt cells (`LivePacket.Luminance`). It takes about
  100 ms, so the map is there before most strokes start. Cells this size follow windows and regions,
  not the letters of a text, so the ink does not flicker along a line of type.
- **One colour a stroke, by contrast.** A stroke is read every 8 pt along its centre line. At each
  reading, the colour with the higher contrast ratio against that cell wins (`InkContrast`). A stroke
  almost all over cells where the ice wins is the ice, one almost all over cells where the deep blue
  wins is deep blue, and one with a real share of both takes the sheath look below. The shader takes
  the stroke's colour as one uniform. Before 2026-10-12 each pixel chose by a brightness threshold,
  and a stroke across mixed content was striped
  (`docs/live-ink-lamp-and-stroke-colour-2026-10-12.md`).
- **The sheath.** Between the two, the deep blue grows in from the line's edge rather than the two
  colours mixing. A half mix is a mid colour, which stands out from nothing: over a background where
  the two tie it measured 2.5. A light middle in a dark sheath measured 3.5 there.
- **A new colour eases in** over 0.2 s times the motion scale, when the backdrop is read again or
  the pen crosses onto other content. Ink drawn before the first map is the ice.
- **No Screen Recording:** there is no map, and the ink is the ice. It stands out on dark windows
  and is faint on white. Live ink's asks need the permission anyway.
- **The done state** is the same rod in green: the green takes the ice's place, and a darker green
  the deep blue's.

## As built

- **Drawing.** `InkMarkLayer` draws its mark into a `CAMetalLayer` (`InkGel`) as one shape: a
  distance field built from the line's segments and the arrow's head, lit as one rod-like surface
  whose highlight follows every bend. `docs/live-ink-one-material-2026-10-13.md` has the design.
- **Where a layer is.** A mark is drawn in its window's overlay or the screen's, so a layer's own
  points are not screen points. The layer finds its overlay window through the root of its layer tree
  and converts its frame to global top-left points before it reads the map.
- **Glow.** The glow and the shadow come from the same distance field, outside the shape. A loop
  that crosses itself is not brighter where it crosses. Over light content the glow mostly goes,
  since an overlay can only tint there.
- **Motion.** `InkClock` is one display link for every gel layer. It drifts the light and a slow
  shimmer along the line at about 30 frames a second, and draws every frame while a line eases onto
  its shape or a map fades in. Its time runs at `inkGelMotion` times the motion scale, so motion 0
  holds the gel still and the link rests. A tweak redraws every gel.
- **What stays the same.** `show`, `showPen`, `ease`, `drawOn`, `undraw`, `twin` and `centreLine`.
  Drawing on and undrawing go through a reveal mask wide enough for the glow.
- **The pen.** A point's width compares how fast the hand moved there with its speed over the 48
  pointer events before it (`InkHand.Pen`), so a drawn part of the line never changes. Points a later
  event cannot move are laid out once into buffers that only grow (`SettledLine`), and each event
  lays out only the last few. An event costs the same at any length: in unit timing, 0.1 ms at
  500 pt and at 12,000 pt. Before, it rebuilt the whole line: 13 ms at 1,500 pt and 65 ms at
  12,000 pt, so long lines dropped frames.
- **Width.** The line is `inkGelWidth` wide, 5 pt. Hit testing and the image sent to the agent still
  use the mark's own style.

## Verified

In the `vignette-e2e` VM (macOS 15.7.7). The app ran from Terminal so it had Screen Recording, over a
window of bands, a light page and a dark terminal, with strokes from `vignette://live-ink-stroke`:

- **Contrast** as in the table above, measured from the VM's screen against the same screen without
  ink. `.scratch/gel-test/contrast.py` does the measuring.
- **The map** came 97 ms after the chord press (`[live-ink] backdrop read`).
- **Ink drawn before the map** was the ice, and turned when the map came.
- **CPU.** The app used about 4% while idle with four marks up.

An earlier round of the same layer checked motion 0: no pixel changed over 3 s.

Not checked yet: the thinking light over the deep blue, a real 120 Hz display, and two displays.
