# The annotator's toolbar

Where Send starts is in `send-start.md`, and the target and its menu are in `session-menu.md`.

- The annotator's window is borderless and spans the screen's visible frame. The frame inside it is
  sized to the image. Its toolbar is a native panel (`AnnotatorToolbar.swift`) placed under the
  frame (`AnnotatorToolbar+Placing.swift`), one level above the flight layer, so a flight into or
  out of the editor passes under it as the editor does. A zoomed frame growing down carries the bar
  with it, in the turn the frame moves (`follow`, `docs/rules/zoom.md`). It is not the annotator window's child, since AppKit keeps a child window at its
  parent's level. It shows `EditorCore.Tool.allCases`, the editor reports the active tool through `onTool`,
  and the bar calls `setTool`, `send` and `done` on the editor, `send` through `onSend` and
  `EditorView.send(to:)`. The destination Send was pressed for travels in the editor's send effect (`EditorCore.Effect.send(_:to:)`), so a press the editor
  ignores, as while it closes, leaves nothing for the next image. A key's send carries no
  destination and goes where the bar's filled button sends. The bar is tools, one divider, then
  what `ToolbarOffer` says the image offers: Copy alone when there is no session to send to; Copy,
  the target, a message field and Send; or the message field and Reply on a card that names the
  session it came from (an agent's reply, or a push with `session=`). Reply is unavailable while
  there is no message and the drawing is exactly what the agent sent (`Model.nothingToReply`,
  `Model.drawingAsSent`, which the editor's `onChange` updates on every change). It rests as a
  control beside a send does (`Resting`), Tab skips it, and its tooltip says why. Return and
  Cmd+Return then copy and close as Done does (`AppDelegate.sendDrawing`). Copy is Done under a label
  that says what it does. The bar's panel takes the keys only for a press on the message field
  (`ToolbarPanel.sendEvent`), since SwiftUI's buttons ask for them as a field does; a press on a
  button leaves them with the editor. The panel also takes them once the image's window is up, when
  the bar has a message field and no key or press has reached the editor yet
  (`AnnotationController.offerTyping`), so typing goes to the agent at once. When the panel does not
  become key then, the field lets the focus go and logs `[annotate] message field did not get the
  keys`, so the image keeps Tab, Space and the arrows, and a later offer tries again. A pick in the
  target's menu, however it is made, gives the field the keys too, with the caret after any words in it
  (`AnnotatorToolbar.typeAfterPick`, `ToolbarPanel.caretToEnd`). It takes them a turn after the menu
  closes, after the bar starts to spring to the new target's width. The field counts as
  typed in only while the panel is key
  (`Model.keyed`), because AppKit makes it the panel's first responder when the bar comes up. The
  panel forgets a press on the field when it resigns the keys, so only a new press or an ask makes
  it key again (`ToolbarPanel.resignKey`).
  While the field has the keys, Cmd+W, the zoom keys, and Cmd+Z and Shift+Cmd+Z unless a word is
  being composed, do what they do on the image: the panel hands them to
  `AnnotationController.fieldCommand` before the field sees them (`FieldCommand`). Other Command
  keys stay with the field, Cmd+C too unless the field is empty. There is no
  palette: a mark's colour says who drew it.
  Return copies and replies only on a card that names its session; Cmd+Return
  sends or replies (`EditorCore.finishes`). On the image, Return never sends to a session Vignette
  picked. In the message field Return sends, as in a chat app, with the target beside it. A field
  that took the keys on its own, empty or as it opened, asks nothing to send, so
  Return and Esc do what they do on the image (`Model.fieldUntouched`, `fieldReturn`, `fieldEscCloses`). A
  pick ends that (`Model.pick`): choosing a session is asking to write to it, so the field then acts
  as pressed. A letter types, Return sends, and Esc hands the keys to the image, from which a second
  Esc closes. Cmd+C in any empty field, one with no words (`Model.fieldEmpty`, the same empty
  as above), copies the drawing (`FieldCommand.copyDrawing`), whatever
  marks the image has selected: one that took the keys on its own, one pressed into later, or one
  after a pick. While a word is being composed in it, the field is not empty.
  `docs/send-and-reply-2026-09-24.md` has the rules. While one image follows another with no gap (a click on
  another card, or the queue moving on) the bar stays on screen and springs to the next image's
  place, and keeps the image before's target until the next image's settles (`Model.begin`'s
  `carryingTarget`), since emptying it took Send off the bar for the listing's 60 to 90 ms and the
  bar jumped narrower and back: `place(below:gap:)` slides the panel when it is already up, one `Tween` per direction, over
  `FlightTiming.covers` for a flight as long as the next image's frame is wide, which is when the
  next image's window comes up. The
  springs move the panel's centre and top edge, so a change of size never moves the bar. When the
  offer changes, the bar springs to its new width inside the panel, which never narrows while the
  bar is up and is clear around it. The controls two offers share (Copy, the message field, the
  filled button) keep one identity so they move rather than cross-fade, and the bar's sides clip
  what comes and goes.
  `hideWindows` asks for the exit through `hideSoon`, which waits one turn of the run loop and is
  cancelled by the next `place`; a swap's park answer and the next `prepare` land in that same turn,
  so the reducer says nothing about this. The panel always keeps
  the room above and below the bar that the message field grows into, clear, since a panel that
  grew when the field took focus moved the bar for a frame. The field grows down, and up out of the
  bar once it nears the bottom of the visible screen (`Model.roomBelow`, `GrowingField`). No SwiftUI
  gesture may sit on the field's text: one took the release of a quick click, and the text field then
  waited for it with every event queued behind, Esc included, until the next click. The padding's
  gesture is behind the box.
  `[state] annotator.toolbar` is the panel's frame without that room, or null when it is off screen.
  Tab goes from the last mark to the bar's controls and back (`AnnotatorToolbar.enter`, `move`,
  `EditorView.enterCanvas`). While a control has the focus the editor keeps the keys and hands Tab
  and Space to the bar (`EditorView.takesKey`), except in the message field, where the bar's panel
  has them and takes Tab first (`ToolbarPanel.sendEvent`). `[state] annotator.toolbarFocus` names
  the focused control, and `annotator.toolbarKey` says whether the bar's panel has the keys. The
  bar draws its own tooltips (`TipSpot`, `TipLabel`): AppKit shows a window's tooltips only while
  it is key or was the last one clicked; `allowsToolTipsWhenApplicationIsInactive` did not help.
  `docs/annotator-toolbar-2026-09-19.md` has the numbers.
