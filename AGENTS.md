# Working on Vignette

Vignette is meant to be modified. This file is the onboarding for a person or an agent: the
rules, the contracts, and where the numbers behind them live. The dated notes in `docs/` hold
the measurements and the reasoning; a rule here points at its note. `docs/adr/` records the
decisions that are hard to reverse, one file each, with what was weighed. Add one when a change
makes such a decision, and mark the old one superseded when a change reverses it.

## Layout

- `Sources/` Swift menu bar app. `AppDelegate.swift` wires everything; `Config.swift` holds the actions.
- `~/.config/vignette/settings.json` holds per-machine settings (`Settings.swift` defines the keys).
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
  and how every mark looks are `UITweaks`, the Editor, Marks and Notes sections of the panel: the
  colours, the stroke and edge widths, the shadows' strength and the arrowhead reach the drawing as
  `MarkStyle`, and the fonts, weights, sizes, padding, width cap and the badge's place as
  `TextStyle` (`docs/mark-style-settings-2026-09-29.md`). A change
  reaches every place that draws marks at once: the open editor (`AnnotationController.applyTweaks`),
  the cards and flights (`ThumbnailController.applyTweaks`), live ink (`LiveInk.applyTweaks`), and
  the next stitch, drag image and rendering, which read the settings when they draw. What a user would tune belongs in `UITweaks`
  with a `Bound` and a slider; when in doubt, put it there. Editing the file is a supported way to
  change settings; the app reloads it within a second. It is the user's real config: never test
  against it. `VIGNETTE_SETTINGS=<path>` in the environment
  (`open -g --env VIGNETTE_SETTINGS=/tmp/x/settings.json <app>`) points a launch at another file,
  and the launch line names it. It also moves Apple's screenshot defaults to
  `<bundle id>.screencapture`, a domain macOS never reads, so a test launch neither takes nor moves
  the user's save location. Vignette follows that domain's `location`, so write it before a launch
  that should watch a scratch folder: `defaults write <bundle id>.screencapture location <folder>`. The tweak panel writes to whichever file the instance was launched
  with, so copy the real file over the scratch copy before a test round and, before relaunching the
  real build, merge back any `ui` keys that changed (`[settings] wrote ui.…` in the log lists them).
  A file that cannot be created (a `~/.config` another tool owns) leaves the launch read-only, with
  `[settings] error cannot create` and a notice in the General tab, and never reads as a first launch.
  A file that does not parse is moved to `settings.json.invalid` and replaced with defaults; bad
  numbers are clamped in memory and logged as `[settings] warning clamped`. `appleOriginal` records
  Apple's screencapture values before Vignette changed them; `open -g vignette://restore-apple-defaults`
  puts them back.
- The drawing editor is Swift, in `Sources/`. `Drawing.swift` is a drawing and its marks, the file
  format, and the one validator for files, pastes and agents' marks. `EditorCore.swift` is the
  editor's reducer, with `EditorGeometry.swift` and `EditorHistory.swift`. `EditorView.swift` hosts
  it in AppKit. `EditorLayers.swift` draws the picture and the overlay, `EditorTextView.swift` the
  text being typed, and `MarkLayers.swift` the marks, for the editor, the cards (`MarksView.swift`)
  and the flights. `MarkRendering.swift` is the renderer and `MarkGeometry.swift` the geometry it
  shares; `AgentMarks.swift` turns an agent's marks into a
  drawing's, `RenderingQueue.swift` runs the renderings, and `Drawings.swift` keeps the drawings on
  disk. `docs/editor.md` says how the editor behaves.
- `scripts/build.sh` regenerates the Xcode project and builds the app.
  `scripts/run.sh` does that, waits for the old process to exit, and relaunches. `scripts/build.sh
  --test` also runs the unit tests in `Tests/` (the `VignetteTests` target compiles `Sources/`
  itself; it never launches the app). A build into another `-derivedDataPath` leaves `build/`,
  and an instance running from it, untouched.
- `docs/releasing.md` says what a release must pass, how to cut and publish it, and how to write
  its release notes.
- `media/trailer/trailer.py all` records the trailer from the current source: it builds a stage copy
  of the app with its own bundle id, sets up a desktop with the game in Chrome and the trailer's own
  Claude Code in Ghostty, with the stage copy's plugin, drives every beat while it records the
  screen, and cuts the result from `beats.toml`. `trailer.py claude` signs that Claude Code in once.
  A take takes over the screen for 5 to 8 minutes. `docs/trailer-pipeline-2026-09-26.md` says how.
- `Sources/AgentConnection.swift`, `Sources/ScreenshotRequests.swift`, `Sources/ReplyProtocol.swift`,
  `Sources/ReplyCommand.swift` and `skills/vignette/scripts/reply` are the closed loop: a drawing
  sent to an agent session and that agent's drawing sent back. See the rules below and
  `docs/closed-agent-loop-implementation-2026-09-20.md`. `agent-plugin/` is the plugin Claude Code
  and Codex install, which carries the skill and, for Claude Code, delivers what Send sends, and
  `Sources/AgentPlugin.swift` installs it (`docs/claude-code-without-herdr-2026-09-27.md`).
- `Sources/LiveInk.swift`, `LiveInkOverlay.swift`, `ModifierChord.swift` and `InkStroke.swift` are
  live ink, drawing on the live screen (the "Live ink" rules below). `LiveNotePanel.swift` is the note
  an ask is typed in, `LivePacket.swift` what an ask sends, `LiveResponder.swift` the `claude`
  process that answers, and `LiveAnswer.swift` and `LiveAnswerLayout.swift` the answer and where its
  marks go. `KeyMonitors.swift` installs the
  key monitors live ink and the double tap share, once the app is trusted for Accessibility.
- `Sources/Identity.swift` reads the bundle id, name, and URL scheme from the bundle and derives
  the log name, the status item's autosave name, the Application Support folder, and the Carbon
  hotkey signature from them, so a fork renames things in project.yml only. A second launch of
  the same bundle id quits the older instance (`[app] replacing older instance`).

## The loop

Before you drive the app:

- Launch a test copy with a scratch settings file: `open -g --env VIGNETTE_SETTINGS=<scratch> <app>`.
  Never test against `~/.config/vignette/settings.json`, which is the user's real config.
- Read `[state]` before every key, click or command, and stop unless `app.bundle` is your build and
  `app.settingsFile` is your scratch file.
- Launch one copy at a time, behind the lock when agents share the Mac, and put the user's own build
  back after every round.
- Never send a synthetic Esc to close the stack or the annotator. Use `vignette://dismiss` and
  `vignette://cancel`.
- Delete test files from the watch folder afterwards. It is the user's real screenshot folder.
- A test copy never touches the person's own `~/.claude` and `~/.codex`: with `VIGNETTE_SETTINGS`
  set, `AgentPlugin.roots` leaves them out and the launch logs `[plugin] test launch: left <folder>
  alone`, and it registers no login item. To test the plugin, also launch with
  `CFFIXED_USER_HOME=<scratch home>` (`docs/test-isolation-2026-09-29.md`). It runs no codex and
  no herdr unless `VIGNETTE_CODEX` or `VIGNETTE_HERDR` names one (`AgentTools.forSessions`), since
  any other found on the Mac reaches the person's own sessions; the launch logs
  `[tools] test launch: codex=… herdr=…`. The plugin's skill names the copy's own URL scheme and log
  (`AgentPlugin.stage`).
- Stop a test copy by its PID before you launch another copy of the same bundle id. On 2026-09-26,
  `open -a <a Release copy> <url>`, sent after a Debug copy of the same bundle id had run, launched a
  second Release instance without `VIGNETTE_SETTINGS`, on the user's real settings file.

The steps below have the details.

1. Change code.
2. `./scripts/run.sh`
3. Drive the app: `open -g vignette://annotate` (or `copy`, `trash`, `last`, `recent`, `state`;
   `open -g vignette://help` logs every command). Plain `open` activates Vignette; `-g` does not.
   Every checkout builds the same bundle id, so with more than one build on the Mac LaunchServices
   sends `vignette://` to whichever copy it registered last, and that copy's launch replaces the
   instance you started: `open -g -a <your build>/Vignette.app "vignette://…"` aims at yours.
   A relaunch from `open` carries no `VIGNETTE_SETTINGS`, so it runs on the user's real settings
   and folder, and when another copy of the bundle id is running `open -a <path>` can launch that
   copy instead of the path given; running `<app>/Contents/MacOS/Vignette` directly always lands on
   the path given. That last one is the wrong way to test anything about permissions: a process
   launched from the terminal is attributed to the terminal, so the app inherits its Accessibility
   trust and reports itself trusted with no entry of its own in the TCC database (measured
   2026-09-21, a build launched from a trusted Ghostty after `tccutil reset Accessibility
   com.petepetrash.vignette`). `open -g --env VIGNETTE_SETTINGS=<path> <app>` goes through
   LaunchServices and answers honestly. `[hotkey] modifier tap needs Accessibility permission` in
   the log, or `app.accessibility` in `[state]`, says which one you got. A driving script reads `[state]` first and stops unless `app.bundle` is its own
   build and `app.settingsFile` is its scratch file, and only then sends an action. `app.bundle` is
   the check that holds: `build` is `git describe` of the checkout, so worktrees branched from one
   commit stamp the same string, and `settingsFile` reads the same from any copy launched without
   `VIGNETTE_SETTINGS`. Confirming a restored instance needs that same check. `state` is no exception: sent without `-a` it
   launches whichever copy LaunchServices has, on the user's file, and that launch fills in every
   settings key the copy's schema has and the user's file does not. Several agents working in
   parallel (a worktree each) share one Mac and one running instance, so they launch one at a time
   behind a lock held only around a launch and a look, and put the user's own build back after every
   round. A build the user runs from a worktree's build folder is copied to a path no build touches
   before that worktree is rebuilt; a rebuild rewrites the bundle under the running process.
   Every command ends with one `[<cmd>] ok <detail>` or `[<cmd>] error <code> <detail>` line; the
   codes are the `CommandError` cases in `Commands.swift`. `file=` must point inside the watch
   folder, and `tweaks`, `install-skill?root=` and `live-ink-stroke` are refused, unless settings.json has
   `"debug": true`. A `file=` inside the folder is taken by the folder's own spelling
   (`Commands.inWatchFolder`), so `/tmp/x.png` and `/private/tmp/x.png` reach one drawing.
   `add` is the exception, and it takes two paths the folder rule does not cover.
   `add?file=` copies an image in from anywhere and the watcher then reports it like a capture,
   minus the copy and annotate toggles (`&annotate` opens the editor). `&agent=<name>` says which
   agent is pushing it: the name is recorded on the copy as the `com.petepetrash.vignette.agent`
   extended attribute (`Agent.swift`, `xattr -l` shows it) and the card gets a white "From <Name>" tab
   with the vendor's logo when `Resources/agents/<name>.svg` has one (`Agent.logo(for:)`). A logo
   that is a single black shape, like Codex's, is listed in `Agent.oneColourLogos` and drawn in the
   colour of the text beside it.
   `&session=<id>` names the Claude Code session pushing it, recorded beside the name as
   `com.petepetrash.vignette.session`, so the card's bar is Reply and goes back there
   (`Agent.origin(of:)`). The id is the pusher's claim. Sending to it still checks that a live
   plugin inbox holds that session (`ClaudeCodeConnection.submit`). Anything but a UUID is not
   recorded, and `[add]` still answers `ok`.
   `&marks=<json file>` pushes the agent's own annotations with the image: they join the
   screenshot's drawing before the card appears (`Drawings.add`), and the command answers once that
   drawing is written. That JSON file may also be anywhere; it is read on the main thread, so it is
   capped at 256 KB, and an error line names the mark and the field without quoting what the file
   said. A text too long to fit even across the whole picture is cut at the edge and named in a
   `[marks] text too long for <name>` line, which is the only thing that says so, since `[add]`
   still answers `ok`. `docs/commands.md` has the format and the rest.
   `[annotate] loaded <ms>ms <name>` reports when the editor has the screen-size decode of the
   image, and `[annotate] takes events after=<n>ms reached=true|false` when its window starts
   taking presses.
4. Look: `screencapture -x -R x,y,w,h /tmp/s.png` captures just that region; then read the PNG.
   To crop a full capture, use Python. Do not use `sips`: it ignores `--cropOffset` and crops from
   the centre.
   Send keys with `osascript -e 'tell application "System Events" to key code 36 using command down'`
   (Return finishes annotating, Cmd+Return too while typing, key code 53 is Esc). The recent stack
   takes key focus, so `keystroke "a" using command down` after `open vignette://recent` selects all.
   For the global hotkey, the sweep gesture, or drag-out, System Events is not enough: use
   `scripts/input.sh` (CGEvent; `hotkey double-rshift`, `hotkey cmd+shift+6`, `click X Y`,
   `drag X1 Y1 X2 Y2 [seconds]`, which holds the button at the end that long and posts nothing
   while it does, `scroll`, `tap`, `key`; run it with no arguments for the list). It compiles
   `scripts/input.swift` with `Sources/HotKeySpec.swift` on first use, so it reads the same hotkey
   strings as settings.json. It posts events only because the terminal it runs from is trusted for
   Accessibility. Its coordinates are global Core Graphics points: top-left of the primary
   display, y down, so a display above it has negative y. Every frame in the `[state]` line uses
   the same convention, so a card or annotator frame from there can be clicked as is.
   Never send Escape that way to close the stack: if the stack is not key, the keystroke reaches
   the frontmost app, and in a terminal running an agent that is the interrupt key. Use
   `open -g vignette://dismiss` for the stack and `open -g vignette://cancel` for the annotator.
   Before any key or click, read `[state]` and confirm the stack or annotator is up and key: a
   synthetic key reaches whatever is frontmost otherwise, and a click lands in whatever window is
   there. A single `move` does not fire hover; walk the cursor in several steps and confirm
   `stack.hovered` (or the focus) in `[state]` before trusting a capture.
   `scripts/input.sh pasteboard` prints the pasteboard's item count and types.
5. Read `~/Library/Logs/Vignette.log`. Every action, URL command, watcher event, and error lands
   there with a `[tag]`. `open -g "vignette://state?tag=<id>"` writes one
   `[state] {json}` line with the tag echoed, so a script waits for its own line:
   `app` (pid, build, bundle, isActive, accessibility, watch folder, settings file, debug), `screen`,
   `stack` (cards with `file`, `frame`, `out`, `forming`, `drawing`, `agent`, `kind`, `copied`,
   `notCopied`, the reason a copy failed or null; `selected`,
   `focused`, `hovered`, `queue`, the files waiting for the annotator, `visible`, `key`, `isStack`,
   `scroll`, `viewport`, `safeBottom`, the room the Dock keeps under the column, panel,
   `widthScale`, how wide the stack is drawn, and `strip`, the selection strip's frame or null),
   `transition` (phase), `annotator` (`current`, `frame`, `toolbar`, `windowVisible`, `key`, `tool`,
   and the zoom's own keys, which the zoom bullet below names), `editor` (`open`, `tool`, `marks`
   with each mark's `type`, `frame` and `agent`, `selection` as indexes into `marks`, `typing`,
   `undo`, `redo`; never a text's words), `drawings` (keys), `requests`, `memory` (rss and thumbnail
   cache in bytes), `backdrop`, `dim`, and `liveInk` (the "Live ink" rules below). Frames are
   `[x, y, w, h]` in global top-left points, except a drawing's mark's, which is in the image's
   pixels.
   `[app] ready pid=… build=… watching=…` marks the end of launch: after it every command
   answers. `build` is `git describe` of the checkout, written into the bundle by a build phase
   (project.yml), so a build from Xcode carries it too.
   Log grammar (`Log.swift`): one event per line, `HH:mm:ss.SSS [tag] …`, details as
   `key=value` pairs, never an embedded newline (the logger flattens them); the launch line ends
   with `date=YYYY-MM-DD`; at 5 MB the file rotates to `Vignette.log.1`, replacing the previous
   one. Drawing events: `[drawing] saved|parked|built|removed|swept|dropped <file>`, and
   `[drawings] <n>` after every change to the set.
   `[stack] shown cards=… files=… shown=…ms decoding=…` counts the watch folder from the
   watcher's index.

A fake screenshot for testing: `screencapture -x -R 200,200,900,560 "<watch folder>/Screenshot test.png"`.
Delete test files afterwards; the watch folder is the user's real screenshot folder. Never retype a
real capture's name to reach it: macOS writes the time with U+202F, a narrow no-break space, before
AM and PM, so a typed path with an ordinary space is a different path and every call on it answers
ENOENT while `ls` still lists the file, which reads as the file being unreadable rather than
misnamed. Take the name from a listing (`os.listdir`, `contentsOfDirectory`) and pass it through.
The prefix is no safer: it is `defaults read com.apple.screencapture name`, the user's to change,
and screen recordings share it, so `Screenshot ….mov` is a recording and only the extension says so.

Measuring a handoff or a flicker: a burst of `screencapture -x -R x,y,w,h` reaches about 12 frames a
second; `screencapture -x -v` records the region at 60, and the frames read back with AVFoundation
give a per-frame position of an edge or the mean brightness of a band, which is how a one-frame
step, a doubled shadow, or a mismatch between a frame and its picture is proven or ruled out.
Compare before and after on the same driven sequence. `scripts/measure/frames.sh` reads a recording
back: `extract` writes its frames as PNGs, `sheet` lays out crops of the frames at given times on
one labelled image, and `track` prints a rect's mean colour in every frame. A rect is in points from
the recording's top-left, at the main display's scale; `FRAMES_SCALE` sets another.

Measuring a stutter: launch the app under Instruments and drive it as above.
`xcrun xctrace record --template 'Time Profiler' --instrument 'Core Animation Commits' --env
VIGNETTE_SETTINGS=<scratch> --time-limit 75s --output perf.trace --launch -- <app>` (a
`--launch` also replaces the running instance; the Animation Hitches template attached to a
running process records no commits or samples on macOS). `xctrace export --xpath
'/trace-toc/run[@number="1"]/data/table[@schema="coreanimation-commit-interval"]'` gives every
commit with its duration; a commit over 8.3 ms dropped a frame at 120 Hz. `time-profile` samples
on the main thread that run without a gap are a stall; the frames from the `Vignette` binary name
the code. Trace time zero is about `[app] launched` minus the first sample inside
`applicationDidFinishLaunching`, which lines the trace up with the log.
`scripts/measure/commits.py <trace>` prints that table as quarter seconds of work, or `--at` the
windows after given times. Compare before and after on the same driven sequence; a single run
varies, and so does the build: `scripts/run.sh` builds Debug and the stage copy is Release, and a
Debug build's narrowing dropped four frames where the Release build's dropped at most one
(`docs/prerelease-fixes-2026-09-26.md`). Check that the driven sequence does what it is meant to:
the stack narrows only when the annotator's frame comes near it, so a trace of 1600 by 1000
images opening measured no narrowing at all, and `stack.widthScale` in `[state]` says whether it did.

The end-to-end tests: `scripts/e2e/e2e.py run` builds the test copy (`scripts/e2e/build.sh`: its
own bundle id, name and URL scheme, given on the `xcodebuild` line) and runs the scenarios in
`scripts/e2e/scenarios.py`, each on a fresh scratch home, settings file and watch folder. It saves
the pasteboard and puts it back, even when stopped (`e2e.py restore` after a crash), and writes a
report under `scripts/e2e/out/runs/`. `--input` adds the scenarios that post keys and clicks, each
gated on the test copy's own state; they need `Vignette E2E` granted Accessibility once, by hand.
The terminal that runs them needs Accessibility and Screen Recording. On macOS 15, the run's first
screen capture can raise a prompt asking whether the terminal may "bypass the system private window
picker". While that prompt is up, the test copy cannot become active (observed 2026-10-01 in a
clean VM), so the editor never takes the keys and every scenario that needs them stops at its gate.
Allow it and run again.
`docs/e2e-suite-plan-2026-09-29.md` has the design and what is still to come.

Testing Send without a real session: a Claude Code session is an inbox folder under the copy's
Application Support, `claude-sessions/<pid>/` with `session`, `cwd` and a fresh `alive`, and `<pid>`
a live process (`App.fake_session` in the runner). Send writes its request line there. A Codex
thread is listed by a fake codex that `VIGNETTE_CODEX` names (`App.fake_codex`,
`scripts/e2e/fake_codex.py`): it answers `app-server`'s `initialize` and `thread/list`, and records
each `codex queue --thread <id> --message <line>`, which is how Send hands a Codex thread its line. Launched
with `--env CFFIXED_USER_HOME=<folder>`, the app takes that folder for the home folder, so the Agents
tab and setup read and write a scratch `.claude` rather than the user's; its log is then under that
folder's `Library/Logs`, which must exist before the launch, or the log lines are dropped. Apple's
screenshot location for such a launch is written with the same variable:
`CFFIXED_USER_HOME=<folder> defaults write <bundle id>.screencapture location <watch folder>`.

## Rules that are not obvious from the code

### Shortcut and capture

- The recent-stack shortcut is either a Carbon hotkey (`HotKey.swift`, no permission needed)
  or a modifier double tap (`ModifierTap.swift`, `"double-rshift"`), which needs the app trusted
  for Accessibility because it watches key events with NSEvent monitors. Both fire the stack on
  the press and `hold` when the key stays down 0.4 s, so a held tap opens the stack and then
  lifts the newest card out of it. `RegisterEventHotKey` answers success for a combination macOS
  or another app already uses (measured with ⌘⇧3, ⌃Space and Raycast's ⌥Space), so only the keys
  firing prove a combination works, which is what setup's try shows. The recorder refuses ⌘ with
  one key, ⌘⇧3/4/5 and macOS's ⌃ shortcuts (`HotKeySpec.refusal`) and says why under the box.
  When the press closed an open stack, the hold brings it back
  (a presentation during the slide-out reuses the cards, which turn around) and lifts the card
  that was focused, or the newest. `annotateOnCapture` sends a new capture straight to
  `annotate` instead of `show`.
- Apple's Cmd+Shift+3/4/5 still capture. The app only watches the folder. Do not register
  those hotkeys.
- With `annotateOnCapture` on, a capture flies into the editor from the rect it was taken from
  (`CaptureOrigin.swift`). macOS records no position in the file, and its capture overlay keeps
  its drag from every other app's event monitors. The button's state still reads, so ⌘ and ⇧ held
  together, seen by a `flagsChanged` monitor, start a 30 Hz poll of `NSEvent.pressedMouseButtons`
  and the pointer for 15 s. None of this needs a permission. `CaptureRect.locate` is the pure part.
  It tries a drag released within 3 s whose size is near the file's, then the topmost window under
  the pointer, bare or with either of Apple's two window shadows, then the display. A selection is
  the release corner and the file's size, since the poll sees the press up to a tick late. The
  capture includes the point under the release. A capture that matches none of them flies from its
  card. The presentation is pinned to the screen holding the rect's centre, and the flight starts in
  `Look.screen`, which has no corners, shadow, ring or matte, so its first frame matches the pixels
  beneath. `ThumbnailController.annotate(_:from:)` waits for the screen-size decode before the run
  starts: a new capture has no picture cached, and a flight with none is invisible in that look, so
  it travelled unseen and appeared part way along. `[origin]` lines say what was found, and `[annotate] from capture` says the flight used
  it. `docs/capture-origin-spike-2026-10-03.md` has the measurements, and the `capture_origin`
  scenario drives it with `screencapture -i`.
- The status item has an autosave name and a seeded preferred position. Without it, a crowded
  menu bar on a notch Mac puts the new icon under the notch and it never appears. Opening Vignette
  again, from Finder or Spotlight, opens Settings (`applicationShouldHandleReopen`), or brings setup
  forward while it is up; with the icon hidden it is the way back. A `vignette://` URL is not a
  reopen (checked 2026-09-25), so a script's commands never open the window. The menu names its
  two screenshot switches as the Screenshots tab does, under an "After a Screenshot" section
  header, and its Live Ink switch as the General tab does.
- Files named `*-annotated.png` are outputs and are ignored by the watcher. `Stitch *.png`
  outputs are not ignored on purpose: they arrive like a capture, which is what carries a stitch into
  the annotator when `annotateOnCapture` is on. The watcher takes png, jpg, jpeg, and heic images
  and mov recordings (`ScreenshotWatcher.candidateExtensions`), reports removals to the stack
  (`[watcher] removed`), waits for a new file to decode before reporting it (a recording, until
  AVFoundation can read its video track), and gives up on one that never does after
  ten seconds (`[watcher] error never-stable`); the next folder event or stack open picks it up.
  Wake from sleep rescans the folder. The watcher keeps an index of the folder (name and
  modification date, from one bulk listing) so opening the stack and finding the newest screenshot
  never list the folder on the main thread. Every stack open asks for a rescan, which is how the
  index catches a file changed in place. The first listing runs on the watcher's queue and launch
  waits for it half a second: macOS holds the first read of a folder it protects (the Desktop,
  Documents, Downloads) until the user answers its prompt, and done on the main thread that read
  held the whole launch for as long as the prompt was up (measured: 4 minutes 20 seconds, no setup
  window and no menu bar icon). Until a listing has worked the reads answer from the empty index.
  While the folder cannot be watched (a volume not mounted yet, or macOS refused the app the
  folder) the reads list it directly and the watch is retried every 2 seconds, logging a change of
  reason rather than every attempt. A folder that was there but unreadable is indexed silently by
  the first listing that works, so a grant does not report every file in it as a new capture; a
  missing folder is indexed as empty, and when it appears, as a volume mounts, the files dated
  before it was found missing are indexed silently and only newer ones are reported. `isDenied` (macOS refused
  the app the folder, at its open or at its listing) and `isReadable` (a listing worked) are what
  setup and the Screenshots tab read. A first launch whose folder is inside the Desktop, Documents
  or Downloads (`ScreenshotWatcher.protectedArea`) makes no watcher until setup's Allow…, its
  Continue or its closing (`watcherWaitsForSetup`), so macOS's prompt comes up under a row that says
  why. `recentShots` answers empty with no watcher, so nothing reads the folder before then.
  project.yml gives macOS's folder prompt its explanation
  (`NSDesktopFolderUsageDescription` and the Documents and Downloads keys).
  `docs/install-2026-09-24.md` has the measurements. Copying puts the image's own bytes on the
  pasteboard under its own type, `public.jpeg` for a JPEG, and promises the TIFF, and the PNG when
  the image is not one. Both are made only when a paste target asks.
- The main thread never reads a file that iCloud Drive has taken off the Mac. With Optimize Mac
  Storage on, an old file in an iCloud Desktop or Documents folder is a placeholder
  (`SF_DATALESS`), and any read of it, ImageIO's header or AVFoundation's asset, downloads all of
  it and waits: a 333 MB recording held the stack's opening for 14 s. The listing, `lstat`, resource
  values and extended attributes do not download. `Thumbnailer.lookUp` is what the main thread
  asks: `.notDownloaded` for a placeholder, and the card takes the kept shape or the screen's, with
  iCloud's thumbnail from Quick Look, which does not download (`Thumbnailer.cardImage`). A
  placeholder screenshot is downloaded in the background (`Thumbnailer.download`), because the
  editor reads the file on the main thread when it opens; a recording is not downloaded, and its
  badge shows no length. `docs/icloud-files-2026-09-25.md` has the measurements and what still
  reads on the main thread.
- A screen recording is a `Screenshot` whose `kind` is `.recording`, read from the `.mov`
  extension alone (`Screenshot.recordingExtensions`). Its card shows the first frame, decoded on
  the thumbnail queue (`Thumbnailer.posterFrame`, about 90 ms), and a badge with its length. Each
  action names the kinds it takes (`ShotAction.kinds`, images only unless it says otherwise), and
  `unavailableReason(for:)` is the one test: the strip greys a row that cannot take every selected
  card, its key beeps, and its URL answers `unsupported-type`. An action never runs on the part of
  a selection it can take. Draw and Open share Return and one strip row (`Config.stripRows` groups
  actions by key); the row shows whichever applies, and Draw when neither does. A click on a
  recording opens it in the app macOS opens movies with. A recording never reaches the annotator,
  so `annotateOnCapture`, the hold, and Draw on Newest Screenshot pass over it. Copy puts a recording
  on the pasteboard as its file URL and path, never its frames. Stitch takes its first frame, which
  is what its card shows (`Thumbnailer.posterFrame`, off the main thread).
  `docs/replacing-apple-capture-2026-09-22.md` has the measurements.
- The first launch opens the setup window (`SetupWindow.swift`), and it has that launch to itself.
  It is pages, one step each: welcome, with the folder permission when macOS protects the watch
  folder, and Open at login; the shortcut; and the agent skill, only when `~/.claude` or `~/.codex`
  exists. Its main job is the shortcut, because the default is `double-rshift` and that needs
  Accessibility. Nothing else
  may raise that dialog: `ModifierTap` is constructed with `prompt: false`, so the only
  `trusted(prompt: true)` in the app is `Accessibility.request()`, which runs from a button the user
  pressed: this window's, after choosing the double tap, and the Settings window's. A dialog raised
  during launch, on a question nobody asked, is the one people dismiss. `request()` raises macOS's
  own alert and nothing else, and opens the pane itself only when no `universalAccessAuthWarn`
  window is up 1.5 s later (measured: the alert came up within half a second). Opening both at
  once put the pane in front of the alert, which then waited behind it and outlived the grant, and
  each further press queued one more alert to come up after it. The window learns the grant landed
  by polling (AXIsProcessTrusted announces nothing), comes back to the front then, since System
  Settings was covering it, and learns the shortcut works from the `.hotKeyFired`
  notification, which `registerHotKey`'s `fire` posts: the keys firing is what proves the setup
  worked, since the stack appearing does not on a Mac with no screenshots yet. Each fire turns the
  key picture's ×2 into a check, and the line then asks for the hold, which posts `.hotKeyHeld`.
  A modifier's keycap in the picture goes down while that key is held (`HeldModifiers`), so the
  picture responds to the keys before Accessibility is granted: a local monitor hears them while
  setup is key, and a global one everywhere once the app is trusted. A combination's own key never reaches the window,
  since the hotkey takes it, so its firing presses the picture. That same poll reads
  the watch folder's count, and an empty folder asks for a capture first, ahead of the fired state:
  a tap with nothing to show opens nothing, so reporting success would report it about an empty
  corner. The two menu items that act on a screenshot, Show Recent Screenshots and Draw on Newest
  Screenshot, are greyed out while the folder is empty (`validateMenuItem`), which is the rest of
  that silence: both used to answer only in the log. `setup` in
  settings.json records `unasked` then `done`, written when the window closes rather than when it
  opens, so a launch quit part way through asks again. The permissions belong to the Mac, and a
  settings.json synced by dotfiles carries `done` to a new one, so the app's own defaults keep
  `setupDoneOnThisMac` too, and a file's `done` counts without it only where an earlier launch left
  the Application Support folder, as every release did (`SetupWindowController.isUnasked`). A test
  launch goes by its scratch file alone. `ShortcutSetting` is the one shortcut
  control, shared with the Settings window's General tab: a pop-up of double taps, then Key
  Combination…, which shows a recorder that starts listening at once. A new settings file starts with
  `launchAtLogin` on: first run turns Apple's thumbnail off, so a restart that does not bring
  Vignette back leaves every capture silent. The window shows the switch, and the login item is
  registered when it closes, not during the launch it is showing in, and after the menu bar intro
  when there is one, since macOS announces a new login item in the corner the intro points at. A login item the person
  removed under Open at Login reads `.notFound` (measured), and a launch then turns
  `launchAtLogin` off instead of registering it again; a copy that moved is told apart by the path
  it registered from (`LoginItem.removedByPerson`). The folder row is a
  permission, not a choice of folder: it appears only for a folder inside the Desktop, Documents or
  Downloads, its Allow… starts the watcher, whose first read raises macOS's prompt, and a refusal
  turns it into a warning whose Allow… opens Privacy & Security > Files and Folders. The window's one
  default button is the next step still to take: a missing permission's Allow…, then Continue or
  Done. The page dots are laid over the buttons, so they sit on the window's centre line whatever
  the buttons are. The skill page's switches start on, and closing the window installs the ones
  still on, but only for someone who reached that page: closed earlier, `agentSkill` stays
  `unasked`, and the next launch offers the skill in the Settings window instead.
  `docs/settings-polish-2026-09-25.md` has the design and its reasons. Closing the window is where
  the menu bar icon is introduced (`MenuBarIntro`), since otherwise it appears in a busy bar with
  nothing pointing at it: a picture of the window covers it, the window closes, and the picture
  pours into the icon, row by row, as macOS's genie pours a window into the Dock: the top edge leads,
  each row narrows to the icon's width ahead of its travel, and each fades as it enters the icon, so
  nothing piles up over it. A shader bends the picture (`Sources/IntroFunnel.metal`) and draws its
  edge, corners and shadow from one distance to the bent shape; SwiftUI's `.shadow` drew nothing
  under that effect. `docs/intro-funnel-2026-09-30.md` has the design and the measurements, and the
  Intro Lab (`vignette://intro-lab`, needs `debug`) tunes it. `ui.introFunnel` at 0 flies the
  picture as one piece instead, on the flight's bowed path. Either way the motion accelerates the
  whole way and arrives at speed, because it goes into something, where a card lands in a slot: a
  spring that settles spends as long on the last tenth of the way as on the rest. A copy of the menu
  bar's highlight comes up behind the icon as the picture reaches it. At the impact the
  icon pops, a light crosses the highlight, and a popover under it names the shortcut, or, while
  something the menu must fix is missing (`missing()`, which the menu's own items come from), names
  that and says to click the icon. All of it is timed from one moment
  on the media clock (`MenuBarIntro.keyframes`), and `ui.introDuration` sets the flight's length.
  The popover draws the shortcut as a key and goes after 5 s, when the shortcut fires, or at a click
  on the icon; a second intro, from the Intro Lab, closes the first one's. The picture is the window as the window
  server draws it, captured with ScreenCaptureKit's `SCShareableContent.currentProcess`, which lets an
  app capture its own windows without Screen Recording permission (macOS 14.4). The window's views
  drawn with `cacheDisplay` lack the wallpaper's tint, and the picture went flat at the handover;
  they are the fallback before 14.4 or when the capture fails or takes over 0.25 s. Neither has the
  outline and the dark-mode rim the window server draws at a window's edge, so the picture draws
  them, as measured on macOS 15. The capture holds the screen's own pixel values labelled sRGB,
  so the picture is labelled with the screen's colour space, and while it covers the window only
  the picture casts a shadow. The picture covers the window before the window closes, because the
  window server takes a window down at once. macOS can give
  the icon a window and draw nothing, under the notch or past the end of a full bar, so the intro
  plays only when `MenuBarIntro.canSee` says the icon shows, and `[state] app.menuBarIcon` reports
  the same answer. With no icon to point at, the last page says to open Vignette again for its
  settings.
- A launch from the disk image offers to move the app to Applications (`AppLocation.swift`),
  from `main` before `Settings.shared` exists, so the copy on the image never creates the settings
  file or touches Apple's defaults. "On the disk image" is a read-only volume or a translocated
  path; a notarized, stapled image is not translocated (observed), so the volume check is the one
  that fires for a real download. The move copies beside the destination, clears the quarantine
  flag (the user already answered Gatekeeper for this app), puts an older copy in the Trash, opens
  the new copy as a new instance, and exits; the new copy replaces the old instance as any launch
  does and detaches the image with `hdiutil detach`, because `NSWorkspace.unmountAndEjectDevice`
  unmounted an APFS image's volume and left the image attached, so opening the same file again
  mounted nothing. `VIGNETTE_SETTINGS` is passed to the moved copy, so a test launch stays on its
  scratch file. The destination is /Applications, or ~/Applications for a user who cannot write
  there. A copy there with a higher `CFBundleVersion` is opened instead, and the image ejected, so an
  old image never replaces what the updater installed. The alert is a non-activating panel
  (`runKeyed`): macOS refuses to activate a menu bar app before `NSApp.run`, and an inactive alert has
  no default button, so Return did nothing (measured on macOS 15, opened from Finder).

### Words and motion

- Vignette has no toasts. What happened is said on something already on screen. A copy or a stitch
  marks its card (`ThumbnailController.showCopied`), a failed copy (`showNotCopied`) or send
  (`SendNotice`) says why on the card, and a card that is not on screen comes up as the lone
  thumbnail to say it. A card says one of these at a time, the newest winning, and a send waiting
  for its answer still gets it after a newer notice took the card, so a failure is never lost
  (`CardNotices`, `docs/card-notices-2026-10-02.md`). A paste the editor cannot take beeps. A settings.json that did not parse is
  a warning at the top of the Settings window's General tab. A command from a script answers in
  the log.
  `docs/no-toasts-2026-09-30.md` has what each toast became.
- `docs/voice.md` is how Vignette speaks: clear, short and humble, pointing to what can happen
  next. It has the rules and every message written to them. A new or changed message follows it
  and is added there.
- Two vocabularies, and they do not mix. Every string a user reads says draw: the buttons, the menu
  items, the toggles, the section headings, the notices on cards. Every name a script, a log reader or a
  compiler reads says annotate: the URL ids (`vignette://annotate`, `copy-annotated`), the log tags
  (`[annotate]`), the settings keys (`quickAnnotate`, `annotateOnCapture`), the `-annotated.png`
  suffix, and every identifier. A label is free to change; those are a contract. The editor window
  is still the annotator in both, because it is a thing rather than an action.
- Every animation goes through `Settings.motionUI`: `ui.motion` (0 to 1) in settings.json scales
  every duration, and the system's Reduce Motion forces 0. Dwell times (`thumbnailSeconds`,
  `markSeconds`) are not motion, and neither is a movement the user's own hand is driving: the
  drag-select's auto-scroll (`ui.autoScrollZone`, `ui.autoScrollSpeed`, `StackLayout.autoScrollSpeed`,
  ticked by a display link in `ThumbnailController`) follows the drag at its own speed whatever
  the scale says. `"ui": {"motion": 0}` makes the stack appear and leave at once, which is what a
  script wants. Every SwiftUI animation is a spring made by `Anim.spring` (`slideInCurve` "spring"
  included), and the AppKit tweens use `Tween`'s spring curve: an interrupted motion keeps its
  velocity and blends into the new target instead of jumping. `Tween.spring` is the closed form of
  a critically damped spring, so a late tick lands where the spring really is by then. Do not step
  it forward by hand: integrating it overshoots by hundreds of points after one late tick.

### The stack

- The stack runs to the bottom of the screen and steps around the Dock. `StackLayout.area` builds
  one `StackArea` from the screen: `bounds` takes its sides and top from `visibleFrame` and its
  bottom from the screen's own `frame`; `safeBottom` is the height AppKit reserves for a bottom
  Dock, but only when the Dock's tiles reach into the column's strip of the screen. The column sits
  above the Dock, the newest card rests `ui.screenMargin` above its top edge, and the mask and the
  hair of alpha that catches clicks are lifted by the same number, so a click on a Dock icon under
  the column still reaches the Dock. The tiles' rect is Accessibility's (`Dock.tiles`, the Dock
  process's one `AXList`): `CGWindowListCopyWindowInfo` reports the Dock's window as the whole
  screen on macOS 15. Untrusted for Accessibility, the Dock is taken to span the whole edge.
  `annotatorRoom` and `annotationFrame` keep reading `visibleFrame`: the annotator must not go
  under the Dock. `docs/stack-dock-2026-09-18.md` has the numbers.
- A card in the stack and the same card in flight have to cast the same shadow. The column is
  masked with a fade over the panel's inset at each end (`StackView.column`), and the bottom fade
  starts below the newest card's shadow: solid for `StackLayout.cardShadowRoom` and fading over the
  rest of the inset. `StackLayout.inset` is therefore at least that room plus `shadowFade`, so a
  shadow bigger than `ui.panelInset` grows the panel around the column instead of being cut off.
  The flight's shadow is cast by the clipped image, before the ring, for the same reason.
- The backdrop's progressive blur is a stack of masked NSVisualEffectViews with different radii.
  The private CAFilter variableBlur ignores its mask when the backdrop renders in the window
  server on macOS 15, and a bare CABackdropLayer renders black. Do not retry. The band masks are
  one-pixel bitmaps stretched to the strip and cached by width; shading a drawing-handler image at
  the strip's full height on every show was measurably slow.
- Stitching from the stack is one motion, not a file appearing later. `ThumbnailController.stitched`
  takes the cards the image was made from out of the column, holds a slot for the new card at the
  bottom, and hands both to `TransitionLayer.converge`: the pieces fly into that slot while the
  finished image fades in under them. Both sets of cards sit in `model.forming` while their image is
  in the transition layer, so a slot keeps its place and draws nothing, and the image is never on
  screen twice. The watcher reports the file a moment later as usual; the card is already there, so
  `insert` ignores it, and with `annotateOnCapture` on that same report flies the new card into the
  annotator. With the stack closed (a `vignette://stitch` from a script) the stitched card comes up
  as the lone thumbnail with the Copied notice. Dismissing the stack mid-converge ends the pieces'
  flights with it, and the stitched card comes up the same way, so a stitch never finishes in
  silence. `Stitch.compose` lays the pieces out for the model that
  will read the result: it tries every column count and keeps the one that survives a vision
  model's resize best (`readerScale`, Anthropic's standard tier: a long edge of 1568 px and 1568
  patches of 28 px). The gap and the badges are fractions of the piece they are on,
  `ui.stitchLongSide` caps the output, and `[stitch] ok` reports the composed size and that scale.
  Each piece carries its drawing, the editor's own for the image open in it and the stored one
  otherwise, and `Drawing.draw` draws it into the piece's pixels as Done does, off the main thread.
  The stitch is a new image with no drawing of its own. `docs/stitch-2026-09-17.md` has the numbers;
  separate images are better when the model has to read the text.
- The stack panel is non-activating but can become key (`ThumbnailPanel.acceptsKeys`). Never
  call `NSApp.activate` for it; the user's app must stay frontmost. Closing the stack or the
  annotator hands the focus back (`FocusReturn.restore`): to the Vignette window the session began
  in when that was Settings, setup or the tweaks, and else to the app before Vignette. While a
  card is in the annotator the panel gives up key status so typing reaches the editor. It gives it
  up in `perform(.prepare)`, right after the annotator's window has taken it, so the keys pass from one
  to the other instead of being nobody's for the length of the flight. A `.help` tooltip never
  shows in the stack: AppKit shows a window's tooltips only while its app is active, unless the
  window sets `allowsToolTipsWhenApplicationIsInactive`, which the panel does not. Text the user
  must see there is drawn, like a greyed strip row's reason (`UnavailableReason`).
- Which card a key acts on is one variable, `model.focused`. The stack focuses the newest card the
  moment it takes keys (`takeKeys`), or the card that just came back from the annotator, the last one
  looked at, so arrows, Space, and Return act on a card without a first click, and the pointer moves
  the focus too: moving onto a card focuses it, and leaving it leaves the focus there. The pointer only
  moves it while the stack holds the keys and no card is in the annotator; while the annotator has
  them nothing moves. A shortcut runs on the selection when there
  is one, else on the focused card (`targetCards`). The ring says where the focus is: the accent
  color on a selected card, white on a focused one. It grows out of the card's resting border and
  shrinks back into it, and the selection circle fades in with it.
- Thumbnails in the corner show the selection circle once there are two or more of them
  (`StackModel.offersSelection`), except while one is in the annotator. Selecting there makes the
  corner the stack with the cards it holds (`ThumbnailController.becomeStack`): it takes the keys
  and the backdrop, a click outside closes it, and it stops timing out.
- The panel widens to the left while cards are selected, to hold the selection strip
  (`StackLayout.stripPlacement` places it, `panelSize(viewport:showsStrip:reveal:)` makes the room:
  the icon column, the gap to the cards, and the room the labels grow into, whether they are out or
  not). Its right edge never moves, so the cards stay where they are. The gap to the cards is
  `ui.selectionStripGap`, measured from the widest selected card (`docs/selection-strip-2026-09-18.md`).
  Only the column carries the hair of alpha that catches clicks and scrolls; the strip's side of
  the panel stays clear, so a click there still reaches the window underneath.
- The strip's labels are out for as long as a selection exists, whichever hand built it: a selection
  is the moment the rows' names and shortcuts are wanted, and a strip that folded back to icons when
  the pointer moved onto a card read as the strip losing interest. Each row draws its shortcut after
  the label from `ShotAction.Key.glyphs`, and `stripReveal(rows:)` measures both, so the panel's
  room holds them. Copy on a card still reveals on hover and grows to the right from an icon that
  does not move; the strip keeps its right edge and grows to the left, so a label never covers a
  card. A row is one button, icon and label together. The strip stands aside while the annotator has
  an image, since it hangs inside the room the frame may grow into: the two places that ask for its
  placement refuse (`ThumbnailController.stripFrame` and `StackView.stripPlacement`), never
  `showsStrip`, which sizes the panel, because the panel's window is not resized while a card is in
  the annotator. The selection is untouched and the strip springs back when the annotator closes.
  `[state] stack.strip` is the grown frame, null while a card is in the annotator.
- The recent stack narrows to make room for the annotator. One number says how wide it is drawn:
  `StackLayout.widthScale`, 1 at rest and never below `ui.stackMinScale`. The cards are drawn at
  that width (`drawn`) and the column with them; their right edge does not move. The panel is always
  the size the stack needs at rest, and transparent outside the column, so nothing has to be resized
  while the stack narrows; the scroll follows the column's height so the same cards stay in view and
  the column comes back to the same place. The rect the annotator fits and grows within is the
  visible frame less the strip the stack keeps at its narrowest, `ui.stackGap` beside it
  (`annotatorRoom`), so the frame can never reach the cards however far a zoom grows it. In between,
  every time the annotator's frame moves the stack takes the widest value that still clears it by
  the gap (`widthScale(clearing:visibleFrame:)`). Opening and closing spring it through
  `ui.relayoutDuration`; a zoom sets it straight, in the same turn as the frame. Only the recent
  stack does this: a lone thumbnail leaves the panel when the annotator opens, and a
  `vignette://annotate` with no stack showing gets the whole visible frame.
  `docs/stack-room-2026-09-17.md` has the numbers, and `docs/stack-narrowing-2026-09-23.md` what a
  frame of the narrowing costs and the options for making it cheaper.
- A card joining the open stack is not animated as a layout change. `ThumbnailController.shiftUp`
  changes the layout and grows the panel with animations off, lifts every card that was there back
  to where it was drawn (`StackModel.lift`), and springs the lifts to 0 on the next turn. The panel
  grows at its top edge at once, and SwiftUI animates in coordinates whose origin is that edge, so
  an animated insert moved the cards half a slot in one frame and carried the new card along with
  the column. The new card slides on the lone thumbnail's spring, after `CardView.insertLead`, so it
  reaches the column's width only once the card above has cleared its slot.
  `docs/stack-insert-2026-09-26.md` has the frames.
- A card's thumbnail fills the card, so a screenshot whose shape differs from the card's box hangs
  outside the card's frame, and the clip that hides it does not shrink the hit area. The
  `contentShape` in `CardView` holds each card's hover and clicks to its own frame; without it a
  hovered card, which `zIndex` raises for its hover scale, takes them from the card below.

### Flights and presses

- A flight does not run down a straight line. `FlightCurve` bows it to one side and swells the card,
  both peaking in the middle and nothing at the ends, so the card still leaves and lands exactly
  where the layout puts it. The amounts are `ui.flightArc` (a fraction of the path's length),
  `ui.flightArcMax` (the bow's cap in points), and `ui.flightDepth`; the motion scale multiplies the
  first and the third, so `motion: 0` and Reduce Motion give a straight line. The side of the bow
  belongs to the line rather than the direction of travel, so a flight that turns around mid-air
  keeps bowing the same way; `TransitionLayer`'s `Bow` blends between a flight's old and new paths,
  so a flight re-aimed in mid-air crosses from one bow to the other instead of stepping sideways.
  A flight also carries a `Look` (corner, shadow opacity, radius, y) animated from `.annotator(ui)`
  to `.card(ui)`; `AnnotationController` reads the annotator window's frame shadow from the same
  `Look.annotator`, so the two ends cannot drift apart. `dropShadow(id:)` zeroes a flight's shadow
  in the same run-loop turn the card appears or the annotator turns its own shadow on, so the
  shadow is never drawn twice and never missing for a frame.
- Nothing takes a flight's place until it has arrived; the annotator hides behind it before then. A
  spring's tail runs well past its nominal duration, so anything put at the exact target on a timer
  steps by what the spring still had to go. `fly` therefore answers on `arrived`, at `Anim.settle`
  (the spring within half a point of the target, with the flight put exactly on it in that turn):
  the card retakes its slot, and the annotator takes the shadow back
  (`AnnotationController.landed`). The flight into the editor lifts at the last of three moments
  (`ThumbnailController.liftIntoEditor`): `arrived`, which `lift(id:)` waits for itself; the
  editor's `loaded` (`editorLoaded`, `loadedKeys`); and its window taking presses
  (`annotatorTakesEvents`, `takingEvents`). The wait for `loaded` matters at motion 0, where the
  flight can arrive before the image, and lifting it then would show an empty editor;
  `docs/native-editor-2026-09-23.md` has the timings. The wait for presses keeps the flight over the
  window until the window takes presses itself, so a press there never falls through to the app
  behind. `fly` answers a second time, earlier, at `Anim.passesTarget`: from the moment a bouncing
  spring first reaches its target the flight's rect contains the target on every side, so the
  annotator's window comes up there, with its own shadow off (`AnnotationController.show`), hidden
  behind the flight image until `arrived`. That is what makes the editor take the pointer the moment
  the card looks still: the toolbar and the outside-click monitor start with the window, and a
  shadow is the one thing that would show, because it falls outside the frame it is cast from. The
  keys come earlier: `prepare` orders the window in at alpha 0 and makes it key, so a tool key or
  Esc pressed during the flight already reaches the editor. Presses come later: the window server
  passes every press through a window at alpha 0, and starts giving the window its presses 6 to
  39 ms after `show` sets alpha 1, or up to 97 ms under load. Nothing announces that moment, so
  `AnnotationController.probeEvents` asks the window server every millisecond from `show` whether a
  press at the frame's centre reaches the window, looking through this app's windows above it. It
  gives up after 0.5 s. `[annotate] takes events after=<n>ms reached=true|false` reports the answer,
  and `reached=false` means it gave up. Until then the flight takes the presses (the next rule).
  Done or Esc is accepted between the two moments, so the `arrived` callback is guarded on the key,
  not the phase. A flight can also go without arriving, and a third callback, `dropped`, runs then,
  so the window never keeps a shadow that is switched off. The window is at the fitted frame by then
  whatever the zoom was: `hide` springs the level back to 1 first and comes down once that has
  arrived (`AnnotationController.fitBeforeHide`). `docs/shadow-2026-09-17.md` and
  `docs/handover-2026-09-18.md` have the frames and what each moment cost.

  The way home is the same handover the other way round. The flight starts at the editor's frame,
  the editor's frame is hidden in the commit that starts the flight moving, and its window is ordered
  out three display refreshes later (`AnnotationController`'s `Removal`). The window server takes a
  window down at once, so ordered out in the turn the flight was added, the window left the frame
  empty for 4 to 9 frames before the flight showed. The flight starts from the editor's own decode,
  from Thumbnailer's cache: a lone thumbnail's flight images are dropped when its stack hides, and
  its card's picture showed for one blurred frame. `docs/e2e-2026-09-26.md` has the frames.
- The flight layer takes the presses on a flying card or a swallow rect, and nothing else; the matte
  rule below says why nothing else reaches it. Its content view, `PressCatcher`, takes each press
  with its drags and its release, and `FlightPress` decides where they go. Its comment and
  `FlightPressTests` have the cases. In short, a press on the card flying into the editor is held
  until the editor's window takes presses, then handed to the editor (`AnnotationController.take`,
  `EditorView.take`), and a press on any other flight is swallowed up to its release. A held event
  lands on the point of the picture that was under the pointer when it happened (`FlightSpotView`);
  after the handover, the pointer's place on screen decides. Marks drawn before the flight lifts
  appear when it lifts. A press handed over onto the text being typed goes to the text
  (`pressText`). The text view cannot track that press itself, because its tracking loop would read
  the drag and the release from the event queue, where they are the flight layer's, in that window's
  coordinates. So such a press cannot drag selected text to move it. A double-click handed over does
  not zoom before the landing (the zoom rule below).

  For `NSEvent.doubleClickInterval` after a click opens a card in the editor, or swaps the editor to
  one, the layer also swallows presses on that card's slot, as the hovered card drew it, before any
  flight over it (`ThumbnailController.swallowSecondClick(on:)`,
  `TransitionLayer.swallowPresses(in:for:on:)`). The `SwallowRect` is drawn with the column's hair
  of alpha, so the window server gives the layer the presses there, above the stack. Opening a card
  narrows the stack away from its slot and can slide the card above into it, so without this the
  second click of a double-click reached the app behind the narrowed stack, or opened the card that
  slid into the slot. Return and URL opens have no click and swallow nothing.

  The layer orders out once it has no flights, no swallow rects and no press down
  (`orderOutIfIdle`), because the window server sends a press's drag and release to the window that
  took the press. `watchRelease` ends a press whose release never arrives, from the button's own
  state, and logs `[flight] release missed`. A stack presented while the layer is up with no flights
  is ordered above it at the same level, so the first flight or swallow rect on a layer with no
  flights brings it back to the front (`showPanel`). A pointer over a flight gives the stack a hover
  exit, so a card landing from the editor takes its hover from where the pointer is
  (`ThumbnailController.hover(landing:)`). `docs/flight-press-2026-09-23.md` has the measurements
  and the two limits that remain: the window server's lag of 6 to about 30 ms, and a press at
  motion 0 that passed through, which needs no fix.
- "Click outside" detection goes through `OutsideClick`. A plain global mouse monitor also
  reports clicks on this app's own floating windows, so the topmost window under the cursor is
  checked first. The stack and the annotator each own one; the monitor's token never leaves that
  file. The annotator's ignores clicks for `outsideClickSettling` after its window is ordered in:
  the window server does not report the new window under the cursor for a few milliseconds, and a
  press inside the frame then reads as outside. That is a race, not motion, so the scale does not
  touch it.
- A screenshot's transparent pixels are never see-through. The annotator's frame, a card
  (`StackView`) and a flight (`TransitionLayer`) paint `Config.matte`, `#1a1a1a`, behind the image,
  so nothing changes when one takes over from another. The matte is also what routes the annotator's
  clicks. Its window spans the screen's visible frame and is clear outside the frame, and the window
  server gives a press to a window only where its pixel is not clear. So every press on the frame
  reaches the editor, and a click outside it reaches the app behind, where the annotator's
  `OutsideClick` sees it and closes the editor. A shadow passes presses too: asked about points from
  1 to 64 pt outside a card, the window server named the window behind every time, for a layer
  shadow like the annotator's and a SwiftUI shadow like a flight's. So the annotator's shadow and a
  flight's are click-through. All of this holds for the annotator and the flight layer only while
  `ignoresMouseEvents` is never set on either: set either way, the window takes or passes every
  press, whatever its pixels.

### The annotator and its reducer

- The annotator must open instantly, so the editor opens at `prepare`, before the image is
  decoded (`AnnotationController.open`). It opens with the screen-size decode when `Thumbnailer`
  has it cached, which it does after a hover, and with no image otherwise; `setImage` adds the image
  when the decode answers, and `[annotate] loaded <ms>ms <name>` is logged then. Opening first is
  what lets the keys work from `prepare`, and it leaves no moment in which an agent's push could
  miss the open drawing. `openGeneration` drops a decode or a colour sample that answers after
  another image opened.
- Which image is in the annotator, where it came from, what is in flight and what opens next have
  one owner: `AnnotationRun`, a pure reducer held by `ThumbnailController`. The controller sends
  what happened (annotate a list, shown, parked, cancel, sent, finish, dismiss, remove, newShot,
  selectionChanged, copyFailed) and runs the effects it returns (prepare, show, park, abandon,
  returnCard, hideAnnotator, join, next, queued, endRun). The moves into and out of the annotator
  are decided by `AnnotatorTransition`, a pure reducer the run holds privately. Done sends
  `finish`: the card returns and takes the Copied notice (`returnCard`'s `copied`), and a lone
  thumbnail, which left the panel when the annotator opened, comes back to the corner for it. Esc
  sends `cancel` and Send sends `sent`, which both reach the transition as `close`: the card returns
  without the Copied notice. A lone thumbnail that comes home with nothing to show, no
  send or failure notice and no other card in the corner, does not land: it flies into the corner and
  off the screen's edge (`ThumbnailController.leavesAtOnce`, `flyAway`). Quick draw sends
  `dismiss(byHand: true)`. A `prepare` is never emitted while a
  park is in flight, which is what serializes rapid swaps; a new screenshot during a lone annotation
  joins the panel instead of closing the editor. Every event logs one
  `[transition] <event> -> <phase> [queued=<n>] effects=…` line. The annotator never hides itself: Esc, a click
  outside, Cmd+W and Done ask through `onClosed` and `onFinished`, and the reducer decides. `show`
  is the window coming up behind the flight. The editor parks synchronously, so an effect can answer
  inside the event that asked for it: at zoom 1 there is no fit-out, and `parked` comes back in the
  same turn as `park`. `EventHold` holds an event that arrives while another is being handled and
  runs it once that one is done, so the reducer's events stay in order. The
  `parking` phase stays for the zoomed case, where the window springs back to the fit before it
  comes down. `dismiss` sets `model.slidingOut` before it sends, so a park that answers in that turn
  leaves the flight it just aimed offscreen to the slide-out. Add a sequence to `AnnotationRunTests`,
  or to `AnnotatorTransitionTests` for the transition's table, before changing either. Their
  random-sequence tests check the invariants through `EventHold`, with same-turn answers among
  their sequences. A swap runs two flights at once, and the
  stack keeps the slot, drawn empty, so the card flies back to the same place.
- The flight to the annotator can be interrupted. In `flyingOut` the window has not come up, so
  nobody has seen that image: a `close` or an `annotate` of another key answers in the same turn
  with `abandon` and `returnCard`, and the flight turns around from where it is (`fly` on an id
  already flying keeps the frame and blends the bow). `abandon` is `AnnotationController.abandon()`:
  it parks the drawing and stores it, since the editor holds the keys during the flight and a key
  pressed then can change the drawing, and it takes the window down with no fit-out, since no zoom
  can have happened. The controller's `.abandon` keeps the parked marks (`parkedMarks`), as `.park`
  does, so the flight home carries the drawing as it was parked, not as it left. `dismiss` and
  `remove` still park from `flyingOut`, because the panel aims that same flight offscreen before the
  event arrives. Esc during the flight comes back through `onClosed` as `cancel`.
  `docs/flight-interrupt-2026-09-18.md` has the frames.
- Annotating a list is one annotation run with a queue (`AnnotationRun.queue`, `stack.queue` in the
  state report): the first file opens and the rest wait, and finishing one opens the next until the
  list is done. When the transition goes idle after a `returnCard`, the run opens the next file in
  that same batch (`returnCard(A) next(B) prepare(B)`). So the card flies home with its Copied notice
  while the next flies out, which is a swap's two flights, and the room beside the stack is made
  once for both. Between two files the dim stays up and the focus stays with Vignette. `endRun`
  comes only when nothing follows: it hides the dim, and hands the focus back when a person's hand
  ended the run. Opening a card does not clear the selection, so after the last one Cmd+C or Cmd+S
  still takes all of them. While a card is in the annotator, selecting another card in the stack
  queues it next, in the order picked (`[annotate] queued <name> 3 of 3`), and deselecting it takes
  it back out (`selectionChanged`, from the model's `onSelectionChanged`). Esc, a dismissal, quick
  annotate, a stack presented anew and the open file going all end the run and drop the queue. Done
  and Send go on to the next file, and any other request to annotate replaces the queue. A queued
  file that has gone, or whose header no longer reads, is passed over before anything moves:
  `reduce` asks its `opens` closure, where the controller makes the card or logs `[annotate] error
  unreadable-image <name>`, and the run opens the file after it or ends. A person's request is
  checked the same way before it is sent, so a file that cannot be read never closes the image
  already open. `docs/annotation-run-2026-10-01.md` has the design and
  `docs/annotation-queue-2026-09-17.md` the handover.
- The annotator's window is borderless and spans the screen's visible frame. The frame inside it is
  sized to the image. Its toolbar is a native panel (`AnnotatorToolbar.swift`) placed under the
  frame, one level above the flight layer, so a flight into or out of the editor passes under it as
  the editor does. It is not the annotator window's child, since AppKit keeps a child window at its
  parent's level. It shows `EditorCore.Tool.allCases`, the editor reports the active tool through `onTool`,
  and the bar calls `setTool`, `send` and `done` on the editor. The bar is tools, one divider, then
  what `ToolbarOffer` says the image offers: Copy alone when there is no session to send to; Copy,
  the target, a message field and Send; or the message field and Reply on a card that names the
  session it came from (an agent's reply, or a push with `session=`). Copy is Done under a label
  that says what it does. The bar's panel takes the keys only for a press on the message field
  (`ToolbarPanel.sendEvent`), since SwiftUI's buttons ask for them as a field does; a press on a
  button leaves them with the editor. The field counts as typed in only while the panel is key
  (`Model.keyed`), because AppKit makes it the panel's first responder when the bar comes up. There is no
  palette: a mark's colour says who drew it. Send starts on
  the session you came from (`AgentDestination.defaultTarget`). When the app before Vignette
  (`FocusReturn.previousApp`) was the Codex app, that is the thread it shows, or else the Codex
  thread used last; herdr's focus is ignored then, because herdr keeps a focused pane while its
  terminal is behind. The thread it shows comes from the app's own log (`AgentApp.shownThread`):
  each time its window moves to another page, the app logs the page's route, and `/local/<id>` is a
  thread. That is a log line, not an interface, so a build that drops it gives the thread used last.
  Accessibility cannot say: the app's window has had no page in its accessibility tree since the
  app left Electron in late September 2026 (openai/codex#25740). A thread older than the list is
  read by its id (`thread/read`). A Codex thread is named the way the app names it
  (`CodexConnection.name(of:)`).
  Otherwise, when herdr runs, it is the session in herdr's focused pane, or the one session in that
  pane's tab when the pane runs none. Else it is the session used last.
  The target shows the agent's logo and the project, cut in the middle past 132 pt with the whole
  name in its tooltip. Its width is set rather than left to the text, so it springs with the bar. A
  pick from its menu is applied a turn later, after the menu's own event loop ends, since a change
  made inside it jumped instead of animating. Its menu lists the active sessions used last, five at
  most, with the target always among them (`AgentDestination.menu`): a Claude Code session is active while the plugin's monitor runs in it,
  and a Codex thread when it was used in the last day, since nothing says which threads the Codex
  app has open. The target settles once, from the first answer that names a focus (herdr's comes in
  about 60 ms, before the bar is up), or else from the whole list (`Model.answered`). After that it
  changes only when its session is gone, so it never changes under the pointer. Codex's list is kept (`AgentConnection.keepsList`): an opening editor answers
  from the last one at once and asks for a fresh one, which comes in about 0.1 s for the five
  threads used last (`AppServer.listLimit`), and it is asked for again at launch, on a capture and
  when the stack opens. Claude Code's list is always asked afresh, because it carries herdr's
  focus, which moves. Coming from the Codex
  app, a kept list that holds the shown thread settles the target at once; one that does not waits
  for the fresh list, since the thread may be newer. Return copies and replies only on a card that names its session; Cmd+Return
  sends or replies (`EditorCore.finishes`). On the image, Return never sends to a session Vignette
  picked. In the message field Return sends, as in a chat app, with the target beside it.
  `docs/send-and-reply-2026-09-24.md` has the rules. While one image follows another with no gap (a click on
  another card, or the queue moving on) the bar stays on screen and springs to the next image's
  place, and keeps the image before's target until the next image's settles (`Model.begin`'s
  `carryingTarget`), since emptying it took Send off the bar for the listing's 60 to 90 ms and the
  bar jumped narrower and back: `place(below:gap:)` slides the panel when it is already up, one `Tween` per direction, over
  `Anim.passesTarget(ui.expandDuration)`, which is when the next image's window comes up. The
  springs move the panel's centre and top edge, so a change of size never moves the bar. When the
  offer changes, the bar springs to its new width inside the panel, which never narrows while the
  bar is up and is clear around it. The controls two offers share (Copy, the message field, the
  filled button) keep one identity so they move rather than cross-fade, and the bar's sides clip
  what comes and goes.
  `hideWindows` asks for the exit through `hideSoon`, which waits one turn of the run loop and is
  cancelled by the next `place`; a swap's park answer and the next `prepare` land in that same turn,
  so the reducer says nothing about this. The panel always keeps
  the room above and below the bar that the message field grows into, clear, since a panel that
  grew when the field took focus moved the bar for a frame. The field grows down, and up out of the
  bar once it nears the bottom of the visible screen (`Model.roomBelow`, `GrowingField`). No SwiftUI
  gesture may sit on the field's text: one took the release of a quick click, and the text field then
  waited for it with every event queued behind, Esc included, until the next click. The padding's
  gesture is behind the box.
  `[state] annotator.toolbar` is the panel's frame without that room, or null when it is off screen.
  Tab goes from the last mark to the bar's controls and back (`AnnotatorToolbar.enter`, `move`,
  `EditorView.enterCanvas`). While a control has the focus the editor keeps the keys and hands Tab
  and Space to the bar (`EditorView.takesKey`), except in the message field, where the bar's panel
  has them and takes Tab first (`ToolbarPanel.sendEvent`). `[state] annotator.toolbarFocus` names
  the focused control, and `annotator.toolbarKey` says whether the bar's panel has the keys. The
  bar draws its own tooltips (`TipSpot`, `TipLabel`): AppKit shows a window's tooltips only while
  it is key or was the last one clicked, so `.help` on the bar showed nothing until the bar was
  clicked, and `allowsToolTipsWhenApplicationIsInactive` did not change
  that. The target's menu is an `NSMenu` (`showTargetMenu`), since SwiftUI's `Menu`
  cannot be opened from a key. Space opens it a turn later: opened inside the editor's keyDown it
  took no keys, and a press on its item closed the editor as a press outside. `docs/annotator-toolbar-2026-09-19.md` has the numbers.

### The editor and drawings

- The editor is a pure reducer and a view that decides nothing. `EditorCore.reduce` takes one
  `Input` and returns the `Effect`s to run, in order; `EditorView` turns events into inputs, runs
  those effects, and draws the core's state in one `CATransaction`. What a press hits is
  `core.target(at:)`, tested against the overlay as drawn and then the marks, so a test drives the
  core with no window. Cmd+Z and Shift+Cmd+Z always reach the editor (`performKeyEquivalent`), so
  one owner handles undo whether a text is being typed or not; while typing, the core takes only
  the keys `takesKey` names and the text view gets the rest, and an input method's composition owns
  every key until it is confirmed. A character right after a box is drawn starts a note for it
  (`startsNote`): the core begins typing and answers `passKeysToText`, and the view replays the key
  event into the text view, so an input method or a dead key composes as usual. A tool key then is
  held (`holdKey`, `heldKeys` in the view) until the next key shows whether it began a word. A Cmd key the core does not take goes on to the menu.
  `docs/editor.md` is the behaviour: keys, gestures, what a press hits, the clipboard, the file.
- A mark has one geometry, and the renderer owns it. `Mark.shape(pointScale:markStyle:)` gives a
  rectangle's, an ellipse's or an arrow's paths, which the renderer draws and `MarkLayers` puts in
  `CAShapeLayer`s, so a shape looks the same in the editor, on a card, in flight and in the PNG. A
  text is a note: a rounded tag in the mark's colour with its words on it, and on an agent's note a
  badge naming the agent (`docs/note-tags-2026-09-29.md`). `TextLayout` owns the tag's geometry,
  its padding, the 18 em cap and the balanced line breaks, and its `box` is the tag, which is what a
  press hits and what is kept inside the image. The tag, the badge and the letters are drawn only by
  the renderer (`MarkRendering.swift`, `NoteTag.draw`), with every letter filled in one pass. An
  agent's text is set in SF Mono and a person's in SF Pro Rounded, and an agent's badge names it:
  every place that lays a text out takes the style from its mark (`TextStyle.forMark`), and the
  editor's `layout(_:of:)` takes the mark, so none can forget. The text being typed wraps without
  balancing, and when typing ends its view springs to the balanced lines
  (`TypingField.settle`) before the drawn note replaces it. `EditorTextView`, the text being typed,
  draws the tag with `NoteTag.draw` under its words, wraps at the layout's `wrapWidth`, and sets
  every line's baseline from `TextLayout` through its layout manager's delegate, so typing and the
  drawn text meet within half a point. The badge's logo comes from `AgentLogos`, which rasterizes
  `Resources/agents/<name>.svg` once so any thread can draw it.
- `MarkLayers` is the one on-screen drawer for a drawing's marks: the editor (`EditorPicture`), a card
  (`MarksView`) and a flight, so a mark looks the same in each and nothing steps when a flight hands
  over to the editor. A text is a bitmap the renderer draws off the main thread, on
  `MarkLayers.textQueue` for the editor and flights and `cardQueue` for cards, so a stack of long
  texts never delays the one being edited. The bitmap is an `IOSurface`, because Core Animation
  copies a `CGImage` on the main thread at the commit that shows it and doubles its memory
  (`docs/native-editor-2026-09-23.md` has the cost). A bitmap is shown only while its text still
  wants exactly that `Target` (mark, region, scale, style), so a bitmap never crosses styles, and
  none is shown after `park()`. A text keeps at most two bitmaps, a whole and a sharper detail, the
  one on its way included. Each owner's plan caps them: the editor's at the view's size in device
  pixels, a card's at the part of the image the card shows at its rest size. The comments in
  `MarkLayers.swift` and `MarksView.swift` say how bitmaps are shared between the editor and a
  flight, restyled, and flattened on a card.
- Drawings are owned by the app, and every write goes through `Drawings` (`Drawings.swift`, with
  `DrawingStore` for the files): one JSON file per screenshot under
  `~/Library/Application Support/<bundle id>/drawings/`, named by a hash of the file path the app
  uses everywhere (`shot.url.path`). The editor hands its drawing over 0.3 s after each change,
  never while a button is held (`[drawing] saved`), and once more when it parks (`parked`). Until
  then the open drawing is ahead of its file, so whatever needs a screenshot's drawing as it is now
  (Copy Drawing, Stitch, a drag) asks `Drawings.current(of:)`, which answers the open drawing over
  the stored one. `Drawings` reaches the editor only through `OpenDrawing`, which `EditorView` is.
  Agents' marks arrive through `Drawings.add` (`built`, or `saved` when they join the open drawing:
  the editor's `join` answers the joined drawing and `add` writes it). A drawing with no marks removes its file. A drawing with marks whose screenshot is gone is not
  written (`[drawing] dropped <name>: its screenshot is gone`). `onChange` hands each card its
  drawing, so a write reaches the card at once. `load` takes a list and reads it in one job off the
  main thread, and a stack opening reads its cards' drawings in one such job per turn and changes
  `cards` once (`ThumbnailController.setDrawings`). A key written or removed while it was read is
  left out of the answer, since `onChange` already said what it is. A file that does not parse is
  set aside as `<id>.json.invalid` only by the launch scan (`DrawingStore.scan`), which runs before
  anything reads or writes a drawing. A read at any other time logs
  `[drawing] error invalid <name>: <reason>; opened without it` and leaves the file where it is.
  Reads run beside the main thread's writes, so a read that moved the file could move a good one a
  write had just put in its place. A newer build's file, another screenshot's, or one made on an
  image of another size is read as no drawing and left where it is. Cleanup waits for a successful
  `ScreenshotWatcher.Inventory` for that drawing's folder. It uses enumerated presence and the
  observation time; unavailable folders retain their inventory and drawings. A positive file lookup
  also preserves a file created since the observation or reached through a case alias. The removal
  callback applies the same check to cards, drawings, and reply records. Suppressed removals stay
  pending until a listing enumerates their presence or confirms their absence. Writes newer
  than the observation wait for another scan. Trash removes drawings only for files it successfully
  trashed. `docs/system-design-work-2026-10-02.md` records the verification. The launch also
  removes what the web editor left, its drafts and WebKit's data, where they are still there
  (`Drawings.removeWebEditorData`, one `[app] removed web editor data <path>` line each); drafts are
  not carried over.
- Done, Send, Copy Drawing and a drag of a card with a drawing render on `RenderingQueue.shared`, one
  at a time, off the main thread: one rendering of the largest capture holds two bitmaps of about
  85 MB. Done's rendering, and Cmd+C with nothing selected, go `.first`, ahead of any rendering that
  has not started, because Done's clipboard is a promise. `Clipboard.copyRendering` puts the path on as text at once and promises
  the PNG, the TIFF and the file URL; a paste that comes first waits for the rendering on the main
  thread for up to 5 s, then gets nothing and logs `[clipboard] error`. The card goes home at once.
  A dragged card with a drawing carries the same item (`Clipboard.renderingItem`), rendered in turn
  from the moment the drag begins and written as `<name>-<result-id>-annotated.png`; a card without one drops
  its file.
  A rendering that fails clears the clipboard, unless something else was copied since, and the card
  says "Not copied" and why in place of its Copied notice (`ThumbnailController.showNotCopied`,
  `Rendering.Failure.reason`). `[annotate] done files=["<absolute path>"] <n> bytes, copied` is
  logged when the file is written. `copy-annotated` and drag completion report the same JSON
  `files=` array. `RenderingQueue` allocates each result path and `PendingRendering` owns it;
  clipboard callers supply only the pending result. Completed files stay until the person deletes
  them. The source-name prefix respects filename and full-path limits, including the physical
  path behind directory symlinks, while keeping the full result id and `-annotated.png` suffix
  (`docs/adr/0018-rendered-files-are-immutable-results.md`). A drawing with no marks copies the
  original file and writes nothing. Send renders even an empty drawing through the queue, to preserve displayed orientation
  and DPI, and writes no file beside the source.
- A mark's colour says who drew it and is not stored: `Mark.color` names a person's colour or the
  agent colour (`MarkColor`, from `agent`), and `MarkStyle.color` gives the settings' red or indigo.
  Contrast comes from a 1.5 pt white edge (`MarkStyle.edgeWidth`) around every mark, notes included,
  which casts the tag's shadows. An agent's
  `color` in `marks=` is ignored and logged. An agent's note becomes the person's when typing ends
  with its words changed (`EditorCore.endTyping`), as one undo step; a move or a resize keeps it the
  agent's. `docs/mark-colour-2026-09-29.md` has the reasons and the candidates.
- A drawing's sizes are in points of its own `pointScale`. A new drawing in the annotator takes the
  backing scale of the screen it opens on; one an agent's marks create takes `NSScreen.main`'s, the
  best guess with no annotator open. Both are clamped to `Drawing.pointScales`. A stored drawing
  keeps its own, so a mark keeps its size in the image when the drawing is opened on another screen.

### Zoom

- Zoom belongs to the annotator, not the editor. A pinch, a two-finger double tap and a wheel over
  the editor go straight to `AnnotationController` through `onZoomGesture`, with the trackpad's
  phases: a pinch and a wheel with cmd or ctrl held zoom, and a plain wheel pans a magnified
  picture. The zoom keys, cmd+plus/minus/0, and a double-click on empty space with the select tool
  are the core's to recognise, because it knows the tool and what is under the pointer, and it sends
  them as a `ZoomRequest` through `onZoom`. While typing, the editor sends the caret's rect in image
  px through `onReveal` whenever it moves, and the zoom pans a magnified picture just far enough to
  show it, since a text wraps at the image's edge and not the frame's.

  The rules are one pure value, `AnnotatorZoom` (`Sources/AnnotatorZoom.swift`), held by
  `AnnotationController`. The controller turns events into its inputs: a wheel's lines into points,
  the trackpad's phases into a hand and a lift, and a point in the window into a fraction of the
  frame. It runs the spring the zoom asks for on a `Tween`, scaled by the motion setting, sends each
  tick back, and puts the frame and the picture where the answer says. Nothing zooms until the
  flight has landed or once the card has started home: the editor takes keys from `prepare` and
  presses handed over from the flight, a zoom before the landing would grow the window under a
  flight image still at the fitted frame, and the card flies home from the fitted frame. The
  zoom's phase is `annotator.zoomPhase` in the state report: closed, flying, landed or closing.
  Add a sequence to `AnnotatorZoomTests` before changing a rule; its random-sequence test checks
  the invariants through a spring that ticks part of the way, turns, and arrives.

  All of them move one number, the level: how far the image is magnified past the frame it opened
  in. The picture is magnified uniformly by that level, so the image is never stretched. The frame
  is not: each of its sides grows with the level until that side fills the room it was given, the
  visible screen less the strip the recent stack keeps. `Zoom.split` divides the level in one place,
  one division per side, so `window * camera` is the level in each direction. Zooming out stops at
  the fitted size. Only a hand pulls below it, with a short pull that springs back when the fingers
  lift; a key or a mouse wheel's notch stops at the fit. Zoom's springs are in code rather than the
  tweaks, but the motion scale still shortens them. `Sources/Zoom.swift` is the geometry. Its
  comments, and those on `AnnotatorZoom.aimFrame`, `aimPan` and `Tween`, say how the spring, the
  anchors and the edge pull work, and `docs/zoom-input-2026-09-19.md` has the measurements behind
  the anchor. `docs/annotator-zoom-2026-10-01.md` has the design of `AnnotatorZoom`.

  One process draws the frame and the picture, so a zoom step is one commit. `moveFrame` is the only
  place the frame's rect is set. In one run loop turn it sets the frame from `Zoom.frame` and the
  picture inside it from `Zoom.picture`, and hands the editor its new size and picture together
  (`EditorView.setSize(_:picture:)`), so the marks, the overlay and the text being typed follow in
  that same turn. The texts are drawn again for the new zoom once the picture has stayed put for
  `EditorView.restDelay`. The state report's `annotator.zoomLevel` is the one number,
  `annotator.zoom` and `annotator.canvasZoom` its two halves per direction, `annotator.zoomAnchor`
  the point the window grows away from, `annotator.zoomCenter` the middle of the visible part, and
  `annotator.room` the rect the frame may grow within.

### Live ink

- Live ink is drawing straight on the screen, over any app, while Control and Option are held. It
  is an option (`liveInk`), and `LiveInk` owns it: the chord, and a surface per screen per Space,
  each a `LiveInkOverlay` and the marks on it. Steps 1 and 2 of
  `docs/live-ink-integration-2026-10-04.md` are built: a mark stays at its place on the screen, on
  the Space it was drawn on, until it is erased or Vignette quits, and an ask about it is answered on
  the screen. Marks do not follow a scroll yet.
- An overlay joins no other Space, so macOS keeps it where it was put up; it is closed, never
  ordered out, since ordered in again it would come up on the active Space. A surface exists while
  it has marks, and the active Space's while the chord is held, so an idle live ink puts no
  full-screen window over every app. An overlay is shared with no capture (`sharingType = .none`), so
  a screenshot leaves the marks out. macOS's window picker (Space during ⌘⇧4, or ⌘⇧5's window
  capture) still takes the window whose pixels are under the pointer, at any level, and reads the
  windows when Space is pressed; over a mark it took the overlay and could not capture it. So after
  ⌘⇧ (`CaptureOrigin.onCaptureKeys`), while there are marks, live ink clears its overlays (alpha 0,
  which the picker passes over) for as long as a `screencapture` process runs or `screencaptureui`
  has a window up (`LiveInk.watchForWindowPicker`). At rest it sits at level 1, above normal windows and below
  the dim (2) and Vignette's floating windows, so the stack and the annotator cover the marks, and
  so do menus, the Dock and other apps' floating windows. It passes every press then
  (`ignoresMouseEvents`). While the chord is held it is inking: it rises to `.screenSaver` with the
  flag off and takes every press, over clear pixels too, as the click rule above says.
- Inking never covers the stack or the annotator. The chord does nothing while
  `ThumbnailController.holdsScreen`, and either coming up while it is held ends the inking
  (`onTakesScreen`). A chord let go mid-stroke keeps the overlays raised until the button is up,
  read from the button's state as well as the release.
- The chord is `HeldChord`, a pure value with tests: exactly ⌃⌥, ended by any key or another
  modifier, and not begun again until its modifiers are let go, so a window manager's ⌃⌥-arrow
  never inks, and neither does letting go of ⌘ out of ⌘⌃⌥. A key another app takes as a shortcut
  reaches no event monitor (measured with a Carbon hotkey), so `ModifierChord` reads keys from the
  HID state, every 50 ms while the chord is held. It has no hold threshold; the glow waits
  `ui.liveInkGlowDelay` instead, or shows at the first press. An overlay never becomes key. Erasing
  is a tap on a mark with the chord held, not a key: Vignette sees a key but cannot keep it from the
  frontmost app, where ⌃⌥⌫ deletes a word.
- Marks are `Mark`s in global top-left points at a `pointScale` of 1, drawn by `ShapeMarkLayer` as
  the editor draws them, and so is the stroke being drawn, on every screen it crosses. `InkStroke`
  reads a stroke: a loop is the ellipse round it, and any other stroke the editor's freehand arrow
  (`Mark.Arrow.freehand`, at the editor's tolerances). A stroke under `ui.shortestArrow` is a tap,
  which erases the topmost mark whose stroke it is within `LiveInk.eraseReach` of, measured as the
  editor measures (`EditorGeometry.strokeDistance`), or else the smallest ellipse it is inside. The
  reach is wider than the editor's, since nothing shows which mark a tap would erase.
- `vignette://live-ink-clear` erases every mark, and `live-ink-stroke?points=x,y;x,y` (debug) takes
  a stroke as if by hand, whether the stack is up or not, so a script can test without posting
  input; it answers what the stroke did. `[state]` has a `liveInk` section: `on`, `inking`, `chord`,
  the surfaces with their frames, whether each is on the active Space and how many marks it has, and
  every mark once with its frame.
- Letting go of the chord after drawing opens `LiveNotePanel` beside the new ink, a non-activating
  panel that takes the keys as the stack's does. It is drawn as the note it becomes, and its target
  is a chip under it. Return asks about the ink drawn since the last ask, or, with none, about the
  ink asked about last. Its target starts on the one picked last, else the responder, and lists the
  sessions Send lists after it. The words stay beside the ink as the person's own note, whichever
  target answers: the chip fades and the panel hands over to the drawn note without the words
  moving (`settle`). The note opens against its ink, where a hand writes one
  (`LiveAnswerLayout.noteSpot`): touching an arrow's tail on the side away from its head, or beside a
  loop's edge. It may cover the window's text there, and never moves elsewhere, since a note away from
  its ink reads as being about something else. Left of the ink it grows to the left. Placing it needs
  the window's frame and text, which `LivePacket.Glance` gives in about 20 ms after the capture:
  Vision's fast level, for where the lines are, not what they say.
- An ask sent to a session goes through Send, as one line that names the app, the window and its
  URL. The person's words stay beside their ink as their own note, and both shimmer until the
  session's turn ends (`LiveInk.watchWorking`, from the `turn` file the plugin's hooks write in its
  inbox; a route that cannot tell stops after 3 minutes). A send that went says nothing more. The
  session sees its own change land, so the skill asks it to answer on the window only when pointing
  helps. It does that with `scripts/reply --answer`: words, and up to four marks that each
  name words on the window (`LiveAnswer`, in the reply's bundle). `LiveInk.showAnswer` captures the
  window the ink is on afresh (`LivePacket.build(window:)`), finds each mark's words in its text,
  since the session has usually changed what it shows, and draws the answer beside the ink as the
  responder's are drawn. The reply's stage is then `shown`, with no file. An answer that cannot be
  drawn there, because the ink was cleared, a newer ask is under way or the app relaunched, becomes
  a card with the words in its corner (`Reply.cardMarks`). `docs/adr/0021-a-sessions-answer-to-live-ink-is-drawn-on-the-window.md`
  has the reasons.
- An ask is answered by `LiveResponder`: one `claude -p` process in stream-json mode, run with
  `--safe-mode --tools ""`, its own system prompt, and `--json-schema` for the answer
  (`LiveAnswer.schema`). Started plainly, the process registered itself as a session in Vignette's
  inbox and could read files, so those flags are the isolation, and the process stops before any
  screen content is sent unless its `init` line lists no tool but `StructuredOutput` and no MCP
  server. It starts at the first inking and sends a short warm-up ask ($0.001 to $0.008) that checks
  that line and caches the prompt. It stops after 10 minutes with nothing asked, and when the ink is
  cleared or live ink is turned off, and starts a new conversation after 12 asks. In a test launch it runs only the `claude` that
  `VIGNETTE_CLAUDE` names, since any other runs on the person's account;
  `scripts/e2e/fake_claude.py` stands in for it.
- `LivePacket` is the ask's content, built in about 300 ms: a ScreenCaptureKit capture of the
  topmost window under the ink below the Dock's level (the Dock has a window over the whole screen at
  its level), Vision's accurate text lines read before the ink is drawn in, with ids, the person's
  ink drawn into the picture and listed as boxes, and the app, title and the Accessibility document
  or web area URL. Ink across a line garbled what Vision read of it, and the fast level garbled code
  (`docs/live-ink-step2-spike-2026-10-04.md`). A follow-up to the same window showing the same text,
  in the same conversation, sends no picture. Capturing needs Screen Recording, which the switch asks
  for when turned on (`ScreenRecording.request`, macOS's own alert, once); a row under the switch and
  the menu's first item open its pane. On macOS 15 the first capture also raised macOS's "bypass the
  system private window picker" alert.
- The answer streams in: `say` is drawn as a note under the person's note as its words arrive
  (`LiveAnswer.partialSay`), left-aligned with it, so the question, the reply and its actions read
  as one thread. It goes right above the note when the room ends under it, and beside the ink when
  there is no note. It wraps at `ui.liveInkTextWidth`, and the marks draw themselves on when the
  answer is whole (`ShapeMarkLayer.drawOn`). `LiveAnswerLayout` places them in global points inside
  the page (a browser's web area, from Accessibility, else the window), clear of the person's ink,
  the window's text and each other, and no note covers what the answer points at: a circle round a
  long line is a box, a circle on a loop of the person's is an arrow, and a label goes beside its
  mark, at an arrow's tail, with the arrow's side chosen for where its label fits. Labels are
  `Mark.isLabel`, drawn without the agent's badge, so only the reply names the agent. The reply
  follows the ink it was about, as the person's note does, so the thread moves as one; a pointing
  mark is anchored to its own content, and a label follows the mark it names. They are agent `Mark`s on the same surfaces, so a tap
  erases them (a note's tag counts) and Clear clears them, and the next ask takes them off. Notes on
  the overlay are `NoteLayer`s, a bitmap `Mark.draw` makes on the main thread, not `MarkLayers`,
  which draws a drawing on an image.
- Vignette's own words about an ask (sending, sent, failed, why) are a note beside the ink in the
  person's colour without a badge, not an agent mark, and are not ink: the next ask is not about them.
- A session picked in the note's target gets the picture through `ScreenshotRequests.send`, as Send
  sends a drawing, with the words and where the ink is in the line. The client's answer goes to the
  ink (`LiveInk.delivered`) rather than a card.
- `live-ink-ask?message=` (debug) asks as Return does, and `&session=<id>` sends to that session.
  `[state] liveInk` adds `new` (ink not yet asked about), `note`, `responder` and `ask` (phase,
  whether it sent a picture, the reply's length), and each mark's `agent`; `app.screenRecording`
  says whether captures are allowed. A test launch with `VIGNETTE_SHARE_LIVE_INK` set lets captures
  see the overlays, so a script can look at what was drawn; the overlay rests under floating
  windows, so a test window that floats keeps the ask on it and must be lowered to be looked at.

### Memory

- Memory is bounded where images are held. `Thumbnailer` keeps decoded images under `budgetBytes`,
  least recently used out first, and screen-size flight decodes are dropped whenever the stack
  hides. Every image that reaches a card, a flight or the editor is decoded before it gets there
  (`Thumbnailer`), in the colour space of the screen it will be shown on (`space:`, from
  `NSScreen.colorSpace`). Core Animation does any work left at the first commit that shows an
  image, on the main thread: it decodes an `NSImage(data:)`, and it converts an image in any other
  colour space. That conversion cost 21 ms for a 3024 by 1964 sRGB image, and 0.05 ms once
  `Thumbnailer.converted(_:to:)` had redrawn it. A capture from the same display is already in that
  space; an agent's push, a stitch or a capture from another display can be in another. The redraw
  is 8-bit, so a deeper image is left as it is. A cache entry records the space it was decoded in,
  and a lookup in another space misses. Renderings and stitches read the file
  itself, so their output does not change. The editor shows the screenshot decoded no larger than
  the visible screen in device pixels, which is the same decode a flight asks for and is counted in
  the thumbnail cache's budget (both ask `Thumbnailer.screenPixels(on:)` and the screen's colour
  space); `editor.clear()` lets it and the marks' layers go when the annotator hides, and
  `removeCards` lets a card's marks go when it leaves the column. Text bitmaps are capped by their
  owner's plan (the `MarkLayers` rule above), and renderings run one at a time (`RenderingQueue`). A
  stitch decodes one piece at a time and draws at the capped output size.

### Build, signing and Apple defaults

- Swift language mode is 5 (see `project.yml`). No sandbox, on purpose: the app writes Apple's
  `com.apple.screencapture` defaults, watches a folder the user names without security-scoped
  bookmarks, and installs global event monitors. The hardened runtime is on.

  Signing: project.yml defaults to ad-hoc so any clone builds; `scripts/build.sh` reads the
  gitignored `scripts/signing.env` (identity and team) and this Mac's names the Developer ID
  certificate. Keep it that way here: Accessibility trust is tied to the signature's designated
  requirement, and an ad-hoc signature changes on every build (`docs/building.md` has the details).
  `ENABLE_DEBUG_DYLIB` is off in project.yml: with it on, a Debug build loads its code from
  `Vignette.debug.dylib`, which the hardened runtime rejects for a signer without a team ID, so a
  self-signed build crashed at launch. macOS keys Accessibility by bundle id: a second copy of
  the app with the same bundle id and a different signature shares the row and stays untrusted,
  so a test build that must be trusted needs its own bundle id.

  `Info.plist` is generated by xcodegen from `project.yml` and is gitignored.
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
- Updates come from Sparkle (`Updater.swift`). The app checks the feed that `SUFeedURL` names once a
  day, and nothing installs until the person presses Install in Sparkle's window. A version a
  scheduled check finds waits as a gentle reminder, Sparkle's name for one that does not take the
  focus (`supportsGentleScheduledUpdateReminders`): a dot on the status item, with a clear ring cut
  into the icon around it, and an "Update Available…" item at the top of its menu. With the menu bar
  icon hidden there is nowhere to show the reminder, so Sparkle shows its window, without activating
  the app. `[update]` lines log what each check found, and `[state] app.update` says what is waiting.
  Sparkle compares `CFBundleVersion`, which the build phase stamps with the commit count. So each
  release needs more commits behind it than the last, which a release cut from main has. Every
  download is checked against `SUPublicEDKey`. Installs trust only images signed with the private key
  in the Keychain account `vignette`, so a lost key leaves every install unable to update. The
  trailer's stage copy turns the checks off. Sparkle relaunches an updated app through
  LaunchServices, with no environment, so a test copy that must stay on scratch files sets
  `VIGNETTE_SETTINGS` and `CFFIXED_USER_HOME` under `LSEnvironment` in its Info.plist.
  `docs/updater-2026-09-27.md` has the tests.

### Agents

- `docs/codex-issues.md` tracks the known problems with Codex and the Codex app, with a progress log.
  Read it before changing anything that talks to Codex, and add to it what you find or fix.
- `docs/glossary.md` is Vignette's vocabulary: screenshots and the corner, drawing, and the agent
  loop. It says what each word means and what not to call it. Use its words in code, docs and
  labels. The distinction it guards most is that an agent session is a conversation and a pane is
  a place.
- Sending a drawing to an agent session and taking its drawing back is one object,
  `ScreenshotRequests`, and one small boundary, `AgentConnection`. Two things are durable and
  different: **acceptance** means Vignette owns every byte of a reply, and is what the receipt a
  helper waits for acknowledges; **publication** means the reply is a card. Between them the reply's
  watch-folder name is reserved and excluded from every listing, so an interrupted import leaves
  nothing half-shown. `isVisible` is derived from the reply record, not a second ledger, and it
  fails closed: a file named `Agent reply <uuid>.png` with no `published` record is hidden, whoever
  wrote it. Only that exact name shape is managed; a screenshot merely starting with "Agent" is an
  ordinary capture. Naming one is refused the same way listing it is: a `file=` on a reserved reply
  answers `missing-file`, and `add` refuses a source with that name outright, since the copy would
  have no record and so could never be shown. Reservation persists the actual destination URL
  before copying. Visibility and origin use that location; a later screenshots-folder change does
  not move an existing reply. Startup loads the records before the watcher starts, then waits for
  successful current-folder inventory before recovery. Deletion needs confirmed absence in the
  reply's own folder. Locationless published records are retained conservatively.
  `Drawings.installReply` writes one complete drawing before publication. Recovery reuses a valid
  checkpoint's geometry and point scale. Strict reads refuse missing marks, invalid fields, wrong
  image size, or shapes outside the image. Text anchors are checked without reflowing their stored
  geometry under current typography. Additive pushes still use `Drawings.add`.
  Clearing commits the terminal request record before removing payloads and unpublished outputs.
  A failed commit retains the state and files. Late transport outcomes report delivery without
  reopening the request. Cleanup uses recorded locations and replays after restart; unresolved
  output cleanup prevents retention pruning. Completed cancellation records remain untouched on
  later scans; failed record writes remain pending until persistence succeeds. Published files
  remain the person's.
  A managed reply is never a capture after publication, so late watcher events cannot copy or
  open it. Its own import inserts the card once. At `maxLiveRequests` a send stores its new
  candidate before clearing the oldest of 50 open requests. Failed retirement discards the
  unsubmitted candidate. A pre-existing over-limit store requires explicit clearing before Send.
  Cleared request folders are removed after a week only when no published reply or unfinished
  output cleanup still needs their records. `docs/request-safety-plan-2026-10-02.md` records the
  contracts and verification.
- A destination is an agent session, never the terminal displaying it. Codex is addressed by its
  thread UUID and nothing else: `codex queue --thread` resolves the UUID in the thread store or
  fails, which is `AddressGuard.runtimeEnforced`, and stores the message in Codex's queue. An engine
  that has the thread loaded, the Codex app's or a CLI session's, takes it within about 10 s. A
  thread no engine has loaded keeps it until someone opens the thread, and it then runs first.
  `codex queue` answers the same either way, so Vignette then looks for the lock file an engine
  holds while it has the thread (`CodexConnection.isLoaded`), and a send to a thread nobody has
  open is reported as queued. The codex Vignette runs is the one inside the Codex app when the app
  is installed (`AgentApp.codexCLI`), since the app keeps it in step with its own engine, and
  otherwise the first `AgentTools` finds. `AppServer.swift` is the only thing that
  speaks the app-server protocol, and it only reads: it carries a `thread/list` to a `codex
  app-server` of its own, asking for the threads used last (`sortKey: recency_at`), and a
  `thread/read` of the thread the Codex app shows, and turns the answers into menu rows, each
  with the thread's own `cwd` and `recencyAt`. An ephemeral thread and a sub-agent's thread (one with
  a `parentThreadId`) are left out. A thread with no name is named by its first message. The thread store is on disk,
  so a server started for the length of that one listing answers for every session, whoever owns
  it; the listing's `status` is that server's own memory and says nothing about a session, so it is
  not kept. No `codex` on the machine means no Codex destinations, which is not an error.
  `docs/codex-discovery-2026-09-21.md` has the protocol, the timings behind `listLimit`, and what
  was verified against a live desktop session. Claude Code is addressed by
  its session id, through the plugin's inboxes (`ClaudeCodeConnection`): one folder per Claude Code
  process, `claude-sessions/<pid>/` under Application Support, holding the session it runs now, its
  folder and a file its monitor touches every 3 s. Only a session whose process and monitor are both
  alive is listed, since only those can receive, in any terminal. The inbox's folder is the
  session's project. Its row comes from its transcript, `~/.claude/projects/<folder>/<id>.jsonl`,
  read from the last 256 KB: the last `ai-title` names it, and the last user or assistant entry's
  `timestamp` is when it was last used. That entry's `cwd` follows the session's shell, so it is the
  project only when the inbox gives none. The file's modification time is
  not the last use: Claude Code writes entries with no message in them to transcripts it is not
  using (measured 2026-09-24). herdr, when it runs, only says which session has the focus. `/clear`
  and `/resume` give the same process another session, so Vignette checks that the inbox still
  holds that exact session immediately before writing the line (`AddressGuard.preflight`). A
  session in no inbox is an error, "closed" or "cleared", and never another session. The line is
  accepted once it is in the inbox; the session reads it when its turn ends. The image travels as a
  path the session opens itself, so a Claude Code session that may not read it stops on a permission
  prompt, which Vignette cannot see. So turning Claude Code on, in setup or the Agents tab, also
  adds `ClaudeReadRule`, one `Read(…/requests/*/image.png)` rule in `~/.claude/settings.json`'s
  `permissions.allow`, which lets Claude Code open the sent images without asking, and turning it
  off there removes the rule. While the plugin is in, the Agents tab has a switch for the rule
  alone. A launch never adds it, so an install from before this keeps what it had. It writes through a link to that file, since people keep it in a dotfiles
  repository; a skill's `allowed-tools` was tried and made Claude Code ask to use the skill
  instead. The two tiers
  are recorded on every request and reported in `[state] requests`; `docs/closed-agent-loop-implementation-2026-09-20.md` says why the weaker one
  is still allowed to submit.
- A `vignette://` URL has no authenticated sender, so a reply is authorized by a per-request bearer
  secret in the request's own directory. The request line names only the image
  (`ScreenshotRequests.requestLine`, "From Vignette: …", then `sendInstructions` from settings.json),
  and the skill tells the agent that the
  ticket is `ticket.json` beside it and the helper is the skill's own `scripts/reply`, so an agent
  without the skill can read the drawing but not answer with one. The secret never travels in the
  line, because `[url]` logs every URL. Holding the ticket permits replies to that one request
  and proves nothing about which process wrote them. The helper writes its envelope where its own
  ids say it should be and Vignette derives that path itself, so a caller cannot name a file
  outside the request directory. Only the request root is resolved, because Vignette created it;
  every component below it must be real, so a link put in place of `submissions/<replyId>` is
  refused rather than read through. A refusal writes a receipt where the attempt's ids say, except
  when the authorization itself failed and a receipt is already there: the attempt id is the
  caller's to choose, and an unauthenticated one may not replace the answer a genuine attempt is
  waiting for. A reply's
  identity is a digest over the bundle file's own bytes and then the image's, which is why the
  helper and the app cannot disagree about how a number is spelled. The same reply id with the same
  digest is acknowledged from its record and makes no second card; with a different digest it is
  refused and the first is untouched. Raise `ReplyProtocol.version` with any change to what either
  side writes: a skill copy from before 2026-09-26 carries a Python helper that still answers.
- The reply helper is the app's own binary. `AppDelegate.main` hands `<binary> reply …` to
  `ReplyCommand` before an `NSApplication` exists, and it exits, so the app never starts. The
  skill's `scripts/reply` is a shell script, so the skill needs nothing a Mac does not ship:
  `/usr/bin/python3` is a stub that asks to install Apple's developer tools. It reads the ticket's
  `app` with `plutil` and runs that bundle's `CFBundleExecutable` only when its Info.plist has
  `VignetteReplyCommand` (project.yml): a binary without the command would start the app and
  replace the running instance. The ticket decides what runs, so the script takes only a ticket in
  `~/Library/Application Support/<that app's bundle id>/requests/<request id>/`. It finds
  `--ticket` the way `ReplyCommand.Options` does, and the command refuses a ticket another app
  issued (`checkIssuer`); change the two parsers together. The file is also Python that hands
  itself to sh, for agents that still hold the version 3 instructions. The command checks the marks
  with `AgentMark.parse` and converts the image to PNG before anything is sent, and the app refuses
  a reply image that is not a PNG, since it is published as `Agent reply <id>.png` and Copy puts a
  file's bytes on the pasteboard as PNG. `docs/reply-command-2026-09-26.md` has the reasons.
- The reply helper returns to the app that issued the request: `ticket.app` names the bundle and the
  helper passes it to `open -a`. Plain `open` hands a `vignette://` URL to whichever copy of the
  bundle id LaunchServices registered last, which on a Mac with a second build is a different app
  that answers `unknown-command` (observed). The helper reads the URL scheme from that bundle's
  Info.plist too (`ReplyCommand.dispatch`), so a fork's reply goes to the fork's scheme.
- Send never reuses Done. It renders the drawing on `RenderingQueue` and closes nothing while it
  waits. The request is stored before the image leaves the editor, so a failure anywhere before then
  leaves the drawing where the hand left it. A rendering belongs to the annotator session Send was
  pressed in (`annotator.session`). One that answers after that session ended is dropped, even when
  the same image is open again, and nothing is sent or closed
  (`[send] dropped <name>; the editor moved on`). `sending` stays on from the press until the bar
  has left, so the button keeps its paper plane through the exit, and `prepare` resets it, so the
  next image's toolbar never shows a send that is not its own. A list of agent sessions that
  arrives after its opening ended is dropped as well, including a close and reopen of the same
  image. Both discovery continuations compare `annotator.session`. A rendering that fails is a
  refusal, never a send of the bare screenshot: only a drawing with no marks sends the picture
  itself, and it goes through PNG whatever the capture's own format is. Send closes the editor
  without a Copied notice, and the queue carries on to the next card: a list of files to annotate is
  something the person asked for, and handing one of them to an agent does not withdraw the rest.
  Esc is the one that empties the queue, because that is a person stopping.
- A send reports on the card it was sent from. Once the request is stored the card
  carries a `SendNotice` (`ThumbnailController.showSending`), keyed by the file's path because a lone
  thumbnail's card leaves the panel while it is in the editor. It shows the destination's logo and
  project from the moment the card lands, and `delivered` turns it to sent, queued, uncertain or
  failed when the client answers. Anything but sent carries a `reason`: every `SubmissionOutcome`
  but `accepted` has one, written where the client knows what happened, and `detail` stays for the
  log. A card gone from the screen by then says nothing more about a success and comes back as a
  lone thumbnail for anything else. A failure before the request is stored leaves the drawing in
  the editor, so it shows there: the button reads "Not sent" and a popover on it gives the reason,
  both until a click elsewhere or Send again. A reply that was accepted and could not be made a card
  has no card to report on, so the card it answers takes a `replyFailed` notice, "Reply not shown"
  (`ScreenshotRequests.Callbacks.replyFailed`). A published reply is its own card and nothing else
  says it arrived. `docs/send-confirmation-2026-09-26.md` has the frames.
- The agent plugin (`agent-plugin/`) and the skill it carries (`skills/vignette/SKILL.md`) ship in
  the bundle as folder resources (project.yml), and `AgentPlugin.swift` installs them.
  `AgentPlugin.stage` writes a marketplace into Application Support: the template, the skill copied
  into `plugins/vignette/skills/vignette`, `scripts/inbox-root` naming this app's inboxes, and both
  marketplace lists named for the URL scheme, so a fork installs `vignette@<its scheme>`. It is
  assembled beside the old copy and swapped in whole. Each agent installs from it with its own
  command line tool (`PluginHost`): `claude plugin marketplace add`, then `claude plugin install
  … --scope user`; `codex plugin marketplace add`, then `codex plugin add`. Claude Code reads a
  folder marketplace in place. Codex copies the plugin into its cache, so its update is `codex
  plugin add` again. A root is `~/.claude` or `~/.codex`, or where `CLAUDE_CONFIG_DIR` and
  `CODEX_HOME` point, and only one that exists. A launch with `VIGNETTE_SETTINGS` never gets the
  person's own two, whatever the environment names (`AgentPlugin.guarded`, found from the user
  database, which `CFFIXED_USER_HOME` does not move). Roots are parameters everywhere, so a test never
  reaches the real ones, and the live check is `install-skill?root=<dir>` (debug only, a folder
  named `.claude` or `.codex`). The tools get the app's `HOME`, so a test copy launched with
  `CFFIXED_USER_HOME` installs into its scratch home. The Codex app's own codex needs nothing from
  `HOME`. A vite-plus shim does: it finds its package through `HOME`, so a test that runs one links
  the scratch home's `.vite-plus` to the real one, and unlinks it before anything lists Codex
  threads. Whether the plugin is on is read from
  the agent's own settings (`enabledPlugins` in Claude Code's settings.json, `[plugins."<id>"]` in
  Codex's config.toml), so a window asks without running a tool. Installs run one at a time on
  `AgentPlugins`' queue and answer on the main thread, and each result logs one `[plugin]` line.
  A launch writes the marketplace and updates an installed plugin whose listed version differs from
  the bundle's, or whose marketplace copy changed. It installs the plugin only where the skill from
  before the plugin is (`<root>/skills/vignette`, and `~/.agents/skills/vignette` for Codex), since
  that person chose the skill. Once the plugin is in, a folder there is removed; a link is the
  person's own and stays, with a `[plugin] kept` line. A launch never removes the plugin, and never
  installs it anywhere else. Raise the version in both of the plugin's manifests with every change
  to the plugin or the skill, and the skill's own `metadata.version` with every change to the skill.
  `agentSkill` in settings.json records only that the offer was made. Setup's last page makes it
  and records `off`. A file that finished setup before that page existed, or a setup closed before
  it, still reads `unasked`, and with an agent directory present the next launch makes the offer
  once as the Settings window at the Agents section. That window
  comes up with `orderFront` and does not activate the app: the user did not ask for it. The Agents
  tab's switches, setup's last page and `install-skill` are the only things that install the plugin
  somewhere new, and the switch is the only thing that removes it. A switch says Installing… or
  Removing… until the tool answers, and a failure is said under the agent's name. A launch's
  update of an installed plugin says a failure only in the log.
  The tools are found by `AgentTools`: the installers' folders, the version managers' (nvm, fnm,
  Volta, Bun, pnpm, asdf, mise), then the login shell's `PATH`, asked once at launch off the main
  thread (`[tools] login shell found …`). A lookup on the main thread answers at once with what is
  known, and setup and the Agents tab refresh on `AgentTools.found`. Without the agent's tool the
  switch is off and says which command is missing. After a Claude Code install, the Agents tab and
  setup's last page say sessions already open need `/reload-plugins`. An older file holding `on` is read
  as `off` (`validated()`). The app carries the plugin because someone who downloads Vignette needs
  their agent to learn the `vignette://` contract and, for Claude Code, to receive what Send sends.
  The app is the one thing they are sure to have and the one thing that knows which commands its
  version supports. `docs/claude-code-without-herdr-2026-09-27.md` has the design and its tests.

## Adding things

- An action: add a `ShotAction` to `Config.actions` and a method on the `Actions` protocol. Its
  `placement` decides whether it is a hover button on a card, a button in the selection strip, or
  both; `key` gives it a shortcut inside the recent stack; `kinds` says whether it takes
  recordings as well as screenshots. It is a `vignette://<id>` URL either way.
  Actions always receive a list of screenshots: in the order the cards were selected when the
  stack runs them, and in the order a URL names its `file=` parameters otherwise. `annotate` opens
  the first of them and queues the rest, since the annotator holds one image; its `ok` line says
  which is opening and how many there are (`ok <name> 1 of 3`), and each later card logs one
  `[annotate] next <name> 2 of 3`.
- An editor tool: add an `EditorCore.Tool` case with its label, key and SF Symbol, and handle it
  in the core's presses and drags. The toolbar shows every case.
