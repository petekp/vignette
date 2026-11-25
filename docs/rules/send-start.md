# Where Send starts

This file says which session the toolbar's target starts on. The bar is in `annotator-toolbar.md`.

- Send starts on the kept pick when there is one: the
  session the person picked in the target's menu and then sent to (`DestinationChoice.KeptPick`,
  `AnnotationController.keptPick`). It holds for 10 minutes after the send that set it, and each
  Send to it starts the 10 minutes again. Pete's runs of sends to one session had gaps under 6
  minutes, and a short window drops a pick once he moves to other work. An image that opened on it
  renews it when sent there, however long the editor stayed open (`KeptPick.after`). It comes before every rule
  below, the Codex app's thread included, so one rule says where Send starts. It ends at the next
  opening, send elsewhere or Reply after its 10 minutes, when a Send goes to another hand pick, which is kept instead, or when every client
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
  terminal is behind. A capture that shows another app's windows more than the Codex app's, such
  as Herdr's inbox panel taken while the Codex app stayed in front, sets that rule aside
  (`DestinationChoice.appRuleApplies`, `CaptureRect.owners`; `docs/send-start-2026-11-21.md`). The thread it shows comes from the app's own log (`AgentApp.shownThread`):
  each time its window moves to another page, the app logs the page's route, and `/local/<id>` is a
  thread. That is a log line, not an interface, so a build that drops it gives the thread used last.
  Accessibility cannot say: the app's window has had no page in its accessibility tree since the
  app left Electron in late September 2026 (openai/codex#25740). A thread older than the list is
  read by its id (`thread/read`). A Codex thread is named the way the app names it
  (`CodexConnection.name(of:)`).
  Otherwise, when the Herdr app runs, it is the session in Herdr's focused pane, or the one agent
  session in that pane's tab when the pane runs none. `DestinationChoice` applies Herdr's focus to
  Claude Code sessions only (`DestinationChoice.markedByHerdr`). Else it is the session used last.
  `HerdrFocus` reads the focus with three calls at once, each 5 to 20 ms (measured 2026-11-12):
  `herdr-app status` names the focused pane and its tab, `herdr-app ls` places each terminal in a
  tab and a pane, and `hc connect`'s `terminal.list` gives each terminal's foreground process and
  labels. The status's `agent` field is never read: it named a stale terminal. The focused
  terminal is the one in the focused pane. When the focus is on the inbox mod's panel, it is the
  terminal whose `inbox.panel` label names that panel. A terminal's session is the listed Claude
  Code session whose plugin inbox belongs to its foreground process, which follows `/clear`. When
  none does, the inbox mod's `inbox.session` label names it, unless another terminal runs that
  session. Herdr names a terminal's agent only once its program reports a status, and a Claude Code
  that `hc` started may never report, so a terminal Herdr shows running nothing still counts when
  its process is a listed Claude Code session. A closed Herdr window, a timeout, an
  answer that does not parse, or a status whose tab is not the focused terminal's marks nothing,
  and logs `[herdr] no focus: <reason>` when the reason changes, then `[herdr] focus read again`.
  The target settles once, from the first answer that names a focus (herdr's comes in
  about 60 ms, before the bar is up), or else from the whole list (`Model.answered`). With a kept
  pick, nothing settles until an answer lists the kept session, or every client has answered afresh
  without it. A kept Claude Code session settles with Claude Code's first answer, as herdr's focus
  does. A kept Codex thread settles at once from the kept list when the list has it, else from the
  fresh one. A target carried from the image before stays until then, so the bar never shows a
  third session between the two. After that it
  changes only when its session is gone, so it never changes under the pointer. Codex's list is kept (`AgentConnection.keepsList`, `SessionListing`): an opening editor answers
  from the last one at once and asks for a fresh one, which comes in about 0.1 s for the five
  threads used last (`AppServer.listLimit`), and it is asked for again at launch, on a capture and
  when the stack opens. Claude Code's list is always asked afresh, and Herdr's focus, which
  moves whenever you change panes, is read in the same job right after it (`HerdrFocus`), so the
  focus comes with Claude Code's first answer. Coming from the Codex
  app, a kept list that holds the shown thread settles the target at once; one that does not waits
  for the fresh list, since the thread may be newer.
