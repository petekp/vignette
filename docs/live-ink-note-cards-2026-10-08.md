# Live ink notes become cards

Decided by Pete on 2026-10-08. A live ink note sent to an agent session leaves the screen as a card.
When the session's work is done, the result comes back as a card from that session. Live ink's
built-in quick answers stay on the window.

Terms used here:

- **Note:** the person's ink and words, sent with live ink.
- **Note card:** the card a note becomes when it is sent to a session.
- **Result card:** the card from the session once its turn is over.
- **Turn:** one run of a session's work. The plugin's hooks write when it starts and ends into the
  session's inbox, for Claude Code only.
- **Responder:** the built-in Claude that answers a note on the window in a few seconds
  (`LiveResponder`, ADR 0020).

## Why

Keeping a session's work on the window is too fragile. Windows move, scroll, get minimized or
closed, and a request queued behind another turn can keep the ink up for as long as 30 minutes.
Pete's log has nine notes sent to sessions, all during testing on 2026-10-07 and 08:

- four turns ended after 13, 18, 31 and 41 seconds;
- two ran into the 3-minute limit for a turn to start;
- one was cleared by hand after 26 seconds;
- two have no ending in the log.

The ink also hid twice because its window scrolled. A card stays where it is, already says what
happened to a send, and its Reply goes back to the session.

The responder's answers stay on the window because they come while the person is still looking at
it. Over Pete's 43 asks they arrived after 3.3 s at the median, 5.2 s at the 90th percentile and
24.7 s at most.

## Pete's choices

- **Quick answers stay on the window.** This change is about sessions only.
- **The note card is a file in the screenshots folder.** Agent replies and stitches already land
  there, and a card that is not a file would be a much larger change to the stack.
- **A result card only when something happened.** That is a reply from the session, or a change in
  the window under the ink. Otherwise the note card says the session is done.

## Behaviour

### Sending a note

1. Vignette captures the window as today. The picture sent to the session does not change: the
   window with the ink drawn in and each stroke numbered, which the message's `[n]` refer to.
2. Vignette also writes the window without the ink into the screenshots folder, as
   `Live ink note <date> at <time>.png`. The person's ink becomes that file's drawing, as the
   editor's marks, and their words become a note on it. So the card is an ordinary drawn-on
   screenshot. It can be opened, changed, copied, dragged or sent again. Live ink's marks are
   already the editor's four kinds, and the capture has no ink until Vignette draws it in
   (`LivePacket.build`), so nothing is redrawn by hand.
3. The file arrives like a capture but skips the capture switches, as a file from `add` does. Copy
   on capture and Draw on capture leave it alone.
4. The request names that file, so the card shows the send as a send from the editor does:
   Sending to, then Sent to, Queued for, Check or Not sent.
5. The ink and the note leave the window at once, and the card comes into the corner. Step 6 below
   makes the card fly there from the window.
6. Nothing on the screen waits on the session, so the person can draw and send another note right
   away. Each request's turn is watched on its own.

### When the session's turn ends

Vignette reads each request's turn twice a second, as it does today.

| What happened | What Vignette shows |
| --- | --- |
| The session answered with `scripts/reply --answer` | A result card: the window captured afresh, with the answer's words and its marks found in that picture, drawn as the agent's. |
| That window cannot be captured: closed, minimized, or Vignette relaunched | A result card: the picture that was sent, with the answer's words in its corner. This is today's fallback. |
| The session replied with `--marks` or `--image` | That reply is the result card, as today. |
| No reply, and the window changed under the ink | A result card: the window as it is now, from the session. |
| No reply, and nothing changed under the ink | No result card. The note card says Done in *project*. |
| The window closed, was minimized or changed size | No result card. The note card says Done in *project*. |
| Vignette stopped waiting on the turn | Nothing more. The note card already said Sent to. |
| The session is a Codex thread | Codex reports no turns, so only a reply from the agent makes a result card. |

The window comparison is the one live ink makes today for its before-and-after playback
(`LiveChange`): the part of the window round the ink, kept as the note goes, against the window
when the turn ends.

A result card that Vignette makes, with no reply behind it, carries the agent and the session as a
card pushed with `add` does. So it shows the "From Claude" tab, and Reply on it goes back to that
session. A Codex thread is recorded in an attribute of its own, `<bundle id>.thread`, which `add`
never writes, so a push's `session=` still names a Claude Code session only. It is named `Live ink result <date> at <time>.png`. A note card that is not on screen when
it says Done comes up as the lone thumbnail, as a result card would.

## What goes away

- **Session answers drawn on the window.** `LiveInk.result` makes the result card instead. The
  reply's stage is `shown` then, as it was for an answer drawn on the window, since the card is an
  ordinary file and the reply has none of its own. ADR 0022 supersedes ADR 0021.
- **The thinking light while a session works,** and Vignette's notes beside the ink about a send.
  The note card says these now.
- **The before-and-after playback on the window:** `replay`, `BeforeLayer` and `Mark.before`. The
  comparison stays, to decide whether a result card is made.
- **Following up a session's answer on the window,** with its Reply field and buttons. Reply on the
  result card does this.
- **The skill's live ink section** is rewritten for result cards. A card has no buttons, so it stops
  asking sessions for `actions`. The helper still accepts them and the card leaves them out. The
  skill's `metadata.version` and both plugin manifests' versions rise.

The responder's answers, follow-ups, tours and buttons on the window do not change.

## Steps

Each step is checked in the macOS 26 VM before the next. All six are built and were checked on
2026-10-08: a changed page, an unchanged one, an `--answer`, and two notes in a row, with Copy on
capture and Draw on capture on. The flight was checked in frames taken with it slowed, and the
ink's handover by the log: VNC frames come 7 s apart, too far apart to show a single commit.

1. The note card: the file, its drawing, the send naming it, the ink leaving, a turn watch for each
   request.
2. The turn's end: a result card, or Done on the note card.
3. A session's `--answer` becomes a result card from a fresh capture.
4. Remove what goes away.
5. The skill, the plugin version, `docs/live-ink.md`, `docs/voice.md`, and ADR 0022.
6. The card flies from the window into the corner, as the ink leaves.

## Checks

- A note sent to a fake session writes one note card with the ink as marks and the words as a note.
  The ink leaves the window, and the card shows Sending to, then Sent to.
- The note card flies from the window to the corner with the ink and the note drawn on it. The ink
  on the window goes on the turn the card starts moving, so the card carries it away.
- Copy on capture and Draw on capture are on, and neither acts on the note card.
- Two notes sent one after the other each get their own card and their own turn watch.
- A turn that ends with the page changed under the ink makes one result card, from the session,
  whose Reply goes to that session.
- A turn that ends with nothing changed makes no result card, and the note card says Done in.
- An `--answer` makes one result card with its marks on the fresh capture. Its turn's end then
  makes no second card.
- With the window minimized at the turn's end, the note card says Done in. An answer then arrives
  on the sent picture.

## Known limits

- **A Codex result card's Reply target may read only "Codex".** The target takes its thread's name
  and project from the session list, which holds the five threads used last, so an older thread
  shows the client's name. Reply still goes to that thread.
- **An answer's words sit in the card's top-left corner,** which on a window capture is the title
  bar or the browser's toolbar.

## Not in this change

- **A lasting sign on the note card while the turn runs.** The card says Sent to, and then nothing
  until the result. If the wait feels blind, a small working badge on the card is the next step.
- **Marking what changed on a result card.** The comparison knows the region, but a scroll also
  counts as a change, so a ring could point at the wrong thing.
