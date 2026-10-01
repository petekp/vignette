# The annotation run has one owner

An annotation run starts when an image opens in the annotator. It ends when the annotator closes
with nothing after it. A run of a list opens each file in turn. `AnnotationRun`, a pure reducer,
owns the whole run: the transition the annotator is in, the files still queued, their counts, and
the moment the run ends. `ThumbnailController` sends it what happened and runs the effects it
returns.

## Why

`AnnotatorTransition` decides every flight and is tested by sequence. The queue around it lived in
`ThumbnailController`, beside the reducer rather than inside it:

- `queue`, `queueTotal` and `queueOpened`.
- `handover`, the next file, held for one `send` so `returnCard` knew the run went on.
- `restoreFocusOnEnd` and `uncopied`.
- The decision that the run was over (`!transition.isActive && handover == nil`).

Seven call sites had to empty the queue before sending `.dismiss`, `.close` or `.remove`. A park
can answer in the same turn, and a queue that still held files then opened the next one. Every
queue bug of the last two weeks landed in the controller, where nothing tested it:

- a583a35: opening the stack sent `.dismiss` before it emptied the queue, and the next file opened
  under the stack.
- c4a35af: a handover to a file with no card left the run open with the dim up.
- 84dc83a: a file gone from the queue skipped a number in the count.
- 7f73e9d: an answer inside an event's effects ran nested inside it.

## The interface

```swift
struct AnnotationRun {
    enum Event {
        case annotate([String])      // a list: the first opens, the rest queue; replaces any queue
        case shown, parked           // the flight landed; the editor parked
        case cancel                  // Esc, a click outside, Cmd+W: the run ends
        case sent                    // Send: the run goes on
        case finish                  // Done or Return: the run goes on
        case dismiss(byHand: Bool)   // the panel is leaving; the run ends
        case remove([String])        // files trashed or deleted
        case newShot(String)
        case selectionChanged(added: [String], removed: [String])
        case copyFailed(String)      // Done's copy failed before the card came home
    }
    enum Effect {
        case prepare(String), show, park(String), abandon(String)
        case returnCard(String, copied: Bool), hideAnnotator, join(String)
        case next(String, place: Int, of: Int)     // the queue opens its next file
        case queued(String, place: Int, of: Int)   // a selected card joined the queue
        case endRun(restoreFocus: Bool)            // nothing follows: the dim goes, the focus may return
    }
    mutating func reduce(_ event: Event, opens: (String) -> Bool) -> [Effect]
    var phase: AnnotatorTransition.Phase { get }
    var key: String? { get }
    var isActive: Bool { get }
    var queue: [String] { get }
}
```

The events say what happened, and the run decides what that means for the queue. Esc and Send
both close the image, but Esc ends the run and Send does not, so they are two events.

`opens` is asked, before `reduce` returns, whether each file the batch opens has a card. A queued
file may have gone or stopped reading since it was queued. One that does not open is passed over:
the run opens the file after it, or ends. This happens before any effect runs, so the room beside
the stack and the flights are aimed at the image that really opens next.

`AnnotatorTransition` stays as it is, held privately inside `AnnotationRun`, and keeps its own
tests. `AnnotationRun` ends or keeps the queue before it hands an event to the transition. When the
transition goes idle after a `returnCard`, the run opens the next queued file in the same batch, so
the effects read `returnCard(A) next(B) prepare(B)`, the same shape as a swap. When nothing follows,
or after `hideAnnotator`, it ends the run with `endRun`.

`EventHold`, beside the reducer, holds an event that arrives while another is being handled and
runs it right after. `ThumbnailController.send` used to do this itself; the tests now drive the
same hold.

## What stays in the controller

- The `Card` the run is about (`sessionCard`): it carries an image and mark layers, which are the
  controller's to show.
- Making a card. A request from a person makes its card before the event is sent, as before, so a
  file that cannot be read never reaches the run. A file the run opens from its queue gets its card
  made in the controller's `opens` closure.
- Every effect: flights, the dim, the room beside the stack, the focus, the log lines.

## Behaviour

The same, except for four edges, each made consistent with a rule AGENTS.md already states:

- **Send during the flight out goes on to the next file.** "Send closes the editor without a
  copied mark, and the queue carries on to the next card." Before, a Send pressed before the
  flight landed ended the run and left the queue behind, unused.
- **A list requested while a dismissal parks does not open its second file.** The transition
  already lets a dismissal win over a later request. Before, the queue the request had set opened
  its second file once the park answered.
- **A queued file that cannot open logs `[annotate] error unreadable-image <name>`.** Before, a
  file whose header did not read was skipped silently.
- **A handover is one batch.** Before, it was two batches in the same turn: the finished card's
  return, then the next file's `annotate`. Now the room is made and both flights are aimed in one
  batch, as a swap does.

The `[transition]` log line is one per event, as before, and also names how many files are queued.
`[state]` keeps its keys: `transition` and `stack.queue`.

## Tests

`Tests/AnnotationRunTests.swift`:

- One sequence per rule: a list opens its first file and queues the rest; Done opens the next file
  in the same batch and the last Done ends the run; Esc ends the run; Send goes on; a quick Done
  ends it; a dismissal with a park that answers in the same turn opens nothing; a queued file that
  does not open is passed over, and the run ends when none is left; a removed file does not skip a
  number; removing the open file ends the run;
  a selection adds and takes files from the queue, never the open one; a failed copy takes the
  copied mark off the returning card.
- Random sequences through `EventHold`, 1000 seeds, including answers in the same turn, lists,
  selections, removals, failed copies and a file that never opens. Invariants: the queue is empty
  whenever the run is idle, and right after Esc or a dismissal; `endRun` comes once per run, in
  exactly the batch where the run goes idle; nothing opens while a dismissal ends the run; a failed
  copy leaves its card unmarked; a file that does not open is never prepared; the transition's own
  invariants still hold.

`AnnotatorTransitionTests` drive `EventHold` too, instead of their own copy of it.

An end-to-end scenario, `annotate_queue`, under `--input`: annotate three files by URL, press
Return twice, and check each time that the next file opens with the dim still up, no `endRun`, and
the previous card copied; then cancel, and check that the run ended with the dim down and nothing
queued. No scenario opened more than one file before. The controller's half of the queue, where
every bug above landed, had no test.

## Verification

1. `scripts/build.sh --test` in the worktree, then `lsregister -u` on the built app. All 422 tests
   pass. With the dismissal's queue-emptying removed, four of the new tests fail, the random test
   at seed 0.
2. `scripts/e2e/e2e.py run`: every scenario without input passes.
3. `scripts/e2e/e2e.py run --input`, which posts keys, so it runs with Pete's go-ahead.
