# Driving the app

1. Change code.
2. `./scripts/run.sh`
3. Drive the app: `open -g vignette://annotate` (or `copy`, `trash`, `last`, `recent`, `state`;
   `open -g vignette://help` logs every command). Plain `open` activates Vignette; `-g` does not.
   Aim each command at your own build with `open -g -a`, as `AGENTS.md` says.
   A relaunch from `open` carries no `VIGNETTE_SETTINGS`, so it runs on the user's real settings
   and folder, and when another copy of the bundle id is running `open -a <path>` can launch that
   copy instead of the path given. Launch a test copy only with an explicit
   `open -g --env VIGNETTE_SETTINGS=<path> --env CFFIXED_USER_HOME=<home> <app>`, never on the
   `LSEnvironment` in its Info.plist alone: on 2026-11-14 a bare `open -g` of a copy rebuilt in
   place ran without its `LSEnvironment`, so it was not a test launch, and it showed setup and
   watched the user's own screenshot folder. Running `<app>/Contents/MacOS/Vignette` directly always lands on
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
   round.
   Every command ends with one `[<cmd>] ok <detail>` or `[<cmd>] error <code> <detail>` line; the
   codes are the `CommandError` cases in `Commands.swift`. `file=` must point inside the watch
   folder, and `install-skill?root=` and the commands `help` marks as needing `debug` (the labs,
   `tweaks` and the `live-ink-*` commands) are refused, unless settings.json has `"debug": true`. A `file=` inside the folder becomes a `ScreenshotKey` through
   `ScreenshotKey(resolving:in:)`, which resolves links on both sides and answers the folder's own
   spelling, so `/tmp/x.png` and `/private/tmp/x.png` reach one drawing.
   `add` takes images from outside the folder, as `docs/rules/agent-push.md` says.
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
   Never send Escape that way (the rules in `AGENTS.md`): if the stack is not key, the frontmost app
   gets it, and a terminal running an agent takes it as the interrupt key.
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
   `notCopied`, the reason a copy failed or null, `notSaved`, whether the card says its drawing was
   not saved; `selected`,
   `focused`, `hovered`, `queue`, the files waiting for the annotator, `visible`, `key`, `isStack`,
   `scroll`, `viewport`, `safeBottom`, the room the Dock keeps under the column, panel,
   `panelOnScreen`, `widthScale`, how wide the stack is drawn, `swipe`, how far a swipe has moved the
   column toward the edge, `older`, the chunks of older cards (`loading`, `reachedOldest`, `added`), `strip`, the selection strip's
   frame or null, and `undoTitle` and `redoTitle`, the stack's Edit menu words, "Undo Move to Trash"),
   `transition` (phase), `annotator` (`current`, `frame`, `toolbar`, `windowVisible`, `key`, `tool`,
   and the zoom's own keys, which `docs/rules/zoom.md` names), `editor` (`open`, `tool`, `marks`
   with each mark's `type`, `frame` and `agent`, `selection` as indexes into `marks`, `typing`,
   `undo`, `redo`, `pointScale`, `markScale`; never a text's words), `drawings` (keys), `requests`,
   `memory` (rss and thumbnail cache in bytes), `backdrop`, `dim`, and `liveInk` (`docs/live-ink.md`).
   Frames are `[x, y, w, h]` in global top-left points, except a drawing's mark's, which is in the
   image's pixels.
   `[app] ready pid=… build=… watching=…` marks the end of launch: after it every command
   answers. `build` is `git describe` of the checkout, written into the bundle by a build phase
   (project.yml), so a build from Xcode carries it too.
   Log grammar (`Log.swift`): one event per line, `HH:mm:ss.SSS [tag] …`, details as
   `key=value` pairs, never an embedded newline (the logger flattens them); the launch line ends
   with `date=YYYY-MM-DD`; at 5 MB the file rotates to `Vignette.log.1`, replacing the previous
   one. Drawing events: `[drawing] saved|parked|built|removed|swept|dropped <file>`, and
   `[drawings] <n>` after every change to the set.
   `[stack] shown cards=… files=… listed=…ms shown=…ms decoding=…` counts the watch folder from
   the watcher's index, and times the listing and then the cards' presentation.
   `[undo] undid|redid <step>: …` follows each Cmd+Z and Shift+Cmd+Z in the stack, and
   `[undo] can't undo|redo <step>: <why>` one whose file has moved since; `[stack] put back cards=<n>`
   follows the cards coming back (`docs/rules/stack-undo.md`).

A fake screenshot for testing: `screencapture -x -R 200,200,900,560 "<watch folder>/Screenshot test.png"`.
Delete it afterwards. Never retype a
real capture's name to reach it: macOS writes the time with U+202F, a narrow no-break space, before
AM and PM, so a typed path with an ordinary space is a different path and every call on it answers
ENOENT while `ls` still lists the file, which reads as the file being unreadable rather than
misnamed. Take the name from a listing (`os.listdir`, `contentsOfDirectory`) and pass it through.
The prefix is no safer: it is `defaults read com.apple.screencapture name`, the user's to change,
and screen recordings share it, so `Screenshot ….mov` is a recording and only the extension says so.

## What a test launch keeps away from the person's data

A test copy never touches the person's own `~/.claude`, `~/.codex` and `~/.agents`, or the
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
