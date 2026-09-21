# Drive it from the terminal

Every action is a URL. Use `open -g` so the terminal keeps focus (plain `open` activates
Vignette). Without `?file=`, an action acts on the newest screenshot. Repeat `file=` for several.
Paths must be percent-encoded and inside the watch folder, except for `add`, which copies a file in
from anywhere.

```
open -g vignette://copy                       # copy to clipboard
open -g vignette://annotate                   # open the annotator
open -g vignette://copy-annotated             # copy with the draft rendered in, if there is one
open -g vignette://paths                      # copy the path as text
open -g "vignette://trash?file=~/Dropbox/Screenshots/x.png"
open -g "vignette://stitch?file=/a.png&file=/b.png"
open -g vignette://last                       # show the thumbnail for the newest screenshot
open -g "vignette://add?file=/tmp/agent/x.png" # copy an image in from anywhere and show its thumbnail; &annotate opens the editor
open -g "vignette://add?file=/tmp/agent/x.png&agent=claude"  # the same, with a purple badge on the card
open -g "vignette://add?file=/tmp/agent/x.png&marks=/tmp/agent/marks.json"  # the same, with the agent's drawing on it
open -g vignette://recent                     # toggle the recent stack (same as the hotkey)
open -g vignette://dismiss                    # close the thumbnail or the stack
open -g vignette://cancel                     # close the annotator without exporting, as Esc would
open -g "vignette://state?tag=t1"             # one [state] {json} line in the log, tag echoed
open -g vignette://help                       # list every command in the log
open -g vignette://settings                   # open the Settings window
open -g vignette://install-skill              # install the agent skill for Claude Code and Codex
open -g vignette://restore-apple-defaults     # put Apple's screencapture defaults back
open -g "vignette://send?to=reviewer&text=why%20is%20this%20clipped"  # hand the path to an agent herdr is running (needs "debug": true)
open -g vignette://tweaks                     # live UI tweaks panel (needs "debug": true)
open -g vignette://show-editor                # the editor window without an image (needs "debug": true)
open -g "vignette://eval?return%201%2B1"      # JavaScript in the editor page (needs "debug": true)
```

An agent can push its own annotations with the image. `marks=` takes the path to a JSON file, or
the JSON itself, with one object per mark. Every number is a fraction of the image, so a mark does
not depend on its pixel size:

```json
[{"type": "ellipse", "x": 0.12, "y": 0.30, "w": 0.20, "h": 0.10, "color": "red"},
 {"type": "arrow", "x": 0.5, "y": 0.5, "x2": 0.7, "y2": 0.6},
 {"type": "text", "x": 0.1, "y": 0.8, "w": 0.5, "text": "Header should not scroll"}]
```

The types are `ellipse`, `rectangle`, `arrow`, and `text`; `ellipse` has no toolbar button, and an
agent can still push one. On a text mark `w` is the box the words wrap in, and it is optional: the
default is the room between `x` and the right edge. The text is drawn at a size the image gives it,
so one sentence covers the same part of a 900-pixel crop and a 5120-pixel capture. A box that would
run off the image is widened until the words fit its height and then moved inside, so a long
sentence becomes a wide block rather than a column running off the bottom; one too long to fit even
across the whole picture is left as wide as it goes and named in a `[web] pushed text too long`
line, since the log is the only place that can say so ([pushed-text-2026-09-19.md](pushed-text-2026-09-19.md) has the
numbers). A mark that names a `color` keeps it — any of `CANDIDATES` in `web/src/config.ts`
— and a mark that names none is coloured from what it covers, like your own. The
marks become a draft before the card appears, so the card shows them, Copy Drawing has them, and
opening the card puts them in the editor to move, retype, or delete like your own. The editor builds
the draft on its own canvas, so a marked push is refused with `page-not-ready` from the moment the
annotator takes an image until it has given it back, and while a Copy Drawing is rendering.

Every command answers with one line in `~/Library/Logs/Vignette.log` (menu bar → Open Log):
`[<command>] ok <detail>` or `[<command>] error <code> <detail>`. The codes are fixed:
`unknown-command`, `missing-file`, `outside-watch-folder`, `not-enough-files`,
`unreadable-image`, `page-not-ready`, `export-timeout`, `export-failed`, `settings-invalid`,
`debug-disabled`, `no-apple-original`, `eval-failed`, `write-failed`, `unsupported-type`,
`invalid-marks`, `no-agent`, `send-failed`, `not-ours`, `linked-root`. The log has one event per
line, `HH:mm:ss.SSS [tag] key=value …`, and rotates to `Vignette.log.1` at 5 MB.

For clicks, drags, and the hotkey itself, `scripts/input.sh` posts real input events (it needs
the terminal trusted for Accessibility). Its coordinates, and every frame in the `[state]` line,
are global points with the origin at the top-left of the primary display, y down.
