# Screenshot comments: Copy, Send, Stitch and Reply

Part of [the screenshot comments plan](../screenshot-comments-2026-11-24.md).

## What each output carries

Today every rendering is the screenshot with its marks, at the screenshot's pixel size. Pins change
that only where their words have to travel.

| Output | With pins |
|---|---|
| Copy, Return, Cmd+C with nothing selected | The picture with a list of the comments (Choice 4) |
| Copy Drawing in the stack, and a card dragged out | The same as Copy |
| Send to an agent session | The picture with its marks and each pin's number and outline, at the screenshot's size, with no words in it. The words travel in the line. |
| Reply on a card that names its session | The same as Send |
| Stitch | Each piece's pins become live pins of the stitch (Choice 6) |
| The stack's Copy, of the original file | Unchanged: the original file |

### Copy

**Choice 4, decided 2026-11-25: the picture plus a list of the comments.** Pete's words: "Picture
plus comment list". It works when the reader sees only the image, and it holds any number of pins at
any density. Pins as notes would make the tags collide, as they did on his 11-14 screenshot. A crop
of each area would make the PNG taller.

- Copy makes one PNG. It holds the picture with its marks, every area's outline and every pin's
  teardrop, and a list of the comments. The list goes below a wide screenshot and to the right of a
  tall one, so the PNG is larger than the screenshot.
- In the PNG every area's outline is drawn, since a reader cannot hover. Teardrops are drawn at the
  drawing's mark scale, with the editor's orientation rule.
- Each row of the list starts with its pin's teardrop and number, the same shape as on the picture,
  then the pin's comments in order. The list is set in SF Pro Rounded at the note's text size for
  the drawing's mark scale, in the screenshot's colour profile. An agent's comment is set in SF
  Mono, as its notes are. The picture's pixels are unchanged.
- The list's size is capped, so a copy's memory stays bounded. Below a screenshot its area is at most
  the picture's, or 4 million px when that is more. Beside one it is no taller than the picture, or
  than 4 million px allows. The pins past the cap become one line: "12 more pins didn't fit. You can
  read them in Vignette."
- Where two teardrops' bodies would overlap in the PNG, the later one first tries its other three
  orientations. If each of them collides, its body moves clear, and a short line in the pin's colour
  joins its tip to its place. Bodies may touch, since teardrops on one place share their tip. Send's
  image places teardrops the same way.
- A drawing with no pins copies exactly as it does today, at the screenshot's size.
- The clipboard keeps the PNG, the TIFF and the file URL. Its text, which a terminal pastes, is the
  path followed by the pins' words in the form Send's line uses. An agent given a pasted path then
  reads the words as text instead of from pixels.
- A rendering that fails says so on the card, as a failed copy does today (`showNotCopied`). The
  drawing stays as it was.

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
- The skill's section "When the user sends you a drawing" says what "Pin 3:" means: the red teardrop
  with that number on the image, whose tip marks the place, with its area outlined. A newer skill
  reaches agents through the plugin install, as every skill change does.
- The line's length is unverified. At 99 pins of 2,000 characters a line could pass 200,000
  characters. Step 2 did not measure whether Claude Code's monitor and `codex queue` take a
  long line whole, since the measurement needs the VM. Step 3's checks measure it. If one cuts it, the line carries the words up to that length and then names `pins.json`.
  `ClaudeReadRule` today lets Claude Code read only `requests/*/image.png` without asking, so that
  step would widen it to `pins.json`.
- A reply drawn without `--image` is drawn on `image.png`, pins included, as replies are drawn on
  the person's marks today. The agent's marks then sit beside the numbers they talk about.
- On an agent's card, a pin added by the person changes the drawing, so Reply sends the picture.
  `Agent.fingerprint`, which `Model.drawingAsSent` compares, then hashes the pins too.

### Stitch

**Choice 6, decided 2026-11-25: a stitch keeps its pieces' pins as live pins.** Pete's words: "Keep
as live pins". The stitch is usually sent or copied next, and live pins let its Copy and Send carry
their words.

- Each piece's pins become pins of the stitch, moved and scaled with the piece, with their comments.
  They are numbered from 1 in piece order, then in each piece's number order.
- The rule in `docs/rules/stack.md` that a stitch has no drawing of its own changes. The stitch's
  drawing is written before its card appears. Its first copy is the rendering with the list, so the
  card's Copied notice waits for that rendering. Unstitch and restitch carry the drawing.
- A stitch whose pieces hold pins is not made when a piece could not be read, and the card says why.
  A stitch made without that piece would drop its comments. For the same reason a stitch is not made
  when its pieces hold more than 99 pins between them, the most a drawing holds.
- A stitch draws each piece's number in a red circle with a white number, inset a quarter of its
  size from the piece's top-left corner (`Stitch.drawBadge`). Pins are the same red. The teardrop's
  shape and its tip tell a pin from a piece's number, and the line calls each one "Pin".
- A teardrop whose body would overlap a piece's number flips away from it, as it flips away from the
  picture's edge. An area pin whose tip sits on a piece's corner is the common case. The stitch's
  drawing keeps where each number is (`pieceNumbers`). When no orientation clears both, the edges
  win on a card. A rendering moves the body clear, and its line stops at the number's edge.

## Agents' marks and answers

- `add?marks=` and the reply helper's `--marks` stay as they are. Agents cannot make pins in steps 1
  to 3.
- **Choice 5, decided 2026-11-25: an agent answers on the pins it was sent, as step 4.** Pete's
  words: "Yes, as step 4".
- The reply helper takes `--comments '{"<pin id>": "Widened the shimmer band to 40% of the row"}'`,
  naming pins from `pins.json`.
- A reply becomes a new card, as every reply does (`Drawings.installReply` writes one complete
  drawing before the card appears). That card holds the person's pins as live pins, each with the
  agent's answer added as an indigo comment.
- A request with pins also stores `base.png`, the picture with the person's marks and no pins. A
  reply without `--image` is drawn on `base.png` from step 4 on, so the reply card's live pins do
  not sit on top of pin numbers drawn into its pixels. Until step 4 a reply is drawn on `image.png`,
  and its numbers stay beside the agent's marks.
- It needs `ReplyProtocol.version` raised, the skill changed, and its own ADR for what a reply may
  carry.

## Message field and Send

- The toolbar's message field stays the request about the whole screenshot. Its words lead the line,
  and the pins follow.
- Its words are kept in the drawing file as now. Pins add nothing to the field.
- A screenshot with pins and an empty message field can be sent. Its line starts with the pins.
- The toolbar's Reply rests when nothing changed (`Model.nothingToReply`). A new pin or comment is a
  change.
