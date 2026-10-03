# Drive it from the terminal

## Commands

Every action is a URL. `open -g` leaves your terminal in front, and plain `open` activates
Vignette. Without `?file=` an action acts on the newest file it can take: `annotate` passes over a
newer recording, and `open` over newer screenshots. `file=` repeats for several. A file the action
cannot take, such as a recording given to `annotate`, answers `unsupported-type`. Percent-encode
every path. A path must be inside the watch folder, unless `debug` is on. `add` is the exception: it
copies an image in from anywhere.

```
open -g vignette://copy                       # copy to clipboard
open -g vignette://annotate                   # open the annotator
open -g vignette://copy-annotated             # copy with the drawing rendered in, if there is one
open -g vignette://paths                      # copy the path as text
open -g vignette://open                       # open the newest recording in the app that plays movies
open -g "vignette://trash?file=~/Dropbox/Screenshots/x.png"
open -g "vignette://stitch?file=~/Dropbox/Screenshots/a.png&file=~/Dropbox/Screenshots/b.png"
open -g vignette://last                       # show the thumbnail for the newest screenshot
open -g "vignette://add?file=/tmp/agent/x.png" # copy an image in from anywhere and show its thumbnail; &annotate opens the editor
open -g "vignette://add?file=/tmp/agent/x.png&agent=claude"  # the same, with a tab naming the agent
open -g "vignette://add?file=/tmp/agent/x.png&agent=claude&session=$CLAUDE_CODE_SESSION_ID"  # the same, and Reply on the card goes back to that Claude Code session
open -g "vignette://add?file=/tmp/agent/x.png&marks=/tmp/agent/marks.json"  # the same, with the agent's drawing on it
open -g vignette://recent                     # toggle the recent stack (same as the shortcut)
open -g vignette://dismiss                    # close the thumbnail or the stack
open -g vignette://cancel                     # close the annotator without copying, as Esc would
open -g "vignette://state?tag=t1"             # one [state] {json} line in the log, tag echoed
open -g vignette://help                       # list every command in the log
open -g vignette://settings                   # open the Settings window
open -g vignette://install-skill              # install the Vignette plugin for Claude Code and Codex
open -g vignette://requests                   # list the open screenshot requests; &clear=<id or all> clears them
open -g vignette://restore-apple-defaults     # put Apple's screencapture defaults back
open -g vignette://tweaks                     # live UI tweaks panel (needs "debug": true)
open -g vignette://intro-lab                  # the Intro Lab, for the intro into the menu bar icon (needs "debug": true)
```

`copy-annotated` answers with `files=["<absolute path>", ...]`, followed by how many had drawings.
The JSON array keeps selection order. A card without a drawing returns its original path. Each
rendering is a new `<name>-<result-id>-annotated.png` beside its source, kept until the person
deletes it. Decode the returned paths; a long source name may be shortened.

Done and Copy Drawing in the editor log the same `files=` field after the rendering finishes.
The PNG, TIFF and file URL on the clipboard all refer to that result.

## Marks

An agent can push annotations with the image. `marks=` takes the path to a JSON file, or the JSON
itself, with one object per mark. Every number is a fraction of the image, so a mark does not depend
on its pixel size:

```json
[{"type": "ellipse", "x": 0.12, "y": 0.30, "w": 0.20, "h": 0.10},
 {"type": "arrow", "x": 0.5, "y": 0.5, "x2": 0.7, "y2": 0.6},
 {"type": "text", "x": 0.1, "y": 0.8, "w": 0.5, "text": "Header should not scroll"}]
```

The types are `ellipse`, `rectangle`, `arrow`, and `text`. The toolbar has no ellipse button, and
an agent can push one anyway. `ellipse` and `rectangle` take `x`, `y`, `w`, `h`. `arrow` takes
`x`, `y`, `x2`, `y2`. `text` takes `x`, `y`, `text`, and an optional `w`, the box the words wrap in. Without
`w` the box runs from `x` to the right edge. Every mark is moved inside the image, and a mark with
nothing inside it is dropped. Text is sized for the image, and a box that would run off the bottom
is widened first. Text too long to fit is cut off at the edge and logged as
`[marks] text too long for <name>`, and [pushed-text-2026-09-19.md](pushed-text-2026-09-19.md) has
the numbers.

Every agent's mark is drawn in the agent colour, indigo, so the person can tell it from their own. A
`color` field is accepted and ignored, with one `[marks] color ignored for <name>` line. Pushed marks join
the image's drawing before the card appears, so the card and Copy Drawing show them, and the editor
can move, retype, or delete them. A push to the image open in the editor joins its drawing as one
undo step.

## The log

Every command answers with one line in `~/Library/Logs/Vignette.log`:
`[<command>] ok <detail>` or `[<command>] error <code> <detail>`. With `debug` on, Open Log in the
menu bar opens it. The codes are fixed:
`unknown-command`, `missing-file`, `outside-watch-folder`, `not-enough-files`, `unreadable-image`,
`debug-disabled`, `no-apple-original`, `write-failed`, `unsupported-type`, `invalid-marks`,
`no-agent`, `send-failed`, `reply-refused`. The log has one event per line,
`HH:mm:ss.SSS [tag] key=value …`, and rotates to `Vignette.log.1` at 5 MB.

## Input events

`scripts/input.sh` posts real input events for clicks, drags, and the shortcut itself. It needs the
terminal trusted for Accessibility. Its coordinates, and every frame in the `[state]` line, are
global points with the origin at the top-left of the primary display, y down.
