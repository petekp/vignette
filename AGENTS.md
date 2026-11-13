# Working on Vignette

Vignette is meant to be modified. This file is the onboarding for a person or an agent: the
guardrails, and a map to the rules and contracts in `docs/rules/`. The dated notes in `docs/`
hold the measurements and the reasoning; a rule points at its note. `docs/adr/` records the
decisions that are hard to reverse, one file each, with what was weighed. Add one when a change
makes such a decision, and mark the old one superseded when a change reverses it.

## Before you change an area

The rules for each part of the app are in `docs/rules/`. Before changing a file or doing a task
this list names, read every file its entry points to. A test file goes with the source file it
tests. A new rule goes in its area's file, and a new area gets a file and an entry here.

- Before driving the app, reading its log or `[state]`, or changing `Commands.swift`,
  `StateReport.swift`, `Log.swift` or `Launch.swift`, read `docs/rules/driving-the-app.md`. Its
  scratch settings file is in the settings.json rule of `docs/rules/settings.md`.
- Before measuring a flicker or a stutter, running or changing the end-to-end tests
  (`scripts/e2e/`, `scripts/measure/`), or testing Send without a real session, read
  `docs/rules/testing.md`.
- `docs/releasing.md` says what a release must pass, how to cut and publish it, and how to write
  its release notes.
- Before changing `Settings*.swift`, `UITweaks*.swift`, `TweakCatalog*.swift`,
  `AppleScreencapture.swift`, `DebugPanel.swift` or `ThisMac.swift`, or adding a number a person
  might tune, read `docs/rules/settings.md`.
- Before changing the shortcut, the watcher or a screenshot's file (`HotKey*.swift`,
  `ModifierTap.swift`, `KeyMonitors.swift`, `CaptureOrigin.swift`, `ScreenshotWatcher.swift`,
  `ScreenshotKey.swift`, `Screenshot.swift`, `FolderWrites.swift`), or how a recording or an
  iCloud file is read, read `docs/rules/capture.md`.
- Before changing setup, the Settings window or the menu bar icon (`Setup*.swift`,
  `SettingsWindow.swift`, `MainMenu.swift`, `MenuBarIntro.swift`, `IntroFunnel.metal`,
  `IntroLab.swift`, `FunnelFlight.swift`, `DropLanding.swift`, `PermissionRow.swift`,
  `AppLocation.swift`, `LoginItem.swift`, `Updater.swift`, `BuildInfo.swift`,
  `ProblemReport.swift`), read `docs/rules/setup-and-updates.md`. The status item's place is in
  `docs/rules/capture.md`.
- Before changing the stack or the corner (`Stack*.swift`, `OlderShots.swift`, `CardPictures.swift`,
  `CornerPresentation.swift`, `CornerKeys.swift`, `CardView.swift`, `CardState.swift`,
  `SelectionStrip.swift`, `Stitch.swift`, `Dock.swift`, `BackdropPanel.swift`, `FocusReturn.swift`,
  `DragSourceView.swift`, `CheckCoin.*`, `CheckLab.swift`), read `docs/rules/stack.md`,
  `docs/rules/stack-column.md` for the long column, and `docs/rules/flights-and-presses.md` for the
  matte and the flights in and out of the column.
- Before changing a flight, a press or an animation (`TransitionLayer.swift`, `Flight*.swift`,
  `OutsideClick.swift`, `Anim.swift`, `Tween.swift`, `Motion.swift`, `WindowRemoval.swift`,
  `Config.matte`), read `docs/rules/flights-and-presses.md`, and
  `docs/rules/stack.md` for the card shadow a flight must match.
- Before changing `AnnotationRun.swift`, `AnnotatorTransition.swift`, `AnnotationWindow.swift` or
  `DimPanel.swift`, read `docs/rules/annotator.md`.
- Before changing `AnnotatorToolbar.swift`, `SessionMenu*.swift`, `DestinationChoice.swift`,
  `AgentApp.swift`, `InboxModStore.swift` or `HeldToolLetter.swift`, read
  `docs/rules/annotator-toolbar.md`, and `docs/rules/send.md` for what Send does.
- Before changing `Zoom.swift` or `AnnotatorZoom.swift`, read `docs/rules/zoom.md`.
- Before changing the editor, a mark or a drawing (`Editor*.swift`, `Drawing.swift`,
  `Drawings.swift`, `DrawingStore.swift`, `Mark*.swift`, `MarksView.swift`, `Card.swift`,
  `AgentMarks.swift`, `RenderingQueue.swift`, `Clipboard.swift`, `DragItems.swift`,
  `CanvasView.swift`, `Leftovers.swift`), read `docs/rules/editor-and-drawings.md`.
  `docs/editor.md` is how the editor behaves.
- Before changing code that decodes or holds an image, read `docs/rules/memory.md`.
- Before changing Send, a send's notice on its card, or a session list (`CardNotices.swift`,
  `AgentConnection.swift`, `CodexConnection.swift`, `ClaudeInbox.swift`, `ClaudeReadRule.swift`,
  `ClaudeSessionStart.swift`, `AppServer*.swift`, `HerdrFocus.swift`, `SessionListing.swift`,
  `SessionStarts.swift`, `SessionPlaces.swift`, `SendGrace.swift`, `SendOverlay.swift`,
  `SubmissionOutcome.swift`, `Subprocess.swift`), read `docs/rules/send.md`.
- `docs/codex-issues.md` tracks the known problems with Codex and the Codex app, with a progress log.
  Read it before changing anything that talks to Codex, and add to it what you find or fix.
- Before changing `ScreenshotRequests.swift`, read `docs/rules/send.md` and
  `docs/rules/replies.md`. Before changing a reply (`ScreenshotRequestRecords.swift`,
  `ReplyProtocol.swift`, `ReplyCommand.swift`, `skills/vignette/scripts/reply`), read
  `docs/rules/replies.md`, and `docs/rules/agent-push.md` for a reply's title.
- Before changing the `add` command, `Agent.swift`, `AgentTitle.swift`, `AgentTitleView.swift`,
  `TitleBackdrop.swift` or `FlightCaption.swift`, read `docs/rules/agent-push.md`.
- Before changing `agent-plugin/`, `skills/vignette/`, `AgentPlugin.swift` or `AgentTools.swift`,
  read `docs/rules/agent-plugin.md`.
- Before changing the states or transitions of a type `docs/state-machines.md` maps, find the
  type in its Index and read the one file in `docs/state-machines/` that the row names. Those files
  map the app's state machines and the invalid states found in them. Each is under 5,000 tokens.
- `Sources/Live*.swift`, `ModifierChord.swift` and `InkStroke.swift` are live ink, drawing on the
  live screen. `docs/live-ink.md` has its rules, which file owns which part, and how to check a
  change: read it before changing those files, the `vignette` skill's live ink answers, or
  `media/live-ink-demo/`. `KeyMonitors.swift` installs the key monitors live ink and the double tap
  share, once the app is trusted for Accessibility.
- Before changing live ink's other files (`Ink*`, `SetupInk*.swift`, `Note*.swift`,
  `*Driver.swift`, `Responder*.swift`, `JSONLinesProcess.swift`, `CodexIsolation.swift`,
  `CodexRollout.swift`, `CodexSignIn.swift`, `Microphone*.swift`, `*Transcriber.swift`,
  `HandStroke.swift`, `PointerField.*`, `HangingPopover.swift`, `PopoverPlace.swift`,
  `ScreenRecording.swift`, `ScreenSpots.swift`, `ScreenLink.swift`, `ResultCard.swift`,
  `VoiceCaret.swift`, `AppDelegate+LiveInkOffer.swift`), read `docs/live-ink.md`.

These files hold code for several areas. Read the file for the part you change:

- `ThumbnailController*.swift`: `stack.md`; `annotate(_:from:)` and `rename`, `capture.md`; the
  annotation run and `leavesAtOnce`, `annotator.md`; `hover(landing:)` and
  `swallowSecondClick`, `flights-and-presses.md`; `setDrawings` and `showNotCopied`,
  `editor-and-drawings.md`; `showSending`, `send.md`; `applyTweaks`, `settings.md`.
- `AnnotationController*.swift`: `open`, `abandon` and `opening`, `annotator.md`; `show`,
  `landed`, `probeEvents`, `take`, `Removal` and `fitBeforeHide`, `flights-and-presses.md`;
  `moveFrame` and the zoom, `zoom.md`; `offerTyping`, `annotator-toolbar.md`; the title
  (`AnnotationController+Title.swift`), `agent-push.md`; `applyTweaks`, `settings.md`.
- `AppDelegate*.swift`: `main` and the reply command, `replies.md`; `connections` and Send,
  `send.md`; the plugin's install, `agent-plugin.md`; setup, `setup-and-updates.md`; Copy
  Drawing, `editor-and-drawings.md`.
- `EditorView*.swift`: `editor-and-drawings.md`; `setSize`, `restDelay` and the zoom steps,
  `zoom.md`; `takesKey` and `enterCanvas`, `annotator-toolbar.md`; `take`, `flights-and-presses.md`.
- `Thumbnailer.swift`: `memory.md`; `lookUp`, `cardImage`, `download` and `posterFrame`,
  `capture.md`.
- `TransitionLayer.swift`: `flights-and-presses.md`; `converge`, `stack.md`; `Caption`,
  `agent-push.md`.
- `Config.swift`: an action, Adding things below; `stripRows` and `kinds`, `capture.md`;
  `matte`, `flights-and-presses.md`.

## Layout

- `Sources/` Swift menu bar app. `AppDelegate.swift` wires everything; `Config.swift` holds the actions.
- `scripts/build.sh` regenerates the Xcode project and builds the app.
  `scripts/run.sh` does that, waits for the old process to exit, and relaunches. `scripts/build.sh
  --test` also runs the unit tests in `Tests/` (the `VignetteTests` target compiles `Sources/`
  itself; it never launches the app). A build into another `-derivedDataPath` leaves `build/`,
  and an instance running from it, untouched.
- `media/trailer/trailer.py all` records the trailer from the current source: it builds a stage copy
  of the app with its own bundle id, sets up a desktop with the game in Chrome and the trailer's own
  Claude Code in Ghostty, with the stage copy's plugin, drives every beat while it records the
  screen, and cuts the result from `beats.toml`. `trailer.py claude` signs that Claude Code in once.
  A take takes over the screen for 5 to 8 minutes. `docs/trailer-pipeline-2026-09-26.md` says how.
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
- Every checkout builds the same bundle id, so with more than one build on the Mac LaunchServices
  sends `vignette://` to whichever copy it registered last, and that copy's launch replaces the
  instance you started: `open -g -a <your build>/Vignette.app "vignette://…"` aims at yours.
- Launch one copy at a time, behind the lock when agents share the Mac, and put the user's own build
  back after every round.
- A build the user runs from a worktree's build folder is copied to a path no build touches
  before that worktree is rebuilt; a rebuild rewrites the bundle under the running process.
- Never send a synthetic Esc to close the stack or the annotator. Use `vignette://dismiss` and
  `vignette://cancel`.
- Delete test files from the watch folder afterwards. It is the user's real screenshot folder.
- A test copy never touches the person's own `~/.claude`, `~/.codex` and `~/.agents`, or the
  folders under `~/Library` their own app stores data in: with
  `VIGNETTE_SETTINGS` set, `AgentPlugin.roots` leaves out the first two, `AgentPlugins` leaves out
  the third, refuses an install into the person's own folders and runs no agent tool on the
  person's own home, and the launch logs a `[plugin] test launch:` line for each. On the person's
  own home it keeps its Application Support, Caches and WebKit folders under its settings file's
  folder, or the temporary folder when that one would reach theirs (`Launch.dataHome`), and logs
  `[app] test launch: … stores its data under <folder>/Library`. It keeps the app's own defaults in
  `<bundle id>.test-launch` there (`Identity.defaults`); only AppKit's record of the status item's place
  stays in the app's own domain, under a key of the test launch's own. `scripts/check-app-data-paths.py` fails a
  path into `Library` with the bundle id built outside `Identity.swift`. It neither registers nor removes a login item. It runs no updater, and logs
  `[update] test launch: no updater`, unless `VIGNETTE_FEED` names a feed. With one, it checks that
  feed in place of the release feed. Each of these gates reads `Launch.isTest`. To test the plugin, also launch with
  `CFFIXED_USER_HOME=<scratch home>` (`docs/test-isolation-2026-09-29.md`). It runs no codex,
  claude, herdr-app or hc unless `VIGNETTE_CODEX`, `VIGNETTE_CLAUDE`,
  `VIGNETTE_HERDR_APP` or `VIGNETTE_HC` names one
  (`AgentTools.forSessions`), since any other found on the Mac reaches the person's own sessions or
  account; the launch logs `[tools] test launch: codex=… claude=… herdr-app=… hc=…`. The plugin's skill names the copy's own URL scheme and log
  (`AgentPlugin.stage`), and every `open` in it names that copy's path with `-a`, so an agent's
  command never starts another build of the same bundle id on the person's settings.
- Stop a test copy by its PID before you launch another copy of the same bundle id. On 2026-09-26,
  `open -a <a Release copy> <url>`, sent after a Debug copy of the same bundle id had run, launched a
  second Release instance without `VIGNETTE_SETTINGS`, on the user's real settings file.
- A launch through LaunchServices with no environment is not a test launch. macOS's Quit & Reopen
  after a permission grant, Sparkle's relaunch and a bare `open` are all such launches.
  `Launch.isTest` then reads false. The copy reads `~/.config/<its URL scheme>/settings.json`,
  writes Apple's own screenshot settings, can register a login item, runs the updater and reaches
  the person's `~/.claude` and `~/.codex`. The end-to-end copies name a scratch home and settings
  file under `LSEnvironment` in their Info.plist, `/tmp/<bundle id>/home` (`scripts/e2e/build.sh`),
  so one launched that way is still a test launch. `open --env` overrides those values key by key.
  For a test by hand, launch the copy on that home, or link it to your scratch home.

`docs/rules/driving-the-app.md` has the steps and their details.

## Words and motion

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
  `markSeconds`, `sendGraceSeconds`) are not motion, and neither is a movement the user's own hand is driving: the
  drag-select's auto-scroll (`ui.autoScrollZone`, `ui.autoScrollSpeed`, `StackLayout.autoScrollSpeed`,
  ticked by a display link in `StackSweep`) follows the drag at its own speed whatever
  the scale says. `"ui": {"motion": 0}` makes the stack appear and leave at once, which is what a
  script wants. Every SwiftUI animation is a spring made by `Anim.spring` (`slideInCurve` "spring"
  included), and the AppKit tweens use `Tween`'s spring curve: an interrupted motion keeps its
  velocity and blends into the new target instead of jumping. `Tween.spring` is the closed form of
  a critically damped spring, so a late tick lands where the spring really is by then. Do not step
  it forward by hand: integrating it overshoots by hundreds of points after one late tick.
- `docs/glossary.md` is Vignette's vocabulary: screenshots and the corner, drawing, and the agent
  loop. It says what each word means and what not to call it. Use its words in code, docs and
  labels. The distinction it guards most is that an agent session is a conversation and a pane is
  a place.

## Build and signing

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
