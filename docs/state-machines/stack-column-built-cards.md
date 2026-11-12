# The corner and the stack: the built cards, lift and carried cards

This file continues [The corner and the stack: the long column, older shots and pictures](stack-column.md), which has the column's introduction. Its rules are in `docs/rules/stack-column.md`.

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

**Late and concurrent answers**

- A frame reads `scroll`, `liftFraction` and `widthScale` as drawn then, so a spring that carries the column far builds the cards on its way. A removal's relayout is a layout animation the column cannot read; `carried` covers it.

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
- `present` always calls `setLifts([:])`, but `shift` changes only in `springLifts`. When `present` reuses the cards during a running spring, the cards jump to their slots while `shift` still holds the old lifts, so a capture within `shiftUpDuration` adds a stale `liftLeft`. Checked by: nothing.
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
| any | `removeCards(where:)` | `carried` = the cards that stay and whose slots meet the band from `scroll - reach` to the built range's top plus the height that leaves (`fall`) | `model.removeCards` runs (the focus moves to the newest card if its card left), then `keepPictures`; a timer starts |
| `carried` set | the timer fires, `carried` equals the set it set | `carried = []` | — |
| `carried` set | the timer fires, `carried` differs | — | a later removal's timer clears it |

`StackModel.removeCards` has callers that do not carry, and `takeOutOfPanel` (`ThumbnailController.swift:955`) removes cards with `model.cards.removeAll`: the slide-out's `removeCards { _ in true }` (`ThumbnailController.swift:715`), `present` (`ThumbnailController.swift:1349`) and `removeOverflow`.

**Invariants**

- A card in `carried` is built (`keptBuilt` includes it) until the timer clears it. `carried` and `sweepCard` are not `@Published` (`StackModel.swift:63`, `:66`), so clearing them redraws nothing: the card stays built until the next published change. Checked by: nothing.
- The timer compares the set, not the removal. A second removal that carries the same cards is cleared by the first's timer, up to `2 × ui.relayoutDuration` before its own. Checked by: nothing; not run.

**Late and concurrent answers**

- A timer that fires with a different `carried` leaves it, so a removal in the middle of another keeps the newer set built.
