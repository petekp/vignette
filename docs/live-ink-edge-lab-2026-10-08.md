# Live ink: the edge lab (2026-10-08)

While Control and Option are held, live ink draws a glow along the screen's edges. It says the
screen is taking ink. Pete asked to try other looks for it, lens distortion and refractive glass
among them, with a panel to tune them.

Status: built and checked in the macOS 26 VM, uncommitted, on branch `glow-lab` in
`~/Code/worktrees/vignette/glow-lab`, from `live-ink` at 8bc5a6f. Not yet seen on Pete's Mac or on
macOS 15.

## The question

Which look should the edge have while inking? A look that bends the screen's own pixels needs a
live picture of the screen. So the question under it is whether that picture holds up on Pete's
Mac: how soon it starts, whether the band shows a seam, and what it costs.

## The plan

1. **Prove the capture path with one look.** A ScreenCaptureKit stream of the display, drawn by a
   Metal layer in the live ink overlay as a glass rim. Check it in the VM for:
   - **No feedback.** The stream leaves out the overlays by window id.
   - **No second cursor.** The stream leaves out the pointer.
   - **No seam.** The bend and the opacity both reach zero at the band's inner edge, and the stream
     and the layer share a colour space.
   - **Start.** The stream starts when the chord goes down. The look fades in from its first frame.
   - **Cost.** The log gives the time to the first frame, the frame rate and the CPU.
   - **Failure.** With no Screen Recording, or a stream error, today's glow shows.
2. **Then the other looks and the lab.**
   - The looks: today's glow, an aurora that flows round the edges, glass, a lens that squeezes the
     edge, a ripple, and frost.
   - The lab is `vignette://edge-lab` (needs `debug`). Its sliders are `ui` settings, so a value
     tuned there is the one live ink draws with.
   - Its preview holds the look on screen at the inking level and passes every press through.
3. **Verify and share.** Every look is checked in the VM, never on Pete's screen. The comparison
   card is a VM capture of each look at its starting values.

## Findings

**The capture path holds up in the VM.** Glass, lens, ripple and frost draw from a live picture of
the screen, and every check passed:

| Check | Result |
|---|---|
| First frame after the request | 51 to 161 ms in every start measured |
| Through the real chord | the look shows 262 ms after the chord, 250 ms of it the glow delay |
| CPU on a still screen | 1.5 to 2.8 % |
| The overlay in its own picture | never: the stream leaves it out by its window id |
| A second pointer | never: the stream leaves the pointer out |
| A seam at the band's inner edge | within 1 level in 255, with tint, shine and split at 0 |
| After the chord is let go | the feed stops once the fade is over, 0.25 s at the default fade |

**macOS shows that the screen is being recorded.** While a look that draws from the screen is up,
the purple recording indicator shows in the menu bar, and it goes when the feed stops. Pete
accepted this on 2026-10-08. Glow and
aurora draw only light and start no feed. Live ink already uses ScreenCaptureKit when it sends, so
these looks need no new permission. They add the indicator for as long as the chord is held.

**Without the picture, the glow shows.** With no Screen Recording, or when the stream stops with an
error, live ink draws the glow, and the next chord tries the picture again. In the VM, a copy never
granted Screen Recording logged `edge feed could not start: noPermission` when the look was held,
and showed the glow along all four edges. Holding it again tried the picture again and showed the
glow again. macOS raised no prompt.

**A stream that stops with an error falls back to the glow.** In the VM, killing `replayd` while
the look was held stopped the stream with `SCStreamErrorDomain -3805`. The glow took over along all
four edges, and holding the look again brought it back, its first frame in 97 ms. A stream that
stops lets its last picture go, and a new stream keeps only its own frames, so the look never
draws the screen as it was before the chord.

**The picture starts in about 100 ms.** On Pete's Mac, macOS 15 on an M4 Max with its built-in
display, the Edge Lab's preview drew its first frame 100 ms after asking for it, and a stream
started from a terminal gave its first frame in 57 to 170 ms. A chord showed the look 330 to 415 ms
after it went down. Of that, 250 ms is the glow's wait (`liveInkGlowDelay`), so Control-Option on
its way to a shortcut does not flash it. The rest was speech input starting the microphone on the
main thread before the glow could show. The microphone now starts on its own queue, after the glow
(`Microphone`). `edge first frame` logs `ms`, how long the look waited for its picture once it was
wanted, and `stream-ms`, the time since the chord. While inking, the picture came at about 61
frames a second, the stream's cap of 60.

**The log gives the GPU's time.** `edge feed stopped` also says how many times the look was drawn
and the GPU's time for each drawing: `drawn=232 gpu-ms mean=1.32 max=17.62` in the VM. A look keeps
up while that stays well under a refresh, 8.3 ms at 120 Hz.

**Moving looks and the wake cost more.** A look that moves, or a wake with rings, redraws every
refresh. In the VM, aurora ripple held the app at about 16 % CPU, and the wake peaked at 29 % during
a drag. The VM's GPU is not a real one, so these say little about a real Mac.

**The frame rate is not measured.** The VM reports the whole screen as changed about 30 times a
second, even on a still page. So the VM cannot say how often a real Mac sends frames, or whether
the band lags behind fast scrolling. Pete's display runs at up to 120 Hz, and the stream is capped
at 60, so the band may trail fast-moving content there by a frame.

**Four problems were found in the VM and fixed:**

- *The app hung.* Drawing on each frame's arrival queued a main-thread block per frame. The run
  loop never got back to commit the layer, so each `nextDrawable()` waited out its one-second
  timeout. The layer now draws only from its display link, at most once a refresh.
- *The lens folded back.* Past a squeeze of 0.5 the band showed the same text twice. The squeeze
  now stops where the picture still keeps its order.
- *Glass folded back at its rim.* The rim is a quarter circle, whose slope grows without limit at
  the edge, so the outer fifth of the band showed the toolbar again, backwards. From where it would
  fold, the rim now goes on straight, and the picture magnifies at most five times.
- *Frost showed copies.* A 13-tap blur showed sharp edges as ghost copies. It is now 24 taps in a
  spiral, turned by a different angle at each pixel, so a wide blur reads as grain.

## What is in the build

- **Seven looks,** picked by `ui.liveInkEdgeStyle`: glow, glass, lens, aurora, ripple, frost, and
  aurora ripple, where ripple's waves bend the screen and aurora's light rides on their crests.
  Glow is `EdgeGlow`. The others are one Metal shader, `Sources/EdgeLens.metal`, drawn by
  `EdgeLensLayer` under the marks, so ink near the edge stays sharp.
- **The aurora's colours,** in aurora and aurora ripple. The light takes the ink colour, a
  rainbow, or two picked colours (`ui.liveInkEdgeColors`, `liveInkEdgeColor1`, `liveInkEdgeColor2`).
  Repeats, a whole number so the colours meet themselves without a seam, hue shift, saturation,
  brightness and drift change any of them. Aurora ripple's light meets the screen through a blend
  mode (`ui.liveInkEdgeBlend`): normal, add, screen, overlay, soft light, colour dodge, multiply,
  colour or difference, each as CSS defines it. Plain aurora draws light alone, with no picture of
  the screen to blend with. Their defaults reproduce Pete's tuning: the ink colour, blended normally.
- **The display's shape.** The band follows the display's corners and goes round its notch, so on
  a MacBook it hugs the screen it is drawn on. macOS reports the notch, through the menu bar's
  areas either side of it, but not the corners. MacBook displays with a notch round their top
  corners and not their bottom ones, so such a display gets rounded top corners of
  `ui.liveInkEdgeCorner`, an estimated 10 pt, and every other display square ones. The notch's
  bottom corners are an estimated 8 pt. Checked in the VM with a notch put in by hand, since the VM
  has none.
- **The wake,** with any look. While the pen draws, a ring spreads from each point it passes and
  bends the screen under it, like water behind a boat. Each ring lasts `ui.liveInkWakeDuration`
  and spreads `ui.liveInkWakeSize` points. `ui.liveInkWakeStrength` at 0 turns it off. It reads the same live picture as the looks, so it shows the recording indicator too.
  The ink is drawn above it and stays sharp. In the VM, 0.3 reads as a slight waver of the lines
  behind the pen, and 0.6 as a clear ripple.
- **The Edge Lab,** `vignette://edge-lab` or the tweak panel's Edge button (needs `debug`). It picks
  a look, starts it from that look's own values, and shows the sliders that change it. "Hold on
  screen" keeps the look up at the inking level and passes every press through.
  `vignette://edge-lab?preview=1` and `preview=0` do the same from a script.
- **The settings** are `ui.liveInkEdge*`, with bounds. Opacity and fade are the glow's own
  `ui.liveInkGlowOpacity` and `ui.liveInkGlowFade`. Speed is scaled by the motion setting, so
  Reduce Motion holds aurora and ripple still.

## Pete's tuning

On 2026-10-08 Pete tuned aurora ripple and the wake in the lab, and those values are the defaults:
aurora ripple at width 38, wave height 2, light 1, colour split 0.5, line 0.89, speed 1.51, and
the wake at strength 0.95, size 36 and duration 0.85. The glow's own width is 29 and its fade 0.5.

## Still open

- How the looks do on macOS 15 and over fast scrolling. Pete tuned aurora ripple and the wake on
  his Mac, on macOS 15, so those draw there. The other looks were not checked there, and nobody has
  watched one over a fast scroll.
- More than one display. Each screen starts its own picture and display link. Pete's Mac has one
  display, and the VM supports only one.
- What the GPU spends on a real Mac, for each look and for the wake while really inking. Glass
  with frost and colour split reads 72 samples for each pixel in the band, and each pixel near the
  pen sums up to 96 of the wake's rings. The `gpu-ms` in the log answers both once Pete has inked
  with this build.
- Whether the wake makes the ink lag behind a long, fast stroke on Pete's Mac.
- Whether the look now shows about 250 ms after the chord on Pete's Mac, with speech on.
- Ripple at its highest waves can still fold the picture back. It was left, since its waves are
  meant to distort.
- Whether 10 pt matches the real top corners of Pete's display, and 8 pt the notch's.
