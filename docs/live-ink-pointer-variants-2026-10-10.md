# Pointer field variants, 2026-10-10

The ring round the pointer and the wake behind the pen each have several styles now. The Pointer
Lab picks them with two segmented controls and shows only the sliders a style uses. Picking a style
keeps the other keys, so tuning carries from one style to the next.

Glass, the ring from before, is ring style 0 and the default. Ripples, the wake from before, is wake
style 4. The default wake is now Ribbon, style 0, so a settings file that does not name a style shows
Ribbon. Every other default is unchanged.

## Ring styles (`ui.liveInkFieldStyle`)

| # | Style | What it is | Its own sliders |
|---|---|---|---|
| 0 | Glass | Today's ring: a soft ridge of glass that bends the screen toward its crest and glows. | Bend, Colour split |
| 1 | Lens | A clear bead. The rim draws the screen in, the middle can magnify about the arrow's tip, and a rim light, a highlight and a soft shadow let it read on white. | Bend, Colour split, Zoom, Clear middle, Shine, Shade |
| 2 | Squircle | The Glass ridge on a rounded square with continuous corners. Break leaves only the four corners. | Bend, Colour split, Squareness, Break |
| 3 | Droplet | Glass at rest. Moving, a teardrop with a round head leading and a tail behind, as long as Stretch allows. | Bend, Colour split |
| 4 | Lamp | No edge: a soft pool of ink-coloured light round the arrow. It never reads the screen. | Spread, Clear middle |
| 5 | Caustic | Light through a glass: a thin edge, and a bright crescent gathering to a point on the side away from the light, fringed by Colour split. | Bend, Colour split, Depth, Shine, Shade |

Every style also takes Size, Glow, Follow and Stretch. All of them light from the top left.

## Wake styles (`ui.liveInkWakeStyle`)

The four new wakes share one smooth field. Each point of the pen's path is a bump that is exactly 0
at its radius. A point comes in over Rise, starts to fade at "Fade starts", and widens as the square
root of its age while it flattens, so the field has one sign and never oscillates. That is what
removes the watery look: Ripples is a packet of waves, and these are a single swell.

| # | Style | What it is | Its own sliders |
|---|---|---|---|
| 0 | Ribbon | A beat behind the pen, the screen near the stroke spreads outward in one swell, wider and flatter as it fades. Swell below 0 pulls it in. | Swell, Colour split, Light |
| 1 | Silk | The screen leans the way the pen went and settles back. Capped at 4 pt and slower to rise, because it moves the screen under the pen's own ink. | none |
| 2 | Mist | A plume of ink-coloured light in slow clumps, drifting up as it fades, over a very slight swell. | Swell, Light, Clumps |
| 3 | Frost | The band behind the pen goes soft, as if breathed on, and clears from its edges. | Swell, Blur, Light |
| 4 | Ripples | Today's rings of waves. | none |

Styles 0 to 3 also take Lift, the most they move the screen in points, and Widen, Rise and Fade
starts. Every style takes Strength, Size and Duration. Size is how far the wake reaches from the
stroke, and Lift is held to a quarter of its narrowest radius.

## Rules that are not obvious from the code

- **Nothing near the pointer moves.** The wake is masked within 1.3 ring radii of the ring, measured
  in the ring's own shape: stretched with it, or along the Droplet's tail. The ring's layer samples
  the screen as it is, so a wake moving the screen there would show it twice.
- **The bend stops short of folding.** The ridge styles cap their pull at 0.9, which is Bend 1.8.
  Past it the glass folds where the ridge is steepest. Colour split above 1 with Bend above 1.4 can
  still reverse one colour channel at the steepest point.
- **Light is a tint, not added light.** Drawing light with no coverage (rgb above alpha) was meant to
  glow on dark pages. Measured in the VM, Lamp at full add showed nothing at all over white, grey
  and black: the window server keeps no colour where a window's pixel has no coverage. So Lamp,
  Caustic and Mist draw as tints, which show on every page.
- **A style that only lights takes no picture.** Lamp, or a wake made only of light, starts no screen
  capture and no recording indicator.
- **The wake's points.** Styles 0 to 3 keep a point every 0.4 of the narrowest radius and fill a long
  step with up to 6 points, so a flick stays one smooth stroke. A full trail of 96 merges its oldest
  points in pairs within a stroke rather than dropping them, since dropping a point that still shows
  makes its part of the field jump. Ripples keeps one ring every 6 pt.
- **The ring's layer.** It reaches as far as the style draws (Lamp's pool, the Droplet's tail), is
  clipped to the screen, and is capped at 600 pt each way.

## Checked

In the VM, over a grid page, with Size 20, Glow 0.85, Split 1 and Follow 0.04 for the ring:
every ring style drew as described, still and moving.

The wakes were measured 0.3 s after a drag, against the same screen once the wake had gone, along
the stroke and away from the ring. The table gives the share of pixels that changed by more than 8
levels, at Duration 1.65 and Strength 1.

| Style | Size 300 | Size 60 |
|---|---|---|
| Ribbon | 17.4% | 4.2% |
| Silk | 8.7% | 3.7% |
| Mist | 11.2% | 2.4% |
| Frost | 13.1% | 2.7% |

The GPU time per drawing was about 1 ms on average for every style, with no style clearly dearer.
The VM's GPU is emulated, so that compares the styles and says nothing about real hardware. The unit
tests cover the trail's spacing, fill and merge.

Not checked: how each looks on Pete's display at 120 Hz.
