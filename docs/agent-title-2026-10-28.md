# An agent's title above its screenshot (2026-10-28)

An agent that pushes a screenshot can say what it shows: `add?…&title=<text>&description=<text>`.
The editor shows the title above the image's frame, in semibold, with the description under it in
the secondary label colour. Nothing else shows it.

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
- Its left edge is on the frame's left edge, and it wraps at the frame's width less its padding. It
  is as wide as its longest line.
- Its text keeps its size at any zoom, and it follows the frame's top-left corner. A wider frame
  wraps it onto fewer lines.
- The room an image opens in keeps the block's height above the frame (`StackLayout.annotationFrame`),
  and the zoom's room ends below it (`AnnotationController.prepare`), so the frame never grows into it.
- It sits on the toolbar's glass, a behind-window blur under a neutral grey. The dim behind the
  editor is 30% black over a blur of whatever is on screen, so a light page behind it stays light:
  white text there is unreadable, and black text is unreadable over a dark one. The glass makes the
  label colours read over either, in light and dark mode.
