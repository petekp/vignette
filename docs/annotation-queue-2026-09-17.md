# The annotation queue (2026-09-17)

Return on several selected cards used to open one of them, the card picked last, and clear the
selection. The rest were dropped. Now the list is a queue.

## What it does

Every action receives a list: the cards in the order they were picked in the stack, or the files in
the order a URL names them. `annotate` opens the first and keeps the rest. Finishing one (Done, or
Return in the annotator) sends that card home and opens the next, until the list is done. The
selection is untouched from beginning to end, so Cmd+C or Cmd+S after the last card acts on the
same cards. Return, the strip's Draw button, and a `shotnote://annotate` naming several files
all start the same run: the queue is in the action, not in what pressed it.

The `[annotate] ok` line names the file that is opening and how many there are
(`ok Screenshot 1.png 1 of 3`); each later card logs one `[annotate] next Screenshot 2.png 2 of 3`.
`stack.queue` in the state report lists the files still waiting, in order.

## The handover

Done sends `finish` to the reducer. The park answers with `returnCard` and `markCopied` and the
phase is `idle` again. The controller takes the queue's next file in that same turn, before those
effects run, and sends `annotate` right after them. So the finished card flies home with its copied
mark while the next card flies out: the two flights a swap already runs. The reducer serializes
them by itself (a `prepare` is never emitted while a park is in flight), so its table is unchanged
and it knows nothing about a queue.

Taking the next file before the effects run is what makes the run one session. `returnCard` ends
the session when it is the last card: it drops the session card, hides the dim, and gives the focus
back to the app the user came from. With another file in hand it does none of that, so the dim
stays up and the focus stays in the annotator between two cards. A file that has gone since drops
out of the queue at that point instead of leaving the dim up with nothing behind it.

## Why the selection stays

Opening a card used to clear the selection. A queue needs the rest of it, and the card comes back
to its slot when it is done, so there was nothing to clear: the cards a user picked stay picked
until the user says otherwise. The selection strip itself stands aside while the annotator has an
image, because it would sit inside the frame's room; the cards keep their numbers and the strip
comes back when the run ends.

## What ends a queue

Esc or a click outside (`close`), a dismissal of the stack, quick annotate, and a stack presented
anew all empty it. A file that is removed drops out of it, and a run ends altogether when the file
that went is the one in the annotator. Anything else that opens an image
replaces the queue: a click on a card while the annotator is open, a URL naming one file, a capture
that goes straight to the annotator. Only the queue continues the queue.
