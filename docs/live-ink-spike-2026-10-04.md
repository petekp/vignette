# Live ink: drawing on the live screen with an agent (spike, 2026-10-04)

Status: done. The prototypes were not kept.

Pete wants to go past screenshots: draw straight on the screen, have Vignette work out what the
drawing points at and hand the agent a context packet, and have the agent draw back on the screen
the same way. This note records what each experiment showed.

## Questions

Each one has a result that would change the design.

1. **Ink over everything.** Can a transparent window take a drawing over any app, including the
   menu bar, and pass every click through when nobody is drawing? If it cannot take presses on
   clear pixels, the window needs a fill, and that fill must not show.
2. **The overlay and capture.** When Vignette captures the screen to build the packet, can it
   leave its own ink out, and can it put the ink back in on its own terms? If ScreenCaptureKit
   cannot exclude the overlay, the packet has to hide the ink for a frame.
3. **What the drawing points at.** From the marks alone, what can Vignette learn: the app, the
   window and its title, the element under each mark and its ancestors, a page's URL, a document's
   path, the text in the region? How long does it take? Under about 200 ms, it can be built while
   the ink settles; much longer, and Send needs a waiting state.
4. **The crop.** Can the crop be chosen from the marks, the window and the elements they touch,
   at a size that survives the model's resize (1568 px on the long side)?
5. **Drawing back.** Can an agent's marks land on the live screen in the right place, and stay on
   the element they point at while the window moves or scrolls? If marks can only be placed in
   screen coordinates, they go stale as soon as anything moves.
6. **Feel.** What makes it feel alive: the ink's look, the edge glow while drawing, the agent's
   marks drawing themselves on, ink that fades once it has been sent.

## Constraints

- Prototypes run as command-line tools from the terminal, so they inherit its Accessibility and
  Screen Recording grants and raise no prompts. A shipped feature would ask for Screen Recording,
  which Vignette does not ask for today.
- Pete's running Vignette, his settings and his screenshots folder are left alone.
- Synthetic presses go to the overlay only after its own state says it is up and taking presses.

## The prototype

InkLab was a command-line tool. Holding Control and Option, drawing and letting go opened a note
field beside the ink. Return sent a packet, which held screenshots of the screen, to `claude -p`
(Sonnet), and the answer drew itself on about 10 s later. Esc dropped that ink instead, and
Control, Option and Delete cleared every mark.

## Results

The lab is a Tart VM (`ink-lab`, macOS 15.7.7) with a checkout page in Safari. Pete's Mac was
locked, and a synthetic key must never reach a lock screen. InkLab ran from the VM's Terminal,
which held Accessibility and Screen Recording.
Every stroke below is a real mouse drag through VNC, sent only after InkLab's own state said the
overlay was taking presses.

1. **Ink over everything works.** A non-activating `NSPanel` at `.screenSaver` level, joining all
   Spaces, takes a drawing over any app. Ink mode fills the window with black at alpha 0.004, which
   nobody can see, because the spike found that clear pixels still passed presses. A later
   measurement showed the fill is not needed once `ignoresMouseEvents` has been set
   (`docs/live-ink-integration-2026-10-04.md`, "Step 1 as built"). Out of ink mode, every press reaches the app below. The strokes are
   recognised as a loop, an arrow or a tap.
2. **Capture can leave the ink out.** `SCScreenshotManager.captureImage` with an
   `SCContentFilter` that excludes this app returned the page without the overlay, its glow or its
   ink. The packet then draws the marks into the crop itself, at the exact pixels. The first capture
   raised macOS 15's "bypass the system private window picker" prompt for Terminal. A shipped
   feature would raise it for Vignette, and macOS repeats it about monthly.
3. **The drawing's targets come from Accessibility, fast.** A loop round the total and an arrow at
   the error message came back as "the text “$197.85”" and "the text “Promo code SPRING25 expired”",
   with each element's frame and its path to the window, the page's URL from the `AXWebArea`, and
   the window title. Measured on the second run, in the VM:

   | Step | ms |
   |---|---|
   | Window under the ink | 0.4 |
   | Accessibility for two marks | 9.5 |
   | Capture of the crop | 57 |
   | Capture of the whole window | 37 |
   | Drawing the ink in, writing PNGs | 39 |
   | **Packet ready** | **144** |
   | Vision text, accurate, afterwards | 619 |

   The VM has no Neural Engine, so Vision is slower than on the Mac. Text recognition runs after
   the packet is written, so it never delays Send.
4. **The crop.** The ink and the small elements it touches, padded by a third, kept inside the
   window, at least 560 by 360 points. Marks far apart produced a crop of the whole window; a crop
   per cluster of marks is still to do. Each packet also carries the whole window, scaled to 1568
   px, with the detail outlined.
5. **Drawing back works, and pinned marks stay on what they point at.** The agent's marks arrive
   in fractions of the crop (Vignette's `marks=` format) and draw themselves on: the stroke grows,
   a pen tip rides its end, the head and the note spring in. Every mark, the person's too, is pinned
   to the element under it, by its offset from the element's corner, or to its window. Read 30
   times a second, the pins kept five marks on their text through a window move and a page scroll.
   Each mark is clipped to its window and scroll area, and the windows in front of its window cut
   it out, so the ink looks drawn on the page. That costs 2 to 3 ms of the main thread per tick
   for five marks, up to 12 ms.
6. **Covering windows, at every level.** A system dialog first drew under the ink, because only
   normal-level windows counted as in front. Now every window above the mark's window cuts the mark
   out, except clear ones and those above normal level that span a whole screen: on macOS 15 the
   Dock reports one, and counting it erased every mark.
7. **The agent names targets, and Vignette draws.** A model places a mark by name far better than by
   coordinates, so the packet gives every element and every recognised line of text an id (`e1`,
   `t1`), and the reply names them:

   ```json
   {"packet": 1, "say": "Subtotal $165.00 plus tax $14.85 is $179.85, not $197.85…",
    "marks": [{"type": "loop", "around": "t11", "text": "should be $179.85"},
              {"type": "point", "at": "t9"}, {"type": "point", "at": "t10"}]}
   ```

   `loop`, `arrow` (with `from`: left, right, above, below), `point` (an underline) and `note` each
   take a target, and Vignette builds the path from the target's live frame. Fractions of the crop
   still work for anything with no id. `say` is the answer, drawn first as a bubble beside the
   person's ink, so it reads as a reply to what they drew; the evidence draws on after it. Every
   model tried used the ids correctly.
8. **A real model answers in 11 to 24 seconds.** The packet for the loop round the total, with
   "the total looks wrong, why?", sent through `claude -p`:

   | Model and input | Wall time | Model time | Turns | Cost | Answer |
   |---|---|---|---|---|---|
   | Opus, reading the packet's files | 22 s | | 5 | $0.32 | right: the 7 and 9 swapped |
   | Sonnet, packet inlined | 10.9 s | 5.5 s | 2 | $0.14 | right |
   | Opus, packet inlined | 16.9 s | 11.5 s | 3 | $0.29 | right |
   | Haiku, packet inlined | 24 s | 18.6 s | 1 | $0.05 | right, but its JSON came in a code fence |

   Inlining the context and the crop saves the turns spent reading files. About 5 s of each run is
   the CLI starting; the rest is the model. Even the fastest answer takes long enough that the
   screen needs to show something is coming.
9. **Notes find room.** A note tries eight spots round its mark, then a grid over the window,
   nearest first. A spot costs the area outside the window and the area over other notes, other
   marks and the packet's recognised text. A note that lands away from its mark gets a leader line.
   This stopped the agent's notes running off screen and covering the numbers they were about.
   Two faults remain, both visible in the recording: a leader line ignores content and crossed the
   Place order button, and the loop's note "should be $179.85" settled beside the subtotal row,
   where it reads as being about the subtotal.
10. **Terminal text comes from Accessibility, by line.** In Terminal, `AXRangeForPosition` gives
    the line under the ink, and `AXBoundsForRange` that line's frame. Terminal answers every point
    on a row with the row's first character, so the column comes from the line's width over its
    character count, which holds only for a monospaced font. A loop round part of a build error came
    back with the words inside it, cut mid-word at the edges; snapping to word boundaries is still
    to do. A mark on text is pinned to its character range, not the text view, so it scrolls with
    its line, and when the line scrolls out of the view the mark is clipped away with it.
11. **Guided steps work.** A reply with `"steps": true` shows one mark at a time. A click on the
    current target passes through to the app, fades that mark and draws the next. Tried in Safari
    with three steps.
12. **How it feels.** The recording (16 s, in the VM) runs: ink mode turns on and the edge glow
    circles the screen; a loop is drawn round the total; Send dims the ink; the answer bubble springs
    in and the agent's loop and underlines draw on in 0.55 s, each with a pen tip riding its end;
    then the Safari window moves and every mark goes with it, with no visible lag at that speed.
    The draw-on reads as someone drawing rather than a layer appearing, and it is the part that
    makes this feel alive. The glow says clearly that the screen is taking ink.

## Limits of this spike

- Everything ran in a macOS 15.7 VM with no Neural Engine and no GPU of its own. Timings on a Mac
  will be shorter, Vision's most of all.
- Untested: the hold-to-ink chord (⌃⌥ held), because VNC drops Option; full-screen apps and other
  Spaces; a second display; Chromium and Electron apps, where Accessibility builds its tree late;
  trackpad pressure; a real Retina display.
- The marks the person draws are recognised as loop, arrow or tap only. Rectangles, underlines and
  handwriting are not.
- The reply came from a file the lab was told to read. No agent session received the packet
  through Vignette's Send.

## Bringing it into Vignette

The prototype shares only the colours and the mark vocabulary with Vignette. The rest would be new,
but it can sit on the closed loop that exists.

- **One more kind of request.** A live send is a `ScreenshotRequests` request whose image is the
  crop with the ink drawn in, plus `context.json` beside it: the app, the window, the URL or
  document, the elements and text lines with their ids. The request line and the plugin stay as
  they are. The skill learns the id-based marks.
- **Replies go back to the screen.** The reply helper already carries marks. A reply to a live
  request draws on the live screen when its targets still resolve, and becomes an ordinary card,
  the crop with the agent's marks, when they do not (the window closed, the page changed). So
  nothing is ever lost, and the stack is where old live exchanges end up.
- **One owner for the overlay.** A `LiveInk` controller owning the overlay panel, ink mode, the
  pins and the follow tick, beside `AnnotationController`. Pins and the covering-window clip are
  pure functions of frames, so they can be tested like `AnnotatorZoom`.
- **The mark model.** Live marks need an anchor that the editor's `Mark` does not have. A live mark
  is a `Mark` plus an anchor, drawn by `MarkLayers` so it looks as it does in the editor, with the
  draw-on added there.
- **A way in.** Something other than the stack's shortcut: a held chord for point-and-ask (hold,
  draw, release sends), and a toggle for drawing several marks before sending.
- **Permissions.** Live ink needs Screen Recording, which Vignette does not ask for, and on macOS
  15 a reminder prompt about once a month. Accessibility it already asks for. Without Screen
  Recording, a packet of Accessibility text alone still works for text-heavy apps, but the agent
  sees no pixels.

## Ideas not tried

- **A waiting state with substance.** While the model thinks, show the elements the packet found:
  faint outlines on the targets the agent can name, so the 10 s wait shows what it is looking at.
- **Voice while inking.** Speak while drawing and send both. `SFSpeechRecognizer` runs on device
  on macOS 15, `SpeechAnalyzer` on 26.
- **Pressure.** Force Touch pressure for stroke width, if a non-activating panel receives
  `pressureChange` events.
- **A fast local first answer.** Foundation Models on macOS 26 could name the target and draft the
  question in under a second, before the remote model's full answer.
- **Ink that stays with the page.** Keep marks keyed by URL or document path and redraw them when
  the page comes back.
- **The agent checking its own advice.** After a guided step, capture the target again and turn the
  mark into a check when the change is there.
- **The agent pointing while it works.** A coding agent marks the line it is editing, or the button
  it is about to press, in the person's own apps.
