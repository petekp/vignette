# Issues

The confirmed findings, grouped by the change that fixes them. An issue keeps its number, which
commit messages cite; the table is in rank order. Rank is impact: how much a person loses, weighed
by how often the sequence comes up. The review moved several of them, and
[What the review changed](#what-the-review-changed) says how. Each issue is fixed in its own commit
with its regression tests.

| Rank | Issue | Findings | What a person hits | Status |
|---|---|---|---|---|
| 1 | [1. The next image forgets what Return and Cmd+Return do](#issue-1) | [editor-1](findings.md#editor-1) | Return copies instead of replying when paging between two replies from one session, every time | Fixed in `72f89df` |
| 2 | [10. A capture into a full column drops the card open in the editor](#issue-10) | [corner-4](findings.md#corner-4) | the card comes home to the newest slot, and another card leaves the column | Fixed in `72f89df`0 |
| 3 | [2. The focus stays on a card the column dropped](#issue-2) | [corner-3](findings.md#corner-3) | with a full column, a capture takes the focus ring away, and Return, Copy and Trash act on the newest card | Fixed in `fc3077b` |
| 4 | [3. A session that is still starting is started again](#issue-3) | [toolbar-3](findings.md#toolbar-3) | two sends to a session that is starting run two Claude Code processes on it, which forks its transcript | Fixed in `f1ea7c3` |
| 5 | [11. A cleared request whose answer live ink drew is never pruned](#issue-11) | [requests-2](findings.md#requests-2) | a request folder left behind for every such answer, forever | Fixed in `72f89df`1 |
| 6 | [12. A plugin switched off comes back at the next launch when the old skill is a link](#issue-12) | [setup-1](findings.md#setup-1) | the Agents tab's off does not hold, at every launch | Fixed in `d0fb7c7` |
| 7 | [9. A drag over the oldest card when a capture fills the column crashes the app](#issue-9) | [corner-9](findings.md#corner-9) | the app quits; rare | Fixed in `8451a9c` |
| 8 | [4. A Codex sign-out leaves its ask waiting forever](#issue-4) | [asks-1](findings.md#asks-1) | live ink answers nothing more, from Claude too, until Esc is pressed on the stuck ask | Fixed in `95c1a56` |
| 9 | [5. A notice on a renamed file never goes](#issue-5) | [corner-1](findings.md#corner-1) | a stale Copied or failure notice, a send's countdown that never comes back, and a lone thumbnail that stays | Fixed in `4e16467` |
| 10 | [7. The run keeps what a hand did after the hand is done](#issue-7) | [run-1](findings.md#run-1), [run-4](findings.md#run-4) | a card selected after Esc opens in the editor; the focus goes back, or stays, when no hand asked | Fixed in `aaba2a2` |
| 11 | [8. A cancel or a deletion while a swap parks is ignored](#issue-8) | [run-2](findings.md#run-2), [run-3](findings.md#run-3) | the shortcut does not close the editor; a card for a deleted file stays in the stack; very rare | Fixed in `b225449` |
| 12 | [6. A deleted screenshot is still sent](#issue-6) | [requests-1](findings.md#requests-1) | the image the person deleted reaches the agent session; very rare | Fixed in `b9b76b8` |

<a id="issue-1"></a>
### Issue 1: The next image forgets what Return and Cmd+Return do

`EditorCore.open` keeps `finishes` as it keeps `zoom`, so the bar's offer, which the host sets only
when it changes, still holds for the next image. Test:
`EditorCoreOpeningTests.testTheNextImageFinishesWithWhatTheBarStillOffers`. **Status**: fixed in `72f89df`.

<a id="issue-2"></a>
### Issue 2: The focus stays on a card the column dropped

`StackModel.removeCards`, which every removal goes through, now owns the rule that `remove(_:)`
stated alone: when the focused card leaves, the newest card takes the focus. `remove(_:)` no longer
repairs it itself, and the stitch clears the focus before its pieces leave, so a stitch still ends
with no focus. Test: `StackModelTests.testWhenTheFocusedCardLeavesTheNewestTakesTheFocus`. **Status**: fixed in `fc3077b`.

<a id="issue-3"></a>
### Issue 3: A session that is still starting is started again

A start had three states, all local to one send: launching, looking for the inbox, and up or
failed. No send could see another's start. The fix adds one state that every send shares: **a start
under way for session S**, held in `SessionStartsUnderWay` (`ClaudeSessionStart.swift`).

- `ClaudeCodeConnection` holds one table, from session id to the sends waiting on that start. It is
  a class behind a lock, since each send runs `startSession` on its own pool thread, and the
  connection's copies share it. The app has one connection, in `AppDelegate.connections`.
- A send that finds S in the table joins it and launches nothing. The first send checks for a live
  inbox, launches, and looks as before. Checking after joining means a start that answered just
  before is found up rather than started again.
- When the start answers, every send waiting on S gets the same answer: `up(inbox)`, and each writes
  its own line into that inbox, or `failed`, and each card reports it. S then leaves the table, so a
  later send after a failure starts again.

The start code moved to `ClaudeSessionStart.swift`, which keeps `AgentConnection.swift` under its
size. Test: `ClaudeSessionStartTests.testASecondSendWhileItsSessionIsStillStartingJoinsThatStart`. Pete
approved the new state on 2026-11-07. **Status**: fixed in `f1ea7c3`.

<a id="issue-4"></a>
### Issue 4: A Codex sign-out leaves its ask waiting forever

The sign-out stops Codex's responder with `stop(failingAsks: true)`, which fails the ask under way
or pending with Codex's "couldn't answer" reason, so `LiveAsks` ends it and the next ask goes. Every
other `stop()` keeps dropping silently, which is right for each of them (see [asks-1](findings.md#asks-1)).
Test: `LiveResponderTests.testAnAskUnderWayWhenTheSignInGoesFailsOnce`. **Status**: fixed in `95c1a56`.

<a id="issue-5"></a>
### Issue 5: A notice on a renamed file never goes

`CardNotices.expire` takes only the notice's id, which no rename changes, and finds the file that
holds it. Test: `CardNoticesTests.testANoticeOnAFileRenamedDuringItsHoldStillExpires`. **Status**: fixed in `4e16467`.

<a id="issue-6"></a>
### Issue 6: A deleted screenshot is still sent

A held-back removal, once a listing confirms it, leaves through `FolderWrites.left` like every
other removal, so `fileRemoved` cancels a send still in its grace. Test:
`FolderWritesTests.testARemovalFromAnOlderListingWaitsForANewerOne`, which pinned the card-only
removal. **Status**: fixed in `b9b76b8`.

<a id="issue-7"></a>
### Issue 7: The run keeps what a hand did after the hand is done

`AnnotationRun.select` queues nothing once the run's list has been ended (Esc, a dismissal, the
open file going), and `reduce` clears `ending` when another image really opens. Tests:
`AnnotationRunTests.testACardSelectedWhileEscParksQueuesNothing`,
`testACardSelectedWhileSendParksIsQueuedNext`, `testAHandoverForgetsHowTheImageBeforeEnded`. **Status**: fixed in `aaba2a2`.

<a id="issue-8"></a>
### Issue 8: A cancel or a deletion while a swap parks is ignored

Two rows of `AnnotatorTransition` change. In `parking(o, then: .annotate(o2))`, `close` becomes
`parking(o, then: .close)`, and `remove(o.key)` becomes `parking(o, then: .remove)`. A later request
wins over a swap, as a swap already wins over an earlier close. Tests:
`AnnotatorTransitionTests.testRemovingTheFileParkingForASwapHidesItAndOpensNothing`,
`AnnotationRunTests.testACancelDuringASwapsParkClosesInsteadOfOpeningTheNextImage`,
`testRemovingTheOpenFileDuringASwapsParkEndsTheRun`. **Status**: fixed in `b225449`.

<a id="issue-9"></a>
### Issue 9: A drag over the oldest card when a capture fills the column crashes the app

`StackSweep` keeps the card the drag started on by its id, not its index. When that card has left
the column, the sweep ends and the drag starts a new one from the card under the pointer. Test:
`StackModelTests.testASweepWhoseFirstCardLeavesStartsAgainFromTheCardUnderThePointer`. **Status**: fixed in `8451a9c`.

<a id="issue-10"></a>
### Issue 10: A capture into a full column drops the card open in the editor

The overflow moves into `StackModel.removeOverflow(over:)` and drops the oldest card that is not in
the annotator or in a stitch, since those come back to their slots. Test:
`StackModelTests.testTheOverflowKeepsTheCardsInTheEditorAndInAStitch`. **Status**: fixed in `72f89df`.0

<a id="issue-11"></a>
### Issue 11: A cleared request whose answer live ink drew is never pruned

Clearing leaves a reply the person already has, published or shown, as it is (`Reply.isPresented`),
so the request has nothing left to clean up and is pruned after a week. Test:
`ScreenshotRequestsClearingTests.testAClearedRequestWhoseAnswerLiveInkDrewStaysDrawnAndIsPrunedAfterAWeek`.
**Status**: fixed in `72f89df`.1

<a id="issue-12"></a>
### Issue 12: A plugin switched off comes back at the next launch when the old skill is a link

The launch records, once per agent folder, that the plugin is in beside the skill from before the
plugin, and installs for that skill only in a folder it has not recorded. A link then gets the
plugin at the first launch, as a folder does, and the switch's off holds after that. The record is
`agent-plugin-migrated.json` in Application Support, a list of folder paths
(`LegacySkillMigrations`). An install from the switch or setup beside the skill records it too.
Tests: `AgentPluginTests.testALaunchLeavesThePluginOffAfterTheSwitchTurnedItOffWhereTheOldSkillIsALink`,
`testALaunchThatFindsThePluginBesideALinkedSkillLeavesItOffOnceTheSwitchTurnsItOff`.
**Status**: fixed in `d0fb7c7`.

## What the review changed

One reviewer, an agent that did not write the findings, tried to refute each one against the code
at 358d988 with the new tests. It read the code and did not run it.

- **All ten confirmed findings stand.** Three fixes changed because of it:
  - run-4: clearing `ending` in the handover would break
    `AnnotationRunTests.testAQueuedFileThatDoesNotOpenIsPassedOver`, so it is cleared in `reduce`,
    once a `prepare` is left.
  - requests-1: the test's comment named the second removal of drawings and replies as a fault. That
    second removal does nothing, so the fix keeps `left` and the comment changes.
  - asks-1: the failure moved from `stop()` to the sign-out, so clearing keeps the silent drop that
    `docs/live-ink.md` states.
- **Reach narrowed**: run-1, run-2 and run-3 need a zoomed editor and a second input within 0.2 s.
  run-2 also needs lone thumbnails, not a stack. They moved to the bottom.
- **Reach widened**: editor-1 happens every time two replies from one session are paged through.
  corner-3 rose to second. toolbar-3 is ordinary use.
- **More consequences found**: corner-1 also keeps a lone thumbnail in the corner. toolbar-3's second
  start can wait the full 45 s and fail. run-4 has a second path: a click during Esc's park.
- **Plausible findings upgraded**: corner-4, corner-9, requests-2, setup-1 and toolbar-1. corner-9 is
  a crash. None had a unit test when the review ran.
- **Downgraded**: flights-1 and run-5 to low, corner-5 to very rare, setup-9 to a missing feature.
- **Refuted**: corner-10 and run-6 as intended, and flights-3 as a bug.
- **Merged**: hand-7 duplicates asks-2.
- **Added**: corner-14, which no map had.

After the review, four of the upgraded findings were confirmed by a failing test: corner-9,
corner-4, requests-2 and setup-1. toolbar-1 was not, because no unit test can build
`AnnotationController`, which held its flag. Its fix moved the destination into `EditorCore`'s
send, which `EditorCoreSendTests` covers.