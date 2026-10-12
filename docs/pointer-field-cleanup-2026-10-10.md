# Pointer field cleanup, 2026-10-10

The pointer field works. Its code still has the spike's shape. Four reviews of `e0a8b7b..3b17a33` covered
reuse, simplification, efficiency and module boundaries. They found one defect: the screen capture
can keep running after the chord is let go. The rest is ownership spread over three files, and a
look that redraws the whole screen to show a small ring.

Status: both steps landed on glow-lab. The smoothness of step 2 at 120 Hz is unchecked on Pete's Mac.

In this note, the pointer field is the whole look. It has two parts: the ring round the pointer, and
the wake, the rings that spread behind the pen.

## Step 1: one owner for the field (structure)

1. **The field owns its own lifetime.** Today `LiveInk`, `LiveInkOverlay` and `PointerFieldLayer` each
   time part of it. `LiveInk` runs the delay. The layer stops the capture with its own timer, and
   `LiveInk` guesses the fade to close the window. After the change, the field is hidden until shown.
   Every path ends hidden: no Metal, nothing to draw, the chord let go before the delay, and a show
   during the fade-out. The field stops its capture once it is hidden, and the overlay closes when
   the field says it is hidden.
2. **Fix the capture that keeps running.** A chord let go inside the 0.25 s delay never hides the
   field. So on a screen with marks, the capture stream keeps running, and macOS keeps showing that
   the screen is recorded. Step 1's single hide path fixes this.
3. **One place decides who holds the field.** Two holders exist: the chord, and the Pointer Lab.
   `LiveInk` tracks them with `fieldShown` and `previewing`, special-cased in five places. After the
   change, `LiveInk` keeps the two holders and one `syncField()` applies them to every surface. The
   overlay's level follows "inking, or holding the field", which replaces `raise`.
4. **The field reads the button itself.** It already reads the pointer every frame. It will read
   whether the button is down on the same frame. That drives the ring tightening and the wake.
   The following go away:
   - `press`, the two `wake` entry points and the canvas calls to them;
   - the Pointer Lab's event monitors.

   The lab then shows the pressed ring too, which it cannot show today. The wake starts only on
   the screen the pointer is on.
5. **The field decides what it needs from the settings.** Today, "draws anything" and "needs the
   screen's picture" are written out in four places. They become private to the field. The ring's
   colour comes from the settings' ink colour inside the field, so no caller passes a colour.
   Changing a setting while inking now starts or stops the capture as needed. Today only the lab
   path does that.
6. **The ring's motion becomes a pure value with tests.** This covers the follow spring, the radius
   spring and the trail of wake points. Tests through its interface catch a 0 s duration producing
   NaN, the trail's cap and spacing breaking, and the ring not settling on the pointer.
7. **A Tween helper for "settle in this time, snap at 0".** The field writes `6.6 / duration` and
   the zero guard twice. `Tween.animate` already has the 6.6.
8. **Smaller tidy-ups:**
   - the shader's uniforms become vectors, and the wake count an integer;
   - the wake's box is found in one pass;
   - an unused parameter is dropped;
   - a shadowed name is renamed;
   - `ScreenFeed` moves to its own file;
   - the shader's dead clamps are removed;
   - the wake rejects distant rings before its square root.

## Step 2: draw only round the ring (rendering)

9. **A ring-sized layer that moves with the ring.** Today every drawn frame clears and draws the whole
   screen, about 24 MB, for a ring about 156 pt across. The window server then composites the whole
   screen. After the change, the ring has its own small layer, positioned each frame in the same
   transaction that presents it. The wake keeps a screen-sized layer, drawn only while rings are
   spreading and hidden otherwise.

This step risks visible lag. The ring's picture could trail its layer by a frame at 120 Hz, and the
VM's VNC view cannot show that. It is verified in the VM by recording frames and tracking the ring
against the pointer, and by the `gpu-ms` log before and after. Pete then checks it on his Mac.

## Not changed

- **Capture at 1x, or around the pointer only.** It trades away the bent picture's sharpness and needs a
  visual judgement.
- **One capture per display.** Starting a display's capture only when the pointer reaches it would show
  that screen without bending for about 0.1 s after crossing.
- **Pausing the display link while idle.** The link is what reads the pointer, so pausing it needs
  another way to hear the pointer move. The saving is under 1% of a core.
- **Skipping frames whose changes miss the ring.** After step 2, a redraw costs a ring-sized draw.
- **The GPU timing and first-frame logs.** They measure whether the look keeps up, which is
  unmeasured on Pete's Mac.
- **The stored keys.** `liveInkFieldSize`, `Bend`, `Split`, `Glow`, `Follow` and `Stretch` set the ring,
  and `liveInkFieldDelay`, `Fade` and `Opacity` set the whole field. Renaming the ring's six to
  `liveInkRing*` is Pete's call.
