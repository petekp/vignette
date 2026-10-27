# Marks sized to the screenshot (2026-10-27)

Status: built on branch `mark-scale` (commit 570360e), not merged. Pete asked for it on 2026-10-27:
on a small screenshot a note covered so much of the picture that it hid the interface it pointed
at.

## The rule

Every drawing has a mark scale, from 0.05 to 1. Every size a mark has in pt is drawn at that share
of its size: the stroke, the edge, the shadows, a note's text, and everything that is a multiple of
the text. A capture of the whole screen has mark scale 1, the sizes marks had before.

```
mark scale = min(1, max(curve, floor))
curve      = (image area / screen area) ^ (power / 2)        power = 0.5
floor      = 16 px / (new text size × screen scale × readerScale(image px))
```

A last bound keeps the drawing's px per pt at 0.5 or more, the limit drawing files already had. With
the defaults it never applies.

### What sets it: the image's area against the screen's

- The screen is the one the annotator opens on, which already set the point scale. So a capture of
  the whole screen gets exactly 1 on any display. The editor sizes its frame against the same
  screen, so a note on a medium crop looks about as big in the editor as a full capture's.
- Area is the measure, and the long edge is not, because a note's tag has a height as well as a
  width. A strip 1500 by 100 pt is as cramped for a note as a small square. Measured by its long
  edge it would keep full-size notes, and one line would cover a third of its height.
- Both are in screen pt: the image's px over the screen's backing scale.
- An image larger than the screen keeps 1. TODOS.md has what that leaves open.

### The curve

`power` is `ui.markScalePower`, 0.5 by default. At 0.5 the mark scale is the square root of the
image's linear size against the screen's. Two ends bracket it:

- At 0, every image gets the same note, so on a 300 by 200 pt crop one line covers 19% of its
  height.
- At 1, a note covers the same share of every image, down to the floor. On a 640 by 400 pt crop
  the curve gives 0.42, so the floor's 0.47 decides. The editor shows that crop at about its own
  size, so the note would read at 9.6 pt on screen, against 12.3 pt on a full capture. That is too
  small to type in comfortably.

At 0.5 the same crop gets 0.64, and its note reads at 13.2 pt in the editor (measured below).

### The floor

A person reads the PNG in Slack, GitHub, Linear or Claude, which show it at one CSS pixel per image
pixel. A model resizes it first, by `Stitch.readerScale`: Anthropic's standard tier, a long edge of
1568 px and 1568 patches of 28 px. So the floor is measured after that resize: a new note's text
reaches the model at no less than `ui.smallestNoteText`, 16 px by default. That is about what a
model sees of a note on a full capture of a 14-inch MacBook Pro's screen: 34 px, resized by 0.453
to 15.4 px.

Because the floor counts the resize, a wide strip that the model shrinks by its long side keeps
notes big enough: 1500 by 100 pt gets 0.90, where the curve alone gives 0.56. Because it is in px,
it holds on any display. A 1x display's crop has half the px, so its notes hardly shrink: at least
0.94.

### Where it lives

The drawing records `markScale` when it is made, as it records its point scale. A mark keeps its
size when the image reopens, on any display, and after a tweak changes the rule.

`pointScale` is px per drawing pt: the screen's scale times the mark scale. Every place that draws
or measures a mark already converted pt to px through `pointScale` alone, so all of them agree: the
editor, the text being typed, cards, flights, the renderer behind Copy, Send, Copy Drawing and a
drag, and a stitch. The file writes `markScale` only when it is under 1, and the format's version
stays 1. An older build sharing the drawings folder draws a new file's marks at the new size,
because it also draws through `pointScale` and ignores a field it does not know.
`docs/adr/0020-marks-are-sized-to-the-screenshot.md` records the choice.

- The editor's own steps in pt are drawing pt too: a nudge, a copy's offset, the 8 pt gap between a
  box and its note, and a new note's 17 pt. On a small crop they shrink with the marks, so on
  screen they keep about the size they have on a full capture.
- The screen's own scale is `pointScale / markScale`. Pasting marks into another screenshot moves
  boxes, arrows and a note's place by the ratio of the two screens' scales, so a box keeps its size
  around the same interface. A pasted mark's stroke and text take the size of the marks already on
  that screenshot, and a note keeps its lines.
- A change to either tweak rescales the drawing open in the editor (`EditorCore.Input.rescaled`).
  The editor hands it over, so its file follows, and the change is not an undo step. Every other
  stored drawing keeps its scale.

### Agents' marks

- An agent's boxes, ellipses and arrows follow the drawing's scale, as a person's do.
- An agent's note keeps `ui.agentTextSize`, 1.33% of the image's width, which already follows the
  image. On a 600 px crop that is 8 px, too small to read, so the same floor applies: at least 16 px
  as a model sees it.
- A drawing that an agent's marks create takes the main screen's scale and size, as its point scale
  did before.

### Settings

Two `UITweaks`, each with a `Bound` and a slider in the tweak panel's Marks section:

| Key | Default | Slider |
|---|---|---|
| `markScalePower` | 0.5 | Shrink on small screenshots, 0 to 1 |
| `smallestNoteText` | 16 px | Smallest note text, 4 to 40 px |

## Measurements

Measured on 2026-10-27 in the `vignette-e2e` VM with its screen set to 1512 by 982 pt at 2x, the
size of Pete's 14-inch screen. The test copy, built from 570360e, drew one box and one note, "This
name is cut off", on three crops of the same Activity Monitor window, and copied each. "Before" is
the same build with `markScalePower` at 0, which gives every image mark scale 1, the sizes marks had
before this change. Each note's size is from `[state]`, and its share is of the image.

| Image (pt) | Rule | Mark scale | Note (px) | Note's share of the image | Text (px) | Text in the editor (pt) |
|---|---|---|---|---|---|---|
| 300 x 200 | before | 1 | 352 x 75 | 58.7% x 18.8% | 34 | 43.7 |
| 300 x 200 | after | 0.471, the floor | 170 x 35 | 28.3% x 8.8% | 16.0 | 20.6 |
| 640 x 400 | before | 1 | 352 x 75 | 27.5% x 9.4% | 34 | 20.5 |
| 640 x 400 | after | 0.644 | 229 x 48 | 17.9% x 6.0% | 21.9 | 13.2 |
| 640 x 400 | power 0.75 | 0.517 | 186 x 39 | 14.5% x 4.9% | 17.6 | 10.6 |
| 1512 x 982 | before | 1 | 352 x 75 | 11.6% x 3.8% | 34 | 12.3 |
| 1512 x 982 | after | 1 | 352 x 75 | 11.6% x 3.8% | 34 | 12.3 |

- "Text in the editor" is the text's px times the editor frame's width in pt over the image's width
  in px. The editor fitted the 300 by 200 crop into a 771 pt wide frame, the 640 by 400 crop into
  770 pt, and the full capture into 1096 pt.
- On the full capture the PNG written after the change is byte for byte the PNG written before, and
  the editor's pixels differ by at most one grey level, which is the VNC capture's own noise.
- The small crop's note is still bigger in the editor than a full capture's, because the editor
  enlarges the crop 2.6 times to fit its frame. Making it look 12.3 pt there would take the PNG's
  text to 9.6 px, under the floor.

## What was verified

- The unit tests: 539 pass, with tests for the rule's table of images and screens, the file's
  `markScale` written and read back and refused out of range, an agent's note floored on a small
  crop, a paste into a drawing with smaller marks, and a rescale of the open drawing in the core
  and the view.
- The end-to-end suite in the VM, on 570360e at its usual 1024 by 768 pt screen: 24 scenarios, 141
  checks, all pass.
- The measurements above, from the editor over VNC and from the PNG each copy wrote.
