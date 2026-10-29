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
- Its left edge is `ui.annotationCornerRadius` in from the frame's left edge, where the frame's top
  edge comes out of its rounded corner. It is as wide as its longest line.
- It wraps at the frame's right edge, or `ui.agentTitleMinWidth` wide when that is wider, so a
  narrow image's title hangs past the frame's right edge instead of wrapping every few words. It
  never wraps past the room's right edge, where the stack's strip begins (`StackLayout.titleWrapWidth`).
- The minimum is 300 pt. 45 characters of the description at 13 pt measured 257 to 276 pt, and
  wrapping at a word needs some slack, so 300 pt gives a line of about 45 characters.
- Its text keeps its size at any zoom, and it follows the frame's top-left corner. A wider frame
  wraps it onto fewer lines.
- The room an image opens in keeps the block's height above the frame (`StackLayout.annotationFrame`),
  and the zoom's room ends twice `ui.agentTitleGap` above it (`AgentTitleView.marginAbove`,
  `AnnotationController.prepare`), so the frame never grows into it and a zoom never presses it
  against the menu bar. At the fitted frame the margin above it is at least `ui.annotationScreenInset`.

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
  zoom step lands. In the VM, five of eight answers came 0.46 to 0.54 s after the editor opened.
  Three, the first opening among them, took 1.8 to 2 s, up to 0.7 s after the flight landed. That
  is why the title waits for its ink.
- **When it shows.** The title fades in once the flight has landed and its ink is known, whichever
  comes second (`TitleReveal`). When the ink is still unknown 0.5 s after the landing
  (`TitleReveal.inkWait`), the title shows in the appearance's ink, and the measured ink replaces
  it when it answers. The wait is for data, so the motion scale does not shorten it, and motion 0
  still waits. `[annotate] title shown ink=… source=… waited=<ms>ms` logs how long each title
  waited.
- **Without it.** Vignette cannot see other apps' windows, so the ink follows the system
  appearance: black in light mode, white in dark mode. A window nearly always covers the top of the
  screen behind the editor, and a light appearance mostly means light windows. Over a dark page in
  light mode, or a light page in dark mode, this picks the wrong ink. The wallpaper was not used:
  it is seldom what is behind the editor.
- `[annotate] title ink=<white or black> source=<backdrop or appearance> …` logs each pick, with the
  luminances measured.

## Checked in the VM

On a 1024 by 768 screen in `vignette-e2e`, in dark mode, driven through the end-to-end suite's
runner. Each backdrop was set as the wallpaper.

- With Screen Recording, a light page measured 0.43 after the dim and took black. A dark page
  measured 0.006 and took white. A busy page, light on the left and dark on the right, measured
  0.009 to 0.45 and took white.
- A copy without Screen Recording took white over all three, from the dark appearance, and logged
  `source=appearance no screen recording`.
- A wide image with a title opened at `[138, 133, 748, 467]`, with the block at
  `[138, 85, 594, 38]`, 10 pt above it.
- A tall image's block was 289 pt wide with the 300 pt minimum, and 186 pt without it, inside a
  frame 189 pt wide. With the minimum the frame was 206 pt wide, because the shorter block leaves
  more height.
- A small image opened scaled up to 719 pt, wider than the minimum, so the minimum did not change it.
- After three zoom steps the frame filled the room and the block sat just under the menu bar. Each
  step measured the ink again. Cmd+0 put both back.
- Over the recent stack, Esc closed the titled image and the stack took the keys back. A second Esc
  closed the stack.
- With the wait, over two runs, 15 of 16 openings with Screen Recording had their ink before the
  flight landed and showed at once. One waited 335 ms. No wait ran out. Without Screen Recording
  the ink is known at opening, so the title never waits. A build that held each measurement back
  1 s ran the wait out on six of eight openings, at 501 to 515 ms. Each showed white from the
  appearance, then took the measured ink when it came: black on the light page.

A run before the ink change also checked the rest of the loop:

- Text past both limits logged two `[add] warning` lines, and `add` answered `ok`.
- A Send carried no title, and a reply with `--title` opened with its block.
