# Where Send starts: the capture's windows, the kept pick and the menu's first row (2026-11-21)

This note holds the measurements behind three rules in `docs/rules/annotator-toolbar.md`. The data is
Pete's Vignette log from 11-13 to 11-20. It has 152 scored sends from the editor, and in 38 of them
Send started on a session other than the one he sent to. The scoring is `score.py` in the send-picks
analysis, with the Codex app's own log and the screenshots themselves.

## The Codex app's thread and the capture

Send started on the thread the Codex app showed 20 times, because the Codex app was the app in
front before Vignette. That start was wrong 13 times. A labeller read each screenshot, and two of
the labels were checked by hand. Of the 13 wrong starts:

- 11 captured the inbox mod's panel, which is a Herdr pane. All 11 were sent to Claude Code sessions.
- 1 captured the Codex app itself.
- 1 opened from the stack, with no capture.

The panel shows the inbox of the terminal in its own tab. Herdr's focus names that terminal while
the window still shows the tab. So after this change, those 11 start on Herdr's focus. The log does
not record Herdr's focus when the Codex app's rule won, so whether each of the 11 now starts right
is not measured. The new `capture=` field on `[send] target` will measure it.

Of the 7 right starts, 4 captured web pages on the laptop's display while the Codex app's maximized
window was in front. Those are its built-in browser, and the Codex log shows browser activity on
that thread before 3 of them. These starts do not change. 3 starts may change:

- 2 captured web pages on the external display, where the window in front is not known.
- 1 captured a small crop of terminal text, either Herdr or the Codex app's own terminal.

So the change moves 11 wrong starts to Herdr's focus and puts at most 3 right ones at risk. Starts
made by any other rule do not change, because the Codex app was not in front for them.

## The kept pick

One wrong start came from a kept pick that ended while the editor was open. The image had opened
on the kept session. Pete drew for longer than the pick's 10 minutes, sent it there, and the next
image started elsewhere. When a send renews the pick the image opened on, that start is right. A
replay of the kept pick with that rule changed no other start.

## The menu's first row

In the 38 sends whose start was wrong, the session Pete picked was the first row other than the start
in 17. Most sent to in the last 4 hours gave 18. The last send other than the start gave 12, and
either of the last two gave 22. The menu keeps its order, ranked by recent sends and then last use.
The start no longer takes the first row, so Down then Return picks the most common correction. Herdr's focus and the captured window were not
logged for these sends, so they could not be scored as ranking signals.
