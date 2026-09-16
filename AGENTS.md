# Working on Shotnote

Shotnote is meant to be modified. This file is the onboarding for a person or an agent.

## Layout

- `Sources/` Swift menu bar app. `AppDelegate.swift` wires everything; `Config.swift` holds the actions.
- `~/.config/shotnote/settings.json` holds per-machine settings (`Settings.swift` defines the keys).
  Its `ui` section (`UITweaks`) holds the layout, style, timing, and backdrop numbers, and its
  defaults are the tuned UI, so a fresh install renders the same. `open -g shotnote://tweaks`
  edits them live (needs `debug`). A few numbers stay in code on purpose: the toolbar's row and
  button sizes (`AnnotatorToolbar.swift`), the card button size (`StackView.swift`), the
  fly-back timing (`TransitionLayer.swift`), and the stitch gap, padding, and badge
  (`Stitch.swift`).
  Editing the file is a supported way to change settings; the app reloads it within a second.
  It is the user's real config: never test against it. The tweak panel writes to whichever file
  the running instance was launched with, and a test launch replaces the user's instance, so copy
  the real file over the scratch copy before a test round and, before relaunching the real build,
  merge back any `ui` keys that changed in the scratch copy (`[settings] wrote ui.…` in the log
  lists them). `SHOTNOTE_SETTINGS=<path>` in the
  environment (`open -g --env SHOTNOTE_SETTINGS=/tmp/x/settings.json <app>`) points a launch at
  another file, and the launch line names it. A file that does not parse is moved to
  `settings.json.invalid` and replaced with defaults; bad numbers are clamped in memory and each
  one logged as `[settings] warning clamped`. `appleOriginal` in the file records Apple's
  screencapture values before Shotnote changed them; `open -g shotnote://restore-apple-defaults`
  puts them back.
- `web/` React + tldraw editor page. `web/src/config.ts` holds the editor knobs.
- `Sources/Bridge.swift` and `web/src/bridge.ts` mirror each other. They are the entire
  contract between Swift and the page. Change both or neither, and bump `bridgeProtocolVersion`
  and `PROTOCOL` together: the page sends its version in `ready`, and a mismatch logs
  `[web] error protocol-mismatch page=… app=…`, toasts, and leaves the page unavailable, so a
  stale `web/dist` is refused rather than silently ignored. Every host->page call is a
  `PageAPI` case rendered to JavaScript; every page->host message is a `WebMessage` case.
- `scripts/build.sh` builds web, regenerates the Xcode project, builds the app.
  `scripts/run.sh` does that, waits for the old process to exit, and relaunches. `scripts/build.sh
  --test` also runs the unit tests in `Tests/` (the `ShotnoteTests` target compiles `Sources/`
  itself; it never launches the app).
- `Sources/Identity.swift` reads the bundle id, name, and URL scheme from the bundle and derives
  the log name, the status item's autosave name, the Application Support folder, and the Carbon
  hotkey signature from them, so a fork renames things in project.yml only. A second launch of
  the same bundle id quits the older instance (`[app] replacing older instance`).

## The loop

1. Change code.
2. `./scripts/run.sh`
3. Drive the app: `open -g shotnote://annotate` (or `copy`, `trash`, `last`, `recent`, `state`;
   `open -g shotnote://help` logs every command). Plain `open` activates Shotnote; `-g` does not.
   Every command ends with one `[<cmd>] ok <detail>` or `[<cmd>] error <code> <detail>` line; the
   codes are the `CommandError` cases in `Commands.swift`. `file=` must point inside the watch
   folder, and `eval`, `show-editor`, and `tweaks` are refused, unless settings.json has
   `"debug": true`. `[annotate] loaded <ms>` reports when the page has the image; it is posted
   from a `requestAnimationFrame`, which WebKit pauses while the screen is locked or the
   window is hidden, so the line never arrives in that state.
4. Look: `screencapture -x /tmp/s.png`, then crop the corner with `sips` and read the PNG.
   Send keys with `osascript -e 'tell application "System Events" to key code 36 using command down'`
   (Return finishes annotating, Cmd+Return too while typing, key code 53 is Esc). The recent stack takes key focus, so
   `keystroke "a" using command down` after `open shotnote://recent` selects all.
   For the global hotkey, the sweep gesture, or drag-out, System Events is not enough: use
   `scripts/input.sh` (CGEvent; `hotkey double-rshift`, `hotkey cmd+shift+6`, `click X Y`,
   `drag`, `scroll`, `tap`, `key`; run it with no arguments for the list). It compiles
   `scripts/input.swift` with `Sources/HotKeySpec.swift` on first use, so it reads the same hotkey
   strings as settings.json. It posts events only because the terminal it runs from is trusted for
   Accessibility. Its coordinates are global Core Graphics points: top-left of the primary
   display, y down, so the Studio Display above it has negative y. Every frame in the `[state]`
   line uses the same convention, so a card or annotator frame from there can be clicked as is.
   Never send Escape that way to close the stack: if the stack is not key, the keystroke reaches
   the frontmost app, and in a terminal running an agent that is the interrupt key. Use
   `open -g shotnote://dismiss` for the stack and `open -g shotnote://cancel` for the annotator.
   `scripts/input.sh pasteboard` prints the pasteboard's item count and types.
   Inside the editor page, `open 'shotnote://eval?<javascript>'` runs the code (async, `window.editor`
   is the tldraw editor) and logs the returned value.
5. Read `~/Library/Logs/Shotnote.log`. Every action, URL command, watcher event, web message,
   and error lands there with a `[tag]`. `open -g "shotnote://state?tag=<id>"` writes one
   `[state] {json}` line with the tag echoed, so a script waits for its own line:
   `app` (pid, build, isActive, accessibility, watch folder, settings file, debug), `screen`,
   `stack` (cards with `file`, `frame`, `out`, `draft`; selection, focus, feedback, panel),
   `transition` (phase), `annotator` (current file, frame, pageState, port, webPid),
   `drafts` (keys), `previews`, `memory` (rss and thumbnail cache in bytes), `backdrop`, and
   `page` (what the editor page reports: shapes, canUndo, hidden) or `"unavailable"` when the
   page does not answer within a second. Frames are `[x, y, w, h]` in global top-left points.
   `webPid` is the web content process, for `kill -9` tests; its size is `ps -o rss= -p <pid>`.
   `[app] ready pid=… build=… port=… watching=…` marks the end of launch: after it every command
   answers. `[web] ready` follows on its own once the editor page is up; `copy-annotated` and
   `eval` answer `error page-not-ready` before it, `annotate` queues one deep. `build` is
   `git describe` of the checkout, written into the bundle by a build phase (project.yml), so a
   build from Xcode carries it too.
   Log grammar (`Log.swift`): one event per line, `HH:mm:ss.SSS [tag] …`, details as
   `key=value` pairs, never an embedded newline (the logger flattens them); the launch line ends
   with `date=YYYY-MM-DD`; at 5 MB the file rotates to `Shotnote.log.1`, replacing the previous
   one. Draft events: `[draft] saved|parked|forgot|swept <file>` and `[drafts] <n>` after every
   change to the set. `[stack] shown cards=… files=… scan=…ms shown=…ms decoding=…` counts the
   watch folder and times the scan.

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
- The screenshot is served by the same `LocalServer`: the page turns the file path in `load`
  into `/<token>/file?p=<path>` under its own origin. It must be same-origin with the page: tldraw's export draws the image on a canvas, and a cross-origin
  image taints it so `render` throws. A custom scheme handler or a second port is therefore
  not an option. Every server path starts with a per-launch token, so no other local process
  can read screenshots through the port; the server answers only GET (405 otherwise), only
  `Host: 127.0.0.1:<port>` (400 otherwise, which stops DNS rebinding), and only the bundle or
  files inside the watch folder (`FileAccess`, lifted by `debug`). Never log the token:
  `LocalServer.redacted` is for URLs in log lines, and the page-state dump reports only the
  file name.
- The recent-stack shortcut is either a Carbon hotkey (`HotKey.swift`, no permission needed)
  or a modifier double tap (`ModifierTap.swift`, `"double-rshift"`), which needs the app trusted
  for Accessibility because it watches key events with NSEvent monitors. Both fire the stack on
  the press and `hold` when the key stays down 0.4 s, so a held tap opens the stack and then
  lifts the newest card out of it. When the press closed an open stack, the hold brings it back
  (a presentation during the slide-out reuses the cards, which turn around) and lifts the card
  that was focused, or the newest. `annotateOnCapture` sends a new capture straight to
  `annotate` instead of `show`.
- Apple's Cmd+Shift+3/4/5 still capture. The app only watches the folder. Do not register
  those hotkeys.
- Preload the web view at launch; the annotator must open instantly.
- Every animation duration goes through `Settings.motionUI`: `ui.motion` (0 to 1) in settings.json
  scales them, and the system's Reduce Motion forces 0. Dwell times (`thumbnailSeconds`,
  `toastSeconds`) are not motion. `"ui": {"motion": 0}` makes the stack appear and leave at once,
  which is what a script wants. Every SwiftUI animation is a spring made by `Anim.spring`
  (`slideInCurve` "spring" included), and the AppKit tweens use `Tween`'s spring curve: an
  interrupted motion keeps its velocity and blends into the new target instead of jumping.
- The backdrop's progressive blur is a stack of masked NSVisualEffectViews with different radii.
  The private CAFilter variableBlur ignores its mask when the backdrop renders in the window
  server on macOS 15 (verified: uniform blur), and a bare CABackdropLayer renders black. Do not retry.
- The status item has an autosave name and a seeded preferred position. Without it, a crowded
  menu bar on a notch Mac puts the new icon under the notch and it never appears.
- Files named `*-annotated.png` are outputs and are ignored by the watcher. `Stitch *.png`
  outputs are not ignored on purpose: they show up as a fresh thumbnail. The watcher takes png,
  jpg, jpeg, and heic (`ScreenshotWatcher.candidateExtensions`), reports removals to the stack
  (`[watcher] removed`), waits for a new file to decode before reporting it, and gives up on one
  that never does after ten seconds (`[watcher] error never-stable`); the next folder event or
  stack open picks it up. Wake from sleep rescans the folder.
- The stack panel is non-activating but can become key (`ThumbnailPanel.acceptsKeys`). Never
  call `NSApp.activate` for it; the user's app must stay frontmost. While a card is in the
  annotator the panel gives up key status so typing reaches the editor.
- "Click outside" detection goes through `OutsideClick`. A plain global mouse monitor also
  reports clicks on this app's own floating windows (verified: a click inside the annotator
  closed it), so the topmost window under the cursor is checked first.
- Which image is in the annotator, where it came from, and what is in flight has one owner:
  `AnnotatorTransition` (a pure reducer) held by `ThumbnailController`. Controllers send events
  (annotate, shown, parked, close, finish, newShot, dismiss, remove) and run the effects it returns
  (prepare, show, park, returnCard, markCopied, hideAnnotator, join). Done sends `finish`: the card
  returns and takes the copied mark, and a lone thumbnail, which left the panel when the annotator
  opened, comes back to the corner for it. Esc sends `close`: a stack card returns, a lone
  thumbnail's annotator just hides. Quick annotate sends `dismiss`. A `prepare` is never emitted while a
  park is in flight, which is what serializes rapid swaps; a new screenshot during a lone
  annotation joins the panel instead of closing the editor. Every event logs one
  `[transition] <event> -> <phase> effects=…` line. The page never hides itself: it asks through
  `onClosed`, and the reducer decides. The flight image lifts once the annotator is visible and
  the page has reported `loaded`. Add a sequence to `AnnotatorTransitionTests` before changing
  the table; the random-sequence test checks the invariants.
- The annotator window is borderless and sized exactly to the image. Its toolbar is a native
  panel (`AnnotatorToolbar.swift`) placed under the window, never inside the page: the page
  sends its tool and color list in the `ready` message, reports the active tool, and takes
  `setTool`/`setColor`/`finish` calls. Keyboard shortcuts inside the editor (tool keys, undo,
  delete, Esc, Return) live in `Hotkeys` in `App.tsx`, because tldraw's own shortcuts are part
  of the UI that `hideUi` removes. `TransitionLayer` flies a card between its stack slot and that
  frame, and the annotator loads the image while hidden (`prepare`) so it can appear the moment
  the card lands (`show`). A swap runs two of these at once. The stack keeps a dashed placeholder
  in the slot.
- Annotations in progress are drafts owned by the app (`DraftStore`), one JSON snapshot per
  screenshot under `~/Library/Application Support/<bundle id>/drafts/` keyed by the file path
  the app uses everywhere (`shot.url.path`), with a preview PNG under `~/Library/Caches/<bundle
  id>/drafts/`. The page holds only the image it is editing: it reports the snapshot shortly
  after every change (`draft` message), and `park` returns the final snapshot plus a preview
  when the user changed it, so the annotator hides only after that answer
  (`AnnotationController.hide(then:)`). Drafts survive relaunches and a web content process
  restart: the terminate delegate reloads the page and the next `ready` re-sends the image
  with its stored draft. A draft for a file that no longer exists is dropped when it arrives,
  and a launch-time sweep removes the rest. The snapshot's asset `src` is the file path; the
  page's asset store resolves it to the served URL, so a stored draft never contains a token.
  Loading a snapshot inside `editor.run(fn, { history: 'ignore' })` keeps it out of undo history.
- Zoom belongs to the app, not the page. A pinch, cmd+wheel, or cmd+plus/minus/0 sends a
  `zoom` message (tldraw never sees those wheels; a plain wheel still pans a magnified image)
  and `AnnotationController.zoom(by:animated:)` grows the window around its center up to the
  visible screen, then magnifies the image inside it through `setCanvasZoom`. Zooming out
  reverses that and stops at the fitted size with a short pull that springs back. The toolbar
  stays where `prepare` placed it and sits above the window as a child. The state report's
  `page.zoom` is the in-window magnification as tldraw sees it (1 = the image fills the window).
  "Copy Annotated" hands the stored snapshots to the live editor (`window.shotnote.export`),
  which restores the canvas afterwards; it falls back to the original file for cards without a
  draft, and answers `error export-failed` or `export-timeout` (15 s) instead of hanging.
- Memory is bounded in three places. `Thumbnailer` keeps decoded images under `budgetBytes`
  (96 MB of RGBA), least recently used out first. Card previews never exceed
  `Config.previewMaxPixel` on the longest side: park previews are rendered at that size by the
  page, and the full-resolution Done rendering is downsampled before it reaches a card or the
  disk. Screen-size flight decodes are dropped whenever the stack hides.
- Bumping tldraw (`web/package.json` pins the version; `LICENSE-tldraw.md` must be the matching
  license text) is a checklist, and `Tests/RenderTests.swift` is the gate:
  1. License: read the new version's LICENSE and its `LicenseProvider`; confirm an unlicensed
     `http://127.0.0.1` origin still renders with the watermark rather than hiding the editor,
     and that the `licenseKey` prop still exists. Replace `LICENSE-tldraw.md` verbatim.
  2. Watermark: note what it says now; it stays, whatever it says.
  3. Snapshots: stored drafts are `TLEditorSnapshot` JSON in Application Support. `loadSnapshot`
     runs the schema migrations, so check the release notes for breaking store changes and open
     an old draft (`[draft] parked` from a previous version) before trusting it.
  4. Asset store: the page's `assets.resolve` turns a path `src` into a served URL. Confirm
     `TLAssetStore.resolve` and `Editor.resolveAssetUrl` are still the hook the image shape uses.
  5. Export: run the render test. If tldraw's own `toImage` now rasterizes an embedded raster
     image in WKWebView, `render` in `App.tsx` can go; until then it stays.
  6. Protocol: any change to `bridge.ts` bumps `PROTOCOL` and `bridgeProtocolVersion` together.
  7. `editor.run(fn, { history: 'ignore' })` must still keep snapshot loads out of undo history
     (the render test checks `getCanUndo()` after an export).
- Exports do not use tldraw's `toImage`. In WKWebView an SVG that embeds the screenshot
  rasterizes blank (WebKit loads the inner raster image asynchronously; tldraw only sleeps
  250ms for browsers it detects as Safari, which WKWebView is not). `render()` in `App.tsx`
  draws the screenshot on a canvas and layers tldraw's SVG of the annotations alone on top.
- Swift language mode is 5 (see `project.yml`). No sandbox, on purpose: the app writes Apple's
  `com.apple.screencapture` defaults, watches a folder the user names without security-scoped
  bookmarks, and installs global event monitors. The hardened runtime is on.
- Signing: project.yml defaults to ad-hoc so any clone builds; `scripts/build.sh` reads the
  gitignored `scripts/signing.env` (identity and team) and this Mac's names the Developer ID
  certificate. Keep it that way here: Accessibility trust is tied to the signature's designated
  requirement, and an ad-hoc signature changes on every build (README has the details).
  `ENABLE_DEBUG_DYLIB` is off in project.yml: with it on, a Debug build loads its code from
  `Shotnote.debug.dylib`, which the hardened runtime rejects for a signer without a team ID, so a
  self-signed build crashed at launch. macOS keys Accessibility by bundle id: a second copy of
  the app with the same bundle id and a different signature shares the row and stays untrusted,
  so a test build that must be trusted needs its own bundle id.
- `Info.plist` is generated by xcodegen from `project.yml` and is gitignored; `web/dist` must
  exist before `xcodegen generate` runs, which build.sh guarantees.
- Settings changes push to Apple's `com.apple.screencapture` defaults (location, show-thumbnail,
  disable-shadow, type). Only keys that changed are written, and never on first run.

## Adding things

- An action: add a `ShotAction` to `Config.actions` and a method on the `Actions` protocol. Its
  `placement` decides whether it is a hover button on a card, a button in the selection bar, or
  both; `key` gives it a shortcut inside the recent stack. It is a `shotnote://<id>` URL either
  way. Actions always receive a list of screenshots, oldest first; `annotate` opens the newest of
  them, since the annotator holds one image, and says so in its `ok` line.
- An editor tool or color: edit `web/src/config.ts`. A tool needs an SF Symbol name for the
  native toolbar; a color needs the hex the swatch shows.
- A new message across the bridge: add it to both bridge files, then handle it in
  `AnnotationController` and `App.tsx`.
