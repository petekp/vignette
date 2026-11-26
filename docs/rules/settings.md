# Settings

- `~/.config/vignette/settings.json` holds per-machine settings (`SettingsData` defines the keys).
  Its `ui` section (`UITweaks`) holds the layout, style, timing, flight, and backdrop numbers, and its
  defaults are the tuned UI, so a fresh install renders the same. The file holds only the `ui`
  values that differ from the defaults (`UITweaks.differencesOnly`), so a default tuned in a later
  build reaches every install. Version 2 of the file brought that in; a build from before it opens
  a version 2 file read-only. `open -g vignette://tweaks`
  edits them live (needs `debug`). A number stays in code when changing it would mean changing the
  code around it, or when it is a fraction of something rather than a size: the toolbar's rows and
  buttons (`AnnotatorToolbar.swift`), the strip's icon and label sizes
  (`StackView.swift`, `StackLayout.swift`), the fly-back timing and the annotator's own shadow
  (`TransitionLayer.swift`), the zoom's springs and limits (`AnnotatorZoom.swift`), the
  stitch's gap, padding, and badge (`Stitch.swift`), the editor's steps (`EditorCore`: the nudges,
  the copy offset, the snap angle, the 0.3 s hand-over), the editor's own colours (`EditorStyle`),
  the badge's own proportions (`NoteBadge`) and the tag's shadows (`NoteTag`). The editor's sizes
  and how every mark looks are `UITweaks`, the Editor, Comments, Marks and Notes sections of the panel: the
  colours, the stroke and edge widths, the shadows' strength, the arrowhead and every pin number
  (`PinStyle`) reach the drawing as `MarkStyle`, and the fonts, weights, sizes, padding, width cap and the badge's place as
  `TextStyle` (`docs/mark-style-settings-2026-09-29.md`). A change
  reaches every place that draws marks at once: the open editor (`AnnotationController.applyTweaks`),
  the cards and flights (`ThumbnailController.applyTweaks`), live ink (`LiveInk.applyTweaks`), and
  the next stitch, drag image and rendering, which read the settings when they draw. How much
  smaller marks are on a small screenshot is the exception: `UITweaks.markScaleRule` sets a
  drawing's mark scale when it is made, and a change reaches only the drawing open in the editor
  (`docs/rules/editor-and-drawings.md`). What a user would tune belongs in `UITweaks`,
  with an entry in `TweakCatalog`, which gives it its row in the tweak panel and its safety range
  (`UITweaks.bounds` is made from it); when in doubt, put it there. A tweak goes in the group whose
  file is named as its `TweakCatalog` file is (`UITweaks+Stack.swift` beside `TweakCatalog+Stack.swift`).
  `ui` stays one flat object: each group decodes its keys from it, `UITweaks.fields` lists every
  tweak by its own name for the encoding, and `ui.<name>` reads a tweak in any group. Inside an
  extension of `UITweaks`, write `self.<name>`, since a bare name does not reach the groups. Editing the file is a supported way to
  change settings; the app reloads it within a second. It is the user's real config: never test
  against it. `VIGNETTE_SETTINGS=<path>` in the environment
  (`open -g --env VIGNETTE_SETTINGS=/tmp/x/settings.json <app>`) points a launch at another file,
  and the launch line names it. It also moves Apple's screenshot defaults to
  `<bundle id>.screencapture`, a domain macOS never reads, so a test launch neither takes nor moves
  the user's save location. A test launch whose data `Launch.dataHome` moves keeps the app's own
  records (`ThisMac`, `setupDoneOnThisMac`, `returnsToLiveInkSetup`, the login item's path) in
  `<bundle id>.test-launch` (`Identity.defaults`), never in the person's own app's domain. Vignette follows that domain's `location`, so write it before a launch
  that should watch a scratch folder: `defaults write <bundle id>.screencapture location <folder>`. The tweak panel writes to whichever file the instance was launched
  with, so copy the real file over the scratch copy before a test round and, before relaunching the
  real build, merge back any `ui` keys that changed (`[settings] wrote ui.…` in the log lists them).
  A file that cannot be created (a `~/.config` another tool owns) leaves the launch read-only, with
  `[settings] error cannot create` and a notice in the General tab, and never reads as a first launch.
  A write that fails later logs `[settings] error write-failed` and is tried again with the next
  change, and at quit when the app changed a setting during the run. Two writes at launch, the
  fill-in of missing keys and the defaults written after a bad file is set aside, log the same line
  and start the run with `lastWriteFailed` set. From the failure until a write
  succeeds (`SettingsSync.lastWriteFailed`), the General tab says Settings not saved, above the
  launch's notice when there is one, since each says something the other does not. It comes and
  goes with the window's notice spring.
  A file that does not parse is moved to `settings.json.invalid` and replaced with defaults; bad
  numbers are clamped in memory and logged as `[settings] warning clamped`. `appleOriginal` records
  Apple's screencapture values before Vignette changed them; `open -g vignette://restore-apple-defaults`
  puts them back.
- Settings changes push to Apple's `com.apple.screencapture` defaults (location, show-thumbnail,
  disable-shadow, type). Only keys that changed are written. First run is the one exception, and it
  writes one key: `show-thumbnail` goes off, because Apple's thumbnail withholds the file for about
  5.6 seconds (measured; `docs/replacing-apple-capture-2026-09-22.md`) and `copyOnCapture` fills the
  clipboard when the watcher reports the file, so with both on a Cmd+V inside that gap pastes what
  was there before. Installing Vignette is choosing what happens after a capture, so that is not a
  question the setup window asks and there is no toggle for it; `appleOriginal`, captured in the
  same turn, is the way back. Vignette replaces the thumbnail only while it runs: quitting puts
  `show-thumbnail` back on when Apple showed it before Vignette (`Settings.handBackAppleThumbnail`),
  unless a newer launch of the same bundle id is replacing this one, and `Settings.reconcileApple()`
  turns it off again at the next launch, before the watcher. So quitting, turning Open at login off,
  or removing the app never leaves captures that show nothing. SIGTERM is turned into a normal quit
  for the same reason; a crash or a force quit still leaves it off until the next launch. The
  reconcile also undoes anything outside the app that turned it on, since Apple's thumbnail breaks
  Vignette rather than merely differing from it. The save location runs the other way:
  Vignette follows macOS's. The launch takes `location` as `screenshotsFolder` (unset reads as
  `~/Desktop`), and a key-value observer on the domain (`AppleScreencapture.observe("location")`) takes
  every later change, a folder picked in ⌘⇧5's Options menu included, as it is written
  (`[settings] following apple location=…`; measured on a scratch domain, 10 to 35 ms after a
  `defaults write` from another process). Picking a folder in Vignette writes `location`, so the two
  never differ, and the observer ignores that write coming back as the folder it already has.
  `type` and `disable-shadow` are never reconciled. The reconcile is silent; the Screenshots tab
  says under "After a screenshot" that Vignette replaces the thumbnail while it runs. It has no
  Restore button: the folder, format and shadow above it are macOS's own settings, and quitting
  already hands the thumbnail back. `vignette://restore-apple-defaults` writes Apple's old value
  into `appleThumbnail`, which is what makes a restore survive the next launch's reconcile, and
  while that is on the tab offers Turn Off, the way back. `target` is ⌘⇧5's Save to: `file`, or `clipboard`, `mail` or `preview`, which
  leave the folder with no new screenshots. Vignette observes it and writes it only from Save to
  Folder, which the menu, setup's shortcut page and the Screenshots tab offer while it is not
  `file` (`Settings.appleTarget`); a choice the person made in ⌘⇧5 is theirs to undo.
