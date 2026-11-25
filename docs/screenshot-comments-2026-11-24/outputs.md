# Screenshot comments: Copy, Send, Stitch and Reply

Part of [the screenshot comments plan](../screenshot-comments-2026-11-24.md).

## What each output carries

Today every rendering is the screenshot with its marks, at the screenshot's pixel size. Pins change
that only where their words have to travel.

| Output | With pins |
|---|---|
| Copy, Return, Cmd+C with nothing selected | The chosen copy format (Question 4) |
| Copy Drawing in the stack, and a card dragged out | The same as Copy |
| Send to an agent session | The picture with its marks and each pin's number and outline, at the screenshot's size, with no words in it. The words travel in the line. |
| Reply on a card that names its session | The same as Send |
| Stitch | Question 6 |
| The stack's Copy, of the original file | Unchanged: the original file |

### Copy

**Question 4 (mock 3).** Pete suggested pins could become today's notes when copied.

- (a) One PNG holding the picture with its numbered pins, and the comments in a list. The list goes
  below a wide screenshot and to the right of a tall one. **Recommended.** It works when the reader
  sees only the image, and it holds any number of pins at any density. The image is larger than the
  screenshot.
- (b) Pins become notes. Each pin's comments become a note tag beside its area, placed by the rules
  a box's note follows today, with the area drawn as a rectangle. The image keeps the screenshot's
  size and reads like today's drawings. Where pins are dense the tags collide, which is the problem
  pins exist to solve.
- (c) One PNG with a list, where each row also shows a small crop of its pin's area. A reader
  matches a comment to its place without hunting for the number. The list is taller, and the PNG
  shrinks further in a chat's preview.

With (a) or (c):

- The list is set in SF Pro Rounded at the note's text size for the drawing's mark scale, in the
  screenshot's colour profile. The picture's pixels are unchanged.
- Where two pins' numbers would overlap in the PNG, the later one moves clear with a short leader
  line back to its place.
- A drawing with no pins copies exactly as it does today, at the screenshot's size.
- The clipboard keeps the PNG, the TIFF and the file URL. Its text, which a terminal pastes, is the
  path followed by the pins' words in the form Send's line uses. An agent given a pasted path then
  reads the words as text instead of from pixels.

### Send to an agent session

- The image the agent reads is the picture with marks, pin numbers and area outlines, at the
  screenshot's size. A list inside the image would make the agent read words from pixels that
  Vignette already has as text.
- The pins' words go in the line, after the person's message and before Vignette's bracket. The line
  is one line, since the plugin's monitor makes each line one message (`String.asOneLine`). Each pin
  is written as its number and its comments: `Tighten the session menu. Pin 1: remove extra margin.
  Pin 2: why such a big gap between these? Pin 3: the shimmer effect is too narrow; needs more width
  and spread. / can we have the dot indicator pulse gently with a subtle glow? [From Vignette:
  "…/image.png". …]`
- The request stores the pins as `pins.json` beside `image.png`, with each pin's `id`, number, area
  in px and comments.
- The skill's section "When the user sends you a drawing" says what "Pin 3:" means: the numbered
  circle on the image, with its area outlined. A newer skill reaches agents through the plugin
  install, as every skill change does.
- The line's length is unverified. At 99 pins of 2,000 characters a line could pass 200,000
  characters. Step 2 measures whether Claude Code's monitor and `codex queue` take a long line
  whole. If one cuts it, the line carries the words up to that length and then names `pins.json`.
  `ClaudeReadRule` today lets Claude Code read only `requests/*/image.png` without asking, so that
  step would widen it to `pins.json`.
- A reply drawn without `--image` is drawn on `image.png`, pins included, as replies are drawn on
  the person's marks today. The agent's marks then sit beside the numbers they talk about.
- On an agent's card, a pin added by the person changes the drawing, so Reply sends the picture.
  `Agent.fingerprint`, which `Model.drawingAsSent` compares, then hashes the pins too.

### Stitch

**Question 6.** A stitch is a new screenshot made from several, with each piece's number on it.
`docs/rules/stack.md` says it has no drawing of its own: each piece's drawing is drawn into its
pixels, and the stitch is copied at once.

- (a) Each piece's pins become live pins of the stitch, moved and scaled with the piece, numbered
  from 1 in piece order and then number order, with their comments. **Recommended.** The stitch is
  usually sent or copied next, and live pins let its Copy and Send carry their words. The stack's
  rule changes, and the stitch gets a drawing, written before its card appears. Its first copy is
  the rendering in the chosen format, so the card's Copied notice waits for that rendering. Unstitch
  and restitch carry the drawing. Pin circles sit beside the pieces' number badges, so the two must
  look distinct. Mock 2 does not show this.
- (b) The stitch keeps no drawing. Each piece's pins are drawn into its pixels with their numbers,
  and their words are lost. Nothing in the stack changes, and a stitch of pinned screenshots loses
  what the person wrote.

## Agents' marks and answers

- `add?marks=` and the reply helper's `--marks` stay as they are. Agents cannot make pins in steps 1
  to 3.
- **Question 5: should an agent answer on the pins it was sent?** The reply helper would take
  `--comments '{"<pin id>": "Widened the shimmer band to 40% of the row"}'`, naming pins from
  `pins.json`. A reply becomes a new card, as every reply does (`Drawings.installReply` writes one
  complete drawing before the card appears). That card would hold the person's pins as live pins,
  each with the agent's answer added as an indigo comment. **Recommended: yes, as step 4.** It lets
  an agent answer each pin where it was asked. It needs `ReplyProtocol.version` raised, the skill
  changed, and its own ADR for what a reply may carry.

## Message field and Send

- The toolbar's message field stays the request about the whole screenshot. Its words lead the line,
  and the pins follow.
- Its words are kept in the drawing file as now. Pins add nothing to the field.
- A screenshot with pins and an empty message field can be sent. Its line starts with the pins.
- The toolbar's Reply rests when nothing changed (`Model.nothingToReply`). A new pin or comment is a
  change.
