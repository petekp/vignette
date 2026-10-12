# Live ink: the person's lines as iridescent gel (2026-10-12)

Status: Pete picked A, opal, and it is built (`InkGel.swift`, `InkGel.metal`). Its look is in the
tweak panel's Live ink gel section.

Pete asked for the person's live ink lines to be an iridescent gel with an emissive glow,
in place of red.

## Scope

- **What changes:** only the lines on screen. That means the person's ink (`InkMarkLayer`) and the
  pen while it draws.
- **What stays the same:** the image sent to the agent. It draws marks with the shared renderer
  (`LivePacket.draw` calls `Mark.draw`), so it stays red. The skill's "red marks are the user's"
  stays true.
- **The agent's light:** unchanged. It keeps one hue, a core and a bloom.
- **The question's note pill:** stays red. Changing it is a follow-up.

## Two earlier decisions this touches

- **Colour says who drew a mark.** Pete's request replaces red on screen. Material still tells the
  marks apart. The person's gel has moving hues, a glassy body and a specular line. The agent's
  light has neither.
- **The rejected "Intelligence gradient".** It looked like Siri's edge glow
  (`docs/live-ink-look-2026-10-07.md`). The gel takes its hue from the stroke itself: the place
  round the loop, the distance along the line, or the line's direction. It does not sweep a rainbow
  across the screen. The colours come from a thin-film model, so they read as a material, the
  way a soap film or oil on water does.

## The looks

The lab is `.scratch/gel-lab/`. It draws each stroke as a triangle strip. Each vertex holds its
place across the stroke and along it, which is how a shipped Metal version would draw it too. The
strokes are 5 pt wide, against 3.5 pt for today's ink. A gel needs that width to show its body.

**Round 1 was rejected as too rainbow-like.** Its hues swept along the line or round the loop, so
the line read as a gradient masked by a stroke.

**Round 2 lights the line as a solid rod.** Its colour comes from the material, not from a gradient:

- **The light follows the line.** Each pixel's normal turns with the line's direction and its
  place across the line. So the highlight sits where the rod faces the light, and it slides round
  every bend.
- **The iridescence is a thin film.** It is a coating of high-order thickness, which gives pale,
  pearly colours. Its colour shifts with the view angle, so the rim differs from the middle. It also
  shifts with the line's direction to the light, so a bend changes it.
- **The motion is the light.** The light wanders a few degrees, and the film drifts slowly. The
  sheen moves along the curves. Nothing sweeps across the screen.

| Look | Body | Iridescence |
|---|---|---|
| A Opal | Milky, pale grey | Pearly at the rim and in the sheen |
| B Glass rod | Nearly clear | Only at the rim and in the highlights |
| C Smoked gel | A deep, near-neutral body | A soft sheen, like oil on water, where it catches light |

Each look draws in Metal. On light pages, A and C hold up, and B nearly disappears.

## Constraints

- **Light pages.** An overlay cannot brighten white, so the glow only tints there. The lab gives
  the gel a darker rim and a soft shadow on light pages. Yellows and cyans thin out on white.
  Looks A and C hold up there.
- **Motion.** The hue drifts slowly. The thinking light already runs along the ink, and the gel's
  drift must not compete with it. While the agent thinks, the flow could speed up in place of the
  band. The drift goes through `Settings.motionUI` and stops at motion 0.
- **Cost.** A Metal version draws one small layer per mark, and redraws only while it moves. Ink
  sits on screen for a whole turn, so the drift should run at a low rate, or stop once the ink
  settles.
- **What `InkMarkLayer` must keep doing:** `showPen`, `ease`, `drawOn` and `undraw` through the
  reveal mask, `twin` for the green done state, `centreLine` for the thinking band, and the pick
  preview. The Core Animation path keeps all of them as they are. A Metal path takes the outline's
  vertices from `InkMarkLayer.outline` and keeps the reveal mask as a layer mask.

## As built

- **Drawing.** `InkMarkLayer` draws its line into a `CAMetalLayer` (`InkGel`). Each vertex of the
  line's triangle strip holds its place across the line and along it, its half width and its tangent.
  The shader lights the line as a rod and adds the film's colour.
- **Glow.** A halo strip under the line, wider by the glow's reach, draws the glow and the shadow in
  one pass, with max blending. A loop that crosses itself is not brighter where it crosses, and a
  tight bend does not show the halo's folds. Over a dark window the glow adds light. Over a light
  one the shadow wins.
- **Bloom.** The glow is brightest where the line faces the light (`inkGelBloom`), so it moves with
  the sheen.
- **Motion.** `InkClock` is one display link for every gel layer. It drifts the light and the film
  at about 30 frames a second, and draws every frame while a line eases onto its shape. Its time runs
  at `inkGelMotion` times the motion scale, so motion 0 holds the gel still and the link rests. A
  tweak redraws every gel.
- **What stays the same.** `show`, `showPen`, `ease`, `drawOn`, `undraw`, `twin` and `centreLine`.
  Drawing on and undrawing still go through a reveal mask, now wide enough for the glow. The green
  done state is the same gel in green.
- **What went.** The wet streak behind the pen and the layered Core Animation bodies. The gel's own
  highlight takes the streak's place.
- **Width.** The gel's line is `inkGelWidth` wide, 5 pt. Its arrowhead is sized for that width. Hit
  testing and the image sent to the agent still use the mark's own style, so they are unchanged.

## Verified

In the `vignette-e2e` VM (macOS 15.7.7), over a light page and a dark terminal, with strokes from
`vignette://live-ink-stroke`:

- **Loops, curved arrows and a sharp V** all draw, and so do their arrowheads.
- **No seams or folds** show where a loop crosses itself or the V turns.
- **The drift runs.** About 72,000 pixels changed over 3 s with the ink idle.
- **CPU.** The app used about 3% while idle with five marks up.

Not checked yet:

- **On a real display** at 120 Hz.
- **The thinking light** over the near-white gel.
- **Motion 0.**
