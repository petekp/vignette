# Live comments: deliveries

This file maps how a pin comment reaches an agent session as it is posted. Its rules are in
`docs/rules/live-comments.md`. The terms are in [the index](../state-machines.md#terms).

### A delivery (implicit)

Owner: `PinCommentDeliveries.swift` (`CommentDeliveries`: `add`, `release`, `finish`, `record`, `lookAgain`, `lookedAtQueue`, `watchTurn`, `releaseHeld`, `renamed`, `fileRemoved`); `PinCommentRules.swift` (`HeldChanges`, `CommentTurnWatch`). Tests: `CommentDeliveryTests`.

One line of comment changes for one screenshot and one session, from its first change to its last answer.

**States**: held (a `HeldChanges` and a timer); sending (submitted, no answer); queued (in a Codex thread's queue); sent; sent and working (the turn it started runs); uncertain; failed. Sent, uncertain and failed are kept until the newest 1,000 push them out.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| none | `add` with no hold for the screenshot and session | held | a timer of `ui.sendGraceSeconds`; `[comments] held` |
| held | `add` | held | `HeldChanges.add` merges; the timer keeps its deadline |
| held | a merge leaves no change | none | timer cancelled; `[comments] held <id> went empty` |
| held | the timer fires, or quit (`releaseHeld`) | sending | the delivery is stored; `submit` runs off the main thread |
| held | the file leaves the folder | none | `[comments] cancelled` |
| sending | `accepted` | sent | stored; the turn watch starts 0.5 s later |
| sending | `queued` with a line | queued | the queue watch starts (`QueueWatch.nextLook`) |
| sending | `uncertain` | uncertain | the reason stored |
| sending | `notSubmitted` or `destinationChanged` | failed | the reason stored |
| sending | the app quits without an answer | uncertain, at the next launch | the store's load turns it |
| queued | `taken` | sent | the turn watch starts |
| queued | `removed` | failed | `CommentDeliveries.removedReason` |
| queued | `threadGone` | failed | `ScreenshotRequests.threadGoneReason` |
| sent | the turn reads busy | sent and working | `[comments] working`; the popover shows the working row |
| sent | idle or nil after 10 s with no busy turn | sent | the watch ends |
| sent and working | idle or nil, or 30 min | sent | `[comments] turn ended`; the row goes |
| any stored | a rename | the same | the delivery's file follows (`renamed`) |
| any stored | the file leaves the folder | none | dropped (`fileRemoved`) |

Every change of state calls `changed`, which reaches an open popover on that screenshot.

**Invariants**

- One hold per screenshot and session. Checked by: the hold's key in `add`.
- A comment's words go at most once per post: the diff counts a comment once, and a post deleted inside the grace never goes. Checked by: `CommentDeliveryTests`.
- An edit, delete, Resolve or Reopen goes only to a session that knows the comment or the pin (`CommentTarget.knows`). Checked by: `CommentDeliveryTests`.
- The working row shows only for the turn after the line went in. A turn already running when the line went in reads busy at the first look, and is taken for the comment's. A Claude Code session reads lines only between turns, so it then still runs its own turn first. Checked by: nothing.

**Late and concurrent answers**

- An answer for a delivery the file's removal dropped finds no delivery and changes nothing (`record` returns false).
- A queue or turn look after a rename finds the delivery by id, so it follows the file.
