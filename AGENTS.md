# Working on Shotnote

Shotnote is meant to be modified. This file is the onboarding for a person or an agent.

## Layout

- `Sources/` Swift menu bar app. `AppDelegate.swift` wires everything; `Config.swift` holds the actions.
- `~/.config/shotnote/settings.json` holds per-machine settings (`Settings.swift` defines the keys).
  Its `ui` section (`UITweaks`) is every layout, style, timing, and backdrop number; nothing visual
  is hard-coded elsewhere. `open shotnote://tweaks` edits them live.
  Editing the file is a supported way to change settings; the app reloads it within a second.
  It is the user's real config: never test against it. `SHOTNOTE_SETTINGS=<path>` in the
  environment (`open -g --env SHOTNOTE_SETTINGS=/tmp/x/settings.json <app>`) points a launch at
  another file, and the launch line names it. A file that does not parse is moved to
  `settings.json.invalid` and replaced with defaults; bad numbers are clamped in memory and each
  one logged as `[settings] warning clamped`. `appleOriginal` in the file records Apple's
  screencapture values before Shotnote changed them; `open -g shotnote://restore-apple-defaults`
  puts them back.
- `web/` React + tldraw editor page. `web/src/config.ts` holds the editor knobs.
- `Sources/Bridge.swift` and `web/src/bridge.ts` mirror each other. They are the entire
  contract between Swift and the page. Change both or neither.
- `scripts/build.sh` builds web, regenerates the Xcode project, builds the app.
  `scripts/run.sh` does that and relaunches. `scripts/build.sh --test` also runs the unit tests
  in `Tests/` (the `ShotnoteTests` target compiles `Sources/` itself; it never launches the app).

## The loop

1. Change code.
2. `./scripts/run.sh`
3. Drive the app: `open -g shotnote://annotate` (or `copy`, `trash`, `last`, `recent`, `state`;
   `open -g shotnote://help` logs every command). Plain `open` activates Shotnote; `-g` does not.
   Every command ends with one `[<cmd>] ok <detail>` or `[<cmd>] error <code> <detail>` line; the
   codes are the `CommandError` cases in `Commands.swift`. `file=` must point inside the watch
   folder, and `eval`, `show-editor`, and `tweaks` are refused, unless settings.json has
   `"debug": true`. `[annotate] loaded <ms>` reports when the page has the image.
4. Look: `screencapture -x /tmp/s.png`, then crop the corner with `sips` and read the PNG.
   Send keys with `osascript -e 'tell application "System Events" to key code 36 using command down'`
   (Cmd+Enter finishes annotating, key code 53 is Esc). The recent stack takes key focus, so
   `keystroke "a" using command down` after `open shotnote://recent` selects all.
   For the global hotkey, the sweep gesture, or drag-out, System Events is not enough: use
   `scripts/input.sh` (CGEvent; `hotkey double-rshift`, `hotkey cmd+shift+6`, `click X Y`,
   `drag`, `scroll`, `tap`, `key`; run it with no arguments for the list). It compiles
   `scripts/input.swift` with `Sources/HotKeySpec.swift` on first use, so it reads the same hotkey
   strings as settings.json. It posts events only because the terminal it runs from is trusted for
   Accessibility. Its coordinates are global Core Graphics points: top-left of the main display,
   y down, so the Studio Display above it has negative y. `shotnote://state` still prints card
   frames with a bottom-left origin and the screen height; convert with y = height - y.
   Never send Escape that way to close the stack: if the stack is not key, the keystroke reaches
   the frontmost app, and in a terminal running an agent that is the interrupt key. Use
   `open shotnote://dismiss` instead. `open shotnote://state` logs each card's frame so a script
   can aim at circles and images. `scripts/input.sh pasteboard` prints the pasteboard's item count and types.
   Inside the editor page, `open 'shotnote://eval?<javascript>'` runs the code (async, `window.editor`
   is the tldraw editor) and logs the returned value.
5. Read `~/Library/Logs/Shotnote.log`. Every action, URL command, watcher event, web message,
   and error lands there with a `[tag]`. `open -g shotnote://state` dumps current state.
   `[app] ready pid=… build=… port=… watching=…` marks the end of launch: after it every command
   answers. `[web] ready` follows on its own once the editor page is up; `copy-annotated` and
   `eval` answer `error page-not-ready` before it, `annotate` queues one deep. `build` is
   `git describe` of the checkout, stamped by build.sh.

A fake screenshot for testing: `screencapture -x -R 200,200,900,560 "<watch folder>/Screenshot test.png"`.
Delete test files afterwards; the watch folder is the user's real screenshot folder.

## Rules that are not obvious from the code

- tldraw is licensed, not open source. Without a license key the SDK treats any `http:` origin
  as a development environment and shows the editor with a "Get a license for production"
  watermark; on `file://` or a custom scheme it hides the editor five seconds after mount.
  `LocalServer.swift` serves `web/dist` on 127.0.0.1 to give the page that http origin. Do not
  switch to file:// or a custom scheme. The license reserves development environments for
  internal use, so the app ships only with a key: `App.tsx` passes `VITE_TLDRAW_LICENSE_KEY`
  from the build environment as the `licenseKey` prop, and the Hobby key waits until the repo
  is public (docs/foundation-review-2026-09-15.md, step 1).
- The tldraw watermark stays, whatever it says. The license forbids interfering with license
  key enforcement, and `LICENSE-tldraw.md` must ship verbatim in the bundle (project.yml).
- The recent-stack shortcut is either a Carbon hotkey (`HotKey.swift`, no permission needed)
  or a modifier double tap (`ModifierTap.swift`, `"double-rshift"`), which needs the app trusted
  for Accessibility because it watches key events with NSEvent monitors.
- Apple's Cmd+Shift+3/4/5 still capture. The app only watches the folder. Do not register
  those hotkeys.
- Preload the web view at launch; the annotator must open instantly.
- The backdrop's progressive blur is a stack of masked NSVisualEffectViews with different radii.
  The private CAFilter variableBlur ignores its mask when the backdrop renders in the window
  server on macOS 15 (verified: uniform blur), and a bare CABackdropLayer renders black. Do not retry.
- The status item has an autosave name and a seeded preferred position. Without it, a crowded
  menu bar on a notch Mac puts the new icon under the notch and it never appears.
- Files named `*-annotated.png` are outputs and are ignored by the watcher. `Stitch *.png`
  outputs are not ignored on purpose: they show up as a fresh thumbnail.
- The stack panel is non-activating but can become key (`ThumbnailPanel.acceptsKeys`). Never
  call `NSApp.activate` for it; the user's app must stay frontmost. While a card is in the
  annotator the panel gives up key status so typing reaches the editor.
- "Click outside" detection goes through `OutsideClick`. A plain global mouse monitor also
  reports clicks on this app's own floating windows (verified: a click inside the annotator
  closed it), so the topmost window under the cursor is checked first.
- The annotator window is borderless and sized exactly to the image. Its toolbar is a native
  panel (`AnnotatorToolbar.swift`) placed under the window, never inside the page: the page
  sends its tool and color list in the `ready` message, reports the active tool, and takes
  `setTool`/`setColor`/`finish` calls. Keyboard shortcuts inside the editor (tool keys, undo,
  delete, Esc, Cmd+Enter) live in `Hotkeys` in `App.tsx`, because tldraw's own shortcuts are part
  of the UI that `hideUi` removes. `ExpandPanel` carries a card between its stack slot and that frame, and the
  annotator loads the image while hidden (`prepare`) so it can appear the moment the card lands
  (`show`). A swap runs two of these at once. The stack keeps a dashed placeholder in the slot.
- Annotations in progress are drafts held in the page's memory, keyed by file path. A swap, Esc,
  or Done parks the current image's draft; loading that image again restores it. Parking also
  renders a preview that the stack shows on the card and in the fly-back, so the annotator hides
  only after the page reports the park (`AnnotationController.hide(then:)`). Drafts die with
  the app; they are never written to disk. Trashing a file forgets its draft. "Copy Annotated"
  renders selected drafts through the live editor (`window.shotnote.export`) and falls back to the
  original file for cards without one.
- Exports do not use tldraw's `toImage`. In WKWebView an SVG that embeds the screenshot
  rasterizes blank (WebKit loads the inner raster image asynchronously; tldraw only sleeps
  250ms for browsers it detects as Safari, which WKWebView is not). `render()` in `App.tsx`
  draws the screenshot on a canvas and layers tldraw's SVG of the annotations alone on top.
- Swift language mode is 5 (see `project.yml`). No sandbox: the app reads the user's folder.
  Builds are signed with the Developer ID certificate on this Mac, not ad-hoc: Accessibility
  trust is tied to the signature, and an ad-hoc signature changes on every build.
- Settings changes push to Apple's `com.apple.screencapture` defaults (location, show-thumbnail,
  disable-shadow, type). Only keys that changed are written, and never on first run.

## Adding things

- An action: add a `ShotAction` to `Config.actions` and a method on the `Actions` protocol. Its
  `placement` decides whether it is a hover button on a card, a button in the selection bar, or
  both; `key` gives it a shortcut inside the recent stack. It is a `shotnote://<id>` URL either
  way. Actions always receive a list of screenshots, oldest first.
- An editor tool or color: edit `web/src/config.ts`. A tool needs an SF Symbol name for the
  native toolbar; a color needs the hex the swatch shows.
- A new message across the bridge: add it to both bridge files, then handle it in
  `AnnotationController` and `App.tsx`.
