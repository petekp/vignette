# Setup, settings and launch: settings, plugins and launch

This file continues [Setup, settings and launch: setup](setup.md), which has the area's introduction and terms.

### SettingsSync (explicit) and Settings (shell)

Owner: `SettingsSync.swift:5` (reducer), `Settings.swift:514` (timers, watchers, `data`). Tests: `SettingsSyncRandomTests.testRandomSequencesKeepTheInvariants`; in `SettingsSyncTests`, `testAnUpdateMadeDuringAWritesTakeInIsInThatWrite`, `testWriteComesAfterTheDelayAndItsOwnEchoAppliesNothing`, `testAFileThatDoesNotParseKeepsTheSettingsAndTheNextWriteReplacesIt`, `testNothingIsWrittenWhileReadOnlyButFileEditsStillArrive`, `testAFileFromANewerVersionMakesTheAppReadOnlyMidRun`, `testAFlushTakesInAPendingFileEditBeforeItWrites`, `testAFolderThatCannotBeWrittenKeepsTheWriteFailedUntilAWriteGoesThrough`.

Keeps `settings.json` and the app's settings in step. The reducer decides; `Settings` runs the timers, the file watchers and the disk reads.

**States**

- Reducer: `syncedBytes` and `syncedData` (what the file and app last agreed on), `writing` (a write awaiting `wrote`), `changedSinceFlush`, `readOnly` (never cleared), `lastWriteFailed` (from a failed `wrote` until a later one succeeds; `Settings` publishes it for the General tab's warning).
- Shell: `writeWork` and `reloadWork` (`DispatchWorkItem`s), `directorySource`, `fileSource`, `hold: EventHold`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `appChanged` (from `update`, `restoreAppleDefaults`, `followAppleLocation`) | `changedSinceFlush = true` | `scheduleWrite(0.3)` |
| any | `fileChanged` (directory or file watcher) | — | `scheduleReload(0.15)` |
| any | `reloadDue(file, app)` | — | `takeIn` |
| any | `writeDue(file, app)` | — | `takeIn`, then `writeAppData`; the `appData` answer writes |
| any | `flush(file, app)` | — | `takeIn`, then `writeAppData` |
| `!changedSinceFlush` | `quit` | — | — |
| `changedSinceFlush` | `quit` | — | `cancelWrite`, `readFileAndFlush` |
| not read-only | `appData(d)` | `writing` set | `write(raw)`, answered by `wrote` |
| `writing` | `wrote(raw, failure)` | `lastWriteFailed = failure != nil`; when it succeeded, `syncedBytes` and `syncedData` set | a failure logs `error write-failed` |
| read-only | `appData(d)` | — | refused: no write |

`takeIn`:

- No-op when the file read failed or equals `syncedBytes`.
- `.invalid` logs and keeps the app's settings.
- `.loaded` validates, three-way merges when `syncedData != app` (the file wins a double change and logs it), emits `apply(next, "file")`, and stamps a pre-version file.

Effects: `log`, `apply`, `write`, `writeAppData`, `readFileAndFlush`, `scheduleWrite`, `cancelWrite`, `scheduleReload`.

Bootstrap (`Settings.bootstrap`, `SettingsFile.swift`): `loaded` (a failed fill-in write sets `lastWriteFailed`); `missing` (create it, or read-only); `invalid` (move aside, use defaults, or read-only; a failed write of defaults sets `lastWriteFailed`). A newer file is read-only. Tests: `SettingsTests.testAFailedFillInWriteIsLoggedAndMarksTheWriteFailed`, `testAFileThatCannotBeCreatedIsReadOnlyWithANotice`.

**Invariants**

- Nothing is written while read-only; no value is clamped silently; a conflict is logged for exactly the keys both sides changed; every edit survives or loses to a logged file conflict. Checked by: `SettingsSyncRandomTests.testRandomSequencesKeepTheInvariants`.
- A failed `write` is logged and a later reload keeps the app's change. Checked by: `testAFailedWriteIsLoggedAndALaterReloadKeepsTheAppsChange`.
- The directory watch survives the folder being replaced. Checked by: nothing; `directorySource` is made once with mask `.write` (`Settings.swift:975-982`) ([setup-15](plausible-findings-requests-to-live-ink.md#setup-15)).

**Late and concurrent answers**

- Reload and write read the file when the timer fires, not when it is set: `sendReadingFile`, `Settings.swift:941`.
- A write first takes in a pending hand edit (the `writeDue` case). Checked by: `testAFlushTakesInAPendingFileEditBeforeItWrites`.
- `onChange` calling `update` during `apply` is held by `EventHold`, and the write uses the data afterwards: `Settings.swift:931`. Checked by: `testAnUpdateMadeDuringAWritesTakeInIsInThatWrite`.
- The app's own write echoing back as `fileChanged` is a no-op because the bytes are equal. Checked by: `testWriteComesAfterTheDelayAndItsOwnEchoAppliesNothing`.
- A half-written file logs `settings-invalid` and keeps the settings. Checked by: `testAFileThatDoesNotParseKeepsTheSettingsAndTheNextWriteReplacesIt`.
- An atomic write replaces the inode, so `watchFile()` re-arms: `Settings.swift:951`.

### Apple screencapture reconcile (implicit)

Owner: `Settings.swift:822-870` (`handBackAppleThumbnail`, `reconcileApple`, `followAppleLocation`, `pushToApple`), `AppleScreencapture.Observer` (`:1044`). Tests: none.

Keeps Apple's `com.apple.screencapture` defaults the way Vignette needs them: its floating thumbnail off while Vignette runs, its save location followed.

**States**: `data.appleThumbnail`, `data.screenshotsFolder`, `data.appleOriginal`; Apple's `show-thumbnail`, `location` and `target`; the published `appleTarget`; observers `appleLocation` and `appleTargetObserver`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| launch | `reconcileApple()` (`AppDelegate.swift:164`, before the watcher) | — | `show-thumbnail` forced to `data.appleThumbnail`; `followAppleLocation()` once; observers installed for `location` and `target` |
| running | Apple's `location` changes (KVO, async to main) | `screenshotsFolder` follows | `followAppleLocation` re-reads Apple's value; no-op when it equals `data.screenshotsFolder` (`samePath`) |
| running | Apple's `show-thumbnail` turned on | unchanged | no observer, so it stays on until the next launch ([setup-9](plausible-findings-requests-to-live-ink.md#setup-9)) |
| running | a Vignette setting changes (`apply` with `pushApple`) | — | `pushToApple` writes only changed keys (`:864`) |
| quit | `handBackAppleThumbnail()` (`AppDelegate.swift:215`) | — | `show-thumbnail = true` only when Vignette had it off, Apple showed it before, and no other instance of this bundle id runs |

**Invariants**

- Apple's thumbnail is off while Vignette runs. Checked by: only at launch (`Settings.swift:827-830`) ([setup-9](plausible-findings-requests-to-live-ink.md#setup-9)).
- Vignette's own write to `location` coming back is ignored. Checked by: `samePath` in `followAppleLocation`.

**Late and concurrent answers**

- Two quick `location` writes both resolve against the latest value, because `followAppleLocation` re-reads Apple's current value.
- Hand-back is skipped when a newer instance exists, guard at `AppDelegate.swift:214`. The newer launch turns the thumbnail off again.
- A force quit (3 s after `replaceOlderInstances`, `AppDelegate.swift:235`) skips `willTerminate`, so the setting stays off, which the next launch expects.
- Between a Sparkle quit and the relaunch, no second instance exists, so hand-back turns Apple's thumbnail on until the new launch reconciles. A capture in that gap is held by Apple for about 5.6 s. This is by design.

### AgentPlugins (implicit)

Owner: `AgentPlugins.swift:9` (class), `AppDelegate.swift:276-350` (callers). Tests: `AgentPluginTests`, `AgentPluginLaunchTests.swift`.

Installs, updates and removes the Vignette plugin in Claude Code and Codex, one run at a time on a serial `DispatchQueue("vignette.agent-plugin")`.

**States**: per root, the truth is on disk (Claude's `settings.json` `enabledPlugins`; Codex's `config.toml`), read by `AgentPlugin.isInstalled`. UI state: `SettingsView.agentWorking[root]` (disables the switch while a run is out, `SettingsWindow.swift:418`), `agentFailures`, `agentsJustInstalled`, and `AppDelegate.pluginFailures` (`AppDelegate.swift:27`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| plugin not on, legacy skill folder present | `launch` (`startAgentPlugin`, `AppDelegate.swift:283`, once setup is asked) | on | installs the plugin; the folder is recorded in `LegacySkillMigrations`, then removed |
| plugin not on, legacy skill is a link, folder not recorded | `launch` | on | installs the plugin and records the folder; the link stays ([setup-1](findings.md#setup-1), [issue 12](issues.md#issue-12)) |
| plugin not on, legacy skill is a link, folder recorded | `launch` | — | — (the switch's off holds) |
| plugin on, legacy skill present | `launch`, or `install(into:)` succeeding | on | records the folder (`retireLegacySkill`) |
| plugin not on, no legacy skill | `launch` | — | — |
| plugin on, marketplace changed or version differs | `launch` | on | `plugin update` |
| any | `install(into:)` (Settings switch, setup `record`, `install-skill`) | on | stage the marketplace, run the tool's install steps, remove the legacy folder |
| any | `remove(from:)` (Settings switch) | off | the tool's uninstall steps; "not found" counts as done |
| test launch, the person's own folder or home (`Launch.isOnPersonsHome`) | `install(into:)`, `remove(from:)`, or `launch` | — | no tool runs: `.failed` (`refusal`); `launch` only stages |

**Invariants**

- A launch never removes the plugin, and installs only where the skill from before the plugin is. Checked by: `testLaunchInstallsNothingWhereNothingWas`, `testLaunchMigratesTheOldSkillAndUpdatesOlderPlugins`. A link counts as that skill.
- A test launch never reads or changes the person's `.claude`, `.codex` or `.agents`, and the `.agents` skill goes only with the Codex folder the environment names. Checked by: `testATestLaunch…` and `testAnInstall…`.
- A test launch stages its marketplace and lists inboxes only under its own data folder (`Launch.dataHome`), never the person's own app's Application Support, whatever its bundle id. Checked by: `IdentityTests.testATestLaunch…`.
- A launch installs for the old skill at most once per agent folder, so the switch's off holds. Checked by: `testALaunchLeavesThePluginOffAfterTheSwitchTurnedItOffWhereTheOldSkillIsALink`, `testALaunchThatFindsThePluginBesideALinkedSkillLeavesItOffOnceTheSwitchTurnsItOff` ([setup-1](findings.md#setup-1)).
- An install started by setup finishes before the app quits. Checked by: nothing; `applicationWillTerminate` (`AppDelegate.swift:210`) waits for `requests.releaseHeld()` and not for this queue ([setup-4](plausible-findings-requests-to-live-ink.md#setup-4)).
- `ClaudeReadRule.set` does not lose a concurrent write to Claude's `settings.json`. Checked by: nothing; it reads and rewrites without a lock.

**Late and concurrent answers**

- A launch update against a switch: both go to the one queue, so they are ordered, and `launch` decides from disk at its own turn.
- Two installs queued: each is idempotent in effect and runs twice.
- The Settings window closed mid-run: its `@State` is discarded and the next open reads the disk again.
- Setup's install failing opens the Agents tab (`installAgentPluginFromSetup`).

### AgentTools (implicit)

Owner: `AgentTools.swift:8`. Tests: `AgentPluginTests.testAToolIsFoundUnderTheNewestNodeAndInTheShellsAnswer`.

Finds the `claude`, `codex` and `herdr` programs. `start()` runs once per launch.

**States**: `started`, `fromShell`, `shellPath`, `shellDone` (a baton semaphore).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| not started | `start()` | started | the login shell runs off the main thread with an 8 s timeout (`:92`) |
| started | `path(...)` on the main thread | — | answers at once from what is known |
| started | `path(...)` off the main thread | — | waits up to 8 s for `shellDone`, then re-signals it (`:36-37`) |
| shell finds a tool | answer | — | `found` posted on main |

**Invariants**

- A tool the login shell finds late is not reported missing. Checked by: nothing; a timeout signals the baton with `fromShell` empty, so a waiter returns nothing and `PluginHost.steps` returns `.noTool` (`AgentPlugin.swift:329`) ([setup-12](plausible-findings-requests-to-live-ink.md#setup-12)).

**Late and concurrent answers**

- A timeout signals the baton early, so later waiters return at once with nothing: `AgentTools.swift:36-37`.

### LoginItem (implicit)

Owner: `LoginItem.swift:7`. Tests: none.

Registers Vignette as a login item. The state is `SMAppService.mainApp.status` plus `loginItemRegisteredPath` in `Identity.defaults`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| macOS agrees with the setting | `apply(enabled)` | — | skipped |
| macOS disagrees | `apply(enabled)` | registered or not | logs errors; a test launch changes nothing |
| `.notRegistered` or `.notFound` and the registered path is this copy | launch (`AppDelegate.swift:183`) | `launchAtLogin` off | `removedByPerson` |
| setup unasked | launch | — | the item is left alone; setup's `record` calls `applyLoginItem()` |

**Invariants**

- A login item the person removed is not registered again. Checked by: `removedByPerson`, applied at `AppDelegate.swift:183`.

**Late and concurrent answers**

- Registration waits for the menu bar intro: `loginItemAfterIntro` (see [MenuBarIntro](setup.md#menubarintro-implicit)).

### Updater and the update dot (implicit)

Owner: `Updater.swift:11` (`waiting`, `:12`), `AppDelegate.swift:1102-1170` (`updateDot`). Tests: none.

Shows a dot on the status item when Sparkle finds an update on a scheduled check.

**States**: `waiting` and `statusItem`, read together each time `showUpdateDot` runs.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `standardUserDriverWillHandleShowingUpdate`, scheduled and not user-initiated, Sparkle not showing it itself | `waiting` set | `showUpdateDot` |
| waiting | `...DidReceiveUserAttention` or `...WillFinishUpdateSession` | `waiting` cleared | dot removed |
| waiting, no status item | `showUpdateDot` | — | `updateDot = nil` (`AppDelegate.swift:1121`) |
| any, test launch | startup | — | no updater unless `VIGNETTE_FEED` is set (`:1103`) |

**Invariants**

- An update that waits always has somewhere to show. Checked by: nothing. Hiding the icon leaves `waiting` set until Sparkle's next scheduled check, which then shows its own window because `hasStatusItem` is false.

**Late and concurrent answers**

- None found.

### AppLocation (explicit, linear)

Owner: `AppLocation.swift:9`. Tests: none.

Runs from `main` before settings exist, when the app starts from a disk image.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| not on a disk image and not translocated | launch | — | returns |
| an installed copy has a newer `CFBundleVersion` | launch | exits | opens the installed copy, ejects the image |
| otherwise | launch | alert | offer to move |
| alert | Quit | exits | — |
| alert | Move | exits | copy to a staging folder, clear quarantine, trash an older copy (`:145`), move into place (`:146`), reopen as a new instance (waits up to 10 s) |
| Move | the final move throws | exits with code 1 | failure alert; the older copy is already in the Trash ([setup-13](plausible-findings-requests-to-live-ink.md#setup-13)) |
| moved copy running | launch | — | ejects the image, 10 retries 0.5 s apart (`:149`) |

**Invariants**

- The installed app survives a failed move. Checked by: nothing; the older copy is trashed before the move (`AppLocation.swift:145-146`) ([setup-13](plausible-findings-requests-to-live-ink.md#setup-13)).

**Late and concurrent answers**

- None found.

### Launch sequence (implicit, ordered)

Owner: `AppDelegate.swift:84-199`. Tests: none.

The order of `applicationDidFinishLaunching`. Order that matters:

1. `replaceOlderInstances` first; its result goes to `startRequests(clearingUnsent: !replacing)`.
2. `AppLocation.ejectDiskImageIfAsked`, `AgentTools.start`, `updateStatusItem`, `startUpdater`.
3. `reconcileApple`, before the watcher.
4. `Leftovers`, `startDrawings`, `startRequests`.
5. `watcherWaitsForSetup`, decided from `isUnasked` (`:131`); `startWatching` unless waiting.
6. `registerHotKey`, `liveInk.setOn`.
7. `settings.onChange` is assigned (`:140`), so changes made earlier, including `followAppleLocation` at launch, never reach `settingsChanged`.
8. Either `setupWindow.show`, or the login item plus `startAgentPlugin` and `offerLiveInk` (`:194`).
9. `sessions.refreshKeptLists`, then `[app] ready` last (`:198`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| `watcherWaitsForSetup` | first launch, protected folder | — | no watcher until setup's Allow…, Continue or close; `askForFolder` (`:1463`) is the only place that clears it |
| `watcherWaitsForSetup` false | `settingsChanged` with a folder in the Desktop, Documents or Downloads | watcher started | macOS's prompt appears with no row in setup to explain it (`:247-249`) ([setup-14](plausible-findings-requests-to-live-ink.md#setup-14)) |
| before `[app] ready` | `application(_:open:)` (`:674`) | command runs | no ready gate ([setup-10](plausible-findings-requests-to-live-ink.md#setup-10)) |

**Invariants**

- After `[app] ready`, every command answers. Checked by: nothing; commands arriving earlier are not held ([setup-10](plausible-findings-requests-to-live-ink.md#setup-10)).
- A first launch with a protected folder starts no watcher until setup asks. Checked by: `watcherWaitsForSetup`, cleared only in `askForFolder` (`AppDelegate.swift:1463`); a later folder change bypasses it ([setup-14](plausible-findings-requests-to-live-ink.md#setup-14)).

**Late and concurrent answers**

- A URL delivered before `applicationDidFinishLaunching` runs on unwired controllers: `thumbnail.actions`, the callbacks, `startDrawings`, `startRequests` and `settings.onChange` are all set inside it ([setup-10](plausible-findings-requests-to-live-ink.md#setup-10); unverified whether macOS delivers it first).

### Hotkey press and hold pair (implicit)

Owner: `AppDelegate.swift:375`. Tests: none.

`fire` records `pressDismissed` and `holdTarget` on each press (`:385-386`); `hold` reads them. `ModifierTap` and `HotKey` guarantee that a hold follows its own `fire`. A hold whose `holdTarget` was trashed since goes to `annotate([shot])`, which `thumbnail.annotate` is expected to refuse. That refusal belongs to the run area and was not traced here.

### Stitch action (implicit)

Owner: `AppDelegate.swift:450-478`. Tests: none.

A stitch request composes off the main thread, then `finishStitch` runs on main: it names the file from the clock to the second, writes it, fills the clipboard, and calls `thumbnail.stitched` or `showCopied`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| composing | pieces gone | — | `ThumbnailController.stitched` returns false (`ThumbnailController.swift:546`); `showCopied` is used |
| composing | two stitches finish in the same second | one file | the second write overwrites the first, with no name check (`AppDelegate.swift:468`, `FolderWrites.swift:157-159`) ([setup-8](plausible-findings-requests-to-live-ink.md#setup-8)) |

**Invariants**

- Each stitch gets its own file. Checked by: nothing (`writeCard` asks `Commands.destination` for a free name at `FolderWrites.swift:169`; stitch does not) ([setup-8](plausible-findings-requests-to-live-ink.md#setup-8)).

### Setup Lab and Intro Lab (debug)

Owner: `SetupLab.swift:18`, `IntroLab.swift`. Tests: none.

Debug windows that run setup and the intro without recording anything. A Setup Lab `Run` holds one controller each, with `closing`, `current` and `replaced`. Its `answerLater` guard compares the override with the value it was asked from (`SetupLab.swift:278`). The Intro Lab uses a stand-in window with 0.4 s and 0.6 s delays. Both share the app's single `MenuBarIntro`, so they can meet its second-play case ([setup-7](plausible-findings-requests-to-live-ink.md#setup-7)).
