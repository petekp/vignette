# One undo timeline holds the stack and the annotator

Supersedes in part ADR 0028: reopening a screenshot in the same run of the app no longer lets
Cmd+Z step straight back through the steps of its earlier openings. The history is still kept in
the drawing file, and after a relaunch a screenshot reopened still undoes its stored steps.

Cmd+Z and Shift+Cmd+Z have one owner, `UndoTimeline`, wherever Vignette has the keys: the stack or
the editor. It keeps Delete, Stitch, opening a screenshot in the annotator and closing it, in the
order they were made. The editor's steps are not copied into it. Each step of the timeline records
how many steps the screenshot in the editor had to undo when it became the next step. While a
screenshot is open, Cmd+Z undoes the editor's own steps down to that number, then runs the
timeline's step. So the editor's steps sit between the opening and the close they were made in.

The timeline lasts while the app runs. A screenshot's own steps stay in its drawing file, which
ADR 0028 decided. After a relaunch the timeline is empty. The stored steps are older than anything
the timeline holds, so a screenshot's opening undoes its stored steps first once nothing older is
left.

Reversing this means taking the two histories apart again. Nothing on disk changes: the timeline
is not stored.

## Considered options

- Copying each editor step into the timeline as it is made. The editor's steps already live in the
  drawing file, which also changes outside the editor: agents' marks join it while it is closed,
  and a drawing changed another way drops its history. Two copies of the steps would disagree.
  Recording a depth keeps one copy.
- The stack's `UndoManager`, as the stack used before. Choosing between the editor's step and the
  timeline's needs the next step's screenshot and depth, which an `UndoManager` does not expose.
- Opening and closing as steps that only reach the stack, with the editor's Cmd+Z stopping at its
  first step. Pete asked for one full timeline, so Cmd+Z at an opening's start closes it.
- Undoing a close from Send or Done by unsending or uncopying. Don't send is already the undo of a
  send, and a copy cannot be taken back from another app's paste. Undoing the close only opens the
  screenshot again.
