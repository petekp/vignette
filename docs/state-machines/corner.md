# The corner and the stack: the corner

The corner is the screen edge where Vignette shows screenshot cards: a few lone thumbnails, or the stack, a column of recent cards that takes the keyboard. `CornerPresentation` decides which one is showing and who holds the keys. `CornerKeys` and `ThumbnailController` run what it decides.

### CornerPresentation (explicit)

Owner: `CornerPresentation.swift:25`, held by `CornerKeys.presentation` (`CornerKeys.swift:48`). Tests: `CornerPresentationTests.testLoneThumbnailsNeverTakeTheKeys`, `testTheShortcutTakesTheKeysBeforeItListsThenOpensTheRecentStack`, `testTheShortcutWithNothingToShowLetsTheKeysGo`, `testTheShortcutClosesTheRecentStack`, `testSelectingInTheCornerMakesItAKeyedStackOfItsOwnCards`, `testEscFromTheCornersEditorMakesTheCornerAKeyedStackOfItsOwnCards`, `testTheFocusGoesBackOnceTheColumnHasSlidOut`, `testRandomSequencesKeepTheKeysWithTheStack`, and the others in that file.

A pure reducer. It decides whether the corner shows lone thumbnails or the stack, when the panel takes and gives up the keys, and when focus goes back to the app the person was in. The controller sends it events through `CornerKeys.send`; it returns effects.

**States**: `mode` (`CornerPresentation.swift:79`) is `.hidden`, `.thumbnails` or `.stack(recent: Bool)`. `recent` is true for the stack the shortcut lists and false for a stack made from the corner's own cards. Flags: `editorOpen` (`:81`), `listing` (`:83`, a recent listing is in flight), `stackOnLanding` (`:85`, private: the card now in the editor becomes a stack when it lands). Derived: `isStack`, `becomesStack` (`stackOnLanding && mode == .thumbnails`), `isKeyed` (`isStack && !editorOpen`), `leavesOnItsOwn` (`mode == .thumbnails && !listing`).

Events and who sends them:

- `cardsShown`: `ThumbnailController.present` (`:1333`).
- `shortcut(StackRequest)`: `toggleRecent` (`:250`), from `AppDelegate.pressRecent` (hotkey fire and hold, menu, `vignette://recent`).
- `listed(found:)`: `openRecent` (`:261`), always in the same drain as the `listRecent` effect.
- `selected`: `StackSweep.move`, through a closure (`:75`).
- `editorOpened`, `editorClosed(RunEnding?)`: `handle` (`:765`), when `model.annotating != run.isActive`.
- `cardLanded(id, others:)`: `returnCard`'s `arrived` (`:916`), only if `visible`.
- `dismiss(reason)`: `ThumbnailController.dismiss(by:)` (`:671`, guarded by `visible`), Esc in `handleKey` (`:1101`), the `OutsideClick` callback (`CornerKeys.swift:97`, not guarded by `visible`).
- `slidOut`: end of `slideOut`'s `asyncAfter` (`:719`), only when its generation still matches.

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

- The backdrop and the click-outside watch exist exactly while `isStack`. Checked by: construction at `CornerKeys.swift:94` (rule stated at `CornerPresentation.swift:23`, `CornerKeys.swift:92`). No test builds `CornerKeys`, which needs panels.
- The panel accepts keys only as the keyed stack, or while `listing`, or while the shortcut closes the editor. Checked by: `testRandomSequencesKeepTheKeysWithTheStack`.
- `takeKeys` is emitted only once the editor is closed. Checked by: the same test.
- `cardsShown`, `editorClosed(nil)`, `slidOut` and `dismiss` never give the corner the keys. Checked by: the same test.
- Focus is restored only after a hand closed the editor or the column slid out. Checked by: the same test.
- `cardsShown` leaves `becomesStack` false. Checked by: the same test.
- `mode == .stack` implies the controller's `visible` is true. Checked by: nothing. The random test never sends `cardsShown` or `selected` while a stack is up, so the "`cardsShown` downgrades a stack" row is unexercised.
- `mode == .thumbnails` can hold while `visible` is false and the panel is ordered out, after `takeOutOfPanel` (`ThumbnailController.swift:950`). This is intended; nothing checks it.

**Late and concurrent answers**

- Events sent inside effects (`present` sends `cardsShown`, `openRecent` sends `listed`, the run sends `editorClosed`): `EventHold` queues them and runs them in order after the current event, `CornerKeys.swift:58,83` (`EventHold` is at `AnnotationRun.swift:278`).
- `cardsShown` inside the shortcut's own `listRecent`: ignored by `guard !listing`, `CornerPresentation.swift:99`.
- A second shortcut during a listing: cannot interleave. `openRecent` always sends `listed` in the same drain, which resets `listing`.
- `listed` while a zoomed editor is still closing: `takeKeys` is skipped (`CornerPresentation.swift:115`); the card landing takes the keys later (`cardLanded`, `isKeyed`).
- Shortcut during a slide-out: mode is `.hidden`, so it lists again. `present` reverses the dismissal (`reusing`, `ThumbnailController.swift:1338`); the `dismissGeneration` bump at `:1308` cancels the removal at `:710`.

### CornerKeys window side (implicit)

Owner: `CornerKeys.swift:47`. Tests: none.

Runs the reducer's effects on the panel, the backdrop and the click-outside watch (`runWindowSide`, `:111`).

**States**: `panel.acceptsKeys` (`:8`, set only in this file), `panel.isKeyWindow`, `heldPanelUp` (`:61`, the panel was brought up only for a listing), `heldAt` (`:63`), backdrop shown, `outsideClick` started, and a 0.1 s retry.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `holdKeys` | `heldPanelUp = !panel.isVisible` | `orderFrontRegardless` if the panel was down; `acceptsKeys = true`; `makeKey` |
| any | `takeKeys` | `heldAt` cleared | `acceptsKeys = true`; `makeKey`; one retry after 0.1 s |
| any | `releaseKeys` | `heldPanelUp`, `heldAt` cleared | `acceptsKeys = false`; resign key; `orderOut` if `heldPanelUp` |
| any | `listed(found: true)` | `heldPanelUp = false`, before the reducer runs (`:86`) | a panel brought up for the listing stays once cards fill it |

**Invariants**

- `heldPanelUp` is true only between `holdKeys` and the next `listed(true)` or `releaseKeys`. Checked by: nothing (comment at `:59`).
- `acceptsKeys` is false while `mode == .hidden` and not listing. Checked by: `testRandomSequencesKeepTheKeysWithTheStack`, on the reducer's effects only.

**Late and concurrent answers**

- The 0.1 s retry re-checks `isKeyed`, `isVisible` and `!isKeyWindow` before acting, `CornerKeys.swift:131`. The retry and the outside-click callback hold `self` weakly.

### Panel visibility and dismissal in ThumbnailController (implicit)

Owner: `ThumbnailController.swift:221-723` and `:1299-1530`. Tests: none.

Decides when the panel is on screen, when cards slide out, and when a slide-out is cancelled. Driven by `show`, the shortcut, dismissals and the annotation run.

**States**: `visible` (`:57`), `panel.isVisible`, `keys.presentation.mode`, `model.isStack` (`StackModel.swift:41`; follows `mode` only when mode is not `.hidden`, `:63`), `model.slidingOut` (`:17`), `model.offscreen` (`:12`), `model.cards`, `dismissGeneration` (`:64`), `shrinkGeneration` (`:65`), `pinnedDisplay`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| not `visible` | `show` (`:226`) | `visible = true` through `present` (`:1299`) | bumps `dismissGeneration`; sends `cardsShown`; then `leaveCorner` |
| `visible` | `show` | card inserted through `insert` (`:1366`) | `shiftUp` (`:1430`) when the column is non-empty and the entrance is `.slide`; else plain insert; then `leaveCorner` |
| not `visible` | `dismiss(by:)` (`:671`) | — | — (guard) |
| `visible` | `dismiss(by:)` | `slideOut` (`:678`): `visible = false`; bumps `dismissGeneration`; ends forming flights; flies every card still flying home to its slot's place off the screen; records the annotator's card in `leavingWithColumn`; `model.slidingOut = true`; `offscreen = all cards` | after the slide: if the generation is unchanged and still `!visible`: `orderOut`, remove all cards, clear selection, `outCards`, forming and scroll, `pinnedDisplay = nil`, send `slidOut` |
| sliding out | `present` | the slide-out is reversed; cards turn around | `dismissGeneration` bumped, so the removal at `:710` skips |
| lone card in the editor | `takeOutOfPanel` (`:950`) | card removed; if the column is now empty, `visible = false` | `panel.orderOut`; mode stays `.thumbnails` |

**Invariants**

- A slide-out's removal runs only if `dismissGeneration == gen && !visible`. Checked by: the guard at `ThumbnailController.swift:710`; no test.
- After a `slidOut` that finds `mode == .hidden`, focus goes back. Checked by: `CornerPresentationTests.testTheFocusGoesBackOnceTheColumnHasSlidOut`, for the reducer only. The controller path skips `slidOut` when the generation was bumped ([corner-6](plausible-findings-run-to-toolbar.md#corner-6)).

**Late and concurrent answers**

- The slide-out removal: generation check at `:710`.
- The shrink after a removal: `shrinkGeneration` check at `:1507`.
- `present` keeps cards the new column still shows (`kept`, `:1318`).
- The `offscreen = []` clear is guarded by `visible` (`:1356`).

### Lone thumbnail timer, `leaveTimer` (implicit)

Owner: `ThumbnailController.swift:50`, armed by `leaveCorner(after:)` (`:1519`). Tests: none.

Takes lone thumbnails off screen after a delay.

**States**: `leaveTimer` armed or nil, with `keys.leavesOnItsOwn`, `model.hoveredCard`, `run.isActive`, `notices.awaitsAnswer`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `leaveCorner(after:)` from `show` (`:233`), `post` (`:668`), `cancelled` (`:622`), `returnCard`'s arrival (`:917`) | newest call sets the time | — |
| `!leavesOnItsOwn` | `leaveCorner(after:)` | — | not armed (guard `:1520`) |
| armed | fires, `hoveredCard != nil` or `run.isActive` or a send awaits an answer | re-armed for 1.5 s | — |
| armed | fires, none of those | — | `dismiss(.timeout)` (no-op when `!visible`) |
| armed | `presentationChanged` with `!new.leavesOnItsOwn` (`:298`), `perform(.prepare)` (`:797`), `slideOut` (`:684`), `present` (`:1307`) | nil | invalidated |

**Invariants**

- The newest `leaveCorner` call sets the time, and no timer runs while the stack is up. Checked by: nothing (comment at `:1514`).
- `leavesOnItsOwn` going false invalidates the timer but going true again does not re-arm it. ([corner-5](plausible-findings-run-to-toolbar.md#corner-5))

**Late and concurrent answers**

- The corner becoming the stack invalidates the timer; the editor-open guard re-arms instead of dismissing.

### CardNotices and its posting timers (explicit value, implicit timers)

Owner: `CardNotices.swift:50`, held as `StackModel.notices` (`StackModel.swift:34`); timers in `ThumbnailController.post` (`:661`). Tests: `CardNoticesTests.testEachNoticeReplacesTheOneBefore`, `testAFailedSendIsShownAfterACopyMadeWhileItWaited`, `testAnEarlierTimerLeavesALaterNoticeUp`, `testAnAnswerToAnEarlierSendIsDropped`, `testAFailedReplyWaitsBehindALaterSendButNotAFinishedOne`, `testWhatACardNobodySeesComesBackFor`, `testHolds`, `testNoticesAreKeptPerFile`, `testASendInItsGraceWaitsAndReleaseMovesItOnToSending`, `testACancelledSendLosesItsNoticeAndTheWaitForAnAnswer`, `testCancellingAnEarlierSendLeavesALaterOneInItsGrace`, `testACopiedNoticeGivesTheCountdownBackWhenItExpires`, `testANoticeOnAFileRenamedDuringItsHoldStillExpires`, `testAReleaseUnderACopiedLeavesNothingToShowWhenTheCopiedExpires`, `testTheGraceRemainingIsClampedToTheSendsOwnLength`, `testALineReleasedAndAnsweredTogetherStillShowsSending`.

A value that holds the one notice each card shows, such as "Copied" or a send's state, and the send each card still waits on. The controller turns its `hold` into a timer that calls `expire`.

**States**: `shown: [ScreenshotKey: (id, Notice)]` (`:92`), `awaitingAnswer: [ScreenshotKey: SendNotice]` (`:93`), `lastID`. `Notice` is `.copied`, `.notCopied` or `.send(SendNotice)`. `SendNotice.State` (`:10`) is `inGrace`, `sending`, `sent`, `queued`, `uncertain`, `failed`, `replyFailed`, `done`. A notice "explains" when it carries a reason; it holds three times as long.

Events (`post`, `:101`): `copied`, `notCopied`, `sending`, `released`, `cancelled`, `answered`, `replyFailed`, `finished`. Also `expire(id, on:)` (`:149`) and `rename(from:to:)` (`:156`). The controller's senders are `showCopied`, `showNotCopied`, `showSending`, `released`, `cancelled`, `delivered`, `finished`, `replyFailed` (`:595-651`), called from `AppDelegate`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `copied`, `notCopied` | `shown[file]` replaced with a new id | hold 1x, or 3x if it explains |
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

- A timer that fires after a newer notice: the id token in `expire`, `CardNotices.swift:150`.
- A late `released`, `cancelled` or `answered`: compared by request id.
- An answer for a card nobody sees: the unseen-card rule at `:132`.
- `finished` and `replyFailed` defer to a later waiting send (`:138,141`).
- A file renamed after a send: `sentShots` follows the rename in `AppDelegate` (`:501`).
