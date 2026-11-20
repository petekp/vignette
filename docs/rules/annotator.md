# The annotator and its reducer

- The annotator must open instantly, so the editor opens at `prepare`, before the image is
  decoded (`AnnotationController.open`). It opens with the screen-size decode when `Thumbnailer`
  has it cached, which it does after a hover, and with no image otherwise; `setImage` adds the image
  when the decode answers, and `[annotate] loaded <ms>ms <name>` is logged then. Opening first is
  what lets the keys work from `prepare`, and it leaves no moment in which an agent's push could
  miss the open drawing. A decode that answers after another opening began is dropped
  (`AnnotationController.opening`).
- Which image is in the annotator, where it came from, what is in flight and what opens next have
  one owner: `AnnotationRun`, a pure reducer held by `ThumbnailController`. The controller sends
  what happened (annotate a list, shown, parked, cancel, sent, finish, dismiss, remove, newShot,
  selectionChanged, failed, loaded, takesPresses, arrived) and runs the effects it returns
  (prepare, show, park, abandon, returnCard, hideAnnotator, join, next, queued, endRun, landed,
  handOverPresses, liftFlight). Each image the run sends to the annotator is an `Opening`: the
  file's path and an id the run mints and never reuses, so the same file opened again is another
  opening. Every answer names its opening, and one that names any other than the current one
  changes nothing. The annotator holds the same value (`AnnotationController.opening`), which is
  what Send and the session listing compare. The moves into and out of the annotator
  are decided by `AnnotatorTransition`, a pure reducer the run holds privately. Done sends
  `finish`: the card returns and takes the Copied notice (`returnCard`'s `copied`), and a lone
  thumbnail that was alone in the corner, and so left the panel when the annotator opened, comes
  back to the corner for it. Esc
  sends `cancel` and Send sends `sent`, which both reach the transition as `close`: the card returns
  without the Copied notice. A lone thumbnail that comes home with nothing to show, no
  send or failure notice and no other card in the corner, does not land: it flies into the corner and
  off the screen's edge (`ThumbnailController.leavesAtOnce`, `flyAway`). Quick draw sends
  `dismiss(byHand: true)`. A `prepare` is never emitted while a
  park is in flight, which is what serializes rapid swaps; a new screenshot during a lone annotation
  joins the panel instead of closing the editor. Every event logs one
  `[transition] <event> -> <phase> [queued=<n>] effects=…` line, where an opening prints as
  `<file name>#<id>`. The annotator never hides itself: Esc, a click
  outside, Cmd+W and Done ask through `onClosed` and `onFinished`, and the reducer decides. `show`
  is the window coming up behind the flight. The editor parks synchronously, so an effect can answer
  inside the event that asked for it: at zoom 1 there is no fit-out, and `parked` comes back in the
  same turn as `park`. `EventHold` holds an event that arrives while another is being handled and
  runs it once that one is done, so the reducer's events stay in order. The
  `parking` phase stays for the zoomed case, where the window springs back to the fit before it
  comes down. A dismissal of the stack takes the image with the column: `hideAnnotator` flies it
  from the editor to its slot's place off the screen, on the slide-out's spring, so a zoomed editor
  springs back to the fit first and its image starts about 0.2 s after the column. The image
  leaves at once, with the newest card, rather than at its slot's place in the stagger. A card already on its way home when the column
  goes is turned around the same way (`ThumbnailController.slideOut`). While the stack shows, a click
  outside reaches only the stack's `OutsideClick` and is a dismissal like the shortcut's
  (`docs/rules/flights-and-presses.md`). Add a sequence to `AnnotationRunTests`,
  or to `AnnotatorTransitionTests` for the transition's table, before changing either. Their
  random-sequence tests check the invariants through `EventHold`, with same-turn answers among
  their sequences. A swap runs two flights at once, and the
  stack keeps the slot, drawn empty, so the card flies back to the same place.
- The flight to the annotator can be interrupted. In `flyingOut` the window has not come up, so
  nobody has seen that image: a `close` or an `annotate` of another key answers in the same turn
  with `abandon` and `returnCard`, and the flight turns around from where it is (`fly` on an id
  already flying keeps the frame and blends the bow). `abandon` is `AnnotationController.abandon()`:
  it parks the drawing and stores it, since the editor holds the keys during the flight and a key
  pressed then can change the drawing, and it takes the window down with no fit-out, since no zoom
  can have happened. The controller's `.abandon` keeps the parked marks (`parkedMarks`), as `.park`
  does, so the flight home carries the drawing as it was parked, not as it left. `dismiss` and
  `remove` still park from `flyingOut`: a dismissal's `hideAnnotator` turns that same flight off the
  screen with the column, and a removal's ends it. Esc during the flight comes back through `onClosed` as `cancel`.
  `docs/flight-interrupt-2026-09-18.md` has the frames.
- Annotating a list is one annotation run with a queue (`AnnotationRun.queue`, `stack.queue` in the
  state report): the first file opens and the rest wait, and finishing one opens the next until the
  list is done. When the transition goes idle after a `returnCard`, the run opens the next file in
  that same batch (`returnCard(A) next(B) prepare(B)`). So the card flies home with its Copied notice
  while the next flies out, which is a swap's two flights, and the room beside the stack is made
  once for both. Between two files the dim stays up and the focus stays with Vignette. A screen change gives a dim that is up the frame of the screen the editor is on
  now (`DimPanel.refit`, from `ThumbnailController.screensChanged`, also when the stack is not visible). `endRun`
  comes only when nothing follows: it hides the dim and carries how a person's hand ended the run
  (`RunEnding`), or nil when no hand did. The run decides nothing about the focus;
  `CornerPresentation` does, from that ending. Opening a card does not clear the selection, so after the last one Cmd+C or Cmd+S
  still takes all of them. While a card is in the annotator, selecting another card in the stack
  queues it next, in the order picked (`[annotate] queued <name> 3 of 3`), and deselecting it takes
  it back out (`selectionChanged`, from the model's `onSelectionChanged`). Esc, a dismissal, quick
  annotate, a stack presented anew and the open file going all end the run and drop the queue. Done
  and Send go on to the next file, and any other request to annotate replaces the queue. A queued
  file that has gone, or whose header no longer reads, is passed over before anything moves:
  `reduce` asks its `opens` closure, where the controller makes the card or logs `[annotate] error
  unreadable-image <name>`, and the run opens the file after it or ends. A person's request is
  checked the same way before it is sent, so a file that cannot be read never closes the image
  already open. `docs/annotation-run-2026-10-01.md` has the design and
  `docs/annotation-queue-2026-09-17.md` the handover.
