# The editor and drawings: the core

The editor is a pure reducer (`EditorCore`) driven by a view (`EditorView`) that turns events into inputs and runs the effects it returns. Drawings are stored one file per screenshot by `Drawings`, and the clipboard and drag paths render them through `RenderingQueue`.

### EditorCore (explicit)

Owner: `EditorCore.swift`, reducer `reduce`. Tests: `EditorCoreSequenceTests.testRandomSequencesKeepTheInvariants` (drives `checkShape`, `checkUndo`, `apply`), `EditorCoreTests`, `EditorCoreOpeningTests`, `EditorCoreTextEditingTests`.

The editor's whole logic: gestures, typing, selection, undo, the 0.3 s save timer, and agent marks joining. `EditorView` sends one `Input` per event and runs the returned `Effect`s in order. A drawing is a screenshot's marks (`Drawing.swift`); a hand-over gives the host the drawing to store.

**States**: the properties that together form the state.

- `isOpen` (`EditorCore.swift`): false until `open`, false again after `park`.
- `gesture: Gesture?` with `Phase`: `pressed`, `drawing(id)`, `placing(pin id)`, `wrapping`, `brushing`, `moving(originals:copies:)`, `resizing(id, pos)`, `draggingEnd(id, kind)`, `bending(id)`. A press's target can be a pin or a cluster as well as a mark.
- `typing: Typing?` (type): the text mark being typed.
- `edit: MarkEdit?`: the open undo step. Set while a gesture has changed marks, or while typing.
- `undoSteps`, `redoSteps` (`[HistoryStep]`, each a drawing step, its marks by index and its pins by `id`, or a message step, with a `StepName`), `message`, `typingMessage` (the top step is the message typing that runs on), `nudging`, `heldArrows`.
- `noteMark: NoteMark?` (type): see HeldKey below. `holdsKey` is `noteMark?.toolBefore != nil`.
- `unsaved`: the drawing changed since the last hand-over.
- `drawing.pins` and `drawing.nextPin`: the Comment tool adds a pin with number 0; its first comment numbers it from `nextPin`, which never goes down. A pin with number 0 is in no hand-over and no undo step.
- `composer: Composer?` (`EditorCore+Pins.swift`): the pin whose popover is open, the comment it edits or nil for a new one, and the draft. While it is open, `edit` is open on that pin. `reportedComposer` is what `settle()` last told the view.
- `fitZoom`, `visible`: from `viewChanged`, for a teardrop's size and Shift+Return's place.
- `selection`, `hover`, `tool`, `zoom`, `style`, `metrics`, `markStyle`.
- `finishes`: what Return and Cmd+Return do. The host sets it from the toolbar's offer.
- `reportedTool`, `reportedCursor`, `announcedSelection`: what `settle()` last told the view.

**Inputs** (`Input`) and who sends them (`EditorView` unless noted): `open` (`EditorView.swift`); `pointerMoved`, `pointerExited`, `pointerPressed`, `pointerDragged`, `pointerReleased` (mouse handlers `EditorView.swift`, `take`, `zoomCameToRest`); `modifiersChanged` (`flagsChanged`); `keyDown`, `keyUp` (`performKeyEquivalent`, `typingKey`, `releaseHeldArrows`); `setTool` (toolbar, `AnnotationController.swift`); `enterCanvas`; `zoomChanged` (`pictureMoved`, `open`); `tweaksChanged`, `rescaled` (`applyTweaks`); `typingChanged`, `typingEnded` (`TypingField.onChange` and `onResign`); `timerFired` (`scheduleHandOver`); `paste` (`.readClipboard` effect, drop); `agentMarks` (`EditorView.join`, from `Drawings.add`); `done`, `send` (toolbar); `park` (`EditorView.park`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| not open | any but `open` | — | Ignored. |
| any | `open(d, message:, history:)` | open, idle (every other property reset, `zoom` and `finishes` kept) | If `typing != nil`: `.endTyping`. Unsaved edits, `gesture`, `noteMark`, `heldArrows` are dropped; `undoSteps`, `redoSteps` and `message` are the ones given, which the host read from the file. `.cancelTimer`, `.tool`. Refused, `isOpen` stays false, when the pixels are 0 or `pointScale` is invalid. **(fixed)** `finishes` is kept ([editor-1](findings.md#editor-1)). |
| open, idle | `pointerPressed` | `gesture = pressed`, or typing begins, or a zoom request | `pressed` ends typing first if any; the press target decides. |
| `pressed` | drag past the drag distance | `drawing`, `moving`, `resizing`, `draggingEnd`, `bending`, `wrapping` or `brushing` | `dragPhase` picks the phase; `startDrag` opens `edit` for the phases that change marks. |
| any gesture | `pointerDragged`, `modifiersChanged` | same gesture, redrawn | `update` redraws from the press to the pointer. |
| any gesture | `pointerReleased` | `gesture = nil` | `released`: a big-enough `drawing` commits, otherwise reverts; moves, resizes, end drags and bends commit. A commit calls `changed()`. A click marked `.type` begins typing. |
| any gesture | `pointerMoved` | `gesture = nil` | `cancelGesture`: the release was lost. Reverts the edit, restores `selectionBefore`. |
| any gesture | `pointerPressed` | new press | `cancelGesture` first. |
| any gesture | `keyDown` | `gesture = nil` unless the key is a zoom key | A zoom key is forwarded. Any other key calls `cancelGesture` and may pick a tool. Cmd+Z here cancels and undoes nothing more. |
| any gesture | `setTool`, `enterCanvas`, `paste` | `gesture = nil` | `cancelGesture` first. |
| any gesture | `done`, `send`, `park` | `gesture = nil` | `finishForHost` releases it as if let go (`released(nil)`). A `pressed` or `wrapping` gesture draws nothing. |
| typing | `typingChanged(s)` | typing | `typed` caps the text, regrows the tag, replaces the words, calls `changed()`. |
| typing | `typingEnded` | not typing | `endTyping`: `.endTyping`. An agent's note turns the person's if its words changed. Anchored text is re-held. A blank text is removed. `commitEdit`. |
| typing | `keyDown` | typing, or not typing | Only Esc, Return (no Shift or Option) and zoom keys reach the core. Esc ends typing. Return ends typing; with Cmd it also runs `finish(finishes.commandReturn)`. The view offers keys only through `takesKey` (`EditorView.swift`) and never during a composition. |
| typing | `pointerPressed` | typing or not | On the text being typed: `.passPressToText` or select all. On another text: `endTyping`, then `beginTyping`. Elsewhere: `endTyping`, then a normal press. |
| typing | `setTool`, `enterCanvas`, `paste`, `done`, `send`, `park` | not typing | `endTyping` first. |
| typing | `agentMarks` | typing | `join` is its own undo step beside the open typing edit. The hand-over carries the typed text unless it is blank. |
| open | `timerFired` | open | If a gesture is held: `.scheduleTimer` again. Else if `unsaved`: `.handOver(drawingForHost)` and `unsaved = false`. |
| open | `agentMarks` | open | `join`: marks placed and added as one step, then `handOver()` at once. `unsaved = false`. `noteMark` cleared (`keepsNoteMark` is false for it). |
| open | `rescaled(p, m)` | open | No change if equal. Sets `drawing.pointScale` and `markScale`; `changed()` when marks exist. Gesture and typing continue. |
| open | `tweaksChanged` | open | Replaces `style`, `metrics`, `markStyle` only. |
| open | `done`, `send` | open | `finishForHost`, then `.done(drawingForHost)` or `.send(drawingForHost)`. Does not cancel the timer, clear `unsaved`, or close: the host parks later. |
| open | `park` | not open | `finishForHost`, `.cancelTimer`, `.handOver(drawingForHost)`, `unsaved = false`, `isOpen = false`; hover, pointer and `heldArrows` cleared. `noteMark`, `undoSteps`, `selection`, `finishes` stay. |
| open, idle | `keyDown` Cmd+Z, Shift+Cmd+Z | open | `undo` or `redo`; `.announce("Undo <name>")` in place of the selection's. A drawing step sets the marks and the pins it touched, pins in number order, and calls `changed()`; a message step sets `message` and emits `.message(words)`. |
| open | `messageChanged(words, name)` | open | Nothing when `words == message`. Typing while `typingMessage` replaces the top step's `after`; anything else pushes a message step, which clears redo. No hand-over: the host stores the message. |
| open | `messageTypingEnded` | open | `typingMessage = false`, so the next typing in the field is a new step. |
| `pressed` on empty space, Comment tool | release | composer open on a new pin | `placePin`: number 0, selected, `edit` opened. Beeps at 99 pins. |
| `pressed` on empty space, Comment tool | drag past the drag distance | `placing(id)` | `placeArea` on each drag; the release keeps it as an area, or a point when smaller than the smallest rectangle, and opens the composer. Ended without a release, the edit reverts. |
| `pressed` on a cluster | release | open | `.showCluster(ids, at:)`; a row sends `composer(.open(id))`. |
| open | double-click a pin, `composer(.open)`, Shift or Option+Return on a lone selected pin | composer open | `openComposer` closes another open one first. |
| composer open | `composer(.post)` | composer open, empty, or closed | A new comment is a `Comment` step, an edited one `Typing`, an emptied one `Delete`; the last comment's removal deletes the pin and closes. Return with nothing typed closes. Nothing changed, nothing is committed. |
| composer open | `composer(.close)`, a press, a tool, Cmd+Z, `done`, `send`, `park` | composer closed | `closeComposer` posts the draft, then reverts a pin still at number 0. |
| composer open | `composer(.finish)` | composer closed | `closeComposer`, then `finish(finishes.commandReturn)`. |
| open, idle | `keyDown` Esc | open | `.close`. The host decides. |
| open, idle | `keyDown` Return | open | `finish(returnKey or commandReturn)`. |
| open, idle | `keyDown` character right after a box or arrow | see HeldKey | `startsNote`. |

**Invariants**

- No mark lies outside the image, ids are unique, selection and hover name live marks, `typing` names a text mark, and a blank text exists only while typed. Checked by: `EditorCoreSequenceTests.checkShape`.
- One Cmd+Z undoes exactly one step and restores marks and selection. Redo mirrors it. Esc in a gesture restores the drawing exactly. A change that leaves the marks as they were adds no step. Checked by: `EditorCoreSequenceTests.checkUndo`, `play`.
- Agent marks joined mid-gesture or mid-typing are their own undo step. Checked by: `checkUndo` (`.agentMarks` branch).
- Every handed-over drawing re-reads through the file validator. Checked by: `apply` (`Self.invalid`).
- `park` hands over and closes. Checked by: `apply` (`.park` branch).
- `gesture` and `typing` are never both non-nil. Every writer of `typing` runs after the gesture is cancelled or cleared. Checked by: nothing.
- `edit != nil` exactly while a changing gesture or a typing session is open. Checked by: nothing.
- `unsaved` implies a `.scheduleTimer` was emitted since the last `.handOver` or `.cancelTimer`: only `changed()` sets `unsaved`, and it emits `.scheduleTimer` in the same call. Checked by: nothing; the sequence test never compares hand-over payloads with `drawingForHost`.
- `finishes` is the host's, and opening an image leaves it alone (a code comment says so). Checked by: `EditorCoreOpeningTests.testTheNextImageFinishesWithWhatTheBarStillOffers` ([editor-1](findings.md#editor-1))
- A held arrow key is cleared by `park` and by the stale-key guard. Checked by: nothing.
- Any new undo step clears the redo stack, an agent push and a message step included (`push`), so agent marks arriving after Cmd+Z drop the redo history. Checked by: `EditorCoreTests.testTheMessageFieldsTypingIsOneStepInOrderWithTheMarksAndUndoPutsItsWordsBack` for a message step.

**Late and concurrent answers**

- Any input after `park` or before `open`: dropped by `isOpen`.
- The 0.3 s save firing after `park`: `park` emits `.cancelTimer` and sets `unsaved = false`; a late `timerFired` is dropped by `isOpen`.
- The save firing after another image opens: `.cancelTimer` and `EditorView.stopTimers()` (`EditorView.swift`).
- The save firing while a button is held: `timerFired` re-arms; `drawingForHost` shows the gesture's marks reverted.
- A text with no words is never handed over.
- A lost release: a move with no button down cancels the gesture; `zoomCameToRest` sends a move only with no button down (`EditorView.swift`).
- Agent marks arriving mid-gesture survive Esc: `reverted` re-places only the touched marks (`EditorHistory.swift`).
- `step` saves and restores the open edit, so a join does not end a gesture's or typing's edit.
- `open` on a core that is still open drops its unsaved edits, gesture and typing, and replaces its undo history with the one given. Nothing guards it. Every `prepare` is preceded by `park()` or `abandon()` today (`AnnotationController.swift`).

### HeldKey (implicit)

Owner: `EditorCore.startsNote` (`EditorCore.swift`), which asks `HeldToolLetter` about each key while a box or arrow is armed, `holdsKey`, `EditorView.heldKeys` (`EditorView.swift`). Tests: `EditorCoreHeldLetterTests.testAToolKeyRightAfterABoxPicksItsToolUnlessACharacterFollows`, `EditorCoreTests.testACharacterTypedRightAfterABoxStartsANoteBesideIt`.

A tool key pressed right after a box or arrow is drawn may be the first letter of a note. The core switches the tool at once, and the view holds the key event until the next key shows whether the person is typing.

**States**: `noteMark` and `noteMark.toolLetter.toolBefore` in the core; `heldKeys: [NSEvent]` in the view.

- None: `noteMark == nil`.
- Armed: `noteMark != nil`, `toolBefore == nil`. Set in `released` when a drawn box or arrow commits by a real release.
- Held: `toolBefore != nil`. The tool is already the pressed key's tool, and the view holds that key's event.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| Armed | tool character, first press | Held | `tool = picked`, `.holdKey`; the view appends the event. |
| Armed | non-space character that is not a tool | None | `newNote(for:)`, `.passKeysToText` (no held keys to replay). |
| Armed | whitespace | None | Falls through; `noteMark = nil`. |
| Armed | repeat | None | Falls through and clears. |
| Held | repeat | Held | Taken. |
| Held | a character with no modifier but Shift | None | `tool = toolBefore`, `newNote`, `.passKeysToText` replays `heldKeys` plus the event into the text view (`EditorView.swift`). |
| Held | any other key: Option, Command or Control held, or a key that types no character | None | `HeldToolLetter` answers `pass`: the tool stays as picked and no note starts, as in the message field. |
| Held | pointer move, key up, modifiers, zoom, tweaks, rescale, timer | Held | — (`keepsNoteMark`). |
| Armed or Held | any other input (press, `setTool`, typing, `paste`, `agentMarks`, `done`, `park`, undo key) | None | `tool` stays as picked. `EditorView.handle` clears `heldKeys` when `!core.holdsKey`. |
| Held | `park` | Held | `park` does not clear `noteMark`; `heldKeys` stay until the next `open`. Harmless. |

**Invariants**

- `holdsKey` implies the view holds at least one event. Only `keyDown(with:)` passes an event (`.holdKey` ignores nil, `EditorView.swift`), and a key with Option, Command or Control has no character for `HeldToolLetter`, so it never holds. Checked by: nothing.
- A key held for good, with no further key or press, leaves the tool switched. That is the design (`HeldToolLetter.swift`).

**Late and concurrent answers**

- `newNote` can fail to place (`placed` is nil): `.passKeysToText` then finds no `typingField` and drops the keys (`EditorView.swift`); `handle` clears `heldKeys`.

### HeldToolLetter (explicit)

Owner: `HeldToolLetter.swift`. Tests: `ToolbarOfferTests` (not covered by this area; [the toolbar section](toolbar.md#heldtoolletter-explicit) owns the field's use).

The hold itself, written once: the editor's `startsNote` asks it while a box or arrow is armed, and the toolbar's message field while the field is untouched. What arms each stays with its owner. State: `toolBefore: Tool?` (`HeldToolLetter.swift`). `key(...)` returns `hold`, `type(restoring:)`, `pass` or `swallow`. `keepTool()` runs on a press or lost keys. `Model.begin` resets it (`AnnotatorToolbar.swift`).
