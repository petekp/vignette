# The editor and drawings: the core

The editor is a pure reducer (`EditorCore`) driven by a view (`EditorView`) that turns events into inputs and runs the effects it returns. Drawings are stored one file per screenshot by `Drawings`, and the clipboard and drag paths render them through `RenderingQueue`.

### EditorCore (explicit)

Owner: `EditorCore.swift:12`, reducer `reduce` at `EditorCore.swift:477`. Tests: `EditorCoreSequenceTests.testRandomSequencesKeepTheInvariants` (drives `checkShape`, `checkUndo`, `apply`), `EditorCoreTests`, `EditorCoreOpeningTests`, `EditorCoreTextEditingTests`.

The editor's whole logic: gestures, typing, selection, undo, the 0.3 s save timer, and agent marks joining. `EditorView` sends one `Input` per event and runs the returned `Effect`s in order. A drawing is a screenshot's marks (`Drawing.swift`); a hand-over gives the host the drawing to store.

**States**: the properties that together form the state.

- `isOpen` (`EditorCore.swift:360`): false until `open`, false again after `park`.
- `gesture: Gesture?` (`:370`) with `Phase` (`:425`): `pressed`, `drawing(id)`, `wrapping`, `brushing`, `moving(originals:copies:)`, `resizing(id, pos)`, `draggingEnd(id, kind)`, `bending(id)`.
- `typing: Typing?` (`:372`, type at `:450`): the text mark being typed.
- `edit: MarkEdit?` (`:378`): the open undo step. Set while a gesture has changed marks, or while typing.
- `undoSteps`, `redoSteps` (`[HistoryStep]`, each a drawing step, its marks by index and its pins by `id`, or a message step, with a `StepName`), `message`, `typingMessage` (the top step is the message typing that runs on), `nudging`, `heldArrows`.
- `noteMark: NoteMark?` (`:385`, type at `:440`): see HeldKey below. `holdsKey` (`:448`) is `noteMark?.toolBefore != nil`.
- `unsaved` (`:387`): the drawing changed since the last hand-over.
- `drawing.pins` and `drawing.nextPin`: no input adds, moves or deletes a pin yet, and only a drawing step's undo or redo changes `pins`. `nextPin` never goes down.
- `selection`, `hover`, `tool`, `zoom`, `style`, `metrics`, `markStyle`.
- `finishes` (`:368`): what Return and Cmd+Return do. The host sets it from the toolbar's offer.
- `reportedTool`, `reportedCursor`, `announcedSelection`: what `settle()` (`:549`) last told the view.

**Inputs** (`Input`, `:51`) and who sends them (`EditorView` unless noted): `open` (`EditorView.swift:146`); `pointerMoved`, `pointerExited`, `pointerPressed`, `pointerDragged`, `pointerReleased` (mouse handlers `EditorView.swift:658-731`, `take` `:682`, `zoomCameToRest` `:422`); `modifiersChanged` (`flagsChanged` `:578`); `keyDown`, `keyUp` (`:565`, `:573`, `performKeyEquivalent` `:584`, `typingKey` `:555`, `releaseHeldArrows` `:639`); `setTool` (toolbar, `AnnotationController.swift:90`); `enterCanvas` (`:199`); `zoomChanged` (`pictureMoved` `:411`, `open` `:152`); `tweaksChanged`, `rescaled` (`applyTweaks` `:226-228`); `typingChanged`, `typingEnded` (`TypingField.onChange` and `onResign`, `:452-457`); `timerFired` (`scheduleHandOver` `:314`); `paste` (`.readClipboard` effect `:295`, drop `:831`); `agentMarks` (`EditorView.join` `:858`, from `Drawings.add`); `done`, `send` (toolbar); `park` (`EditorView.park` `:162`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| not open | any but `open` | — | Ignored (`:481`). |
| any | `open(d, message:, history:)` | open, idle (every other property reset, `zoom` and `finishes` kept) | If `typing != nil`: `.endTyping`. Unsaved edits, `gesture`, `noteMark`, `heldArrows` are dropped; `undoSteps`, `redoSteps` and `message` are the ones given, which the host read from the file. `.cancelTimer`, `.tool`. Refused, `isOpen` stays false, when the pixels are 0 or `pointScale` is invalid (`:580`). **(fixed)** `finishes` is kept ([editor-1](findings.md#editor-1)). |
| open, idle | `pointerPressed` | `gesture = pressed`, or typing begins, or a zoom request | `pressed` (`:733`) ends typing first if any; the press target decides. |
| `pressed` | drag past the drag distance | `drawing`, `moving`, `resizing`, `draggingEnd`, `bending`, `wrapping` or `brushing` | `dragPhase` (`:818`) picks the phase; `startDrag` (`:842`) opens `edit` for the phases that change marks. |
| any gesture | `pointerDragged`, `modifiersChanged` | same gesture, redrawn | `update` (`:868`) redraws from the press to the pointer. |
| any gesture | `pointerReleased` | `gesture = nil` | `released` (`:928`): a big-enough `drawing` commits, otherwise reverts; moves, resizes, end drags and bends commit. A commit calls `changed()`. A click marked `.type` begins typing. |
| any gesture | `pointerMoved` | `gesture = nil` | `cancelGesture` (`:728`): the release was lost. Reverts the edit, restores `selectionBefore`. |
| any gesture | `pointerPressed` | new press | `cancelGesture` (`:734`) first. |
| any gesture | `keyDown` | `gesture = nil` unless the key is a zoom key | A zoom key is forwarded. Any other key calls `cancelGesture` and may pick a tool (`:1322-1329`). Cmd+Z here cancels and undoes nothing more. |
| any gesture | `setTool`, `enterCanvas`, `paste` | `gesture = nil` | `cancelGesture` first. |
| any gesture | `done`, `send`, `park` | `gesture = nil` | `finishForHost` (`:597`) releases it as if let go (`released(nil)`). A `pressed` or `wrapping` gesture draws nothing. |
| typing | `typingChanged(s)` | typing | `typed` (`:1242`) caps the text, regrows the tag, replaces the words, calls `changed()`. |
| typing | `typingEnded` | not typing | `endTyping` (`:1258`): `.endTyping`. An agent's note turns the person's if its words changed. Anchored text is re-held. A blank text is removed. `commitEdit`. |
| typing | `keyDown` | typing, or not typing | Only Esc, Return (no Shift or Option) and zoom keys reach the core. Esc ends typing. Return ends typing; with Cmd it also runs `finish(finishes.commandReturn)` (`:1310-1320`). The view offers keys only through `takesKey` (`EditorView.swift:1185`) and never during a composition. |
| typing | `pointerPressed` | typing or not | On the text being typed: `.passPressToText` or select all. On another text: `endTyping`, then `beginTyping`. Elsewhere: `endTyping`, then a normal press. |
| typing | `setTool`, `enterCanvas`, `paste`, `done`, `send`, `park` | not typing | `endTyping` first. |
| typing | `agentMarks` | typing | `join` (`:1580`) is its own undo step beside the open typing edit. The hand-over carries the typed text unless it is blank. |
| open | `timerFired` | open | If a gesture is held: `.scheduleTimer` again (`:620`). Else if `unsaved`: `.handOver(drawingForHost)` and `unsaved = false`. |
| open | `agentMarks` | open | `join`: marks placed and added as one step, then `handOver()` at once (`:1586`). `unsaved = false`. `noteMark` cleared (`keepsNoteMark` is false for it, `:1631`). |
| open | `rescaled(p, m)` | open | No change if equal (`:528`). Sets `drawing.pointScale` and `markScale`; `changed()` when marks exist. Gesture and typing continue. |
| open | `tweaksChanged` | open | Replaces `style`, `metrics`, `markStyle` only. |
| open | `done`, `send` | open | `finishForHost`, then `.done(drawingForHost)` or `.send(drawingForHost)`. Does not cancel the timer, clear `unsaved`, or close: the host parks later. |
| open | `park` | not open | `finishForHost`, `.cancelTimer`, `.handOver(drawingForHost)`, `unsaved = false`, `isOpen = false`; hover, pointer and `heldArrows` cleared (`:607-616`). `noteMark`, `undoSteps`, `selection`, `finishes` stay. |
| open, idle | `keyDown` Cmd+Z, Shift+Cmd+Z | open | `undo` or `redo`; `.announce("Undo <name>")` in place of the selection's. A drawing step sets the marks and the pins it touched, pins in number order, and calls `changed()`; a message step sets `message` and emits `.message(words)`. |
| open | `messageChanged(words, name)` | open | Nothing when `words == message`. Typing while `typingMessage` replaces the top step's `after`; anything else pushes a message step, which clears redo. No hand-over: the host stores the message. |
| open | `messageTypingEnded` | open | `typingMessage = false`, so the next typing in the field is a new step. |
| open, idle | `keyDown` Esc | open | `.close`. The host decides. |
| open, idle | `keyDown` Return | open | `finish(returnKey or commandReturn)`. |
| open, idle | `keyDown` character right after a box or arrow | see HeldKey | `startsNote` (`:1388`). |

**Invariants**

- No mark lies outside the image, ids are unique, selection and hover name live marks, `typing` names a text mark, and a blank text exists only while typed. Checked by: `EditorCoreSequenceTests.checkShape`.
- One Cmd+Z undoes exactly one step and restores marks and selection. Redo mirrors it. Esc in a gesture restores the drawing exactly. A change that leaves the marks as they were adds no step. Checked by: `EditorCoreSequenceTests.checkUndo`, `play`.
- Agent marks joined mid-gesture or mid-typing are their own undo step. Checked by: `checkUndo` (`.agentMarks` branch).
- Every handed-over drawing re-reads through the file validator. Checked by: `apply` (`Self.invalid`).
- `park` hands over and closes. Checked by: `apply` (`.park` branch).
- `gesture` and `typing` are never both non-nil. Every writer of `typing` runs after the gesture is cancelled or cleared. Checked by: nothing.
- `edit != nil` exactly while a changing gesture or a typing session is open. Checked by: nothing.
- `unsaved` implies a `.scheduleTimer` was emitted since the last `.handOver` or `.cancelTimer`: only `changed()` sets `unsaved`, and it emits `.scheduleTimer` in the same call (`:641`). Checked by: nothing; the sequence test never compares hand-over payloads with `drawingForHost`.
- `finishes` is the host's, and opening an image leaves it alone (comment at `:367`). Checked by: `EditorCoreOpeningTests.testTheNextImageFinishesWithWhatTheBarStillOffers` ([editor-1](findings.md#editor-1))
- A held arrow key is cleared by `park` and by the stale-key guard (`:1335`). Checked by: nothing.
- Any new undo step clears the redo stack, an agent push and a message step included (`push`), so agent marks arriving after Cmd+Z drop the redo history. Checked by: `EditorCoreTests.testTheMessageFieldsTypingIsOneStepInOrderWithTheMarksAndUndoPutsItsWordsBack` for a message step.

**Late and concurrent answers**

- Any input after `park` or before `open`: dropped by `isOpen`, `:481`.
- The 0.3 s save firing after `park`: `park` emits `.cancelTimer` (`:609`) and sets `unsaved = false` (`:611`); a late `timerFired` is dropped by `isOpen`.
- The save firing after another image opens: `.cancelTimer` (`:591`) and `EditorView.stopTimers()` (`EditorView.swift:137`).
- The save firing while a button is held: `timerFired` re-arms (`:620`); `drawingForHost` shows the gesture's marks reverted (`:633`).
- A text with no words is never handed over (`:634`).
- A lost release: a move with no button down cancels the gesture (`:728`); `zoomCameToRest` sends a move only with no button down (`EditorView.swift:420`).
- Agent marks arriving mid-gesture survive Esc: `reverted` re-places only the touched marks (`EditorHistory.swift:42`).
- `step` saves and restores the open edit (`:674-680`), so a join does not end a gesture's or typing's edit.
- `open` on a core that is still open drops its unsaved edits, gesture and typing, and replaces its undo history with the one given (`:574-579`). Nothing guards it. Every `prepare` is preceded by `park()` or `abandon()` today (`AnnotationController.swift:464`, `:477`).

### HeldKey (implicit)

Owner: `EditorCore.startsNote` (`EditorCore.swift:1371`), which asks `HeldToolLetter` about each key while a box or arrow is armed, `holdsKey` (`:437`), `EditorView.heldKeys` (`EditorView.swift:104`). Tests: `EditorCoreHeldLetterTests.testAToolKeyRightAfterABoxPicksItsToolUnlessACharacterFollows`, `EditorCoreTests.testACharacterTypedRightAfterABoxStartsANoteBesideIt`.

A tool key pressed right after a box or arrow is drawn may be the first letter of a note. The core switches the tool at once, and the view holds the key event until the next key shows whether the person is typing.

**States**: `noteMark` and `noteMark.toolLetter.toolBefore` in the core; `heldKeys: [NSEvent]` in the view.

- None: `noteMark == nil`.
- Armed: `noteMark != nil`, `toolBefore == nil`. Set in `released` (`:1040`) when a drawn box or arrow commits by a real release.
- Held: `toolBefore != nil`. The tool is already the pressed key's tool, and the view holds that key's event.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| Armed | tool character, first press | Held | `tool = picked`, `.holdKey`; the view appends the event (`:1392-1396`). |
| Armed | non-space character that is not a tool | None | `newNote(for:)`, `.passKeysToText` (no held keys to replay). |
| Armed | whitespace | None | Falls through; `noteMark = nil` (`:1332`). |
| Armed | repeat | None | Falls through and clears. |
| Held | repeat | Held | Taken. |
| Held | a character with no modifier but Shift | None | `tool = toolBefore`, `newNote`, `.passKeysToText` replays `heldKeys` plus the event into the text view (`EditorView.swift:276-282`). |
| Held | any other key: Option, Command or Control held, or a key that types no character | None | `HeldToolLetter` answers `pass`: the tool stays as picked and no note starts, as in the message field. |
| Held | pointer move, key up, modifiers, zoom, tweaks, rescale, timer | Held | — (`keepsNoteMark`, `:1631`). |
| Armed or Held | any other input (press, `setTool`, typing, `paste`, `agentMarks`, `done`, `park`, undo key) | None | `tool` stays as picked. `EditorView.handle` clears `heldKeys` when `!core.holdsKey` (`:264`). |
| Held | `park` | Held | `park` does not clear `noteMark`; `heldKeys` stay until the next `open`. Harmless. |

**Invariants**

- `holdsKey` implies the view holds at least one event. Only `keyDown(with:)` passes an event (`.holdKey` ignores nil, `EditorView.swift:275`), and a key with Option, Command or Control has no character for `HeldToolLetter`, so it never holds. Checked by: nothing.
- A key held for good, with no further key or press, leaves the tool switched. That is the design (`HeldToolLetter.swift:3-6`).

**Late and concurrent answers**

- `newNote` can fail to place (`placed` is nil): `.passKeysToText` then finds no `typingField` and drops the keys (`EditorView.swift:278`); `handle` clears `heldKeys`.

### HeldToolLetter (explicit)

Owner: `HeldToolLetter.swift:7`. Tests: `ToolbarOfferTests` (not covered by this area; [the toolbar section](toolbar.md#heldtoolletter-explicit) owns the field's use).

The hold itself, written once: the editor's `startsNote` asks it while a box or arrow is armed, and the toolbar's message field while the field is untouched. What arms each stays with its owner. State: `toolBefore: Tool?` (`HeldToolLetter.swift:9`). `key(...)` returns `hold`, `type(restoring:)`, `pass` or `swallow`. `keepTool()` runs on a press or lost keys. `Model.begin` resets it (`AnnotatorToolbar.swift:144`).
