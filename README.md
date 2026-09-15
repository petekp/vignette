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

- `Sources/` is the Swift shell: menu bar item, folder watcher, panels, clipboard, hotkey.
- `web/` is the editor page: React + tldraw, built with Vite into `web/dist`, bundled into the app.
- `Sources/LocalServer.swift` serves `web/dist` on 127.0.0.1. tldraw only runs unlicensed on http
  origins; file:// and custom schemes make it hide the editor after five seconds.
- `web/src/bridge.ts` is the whole contract between the two sides: `window.shotnote.load(...)`
  and `reset()` inbound, `{type: 'ready' | 'done' | 'cancel' | 'log'}` outbound.

## Build and run

```
./scripts/run.sh      # builds web, regenerates the Xcode project, builds, relaunches
```

Requires Xcode, `xcodegen`, and `pnpm`. The app is unsigned; first launch may need
right-click → Open.

## The recent stack

Cmd+Shift+6 shows your last five screenshots in the corner. The stack takes keyboard focus without
stealing your app's focus.

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

## Make it yours

- `~/.config/shotnote/settings.json`: folder, counts, timing, hotkey, backdrop. No rebuild.
- `Sources/Config.swift`: the actions list.
- `web/src/config.ts`: editor tools, default tool, colors, stroke size.
- `web/src/bridge.ts` and `Sources/Bridge.swift`: the only contract between the two sides.

See `AGENTS.md` for the working loop.

## Drive it from the terminal

Every action is a URL. Without `?file=`, it acts on the newest screenshot. Repeat `file=` for
several. Paths must be percent-encoded.

```
open shotnote://copy                       # copy to clipboard
open shotnote://annotate                   # open the annotator
open "shotnote://trash?file=~/Desktop/x.png"
open "shotnote://stitch?file=/a.png&file=/b.png"
open shotnote://last                       # show the thumbnail for the newest screenshot
open shotnote://recent                     # toggle the recent stack (same as Cmd+Shift+6)
open shotnote://state                      # dump app and page state to the log
open shotnote://settings                   # open the Settings window
open shotnote://tweaks                     # toggle the live UI tweaks panel
open shotnote://show-editor                # open the editor window without an image
```

Everything the app does is appended to `~/Library/Logs/Shotnote.log` (menu bar → Open Log).

## Settings

`~/.config/shotnote/settings.json` is the source of truth. The Settings window (menu bar → Settings…,
or `open shotnote://settings`) edits it; so can you or your agent. The app reloads it on save.

```json
{
  "screenshotsFolder": "~/Dropbox/Screenshots",
  "syncAppleSaveLocation": true,
  "appleThumbnail": false,
  "windowShadow": false,
  "format": "png",
  "recentCount": 5,
  "recentHotkey": "cmd+shift+6",
  "hideMenuBarIcon": false,
  "ui": { "cardMaxWidth": 220, "slideInDuration": 0.4, "backdropBlurRadius": 40, "...": "every layout, style, timing, and backdrop knob" }
}
```

The folder is one setting for two things: where Cmd+Shift+3/4/5 saves and what Shotnote watches.
`appleThumbnail`, `windowShadow`, and `format` are Apple's own screenshot defaults; Shotnote writes
them for you. On first run the file mirrors what macOS is already doing, so nothing changes until
you edit it.

The `ui` section holds every visual and timing constant: card sizes, corners, shadows, hover
buttons, animation durations and curves, backdrop blur and tint, annotator window limits.
Menu bar → Tweak UI… (or `open shotnote://tweaks`) opens a floating panel of sliders that edits
them live, with buttons to summon the thumbnail, stack, toast, and annotator while you tweak.
