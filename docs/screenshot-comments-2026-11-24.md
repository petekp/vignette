# Screenshot comments: the plan

Pete asked on 2026-11-11 for comments on screenshots, like Figma's. A person drags a rectangle round
any part of a screenshot, or clicks a point, and writes one or more comments about it. Each place
then collapses to a small numbered teardrop, so a crowded area can hold many comments. Today a
person writes notes all over the picture, and in a dense area they collide.

This plan turns that request into steps that can be built against today's editor. It replaces the
11-11 proposal and its review (`screenshot-comments-proposal-2026-11-11.md` and
`REVIEW-screenshot-comments-2026-11-11.md`), which were never committed, and folds in the parts of
them that still hold. [The 11-11 proposal](screenshot-comments-2026-11-24/proposal-11-11.md) says
what this plan keeps from it and where it departs. Nothing here is built. Pete decided the plan's
six open choices on 2026-11-25, and each is marked **Choice** with his words.

[ADR 0030](adr/0030-pins-are-kept-in-the-drawing-file.md) records the storage decision. That is the
one part that is hard to reverse.

## Words

`docs/glossary.md` lists "comment" as a word to avoid for a note. It already uses "badge" for the
agent's name on a note, and "thread" for a Codex thread. This plan uses four words the glossary does
not have yet, and step 1 adds them.

| Word | Meaning |
|---|---|
| Pin | A numbered place on a screenshot, a point or an area, that holds one or more comments. On the picture it shows as a red teardrop holding its number, whose tip marks the place. Pete's "numbered badge" is a pin. |
| Comment | The words one person or one agent wrote on a pin. A pin's comments are kept in the order they were written. |
| Pin number | The number a pin shows |
| Cluster | Pins too close to tell apart at the current zoom, drawn as one teardrop widened to name them, such as "3 · 4" |

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
| [The 11-11 proposal](screenshot-comments-2026-11-24/proposal-11-11.md) | What this plan keeps from the earlier proposal, where it departs, and what is left out |

## Pete's choices

Pete decided these on 2026-11-25. He chose from mocks shown to him in Vignette, which are not kept
in the repo.

| Choice | Pete's words | What it means |
|---|---|---|
| 1. Today's tools | "Keep all, add Comment" | Select, Rectangle, Arrow and Text stay, and Comment is a fifth tool |
| 2. Where an open pin's comments show | "Popover by the pin" | A popover beside the pin, built on live ink's popover |
| 3. What a pin looks like | "Teardrop" | A red teardrop whose tip marks the place |
| 4. What Copy puts on the clipboard | "Picture plus comment list" | One PNG with the pins on the picture and their comments in a list |
| 5. Agents answer on the pins they were sent | "Yes, as step 4" | A reply card holds the person's pins with the agent's answers |
| 6. A stitch and its pieces' pins | "Keep as live pins" | The stitch's pins are live and numbered from 1 |
