# The annotator's toolbar

- The annotator's window is borderless and spans the screen's visible frame. The frame inside it is
  sized to the image. Its toolbar is a native panel (`AnnotatorToolbar.swift`) placed under the
  frame, one level above the flight layer, so a flight into or out of the editor passes under it as
  the editor does. It is not the annotator window's child, since AppKit keeps a child window at its
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
  (`AnnotationController.offerTyping`), so typing goes to the agent at once. The field counts as
  typed in only while the panel is key
  (`Model.keyed`), because AppKit makes it the panel's first responder when the bar comes up. There is no
  palette: a mark's colour says who drew it. Send starts on the kept pick when there is one: the
  session the person picked in the target's menu and then sent to (`DestinationChoice.KeptPick`,
  `AnnotationController.keptPick`). It holds for 10 minutes after the send that set it, and each
  Send to it starts the 10 minutes again. Pete's runs of sends to one session had gaps under 6
  minutes, and a short window drops a pick once he moves to other work. It comes before every rule
  below, the Codex app's thread included, so one rule says where Send starts. It ends when the 10
  minutes pass, when a Send goes to another hand pick, which is kept instead, or when every client
  has answered afresh without it, its agent's list holding other sessions: an agent that listed
  none may have failed to answer, so the image starts on the usual choice and the pick stays. A session that `/clear` gave a new id is gone: no guess at the
  same one replaces it, since no send in two weeks of Pete's log was refused as cleared. A pick that
  is never sent keeps nothing, so a first send is never surprised. A Reply neither sets, refreshes
  nor ends it, and a card that offers Reply still offers Reply. It is kept in memory only. Codex
  lists only the threads used last, so a kept Codex thread is asked for by its id
  (`SessionListing.list(including:)`). When the Codex app shows another thread, the same listing
  reads that one by its id too, so the menu lists both. Otherwise Send starts on
  the session you came from (`DestinationChoice`). When the app before Vignette
  (`FocusReturn.previousApp`) was the Codex app, that is the thread it shows, or else the Codex
  thread used last; herdr's focus is ignored then, because herdr keeps a focused pane while its
  terminal is behind. The thread it shows comes from the app's own log (`AgentApp.shownThread`):
  each time its window moves to another page, the app logs the page's route, and `/local/<id>` is a
  thread. That is a log line, not an interface, so a build that drops it gives the thread used last.
  Accessibility cannot say: the app's window has had no page in its accessibility tree since the
  app left Electron in late September 2026 (openai/codex#25740). A thread older than the list is
  read by its id (`thread/read`). A Codex thread is named the way the app names it
  (`CodexConnection.name(of:)`).
  Otherwise, when herdr runs, it is the session in herdr's focused pane, or the one session in that
  pane's tab when the pane runs none. `DestinationChoice` applies herdr's focus to Claude Code
  sessions only (`DestinationChoice.markedByHerdr`). Else it is the session used last.
  The target shows the agent's logo and the session's title, cut in the middle past 132 pt, with
  the title, the second line and the repository in its tooltip (`SessionMenu.row(of:among:)`). Its width is set rather than left to the text, so it springs with the bar. A
  pick from its menu is applied a turn later, after the menu's own event loop ends, since a change
  made inside it jumped instead of animating. Its menu is `SessionMenu.menu` (`docs/session-menu-2026-10-18.md`): the
  sessions the person sent to in the last 4 hours, newest send first, then the rest by when the agent last worked; five of them, with
  the target always among them, grouped under a header for each repository with Other folders last, then, after a separator, one submenu per project, titled as its header, with its count as a badge and every
  active session of that project in it, the top rows too (live ink's Tab steps through the five only). The menu's first row is a search field that has the keyboard: typing lists the matching sessions from every project, Return picks the first, and Esc closes the menu (`SessionMenuSearch`). A row's title is the herdr tab's label, else
  the session's name; its second line is the worktree, the branch and the inbox mod's goal; a badge says Needs you or Working
  (`InboxModStore` reads the mod's private file and may find nothing). A Claude Code session is active while the plugin's monitor runs in it,
  and a Codex thread when it was used in the last day, since nothing says which threads the Codex
  app has open. The target settles once, from the first answer that names a focus (herdr's comes in
  about 60 ms, before the bar is up), or else from the whole list (`Model.answered`). With a kept
  pick, nothing settles until an answer lists the kept session, or every client has answered afresh
  without it. A kept Claude Code session settles with Claude Code's first answer, as herdr's focus
  does. A kept Codex thread settles at once from the kept list when the list has it, else from the
  fresh one. A target carried from the image before stays until then, so the bar never shows a
  third session between the two. After that it
  changes only when its session is gone, so it never changes under the pointer. Codex's list is kept (`AgentConnection.keepsList`, `SessionListing`): an opening editor answers
  from the last one at once and asks for a fresh one, which comes in about 0.1 s for the five
  threads used last (`AppServer.listLimit`), and it is asked for again at launch, on a capture and
  when the stack opens. Claude Code's list is always asked afresh, and herdr's focus, which
  moves whenever you change panes, is read in the same job right after it (`HerdrFocus`), so the
  focus comes with Claude Code's first answer. Coming from the Codex
  app, a kept list that holds the shown thread settles the target at once; one that does not waits
  for the fresh list, since the thread may be newer. Return copies and replies only on a card that names its session; Cmd+Return
  sends or replies (`EditorCore.finishes`). On the image, Return never sends to a session Vignette
  picked. In the message field Return sends, as in a chat app, with the target beside it. A field
  that took the keys on its own and is still empty has nothing that asks to send, so Return and Esc
  there do what they do on the image (`Model.fieldReturn`, `fieldEscCloses`).
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
  it is key or was the last one clicked, so `.help` on the bar showed nothing until the bar was
  clicked, and `allowsToolTipsWhenApplicationIsInactive` did not change
  that. The target's menu is an `NSMenu` (`showTargetMenu`), since SwiftUI's `Menu`
  cannot be opened from a key. Space opens it a turn later: opened inside the editor's keyDown it
  took no keys, and a press on its item closed the editor as a press outside. In the message field,
  Up on the first line or Down on the last opens it the same way, as on a pop-up button, and the
  arrows then move through it (`ToolbarPanel.onMenuKey`). `docs/annotator-toolbar-2026-09-19.md` has the numbers.
