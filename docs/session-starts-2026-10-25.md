# Sending to a Claude Code session that is not running (2026-10-25)

Both session menus, the editor toolbar's and live ink's note's, now offer projects that have no
running Claude Code session. Each such project has two rows. **Continue last session** resumes the
project's most recent session. **New session** starts a fresh one. Sending to either row opens a
tab in the Herdr window, starts `claude` there in the project's folder, waits until the session can receive, and
then delivers the drawing as Send does to a running session.

Terms used below:

- **Inbox:** the folder the Vignette plugin keeps for each running Claude Code process, under
  Application Support (`claude-sessions/<pid>/`). It names the session the process runs. A send
  writes its line there, and the plugin's monitor hands it to the session.
- **Herdr:** the terminal host. herdr-core (`hc`) runs its terminals, and the Herdr app's window
  shows them in spaces, tabs and panes.
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
  a new id when resuming, so a plain resume reuses the original. Pete's transcripts agree: on
  2026-10-26, 11 of his last 400 were written by several Claude Code versions over days, every entry
  under the one session id that names the file.
- `.new(folder:)`: the row's id is `new:<folder>`, stable across listings, so a pick survives a
  later answer. `ScreenshotRequests.send`, where the editor's Send and live ink's note meet, chooses
  the session's UUID and records it as the request's destination. The session starts with
  `claude --session-id <uuid>`, and from then on it is addressed like any other.

The request record keeps `start` (`ScreenshotRequests.Record.start`), so the process starts when
the line is handed over, after the grace period. Don't send during the grace leaves no stray tab.

Starting answers a `SubmissionOutcome`, the same as any send, so the card, the request record and
the log need no second path. `ClaudeCodeConnection.submit(_:to:completion:)`:

1. If a live inbox already holds the session (resumed by hand since it was listed), skips the start.
2. Otherwise runs `HerdrLauncher.start`. It reads the space the Herdr window shows from
   `herdr-app status`, then runs `hc run --bg --json --cwd <folder> --no-parent --label
   herdr.space=<space> --label herdr.tab=tb<32 hex> -- <shell> -lic '"$@"; exec "$0" -li' <shell>
   claude --resume <id>`. Only a UUID and the folder reach the command, each as its own argument.
   The labels put the terminal in a new tab of that space without moving what the window shows. A
   terminal without `herdr.space` would be hidden, so with no window or no space nothing starts.
   `<shell>` is the person's login shell when it is zsh or bash, else `/bin/zsh`. It runs as a
   login, interactive shell, so it reads their startup files and finds `claude` on their `PATH`, and
   it becomes a shell when `claude` exits. A function named `claude` runs; an alias does not, since
   a shell expands aliases only in words it reads, not in `"$@"`.
   The tab is named with the project by `herdr-app do tab.rename`, tried every 0.5 s for up to 5 s
   in the background, since the app renames a tab only once it shows it. A rename that never takes
   logs `[send] tab <id> not named` and is not a failed start.
3. Looks every 0.25 s for up to 45 s (`startTimeout`) for a live inbox holding the session. Each
   look reads only the inbox folders made since the launch, and only their `session` file until one
   names it. The looks are scheduled with `asyncAfter`, so no thread waits through the 45 s.
4. Writes the line into that inbox.

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

- Skip it when the folder is gone. Half the recent projects on Pete's Mac were deleted worktrees.
- Read the transcripts of its last 3 sessions typed in, by the rule a running session's are read
  (`ClaudeCodeConnection.transcript(tail:)`). The one with the latest user or assistant entry is
  Continue's session, and that time is the project's last use. Its row is made as a running
  session's is (`ClaudeCodeConnection.destination`), with `start` set.

The history and each transcript are read again only when their size or modification date changed
(`FileMemo`).

A project that has a running session is left out when the listing joins this list to the running
sessions (`SessionListing.startable(_:beside:)`): one whose inbox `cwd` is the same folder, or whose
last session is now running. The two spell a folder alike: an inbox writes `pwd -P`, and all 123
folders in Pete's history on 2026-10-26 were already physical paths.

On Pete's Mac on 2026-10-25 that gave 16 projects with no session running, 32 rows. The site
project was 14th by last use, so a count cap would have hidden the project that prompted this.

The rows come from their own listing job (`SessionListing`'s `startable`), so the running sessions'
answer, which settles Send's target with herdr's focus, never waits for transcripts to be read. A
listing is complete and fresh by the agent clients alone, since nothing picks one of these rows. Its
last answer is kept and shown until a fresh one comes.

## Where the rows go

- **Both menus get them.** Pete hit this in live ink's note. A screenshot of the same site goes
  through the editor's Send. Both menus are built by `SessionMenu.menu`, so one change serves both.
- **After every running session.** Sending to a startable row starts a process, so it never takes
  one of the five top rows from a session that can receive now (`SessionMenu.ranked`). With five or
  more sessions running, they appear in the project submenus and in search. Continue comes before
  New in each project.
- **Nothing picks one on its own.** The rows travel apart from the running sessions
  (`DestinationChoice.Candidates.startable`, `Answer.startable`), so no pick rule sees them. Only the
  menus join the two lists, and a person's pick in one may land on a row. A Reply to a session that
  has ended is not revived through its Continue row.
- **The bar with nothing running.** Once every client has answered and none has a session, while
  some can be started, the bar shows Copy and an empty target, "Choose a session", with the same
  menu (`ToolbarOffer.choose`). Return copies.
- **A picked row names its project** in the bar's target and the note's target button: "Last
  session in *project*" or "New session in *project*" (`SessionMenu.row(of:among:)`). The menu row
  itself leaves the project to the header above it.
- **Live ink's note** joins the rows to its list where it stores the listing's answer
  (`LiveNotePopover.setSessions`), and a pick goes through `LiveNoteCards.send` as any other.

## What the card says

- During the grace: "Sending to *place*", with Don't send.
- While the session starts and the line waits for its inbox: "Starting in *place*".
- Delivered: "Sent to *place*".
- No Herdr window, no space, or `hc run` refused: "Not sent", "Vignette couldn't open a herdr tab for Claude Code. The log
  has details."
- No inbox after 45 s: "Not sent", "Claude Code didn't open in time. You can send again once it's
  running." The tab stays, and the session may still come up there; the next Send finds it running.

## Test isolation

Rows are offered only when a launcher exists: both the Herdr app and `hc` are found
(`HerdrFocus.appToRun`, `coreToRun`, through `AgentTools.forSessions`). A test launch without
`VIGNETTE_HERDR_APP` and `VIGNETTE_HC` offers none and starts nothing. Vignette never runs `claude`
itself: herdr-core runs the person's login shell, which runs it.
A test launch with `CFFIXED_USER_HOME` reads only the scratch home's history and transcripts.

On 2026-10-26 both rows were sent to in the `vignette-e2e` VM through herdr 0.9.5 itself, with a
stand-in `claude` on the panes' PATH that keeps an inbox, as the plugin's monitor does. Each opened
an unfocused tab in its folder, ran `claude` there once with the right arguments, and got one line.
A stand-in that never came up gave "Not sent" after the 45 s wait. On Pete's history a unit test's
listing took 219 ms on its first call and about 50 ms on later ones, which read only changed
transcripts. It listed 68 rows, more than the app would: the test host most likely reads another
app's inboxes, so projects with a running session were not left out.

The e2e runner has a fake Herdr app and a fake `hc` (`scripts/e2e/fake_herdr.py`,
`App.fake_herdr`). For an `hc run` of `claude` it brings up a plugin inbox for that session.
In `scripts/e2e/session_starts.py`, `send_offers_start` checks the empty target and that nothing starts. `send_starts_session` picks
Continue through the menu's search and checks the terminal's folder, space and resume command, the
tab's name and the line in the inbox.

## Without herdr (proposed, not built)

Write the command to a `.command` file in Application Support and open it with `NSWorkspace`. The
Mac's handler for `.command` files, Terminal unless the person chose another, opens a window in the
folder and runs it. It needs no Automation permission, which AppleScript to Terminal would. Ghostty
and iTerm2 each have their own way to open a window with a command, and they could come later. The
window would take the focus, unlike a Herdr tab started through `hc`.

## Follow-ups

- Match the window the ink was drawn on to a project, so the note starts on the right project's row.
- List Codex threads older than a day, so a thread nobody has open is offered too.
