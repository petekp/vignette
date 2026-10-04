# An end-to-end test suite (2026-09-29)

Status: built, 22 scenarios. All 22 passed on 2026-10-03, with `--input`.
"Where things stand" is at the end.

Pete wants a suite of end-to-end tests to run before this release and every later one, so that
what a person does with Vignette is checked on the running app and a regression is caught before
it ships.

## Recommendation

- **A small release gate first, then growth.** 0.1.2 waits for the test-launch fence, the runner
  and five smoke scenarios, not the whole suite. The rest of the release still rests on
  `scripts/release.sh`, which already checks the stapled image with `stapler validate` and `spctl`,
  and on fresh installs in a Tart VM (`docs/install-setup-hardening-2026-09-30.md`).
- **One runner, `scripts/e2e`,** that builds a test copy from the current source, launches it on a
  scratch home, settings file and watch folder, runs scenarios, and writes a report: pass or fail
  per step, with the log lines, the state, and a capture of the app's own windows.
- **Scenarios drive the app through `vignette://` commands and `scripts/input.sh`,** and check the
  `[state]` report, the command's `ok` or `error` line, the files the app writes, the pasteboard,
  and the pixels of a rendering. Every key or click is gated on the test copy's own `stack.key` or
  `annotator.key`, read in the same step.
- **A test launch cannot reach anything of Pete's.** That needs one fence in the app, below, and
  the runner's own rules.

## The test-launch fence

A test launch is one with `VIGNETTE_SETTINGS` set. Today it already keeps out of `~/.claude`,
`~/.codex`, Apple's screenshot defaults and the login items. It does not keep out of Codex or the
update feed, and its skill names the real app.

1. **Codex.** A test launch lists Pete's real Codex threads and can queue a message into one.
   `CodexConnection.binary()` goes through `AgentTools.path`, which since 8849a39 also looks in the
   version managers' folders and asks the login shell. That found `~/.vite-plus/bin/codex`, and the
   tools inherit the app's `HOME`. It also defeats the trailer's fence, which empties
   `binaryPaths` (`trailer.py`): a take's stage copy now lists Pete's Codex threads, and a recent
   one can become Send's default target. **Fix:** in a test launch, Codex and herdr are used only
   when `VIGNETTE_CODEX` or `VIGNETTE_HERDR` names a binary, for listing, for submitting and for
   the Codex app's title search. It fails closed.
2. **Claude Code needs no fence.** Send lists only sessions whose plugin wrote an inbox under the
   copy's own Application Support folder (`liveInboxes`), and a test copy has its own bundle id.
   herdr only marks which listed session has the focus. A fake session is a folder with an inbox
   file and a live pid, which `.scratch/fake-sessions.sh` already writes; it moves into the repo.
3. **The skill.** `skills/vignette/SKILL.md` names `vignette://` and `Vignette.log`, and
   `AgentPlugin.stage` copies it as it is, so a test copy's plugin tells its agent to drive Pete's
   Vignette. The trailer patches the source to avoid that. **Fix:** `AgentPlugin.stage` writes the
   scheme and log name from `Identity`. This also fixes forks, which AGENTS.md says rename things
   in project.yml only.
4. **Updates.** A test copy keeps `SUEnableAutomaticChecks` and checks the real feed. With the menu
   bar icon hidden, Sparkle can put up its window mid-run. **Fix:** a test launch does not start
   the updater.

With the scheme read from a build setting in project.yml, the test copy is built from the source
as it is, with its bundle id, name and scheme given on the `xcodebuild` line and its own derived
data folder. The trailer can then drop its source patches.

## The runner's rules

- **Pete's build is stopped for a run and put back after,** even when a step fails. Both copies
  would otherwise answer the same double tap, and a key meant for the test stack could reach his.
  The test copy also gets its own key combination.
- **Two test bundle ids.** `…vignette.e2e` is granted Accessibility once, by hand; the double tap
  and the Dock's rect need it. `…vignette.e2e-fresh` is reset with `tccutil` before a run, for the
  untrusted paths and setup's Accessibility request.
- **The pasteboard is saved and put back,** skipping concealed types (passwords), and put back by a
  trap when the runner is stopped. Clipboard managers still record what a run copies.
- **Files a scenario deletes go to the real Trash;** the runner removes them from it by name.
- **The Mac stays usable for the run:** `caffeinate`, Do Not Disturb, and a check that the session
  is unlocked. On 2026-09-29 synthetic keys reached Slack.
- **Timing:** each wait is on a log line or a state value, never a sleep. The smoke scenarios run
  at motion 1, because the flights and the press handover are the fragile code and motion 0 skips
  them.
- **The driver:** the generic helpers from `media/trailer/drive.py` (`url`, `wait_log`, `state`,
  `wait_state`, `require_*`, `stop_pid`) are copied into `scripts/e2e`, and the trailer is left
  alone. `state()` also checks the watch folder, and the window check compares pids, not names,
  and asks whether the pixel under the point is clear, since the annotator's window spans the
  screen.

## The scenarios

**The smoke gate for 0.1.2:**

| Scenario | What it checks |
|---|---|
| Launch | `[app] ready`; the fence's log lines; no login item; no Codex listed; `vignette://help` lists every command. |
| Capture and draw | A file in the watch folder shows a card. Draw opens it; wait for `takes events reached=true`; a box and a note are drawn. Done puts a PNG on the pasteboard with the marks in the person's colour. A JPEG capture's copy is `public.jpeg`. |
| Agent push | `add?marks=` shows a card with the agent's tab and marks. A `color` is ignored and logged. |
| Send and Reply | Send to a fake session writes one request to its inbox. `scripts/reply` with the ticket makes a reply card; a wrong ticket is refused. Reply goes back to the same fake. |
| Relaunch | Drawings, settings and open requests survive a relaunch. |

**After the release,** in this order:

- **The stack:** the double tap and hold, arrows, Space, Return, the strip's actions, Stitch with a
  recording, and Delete.
- **The editor:** the annotate queue, a swap mid-flight, an interrupted flight, zoom keys, undo, and
  an agent's note becoming the person's.
- **Settings:** a live edit reaching the editor, a bad colour repaired, a file that does not parse
  moved to `.invalid`.
- **Setup,** on the fresh bundle id.
- **Memory:** RSS stays bounded after twenty opens.
- **Frames:** a recording of a flight, checked for a blank or doubled frame. `frames.sh` extracts
  and tracks; the check itself is still to write.

Some checks need state the app does not report: the setup page, a send notice on a card, and
whether a note's lines are balanced. Each gets a field in `[state]` when its scenario is built.

## Later: a clean Mac

Installing from the disk image and updating from the previous version need a Mac that has never
run Vignette. A Tart VM can do it, but it takes days: the image must carry the quarantine flag or
Gatekeeper never checks it, granting permissions in the guest needs its screen, and posted events
need its login session. The update test also needs a published release that has the updater: 0.1.2
updating to 0.1.3, through a feed the test can point at. Both were checked by hand in a Tart VM:
the update from 0.1.2 to 0.1.3 in `docs/updater-2026-09-27.md`, and fresh installs in
`docs/install-setup-hardening-2026-09-30.md`.

## Order of work

1. **Fix the Codex leak** in the test launch. It is live now, in the trailer and in every stage
   copy.
2. The rest of the fence: the skill from `Identity`, no updater, the scheme as a build setting.
3. The runner, its rules and the report.
4. The five smoke scenarios, then cut 0.1.2.
5. The later scenarios.

## Decisions for Pete

1. **Does 0.1.2 wait for the smoke gate?** Recommendation: yes. It is steps 1 to 4.
2. **Where it runs.** Recommendation: this Mac, with your build stopped for the run. A second macOS
   user account is safer (its own pasteboard, home, Trash and permissions, with no agent sessions
   and no running Vignette) and costs a one-time setup there.
3. **The one-time Accessibility grant** for the `.e2e` bundle id, by hand.
4. **Test hooks in shipping code.** The fence adds `VIGNETTE_CODEX` and `VIGNETTE_HERDR`, and new
   `[state]` fields later. They only act in a test launch.
5. **A real Claude Code session.** Recommendation: not in the gate. Once the skill names the test
   copy, a scenario with a real session can run before a release, signed in and costing tokens.

## Where things stand (2026-10-03)

Pete approved the plan, the release gate, running on this Mac, the test hooks, and granted
`Vignette E2E` Accessibility.

**Built:**

- **The fence.** A test launch runs codex and herdr only when `VIGNETTE_CODEX` or `VIGNETTE_HERDR`
  names one (`AgentTools.forSessions`), and logs `[tools] test launch: codex=… herdr=…`. This also
  closes the leak in the trailer's stage copy. The staged skill names the copy's own scheme and log
  (`AgentPlugin.stage`). Two unit tests cover both.
- **The build.** `VIGNETTE_URL_SCHEME` is a build setting in project.yml, and the trailer reads it.
  `scripts/e2e/build.sh` builds `Vignette E2E` (`com.petepetrash.vignette.e2e`, `vignette-e2e`) from
  the source as it is. `build.sh fresh` builds the untrusted copy.
- **Updates in a test copy** are off through Sparkle's own user default,
  `SUEnableAutomaticChecks false` in the copy's scratch domain, so no code change was needed.
- **The runner**, `scripts/e2e/e2e.py`, with `probe.swift` for the pasteboard, pixels and test
  images. It saves the pasteboard, skipping a concealed item, and puts it back on exit or
  `e2e.py restore`.
- **`scripts/fake-herdr` is removed.** Nothing ran it.

**Scenarios** (`e2e.py list` prints them; "input" ones run only with `--input`):

| Scenario | Input | What it checks |
|---|---|---|
| `launch` | no | the fence's log lines, no login item, `help` lists every command, bad files answer errors |
| `first_launch` | no | setup shows and turns Apple's thumbnail off; quitting puts it back and asks again next launch |
| `upgrade` | no | a 0.1.1 settings file keeps only what differs from 0.1.1's defaults |
| `agent_push` | no | a push's marks in the agent's colour, a named colour ignored, Copy Drawing's rendering; a second Copy Drawing writes a new file and leaves the first as it was |
| `annotate_open` | no | the editor has the agent's marks, the bar offers Copy alone, a push joins the open drawing |
| `send_target` | no | the bar offers Send to a fake Claude Code session |
| `send_target_codex` | no | the bar offers Send to a fake codex's thread, listed by `codex app-server` |
| `copy_types` | no | Copy puts a JPEG's and a PNG's own bytes on the pasteboard under their own types |
| `stitch` | no | Stitch writes one image, and its card comes up with the Copied notice |
| `instant_draw` | no | with Instant Draw on, a capture is copied and opens straight in the editor; closed with nothing to show, it leaves the corner at once |
| `relaunch` | no | drawings and settings survive a relaunch |
| `settings_repair` | no | bad values are clamped and logged; a file that does not parse is set aside |
| `draw_and_done` | yes | a drawn box in the person's colour; Return's PNG bytes and file URL match its rendering |
| `annotate_queue` | yes | Return goes through three images with the dim up; a cancel ends a run with images waiting |
| `zoom_keys` | yes | Cmd+Minus at the fit moves nothing, Cmd+Plus grows the frame, Cmd+0 brings it back |
| `send_and_reply` | yes | one request line in the fake session's inbox; a reply through the helper is a card; a ticket copied elsewhere is refused |
| `send_message` | yes | M puts the keys in the message field, and Return there sends with the message ahead of Vignette's line |
| `send_and_reply_codex` | yes | the same send and reply, through one `codex queue` call to the fake codex |
| `send_codex_thread_gone` | yes | a send to a thread deleted after the bar offered it fails as a thread that is gone |
| `send_codex_queued` | yes | a send to a thread no engine has loaded is reported as queued |
| `agent_marks_editable` | yes | a click selects an agent's mark and a drag moves it |
| `corner_select` | yes | a click on a corner card's circle makes the corner the stack, with the strip out |

**Found while building it:**

- **The git stamp could land before Xcode wrote the Info.plist.** The phase declared no inputs, so
  nothing ordered it after `ProcessInfoPlistFile`. In the E2E build it ran first, and the app came
  out as `build=local`, `CFBundleVersion` 0; a release stamped 0 would break Sparkle's version
  comparison. Fixed with Pete's approval: the phase takes the processed Info.plist as its input, and
  `release.sh` refuses an archive stamped 0.
- **A reply's secret is checked against `ticket.json` on disk**, so rewriting that file rewrites the
  reference. That is not a hole, since whoever can write the file can read the real secret, but it
  is why the end-to-end check cannot test a wrong secret through the helper.

**Next:** grow the suite in the order above. The newer features without a scenario are Delete on a
lone thumbnail, the send notice on a card, and the setup's close into the menu bar icon.
