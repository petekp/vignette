# Vignette's state machines

These files map every state machine in the app: the reducers written as one, and the state spread
over flags, optionals, ids and timers that behaves as one. For each it gives the states, the
events, the transition table and the invariants, and where each invariant is checked. After the
machines, [Findings](state-machines/findings.md#findings) lists the invalid states and transitions the code can reach, with
the evidence for each, and [Issues](state-machines/issues.md#issues) groups the confirmed ones into fixes.

Keep them current. A change that adds a state, an event, a timer or a callback to one of these
machines updates its section in the same commit. A new finding goes in [Findings](state-machines/findings.md#findings) with
its evidence and status.

## Terms

- **State machine**: anything whose next behaviour depends on what happened before. Here that is
  either an **explicit** machine, a type with a `Phase` or `reduce(_:)`, or an **implicit** one:
  several properties that only make sense together, such as a flag, an optional and a timer.
- **Event**: one input to a machine, by its name in the code. A **late answer** is an event that
  answers an earlier effect, such as a park, a decode, a rendering or a session list, after the
  thing it was for has moved on.
- **Same-turn answer**: an effect answered inside the event that asked for it, in one run-loop
  turn. `EventHold` (`AnnotationRun.swift`) queues such an answer and runs it after the event
  being handled, so no event runs nested inside another.
- **Opening**: one screenshot's time in the annotator (`Opening`, `AnnotatorTransition.swift`).
  The run mints an id per opening and never reuses one, so an answer that names an old opening
  is recognised and dropped.
- **Invariant**: something that holds in every state the machine can reach. Each one names where
  it is checked: a test, a guard in the code, or nothing.
- **Reachable invalid state**: a state or transition that breaks an invariant, together with a
  concrete sequence of events that gets there in the shipped code.
- **Confirmed**: a reachable invalid state with a traced sequence (file and line), and a unit
  test that fails before the fix. **Plausible**: a traced sequence that no unit test can reach yet,
  or one with a step that could not be checked. Only confirmed findings are fixed.

## How to read a transition table

Rows are states, columns or the second cell are events, and each cell is `next state; effects`.
`—` means the event changes nothing in that state. A cell marked **(fixed)** names a row a fix
changed, and the finding that changed it.

This file is the index. Each file below is under `docs/state-machines/`; the table says which one holds a machine and which Swift types it maps. A new machine goes in the file for its area, with a row in the table. When no file fits, it gets a new file. A file stays under the size hook's 5,000 tokens, so a file that fills up is split between two machines.

## Index

| Machine | Swift types | File |
|---|---|---|
| AnnotatorTransition | `AnnotatorTransition` | [annotation-run](state-machines/annotation-run.md) |
| AnnotationRun | `AnnotationRun` | [annotation-run](state-machines/annotation-run.md) |
| EventHold | `EventHold` | [annotation-run](state-machines/annotation-run.md) |
| ThumbnailController, the run's effect layer | `ThumbnailController` | [annotation-run-effects](state-machines/annotation-run-effects.md) |
| AnnotationController session | `AnnotationController` | [annotation-run-effects](state-machines/annotation-run-effects.md) |
| TitleReveal | `TitleReveal` | [annotation-run-effects](state-machines/annotation-run-effects.md) |
| WindowRemoval | `WindowRemoval` | [annotation-run-effects](state-machines/annotation-run-effects.md) |
| OutsideClick | `OutsideClick` | [annotation-run-effects](state-machines/annotation-run-effects.md) |
| FocusReturn | `FocusReturn` | [annotation-run-effects](state-machines/annotation-run-effects.md) |
| TransitionLayer flights | `TransitionLayer` | [flights](state-machines/flights.md) |
| TransitionLayer panel and press | `TransitionLayer` | [flights](state-machines/flights.md) |
| FlightPress | `FlightPress` | [flights](state-machines/flights.md) |
| Tween | `Tween` | [flights](state-machines/flights.md) |
| AnnotatorZoom | `AnnotatorZoom` | [zoom-and-panels](state-machines/zoom-and-panels.md) |
| Zoom glue: `fitBeforeHide` and `hideWindows` | `AnnotationController` | [zoom-and-panels](state-machines/zoom-and-panels.md) |
| DimPanel | `DimPanel` | [zoom-and-panels](state-machines/zoom-and-panels.md) |
| BackdropPanel | `BackdropPanel` | [zoom-and-panels](state-machines/zoom-and-panels.md) |
| CornerPresentation | `CornerPresentation` | [corner](state-machines/corner.md) |
| CornerKeys window side | `CornerKeys` | [corner](state-machines/corner.md) |
| Panel visibility and dismissal in ThumbnailController | `ThumbnailController` | [corner](state-machines/corner.md) |
| Lone thumbnail timer, `leaveTimer` | `ThumbnailController` | [corner](state-machines/corner.md) |
| CardNotices and its posting timers | `CardNotices`, `StackModel`, `ThumbnailController` | [corner](state-machines/corner.md) |
| Stack selection, focus and hover | `StackModel` | [stack](state-machines/stack.md) |
| Stitch converge | `ThumbnailController` | [stack](state-machines/stack.md) |
| shiftUp and card entrance | `ThumbnailController` | [stack](state-machines/stack.md) |
| StackSweep | `StackSweep` | [stack](state-machines/stack.md) |
| HotKey | `HotKey` | [stack](state-machines/stack.md) |
| ModifierTap and KeyMonitors | `ModifierTap`, `KeyMonitors` | [stack](state-machines/stack.md) |
| StackSwipe | `StackSwipe` | [stack](state-machines/stack.md) |
| StackAreaReader | `StackAreaReader` | [stack](state-machines/stack.md) |
| OlderShots | `OlderShots`, `ThumbnailController` | [stack-column](state-machines/stack-column.md) |
| CardPictures | `CardPictures`, `ThumbnailController` | [stack-column](state-machines/stack-column.md) |
| CardColumn built cards | `CardColumn`, `StackModel`, `StackLayout` | [stack-column](state-machines/stack-column.md) |
| StackModel.liftFraction | `StackModel`, `ThumbnailController` | [stack-column](state-machines/stack-column.md) |
| StackModel.carried | `StackModel`, `ThumbnailController` | [stack-column](state-machines/stack-column.md) |
| EditorCore | `EditorCore` | [editor-core](state-machines/editor-core.md) |
| HeldKey | `EditorCore`, `EditorView` | [editor-core](state-machines/editor-core.md) |
| HeldToolLetter | `HeldToolLetter` | [editor-core](state-machines/editor-core.md) |
| EditorView session | `EditorView` | [editor-view-and-drawings](state-machines/editor-view-and-drawings.md) |
| MarkLayers text bitmap | `MarkLayers` | [editor-view-and-drawings](state-machines/editor-view-and-drawings.md) |
| TypingField | `TypingField` | [editor-view-and-drawings](state-machines/editor-view-and-drawings.md) |
| Drawings | `Drawings`, `DrawingStore` | [editor-view-and-drawings](state-machines/editor-view-and-drawings.md) |
| Rendering and clipboard promise | `RenderingQueue`, `Clipboard`, `DragItems` | [editor-view-and-drawings](state-machines/editor-view-and-drawings.md) |
| DragSourceView press | `DragSourceView`, `StackModel` | [editor-view-and-drawings](state-machines/editor-view-and-drawings.md) |
| AnnotatorToolbar.Model: target and offer | `AnnotatorToolbar.Model` | [toolbar](state-machines/toolbar.md) |
| ToolbarOffer | `ToolbarOffer` | [toolbar](state-machines/toolbar.md) |
| Send progress: sending, failure | `AnnotatorToolbar.Model` | [toolbar](state-machines/toolbar.md) |
| Bar presence: shown, hideGeneration, sliding | `AnnotatorToolbar.Model` | [toolbar](state-machines/toolbar.md) |
| Keyboard focus: focus, keyed, tookKeysOnOpen, toolLetter, heldLetter | `AnnotatorToolbar.Model` | [toolbar](state-machines/toolbar.md) |
| HeldToolLetter | `HeldToolLetter` | [toolbar](state-machines/toolbar.md) |
| Target menu pick | `AnnotatorToolbar.Model` | [toolbar](state-machines/toolbar.md) |
| SessionListing | `SessionListing` | [destinations](state-machines/destinations.md) |
| AppDelegate.refreshDestinations and listDestinations | `AppDelegate` | [destinations](state-machines/destinations.md) |
| DestinationChoice | `DestinationChoice` | [destinations](state-machines/destinations.md) |
| ClaudeCodeConnection: submit, preflight, start | `ClaudeCodeConnection`, `ClaudeInbox` | [destinations](state-machines/destinations.md) |
| HerdrLauncher.start | `HerdrLauncher` | [destinations](state-machines/destinations.md) |
| CodexConnection: discover and submit | `CodexConnection` | [destinations](state-machines/destinations.md) |
| AppServer.converse | `AppServer` | [destinations](state-machines/destinations.md) |
| AppServerSession | `AppServerSession` | [destinations](state-machines/destinations.md) |
| SendOverlay notice animation | `SendOverlay` | [destinations](state-machines/destinations.md) |
| Record.Status | `ScreenshotRequests`, `Record` | [requests-and-replies](state-machines/requests-and-replies.md) |
| SendGrace | `SendGrace` | [requests-and-replies](state-machines/requests-and-replies.md) |
| Send bookkeeping | `ScreenshotRequests`, `AppDelegate` | [requests-and-replies](state-machines/requests-and-replies.md) |
| Reply.Stage | `Reply` | [requests-and-replies](state-machines/requests-and-replies.md) |
| Reply import pipeline | `ScreenshotRequests` | [requests-and-replies](state-machines/requests-and-replies.md) |
| Clearing and cleanup | `ScreenshotRequests` | [screenshots-folder](state-machines/screenshots-folder.md) |
| Admission limit | `ScreenshotRequests` | [screenshots-folder](state-machines/screenshots-folder.md) |
| FolderWrites pending adds | `FolderWrites` | [screenshots-folder](state-machines/screenshots-folder.md) |
| FolderWrites held-back reports | `FolderWrites` | [screenshots-folder](state-machines/screenshots-folder.md) |
| ScreenshotWatcher | `ScreenshotWatcher` | [screenshots-folder](state-machines/screenshots-folder.md) |
| Thumbnailer | `Thumbnailer` | [screenshots-folder](state-machines/screenshots-folder.md) |
| CaptureOrigin | `CaptureOrigin` | [screenshots-folder](state-machines/screenshots-folder.md) |
| ReplyCommand and ReplyProtocol | `ReplyCommand`, `ReplyProtocol` | [screenshots-folder](state-machines/screenshots-folder.md) |
| SetupWindowController | `SetupWindowController` | [setup](state-machines/setup.md) |
| SetupModel | `SetupModel` | [setup](state-machines/setup.md) |
| SetupBanter | `SetupBanter` | [setup](state-machines/setup.md) |
| SetupInkPlayer and SetupInkGuide | `SetupInkPlayer`, `SetupInkGuide` | [setup](state-machines/setup.md) |
| MenuBarIntro | `MenuBarIntro` | [setup](state-machines/setup.md) |
| Accessibility.request | `Accessibility` | [setup](state-machines/setup.md) |
| ShortcutRecorderView | `ShortcutRecorderView` | [setup](state-machines/setup.md) |
| SettingsSync (explicit) and Settings | `SettingsSync`, `Settings` | [settings-and-launch](state-machines/settings-and-launch.md) |
| Apple screencapture reconcile | `Settings`, `AppleScreencapture` | [settings-and-launch](state-machines/settings-and-launch.md) |
| AgentPlugins | `AgentPlugins` | [settings-and-launch](state-machines/settings-and-launch.md) |
| AgentTools | `AgentTools` | [settings-and-launch](state-machines/settings-and-launch.md) |
| LoginItem | `LoginItem` | [settings-and-launch](state-machines/settings-and-launch.md) |
| Updater and the update dot | `Updater`, `AppDelegate` | [settings-and-launch](state-machines/settings-and-launch.md) |
| AppLocation | `AppLocation` | [settings-and-launch](state-machines/settings-and-launch.md) |
| Launch sequence | `AppDelegate` | [settings-and-launch](state-machines/settings-and-launch.md) |
| Hotkey press and hold pair | `AppDelegate` | [settings-and-launch](state-machines/settings-and-launch.md) |
| Stitch action | `AppDelegate` | [settings-and-launch](state-machines/settings-and-launch.md) |
| Setup Lab and Intro Lab | `SetupLab`, `IntroLab` | [settings-and-launch](state-machines/settings-and-launch.md) |
| HeldChord | `HeldChord` | [live-ink-inking](state-machines/live-ink-inking.md) |
| ModifierChord | `ModifierChord` | [live-ink-inking](state-machines/live-ink-inking.md) |
| LiveInk inking lifecycle | `LiveInk` | [live-ink-inking](state-machines/live-ink-inking.md) |
| LiveInk stroke | `LiveInk`, `LiveInkOverlay` | [live-ink-inking](state-machines/live-ink-inking.md) |
| LiveInkTap | `LiveInkTap` | [live-ink-inking](state-machines/live-ink-inking.md) |
| Overlay surfaces | `LiveInk`, `LiveInkOverlay` | [live-ink-surfaces-and-tours](state-machines/live-ink-surfaces-and-tours.md) |
| Window picker watch | `LiveInk` | [live-ink-surfaces-and-tours](state-machines/live-ink-surfaces-and-tours.md) |
| Menu hand-off: overMenus and LiveMenus | `LiveInk`, `LiveMenus` | [live-ink-surfaces-and-tours](state-machines/live-ink-surfaces-and-tours.md) |
| LiveEscape (explicit) and the Esc hotkey | `LiveEscape`, `LiveInk` | [live-ink-surfaces-and-tours](state-machines/live-ink-surfaces-and-tours.md) |
| FocusRun, the focus tour | `LiveInk` | [live-ink-surfaces-and-tours](state-machines/live-ink-surfaces-and-tours.md) |
| Steps tour | `LiveInk` | [live-ink-surfaces-and-tours](state-machines/live-ink-surfaces-and-tours.md) |
| LiveListening and the transcriber chain | `LiveListening`, `Microphone`, `AppleTranscriber` | [live-ink-surfaces-and-tours](state-machines/live-ink-surfaces-and-tours.md) |
| LiveWindows Tracked | `LiveWindows` | [live-ink-surfaces-and-tours](state-machines/live-ink-surfaces-and-tours.md) |
| LiveInk.setOn and the chord object | `LiveInk` | [live-ink-surfaces-and-tours](state-machines/live-ink-surfaces-and-tours.md) |
| LiveAsks | `LiveAsks`, `LiveInk` | [live-ink-asks](state-machines/live-ink-asks.md) |
| LiveInk ask glue | `LiveInk` | [live-ink-asks](state-machines/live-ink-asks.md) |
| LiveResponder | `LiveResponder` | [live-ink-asks](state-machines/live-ink-asks.md) |
| LiveResponders | `LiveResponders` | [live-ink-responders-and-notes](state-machines/live-ink-responders-and-notes.md) |
| ClaudeDriver | `ClaudeDriver` | [live-ink-responders-and-notes](state-machines/live-ink-responders-and-notes.md) |
| JSONLinesProcess | `JSONLinesProcess` | [live-ink-responders-and-notes](state-machines/live-ink-responders-and-notes.md) |
| CodexDriver and CodexRun | `CodexDriver`, `CodexRun` | [live-ink-responders-and-notes](state-machines/live-ink-responders-and-notes.md) |
| ResponderStatus | `ResponderStatus` | [live-ink-responders-and-notes](state-machines/live-ink-responders-and-notes.md) |
| CodexLogin | `CodexLogin` | [live-ink-responders-and-notes](state-machines/live-ink-responders-and-notes.md) |
| LiveNoteCards | `LiveNoteCards` | [live-ink-responders-and-notes](state-machines/live-ink-responders-and-notes.md) |
| NoteCardWait | `NoteCardWait` | [live-ink-responders-and-notes](state-machines/live-ink-responders-and-notes.md) |
| TurnWatch | `TurnWatch` | [live-ink-responders-and-notes](state-machines/live-ink-responders-and-notes.md) |
| NoteCardGroups | `NoteCardGroups` | [live-ink-responders-and-notes](state-machines/live-ink-responders-and-notes.md) |
| RolloutTurns and CodexTurns | `RolloutTurns`, `CodexTurns` | [live-ink-responders-and-notes](state-machines/live-ink-responders-and-notes.md) |
| LiveNotePopover | `LiveNotePopover` | [live-ink-responders-and-notes](state-machines/live-ink-responders-and-notes.md) |

The findings and the issues they group into are in
[findings](state-machines/findings.md), [plausible findings](state-machines/plausible-findings-run-to-toolbar.md), [more plausible findings](state-machines/plausible-findings-requests-to-live-ink.md) and [issues](state-machines/issues.md).
