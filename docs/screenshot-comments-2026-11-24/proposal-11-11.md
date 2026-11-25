# Screenshot comments: What the 11-11 proposal gets wrong

Part of [the screenshot comments plan](../screenshot-comments-2026-11-24.md).

The proposal was written against the editor of 11-11. Since then the editor keeps its undo history
and message in the drawing file, and shares one undo timeline with the stack. Its toolbar carries a
message and a session control, and double-click editing is changing. This plan departs from it as
follows.

- It kept unfinished comments as drafts with an indicator, and had Copy and Send ask whether to
  include them. Vignette keeps what was typed when typing ends, and asks no questions
  (`docs/no-toasts-2026-09-30.md`). Here a comment posts whenever its typing ends.
- It saved with Cmd+Return and broke lines with Return. In Vignette Cmd+Return sends, and Return
  finishes a note and sends from the message field. Here Return posts, and Cmd+Return posts and
  sends.
- It said to reuse the editor's history. A history step names a mark by its index, and the file
  checks its history against a hash of the marks and message (ADR 0028). Pins need a step that names
  them by `id`, and the hash has to cover them.
- It predates ADR 0029. Pin steps are editor steps, so Cmd+Z at an opening's start closes the
  screenshot as it does now. The timeline does not change.
- It said nothing about an older build writing over a file with pins. Here such a file is version 2,
  which an older build leaves alone.
- It treated a drawing as present when it has marks, as the code does. Here step 1 changes that
  everywhere first.
- It checked the picture's content so a replaced image could not inherit comments. Marks already
  follow the size and key checks, and pins follow the same ones. A content check would cover pins
  and not marks.
- It stored a file of anchors with a request and left open how the words reach the agent. Here the
  words go in the line the agent already reads, after the person's message, which it did not
  mention.
- It added Copy Markup Only, Copy Comments and a switch to hide badges. Each is one more choice
  before sharing. Clusters and the list keep the picture readable, and Send carries the words as
  text. A person who wants a picture without pins can delete them.
- It gave a stitch its own numbering in pixels, which loses the words. Question 6 keeps them.
- It called the place a badge, and its entries comments in a thread. In the glossary a badge is an
  agent's name on a note, "comment" is an avoided name for a note, and a thread is a Codex thread.
- Its mocks show a checkout page in a generic light style. The new mocks use one of Pete's own
  screenshots and Vignette's look.

## Not in this plan

- Resolving a pin, or hiding resolved pins. With one person and an agent, deleting a pin does the
  same job. It could follow step 4, when an agent's answer might mark a pin done.
- Comments on screen recordings, which are never drawn on.
- Pins in live ink, whose note is already words about one place.
