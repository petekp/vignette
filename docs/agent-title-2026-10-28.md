# An agent's title above its screenshot (2026-10-28)

An agent that pushes a screenshot can say what it shows: `add?…&title=<text>&description=<text>`,
or `--title` and `--description` on the reply helper.
The editor shows the title above the image's frame, in semibold, with the description under it in
the same colour, fainter. Nothing else shows it.

## Limits

The title takes 60 characters and the description 140. `AgentTitle.validated` enforces both, for a
push, a reply and a read of the file's attributes. Longer text is cut at the last space that keeps
a word whole, with an ellipsis, and the push still succeeds with a warning.

The numbers come from measuring the block at the default sizes, 17 pt semibold and 13 pt regular,
with 12 pt of padding on each side. The narrowest frame the editor opens is a tall screenshot's: a
phone capture on a laptop's 944 pt high screen opens about 300 to 360 pt wide. A wide image never
opens narrower than `ui.annotationMinWidth`, 770 pt.

| Limits | Frame width | Title lines | Description lines | Block height |
|---|---|---|---|---|
| 80 and 200 | 300 pt | 3 | 5 | 158 pt |
| 80 and 200 | 770 pt | 1 | 2 | 70 pt |
| 60 and 140 | 300 pt | 2 | 4 | 122 pt |
| 60 and 140 | 360 pt | 2 | 3 | 106 pt |
| 60 and 140 | 770 pt | 1 | 2 | 70 pt |

A title of 60 characters is one line from a frame about 520 pt wide. The block's height comes out
of a tall image's height, so 80 and 200 took 158 pt of a 300 pt wide frame's room. 60 and 140 keep
the title to two lines there and the whole block to 122 pt.

## Where it sits

- The block is a sibling of the frame in the annotator's window, and `moveFrame` places it, so it
  moves with the frame in the same commit.
- Its left edge is on the frame's left edge. It is as wide as its longest line.
- It wraps at the frame's width, or at `ui.agentTitleMinWidth` when the frame is narrower, so a
  narrow image's title hangs past the frame's right edge instead of wrapping every few words. It
  never wraps past the room's right edge, where the stack's strip begins (`StackLayout.titleWrapWidth`).
- The minimum is 300 pt. 45 characters of the description at 13 pt measured 257 to 276 pt, and
  wrapping at a word needs some slack, so 300 pt gives a line of about 45 characters.
- Its text keeps its size at any zoom, and it follows the frame's top-left corner. A wider frame
  wraps it onto fewer lines.
- The room an image opens in keeps the block's height above the frame (`StackLayout.annotationFrame`),
  and the zoom's room ends below it (`AnnotationController.prepare`), so the frame never grows into it.

## Its ink

The text sits straight on the editor's backdrop: a 17 pt blur of the screen under 30% black. A light
page behind it stays light grey and a dark one stays dark, so no one colour reads over both.

- **The rule.** `TitleInk.choose` takes the relative luminance of each part of the backdrop behind
  the block and picks white or black by the WCAG 2 contrast ratio. White's worst part is the
  lightest and black's the darkest, so a block over light and dark parts is chosen for the part
  least like it. The two tie at a luminance of about 0.179.
- **With Screen Recording.** ScreenCaptureKit captures the screen under the block, with Vignette's
  own windows left out, at a pixel every two points, in cells as wide as the blur's radius.
  `TitleInk.luminance` lays the dim's black over each cell, then makes it linear. The capture is not
  blurred, so its lightest and darkest cells are a little more extreme than what is shown, which
  errs toward the safer pick. It runs off the main thread when the editor opens, and again when a
  zoom step lands. The answer usually comes before the flight lands. When it comes later, the ink
  changes at once.
- **Without it.** Vignette cannot see other apps' windows, so the ink follows the system
  appearance: black in light mode, white in dark mode. A window nearly always covers the top of the
  screen behind the editor, and a light appearance mostly means light windows. Over a dark page in
  light mode, or a light page in dark mode, this picks the wrong ink. The wallpaper was not used:
  it is seldom what is behind the editor.
- `[annotate] title ink=<white or black> source=<backdrop or appearance> …` logs each pick, with the
  luminances measured.

## Checked in the VM

On a 1024 by 768 screen in `vignette-e2e`, in light and dark mode, driven through the end-to-end
suite's runner:

- A wide image without a title opened at `[100, 85, 824, 515]`, as before. With a title it opened
  at `[151, 149, 722, 451]`, with the block at `[151, 85, 618, 54]`, 10 pt above it.
- A tall image's block wrapped to six lines at 174 pt, 138 pt high.
- After three zoom steps the wide frame filled the room, `[0, 89, 1024, 624]`, and the block sat at
  `[0, 25, 618, 54]`, just under the menu bar. Cmd+0 put both back where they opened.
- Following the frame was kept: the room stops the frame below the block, so following never takes
  the block off screen. Pinning the block to the room's top was not built.
- Text past both limits logged two `[add] warning` lines, and `add` answered `ok`.
- A Send carried no title, and a reply with `--title` opened with its block.
