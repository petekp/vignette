# The toolbar and destinations: the target menu

This file continues [The toolbar and destinations: the toolbar](toolbar.md), which has the area's introduction and terms.

### Target menu pick (implicit)

Owner: `AnnotatorToolbar+TargetMenu.swift:11-21` (`pressTarget`), `:26-28` (`openTargetMenuFromKeys`), `:35-54` (`showTargetMenu`); `AnnotatorToolbar+TargetPick.swift:9-22` (`onPick`); `AnnotatorToolbar.swift:285-289` (`onMenuKey`), `:47-49` (`targetMenuImage`); `AnnotatorToolbar+Panel.swift:77` (the press), `:90` (Up or Down); `AnnotatorToolbar+Focus.swift:26` (Space). Tests: `ToolbarOfferTests.testAPickInTheTargetsMenuLandsOnlyOnTheImageWhoseMenuItCameFrom`.

A press opens the target menu at once and the keys open it a turn later. A pick is applied one turn later.

**States**: closed; open (modal `NSMenu`, `popUp` has not returned); pick queued.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| closed | a press on the target's box or its slop (`targetSlop`), not on the message field, while `model.shown`, the offer offers a target, `!model.sending` and `targetFrame != nil` | open, at once | `ToolbarPanel.sendEvent` calls `pressTarget` before SwiftUI's button sees the press, and the press is not passed on. AppKit's menu tracking has the press: a drag onto a row and a release picks it, and a release with no drag leaves the menu open |
| closed | a press that fails one of those guards | closed | `pressTarget` returns false and the press goes on to the bar |
| closed | Space on the focused target, or Up on the message field's first line or Down on its last | open, one turn later | `openTargetMenuFromKeys` queues `showTargetMenu(fromKeys: true)`, which highlights the first row, the row Return picks |
| closed | `showTargetMenu` with no target offer or `targetFrame == nil` | closed | refused (`AnnotatorToolbar+TargetMenu.swift:36`) |
| closed | `showTargetMenu` passes its guard | open | builds an `NSMenu` from `model.destinations + model.startable`; `model.targetMenuOpened()` records `imageNumber` as `targetMenuImage`; `TargetShade.show(open: true)` darkens the target; `popUp` |
| open | item chosen | pick queued | `TargetMenuActions.pick` (`SessionMenuPicks.swift:10`) calls `onPick`, which reads `targetMenuImage` and calls `DispatchQueue.main.async` |
| open | the menu closes, with a pick or without | closed, or pick queued | `popUp` returns and `TargetShade.show(open: false)` lightens the target |
| pick queued | the block runs | closed | `model.pick(destination)` under `withAnimation`, if `shown` and `imageNumber` still equals the `targetMenuImage` read at the pick; else `[send] pick dropped` |

**Invariants**

- The keys open the menu a turn later so the menu takes keys (comment `AnnotatorToolbar+TargetMenu.swift:23-25`). Checked by: nothing.
- A pick belongs to the image the menu opened on. Checked by: `ToolbarOfferTests.testAPickInTheTargetsMenuLandsOnlyOnTheImageWhoseMenuItCameFrom`. `targetFrame` comes from SwiftUI geometry and is never cleared (`AnnotatorToolbar.swift:270`).
- The target looks pressed exactly while the menu is open, since `popUp` returns only when it closes. Checked by: nothing.

**Late and concurrent answers**

- A `begin` while the menu is open (a block already on the main queue runs during menu tracking, which is one of the run loop's common modes), a `begin` between the pick and the queued block, or a hide: the pick is dropped.
