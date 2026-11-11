# The corner and the stack: the long column and the built cards

This file continues [The corner and the stack: the corner](corner.md), which has the area's introduction and terms. Its rules are in `docs/rules/stack-column.md`.

The recent stack's column can be as long as the folder. Older screenshots come in a chunk at a time (`OlderShots`), cards far from the view let their pictures go (`CardPictures`), and only the cards near the view are built at all (`CardColumn`).

### OlderShots (implicit)

Owner: `OlderShots.swift:8`, held as `ThumbnailController.older` (`ThumbnailController.swift:48`) and driven by `ThumbnailController+Older.swift`. Tests: `OlderShotsTests` covers the order in which `ScreenshotWatcher.older` lists files, and nothing of this machine's state.

Reads the screenshots older than the column's oldest card, one chunk of `recentCount` at a time, and hands them to the controller to make cards. The folder is listed and each file's header looked up on a background queue (`OlderShots.queue`, `:28`). The person's filter (`isShown`) runs on the main thread.

**States**: `loading` (`:19`), `reachedOldest` (`:21`), `added` (`:23`, how many cards the chunks brought in), `after` (`:25`, the last file examined, which the next chunk starts after; nil starts below the column's top card), `generation` (`:26`), `waiting` (`:27`, closures that run once the next chunk is in). `columnLimit` (`:33`) is derived: no limit once `added > 0` or a chunk is `loading`, else `recentCount`. The phase is one of idle (neither flag), `loading` and `reachedOldest`; the two flags are never set together.

**Events**: `load` (`:54`, from `ThumbnailController.loadOlder`, `ThumbnailController+Older.swift:47`); the listing's answer, then the headers' answer (`filter`, `:69`); `took` (`:98`); `afterChunk` (`:48`); `reset` (`:38`, from `ThumbnailController.newColumn`, which only `present` calls, `ThumbnailController.swift:1312`). The controller calls `loadOlder` from `columnMoved` when the scroll moved toward older cards and the view is within 1.5 viewports of the column's top (`ThumbnailController+Older.swift:30-34`, `olderLead`), and from `waitsForOlder` (`ThumbnailController+Older.swift:37`). `columnMoved` runs on the turn after any change to `StackModel.scroll` (`scrolled`, `ThumbnailController+Older.swift:24`; `StackModel.swift:58`) and at the end of every wheel step (`scrollColumn`, `ThumbnailController.swift:1181`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| idle | `load` with no watcher (`listing()` is nil) or `limit == 0` | idle | — |
| idle | `load` | loading | reads `after`, `generation`; on the queue: lists `2 × limit + 16` files after `after`, else after `top` (the column's oldest card), skipping `shown` |
| loading, `reachedOldest` | `load` | — | — |
| loading | the listing's answer, same generation | loading | takes files until `limit` pass `isShown`; `after` = the last file examined, hidden ones included, unless none was examined; looks up the taken files' headers on the queue |
| loading | the headers' answer, same generation, more files remain (the listing had more, or a shown file was left over) | idle | `deliver` (`addOlder`), then each `waiting` closure runs, then `waiting` is emptied |
| loading | the headers' answer, same generation, nothing remains | `reachedOldest` | as above |
| loading | either answer, the generation has changed | — | dropped; `loading` is not touched |
| any | `reset` | idle, `reachedOldest = false`, `added = 0`, `after = nil`, `waiting = []` | `generation += 1`; `CardPictures` resets with it |
| any | `took(n)` | `added += n` | called by `addOlder` with the cards it made |
| any | `afterChunk` | `waiting` gains a closure | — |

`addOlder` (`ThumbnailController+Older.swift:58`) does nothing when the column is no longer the recent stack (`isRecentStack`, `:13`: `visible` and the presentation is `.stack(recent: true)`). Otherwise it skips files that already have a card, makes the cards (`makeCard` returns nil for an unreadable file), calls `took`, logs `[stack] older cards=<n> column=<n>`, and, when there are any, appends them to the column in one update with animations off, parks them offscreen for one turn, gives them entrance ranks from the lowest, and calls `keepPictures`.

**Invariants**

- Only one chunk is read at a time. Checked by: the `loading` guard in `load` (`:56`).
- A chunk never starts before the files an earlier chunk examined. The listing orders by date and name, as the recent stack does, and starts after `after`. Checked by: `OlderShotsTests.testChunksWalkTheFolderNewestFirstFromBelowTheColumnToTheOldestFile`, `testAChunkStartsAfterThePlaceTheLastOneTookEvenOnceThatFileIsGone`, `testEqualDatesFallToTheNameAsTheRecentStackOrdersThem`.
- The first chunk starts below the column's top card, and skips every file the column shows. Checked by: `testAChunkSkipsWhatTheColumnShowsAndStartsBelowItsTopCard`, `testACardWithAnOldDateBelowTheTopCardDoesNotMoveTheStart`, `testAColumnTheIndexDoesNotHoldStartsAtTheNewestFile`.
- A capture that joins the column drops its oldest card when the column holds more than `recentCount` (`removeOverflow`, `ThumbnailController.swift:1470`). While a chunk is being read, and once any chunk has brought in a card, nothing drops, since the oldest cards are the ones the person scrolled to. A chunk that brought in no card leaves `added` at 0, so the limit goes back to `recentCount`. Checked by: nothing.
- A chunk read for a column that has since been replaced is never delivered: both answers check `generation`, and `reset` empties `waiting`. Checked by: nothing.
- After `reachedOldest` nothing loads until `reset`, and the key press that waited for older cards no longer waits (`waitsForOlder` returns false, `ThumbnailController+Older.swift:38`). Checked by: nothing.

**Late and concurrent answers**

- A listing or a header lookup that answers after `reset` is dropped at its own check, so a chunk for an old column never reaches the new one.
- A chunk that arrives after the stack slid out, or when the corner shows instead, reaches `addOlder`, which returns at its guard. `after` and `loading` have already moved on, so the files that chunk took are not offered again in that column. The next `present` resets.
- Up arrow on the top card (`moveFocus`, `ThumbnailController.swift:1146`) swallows the key when `waitsForOlder` returns true. It queues a closure and calls `loadOlder`. With no watcher, or a `recentCount` of 0 (`load` returns at its guard), no chunk comes and the closure waits for the next chunk or a `reset`.
- The closure moves the focus on only if the focused card is still the one that was on top and a card has since been added above it (`ThumbnailController+Older.swift:40`).

### CardPictures (implicit)

Owner: `CardPictures.swift:9`, held as `ThumbnailController.pictures` (`ThumbnailController.swift:49`); the controller's `keepPictures` (`ThumbnailController+Older.swift:86`), `askPicture` (`ThumbnailController+Older.swift:105`) and `arrive` (`ThumbnailController+Older.swift:117`) run it. Tests: `CardPicturesTests`, which covers `CardPictures.plan` and nothing of the controller's side.

Lets the cards far from the view drop their pictures and takes them back as the view comes near, so a column as long as the folder does not hold every picture. A card holds a picture when `image != nil` or its picture is waiting in `arrived`.

**States**, per card: holding, dropped, asked (`asked`, `CardPictures.swift:39`: the picture is being decoded, or failed to decode) and arrived (`arrived`, `CardPictures.swift:41`: decoded, and waiting for the arrival window to end). Per column: `asked` and `arrived` are emptied by `reset` (`CardPictures.swift:46`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `keepPictures`, the stack not `visible`, or the column no longer than `keptAlways` (100) or `recentCount`, whichever is larger | — | returns at once: every picture is kept (`ThumbnailController+Older.swift:88`, `CardPictures.plan`, `CardPictures.swift:25`) |
| holding | `keepPictures`, more than `keptAlways` and `recentCount` cards, the card more than `far` (4) viewports from the view, not in `recentCount` newest, not held, and 30 or more cards qualify | dropped | `image = nil` for all of them in one update (`ThumbnailController+Older.swift:99`) |
| holding | the same, fewer than `batch` (30) cards qualify | — | none drops |
| dropped | `keepPictures`, the card less than `near` (2) viewports from the view, not in `asked` | asked or arrived | `askPicture`, as the next two rows |
| dropped, in `Thumbnailer`'s cache | `askPicture` | arrived | `arrive` at once, with the cached picture |
| dropped, not cached | `askPicture` | asked | decodes off the main thread (`Thumbnailer.loadCard`, `caches: false`) |
| asked | the decode answers with a picture, `asked` still has the card | arrived | `asked` loses the card |
| asked | the decode answers with no picture | asked | stays asked, so it is not asked for again in this column |
| asked | the decode answers after `reset` | — | dropped at the `asked` check |
| arrived | `arrivalWindow` (0.05 s) ends | holding | every picture that arrived in the window goes to its card in one update; `arrived` is emptied |
| any | `reset` | `asked = []`, `arrived = [:]` | — |

The cards a person is using keep their pictures wherever they are: the newest `recentCount`, those in the annotator or a stitch (`outCards`, `forming`), the selection, and the pressed, dragged, hovered and focused card (`held`, `ThumbnailController+Older.swift:89-95`). A flight out of the column carries the card's picture.

**Invariants**

- A column of at most `max(keptAlways, recentCount)` cards holds every picture. Checked by: `CardPicturesTests.testAColumnNoLongerThanKeptAlwaysKeepsEveryPicture`, `testAColumnNoLongerThanALargerRecentCountKeepsEveryPicture`.
- Pictures go only in a batch of 30 or more. Checked by: `testPicturesFarFromTheViewGoInABatchAndThoseInViewStay`, `testAFewFarPicturesWaitForAWholeBatch`.
- A card the controller holds keeps its picture at any distance. Checked by: `testACardTheControllerHoldsKeepsItsPictureAnywhere`.
- A card within `near` viewports of the view asks for a missing picture. Checked by: `testCardsComingNearTheViewAskForTheirPicturesBack`.
- A card is asked for its picture once per column while the decode is pending or has failed. Checked by: nothing.
- The pictures of the cards of older chunks never enter `Thumbnailer`'s cache (`makeCard(…, caches: false)`, `askPicture`), and only the newest `recentCount` cards decode into it on a settings change (`cachesPicture(at:)`, `ThumbnailController.swift:526`). Checked by: nothing.

**Late and concurrent answers**

- A decode that answers after the card left the column still reaches `arrive`; the window's update ignores an id with no card (`ThumbnailController+Older.swift:123`).
- `keepPictures` also runs at the end of `addOlder` and on every `columnMoved`.

### CardColumn built cards (implicit)

Owner: `CardColumn` in `StackView.swift:307`, with `StackModel.keptBuilt` (`StackModel.swift:71`) and `StackLayout.cards(meeting:sizes:lifts:)` (`StackLayout+Slots.swift:10`). Tests: `ColumnSlotsTests`, which covers which cards meet a band and nothing of the view's building.

The column builds a card's view only while its slot is within one viewport of the view (`StackLayout.reach`, `StackLayout+Slots.swift:5`). Every other card is an empty frame of its drawn size in the `VStack`, so each card sits where a column of built cards would put it.

**States**, per card: built or an empty slot. The inputs are `scroll`, `liftFraction` and `widthScale`, which `CardColumn` reads as its animatable data (`StackView.swift:315`), so SwiftUI hands it each frame's value while they spring, and `keptBuilt`. The selection strip's lift follows the first selected card's (`stripLift`, `StackView.swift:77`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| slot | a frame where the card's slot, drawn its lift below, meets the band `scroll - reach … scroll + viewport + reach` | built | `CardView` made in the slot with `.transition(.identity)`, drawn its lift times `liftFraction` below the slot |
| slot | the card enters `keptBuilt` | built | the same |
| built | a frame where the slot is outside the band and the card is not in `keptBuilt` | slot | `CardView` removed with no transition, so a fade is not still running if a fling brings it back |
| built | the card leaves `keptBuilt` while outside the band | slot | the same |

`keptBuilt` holds the cards in the annotator or in a stitch (`outCards`, `forming`), those a removal carries (`carried`), the pressed, dragged, hovered, focused and entering card, the card that carries a drag-select's gesture (`sweepCard`), and every card showing a notice (`StackModel.swift:71-73`).

**Invariants**

- Every slot has its card's drawn size whether the card is built or not, so `StackLayout.cardFrame` holds for each card. Checked by: nothing.
- A card meets the band by where it is drawn, its lift included. Checked by: `ColumnSlotsTests.testALiftedCardMeetsTheBandWhereItIsDrawn`, `testTheCardsMeetingABandAreEveryCardWithAnyPartInIt`, `testABandInTheGapBetweenTwoCardsMeetsNeither`, `testABandPastEitherEndMeetsOnlyTheCardsThere`.
- A card whose view holds state that would end with it (a press, a drag, a hover, a notice's overlay, a drag-select's gesture) stays built. Checked by: nothing; `keptBuilt` lists them.
- A relayout the column cannot read, a removal's, must not leave a card unbuilt on its way through the view. Held by `carried`, below.

### StackModel.liftFraction (implicit)

Owner: `StackModel.liftFraction` (`StackModel.swift:16`), `setLifts` (`StackModel.swift:76`), `ThumbnailController.springLifts` (`ThumbnailController.swift:1412`), read in `CardColumn` (`StackView.swift:323`). Tests: none.

A capture, or a column shown over another, lifts each card back to where it was drawn (`lift`, a distance below its slot) and springs the lifts to 0 on `ui.shiftUpDuration`. The lifts share one fraction. `CardColumn` draws each card its lift times the fraction below its slot, so a card the column builds in the middle of the spring is drawn where the others are.

**States**: `liftFraction` (0 to 1), `lift` (per card), `ThumbnailController.shift` (`ThumbnailController.swift:1427`, when the lifts last sprang and what they were).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `setLifts(lifts)` | `lift = lifts`; `liftFraction = 1`, or 0 when `lifts` is empty | set with animations off, from `shiftUp` and `present` |
| `liftFraction == 1` | `springLifts`, next turn | `liftFraction` springs to 0 | `shift = (time, lift)`; `first()` runs before the spring and `alongside` inside it |
| springing | `setLifts` again (a second card joins, or the column is shown again) | `liftFraction = 1`, `lift` = what is left of the old lifts plus the new rise (`liftLeft`, `ThumbnailController.swift:1463`) | the new spring replaces the old |
| 0 | a frame | — | `CardColumn` draws no lift (`StackView.swift:323`) |
| any | `present` | `setLifts([:])`; then, when the cards are not the ones on screen, `setLifts(keptLift)` | `springLifts` when any lift is left |

**Invariants**

- A card is drawn `lift × liftFraction` below its slot, whether it was built before the spring or during it. Checked by: nothing.
- `lift` is not cleared when the spring ends: `liftFraction == 0` is what stops it drawing, and the next `setLifts` replaces it. Checked by: nothing.
- `liftLeft` computes what is left with `Spring(duration: ui.shiftUpDuration, bounce: 0)`, and the column's fraction springs with `Anim.spring(ui.shiftUpDuration)`. A second lift starts where the first is drawn only while the two agree. Checked by: nothing.

**Late and concurrent answers**

- `springLifts` sets `shift` at once and starts the spring on the next turn (`ThumbnailController.swift:1414-1419`). Until then `liftFraction` is 1 and the lifts are drawn whole.

### StackModel.carried (implicit)

Owner: `StackModel.carried` (`StackModel.swift:66`), set by `ThumbnailController.removeCards(where:)` (`ThumbnailController+Scroll.swift:18`). Tests: none.

Takes cards out of the visible column and keeps built every card whose slot passes through the view while the relayout runs. A removal's relayout is a layout animation, which `CardColumn` cannot read frame by frame, and the cards above the removed ones slide down by their height, which can be more than the margin the column builds past the view.

**States**: `carried` (a set of card ids), a timer set with each removal (`2 × ui.relayoutDuration`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `removeCards(where:)` | `carried` = the cards that stay and whose slots meet the band from `scroll - reach` to the built range's top plus the height that leaves (`fall`) | `model.removeCards` runs (the focus moves to the newest card if its card left); a timer starts |
| `carried` set | the timer fires, `carried` equals the set it set | `carried = []` | — |
| `carried` set | the timer fires, `carried` differs | — | a later removal's timer clears it |

`StackModel.removeCards` has callers that do not carry: the slide-out's `removeCards { _ in true }` (`ThumbnailController.swift:715`), `present` (`ThumbnailController.swift:1349`) and `removeOverflow`.

**Invariants**

- A card in `carried` is built (`keptBuilt` includes it) until the timer clears it. Checked by: nothing.
- The timer compares the set, not the removal. A second removal that carries the same cards is cleared by the first's timer, up to `2 × ui.relayoutDuration` before its own. Checked by: nothing; not run.

**Late and concurrent answers**

- A timer that fires with a different `carried` leaves it, so a removal in the middle of another keeps the newer set built.
