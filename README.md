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
                        │ Copy / Annotate / Delete
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
  In selection mode clicking a card toggles it.
- Drag a card out to drop it as a file on a chat window, Finder, or a terminal. A selected card
  drags the whole selection.
- Cmd+C copies the selection as files, paths as text, and the first image's pixels, so chat apps
  attach all of them and terminals paste the paths. Option+Cmd+C copies only the paths.
- Cmd+S stitches the selection into one tall image with numbered badges, saved next to the
  originals and copied.
- Arrows move focus, Shift extends, Space toggles, Cmd+A selects all, Return annotates,
  Cmd+Delete trashes, Esc clears then dismisses.
- A card with a pencil badge has a draft: annotations you parked with Esc or a swap. Reopen it
  and they are back; Copy Annotated renders them without opening the editor.

The hotkey is either a key combination (no permission needed) or `double-rshift`, a double tap
of right Shift, which needs Shotnote trusted for Accessibility (System Settings → Privacy &
Security → Accessibility); the app asks the first time. Hold the key, or the second tap, and the
newest screenshot lifts out of the stack into the annotator: capture, tap-tap-hold, draw. The
menu bar has the same command.

## Make it yours

- `~/.config/shotnote/settings.json`: folder, counts, timing, hotkey, backdrop. No rebuild.
- `Sources/Config.swift`: the actions list.
- `web/src/config.ts`: editor tools, default tool, colors, stroke size.
- `web/src/bridge.ts` and `Sources/Bridge.swift`: the only contract between the two sides.

See `AGENTS.md` for the working loop.

## Drive it from the terminal

Every action is a URL. Use `open -g` so the terminal keeps focus (plain `open` activates
Shotnote). Without `?file=`, an action acts on the newest screenshot. Repeat `file=` for several.
Paths must be percent-encoded and inside the watch folder.

```
open -g shotnote://copy                       # copy to clipboard
open -g shotnote://annotate                   # open the annotator
open -g shotnote://copy-annotated             # copy with the draft rendered in, if there is one
open -g shotnote://paths                      # copy the path as text
open -g "shotnote://trash?file=~/Dropbox/Screenshots/x.png"
open -g "shotnote://stitch?file=/a.png&file=/b.png"
open -g shotnote://last                       # show the thumbnail for the newest screenshot
open -g shotnote://recent                     # toggle the recent stack (same as the hotkey)
open -g shotnote://dismiss                    # close the thumbnail or the stack
open -g shotnote://cancel                     # close the annotator without exporting, as Esc would
open -g "shotnote://state?tag=t1"             # one [state] {json} line in the log, tag echoed
open -g shotnote://help                       # list every command in the log
open -g shotnote://settings                   # open the Settings window
open -g shotnote://restore-apple-defaults     # put Apple's screencapture defaults back
open -g shotnote://tweaks                     # live UI tweaks panel (needs "debug": true)
open -g shotnote://show-editor                # the editor window without an image (needs "debug": true)
open -g "shotnote://eval?return%201%2B1"      # JavaScript in the editor page (needs "debug": true)
```

Every command answers with one line in `~/Library/Logs/Shotnote.log` (menu bar → Open Log):
`[<command>] ok <detail>` or `[<command>] error <code> <detail>`. The codes are fixed:
`unknown-command`, `missing-file`, `outside-watch-folder`, `not-enough-files`,
`unreadable-image`, `page-not-ready`, `export-timeout`, `export-failed`, `settings-invalid`,
`debug-disabled`, `no-apple-original`, `eval-failed`, `write-failed`. The log has one event per
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
  "ui": { "cardMaxWidth": 208, "slideInDuration": 0.75, "backdropBlurRadius": 13, "...": "the design numbers" },
  "appleOriginal": { "location": "~/Desktop", "showThumbnail": true, "disableShadow": false, "type": "png" }
}
```

The folder is one setting for two things: where Cmd+Shift+3/4/5 saves and what Shotnote watches.
`appleThumbnail`, `windowShadow`, and `format` are Apple's own screenshot defaults; Shotnote writes
them for you. On first run the file mirrors what macOS is already doing, so nothing changes until
you edit it; `appleOriginal` records those first values, and `restore-apple-defaults` puts them
back. `launchAtLogin` adds Shotnote to your login items. `quickAnnotate` makes Done copy the
annotated image and close the annotator and the stack at once, instead of returning to the stack.
`copyOnCapture` puts every new screenshot on the clipboard as it lands (the image, plus its file
URL and path for apps that take those), and is on by default. `annotateOnCapture` opens every new
screenshot in the annotator right away, instead of showing a thumbnail. The menu bar toggles both.
`debug` unlocks `eval`, `show-editor`,
`tweaks`, and `file=` outside the watch folder. A file that does not parse is moved aside as
`settings.json.invalid` and replaced with defaults, with a toast saying so.

The `ui` section holds the design numbers: card sizes, corners, shadows, hover buttons, animation
durations and curves, backdrop blur and tint, annotator window limits. The defaults are the tuned
UI, so a fresh install looks the same. With `debug` on, menu bar → Tweak UI… (or
`open -g shotnote://tweaks`) opens a floating panel of sliders that edits them live, with buttons
to summon the thumbnail, stack, toast, and annotator while you tweak. `"ui": {"motion": 0}` turns
every animation off; the system's Reduce Motion does the same.

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
