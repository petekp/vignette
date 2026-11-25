# Screenshot comments: the plan

Pete asked on 2026-11-11 for comments on screenshots, like Figma's. A person drags a rectangle round
any part of a screenshot, or clicks a point, and writes one or more comments about it. Each place
then collapses to a numbered circle, so a crowded area can hold many comments. Today a person writes
notes all over the picture, and in a dense area they collide.

This plan turns that request into steps that can be built against today's editor. It replaces the
11-11 proposal and its review (`screenshot-comments-proposal-2026-11-11.md` and
`REVIEW-screenshot-comments-2026-11-11.md`), which were never committed. [What the 11-11 proposal
gets wrong](screenshot-comments-2026-11-24/proposal-11-11.md) says what changed. Nothing here is
built. Six choices are Pete's, each marked **Question** with a recommendation. Three of them have
mocks.

[ADR 0030](adr/0030-pins-are-kept-in-the-drawing-file.md) is the draft of the storage decision, the
one part that is hard to reverse.

## Words

`docs/glossary.md` lists "comment" as a word to avoid for a note. It already uses "badge" for the
agent's name on a note, and "thread" for a Codex thread. This plan uses four words the glossary does
not have yet, and step 1 adds them.

| Word | Meaning |
|---|---|
| Pin | A numbered place on a screenshot, a point or an area, that holds one or more comments. On the picture it shows as its number in a circle. Pete's "numbered badge" is a pin. |
| Comment | The words one person or one agent wrote on a pin. A pin's comments are kept in the order they were written. |
| Pin number | The number a pin shows |
| Cluster | Pins too close to tell apart at the current zoom, drawn as one circle with their numbers |

A note stays as it is today, words on a tag drawn on the picture. A pin's comments are not drawn on
the picture until someone opens the pin. The glossary's **Drawing**, "all the marks on one
screenshot", becomes the marks and the pins.

## The plan's parts

| Part | What it settles |
|---|---|
| [What a pin is](screenshot-comments-2026-11-24/pins.md) | A pin's fields, a drawing that holds only pins, the drawing file and version 2, and how numbers stay put |
| [Pins in the editor](screenshot-comments-2026-11-24/editor.md) | The Comment tool, writing comments, where they show, a pin's look, size and zoom, dense areas, keyboard and VoiceOver |
| [Copy, Send, Stitch and Reply](screenshot-comments-2026-11-24/outputs.md) | What each output carries, agents' answers, and the message field |
| [Undo, state machines and build steps](screenshot-comments-2026-11-24/building.md) | Undo steps, the state machines that change, and four steps that each ship on their own |
| [What the 11-11 proposal gets wrong](screenshot-comments-2026-11-24/proposal-11-11.md) | Where this plan departs from the earlier proposal, and what is left out |

## Pete's questions

| Question | Recommended | Where |
|---|---|---|
| 1. Keep today's marks beside pins? | Keep every tool and add Comment as a fifth | [editor](screenshot-comments-2026-11-24/editor.md) |
| 2. Where an open pin's comments show (mock 1) | A popover beside the pin | [editor](screenshot-comments-2026-11-24/editor.md) |
| 3. What a pin looks like (mock 2) | A red circle at the area's corner, the outline only on hover, selection or open | [editor](screenshot-comments-2026-11-24/editor.md) |
| 4. What Copy puts on the clipboard (mock 3) | One PNG with the comments in a list | [outputs](screenshot-comments-2026-11-24/outputs.md) |
| 5. Should an agent answer on the pins it was sent? | Yes, as step 4 | [outputs](screenshot-comments-2026-11-24/outputs.md) |
| 6. Does a stitch keep its pieces' pins? | Yes, as live pins numbered from 1 | [outputs](screenshot-comments-2026-11-24/outputs.md) |
