# Setup, settings and launch: setup

This area covers what runs once per launch or once per Mac: the setup window and its model, the menu bar intro that closes it, the settings file and its sync with the app, Apple's screencapture defaults, agent plugin installs, permission requests, the login item, the updater, the disk image move and the order of the launch. Most of it is implicit state in AppKit objects. `SettingsSync` is the one explicit reducer.

Paths are under `Sources/`. Test names are `Class.testName`. A launch that sets `VIGNETTE_SETTINGS` is a test launch (`Launch.isTest`).

### SetupWindowController (implicit)

Owner: `SetupWindow.swift:51`. Tests: none.

Shows the setup window once per Mac, records what the person chose when the window closes, and plays the menu bar intro on the way out. `AppDelegate` drives it; each Setup Lab run makes its own controller.

**States**: properties that together form the state.

- `window: NSWindow?` (`SetupWindow.swift:53`) and `model: SetupModel?` (`:54`). Both nil means no setup. `open` sets both (`:117`, `:132`). `windowWillClose` nils `model` at once (`:196`) and `window` one turn later (`:199`).
- `introducing: Bool` (`:187`). Set by `windowShouldClose`, never reset. Safe only because one controller shows one window.
- `quitting: Bool` (`:57`). Set by `AppDelegate.applicationWillTerminate` (`AppDelegate.swift:211`).
- `applyLoginItem` closure (`:190`), set by `AppDelegate` before `show` (`AppDelegate.swift:176`).
- Persistent: `Settings.data.setup` (`unasked` | `done`), `UserDefaults setupDoneOnThisMac` (`:73`), `launchedHereBefore` (`:75`, read when the controller is built, before the Application Support folder exists), and `setupReturnsToLiveInkPermissions`, which is `SetupModel.returnsToLiveInkSetup` (`:408`).

Whether setup is asked (`isUnasked`, `:67`, non-test launch):

| `setupDoneOnThisMac` | file `setup` | App Support folder existed | asked |
|---|---|---|---|
| true | any | any | no |
| false | done | yes | no |
| false | done | no (synced file, new Mac) | yes |
| false | unasked | any | yes |

A test launch asks only when the file says `unasked` (`:68`). Setting the file back to `unasked` does not re-ask on a Mac that has `setupDoneOnThisMac`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| no window | `show` (once per launch, only when `isUnasked`, `AppDelegate.swift:177`) or Setup Lab `run` | window and model set | `SetupModel` built, `[setup] shown`, window key, app activated |
| window up | `open` again, or `bringToFront()` (reopen, `AppDelegate.swift:206`) | same | window to front (`:102`) |
| window up | `windowShouldClose`, `quitting` or `model == nil` | closes | returns true (`:181`) |
| window up, `introducing` | `windowShouldClose` | unchanged | returns false: a second close during the intro is ignored (`:182`) |
| window up | `windowShouldClose`, menu bar icon visible | `introducing = true` | returns false; `MenuBarIntro.play` closes the window later |
| window up | `windowShouldClose`, no icon | closes | `introduceMenuBar` returned false (`:184`) |
| window up | `windowWillClose` | `model = nil`, `window = nil` next turn | `inkPlayer.stop()`, `record` |
| closed | `granted()` or `folderAnswered(_)` from `SetupModel.look` | — | log line only; `comeBack` guards `model != nil` (`:173`) |

`record(_:)` (`:206`), per close:

- `quitting`: logs `[setup] quit before it was done` and writes nothing. `setup` stays `unasked`, so the next launch asks again.
- Otherwise: `askFolder()` if the last look saw `.ask` (`:212`). One `settings.update` writes `setup = done`, `liveInkOffered = true` if live ink's page was reached, and `launchAtLogin` only if the switch moved (`:213-217`). Then `setupDoneOnThisMac = true` and `returnsToLiveInkSetup = false`. ([setup-2](plausible-findings-requests-to-live-ink.md#setup-2))
- If the agents page was reached (`sawAgents`): install the chosen agents that are not installed (`installAgentPlugin(roots)`), apply `ClaudeReadRule` if Claude's plugin is already in, and write `agentSkill = off` (`:223-231`). The install is only queued; nothing waits for it. ([setup-4](plausible-findings-requests-to-live-ink.md#setup-4)) If the page was not reached, `agentSkill` stays `unasked` and the next launch makes the offer in Settings (`AppDelegate.swift:282`).
- `applyLoginItem()` (defers while the intro plays), then `FocusReturn.restore` next turn.

What a normal close leaves, by the page the window was on:

| Closed on | `setup` | `liveInkOffered` | `agentSkill` | Plugin install |
|---|---|---|---|---|
| welcome, shortcut | done | unchanged | `unasked` | none |
| liveInk, liveInkSetup | done | true | `unasked` unless the agents page was visited | none |
| agents | done | true if visited | `off` | chosen agents not yet installed |

On a quit, none of this is written. `liveInk` was already written when Use Live Ink or Not Now was pressed (`SetupWindow.swift:80`, `SetupModel.useLiveInk`). ([setup-16](plausible-findings-requests-to-live-ink.md#setup-16))

**Invariants**

- Setup is recorded as done when the window closes, not when it opens (`SetupWindow.swift:59`). Checked by: nothing.
- A quit is not an answer (`:55`). Checked by: nothing.
- `record` runs when the window closes, 0.05 s after the intro's picture is up. Checked by: nothing.

**Late and concurrent answers**

- Second close during the intro: ignored, guard at `SetupWindow.swift:182`.
- A grant or folder answer after close: log only, guard at `:173`.
- `windowWillClose` called twice: guard at `:193`.
- The view's poll running one more turn after close: effects are logs only, because the model is still alive.

### SetupModel (implicit)

Owner: `SetupWindow.swift:240`. Tests: `SetupModelTests.testNotNowClosesLiveInkAlone`, `testNotNowInAllOfSetupGoesOnToTheAgents`, `testSetupSavesOpenAtLoginOnlyWhenItsOwnSwitchMoved`, `testAToolFoundAfterSetupOpensTurnsItsSwitchOn`, `testStartingOnLiveInkPermissionsHoldsThemAfterUseLiveInk`.

The pages of setup and the flags that decide what `record` writes. The window's buttons and a 0.5 s poll drive it.

**States**

- `page: Page` (`:269`; `Page` at `:242`): `welcome | shortcut | liveInk | liveInkSetup | agents`. `pages` is derived from `scope`, `usesLiveInk` and `agents.isEmpty` (`:363-373`). `index` is 0 when `page` is not in `pages` (`:374`).
- `usesLiveInk` (`:258`): Use Live Ink was pressed. It brings in `liveInkSetup`.
- `seen: SetupConditions` (`:247`), the last look. `agents` (`:248`), refreshed only on `callbacks.changes`. `chosen: Set<URL>` (`:276`), the agent switches.
- Flags for `record`: `sawLiveInk` (`:280`), `sawAgents` (`:277`), `launchAtLogin` against `launchAtLoginAtOpen` (`:260-264`).
- `forward` (`:273`) only sets the slide direction.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| welcome | Continue, folder `.ask` with a protected area | shortcut | `askFolder()` first (`:649`) |
| shortcut | Continue | liveInk | `sawLiveInk = true`, `responders.look()` |
| liveInk | Use Live Ink | liveInkSetup | `usesLiveInk = true`; `choseLiveInk(true)` writes `liveInk = true` now |
| liveInk | Not Now, not last page | agents | `usesLiveInk = false`; `liveInk = false` written now |
| liveInk | Not Now, last page (no agents, or scope `.liveInk`) | window closes | `done()` (`:387`) |
| liveInkSetup | Continue | agents, or close | `sawAgents = true` on reaching agents |
| agents | Done | close | `done()` |
| any | Back | previous page | — |
| agents | last agent gone | last remaining page | `show(last, forward: false)` (`:328`) |

A page change is deferred one turn (`show`, `:401`). `sawAgents` is set in that deferred block (`:403`) or in `init` (`:295`).

**Invariants**

- Not Now on the last page closes the window. Checked by: `SetupModelTests.testNotNowClosesLiveInkAlone`, `testNotNowInAllOfSetupGoesOnToTheAgents`.
- `launchAtLoginChoice` is nil unless setup's own switch moved. Checked by: `SetupModelTests.testSetupSavesOpenAtLoginOnlyWhenItsOwnSwitchMoved`.
- A tool found after open turns its switch on. Checked by: `SetupModelTests.testAToolFoundAfterSetupOpensTurnsItsSwitchOn`.
- Starting on `.liveInkSetup` keeps that page. Checked by: `SetupModelTests.testStartingOnLiveInkPermissionsHoldsThemAfterUseLiveInk`.
- `look` agrees with what `record` writes. Checked by: nothing.

**Late and concurrent answers**

- `granted()` fires only on the edge `seen.trusted && !before.trusted`, guard at `SetupWindow.swift:330`.
- The folder answer fires only from a prior state that was not `.ask`, guard at `:335`, so an already-allowed folder does not pull the window forward.
- A double Continue before the deferred page change is idempotent: both target the same page.

### SetupBanter (explicit)

Owner: `SetupBanter.swift:8`. Tests: none.

A value type that picks the line the shortcut page's picture says as the person holds the key. The `.hotKeyHeld` notification, the editor closing, and a shortcut or page change drive it.

**States**: `counted: Place` and `shown: Place` (`step`, `holds`, `proven`; `:60-72`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| first hold | `hold(rowReady:)` (`:118-123`) | `counted.step = 0` | — |
| later holds | `hold(rowReady:)` | moves on only while `rowReady && line != nil` (`:75-86`) | — |
| any | `reveal()` (editor closed, or one turn after a hold with no editor open, `:121-126`) | `shown` = `counted` | at the bye line, a 1.2 s timer calls `moveOn` if `saysBye` and `rowReady()` still hold (`:138-140`) |
| any | `leftPage()` (`:127`) | "Bye." turns back into the greeting | — |
| any | `shortcutChanged()` (`SetupWindow.swift:455`) | reset | — |

**Invariants**

- None stated. Checked by: nothing.

**Late and concurrent answers**

- The dwell timer re-checks `saysBye && rowReady()` when it fires, guard at `SetupBanter.swift:139`. Leaving the page inside 1.2 s moves nothing.

### SetupInkPlayer and SetupInkGuide (implicit)

Owner: `SetupInk.swift:12` (demo), `SetupInkGuide.swift:9` (pointer). Tests: `SetupInkDemoTests.testTheSessionsTurnEndsOnlyAfterTheKeysHaveGrown`, `testTheHandFinishesEachStrokeBeforeTheNextBegins`, `testTheNoteIsSentWithAllItsWords`, `testAHandSlowsWhereTheLineTurns` (the demo's beat order only).

The live ink page's scripted demo and the pointer that retires marks. The setup view drives both.

**States**

- `SetupInkPlayer`: `played`, `next` (index into `SetupInkDemo.steps`), `writing`, `loopPen`, `loop`, `note`, `wait: NoteCardWait`, `stage.isRunning`. It plays once per window; a second `play()` calls `rest()`. `stop()` (from `windowWillClose` at `SetupWindow.swift:194`, and when the page is left) clears everything and sets `next = steps.count`.
- `SetupInkGuide`: `pointing`, `aimedAt`, `agent`, `shown`, `leaving`. `point(at:)` retires old marks with a timer (`:109`) that removes only the ids it captured. `leave()` clears all.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| not played | `play()` | playing | steps run in order |
| played | `play()` | — | `rest()` |
| playing | `stop()` | `next = steps.count` | all state cleared |

**Invariants**

- Each demo step finishes before the next begins. Checked by: `SetupInkDemoTests.testTheHandFinishesEachStrokeBeforeTheNextBegins`.

**Late and concurrent answers**

- Three deferred closures are each guarded: `openNote`'s `reveal` by `self?.note === note` (`SetupInk.swift:241`); `done()`'s line-two restore by `self.note == nil` (`:267`); `done()`'s cleanup by `self.loop?.mark.id == loop.mark.id` (`:264`), which `stop()` defeats by nil-ing `loop`.

### MenuBarIntro (implicit)

Owner: `MenuBarIntro.swift:10`. Tests: none.

Plays the picture of the setup window flying into the menu bar icon, then shows a popover. Setup's `windowShouldClose` and the Intro Lab and Setup Lab (debug windows) call it.

**States**

- `finished: (() -> Void)?` (`:32`) is the playing flag (`isPlaying`, `:34`).
- `flight: NSPanel?` (`:27`), `popover: NSPopover?`, `monitors`, `timeout: Timer?`, `shortcutFired` (`:28-31`), and `FunnelClock.begin`.

There is no enum. The phases are idle (`finished == nil`), capturing (up to 0.25 s), flying (the window closes 0.05 s after the panel is up), arrived (panel out, popover 0.12 times the motion scale later) and popover up (5 s).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| idle | `play`, duration 0 (`AppDelegate.introduceMenuBar`, `AppDelegate.swift:907`) | popover | next turn: `close()`, `showPopover` (`:59`) |
| idle | `play`, picture nil or no icon window | popover | `close()`, `showPopover` (`:67`) |
| idle | `play`, picture ok | flying | panel up, `window.hasShadow = false` at +0.02 s, `close()` at +0.05 s |
| flying | arrival | popover | panel out, popover at +0.12 times the motion scale |
| popover | timeout, click on the icon, or `.hotKeyFired` | idle | `dismiss`: `closePopover`, then `finished()` |
| capturing, flying or popover | `play` again | restarts | `dismiss()` runs the first intro's `finished` (`:55`); the first intro's deferred closures still run against the second ([setup-7](plausible-findings-requests-to-live-ink.md#setup-7)) |
| flying | icon hidden by `settingsChanged` | unchanged | the popover still shows on the kept `button` (`:511`) ([setup-11](plausible-findings-requests-to-live-ink.md#setup-11)) |

While an intro plays, `AppDelegate.applyLoginItem` (`AppDelegate.swift:269`) sets `loginItemAfterIntro`. The intro's `finished` clears it and calls `applyLoginItem()` again (`:918-922`). A quit before then drops nothing: every later launch applies the setting.

**Invariants**

- `finished != nil` from `play` until the popover is gone (`MenuBarIntro.swift:33`). Checked by: nothing.

**Late and concurrent answers**

- A second `play` while one is up calls `dismiss()` and orders out the old panel, guard at `MenuBarIntro.swift:55-58`. The first intro's closures at `:65`, `:122`, `:130-145` are not cancelled. ([setup-7](plausible-findings-requests-to-live-ink.md#setup-7))
- The capture races its 250 ms limit through `Gate`, guard at `:679`.
- The popover timer, monitors and shortcut observer are removed together in `closePopover` (`:157`).
- `canSee` is checked once, when setup closes (`AppDelegate.swift:908`). ([setup-11](plausible-findings-requests-to-live-ink.md#setup-11))

### Accessibility.request (implicit)

Owner: `SettingsWindow.swift:857` (in `enum Accessibility`, `:838`). Tests: none.

Raises macOS's Accessibility alert from a button press and brings the asking window back. Callers are setup rows (`SetupWindow.swift:530`, and `callbacks.askAccessibility` in `SetupInk.swift`), Settings rows (`SettingsWindow.swift:272`, `:305`) and the status menu (`AppDelegate.swift:1086`).

**States**: no stored state. The machine is the alert's presence (`alertOwnerPID`, `:909`: a window of `universalAccessAuthWarn`) plus the `Task` started per call.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| alert up | `request` | unchanged | `bringForward(alert)`, no new Task (`:858`) |
| no alert yet | `request` | Task started | `trusted(prompt: true)`; waits up to 1.5 s for the alert; if it came, waits until it is gone; else opens the pane |
| alert already up but not yet seen | `request` | second Task | a second prompt and Task start ([setup-5](plausible-findings-requests-to-live-ink.md#setup-5)) |
| already trusted | `request` | Task started | no alert appears, the wait times out, and System Settings opens ([setup-6](plausible-findings-requests-to-live-ink.md#setup-6)) |
| Task, after alert or pane | System Settings in front | waits | polls every 250 ms for trust or System Settings quitting |
| Task end | not trusted and `asking` visible | — | `makeKeyAndOrderFront` on the asking window |

A grant is left to each window's own poll: `SetupModel.look` 0.5 s, `SettingsView` 1 s, `KeyMonitors` 2 s.

**Invariants**

- One alert at a time. Checked by: the guard at `SettingsWindow.swift:858`, which only sees an alert already on screen ([setup-5](plausible-findings-requests-to-live-ink.md#setup-5)).
- No pane opens for a permission already granted. Checked by: nothing (`ScreenRecording.request` has this guard at `ScreenRecording.swift:12`; this one does not) ([setup-6](plausible-findings-requests-to-live-ink.md#setup-6)).

**Late and concurrent answers**

- A press during the alert: handled by the early return at `:858`.
- The asking window closed during the wait: guard on `asking.isVisible`.
- A grant landing mid-loop: `ModifierTap.trusted` is re-checked on each pass.

### ShortcutRecorderView (implicit)

Owner: `SettingsWindow.swift:644`. Tests: none.

The control that records a key combination for the shortcut. Mouse, key and window events drive it.

**States**: `recording`, `refused`, the `outsideClick` monitor, `recordOnWindow`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| idle | mouseDown, or `viewDidMoveToWindow` with `recordOnWindow` | recording | `begin`: monitor installed |
| recording | key equivalent or keyDown | idle, or refused | `stop()` on accept; a refused combination keeps the refusal text |
| recording | resign or outside click | idle | `stop()`: clears `refused` and its text, removes the monitor |
| any | `deinit` | — | monitor removed |

**Invariants**

- The monitor is present exactly while `recording`; `begin` and `stop` set and clear them together. Checked by: nothing.

**Late and concurrent answers**

- None found.
