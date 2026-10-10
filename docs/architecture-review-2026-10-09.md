# Architecture review (2026-10-09)

The foundation is sound where ADR 0003's pure reducers already decide: the editor, the annotation
run, the zoom, card notices, drawings and the reply protocol. It is weak where live ink grew fast.
There, state machines are held as loose fields, one rule is spread across `AppDelegate`, `LiveInk`
and the panels, and none of the ordering is tested.

Six changes are recommended, in the order below.

## Progress

- **1, destination choice:** done. Send's rules on main as `d666c89` and `a824394`; the live ink
  note adopted them on live-ink as `cc3f728`.
- **2, files written into the screenshots folder:** done. `FolderWrites` on main as `98a2135`;
  live-ink's note cards and result cards call it since `99be46c`.
- **3, a note card's wait:** done on live-ink. `NoteCardWait` decides and `LiveNoteCards` runs it.
  A note to a Codex thread is no longer watched: it stops waiting as it is sent, where it used to
  stop 180 s later without a word. An answer that comes after a note's result card was made goes
  on that card instead of becoming a second card.
- **4, result card placement:** done on live-ink as `3fd6de9`, with the badge fix below.
- **5, the live ink ask as a reducer:** done on live-ink. `d81deb7` moved the ask's state into
  `LiveAsks` with the same transitions, and `b4a49eb` simplified it. A callback for an ask that is
  no longer current now changes nothing. Before, it landed on whichever ask was in the right
  phase, so a cleared ask's packet could be sent as the next ask's question. A mark taken off the
  screen loses its roles. The steps and the focus tour are still in `LiveInk`, for a later pass.
- **6, settings file sync:** done on main as `880ec84`.

Open questions the changes left as they were:

- A stitch records no write time, unlike an add, a reply or a live ink card.
  `testAStitchIsNotReservedAndRecordsNoWriteTime` pins this, so changing it is a deliberate edit.
- `LiveNotePanel.setSessions` still takes a list that arrives after the note was sent or began
  closing. It had no guard before either, and whether such a list can change what the sent note
  shows has not been checked.
- A remembered session can be picked from a kept list before the fresh one arrives, and then move
  if the fresh one says otherwise. That is today's behaviour, kept.
- Erased ink stays in what its ask is about, so the × and a session's card still finish it and
  count it in `dismissed marks=`. Taking it out would also need another way to end an ask, since
  `.finished` ends one when every mark it is about has finished.
- `pictureSent` is recorded on whichever ask is current, not matched by id, so a cleared ask's
  picture flag can land on the next ask in `[state]`. `testAPictureIsRecordedOnWhicheverAskIsCurrent`
  pins this.

This review covers the live-ink branch, which holds main and live ink. Symbols are cited rather
than line numbers, because the two branches number lines differently.

## Order

| # | Change | Branch | Why at this point in the order |
|---|---|---|---|
| 1 | Destination choice | main, then live-ink | Session detection, the next planned feature, changes these rules. Send and the note already choose differently. |
| 2 | Files Vignette writes into the screenshots folder | main | `add`, note cards, result cards, replies and Stitch all write files there, each doing part or all of one order by hand. Change 3 builds on this one. |
| 3 | A note card's wait | live-ink | The newest code. It is spread over three files, and every change to it has touched all three. |
| 4 | Result card placement from plain text lines | live-ink | The last three result card bugs were in the half no test reaches. |
| 5 | The live ink ask as a reducer | live-ink | The most-changed code in the app. Change 3 takes the session route out of it first, which makes it smaller. |
| 6 | Settings file sync as a reducer | main | The person's real settings file depends on it. A race in it was just fixed, and the fix was checked only by hand. |

Changes 1, 2 and 6 touch shared code, so they land on main first. Main then merges into live-ink,
and live-ink into glow-lab. A verification build goes into `next`, never into `lab`.

One bug found during the review needs no change of shape. Fix it in place:
`LiveAnswerLayout.noteBox` treats a badge's overlap as its height. The badge rises
`NoteBadge.above`, which is 1.16 em, while `noteBox` allows only `badgeOverlap`, which is 0.2 em.
No answer on the screen carries a badge yet, so nothing shows it today. Read the extent from the
shared geometry instead, as `EditorGeometry.inkExtent` does.

## 1. Destination choice

**What hurts.** The rule for which session Send or a note goes to has no single home:

- `AgentDestination.defaultTarget` ranks by a `focus` field on each destination: the app's shown
  thread first, then herdr's pane, then its tab, then the session used last.
- `ClaudeCodeConnection.markFocus` sets herdr's focus inside the Claude Code adapter. A Codex
  thread therefore can never be marked as focused.
- `AgentDestination.cameFrom` and the `waits` rule in `AppDelegate.listDestinations` handle the
  thread the Codex app shows.
- `LiveNotePanel.setSessions` and `find` keep the note's last pick. When `/clear` has given that
  session a new id, they find it as the one session of its agent in its project.
- `AnnotatorToolbar.Model.answered` settles the target once and keeps it from changing under the
  pointer.

So Send and the note use different rules. The note keeps the session picked last and Send does not.
A note never uses the thread the Codex app shows. Every step in "Where this stands" in
`docs/session-detection-exploration-2026-10-08.md` changes one of these rules.

**The change.** Grow `AgentDestination`'s static functions into one module that takes the
candidate sessions and the facts about them, and answers the pick and the menu's order. Those facts
are the card's origin, herdr's focus, the app's shown thread, the last pick and when it was made,
and when each session was used last. Send and the note both ask it. The toolbar keeps only its
promise not to change the target under the pointer.

**Why a module, and the simpler alternative.** The requirement: the two callers disagree today, and
the rules are about to change. The simpler path is to add each new rule wherever its input arrives.
That is how the rules came to sit in five places, and each new step of session detection would add
a sixth. The module is not a new layer: it replaces `defaultTarget`, `cameFrom`, the `waits` rule
and `LiveNotePanel.find`.

**Decisions from the grill.**

1. *First commit preserves behaviour.* It moves Send's rules into the module unchanged, and tests
   pin them, including the `waits` rule, which had no test. Done on main as `d666c89`, as
   `DestinationChoice`. Each rule change after that is one commit with its own tests and shadow log
   evidence.
2. *No "not sure" answer yet.* Session detection needs one, but no rule produces it today. It is
   added with the first rule that does.
3. *The module holds no state.* The last pick is a fact passed in. The send path records it for
   Send and the note alike. It is kept in memory, as the note's pick is now.
4. *Session listing moves too, as a second step.* The kept lists and joined asks in
   `ScreenshotRequests` share no state with its requests and replies. Moving them out leaves
   `ScreenshotRequests` with one job, the request store. herdr's focus moves out of the Claude
   Code adapter in the same step, to become a fact passed to the module. Moved on its own, it
   would change when the first answer settles the target: today it arrives inside Claude Code's
   listing, about 60 ms after the editor opens.
5. *Per-agent rules move into the adapters.* Callers currently switch on the client to decide some
   things. The adapters will answer them instead: whether a listing is complete, whether a session
   is active, and whether it can report its turn. `ToolbarOffer`'s rule that a Claude Code session
   missing from the list is closed is one of these.
6. *Branch.* Send's rules are on main and the note panel is on live-ink. The module and Send's use
   of it land on main. The note adopts it on live-ink, and only then does the module take which
   surface is asking (Send or the note), with the note's last pick and its `find` after `/clear`.
   Main has only Send, so it takes no such input yet.

## 2. Files Vignette writes into the screenshots folder

**What hurts.** `add`, note cards and result cards write into the screenshots folder and wait for
the watcher to report the file. Each one does the same steps by hand, in the same order:

1. Register the name in `pendingAdds`.
2. Write the file.
3. Set `screenshotWrittenAt`.
4. Clear `addingMarks`.
5. Call `presentAdd`.

Replies and Stitch also write there, and each does part of this its own way. A reply's name is
reserved in `ScreenshotRequests`, and its `present` callback sets the write time and shows the card
directly. `finishStitch` skips step 3. No harm from that has been found, but nothing enforces the
rule either.

What happens when a file leaves is also written out twice. `thumbnail.remove`, `drawings.remove`
and `requests.fileRemoved` appear together in `moveToTrash` and in the watcher's `onRemoved`. A
deferred removal does only the card's part. Only `AppDelegate` knows any of this, and no test
reaches `AppDelegate`.

**The change.** One module owns what Vignette puts into the folder and what it takes out. It
reserves the name, writes the file, records the agent and the session or thread on it, and
presents the card once both the watcher's report and the joining marks have arrived. It defers a
removal when the folder was listed before the app's last write. It also tells the stack, the
drawings and the requests when a file has left. `add`, Stitch, note cards, result cards and
replies call it.

**Why a module, and the simpler alternative.** The requirement: five writers carry one order between
them by hand, and one already skips a step. The simpler path is a private helper in `AppDelegate`. It
would make the order hard to skip, but the order would still be untestable, because the helper
would live where no test reaches. The module also lets tests cover the watcher reporting before
the marks join, a removal deferred against an older listing, and a refused note taking back its
file. It conflicts with neither ADR 0011 nor ADR 0022.

## 3. A note card's wait

**What hurts.** A note sent to a session is tracked in four places, all keyed by its request id:
`LiveInk.watches`, `AppDelegate.liveNotes`, `AppDelegate.sentShots` and the record in
`ScreenshotRequests`. Four closures on `LiveInk` join them: `listSessions`, `turn`, `sendNote` and
`turnEnded`. Each has one adapter, so none is a real seam.

`LiveInk.checkTurn` is a timer-driven state machine with limits of 2 s, 180 s and 30 min. It reads
`Date()` itself and has no tests. Whether a note ends with a result card, a "done" notice or
nothing depends on the order in which callbacks across three objects arrive:

- `delivered` in `AppDelegate` stops the watch.
- `liveNoteEnded` asks `requests.hasReply`.
- `LiveInk.result(for:)` works only while `watches` still holds the request, but `endTurn`
  removes the request before it looks at the window again.

One sequence is suspected but not confirmed: a reply that arrives after a "changed" result card
was made would become a second card.

**The change.** One value per note decides, and it is pure. It takes:

- sent;
- delivered, with the outcome;
- each turn reading, with the time;
- reply accepted;
- the window looked at again.

It returns what to do: watch the turn, stop waiting, look again, make a result card, say "done",
or draw the reply on a fresh capture. A small owner keeps these values by request id and runs what
they return, so `sendLiveNote`, `liveNoteEnded` and `addLiveResult` leave `AppDelegate`. `LiveInk`
keeps only the screen's part: once the note card leaves the window, its job is done.

**Why a module, and the simpler alternative.** The requirement: per-note state is held in three
files, and the outcome depends on callback order. The simpler path is to make `checkTurn` a pure
static rule, as `ListeningEnd` is. Do that either way. It tests the turn limits but not the order of
reply, turn end and delivery, which is where the suspected bug sits.

**Decisions from the grill.**

1. *The clock is an input.* Every event carries `now`, so tests run on a fake clock.
2. *A Codex note is not watched at all.* Codex reports no turns. Today such a note waits 180 s and
   then stops waiting without a word. That is the intended outcome (the note-cards plan), and the
   value now gives it at once, without a timer.
3. *Nothing survives a relaunch.* Nothing does today either, and nothing requires it.
4. *Tests first.* The first commit pins today's behaviour in sequence tests, including the late
   reply. If the second card is confirmed, the fix is its own commit and needs Pete's call on what
   should happen.
5. *Order.* After change 2, so that writing the note card and the result card calls the folder
   module. After change 1, so that the note's destination comes from destination choice.

## 4. Result card placement from plain text lines

**What hurts.** `LiveAnswer.cardMarks` is pure and tested. Its inputs, though, are worked out
inside `LiveInk.result(for:)` in an async task: the target lookup, the padding round a ring, the
fractions and the page's rect. `LiveInk.target(of:in:sent:)` is private and reads Vision's own
result type, which a test cannot build.

Fixes `aa94b17`, `a43d0b0` and `28d1b49` each had to change `LiveInk` as well as `LiveAnswer`. The
bug in `a43d0b0`, an arrow padded as if it were a ring, was in the untested half.

`cardMarks` also measures a note by turning it into a temporary `AgentMark` and back, to learn the
wrap `AgentMarks` would choose. That copies the agent-text rules, so a change to `AgentMarks.fit`
moves card notes without a test noticing.

**The change.** One module takes the captured window as plain values: its frame, its page, and its
text lines with their word boxes. It also takes the answer and the ink's rect, and returns the
card's marks and the ones it could not draw. A small adapter turns Vision's lines into those
values. `AgentMarks` places an agent note near a rect itself, so one module owns how agent text is
wrapped, fitted and placed.

**Why a module, and the simpler alternative.** The requirement: three bugs in a row landed in the
untested half. The simpler path is to test `LiveInk.result(for:)` itself, but it captures the
screen and runs Vision, so it cannot be tested without a window.

## 5. The live ink ask as a reducer

**What hurts.** `LiveInk` is 2,051 lines. It was changed 30 times in the two weeks to 2026-10-09,
and its tests reach the pure helpers beside it but none of its own logic. An ask moves through drawing, note, looking, asking, answered
or failed, follow-up, restore and finish. That path is held in `AskState.phase` and about 15
fields beside it, including `asked`, `answerMarks`, `noteInk`, `followed`, `prepared`, `handing`,
`spoken` and `finishing`.

Each way out resets a different set of those fields by hand:

- `endConversation` resets most of them.
- `removeAnswer` resets `followed` and `answerMarks`.
- `clearEarlierAnswer` resets only `followed`.
- The delayed closure in `finish`, which `dismissAnswer` goes through, resets `finishing`, `asked`,
  `answerMarks` and `asking`.

A check for a callback that answers too late is written out wherever one returns:
`asking?.about == about`, `say?.id == replyID`, `phase == .looking` and `focusRun?.id`.

About nine sets record a role per mark. `remove` cleans none of them, and `strokeTimes` is
cleared only by `endConversation`. Adding replies to an answer in words (`e258e5c`) changed 15
files and 263 lines of `LiveInk`.

**The change.** A pure reducer owns the asks since the screen was last cleared: which ink is new,
which ink has been asked about, the ask's phase including follow-up and restore after a failure,
which marks are the answer's, and what dismiss, erase, clear and finish do to each of them. Every
async effect carries its ask's id, and the reducer drops an answer for an ask that has ended. One
record per mark holds its role, so removing a mark is one call. `LiveInk` runs the effects: it
builds the packet, asks the responder, puts marks on the screen and finishes them.

**Why a module, and the simpler alternative.** ADR 0003 already decided this for the app's state
machines, for the reason seen here: before the annotation run became a reducer, its last four bugs
came from callers that had to reset state before an event. The simpler path is one `resetAsk()`
helper for the five exits. It makes the exits consistent, but the late-callback checks and the
phase guards stay scattered, and the sequences stay untested.

**Decisions from the grill.**

1. *After change 3.* The session route enters `AskState` in `.looking`, so "looking" also means
   "being sent to a session". Change 3 removes that use.
2. *In scope:* the ask, its answer, follow-up, restore and each mark's role. *Out of scope:* the
   chord, strokes, panels, pinning marks to windows (`LiveWindows`) and listening, since
   `ListeningEnd` is already pure. The steps and the focus tour come in a second pass.
3. *Two commits.* The first moves the state into the reducer with the same transitions and pins
   them with sequence and random-sequence tests, as in `AnnotationRunTests`. The second simplifies
   with those tests in place.

## 6. Settings file sync as a reducer

**What hurts.** The write, the reload and the merge in `Settings` share `syncedBytes`,
`syncedData`, `readOnly` and two timers. The tests reach only the static `merged`. The race fixed
in `c6249bf` was proved by hand in the VM, by losing an edit 3 times out of 3 before the fix and
keeping it 3 out of 3 after. The order that fix relies on has no test:

- a write takes in the file first;
- a reload skips the app's own bytes;
- the base for the next merge is the file's validated data.

That order is out of reach of a test because it is private state on a singleton whose file URL is
a `static let`, and whose `init` starts the file watchers.

**The change.** A pure value owns the sync's state. It takes what happened: the app changed, the
file's bytes were seen, a write is due, a flush, the app quitting. It returns what to do: write
these bytes, take in this data, log these lines, become read-only. The file watcher and the timers
feed it.

**Why a module, and the simpler alternative.** The requirement: this protects the person's real
settings file, and the last fix to it could not be tested. The simpler path is a test that drives
the singleton against a temporary file. That needs a seam for the file URL anyway, and the timing
would still come from real timers.

## Worth exploring

These are real costs, but nothing planned next depends on them.

- **Keyboard focus between the editor and the toolbar** (main). Who holds the keys is decided
  across `AnnotationController`, `AnnotatorToolbar.Model`, `ToolbarPanel` and `EditorView`, partly
  in observers of the window's key state. `ef23e7f` changed three of those files and was checked by
  hand. A focus reducer would take Tab, Space, Return, Esc, presses and key-window changes, and
  return what to do.
- **One table entry per tweak** (main). Each number's safe range, slider range and whether it is
  motion are kept in three lists beside its property: `bounds`, `scaledForMotion` and 108
  `Tweak(...)` rows in `DebugPanel`. A test guesses which tweaks are motion from words in their
  names. One table keyed by key path would feed all three.
- **A launch profile, and a seam for Apple's defaults** (main). Seven files re-read
  `VIGNETTE_SETTINGS`. The Apple capture settings code (`reconcileApple`, `followAppleLocation`,
  `pushToApple`, `restoreAppleDefaults`, `handBackAppleThumbnail`) has no tests. A test run without
  the scheme's `VIGNETTE_SETTINGS`, such as plain `xctest`, has `bootstrap` read the Mac's real
  capture settings. One profile read at launch, and a sync
  module given its defaults store, would make both testable.
- **A slot held by a flight** (main). The step "take the card out of `forming` or `outCards`, drop
  the shadow, lift on the next turn" is written three times in `ThumbnailController`. `3c7cc67`
  copied it whole. `TransitionLayer` has no tests.

## Considered and dropped

- **A recording fake for the stack's annotator closures.** The reducers behind them are tested,
  and the end-to-end suite drives the closures themselves. A fake would give one adapter a second
  only for tests, with no rule to pin that the suites miss.
- **Moving the command file checks into `Commands`.** The chain in `AppDelegate.run` is about 30
  lines, and its refusal codes are visible in the log. Add a test at the next change to it instead.
- **A transition table for requests and replies.** `ScreenshotRequests` has about 35 file-backed
  tests of recovery and ordering. The contract there is the order of the file writes, which a pure
  table would not capture.

## Judged fine

So that a later review does not suggest these again:

- `EditorCore` and `EditorGeometry`: deep, pure and heavily tested.
- `Drawings`, `DrawingStore` and `RenderingQueue`: narrow interfaces, good tests.
- `ReplyProtocol` and `ReplyCommand`: each path, the digest, the ticket and the receipt are defined
  once.
- `Subprocess`: `eb59689` landed in one place.
- `StackLayout`, `CardNotices`, `AnnotationRun`, `AnnotatorZoom`: pure and tested.
- `Settings.shared` read directly from the AppKit and SwiftUI code: pure modules already take
  `UITweaks` by value, and injecting it into that code would add interface with no test to gain.
- `LiveChange`, `LivePatch`, `LiveAnswerLayout`, `ListeningEnd`: pure and tested.
- Live ink and ADR 0010: shapes go through `Mark.shape`, and notes are drawn with `mark.draw`. The
  ink look, the light look and the glass popover are deliberate different looks.
- A note to a Codex thread gets no result card from a change: Codex reports no turns. This is
  documented in `docs/live-ink-note-cards-2026-10-08.md`.

## Terms

The proposed modules are named here, not yet in `docs/glossary.md`, which says what is true now.
A term goes into the glossary in the commit that builds its module. *Destination choice* is the
pick among candidate agent sessions and the facts about them. *A note card's wait* runs from
sending a note card until its result card, its "done" notice, or Vignette stopping waiting.
