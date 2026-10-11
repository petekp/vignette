# Send waits a few seconds, and can be cancelled

Status: built 2026-10-10. The pure part is `Sources/SendGrace.swift`, run by
`Sources/ScreenshotRequests.swift`. Checked in the VM on 2026-10-10 with live ink notes to a fake
Claude Code session: the line arrived 3.1 s after the send; `unsend` at 1 s left no line, and the
note card and its file went; of two notes, cancelling the second left the first to go; SIGTERM
during the wait sent the line and the app quit. VNC captures show the ring emptying, then Sending,
then Sent. A VNC click on Don't send cancelled a live ink note and an editor Send to a Codex
thread; the screenshot stayed. Not yet run: the `send_grace` e2e scenario, which posts keys and
clicks and needs python3, which the VM lacks.

## What Pete asked for

On 2026-10-10: "i think i'd like to have a grace period before something is delivered to the agent
after i hit send, perhaps we keep the ability to cancel in the thumbnail that appears post-send."
Then: "like i should be able to delete it before it sends. we can use a circular countdown."

Pete's answers: it covers a live ink note sent to a session and Send or Reply from the drawing
editor. The wait is 3 seconds.

## Behaviour

- After Send or Reply, or after a live ink note goes to a session, the request is stored at once,
  as before. The line is not written to the Claude Code inbox, and `codex queue` is not run, until
  the grace period ends.
- The grace period is `ui.sendGraceSeconds`. It is 3 by default. 0 turns the wait off: the line
  goes at once and the card shows no ring.
- The card that comes up after the send shows a ring round the agent's logo that empties over the
  grace period, and a Don't send button. A card that is not on screen comes up as the lone
  thumbnail for the wait, so the ring can always be seen.
- When the grace period ends the line goes exactly as it did before: the same text, the same inbox
  write or `codex queue`, the same notices after.
- Don't send before that moment means nothing reaches the agent, ever. The request is cleared by
  the existing clearing path, so no ticket and no inbox line remain, and a late reply to it is
  refused as `request-closed`.
- On an editor card, the screenshot and its drawing stay. The send notice goes and the card is as
  it was.
- On a live ink note card, the note's file, its drawing and its card go. They are Vignette's own.
  The ink left the window when the note was sent, so there is nothing to put back.
- `vignette://unsend?file=<file in the screenshots folder>` does what the button does, for a script.

## Decisions and their reasons

- **The wait lives in `ScreenshotRequests`.** It already owns the request, its record and its
  clearing. The request is stored first with status `prepared`, and the private `submit` runs
  later, unchanged. So nothing that is written changes once the grace period ends.
- **`SendGrace` is a pure value** (ADR 0003). It holds who is waiting and until when, and decides
  what each event does. `ScreenshotRequests` arms the timers and runs the effects. The tests
  drive it with times, with no timers.
- **Cancelling an editor send says nothing.** Vignette has no toasts. The person's own press on
  that card is the confirmation, and the ring and the button go. "Not sent" is the headline for a
  failure, so a choice must not reuse it.
- **Don't send cancels every send of that screenshot still waiting.** The notice holds one waiting
  send per file, so two sends of the same file show one ring. A cancel that left an earlier send
  waiting would let a line go out unseen.
- **Sends of different screenshots are independent.** Each request has its own deadline and timer.
- **Quitting sends at once.** `applicationWillTerminate` hands over every waiting line and waits at
  most 2 seconds for the clients. Quitting is not a retraction. Dropping the line would lose
  something the person believes went, with no card left to say so. Sending after the next launch
  would be a surprise. The cap is 2 seconds because a newer launch force-terminates an older copy
  after 3.
- **A session that goes away during the wait is the existing failure.** The inbox check and the
  Codex thread lookup run when the line is handed over, so the card says "Not sent" with the
  session's reason, as it does now.
- **The grace period is time, not motion.** `ui.motion` and Reduce Motion do not shorten it. The
  ring is a clock: it counts down linearly to the absolute deadline. A card shown late starts at
  what is left.
- **The clock is `ProcessInfo.systemUptime`**, and the timer is a dispatch timer. Both stop while
  the Mac sleeps, so the deadline and the timer stay in step. After a sleep the line can go later
  than 3 seconds of wall time, never earlier.
- **Deleting a card during the wait cancels its send.** "I should be able to delete it before it
  sends." A file leaving the watch folder (the Trash button, Cmd+Delete, or Finder) reaches
  `ScreenshotRequests.fileRemoved`, which runs the same cancel as Don't send. Without it the card
  would be gone and its line would still go.
- **A Copied notice that covers the ring does not hide the button for good.** When it expires and
  the send is still in its grace, the countdown comes back. A send already released does not: its
  card shows nothing until the client answers, as a send with no grace does.
- **The card's state during the grace is `inGrace`.** `waiting` is not used, because `CardNotices`
  already keeps the sends that wait for an answer.
- **The notice reducer's events are `released` and `cancelled`.** `NoteCardWait.Phase.unsent` already
  means a note whose sent event has not been handled, so `unsent` is not used for a cancel.
- **The ring is drawn from the clock** (`TimelineView`), not animated to a final value, so a card
  shown late, rebuilt, or replaced by a second send of the same file always shows what is left.
  It is the one animation the motion scale does not shorten.
- **Don't send takes presses only once the overlay has landed.** Before then it is invisible, and an
  invisible button must not cancel a send.
- **A crash or force quit loses the line, and the next launch clears the request.** The line waits
  in memory. A relaunch cannot send it, so `load` clears any request still `prepared` and logs it
  (`[requests] cleared <id>: its line never went, Vignette quit first`). The person cannot be told,
  since the card is gone. Only a request whose line never left is still `prepared`: every hand-over
  to a client stores the request as `uncertain` first, since the client may have the line while
  its call runs, for up to 25 s with `codex queue`.
- **A launch that replaces a running copy does not clear.** The older copy may still be handing its
  waiting lines over as it quits, and clearing then deletes the image a line names. That launch
  calls `load(clearingUnsent: false)`, and a later launch clears what a crash left.
- **Quit does its other work first.** `applicationWillTerminate` stores drawings, flushes settings
  and hands back Apple's thumbnail before it hands over waiting lines, so a slow client cannot make
  a newer launch's 3 second force-quit cut them off. Each request is recorded `uncertain` before
  its line leaves, and a client that has not answered in 2 seconds stays `uncertain`: the line may
  have arrived, so the next launch must not clear it.
- **The shadow log knows about a cancel.** `SendContext.cancelled` writes a `send-cancelled` event
  with the request id for an editor send. For a live ink note it names the session in `note`,
  because the `note` event carries no request id. The cancel can be matched to its note only when
  one note to that session is waiting; with two waiting, which one was cancelled is not recorded.
- **The live ink turn watch starts when the line is handed over.** A turn that ends during the wait
  is not this note's. `NoteCardGroups` decides it: a note sent with a grace period is `held`, and
  `released` starts its wait as `sent` does, while `cancelled` forgets it.

## How the notices change

A send with a grace period posts `.sending` with a `SendNotice.Grace`, so its state is `inGrace`
until its line goes. `.released` turns it to `.sending` without changing the card's notice id.
`.cancelled` takes the send and a shown notice of that request away, so a late answer to it is
dropped. An `inGrace` send has no hold, and the corner stays for it as for any send awaiting an
answer. When a notice that covered a send in its grace expires, the countdown comes back.

## Log lines

- `[send] prepared …`, then `[send] waiting <ms>ms request=<id>` when there is a grace period.
- `[send] released request=<id> after=<ms>ms` when it ends, then `[send] ok|queued|uncertain|error`
  as before.
- `[send] released at quit request=<id>` for a line handed over on quit.
- `[send] cancelled request=<id> before it was sent`, with `: its request was cleared` when a clear
  took it.
- `[live-ink] note card cancelled request=<id> before it was sent`.
- `[unsend] ok request=<ids> <name>` or `[unsend] error nothing-to-unsend <name>: no send of it is
  waiting`.
- `[state] requests` gives a waiting request a `graceMs`.

## Open questions and known gaps

- **There is a slider for the grace period only in the debug panel.** The Settings window has no
  control for it. Pete decides whether it should have one.
- **A cancelled live ink note does not put its ink back on the window.** The note card held the
  ink and is deleted.
- **`unsend` with no file acts on the newest screenshot.** A script
  that does not know which file is waiting reads `[state] requests`, where a waiting request has
  `graceMs`. The command answers one line for all the files it was given.
- **A second `unsend` of a cancelled live ink note answers `missing-file`.** The note's file is
  gone, and the URL dispatcher checks that before the action runs.
- **The narrowest card shows a small round close button without a visible label.** It is labelled
  Don't send for VoiceOver. Check it on a running copy.

## Checks to run on a copy

Use a test copy with scratch settings that set `ui.sendGraceSeconds` to 3 and `debug` to true, and
a fake Claude Code inbox (`App.fake_session`).

1. **The line waits.** Send a live ink note to the fake session. No `.line` file appears for about
   3 seconds. The card shows the ring and Don't send. The log shows `[send] waiting 3000ms`, then
   `[send] released`, then `[send] ok`. `[state] requests` shows `graceMs` during the wait. Then
   exactly one `.line` appears, and the card goes from Sending to Sent.
2. **Don't send before the deadline.** Repeat 1 and run `unsend?file=<the note file>` at about 1
   second. The log shows `[unsend] ok`, `[send] cancelled` and `[live-ink] note card cancelled`. No
   `.line` ever appears. The card, the file and its drawing are gone, and the request is `cleared`.
3. **Too late.** `unsend` of a note after 4 seconds, when the line has gone, answers
   `nothing-to-unsend`. `unsend` of an editor send's screenshot after a cancel does too. For a
   cancelled note, whose file is gone, it answers `missing-file`.
4. **Two notes.** Two notes 1 second apart each get their own ring. Cancelling one leaves the other
   to send.
5. **A session mid-turn.** With the fake session's turn busy when the note is sent, no
   `[live-ink] session's turn ended` appears before the `.line` does.
6. **Grace 0.** With `sendGraceSeconds` 0 the line appears at once and no ring shows.
7. **Quit.** `kill <pid>` the test copy during the wait. The `.line` appears once,
   `[send] released at quit` is logged, and the app exits within about 2 seconds.
8. **The editor's Send and Reply.** No URL presses Send, so this needs a click or the input
   scenarios. Open a screenshot, draw, pick the fake session and send. Check the same inbox timing.
   Click Don't send: the screenshot and its drawing stay, no `.line` appears, and the notice goes
   with no words. Repeat with `unsend?file=<the screenshot>`, and from an agent reply's card (Reply).
   Check a narrow card beside the annotator still shows a working button. Check that a dismissed
   stack still delivers at the deadline.
9. **Delete during the wait.** Send from the editor, then press the Trash button on the card
   within 3 seconds. No `.line` appears and `[send] cancelled` is logged.
10. **The e2e suite.** The existing scenarios start with the grace period at 0 (`start(app)`).
    `send_grace` runs it at 3: it has not been run yet.
