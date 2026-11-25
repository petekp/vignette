# The corner and the stack: the long column, older shots and pictures

This file continues [The corner and the stack: the corner](corner.md), which has the area's introduction and terms. Its rules are in `docs/rules/stack-column.md`.

The recent stack's column can be as long as the folder. Older screenshots come in a chunk at a time (`OlderShots`), cards far from the view let their pictures go (`CardPictures`), and only the cards near the view are built at all (`CardColumn`, in [the next file](stack-column-built-cards.md)).

### OlderShots (implicit)

Owner: `OlderShots.swift`, held as `ThumbnailController.older` (`ThumbnailController.swift`) and driven by `ThumbnailController+Older.swift`. Tests: `OlderShotsTests` covers the order in which `ScreenshotWatcher.older` lists files, and nothing of this machine's state.

Reads the screenshots older than the column's oldest card, one chunk of `recentCount` at a time, and hands them to the controller to make cards. The folder is listed and each file's header looked up on a background queue (`OlderShots.queue`). The person's filter (`isShown`) runs on the main thread.

**States**: `loading`, `reachedOldest`, `added` (how many cards the chunks brought in), `after` (the last file examined, which the next chunk starts after; nil starts below the column's top card), `generation`, `waiting` (closures that run once the next chunk is in). `columnLimit` is derived: no limit once `added > 0` or a chunk is `loading`, else `recentCount`. The phase is one of idle (neither flag), `loading` and `reachedOldest`; the two flags are never set together.

**Events**: `load` (from `ThumbnailController.loadOlder`, `ThumbnailController+Older.swift`); the listing's answer, then the headers' answer (`filter`); `took`; `afterChunk`; `reset` (from `ThumbnailController.newColumn`, which only `present` calls, `ThumbnailController.swift`). The controller calls `loadOlder` from `columnMoved` when the scroll moved toward older cards and the view is within 1.5 viewports of the column's top (`ThumbnailController+Older.swift`, `olderLead`), and from `waitsForOlder` (`ThumbnailController+Older.swift`). `columnMoved` runs on the turn after any change to `StackModel.scroll` (`scrolled`, `ThumbnailController+Older.swift`; `StackModel.swift`) and at the end of every wheel step (`scrollColumn`, `ThumbnailController.swift`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| idle | `load` with no watcher (`listing()` is nil) or `limit == 0` | idle | — |
| idle | `load` | loading | reads `after`, `generation`; on the queue: lists `2 × limit + 16` files after `after`, else after `top` (the column's oldest card), skipping `shown` |
| loading, `reachedOldest` | `load` | — | — |
| loading | the listing's answer, same generation | loading | takes files until `limit` pass `isShown`; `after` = the last file examined, hidden ones included, unless none was examined; looks up the taken files' headers on the queue |
| loading | the headers' answer, same generation, more files remain (the listing had more, or a shown file was left over) | idle | `deliver` (`addOlder`), `waiting` is copied and emptied, then each copied closure runs (`OlderShots.swift`), so a closure may call `afterChunk` again |
| loading | the headers' answer, same generation, nothing remains | `reachedOldest` | as above |
| loading | either answer, the generation has changed | — | dropped; `loading` is not touched |
| any | `reset` | idle, `reachedOldest = false`, `added = 0`, `after = nil`, `waiting = []` | `generation += 1`; `CardPictures` resets with it |
| any | `took(n)` | `added += n` | called by `addOlder` with the cards it made |
| any | `afterChunk` | `waiting` gains a closure | — |

`addOlder` (`ThumbnailController+Older.swift`) does nothing when the column is no longer the recent stack (`isRecentStack`: `visible` and the presentation is `.stack(recent: true)`). Otherwise it skips files that already have a card, makes the cards (`makeCard` returns nil for an unreadable file), calls `took`, logs `[stack] older cards=<n> column=<n>` (with ` reached-oldest` after the last chunk), and, when there are any, appends them to the column in one update with animations off, parks them offscreen for one turn, gives them entrance ranks from the lowest, and calls `keepPictures`.

**Invariants**

- Only one chunk is delivered at a time, and a new read starts only when none is loading (`load`'s guard). `reset` sets `loading = false`, so the old chunk's work may still run on the queue while a new read starts; its answers are dropped by `generation`. Checked by: nothing.
- A chunk never starts before the files an earlier chunk examined. The listing orders by date and name, as the recent stack does, and starts after `after`. Checked by: `OlderShotsTests.testChunksWalkTheFolderNewestFirstFromBelowTheColumnToTheOldestFile`, `testAChunkStartsAfterThePlaceTheLastOneTookEvenOnceThatFileIsGone`, which pass `after` themselves; nothing checks that `OlderShots` sets `after` to the last file examined. The ordering is also checked by `testEqualDatesFallToTheNameAsTheRecentStackOrdersThem`.
- The first chunk starts below the column's top card, and skips every file the column shows. Checked by: `testAChunkSkipsWhatTheColumnShowsAndStartsBelowItsTopCard`, `testACardWithAnOldDateBelowTheTopCardDoesNotMoveTheStart`. When the index does not hold the top card, the listing starts after the oldest shown file it holds, and when it holds none, it lists every file (`ScreenshotWatcher+Older.swift`; `testAColumnTheIndexDoesNotHoldStartsAtTheNewestFile`).
- A capture that joins the column drops its oldest card when the column holds more than `recentCount` (`removeOverflow`, `ThumbnailController.swift`). While a chunk is being read, and once any chunk has brought in a card, nothing drops, since the oldest cards are the ones the person scrolled to. A chunk that brought in no card leaves `added` at 0, so the limit goes back to `recentCount`; cards that joined meanwhile stay, and each later capture drops one. Checked by: `StackModelTests.testTheOverflowKeepsTheCardsInTheEditorAndInAStitch` for the drop itself; nothing for the limit.
- A chunk read for a column that has since been replaced is never delivered: both answers check `generation`, and `reset` empties `waiting`. Checked by: nothing.
- After `reachedOldest` nothing loads until `reset`, and the key press that waited for older cards no longer waits (`waitsForOlder` returns false, `ThumbnailController+Older.swift`). Checked by: nothing.

**Late and concurrent answers**

- A listing or a header lookup that answers after `reset` is dropped at its own check, so a chunk for an old column never reaches the new one.
- A chunk that arrives after the stack slid out, or when the corner shows instead, reaches `addOlder`, which returns at its guard. `after` and `loading` have already moved on, so the files that chunk took are not offered again in that column. The next `present` resets.
- Up arrow on the top card (`moveFocus`, `ThumbnailController.swift`) swallows the key when `waitsForOlder` returns true. It queues a closure and calls `loadOlder`. With no watcher, or a `recentCount` of 0 (`load` returns at its guard), no chunk comes and the closure waits for the next chunk or a `reset`.
- The closure moves the focus on only if the focused card is still the one that was on top and a card has since been added above it (`ThumbnailController+Older.swift`).

### CardPictures (implicit)

Owner: `CardPictures.swift`, held as `ThumbnailController.pictures` (`ThumbnailController.swift`); the controller's `keepPictures` (`ThumbnailController+Older.swift`), `askPicture` (`ThumbnailController+Older.swift`) and `arrive` (`ThumbnailController+Older.swift`) run it. Tests: `CardPicturesTests`, which covers `CardPictures.plan`, and of the controller's side only a column that shrank taking its pictures back.

Lets the cards far from the view drop their pictures and takes them back as the view comes near, so a column as long as the folder does not hold every picture. A card holds a picture when `image != nil` or its picture is waiting in `arrived`.

**States**, per card: holding, dropped, asked (`asked`, `CardPictures.swift`: the picture is being decoded, or failed to decode) and arrived (`arrived`, `CardPictures.swift`: decoded, and waiting for the arrival window to end). Per column: `dropped` (`CardPictures.swift`) holds the cards in the column that are dropped. `asked` and `arrived` are emptied by `reset` (`CardPictures.swift`). `dropped` outlasts it, since `present` keeps the cards on screen by id, a reversed dismissal the whole column, and `keepPictures` trims it to the column's cards.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `keepPictures` | — | `dropped` loses the cards no longer in the column (`ThumbnailController+Older.swift`) |
| any | `keepPictures`, the stack not `visible`, or the column no longer than `keptAlways` or `recentCount`, whichever is larger, and `dropped` empty | — | returns at once: every picture is kept (`ThumbnailController+Older.swift`) |
| holding | `keepPictures`, the column no longer than `max(keptAlways, recentCount)`, `dropped` not empty | — | none drops (`CardPictures.plan`, `dropsAny`, `CardPictures.swift`); the dropped rows below still run |
| holding | `keepPictures`, more than `keptAlways` and `recentCount` cards, the card more than `far` (4) viewports from the view, not in `recentCount` newest, not held, and 30 or more cards qualify | dropped | `image = nil` for all of them in one update, and they join `dropped` (`ThumbnailController+Older.swift`) |
| holding | the same, fewer than `batch` cards qualify | — | none drops |
| dropped | `keepPictures`, the card less than `near` (2) viewports from the view, not in `asked` | asked or arrived | `askPicture`, as the next two rows |
| dropped, in `Thumbnailer`'s cache | `askPicture` | arrived | `arrive` at once, with the cached picture |
| dropped, not cached | `askPicture` | asked | decodes off the main thread (`Thumbnailer.loadCard`, `caches: false`) |
| asked | the decode answers with a picture, `asked` still has the card | arrived | `asked` loses the card |
| asked | the decode answers with no picture | asked | stays asked, so it is not asked for again in this column; `dropped` loses the card (`ThumbnailController+Older.swift`) |
| asked | the decode answers after `reset` | — | dropped at the `asked` check |
| arrived | `arrivalWindow` (0.05 s) ends | holding | every picture that arrived in the window goes to its card in one update; `arrived` is emptied and `dropped` loses those cards |
| any | `reset` | `asked = []`, `arrived = [:]` | `dropped` is kept |

The cards a person is using keep their pictures wherever they are: the newest `recentCount`, those in the annotator or a stitch (`outCards`, `forming`), the selection, and the pressed, dragged, hovered and focused card (`held`, `ThumbnailController+Older.swift`). A flight out of the column carries the card's picture.

**Invariants**

- A column of at most `max(keptAlways, recentCount)` cards lets no picture go. Checked by: `CardPicturesTests.testAColumnNoLongerThanKeptAlwaysKeepsEveryPicture`, `testAColumnNoLongerThanALargerRecentCountKeepsEveryPicture`.
- A column that removals made that short still takes back, near the view, the pictures it let go. Checked by: `testAColumnThatShrankTakesBackThePicturesItLetGo` (the plan), `testACardInViewGetsItsPictureBackAfterTheColumnShrinks` (the controller).
- Pictures go only in a batch of 30 or more. Checked by: `testPicturesFarFromTheViewGoInABatchAndThoseInViewStay`, `testAFewFarPicturesWaitForAWholeBatch`.
- A card the controller holds keeps its picture at any distance. Checked by: `testACardTheControllerHoldsKeepsItsPictureAnywhere`.
- A card within `near` viewports of the view asks for a missing picture. Checked by: `testCardsComingNearTheViewAskForTheirPicturesBack`.
- A card is asked for its picture once per column while the decode is pending or has failed. Checked by: nothing.
- The pictures of the cards of older chunks are made and asked for without the cache (`makeCard(…, caches: false)`, `askPicture`), and a settings change decodes into it only for the cards at an index below `recentCount` (`cachesPicture(at:)`, `ThumbnailController.swift`), so an older card that has moved below that index after removals does enter it. Checked by: nothing.

**Late and concurrent answers**

- A decode that answers after the card left the column still reaches `arrive`; the window's update ignores an id with no card (`ThumbnailController+Older.swift`).
- `keepPictures` also runs at the end of `present` once the panel is laid out (`ThumbnailController.swift`), on every `columnMoved`, at the end of `addOlder` when the chunk made cards, and after every removal from a visible column (`ThumbnailController.removeCards(where:)`), whose cards above slide down with no scroll.
- A card from a new chunk has no picture while its first decode (`makeCard`, `ThumbnailController.swift`) is pending, and is not in `asked`. In a column longer than `max(keptAlways, recentCount)`, `keepPictures` at the end of `addOlder` finds it within `near` and asks again, so it is decoded twice.
- A card in `arrived` counts as holding. If it is in a dropped batch, the drop does nothing to it, and the arrival window then gives it its picture far from the view.
