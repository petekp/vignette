# The toolbar and destinations: the toolbar

The toolbar is the bar under the annotator's frame. It holds the tools, a target (the agent session Send goes to), a message field and Send or Reply. This area covers how the bar picks its target and offer, how a send progresses, how the bar comes and goes, and how the agent connections list sessions and take a line.

A destination is an `AgentDestination`: one agent session a line can go to. A startable row is a past Claude Code session, or a new one, that Send would start. A kept list is the last session list a connection answered, kept so the next opening can answer at once.

### AnnotatorToolbar.Model: target and offer (implicit)

Owner: `AnnotatorToolbar.swift`. Tests: `ToolbarOfferTests.testTheTargetSettlesOnHerdrsFocusAndStaysWhenCodexAnswersLater`, `testWithNoFocusTheTargetIsTheSessionUsedLastAndIsReplacedOnlyWhenItIsGone`, `testASwapKeepsTheTargetOnTheBarUntilTheNextImagesSettles`.

Holds which session Send goes to for the open image. `AnnotationController.beginDestinations` (`AnnotationController.swift`) and `destinationsAnswered` drive it, called from `AppDelegate.refreshDestinations` and `listDestinations` (`AppDelegate+Send.swift`).

**States**: the properties together:
- `listing`: the last answer `DestinationChoice.replacesList` let in, which may be the image before's. Its `list` is the running sessions, its `startable` the rows Send would start, and its `sessions` both, the list every session menu and the target's words are built from. Its `complete`: every client answered it.
- `listed`: every client has answered for this image.
- `replyTo`: the session this image came from. `target`: the chosen destination.
- `picked`: the person chose the target. `isHandPick(_:)` reads it, and a Send to a hand pick sets the kept pick (the next machine). `carried`: the target is the image before's and waits for this image's first deciding answer.
- `offer` is derived (next machine) from `listing`. `reportOffer` calls `onOfferChanged` only when the offer changed.

A `decided` answer is one `DestinationChoice` marks as settled: complete, or any session marked by herdr.

**Transitions**

Events: `begin(replyTo:carryingTarget:)` (sent by `beginDestinations` with `carryingTarget: toolbar.model.shown`, right after `annotator.prepare`, `AppDelegate.swift`); `answered(_:)` (once per `SessionListing.deliver`); `pick(_:)` (from the target menu a turn later, `AnnotatorToolbar+TargetPick.swift`).

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `begin(carryingTarget: false)`, or `target == nil` | `replyTo` set; `listed`, `picked`, `carried` false; `listing` is `nothingListed`; `target` cleared | — |
| `target != nil`, not carried | `begin(carryingTarget: true)` | `carried = true`; `listing`, `target` kept; `listed`, `picked` false | — |
| any | `answered`, complete, or `listing` is not complete | the answer replaces `listing` (`DestinationChoice.replacesList`); then the rows below | — |
| `listing.complete` | `answered`, not complete | `listing` kept; `listed` false; then the rows below | — |
| carried | `answered`, not decided | `target` refreshed from the answer if same id; stays carried | — |
| carried | `answered`, decided | `carried = false`; `target = answer.pick` (may be nil) | — |
| not picked, not carried, `target == nil` | `answered`, decided | `target = answer.pick` | — |
| not picked, not carried, target set | `answered` | target kept, unless the answer is complete, the target is absent from it (`gone`) and the answer is decided: then `target = answer.pick` | — |
| picked | `answered` | `listed` updates, `listing` as above; `target` only refreshed to the object with the same id, never replaced | — |
| any | `pick(d)` | `target = d`, `picked = true`, `carried = false`. No check that `d` is in a list | — |

**Invariants**

- The target settles once, then changes only when its session is gone from a complete list (doc comment). A nil `pick` leaves `target == nil`, so the next decided answer settles it. Checked by: `ToolbarOfferTests.testTheTargetSettlesOnHerdrsFocusAndStaysWhenCodexAnswersLater`, `testWithNoFocusTheTargetIsTheSessionUsedLastAndIsReplacedOnlyWhenItIsGone`. A failed Codex listing can break it ([toolbar-2](plausible-findings-run-to-toolbar.md#toolbar-2)).
- A pick stays even when the list no longer has it. Checked by: the same two tests.
- A swap keeps the old target until this image's first deciding answer. Checked by: `ToolbarOfferTests.testASwapKeepsTheTargetOnTheBarUntilTheNextImagesSettles`.
- Reply stays Send until the whole list answers. Checked by: the same test.
- A complete list in the menu is never replaced by an incomplete answer, the image before's included. Checked by: the same test.
- A carried target still exists. Checked by: nothing.

**Late and concurrent answers**

- A list answer for an ended opening: dropped, guard at `AppDelegate+Send.swift` (`annotator.opening == opening`), and again after the off-main read. `Opening` ids are never reused, so closing and reopening the same file is another opening. `annotator.opening` is nil when `current == nil` (`AnnotationController.swift`).
- A carried target whose session is gone: Send still shows. A send to it fails at the preflight (`AgentConnection.swift`, "closed" or "cleared") and never lands on another session.
- A menu pick whose image is no longer open, because a `begin` ran while the menu was open or after the pick, or the bar hid: dropped ([target menu pick](target-menu.md)).

### Kept pick: AnnotationController.keptPick (implicit)

Owner: `AnnotationController.keptPick`, driven in `AnnotationController+Send.swift`. The window is `DestinationChoice.KeptPick.lasts`. Tests: `DestinationChoiceTests` (the tests named for the kept pick); `ToolbarOfferTests.testOnlyTheTargetPickedInTheMenuIsAHandPick`, `testAKeptPickSettlesASwappedBarWithoutShowingAnotherSessionFirst`.

The session Send starts on after the person picked it in the target's menu and sent to it. It spans openings and lives in memory only.

**States**: none (`keptPick == nil`); kept (`session`, `sentAt`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `sent(to:as:)` from `AppDelegate.submit` once the request is stored, a Send to the hand pick (`model.isHandPick`) or to the kept session (`KeptPick.after`), even 10 minutes since `sentAt` | kept (`sentAt` now); for a Continue last session or New session row, the session the send started (`AgentDestination.sent(as:)`), never the row | `[send] kept <address> project=<detail>` |
| kept | `sent(to:as:)`, a Reply, or a Send to a start Vignette chose, within 10 minutes | unchanged | — |
| kept | `sent(to:as:)`, a Reply, or a Send to a start Vignette chose, 10 minutes since `sentAt` | none | `[send] kept ended <address> reason=time` |
| kept | `beginDestinations`, 10 minutes since `sentAt` | none | `[send] kept ended <address> reason=time` |
| kept | `beginDestinations`, within 10 minutes | kept | answers `session`, passed to `Asker.send(kept:)` for this opening |
| kept | `destinationsAnswered`, `answer.keptIsGone` | none | `[send] kept ended <address> reason=gone` |

**Invariants**

- A pick that is never sent keeps nothing. Checked by: `DestinationChoiceTests.testOnlyASendToAHandPickOrToTheKeptPickKeepsIt`, `ToolbarOfferTests.testOnlyTheTargetPickedInTheMenuIsAHandPick`.
- A Reply neither sets, refreshes nor ends it. Checked by: the first of those for set and refresh; nothing ends it but time and `keptIsGone`.
- A listing that failed does not end it: `keptIsGone` needs the kept session's agent to have listed some session. Checked by: `testAnAgentThatListedNoSessionDoesNotEndTheKeptPick`. A Codex listing that times out takes 8 s, and the target waits for it only when the kept Codex list lacks the thread.
- Until the kept session is listed, or every client has answered afresh, no other session settles the target. Checked by: `testSendSettlesOnNothingElseUntilTheKeptPickIsListedOrEveryClientHasAnsweredAfresh`, `testAKeptPickSettlesASwappedBarWithoutShowingAnotherSessionFirst`.

**Late and concurrent answers**

- An opening reads the window once, at `beginDestinations`, so a pick that expires while the image is open still starts that image, and a Send of that image to it renews it. A Reply or a send elsewhere after the window ends it. Checked by: `testOnlyASendToAHandPickOrToTheKeptPickKeepsIt`.
- A send closes its opening, so no answer of the opening that set the kept pick reaches `destinationsAnswered` after it.
- A kept session that is still starting (a Continue last session or New session row) is not listed until its inbox is up, up to 45 s; an opening in that time finds it gone.

### ToolbarOffer (explicit, derived)

Owner: `ToolbarOffer.swift`. Tests: `ToolbarOfferTests.testEachOfferSaysWhatReturnAndCmdReturnDo`.

What the bar offers for the open image. It is computed from `Model` inputs and never stored. `AnnotationController.offerChanged` passes it to `editor.finishes`; the bar's `controls` and `offersTarget` read it.

**States**: `copy`, `choose`, `send(d)`, `reply(d)`.

**Transitions**

The offer is recomputed whenever `replyTo`, `listing` or `target` changes. `ToolbarOffer` reads `listing.list` as the destinations, `listing.complete` as `listed`, and `listing.startable`. First match wins:

| Condition | Offer |
|---|---|
| `replyTo` is set, and not (`listed`, Claude, and absent from the list) | `reply(replyTo)` |
| `target` is set | `send(target)` |
| `listed` and `startable` is not empty | `choose` |
| otherwise | `copy` |

**Invariants**

- Return never sends to a session Vignette picked (`ToolbarOffer.finishes`). Checked by: `ToolbarOfferTests.testEachOfferSaysWhatReturnAndCmdReturnDo`.

**Late and concurrent answers**

- None of its own. It follows `Model`.

### Send progress: sending, failure (implicit)

Owner: `Model.sending` (`AnnotatorToolbar.swift`), `failure`, `failures`. Tests: `EditorCoreSendTests`.

Tracks one Send press from the bar to the stored request. `sendDrawing` (`AppDelegate+Send.swift`) renders and submits.

**States**: idle (`sending == false`, `failure == nil`); sending; notSent (`failure != nil`). A press's destination travels with it, in `EditorCore.Input.send` and `Effect.send(_:to:)`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| idle or notSent | press (button, Cmd+Return, Space on the action, field Return: `AnnotatorToolbar.swift`) | — | `onSend` calls `editor.send(to:)` (`AnnotationController.swift`). The core emits `.send(drawing, to: destination)` only while open, and a key's send with `to: nil`. `editor.onSend` uses that destination, else `offer.destination`, then `sendDrawing` sets `sending = true`, which clears `failure` ([toolbar-1](plausible-findings-run-to-toolbar.md#toolbar-1)) |
| idle or notSent | Return, no message, drawing as sent | as Done (`nothingToReply`) | — |
| sending | press | refused at every entry (`!model.sending` in `sendDrawing`) | — |
| sending | render fails, or `requests.send` throws | notSent: `sending = false`, `failure = reason`, `failures += 1` (`sendFailed`) | — |
| sending | render answers for an ended opening | dropped by the `opening` guard; `sending` untouched | next `prepare` resets |
| sending | request stored | stays sending until the bar leaves | next `prepare` calls `resetSend` (from `AnnotationController.swift`) |

**Invariants**

- `sending` stays on from the press until the bar has left, and `prepare` resets it. Checked by: `prepare` at `AnnotationController.swift`.
- A press the editor ignored leaves nothing for the next image. Held by the destination travelling in the input, with no flag outside the core; `EditorCoreSendTests` checks the core's side only ([toolbar-1](plausible-findings-run-to-toolbar.md#toolbar-1)).

**Late and concurrent answers**

- A rendering that answers after its opening ended, and a second press while sending: as above.
- Esc during the render: the opening ends, so the same guard drops the answer.

### Bar presence: shown, hideGeneration, sliding (implicit)

Owner: `AnnotatorToolbar.swift` (`hideGeneration`). Tests: none (needs `NSPanel`).

Whether the bar's panel is on screen, and when it fades out. `prepare` calls `place`, `AnnotationController.show` calls `show`, and `hideWindows` calls `hideSoon`.

**States**: the properties `Model.shown`, `sliding`, `placedBelow`, `slideX` and `slideY`, `hideGeneration`, and `panel.isVisible`. Together:
- absent: panel out, `shown == false`.
- entering: panel in, `shown` false until the next turn.
- up: `shown == true`.
- fading: `shown == false`, panel still in, orderOut pending 0.2 s (scaled by the motion setting).
- sliding: `sliding == true`, springs move the panel.

**Transitions**

Events: `place(below:gap:)`, `show()`, `hideSoon()`, `hide()`, `refit()` (from SwiftUI `onWidth`).

| State | Event | Next state | Effects |
|---|---|---|---|
| absent | `place` | absent | frame set; panel not shown |
| any | `place` | — | generation +1, `position(slide: true)` (cancels a pending `hide` or orderOut) |
| any | `show` | up (`shown = true` a turn later) | generation +1; panel ordered front |
| up | `hideSoon` alone | fading, next turn | `hide()` runs if the generation is unchanged |
| up | `hideSoon` then `place` in the same turn | up | `place` bumps the generation, so `hide` never runs (a swap) |
| fading | `place` | fading; `shown` stays false | cancels the orderOut; content stays hidden until `show()` |
| fading | `show` | up | cancels the orderOut |
| fading | timer, generation unchanged | absent | `orderOut` |
| up or fading | `refit` | — | next turn `position(slide: sliding)` if `shown || !panel.isVisible`; a bar on its way out is left alone |

**Invariants**

- A swap does not hide the next image's bar: `hideSoon` is queued before the next `place` in the same turn. Checked by: comments; nothing else. If the order flipped, the bar would be absent during the next flight, not stuck, since `show()` orders it in again.

**Late and concurrent answers**

- A deferred `hide` or orderOut after a newer event: dropped by the generation compare.
- `show()`'s deferred `shown = true` has no generation check. It is safe today because `hide()` can only run from a `hideSoon` queued after `show()`.

### Keyboard focus: focus, keyed, tookKeysOnOpen, toolLetter, heldLetter (implicit)

Owner: `Model.focus` (`AnnotatorToolbar.swift`), `keyed`, `tookKeysOnOpen`, `toolLetter`, `messageAsks`; `AnnotatorToolbar.heldLetter`; `ToolbarPanel.pressOnField` (`AnnotatorToolbar+Panel.swift`), `wantsKeys`, `caretToEnd`. Tests: none for the panel; `HeldToolLetter` below has one.

Decides whether the bar's panel or the editor has the keys. Only a press on the message field or an explicit ask lets the panel take them.

**States**: the panel is key or not (`panel.isKeyWindow`, mirrored by `keyed` through `didBecomeKey` and `didResignKey`). `focus` is nil, a tool, copy, the target, an action, or `.message`. `tookKeysOnOpen` says the field got the keys without a press.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `didBecomeKey` | `keyed = true`, `focus = .message` | whatever made the panel key |
| any | `didResignKey` | `keyed = false`, `tookKeysOnOpen = false`, `caretToEnd = false`; `focus = nil` if it was `.message` | `makeFirstResponder(nil)` |
| any | `begin` | `imageNumber += 1`, `focus = nil`, `tookKeysOnOpen = false`, `toolLetter` reset | `keyed` and `panel.isKeyWindow` untouched; `message` stays as `restore` set it when the image opened |
| any | `restore(message:)` (`AnnotationController.open`) | `message` and `messageOnOpen` set to the words stored for the image, or "" | the controller's `storedWords` set, so they are not written back |
| bar shown, a field on it | a pick in the target's menu (`typeAfterPick`, `AnnotatorToolbar+Focus.swift`) | `tookKeysOnOpen = false` (`Model.pick`); `focus = .message` | the controller's `editorUntouched = false` first; the panel takes the keys |
| panel not key | `typeOnOpen` (`AnnotatorToolbar+Focus.swift`, from `offerTyping`) | `focus = .message`, `tookKeysOnOpen = true` if the panel became key, else `focus = nil` | false when it did not: logs, and `editorUntouched` stays, so a later offer tries again |
| panel already key | `typeOnOpen` | — | refused |
| panel key | Cmd+W, Cmd+Plus, Cmd+Minus, Cmd+0; Cmd+C in an empty field, nothing being composed; Cmd+Z and Shift+Cmd+Z, nothing being composed | — | `FieldCommand`: the window's close, the zoom, the drawing copied, or the editor's undo and redo; other Command keys go to the field |
| any | Tab, Shift+Tab (`move`); Space (`activate`); M or P (`focusMessage`); press (`onPress`); `keyDown` | `focus` moves | — |

**Invariants**

- The panel can be key only by `canBecomeKey = pressOnField || wantsKeys || isKeyWindow` (`AnnotatorToolbar+Panel.swift`). Checked by: the guard there. `resignKey` clears `pressOnField`, so after a resign only a press or `takeKeys` makes it key.

**Late and concurrent answers**

- `offerTyping` gives the field the keys at most once per image (`editorUntouched`), and not after a pick. `tookKeysOnOpen` is cleared on resign and by a pick.

### HeldToolLetter (explicit)

Owner: `HeldToolLetter.swift`. Tests: `ToolbarOfferTests.testAToolLetterTypedFirstPicksItsToolUntilAWordShowsItBeganOne`.

Holds a tool letter typed first on an untouched field, until the next key shows whether it began a word. The editor's `startsNote` uses the same value after a box or arrow ([editor-core](editor-core.md#heldkey-implicit)), so both read a key's character the same way (`HeldToolLetter.character`).

**States**: `toolBefore` is nil (nothing held) or the tool that was active before the held letter.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| nil | `key`, an eligible letter on an untouched field | `toolBefore` set | the key is kept in `heldLetter` |
| held | `key`, a repeat | held | swallow |
| held | `key`, another character | nil | restore the tool, replay the held key into the field |
| held | `key`, no character: Option, Command or Control held, or a key that types none | nil | pass: the held key is dropped and the tool stays |
| held | `keepTool()` (press, resign) | nil | the tool stays |

**Invariants**

- `heldLetter` (toolbar) and `toolBefore` (model) agree where it matters. `begin` resets `toolLetter` but not `heldLetter` (`AnnotatorToolbar.swift`), and a stale `heldLetter` is read only after a `hold` sets it again. Checked by: `testAToolLetterTypedFirstPicksItsToolUntilAWordShowsItBeganOne`.

**Late and concurrent answers**

- None.
