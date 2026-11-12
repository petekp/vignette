# Choosing the session: the experience, and what it would take (2026-11-11)

<!-- review-gate author: claude-fable-5-2 (Vignette coordinator session fd23d22c) -->

Pete asked on 2026-11-11 for a broad look at how Vignette identifies and selects the agent session
a drawing goes to. He asked to start from what a superlative experience would be and work backwards
to what is and is not possible. "Identifies" is read here as two things: how Vignette works out the
session, and how a session is shown so that a person can tell it from the others.

This note proposes directions. It builds none of them, and none is decided. It was revised on
2026-11-12 after an independent review, which is saved beside it as
`REVIEW-session-experience-2026-11-11.md`. The last section says what the review changed.

## The conclusion

The largest cause of a wrong destination in Pete's log is addressed. A destination picked by hand
did not last, and it now holds for 10 minutes (in Pete's build since 2026-11-11). herdr's focus,
which has not been read since herdr moved to herdr-core, is being rebuilt by a delegate on the
`send-target` branch. That outage touched 6 of the 122 scored sends.

What is left is less about guessing and more about what happens around the guess. There are five
gaps, and each has earlier work that a new design must answer to.

1. When the guess is wrong, the right session is usually the first row of the menu, and reaching
   it still takes the menu.
2. The bar shows every guess the same way, however often the rule behind it has been right.
3. The names in the menu and on the card have fallen back to titles the agents wrote, because the
   herdr tab names they were designed around are no longer read.
4. Codex threads take most of Pete's sends and get the least: five threads listed, no badge, no
   goal.
5. A wrong send can be stopped for 3 seconds. For a busy Claude Code session it could be stopped
   for much longer, and it is not.

None of these has a ranking that the evidence supports yet. Each needs either a number that is not
logged today or a choice by Pete between designs.

## Where the numbers come from

- "The scoring of 2026-11-11" is `~/Code/vignette/.scratch/send-target-2026-11-11/RESULT.md`: 122
  sends from the editor, 2026-10-29 to 2026-11-11. An independent reviewer recomputed it.
- "The first scoring" is `docs/session-detection-exploration-2026-10-08.md`, "The plan": 113 sends
  and 48 live ink notes, 2026-10-08 to 2026-10-18. A second script agreed within 1.
- "The menu replay" is `docs/session-menu-2026-10-18.md`, "Why this order": 125 sends, 2026-09-29
  to 2026-10-18. A second replay agreed within 2 sends. Its scripts were not kept, so it cannot be
  rerun.
- "The snapshot" is one reading of the live sessions on Pete's Mac at 22:49 on 2026-11-11, in
  `~/Code/vignette/.scratch/session-experience-2026-11-11/`. Its method was written before the
  count, and the reviewer recounted it.

A number from anywhere else says where it is from and whether it was checked. "Read in code" means
the code says so and nothing was run. "Unverified" is followed by the cheapest check.

## What happens today

### The guess

Send picks a destination once, when the editor opens (`DestinationChoice.pick`). The order is:

| Order | Rule | Right, in the scoring of 2026-11-11 |
|---|---|---|
| 1 | The kept pick: a session picked by hand and sent to in the last 10 minutes | Merged after the scoring. Simulated on the same 122 sends, it raised the start from 66 right to 101, which is fitted to those sends |
| 2 | The Codex app was in front: the thread it shows, or the Codex thread used last when the shown thread is not known | 45 of 51 |
| 3 | herdr's focused pane runs a Claude Code session | 20 of 64. All 34 sends of one run on 2026-11-10 were wrong; outside that run it was right 20 of 30 |
| 4 | That pane runs no agent, and its tab holds one session | 1 of 1 |
| 5 | The session used last: for Claude Code the newest user or assistant entry in its transcript, for Codex the thread's own recency | 0 of 6 |

Before the kept pick, the start was right 66 times in 122, and 78 times in 113 in the first
scoring. Rules 3 and 4 have not applied since the 2026-11-11 launches, because the old `herdr`
command no longer sees Pete's sessions.

The live ink note uses another rule. It starts on the destination the note before went to, or on
the one session of that agent in that project when the first is gone, and otherwise on the
responder that answers on the screen. In the first scoring its start was right 45 times in 48.
Notes and sends are different work, so this does not show the note's rule would do as well for
Send.

### What a session looks like

`docs/session-menu-2026-10-18.md` built most of this. The destination control on the bar shows the
agent's logo and one title, cut in the middle past 132 points. The menu has a search field, the
five most likely sessions, a submenu for each project, and a second line with the worktree, the
branch and the session's goal. It has "Needs you" and "Working" badges. Rows that start a new
session come last (`docs/session-starts-2026-10-25.md`).

Three things are missing, all read in code:

- No view shows why a destination was chosen. The rule is computed and logged
  (`[send] target … focus=…`) and nothing draws it.
- The bar has no "not sure" state. `docs/session-detection-exploration-2026-10-08.md` set "not
  sure must stay a possible answer" as a constraint. The bar has only "Choose a session", for when
  no session is running.
- A Reply card shows the agent's logo and no session, and its bar has no destination control. When
  Reply would go to the wrong session, nothing on the bar changes it.

### Correcting, confirming and recovering

A miss takes a click on the destination control and a click on a row. By keys it takes Tab to the
control, Space, typing and Return.

After the send, the card says "Sending to" the session for 3 seconds with a Don't send button
(`docs/send-grace-2026-10-10.md`), then "Sent to". The 3 seconds is `ui.sendGraceSeconds`, a
setting. After it, nothing takes a send back.

The line Vignette puts in the session names the image and no session or project. Pete chose a short
line on 2026-09-25 and left the rest to the skill (`docs/request-line-2026-09-25.md`).

### What broke when herdr moved to herdr-core

Vignette reads herdr through the old `herdr` command. Pete's sessions now live in herdr-core
terminals, which that command does not see. Run on 2026-11-11, `herdr pane list` and
`herdr tab list` answered 5 old panes and tabs, with no agent on any pane.

- Rules 3 and 4 above never apply. Pete approved a rebuild on `herdr-app status` on 2026-11-11,
  and it is under way.
- A menu row's title is the herdr tab's label, and the session's own name only when there is none
  (`SessionMenu.titleParts`). No session has a tab label now, so every row, and the card's
  "Sending to" line, shows the title the agent wrote. A count on 2026-10-23 found the tab label fit
  the control's width for 23 of 31 sessions and the session's own name for 12 (measured once).
  Read in code and in the commands' output. Not checked on screen.
- `SessionStarts` runs `herdr tab create` through the old command, and the old herdr server is
  still running. So a session started from the menu opens in a tab Pete cannot see. Read in code,
  not run.

### How many sessions there are

The snapshot found 29 live agent sessions, all Claude Code. By herdr-core's labels 7 were
coordinators, 21 were delegates that a coordinator had started, and 1 was neither. Codex threads
are not terminals and are not in this count.

By the last part of their folder, 4 of the 29 share a name. The menu groups a worktree under its
repository, and by that grouping 27 of the 29 sit under a header they share with another session
(the reviewer's count, from the same snapshot). So the header separates almost nothing, and the
title carries the whole job.

The menu was decided on 2026-10-22 and 2026-10-23. A count on 2026-10-23 found 31 live sessions,
and another that day listed 28 inboxes. Those were counted another way than the snapshot's 29
terminals, so the three are not compared here.

The snapshot could not say whether Pete sends mostly to coordinators. Of the 122 scored sends, 79
went to Codex threads and 36 to Claude Code sessions that have ended. Only 7 went to a session
still live.

## The experience to aim for

Each moment says what Pete would see and do.

1. The first glance. He opens a screenshot. The bar already shows where it will go, by the name he
   knows that conversation by. He recognises it without reading it. When Vignette is not sure, the
   bar looks different, and it is plain that it is asking.
2. A miss. One action reaches the session he meant. He does not open a menu for a session he sent
   to today.
3. A run of sends. He chooses once, and the rest are a keystroke each. This is the kept pick,
   built.
4. A send that went wrong. One action on the card stops it or moves it, for as long as the agent
   has not read it.
5. Thirty sessions. Sessions he never talks to do not crowd the list. Two sessions in one project
   differ by what they are doing, in words he would use.
6. A Codex thread is as easy to find, to name and to judge as a Claude Code session.

## Working backwards

`docs/session-experience-working-backwards-2026-11-11.md` takes each moment above and says what
Vignette must know, where it could come from, and what is known, with the status of every claim.
It also lists what was tried and dropped for the guess, and what cannot be done. The directions
below rest on it.

## The directions

They are not ranked. Each says why, what it costs, and what must be settled first.

1. Restore the names. Read each session's sidebar name from herdr-core, beside the focus rebuild
   that is already under way, and move session starts to herdr-core. Why: the menu, the bar and
   the card's "Sending to" line were designed around that name, and 27 of 29 sessions share a
   header with another. Cost: a second reader. Starting a session through herdr-core changes how a
   session starts, so it is a separate decision. Works for herdr users.
2. Make a miss cost one action. Why: when the choice was wrong, row 1 held the session 31 times in
   37. Cost: either a key on the destination control, which adds nothing to the bar, or sessions
   on the bar, which reopens the paused redesign and Pete's condition on it. Settle first: score
   it on sends made after the kept pick, since both use recent sends.
3. Say "not sure". Why: rule 5 has been right 0 times in 6, which is thin, and nothing else in
   the log yet separates a good guess from a bad one. Cost: a new state on the bar, with Return,
   Cmd+Return and the settle-once rule to answer. Needs mocked variants, and a signal to trigger
   it beyond rule 5.
4. Stop a wrong send for longer. Why: a waiting line is a file Vignette can delete. Cost: a new
   state for the request, a notice on the card and a rule for the race with the monitor, for a
   busy Claude Code session; unknown for Codex. A longer grace is a one-number experiment that
   needs no design.
5. Bring Codex threads level. Why: they take most of the sends. Cost: listing time, which the
   kept list can hide, and 0.13 to 0.17 s for a badge.
6. Put delegates under their coordinator. Why: 21 of 29 live sessions are delegates. Settle first:
   whether Pete sends to delegates, from the role logged with each pick.

## What to measure from now on

- The role of the session, with each `[send] picked` line. The pick is logged in Pete's build
  since 2026-11-11 22:58; the role is not.
- The rows the menu showed, as session ids, when a pick is made from it.
- The destination a live ink note starts on. A sent note's session is already in
  `[send] prepared`.
- The time from the bar settling to the send can be estimated from lines that exist.

These are ids, rule names and times, and none holds a title, an address or a message. The shadow
log of October was removed on 2026-11-02. `docs/live-ink-release-plan-2026-10-24.md` gives the
reasons it could not ship: nothing gated it, it read `~/.claude/file-history`, and it ran text
recognition on each capture. A new measure has to be one that can ship.

## Limits

- The scorings are one person on one Mac. Most of the misses fall on a few days.
- The scoring of 2026-11-11 was made before the kept pick, and its last day had no herdr focus. Its
  rates describe Send as it was, not as it is.
- The snapshot is one moment. Its `hc get` answers were not saved, so its roles cannot be rebuilt
  from the saved file alone. Its `PREREG.md` gives its own time as 22:58, and the file was written
  at 22:48, a minute before the snapshot. One terminal named a coordinator has no role label and
  counts as neither.
- The menu replay cannot be rerun, and its "31 of 37" predates the kept pick.
- Every "read in code" line may differ from what the app does. Each names what to run.

## What the review changed

The first draft ranked "likely sessions on the bar" first and proposed "the session typed into
last" as a new signal. The review showed that the second was scored on 2026-09-24 and lost, and
that the first rested on a session count that was wrong, a figure that included sends the guess
already got right, and a design Pete had paused with a condition. The draft also gave four wrong
numbers, called four things impossible that the code or docs answer, left out Codex threads, and
described the kept pick as not yet built. All of these are corrected above, and the directions are
no longer ranked.

A second pass confirmed those corrections and most of the new figures, and found nine more points. The
main three: the app Pete came from does not separate good guesses from bad once the one long run
is set aside; the herdr outage touched 6 sends and is not one of the largest causes; and taking
back a waiting line costs more than deleting a file. Those are corrected above too.
