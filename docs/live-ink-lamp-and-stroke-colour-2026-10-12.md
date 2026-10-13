# Live ink: one colour per stroke, and a living Lamp (2026-10-12)

Status: built on `live-ink`.

Two changes to how live ink looks while drawing.

## One colour per stroke, chosen by contrast

**Problem.** The gel picks ice or deep blue for each pixel from the brightness of the 8 pt cell
behind it. A stroke across mixed content flips colour at every boundary and reads as a striped rope.
The choice is a brightness threshold (`inkGelSwitch`), so a saturated mid-tone such as a blue band
gets deep blue on blue.

**Change.**

- Each stroke has one colour state for its whole length, a number from 0 (ice) to 1 (deep blue).
  The shader takes it as a uniform, in place of reading the brightness maps per pixel.
- The state comes from the content behind the stroke, sampled every 8 pt along its centre line. At
  each sample the colour that wins is the one with the higher contrast ratio (WCAG) against that
  sample's luminance, using the two colours the person set (`inkGelLight`, `inkGelDeep`).
- A stroke almost all over content where ice wins is ice. One almost all over content where deep
  blue wins is deep blue. A stroke with a real share of both takes the sheath look: a light middle
  in a deep sheath, which is the state the gel already has for standing out from anything.
- The state eases to a new value over 0.2 s (times the motion scale) when the backdrop is read
  again or the pen crosses onto other content, so nothing snaps.
- `inkGelSwitch` and `inkGelSwitchWidth` go: the contrast rule replaces them. With Pete's colours
  (#0085ff and #051a91) the two colours tie at a cell brightness of about 0.35, next to the 0.31
  he tuned by hand.
- The brightness maps stay on the CPU only. The textures, their fade and the shader's sampling go.

**Why per stroke, not per area blended along the line.** A line is one mark, and one colour says
so. A stroke over mixed content gets the sheath look, which was built for exactly that case.

## The pointer: Lamp, coloured like the ink, and alive

Pete already uses Lamp. Two things are wrong or missing.

- **Its colour.** Every ring style is tinted from the old red person colour, so a pink pool sits
  at the pen while the ink is blue. The field now takes the gel's colours: the lamp is the ice over
  dark content and deep blue over light content, from the same contrast rule, read at the pointer
  each frame and eased over 0.3 s as it crosses onto other content. Every ring style takes these
  colours. Over light content the deep
  blue pool darkens what is behind it, so it shows on white, where a light glow cannot.
- **Its life.** The lamp is static apart from following the pointer. It gains:
  - a slow breath, the pool's size and light rising and falling over a few seconds;
  - energy from the pointer's speed: brighter and wider while moving fast, settling back at rest;
  - a slow drift of light inside the pool, so it glows rather than sits.

  Each has a tweak in the Pointer section, and the motion scale and Reduce Motion turn the breath
  and the drift off. The press brightening it already has stays.
- Lamp becomes the default style, since it is the direction for the pointer. The other styles stay
  in the Pointer Lab for now.

## Not in this change

The arrowhead drawn as gel, a clearer difference between the person's ink and the agent's light,
and reading the backdrop again while ink is on screen.

## Verified

In the `vignette-e2e` VM, with Pete's ink and pointer values:

- A scribble across white, greys, blue, yellow, green and black was one colour along its whole
  length, in the sheath look, where it had been striped.
- The lamp was a deep blue pool over white and an ice pool over dark content.
- With the pointer still, the lamp's lit area changed from 1153 to 1722 px between two captures
  1.75 s apart, about half a breath.
