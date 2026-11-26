# `show` joins an agent's marks and pins to the drawing at once

Status: accepted, 2026-11-26, and built: `AppDelegate+Show.swift`. It supersedes ADR 0031's "`show` writes
nothing" and the Keep and Clear it led to. The rest of ADR 0031 stands.

ADR 0031 kept the marks and pins an agent brought with `show` in memory, drawn on top of the person's
drawing, until the person pressed Keep or Clear on the card or in the editor's bar. Pete, on that bar
(2026-11-26): "i don't think we even need this. can we just include a way to delete the comments from
within the comment itself?"

## The decision

`show` with `marks=` or `pins=` joins them to the first file's drawing as soon as the call is checked,
through `add`'s own path (`AppDelegate.addMarks`, `Drawings.add`), as one undo step named after the
agent ("Claude's Marks"). The step goes in the editor when the screenshot is open there, else in the
stored history. New pins take their numbers then. The cards come up after the write, and a write that
fails answers its error and shows nothing. The person removes the marks as they remove their own, a
comment from its popover, or all of them with Undo.

The shown state, the notice, the dim and the waiting calls stay as ADR 0031 has them, in memory.

## What it removes

The Keep and Clear buttons on the card and in the editor, the band "Marks from Claude", the marks on top
(`PendingMarks`, `Card.agentMarks`), the Keep Marks and Clear Marks steps of the undo timeline and
the take-back of a kept join (`Drawings.takeBackAgentMarks`). The log lines `[show] kept` and
`[show] cleared` and the `[state]` fields `agentMarks` and `agentPins` go with them.

## What was weighed

- Keeping Keep and Clear with clearer words. Pete read the bar as unclear, and a choice the person
  must make before the marks count is a step `add` never asks for.
- Joining at once but offering Clear. Undo already takes the step off, and a comment's own Delete
  takes one comment.

Reversing this means bringing back a layer of marks on top, held in memory, with its own controls on
the card and in the editor, and the undo steps that move marks between that layer and the drawing.
