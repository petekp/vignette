# The undo history is kept in the drawing file

Superseded in part by ADR 0029: within one run of the app, Cmd+Z in a screenshot opened again stops
at that opening's start and then closes it. Its earlier steps come back once the timeline reopens it.

Each screenshot's undo and redo history is kept in its drawing file, under `history`, beside the
marks and the message (`docs/drawing-file.md`). Reopening the screenshot, or relaunching the app,
lets Cmd+Z step back through what was done before, and Shift+Cmd+Z redo what was undone, until the
next change. The format's `version` stays 1: a build that does not know the key ignores it, and
any write of its own leaves it out.

The editor writes the history, and agents' marks added while the screenshot is closed add one step
to it, as they do while it is open. It is checked on read against `basis`, a hash of the marks as
stored and the message it ends at, and dropped when they differ. Every other writer, such as a
reply's install or live ink, writes the file without one. A step names
a mark by its index in the file's marks, since a mark's id lives only while the app runs.

At most 100 steps and 256 KB are kept, because a card reads the whole file to draw its marks.

Reversing this means teaching readers to ignore `history` again, and every file written since
keeps the key until it is next written.

## Considered options

- A file beside the drawing for its history. A rename, a removal, the launch sweep and the Trash
  would each have to move or remove two files, and the two could disagree after a crash. One
  atomic write keeps them together.
- Keeping the history across any change made outside the editor, such as a reply's install.
  Undoing a step recorded against marks that have since changed can bring back or move the wrong
  mark. Apple's editors clear the undo stack when a document changes on disk. Agents' marks are the
  exception, because they only add marks, and their step says so.
- Dropping the history when agents' marks arrive while the screenshot is closed. Sending a drawing
  to a session and getting its marks back is the agent loop, so every round would end the person's
  undo.
- A cap by steps alone. One paste of a long message is a large step, so bytes bound the file too.
- A history for a drawing with no marks and no message. Such a screenshot keeps no file, and a file
  kept only for its history would need its own place in the launch sweep and the rename.
