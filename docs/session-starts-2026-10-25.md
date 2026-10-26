# Sending to a Claude Code session that is not running (2026-10-25)

Both session menus, the editor toolbar's and live ink's note's, now offer projects that have no
running Claude Code session. Each such project has two rows. **Continue last session** resumes the
project's most recent session. **New session** starts a fresh one. Sending to either row opens a
herdr tab in the project's folder, starts `claude` there, waits until the session can receive, and
then delivers the drawing as Send does to a running session.

Terms used below:

- **Inbox:** the folder the Vignette plugin keeps for each running Claude Code process, under
  Application Support (`claude-sessions/<pid>/`). It names the session the process runs. A send
  writes its line there, and the plugin's monitor hands it to the session.
- **herdr:** the terminal host that runs agent sessions in tabs and panes.
- **Startable row:** a menu row whose `AgentDestination.start` is set. It is not running.

## The problem

On 2026-10-25 Pete circled a nit on his website with live ink and found no session for the
project in the note's list. The list shows a Claude Code session only while its process and the
plugin's monitor run. His three past sessions for that project were on disk as transcripts.

## The data shape

A startable row is an `AgentDestination` with `start: SessionStart?` set
(`Sources/SessionStarts.swift`). Nil means the session runs and can receive now.

- `.resume(folder:)`: the row's id and address are the past session's id. `claude --resume <id>`
  keeps that id. The Claude Code binary (2.1.310) documents `--fork-session` as the flag that makes
  a new id when resuming, so a plain resume reuses the original.
- `.new(folder:)`: the row's id is `new:<folder>`, stable across listings, so a pick survives a
  later answer. `AgentDestination.addressed()` mints the session's UUID when Send is pressed, and
  the session starts with `claude --session-id <uuid>`. From then on it is addressed like any other.

The request record keeps `start` (`ScreenshotRequests.Record.start`), so the process starts when
the line is handed over, after the grace period. Don't send during the grace leaves no stray tab.

Starting returns a `SubmissionOutcome`, the same as any send, so the card, the request record and
the log need no second path. `ClaudeCodeConnection.submit`:

1. If a live inbox already holds the session (resumed by hand since it was listed), skips the start.
2. Otherwise runs `HerdrLauncher.start`: `herdr tab create --cwd <folder> --no-focus --label
   <project>`, then `herdr pane run <pane> "'claude' '--resume' '<id>'"`. Only a UUID reaches the
   command, and each word is single-quoted.
3. Polls the inboxes every 0.25 s for up to 45 s (`startTimeout`) until a live one holds the session.
4. Writes the line into that inbox past the usual guard.

The line goes through the inbox rather than as `claude`'s first prompt. That keeps one delivery
path, with today's guarantee: "sent" means the line is in the session's inbox. It also keeps the
line, which holds the person's message, out of the shell's command line and history.

## Which projects

Claude Code's prompt history, `~/.claude/history.jsonl`, is the index. It has one line per prompt
typed in an interactive session, with the folder Claude Code ran in (`project`) and the session id.
Its last 2 MB went back 45 days on Pete's Mac and parse in 13 ms. The transcript folders are not a
usable index: Pete's Mac has 11,606, most from scripted runs. `sessions-index.json` in a project
folder is stale (last written in April for a project used in October).

For each folder typed in within the last 14 days (`StartableSessions.window`):

- Skip it when a running session's inbox `cwd` is the same folder after resolving links.
- Skip it when the folder is gone. Half the recent projects on Pete's Mac were deleted worktrees.
- Read the transcripts of its last 3 sessions typed in, by the rule a running session's are read
  (`ClaudeCodeConnection.transcript(tail:)`). The one with the latest user or assistant entry is
  Continue's session, and that time is the project's last use. A transcript is read once while its
  size and modification date stay the same (`TranscriptMemo`).

On Pete's Mac on 2026-10-25 that gave 16 projects with no session running, 32 rows. The site
project was 14th by last use, so a count cap would have hidden the project that prompted this.

The rows come from their own listing job (`SessionListing`'s `startable`), so the running sessions'
answer, which settles Send's target with herdr's focus, never waits for transcripts to be read. A
listing counts as fresh only once this job has answered too.

## Where the rows go

- **Both menus get them.** Pete hit this in live ink's note. A screenshot of the same site goes
  through the editor's Send. Both menus are built by `SessionMenu.menu`, so one change serves both.
- **After every running session.** Sending to a startable row starts a process, so it never takes
  one of the five top rows from a session that can receive now (`SessionMenu.ranked`). With five or
  more sessions running, they appear in the project submenus and in search. Continue comes before
  New in each project.
- **Nothing picks one on its own.** `DestinationChoice` skips startable rows for Send's pick, for
  the session a note remembers, and for the Codex app's mark. A Reply to a session that has ended is
  not revived through its Continue row (`ToolbarOffer`).
- **The bar with nothing running.** When no session runs and some can be started, the bar shows
  Copy and an empty target, "Choose a session", with the same menu (`ToolbarOffer.choose`). Return
  copies.
- **Live ink's note** needs no change of its own: its list comes from the same listing, and a pick
  goes through `LiveNoteCards.send`, which addresses the destination before sending.

## What the card says

- During the grace: "Sending to *place*", with Don't send.
- While the session starts and the line waits for its inbox: "Starting in *place*".
- Delivered: "Sent to *place*".
- herdr refused the tab: "Not sent", "Vignette couldn't open a herdr tab for Claude Code. The log
  has details."
- No inbox after 45 s: "Not sent", "Claude Code didn't open in time. You can send again once it's
  running." The tab stays, and the session may still come up there; the next Send finds it running.

## Test isolation

Rows are offered only when a launcher exists. The launcher is herdr through
`AgentTools.forSessions("VIGNETTE_HERDR")`, so a test launch without `VIGNETTE_HERDR` offers none
and starts nothing. Vignette never runs `claude` itself: the person's shell in the herdr tab does.
A test launch with `CFFIXED_USER_HOME` reads only the scratch home's history and transcripts.

The e2e runner has a fake herdr (`scripts/e2e/fake_herdr.py`, `App.fake_herdr`). For a `claude`
typed into one of its panes it brings up a plugin inbox for that session. `send_offers_start`
checks the empty target and that nothing starts. `send_starts_session` picks Continue through the
menu's search and checks the tab, the resume command and the line in the inbox.

## Without herdr (proposed, not built)

Write the command to a `.command` file in Application Support and open it with `NSWorkspace`. The
Mac's handler for `.command` files, Terminal unless the person chose another, opens a window in the
folder and runs it. It needs no Automation permission, which AppleScript to Terminal would. Ghostty
and iTerm2 each have their own way to open a window with a command, and they could come later. The
window would take the focus, unlike herdr's `--no-focus` tab.

## Follow-ups

- Match the window the ink was drawn on to a project, so the note starts on the right project's row.
- List Codex threads older than a day, so a thread nobody has open is offered too.
