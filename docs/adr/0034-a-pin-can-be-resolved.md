# A pin can be resolved, by the person or by an agent

Status: accepted, 2026-11-26. Pete chose this design ("Build B") and decided that every hand-over
leaves resolved pins out ("Leave them out").

A pin asks for something: "too tight", "wrong date". Once that is done, nothing said so. The pin
stayed in colour, every Send carried it to the agent again, and every Copy listed it. The only way
to stop that was to delete the pin, which also deleted the conversation on it.

## What resolving does

A pin has `resolved` while its ask is done: who resolved it, the person or an agent by name, and
when. A resolved pin keeps its number, place and comments. It turns grey in place, and the
popover opens on "Resolved by Claude, 1 min. ago" with Reopen. It is never deleted or hidden.

- The person resolves an open pin with Resolve in its popover, or Reply and Resolve while the field
  holds words. Either is one undo step. Reopen is one too.
- A new comment on a resolved pin reopens it, since it asks again.
- An agent resolves a pin only when it says so: `"resolve": true` on an answer in `pins=`, or
  `--resolve` on a reply naming pins its `--comments` answer. An answer without it reopens a
  resolved pin. A new pin cannot be resolved, so an agent cannot leave a note that is born done.
- Copy, Done, a drag, Copy Drawing's rendering and Send leave resolved pins out
  (`Drawing.handedOver`). The agent and the clipboard see only open asks. Copied items pasted inside
  Vignette and a stitch keep resolved pins resolved, since they stay in Vignette, where they can be
  reopened.

## The file

`resolved` is written on the pin as `{"agent": true, "agentName": "Claude", "at": "…"}`, the fields
a comment uses to name its writer, with `agent` and `agentName` left out for the person. A file
whose drawing, or a step of whose history, holds a resolved pin is version 3. A build from before
this change leaves such a file alone instead of writing it back without `resolved`, which would
reopen every pin. A file without a resolved pin stays version 2 or 1, so older builds keep reading
it.

`ReplyProtocol.version` goes from 7 to 8, since a reply's comment gains `resolve`. A ticket from
before the update is refused by the new helper, so the person sends it again.

## What was weighed

- Hiding or collapsing resolved pins. The conversation would leave the picture it is about, and a
  reopen would need a place to find them. Grey in place keeps them where they were said.
- Any agent answer resolving its pin. An answer is often a question back or a partial fix. The
  agent has to say it is done.
- Keeping resolved pins in Copy and Send, marked as done. The agent would read the old asks again,
  and the person's copy would list finished work. Pete chose to leave them out.
- A separate `resolvedBy` string, as first sketched. It would name a writer differently from how
  comments do, so the reader would need two rules.
