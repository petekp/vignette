# State machines are pure reducers, and the AppKit side only runs their effects

The editor, the moves into and out of the annotator, the annotation run, the zoom and card notices
are each a pure value that takes an event and returns the effects to run. The windows and views run
those effects and decide nothing. Sequence and random-sequence tests can then drive each machine
with no window. Before the annotation run became one, seven call sites had to empty the queue
before an event whose answer could come in the same turn, and that is where the last four queue
bugs came from.

## Consequences

An effect can answer inside the event that asked for it, as the editor's park does. Events
therefore pass through one hold that runs an event arriving mid-handling right after the current
one, so each machine sees its events in order.

Sources: commits fd012b0, 1ee1067, 4c4a541 and 6e0baf2, `docs/annotation-run-2026-10-01.md`.
