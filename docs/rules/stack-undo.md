# Undo and Redo in the stack

- Cmd+Z in the stack undoes what Vignette last did to a screenshot, and Shift+Cmd+Z redoes it, as
  Finder's Undo does (`StackUndo`). Two actions make a step, whatever asked for them: the stack's
  hand, or a `vignette://trash` or `vignette://stitch` from a script. Undoing Delete puts each file
  back from the Trash with its drawing, which the Trash does not keep, and its card back where it
  was in the column. Its agent, its title and its Sent tab are extended attributes, so they travel
  with the file. A send still in its grace when the file went stays cancelled, and an agent reply's
  record stays marked removed. Undoing Stitch moves the stitched file to the Trash and brings back
  the cards it took out of the column; redoing it puts the file back and takes them out again.
- Copy, Copy Paths, Copy Drawing, Draw, Open, a selection, a scroll, a dismissal and a drag out
  change no file the stack owns, so they make no step, and Don't send is already the undo of a
  send. No stack action renames a file. A rename in Finder is Finder's to undo, and the steps follow
  it to the new name.
- The steps are the stack panel's own `UndoManager` (`ThumbnailPanel.undoManager`), so the Edit
  menu's items and `validateMenuItem` name the step ("Undo Move to Trash", "Redo Stitch"). Vignette
  is an accessory app and its Edit menu never shows. The names reach a person through VoiceOver,
  which hears them after each Undo and Redo, and a script through `[state] stack.undoTitle` and
  `redoTitle`. `docs/voice.md` has the names.
- Cmd+Z reaches the stack only while it has the keys. Lone thumbnails never take them, and the app
  in front keeps its own Cmd+Z. Deleting the last card closes the stack, so its step waits for the
  stack's next opening.
- The steps last while the app runs, through the stack closing and opening again, and not across a
  relaunch, as Finder's do.
- A step whose file has moved since (the Trash was emptied, a new file took the name, the stitched
  file is gone) is used up with a beep, as a disabled menu item's shortcut beeps. It also logs an
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
