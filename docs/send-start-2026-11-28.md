# Where Send starts, a week after the capture rule (2026-11-28)

This note scores where Send started from 2026-11-21 to 2026-11-27, the week after the changes in
`docs/send-start-2026-11-21.md`. It answers three questions. How often was each start rule right? Should a
capture of the Codex app start on its thread when another app is in front? Do the log lines added on 11-21 read
correctly? The data is Pete's Vignette log, from the first launch of a build with those changes (11-21 at 11:01)
to the end of 11-27.

The log holds 227 sends from the editor. 3 were cancelled during the 3-second wait and 85 were Replies, which go
back to the card's own session and so have no start to score. That leaves 139 scored sends. Send started on the
session Pete sent to in 103 of them (74%, 95% interval 66% to 81%). Sends on the same day are alike, so the interval was also computed by resampling
whole days, which gives 66% to 79%; with 7 days that interval is rough.

## Terms

- Agent session: one Claude Code conversation or one Codex thread that Send can deliver a drawing to.
- Herdr: the terminal app where Pete runs his Claude Code sessions, one per pane. Herdr's focus is the pane he
  was last in.
- Coordinator and delegate: a coordinator is a Claude Code session that runs other sessions, its delegates, each
  in its own worktree. The log's `role=` field says which a session is, from labels on its Herdr terminal.
- The inbox mod: a Claude Code mod that keeps the questions each session has for Pete, with a panel in Herdr. One
  coordinator, named inbox, develops it.
- The stack: Vignette's column of recent screenshots in the corner of the screen. An image opened from it, or
  reached by paging to the image beside it in the editor, carries no capture.
- Start: the session the bar's target shows when the editor opens, before Pete touches it. It is right when Pete
  sent to that session.
- Rule: why Send started where it did, logged as `focus=` on `[send] target`. `kept` is the kept pick, `app`
  is the thread the Codex app shows, and `pane` is the Claude Code session in Herdr's focused pane.
- The capture rule: when the Codex app was in front but the capture shows another app's windows more, Send sets
  the Codex app's thread aside (`DestinationChoice.appRuleApplies`). It logs
  `[send] came from the Codex app, capture shows … thread not read`.
- The reverse rule, proposed and not built: when another app is in front but the capture shows the Codex app most,
  start on the thread the Codex app shows.

## How often each rule was right

| Rule | Right | 95% interval |
|---|---|---|
| Codex app's thread (`app`) | 4 of 8 | 22% to 78% |
| Herdr's focus (`pane`) | 71 of 98 | 63% to 80% |
| Kept pick (`kept`) | 27 of 32 | 68% to 93% |
| Session used last (`none`) | 1 of 1 | |

No scored send started on the image's last session or on the session that showed it. Both rules shipped during
the week and started only opens that ended in a Reply or without a send.

The Codex app's thread was right 4 of 8 times. Five of the 8 were captures of the Codex app itself, and 3 opened
with no capture. All 4 wrong starts went to Claude Code sessions: 2 to the inbox mod's coordinator and 2 to the
Vignette coordinator. Three of the 4 were captures whose windows were 100% the Codex app.

Herdr's focus was right 71 of 98 times. It starts most sends, so most wrong starts come from it (27 of
36), though its rate is close to the overall rate. By the app the capture showed most, it was right 34 of 49 times for the
browser, 19 of 28 for Herdr and 16 of 19 for images opened from the stack. Its 27 wrong starts fall into a few groups:

- 8 captures of Herdr went to the inbox mod's coordinator while Herdr's focus was on another coordinator.
- 6 browser captures went to one Codex thread for work. Herdr's focus marks Claude Code sessions only, so it can
  never start on a Codex thread.
- 5 browser captures on 11-27 went to a new Claude Code session in the home folder.
- The other 8 went to other coordinators.

The scoring behind the 11-21 note found Herdr's focus right 79 of 100 times and the Codex app's thread 7 of 20.
Those were other days and other builds.

When the start was wrong, Pete picked the session he wanted from the menu's top five rows in 24 of 36 sends (67%):
the first row in 11, rows 2 to 5 in 13. He used search in 9 (25%, 95% 14% to 41%) and a project submenu in 3. In
the 11-21 scoring, search fixed 4 of 38 wrong starts. This week 5 of the 9 searches were for the inbox mod's
coordinator, 2 for the Vignette coordinator and 2 for the new home-folder session.

Pete quit the ChatGPT app, which is the Codex app, at about 15:32 on 11-27. The Codex app's own log shows it
running again from about 15:56. No send after 15:32 started on the Codex app's thread. The 17 scored sends after
15:32 were right 15 times. The Codex app was in front for one more open, at 16:38, which ended without a send.

## The capture rule never came up

The capture rule's line appears 0 times. The Codex app was in front for 109 opens of the editor. 96 of them had
no capture: images opened from the stack or reached by paging. The other 13 were captures, and in all 13 the Codex app's
windows were the largest part. So no capture showed another app while the Codex app was in front. The 11 starts
that 11-21 note expected to move to Herdr's focus, captures of the inbox mod's panel taken with the Codex app in
front, did not happen this week. Whether the capture rule picks the right session is still not measured.

## The reverse rule would have changed nothing

The reverse rule needs a send whose capture shows the Codex app most while another app was in front. The week has
none. All 13 opens whose capture showed the Codex app most had the Codex app in front, where the Codex app's
thread rule already applies. The `[capture] clues` line, which records every capture from 11-24 on, names 10
captures with the Codex app largest, and each was first opened with the Codex app in front. So the reverse rule would have fixed 0 starts and broken 0.

One of those captures, taken at 23:59 on 11-25, was opened twice more later with another app in front. Both opens
ended without a send. Send reads a capture's windows only on its first opening (`CaptureOrigin.windows(of:)`), so
a reverse rule built on that clue would not have seen these opens either.

The backlog said the reverse rule might fix 3 starts and risk up to 7. Those figures could not be traced to a
measurement. This week's count is 0 and 0.

The week gives no support for the reverse rule either. When the Codex app was in front and the capture showed only
its windows, Pete sent to its thread 2 of 5 times (95% 12% to 77%), and the other 3 to Claude Code coordinators.
That is too few sends to say what a capture of the Codex app means, and all of them had the Codex app in front.

## The log lines added on 11-21

Each line appears in the real log and reads as its code says.

- `role=delegate` appears on 195 lines: 188 Replies to a delegate's card, 4 starts and 3 picks. They name 30
  sessions whose projects are delegates' worktree names. `role=coordinator` appears on 611 lines in 6 projects.
  No session logged both. `role=none` is logged for every Codex thread, for 237 Reply lines that also have an empty
  `project=`, and for 6 other Claude Code lines. Two coordinators show `none` on one such line each, for a
  reason not found.
- `[send] menu request=… top=…` appears once for each of the 139 scored sends, and for none of the 85 Replies.
  Each lists at most 5 rows. The line builds the menu around the session sent to. So after a hand pick it shows the
  menu as it would open now, with the wrong start in row 1 (13 sends). The menu Pete actually opened is in the pick's
  own line, `[send] menu top=… picked=… row=`.
- `[send] handed` appears once for 170 of the 171 Claude Code sends that left the 3-second wait. The other was sent
  2 minutes before the app relaunched, so its check never finished. One of the 170 says `not handed` with
  `reason=limit`. No Codex send has one. The plugin's monitor took a send after a median of 0.2 s; 1 in 10 took
  a minute or more, and the longest took 27 minutes. A Claude Code session takes a send only between turns.
- `[annotate] closed … reason=` appears for none of the 227 opens that ended in a send. It appears exactly once
  for 701 of the 704 opens that did not. The other 3 were open when the app relaunched. The reasons were page 298,
  Esc in the bar's message field 139, another image 100, Done 63, a click outside 52, Esc 34, the stack closing 8, Undo 6 and
  a shortcut 1.

## How this was measured

`score.py` reads a copy of the log taken 2026-11-28 and finds each send: a `[send] prepared` line followed within
1 s by `[transition] sent`. A live ink note is left out. The start is the last `[send] target` line after the
editor's last `prepare(` effect and before the first `[send] picked` line. `score.py` adapts the 11-21 scoring,
whose target pattern could not read 235 lines this week, because of the new `capture=` field and the two new
rules. Every build launched in the window contains both 11-21 changes (67 builds, checked with git). Its plan, written before any start was compared with a send, fixed the unit, the exclusions and the test for
the reverse rule. The log decided every send, so no screenshot was read.

Dropping sends in the first 10 minutes after a launch, which are likeliest to be tests of a new build though the
log cannot tell, gives 88 of 120 (73%). Dropping sends to the Vignette coordinator gives 78 of 107 (73%), and both together 73 of 99 (74%). Each
stays within about a point of the main figure.

## Limits

- One person on one Mac for seven days, with 71 launches of new builds. The Codex app's thread started only 8
  scored sends, so its rate is wide (22% to 78%).
- 26 of the 139 scored sends carry no `capture=` field, so the splits by captured app leave them in a group of
  their own.
- Only opens that ended in a send are scored. A wrong start that made Pete close the editor is not counted, and he
  accepts a start that is close enough. Both make the rates higher than how often the start matched what he wanted.
- The thread the Codex app shows is logged only when the Codex app is in front. A rebuild of it from the Codex app's
  own log matched Vignette's logged thread 59 of 109 times, for a reason not found. No figure here uses it, since
  the reverse rule had no send to replay. A later replay would need Send to log the shown thread on every opening
  while the Codex app runs.

## Recommendation

Do not build the reverse rule. It would have changed no start this week, and the few captures of the Codex app
give it no support. Keep the capture rule and its log line. That case did
not come up, so it is still unmeasured. Herdr's focus starts most sends, so it holds most wrong starts, 27 of the 36. Two
patterns there are worth a look before any new rule: captures of Herdr sent to the inbox mod's coordinator, and
browser captures sent to a Codex thread, which Herdr's focus cannot name.
