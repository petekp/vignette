# The annotator's redesign: agent controls and comments (2026-09-24)

Paused on 2026-09-24 so the promo videos can go first. This is the plan to pick up from, and
`docs/TODOS.md` points here. One part came forward and was built the same day: Copy in place of
Done, Send starting on the session in front of you, shown as a target beside Send rather than tabs,
Cmd+Return to send, and Reply alone on an agent's card (`docs/send-and-reply-2026-09-24.md`). The
rest is not built.

Pete's goals:

- **Make Send first-class.** He copies and pastes out of muscle memory, and wants "a more fluid
  exchange" with Claude Code and Codex.
- **Make Done unambiguous.** Done copies, writes `-annotated.png`, marks the card, closes the editor
  and opens the next card in a queue. Esc also closes and keeps the marks, so only the copy sets
  Done apart, and nothing on the bar says so.
- **Replace a single note with comments pinned to the image,** as Figma does. Agents leave comments
  and answer them too.

`docs/annotator-redesign-2026-09-24-mockup.html` shows the design below in three views: Claude's
review with eight comments, your own comments, and what Copy pastes. It is one self-contained page;
open it in a browser.

## The design so far

Decided with Pete on 2026-09-24.

**Layout**

- The tools are a vertical rail left of the image. The comment tool leads it and is selected when
  the editor opens. Select, rectangle, arrow and text stay below it, because visual markup still
  helps when the drawing is for a person.
- The comments are a list to the right of the image.
- The bottom row holds Copy and the agent controls: session tabs over a field for a message about
  the whole screenshot, then Send. When Copy is alone it sits at the right end. When the agent
  controls are there, they take the right and push Copy to their left.
- There's no close button. Esc and a click outside close the editor and keep the marks, as now.

**Keys**

- Done becomes Copy, still on Return. It copies the drawing and closes the editor, as Done does.
- Cmd+Return sends to the selected session and closes the editor. While typing, it ends the typing
  and then sends. With no sessions, it does nothing.

**Sessions**

- Each session is a tab: its agent's logo and the start of its name, with the full name on hover.
  The five used last get tabs, and a last tab, "+28", opens the rest. Tabs shrink to fit the image's
  width, and the selected tab keeps its full name. The order is the one the Send menu got on
  2026-09-24 (`docs/send-menu-2026-09-24.md`).
- The session in front of you is selected when the editor opens. That's herdr's focused pane,
  unless a Codex thread was used more recently. Measured that day: two sessions had prompts from
  Pete a minute apart, and the focused pane was the one he was talking to. "The session you last
  wrote to" would have picked the other one.
- The tabs open with the last list read and update in place when the new one arrives, 0.5 to 2
  seconds later, because Codex's listing runs a process (`AppServer`). If the row waited, Copy would
  slide left under the pointer on every open.
- A reply card shows no tabs. The reply goes back to the session the card came from, and Send reads
  Reply. If that session is gone, the tabs come back so you can pick another.

**Comments**

- A click places a numbered pin, and its comment opens at the end of the list with the caret in
  it. A drag makes a box with a comment, and its pin sits at the box's top-left corner.
- Hovering a comment lights its pin or box, and hovering a pin lights its comment.
- Agents comment too. A pin's colour says who wrote it: the agent's colour, such as Claude's
  orange, or the accent blue for you. A white ring and a shadow keep a pin readable on any
  screenshot, so the colour pass doesn't colour pins.
- You can reply to any comment. Replies wait as drafts, and one Send carries every reply and the
  whole-screenshot message together. Send shows how many things it carries, such as "Reply 3".
- Copy draws the comments in a margin beside the screenshot, each with its number and author, so
  the words survive a paste into Claude Code, Slack or a PR.

**Proposed, not yet agreed: no history from one screenshot to the next.** Pete doubted that seeing
earlier rounds helps. An agent answers in one of two ways:

- **On the picture you sent,** which is the reply helper's default: its marks go on the
  `image.png` you sent unless it passes `--image`. Your comments are on the same pixels, so its
  comment can sit under the one it answers.
- **On a new picture,** after it changed something. Your pins point at pixels that may have moved,
  so your comments don't carry over. The agent's comment can name the one it answers, shown as
  "re ②" with your words quoted, and the card can link back to the one it answers.

The agent's session already holds the whole conversation, so Vignette doesn't keep a second copy.

## Still open

**Settle these first.**

1. **The Return rule.** Return copies and closes. It also finishes a comment and a reply draft, and
   could send from the message field. With text fields in the list and the bottom row, one stray
   Return can close the editor or send. Write one rule for Return, Cmd+Return and Esc in each place
   before building.
2. **Whether the comment tool absorbs the rectangle tool.** A drag with no words is just a box.
   That would leave Comment, Arrow, Text and Select.

**Other questions**

3. **How comments travel to a session.** Send submits one line, because herdr submits with Return.
   The proposal: Send writes `request.md` beside the image, with the comments by number, their words,
   their places as fractions of the image, and a crop of each box. The line only points at the
   file. Any agent can read Markdown, with or without the skill.
4. **What a comment is in the file.** Marks today are a rectangle, an ellipse, an arrow and a text
   (`Drawing.swift`). A comment adds a stable id, a number, a pin or a box, its words, its author,
   and the comment it answers. The file format, the agent's `marks=` format, the skill and the reply
   protocol all change with it.
5. **Naming the sender of a pushed image.** An image an agent pushes with `add` records the agent's
   name but not its session, so no tab can say Reply. The skill could pass the session id with the
   push. Claude Code gives an agent its id as `CLAUDE_CODE_SESSION_ID` (checked in a session on
   2026-09-24). Codex isn't checked.
6. **Whether Cmd+1 to Cmd+5 are free in the editor,** to pick a tab by key.
7. **Codex's logo** waits on the vendor-logo review in `docs/TODOS.md`. The mockup uses a
   placeholder.
8. **Whether Codex's `recencyAt` moves while a thread works on its own,** as a Claude Code
   transcript does. It decides whether a busy Codex thread can take the default from the pane in
   front of you.
9. **The author in the Copy margin.** "Pete" helps a person reading a paste, and is noise for an
   agent.

**Issues found in review**

- **The screenshot gets smaller.** The rail takes about 54 points of width, the list about 310,
  and the bottom row about 82 of height where today's bar takes 53. All of it comes out of the
  frame's room (`annotatorRoom`), beside the recent stack, so small text in a screenshot gets harder
  to read and to point at. Measure it on a 1512-point screen. Ways to win room back: show the list
  only once there's a comment, or let it overlap the stack's strip.
- **Numbers must freeze once sent.** If deleting comment 2 renumbers 3 as 2 after the agent has
  answered "re ③", the answer points at the wrong comment.
- **Agents place pins imprecisely.** A model is poor at exact pixel positions on an image it only
  looked at, and one misplaced pin makes the rest less trustworthy. An agent that drove the page it
  captured knows where its elements are. Otherwise a box is more forgiving than a pin, and a comment
  with no place should be allowed.
- **The Copy margin shrinks the screenshot for a model.** A vision model resizes to a long edge of
  1568 pixels, as `Stitch.readerScale` assumes. A margin on the right of a wide screenshot makes the
  screenshot part smaller. The margin should go on whichever side keeps it largest, which
  `Stitch.compose` already works out for pieces.
- **The log must not carry comment text.** `[state]` reports a text mark's frame and never its words.
  Comments, replies and the request files need the same care.

**Opportunities**

- **A full-resolution crop of each box, sent with the image.** Small text that blurs when the whole
  screenshot is resized stays readable in the crop. This is the "crop per mark" idea in
  `docs/TODOS.md`.
- **A sharper pitch.** "Figma-style comments on any screenshot, with your coding agent" says more
  than the site's current headline. The recordings would change too: clip 3's "too far!" and "add a
  ladder?" are comments (`docs/recordings-2026-09-24.md`).
- **Several screenshots, one message.** Today each Send is its own request and its own turn for the
  agent. Comments on three screenshots could go as one message, as Stitch makes one image from
  several.
- **Three shippable steps.** First the layout: the rail, the bottom row, the tabs, and Copy in place
  of Done. Then your own comments: pins, boxes, the list, the Copy margin, and Send as text. Then
  agents' comments and replies: the `marks=` format, the skill and the reply protocol.

## Background

**How the design got here, 2026-09-24**

- Send was a menu. The first plan named the session on a Send button, with a chevron for the rest.
  Pete: "putting the session name in the button isn't a good idea." The sessions became pills above
  the bar, then tabs, when Pete moved the tools to a rail on the left: "if we did that i'd want to
  go with the sessions as tabs treatment."
- The note began as one field beside Send, because Send carried only the text marks on the drawing
  ("open the drawing and do what it asks", `ScreenshotRequests.requestLine`). Pete: "why don't we
  just allow you to add inline comments to things, similar to how comment work in figma". The note
  survives as the message about the whole screenshot.
- Pete first pictured a comment as only its pin, read by clicking it. Reading eight comments from an
  agent that way takes eight clicks, so the comments became a list beside the image.

**Why sending has to be as quick as pasting**

| Copy and paste | Send before the redesign |
|---|---|
| Return | Click Send |
| Switch to the terminal | Read the list and click a session |
| Click the right pane | |
| Paste | |
| Type what you want | |
| Press Return | |

Send saved the switch and the paste, but lost the typed prompt, and it had no key.
