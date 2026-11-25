# Undo and redo

How the drawing editor's undo and redo behave. It is section 7 of [the drawing editor](editor.md).

- One owner handles Cmd+Z, Shift+Cmd+Z and any Undo or Redo menu item, on the image and in the
  message field alike.
- Each step is one thing the person did. Its name follows Undo or Redo in the Edit menu, and
  VoiceOver says it after each undo or redo, as in "Undo Arrow" or "Redo Typing":

| Step | Name |
|---|---|
| Creating a rectangle | Rectangle |
| Creating an ellipse | Ellipse |
| Creating an arrow | Arrow |
| Moving marks by a drag, or one nudge press with its repeats | Move |
| Resizing | Resize |
| Bending an arrow | Bend Arrow |
| Dragging an arrow's end | Move Arrow End |
| Duplicating, with Cmd+D or an Option-drag | Duplicate |
| Deleting | Delete |
| Pasting, or dropping | Paste |
| Cutting | Cut |
| One typing session; a new text and its first session are one step | Typing |
| Agents' marks added to the open drawing | The agent's name, as in "Claude's Marks"; "Agent's Marks" when the marks name none or several |
| Typing in the message field, until the field loses the keys, the bar is pressed, or another step comes | Typing |
| A paste or a cut in the message field | Paste, Cut |

- Selecting is never a step. Undo and redo put back the selection that belonged to the step.
- Cmd+Z during a drag cancels the drag and undoes nothing more.
- A step that changes the drawing holds its marks and its pins together, so a step that moves or
  deletes both undoes as one. Undoing a deleted pin brings it back with its own number.
- The message field's steps are in the one history, in order with the marks. While the field has
  the keys, Cmd+Z undoes the last step, whether it changed the marks or the words, and the keys
  stay in the field. Undoing a step of the field's words while the image has the keys changes the
  words and leaves the keys on the image. While a word is being composed, Cmd+Z is the input
  method's.
- The history is kept with the screenshot's drawing ([the drawing file](drawing-file.md)), so
  reopening the screenshot, or relaunching the app, keeps its undo and its redo steps. Redo lasts
  until the next change, as in Apple's editors.
- Opening and closing a screenshot are steps of the app's undo timeline
  ([Undo and Redo in the stack and the annotator](rules/undo-timeline.md)). Cmd+Z undoes the editor's
  steps back to where this opening began, then closes the screenshot. The stored steps from before
  come first when nothing older is left in the timeline, as after a relaunch. Otherwise they come
  back once the timeline reopens the screenshot where an earlier opening closed it.
- Agents' marks added while the screenshot is closed join its history as one step, as they do while
  it is open. A drawing changed any other way outside the editor, such as by a reply's drawing
  installed, opens with no history. An image replaced by one of another size
  opens without its drawing, and so without its history. A rename keeps both. A drawing with no
  marks, no pins and no message keeps no file, and so no history.
- A file keeps the newest 100 steps, in about 256 KB.
