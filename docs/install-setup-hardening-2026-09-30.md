# Install and setup hardening (2026-09-30)

Pete's goal: installing Vignette and going through setup must work every time, for every new user.

Three read-only audits covered the path from download to the first minutes of use. Each finding
below says how sure it is:

- **Confirmed** means the code path was traced end to end.
- **Plausible** means it depends on macOS behaviour nobody has measured yet.

The main path works today: a fresh Mac, screenshots on the Desktop, the app dragged to
Applications, setup finished. The failures are on the paths next to it. The worst of them leave
captures silent. Vignette turns Apple's thumbnail off at launch, so anything that stops Vignette
working afterwards leaves the person with no feedback from either app.

## Status

Every item below is fixed and committed, or measured and left as is:

- Sections 1 to 4: 0d73cf5.
- The "Fix next" list: 4aabef3.
- The default key combination: 939c538.

0.1.2 is cut from 939c538 as build 471, notarized and stapled. It is not published yet.

The VM found three more defects in sections 1 to 4, fixed in 0d73cf5:

- A quit during setup ran setup's close handler. A quit now applies nothing.
- The double tap fired twice while Vignette was the active app. Each event now counts once.
- The focus went back to macOS's Accessibility alert after setup. Only a regular app gets it back.

What each "Fix next" item came to:

| Item | Outcome |
|---|---|
| Recorder accepts ⌘Q, ⌘C, ⌘⇧3 | Fixed. It beeps, keeps listening, and says why under the box. |
| Default combination ⌘⇧6 is the Touch Bar screenshot shortcut | Fixed. The default is ⌘⇧2, beside the capture keys, which macOS does not claim. Xcode uses it for Devices and Simulators. |
| Hotkey registration not checked | Measured: Carbon answers success for combinations macOS or another app owns (⌘⇧3, ⌃Space, Raycast's ⌥Space). Only a real failure is logged now. Setup's live try is what proves the keys. |
| Done returns focus to System Settings | Fixed in 0d73cf5. |
| Double tap dead after revoke and grant | Not a bug. Measured: the monitors keep firing after a revoke. |
| Allow… for Accessibility pressed twice | Fixed. A press while macOS's alert is up is skipped and logged. |
| `~/.config` not writable | Fixed. The launch says so in the log and in Settings, runs read-only, and setup is recorded per Mac. |
| Old disk image replaces a newer install | Fixed. A newer copy in Applications is opened instead, and the image ejected. |
| A volume mounting reports every file | Fixed. Files older than the moment the folder was found missing are indexed silently. |
| Sweep deletes drawings in an unreadable folder | Not a bug. Measured: with Desktop access refused, the file is still visible to `stat`, and the drawing stays. |
| Shell lookup runs before setup | Left as is. Deferring it moves an unexplained prompt to a later page, and no prompt has been seen. |
| ⌘⇧5 set to Clipboard, Mail or Preview | Fixed. The menu, setup and the Screenshots tab say so, with Save to Folder. |
| `appleOriginal` lost with settings.json | Left as is. Apple's thumbnail is handed back at quit, so a new record reads its true value. |
| No way back after Restore | Fixed. The Screenshots tab offers Turn Off while the macOS thumbnail is on. |
| Removed login item comes back | Fixed. A removal in System Settings turns Open at login off. It reads `.notFound`, measured. |
| Dotfiles carry `setup: done` to a new Mac | Fixed. Setup's done is kept per Mac in the app's defaults. Upgraders count as done. |
| AGENTS.md says Send reaches Claude Code only through herdr | Fixed. It describes the plugin's inboxes, and herdr as the focus hint. |

The install path was walked through on the notarized image in a fresh macOS 15.7 VM: Gatekeeper's
prompt, Move to Applications, the image ejecting, setup by keyboard, Accessibility, the tap and the
hold, Done, the login item, the thumbnail handed back at quit, and no second setup. One defect came
out of it: the move alert came up inactive, so Return did nothing. macOS refuses to activate a menu
bar app before it has finished launching, so the alert is now a panel that takes the keys without
activating the app. ⌘⇧2 was checked in a fresh VM on a Release build of 939c538.

Unit tests and the e2e suite pass. New unit tests cover the recorder refusals, a folder that cannot
be written, and a folder that appears with old files.

One limit remains, accepted: a power-off or crash during setup leaves Apple's thumbnail off. The
login item is registered only when setup closes, so Vignette does not come back at login, and
captures show nothing until the person opens it again.

The VM harness lives in `.scratch/vm.py`; how it works is in Claude's memory for this project.

## Fix before 0.1.2

These can reach a first-time user or an upgrader, and each one breaks the product or hides that it
is broken.

### 1. Captures never go silent

- **Apple's thumbnail stays off after Vignette stops.** Confirmed. Quitting during setup, removing
  the app, or turning Open at login off leaves `show-thumbnail` off for good.
  - Fix: Apple's thumbnail is off only while Vignette runs. Put it back when Vignette quits, and
    let `reconcileApple` turn it off at the next launch.
  - Skip that when another instance of the same bundle id is taking over, or the replaced instance
    would turn it back on after the new one's reconcile.
  - Restore stays the way to keep Apple's thumbnail on while Vignette runs.
  - This also covers an uninstall with no uninstaller.
- **Vignette can't see the folder, and nothing outside Settings says so.** Confirmed. The folder
  can be refused in setup, refused later, or in a place macOS asks about with no explanation.
  - Fix: a first item in the menu bar menu, "Vignette can't see your screenshots", whose Allow…
    opens Privacy & Security > Files and Folders.
- **The double tap needs Accessibility, and nothing outside Settings says so.** Confirmed.
  Continue works on the shortcut page without the grant, so setup can finish with a shortcut that
  does nothing.
  - Fix: in the menu, the shortcut's badge becomes "Shortcut needs Accessibility…", which asks
    for it.

### 2. Setup tells the truth, and stays in front when it should

- **A closed setup window comes back.** Confirmed by reading. The window is kept after it closes,
  and its 0.5 s poll still runs. A later Accessibility grant or folder answer brings it back to the
  front. Its buttons then do nothing, because the model behind them is gone.
  - Fix: remove the window's content when it closes, which stops the poll, and guard `comeBack`.
- **The shortcut page reports success over an empty stack.** Confirmed. With the folder refused
  or its prompt unanswered, a tap turns the ×2 into a check and says "There they are", though
  nothing appeared.
  - Fix: while the folder is not granted, the page's status line is the folder's permission row.
- **Setup stays behind System Settings after a folder grant.** Confirmed. Setup comes back to the
  front only after its poll sees the prompt pending (`.waiting`). A grant made in System Settings
  after a refusal never passes through that state.
  - Fix: come back on any change into granted or refused once Allow… has been pressed.
  - Whether the first answer passes through `.waiting` depends on which call raises macOS's
    prompt. Measurement M1 below answered it.
- **Some protected folders get macOS's prompt at launch, before setup, with no explanation.** The
  code path is confirmed; which folders macOS protects is plausible.
  - `protectedArea` knows only the Desktop, Documents and Downloads. macOS also asks before reading
    an external or network volume, and may ask for `~/Library/CloudStorage` (Dropbox, Google Drive)
    and iCloud Drive.
  - This is the original "setup never showed" pattern, on paths the fix on main does not cover.
  - Fix: treat those as protected, named "that folder".

### 3. The agent tools work however they were installed

- **npm-installed `codex` and `claude` fail.** Confirmed: `Subprocess.run` gives tools the app's
  environment, which has no `PATH` beyond the system folders.
  - An app opened from Finder has `PATH=/usr/bin:/bin:/usr/sbin:/sbin`.
  - `npm i -g @openai/codex` installs a `#!/usr/bin/env node` script. Run with that `PATH`, it
    fails with `env: node: No such file or directory`.
  - The plugin install fails, and the Codex session list, `codex queue` and the app server all
    fail, so Send shows no Codex sessions.
  - This Mac never shows it: its `claude` and `codex` are native binaries.
  - Fix: run each tool with the login shell's `PATH` (already asked for at launch) and the tool's
    own folder in front.
- **A plugin install that fails in setup is silent and never offered again.** Confirmed. Setup
  records the offer as made, and the failure reaches only the log.
  - Fix: record the failure where the Agents tab shows it, and keep the offer open.

### 4. Upgraders keep the defaults they never chose

- Confirmed. 0.1.0 and 0.1.1 wrote every `ui` value into settings.json. The step to version 2 keeps
  them all as choices, so an upgrader stays on 0.1.1's values:

  | Setting | 0.1.1 | Now |
  |---|---|---|
  | `newTextSize` | 24 | 17 |
  | `textWeight` | 500 | 600 |
  | `textLineHeight` | 1.35 | 1.32 |
  | `slideInDuration` | 0.75 | 0.4 |
  | `annotationScreenInset` | 65 | 60 |

- Fix: when a version 1 file is read, drop each `ui` value equal to 0.1.1's default. No released
  build writes version 2 yet, so this is safe to change until 0.1.2 ships.

## Fix next

These are real but narrower, or need a measurement first.

- **The key recorder accepts ⌘Q, ⌘W, ⌘C, ⌘⇧3/4/5 and similar.** Confirmed. Recording ⌘Q
  registers it as a global hotkey, and no app quits with ⌘Q after that. Fix: refuse the reserved
  combinations with a beep.
- **A key combination that fails to register is logged as registered.** Confirmed. The default
  combination, ⌘⇧6, is macOS's Touch Bar screenshot shortcut on Touch Bar Macs. Fix: check the
  status and say "Another app uses this shortcut" under the recorder.
- **Done in setup returns the focus to System Settings.** Confirmed, and it happens on the default
  path. Fix: restore the app that was in front when setup opened.
- **The double tap can stay dead after Accessibility is revoked and granted again.** Plausible.
  Setup can also say "Try it now" up to 2 s before the tap works. Fix: re-register the shortcut
  whenever trust changes from off to on.
- **Allow… for Accessibility can be pressed twice.** Plausible. macOS queues one alert per request.
  Fix: the row is busy while a request runs.
- **If `~/.config` cannot be written, every launch is a first launch.** Confirmed. A root-owned
  `~/.config` is common on developer Macs. Setup shows at every login, and `appleOriginal` is
  recorded again after Vignette changed it. Fix: log the failure, run read-only, and say so in
  Settings.
- **An old disk image replaces a newer install.** Confirmed. Move to Applications trashes a newer
  copy that the updater installed. Fix: compare `CFBundleVersion` and open the newer copy instead.
- **A volume that mounts after launch reports every file on it as a new capture.** Confirmed. That
  means clipboard copies, thumbnails, and the editor opening if `annotateOnCapture` is on. It can
  happen at every login for someone who saves to a NAS. Fix: index a folder that appears silently,
  as a newly readable folder already is.
- **The launch sweep may delete drawings when the folder is unreadable.** Plausible. It depends on
  whether macOS refuses `stat` inside a protected folder. Deleted drawings cannot be recovered.
  Fix: sweep from the watcher's first successful listing.
- **The agent tool lookup runs the person's shell startup files at first launch.** Plausible. A
  `.zshrc` that reads `~/Documents` would raise a folder prompt in Vignette's name before setup.
  Fix: on a first launch, look the tools up when setup reaches the agents page.
- **"Save to Clipboard" in ⌘⇧5 Options means no file ever arrives.** Plausible. Nothing reads
  `com.apple.screencapture target`. Fix: detect it, and offer to save to the folder.
- **A reinstall can leave Restore unable to bring Apple's thumbnail back.** Confirmed. Examples:
  after a cleaner deleted `~/.config/vignette`, or after a deleted settings.json (already in
  TODOS). With the quit-time restore in section 1, this matters much less. Fix: keep
  `appleOriginal` in the app's own defaults too.
- **A reinstall after Restore leaves Apple's thumbnail on, with no control to turn it off.**
  Confirmed. Fix: a "Replace the macOS thumbnail" button in the Screenshots tab while it is on.
- **A login item the person removed in System Settings comes back.** Confirmed. Fix: when macOS
  reports it removed, turn Open at login off instead of registering again.
- **A settings.json synced through dotfiles carries `setup: done` to a new Mac.** Confirmed. Setup
  never shows there. Fix: keep "setup shown on this Mac" in the app's own defaults, and write the
  file through a link.
- **AGENTS.md says Send reaches Claude Code only through herdr.** The plugin's inbox made herdr
  optional. Fix the sentence.

## How it was proved

1. **Unit tests** for the pure parts: the version 1 migration table, `protectedArea` and the
   reserved combinations.
2. **End-to-end scenarios** on the test copy (`scripts/e2e/scenarios.py`):
   - `first_launch`: setup appears, Apple's thumbnail goes off, and a quit during setup puts the
     thumbnail back and leaves setup to show again.
   - `upgrade`: a 0.1.1 settings file keeps only real choices.
   - `apple_thumbnail`: the thumbnail comes back when the test copy quits. The test copy has its
     own screencapture domain, so this never touches this Mac's.
3. **Measurement M1, on this Mac, with Pete clicking.** The watcher's `open` of a Desktop folder
   blocks while macOS's prompt is up, then fails with `EPERM` on Don't Allow.
4. **A clean Mac.** A Tart macOS 15.7 VM, a fresh clone for each run, with the notarized image
   installed as a download would be.
