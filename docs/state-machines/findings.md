# Findings

The area maps raised 84 invalid states and transitions, and the reviewer found one more. A **confirmed** finding has a traced sequence and a unit test that failed before its fix, and belongs to one of the [issues](issues.md#issues). Fourteen are confirmed. A **plausible** finding is traced, but no unit test reaches it yet or one step of it was not checked, and it is not fixed. Each plausible entry ends with how sure its mapper was and what was left unchecked, and with the review's verdict where it gave one.

Line references are to commit 358d988 unless a finding says otherwise. Those in the confirmed findings were checked; the rest are the mappers', partly corrected, and drift as the code changes. Search for the symbol a reference names.

### Confirmed findings

<a id="editor-1"></a>
#### editor-1: Opening an image resets what Return and Cmd+Return do

- **Sequence**: the person pages with Left or Right between two agent replies from the same session,
  or opens another image while the bar offers Send, so the bar's offer does not change. They press
  Return on the Reply card (or Cmd+Return to send).
- **Trace**: `EditorCore.open` replaces the whole core with `self = EditorCore()`
  (`EditorCore.swift:577`), keeping only `zoom` and the pending effects, so `finishes` goes back to
  `Finishes()`, Done for both keys. The comment on `finishes` (`:367`) says opening leaves it alone.
  The host sets it only from `offerChanged` (`AnnotationController.swift:640`), and the bar reports
  its offer only when it changes (`AnnotatorToolbar.swift:130`); a bar that carries its target
  (`Model.begin`'s `carryingTarget`) does not change it. Two replies from one session both offer
  `.reply(S)`, so paging between them never re-reports it. A fresh session list that differs in any
  field re-reports the offer, which hides the bug on the Send path more often than on Reply.
- **Breaks**: Cmd+Return copies and closes instead of sending; Return on a Reply card copies instead of
  replying.
- **Test**: `EditorCoreOpeningTests.testTheNextImageFinishesWithWhatTheBarStillOffers`.
- **Fix**: `open` keeps `finishes`, as it keeps `zoom`.
- **Status**: fixed, [issue 1](issues.md#issue-1), in `72f89df`.

<a id="toolbar-3"></a>
#### toolbar-3: A second send to a session that is still starting starts it again

- **Sequence**: the person sends to a "Continue last session" row, which starts `claude --resume` in
  a new herdr tab and waits up to 45 s for its inbox. Before the inbox comes up, they send another
  image to the same row, which stays listed until a live inbox holds the session. Two screenshots
  sent one after the other to a session that takes a few seconds to start is enough.
- **Trace**: each send runs `startSession` on its own pool thread (`AgentConnection.swift:425-437`).
  The only guard is `liveInbox(holding: session)` (`:274`), which is false until the first start's
  inbox is live, so the second send launches again (`:277`). Nothing records a start under way.
- **Breaks**: two Claude Code processes resume one session, which forks its transcript, and a stray
  tab is left. When the first inbox exists but is not live yet, the second start never finds it
  (`look` takes only folders made since its own launch, `:289`) and fails after 45 s. That second
  case is traced, not tested; the test shows the double launch.
- **Test**: `ClaudeSessionStartTests.testASecondSendWhileItsSessionIsStillStartingJoinsThatStart`, which sends
  twice while the first start looks for its inbox and expects one launch.
- **Fix**: one start per session id at a time. A send for a session already starting waits for that
  start's answer and writes its line into the same inbox. It adds a state, a start under way, which
  Pete approved ([issue 3](issues.md#issue-3)).
- **Status**: fixed, [issue 3](issues.md#issue-3), in `f1ea7c3`.

<a id="requests-1"></a>
#### requests-1: A screenshot deleted during its send's grace period is still sent

- **Sequence**: the person sends a screenshot; its line waits `ui.sendGraceSeconds`. Within about one
  listing of an app write to the folder (an agent's push, a reply, a live ink card), they delete the
  screenshot in Finder.
- **Trace**: the watcher's report comes from a listing older than the write, so
  `FolderWrites.removed` holds the removal back (`FolderWrites.swift:259-262`). The next listing
  settles it with `callbacks.removeCards` only (`:315-316`). `fileRemoved`, which cancels a waiting
  send (`ScreenshotRequests.fileRemoved`), is called only from `left` (`:328`).
- **Breaks**: the card goes, but the line still reaches the session when the grace ends, with the
  image the person deleted. Vignette's own Trash goes through `left` directly and still cancels;
  only a deletion from outside, during the grace and the same listing interval as an app write,
  reaches this path.
- **Test**: `FolderWritesTests.testARemovalFromAnOlderListingWaitsForANewerOne`, which pinned the
  card-only removal and now expects the whole removal.
- **Fix**: a held-back removal, once confirmed, leaves through `left` like any other. Its drawing
  and replies are already gone by then, and removing them again does nothing (`Drawings.remove`
  filters on the keys it holds, and `fileRemoved` skips a reply already deleted), so `left` is safe
  to reuse. The test's own comment, which named that second removal as a fault, changes with it.
- **Status**: fixed, [issue 6](issues.md#issue-6), in `b9b76b8`.

<a id="asks-1"></a>
#### asks-1: Signing out of Codex while it answers leaves the ask waiting forever

- **Sequence**: live ink asks Codex. While the answer is under way, the person signs out of Codex in
  Settings.
- **Trace**: `ResponderStatus.signOut` calls `onCodexSigningOut` (`ResponderStatus.swift:133`), which
  is `all[.codex]?.stop()` (`LiveResponders.swift:26`). `LiveResponder.stop()` shuts down with no
  failure (`LiveResponder.swift:162-166`), and `shutDown` returns before answering the dropped asks
  (`:369-380`). The ask timer was invalidated, so no timeout comes either.
- **Breaks**: `LiveAsks` keeps the ask `asking`: its thinking light stays on, and every later ask,
  to Claude too, waits behind it until the person presses Esc on each stuck ask.
- **Test**: `LiveResponderTests.testAnAskUnderWayWhenTheSignInGoesFailsOnce`. Before the fix it failed
  through `stop()`, which the sign-out called.
- **Fix**: the sign-out fails the asks it drops: `stop(failingAsks: true)`. Every other caller of
  `stop()` keeps the silent drop. Clearing has already ended its asks in `LiveAsks`
  (`LiveInk.swift:1728-1729`, and `docs/live-ink.md` states the silent drop for it); the idle stop
  and the conversation limit run with nothing held; the restart after an unanswered interrupt asks
  the pending ask again.
- **Status**: fixed, [issue 4](issues.md#issue-4), in `95c1a56`.

<a id="run-2"></a>
#### run-2: The shortcut pressed while a zoomed swap parks does not close the editor

- **Sequence**: two or more lone thumbnails in the corner, not a stack. One is open in the editor and
  zoomed in. The person clicks another lone thumbnail, or presses Left or Right, which parks the
  first image while the frame springs back to its fit (0.2 s at motion 1). During that spring they
  press the shortcut, or pick Show Recent Screenshots. With a stack the shortcut dismisses instead,
  which the park already handles. Very rare.
- **Trace**: `CornerPresentation` answers the shortcut with `.closeEditor`
  (`CornerPresentation.swift:109`), which sends `.cancel(.shortcut)` (`ThumbnailController.swift:284`).
  The run empties its queue and forwards `.close`, which `AnnotatorTransition` ignores in
  `parking(o, then: .annotate(o2))` (`AnnotatorTransition.swift:220`). Esc and a click outside cannot
  reach this phase: `AnnotationController.cancel` returns once `hide` has cleared `current`.
- **Breaks**: the next image opens anyway, under the stack the shortcut brought up, and the run
  keeps `.shortcut` as its ending for whatever ends it later.
- **Test**: `AnnotationRunTests.testACancelDuringASwapsParkClosesInsteadOfOpeningTheNextImage`.
- **Fix**: `.close` in `parking(o, then: .annotate)` becomes `parking(o, then: .close)`: a later
  request wins, as it already does the other way round.
- **Status**: fixed, [issue 8](issues.md#issue-8), in `b225449`.

<a id="run-3"></a>
#### run-3: The open file deleted while a zoomed swap parks comes back as a card

- **Sequence**: the stack is open with other cards. An image is open and zoomed; the person clicks
  another card, which parks the first while its frame springs back. During that spring the first
  image's file is deleted (Finder, an agent's `trash`). Very rare: the window is about 0.2 s.
- **Trace**: the run empties its queue (`AnnotationRun.swift:136`), but `AnnotatorTransition`
  ignores `.remove(o.key)` in `parking(o, then: .annotate)` (`:211-216`). `ThumbnailController.remove`
  takes the card out of the stack; `parked` then answers `returnCard(o)`, and `returnCard` inserts the
  card back (`ThumbnailController.swift:883-895`) for a file that no longer exists.
- **Breaks**: a card for a deleted file sits in the stack, and every action on it fails.
- **Tests**: `AnnotatorTransitionTests.testRemovingTheFileParkingForASwapHidesItAndOpensNothing`,
  `AnnotationRunTests.testRemovingTheOpenFileDuringASwapsParkEndsTheRun`.
- **Fix**: that row becomes `parking(o, then: .remove)`, as for `close` and `finish`: the annotator
  hides and nothing takes its place, which is the run's own rule (`AnnotationRun.swift:135`).
- **Status**: fixed, [issue 8](issues.md#issue-8), in `b225449`.

<a id="run-1"></a>
#### run-1: A card selected while Esc's park runs opens in the editor

- **Sequence**: a stack card is open and zoomed. The person presses Esc; while the frame springs back
  they select a card in the stack.
- **Trace**: `.cancel` empties the queue (`AnnotationRun.swift:121`), but `select` checks only that
  the transition is active (`:255`), so the selected card is queued, and `parked` opens it
  (`continueOrEnd`, `:232`).
- **Breaks**: the editor opens again on the card the person only selected, after they pressed Esc.
- **Test**: `AnnotationRunTests.testACardSelectedWhileEscParksQueuesNothing`;
  `testACardSelectedWhileSendParksIsQueuedNext` keeps Send's queue going.
- **Fix**: a run whose queue was ended (Esc, a dismissal, the open file going) takes no more
  selected files. A click on a card during the same park still opens that card, as a click does
  when nothing is open; only a selection, which opens nothing on its own, is refused.
- **Status**: fixed, [issue 7](issues.md#issue-7), in `aaba2a2`.

<a id="run-4"></a>
#### run-4: A list's run reports how an earlier image ended

- **Sequence**: a list of two opens. Done on the first; the second opens. The second then ends with
  no hand: its file is deleted, or the panel goes away.
- **Trace**: `finish` sets `ending = .finished` (`AnnotationRun.swift:127`). The handover in
  `continueOrEnd` (`:240-243`) leaves it, and only the run's end clears it (`:236`). A second path
  carries it too: after Esc, a click on another card during the zoomed park swaps to it
  (`AnnotatorTransition.swift:203`), so the transition never goes idle and `.back` stays set.
- **Breaks**: `endRun(.finished)` reaches `CornerPresentation`, which returns the focus to the app
  before Vignette when no hand asked it to; a stale `.shortcut` keeps it from returning.
- **Test**: `AnnotationRunTests.testAHandoverForgetsHowTheImageBeforeEnded`.
- **Fix**: `ending` is cleared when another image really opens: in `reduce`, after the files that
  cannot open are passed over, and only when a `prepare` is left. Clearing it in the handover
  itself would be wrong: when Done is pressed and no queued file opens, the run must still report
  `.finished` (`AnnotationRunTests.testAQueuedFileThatDoesNotOpenIsPassedOver`).
- **Status**: fixed, [issue 7](issues.md#issue-7), in `aaba2a2`.

<a id="corner-1"></a>
#### corner-1: A notice on a file renamed during its hold never goes

- **Sequence**: a card shows Copied (or Not copied, or a failed send). Within the notice's hold the
  file is renamed inside the folder.
- **Trace**: `ThumbnailController.post` schedules `notices.expire(posted.id, on: file)` with the key
  from before the rename (`ThumbnailController.swift:666`). `CardNotices.rename` moves the notice to
  the new key (`CardNotices.swift:157`), so `expire` finds nothing under the old one (`:150`).
- **Breaks**: the renamed card keeps the notice until another replaces it, and a send's countdown it
  covered never comes back. While the notice stays, a lone thumbnail of that file that comes home
  from the editor skips both ways out of the corner (`ThumbnailController.swift:918`, `:925-926`),
  so it stays until something else arms the timer.
- **Test**: `CardNoticesTests.testANoticeOnAFileRenamedDuringItsHoldStillExpires`.
- **Fix**: `expire` takes only the notice's id, which no rename changes.
- **Status**: fixed, [issue 5](issues.md#issue-5), in `4e16467`.

<a id="corner-3"></a>
#### corner-3: The focus stays on a card the column dropped

- **Sequence**: the stack is open and has the keys, with the column full (`recentCount` cards). The
  person moves the focus to the oldest card. A capture or an agent's push arrives.
- **Trace**: the new card slides in (`shiftUp`), and the overflow drops the oldest card
  (`ThumbnailController.removeOverflow`, `ThumbnailController.swift:1465-1470`, called at `:1446`).
  It removes the card and deselects it, but leaves `model.focused` on its id. `remove(_:)` repairs
  the focus when a card's file goes (`:487`); this path does not. The stack's next `takeKeys`
  refocuses only when `focused` is nil (`:279`), so a stale id is never replaced.
- **Breaks**: no card wears the focus ring and Space does nothing, while Return, Copy and Trash act
  on the newest card (`targetCards`, `:1081-1082`). The focus stays lost until an arrow key or the
  pointer sets it.
- **Test**: `StackModelTests.testWhenTheFocusedCardLeavesTheNewestTakesTheFocus`.
- **Fix**: `StackModel.removeCards` owns the rule `remove(_:)` states: when the focused card leaves,
  the newest card takes the focus. The stitch, which wants no focus once its pieces leave, clears it
  before it removes them.
- **Status**: fixed, [issue 2](issues.md#issue-2), in `fc3077b`.

<a id="corner-9"></a>
#### corner-9: A drag over the oldest card when a capture fills the column crashes the app

- **Sequence**: the stack is open with a full column. The person drags from a selection circle, and
  a capture or an agent's push arrives while the pointer is over the oldest card.
- **Trace**: `insert` ends the sweep (`ThumbnailController.swift:1367`) and `shiftUp` puts the new card
  at index 0, so the column holds one card too many until the next turn, when `springLifts` runs
  `removeOverflow` (`:1446`). A drag move in between anchors the new sweep on the oldest card, at an
  index that `removeOverflow` then takes away. The sweep kept its anchor as an index
  (`StackSweep.swift:17`), so the next move reads `model.cards[anchor]` past the end (`:73`).
- **Breaks**: "Index out of range", which ends the app.
- **Test**: `StackModelTests.testASweepWhoseFirstCardLeavesStartsAgainFromTheCardUnderThePointer`,
  which crashed the test process at `StackSweep.swift:73` before the fix.
- **Fix**: the sweep anchors on the card's id. When that card has left, the sweep ends and the drag
  starts a new one from the card under the pointer, as it does after an insert.
- **Status**: fixed, [issue 9](issues.md#issue-9), in `8451a9c`.

<a id="corner-4"></a>
#### corner-4: A capture into a full column drops the card open in the editor

- **Sequence**: the stack is open with a full column, and the oldest card is open in the editor, its
  slot drawn empty. A capture with `annotateOnCapture` off, or an agent's push, arrives. Pushes while
  the person draws are the agent loop's normal case.
- **Trace**: `removeOverflow` dropped `model.cards.last` without checking `outCards` or `forming`
  (`ThumbnailController.swift:1465-1470`), and `removeCards` cleared its marks (`StackModel.swift:87`).
  When the editor closes, `returnCard` finds the card missing and inserts it again at index 0
  (`ThumbnailController.swift:886-892`), and that insert drops the next oldest card.
- **Breaks**: the card comes home to the newest slot, and an unrelated card leaves the column.
- **Test**: `StackModelTests.testTheOverflowKeepsTheCardsInTheEditorAndInAStitch`. The overflow moved
  into `StackModel` unchanged so a test could reach it, and the test failed against it.
- **Fix**: the overflow drops the oldest card that is not in the annotator or in a stitch.
- **Status**: fixed, [issue 10](issues.md#issue-10), in `72f89df`0.

<a id="requests-2"></a>
#### requests-2: A cleared request whose answer live ink drew is never pruned

- **Sequence**: live ink asks a session, and its answer becomes live ink's own result card, so the
  reply is `shown`. Later the request is cleared, by `requests?clear=` or by the 50-request limit,
  which clears the oldest on its own.
- **Trace**: `cleanup` treated every reply but a published one as unpublished
  (`ScreenshotRequests.swift:823`). It turned the shown reply `cancelled` and set
  `needsOutputCleanup`, since its stage is not `accepted` (`:828-830`). A shown reply has no
  `destination`, which only `publishCard` sets (`:649`), so its `outputURL` is nil and the flag
  never clears. `prune` skips any request with that flag (`:785`).
- **Breaks**: every such request's folder stays forever, with its records, and `load` reads all of
  them. The drawn answer's receipt also changed from ready to cancelled.
- **Test**: `ScreenshotRequestsClearingTests.testAClearedRequestWhoseAnswerLiveInkDrewStaysDrawnAndIsPrunedAfterAWeek`,
  in a new file because `ScreenshotRequestsTests.swift` is over the size limit.
- **Fix**: clearing leaves a shown reply as it leaves a published one (`Reply.isPresented`).
- **Status**: fixed, [issue 11](issues.md#issue-11), in `72f89df`1.

<a id="setup-1"></a>
#### setup-1: A plugin switched off comes back at the next launch when the old skill is a link

- **Sequence**: the person kept the skill from before the plugin as a link, as Pete does
  (`docs/claude-code-without-herdr-2026-09-27.md:415-416`). They turn the plugin off with the Agents
  tab's switch, then Vignette launches again.
- **Trace**: the switch runs `plugin remove`, so `isInstalled` reads false at launch. The launch
  installed wherever an old skill was, folder or link. A link is never
  removed (`removeLegacySkill`, `testOldSkillFolderGoesAndALinkStays`), so every launch installs
  again.
- **Breaks**: the switch's off does not hold. `docs/rules/agent-plugin.md` says the switch is
  the only thing that removes the plugin, and the person's choice is undone at each launch.
- **Test**: `AgentPluginTests.testALaunchLeavesThePluginOffAfterTheSwitchTurnedItOffWhereTheOldSkillIsALink`,
  which launches twice and expects the second launch to install nothing, and
  `testALaunchThatFindsThePluginBesideALinkedSkillLeavesItOffOnceTheSwitchTurnsItOff`, for a plugin
  already in beside a link when the fix arrives. Both failed before the fix.
- **Fix**: the plugin being in beside the old skill, from a launch or a switch, records the agent
  folder in `agent-plugin-migrated.json` in Application Support (`LegacySkillMigrations`), and a
  launch installs for the old skill only in a folder not recorded.
- **Status**: fixed, [issue 12](issues.md#issue-12), in `d0fb7c7`.