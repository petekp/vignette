# Live ink: a more refined look (2026-10-07)

Status: built on branch `live-ink`, not yet committed. Plan steps 1 to 8 are done.
Pete asked for a more sophisticated, dynamic look for live ink, with more shaders and annotations
that look more native to macOS.
The renders come from a throwaway lab in `.scratch/look-lab/`, which Git ignores. The gallery is
`.scratch/look-lab/out/gallery.html`.

## Recommendation

Draw the person's marks as **ink** and the agent's marks as **light**. Put the words in **system
materials**.

- **The person's ink.** The stroke's width follows the hand: wider where it slowed, thinner where it
  sped up, tapered where the pen landed and lifted. On release a loop eases into its recognised
  ellipse over about 0.3 s and keeps the hand's widths. Fresh ink carries a sheen that dries in
  about half a second.
- **The agent's light.** A bright core in the agent's indigo with a soft bloom around it. A glint
  leads the mark as it draws itself on, and the bloom settles once it is done.
- **Thinking.** While the agent works, a band of light runs along the person's ink and then crosses
  their note. It replaces today's band that dims the marks to 40%.
- **The answer.** A popover attached to what the answer points at: Liquid Glass on macOS 26, the
  popover material on 14 and 15. Its first line names the agent and quotes the question, and the
  question's pill fades as it arrives. The words fade in one at a time, and the popover springs to
  fit them.

The reasons:

- The material says who drew a mark, as well as the colour does. Ink reads as drawn by hand. Light
  reads as pointed out by a machine. That works for someone who cannot tell red from indigo.
- It matches `docs/LIVE_INK_VISION.md`: "Ink behaves like ink on paper", and you can see where the
  agent is looking.
- macOS has no ink for drawing over other apps, so the marks need custom drawing. The containers
  do have system versions, and the system adjusts those for Reduce Transparency (not tested here).
- It keeps the rule that a mark's colour says who drew it: red for the person, indigo for the agent.

Leave the multi-colour gradient out. Its reasons are below. The spotlight became a capability of
its own: the agent pulling focus to what it means (Pulling focus, below).

## The looks

Each look ran over two synthetic scenes: a light checkout page and a dark terminal. The person
loops something and asks; the agent thinks, answers and points. Each run is 6.6 s at 30 fps.

| Look | Person's marks | Agent's marks | Thinking | Words |
|---|---|---|---|---|
| Today | Flat, white edge, snaps to an ellipse | Flat, white edge | Marks dim to 40% in a sweeping band | The question goes in one frame |
| Ink | Ink | Ink, in indigo | Light along the ink | Ink pills, the question grows into the answer |
| Ink and light | Ink | Light | Light along the ink | Frosted glass, the question grows into the answer |
| Intelligence gradient | Ink | Light in moving colours | Light along the ink | Glass with a moving gradient rim |
| Spotlight | Ink | Light | Light along the ink | Glass; the screen dims around the agent's target |
| Native materials | Flat, eases into the ellipse | Focus-ring style ring | Today's band | A popover attached to the target |

**Today.** The lab reproduces the current look to compare against. It shows four rough edges:

- On release the stroke becomes the recognised ellipse in a single frame.
- The thinking band lowers the marks' opacity, so the marks seem to fade rather than work.
- The question disappears in a single frame as the reply springs in, and the reply's tag changes
  size with each word.
- The edge glow is a 10 pt band at half opacity, and half of it is off the screen.

Reading the code shows one more: the note panel's window shadow is not the drawn tag's
shadow, so the two differ at the handover.

**Ink.** The person's marks and the agent's are both ink, the agent's in indigo. It looks calm and consistent. But the
agent's marks look hand-drawn, which suggests a person drew them, and colour becomes the only cue
to who drew a mark. Indigo ink almost disappears on a dark screen. The lab lightens ink by 16%
over dark backgrounds to keep it visible.

**Ink and light (recommended).** The details, as rendered:

- Ink width is 3.5 pt times a factor from the hand's speed, between 0.72 and 1.4, smoothed, and
  tapered over the first 14 pt and the last 26 pt.
- Over a light background the ink casts a soft shadow. Over a dark one it glows in its own colour.
- The agent's core is white over dark backgrounds and indigo over light ones. The bloom settles
  over 0.9 s after the mark is drawn.
- The thinking light is about 40 pt long and runs along the ink every 1.15 s.

On a light page the light look is quieter. The core turns indigo and the halo darkens instead of
glowing. That is the right direction, but it needs tuning on a real screen.

**Intelligence gradient.** The agent's light cycles through blue, purple, pink and orange, and so do
the edge glow and the answer's rim. It looks the most like AI of the six, which causes two problems:

- It looks like Apple Intelligence and Siri's edge glow, so a person may think Siri is listening.
- Colour stops saying who drew a mark.

**Spotlight.** The screen dims around the agent's target for a moment, then eases back halfway. It
draws the eye more than any mark does. But it changes the whole screen for one answer, and on a light page
the undimmed area reads as a white patch. Pete liked the idea of the agent pulling focus, and the next section
develops it.

**Native materials.** The agent's mark is a ring in the style of the keyboard focus ring, and the
answer is a popover whose arrow points at it. The real AppKit versions are in the next section.

## Pulling focus

Pete asked to develop the spotlight: the agent able to pull focus to something. The lab rendered
five ways, over the same two scenes. The focus comes in at 3.55 s, as the agent's mark starts to
draw, and lets go at 7 s.

| Look | The rest of the screen | The target |
|---|---|---|
| Iris | Dims | Unchanged |
| Rack focus | Blurs, loses its colour, dims a little | Stays sharp |
| Lift | Blurs and dims | Rises: 6% larger, with a shadow under it |
| Tour | As rack focus | The sharp area moves on to the next target, and the earlier mark fades to 35% |
| Loupe | Dims and blurs a little | Magnified 1.7× under a lens |

In every one the person's ink and the answer stay sharp, so the question and its answer stay in
focus with the target.

- **Rack focus reads best on both pages.** Taking the colour away does what darkness does in the
  iris, so a light page does not turn into a grey sheet with a white hole. The film term fits:
  everything else goes soft, and the target stays itself.
- **Tour lets one answer point at several things in order.** In the terminal it goes from the
  declaration of `inbox` to the line that uses it.
- **Loupe is for things too small to see:** a 1 px gap, a small icon, fine print. It covers what is
  next to the target, and near a window's edge it runs past it. It has to stay on the screen.
- **Lift is the most physical, but it moves pixels.** The target is drawn larger and a few points
  from where it really is, so a click aimed at it can miss.
- **Iris is the weakest on a light page.**

**Recommendation:** rack focus as the way the agent pulls focus, a tour when it points at several
things in turn, and the loupe when the target is small. Leave out lift and the iris.

**What the agent can ask for:**

- A `focus` mark in the answer, naming its target the way the other marks do. The agent says what
  to focus on. Vignette decides how it looks and how long it lasts.
- Several `focus` marks make a tour. Each moves on when the reply's words reach the sentence that
  goes with it, so the focus follows the reading.
- A `focus` mark with `zoom` asks for the loupe.

**The person stays in charge.** One focus shows at a time. It lets go on its own a few seconds
after the reply is whole: 2.5 s in the lab. It lets go at once when the person moves the pointer
away, scrolls, types or draws.

**Building it.** The effect is drawn from a picture of the window, captured when the focus starts.
The overlay shows that picture blurred and greyed, with the target cut out sharp; lift and loupe
magnify the same picture. A still picture works because live ink's marks already hold still while
the agent answers, and the focus lets go when the window changes. Live ink already captures
windows for the ask, with the Screen Recording permission it asks for. Without a picture, the
recent stack's backdrop is the fallback: masked `NSVisualEffectView`s (`BackdropPanel.swift`), with the
target cut out. That fallback blurs but cannot take the colour away.

## Native materials on real macOS

A small AppKit app (`.scratch/look-lab/native/NativeLab.swift`) put the real controls over the same
scenes. It ran in a macOS 26.6.2 VM and a macOS 15.7.7 VM.

- **`NSPopover`** attached to the target reads as macOS's own interface. On macOS 26 it is Liquid
  Glass: larger corners and translucent enough to show the terminal's text behind it. On macOS 15
  it is the older, more opaque popover with smaller corners.
- **The keyboard focus ring** is drawn by AppKit, but in the person's accent colour. That breaks the
  colour rule, and the accent can be red, the person's own colour. On the dark terminal the ring is
  dim. A ring of the same shape in the agent's indigo keeps the meaning; then it is a mark, not the
  system's ring.
- **A Liquid Glass question** tinted with the person's red looks close to today's pill. The plain
  glass version, with a red dot, reads as system interface and loses its tie to the ink.
- **A Liquid Glass answer and a popover-material answer** look almost the same over flat
  backgrounds. Glass shows its refraction only over detail behind it.

`NSGlassEffectView` in a borderless overlay window samples the other app's window behind it: over
TextEdit, it blurs TextEdit's toolbar and text (plan step 1).

## Building it

The overlays today are AppKit and Core Animation. `LiveInkOverlay.swift` holds the canvas and the
edge glow, `MarkLayers.swift` the shapes (`ShapeMarkLayer`, shared with the editor and cards), and
`LiveNotePanel.swift` the note being typed. The only shader in the app is `IntroFunnel.metal`,
loaded through SwiftUI's `ShaderLibrary`.

**Start with Core Animation.** Every part of the recommendation has a Core Animation form, and it
keeps the existing layer tree, motion scale and Reduce Motion handling:

- Variable-width ink is a filled outline built from the points and their widths, in place of a
  stroked path.
- The light is three shape layers: a wide coloured stroke with a blurred shadow for the bloom, a
  core stroke, and a small glint layer that follows the drawing head along the path.
- The thinking light is a short bright stroke whose `strokeStart` and `strokeEnd` travel along the
  ink, with a shadow for its glow.
- The drying sheen is a lighter stroke that trails the pen by a fixed length.
- The containers are `NSGlassEffectView` on macOS 26 and `NSVisualEffectView` with the popover
  material on 14 and 15.

**Move the ink to Metal only if Core Animation falls short.** The lab's sheen and highlight are
shaded per pixel from the stroke's direction, which Core Animation cannot do. A `CAMetalLayer` in
the overlay could draw the strokes with the lab's shader. The lab tests every stroke segment at
every pixel, which is fine for a lab and wrong for a 5K screen. A production version would draw
one small quad per segment, so the work follows the ink's area. SwiftUI's `layerEffect`, the path
`IntroFunnel.metal` uses, suits effects on a layer that already exists, like a sheen. It does not
suit strokes whose width varies along their length.

**Keep the shared renderer as it is.** The new materials belong to live ink's own layers
(`LiveMarksLayer`, `NoteLayer`, the edge glow). `ShapeMarkLayer` and `MarkRendering.swift` keep
drawing the editor, the cards and the PNGs.

**Reduce Motion.** With the motion scale at 0, the glint, the travelling light and the word fades
go. The thinking state becomes a steady brightening of the ink, and containers appear at full size.

Performance is not measured. None of the lab's timings say anything about the app.

## Plan

Pete chose on 2026-10-07: ink and light, a stroke that eases into its recognised shape, the answer
in a popover on its target, and a stroke of light for the agent. How the agent pulls focus is still
open. Each step is checked in a test copy on scratch settings, never in Pete's trial build.

1. **A popover from an overlay.** In the macOS 26 and 15 VMs, a panel built like `LiveInkOverlay`
   and `WindowOverlay` shows an `NSPopover` attached to a point in it, over another app's window.
   It passes when the popover takes neither the keys nor the active app from the person, when
   another window raised over the anchored one covers the popover as it covers the marks, and when
   the popover follows its window as it moves. The same check covers an `NSGlassEffectView` and an
   `NSVisualEffectView` with behind-window blending, the fallback if the popover fails. Step 6
   depends on it.

   **Passed on macOS 26.6.2 and 15.7.7.** A probe app (`.scratch/look-lab/native/OverlayProbe.swift`,
   run by `native/probe.sh`) built a panel with `WindowOverlay`'s flags over a TextEdit window and
   showed an `NSPopover` with `.applicationDefined` behaviour from a view in it. On both systems:

   - TextEdit stayed the active app, and the probe had no key window.
   - The popover's window is a child of the overlay, at the normal level.
   - A second TextEdit window raised over the first covered the popover and the ring together.
   - Moving the overlay by 80 and -60 pt moved the popover by the same amount.
   - The popover's material blurs the other app's window behind it: on macOS 15 the coloured words
     show through, tinted.

   On macOS 26 an `NSGlassEffectView` in the same panel blurs TextEdit's toolbar and text behind it.
   An `NSVisualEffectView` with the popover material reads as flat grey over a white page on both.
2. **The agent's light.** A layer for the agent's shapes in live ink only, in place of
   `ShapeMarkLayer` there. It has a bloom (a wide indigo stroke with a blurred shadow), a core,
   and a glint that rides the drawing head on today's `drawOn` curve. The bloom settles over 0.9 s.
   The core is white over a dark background and indigo over a light one, judged from the window
   capture the ask already holds.

   **Built.** `LightMarkLayer` (`Sources/LiveInkLight.swift`) draws every agent shape in live ink.
   The core is three strokes, each narrower and lighter. The bloom is two shadows of the shape,
   3 and 9 pt on a dark window, so it reads as a glow rather than a blur. The glint is a 26 pt piece
   of the path whose `strokeStart` and `strokeEnd` run with the head. `LivePacket.Luminance` keeps a
   64-column grid of the capture's luminance, and a shape whose surroundings average 0.45 or less
   is drawn for a dark window. Checked in the macOS 26 VM with a fake Claude Code session answering
   through the reply helper, over TextEdit (light) and a dark Terminal, with the draw-on slowed to
   3 s to catch the glint. With the chord held and the pointer on the agent's rectangle, the light
   gave way to the person's red ink, and came back when the chord was let go.
3. **The thinking light.** It replaces `ShimmerMask`. A short bright stroke runs along each asked
   ink path every 1.15 s, timed from one shared start as today, then a sheen crosses the
   question's note. With Reduce Motion the ink brightens and holds.

   **Built.** `LiveMarksLayer.think` adds a `ThinkingBand` to each waiting stroke: a white stroke
   with a white shadow whose `strokeStart` and `strokeEnd` run a 40 pt piece along the path, with
   40 pt of run-up off each end so each pass ends in a short rest. A waiting note gets a
   `NoteSheen`, a diagonal gradient masked by the note's own picture, a third of a beat behind the
   band. Both fade in and out over 0.2 s. Checked in the macOS 26 VM over the dark Terminal and
   light TextEdit: on the dark window the band reads as light running round the loop; on the light
   one it reads as a pale highlight on the red, since its white glow has nothing to show against.
4. **The edge glow.** The band moves fully onto the screen as a thin bright line with a soft
   falloff, brightest near the pen through a mask that follows it.

   **Built.** `EdgeGlow` draws the lab's profile into a bitmap for each edge's strip: a line that
   falls to a third over 1.6 pt, and a glow that falls to a third over `ui.liveInkGlowWidth`, now
   22 pt. Each strip has a radial mask centred on the pointer, full strength near it and a third
   far from it, so a move composites four thin strips rather than the whole screen. Checked in the
   macOS 26 VM with the pointer in each corner: by the pointer the edge reads as a lit coral rim
   round the corner, and the far corner is faint, as in the lab render.
5. **The person's ink.** Width comes from the hand's speed, read from the spacing of the raw points
   before smoothing. The ends taper, and a lighter stroke trails the pen as the sheen. It is drawn
   as a filled outline. On release each point eases onto the recognised shape over about 0.3 s,
   keeping its width, so the ellipse or arrow still looks drawn by hand.

   **Built.** `InkMarkLayer` (`Sources/LiveInkHand.swift`) draws the person's marks and the stroke
   being drawn. Its body is three fills of the outline, each narrower and nearer the ink's colour,
   so the edge is darker than the middle, with a soft shadow under the widest. `InkHand` keeps the
   hand with the mark: each point's width and its place on the shape, as an angle round an
   ellipse or a fraction along an arrow or round a rectangle. So a mark on a window that has moved
   eases from where the window is now. An answer's mark the person picks gets an even hand that
   starts at its upper left and draws itself on. Checked in the macOS 26 VM through Tart's VNC,
   with pointer events about 8 ms apart and spaced as a hand's are, and the ease slowed to 2.5 s:
   loops over TextEdit, the dark Terminal and the wallpaper, an arrow, and a pick of an answer's
   ellipse and of its rectangle. With the chord held through the test hook, resting the pointer on
   Claude's loop crossfades its light into the person's ink over 0.12 s, and back when the pointer
   leaves. On the dark Terminal the ink reads clearly without the glow the
   lab gave it there, so that glow is not built. Only the capture taken after the stroke says
   whether the window is dark, so the ink would change its look while it eases.
6. **The answer in a popover.** The reply is an `NSPopover` attached to the answer's first pointing
   mark, or to the person's ink when the answer points at nothing. That gives Liquid Glass on macOS
   26 and the system popover on 14 and 15 with no drawing of our own. If step 1 fails, it is a
   glass view with an arrow in the overlay instead. Its first line holds the agent's logo and name
   and the question in quotes, and the question's pill fades as it arrives. Each update crossfades
   the words over 0.2 s while the popover springs to its new size.

   **Spiked before building**, with `OverlayProbe`'s `step6` modes in the macOS 26 and 15 VMs:

   - A popover follows its anchor when the anchor rect moves. Its window's alpha fades it, and it
     leaves and comes back with the overlay when the overlay is ordered out and in.
   - A button inside the popover takes the keys. On macOS 26, buttons that refuse first responder
     fixed it: the click ran their action and TextEdit kept its active window. On macOS 15 the
     same click still took TextEdit's key window, though the menu bar kept its name.
   - On macOS 15, with the popover's window set to ignore the mouse and the buttons in a
     non-activating panel of their own, both clicks kept TextEdit active. The click on the
     popover's words reached TextEdit, and the click on the button ran its action.
   - The window server keeps the popover's window one size while its content grows. Setting the
     content size each frame grows the visible popover.

   **The design.** Each choice and its reason:

   - The popover holds only words: the header and the reply. Its window ignores the mouse, as
     today's note does, so a click on it reaches the app under it. The × and the actions stay
     panels of their own, laid over the popover's top-left corner and its bottom edge, which keeps
     room for them. Buttons inside the popover take the person's keys on macOS 15. The panels are
     child windows of the popover's window, so they share its layer: a window raised over the
     answer covers them with it.
   - The reply is still a text `Mark`, so every rule that pins, follows, hides and clears an
     answer's marks still holds. A reply that is a popover carries where it hangs: the rect it
     points at, the edge it hangs from, and its body's expected rect. A text mark without that is a
     note as before: a label, or Vignette's own note.
   - A whole answer hangs its reply from its first pointing mark: a circle's or box's edge, or an
     arrow's tail, so the eye goes from the words along the arrow to its target. With no pointing
     mark it hangs from the person's ink. That mark's label is placed with the reply: for each spot
     the reply could take, the label goes in the room left, and the pair that covers least wins.
     Placed one after the other, either took the spot the other needed.
   - A reply that streams in hangs from the person's ink and stays there when its marks arrive.
     The person is reading it by then, and a reply that moved while read would lose their place.
     Today's note stays put while it grows for the same reason.
   - `LiveAnswerLayout` picks the edge. It tries the middle of each side of the anchor, or an
     arrow's tail, below, above, right and left, with the body centred on that point, as AppKit
     centres a popover on its arrow. The body may hang past the window onto the visible screen,
     since the popover is a window of its own. It keeps off every mark before it keeps off the
     window's text: a mark under the reply is part of the conversation hidden, and on a page of
     text some text is always covered. The body is measured as the popover lays it out.
   - The person's question note is left out of the scene the answer is placed in, since the reply
     replaces it.
   - The words are the system font at 13 pt and the header 11 pt, as the native lab drew them and
     as macOS's own popovers set text.
   - The actions are AppKit's own push buttons at the large size, 28 pt tall on macOS 15 and 26,
     so they look like a popover's buttons on each version. macOS draws every control in an app
     that is not frontmost in its inactive look, and Vignette never is while an answer shows. So
     the recommended first action is not filled with the accent colour. `ButtonLab`
     (`.scratch/look-lab/native`) tried a default button, a tinted bezel, a panel that reports
     itself key, and SwiftUI's bordered and glass styles. Only SwiftUI on macOS 26 could be drawn
     active, and its glass styles looked disabled before any click.
   - A click keeps the buttons. All of them are disabled and the picked one gains a checkmark,
     which is how macOS marks a choice, so the person sees what they asked for while the session
     works on it.
   **Built.** `ReplyPopover` (`Sources/LiveReplyPopover.swift`) shows the reply.
   `LiveMarksLayer.showPopover` keeps it on its mark as the overlay moves, and fades and closes it
   with its mark. Checked in the macOS 26 VM: the popover hangs beside the circled word with its
   header and its actions. It, the × and the actions follow a window move. The × dismisses the
   answer while TextEdit stays active, and Terminal raised over the answer covers all three. On
   macOS 15, `OverlayProbe`'s `step6e` mode showed that a button in a child panel of the popover's
   window runs its action and leaves TextEdit active. The words cross-fade when they change. That
   and a streamed reply are not checked on screen: the VM has no `claude` to stream one.
7. **The docs.** `docs/live-ink.md` gets the rules for each change.

   **Built.** Each step's rules are in `docs/live-ink.md`.
8. **Pulling focus.** Pete chose rack focus, the tour and the loupe (decision 5). The build:

   - **The answer asks for it.** A `focus` mark names its target as a circle does, and `zoom` on it
     asks for the loupe. The responder's prompt and the skill say when: the one thing the reply is
     about, several in reading order for a tour, and `zoom` for something too small to see. A build
     without it drops a kind it does not know, so the reply still shows.
   - **A focus is an answer mark that draws no stroke.** The layout gives it the target's rect, or
     the lens's, so labels, the reply and the other marks keep clear of it, the reply can hang from
     it, and it follows, hides and clears as every answer mark does. A tap on it lets it go rather
     than picking it. In an answer in steps it is a circle, since a step is something to click.
   - **The picture.** When the answer is shown, Vignette captures the window once, without its own
     overlay, and softens it off the main thread as the lab did: rack focus blurs it 5 pt, takes 80%
     of its colour and dims it 10%, or 35% on a dark window. The overlay shows that picture under
     the marks, with the target cut out by a mask whose edge softens over 16 pt, so the person's
     ink, the answer's marks and the reply stay sharp. The loupe shows the window lightly blurred
     and dimmed 22%, and a lens over the target: the capture there at 1.7×, kept inside the window,
     with a lit rim and a shadow, grown from 1× as it comes in.
   - **A tour racks from one target to the next.** One focus shows at a time. The next comes in
     before the last lets go, so the old target blurs and then the new one sharpens, as a camera
     racks focus. Stops pair with the reply's sentences in order, and each holds for its sentence
     read at 0.3 s a word, at least 2 s; the last holds at least 2.5 s and then lets go.
   - **The person stays in charge.** The focus lets go at once on a key, a click, a scroll, the ink
     chord, or the pointer moving 120 pt from where it was when the focus came in. Its fades follow
     the motion setting, as every animation in Vignette does.

   **Built.** `Sources/LiveFocus.swift` draws it, and `LiveInk` captures the window and runs the
   stops. Checked in the macOS 26 VM on TextEdit:
   - Rack focus: the first GREEN stays sharp and the rest of the window goes soft and grey. The
     person's loop, the label and the reply stay sharp over it. The picture was ready 40 to 220 ms
     after the answer was drawn.
   - Tour: the first GREEN, then the last line, held 2.1 s and 2.7 s, then let go.
   - Loupe: "Helvetica" in the toolbar at 1.7× under a lens with a rim and a shadow, and the reply
     beside the lens.
   - A pointer move, a scroll, a click and a key each let it go mid-hold. The key, a right arrow
     sent to TextEdit, let go of the first stop 1.55 s into its 2.1 s hold. A key needs the copy
     trusted for Accessibility, since only then does its global monitor hear keys. The ink chord
     needs that same trust, so a copy that can ink can hear the key.
   - The first run put the picture off by the window's origin. A mark pinned to a window moves into
     the window's coordinates, and its focus now moves with it (`FocusPlace.moved`).

   **The tour, revised.** At the second stop of the first build, the person's bold loop round
   another word drew the eye away from the target, and the reply still hung from the first stop.
   Pete chose these changes:
   - The reply moves to hang from each stop, with that stop's label beside it. It keeps its side
     when it can and slides there on a spring over 0.45 s, as long as the next target takes to
     sharpen. Checked in the macOS 26 VM: it moved 133 pt in about 0.5 s.
   - While a stop shows, the window's other marks fade to 20%: all but the stop, the reply, and the
     person's ink round the stop's target. Checked: the loop round RED faded at the first stop and
     stood at full strength at the second, whose line it is on.
   - The focus still leaves over 0.18 s, as every answer mark leaves, so the page shows as soon as
     the person acts.

## Decisions for Pete

1. **Ink and light as the direction.** Pete chose it on 2026-10-07.
2. **The person's stroke after release.** Pete chose to ease it into the recognised shape.
3. **Where the answer sits.** Pete chose a popover attached to the agent's target.
4. **The agent's highlight.** Pete chose a stroke of light.
5. **How the agent pulls focus.** Pete chose rack focus, the tour and the loupe on 2026-10-07.

## The lab

What it simplifies:

- The scenes are drawn, not real windows.
- An arrowhead is a tapered stroke with a flat back, not today's filled triangle.
- It has no note panel, typing, listening state, target chip, actions or done animation.
- The agent's marks draw on while its words arrive. Today they draw on once the answer is whole.
- Its glass is the scene blurred and tinted. The native section has the real thing.
- It blends colours in sRGB without linearising, and wraps lines greedily rather than balancing them.

To rebuild it, from `.scratch/look-lab/`:

```
swiftc -O lab.swift -o lab
./lab Shaders.metal.txt out ../../Resources/agents/claude.svg
python3 assets.py
```

`./lab … --stills` skips the videos, and a scene or look name renders only that one
(`./lab … web ink-and-light`). The native app builds with
`xcrun swiftc -O -target arm64-apple-macos14.0 native/NativeLab.swift -o
native/NativeLab.app/Contents/MacOS/NativeLab`. `native/capture.sh` opens it in a VM through the main
checkout's `.scratch/vm.py` and captures the screen, once the app and `native/nl` are in the VM's
`/tmp`.
