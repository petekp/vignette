# Working on Shotnote

Shotnote is meant to be modified. This file is the onboarding for a person or an agent.

## Layout

- `Sources/` Swift menu bar app. `AppDelegate.swift` wires everything; `Config.swift` holds the actions.
- `~/.config/shotnote/settings.json` holds per-machine settings (`Settings.swift` defines the keys).
  Its `ui` section (`UITweaks`) is every layout, style, timing, and backdrop number; nothing visual
  is hard-coded elsewhere. `open shotnote://tweaks` edits them live.
  Editing the file is a supported way to change settings; the app reloads it within a second.
- `web/` React + tldraw editor page. `web/src/config.ts` holds the editor knobs.
- `Sources/Bridge.swift` and `web/src/bridge.ts` mirror each other. They are the entire
  contract between Swift and the page. Change both or neither.
- `scripts/build.sh` builds web, regenerates the Xcode project, builds the app.
  `scripts/run.sh` does that and relaunches.

## The loop

1. Change code.
2. `./scripts/run.sh`
3. Drive the app: `open shotnote://annotate` (or `copy`, `trash`, `last`, `recent`, `state`).
4. Look: `screencapture -x /tmp/s.png`, then crop the corner with `sips` and read the PNG.
   Send keys with `osascript -e 'tell application "System Events" to key code 36 using command down'`
   (Cmd+Enter finishes annotating, key code 53 is Esc). The recent stack takes key focus, so
   `keystroke "a" using command down` after `open shotnote://recent` selects all.
   For the global hotkey, the sweep gesture, or drag-out, System Events is not enough: use
   `scripts/input.py` (CGEvent, needs `pyobjc-framework-Quartz`). `open shotnote://state`
   logs each card's frame so a script can aim at circles and images.
   Inspect the pasteboard with JXA: `osascript -l JavaScript -e 'ObjC.import("AppKit"); $.NSPasteboard.generalPasteboard.pasteboardItems.count'`.
5. Read `~/Library/Logs/Shotnote.log`. Every action, URL command, watcher event, web message,
   and error lands there with a `[tag]`. `open shotnote://state` dumps current state.

A fake screenshot for testing: `screencapture -x -R 200,200,900,560 "<watch folder>/Screenshot test.png"`.
Delete test files afterwards; the watch folder is the user's real screenshot folder.

## Rules that are not obvious from the code

- tldraw hides its editor five seconds after mount on any non-http origin without a license.
  That is why `LocalServer.swift` serves `web/dist` on 127.0.0.1. Do not switch to file:// or
  a custom scheme.
- The "Made with tldraw" badge stays. Hiding it breaks the free license.
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
- The annotator window is borderless and sized exactly to the image; the toolbar floats over
  the bottom edge. `ExpandPanel` carries a card between its stack slot and that frame, and the
  annotator loads the image while hidden (`prepare`) so it can appear the moment the card lands
  (`show`). A swap runs two of these at once. The stack keeps a dashed placeholder in the slot.
- Swift language mode is 5 (see `project.yml`). No sandbox: the app reads the user's folder.
- Settings changes push to Apple's `com.apple.screencapture` defaults (location, show-thumbnail,
  disable-shadow, type). Only keys that changed are written, and never on first run.

## Adding things

- An action: add a `ShotAction` to `Config.actions` and a method on the `Actions` protocol. Its
  `placement` decides whether it is a hover button on a card, a button in the selection bar, or
  both; `key` gives it a shortcut inside the recent stack. It is a `shotnote://<id>` URL either
  way. Actions always receive a list of screenshots, oldest first.
- An editor tool or color: edit `web/src/config.ts`.
- A new message across the bridge: add it to both bridge files, then handle it in
  `AnnotationController` and `App.tsx`.
