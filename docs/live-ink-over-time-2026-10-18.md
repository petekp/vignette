# Live ink: asking about what changes over time (2026-10-18)

An area of investigation, not a plan. Nothing here is built or decided.

## The gap

An ask sends one picture: the window under the ink, captured as the last stroke ends
(`LiveInk.prefetch`, `LivePacket.build`). Anything not on the screen at that moment cannot reach
the agent. Three kinds of moment miss it:

1. **What happened before the chord went down.** The person saw it, and it was gone by the time
   they pressed ⌃⌥.
   - A transition that flickers or steps for one frame.
   - A toast, an error banner or a tooltip that left before it could be circled.
   - A layout shift: a button moved as an image loaded.
   - Possibly a hover menu. While the chord is held the overlay takes every press, which may close
     the menu. Not checked yet.
2. **What changed between strokes.** The person draws, lets go, uses the app, and draws again.
   - "I click this [1], and this list [2] doesn't update."
   - A flow across pages: a name typed on one page shows wrong on a later one.
   - Before and after a hot reload: "this was right [1], now it's wrong [2]."

   Today the moment of stroke 1 is lost, because the one capture is taken after stroke 2.
3. **Motion the app makes while the person watches.**
   - A spinner that never resolves, a skeleton that flashes, a progress bar that stalls.
   - Live data: a counter that ticks wrong, a log that streams the wrong lines.
   - Dropped frames. A capture stream reports when each frame arrived, so the agent could get the
     gaps as numbers, not only as pictures.

Ink that follows moving content is out of scope. Pete judged on 2026-10-18 that its behaviour is
too hard to predict to be worth much.

## Capturing the frames

Each kind of moment needs a different capture:

| Capture | Covers | Cost |
|---|---|---|
| **A frame per stroke**: each stroke keeps the window as it was when that stroke ended | 2 | Low. A capture already starts as each stroke ends. |
| **A replay buffer**: the last few seconds of the window, kept before the chord goes down | 1 and 3 | The stream runs all the time, so macOS shows its screen-recording indicator for as long as Vignette runs. It also costs battery and memory. |
| **Frames while the chord is held** | 3 only | While the chord is held, presses go to the ink. So it catches only motion the app makes by itself. |

A frame per stroke is the most predictable: each mark is a picture of the moment it was drawn.

The replay buffer is worth the most for interface work, because what has already gone is the
hardest thing to describe. It needs a spike first, to measure what a buffer of only the front window
costs and to see how the indicator reads with the stream always on.

## Sending them: a stitch, with the words as text

The frames go as one stitched image. Everything that is words goes as text beside it.

- **The stitch.** `Stitch.compose` lays the frames out for the model's resize and numbers each
  one. A request carries one image, so one stitch fits `ScreenshotRequests` as it is.
- **The text, frame by frame.** Each frame gets its number, its time, and the words said or typed
  over it, tagged with the strokes they belong to. `SpokenNote.marked` already tags words with
  `[n]`. Each frame also gets the window's text lines near its ink, in the form asks send them now:

  ```
  #1 0:00  "I click this [1]"   t4 120 88 210 14 Save
  #2 0:03  "and this list doesn't update [2]"   t9 40 300 180 14 Inbox (3)
  Full frames: …/frame-1.png, …/frame-2.png
  ```

- **The full frames, as paths.** A composite reads worse than separate images
  (`docs/stitch-layout-2026-09-27.md`). Three full-screen captures stitched together reach Claude
  Code with their text at 7.3 px, under the 10 px a model needs to read it. So the stitch shows the
  sequence at a glance, and the agent opens a full frame when it has to read one.

## Cropping each frame

Each frame is cropped before it is stitched, so its text stays readable. Live ink knows more about
a frame than its pixels, and each of these rules uses that:

1. **Crop to the element, not to white space.** Live ink reads the window's Accessibility tree to
   anchor marks, so it knows the frames of the elements under the ink: a card, a list, a form
   section. The crop is the smallest of those that holds the ink with room around it. A window with
   no tree, such as a Chromium browser's, falls back to pixels. Its edges move into white space and
   past the ends of the text lines Vision read, so no word is cut.
2. **Let the ink's shape set the scope.** `InkStroke` already tells a loop from an arrow. A loop
   round a word asks for a small crop, and a loop round a panel asks for the panel. An arrow asks
   for both what its tail starts on and what its head points at, however far apart they are.
3. **Size the crop for the reader.** Make the crop as large as it can be while the window's
   smallest text still reaches the model at 10 px or more. Two frames then get more context than
   six. The crops and the layout are chosen together, since `Stitch.compose` already tries every
   column count. This rule is the one most worth testing. Its claim is that a crop sized for
   legibility beats a fixed padding.
4. **Keep frames of one window aligned.** Frames of the same window share one crop, so #1 and #2
   line up and only what changed differs. A small or medium window stays whole.
5. **Send the change itself.** `LiveChange` already compares a window in 3 pt cells and leaves out
   a caret or a spinner. Run between frames, the same comparison gives "the region at this box
   changed between #1 and #2" as text. The stitch could also outline that region.

## Where the answer goes

The moment is past, so the answer's marks cannot go on the live window. They go on the stitch, as
a result card, which Reply already handles for any image.

Each crop's place in window coordinates is recorded. So when part of the live window still looks
the same as its frame, a mark on the stitch can also be drawn there. `LiveChange`'s comparison
decides whether it looks the same.

## Open questions

- **How many frames.** The stitch is one image, so its token cost stays the same however many
  frames it holds. Legibility sets the limit instead: how many crops fit before the text falls under
  10 px. The person's strokes are never dropped.
- **Which frames a replay buffer keeps.** Candidates: a frame where the picture settled after a
  change, a frame at each stroke, and none for a stretch where nothing changed.
- **Legibility.** Whether the 10 px threshold holds for stitches pasted into Claude Code. The stitch
  layout entry in `docs/TODOS.md` asks the same.
- **How to judge a crop.** A set of made-up windows, each with a hand-drawn ideal crop, and a score
  for how much of the ink and its context a crop keeps and how readable it is in the stitch. That
  would show whether cropping rules 1 to 4 beat a plain padding.
- **The hover question** from the gap above: whether holding the chord closes what it was meant to
  circle.
