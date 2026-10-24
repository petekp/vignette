# The agent session menu: names, repository headers and send order (2026-10-18)

The agent session menu lists the destinations a drawing can go to. It appears in two places: under
the editor toolbar's destination control, and under live ink's note. Both are built from one
function, `SessionMenu.menu` (`Sources/SessionMenu.swift`). This note says what each row says, how
rows are grouped and in what order. It describes what is built, and "Why the menu needs this" says
why.

**What is built.** A row's title is the name of the herdr tab the session runs in, else the
session's own name. Its second line says where the session works and what it is for. A badge says
when it needs the person or is working. Rows sit under a header that names their repository.
Sessions with no repository sit last, under "Other folders". Rows are ordered by when the person
last sent to each session, within the last 4 hours, then by when the agent last worked. The menu
shows 5 rows. When more sessions are active, one submenu per project follows them.

Terms used below:

- **Destination choice:** the session Vignette selects before the person picks one
  (`docs/glossary.md`). It was wrong when the person sent to a different session.
- **The responder:** the `claude` process Vignette runs to answer live ink notes, listed first in
  live ink's menu as "Claude, on the screen". It is not an agent session.
- **herdr:** a terminal host that runs agent sessions in panes and tabs.
- **Worktree:** a second working folder git makes for one repository. **Main checkout:** the
  repository's original folder.

## Why the menu needs this

The goal is that a person sees where a drawing will go, and corrects it, in about a second.
`docs/session-detection-exploration-2026-10-08.md` found that guessing the destination is near its
limit, so the menu is where reliability now comes from.

- **Today, rows lead with the folder name.** That is `AgentDestination.project`: the last part of
  the session's folder, or the agent client's name when there is no folder. The session's name is a
  subtitle on macOS 14.4 and later.
- **Folder names collide.** On Pete's Mac on 2026-10-18, 11 live Claude Code sessions had 7 folder
  names. One folder held 3 sessions and two held 2 each.
- **Branch and checkout do not tell them apart.** Every session in each of those groups was on the
  same branch in the same checkout. The session's name told all of them apart, and so did the herdr
  tab label.
- **A worktree's folder does not name its repository.** A Claude Code worktree reads
  `live-ink-app`. 32 of the 50 newest Codex threads run in `~/.codex/worktrees/<name>/<repo>`,
  whose last part looks like the main checkout.
- **Live ink's menu shows less.** Before macOS 14.4 it shows no session name, since it has no
  tooltip fallback. Live ink's target button has one tooltip for every session.
- **A session Pete renamed shows Claude Code's own title.** `ClaudeCodeConnection.transcript(tail:)`
  reads only `ai-title` entries, never `custom-title`.

## What a row says

```
vignette
  ✓ Row format F                 Needs you
    Show each session by its tab label
    menu build
    session-menu
inbox
    reply esc                    Working
    Close the ledger for September
Other folders
    tethering
    ~/Code · Mac Wi-Fi to iPhone tethering
```

The names above are made up.

- **Title: the herdr tab's label,** without a leading "<repository>:" (any case), else the session's
  own name. Pete already names his tabs in herdr, so the label is the name he knows a session by.
  The label fit the destination control for 23 of 31 live sessions on 2026-10-23. The session's name
  fit for 12. The session's own name is a Claude Code transcript's last `custom-title`, which the
  person chose, else its last `ai-title`, which Claude Code writes. A Codex thread's name is its own
  name, else its first message (`CodexConnection.name(of:)`). `AgentDestination.name` keeps the
  session's own name, so request records and log lines do not change.
- **Second line,** parts joined by " · ", each part once (the same text in another case counts as
  the same):
  1. the worktree's folder name, when the session is in a worktree. For a worktree Codex made under
     `~/.codex/worktrees`, "Codex worktree", since that folder's name is the repository's;
  2. the branch, only when it is not the repository's default;
  3. the session's goal, from the inbox mod; with no goal, the session's name when it differs from
     the title.

  For a folder with no repository, the path from home comes first: `~/Code`, or `~` for home. The
  goal does not change between turns, which keeps a row steady. A row has no age, since rows are
  already in order of use.
- **Badge.** "Needs you" when the inbox mod has an open question for the session, else "Working"
  while the agent reports a turn in progress (`SessionTurn.busy`), else none. `SessionTurn.waiting`
  means a drawing is still unread in the session's inbox, and is not shown, because a bare
  "Waiting" would read as the agent waiting for the person.
- **A row with no herdr tab and no goal** shows the session's name as its title. Its second line
  is the worktree, subfolder, branch and how long ago the session was used. Codex threads have no
  herdr tab or goal today, so they read this way.
- **Equal titles in one group** take a suffix in parentheses: the first of the herdr tab, the
  worktree and the branch that every one of them has and no two share. If none tells them apart,
  "#1", "#2" by when the sessions started: the creation time of the inbox's `session` file for
  Claude Code, and the thread's `createdAt` for Codex.
- **Tooltips.** The tooltip of a row, of the destination control and of live ink's target button
  is the title, the second line, then the repository or the path from home. Before macOS 14.4 an
  item has no subtitle, so the tooltip is where the second line is. Do not use an attributed title:
  AppKit's header says that on macOS 14 an item with one does not show its subtitle.
- **The inbox mod's data.** The goal and the open questions come from the inbox mod's own file,
  `~/.claude/plugins/store/inbox_inline-<hash>.json` (`InboxModStore`). That file is private to the
  mod and the mod is being renamed, so one reader finds it by its name's start, reads it in the
  listing job, and treats a missing or changed file as no goal and no badge. The first failure is
  logged once. A test launch reads only its scratch home's copy.

## Groups

**A row's header names its repository.** The header is the main checkout's folder name as it is on
disk, such as `evercars-backend`. It is never the remote's name: `circuit-v1`'s remote is
`circuit`, and two clones stay two groups.

**How a session finds its repository and branch.** This runs in the listing job, off the main
thread, and reads files only. It never runs `/usr/bin/git`, which raises the install dialog for
Apple's developer tools on a Mac without them, as `/usr/bin/python3` does.

1. Make the folder's path canonical (`URLResourceValues.canonicalPath`), so a case variant such as
   `~/Code/Vignette` finds the folder on disk.
2. Walk up to the nearest `.git`, checking every folder below the home folder, but not the home
   folder itself.
   - A `.git` folder is a main checkout.
   - A `.git` file names a gitdir. Its `commondir` names the main repository's git folder. Both can
     be relative paths, resolved from the file's folder and from the gitdir.
   - A submodule needs nothing special: the nearest `.git` wins.
3. If the folder is gone, walk up from its nearest folder that exists. If that finds nothing, read
   the repository from the path's shape: `~/.codex/worktrees/<any name>/<repo>/…`,
   `…/worktrees/<repo>/<name>`, `<repo>/.worktrees/<name>` or `<repo>/.claude/worktrees/<name>`.
4. Codex only, when step 3 found nothing: the last part of `gitInfo.originUrl`, without `.git`. 19
   of the 20 listed threads whose folder was gone still carried one.
5. A name found in steps 3 or 4 joins the group whose main checkout has that name, when exactly
   one does. Otherwise it makes a group of its own.
6. Otherwise the session has no repository and goes in Other folders. That covers a folder with no
   `.git` (such as `~/Code`), a folder that is gone with nothing to go on, and a session with no
   folder.
7. The branch is the `HEAD` file in the session's own gitdir; a worktree has its own. The default
   branch is the target of `refs/remotes/origin/HEAD` in the main repository's git folder, else
   `main`, else `master`. A detached `HEAD`, or no match, shows no branch.

The session's own folder decides, never the transcript's `cwd`, which follows the shell. Claude
Code's sessions are read again at every listing, so a branch change or a `git init` shows at the
next open. Codex's last list is kept (`CodexConnection.keepsList`) and shown until the fresh list
arrives, about 0.1 s later, so a Codex row can be one listing old in that time.

**Every group has a header,** even a group of one. The header is the only place a row's repository is written. The fixed headers "Send to" and "Send to a
session" go: macOS 14's section headers are flat, so a header over headers reads as an empty group.
In live ink's menu a separator already sets the responder apart.

**Two repositories with one folder name** add their parent folder to both headers, such as
`ever/foo` and `Code/foo`. Other folders cannot collide with a repository, because its rows show
paths from home.

**With no sessions** the menu has no header and no session rows; live ink's menu still lists the
responder. With one session, it shows under its header.

## Order

**Sessions the person sent to in the last 4 hours come first, newest send first. The rest follow
by when the agent last worked** (`AgentDestination.lastUsed`, today's only order).

1. Rank every listed session that way. A Claude Code session is listed while its plugin's monitor
   runs. A Codex thread is listed when it is among the 5 most recently used (`AppServer.listLimit`)
   and was used in the last 24 hours (`AgentDestination.isActive`). So a Codex thread sent to an
   hour ago is missing when 5 others were used since.
2. Keep the first 5. When the destination is not among them, it takes the fifth row.
3. Group those 5 rows. Groups come in the order of their first row, and Other folders comes last.
4. When any active session is not among the 5, a separator and one submenu per project follow the
   rows. A submenu is titled with its project's header and shows the number of its sessions as a
   badge. It lists every active session of that project, the top 5 included, in rank order, with the
   destination's check mark, so a row reads the same in either place. The submenus come in the
   headers' order, then any project with no row in the 5, in rank order, and Other folders last. A
   project with one session still gets a submenu. With every active session in the 5, there are none.
5. The grouped five feed both the menu's items and live ink's Tab order: the responder first, then
   the rows from top to bottom. Tab does not step through the submenu.
6. Build the menu once per opening. A list that arrives late changes the next opening.

**The destination is not pinned to the top.** The destination control already names it, and the
menu shows it with a checkmark where its rank puts it.

**Send history.** For each session, the time its newest drawing was handed to it. Vignette has that
in its request records (`ScreenshotRequests.sendHistory`), so the order is known before any agent
client answers. `SessionListing` puts it on each session as `lastSent`. A send cancelled in its
grace period must not count, but a cancelled request and a request cleared later both end as
`cleared`. So the record has `handedOver`, the time its line was handed over, and send history
reads that field. Older records have none. `/clear` and `/resume` give a process a new session id, which starts with no history.

**Why this order.** This order puts the chosen session in row 1 for 96 of 125 sends, against
78 under today's order. A replay of the person's sends from 2026-09-29 to 2026-10-18 rebuilt each
moment from the request records and the session-context log, and asked where the chosen session
would have been. A second replay, written separately, agreed to within 2 sends.

| Order | Chosen session in row 1 | In rows 1 or 2 |
|---|---|---|
| When the agent last worked (today) | 78 | 99 |
| When the person last sent, any time | 94 | 108 |
| When the person last sent, in the last 4 hours, then when the agent last worked | 96 | 112 |

- **Where the destination choice was wrong** (37 of the 125 sends), the chosen session was in row 1
  for 15 under today's order and 31 under this one.
- **The window matters for new sessions.** 15 sends went to a session never sent to before. With no
  window, old sends pushed those to a median of row 5. With 4 hours, row 2. 4 hours and 24 hours
  differed by 2 sends in 125.
- **Send order is steadier.** Of 95 pairs of sends less than 30 minutes apart, the first 5 rows
  stayed the same in 69 when sessions were ordered by last send with no window, and in 56 under
  today's order. The 4-hour order was not measured. Its sessions not sent to in the window are
  still ordered by when the agent last worked, so that part can move while an agent works.
- **Choosing before grouping matters.** Grouping every listed session and then keeping 5 put the
  chosen session in the first 5 for 89 to 90% of sends under this order, and 78 to 79%
  under today's, against 94% when 5 are chosen first. A repository with many sessions filled the
  menu.
- **Pinning the destination to row 1 costs the most.** Where the destination choice was wrong, the
  chosen session was in row 1 for 30 sends with a 24-hour window, and for none with the
  destination pinned.

For Send, the destination choice does not use send history, so these gains are not circular. It
comes from the agent app in front, then herdr's focused pane, then the session used last. A live
ink note starts on the session the note before it was sent to. The replay scored Send only.

## Search

Both menus open with a search field as their first row, which has the keyboard. It is an item whose
view holds an `NSSearchField` (`SessionMenuSearch`), so the menu is still an `NSMenu`. Typing replaces
the rows below it with the sessions that match, from every project, under their project headers, in
the usual order (`SessionMenu.matching`). With the field empty the menu is the top 5 and the project
submenus.

- **A session matches** when every word typed is found, ignoring case and accents, in its title, its
  second line or its project's header.
- **Return** picks the first match. **Down** moves into the matches.
- **Esc closes the menu**, whether the field holds text or not. `NSMenu`'s tracking takes Esc before
  the field's editor and before a local key monitor, so Esc cannot clear the field there. The
  field's clear button does.
- **No match** shows one disabled row, "No session matches".
- **Live ink's Tab order** is unchanged.

## Outside the menu

- **The destination control and live ink's target button** show the agent's logo and the row's
  title, cut in the middle at their current widths. Their tooltip is the title, the second line,
  then the repository or the path from home. Before this, the toolbar's tooltip said the name and
  the agent client, and live ink's was the same for every session.
- **The sent card** names the row's header: the repository, the path from home in Other folders, or
  the agent client's name for a session with no folder (`SessionMenu.sentLabel`). That holds for
  every headline in `docs/voice.md`'s send table that names a place: "Sending to", "Sent to",
  "Queued for", "Check" and "Done in". The label is taken when Send is pressed and kept on the
  notice, so every headline names the same thing. It is the repository's folder name; two
  repositories with one folder name are told apart in the menu's headers only.
- **`AgentDestination.detail` stays.** The `[send]` log lines, the `project` field of the JSON
  `annotate` answer, and matching a session again after `/clear` read it. `project` stays as the
  fallback label. Live ink's answer row (`Mark.answerer`) and the `sending to` line of the
  `live-ink-ask` and `annotate` answers read `project`; this note does not change what they say.

## Where the data comes from

**Claude Code**, in the listing job that already reads the transcript's last 256 KB:

- name: `custom-title`, then `ai-title`;
- repository, worktree, subfolder and branch: the session's folder, through the steps above;
- when the agent last worked: the last user or assistant entry's timestamp, as now. A live session
  with no such entry sorts last today, and so is the first cut. Use the modification time of its
  inbox's `session` file instead;
- state: `ClaudeCodeConnection.turn(of:)`, from the plugin's turn file.

Parsing the tail took at most 1.23 ms per session on Pete's Mac.

**Codex**, from the `thread/list` call Vignette already makes:

- name: as now;
- repository: the thread's `cwd`, through the steps above, then `gitInfo.originUrl`;
- branch: the checkout's own `HEAD`. `gitInfo.branch` is the branch when the thread was recorded:
  909 of 2,064 stored branches no longer matched the checkout;
- start time: `createdAt`, which the call returns and Vignette drops now;
- when it was last used: `recencyAt`;
- no state for now. `thread/turns/list` takes 0.13 to 0.17 s for five threads, after the menu is
  built. Codex has hooks, but whether the Codex app runs a plugin's hooks is untested, and the
  plugin's hooks today are Claude Code's and do nothing in Codex.

**herdr**, for any session in a herdr pane: the tab's label from `herdr tab list`, about 5 ms, run
beside the `herdr pane list` Send already reads. It is used only to tell apart two rows with the
same title.

## The data model

Each agent client's listing code fills plain optional fields on `AgentDestination`: `place`
(`Place`: a repository with its worktree and subfolder, a folder, or none), `branch`, `hostLabel`
(the herdr tab's label), `started`, `turn`, `goal`, `needsYou`, `hasOwnName` and `lastSent`.
`SessionPlaces` finds the place from files. `SessionMenu` turns the sessions on offer into rows and
groups, and it is pure, so adding an agent client means filling the fields, with no change to the
menus. `SessionMenuItems.swift` turns rows into `NSMenuItem`s for both menus.

This design leaves out a layer that records where each fact came from and how fresh it is, because
every field here has one fixed source per agent client. That layer becomes worth building when a
slow source has to change rows after the menu is built, such as the author search: a search of
the files each session edited for the text under the ink, which guesses the session a drawing is
about (question 9 of the session-detection note).

## Two smaller fixes in the same menus

- **Live ink's menu falls back to the responder without saying so.** When the session picked from
  the menu has ended by the time it is applied, `pickTarget` falls back to "Claude, on the screen".
  It should carry the destination, as the toolbar's menu does, so the send says the session ended.
- **Live ink's note can show an old copy of a hand-picked destination.** `DestinationChoice.start`
  returns the session stored with the pick, not the list's record of the same id, so its folder and
  time can be stale. It should return the list's record. The toolbar already uses the fresh record
  (`Model.answered`).

## How to build it, and how to tell if it helps

The data was built first (`custom-title`, the repository and branch steps, the herdr tab label,
`handedOver`), then the rows, the order and the sent card, which were built in one change because
they read one builder.

A throwaway script over the live inboxes on 2026-10-23 found no two equal titles in one group among
28 sessions. 48 places resolved in 124 ms in one process, cold start included.

To see whether it helps, `send-context.jsonl` (`SendContext.menu`) records a `menu` event each time
a menu closes: the surface ("bar" or "note"), the number of picks, how long after the bar or note
opened the last pick came, and whether it came from the keyboard. Counts and times only, no ids.
That log is removed before live ink reaches main, so these fields measure this branch only. A
measure that should outlast the merge needs a place of its own.

The baseline: in that log on 2026-10-18, the person changed the destination choice on 35 of 122
sends and 7 of 78 notes. The replay's 37 of 125 counts the same thing over its own set of sends,
which leaves out replies to agents. The share may rise if clearer rows show wrong choices that
used to go unnoticed. A rise of that kind means the rows work.

## What this does not fix

Many wrong destination choices for Send look like the rule for when the Codex app was in front. Of
the 37 wrong choices, 23 offered a session missing from the replayed list for a drawing sent to a
Claude Code session. 18 of those 23 are confirmed Codex threads, and 14 offered the same thread.
The log does not record whether the Codex app was in front, so this is likely, not proven. This order puts the chosen session in row 1 for 22 of the 23.

The session-detection note proposes a narrow rule for this case ("The plan"). It is not built, and
it waits for a second scoring on 2026-11-01. It uses send history, so if it ships, the destination
choice uses send history too, and the replay here must be run again.

## Decisions

1. **The destination control shows the row's title.** Pete chose the tab label as the title on
   2026-10-23, so the control, the menu and the tooltip say the same thing.
2. **The herdr tab label is the title.** It is the name Pete already uses in herdr, it fit the
   control for 23 of 31 live sessions against 12 for the session's name, and it does not change
   between turns. Without herdr, or for a Codex thread, the session's name is the title.
3. **The sent card names the row's header.** Cards are seen more widely than the menu.
4. **State reported by the plugin itself is later.** "Needs you" comes from the inbox mod, and
   "Working" from the plugin's turn file. A state the plugin would report itself needs a plugin
   version change, and Codex's hooks are untested in the Codex app.
5. **One submenu per project follows the 5 rows.** Pete chose "top 5, then the rest in one
   submenu" on 2026-10-22. On 2026-10-23 he asked for the rest to be sorted by project instead of
   one list, and chose a submenu per project.
6. **Sessions in a folder that only holds worktrees stay under Other folders.**

## Considered and left out

- **The folder as the title, with a suffix:** 7 of 11 rows needed one, and the destination control
  would have had to grow into the message field.
- **The branch before the name:** it told apart none of the groups that share a folder.
- **The last prompt in the row:** private, long, and shown on a shared screen.
- **herdr's `terminal_title`:** the program in the pane writes it.
- **The author search in the row:** 2.2 s at the median for editor captures and 4.5 s for live ink
  notes, long after the menu is built.
- **The session a window shows, as a row's label:** for the Codex app it was right for 7 of 26
  sends and 0 of 11 notes.
- **A git subprocess:** about 8 ms per session, against under 1 ms for reading `.git`.
- **Flat rows for groups of one:** two row layouts in one menu of 5 rows.
- **A setting for which parts to show:** the rules above leave nothing to choose.

## Limits of the evidence

- One person on one Mac, over three weeks.
- Codex history has gaps: one thread sent to 5 times has no history file, so Codex positions in the
  replay are approximate.
- Typing straight into a session counts as the agent working, not as a send. Ordering by the last
  thing the person typed or sent might rank better. It was not scored.
- The replays' scripts were in a scratch folder and are not kept.
