# Drive it from the terminal

## Commands

Every action is a URL. `open -g` leaves your terminal in front, and plain `open` activates Vignette.
Without `?file=` an action acts on the newest file it can take: `annotate` passes over a newer
recording, and `open` over newer screenshots. `file=` repeats for several. A file the action cannot
take, such as a recording given to `annotate`, answers `unsupported-type`. Percent-encode every
path. A path must be inside the screenshots folder, unless `debug` is on. `add` is the exception: it
copies an image in from anywhere.

```
open -g vignette://copy                       # copy to clipboard
open -g vignette://annotate                   # open the annotator
open -g vignette://copy-annotated             # copy with the drawing rendered in, if there is one
open -g vignette://paths                      # copy the path as text
open -g vignette://open                       # open the newest recording in the app that plays movies
open -g "vignette://trash?file=~/Dropbox/Screenshots/x.png"
open -g "vignette://unsend?file=~/Dropbox/Screenshots/x.png"  # cancel a send still in its grace period, as Don't send on its card does: [unsend] ok request=<ids> <name>, or error nothing-to-unsend. Without file= it acts on the newest screenshot
open -g "vignette://stitch?file=~/Dropbox/Screenshots/a.png&file=~/Dropbox/Screenshots/b.png"
open -g vignette://last                       # show the newest screenshot or recording as a lone thumbnail
open -g "vignette://show?file=~/Dropbox/Screenshots/a.png&file=~/Dropbox/Screenshots/b.png&agent=claude&session=$CLAUDE_CODE_SESSION_ID&message=Is%20this%20the%20bug%3F"  # point the user at screenshots already in the folder: the cards come up, or are marked in place, with "From Claude" and the message; &marks=<json> draws on the first one until the user keeps or clears the marks; changes no file
open -g "vignette://add?file=/tmp/agent/x.png" # copy an image in from anywhere and show its thumbnail; &annotate opens the editor
open -g "vignette://add?file=/tmp/agent/x.png&agent=claude"  # the same, with a tab naming the agent
open -g "vignette://add?file=/tmp/agent/x.png&agent=claude&session=$CLAUDE_CODE_SESSION_ID"  # the same, and Reply on the card goes back to that Claude Code session
open -g "vignette://add?file=/tmp/agent/x.png&agent=codex&session=$CODEX_THREAD_ID"  # the same from Codex: Reply goes back to that Codex thread
open -g "vignette://add?file=/tmp/agent/x.png&marks=/tmp/agent/marks.json"  # the same, with the agent's drawing on it
open -g "vignette://add?file=/tmp/agent/x.png&title=Checkout%20at%20390%20px&description=After%20the%20fix"  # the same, with a title above it in the editor
open -g vignette://recent                     # toggle the recent stack (same as the shortcut)
open -g vignette://dismiss                    # close the thumbnail or the stack
open -g vignette://cancel                     # close the annotator without copying, as Esc would
open -g "vignette://state?tag=t1"             # one [state] {json} line in the log, tag echoed
open -g "vignette://state?tag=t1&section=liveInk"   # only app and that section
open -g vignette://help                       # list every command in the log
open -g vignette://settings                   # open the Settings window
open -g vignette://install-skill              # install the Vignette plugin for Claude Code and Codex; &root=<dir> installs into one .claude or .codex folder (needs "debug": true)
open -g vignette://requests                   # list the open screenshot requests; &clear=<id or all> clears them
open -g "vignette://reply?file=<envelope>"    # an agent's reply to a screenshot request; only the skill's reply helper sends it
open -g vignette://restore-apple-defaults     # put Apple's screencapture defaults back
open -g vignette://live-ink-clear             # erase every live ink mark
open -g "vignette://live-ink-stroke?points=100,100;300,120"  # draw a live ink stroke as if by hand (needs "debug": true)
open -g vignette://live-ink-chord-down       # hold the live ink chord down, as if by hand (needs "debug": true)
open -g vignette://live-ink-chord-up         # let go of it: with ink drawn while it was down, the note opens (needs "debug": true)
open -g "vignette://live-ink-ask?message=is%20this%20right"  # ask about the live ink, as Return in its note does (needs "debug": true)
open -g vignette://tweaks                     # live UI tweaks panel (needs "debug": true)
open -g vignette://intro-lab                  # the Intro Lab, for the intro into the menu bar icon (needs "debug": true)
open -g vignette://setup-lab                  # the Setup Lab, to run setup as a new person sees it (needs "debug": true)
open -g vignette://check-lab                  # the Check Lab, for the check on copied and sent cards (needs "debug": true)
```

`add` refuses a file that is not a png, jpg, jpeg or heic, a name ending in `-annotated`, and the
name of an agent reply, with `unsupported-type`. A file already in the screenshots folder is shown
where it is. A push with `agent=` replaces the agent and session an earlier push recorded on it,
so one without `session=` removes the earlier session. Reply on the card needs `agent=claude` or `agent=codex` and a `session=` that is a UUID: a Claude
Code session id or a Codex thread id. Any other `session=` is not recorded, and `[add]` still
answers `ok` with a warning.

`title=` and `description=` say what the image shows. The editor shows the title above the image's
frame, with the description under it in fainter text. The text is white or black, whichever
stands out more from the screen behind it. Each is one line of up to 60
and 140 characters. Longer text is cut at a word with an ellipsis, and `[add]` still answers `ok`,
with a warning naming the part that was cut. The card, a copy, a stitch and a send leave them out.

`copy-annotated` answers with `files=["<absolute path>", ...]`, followed by how many had drawings.
The JSON array keeps selection order. A card without a drawing returns its original path. Each
rendering is a new `<name>-<result-id>-annotated.png` beside its source, kept until the person
deletes it. Parse the array as JSON, since each `/` in it is written as `\/`. A long source name
may be shortened, so use the returned path.

Copy in the editor, and Cmd+C there with nothing selected, log the same `files=` field once the
rendering finishes, as `[annotate] done` and `[annotate] copied`. The PNG, TIFF and file URL on the
clipboard all refer to that result. With nothing drawn, no file is written, and the line says
`nothing drawn, original copied`.

## Marks

An agent can push annotations with the image. `marks=` takes the path to a JSON file, or the JSON
itself, with one object per mark. Every number is a fraction of the image, so a mark does not depend
on its pixel size:

```json
[{"type": "ellipse", "x": 0.12, "y": 0.30, "w": 0.20, "h": 0.10},
 {"type": "arrow", "x": 0.5, "y": 0.5, "x2": 0.7, "y2": 0.6},
 {"type": "text", "x": 0.1, "y": 0.8, "w": 0.5, "text": "Header should not scroll"}]
```

The types are `ellipse`, `rectangle`, `arrow`, and `text`. The toolbar has no ellipse button, and an
agent can push one anyway. `ellipse` and `rectangle` take `x`, `y`, `w`, `h`. `arrow` takes `x`,
`y`, `x2`, `y2`. `text` takes `x`, `y`, `text`, and an optional `w`, the box the words wrap in.
Without `w`, the words wrap as a person's note does: at 18 times the text's size (`noteMaxWidth`),
about a quarter of the image's width, or sooner at the image's right edge, but never narrower than
15% of the width. Every mark is moved inside the image, and a mark with nothing inside it is
dropped. One push takes at most 100 marks and 256 KB. A file that breaks a rule answers
`invalid-marks`, naming the mark and the field. Text is sized for the image, and a box that would
run off the bottom is widened first. Text too long to fit is cut off at the edge and logged as
`[marks] text too long for <name>`, and [pushed-text-2026-09-19.md](pushed-text-2026-09-19.md) has
the numbers.

Every agent's mark is drawn in the agent colour, indigo, so the person can tell it from their own. A
`color` field is accepted and ignored, with one `[marks] color ignored for <name>` line. Pushed
marks join the image's drawing before the card appears, so the card and Copy Drawing show them, and
the editor can move, retype, or delete them. A push to the image open in the editor joins its
drawing as one undo step.

## The log

Every command answers with one line in `~/Library/Logs/Vignette.log`:
`[<command>] ok <detail>` or `[<command>] error <code> <detail>`. With `debug` on, Open Log in the
menu bar opens it. The codes are fixed:
`unknown-command`, `missing-file`, `outside-watch-folder`, `not-enough-files`, `unreadable-image`,
`debug-disabled`, `no-apple-original`, `write-failed`, `unsupported-type`, `invalid-marks`,
`no-agent`, `send-failed`, `reply-refused`, `live-ink-off`, `invalid-points`, `live-ink-not-asked`, `unknown-section`, `nothing-to-unsend`, `too-many-files`. The log has one event per line,
`HH:mm:ss.SSS [tag] key=value …`, and rotates to `Vignette.log.1` at 5 MB.

`show` answers `[show] ok files=[<names>] agent=<name> session=<id> joined=<n> inColumn=<n> inEditor=<n>
marks=<n> after=<ms> tag=<tag>` once its cards are up. `files=` is a JSON array, since names hold
spaces. While the person's hand is in the corner it first logs `[show] waits for
<press|drag|sweep|swipe|stitch|slide-out>`, and `after=` counts the wait. A shown state that ends
logs `[show] ended <name> by=left|opened|replaced`, and Keep and Clear log `[show] kept marks=<n>
<name>` and `[show] cleared marks=<n> <name>`. `add` of the person's own screenshot in the folder
answers `unsupported-type` and names `show`.

Where Send starts is logged too. `[send] target <address> project=<detail> focus=<why> role=<role> [reply] [capture=<app>:<percent>,…]`
names the session the bar's filled button sends to whenever one of these changes. `focus` is
`showedIt` (the session that showed the image with `show`), `kept`, `app`, `pane`, `tab` or `none` (the session used last). `capture` is there when the image opened
from a capture whose rect Vignette saw: the apps whose windows it showed, by bundle id (or process
name), with each one's share of the points some window covered, the largest first, three at most.
When the app before Vignette was the Codex app and the capture showed another app more, the log
has `[send] came from the Codex app, capture shows <app>: thread not read`, and the Codex app's
thread is not where Send starts.

`role` is the `fleet.role` label of the herdr-core terminal that runs the session. It is the label
when that is 1 to 24 letters, digits and hyphens, and `other` for any other text. A terminal with no
label but a parent terminal, as the ones a coordinator starts have, is `delegate`. It is `none` for
a Codex thread, for a terminal with neither, without Herdr, and until Claude Code's listing answers. The target is
logged again when its role arrives, so the last `target` line before a send has it.

`[send] picked <address> project=<detail> role=<role>` is a pick from the target's menu. The next
line, `[send] menu top=<rows> list=top|project|search [submenu=<n>] [rows=<rows>] picked=<row>
row=<n>`, says where the pick was made:

- `top` holds the menu's first rows, up to five: running sessions, or with none running, the rows
  that start one. A searched row that starts a session is `resume:<id>` or `new` in `rows=` and `picked=`.
- `list=top` means the pick came from those rows, with no search typed.
- `list=project` is the `submenu`-th project submenu, counted from the top.
- `list=search` is the rows a search left.
- `rows` is that list when it is not `top`, and `row` is the picked row's place in it, from 1.
- A row is a session id, `resume:<id>` for Continue last session, or `new` for New session.

`[send] menu request=<id> top=<rows>` follows each `[send] prepared` line of a send from the editor
that has a target menu (not a Reply). `rows` are the menu's first rows as they stood at the send,
named as above, whether or not the menu was opened. A live ink note's send writes no such line.

`[send] ok <id> <name> inbox=<pid> session=<id> line=<file>` names the file a Claude Code send wrote
into the session's inbox. The plugin's monitor prints that file between turns and removes it, and
Vignette looks for that: `[send] handed line=<file> inbox=<pid> after=<ms>` is the time from the
write to the file being gone while the session's Claude Code process still runs. The monitor looks
every 0.3 s, so `after` can be up to 0.3 s past the moment the session could first take the line.
`[send] not handed line=<file> inbox=<pid> after=<ms> reason=inbox-gone|limit` is a file that went
after that process exited, as its inbox was removed, or one still there after an hour.
`[annotate] closed <file> reason=<reason>` is one line for each image the editor leaves without
sending it, before the `[transition]` line of the event. `reason` is `esc`, `window` (Cmd+W, or an
Esc no view took), `bar` (Esc in the message field), `click-outside`, `shortcut` (the shortcut that
opens the stack), `url` (`vignette://cancel`), `unreadable-image`, `done`, `page` (Left or Right),
`another-image` (a card clicked, or Draw on others), `file-removed` and `stack-closed`. Send writes
none, and the editor closing after a send is not a close.

`[send] kept <address> project=<detail>` is a send that set or refreshed the kept pick
(`docs/glossary.md`), and `[send] kept ended <address> reason=time|gone` is its end.
`[state] annotator.keptPick` is the kept pick's `session`, `client` and `secondsLeft`, or null.

`[main] slow inventory <n>ms` is a delivery of the screenshots folder's listing that held the main
thread for more than 8 ms, which costs at least a frame at 120 Hz. Each stack open lists the folder
again, so one of these during an opening is a frame that opening lost.

## Input events

`scripts/input.sh` posts real input events for clicks, drags, and the shortcut itself. It needs the
terminal trusted for Accessibility. Its coordinates, and every frame in the `[state]` line, are
global points with the origin at the top-left of the primary display, y down.
