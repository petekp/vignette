# Shotnote

A macOS screenshot companion you can reshape. Apple's Cmd+Shift+3/4/5 still take the
screenshot. Shotnote watches the save folder and handles everything after: a floating
thumbnail, a recent-screenshots stack, and a tldraw annotator that copies the result to
your clipboard.

## How it works

```
Cmd+Shift+4  ──►  ~/Dropbox/Screenshots/Screenshot ….png
                        │
                        ▼  ScreenshotWatcher (DispatchSource on the folder)
                  ThumbnailController  ── bottom-right panel: fresh shot, or recent stack
                        │ Copy / Draw / Delete
                        ▼
                  AnnotationController ── window hosting web/ (tldraw) via LocalServer
                        │ "done" message with PNG
                        ▼
                  Clipboard + "<name>-annotated.png" next to the original
```

- `Sources/` is the Swift shell: menu bar item, folder watcher, panels, clipboard, hotkey, drafts.
- `web/` is the editor page: React + tldraw, built with Vite into `web/dist`, bundled into the app.
- `Sources/LocalServer.swift` serves `web/dist` and the screenshot being annotated on 127.0.0.1,
  behind a per-launch token. tldraw only runs unlicensed on http origins; `file://` and custom
  schemes make it hide the editor after five seconds, and the image has to share the page's
  origin for the export canvas to stay untainted.
- `web/src/bridge.ts` and `Sources/Bridge.swift` are the whole contract between the two sides.
  The page reports a protocol version in `ready`; a stale page is refused with a log line and a
  toast instead of failing quietly.
- Annotations in progress are drafts the app keeps on disk (`~/Library/Application Support/
  com.petepetrash.shotnote/drafts/`), so they survive relaunches and a crashed web process.

## Build and run

```
./scripts/run.sh          # builds web, regenerates the Xcode project, builds, relaunches
./scripts/build.sh --test # the same build plus the unit tests
```

Requires Xcode, `xcodegen`, and `pnpm` (run `pnpm install` in `web/` once). `web/dist` must
exist before `xcodegen` runs, which is why `build.sh` builds the page first; `Info.plist` is
generated from `project.yml`, so edit that.

### Signing

Without `scripts/signing.env` the build is ad-hoc signed and runs. The catch is Accessibility:
the double-tap hotkey needs the app trusted for Accessibility, and macOS ties that grant to the
app's code signature. An ad-hoc signature is a hash of the build, so every rebuild is a new app
to macOS and the grant is lost. A certificate fixes that: the signature's designated requirement
names the certificate, not the build, so trust survives rebuilds (verified with a Developer ID
certificate). Put yours in the gitignored `scripts/signing.env`:

```
CODE_SIGN_IDENTITY="Developer ID Application"
DEVELOPMENT_TEAM=ABCDE12345
```

A self-signed code-signing certificate made in Keychain Access (Certificate Assistant → Create a
Certificate, type Code Signing) works the same way, verified: its designated requirement names the
certificate, and a build rebuilt from changed source kept its Accessibility grant. Leave
`DEVELOPMENT_TEAM` empty for it. Two things to know for that route: `project.yml` turns off
Xcode's debug dylib (`ENABLE_DEBUG_DYLIB`), because the hardened runtime refuses to load it when
the signer has no team ID and the app dies at launch; and macOS keys the Accessibility list by
bundle id, so a second build of the same bundle id with a different signer shows the existing row
as enabled while staying untrusted. Give a fork its own bundle id (see Forking).
The hardened runtime is on so notarizing later needs no code change. The app is not sandboxed: it
writes Apple's screencapture defaults, watches a folder you name, and installs global event monitors.

### tldraw license

tldraw is licensed, not open source. Without a key the editor shows a "Get a license for
production" watermark, which stays. A key goes in as `VITE_TLDRAW_LICENSE_KEY` in the build
environment (`App.tsx` passes it as the `licenseKey` prop). `LICENSE-tldraw.md` ships in the
bundle verbatim, as the license requires.

## The recent stack

Cmd+Shift+6 shows your recent screenshots in the corner (30 by default). The stack takes
keyboard focus without stealing your app's focus. Opening the annotator does activate Shotnote,
and closing it hands focus back to the app you came from.

- Hover a card for a selection circle. Click it, or drag from it down the column, to select.
  In selection mode clicking a card toggles it. Drag into the band at the top or bottom of the
  column and it scrolls on its own, faster the closer to the edge you hold, selecting the cards
  that come past until you leave the band, stop at the end of the column, or let go.
- A selected circle carries the card's place in the selection, counting in the order you picked
  them. That is the order every action receives them; picking a card again puts it last. Cmd+A
  has nobody's order to follow, so it takes the column's: oldest first.
- The selected cards get a control strip to their left: copy, draw, stitch, delete.
  It stays centered between the topmost and the bottommost selected card, and follows the selection.
  Put the cursor on it and it grows to the left to name each button, so the names never cover a
  thumbnail. The row under the cursor is still the button you press. While you are annotating, the
  strip steps out of the annotator's way; the cards stay selected and it comes back when you are done.
- Opening a card in the annotator narrows the stack to make room for it, down to half its width.
  The cards keep their corner; only their size changes, and they come back when the annotator
  closes. The annotator never grows into the width the stack keeps, however far you zoom in.
- A card on its way to the annotator can be turned around. Esc, or clicking another card, sends it
  straight home from wherever it is and the editor never appears. Nothing is lost: nobody could
  draw on an image that was never on screen, and a drawing you parked earlier stays as it was.
- Drag a card out to drop it as a file on a chat window, Finder, or a terminal. A selected card
  drags the whole selection.
- Cmd+C copies the selection as files, paths as text, and the first image's pixels, so chat apps
  attach all of them and terminals paste the paths. Option+Cmd+C copies only the paths.
- Cmd+S stitches the selection into one image with numbered badges, saved next to the originals
  and copied. Two or three pieces stack; more go in a grid, because a very tall image loses more of
  itself when a model resizes it to read it. Each badge is the number the card's circle showed. The
  selected cards fly together into the new card, which takes their place at the bottom of the
  stack, or opens in the annotator when Draw on New Captures is on.
- The newest card has the focus as soon as the stack is up, and the focus follows the mouse: move
  onto a card and keys act on that one. So Space over one card after another builds a selection
  without clicking, and Return opens the card the mouse is on. A key runs on the selection when
  there is one, else on the focused card.
- Arrows move focus, Shift extends in the direction you travel (turning back drops the card it
  added last), Space toggles, Cmd+A selects all, Return opens the card to draw on, Cmd+Shift+C
  copies with the drawing rendered in, Cmd+Delete trashes, Esc clears then dismisses.
- Return on several selected cards, or Draw in the strip, opens them one after another, in
  the order you picked them: each Done sends that card home and opens the next. They stay selected
  the whole time, so Cmd+C or Cmd+S afterwards still takes all of them. Esc, or closing the stack,
  drops the rest of the queue.
- A card whose drawing you parked with Esc or a swap shows it in its thumbnail. That
  thumbnail is a preview PNG in `~/Library/Caches`; if macOS clears the folder, the next launch
  renders it again from the draft. Reopen the card and the drawing is back either way;
  Copy Drawing renders it without opening the editor.
- Reopening a card you have already drawn on starts on the selection tool with the mark you
  drew last already picked up, so a drag or Delete acts on it without a click first.
  A fresh image starts on the rectangle tool.
- Pinch, Cmd+scroll, or Cmd+plus and Cmd+minus zoom the image in the annotator; Cmd+0 fits it
  again. A two-finger double tap, or a double-click with the selection tool, zooms in twice on the
  point you are on and comes home to the fitted size from anywhere above it. A double-click on a
  mark is the editor's, not the zoom's.
- A mark is drawn in red unless red is what it sits on. The editor measures the pixels under each
  mark, when you draw it and when you let go of it, and moves to yellow, light blue, white, or
  violet, whichever is far enough from them.
- A card with a purple badge was pushed in by an agent (`add?agent=<name>`), not captured. Hover
  it to see which one. The name is stored on the file itself, so it survives a rename.

The hotkey is either a key combination (no permission needed) or `double-rshift`, a double tap
of right Shift, which needs Shotnote trusted for Accessibility (System Settings → Privacy &
Security → Accessibility); the app asks the first time. Hold the key, or the second tap, and the
newest screenshot lifts out of the stack into the annotator: capture, tap-tap-hold, draw. The
menu bar has the same command.

## Make it yours

- `~/.config/shotnote/settings.json`: folder, counts, timing, hotkey, backdrop. No rebuild.
- `Sources/Config.swift`: the actions list.
- `web/src/config.ts`: editor tools, the tool each image opens on, the colours a mark may be drawn
  in, stroke size.
- `web/src/bridge.ts` and `Sources/Bridge.swift`: the only contract between the two sides.

See `AGENTS.md` for the working loop.

## Drive it from the terminal

Every action is a URL. Use `open -g` so the terminal keeps focus (plain `open` activates
Shotnote). Without `?file=`, an action acts on the newest screenshot. Repeat `file=` for several.
Paths must be percent-encoded and inside the watch folder, except for `add`, which copies a file in
from anywhere.

```
open -g shotnote://copy                       # copy to clipboard
open -g shotnote://annotate                   # open the annotator
open -g shotnote://copy-annotated             # copy with the draft rendered in, if there is one
open -g shotnote://paths                      # copy the path as text
open -g "shotnote://trash?file=~/Dropbox/Screenshots/x.png"
open -g "shotnote://stitch?file=/a.png&file=/b.png"
open -g shotnote://last                       # show the thumbnail for the newest screenshot
open -g "shotnote://add?file=/tmp/agent/x.png" # copy an image in from anywhere and show its thumbnail; &annotate opens the editor
open -g "shotnote://add?file=/tmp/agent/x.png&agent=claude"  # the same, with a purple badge on the card
open -g "shotnote://add?file=/tmp/agent/x.png&marks=/tmp/agent/marks.json"  # the same, with the agent's drawing on it
open -g shotnote://recent                     # toggle the recent stack (same as the hotkey)
open -g shotnote://dismiss                    # close the thumbnail or the stack
open -g shotnote://cancel                     # close the annotator without exporting, as Esc would
open -g "shotnote://state?tag=t1"             # one [state] {json} line in the log, tag echoed
open -g shotnote://help                       # list every command in the log
open -g shotnote://settings                   # open the Settings window
open -g shotnote://install-skill              # install the agent skill for Claude Code and Codex
open -g shotnote://restore-apple-defaults     # put Apple's screencapture defaults back
open -g "shotnote://send?to=reviewer&text=why%20is%20this%20clipped"  # hand the path to an agent herdr is running (needs "debug": true)
open -g shotnote://tweaks                     # live UI tweaks panel (needs "debug": true)
open -g shotnote://show-editor                # the editor window without an image (needs "debug": true)
open -g "shotnote://eval?return%201%2B1"      # JavaScript in the editor page (needs "debug": true)
```

An agent can push its own annotations with the image. `marks=` takes the path to a JSON file, or
the JSON itself, with one object per mark. Every number is a fraction of the image, so a mark does
not depend on its pixel size:

```json
[{"type": "ellipse", "x": 0.12, "y": 0.30, "w": 0.20, "h": 0.10, "color": "red"},
 {"type": "arrow", "x": 0.5, "y": 0.5, "x2": 0.7, "y2": 0.6},
 {"type": "text", "x": 0.1, "y": 0.8, "text": "Header should not scroll"}]
```

The types are `ellipse`, `rectangle`, `arrow`, and `text`; `ellipse` has no toolbar button, and an
agent can still push one. A mark that names a `color` keeps it — any of `CANDIDATES` in
`web/src/config.ts` — and a mark that names none is coloured from what it covers, like your own. The
marks become a draft before the card appears, so the card shows them, Copy Drawing has them, and
opening the card puts them in the editor to move, retype, or delete like your own. The editor builds
the draft on its own canvas, so a marked push is refused with `page-not-ready` from the moment the
annotator takes an image until it has given it back, and while a Copy Drawing is rendering.

Every command answers with one line in `~/Library/Logs/Shotnote.log` (menu bar → Open Log):
`[<command>] ok <detail>` or `[<command>] error <code> <detail>`. The codes are fixed:
`unknown-command`, `missing-file`, `outside-watch-folder`, `not-enough-files`,
`unreadable-image`, `page-not-ready`, `export-timeout`, `export-failed`, `settings-invalid`,
`debug-disabled`, `no-apple-original`, `eval-failed`, `write-failed`, `unsupported-type`,
`invalid-marks`, `no-agent`, `send-failed`, `not-ours`, `linked-root`. The log has one event per
line, `HH:mm:ss.SSS [tag] key=value …`, and rotates to `Shotnote.log.1` at 5 MB.

For clicks, drags, and the hotkey itself, `scripts/input.sh` posts real input events (it needs
the terminal trusted for Accessibility). Its coordinates, and every frame in the `[state]` line,
are global points with the origin at the top-left of the primary display, y down.

## Settings

`~/.config/shotnote/settings.json` is the source of truth. The Settings window (menu bar → Settings…,
or `open -g shotnote://settings`) edits it; so can you or your agent. The app reloads it within a
second of a save. `SHOTNOTE_SETTINGS=<path>` in the environment points a launch at another file,
which is how tests and agents keep away from the real one.

```json
{
  "screenshotsFolder": "~/Dropbox/Screenshots",
  "syncAppleSaveLocation": true,
  "appleThumbnail": false,
  "windowShadow": false,
  "format": "png",
  "recentCount": 30,
  "recentHotkey": "cmd+shift+6",
  "hideMenuBarIcon": false,
  "launchAtLogin": false,
  "quickAnnotate": false,
  "annotateOnCapture": false,
  "copyOnCapture": true,
  "debug": false,
  "agentSkill": "unasked",
  "ui": { "cardMaxWidth": 208, "slideInDuration": 0.75, "backdropBlurRadius": 13, "...": "the design numbers" },
  "appleOriginal": { "location": "~/Desktop", "showThumbnail": true, "disableShadow": false, "type": "png" }
}
```

The folder is one setting for two things: where Cmd+Shift+3/4/5 saves and what Shotnote watches.
`appleThumbnail`, `windowShadow`, and `format` are Apple's own screenshot defaults; Shotnote writes
them for you. On first run the file mirrors what macOS is already doing, so nothing changes until
you edit it; `appleOriginal` records those first values, and `restore-apple-defaults` puts them
back. `launchAtLogin` adds Shotnote to your login items. `quickAnnotate` is Quick draw: Done
copies the image you drew on and closes the annotator and the stack at once, instead of returning
to the stack. `copyOnCapture` puts every new screenshot on the clipboard as it lands (the image,
plus its file URL and path for apps that take those), and is on by default. `annotateOnCapture` is
Draw on New Captures: it opens every new screenshot in the annotator right away, instead of showing
a thumbnail. The menu bar toggles both.
An image that arrives through `add` skips both: a push from an agent is not a capture.
`agentSkill` is the skill for coding agents: `unasked`, `on`, or `off` (see For agents).
`debug` unlocks `eval`, `show-editor`,
`tweaks`, `send`, and `file=` outside the watch folder. A file that does not parse is moved aside as
`settings.json.invalid` and replaced with defaults, with a toast saying so.

The `ui` section holds the design numbers: card sizes, corners, shadows, hover buttons, animation
durations and curves, how far a card bows and swells on its way to the annotator, how narrow the
stack goes to make room for it and how far it stays from it, how deep the drag-select's edge band is
and how fast it scrolls there, how near an edge of the image a zoom holds that edge, backdrop blur
and tint, annotator window limits. The defaults are the
tuned UI, so a fresh install looks the same. A key the app does not know is ignored and the number
it names takes its default, so a renamed key leaves a dead line you can delete: `zoomEdgeBand`, a
fraction of the picture, is now `zoomEdgeBandPoints`, in points. With `debug` on, menu bar → Tweak UI… (or `open -g
shotnote://tweaks`) opens a floating panel of sliders that edits them live, with buttons to summon
the thumbnail, stack, toast, and annotator while you tweak. `"ui": {"motion": 0}` turns every
animation off; the system's Reduce Motion does the same.

## For agents

The app ships a skill that teaches a coding agent the `shotnote://` contract: push an image with
`add`, draw on it with `marks=`, read `<name>-annotated.png` back. It lives in
`skills/shotnote/SKILL.md`, ships in the bundle, and the app is what installs it, because the app
is the only thing that knows which commands its version has.

On the first launch that finds `~/.claude` or `~/.codex`, Shotnote opens Settings at the Agents
section and asks once. The window comes up without taking the keyboard from what you are doing, the
answer is recorded as `agentSkill` in settings.json, and the question never comes back. Turning the toggle on copies the skill into `~/.claude/skills/shotnote` and
`~/.codex/skills/shotnote`; turning it off removes those copies. A later launch rewrites a copy
that is older than the app. `open -g shotnote://install-skill` does the same from a script.

The installer only ever touches a copy it made. It writes `.shotnote-skill.json` beside the skill
naming the build that wrote it, and anything at that path without one, including a link to your own
copy, is left alone and answered with `not-ours`.

An agent directory whose `skills` is itself a link is skipped whole, with `linked-root`: writing
through the link would put the skill inside whatever that link points at, which on this Mac is a git
repository. Move the skill there by hand if you want it.

## Forking

1. In `project.yml`, change `name`, the target and scheme keys that repeat it, both
   `PRODUCT_BUNDLE_IDENTIFIER` values, and the URL scheme. The log name, status item, drafts
   folder, and hotkey registration follow the bundle id at runtime.
2. Signing: add `scripts/signing.env` with your certificate, or accept ad-hoc and re-grant
   Accessibility after each rebuild if you use the double-tap hotkey.
3. `./scripts/build.sh --test`. It builds `web/dist` before `xcodegen`, so a clone builds
   without any manual step besides `pnpm install`.
4. Drafts live on disk, so relaunching while annotating loses nothing that was parked.
5. Ship only with a tldraw license key of your own (see above).
