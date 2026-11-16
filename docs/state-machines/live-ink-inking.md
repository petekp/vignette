# Live ink: the hand: the chord and the stroke

Live ink is drawing on the live screen while a two-modifier chord is held. This area is the hand side: the chord, the inking lifecycle, strokes, the event tap that swallows clicks, overlay windows, window tracking, Esc, the focus tour, listening, and the menu hand-off. Asks, notes and responders are in "Live ink: asks and responders".

Almost none of this has an executable contract. `LiveInkTests` covers `HeldChord`, `ListeningEnd`, `SpokenNote`, `InkStroke` and static helpers, and `LiveEscapeTests` covers the pure `LiveEscape.next`. No test constructs `LiveInk`, `LiveInkTap`, `LiveWindows`, `LiveListening` or `LiveInkOverlay`.

### HeldChord (explicit)

Owner: `ModifierChord.swift:8`. Tests: `LiveInkTests.testBeginsOnExactlyControlAndOptionInEitherOrder`, `testAKeyEndsItUntilTheModifiersAreLetGo`, `testLettingGoOfTheRestOfALargerChordDoesNotBeginIt`, `testAnotherModifierJoiningInterruptsItUntilTheModifiersAreLetGo`, `testDoesNotBeginWithAnotherModifierHeld`, `testIgnoresFlagsThatAreNotModifiers`.

A pure value that turns modifier flags and key presses into `Change`s: `.began`, `.ended`, `.interrupted`. `ModifierChord` feeds it.

**States**: idle (`isHeld` false, `waitingForRelease` false), held (`isHeld`, `ModifierChord.swift:10`), waiting-for-release (`waitingForRelease`, `:11`). Waiting means the chord was broken and the pair must be fully released before it can begin again.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| idle | `flagsChanged`, flags equal the pair | held | `.began` |
| idle | `flagsChanged`, flags a strict superset of the pair | waiting | — |
| idle, waiting | `flagsChanged`, flags disjoint from the pair | idle | — |
| waiting | `flagsChanged`, anything else | waiting | — |
| held | `flagsChanged`, flags equal the pair | held | — (the monitor and the poll may both report it) |
| held | `flagsChanged`, flags a superset but not equal | waiting | `.interrupted` |
| held | `flagsChanged`, flags not a superset | idle | `.ended` |
| held | `keyDown()` | waiting | `.interrupted` |
| idle, waiting | `keyDown()` | unchanged | — |

Letting go of one modifier and pressing it again while the other stays down gives `.ended`, then `.began`.

**Invariants**

- It begins only on exactly the pair, in either order. Checked by: `testBeginsOnExactlyControlAndOptionInEitherOrder`.
- A key or another modifier ends it until the pair is released. Checked by: `testAKeyEndsItUntilTheModifiersAreLetGo`, `testAnotherModifierJoiningInterruptsItUntilTheModifiersAreLetGo`.
- Two reports of the same flags give one change. Checked by: the equal-flags return at `ModifierChord.swift:35`.

**Late and concurrent answers**

- The monitor and the 50 ms poll can both report one flag change: the second returns no change, `ModifierChord.swift:35`.

### ModifierChord (implicit)

Owner: `ModifierChord.swift:63`. Tests: none.

Owns a `HeldChord`, the modifier tap (`FlagsTap`, or the key monitors without it) and a poll that detects a key pressed during the chord. `LiveInk.makeChord` creates it and `LiveInk.takeChord()` replaces it.

**States**: `chord` (`:64`), `keyWatch: Timer?` (`:66`), `beganAt` (`:68`, set only from a tap or monitor event). The states: not held (no `keyWatch`), held (`keyWatch` running).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| not held | tap or monitor `flagsChanged` giving `.began` | held | `keyWatch` created (`apply`, `:94`), `beganAt` set |
| held | tap or monitor `flagsChanged` giving `.ended` or `.interrupted` | not held | `keyWatch` invalidated first |
| held | 50 ms `checkKeys` (`:105`) reads flags or a key | not held or held | `HeldChord.flagsChanged` or `keyDown()`; changes go to `apply` |
| not held | `checkKeys` | — | the poll does not run |

**Invariants**

- The poll timer runs exactly while the chord is held. `apply` invalidates it before every change and creates it only on `.began`. Checked by: nothing.
- The poll never produces `.began`, so `beganAt` always comes from a tap or monitor event. Checked by: nothing.

**Late and concurrent answers**

- Object teardown: `isolated deinit` invalidates the timer, `ModifierChord.swift:80`.
- The URL commands `live-ink-chord-down` and `live-ink-chord-up` (debug only, `AppDelegate.swift:713`) call `chordChanged` directly. The real `ModifierChord` never sees `.began`, so it has no `keyWatch` and nothing ends the inking ([hand-10](plausible-findings-requests-to-live-ink.md#hand-10)).

### LiveInk inking lifecycle (implicit)

Owner: `LiveInk.swift:1760` (`chordChanged`), `:1778` (`startInking`), `:1803` (`stopInking`), `:1928` (`finishInking`). Tests: none.

Decides when the screen takes ink, and what happens to the ink when the hand lets go. Driven by `ModifierChord`, the debug URL commands, and the stack and system events listed below.

**States**: the properties below form the state.

- `isInking` (`LiveInk.swift:13`): the chord is held, and the tap and overlays are up.
- `inking: [Surface]` (`:17`): the surfaces taking presses, fixed by `startInking`. A surface is one overlay window on one screen of one Space.
- `tap: LiveInkTap?` (`:27`), `pressedSurface` (`:30`).
- `fieldTimer` (`:21`), `chordShowsField` (`:23`): the pointer field and listening start together at the first stroke movement or after `ui.liveInkFieldDelay`.
- `releaseWatch: Timer?` (`:25`): non-nil means the chord was let go mid-stroke and the button is awaited.
- `inkings: Int` (`:1951`): counts inkings. `menusWaiting: (inking: Int, noteWasUp: Bool)?`: the inking whose note waits for open menus to close, and whether a note was up then.
- `chordInterrupted` (`:68`), `drewWhileInking` (`:66`).
- `strokeBegan` (`:89`), `strokeScreenDiagonal` (`:91`): scratch for the stroke in progress.
- `overMenus` (`:465`), `pinsAfterMenus` (`:468`), each overlay's `keptAboveMenus`.
- `preview`, `justPicked` (`:129`, `:132`): hover preview.

Derived states:

- Idle: `!isInking`, `releaseWatch == nil`, `inking` empty.
- Inking: `isInking`, tap up (or refused), field timer pending or `chordShowsField`.
- Stroking: Inking and some `inking` overlay `isTracking`.
- ReleasePending: `isInking && releaseWatch != nil` (chord up, button down).
- MenuWait: `!isInking && menusWaiting?.inking == inkings` (chord up, an open menu is being closed, ink kept above menus).
- Settled: `!isInking`, nothing pending. Idle and Settled differ only in history.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `.began` and `mayInk()` false | unchanged | log only; `HeldChord` stays held (`:1763`) |
| Idle, Settled, MenuWait | `.began` | Inking | `ownMenus.close()` (Vignette's own open menu, `LiveMenus.Own`), `chordInterrupted=false`, `listening?.pressedAgain()`, then `startInking`: `inkings += 1`, `FocusReturn.sessionStarting`, `drewWhileInking=false`, `releaseWatch=nil`, `inking=activeSurfaces()`, overlays `setInking(true)`, `startTap`, hover, `fieldTimer`. A pending `closeMenus` is dropped by the `inkings` mismatch. |
| Inking, Stroking | `.began` (script, or a re-begin) | same | `startInking` runs again: new `inkings`, timer restarted, tap and `pressedSurface` kept (`startTap` guard, `:1826`) |
| ReleasePending | `.began` | Stroking | `releaseWatch` invalidated (`:1783`); the stroke now ends without ending inking |
| Inking | first non-empty `strokeMoved`, or `fieldTimer` fires | Inking, field shown | `showFieldForChord`: `holdField`, `letGoOfFocus("ink")`, `InkBackdrop.refresh`, `listen()` |
| Stroking | tap `.released` | Inking | overlay `endStroke` → `strokeEnded` → `take`; `strokeBegan=nil` |
| Inking | `.ended` or `.interrupted`, no overlay tracking | Settled or MenuWait | `finishInking` |
| Stroking | `.ended` or `.interrupted` | ReleasePending | `watchRelease` |
| ReleasePending | tap `.released` | Settled or MenuWait | `strokeEnded` → `finishInking` (`:1921`) |
| ReleasePending | 50 ms poll finds `!LiveInkTap.isButtonDown` | Settled or MenuWait | `endStroke` on each inking overlay, `finishInking` (`:1987`) |
| any inking state | `spaceChanged`, `willSleep`, `sessionDidResignActive`, `screensChanged` with a changed inking frame, `takeChord()` | Settled | `cutInkingShort`: `closeNote` if by the pointer, `stopListening`, `stopInking`. Stroke dropped (`cancelStroke`), no note ([hand-6](plausible-findings-requests-to-live-ink.md#hand-6)) |
| any inking state | `standAside()` (from `ThumbnailController.onTakesScreen`) | Settled | note hidden (closed if by the pointer), `stopListening`, `stopInking`. No note for ink drawn this hold ([hand-6](plausible-findings-requests-to-live-ink.md#hand-6)) |
| any inking state | Esc (`cancelHold`), or `.interrupted` while Esc is down | Settled | `stopListening`, `stopInking("esc")`, the hold's note ink removed with the fade, a note opened in the hold closed, `FocusReturn.restore` unless the note has the keys. No note, no ask. The chord's later `.ended` is ignored |
| any inking state | `setOn(false)` | Settled | `stopInking`, everything torn down (`:206`) |
| Idle, Settled, MenuWait | `.ended` or `.interrupted` | — | ignored by `guard isInking` (`:1773`) |
| `finishInking` | no open menus | Settled | `pinOverMenus`, `settleInking(opensNote)` |
| `finishInking` | open menus and `opensNote` | MenuWait | surfaces kept at `.screenSaver`; `closeMenus` after the glance or `revealLimit` (0.8 s) |
| MenuWait | first `closeMenus` caller | Settled | `LiveMenus.close`, `pinOverMenus`, then `settleInking(opensNote:, takingKeys:)`, with `opensNote` false when a note was up and is gone, asked from or closed during the wait; stops early if `!isOn`; no note if `!mayInk()` ([hand-6](plausible-findings-requests-to-live-ink.md#hand-6)) |
| MenuWait | second `closeMenus` caller | — | ignored: `menusWaiting == nil` (`:1956`) |
| any inking state | a display is added | unchanged | `inking` was fixed at `startInking`; the tap swallows clicks on the new display ([hand-12](plausible-findings-requests-to-live-ink.md#hand-12)) |
| MenuWait | `LiveMenus.close` runs | unchanged | Accessibility reads on the main thread ([hand-13](plausible-findings-requests-to-live-ink.md#hand-13)) |

`finishInking` sets `opensNote` to `noteHangsAtPointer || heardWords` with no new ink, else `drewWhileInking || listening != nil || heardBeforeNote != nil || !chordInterrupted` (`:1930`).

**Invariants**

- The tap exists only while inking. Checked by: `stopInking` → `stopTap` (`LiveInk.swift:1814`).
- Inking never covers the stack or the annotator. Checked by: the `mayInk()` gate at `.began` (`:1762`) and `standAside()` mid-ink.
- A chord let go mid-stroke keeps the overlays raised until the button is up. Checked by: `watchRelease` (`:1982`).
- Ink no ask has been about always has its note. Checked by: nothing; cut-short inking breaks it ([hand-6](plausible-findings-requests-to-live-ink.md#hand-6)).
- No frame shows two copies of a mark handed from a surface to its window. Checked by: `LiveMarksLayer.handOff`, nothing tests it.
- A surface exists only while it has marks, is inking or holds the note. Checked by: `closeEmpty` (`:2050`).

**Late and concurrent answers**

- A press again before the button came up: `releaseWatch` invalidated, `LiveInk.swift:1783`.
- A stale menu closer from an earlier inking: dropped by `menusWaiting?.inking == inking, inkings == inking, !isInking`, `:1956`, and again in the closure, `:1960`.
- The two menu-close triggers (the glance `Task` and the 0.8 s `asyncAfter`) run one close: `menusWaiting = nil` after the first, `:1957`.
- A stroke's release after the chord was let go: `chordChanged(.ended)` checks `inking.contains(where: \.overlay.isTracking)`, `:1774`.
- `stopInking` always invalidates `releaseWatch` and `fieldTimer` and resets `chordShowsField`, `:1806`.
- A tap hand-off queued before `stopTap`: dropped by `source != nil` (`LiveInkTap.swift:194`); `pressedSurface = nil` in `stopTap` (`:1835`); `inking` is empty so `under()` finds nothing (`:1847`).
- `setOn(false)` does not clear `menusWaiting`, `fieldTimer` or `releaseWatch` unless inking was on; a pending `closeMenus` after off cancels the menus before it checks `isOn`, `:1958`.

### LiveInk stroke (implicit)

Owner: `LiveInk.swift:1864` (`strokeMoved`), `:1911` (`strokeEnded`); overlay side `LiveInkOverlay.Canvas` (`LiveInkOverlay.swift:182`). Tests: `LiveInkTests` covers `InkStroke` classification and `markToErase` only.

One press-drag-release on an inking overlay. The canvas collects points; `LiveInk` classifies the stroke (`take`, `:398`) as an ellipse, an arrow, a tap (pick, erase or miss) or nothing. A short press is a tap and erases the mark under it.

**States**: per overlay `stroke: [CGPoint]` (`LiveInkOverlay.swift:182`) and `isTracking = !stroke.isEmpty` (`:203`). In `LiveInk`: `strokeBegan`, `strokeScreenDiagonal` (`:89`, `:91`), `pressedSurface` (`:30`), `strokeTimes`, `drawingOn`. States: not tracking, tracking.

**Transitions** (`Canvas.take`, `LiveInkOverlay.swift:265`)

| State | Event | Next state | Effects |
|---|---|---|---|
| not tracking | `.moved` | not tracking | `onHover` |
| tracking | `.moved` | tracking | ignored (`guard !isTracking`); hover freezes ([hand-3](plausible-findings-requests-to-live-ink.md#hand-3)) |
| any | `.pressed` | tracking, `[point]` | restarts without ending a stroke already tracking; `onStrokeMoved` ([hand-1](plausible-findings-requests-to-live-ink.md#hand-1)) |
| not tracking | `.dragged`, `.released` | not tracking | ignored |
| tracking | `.dragged` | tracking | append, `onStrokeMoved` |
| tracking | `.released` | not tracking | `endStroke` → `onStroke(points)` → `strokeEnded` |
| tracking | `endStroke()` (from `watchRelease`) | not tracking | `onStroke(points so far)` |
| tracking | `setInking(false)` | not tracking | `cancelStroke` → `onStrokeMoved([])`, no `onStroke`; the stroke is dropped ([hand-1](plausible-findings-requests-to-live-ink.md#hand-1), [hand-6](plausible-findings-requests-to-live-ink.md#hand-6)) |

`strokeMoved` sets `strokeBegan` and `strokeScreenDiagonal` only when `strokeBegan == nil` and `points` is non-empty. Only `strokeEnded` clears them ([hand-1](plausible-findings-requests-to-live-ink.md#hand-1)). A release that the tap did not see reaches neither the app nor the canvas ([hand-2](plausible-findings-requests-to-live-ink.md#hand-2), [hand-3](plausible-findings-requests-to-live-ink.md#hand-3)).

**Invariants**

- A stroke is dropped, never taken, when inking is cut short. Checked by: `cancelStroke` (`LiveInkOverlay.swift:291`).
- `strokeTimes` records `strokeBegan ?? Date()` (`LiveInk.swift:438`). Checked by: nothing; a stale `strokeBegan` breaks it ([hand-1](plausible-findings-requests-to-live-ink.md#hand-1)).

**Late and concurrent answers**

- `tapped(.dragged)` and `tapped(.released)` guard on `pressedSurface` and `isTracking`, `LiveInk.swift:1845`.
- `strokeEnded` takes the surface weakly, `:2038`.

### LiveInkTap (implicit)

Owner: `LiveInkTap.swift:19`. Tests: none.

A CGEvent tap, created at the start of inking, that swallows mouse down, drag, up and move events and hands them to the overlays. It exists only while inking. Events arrive on a tap thread and move to the main thread through `DispatchQueue.main.async` (`:190`).

**States**: off (no object); on (port and source set); on but disabled by the system. Properties: `link.port` and `source` (nil after `stop`), `onTurnedOff`, static `taken` (`last`, `sessionAtStop`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| off | `start` (`:39`, from `LiveInk.startTap`) | on | tap installed |
| on | mouse event | on | returned nil (swallowed), including a release whose press the tap never saw; handed to main ([hand-2](plausible-findings-requests-to-live-ink.md#hand-2)) |
| on | `.tapDisabledByTimeout` | on | re-enabled on the tap thread, logged (`:179`); a lost mouse-up leaves the stroke tracking ([hand-3](plausible-findings-requests-to-live-ink.md#hand-3)) |
| on | `.tapDisabledByUserInput` | on but disabled | logged; on main `stoppedTaking()` and `onTurnedOff`, which sets `tapTakesPresses=false` on the inking overlays (`LiveInk.swift:1828`) so the overlays take presses. `LiveInk.tap` stays non-nil until `stopTap`. |
| on | `stop()` (`:92`, from `LiveInk.stopTap` or `deinit`) | off | port taken first |

**Invariants**

- Exists only while inking. Checked by: `LiveInk.stopInking` → `stopTap`.
- Process exit removes the tap. Checked by: nothing (measured, `docs/live-ink.md`).

**Late and concurrent answers**

- `stop` takes the port first, so the callback's disabled-event branch does nothing after it, `LiveInkTap.swift:177`.
- A hand-off queued behind `stop`: `handOn` guard `source != nil`, `:194`.
- `info.release()` is queued behind a running callback, `:102`.
- `link.tap` is weak.
