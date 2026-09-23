# Drive it from the terminal

## Commands

Every action is a URL. `open -g` leaves your terminal in front, and plain `open` activates
Vignette. Without `?file=` an action acts on the newest file it can take: `annotate` passes over a
newer recording, and `open` over newer screenshots. `file=` repeats for several. A file the action
cannot take, such as a recording given to `annotate`, answers `unsupported-type`. Percent-encode
every path. A path must be inside the watch folder, except for `add`, which copies an image in from
anywhere.

```
open -g vignette://copy                       # copy to clipboard
open -g vignette://annotate                   # open the annotator
open -g vignette://copy-annotated             # copy with the drawing rendered in, if there is one
open -g vignette://paths                      # copy the path as text
open -g vignette://open                       # open the newest recording in the app that plays movies
open -g "vignette://trash?file=~/Dropbox/Screenshots/x.png"
open -g "vignette://stitch?file=/a.png&file=/b.png"
open -g vignette://last                       # show the thumbnail for the newest screenshot
open -g "vignette://add?file=/tmp/agent/x.png" # copy an image in from anywhere and show its thumbnail; &annotate opens the editor
open -g "vignette://add?file=/tmp/agent/x.png&agent=claude"  # the same, with a tab naming the agent
open -g "vignette://add?file=/tmp/agent/x.png&marks=/tmp/agent/marks.json"  # the same, with the agent's drawing on it
open -g vignette://recent                     # toggle the recent stack (same as the hotkey)
open -g vignette://dismiss                    # close the thumbnail or the stack
open -g vignette://cancel                     # close the annotator without copying, as Esc would
open -g "vignette://state?tag=t1"             # one [state] {json} line in the log, tag echoed
open -g vignette://help                       # list every command in the log
open -g vignette://settings                   # open the Settings window
open -g vignette://install-skill              # install the agent skill for Claude Code and Codex
open -g vignette://restore-apple-defaults     # put Apple's screencapture defaults back
open -g vignette://tweaks                     # live UI tweaks panel (needs "debug": true)
```

## Marks

An agent can push annotations with the image. `marks=` takes the path to a JSON file, or the JSON
itself, with one object per mark. Every number is a fraction of the image, so a mark does not depend
on its pixel size:

```json
[{"type": "ellipse", "x": 0.12, "y": 0.30, "w": 0.20, "h": 0.10, "color": "red"},
 {"type": "arrow", "x": 0.5, "y": 0.5, "x2": 0.7, "y2": 0.6},
 {"type": "text", "x": 0.1, "y": 0.8, "w": 0.5, "text": "Header should not scroll"}]
```

The types are `ellipse`, `rectangle`, `arrow`, and `text`. The toolbar has no ellipse button, and
an agent can push one anyway. `ellipse` and `rectangle` take `x`, `y`, `w`, `h`. `arrow` takes
`x`, `y`, `x2`, `y2`. `text` takes `x`, `y`, `text`, and an optional `w`, the box the words wrap in. Without
`w` the box runs from `x` to the right edge. Text is sized for the image. A box that would run off
is widened and moved inside. Text too long to fit is cut off at the edge and logged as
`[marks] text too long`, and [pushed-text-2026-09-19.md](pushed-text-2026-09-19.md) has the numbers.

`color` is optional. A mark may name `red`, `yellow`, `light-blue`, `white`, or `violet`, and keeps
it. A mark that names none is coloured from what it covers, like your own marks. Pushed marks join
the image's drawing before the card appears, so the card and Copy Drawing show them, and the editor
can move, retype, or delete them. A push to the image open in the editor joins its drawing as one
undo step.

## The log

Every command answers with one line in `~/Library/Logs/Vignette.log` (menu bar → Open Log):
`[<command>] ok <detail>` or `[<command>] error <code> <detail>`. The codes are fixed:
`unknown-command`, `missing-file`, `outside-watch-folder`, `not-enough-files`, `unreadable-image`,
`settings-invalid`, `debug-disabled`, `no-apple-original`, `write-failed`, `unsupported-type`,
`invalid-marks`, `no-agent`, `send-failed`. The log has one event per line,
`HH:mm:ss.SSS [tag] key=value …`, and rotates to `Vignette.log.1` at 5 MB.

## Input events

`scripts/input.sh` posts real input events for clicks, drags, and the hotkey itself. It needs the
terminal trusted for Accessibility. Its coordinates, and every frame in the `[state]` line, are
global points with the origin at the top-left of the primary display, y down.
