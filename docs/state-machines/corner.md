# The corner and the stack: the corner

The corner is the screen edge where Vignette shows screenshot cards: a few lone thumbnails, or the stack, a column of recent cards that takes the keyboard. `CornerPresentation` decides which one is showing and who holds the keys. `CornerKeys` and `ThumbnailController` run what it decides.

### CornerPresentation (explicit)

Owner: `CornerPresentation.swift`, held by `CornerKeys.presentation` (`CornerKeys.swift`). Tests: `CornerPresentationTests.testLoneThumbnailsNeverTakeTheKeys`, `testTheShortcutTakesTheKeysBeforeItListsThenOpensTheRecentStack`, `testTheShortcutWithNothingToShowLetsTheKeysGo`, `testTheShortcutClosesTheRecentStack`, `testSelectingInTheCornerMakesItAKeyedStackOfItsOwnCards`, `testEscFromTheCornersEditorMakesTheCornerAKeyedStackOfItsOwnCards`, `testTheFocusGoesBackOnceTheColumnHasSlidOut`, `testRandomSequencesKeepTheKeysWithTheStack`, and the others in that file.

A pure reducer. It decides whether the corner shows lone thumbnails or the stack, when the panel takes and gives up the keys, and when focus goes back to the app the person was in. The controller sends it events through `CornerKeys.send`; it returns effects.

**States**: `mode` (`CornerPresentation.swift`) is `.hidden`, `.thumbnails` or `.stack(recent: Bool)`. `recent` is true for the stack the shortcut lists and false for a stack made from the corner's own cards. Flags: `editorOpen`, `listing` (a recent listing is in flight), `stackOnLanding` (private: the card now in the editor becomes a stack when it lands). Derived: `isStack`, `becomesStack` (`stackOnLanding && mode == .thumbnails`), `isKeyed` (`isStack && !editorOpen`), `leavesOnItsOwn` (`mode == .thumbnails && !listing`).

Events and who sends them:

- `cardsShown`: `ThumbnailController.present`.
- `shortcut(StackRequest)`: `toggleRecent`, from `AppDelegate.pressRecent` (hotkey fire and hold, menu, `vignette://recent`).
- `listed(found:)`: `openRecent`, always in the same drain as the `listRecent` effect.
- `selected`: `StackSweep.move`, through a closure.
- `editorOpened`, `editorClosed(RunEnding?)`: `handle`, when `model.annotating != run.isActive`.
- `cardLanded(id, others:)`: `returnCard`'s `arrived`, only if `visible`.
- `dismiss(reason)`: `ThumbnailController.dismiss(by:)` (guarded by `visible`), Esc in `handleKey`, the `OutsideClick` callback (`CornerKeys.swift`, not guarded by `visible`).
- `slidOut`: end of `slideOut`'s `asyncAfter`, only when its generation still matches.

Effects: `holdKeys`, `takeKeys(.current | .card(id))`, `releaseKeys`, `restoreFocus(reason:)`, `closeEditor`, `listRecent`, `slideOut(reason)`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| `listing` | `cardsShown` | unchanged; `stackOnLanding = false` | — (ignored) |
| not `listing` | `cardsShown` | `.thumbnails`; `stackOnLanding = false` | `releaseKeys` (also downgrades a `.stack`) |
| not a stack | `shortcut` | unchanged; `listing = true` | `holdKeys`, `closeEditor` if `editorOpen`, `listRecent` |
| `.stack(recent: true)`, or `.stack(false)` with `editorOpen` | `shortcut` | `.hidden` | `releaseKeys`, `slideOut` |
| `.stack(false)`, no editor | `shortcut` | unchanged; `listing = true` | `holdKeys`, `listRecent` |
| any | `listed(found)` | `listing = false`; `.stack(true)` if `found` | `takeKeys(.current)` unless `editorOpen`; `releaseKeys` if not a stack and not `found` |
| `.thumbnails`, no editor | `selected` | `.stack(false)` | `takeKeys(.current)` |
| other | `selected` | — | — (ignored) |
| any | `editorOpened` | `editorOpen = true`; `stackOnLanding = false` | `releaseKeys` |
| any | `editorClosed(e)` | `editorOpen = false`; `stackOnLanding = (e == .back && mode == .thumbnails)` | `restoreFocus` when `e` is non-nil and not `.shortcut`; else — |
| `.thumbnails`, `stackOnLanding`, no editor, `others` | `cardLanded` | `.stack(false)` | `takeKeys(.card(id))` |
| `isKeyed` | `cardLanded` | — | `takeKeys(.card(id))` |
| other | `cardLanded` | — | — |
| not `.hidden` | `dismiss` | `.hidden`; `stackOnLanding = false` | `releaseKeys`, `slideOut(reason)` |
| `.hidden` | `dismiss` | — | — (ignored) |
| `.hidden` | `slidOut` | — | `restoreFocus` |
| other | `slidOut` | — | — (ignored) |

**Invariants**

- The backdrop and the click-outside watch exist exactly while `isStack`. Checked by: construction at `CornerKeys.swift` (rule stated at `CornerPresentation.swift`, `CornerKeys.swift`). No test builds `CornerKeys`, which needs panels.
- The panel accepts keys only as the keyed stack, or while `listing`, or while the shortcut closes the editor. Checked by: `testRandomSequencesKeepTheKeysWithTheStack`.
- `takeKeys` is emitted only once the editor is closed. Checked by: the same test.
- `cardsShown`, `editorClosed(nil)`, `slidOut` and `dismiss` never give the corner the keys. Checked by: the same test.
- Focus is restored only after a hand closed the editor or the column slid out. Checked by: the same test.
- `cardsShown` leaves `becomesStack` false. Checked by: the same test.
- `mode == .stack` implies the controller's `visible` is true. Checked by: nothing. The random test never sends `cardsShown` or `selected` while a stack is up, so the "`cardsShown` downgrades a stack" row is unexercised.
- `mode == .thumbnails` can hold while `visible` is false and the panel is ordered out, after `takeOutOfPanel` (`ThumbnailController.swift`). This is intended; nothing checks it.

**Late and concurrent answers**

- Events sent inside effects (`present` sends `cardsShown`, `openRecent` sends `listed`, the run sends `editorClosed`): `EventHold` queues them and runs them in order after the current event, `CornerKeys.swift` (`EventHold` is at `AnnotationRun.swift`).
- `cardsShown` inside the shortcut's own `listRecent`: ignored by `guard !listing`, `CornerPresentation.swift`.
- A second shortcut during a listing: cannot interleave. `openRecent` always sends `listed` in the same drain, which resets `listing`.
- `listed` while a zoomed editor is still closing: `takeKeys` is skipped (`CornerPresentation.swift`); the card landing takes the keys later (`cardLanded`, `isKeyed`).
- Shortcut during a slide-out: mode is `.hidden`, so it lists again. `present` reverses the dismissal (`reusing`, `ThumbnailController.swift`); the `dismissGeneration` bump cancels the removal.

### CornerKeys window side (implicit)

Owner: `CornerKeys.swift`. Tests: none.

Runs the reducer's effects on the panel, the backdrop and the click-outside watch (`runWindowSide`).

**States**: `panel.acceptsKeys` (set only in this file), `panel.isKeyWindow`, `heldPanelUp` (the panel was brought up only for a listing), `heldAt`, backdrop shown, `outsideClick` started, and a 0.1 s retry.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `holdKeys` | `heldPanelUp = !panel.isVisible` | `orderFrontRegardless` if the panel was down; `acceptsKeys = true`; `makeKey` |
| any | `takeKeys` | `heldAt` cleared | `acceptsKeys = true`; `makeKey`; one retry after 0.1 s |
| any | `releaseKeys` | `heldPanelUp`, `heldAt` cleared | `acceptsKeys = false`; resign key; `orderOut` if `heldPanelUp` |
| any | `listed(found: true)` | `heldPanelUp = false`, before the reducer runs | a panel brought up for the listing stays once cards fill it |

**Invariants**

- `heldPanelUp` is true only between `holdKeys` and the next `listed(true)` or `releaseKeys`. Checked by: nothing (a code comment says so).
- `acceptsKeys` is false while `mode == .hidden` and not listing. Checked by: `testRandomSequencesKeepTheKeysWithTheStack`, on the reducer's effects only.

**Late and concurrent answers**

- The 0.1 s retry re-checks `isKeyed`, `isVisible` and `!isKeyWindow` before acting, `CornerKeys.swift`. The retry and the outside-click callback hold `self` weakly.

### Panel visibility and dismissal in ThumbnailController (implicit)

Owner: `ThumbnailController.swift` and. Tests: none.

Decides when the panel is on screen, when cards slide out, and when a slide-out is cancelled. Driven by `show`, the shortcut, dismissals and the annotation run.

**States**: `visible`, `panel.isVisible`, `keys.presentation.mode`, `model.isStack` (`StackModel.swift`; follows `mode` only when mode is not `.hidden`), `model.slidingOut`, `model.offscreen`, `model.cards`, `dismissGeneration`, `shrinkGeneration`, `pinnedDisplay`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| not `visible` | `show` | `visible = true` through `present` | bumps `dismissGeneration`; sends `cardsShown`; then `leaveCorner` |
| `visible` | `show` | card inserted through `insert` | `shiftUp` when the column is non-empty and the entrance is `.slide`; else plain insert; then `leaveCorner` |
| not `visible` | `dismiss(by:)` | — | — (guard) |
| `visible` | `dismiss(by:)` | `slideOut`: `visible = false`; bumps `dismissGeneration`; ends forming flights; flies every card still flying home to its slot's place off the screen; records the annotator's card in `leavingWithColumn`; `model.slidingOut = true`; `offscreen = all cards` | after the slide: if the generation is unchanged and still `!visible`: `orderOut`, remove all cards, clear selection, `outCards`, forming and scroll, `pinnedDisplay = nil`, send `slidOut` |
| sliding out | `present` | the slide-out is reversed; cards turn around | `dismissGeneration` bumped, so the removal skips |
| lone card in the editor | `takeOutOfPanel` | card removed; if the column is now empty, `visible = false` | `panel.orderOut`; mode stays `.thumbnails` |

**Invariants**

- A slide-out's removal runs only if `dismissGeneration == gen && !visible`. Checked by: the guard at `ThumbnailController.swift`; no test.
- After a `slidOut` that finds `mode == .hidden`, focus goes back. Checked by: `CornerPresentationTests.testTheFocusGoesBackOnceTheColumnHasSlidOut`, for the reducer only. The controller path skips `slidOut` when the generation was bumped ([corner-6](plausible-findings-run-to-toolbar.md#corner-6)).

**Late and concurrent answers**

- The slide-out removal: generation check.
- The shrink after a removal: `shrinkGeneration` check.
- `present` keeps cards the new column still shows (`kept`).
- The `offscreen = []` clear is guarded by `visible`.

### Lone thumbnail timer, `leaveTimer` (implicit)

Owner: `ThumbnailController.swift`, armed by `leaveCorner(after:)`. Tests: none.

Takes lone thumbnails off screen after a delay.

**States**: `leaveTimer` armed or nil, with `keys.leavesOnItsOwn`, `model.hoveredCard`, `run.isActive`, `notices.awaitsAnswer`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `leaveCorner(after:)` from `show`, `post`, `cancelled`, `returnCard`'s arrival | newest call sets the time | — |
| `!leavesOnItsOwn` | `leaveCorner(after:)` | — | not armed (guard) |
| armed | fires, `hoveredCard != nil` or `run.isActive` or a send awaits an answer | re-armed for 1.5 s | — |
| armed | fires, none of those | — | `dismiss(.timeout)` (no-op when `!visible`) |
| armed | `presentationChanged` with `!new.leavesOnItsOwn`, `perform(.prepare)`, `slideOut`, `present` | nil | invalidated |

**Invariants**

- The newest `leaveCorner` call sets the time, and no timer runs while the stack is up. Checked by: nothing (a code comment says so).
- `leavesOnItsOwn` going false invalidates the timer but going true again does not re-arm it. ([corner-5](plausible-findings-run-to-toolbar.md#corner-5))

**Late and concurrent answers**

- The corner becoming the stack invalidates the timer; the editor-open guard re-arms instead of dismissing.

### CardNotices and its posting timers (explicit value, implicit timers)

Owner: `CardNotices.swift`, held as `StackModel.notices` (`StackModel.swift`); timers in `ThumbnailController.post`. Tests: `CardNoticesTests.testEachNoticeReplacesTheOneBefore`, `testAFailedSendIsShownAfterACopyMadeWhileItWaited`, `testAnEarlierTimerLeavesALaterNoticeUp`, `testAnAnswerToAnEarlierSendIsDropped`, `testAFailedReplyWaitsBehindALaterSendButNotAFinishedOne`, `testWhatACardNobodySeesComesBackFor`, `testHolds`, `testNoticesAreKeptPerFile`, `testASendInItsGraceWaitsAndReleaseMovesItOnToSending`, `testACancelledSendLosesItsNoticeAndTheWaitForAnAnswer`, `testCancellingAnEarlierSendLeavesALaterOneInItsGrace`, `testACopiedNoticeGivesTheCountdownBackWhenItExpires`, `testANoticeOnAFileRenamedDuringItsHoldStillExpires`, `testAReleaseUnderACopiedLeavesNothingToShowWhenTheCopiedExpires`, `testTheGraceRemainingIsClampedToTheSendsOwnLength`, `testALineReleasedAndAnsweredTogetherStillShowsSending`.

A value that holds the one notice each card shows, such as "Copied" or a send's state, and the send each card still waits on. The controller turns its `hold` into a timer that calls `expire`.

**States**: `shown: [ScreenshotKey: (id, Notice)]`, `awaitingAnswer: [ScreenshotKey: SendNotice]`, `lastID`. `Notice` is `.copied`, `.notCopied`, `.notSaved` or `.send(SendNotice)`. `SendNotice.State` is `inGrace`, `sending`, `sent`, `queued`, `uncertain`, `failed`, `replyFailed`, `done`. A notice "explains" when it carries a reason; it holds three times as long.

Events (`post`): `copied`, `notCopied`, `notSaved`, `sending`, `released`, `cancelled`, `answered`, `replyFailed`, `finished`. Also `expire(id, on:)` and `rename(from:to:)`. The controller's senders are `showCopied` and `showFailed` (`ThumbnailController.swift`), and `showNotCopied`, `showNotSaved`, `showSending`, `released`, `cancelled`, `delivered`, `finished` and `replyFailed` in `ThumbnailController+Notices.swift`, called from `AppDelegate`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `copied`, `notCopied`, `notSaved` | `shown[file]` replaced with a new id | hold 1x, or 3x if it explains |
| any | `replyFailed`, `finished` | as above when no later send waits; else — | hold; — |
| any | `sending` | `awaitingAnswer[file]` set; `shown` replaced; state `inGrace` if a grace is given | no hold |
| waiting request is `r` and `inGrace` | `released(r)` | waiting state becomes `sending`; `shown` updated only if it still shows that send | — |
| any other | `released(r)` | — | — |
| `shown` and waiting are both `r` | `cancelled(r)` | both cleared | — |
| waiting request is not `r` | `answered(r)` | — | — (dropped) |
| waiting request is `r`, card unseen, state does not explain | `answered(r)` | waiting cleared; matching `shown` cleared | — |
| waiting request is `r`, otherwise | `answered(r)` | waiting cleared; new state shown | hold |
| `shown[file].id != id` | `expire(id, file)` | — | — (ignored) |
| `shown[file].id == id` | `expire(id, file)` | cleared; a waiting send `inGrace` is shown again | no timer |
| any | `rename(old, new)` | `shown` and `awaitingAnswer` keys move | — |

**Invariants**

- One notice per file, the newest wins. Checked by: `testEachNoticeReplacesTheOneBefore`.
- A failed send is shown after a copy made while it waited. Checked by: `testAFailedSendIsShownAfterACopyMadeWhileItWaited`.
- An earlier timer leaves a later notice up. Checked by: `testAnEarlierTimerLeavesALaterNoticeUp`.
- An answer to an earlier send is dropped. Checked by: `testAnAnswerToAnEarlierSendIsDropped`. The written rule "a failure is never lost" disagrees for a re-sent card. ([corner-10](plausible-findings-run-to-toolbar.md#corner-10))
- The grace countdown returns when a covering Copied expires. Checked by: `testACopiedNoticeGivesTheCountdownBackWhenItExpires`.
- A notice moved by `rename` still expires. Checked by: `CardNoticesTests.testANoticeOnAFileRenamedDuringItsHoldStillExpires`: `expire` takes only the notice's id (**fixed**, [corner-1](findings.md#corner-1)).
- `awaitingAnswer` entries for files that left, the controller's timer wiring and the `seen` computation. Checked by: nothing.

**Late and concurrent answers**

- A timer that fires after a newer notice: the id token in `expire`, `CardNotices.swift`.
- A late `released`, `cancelled` or `answered`: compared by request id.
- An answer for a card nobody sees: the unseen-card rule.
- `finished` and `replyFailed` defer to a later waiting send.
- A file renamed after a send: `sentShots` follows the rename in `AppDelegate`.
