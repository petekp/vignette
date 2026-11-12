# The corner and the stack: the stack

This file continues [The corner and the stack: the corner](corner.md), which has the area's introduction and terms.

### Stack selection, focus and hover (implicit)

Owner: `StackModel.swift:37-38,20,23`. Tests: `StackModelTests.testSelectionNumbersCountInTheOrderTheCardsWereSelected`, `testPickingACardAgainPutsItLast`, `testSelectionChangesReportWhatJoinedInOrderAndWhatLeft`. They cover selection order only.

Which card keys act on, which card the pointer is over, and which cards are selected. `model.focused` is the one variable keys read.

**States**: `selection` (ordered ids), `focused` (`StackModel.swift:38`, the keyboard ring), `hoveredCard` (`:20`, `didSet` calls `onHover`), `holdsHover` (`:23`, hover frozen while the wheel moves the column), `pressedCard`; controller timer `wheelSettling` (`ThumbnailController.swift:52`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| keyed stack | `toggle`, `moveFocus`, Cmd+A, Esc (`handleKey`, `:1085`) | selection or `focused` change | — |
| not `holdsHover` | `CardView.onHover` (`CardView.swift:204`) | `hoveredCard` set | `onHover` closure (`:136`) sets `focused` only when `keys.isKeyed` |
| `holdsHover` | `CardView.onHover` | — | — (ignored) |
| `focused == nil` | `takeKeys(.current)` (`:276`) | `focused = hoveredCard ?? cards.first` | — |
| card exists | `takeKeys(.card(id))` | `focused = id` | — |
| any | `releaseKeys` (`:282`) | `focused = nil` | — |
| any | `present` | `focused`, `hoveredCard` (unless kept), selection, `lift`, `entranceRanks` cleared | — |
| any | `StackModel.removeCards`, which `remove(_:)`, `removeOverflow`, the stitch and the slide-out all call | `focused` moves to the newest card if its card left (**fixed**, [corner-3](findings.md#corner-3)); `remove(_:)` also filters the selection, `removeOverflow` deselects the card it drops; `hoveredCard` untouched ([corner-2](plausible-findings-run-to-toolbar.md#corner-2)) | — |
| any | wheel `scroll` → `holdHover` (`:1187`) | `holdsHover = true`; 0.15 s timer replaced on each step | — |
| `wheelSettling` fires | `hoverAfterWheel` (`:1198`) | `holdsHover = false` | if `visible`, hover = the card under the pointer now |

**Invariants**

- The focused card is where keys act, and `focused` and `hoveredCard` name a card in `cards`. For `focused`, checked by `StackModelTests.testWhenTheFocusedCardLeavesTheNewestTakesTheFocus`: `StackModel.removeCards` gives the focus to the newest card when its card leaves (**fixed**, [corner-3](findings.md#corner-3)). For `hoveredCard`, checked by nothing: no removal clears it ([corner-2](plausible-findings-run-to-toolbar.md#corner-2)).

**Late and concurrent answers**

- The wheel timer is replaced, not stacked (`:1189`). On fire it re-reads the cards and checks `visible`. A hover exit while held is repaired by the recompute (`:1204`).

### Stitch converge (implicit)

Owner: `ThumbnailController.stitched` (`:543`). Tests: none.

Flies the pieces of a stitch into one new card while the finished image fades in. The flights themselves belong to `TransitionLayer`.

**States**: `model.forming` (`StackModel.swift:19`, cards whose slot is held and drawn empty), `stitchGeneration` (`:66`), the result card at `cards[0]`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| `visible`, `isStack`, `!run.isActive`, 2+ pieces, all on screen | `stitched` | `forming` = pieces + result; pieces removed; result inserted at 0; selection cleared; `focused` cleared if a piece | `flights.converge` |
| any other | `stitched` | — | refused |
| converging | converge completion (`:567`) | `forming` minus ids and the result | `showCopied([result.shot])` if `stitchGeneration` is unchanged |
| converging | `slideOut` (`:687`) | `flights.end` makes each piece answer `dropped` | completion runs a turn later (`TransitionLayer.swift:275`); the result then comes up as a lone thumbnail through `showCopied` → `show` → `present`, which cancels the slide-out's `slidOut` ([corner-6](plausible-findings-run-to-toolbar.md#corner-6)) |

**Invariants**

- The image is never on screen twice, and a stitch never finishes in silence. Checked by: nothing on the controller side.
- `targetCards()` does not filter forming cards, so Cmd+A can select the result slot. ([corner-7](plausible-findings-run-to-toolbar.md#corner-7))
- The destination frame is computed once (`:568`); a card inserted during the converge moves the slot. ([corner-8](plausible-findings-run-to-toolbar.md#corner-8))

**Late and concurrent answers**

- Dropped pieces still finish the converge: `TransitionLayer.swift:267`.
- A stale completion skips the Copied notice by generation: `ThumbnailController.swift:572`.
- `reshape` skips forming cards: `:1276`.

### shiftUp and card entrance (implicit)

Owner: `ThumbnailController.shiftUp` (`:1430`). Tests: none.

Inserts a card into the open stack without animating the layout change; the new card slides in after the old ones are lifted back.

**States**: `model.entering` (`StackModel.swift:12`), `model.lift`, `model.offscreen`, `shift` (`ThumbnailController.swift:1417`), `model.scroll`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| visible stack | `shiftUp` | card inserted at 0, `lift` set for every old card, `scroll = 0` | synchronous |
| next turn | `first` | card removed from `offscreen` | then `withAnimation`: `lift = [:]`, `removeOverflow()`, `relayout()` |
| after `shiftUpDuration` | clear | `entering` cleared if still this card | — |

**Invariants**

- `removeOverflow`, now `StackModel.removeOverflow(over:)`, drops the oldest card that is not in `outCards` or `forming` (**fixed**, [corner-4](findings.md#corner-4)), and none once older cards were loaded (`OlderShots.columnLimit`).
- A dismissal in the same turn as `shiftUp` gets undone by `first`, which un-parks the new card. ([corner-13](plausible-findings-run-to-toolbar.md#corner-13))

**Late and concurrent answers**

- The `entering` clear compares ids (`:1451`). A second insert adds to the first's remaining lift through `liftLeft` (`:1457`). `present` recomputes lifts for kept cards.

### StackSweep (implicit)

Owner: `StackSweep.swift:7`. Tests: none.

The drag-select gesture over the selection circles, with auto-scroll while the pointer is near an edge.

**States**: `anchor: Int?` (`:17`, an index into `model.cards`), `selecting` (`:18`), `before` (`:19`), `fromTop` (`:22`), `autoScrollLink` (`:23`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `move(toYFromTop:)` from `model.onSweep` | `anchor` set; selection updated; maybe starts the link | sends `selected` |
| any | `end()` from `onSweepEnd`, `insert`, `present`, `remove`, `stitched` | `anchor`, `fromTop`, link cleared | — |
| link running | display-link tick | — | stops itself when `!isVisible()`, `!model.isStack` or speed is 0; `dt` clamped for a stalled run loop (`:109`) |

**Invariants**

- `anchor` names the card the drag started on, by id; when that card has left, the next move starts a new sweep. Checked by: `StackModelTests.testASweepWhoseFirstCardLeavesStartsAgainFromTheCardUnderThePointer` (**fixed**, [corner-9](findings.md#corner-9)). `removeOverflow` and `slideOut`'s final `removeCards` do not call `end()`, which is now safe.

**Late and concurrent answers**

- `end()` at every insert, present, remove and stitch site keeps `anchor` valid; the tick re-checks visibility.

### HotKey (implicit)

Owner: `HotKey.swift:7`. Tests: none (`HotKeySpecTests` parse key strings only).

One Carbon global hotkey with a hold timer.

**States**: `isDown` (`:19`), `holdTimer` (`:18`), `ref`, a static `keys` table.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| `isDown` | Carbon pressed (`:50`) | — | — (ignored, `:62`) |
| not `isDown` | pressed | `isDown = true` | `action()`; arm the hold timer |
| any | released | `isDown = false`; timer invalidated | — |
| armed | hold timer fires | — | `hold()` |

**Invariants**

- Only a release event clears `isDown`, so a lost release leaves the shortcut dead until the setting changes. Checked by: nothing. ([corner-12](plausible-findings-run-to-toolbar.md#corner-12))

**Late and concurrent answers**

- The key table holds entries weakly; `deinit` unregisters.

### ModifierTap and KeyMonitors (implicit)

Owner: `ModifierTap.swift:9`, `KeyMonitors.swift:8`. Tests: none.

The double-tap-a-modifier shortcut. `KeyMonitors` installs global and local event monitors once Accessibility is granted.

**States**: `ModifierTap.count` (`:18`), `last` (`:19`), `holdTimer` (`:20`), `monitors` (`:17`); `KeyMonitors.monitors` (`:9`), `retry` (`:10`, a 2 s timer).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `flagsChanged` of another modifier | `count = 0` | hold timer kept ([corner-11](plausible-findings-run-to-toolbar.md#corner-11)) |
| any | this key released | hold timer invalidated | — |
| any | this key down with `mods == flag` | `count + 1` | `action()` and arm the hold timer once `count >= taps` |
| any | any `keyDown` or click, global or local | `count = 0`; timer off | — |
| not trusted | retry timer | — | tries to install monitors; stops once granted |

**Invariants**

- A hold fires only while the one key is held alone. Checked by: nothing; another modifier does not stop the timer. ([corner-11](plausible-findings-run-to-toolbar.md#corner-11))

**Late and concurrent answers**

- A global and a local monitor both report one event; only an event newer than the last passes, `KeyMonitors.swift:33`. Callbacks hold `self` weakly.

### StackSwipe (explicit)

Owner: `StackSwipe.swift:13`, run by `StackSwipeDriver` and fed by `ThumbnailController.scroll` (`:1170`). Tests: `StackSwipeTests`.

A sideways two-finger swipe moves the column toward the edge and closes the corner (`docs/rules/stack.md`). **States**: `phase` (`:50`) is `idle`, `touching`, `deciding`, `vertical`, `horizontal(raw)`, `closing` or `leaving`, with `offset`, a spring and `carriesColumn` (`model.swipeExit`).

| State | Event | Next state | Effects |
|---|---|---|---|
| not `closing`, `leaving` | `mayBegin` | `touching`; a spring stops | — |
| not `closing`, `leaving` | `began` | `deciding`; a spring stops | — |
| `deciding` | `changed` under 3 pt | unchanged | — |
| `deciding` | `changed` | `horizontal` if sideways and swipes are on, else `vertical` | `moved` or `scrollColumn` |
| `horizontal` | `ended` toward the edge fast enough, or past the distance | `closing` | `close`: `dismiss(by: .swipe)` |
| `horizontal` | other `ended`, `cancelled` | `idle`, springing to 0 | — |
| `horizontal` | swipes turn off | `vertical`, springing to 0 | — |
| `closing` | `leave` from `slideOut` (`:706`) | `leaving`, springing past the edge | `carriesColumn` |
| `closing` | the dismissal did not happen | `idle`, springing to 0 | `cancelClose` |
| `closing`, `leaving` | `presented` from `present` (`:1343`) | `idle`, springing to 0 | `carriesColumn` until it lands |
| any | `reset` from the removal (`:719`) | `idle`, offset 0; the last axis stays | — |
| `vertical` | `ended` | `idle` | `scrollColumn` |
| not `closing`, `leaving` | momentum | unchanged | `scrollColumn` after a vertical gesture |
| not `closing`, `leaving` | no phase (a wheel) | unchanged | `scrollColumn` |
| `closing`, `leaving` | any scroll | unchanged | — |

**Invariants**

- Momentum never moves the column, and a gesture without `began` never swipes. A leaving column is never caught. Checked by: `StackSwipeTests`.

### StackAreaReader (implicit)

Owner: `StackAreaReader.swift:7`. Tests: none.

Reads where the Dock's tiles are, so the column steps around them. The read can fail while the Dock is starting.

**States**: `dockTiles` (`:15`, the last good read), `dockRetry` (`:16`), `dockReadsLeft` (`:17`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `read` (every `layoutPanel`), read fails | `dockTiles` kept | schedule one retry in 0.5 s, at most 8 per presentation |
| any | `read` succeeds | `dockTiles` updated | cancel the pending retry (`:36`) |
| any | `presented` (when `visible` becomes true) | `dockReadsLeft` reset | — |
| retry fires | not visible | — | dropped |
| retry fires | Dock answers | — | `relayout` |
| retry fires | Dock silent | — | schedule again |

**Invariants**

- At most one retry is pending (`dockRetry == nil` before scheduling). Checked by: nothing.

**Late and concurrent answers**

- The retry rechecks `isVisible` when it fires.
