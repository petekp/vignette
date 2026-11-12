# Choosing the session: working backwards from each moment (2026-11-11)

<!-- review-gate author: claude-fable-5-2 (Vignette coordinator session fd23d22c) -->

This is the second half of `docs/session-experience-2026-11-11.md`, split out to keep each file
short. That note says where the numbers come from, what "read in code" and "unverified" mean, and
what the six moments are.

## What each moment needs

For each moment: what Vignette must know, where it could come from, and what is known.

### Moment 1, the name he knows, and saying "not sure"

| Needs | Source | Status |
|---|---|---|
| The name in the terminal's sidebar | herdr-core's `where` label on each terminal, matched to a session by its `inbox.session` label | Read with `hc get` on 2026-11-11. All 29 live sessions carried `inbox.session` at 22:49; one had lost it by 22:56. The label is set by Pete's inbox mod. Unverified: a match that needs no mod, such as the terminal's process id against the plugin inbox's folder. The herdr focus rebuild is asked to check this |
| Its colour | herdr-core's `herdr.color` label | The label exists. Unverified: what its values mean |
| A name for someone without herdr | The agent's own title, the project, the branch | Built |
| How sure Vignette is | The rule that made the guess | The rule is known at the pick. In the scoring of 2026-11-11, rule 5 was right 0 times in 6. The app Pete came from does not separate good guesses from bad: herdr's pane was right 5 times in 40 from the browser, but 34 of those 40 are the one run of 2026-11-10, and without it the figure is 5 of 6 |

A "not sure" state has open questions that the design must answer. Return must still never send
to a session Vignette picked. Cmd+Return needs something to do when the bar commits to no session.
The destination must still settle once and not change under the pointer.

### Moment 2, a miss that costs less than a menu

| Needs | Source | Status |
|---|---|---|
| The session he meant, one action away | The menu's own order: sent to in the last 4 hours, then used last | The menu replay: for the 37 sends in 125 where the destination choice was wrong, the session Pete chose was row 1 for 31. Not checked since. The kept pick now uses the same recent-send signal, so the gain left after it is unknown |
| A way to reach row 1 without the menu | A key that moves the destination control to the next likely session, as Tab already does on the live ink note; or the likely sessions shown on the bar | Both are designs, and the second has history, below |

Showing sessions on the bar was designed with Pete on 2026-09-24 and paused
(`docs/annotator-redesign-2026-09-24.md`). The five sessions used last were tabs. Pete tied tabs to
moving the tools to a rail on the left: "if we did that i'd want to go with the sessions as tabs
treatment." He rejected the session's name on the Send button. What was built that day was "a
target beside Send rather than tabs".

The bar's width is the limit. `docs/session-menu-2026-10-18.md` dropped a longer title because the
control "would have had to grow into the message field". Two more controls of 132 points fit only
if the tools leave the bar, which is the paused redesign. Names cut at 132 points under one
repository header are also harder to tell apart than one.

Keys have limits too. Cmd+1 to Cmd+3 are free in the editor, but the bar's panel takes the keys
when it has a message field, and Tab already moves between the marks and the bar's controls.

### Moment 4, stopping or moving a wrong send

| Needs | Source | Status |
|---|---|---|
| The line not yet read by a busy Claude Code session | The plugin's monitor prints a waiting line only between turns. Until then it is a file Vignette wrote in the session's inbox folder | Read in code (`agent-plugin/plugins/vignette/scripts/inbox.sh`). Vignette can delete the file. The monitor polls every 0.3 s, so a delete races the read once the turn ends. Not run. Today the send counts as accepted once the line is in the inbox (`docs/rules/send.md`) and the card says "Sent to", so taking it back needs a new state for the request, a notice on the card and a rule for that race |
| A Codex message not yet taken | `codex queue` stores it until an engine takes it | Unverified: whether a queued message can be removed |
| A longer window for every send | `ui.sendGraceSeconds` | A setting today. Trying 5 or 10 seconds is a one-number change |
| The wrong agent told to ignore it | A second line to that session | Possible today: it is another send. Its wording is a choice |
| The agent noticing by itself | A line in the skill: ask before acting on a picture that is plainly about other work | The skill is Vignette's own. No evidence that agents would notice. Naming the session in the request line is a different idea and cuts against Pete's 2026-09-25 choice of a short line |

Once a session has read a line it is part of the conversation. Nothing Vignette does removes it.

How much a wrong send costs is not measured. No send in the scoring of 2026-11-11 was cancelled.

### Moment 5, thirty sessions

| Needs | Source | Status |
|---|---|---|
| Which sessions are delegates | herdr-core: a delegate's terminal has a `parent` | Read on 2026-11-11: 21 delegates, each with a coordinator as parent. `fleet.role` is set by Pete's own scripts, so only `parent` is general |
| The same for someone without herdr | Claude Code's own subagents are not sessions and are never listed | Nothing to do |
| What a session is doing | The inbox mod's goal, on the menu's second line; herdr-core's `inbox.focus` | Built for the goal |
| Whether Pete sends to delegates at all | Each pick, logged with the session's role | The pick is logged in Pete's build since 2026-11-11 22:58 (`[send] picked`). The role is not |

Putting delegates under their coordinator is safe only if Pete rarely sends to them. That is not
known.

### Moment 6, Codex threads

79 of the 122 scored sends went to Codex threads. Most of what the menu shows comes from sources
only Claude Code has: herdr's tab, the inbox mod's goal and badge, the transcript.

| Needs | Source | Status |
|---|---|---|
| More than five threads | The list is kept between openings, so a longer one could be fetched after the bar is up and used next time. `thread/list` with a search term answered in about 2 ms when asked with `useStateDbOnly` | Measured once (`docs/codex-discovery-2026-09-21.md`). Listing 15 took 0.42 to 0.74 s. `docs/session-starts-2026-10-25.md` lists "threads older than a day" as a follow-up |
| A "Working" badge | `thread/turns/list` gives working or idle, 0.13 to 0.17 s for five threads | Measured once (`docs/session-menu-2026-10-18.md`). Left out then for its time, not because Codex lacks it |
| A goal | Nothing | Codex has none |

### The guess itself

These were tried and dropped, and are not proposed again.

- A folder read from what the screenshot shows. 1 of 20 captures gave one, and in 44 of 55 sends
  no session worked in the folder found (measured once). Live ink does read a page's address; the
  address rarely leads to a session.
- A dev server's session, text matching, and a small model as the decider
  (`docs/session-detection-exploration-2026-10-08.md`).
- The session the person wrote to last. "Prompted last" was right 39 times in 53 against 42 for
  "used last" (`docs/session-auto-select-2026-09-24.md`, measured once). By entry type alone a
  transcript does not tell Pete's typing from Vignette's own request lines or a coordinator's
  messages. Vignette's lines can be told by their "From Vignette:" text, and leaving them out
  would be a new scoring. With them in, the signal mostly repeats "sent to last", which the kept
  pick now uses.
- A Codex offer giving way to the Claude Code session sent to last. Pete declined it on
  2026-11-02.
- An agent saying the next screenshot is its own (`vignette://expect`). Considered and left out on
  2026-09-24, because "it covers only the case where the agent asks". A card an agent pushes
  already gets Reply, and 91 of the 224 sends in the 2026-11-11 log were Replies.

Both large runs of misses had one shape. The window in front showed one thing, and the drawing was
for a conversation about something else. No reading of the window finds that conversation. The
kept pick is the answer to that shape that is built. Whether the guess has more to give after the
kept pick and the focus rebuild is not known until both have run for a while.

## What cannot be done

- Taking back a line a session has read.
- A goal for a Codex thread.
- herdr's focus when the Herdr app's window is closed. `herdr-app status` answers only while the
  window process runs. Unverified: whether it answers while the app is behind another app.
- For someone without herdr: the sidebar name, the colour and delegates. Starting a session
  without herdr is proposed in `docs/session-starts-2026-10-25.md` and not built.
