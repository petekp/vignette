# Measuring and testing

Measuring a handoff or a flicker: a burst of `screencapture -x -R x,y,w,h` reaches about 12 frames a
second; `screencapture -x -v` records the region at 60, and the frames read back with AVFoundation
give a per-frame position of an edge or the mean brightness of a band, which is how a one-frame
step, a doubled shadow, or a mismatch between a frame and its picture is proven or ruled out.
Compare before and after on the same driven sequence. `scripts/measure/frames.sh` reads a recording
back: `extract` writes its frames as PNGs, `sheet` lays out crops of the frames at given times on
one labelled image, and `track` prints a rect's mean colour in every frame. A rect is in points from
the recording's top-left, at the main display's scale; `FRAMES_SCALE` sets another.

Measuring a stutter: launch the app under Instruments and drive it as `docs/rules/driving-the-app.md` says.
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
`scripts/e2e/scenarios.py` and `live_ink.py`, each on a fresh scratch home, settings file and watch
folder. Before each launch the runner links the home the copy's Info.plist names to the scenario's,
and unlinks it after, so a launch with no environment comes back on the scenario's files. Before the
first scenario it runs the copy once, as `<executable> reply --help`, which exits before the app
starts. macOS checks a new build's first run, and now and then kills it:
syspolicyd logs "Terminating process due to Gatekeeper rejection". In the VM that was 1 first
run in about 30 (measured 2026-10-26). `open` still answers 0 for a killed launch, so a scenario
would wait out its 30 s. The runner retries a killed run and prints how long it took
and whether macOS killed it. It saves the pasteboard and puts it back, even when stopped (`e2e.py restore` after a
crash), and writes a report under `scripts/e2e/out/runs/`. `--input` adds the scenarios that post keys and clicks, each
gated on the test copy's own state; they need `Vignette E2E` and the terminal that runs them granted
Accessibility and Screen Recording, once by hand. Without Screen Recording, every live ink ask fails
at its picture, which `ink_no_recording` checks on `Vignette E2E Fresh` (`build.sh fresh`), granted
nothing and reset with `tccutil` before it. On macOS 15, the run's first screen capture
can raise a prompt asking whether the terminal may "bypass the system private window
picker". While that prompt is up, the test copy cannot become active (observed 2026-10-01 in a
clean VM), so every scenario that needs the keys stops at its gate.
Allow it and run again.
`docs/e2e-suite-plan-2026-09-29.md` has the design and what is still to come.

Testing Send without a real session: a Claude Code session is an inbox folder under the copy's
Application Support (`Identity.applicationSupportURL`, which for a copy on your own home is
`<settings folder>/Library/Application Support/<bundle id>`), `claude-sessions/<pid>/` with `session`, `cwd` and a fresh `alive`, and `<pid>`
a live process (`App.fake_session` in the runner). Send writes its request line there. A Codex
thread is listed by a fake codex that `VIGNETTE_CODEX` names (`App.fake_codex`,
`scripts/e2e/fake_codex.py`): it answers `app-server`'s `initialize` and `thread/list`, and records
each `codex queue --thread <id> --message <line>`, which is how Send hands a Codex thread its line. Launched
with `--env CFFIXED_USER_HOME=<folder>`, the app takes that folder for the home folder, so the Agents
tab and setup read and write a scratch `.claude` rather than the user's; its log is then under that
folder's `Library/Logs`, which must exist before the launch, or the log lines are dropped. A
scratch home moves files, not preferences: `defaults` and `UserDefaults` ignore
`CFFIXED_USER_HOME` and write the real `~/Library/Preferences` (measured 2026-10-26 on macOS 15). A
test copy's preferences are kept apart from the person's by its bundle id, in `<bundle id>` and,
as a test launch, `<bundle id>.screencapture`. So its screenshot location is
`defaults write <bundle id>.screencapture location <watch folder>`. Those two domains outlive a
scratch home, so the end-to-end runner clears both before each scenario (`App.reset_defaults`).
