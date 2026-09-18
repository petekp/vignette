# Working on Shotnote

Shotnote is meant to be modified. This file is the onboarding for a person or an agent.

## Layout

- `Sources/` Swift menu bar app. `AppDelegate.swift` wires everything; `Config.swift` holds the actions.
- `~/.config/shotnote/settings.json` holds per-machine settings (`Settings.swift` defines the keys).
  Its `ui` section (`UITweaks`) holds the layout, style, timing, flight, and backdrop numbers, and its
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
   Every checkout builds the same bundle id, so with more than one build on the Mac LaunchServices
   sends `shotnote://` to whichever copy it registered last, and that copy's launch replaces the
   instance you started: `open -g -a <your build>/Shotnote.app "shotnote://…"` aims at yours.
   That same command relaunches your build when its instance has gone, and the relaunch carries
   no `SHOTNOTE_SETTINGS`, so it runs on the user's real settings and folder: a driving script
   reads `[state]` first and stops unless `app.settingsFile` is its scratch file, and only then
   sends an action. Several agents working in parallel (a worktree each) share one Mac and one
   running instance, so they launch one at a time behind a lock held only around a launch and a
   look, and put the user's own build back after every round. A build the user runs from a
   worktree's build folder is copied to a path no build touches before that worktree is rebuilt;
   a rebuild rewrites the bundle under the running process.
   Every command ends with one `[<cmd>] ok <detail>` or `[<cmd>] error <code> <detail>` line; the
   codes are the `CommandError` cases in `Commands.swift`. `file=` must point inside the watch
   folder, and `eval`, `show-editor`, `tweaks`, and `send` are refused, unless settings.json has
   `"debug": true`. `add` is the exception, and it takes two paths the folder rule does not cover.
   `add?file=` copies an image in from anywhere and the watcher then reports it like a capture,
   minus the copy and annotate toggles (`&annotate` opens the editor). `&agent=<name>` says which
   agent is pushing it: the name is recorded on the copy as the `com.petepetrash.shotnote.agent`
   extended attribute (`Agent.swift`, `xattr -l` shows it) and the card gets a purple badge.
   `&marks=<json file>` pushes the agent's own annotations with the image (README has the format):
   the page turns them into a draft before the card appears, so the human edits them like their own,
   and the command answers once that draft is stored. That JSON file may also be anywhere; it is
   read on the main thread, so it is capped at 256 KB, and an error line names the mark and the
   field without quoting what the file said.
   `[annotate] loaded <ms>` reports when the page has the image; it is posted
   from a `requestAnimationFrame`, which WebKit pauses while the screen is locked or the
   window is hidden, so the line never arrives in that state.
4. Look: `screencapture -x /tmp/s.png`, then crop the corner with `sips` and read the PNG.
   Send keys with `osascript -e 'tell application "System Events" to key code 36 using command down'`
   (Return finishes annotating, Cmd+Return too while typing, key code 53 is Esc). The recent stack takes key focus, so
   `keystroke "a" using command down` after `open shotnote://recent` selects all.
   For the global hotkey, the sweep gesture, or drag-out, System Events is not enough: use
   `scripts/input.sh` (CGEvent; `hotkey double-rshift`, `hotkey cmd+shift+6`, `click X Y`,
   `drag X1 Y1 X2 Y2 [seconds]`, which holds the button at the end that long and posts nothing
   while it does, `scroll`, `tap`, `key`; run it with no arguments for the list). It compiles
   `scripts/input.swift` with `Sources/HotKeySpec.swift` on first use, so it reads the same hotkey
   strings as settings.json. It posts events only because the terminal it runs from is trusted for
   Accessibility. Its coordinates are global Core Graphics points: top-left of the primary
   display, y down, so the Studio Display above it has negative y. Every frame in the `[state]`
   line uses the same convention, so a card or annotator frame from there can be clicked as is.
   Never send Escape that way to close the stack: if the stack is not key, the keystroke reaches
   the frontmost app, and in a terminal running an agent that is the interrupt key. Use
   `open -g shotnote://dismiss` for the stack and `open -g shotnote://cancel` for the annotator.
   Before any key or click, read `[state]` and confirm the stack or annotator is up and key: a
   synthetic key reaches whatever is frontmost otherwise, and a click lands in whatever window is
   there. A single `move` does not fire hover; walk the cursor in several steps and confirm
   `stack.hovered` (or the focus) in `[state]` before trusting a capture.
   `scripts/input.sh pasteboard` prints the pasteboard's item count and types.
   Inside the editor page, `open 'shotnote://eval?<javascript>'` runs the code (async, `window.editor`
   is the tldraw editor) and logs the returned value.
5. Read `~/Library/Logs/Shotnote.log`. Every action, URL command, watcher event, web message,
   and error lands there with a `[tag]`. `open -g "shotnote://state?tag=<id>"` writes one
   `[state] {json}` line with the tag echoed, so a script waits for its own line:
   `app` (pid, build, isActive, accessibility, watch folder, settings file, debug), `screen`,
   `stack` (cards with `file`, `frame`, `out`, `forming`, `draft`, `agent`; selection, focus,
   the hovered card, feedback, panel, and `strip`, the selection strip's frame or null),
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
   one. Draft events: `[draft] saved|parked|built|preview|forgot|swept <file>` and `[drafts] <n>`
   after every change to the set. `[stack] shown cards=… files=… shown=…ms decoding=…` counts the
   watch folder from the watcher's index.

A fake screenshot for testing: `screencapture -x -R 200,200,900,560 "<watch folder>/Screenshot test.png"`.
Delete test files afterwards; the watch folder is the user's real screenshot folder.

Measuring a handoff or a flicker: a burst of `screencapture -x -R x,y,w,h` reaches about 12 frames a
second; `screencapture -x -v` records the region at 60, and the frames read back with AVFoundation
give a per-frame position of an edge or the mean brightness of a band, which is how a one-frame
step, a doubled shadow, or a mismatch between a frame and its picture is proven or ruled out.
Compare before and after on the same driven sequence.

Measuring a stutter: launch the app under Instruments and drive it as above.
`xcrun xctrace record --template 'Time Profiler' --instrument 'Core Animation Commits' --env
SHOTNOTE_SETTINGS=<scratch> --time-limit 75s --output perf.trace --launch -- <app>` (a
`--launch` also replaces the running instance; the Animation Hitches template attached to a
running process records no commits or samples on macOS). `xctrace export --xpath
'/trace-toc/run[@number="1"]/data/table[@schema="coreanimation-commit-interval"]'` gives every
commit with its duration; a commit over 8.3 ms dropped a frame at 120 Hz. `time-profile` samples
on the main thread that run without a gap are a stall; the frames from the `Shotnote` binary name
the code. Trace time zero is about `[app] launched` minus the first sample inside
`applicationDidFinishLaunching`, which lines the trace up with the log. Compare before and after on
the same driven sequence; a single run varies.

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
- Every animation goes through `Settings.motionUI`: `ui.motion` (0 to 1) in settings.json scales
  every duration, and the system's Reduce Motion forces 0. Dwell times (`thumbnailSeconds`,
  `toastSeconds`) are not motion, and neither is a movement the user's own hand is driving: the
  drag-select's auto-scroll (`ui.autoScrollZone`, `ui.autoScrollSpeed`, the speed function in
  `StackLayout.autoScrollSpeed`, ticked by a display link in `ThumbnailController`) follows the
  drag at its own speed whatever the scale says. `"ui": {"motion": 0}` makes the stack appear and leave at once,
  which is what a script wants. Every SwiftUI animation is a spring made by `Anim.spring`
  (`slideInCurve` "spring" included), and the AppKit tweens use `Tween`'s spring curve: an
  interrupted motion keeps its velocity and blends into the new target instead of jumping.
  `Tween.spring` is the closed form of a critically damped spring, so a tick that arrives late
  lands where the spring really is by then and a stalled main thread simply finds it settled. Do
  not step it forward by hand: integrating it cost the backdrop strip hundreds of points of
  overshoot after one late tick, which is what swept back across the screen.
- A flight does not run down a straight line. `FlightCurve` bows it to one side and swells the card,
  both peaking in the middle and nothing at the ends, so the card still leaves and lands exactly
  where the layout puts it. The amounts are `ui.flightArc` (a fraction of the path's length),
  `ui.flightArcMax` (the bow's cap in points), and `ui.flightDepth`; the motion scale multiplies the
  first and the third, so `motion: 0` and Reduce Motion give a straight line. The bow leans up from a
  path that runs mostly sideways and left from one that runs mostly up or down, and the side belongs
  to the line rather than the direction of travel, so a flight that turns around mid-air keeps bowing
  the same way. `TransitionLayer`'s `Bow` animates the card's centre and a blend between the
  flight's old and new paths, so the curve follows the frame's own spring, and a flight aimed
  somewhere else in mid-air crosses from one bow to the other instead of stepping sideways. The
  blend settles at 1, where only the new path counts and its own end is flat, so the card still
  lands exactly on its target. A flight also carries a `Look` (corner, shadow opacity, radius, y)
  animated from `.annotator(ui)` to `.card(ui)`, so its shadow shrinks along the path instead of
  swapping for the card's at the end; `AnnotationController` reads the annotator window's frame
  shadow from the same `Look.annotator`, so the two ends cannot drift apart. `dropShadow(id:)`
  zeroes a flight's shadow in the same run-loop turn the card appears or the annotator window
  comes up, so the shadow is never drawn twice and never missing for a frame.
- Nothing takes a flight's place until it has arrived. A spring's tail runs well past its nominal
  duration: at `expandDuration * 1.15` it is still a few points short, and a card or a window put
  at the exact target then steps by that much, shadow included. `fly` therefore answers on
  `arrived`, at `Anim.settle` (when the spring is within half a point of the target, with the
  flight put exactly on it in that turn): the card retakes its slot there, the annotator window
  comes up there, and `lift(id:)` removes the flight image then or later, when the page reports the
  shot. The annotator draws the same ring and shadow as the flight, so a window put up earlier
  would step against the picture the flight is still showing; the cost is the toolbar, which is
  outside the flight image and appears with it. The window is at the fitted frame by then whatever
  the zoom was: `hide` springs the level back to 1 first and comes down once that has arrived, so
  the flight starts where the picture is (`AnnotationController.fitBeforeHide`).
  `docs/shadow-2026-09-17.md` has the frames.
- A card in the stack and the same card in flight have to cast the same shadow. The column is
  masked with a fade over the panel's inset at each end (`StackView.column`), and the newest card
  rests on the viewport's bottom edge, so the bottom fade starts below its shadow rather than
  through it: solid for `StackLayout.cardShadowRoom` and fading over what is left of the inset.
  `StackLayout.inset` is therefore at least that room plus `shadowFade`, so a shadow bigger than
  `ui.panelInset` grows the panel around the column instead of being cut off; the cards do not
  move, since their frames are measured from the panel's edge inwards. The flight's shadow is cast
  by the clipped image, before the ring, for the same reason.
- The backdrop's progressive blur is a stack of masked NSVisualEffectViews with different radii.
  The private CAFilter variableBlur ignores its mask when the backdrop renders in the window
  server on macOS 15 (verified: uniform blur), and a bare CABackdropLayer renders black. Do not retry.
  The band masks are one-pixel bitmaps stretched to the strip and cached by width: a drawing-handler
  image is shaded at the strip's full height on every show (measured: 12 ms per open).
- The status item has an autosave name and a seeded preferred position. Without it, a crowded
  menu bar on a notch Mac puts the new icon under the notch and it never appears.
- Files named `*-annotated.png` are outputs and are ignored by the watcher. `Stitch *.png`
  outputs are not ignored on purpose: they arrive like a capture, which is what carries a stitch into
  the annotator when `annotateOnCapture` is on. The watcher takes png, jpg, jpeg, and heic
  (`ScreenshotWatcher.candidateExtensions`), reports removals to the stack
  (`[watcher] removed`), waits for a new file to decode before reporting it, and gives up on one
  that never does after ten seconds (`[watcher] error never-stable`); the next folder event or
  stack open picks it up. Wake from sleep rescans the folder. The watcher also keeps an index of
  the folder (name and modification date, from one bulk listing) so opening the stack and finding
  the newest screenshot never list the folder on the main thread (measured: a per-file attribute
  read cost 150 ms on 1300 files at every open). Every stack open asks for a rescan, which is how
  the index catches a file changed in place. While the folder cannot be watched (a volume not
  mounted yet) the reads list it directly and each rescan retries the watch. Copying puts the PNG
  on the pasteboard and promises the TIFF, which is rendered only when a paste target asks.
- Stitching from the stack is one motion, not a file appearing later. `ThumbnailController.stitched`
  takes the cards the image was made from out of the column, holds a slot for the new card at the
  bottom, and hands both to `TransitionLayer.converge`: the pieces fly into that slot while the
  finished image fades in under them. Both sets of cards sit in `model.forming` while their image is
  in the transition layer, so a slot keeps its place in the column and draws nothing, and the image
  is never on screen twice. The watcher reports the file a moment later as usual; the card is already
  there, so `insert` ignores it, and with `annotateOnCapture` on that same report flies the new card
  into the annotator. Only the choreography is new: the composing, the file, and the copy are
  unchanged, and with the stack closed (a `shotnote://stitch` from a script) the toast is still the
  whole of it. Dismissing the stack mid-converge ends the pieces' flights with it and the stitch
  says so as a toast instead of marking a card that has gone, so it never finishes in silence.
- The stack panel is non-activating but can become key (`ThumbnailPanel.acceptsKeys`). Never
  call `NSApp.activate` for it; the user's app must stay frontmost. While a card is in the
  annotator the panel gives up key status so typing reaches the editor.
- Which card a key acts on is one variable, `model.focused`. The stack focuses the newest card the
  moment it takes keys (`takeKeys`), so arrows, Space, and Return act on a card without a first
  click or arrow press, and the pointer moves the focus too: moving onto a card focuses it, and
  leaving the card leaves the focus there, so the card the mouse last named is the one a key acts
  on. The pointer only moves it while the stack holds the keys; while the annotator has them
  nothing moves. A shortcut runs on the selection when there is one, else on the focused card
  (`targetCards`). The ring says where the focus is: the accent color on a selected card, white on
  a focused one. So Space over one card after another builds a selection from the mouse alone, and
  Return opens the card the mouse is on.
- The panel widens to the left while cards are selected, to hold the selection strip
  (`StackLayout.stripPlacement` places it, `panelSize(viewport:showsStrip:)` makes the room). Its
  right edge never moves, so the cards stay where they are. Only the column carries the hair of
  alpha that catches clicks and scrolls; the strip's side of the panel stays clear, so a click
  there still reaches the window underneath.
- A card's thumbnail fills the card, so a screenshot whose shape differs from the card's box hangs
  outside the card's frame, and the clip that hides it does not shrink the hit area. The
  `contentShape` in `CardView` holds each card's hover and clicks to its own frame; without it a
  card takes both over its neighbours, and a hovered card, which `zIndex` raises for the Draw hint,
  takes them from the card below.
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
  the card lands (`show`). A swap runs two of these at once. The stack keeps the slot, drawn
  empty, so the card flies back to the same place. Which tool an image opens on is in
  `web/src/config.ts`: `DEFAULT_TOOL` (circle) for a fresh image, `REOPEN_TOOL` (select) for one
  that already has a draft. A reopen drops the selection the draft was parked with and picks up
  the annotation drawn last instead (`lastAnnotation`: the top of the page's z-order, which is
  where tldraw puts each new shape), so a color press, a drag, or Delete acts on that mark.
- Annotations in progress are drafts owned by the app (`DraftStore`), one JSON snapshot per
  screenshot under `~/Library/Application Support/<bundle id>/drafts/` keyed by the file path
  the app uses everywhere (`shot.url.path`), with a preview PNG under `~/Library/Caches/<bundle
  id>/drafts/`. The page holds only the image it is editing: it reports the snapshot shortly
  after every change (`draft` message), and `park` returns the final snapshot plus a preview
  when the user changed it, so the annotator hides only after that answer
  (`AnnotationController.hide(then:)`). Drafts survive relaunches and a web content process
  restart: the terminate delegate reloads the page and the next `ready` re-sends the image
  with its stored draft. A draft for a file that no longer exists is dropped when it arrives,
  and a launch-time sweep removes the rest. A draft whose preview is gone (Caches is the
  system's to clear) is rendered again through `export` once the page reports `ready` and
  nothing owns its canvas, one `[draft] preview <file>` line each; normally there is none, and
  a refusal leaves the rest for the next launch. The snapshot's asset `src` is the file path; the
  page's asset store resolves it to the served URL, so a stored draft never contains a token.
  Loading a snapshot inside `editor.run(fn, { history: 'ignore' })` keeps it out of undo history.
- A draft can arrive without anyone opening the editor: `add?marks=` sends the image and the marks
  to `window.shotnote.build`, which puts them on the page's canvas, takes the snapshot and a
  preview, and puts the canvas back the way it was (like `export`, and inside the same
  `history: 'ignore'`). That borrows the canvas for the length of one rendering, so a build is
  refused while anything else owns it (`AnnotationController.canvasRefusal`): the annotator owns it
  from `prepare`, half a second before its window appears, until `park` answers, and an export owns
  it for as long as Copy Annotated runs. A refusal is one `page-not-ready` line and no file copied.
  Every call that touches the canvas — `load`, `reset`, `park`, `export`, `build`, and `finish` —
  runs one at a time on the page, in the order the host called them: the rendering ones take their
  snapshot after an `await` and put the canvas back afterwards, so an image that landed in between
  would be stored under the wrong key or wiped.
  Only the canvas change waits in that queue; a load reports `loaded` two frames later, and the
  flight waits for that, so a load behind a long export keeps the card in the air instead of
  showing an empty window. The transition reducer knows nothing about a build, on purpose:
  nothing is shown, so no card, dim, or flight is involved.
- Zoom belongs to the app, not the page. A pinch, cmd+wheel, or cmd+plus/minus/0 sends a
  `zoom` message (tldraw never sees those wheels; a plain wheel still pans a magnified image) and
  `AnnotationController.zoom(by:at:as:)` moves one number, `zoomLevel`: how far the image is
  magnified past the frame it opened in. `Zoom.split` divides that level between the window's scale
  and the page's camera in one place, so `window * camera` is the level and the two cannot disagree:
  the window grows up to the visible screen and the camera stays at exactly 1 until it cannot grow
  further. Zooming out reverses that and stops at the fitted size with a short pull that springs
  back. The toolbar stays where `prepare` placed it and sits above the window as a child.
  One spring carries the level, ticked by the screen's display link, so nothing teleports and a
  gesture, a key and a fit bend into each other; a gesture's spring is short (it follows the
  fingers), a key's, a double tap's and a fit's is longer. What tells them apart is the cursor: a
  gesture names the point it is over, a key names none. Each tick sets the frame's rect from
  `Zoom.frame` and then scales the web view's layer by **the frame's own bounds over the size the
  page was laid out at**, so the image's edges are the frame's edges by construction, in one layer
  commit. `moveFrame` is the only place the rect is set and it publishes it through `frameOnScreen`
  and `frameOnScreen` reads that rect back. The page is relaid out at the frame's size only once a spring has arrived
  (on the next turn of the run loop, and skipped if a new input has arrived), because a page laid
  out smaller than it is drawn is soft; the relayout is a geometric no-op, since the page's
  `fit-max` camera grows with its viewport by exactly the transform the host drops.
  Both phases hold the point under the cursor. The message carries the cursor as a fraction of the
  window (`at`, y from the top), which the window growth and the page's camera each read in their
  own space; a keyboard step sends none and zooms about the window's middle, as Preview does. A
  two-finger double tap (`smartMagnify`) zooms twofold at the tap, or back to the fitted size from
  anywhere above it. `Sources/Zoom.swift` is the geometry: the window grows away from the anchor,
  at scale 1 it is the fitted frame again whatever the anchor, and against the screen edge the
  frame slides and the anchor gives way, which is where magnification takes over. The anchor is
  read off the frame on screen at each step, so a frame the edge nudged does not carry that error
  forward, and a step aimed somewhere else mid-spring blends from the anchor it had to the new one
  (`ZoomAim`) instead of stepping sideways. Zoom's springs are in code rather than the tweaks, but
  the motion scale still shortens them, so `ui.motion: 0` and Reduce Motion land a step at once.
  The state report's `page.zoom` is the in-window
  magnification as tldraw sees it (1 = the image fills the window), `page.visible` is the part of
  the image the window shows, `annotator.zoomLevel` is the one number, `annotator.zoom` and
  `annotator.canvasZoom` are its two halves, and `annotator.zoomAnchor` is the point zoom is
  holding. `docs/zoom-2026-09-17.md` says why it is shaped this way.
  "Copy Annotated" hands the stored snapshots to the live editor (`window.shotnote.export`),
  which restores the canvas afterwards; it falls back to the original file for cards without a
  draft, and answers `error export-failed` or `export-timeout` (15 s) instead of hanging.
- Memory is bounded in three places. `Thumbnailer` keeps decoded images under `budgetBytes`
  (96 MB of RGBA), least recently used out first. Card previews never exceed
  `Config.previewMaxPixel` on the longest side: park previews are rendered at that size by the
  page, and the full-resolution Done rendering is downsampled before it reaches a card or the
  disk. Screen-size flight decodes are dropped whenever the stack hides. Every image that reaches
  a card is decoded before it gets there (`Thumbnailer`, draft previews through
  `Thumbnailer.decode`): an `NSImage(data:)` is decoded by Core Animation at its first commit, on
  the main thread, which cost the stack's first paint 40 ms for ten previews. The cover a zoom's
  relayout hides behind is a snapshot of the web view at its previous rest size (about 59 MB at 2x
  on a 5K display); there is one at a time, and it is freed when the page reports it has painted or
  after two seconds.
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
- `send` (`Send.swift`, debug only) shells out to herdr, which is the only thing on the machine that
  knows which panes hold a coding agent: `herdr agent list` names them, `herdr agent prompt` types
  one line into one of them. The image travels as a path the agent opens itself, so the agent must
  already be allowed to read it or it stops on a permission prompt and herdr reports it as
  `blocked`. The herdr calls are socket round trips, so they run off the main thread and the
  `[send]` line arrives when herdr answers. Without herdr the command is one `no-agent` error;
  nothing else in the app depends on it. `docs/send-to-agent-exploration-2026-09-17.md` has the
  routes that were measured and why the others were refused.

## Adding things

- An action: add a `ShotAction` to `Config.actions` and a method on the `Actions` protocol. Its
  `placement` decides whether it is a hover button on a card, a button in the selection strip, or
  both; `key` gives it a shortcut inside the recent stack. It is a `shotnote://<id>` URL either
  way. Actions always receive a list of screenshots: in the order the cards were selected when the
  stack runs them, and in the order a URL names its `file=` parameters otherwise. `annotate` opens
  the last of them, since the annotator holds one image, and says so in its `ok` line.
- An editor tool or color: edit `web/src/config.ts`. A tool needs an SF Symbol name for the
  native toolbar; a color needs the hex the swatch shows.
- A new message across the bridge: add it to both bridge files, then handle it in
  `AnnotationController` and `App.tsx`.
