# Undo and Redo in the stack and the annotator

- Cmd+Z undoes what Vignette last did to a screenshot, and Shift+Cmd+Z redoes it, as Finder's Undo
  does. One timeline holds every step in the order it was made (`StackUndo`): Delete, Stitch,
  opening a screenshot in the annotator and closing it, and between those the editor's own steps
  on the screenshot open then. Delete and Stitch make a step whatever asked for them: the stack's
  hand, or a `vignette://trash` or `vignette://stitch` from a script. Undoing Delete puts each file
  back from the Trash with its drawing, its message and its history, which the Trash does not keep, and its card back where it
  was in the column. Its agent, its title and its Sent tab are extended attributes, so they travel
  with the file. A send still in its grace when the file went stays cancelled, and an agent reply's
  record stays marked removed. Undoing Stitch moves the stitched file to the Trash and brings back
  the cards it took out of the column; redoing it puts the file back and takes them out again.
- Copy, Copy Paths, Copy Drawing, Draw, Open, a selection, a scroll, a dismissal and a drag out
  change no file the stack owns, so they make no step, and Don't send is already the undo of a
  send. No stack action renames a file. A rename in Finder is Finder's to undo, and the steps follow
  it to the new name.
- The timeline keeps its own two lists of steps, since choosing between the editor's step and its
  own needs the next step's screenshot, which an `UndoManager` does not show. `validateMenuItem`
  on the stack's panel and on the editor names the step ("Undo Move to Trash", "Undo Close
  Drawing", "Undo Arrow"). Vignette is an accessory app and its Edit menu never shows. The names
  reach a person through VoiceOver, which hears them after each Undo and Redo, and a script through
  `[state] stack.undoTitle` and `redoTitle`. `docs/voice.md` has the names.
- Cmd+Z reaches Vignette only while the stack or the editor has the keys. Lone thumbnails never take
  them, and the app in front keeps its own Cmd+Z. Deleting the last card closes the stack, so its
  step waits for the stack's next opening.
- The timeline's steps last while the app runs, through the stack closing and opening again, and
  not across a relaunch, as Finder's do. Each screenshot's own steps are kept in its drawing file
  (ADR 0028), so after a relaunch a screenshot opened again still undoes them.

## Opening and closing a screenshot

- Opening a screenshot in the annotator is an "Open Drawing" step, and the run ending with it
  closed is a "Close Drawing" step (ADR 0029). Moving from one screenshot to another without the
  annotator closing is one "Open Drawing" step, which undoing takes back to the screenshot before:
  Left and Right, a click on another card, a queue moving on to its next file.
- Every opening is a step, whatever asked for it: a card's Draw, a click, a queued
  `annotate` of several files, which makes one step per file, or `vignette://annotate` from a
  script. Redo opens the screenshots again one at a time. It does not start the queue again.
- While a screenshot is in the editor, Cmd+Z undoes the editor's steps made since this opening
  began (`docs/editor-undo.md`). The next Cmd+Z undoes the opening: the annotator closes and the
  stack shows again, and the one after goes on to the steps before it. Shift+Cmd+Z walks forward the
  same way, through the opening, then the editor's steps redone, then the close.
- An opening stops Cmd+Z at its own start. A later opening of the same screenshot does too, and the
  steps of the earlier opening wait at their place, after the close before them is undone.
- Undoing a close opens the screenshot again as it was closed, with its history. A close that came
  from Done, Send or Reply is undone the same way: the screenshot opens again, and nothing is
  uncopied or unsent. Don't send is the undo of a send. Redoing a close closes it as Esc does, with
  no copy and no send.
- Undoing an opening leaves the editor's steps that were undone in it on the screenshot's redo.
  Redoing the opening opens it where it began, and Shift+Cmd+Z then redoes those steps. A new step in
  the editor ends what the timeline could redo, as a new step ends the editor's own redo.
- A screenshot opened or closed by Undo or Redo moves on the flights a click on its card or Esc
  starts. The stack keeps the keys while the card flies home (`AnnotationRun.Event.undo`), so the
  app in front never gets a Cmd+Z meant for Vignette. Over lone thumbnails nothing would have the
  keys once the annotator closed, so there Cmd+Z stops at the opening's start and beeps.
- A key held down repeats only the editor's own steps. Each opening, close or step of the stack's
  takes a new press.
- With nothing older left in the timeline, as after a relaunch, a screenshot's stored steps come
  before its opening: they are older than anything the timeline holds.
- A close because the file left the folder is no step: the step that took the file away closed the
  screenshot. Undoing a Delete of the screenshot in the editor opens it there again.
- A file keeps at most `EditorHistory.maxSteps` steps, dropping the oldest. A screenshot that opens
  with fewer steps than it closed with moves the timeline's places in its history down by as many.
  Agents' marks join a closed screenshot's history on top, which leaves those places where they are.
- A screenshot to open again is the same file when its size and its modification date are. A sync
  client can replace a file with the same one under a new file number.
- Undo and Redo wait while the annotator opens or closes a screenshot, as behind a zoom springing
  back to the fit, and beep until it has, since the next step is not known before.
- A step whose file has moved since (the Trash was emptied, a new file took the name, the stitched
  file is gone, the screenshot to open again was deleted or replaced) is used up with a beep, as a disabled menu item's shortcut beeps. It also logs an
  `[undo] can't …` line, since its card is not on screen to say so. A step that can run in part
  does that part and logs the rest.
- A card comes back as a card joins the open stack (`ThumbnailController.putBack`, through
  `shiftUp`). The layout changes at once, the cards that were there are lifted back to where they
  were drawn and spring to their slots on `ui.shiftUpDuration`, and the returning card slides in
  from the edge on the card slide-in. It goes before the first older card still in the column, else
  after the first newer one (`StackUndo.place`). One card that comes back takes the focus. Several,
  or one while cards are selected, become the selection, as Finder selects what its Undo put back.
- A file put back is not a capture. `FolderWrites.putBack` reserves its name, so the watcher's
  report neither copies it nor opens the editor. It also records the write time, so a removal from
  an older listing waits for a newer one.
