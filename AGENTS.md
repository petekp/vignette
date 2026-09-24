# Working on Vignette

Vignette is meant to be modified. This file is the onboarding for a person or an agent: the
rules, the contracts, and where the numbers behind them live. The dated notes in `docs/` hold
the measurements and the reasoning; a rule here points at its note.

## Layout

- `Sources/` Swift menu bar app. `AppDelegate.swift` wires everything; `Config.swift` holds the actions.
- `~/.config/vignette/settings.json` holds per-machine settings (`Settings.swift` defines the keys).
  Its `ui` section (`UITweaks`) holds the layout, style, timing, flight, and backdrop numbers, and its
  defaults are the tuned UI, so a fresh install renders the same. `open -g vignette://tweaks`
  edits them live (needs `debug`). A number stays in code when changing it would mean changing the
  code around it, or when it is a fraction of something rather than a size: the toolbar's rows and
  buttons (`AnnotatorToolbar.swift`), the card button size and the strip's icon and label sizes
  (`StackView.swift`, `StackLayout.swift`), the fly-back timing and the annotator's own shadow
  (`TransitionLayer.swift`), the zoom's springs and limits (`AnnotationController.swift`), the
  stitch's gap, padding, and badge (`Stitch.swift`), the editor's steps (`EditorCore`: the nudges,
  the copy offset, the snap angle, the 0.3 s hand-over), the editor's own colours (`EditorStyle`),
  the stroke width and the text outline (`Mark.strokeWidth`, `Mark.Text.outlineWidth`), and the
  colour pass (`ColorPass.swift`). The editor's sizes, its text's weight and line height, and the
  arrowhead's proportions are `UITweaks`, the Editor and Marks sections of the panel. A change
  reaches every place that draws marks at once: the open editor (`AnnotationController.applyTweaks`),
  the cards and flights (`ThumbnailController.applyTweaks`), and the next stitch, drag image and
  rendering, which read the settings when they draw. What a user would tune belongs in `UITweaks`
  with a `Bound` and a slider; when in doubt, put it there. Editing the file is a supported way to
  change settings; the app reloads it within a second. It is the user's real config: never test
  against it. `VIGNETTE_SETTINGS=<path>` in the environment
  (`open -g --env VIGNETTE_SETTINGS=/tmp/x/settings.json <app>`) points a launch at another file,
  and the launch line names it. The tweak panel writes to whichever file the instance was launched
  with, so copy the real file over the scratch copy before a test round and, before relaunching the
  real build, merge back any `ui` keys that changed (`[settings] wrote ui.…` in the log lists them).
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
  shares; `ColorPass.swift` is the colour pass, `AgentMarks.swift` turns an agent's marks into a
  drawing's, `RenderingQueue.swift` runs the renderings, and `Drawings.swift` keeps the drawings on
  disk. `docs/editor.md` says how the editor behaves.
- `scripts/build.sh` regenerates the Xcode project and builds the app.
  `scripts/run.sh` does that, waits for the old process to exit, and relaunches. `scripts/build.sh
  --test` also runs the unit tests in `Tests/` (the `VignetteTests` target compiles `Sources/`
  itself; it never launches the app). A build into another `-derivedDataPath` leaves `build/`,
  and an instance running from it, untouched.
- `Sources/AgentConnection.swift`, `Sources/ScreenshotRequests.swift`, `Sources/ReplyProtocol.swift`,
  and `skills/vignette/scripts/reply` are the closed loop: a drawing sent to an agent session and
  that agent's drawing sent back. See the rules below and
  `docs/closed-agent-loop-implementation-2026-09-20.md`.
- `Sources/Identity.swift` reads the bundle id, name, and URL scheme from the bundle and derives
  the log name, the status item's autosave name, the Application Support folder, and the Carbon
  hotkey signature from them, so a fork renames things in project.yml only. A second launch of
  the same bundle id quits the older instance (`[app] replacing older instance`).

## The loop

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
   folder, and `tweaks` and `install-skill?root=` are refused, unless settings.json has
   `"debug": true`. `add` is the exception, and it takes two paths the folder rule does not cover.
   `add?file=` copies an image in from anywhere and the watcher then reports it like a capture,
   minus the copy and annotate toggles (`&annotate` opens the editor). `&agent=<name>` says which
   agent is pushing it: the name is recorded on the copy as the `com.petepetrash.vignette.agent`
   extended attribute (`Agent.swift`, `xattr -l` shows it) and the card gets a white "From <Name>" tab
   with the vendor's logo when `Resources/agents/<name>.svg` has one (`Agent.logo(for:)`).
   `&marks=<json file>` pushes the agent's own annotations with the image (`docs/commands.md` has the format):
   they join the screenshot's drawing before the card appears (`Drawings.add`), so the human edits
   them like their own, and the command answers once that drawing is written. That JSON file may
   also be anywhere; it is read on the main thread, so it is capped at 256 KB, and an error line
   names the mark and the field without quoting what the file said. Every mark is moved inside the
   image (`Mark.placed`). A text mark is sized from the image's width, wrapped, and widened until
   the words fit the image's height; one too long to fit even across the whole picture is cut at
   the edge and named in a `[marks] text too long for <name>` line, which is the only thing that
   says so, since `[add]` still answers `ok` (`docs/pushed-text-2026-09-19.md`).
   `[annotate] loaded <ms>ms <name>` reports when the editor has the screen-size decode of the
   image, and `[annotate] takes events after=<n>ms reached=true|false` when its window starts
   taking presses; the flight's image waits for both before it lifts.
4. Look: `screencapture -x /tmp/s.png`, then crop the corner with `sips` and read the PNG.
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
   `stack` (cards with `file`, `frame`, `out`, `forming`, `drawing`, `agent`, `kind`; `selected`,
   `focused`, `hovered`, `queue`, the files waiting for the annotator, `visible`, `key`, `isStack`,
   `scroll`, `viewport`, `safeBottom`, the room the Dock keeps under the column, feedback, panel,
   `widthScale`, how wide the stack is drawn, and `strip`, the selection strip's frame or null),
   `transition` (phase), `annotator` (`current`, `frame`, `toolbar`, `windowVisible`, `key`, `tool`,
   and the zoom's own keys, which the zoom bullet below names), `editor` (`open`, `tool`, `marks`
   with each mark's `type`, `frame` and `agent`, `selection` as indexes into `marks`, `typing`,
   `undo`, `redo`; never a text's words), `drawings` (keys), `requests`, `memory` (rss and thumbnail
   cache in bytes), `backdrop`, and `dim`. Frames are `[x, y, w, h]` in global top-left points,
   except a mark's, which is in the image's pixels.
   `[app] ready pid=… build=… watching=…` marks the end of launch: after it every command
   answers. `build` is `git describe` of the checkout, written into the bundle by a build phase
   (project.yml), so a build from Xcode carries it too.
   Log grammar (`Log.swift`): one event per line, `HH:mm:ss.SSS [tag] …`, details as
   `key=value` pairs, never an embedded newline (the logger flattens them); the launch line ends
   with `date=YYYY-MM-DD`; at 5 MB the file rotates to `Vignette.log.1`, replacing the previous
   one. Drawing events: `[drawing] saved|parked|built|removed|swept <file>`, and `[drawings] <n>`
   after every change to the set. `[stack] shown cards=… files=… shown=…ms decoding=…` counts the
   watch folder from the watcher's index.

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
Compare before and after on the same driven sequence.

Measuring a stutter: launch the app under Instruments and drive it as above.
`xcrun xctrace record --template 'Time Profiler' --instrument 'Core Animation Commits' --env
VIGNETTE_SETTINGS=<scratch> --time-limit 75s --output perf.trace --launch -- <app>` (a
`--launch` also replaces the running instance; the Animation Hitches template attached to a
running process records no commits or samples on macOS). `xctrace export --xpath
'/trace-toc/run[@number="1"]/data/table[@schema="coreanimation-commit-interval"]'` gives every
commit with its duration; a commit over 8.3 ms dropped a frame at 120 Hz. `time-profile` samples
on the main thread that run without a gap are a stall; the frames from the `Vignette` binary name
the code. Trace time zero is about `[app] launched` minus the first sample inside
`applicationDidFinishLaunching`, which lines the trace up with the log. Compare before and after on
the same driven sequence; a single run varies.

## Rules that are not obvious from the code

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
- `docs/glossary.md` is the vocabulary for the agent loop: agent client, agent session, terminal
  host, destination, delivery route, screenshot request, screenshot reply, reply ticket. It says
  what each one means and what not to call it. The distinctions it keeps are load-bearing, above
  all that a session is a conversation and a pane is a place.
- Two vocabularies, and they do not mix. Every string a user reads says draw: the buttons, the menu
  items, the toggles, the section headings, the toasts. Every name a script, a log reader or a
  compiler reads says annotate: the URL ids (`vignette://annotate`, `copy-annotated`), the log tags
  (`[annotate]`), the settings keys (`quickAnnotate`, `annotateOnCapture`), the `-annotated.png`
  suffix, and every identifier. A label is free to change; those are a contract. The editor window
  is still the annotator in both, because it is a thing rather than an action.
- The annotator must open instantly, so the editor opens at `prepare`, before the image is
  decoded (`AnnotationController.open`). It opens with the screen-size decode when `Thumbnailer`
  has it cached, which it does after a hover, and with no image otherwise; `setImage` adds the image
  when the decode answers, and `[annotate] loaded <ms>ms <name>` is logged then. Opening first is
  what lets the keys work from `prepare`, and it leaves no moment in which an agent's push could
  miss the open drawing. `openGeneration` drops a decode or a colour sample that answers after
  another image opened.
- Every animation goes through `Settings.motionUI`: `ui.motion` (0 to 1) in settings.json scales
  every duration, and the system's Reduce Motion forces 0. Dwell times (`thumbnailSeconds`,
  `toastSeconds`) are not motion, and neither is a movement the user's own hand is driving: the
  drag-select's auto-scroll (`ui.autoScrollZone`, `ui.autoScrollSpeed`, `StackLayout.autoScrollSpeed`,
  ticked by a display link in `ThumbnailController`) follows the drag at its own speed whatever
  the scale says. `"ui": {"motion": 0}` makes the stack appear and leave at once, which is what a
  script wants. Every SwiftUI animation is a spring made by `Anim.spring` (`slideInCurve` "spring"
  included), and the AppKit tweens use `Tween`'s spring curve: an interrupted motion keeps its
  velocity and blends into the new target instead of jumping. `Tween.spring` is the closed form of
  a critically damped spring, so a late tick lands where the spring really is by then. Do not step
  it forward by hand: integrating it overshoots by hundreds of points after one late tick.
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
  (`annotatorTakesEvents`, `takingEvents`). The wait for `loaded` matters at motion 0: at motion 1
  the image was in 1 to 50 ms after `annotate` and the window came up 213 to 234 ms after, but at
  motion 0 the flight arrived 34 ms before the image, and lifting it then would show an empty
  editor. The wait for presses keeps the flight over the window until the window takes presses
  itself, so a press there never falls through to the app behind. `fly` answers a second time,
  earlier, at `Anim.passesTarget`: from the moment a bouncing spring first reaches its target the
  flight's rect contains the target on every side, so the annotator's window comes up there, with
  its own shadow off (`AnnotationController.show`), hidden behind the flight image until `arrived`.
  That is what makes the editor take the pointer the moment the card looks still: the toolbar and
  the outside-click monitor start with the window, and a shadow is the one thing that would show,
  because it falls outside the frame it is cast from. The keys come earlier: `prepare` orders the
  window in at alpha 0 and makes it key, so a tool key or Esc pressed during the flight already
  reaches the editor. Presses come later: the window server passes every press through a window at
  alpha 0, and starts giving the window its presses 6 to 39 ms after `show` sets alpha 1, or up to
  97 ms under load. Nothing announces that moment, so `AnnotationController.probeEvents` asks the
  window server every millisecond from `show` whether a press at the frame's centre reaches the
  window, looking through this app's windows above it. It gives up after 0.5 s.
  `[annotate] takes events after=<n>ms reached=true|false` reports the answer, and `reached=false`
  means it gave up. Until then the flight takes the presses (the next rule). Done or Esc is accepted
  between the two moments, so the `arrived` callback is guarded on the key, not the phase. A flight
  can also go without arriving, and a third callback, `dropped`, runs then, so the window never
  keeps a shadow that is switched off. The window is at the fitted frame by then whatever the zoom
  was: `hide` springs the level back to 1 first and comes down once that has arrived
  (`AnnotationController.fitBeforeHide`). `docs/shadow-2026-09-17.md` and
  `docs/handover-2026-09-18.md` have the frames and what each moment cost.
- The flight layer takes the presses on a flying card and passes every other press.
  `TransitionLayer`'s panel covers the screen and is clear outside its flights, so the window server
  gives it only the presses on a flight's pixels; a flight's shadow passes them, as the matte rule
  below says. Its content view, `PressCatcher`, takes each press with its drags and its release, and
  `FlightPress`, a pure state machine, decides where they go. A press on the card flying into the
  editor, while the reducer is in `flyingOut` or `annotating` for it, is held until the editor's
  window takes presses, then handed to the editor with every drag since, in order, and the rest of
  the press follows it there (`ThumbnailController.flightPressed`, `AnnotationController.take`,
  `EditorView.take`). A held event lands on the point of the picture that was under the pointer when
  it happened: each flight carries a `FlightSpotView`, placed before the `Bow`, and
  `FlightSpotView.fraction(of:in:picture:)` maps the press onto the aspect-filled picture. After the
  handover, the rest of the press is placed by where the pointer is on screen. Marks drawn before
  the flight lifts appear when it lifts. A press handed over onto the text being typed goes to the
  text. `pressText` places the caret, or selects the word or the paragraph as the click count says;
  a drag extends that, and Shift extends the current selection. The text view cannot track that
  press itself, because its tracking loop would read the drag and the release from the event queue,
  where they are the flight layer's, in that window's coordinates. So such a press cannot drag
  selected text to move it. A double-click handed over does not zoom before the landing (the zoom
  rule below). A press on any other flight, such as a card flying home, one leaving with the stack
  or a stitch's pieces, is swallowed up to its release. So is the rest of a press held for an image
  that turns back, after Esc, a `cancel` or another image opening. The panel stays ordered in until
  a press's release, because the window server sends the drag and the release to the window that
  took the press. A release that never arrives would leave the editor mid-stroke and the panel up:
  in driven presses on flights home, 4 releases in 29 reached no window at all. So `watchRelease`
  reads `NSEvent.pressedMouseButtons` every 50 ms while a press is down, and after two readings of
  up in a row it ends the press and logs `[flight] release missed`. A stack presented while the
  panel is up and empty is ordered above it at the same level, so the first flight on an empty layer
  brings the layer back to the front (`showPanel`). A pointer over a flight is over the flight
  layer's window, so the stack gets a hover exit. A card landing from the editor therefore takes its
  hover from where the pointer is (`ThumbnailController.hover(landing:)`): hovered when the pointer
  is on its frame and the topmost window there is this app's, and not hovered otherwise. Two limits
  remain. The window server applies a window's new pixels 6 to about 30 ms late, and a press in that
  interval reaches what was drawn there before. At motion 0, one press on the card flying into the
  editor reached the window behind. The likely cause, not confirmed, is that lag: at motion 0 the
  flight layer and the editor's alpha reach the window server within two run-loop turns of each
  other, and both are new to it. It needs no fix: `show` comes 45 to 60 ms after the click that
  opened the card, a press falls through only if it lands where the editor appears within about
  30 ms of `show`, and a double-click's second click lands on the card. Reduce Motion forces motion 0,
  so this is a user's case too, not only a script's. `docs/flight-press-2026-09-23.md` has the
  measurements.
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
- The status item has an autosave name and a seeded preferred position. Without it, a crowded
  menu bar on a notch Mac puts the new icon under the notch and it never appears.
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
  index catches a file changed in place. While the folder cannot be watched (a volume not mounted
  yet) the reads list it directly and each rescan retries the watch. Copying puts the PNG on the
  pasteboard and promises the TIFF, which is rendered only when a paste target asks.
- A screen recording is a `Screenshot` whose `kind` is `.recording`, read from the `.mov`
  extension alone (`Screenshot.recordingExtensions`). Its card shows the first frame, decoded on
  the thumbnail queue (`Thumbnailer.posterFrame`, about 90 ms), and a badge with its length. Each
  action names the kinds it takes (`ShotAction.kinds`, images only unless it says otherwise), and
  `unavailableReason(for:)` is the one test: the strip greys a row that cannot take every selected
  card, its key beeps, and its URL answers `unsupported-type`. An action never runs on the part of
  a selection it can take. Draw and Open share Return and one strip row (`Config.stripRows` groups
  actions by key); the row shows whichever applies, and Draw when neither does. A click on a
  recording opens it in the app macOS opens movies with. A recording never reaches the annotator,
  so `annotateOnCapture`, the hold, and Draw on Last Screenshot pass over it. Copy puts a recording
  on the pasteboard as its file URL and path, never its frames.
  `docs/replacing-apple-capture-2026-09-22.md` has the measurements.
- Stitching from the stack is one motion, not a file appearing later. `ThumbnailController.stitched`
  takes the cards the image was made from out of the column, holds a slot for the new card at the
  bottom, and hands both to `TransitionLayer.converge`: the pieces fly into that slot while the
  finished image fades in under them. Both sets of cards sit in `model.forming` while their image is
  in the transition layer, so a slot keeps its place and draws nothing, and the image is never on
  screen twice. The watcher reports the file a moment later as usual; the card is already there, so
  `insert` ignores it, and with `annotateOnCapture` on that same report flies the new card into the
  annotator. With the stack closed (a `vignette://stitch` from a script) the toast is the whole of
  it. Dismissing the stack mid-converge ends the pieces' flights with it and the stitch says so as a
  toast, so it never finishes in silence. `Stitch.compose` lays the pieces out for the model that
  will read the result: it tries every column count and keeps the one that survives a vision
  model's resize best (`readerScale`, Anthropic's standard tier: a long edge of 1568 px and 1568
  patches of 28 px). The gap and the badges are fractions of the piece they are on,
  `ui.stitchLongSide` caps the output, and `[stitch] ok` reports the composed size and that scale.
  Each piece carries its drawing, the editor's own for the image open in it and the stored one
  otherwise, and `Drawing.draw` draws it into the piece's pixels as Done does, off the main thread.
  The stitch is a new image with no drawing of its own. `docs/stitch-2026-09-17.md` has the numbers;
  separate images are better when the model has to read the text.
- The stack panel is non-activating but can become key (`ThumbnailPanel.acceptsKeys`). Never
  call `NSApp.activate` for it; the user's app must stay frontmost. While a card is in the
  annotator the panel gives up key status so typing reaches the editor. It gives it up in
  `perform(.prepare)`, right after the annotator's window has taken it, so the keys pass from one
  to the other instead of being nobody's for the length of the flight. A `.help` tooltip never
  shows in the stack: AppKit shows a window's tooltips only while its app is active, unless the
  window sets `allowsToolTipsWhenApplicationIsInactive`, which the panel does not. Text the user
  must see there is drawn, like a greyed strip row's reason (`UnavailableReason`).
- Which card a key acts on is one variable, `model.focused`. The stack focuses the newest card the
  moment it takes keys (`takeKeys`), so arrows, Space, and Return act on a card without a first
  click, and the pointer moves the focus too: moving onto a card focuses it, and leaving it leaves
  the focus there. The pointer only moves it while the stack holds the keys and no session is
  running; while the annotator has them nothing moves. A shortcut runs on the selection when there
  is one, else on the focused card (`targetCards`). The ring says where the focus is: the accent
  color on a selected card, white on a focused one.
- The panel widens to the left while cards are selected, to hold the selection strip
  (`StackLayout.stripPlacement` places it, `panelSize(viewport:showsStrip:reveal:)` makes the room:
  the icon column, the gap to the cards, and the room the labels grow into, whether they are out or
  not). Its right edge never moves, so the cards stay where they are. The gap to the cards is
  `ui.selectionStripGap`, measured from the widest selected card (`docs/selection-strip-2026-09-18.md`).
  Only the column carries the hair of alpha that catches clicks and scrolls; the strip's side of
  the panel stays clear, so a click there still reaches the window underneath.
- The strip's labels are out for as long as a selection exists, whichever hand built it: a
  selection is the moment the rows' names and shortcuts are wanted, and a strip that folded back to
  icons when the pointer moved onto a card read as the strip losing interest. Each row draws its shortcut
  after the label from `ShotAction.Key.glyphs`, and `stripReveal(rows:)` measures both, so the
  panel's room holds them. Copy on a card still reveals on hover and grows to the right from an
  icon that does not move; the strip keeps its right edge and grows to the left, so a label never
  covers a card. A row is one button, icon and label together. The strip stands aside while the annotator has an image,
  since it hangs inside the room the frame may grow into: the two places that ask for its placement
  refuse (`ThumbnailController.stripFrame` and `StackView.stripPlacement`), never `showsStrip`,
  which sizes the panel, because the panel's window is not resized while a session runs. The
  selection is untouched and the strip springs back when the session ends. `[state] stack.strip` is
  the grown frame, null while a card is in the annotator.
- The recent stack narrows to make room for the annotator. One number says how wide it is drawn:
  `StackLayout.widthScale`, 1 at rest and never below `ui.stackMinScale`. The cards are drawn at
  that width (`drawn`) and the column with them; their right edge does not move. The panel is
  always the size the stack needs at rest, and transparent outside the column, so nothing has to be
  resized while the stack narrows; the scroll follows the column's height so the same cards stay in
  view and the column comes back to the same place. The rect the annotator fits and grows within is
  the visible frame less the strip the stack keeps at its narrowest, `ui.stackGap` beside it
  (`annotatorRoom`), so the frame can never reach the cards however far a zoom grows it. In between,
  every time the annotator's frame moves the stack takes the widest value that still clears it by
  the gap (`widthScale(clearing:visibleFrame:)`). Opening and closing spring it through
  `ui.relayoutDuration`; a zoom sets it straight, in the same turn as the frame. Only the recent
  stack does this: a lone thumbnail leaves the panel when the annotator opens, and a
  `vignette://annotate` with no stack showing gets the whole visible frame.
  `docs/stack-room-2026-09-17.md` has the numbers, and `docs/stack-narrowing-2026-09-23.md` what a
  frame of the narrowing costs and the options for making it cheaper.
- The click hint (Draw on a screenshot, Open on a recording) goes out over the card's two corner
  buttons and nowhere else (`CardView.overCornerButton`): each button's frame plus its padding, not
  the whole band along the bottom, so the hint stays up over the middle of the band and a click
  there still does what it says.
- A card's thumbnail fills the card, so a screenshot whose shape differs from the card's box hangs
  outside the card's frame, and the clip that hides it does not shrink the hit area. The
  `contentShape` in `CardView` holds each card's hover and clicks to its own frame; without it a
  hovered card, which `zIndex` raises for the click hint, takes them from the card below.
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
- Which image is in the annotator, where it came from, and what is in flight has one owner:
  `AnnotatorTransition` (a pure reducer) held by `ThumbnailController`. Controllers send events
  (annotate, shown, parked, close, finish, newShot, dismiss, remove) and run the effects it returns
  (prepare, show, park, abandon, returnCard, markCopied, hideAnnotator, join). Done sends `finish`:
  the card returns and takes the copied mark, and a lone thumbnail, which left the panel when the
  annotator opened, comes back to the corner for it. Esc sends `close`: a stack card returns, a lone
  thumbnail's annotator just hides. Quick draw sends `dismiss`. A `prepare` is never emitted while a
  park is in flight, which is what serializes rapid swaps; a new screenshot during a lone
  annotation joins the panel instead of closing the editor. Every event logs one
  `[transition] <event> -> <phase> effects=…` line. The annotator never hides itself: Esc, a click
  outside, Cmd+W and Done ask through `onClosed` and `onFinished`, and the reducer decides. `show`
  is the window coming up behind the flight; the flight image lifts once the editor has reported
  `loaded`, its window takes presses, and the flight has arrived. The editor parks synchronously,
  so an effect can answer inside the event that asked for it: at zoom 1 there is no fit-out, and
  `parked` comes back in the same turn as `park`. `ThumbnailController.send` holds an event that
  arrives while another is being handled and runs it once that one is done, so the reducer's events
  stay in order. The `parking` phase stays for the zoomed case, where the window springs back to the
  fit before it comes down. `dismiss` sets `model.slidingOut` before it sends, so a park that
  answers in that turn leaves the flight it just aimed offscreen to the slide-out. Add a sequence to
  `AnnotatorTransitionTests` before changing the table; the random-sequence test checks the
  invariants, with same-turn answers among its sequences.
- The flight to the annotator can be interrupted. In `flyingOut` the window has not come up, so
  nobody has seen that image: a `close` or an `annotate` of another key answers in the same turn
  with `abandon` and `returnCard`, and the flight turns around from where it is (`fly` on an id
  already flying keeps the frame and blends the bow). `abandon` is `AnnotationController.abandon()`:
  it parks the drawing and stores it, since the editor holds the keys during the flight and a key
  pressed then can change the drawing, and it takes the window down with no fit-out, since no zoom
  can have happened. The controller's `.abandon` keeps the parked marks (`parkedMarks`), as `.park`
  does, so the flight home carries the drawing as it was parked, not as it left. `dismiss` and
  `remove` still park from `flyingOut`, because the panel aims that
  same flight offscreen before the event arrives. Esc is the user's way in: the annotator's window
  holds the keys from `prepare`, so the editor sees it and asks through `onClosed`, which the
  controller sends as `close`. `docs/flight-interrupt-2026-09-18.md` has the frames.
- Annotating a list is a queue (`ThumbnailController.queue`, `stack.queue` in the state report):
  the first file opens and the rest wait, and finishing one opens the next until the list is done.
  The controller takes the next file in the turn `parked` comes back and sends `annotate` after the
  finished card's effects, so the card flies home with its copied mark while the next flies out,
  which is a swap's two flights. The reducer knows nothing of the queue; `returnCard` only ends the
  session, hides the dim, and hands the focus back when nothing follows. Opening a card does not
  clear the selection, so after the last one Cmd+C or Cmd+S still takes all of them. While a card
  is in the annotator, selecting another card in the stack queues it next, in the order picked
  (`[annotate] queued <name> 3 of 3`), and deselecting it takes it back out
  (`queueFromSelection`, from the model's `onSelectionChanged`). Esc, a dismissal, quick
  annotate, and a stack presented anew empty the queue; a removed file drops out of it, and a run
  ends when the file in the annotator is the one that went; any other request to annotate
  replaces it. `docs/annotation-queue-2026-09-17.md` has the handover.
- The annotator window is borderless and sized exactly to the image. Its toolbar is a native
  panel (`AnnotatorToolbar.swift`) placed under the window. It shows `EditorCore.Tool.allCases`,
  the editor reports the active tool through `onTool`, and the bar calls `setTool`, `send` and
  `done` on the editor. The bar is tools, one divider, Send, Done: there is no palette, so which
  colour a mark is drawn in is the colour pass's, not the user's. Send has
  no default and no last-used target; its menu groups the agent sessions by project, as sections up
  to `submenuThreshold` projects and as a submenu each above it, so where a drawing is going is
  read before it goes. While one image
  follows another with no gap (a click on another card, or the queue moving on) the bar stays on
  screen and springs to the next image's place: `place(below:gap:)` slides the panel when it is
  already up, one `Tween` per direction, over `Anim.passesTarget(ui.expandDuration)`, which is when
  the next image's window comes up. `hideWindows` asks for the exit through `hideSoon`, which waits
  one turn of the run loop and is cancelled by the next `place`; a swap's park answer and the next
  `prepare` land in that same turn, so the reducer says nothing about this. `[state]
  annotator.toolbar` is the panel's frame, or null when it is off screen.
  `docs/annotator-toolbar-2026-09-19.md` has the numbers. A swap runs two flights at once, and the
  stack keeps the slot, drawn empty, so the card flies back to the same place.
- The editor is a pure reducer and a view that decides nothing. `EditorCore.reduce` takes one
  `Input` and returns the `Effect`s to run, in order; `EditorView` turns events into inputs, runs
  those effects, and draws the core's state in one `CATransaction`. What a press hits is
  `core.target(at:)`, tested against the overlay as drawn and then the marks, so a test drives the
  core with no window. Cmd+Z and Shift+Cmd+Z always reach the editor (`performKeyEquivalent`), so
  one owner handles undo whether a text is being typed or not; while typing, the core takes only
  the keys `takesKey` names and the text view gets the rest, and an input method's composition owns
  every key until it is confirmed. A Cmd key the core does not take goes on to the menu.
  `docs/editor.md` is the behaviour: keys, gestures, what a press hits, the clipboard, the file.
- A mark has one geometry, and the renderer owns it. `Mark.shape(pointScale:arrowhead:)` gives a
  rectangle's, an ellipse's or an arrow's paths, which the renderer draws and `MarkLayers` puts in
  `CAShapeLayer`s, so a shape looks the same in the editor, on a card, in flight and in the PNG. A
  text's letters are drawn only by the renderer (`MarkRendering.swift`): its outline is stroked a
  glyph at a time and then filled in one pass, which took a 2,000-character text from 240 ms to
  about 62 ms. `EditorTextView`, the text being typed, sets every line's baseline from `TextLayout`
  through its layout manager's delegate, so typing and the drawn text meet within half a point.
- `MarkLayers` is the one on-screen drawer for marks: the editor (`EditorPicture`), a card
  (`MarksView`) and a flight. A text is a bitmap the renderer draws off the main thread, on
  `MarkLayers.textQueue` for the editor and flights and `cardQueue` for cards, so a stack of long
  texts never delays the one being edited. The bitmap is an `IOSurface`: Core Animation copies a
  `CGImage` at the commit that shows it, which took up to 22 ms on the main thread for a text the
  size of the view and doubled its memory. A bitmap is shown only while its text is the same record
  and still wants exactly that `Target` (mark, region, scale, style); a draw no longer wanted is
  skipped before it starts, and after `park()` nothing is shown. The shared bitmaps and
  `take(from:)` match on the style too, so a bitmap never crosses styles. A card's or a flight's
  marks take a new style through `restyle(_:arrowhead:)`, and each text keeps the bitmap it has
  until its new one arrives. A text keeps at most two bitmaps, a whole and a sharper
  detail, the one on its way included. Each owner's plan caps them: the editor's at the view's size
  in device pixels, a card's at the part of the image the card shows at its rest size. The editor
  and the flight into it ask for the same targets, so the second shows the first's bitmap
  (`adopt(from:)`) instead of drawing it again. The typed text's view stays until its bitmap
  arrives (`onTextDrawn`), so the words are on screen in every frame. A card's marks sit inside its
  `DragSource` view and are flattened at the larger of the biggest size the card has been placed at
  and its rest size (`MarksView.restSize`), so a narrowing stack redraws nothing and a card first
  placed in a narrowed one is sharp when it widens. A flight carries them as a SwiftUI `.marks`
  overlay after the shadow, because SwiftUI draws the shadow of a view holding an AppKit view a
  level or two differently, and a card's shadow has to match its flight's. The overlay clips on its
  own layer's corner (`MarksView.corner`), which follows the flight's corner in every frame. The
  drag image is the card as drawn: `DragSourceView.dragImage` draws the image over the matte,
  clipped to the card's corner, and draws the drawing over it with `Drawing.draw` in the live style.
- Drawings are owned by the app, and every write goes through `Drawings` (`Drawings.swift`, with
  `DrawingStore` for the files): one JSON file per screenshot under
  `~/Library/Application Support/<bundle id>/drawings/`, named by a hash of the file path the app
  uses everywhere (`shot.url.path`). The editor hands its drawing over 0.3 s after each change,
  never while a button is held (`[drawing] saved`), and once more when it parks (`parked`);
  agents' marks arrive through `Drawings.add` (`built`, or `saved` when they join the open
  drawing). A drawing with no marks removes its file. `onChange` hands each card its drawing, so a
  write reaches the card at once. `load` takes a list and reads it in one job off the main thread,
  and a stack opening reads its cards' drawings in one such job per turn and changes `cards` once
  (`ThumbnailController.setDrawings`). A key written or removed while it was read is left out of
  the answer, since `onChange` already said what it is. A file that does not parse is set aside as
  `<id>.json.invalid`; a newer build's file, another screenshot's, or one made on an image of
  another size is read as no drawing and left where it is. A launch sweeps the drawings whose screenshot is gone. It also removes what the
  web editor left, its drafts and WebKit's data, where they are still there
  (`Drawings.removeWebEditorData`, one `[app] removed web editor data <path>` line each); drafts are
  not carried over.
- Done, Send and Copy Drawing render on `RenderingQueue.shared`, one at a time, off the main thread:
  one rendering of the largest capture holds two bitmaps of about 85 MB. Done's rendering, and Cmd+C
  with nothing selected, go `.first`, ahead of any rendering that has not started, because Done's
  clipboard is a promise. `Clipboard.copyRendering` puts the path on as text at once and promises
  the PNG, the TIFF and the file URL; a paste that comes first waits for the rendering on the main
  thread for up to 5 s, then gets nothing and logs `[clipboard] error`. The card goes home at once.
  A rendering that fails clears the clipboard, unless something else was copied since, and takes the
  card's copied mark back (`takeBackCopied`), with the toast "Could not copy the drawing; see the
  log". `[annotate] done <file> <n> bytes, copied` is logged when the file is written. A drawing
  with no marks copies the original file and writes nothing.
- A mark's colour is picked by the colour pass, not by the user. `ColorSample` draws the screenshot
  at 320 px on its long side, off the main thread, and `pick(for:pointScale:style:)` keeps the first
  colour in `MarkColor.allCases` whose CIELAB distance from the pixels under the mark is at least
  `minDistance`. The core runs it outside undo history when the hand-over timer fires, when typing
  ends, and before a park, Done, Send or a copy of the drawing; never at open, and never on a mark an
  agent named a colour for (`colorChosen`). A mark whose sample has not arrived stays owed
  (`colorOwed`) until `colorSampleArrived()`. `docs/annotation-colour-2026-09-17.md` has the numbers
  and why the measure is not a WCAG ratio.
- A drawing's sizes are in points of its own `pointScale`. A new drawing in the annotator takes the
  backing scale of the screen it opens on; one an agent's marks create takes `NSScreen.main`'s, the
  best guess with no annotator open. Both are clamped to `Drawing.pointScales`. A stored drawing
  keeps its own, so a mark keeps its size in the image when the drawing is opened on another screen.
- Zoom belongs to the annotator, not the editor. A pinch, a two-finger double tap and a wheel over
  the editor go straight to `AnnotationController` through `onZoomGesture`, with the trackpad's
  phases: a pinch and a wheel with cmd or ctrl held zoom, and a plain wheel pans a magnified
  picture (`pan` moves `zoomCenter` and sets `editor.pictureRect`). The zoom keys, cmd+plus/minus/0,
  and a double-click on empty space with the select tool are the core's to recognise, and it sends
  them as a `ZoomRequest` through `onZoom`. Those are ignored until the flight has landed
  (`landed` sets `hasLanded`, and the next `prepare` clears it): the editor takes keys from
  `prepare` and presses handed over from the flight, and a zoom before the landing would grow the
  window under a flight image still at the fitted frame. All of them reach
  `AnnotationController.zoom(by:at:as:)`, which moves one number, `zoomLevel`: how far the image is
  magnified past the frame it opened in. The picture is magnified uniformly by that level, so the
  image is never stretched; the frame is not, and each of its sides grows with the level until that
  side fills the room it was given (the visible screen, less the strip the recent stack keeps).
  `Zoom.split` divides the level in one place, one division per side, so `window * camera` is the
  level in each direction: a side's growth is `min(level, reach)` and the magnification in that
  direction takes what is left. The two sides reach the room at different levels, so between them
  the frame does not carry the image's shape and the visible part of the image is a different
  fraction in each direction. Zooming out reverses that and stops at the fitted size. Only a hand
  pulls below it, with a short pull that springs back when the fingers lift (the pinch's and the
  wheel's `ended` phase, `release`); a key or a mouse wheel's notch, which has no phases, stops at
  the fit, and an input that moves nothing is dropped. One spring
  carries the level, ticked by the screen's display link and retargeted in place by every input
  (`Tween.animate` keeps its link and its last tick, because a link made anew per input fired at
  an arbitrary part of the refresh and read as uneven steps); a gesture's spring is short, a
  key's, a double tap's and a fit's longer, and a step aimed elsewhere mid-spring blends its anchor
  (`ZoomAim`) instead of stepping sideways. The window's growth is not aimed: each side grows into
  the room beside it, which leaves exactly one anchor per direction (`Zoom.anchor(fitted:within:)`),
  read off the frame on screen at every step (`Zoom.anchor(reproducing:fitting:or:)`) so a nudged
  frame does not carry its error forward. Below the fit the frame keeps the line it is on (the
  room's for a zoom-out that runs on through the fit, the cursor's for a pull from rest); an anchor
  worked out to hold the cursor's point divided by the shrink, which passes through zero at the
  fit, and stepped the frame 40 points sideways (`docs/zoom-input-2026-09-19.md`).
  The cursor names which part of the image is magnified once a side has filled the room
  (`ZoomPan`), and a cursor near an edge of the picture is pulled onto it first
  (`Zoom.pulledToEdges`, `ui.zoomEdgeBandPoints`, `ui.zoomEdgePull`) so that edge stays in view; the
  pull runs in both directions on every input, because one side can be cropped while the other is
  still growing. The cursor is a fraction of the window (`at`, y from the top); a keyboard step has
  none and zooms about the middle. A two-finger double tap zooms twofold at the tap, or back to the
  fitted size from anywhere above it (`smartZoom`), and a double-click with the select tool asks
  for the same step: the core decides, because it knows the tool and what is under the pointer, so
  a double-click on a text still edits it. Zoom's springs are in code rather than the tweaks, but
  the motion scale still shortens them. `Sources/Zoom.swift` is the geometry, and its comments say
  why it is shaped this way.

  One process draws the frame and the picture, so a zoom step is one commit. Each tick sets the
  frame's rect from `Zoom.frame` and the picture's rect inside it from `Zoom.picture` in one run
  loop turn: `moveFrame` is the only place the frame's rect is set, and it hands the editor its new
  size and picture together (`EditorView.setSize(_:picture:)`), so the marks, the overlay and the
  text being typed follow in that same turn. `frameOnScreen` reads the rect back. The texts are
  drawn again for the new zoom once the picture has stayed put for `EditorView.restDelay`. The
  state report's `annotator.zoomLevel` is the one number, `annotator.zoom` and
  `annotator.canvasZoom` its two halves per direction, `annotator.zoomAnchor` the point the window
  grows away from, `annotator.zoomCenter` the middle of the visible part, and `annotator.room` the
  rect the frame may grow within.
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
  and a lookup in another space misses. Renderings, stitches and the colour pass read the file
  itself, so their output does not change. The editor shows the screenshot decoded no larger than
  the visible screen in device pixels, which is the same decode a flight asks for and is counted in
  the thumbnail cache's budget (both ask `Thumbnailer.screenPixels(on:)` and the screen's colour
  space); `editor.clear()` lets it and the marks' layers go when the annotator hides, and
  `removeCards` lets a card's marks go when it leaves the column. Text bitmaps are capped by their
  owner's plan (the `MarkLayers` rule above), and renderings run one at a time (`RenderingQueue`). A
  stitch decodes one piece at a time and draws at the capped output size.
- Swift language mode is 5 (see `project.yml`). No sandbox, on purpose: the app writes Apple's
  `com.apple.screencapture` defaults, watches a folder the user names without security-scoped
  bookmarks, and installs global event monitors. The hardened runtime is on.
- Signing: project.yml defaults to ad-hoc so any clone builds; `scripts/build.sh` reads the
  gitignored `scripts/signing.env` (identity and team) and this Mac's names the Developer ID
  certificate. Keep it that way here: Accessibility trust is tied to the signature's designated
  requirement, and an ad-hoc signature changes on every build (`docs/building.md` has the details).
  `ENABLE_DEBUG_DYLIB` is off in project.yml: with it on, a Debug build loads its code from
  `Vignette.debug.dylib`, which the hardened runtime rejects for a signer without a team ID, so a
  self-signed build crashed at launch. macOS keys Accessibility by bundle id: a second copy of
  the app with the same bundle id and a different signature shares the row and stays untrusted,
  so a test build that must be trusted needs its own bundle id.
- `Info.plist` is generated by xcodegen from `project.yml` and is gitignored.
- Settings changes push to Apple's `com.apple.screencapture` defaults (location, show-thumbnail,
  disable-shadow, type). Only keys that changed are written. First run is the one exception, and it
  writes one key: `show-thumbnail` goes off, because Apple's thumbnail withholds the file for about
  5.6 seconds (measured; `docs/replacing-apple-capture-2026-09-22.md`) and `copyOnCapture` fills the
  clipboard when the watcher reports the file, so with both on a Cmd+V inside that gap pastes what
  was there before. Installing Vignette is choosing what happens after a capture, so that is not a
  question the setup window asks and there is no toggle for it; `appleOriginal`, captured in the same
  turn, is the way back. `Settings.reconcileApple()` runs at every launch, before the watcher, and
  puts back `show-thumbnail`, and `location` when `syncAppleSaveLocation` is on, if something outside
  the app changed them: those two break Vignette rather than merely differing from it. `type` and
  `disable-shadow` are never reconciled. The reconcile is silent; the Screenshots tab states that
  Vignette replaces the thumbnail, a few rows above "Restore macOS Screenshot Settings…", which is
  the disable path and the only way back in the UI. `appleThumbnail` stays a settings.json key with
  no control, because `restoreAppleDefaults()` writes Apple's old value into it and that is what
  makes a restore survive the next launch's reconcile.
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
  have no record and so could never be shown. Clearing a request takes its reserved file back and
  cancels an import whose marks are still joining its drawing; publication re-reads the record
  rather than trusting the copy its import has been carrying. A managed reply is never a capture even after publication, so a late watcher
  event cannot copy it to the clipboard or open the editor, and its card is inserted once, by its
  own import. Startup loads the records before the watcher starts or anything warms the stack.
- A destination is an agent session, never the terminal displaying it. Codex is addressed by its
  thread UUID and nothing else: `codex queue --thread` finds the engine that owns the thread, the
  desktop app's included, and that engine resolves the UUID or fails, which is
  `AddressGuard.runtimeEnforced`. `AppServer.swift` is the only thing that speaks the app-server
  protocol, and it only reads: it carries one `thread/list` to a `codex app-server` of its own and
  turns the answer into menu rows, grouped by each thread's own `cwd`. The thread store is on disk,
  so a server started for the length of that one listing answers for every session, whoever owns
  it; the listing's `status` is that server's own memory and says nothing about a session, so it is
  not kept. No `codex` on the machine means no Codex destinations, which is not an error.
  `docs/codex-discovery-2026-09-21.md` has the protocol, the timings behind `listLimit`, and what
  was verified against a live desktop session. Claude Code is addressed by
  its session id, which herdr reports per pane; herdr's submission API takes a pane and has no
  expected-session parameter, so Vignette re-lists and checks the pane still holds that exact
  session immediately before submitting (`AddressGuard.preflight`). A session in no pane is an
  error and never another pane. The image travels as a path the session opens itself, so a Claude
  Code session that may not read it stops on a permission prompt. herdr reports that pane as
  `blocked`, and Vignette records the request as not submitted, with `send-failed`. The two tiers
  are recorded on every request and reported in `[state] requests`; `docs/closed-agent-loop-implementation-2026-09-20.md` says why the weaker one
  is still allowed to submit.
- A `vignette://` URL has no authenticated sender, so a reply is authorized by a per-request bearer
  secret in the request's own directory. The ticket's path travels in the request line; the secret
  does not, because `[url]` logs every URL. Holding the ticket permits replies to that one request
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
  refused and the first is untouched. `ReplyProtocol.version` and the helper's `PROTOCOL` go up
  together.
- The reply helper returns to the app that issued the request: `ticket.app` names the bundle and the
  helper passes it to `open -a`. Plain `open` hands a `vignette://` URL to whichever copy of the
  bundle id LaunchServices registered last, which on a Mac with a second build is a different app
  that answers `unknown-command` (observed).
- Send never reuses Done. It renders the drawing on `RenderingQueue` and closes nothing while it
  waits. The request is stored before the image leaves the editor, so a failure anywhere before
  then leaves the drawing where the hand left it; a rendering that answers after the person moved to
  another image is dropped rather than closing that one (`[send] dropped <name>; the editor moved
  on`), and so is a list of sessions that arrives after the editor moved on. A rendering that fails
  is a refusal, never a send of the bare screenshot: only a drawing with no marks sends the picture
  itself, and it goes through PNG whatever the capture's own format is. Send ends the session without a copied mark and the
  queue carries on to the next card: a list of files to annotate is something the person asked for,
  and handing one of them to an agent does not withdraw the rest. Esc is the one that empties the
  queue, because that is a person stopping.
- The first launch opens the setup window (`SetupWindow.swift`), and it has that launch to itself:
  the agent-skill offer waits for the next one rather than competing for a first-time user. Its job
  is the shortcut, because the default is `double-rshift` and that needs Accessibility. Nothing else
  may raise that dialog: `ModifierTap` is constructed with `prompt: false`, so the only
  `trusted(prompt: true)` in the app is the window's own button, pressed after the user has chosen
  the double tap. macOS gives an app few chances at the dialog, and one spent during launch on a
  question nobody asked is the one people dismiss. The window learns the grant landed by polling
  (AXIsProcessTrusted announces nothing) and learns the shortcut works from the `.hotKeyFired`
  notification, which `registerHotKey`'s `fire` posts: the keys firing is what proves the setup
  worked, since the stack appearing does not on a Mac with no screenshots yet. That same poll reads
  the watch folder's count, and an empty folder asks for a capture first, ahead of the fired state:
  a tap with nothing to show opens nothing, so reporting success would report it about an empty
  corner. The two menu items that act on a screenshot, Show Recent Screenshots and Draw on Last
  Screenshot, are greyed out while the folder is empty (`validateMenuItem`), which is the rest of
  that silence: both used to answer only in the log. `setup` in
  settings.json records `unasked` then `done`, written when the window closes rather than when it
  opens, so a launch quit part way through asks again. `ShortcutSetting` is the one shortcut
  control, shared with the Settings window's General tab.
- The agent skill (`skills/vignette/SKILL.md`) ships in the bundle as a folder resource
  (project.yml), and `SkillInstaller.swift` copies it out. A root is an agent's own directory,
  `~/.claude` or `~/.codex`, and only one that exists; the skill lands in `<root>/skills/vignette`.
  Roots are parameters everywhere, so a test never reaches the real ones, and the live check is
  `install-skill?root=<dir>` (debug only). Links are resolved all the way, including one at the
  skill folder itself (`destination(in:)`), so a skill the user keeps elsewhere is rewritten where
  it lives and two roots reaching one folder are one copy reported for both. Removing takes the
  entry at `<resolved skills>/vignette` away without following it, so a link goes and its target
  stays (`entry(in:)`). An install overwrites whatever is there, and `matches(source:installed:)`
  is what makes a launch with nothing to change say nothing. The copy is staged beside the
  destination and moved into place, so a failed install leaves the old one where it was.
  `agentSkill` in settings.json records only that the offer was made: `unasked` with an agent
  directory present makes it once, which is the Settings window at the Agents section, since the
  toast carries no button, and making it records `off`. That window comes up with `orderFront` and
  does not activate the app: the user did not ask for it. Disk is the rest of the truth. A launch
  rewrites every copy that is there and differs from the bundle's, installs nothing new, and removes
  nothing; the Agents tab's per-agent buttons and `install-skill` are the only things that put the
  skill somewhere or take it away. An older file holding `on` is read as `off` (`validated()`).
  The app carries the skill because someone who downloads Vignette needs their agent to learn the
  `vignette://` contract, and the app is the one thing they are sure to have and the one thing that
  knows which commands its version supports. `docs/menu-settings-revamp-2026-09-20.md` is the
  installer as it works now.

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
- A colour: add a `MarkColor` case with its hex. The order of `MarkColor.allCases` is the colour
  pass's order, and a case's raw value is what the file format and an agent's `marks=` name. There
  is no palette in the toolbar.
