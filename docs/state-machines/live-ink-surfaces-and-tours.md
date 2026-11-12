# Live ink: the hand: surfaces, tours, listening and windows

This file continues [Live ink: the hand: the chord and the stroke](live-ink-inking.md), which has the area's introduction and terms.

### Overlay surfaces (implicit)

Owner: `LiveInk.swift:2030` (`activeSurfaces`), `:2050` (`closeEmpty`); `LiveInkOverlay.swift:63`. Tests: none.

One overlay window per screen per Space holds the strokes and the field. `activeSurfaces` creates them lazily; `closeEmpty` removes those with no marks.

**States**: `surfaces`, `inking`. Per overlay: `takesInk`, `holdsField`, `keptAboveMenus`, `level` (`raise`, `LiveInkOverlay.swift:167`: `.screenSaver` if kept above menus, else the resting level), `ignoresMouseEvents = !inking`, `alphaValue` (0 while `pickerUp`), `notice`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| none for a screen and Space | `activeSurfaces` | created | overlay made |
| surface | `closeEmpty` | closed | removed from `surfaces` at once; the window closes after `fade` and the field's fade-out (`close(after:)`, `LiveInkOverlay.swift:108`) |
| surface | `screensChanged` | refitted | `fit(to:)` (`:90`) |
| surface | its display gone | closed with its marks | `LiveInk.swift:2102` |

**Invariants**

- An overlay is closed, never ordered out. Checked by: nothing.
- A surface closed by `closeEmpty` is never reused, because it leaves `surfaces` first. Checked by: `closeEmpty`.

**Late and concurrent answers**

- Inking again while a surface fades out: `activeSurfaces` looks only at `surfaces`, so a new overlay is made.
- A fading field on a surface that stays is brought back by `holdField(true)` → `comeUp`, which clears `fadeOut` (`PointerField.swift:166`).

### Window picker watch (implicit)

Owner: `LiveInk+WindowPicker.swift:14`. Tests: none.

While a capture may be starting, hides the overlays when macOS's window picker is up so the picker is not covered.

**States**: `pickerWatch: Timer?` (`LiveInk.swift:32`), `pickerWatchUntil` (`:33`), `pickerUp` (`:35`). States: idle, watching, picker up.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| idle | `watchForWindowPicker()` (from `CaptureOrigin.onCaptureKeys`), marks exist | watching | 0.1 s timer `checkWindowPicker` (`:24`) |
| watching | `isCapturing()` true | picker up | surface `alphaValue = 0`, `windows.pickerClear` |
| picker up | `isCapturing()` false | watching | alpha restored |
| watching | not up and past `pickerWatchUntil` | idle | timer stopped |
| watching, picker up | `setOn(false)` | idle | `stopWatchingForWindowPicker` |

**Invariants**

- New overlays and window overlays take their alpha from `pickerUp` and `pickerClear`. Checked by: `LiveInk.swift:2035`, `LiveWindows.swift:249`.
- Overlays at alpha 0 still take ink and the tap still swallows clicks, so a chord held while the picker is up draws invisible ink. Checked by: nothing.

### Menu hand-off: overMenus and LiveMenus (implicit)

Owner: `LiveInk.swift:449` (`place`), `:472` (`pinOverMenus`), `LiveMenus.swift:32` (`close`). Tests: none.

A mark drawn over an open menu cannot belong to the menu's window. It stays on the surface until the menu closes, then moves onto its window.

**States**: `overMenus` (`:465`), `pinsAfterMenus` (`:468`), each overlay's `keptAboveMenus`, `menusWaiting` (`:1953`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| inking | a mark is drawn over an open menu | mark on the surface | recorded in `overMenus` and `pinsAfterMenus` |
| inking ends | `stopInking(keepingInkAboveMenus: true)` | surfaces kept above menus | level `.screenSaver` |
| menus closed or none | `pinOverMenus` | marks on their windows | one turn, `handOff`; level dropped |

**Invariants**

- No frame shows two copies of a mark. Checked by: `LiveMarksLayer.handOff`, nothing tests it.
- `clear()` empties `overMenus` and the emptied surfaces close, `LiveInk.swift:287`. Checked by: nothing.

**Late and concurrent answers**

- A mark erased or cleared before `pinOverMenus`: filtered by `screenMarks`, `LiveInk.swift:477`.
- Window gone before `pinOverMenus`: the mark stays on the surface (`windows.target(id:)` is nil).
- `LiveMenus.close` makes up to about 41 Accessibility reads per window on the main thread, each with a 0.25 s timeout, `LiveMenus.swift:61` ([hand-13](plausible-findings-requests-to-live-ink.md#hand-13)).

### LiveEscape (explicit) and the Esc hotkey (implicit)

Owner: `LiveEscape.swift` (`next`), `LiveInk+Escape.swift` (`escapeSnapshot`, `holdEscape`, `cancelHold`, `keepEscapeAfterRelease`), `LiveEscapeAfterRelease.swift`. Tests: `LiveEscapeTests` (every test in it).

Esc backs out of live ink one step per press. `LiveEscape.next(Snapshot)` is pure: it returns the step to run, or nil to let the app have the key. `escapeKey: (key: HotKey, modifiers: UInt32)?` is held only while a step exists, with the chord's Carbon modifiers while the step is `cancelHold` and the chord is held, and plain Esc otherwise. `escapeAfterRelease: LiveEscapeAfterRelease?` is set when `settleInking` opens or keeps the note and a note or a stoppable ask is up, and cleared by a mouse press off the ink, another app's activation (not the app `FocusReturn` hands back to), the next `startInking`, or `holdEscape` once no note and no stoppable ask is left.

**States**: `Snapshot` (`LiveEscape.swift:29`) in, `Step?` out; and the hotkey, held or not.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| `!isOn`, or the stack holds the screen, or the note's menu is open | any | no step | Esc goes to the app |
| inking (chord held, or a stroke outliving it) | Esc with the chord's modifiers, or plain Esc after it | step `cancelHold` | inking stops; the hold's ink fades; listening stops; a note opened in the hold closes; nothing sent |
| note has keys, or note without keys and `justLetGo` | Esc | step `discardNote` | note discarded |
| note without keys, not `justLetGo` | any | no step | Esc goes to the app |
| Reply field open | Esc | step `closeReplyField` | field closed |
| the pointer is on ink or `justLetGo`, and an ask is out | Esc | step `cancelAsk`, or `discardAsk` when that ask was sent on release | ask stopped; `discardAsk` takes its new ink away and opens no note, as stopping an ask with no ink does |
| the pointer is on ink, a tour is running | Esc | step `endTour` | tour let go |
| the pointer is on ink, an answer is up | Esc | step `closeAnswer` | answer closed |
| the pointer is on ink, ink exists | Esc | step `clearInk` | ink cleared |
| the pointer is not on ink, none of the steps before the tour apply | Esc | no step | Esc goes to the app |

The order in the table is the order of `next`: when two things are open, the earlier step runs first, one per press. A `CFRunLoopObserver` re-evaluates the hotkey before every wait of the main loop (`LiveInk.swift:196`). `escape()` recomputes `next` at press time (`LiveInk+Escape.swift:35`).

**Invariants**

- Esc backs out one step per press, in the order above. Checked by: `LiveEscapeTests.testEscBacksOutOneStepAtATimeInOrder`.
- While the chord is held, the chord does not end on the Esc press before the hotkey runs `cancelHold`: `ModifierChord.checkKeys` ends the chord one poll after it reads a key, and a change of modifiers after that read ends it as `.interrupted`, not `.ended`. Checked by: nothing; it reads the HID state.
- The hotkey is held exactly while `next(snapshot)` is non-nil. Checked by: nothing; `LiveInk` is not constructible in a test.
- `pointerOnInk` reads `NSEvent.mouseLocation` (`LiveInk+Escape.swift:11`), which stays stale after inking, so the hotkey may not be held and Esc reaches the app ([hand-9](plausible-findings-requests-to-live-ink.md#hand-9)).

**Late and concurrent answers**

- Esc pressed just before the key is held: reaches `escape()` through the note's `onEscape`; `escape()` returns without a log when `next` is nil, `LiveInk+Escape.swift:35`.

### FocusRun, the focus tour (implicit)

Owner: `LiveInk.swift:1371` (`FocusRun`), `pullFocus` `:1389`, `nextFocus` `:1450`, `letGoOfFocus` `:1483`. Tests: `LiveInkTests.testATourHoldsEachStopForItsSentence` covers only `Focus.holds`.

A focus tour dims a window's other marks and shows an answer's stops one at a time. `pullFocus` is called from the answer code, which is covered in the asks area.

**States**: `focusRun: FocusRun?` (`:61`) with `id`, `ask`, `stops`, `holds`, `window`, `index` (-1 until the first stop shows), `timer`, `watch` (event monitors), `origin`. States: none; capturing (`focusRun != nil`, `index == -1`, no monitors); showing(index) (timer and monitors on).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `pullFocus` | capturing | prior tour let go (`:1398`); no window → `showUnfocused`, none |
| capturing | capture succeeds | showing(0) | stops get the picture; `nextFocus` |
| capturing | capture fails or no picture | none | `showUnfocused` |
| capturing | `focusRun.id` changed | — | ignored, `guard focusRun?.id == run.id` (`:1423`, `:1431`) |
| showing(i) | stop timer | showing(i+1) | previous stop dropped after `Focus.fade * overlap * motionScale` |
| showing(last) | stop timer | none | `letGoOfFocus("read")` |
| showing | key, click, scroll, or pointer beyond `Focus.pointerReach` (120 pt) (`focusHeard`, `:1531`) | none | `letGoOfFocus` |
| capturing | key, click, scroll, pointer | capturing | no monitors yet, so nothing |
| any | Esc `endTour`, `showFieldForChord("ink")`, `removeAnswer`, `setAside`, `endConversation` | none | `letGoOfTour` / `letGoOfFocus` |
| showing | the person draws while a tour is up | showing | not ended: the ink-time `letGoOfFocus` runs only when the field was not already shown, and the tap hides events from the monitors ([hand-4](plausible-findings-requests-to-live-ink.md#hand-4)) |

**Invariants**

- One tour at a time. Checked by: the prior tour let go at `:1398`.
- The stop on screen fades on let-go, and `windows.light` restores the other marks. Checked by: nothing.

**Late and concurrent answers**

- A capture answering after replacement or let-go: run id compare, `LiveInk.swift:1423`, `:1431`.
- The delayed `dropFocus` after the ids left: harmless, it intersects with `asks.answerMarks`, `:1513`.
- `letGoOfFocus` when none: returns at `:1484`.

### Steps tour (implicit)

Owner: `LiveInk.swift:112` (properties), `clicked(at:)` `:1340`, `stopSteps` `:1328`. Tests: none.

An answer with steps is shown one step group at a time; clicking the target of the shown step advances. Set up in the answer code (asks area).

**States**: `stepClicks` nil (none) or non-nil (running: a global `.leftMouseUp` monitor, `watchStepClicks` `:1320`); `steps` holds the groups still to show; `stepsAsk`, `stepsWindow`, `stepsOnTheirWindows`, `stepTargets`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| running | click on the shown step | running, or none after the last | `steps.removeFirst()`, `stopSteps` if empty, then after `stepPause` (0.35 s) remove the done marks and show the next group |
| running | click while inking | running | ignored, `guard !isInking` (`:1341`) |
| running | second click within `stepPause` | running | picks the same step again, pops another group, schedules a second closure ([hand-7](plausible-findings-requests-to-live-ink.md#hand-7)) |
| running | Esc `endTour` within `stepPause` | none | `stopSteps`, but the pending closure still draws the next group ([hand-7](plausible-findings-requests-to-live-ink.md#hand-7)) |

**Invariants**

- A step group that was replaced or removed during the pause does not draw. Checked by: the guard `asks.answer(of: current.id) == id` (`:1356`).

### LiveListening and the transcriber chain (implicit)

Owner: `LiveListening.swift:36`; `LiveInk+Listening.swift:6` (`listen`), `:45` (`doneListening`), `:66` (`stopListening`); `Microphone.swift:16`; `AppleTranscriber.swift:6`. Tests: `ListeningEnd` only.

Captures speech while the chord is held and a short time after, and turns it into the note's words.

**States**: in `LiveInk`: `listening: LiveListening?` (`LiveInk.swift:75`), `typedOver` (`:82`), `spoken` (`:85`), `heardBeforeNote` (`:87`), `speechProblem` (`:77`). In `LiveListening`: `finishing` (`:41`, one-way), `end: ListeningEnd` (`:39`), the 0.1 s timer. `Microphone`: engine, `running`, a shared serial queue. `AppleTranscriber`: `request`, `task`, `latest`, `final`, `waiting`, under one lock. States of a listening: none, starting or listening, finishing (delivered or cancelled).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| none | `listen()`, speech on, permission granted, recognizer present | starting | `LiveListening.start`; `typedOver` set |
| none | `listen()`, speech off | none | `speechProblem = nil` |
| none | `listen()`, no permission or no recognizer | none | `speechProblem` set |
| starting, listening | `pressedAgain()` | same | `end.pressAgain()` |
| listening | first words, chord held, no note or menu | same | `showNoteOnTheVoice`: note by the pointer, no keys |
| starting, listening | `released()` | same | `end.release(at:)`; ends 0.3 s later |
| starting, listening | start fails and `!finishing` | none | `failed` → `LiveInk.listening = nil`, `speechProblem = reason` |
| starting, listening | `finish()` (0.1 s timer says `ListeningEnd.isOver`, or `typedInNote`) | finishing | mic stop queued behind start, `transcriber.finish(timeout: 2)`, then `onFinished` |
| starting, listening | `cancel()` (from `stopListening`) | finishing, cancelled | mic stop, `transcriber.cancel()` |
| finishing | `finish()`, `cancel()` | — | ignored, `guard !finishing` (`:90`, `:107`) |
| finishing | `pressedAgain()`, `released()` | finishing | only edit `end`; no new listening starts because `listen()` returns at `guard listening == nil` (`LiveInk+Listening.swift:7`) ([hand-5](plausible-findings-requests-to-live-ink.md#hand-5)) |
| finishing | transcriber words | — | dropped, `LiveListening.swift:62` |
| finishing (finish) | `onFinished`, `LiveInk.listening === listening` | none | `doneListening`: `listening = nil`; no note → `heardBeforeNote`; note and `!typedOver` → `spoken`, `note.hear`, and `note.send()` with ink when `liveInkSendWhenQuiet` (default true), which may send while the next stroke is under way ([hand-5](plausible-findings-requests-to-live-ink.md#hand-5)) |
| finishing | `onFinished` after `stopListening` or a new listening | — | dropped by identity, `LiveInk+Listening.swift:25`, `:30` |
| starting | microphone start fails after `finish()` | finishing | the failure is dropped with no `speechProblem` ([hand-11](plausible-findings-requests-to-live-ink.md#hand-11)) |

**Invariants**

- A stop sent while a start is under way turns the mic off after it is on, and one listening's stop finishes before the next one's start. Checked by: the serial queue in `Microphone.swift:16`.
- A listening ends just after the chord is let go, and not if the chord is pressed again. Checked by: `testListeningEndsJustAfterTheChordIsLetGo`, `testPressingTheChordAgainKeepsListening`.
- `LiveListening`, `doneListening`, `heardBeforeNote` and the finishing window. Checked by: nothing.

**Late and concurrent answers**

- Mic start answering after `finish` or `cancel`: `guard !finishing`, `LiveListening.swift:67`.
- Words queued before `finishing` was set: re-checked on main, `:62`.
- `AppleTranscriber.finish` timing out after the real answer: `answer(timedOut:)` no-ops when `waiting` is nil (`AppleTranscriber.swift:117`); the continuation is taken and cleared under the lock.
- A failed `begin()` cancels the transcriber (`Microphone.swift:31`), so a later `finish` returns `latest` at once.
- Heard words with no note: `heardBeforeNote` is reset by the next `listen()` and by `stopListening`.
- Permission is read once, synchronously (`SpeechPermission.granted`, `LiveInk+Listening.swift:11`); no async permission answer reaches live ink.

### LiveWindows Tracked (implicit)

Owner: `LiveWindows.swift:11`; per window `Tracked` (`:40`); `update` `:559`. Tests: `LiveInkTests` covers only `fits` (`testAMarkPastAShrunkWindowsEdgeNoLongerFits`, `testAnArrowFitsByItsHeadNotItsTail`, `testAReplyHangingPastTheWindowStillFits`).

Pins marks to the windows they were drawn on, so marks move, fade and leave with the window. A display link drives it: 10 Hz when idle, display rate while a window is moving.

**States**: per window `frame`, `onScreen`, `showFrom`, `liftedAt`, `minimisingSince`, `pins`, `overlay`. Global: `link`, `monitors`, `observers`, `watchers` (Accessibility, per pid), `activeUntil`, `buttonDown`, `askedForTree`, `pickerClear`. Derived: `isAway = minimisingSince != nil || showFrom != nil`. A pin is drawn when `!isAway && !outside`, and shown when drawn and not aside. Window states: on screen, minimising, away (`!onScreen`, overlay ordered out), landing (`showFrom` set), lifted (`liftedAt` set, level `.floating`), gone.

**Transitions** (`update`, `:559`)

| State | Event | Next state | Effects |
|---|---|---|---|
| on screen | not on screen in the window list | away | `orderOut` |
| away | on screen again | landing | level `.normal`, order above, `minimisingSince = nil`, `showFrom = now + 0.2`, marks faded to 0 |
| landing | `now >= showFrom` | on screen | `showAgain`: fade to opacity (`:317`) |
| on screen | ⌘M or minimise-button release | minimising | `fadeForMinimise` (`:524`) |
| minimising | still on screen 1 s later | landing | `showFrom = now`, marks back |
| any | frame size changed | same | `fitMarks`, `fitOverlay`; pin `outside` toggles |
| any | frame origin changed | same | overlay `move(over:)` |
| any | its app activated | lifted | level `.floating` until its app raises its windows (`keepInPlace`, `:601`) |
| any | id missing from the window list | gone | overlay closed at once, `onGone(ids)` → `LiveInk.forget` |
| any | `pin` of a mark for a moved window before the next tick | same | uses the old `frame`, so the mark is displaced for good ([hand-8](plausible-findings-requests-to-live-ink.md#hand-8)) |
| last window gone | | link stopped | `stop()` |

**Invariants**

- Marks move with the window, fade as it minimises, go when it closes, and hide when the window shrinks past the point. Checked by: `fits` tests only; tracking itself has no test.

**Late and concurrent answers**

- `liftedAt` left set when the window goes away: heals on the next `keepInPlace` (`now - lifted > 0.5`).
- Asking for a page tree: deduped by pid, retried when it could not tell, `LiveWindows.swift:134`.
- The minimise-button Accessibility probe re-looks the window up on main, `:524`.
- A re-pin to a retired window id makes a fresh `Tracked` and overlay, `retire` `:204`, `tracked` `:344`.

### LiveInk.setOn and the chord object (implicit)

Owner: `LiveInk.swift:206`. Tests: none.

Turns live ink on and off. `isOn` is `chord != nil`.

**States**: `chord: ModifierChord?`, `observers` (screen, Space, sleep, session).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| off | `setOn(true)` | on | chord and observers made |
| on | `setOn(false)` | off | `stopInking` if inking, window picker watch stopped, `endConversation`, marks and surfaces dropped, `windows.removeAll` |
| on or off | `setOn` with the same value | — | `guard on != isOn` |
| on | `takeChord()` (`:248`) | on | the chord object replaced; inking cut short |

**Invariants**

- Off does not clear `menusWaiting`, `listing`, `lastTarget`, `typedOver`, `fieldTimer` (invalidated only by `stopInking`, which runs only while inking) or `releaseWatch`. Checked by: nothing.
