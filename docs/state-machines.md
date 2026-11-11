# Vignette's state machines

This file maps every state machine in the app: the reducers written as one, and the state spread
over flags, optionals, ids and timers that behaves as one. For each it gives the states, the
events, the transition table and the invariants, and where each invariant is checked. After the
machines, [Findings](#findings) lists the invalid states and transitions the code can reach, with
the evidence for each, and [Issues](#issues) groups the confirmed ones into fixes.

Keep it current. A change that adds a state, an event, a timer or a callback to one of these
machines updates its section in the same commit. A new finding goes in [Findings](#findings) with
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

## Index

| Area | Machines |
|---|---|
| [The annotation run](#the-annotation-run) | AnnotatorTransition, AnnotationRun (explicit, composite), EventHold, ThumbnailController, the run's effect layer, AnnotationController session, TitleReveal, WindowRemoval, OutsideClick, FocusReturn |
| [Flights and zoom](#flights-and-zoom) | TransitionLayer flights, TransitionLayer panel and press, FlightPress, Tween, AnnotatorZoom, Zoom glue: `fitBeforeHide` and `hideWindows`, DimPanel, BackdropPanel |
| [The corner and the stack](#the-corner-and-the-stack) | CornerPresentation, CornerKeys window side, Panel visibility and dismissal in ThumbnailController, Lone thumbnail timer, `leaveTimer`, CardNotices and its posting timers (explicit value, implicit timers), Stack selection, focus and hover, Stitch converge, shiftUp and card entrance, StackSweep, StackSwipe, HotKey, ModifierTap and KeyMonitors, StackAreaReader |
| [The editor and drawings](#the-editor-and-drawings) | EditorCore, HeldKey, HeldToolLetter, EditorView session, MarkLayers text bitmap (implicit, one per text mark), TypingField, Drawings (implicit, per screenshot key), Rendering and clipboard promise, DragSourceView press |
| [The toolbar and destinations](#the-toolbar-and-destinations) | AnnotatorToolbar.Model: target and offer, ToolbarOffer (explicit, derived), Send progress: sending, failure, Bar presence: shown, hideGeneration, sliding, Keyboard focus: focus, keyed, tookKeysOnOpen, toolLetter, heldLetter, HeldToolLetter, Target menu pick, SessionListing, AppDelegate.refreshDestinations and listDestinations, DestinationChoice (pure functions, no state), ClaudeCodeConnection: submit, preflight, start, HerdrLauncher.start, CodexConnection: discover and submit, AppServer.converse, AppServerSession (implicit; live ink's), SendOverlay notice animation |
| [Requests, replies and the screenshots folder](#requests-replies-and-the-screenshots-folder) | Record.Status, SendGrace, Send bookkeeping, Reply.Stage, Reply import pipeline, Clearing and cleanup, Admission limit, FolderWrites pending adds, FolderWrites held-back reports, ScreenshotWatcher (implicit, with explicit pieces), Thumbnailer, CaptureOrigin, ReplyCommand and ReplyProtocol (explicit by order) |
| [Setup, settings and launch](#setup-settings-and-launch) | SetupWindowController, SetupModel, SetupBanter, SetupInkPlayer and SetupInkGuide, MenuBarIntro, Accessibility.request, ShortcutRecorderView, SettingsSync and Settings (shell), Apple screencapture reconcile, AgentPlugins, AgentTools, LoginItem, Updater and the update dot, AppLocation (explicit, linear), Launch sequence (implicit, ordered), Hotkey press and hold pair, Stitch action, Setup Lab and Intro Lab (debug) |
| [Live ink: the hand](#live-ink-the-hand) | HeldChord, ModifierChord, LiveInk inking lifecycle, LiveInk stroke, LiveInkTap, Overlay surfaces, Window picker watch, Menu hand-off: overMenus and LiveMenus, LiveEscape and the Esc hotkey, FocusRun, the focus tour, Steps tour, LiveListening and the transcriber chain, LiveWindows Tracked, LiveInk.setOn and the chord object |
| [Live ink: asks and responders](#live-ink-asks-and-responders) | LiveAsks, LiveInk ask glue, LiveResponder, LiveResponders, ClaudeDriver, JSONLinesProcess, CodexDriver and CodexRun (explicit phase inside an implicit machine), ResponderStatus, CodexLogin, LiveNoteCards, NoteCardWait, TurnWatch, NoteCardGroups, RolloutTurns and CodexTurns, LiveNotePopover |

## The annotation run

The annotation run decides which image is in the annotator (the editor window), what is flying, and what opens next. A pure reducer (`AnnotationRun`) holds a pure transition table (`AnnotatorTransition`), and `ThumbnailController` and `AnnotationController` carry out the effects they return.

### AnnotatorTransition (explicit)

Owner: `AnnotatorTransition.swift:31`, held privately by `AnnotationRun.transition` (`AnnotationRun.swift:63`). Tests: `AnnotatorTransitionTests.testRandomSequencesKeepTheInvariants`, `AnnotatorTransitionTests.testRequestingTheImageParkingForASwapOpensItAgainAfterThePark`, `AnnotatorTransitionTests.testRemovingTheFileParkingForASwapHidesItAndOpensNothing` ([issue 8](#issue-8)).

Decides how the annotator moves between images and when it closes. `AnnotationRun` is the only sender (`forward`, `AnnotationRun.swift:206`).

An `Opening` (`AnnotatorTransition.swift:7`) is one image sent to the annotator. Its `id` is its identity (`==` and `hash` use only `id`). Its `key` can change by rename, and `paged` is set by `.page`.

**States** (`Phase`, `:41`)

- `idle`.
- `flyingOut(o)`: `prepare` was sent and the card is travelling. The window is ordered in at alpha 0, nobody has seen it, and no zoom is possible.
- `annotating(o)`: `shown(o)` came and the window is up.
- `parking(o, then: Next)`: the editor is parking `o`'s drawing. `Next` (`:33`) is `annotate(o2)` (a swap), `close` (Esc or Send), `finish` (Done), `dismiss` or `remove`.

**Transitions** (`:48`; `—` means ignored, returns `[]`)

| State | Event | Next state | Effects |
|---|---|---|---|
| `idle` | `annotate(o2)` | `flyingOut(o2)` | `prepare(o2)` |
| `flyingOut(o)` | `annotate(o2)`, same key | — | — |
| `flyingOut(o)` | `annotate(o2)`, other key | `flyingOut(o2)` | `abandon(o)`, `returnCard(o)`, `prepare(o2)` |
| `annotating(o)` | `annotate(o2)`, same key | — | — |
| `annotating(o)` | `annotate(o2)`, other key | `parking(o, annotate(o2))` | `park(o)` |
| `parking(o, annotate)` | `annotate(o2)` | retargets the swap to `o2` | — |
| `parking(o, close)` | `annotate(o2)` | same key: stays `close`. Other key: `annotate(o2)` | — |
| `parking(o, finish)` | `annotate(o2)` | same key: —. Other key: `annotate(o2)` | — |
| `parking(o, dismiss or remove)` | `annotate(o2)` | — (a dismissal keeps winning) | — |
| `flyingOut(o)` | `shown(s)` | `s == o`: `annotating(o)`. Else — | `show` |
| other states | `shown` | — | — |
| `parking(o, N)` | `parked(p)`, `p == o` | `N = annotate(o2)`: `flyingOut(o2)`. `close`: `idle`. `finish`: `idle`. `dismiss` or `remove`: `idle` | `annotate`: `returnCard(o, copied: false)`, `prepare(o2)`. `close`: `returnCard(o, false)`. `finish`: `returnCard(o, true)`. `dismiss`/`remove`: `hideAnnotator` |
| any other state | `parked`, or a `parked` for another opening | — | — |
| `flyingOut(o)` | `close` | `idle` | `abandon(o)`, `returnCard(o, false)` (same turn) |
| `annotating(o)` | `close` | `parking(o, close)` | `park(o)` |
| `parking(o, annotate(o2))` | `close` | `parking(o, close)` (**fixed**, [run-2](#run-2)) | — |
| `parking(o, close, finish, dismiss or remove)` | `close` | — | — |
| `flyingOut(o)`, `annotating(o)` | `finish` | `parking(o, finish)` | `park(o)` |
| `parking(o, any N)` | `finish` | — (ignored in every `N`) | — |
| `flyingOut(o)`, `annotating(o)`, `parking` | `dismiss` | `parking(o, dismiss)` | `park(o)`, except none from `parking` |
| `flyingOut(o)`, `annotating(o)` | `remove(r)`, `r == o.key` | `parking(o, remove)` | `park(o)` |
| `flyingOut(o)`, `annotating(o)` | `remove(r)`, other key | — | — |
| `parking(o, annotate(o2))` | `remove(r)`, `r == o2.key` | `parking(o, close)` | — |
| `parking(o, close or finish)` | `remove(r)`, `r == o.key` | `parking(o, remove)` | — |
| `parking(o, annotate(o2))` | `remove(r)`, `r == o.key` | `parking(o, remove)`: the annotator hides and nothing opens (**fixed**, [run-3](#run-3)) | — |
| `parking(o, dismiss or remove)` | `remove` | — | — |
| not `idle` | `newShot(n)` | unchanged | `join(n)` (the controller ignores `.join` under `dismiss` and `remove`, `ThumbnailController.swift:863`) |
| not `idle` | `renamed(old, new)` | unchanged, `o` re-keyed (also the `o2` in `annotate(o2)`) | — |

`heading` (`:84`) is the image a page moves on from: `o` in `flyingOut` and `annotating`, `o2` in `parking(_, annotate(o2))`, else nil.

**Invariants**

- A `prepare` is never emitted while a park is in flight (`:26`). Checked by: `AnnotatorTransitionTests.testRandomSequencesKeepTheInvariants`.
- At most one park is in flight, and `park` and `abandon` name the prepared opening. Checked by: the same test.
- An answer naming another opening changes nothing. Checked by: the same test and the guards at `:119` and `:179`.
- `annotating` implies the image was prepared. A dismissal ends `idle` with everything hidden. Checked by: the same test.
- A close takes effect over a swap that is parking. Checked by: `AnnotationRunTests.testACancelDuringASwapsParkClosesInsteadOfOpeningTheNextImage` (**fixed**, [run-2](#run-2)). A close or a finish during any other park is ignored: the park already ends the image.
- `returnCard` is never emitted for a file that no longer exists. Checked by: `AnnotatorTransitionTests.testRemovingTheFileParkingForASwapHidesItAndOpensNothing` for the swap's park (**fixed**, [run-3](#run-3)); nothing else checks it.

**Late and concurrent answers**

- `shown` and `parked` naming a past opening: dropped by the opening compare, `:119`, `:180`.
- `close` or `annotate` while `flyingOut`: answered in the same turn with `abandon` and `returnCard`, `:122-128`.
- A swap back to the same key while parking: reopens it after the park (`AnnotatorTransitionTests.testRequestingTheImageParkingForASwapOpensItAgainAfterThePark`).
- A removed swap target turns the swap into a close, `:213`.

### AnnotationRun (explicit, composite)

Owner: `AnnotationRun.swift:12`, held in `ThumbnailController.run` (`ThumbnailController.swift:75`); only `handle` writes it. Tests: `AnnotationRunTests.testRandomSequencesKeepTheInvariants` (in `AnnotationRunTests+Sequences.swift`), `AnnotationRunTests.testAFileGoneFromTheQueueSkipsNoNumber`, `AnnotationRunTests.testADismissalEndsTheRunAndSaysWhetherAHandEndedIt`, `AnnotationRunTests.testACancelDuringASwapsParkClosesInsteadOfOpeningTheNextImage` and `AnnotationRunTests.testRemovingTheOpenFileDuringASwapsParkEndsTheRun` ([issue 8](#issue-8)).

Owns the list of files to annotate and how a hand ended the run. It wraps the transition, adds the queue, and emits `endRun` once per run. `ThumbnailController` sends the events.

**States**: the properties together (`AnnotationRun.swift`).

- `transition` `:63`: the phase above.
- `minted` `:65`: the last opening id. Never reset.
- `lift: Lift` `:56`, `:66`: `loaded`, `takesPresses`, `arrived`, `lifted`. Reset at each `prepare` (`:213`).
- `queue` `:68`, `total` `:71`, `opened` `:72`, `fromQueue` `:74`: the list and its counters.
- `uncopied: Opening?` `:76`: Done's copy failed while this opening parked.
- `ending: RunEnding?` `:78`: how a hand ended the run. Reported once by `endRun`.

**Events** (`:13`) and senders (`ThumbnailController.swift`)

- `annotate([key])`: `startAnnotating` `:341`, and a card click while active `:115`.
- `page(key, isRepeat)`: `page(_:isRepeat:)` `:388`, from the editor's Left and Right.
- `shown(o)`, `arrived(o)`: flight closures in `perform(.prepare)`.
- `parked(o)`: `perform(.park)` `:844`.
- `loaded(o)`: `editorLoaded` `:396`. `takesPresses(o)`: `annotatorTakesEvents` `:401`.
- `cancel(RunEnding)`: `annotationEnded` `:367` (Esc, Cmd+W, bar close, click outside, decode failure) and `CornerPresentation` `.closeEditor` as `.shortcut` `:284`.
- `sent`: `annotationSent` `:375`. `finish`: `annotationFinished(quick: false)` `:381`. `dismiss(.finished)` for quick Done, `dismiss(nil)` from `slideOut` `:704`.
- `remove([key])`: `:476`. `renamed`: `:493`. `selectionChanged`: `:768`. `copyFailed(o)`: `showNotCopied(in:)` `:646`. `newShot`: `show` `:230`.

**Transitions** (the run's own change, then the transition's result `T`)

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `annotate(keys)` | `queue = keys.dropFirst()`, `total`, `opened = 1`, `fromQueue = nil` (set even when `T` ignores the annotate), then `T.annotate(mint(first))` | as `T` |
| any | `page(key)` | refused unless `takesPage` (`:168`): `heading != nil`, and a repeat also needs `annotating` and `lift.lifted`. Else as `annotate([key], paged)` | as `T` |
| any | `loaded`, `takesPresses`, `arrived` for `o == opening` | sets that `Lift` flag | `takesPresses` adds `handOverPresses`, `arrived` adds `landed`; `liftFlight` once when all three are in (`:190`) |
| any | `shown`, `parked` | as `T` | as `T` |
| any | `cancel(how)` | `ending = how` if active; `queue = []` always (`:119-122`), then `T.close` ([run-1](#run-1), [run-2](#run-2)) | as `T` |
| any | `sent` | `ending = .sent` if active; queue kept, then `T.close` | as `T` |
| any | `finish` | `ending = .finished` if active; queue kept, then `T.finish` ([run-4](#run-4)) | as `T` |
| any | `dismiss(e)` | `ending = e` if `e` is set and active; `queue = []`, then `T.dismiss` | as `T` |
| any | `remove(keys)` | drops them from `queue` (`total` is not reduced, [run-6](#run-6)); if the open key is removed, `queue = []` (`:136`), then one `T.remove` per key ([run-3](#run-3)) | as `T` |
| any | `renamed` | re-keys `queue`, `fromQueue`, `uncopied` and `T` | — |
| active, list not ended | `selectionChanged` | removes, then appends the added keys | `queued` |
| active, list ended (`total == 0`: Esc, a dismissal or the open file going) | `selectionChanged` | — (**fixed**, [run-1](#run-1)) | — |
| idle | `selectionChanged` | — | — |
| `parking(o, finish)` | `copyFailed(o)` | `uncopied = o` (`:148`) | — |
| other | `copyFailed` | — | — |

After every `T` result:

- `.prepare` resets `uncopied` and `lift` (`:211`).
- `.returnCard` drops the Copied mark if `uncopied == opening` (`:218`).
- `.hideAnnotator` calls `endQueue` (`:221`).
- When the transition goes from active to idle, `continueOrEnd` (`:227`) opens `queue.first` (`next`, then annotate) or emits `endRun(ending)` and clears `ending` (`:232-239`). `reduce` also clears `ending` whenever a `prepare` is left after the files that cannot open are passed over (**fixed**, [run-4](#run-4)).
- `reduce` (`:94`) asks `opens(key)` for the last `prepare`. When the file cannot open it deletes that `prepare` and `next`, and `cannotOpen` (`:198`) resets the transition to `idle` and calls `continueOrEnd`.

**Invariants**

- The queue is empty whenever idle and right after a cancel or dismiss. `endRun` comes exactly when the run goes idle, once per run. Nothing opens while a dismissal ends the run. Every opening is new. A flight lifts once. Handover, landed and lift name the opening in the editor. A file that does not open is never prepared. A failed copy leaves its card unmarked. A page replaces the queue. A repeat in flight changes nothing. Checked by: `AnnotationRunTests.testRandomSequencesKeepTheInvariants`.
- Once Esc, a dismissal or the open file going empties the queue, nothing refills it before the park ends. Checked by: `AnnotationRunTests.testACardSelectedWhileEscParksQueuesNothing` (**fixed**, [run-1](#run-1)).
- `ending` describes only the image it was set for (comment at `:246`). Checked by: `AnnotationRunTests.testAHandoverForgetsHowTheImageBeforeEnded` (**fixed**, [run-4](#run-4)).
- `place ... of total` stays inside `1...total`. Checked by: the random test. `total` is not reduced when a queued file is removed, so the log says "2 of 3" for two files (`AnnotationRunTests.testAFileGoneFromTheQueueSkipsNoNumber` asserts it); log only ([run-6](#run-6)).

**Late and concurrent answers**

- Any run event naming a past opening: dropped, `:151`, `:155`, `:159`.
- A file that stops reading before it opens: `cannotOpen`, `:96-104`.
- A session-ending event clears the queue before a park can answer in the same turn: `:119-132`, `:221`.
- `uncopied` is matched by opening id: `:148`, `:219`.
- A rename re-keys the queue: `:141`.
- A flight dropped before it arrives sends no `arrived`, so `lift.lifted` stays false and a held Left/Right stops repeating. No guard ([run-5](#run-5)).

### EventHold (explicit)

Owner: `AnnotationRun.swift:278`, held by `ThumbnailController.hold` (`:726`). Tests: `AnnotatorTransitionTests.testRandomSequencesKeepTheInvariants`.

Runs events in order. An event sent while another is being handled waits its turn. State: `held: [Event]` and `handling: Bool`.

**States**: idle (`handling == false`) and draining (`handling == true`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| idle | `send` | draining, then idle when `held` is empty | runs the event, then every held event in FIFO order |
| draining | `send` | draining | appends to `held` (`:283-286`) |

**Invariants**

- No event runs inside another. Checked by: `AnnotatorTransitionTests.testRandomSequencesKeepTheInvariants` ("a held event runs in the loop that holds it").

**Late and concurrent answers**

- A same-turn `parked` from `hide` at zoom 1 (`fitBeforeHide` calls `done()` at once, `AnnotationController.swift:508`): held until the current event ends.
- `loaded` from a cached decode inside `prepare` (`AnnotationController.swift:229`): held.
- A failed `open` calling `cancel()` inside `prepare` (`:206-210`): held.

### ThumbnailController, the run's effect layer (implicit)

Owner: `ThumbnailController.swift:734` (`handle`), `:790` (`perform`). Tests: none.

Carries out the run's effects and keeps the stack, the dim and the keys in step with it.

**States**: the properties that together say "an annotation is on screen".

- `run` `:75`. `sessionCard` `:77`, the card the run has open: set in `perform(.prepare)` `:797`, nil at `.endRun` `:871`. `annotating` `:78` is `run.isActive ? sessionCard : nil`.
- `annotationFrame` `:79`, `parkedMarks` `:82`, `captureOrigin` `:145`, `flightPress` `:84`.
- `model.annotating` and `flights.staysUp`: flipped together at the end of `handle` when `model.annotating != run.isActive` (`:757-765`), which sends `keys.send(.editorOpened)` or `.editorClosed(ending)` with the `ending` from this batch's `endRun`.
- `model.outCards` holds the session card's id from `.prepare` (`:803`) until `returnCard` arrives (`:~915`) or `.hideAnnotator` (`:856`).
- `dim`: shown at `.prepare` (`:808`), hidden only at `.endRun` (`:872`).
- `model.slidingOut` (set `:704`, reset `:716` and in `present`).

**Transitions** (effect, guard, result)

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `.prepare` | `sessionCard` set, card in `outCards`, dim shown, `parkedMarks` cleared | returns silently when the stack has no card for the key (`:794`; not reachable, `opens` made the card first) |
| any | `.show` | — | `onAnnotatorShow`; a lone card alone in the corner leaves the panel (`:838-843`) |
| any | `.park` | `parkedMarks = annotatorMarks()` | `onAnnotatorHide` then `send(.parked(opening))` (`:845`) |
| any | `.abandon` | `parkedMarks` set | `onAnnotatorAbandon` (`:847`) |
| any | `.returnCard` | card home | needs `sessionCard.key == opening.key` (`:852`); re-inserts the card when the panel lacks it (`returnCard`, `:888-900`) ([run-3](#run-3)) |
| any | `.hideAnnotator` | `parkedMarks = nil` | ends the flight unless the column is sliding out with that card in it (`:855-858`) |
| any | `.endRun` | `sessionCard = nil` | `dim.hide()` |
| any | `.landed`, `.liftFlight` | — | each needs `sessionCard` (`:874`, `:882`) |
| any | `.handOverPresses` | — | `flightPress.ready(key)` (`:880`) |
| any | `.join`, `.next`, `.queued` | — | `.join` is a no-op; the others only log |

**Invariants**

- The editor is open exactly while the run is (comment `:754`). Checked by: nothing; the reducer tests cover only `endRun` once per run.
- `parkedMarks` is consumed by `homeFlightMarks` (`:985`) and cleared at `.prepare` (`:809`) and `.hideAnnotator`. A stale value is used only when its `drawing.key` matches the card (`:988`). Checked by: nothing.

**Late and concurrent answers**

- `slideOut` sets `model.slidingOut` and aims the flight offscreen before sending `.dismiss`, so a same-turn park keeps that flight: `:704`, `:855`.
- `handle` runs `makeRoom` once for a batch, so a swap is one column: `:741-748`.
- `flightPress.ended` for an image no longer in the editor: `:750-752`.
- `perform(.park)` sends by opening id, so the reducer drops a late `parked`.
- A rename updates `sessionCard` before `send(.renamed)`, so `returnCard`'s key compare holds: `:501-507`.
- `annotate(_:from:)` calls `startAnnotating` after the capture's decode with no check that anything changed (`:324-338`), and `captureOrigin` (`:343`) survives an ignored annotate until the next `prepare` of that key ([run-7](#run-7)).

### AnnotationController session (implicit)

Owner: `AnnotationController.swift:8`. Tests: none (needs AppKit).

The annotator window and editor for the image the run opened. It is reused; the run's effects drive it.

**States**: the properties together.

- `current: Screenshot?` `:48`: set in `prepare` (`:163`), nil in `hide` and `abandon` (`:476`, `:462`). `opened: Opening?` `:56`. `opening` `:594` is `current == nil ? nil : opened`.
- `windowUp` `:64` (true after `show`, false at `prepare`), `editorUntouched` `:62`.
- `eventProbe: Timer?` `:51`, `outsideClick` `:49`, `removal` `:53` (`WindowRemoval`), `titleReveal` `:90`, `inkMeasurement` `:86`. The zoom properties belong to the flights area.

Phases, derived:

1. Closed: `current == nil`, window hidden or absent.
2. Prepared: `current != nil`, `windowUp == false`, alpha 0, keys held.
3. Shown: `windowUp == true`, `outsideClick` running, `eventProbe` running until it answers.
4. Hiding: `current == nil` while `fitBeforeHide` is pending (zoomed only).
5. Removing: `removal` pending (`hideWindows`, `:514`); the window is still ordered in.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `prepare` (`:161`) | Prepared | cancels `removal` (`:170`); resets `windowUp`, `editorUntouched`, zoom and title reveal (`.opened` / `.closed`) |
| Prepared | `prepare` with an unreadable image | Prepared | calls `cancel()` (`:206-210`), so `onClosed(.back)` reaches the run as `.cancel`, held until the batch ends |
| Prepared | `show` | Shown | needs `current != nil` (`:354`) |
| Closed | `show` | — (ignored) | — |
| `current != nil` | `cancel(how)` | — | `onClosed(how)` only; hides nothing |
| `current == nil` | `cancel` | — (ignored, `:664`) | — |
| any | `hide(then:)` | Hiding (zoomed) or Removing | `current = nil`, `park()`, `fitBeforeHide`, then `hideWindows` and `then()` |
| `current != nil` | `abandon` | Removing | `zoom.reduce(.close)`, `current = nil`, `park()`, `hideWindows()` |
| `current != nil` and `opened == opening` | `renamed` | — | re-keys `current` |
| Hiding | `renamed` | — (ignored; `opened` keeps the old key, so the flight home loses the title, `takeTitle(of:)` `:487`) ([run-8](#run-8)) | — |
| any | `landed` (`:440`) | — | sets the shadow, `revealTitle(.landed)`; not guarded by opening or `current` |

**Invariants**

- `hide` is called once per `prepare` (comment `:468`). Checked by: nothing in the controller; the run emits one `park` or `abandon` per opening.
- The window and editor are reused, and the last image's `removal` must not take them (comment `:168`). Checked by: `removal.cancel()` at `:170`.
- `eventProbe` never answers for an opening that ended. Checked by: the compare at `:393` and `stopProbe()` in `hide` and `abandon`.
- `landed()`, `onClosed`, `onFinished` and `onSend` rely on `current != nil` meaning "the run's current opening". That holds because `hide` clears `current` in the call that begins the park, and the run emits `prepare` only after `parked`. Checked by: nothing.

**Late and concurrent answers**

- The `loaded` decode: dropped unless `self.opening == opening`, `:217`.
- The `eventProbe` answer: compares `opening`, `:393`; gives up after 0.5 s.
- The `revealTitle` 0.5 s wait: compares `opened == opening` and `current != nil`, `:321`.
- The ink `Task`: compares `inkMeasurement` and `current != nil`, `:296`. `measureTitleInk` returns early without bumping it when the next image has no title (`:282`), so a stale answer lands on a `.closed` reveal with no visible effect.
- `offerTyping`: needs `windowUp`, `editorUntouched` and `current != nil`, `:377`.
- `fitBeforeHide`: answers once (`answered`, `:509`) from the tween or its 0.3 s deadline.
- Esc during the zoomed fit-out: dropped by `cancel`'s `current != nil` guard, `:664`.
- `dropped:` closure of a flight: calls `onAnnotatorLanded` with no opening compare (`ThumbnailController.swift:836`); `TitleReveal` ignores a late `landed` once closed.

### TitleReveal (explicit)

Owner: `AgentTitle.swift:106`. Tests: none. Driven by `AnnotationController.revealTitle` (`:316`).

Decides when an image's title fades in: after the flight lands and its ink is known.

**States**: `flying(inkKnown)`, `waiting(since)`, `shown`, `closed`. Inputs: `opened`, `inkKnown`, `landed`, `waitEnded`, `closed`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `opened` | `flying(false)` | — |
| any | `closed` | `closed` | — |
| `flying` | `inkKnown` | `flying(true)` | — |
| `waiting` | `inkKnown` | `shown` | `.show(waited)` |
| `flying(true)` | `landed` | `shown` | `.show(0)` |
| `flying(false)` | `landed` | `waiting` | `.waitForInk` |
| `waiting` | `waitEnded` | `shown` | `.showInAppearanceInk` |
| anything else | any | — (the `default` row) | — |

**Invariants**

- A late `landed`, `inkKnown` or `waitEnded` after `closed` is ignored. Checked by: the `default` row; no test.

**Late and concurrent answers**

- The wait timer compares the opening id: `AnnotationController.swift:321`.
- `inkKnown` for the previous image after `closed`: ignored.

### WindowRemoval (implicit)

Owner: `WindowRemoval.swift:9`. Tests: none.

Takes the annotator window down after the flight home covers the frame. State: `generation`, `link`, `left`, `remove`.

**States**: idle, started (waiting for the next main turn), counting (display link running, `left` refreshes to go).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `start` | started | cancels first; next main turn runs `hide`, installs a display link, runs `remove` after 3 refreshes (`:11-12`, `:40-46`) |
| started or counting | `cancel` | idle | bumps `generation`, kills the link, drops `remove` |

**Invariants**

- A removal cancelled before its main-queue hop runs neither `hide` nor `remove`. Checked by: the `generation` compare at `:22`.

**Late and concurrent answers**

- A display link that never fires (display asleep): `remove` never runs and the editor's image stays held until the next `prepare`. No guard.

### OutsideClick (implicit)

Owner: `OutsideClick.swift:12`. Tests: none.

Reports a click outside the annotator. State: `monitor: Any?`. The annotator starts it in `show` (`AnnotationController.swift:366`) and stops it in `hide` and `abandon`; `start` replaces an earlier monitor. The handler ignores clicks before `watching` (`settling` 0.15 s, `OutsideClick.swift:22`) and checks the window under the cursor first.

### FocusReturn (implicit)

Owner: `FocusReturn.swift:6`. Tests: none.

Remembers where the focus goes back to. State: `previousApp` and a weak `ownWindow`. `sessionStarting` records a titled key window (only if Vignette is active); an app activation clears `ownWindow` and sets `previousApp`; `restore` prefers a visible `ownWindow` and does not clear it, so it persists until another app activates. `CornerKeys` calls it on `.restoreFocus` after `editorClosed(ending)`.

## Flights and zoom

A flight is a card (or picture) animated across the screen on a spring, drawn by one shared panel. This area holds the layer that draws flights and takes presses over them, the reducer that decides what a press does, the spring that drives most motion, the annotator's zoom, and the two panels that fade in behind the stack.

All line numbers are in `Sources/`.

### TransitionLayer flights (implicit)

Owner: `TransitionLayer.swift:11`, one instance at `ThumbnailController.swift:46`. Tests: none. Nothing constructs `TransitionLayer`. `MotionTests.testAFlightHandsOverOnlyOnceItIsThere` and `MotionTests.testAFlightCoversItsTargetFromTheMomentItReachesIt` test the timing helpers only.

The layer holds a set of flights. `ThumbnailController` starts, re-aims, lifts and ends them; timers inside the layer report arrival.

**States**: a flight has no state enum. These properties together make it:

- `model.flights: [Flight]` (`:45`). A flight is in the array or not.
- `Flight.generation` (`:30`), taken from `nextGeneration` (`:76`) in `start` (`:319`). Never reused. `converge`'s resting result flight keeps generation 0 (`:264`).
- `Flight.dropped: (() -> Void)?` (`:34`). Set by `start` (`:330`, `:333`), cleared on arrival (`:231`).
- `Flight.path`, `previousPath`, `blend` (`:25-29`): the bow of the path. `start` sets `blend = 0`; the async block of `fly` animates it to 1 (`:212`).
- `Flight.look`, `frame`, `opacity`, `caption`, `leavingAnnotator` (`:13-23`).
- `arrivedFlights: Set<UUID>` (`:70`): the spring settled on its target.
- `pendingLift: Set<UUID>` (`:71`): a lift was asked before arrival.
- `model.swallowRects` (`:46`): each lives until its own `asyncAfter` removes it (`:403-407`) or `endAll` empties the array (`:375`).

Flight states these make: `absent` (not in `model.flights`), `flying` (in it, not in `arrivedFlights`), `flying+liftPending` (`flying` and in `pendingLift`), `arrived` (in `arrivedFlights`, `dropped` is nil).

Events and senders:

- `fly(id:…)` (`:187`): `ThumbnailController.swift:695` (`slideOut`), `:828` (card to annotator), `:907` (`returnCard`), `:941` (`flyAway`), and `converge` (`:293`).
- `converge(…)` (`:254`): `ThumbnailController.swift:567` (stitch).
- `lift(id:)` (`:363`): `ThumbnailController.swift:884` (`.liftFlight`), `:915`.
- `end(id:)` (`:369`): `ThumbnailController.swift:479, 688, 698, 860, 902, 943`, and `:277`, `:288` here.
- `endAll(except:)` (`:374`): `ThumbnailController.swift:1319` (`present`).
- `dropShadow(id:)` (`:356`): `ThumbnailController.swift:878, 913`, and `:282` here.
- `setImage(id:)` (`:348`): `FlightImages.swift:60`.
- `swallowPresses(in:for:on:)` (`:399`): `ThumbnailController.swift:961`.
- Timers: the three `DispatchQueue.main` hops in `fly` (`:203`, `:216`, `:223`) and the swallow rect expiry (`:403`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| absent | `fly` | flying | `start` appends the flight (`:333`) with a new `generation`; `showPanel`; an async hop commits the start, then animates to the target |
| absent | `converge` | resting result flight (opacity 0, generation 0) plus flying pieces | the result id is removed first (`:261`); pieces fly with `arrived: land, dropped: land` |
| flying, arrived | `fly` (same id) | flying (new generation) | new image and marks (old marks cleared if different, `:324`), `path`/`previousPath`, `blend = 0`, `dropped` replaced (may become nil); `arrivedFlights` and `pendingLift` cleared (`:315-316`). The old `covered`, `arrived` and `dropped` are never called |
| any | second `fly` in the same turn as the first | second generation wins | the first hop sees a `generation` mismatch and returns (`:204`) |
| flying | cover timer, `isCurrent` | flying | `covered()` (`:216-219`) |
| flying | arrival timer, `isCurrent` | arrived | frame and look snapped without animation (`:225-229`); inserted in `arrivedFlights`; `dropped = nil`; `arrived()`; then `end` if in `pendingLift` (`:233`) |
| flying | either timer fires and the flight is absent or has another generation | unchanged | ignored (`:217`, `:224`) |
| flying | `lift` | flying+liftPending | `pendingLift.insert` (`:365`) |
| arrived | `lift` | absent | `end` (`:365`) |
| absent | `lift` | absent | ignored (`:364` guard) |
| flying | `end`, `endAll` | absent | marks cleared, flight removed, `orderOutIfIdle`, then `dropped` called (`:382-387`) ([flights-1](#flights-1)) |
| arrived | `end`, `endAll` | absent | no `dropped` (`:382` filter) |

**Invariants**

- The panel is up whenever a flight, a swallow rect, `staysUp` or a held press exists (comments `:410-411`, `:430-432`). Checked by: nothing.
- `ignoresMouseEvents` is never set on the panel (comment `:8-9`). Checked by: nothing.
- A flight's `dropped` runs only if the flight did not arrive, and at most once. Checked by: the filter at `:382` and `dropped = nil` at `:231`; no test.
- `arrived` runs once the spring is within 0.5 pt of its target (`arrivalTolerance`, `:74`; `Anim.settle`). Checked by: `MotionTests.testAFlightHandsOverOnlyOnceItIsThere` (timing helper only).
- `covered` runs before `arrived` (comment `:215`); `coverTime = min(settleTime, passesTarget)` (`:199`). Checked by: `MotionTests.testAFlightCoversItsTargetFromTheMomentItReachesIt` (`passesTarget < settle` only).
- No two live flights share a generation. Checked by: `nextGeneration` (`:76`, `:319`); no test.

**Late and concurrent answers**

- A timer for a flight that was re-aimed or removed: ignored by `isCurrent(id, gen)` (`:246`, used at `:217`, `:224`), by the `generation == gen` check in the first hop (`:204`) and by the index lookup (`:224`).
- Two `fly` calls in one turn: the second `start` bumps `generation` (`:319`), so the first hop returns at `:204`.
- A reused id: generations never repeat (comment `:317-320`).
- `covered` and `arrived` due at the same instant (motion 0): `covered` is scheduled first (`:215`) and the deadlines come from two successive `.now()` calls, so the order holds.
- A lift asked before arrival: held in `pendingLift` (`:365`), run at `:233`, cleared on re-aim (`:316`).
- A `dropped` handler that re-enters the layer: `end(where:)` removes first and calls handlers after (`:383-387`); `converge`'s `land` defers a turn (`:275`).
- Dismissing during a converge: dropped pieces still answer `land` (`:294`); the result flight is uncovered only if its generation is still the resting one (`:281-282`, `:286-287`).
- Zero-duration motion: `Anim.settle` and `Anim.passesTarget` return 0 (`Settings.swift:1109`, `:1149`), so both timers run next turn. `Anim.spring(0)` is `.linear(duration: 0)` (`Settings.swift:1100`).

### TransitionLayer panel and press (implicit)

Owner: `TransitionLayer.swift:11`. Tests: none.

The layer's one panel and the press it is holding. `PressCatcher` (`:503-505`) hands each mouse event to `pressed` (`:94`); `FlightPress` decides where the press goes.

**States**:

- `panel.isVisible` (`:79`). Shown by `showPanel` (`:428`), taken down by `orderOutIfIdle` (`:412`). `orderIn` and `orderBelow` only order other windows relative to it.
- `staysUp` (`:63`), set by `ThumbnailController.swift:758` (`flights.staysUp = run.isActive`).
- `pressDown` (`:59`), `pressedFlight` (`:58`), `releaseWatch` (`:67`), `screen` (`:68`).

**Transitions**

Panel:

| State | Event | Next state | Effects |
|---|---|---|---|
| hidden | `fly`, `converge`, `swallowPresses` | visible | `showPanel` sets the frame to `screen.frame` and calls `orderFrontRegardless` (`:433-436`) |
| visible | `end`, `endAll`, rect expiry, `released`, `staysUp = false` | hidden if `!staysUp && flights.isEmpty && swallowRects.isEmpty && !pressDown` (`:413`) | otherwise stays up |
| visible | `showPanel` for another screen | visible, frame moves to that screen (`:433-435`) | existing flights and swallow rects keep frames local to the earlier screen ([flights-2](#flights-2)) |

Press:

| State | Event | Next state | Effects |
|---|---|---|---|
| up | `leftMouseDown` | down | `pressedFlight` is nil if a swallow rect covers the point, else the topmost flight under it (`:99`); `watchRelease` starts; `.pressed` reported (`:102`) |
| down | `leftMouseDragged` | down | `.dragged` reported (`:104`) |
| down | `leftMouseUp` | up | `released`: timer cancelled, `orderOutIfIdle`, `.released` reported (`:112-122`) |
| down | timer: the button reads up on 2 ticks (`:146-147`) | up | logs `[flight] release missed`, calls `released` |
| up | `leftMouseUp` | up | ignored by `guard pressDown` (`:113`) |
| up | extra `leftMouseDragged` | up | still reported with `pressedFlight` nil (`:104`); `FlightPress` ignores it in `idle` (`FlightPress.swift:61`) |
| down | `leftMouseDown` | down | state overwritten, old watch invalidated (`:141`); nothing is done for the lost first press |

**Invariants**

- A swallow rect always clears: expiry is an unconditional `asyncAfter` (`:403`) and `endAll` empties them (`:375`). Checked by: nothing.
- The panel stays up while a press is down, even after its swallow rect expired. Checked by: the `!pressDown` term at `:413`.

**Late and concurrent answers**

- A release that never arrives: `watchRelease` (`:140`) ends the press from the button's own state; the real release, if it comes late, is ignored (`:113`).
- A release after the flight is gone: `fraction(of:on:)` returns nil (`:171`); `FlightPress` takes events with `picture` nil (`:127`).

### FlightPress (explicit)

Owner: `FlightPress.swift:10`, instance `flightPress` at `ThumbnailController.swift:84`. Tests: `FlightPressTests.testAPressBeforeTheEditorCanTakeItIsHeldThenHandedOverInOrder`, `testAPressOnceTheEditorCanTakeItGoesAtOnce`, `testAPressReleasedDuringTheFlightIsHandedOverWhole`, `testAPressOnAnyOtherFlightIsSwallowedToItsRelease`, `testAPressBesideThePictureIsSwallowed`, `testAPressHeldForAnImageThatTurnsBackGoesNowhere`, `testAPressHandedOverStopsWhenTheImageLeavesTheEditor`, `testAnAnswerForAnotherImageHandsNothingOver`, `testAPointOnTheFlightIsItsPlaceOnThePicture`.

A pure reducer. It decides whether a press on a flight is held until the editor can take it, handed to the editor, or swallowed.

**States** (`State`, `:29`): `idle`; `holding(key:events:)`; `handing(key:)`; `swallowing`.

Events and senders: `press(_:into:ready:)` (`:49`; `ThumbnailController.swift:411`), `move(_:)` (`:59`; `:414`), `ready(_:)` (`:80`; `:880` on `.handOverPresses`), `rename(from:to:)` (`:87`; `:506`), `ended(_:)` (`:97`; `:751`).

**Transitions** (k is the key, ev the held events)

| State | `press` | `move` | `ready(k)` | `ended(k)` | `rename` |
|---|---|---|---|---|---|
| `idle` | no key or no picture: `swallowing`. `ready`: `handing`, returns the event. Else `holding`, returns [] | returns [] (`:62`) | — | — | — |
| `holding(k, ev)` | state replaced by the new press; the old press's events are lost | appends; on `.released` stays `holding` | k matches: `idle` if the last event is `released`, else `handing`; returns all events. Other key: [] | k matches: `idle` if the last event is `released`, else `swallowing` | key replaced |
| `handing(k)` | replaced | returns the event with `picture` nil; `released` goes to `idle` | no change, [] | k matches: `swallowing` | key replaced |
| `swallowing` | replaced | returns []; `released` goes to `idle` | [] | — | — |

**Invariants**

- A press held for a key is handed over in order and once. Checked by: `FlightPressTests.testAPressBeforeTheEditorCanTakeItIsHeldThenHandedOverInOrder`, `testAPressReleasedDuringTheFlightIsHandedOverWhole`.
- A press on any other flight is swallowed to its release. Checked by: `testAPressOnAnyOtherFlightIsSwallowedToItsRelease`, `testAPressBesideThePictureIsSwallowed`.
- A held or handed press stops when its image leaves. Checked by: `testAPressHeldForAnImageThatTurnsBackGoesNowhere`, `testAPressHandedOverStopsWhenTheImageLeavesTheEditor`, `testAnAnswerForAnotherImageHandsNothingOver`.
- `rename` carries the key to the new file name (`docs/rules/capture.md`). Checked by: nothing; no test calls `rename`.

**Late and concurrent answers**

- A second `ready`: hands nothing over (pattern match at `:81`).
- An `ended` for a key not held: ignored (`:103`).
- A flight removed while its press is held: the reducer is told only by `ThumbnailController.send`, which ends the press when `keyInEditor` stops matching after any event (`ThumbnailController.swift:750-752`). Later events carry `picture` nil (`TransitionLayer.swift:127`, `:171`).

### Tween (implicit)

Owner: `Tween.swift:9`. Tests: `MotionTests.testSpringStepNeverPassesItsTargetHoweverLateTheTickIs`, `MotionTests.testSpringTweenSettlesWithoutOvershootAndReversesFromWhereItIs`. Nothing runs a `Tween` against a run loop.

A critically damped spring on one number. Users in this area: `zoomTween` (`AnnotationController.swift:84`) and `BackdropPanel.alpha`/`slide` (`BackdropPanel.swift:18-20`). Other users: the toolbar's `slideX`/`slideY`, `HangingPopover`, `fade` (`AnnotationController.swift:801`), `EditorView.swift:492`, `LiveNoteContent.swift:43`.

**States**: `spring: (target, omega, lastTick)?` (`:14`), `link`/`timer` (`:11-12`), `velocity` (`:15`), `completion` (`:17`), `value` (`:10`). Idle: `spring == nil` and no link. Ticking: `spring != nil` with a link or timer.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `animate(to:duration:completion:)` with `duration <= 0` or `target == value` | idle | `completion` stored (`:47`); `set(target)` stops ticking and applies; the new completion is called directly (`:48`). The stored copy is not cleared |
| idle | `animate`, positive duration, new target | ticking | spring started; display link on `NSScreen.main`, or a 1/60 timer |
| ticking | `animate` | ticking | `completion` replaced (`:47`); the old one is dropped without being called ([flights-3](#flights-3)); link and `lastTick` kept (`:53`) |
| ticking | tick settles (`abs(value - target) < 0.001 && abs(velocity) < 0.01`) | idle | value snapped, `apply`, `completion` taken and called once (`:86-90`) |
| ticking | `set(x)` | idle | no completion call; `completion` not cleared ([flights-3](#flights-3)) |
| ticking | `stop()` | idle | no `apply`; `completion = nil` (`:67-71`) |

**Invariants**

- A late tick lands where the spring really is. Checked by: `MotionTests.testSpringStepNeverPassesItsTargetHoweverLateTheTickIs`.
- A reversal keeps velocity. Checked by: `MotionTests.testSpringTweenSettlesWithoutOvershootAndReversesFromWhereItIs`.
- A completion does not run exactly once per `animate`: it is dropped on retarget, `set` and `stop`. Callers that need exactly-once add their own guard (`fitBeforeHide`). ([flights-3](#flights-3))

**Late and concurrent answers**

- `animate` called from inside a completion: works, because `spring` and `completion` are nil before the call (`:87-89`).
- A tick after `stop`: cannot run, the link is invalidated (`:39-42`).

### AnnotatorZoom (explicit)

Owner: `AnnotatorZoom.swift:11`, held as `zoom` in `AnnotationController` and run by `AnnotationController+Zoom.swift:17` (`run`). Tests: `AnnotatorZoomTests` (the reducer, plus a 1000-seed random run through a spring that ticks, turns and arrives), `ZoomTests` (geometry).

A pure reducer for the annotator's zoom. It decides what each zoom input does and which spring to run; the controller turns events into inputs and runs the spring on a `Tween`.

**States** (`Phase`, `:37`): `closed` (initial only), `flying`, `landed`, `closing`. Other fields: `level`, `target` (`:63-66`), `aim`, `pan`, `camera`, `center`, `frame`, `fitted`, `room`.

Events (`Input`, `:12`) and senders:

- `prepare(fitted:room:)`: `AnnotationController.swift:187`.
- `landed`: `AnnotationController.swift:441`, called from `ThumbnailController.swift:836` (flight `dropped`) and `:877` (`.landed` effect) through `AppDelegate.swift:123`.
- `zoomIn`, `zoomOut`, `fit`, `smart`: `zoomRequested` (`AnnotationController+Zoom.swift:36`) from `editor.onZoom` (`AnnotationController.swift:147`).
- `pinch`, `smart`, `wheel`, `lift`, `pan`: `zoomGesture` (`+Zoom.swift:51`) from `editor.onZoomGesture` (`:148`).
- `reveal`: `AnnotationController.swift:152`.
- `tick`: the `zoomTween` apply (`:84`).
- `arrived`: the `animate` completion (`+Zoom.swift:21-24`).
- `close`: `fitBeforeHide` (`:507`) and `abandon` (`:459`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `prepare` | `flying` | reset except `edge` and `pixelScale` (`:121`); `level = 1`, `frame = fitted` |
| any | `tick(level)` | same | `place(frame, picture)`; no phase check (`:126`) |
| any | `close` | `closing` | `spring(to: 1)` if `level` or `target` is off 1, else nil (`:186-193`). `closed` becomes `closing` too. Nothing ever sets `closed` again ([flights-4](#flights-4)) |
| `flying` | `landed` | `landed` | `:124` |
| `landed`, `closing`, `closed` | `landed` | — | `:124` acts only in `flying` |
| `flying`, `closing`, `closed` | any zoom, pan, reveal, lift or arrived input | — | refused: nil (`:133` guard) |
| `landed` | `zoomIn`, `zoomOut`, `fit`, `smart`, `pinch`, `wheel` | `landed` | `.spring` effect; `target` moved; `aim` and `pan` aimed |
| `landed` | `lift`, `arrived` | `landed` | if `target < 1`, spring back to 1 (the hand let go); else — (`:148-151`) |
| `landed` | `pan`, `reveal` | `landed` | `.movePicture` or nil |

**Invariants**

- Nothing zooms before landing. Checked by: `AnnotatorZoomTests.testNothingZoomsBeforeTheFlightLands`.
- Nothing zooms once closing, and the close springs to 1. Checked by: `testTheCardLeavesFromTheFittedFrameAndNothingZoomsOnTheWay` and the random test's `check`.
- Keys and wheel notches stop at the fit; only a hand goes below it, down to `minLevel`. Checked by: `testAKeyOrAMouseWheelsNotchStopsAtTheFit`, `testOnlyAHandPullsBelowTheFitAndNoFurtherThanHalfOfIt`.
- A pull springs back on `lift`, and on `arrived` for a hand that stopped without lifting. Checked by: `testAPullSpringsBackWhenTheFingersLift`, `testAPullSpringsBackWhenTheSpringCatchesUpWithAHandThatStopped`.
- The frame stays in the room and on the pixel grid, the picture covers the frame, and `window * camera == level`. Checked by: `testRandomSequencesKeepTheRules`.
- `prepare` resets level, frame and center, and keeps `edge`. Checked by: `testTheNextImageOpensAtItsFitWithTheSameEdgePull`.
- `closed` is re-entered after a close. Checked by: nothing; it is not ([flights-4](#flights-4)).
- `zoom.phase` agrees with the run's phase. Checked by: nothing.

**Late and concurrent answers**

- Zoom input before `landed`: refused by the `phase == .landed` guard (`:133`).
- Zoom input after `close`: refused by the same guard. A pinch whose `lift` was lost is recovered by `.arrived`, which re-fits any `target < 1` (`:148`). A hand that releases Cmd mid-scroll sends `.pan` instead of `.lift` (`+Zoom.swift:60-63`) and is recovered the same way.
- `landed` after `close`: ignored (`:124`).
- Re-entrancy: `run` finishes `zoom.reduce` before acting on the effect (`+Zoom.swift:18-31`), so `moveFrame` calling back into the editor (`onReveal`) cannot overlap a mutation of `zoom`.
- Motion 0: `zoomTween.animate` with duration 0 calls `set` and the completion at once, so `.arrived` is sent inside `animate` and can issue a nested `animate` (the spring-back). It ends because the nested one targets 1 (`:151`).

### Zoom glue: `fitBeforeHide` and `hideWindows` (implicit)

Owner: `AnnotationController.swift:506` (`fitBeforeHide`) and `:514` (`hideWindows`); also `hide(then:)` `:472`, `abandon()` `:456`, `prepare` `:161`. Tests: none.

Brings the zoom back to the fitted size before the annotator's window comes down, so the card flies home from the fitted frame. The run's `.park` drives it.

**States**: `zoomTween` ticking or not; the local `answered` flag (`:508`); `zoom.phase`; `removal` (`WindowRemoval.generation`, `link`; `WindowRemoval.swift:13-16`); `window`; `current`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| open | `hide(then:)` | closing | `current = nil`, `park()`, `fitBeforeHide`: `zoom.reduce(.close)` |
| closing | `.close` gave no spring, or no window | closed | `done()` now |
| closing | `.close` gave a spring | waiting | `zoomTween.animate(… completion: once)`, plus a deadline `asyncAfter(motionScaled(seconds) + 0.3)` that calls `once` (`:509-511`) |
| waiting | spring arrives or deadline fires, first of the two | closed | `once` runs `done` once: `hideWindows()`, then the caller's completion (the run's `.parked`) |
| waiting | the other of the two | closed | `answered` stops a second `done` |
| closed | `hideWindows` | — | `zoomTween.stop()`, `toolbar.hideSoon()`, `shadowOpacity = 0`, `removal.start(…)` (hide the frame view on the next main turn, `orderOut` after 3 display refreshes) |
| any | `prepare` | open | `removal.cancel()` (`:168`), `zoom` gets `.prepare`, `zoomTween.set(1)` |

**Invariants**

- `hide` is called once per `prepare`, by the reducer (comment `:471`). Checked by: nothing.
- The deadline covers a spring that never arrives (comment `:504`). Checked by: nothing.

**Late and concurrent answers**

- A spring that never ticks (dead display link): the deadline calls `once` (`:511`), then `hideWindows` stops the tween.
- Reduce Motion or motion 0: `animate` answers inside the call.
- A removal's late `hide` or `remove` after a new `prepare`: dropped by the `generation` compare (`WindowRemoval.swift:22`); `cancel` at `:34`.
- Another writer to `zoomTween` during a close would drop `once`, and the window would wait for the deadline ([flights-3](#flights-3)).

### DimPanel (implicit)

Owner: `DimPanel.swift:7`. Used by `ThumbnailController.swift:804` (`dim.show`, at `.prepare`) and `:872` (`dim.hide`, at `.endRun`). Tests: none. The written contract is `docs/scrim-fade-2026-10-31.md`.

The scrim behind the annotator. It fades in and out on a spring.

**States**: `isVisible`, `generation` (`:8`), `fadeCount` (`:9`), `spring` (`:14`), and the layer opacity animation under the key `"fade"`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| hidden | `show` | fading in | `generation += 1`, `orderFront`, `fade(to: 1, fromNothing: true)` |
| fading in, shown | `show` | fading in | restarts from the spring's current value (`:90-92`); settings re-applied |
| fading in, shown | `hide` | fading out | at the end, `orderOut` only if `generation == gen` (`:71`) |
| fading out | `show` | fading in | `generation` bumped, so the hide's `orderOut` is dropped (`:71`); the fade turns around from where it is |
| fading out | `hide` | fading out | the second hide replaces the animation; the first completion runs and fails the generation compare |
| hidden | `hide` | hidden | `fade` finds value 0 and does not animate; completion runs at once; `orderOut` of an off-screen panel |

**Invariants**

- The scrim is never fully opaque (`alphaValue = 0.995`, `:27`). Checked by: nothing.
- A hide never orders out a panel that a later `show` raised. Checked by: the `generation` compare (`:68-73`).

**Late and concurrent answers**

- A superseded fade's `CATransaction` completion runs when its animation is removed. It writes the final alpha only if `fadeCount == thisFade` (`:113`) and orders out only if `generation` matches (`:71`).

### BackdropPanel (implicit)

Owner: `BackdropPanel.swift:14`. Driven by `CornerKeys.swift:96` (`show`) and `:100` (`hide`). Tests: none.

The blurred backdrop behind the stack. It fades with one `Tween` and slides with another.

**States**: `alpha` Tween, `slide` Tween, `isVisible`, `strip`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| hidden | `show` | visible | `slide.set(0)` (`:57`), `orderFront`, alpha tween to 1, slide tween to 1 |
| visible | `show` | visible | tweens retarget; the pending hide's completion is replaced, so the hide cannot `orderOut` (`Tween.animate` `:47`) ([flights-3](#flights-3)) |
| visible | `hide` | hiding | tweens to 0; alpha's completion orders out if `alphaValue == 0` (`:107`) |
| hidden | `hide` | hidden | `animate` with `target == value` runs `set` and the completion at once (`orderOut` again) |

**Invariants**

- A later `show` cancels an earlier `hide`'s `orderOut`. It relies on `Tween` replacing the completion on retarget. Checked by: nothing. ([flights-3](#flights-3))

**Late and concurrent answers**

- The slide may still be moving after `orderOut`: the next `show` resets it with `slide.set(0)` only when `!isVisible` (`:57`).

## The corner and the stack

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

**States**: `visible` (`:57`), `panel.isVisible`, `keys.presentation.mode`, `model.isStack` (`StackModel.swift:41`; follows `mode` only when mode is not `.hidden`, `:63`), `model.slidingOut` (`:17`), `model.offscreen` (`:12`), `model.cards`, `dismissGeneration` (`:64`), `shrinkGeneration` (`:65`), `pinnedScreen`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| not `visible` | `show` (`:226`) | `visible = true` through `present` (`:1299`) | bumps `dismissGeneration`; sends `cardsShown`; then `leaveCorner` |
| `visible` | `show` | card inserted through `insert` (`:1366`) | `shiftUp` (`:1430`) when the column is non-empty and the entrance is `.slide`; else plain insert; then `leaveCorner` |
| not `visible` | `dismiss(by:)` (`:671`) | — | — (guard) |
| `visible` | `dismiss(by:)` | `slideOut` (`:678`): `visible = false`; bumps `dismissGeneration`; ends forming flights; `model.slidingOut = true`; `offscreen = all cards` | after the slide: if the generation is unchanged and still `!visible`: `orderOut`, remove all cards, clear selection, `outCards`, forming and scroll, `pinnedScreen = nil`, send `slidOut` |
| sliding out | `present` | the slide-out is reversed; cards turn around | `dismissGeneration` bumped, so the removal at `:710` skips |
| lone card in the editor | `takeOutOfPanel` (`:950`) | card removed; if the column is now empty, `visible = false` | `panel.orderOut`; mode stays `.thumbnails` |

**Invariants**

- A slide-out's removal runs only if `dismissGeneration == gen && !visible`. Checked by: the guard at `ThumbnailController.swift:710`; no test.
- After a `slidOut` that finds `mode == .hidden`, focus goes back. Checked by: `CornerPresentationTests.testTheFocusGoesBackOnceTheColumnHasSlidOut`, for the reducer only. The controller path skips `slidOut` when the generation was bumped ([corner-6](#corner-6)).

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
- `leavesOnItsOwn` going false invalidates the timer but going true again does not re-arm it. ([corner-5](#corner-5))

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
- An answer to an earlier send is dropped. Checked by: `testAnAnswerToAnEarlierSendIsDropped`. The written rule "a failure is never lost" disagrees for a re-sent card. ([corner-10](#corner-10))
- The grace countdown returns when a covering Copied expires. Checked by: `testACopiedNoticeGivesTheCountdownBackWhenItExpires`.
- A notice moved by `rename` still expires. Checked by: `CardNoticesTests.testANoticeOnAFileRenamedDuringItsHoldStillExpires`: `expire` takes only the notice's id (**fixed**, [corner-1](#corner-1)).
- `awaitingAnswer` entries for files that left, the controller's timer wiring and the `seen` computation. Checked by: nothing.

**Late and concurrent answers**

- A timer that fires after a newer notice: the id token in `expire`, `CardNotices.swift:150`.
- A late `released`, `cancelled` or `answered`: compared by request id.
- An answer for a card nobody sees: the unseen-card rule at `:132`.
- `finished` and `replyFailed` defer to a later waiting send (`:138,141`).
- A file renamed after a send: `sentShots` follows the rename in `AppDelegate` (`:501`).

### Stack selection, focus and hover (implicit)

Owner: `StackModel.swift:37-38,20,23`. Tests: `StackModelTests.testSelectionNumbersCountInTheOrderTheCardsWereSelected`, `testPickingACardAgainPutsItLast`, `testSelectionChangesReportWhatJoinedInOrderAndWhatLeft`. They cover selection order only.

Which card keys act on, which card the pointer is over, and which cards are selected. `model.focused` is the one variable keys read.

**States**: `selection` (ordered ids), `focused` (`StackModel.swift:38`, the keyboard ring), `hoveredCard` (`:20`, `didSet` calls `onHover`), `holdsHover` (`:23`, hover frozen while the wheel moves the column), `pressedCard`; controller timer `wheelSettling` (`ThumbnailController.swift:52`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| keyed stack | `toggle`, `moveFocus`, Cmd+A, Esc (`handleKey`, `:1085`) | selection or `focused` change | — |
| not `holdsHover` | `CardView.onHover` (`CardView.swift:204`) | `hoveredCard` set | `onHover` closure (`:136`) sets `focused` only when `keys.isKeyed` |
| `holdsHover` | `CardView.onHover` | — | — (ignored) |
| `focused == nil` | `takeKeys(.current)` (`:276`) | `focused = hoveredCard ?? cards.first` | — |
| card exists | `takeKeys(.card(id))` | `focused = id` | — |
| any | `releaseKeys` (`:282`) | `focused = nil` | — |
| any | `present` | `focused`, `hoveredCard` (unless kept), selection, `lift`, `entranceRanks` cleared | — |
| any | `StackModel.removeCards`, which `remove(_:)`, `removeOverflow`, the stitch and the slide-out all call | `focused` moves to the newest card if its card left (**fixed**, [corner-3](#corner-3)); `remove(_:)` also filters the selection, `removeOverflow` deselects the card it drops; `hoveredCard` untouched ([corner-2](#corner-2)) | — |
| any | wheel `scroll` → `holdHover` (`:1187`) | `holdsHover = true`; 0.15 s timer replaced on each step | — |
| `wheelSettling` fires | `hoverAfterWheel` (`:1198`) | `holdsHover = false` | if `visible`, hover = the card under the pointer now |

**Invariants**

- The focused card is where keys act, and `focused` and `hoveredCard` name a card in `cards`. For `focused`, checked by `StackModelTests.testWhenTheFocusedCardLeavesTheNewestTakesTheFocus`: `StackModel.removeCards` gives the focus to the newest card when its card leaves (**fixed**, [corner-3](#corner-3)). For `hoveredCard`, checked by nothing: no removal clears it ([corner-2](#corner-2)).

**Late and concurrent answers**

- The wheel timer is replaced, not stacked (`:1189`). On fire it re-reads the cards and checks `visible`. A hover exit while held is repaired by the recompute (`:1204`).

### Stitch converge (implicit)

Owner: `ThumbnailController.stitched` (`:543`). Tests: none.

Flies the pieces of a stitch into one new card while the finished image fades in. The flights themselves belong to `TransitionLayer`.

**States**: `model.forming` (`StackModel.swift:19`, cards whose slot is held and drawn empty), `stitchGeneration` (`:66`), the result card at `cards[0]`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| `visible`, `isStack`, `!run.isActive`, 2+ pieces, all on screen | `stitched` | `forming` = pieces + result; pieces removed; result inserted at 0; selection cleared; `focused` cleared if a piece | `flights.converge` |
| any other | `stitched` | — | refused |
| converging | converge completion (`:567`) | `forming` minus ids and the result | `showCopied([result.shot])` if `stitchGeneration` is unchanged |
| converging | `slideOut` (`:687`) | `flights.end` makes each piece answer `dropped` | completion runs a turn later (`TransitionLayer.swift:275`); the result then comes up as a lone thumbnail through `showCopied` → `show` → `present`, which cancels the slide-out's `slidOut` ([corner-6](#corner-6)) |

**Invariants**

- The image is never on screen twice, and a stitch never finishes in silence. Checked by: nothing on the controller side.
- `targetCards()` does not filter forming cards, so Cmd+A can select the result slot. ([corner-7](#corner-7))
- The destination frame is computed once (`:568`); a card inserted during the converge moves the slot. ([corner-8](#corner-8))

**Late and concurrent answers**

- Dropped pieces still finish the converge: `TransitionLayer.swift:267`.
- A stale completion skips the Copied notice by generation: `ThumbnailController.swift:572`.
- `reshape` skips forming cards: `:1276`.

### shiftUp and card entrance (implicit)

Owner: `ThumbnailController.shiftUp` (`:1430`). Tests: none.

Inserts a card into the open stack without animating the layout change; the new card slides in after the old ones are lifted back.

**States**: `model.entering` (`StackModel.swift:12`), `model.lift`, `model.offscreen`, `shift` (`ThumbnailController.swift:1417`), `model.scroll`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| visible stack | `shiftUp` | card inserted at 0, `lift` set for every old card, `scroll = 0` | synchronous |
| next turn | `first` | card removed from `offscreen` | then `withAnimation`: `lift = [:]`, `removeOverflow()`, `relayout()` |
| after `shiftUpDuration` | clear | `entering` cleared if still this card | — |

**Invariants**

- `removeOverflow`, now `StackModel.removeOverflow(over:)`, drops the oldest card that is not in `outCards` or `forming` (**fixed**, [corner-4](#corner-4)).
- A dismissal in the same turn as `shiftUp` gets undone by `first`, which un-parks the new card. ([corner-13](#corner-13))

**Late and concurrent answers**

- The `entering` clear compares ids (`:1451`). A second insert adds to the first's remaining lift through `liftLeft` (`:1457`). `present` recomputes lifts for kept cards.

### StackSweep (implicit)

Owner: `StackSweep.swift:7`. Tests: none.

The drag-select gesture over the selection circles, with auto-scroll while the pointer is near an edge.

**States**: `anchor: Int?` (`:17`, an index into `model.cards`), `selecting` (`:18`), `before` (`:19`), `fromTop` (`:22`), `autoScrollLink` (`:23`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `move(toYFromTop:)` from `model.onSweep` | `anchor` set; selection updated; maybe starts the link | sends `selected` |
| any | `end()` from `onSweepEnd`, `insert`, `present`, `remove`, `stitched` | `anchor`, `fromTop`, link cleared | — |
| link running | display-link tick | — | stops itself when `!isVisible()`, `!model.isStack` or speed is 0; `dt` clamped for a stalled run loop (`:109`) |

**Invariants**

- `anchor` names the card the drag started on, by id; when that card has left, the next move starts a new sweep. Checked by: `StackModelTests.testASweepWhoseFirstCardLeavesStartsAgainFromTheCardUnderThePointer` (**fixed**, [corner-9](#corner-9)). `removeOverflow` and `slideOut`'s final `removeCards` do not call `end()`, which is now safe.

**Late and concurrent answers**

- `end()` at every insert, present, remove and stitch site keeps `anchor` valid; the tick re-checks visibility.

### HotKey (implicit)

Owner: `HotKey.swift:7`. Tests: none (`HotKeySpecTests` parse key strings only).

One Carbon global hotkey with a hold timer.

**States**: `isDown` (`:19`), `holdTimer` (`:18`), `ref`, a static `keys` table.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| `isDown` | Carbon pressed (`:50`) | — | — (ignored, `:62`) |
| not `isDown` | pressed | `isDown = true` | `action()`; arm the hold timer |
| any | released | `isDown = false`; timer invalidated | — |
| armed | hold timer fires | — | `hold()` |

**Invariants**

- Only a release event clears `isDown`, so a lost release leaves the shortcut dead until the setting changes. Checked by: nothing. ([corner-12](#corner-12))

**Late and concurrent answers**

- The key table holds entries weakly; `deinit` unregisters.

### ModifierTap and KeyMonitors (implicit)

Owner: `ModifierTap.swift:9`, `KeyMonitors.swift:8`. Tests: none.

The double-tap-a-modifier shortcut. `KeyMonitors` installs global and local event monitors once Accessibility is granted.

**States**: `ModifierTap.count` (`:18`), `last` (`:19`), `holdTimer` (`:20`), `monitors` (`:17`); `KeyMonitors.monitors` (`:9`), `retry` (`:10`, a 2 s timer).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `flagsChanged` of another modifier | `count = 0` | hold timer kept ([corner-11](#corner-11)) |
| any | this key released | hold timer invalidated | — |
| any | this key down with `mods == flag` | `count + 1` | `action()` and arm the hold timer once `count >= taps` |
| any | any `keyDown` or click, global or local | `count = 0`; timer off | — |
| not trusted | retry timer | — | tries to install monitors; stops once granted |

**Invariants**

- A hold fires only while the one key is held alone. Checked by: nothing; another modifier does not stop the timer. ([corner-11](#corner-11))

**Late and concurrent answers**

- A global and a local monitor both report one event; only an event newer than the last passes, `KeyMonitors.swift:33`. Callbacks hold `self` weakly.

### StackSwipe (explicit)

Owner: `StackSwipe.swift:13`, run by `StackSwipeDriver` and fed by `ThumbnailController.scroll` (`:1170`). Tests: `StackSwipeTests`.

A sideways two-finger swipe moves the column toward the edge and closes the corner (`docs/rules/stack.md`). **States**: `phase` (`:50`) is `idle`, `touching`, `deciding`, `vertical`, `horizontal(raw)`, `closing` or `leaving`, with `offset`, a spring and `carriesColumn` (`model.swipeExit`).

| State | Event | Next state | Effects |
|---|---|---|---|
| not `closing`, `leaving` | `mayBegin` | `touching`; a spring stops | — |
| not `closing`, `leaving` | `began` | `deciding`; a spring stops | — |
| `deciding` | `changed` under 3 pt | unchanged | — |
| `deciding` | `changed` | `horizontal` if sideways and swipes are on, else `vertical` | `moved` or `scrollColumn` |
| `horizontal` | `ended` toward the edge fast enough, or past the distance | `closing` | `close`: `dismiss(by: .swipe)` |
| `horizontal` | other `ended`, `cancelled` | `idle`, springing to 0 | — |
| `horizontal` | swipes turn off | `vertical`, springing to 0 | — |
| `closing` | `leave` from `slideOut` (`:706`) | `leaving`, springing past the edge | `carriesColumn` |
| `closing` | the dismissal did not happen | `idle`, springing to 0 | `cancelClose` |
| `closing`, `leaving` | `presented` from `present` (`:1343`) | `idle`, springing to 0 | `carriesColumn` until it lands |
| any | `reset` from the removal (`:719`) | `idle`, offset 0; the last axis stays | — |
| `vertical` | `ended` | `idle` | `scrollColumn` |
| not `closing`, `leaving` | momentum | unchanged | `scrollColumn` after a vertical gesture |
| not `closing`, `leaving` | no phase (a wheel) | unchanged | `scrollColumn` |
| `closing`, `leaving` | any scroll | unchanged | — |

**Invariants**

- Momentum never moves the column, and a gesture without `began` never swipes. A leaving column is never caught. Checked by: `StackSwipeTests`.

### StackAreaReader (implicit)

Owner: `StackAreaReader.swift:7`. Tests: none.

Reads where the Dock's tiles are, so the column steps around them. The read can fail while the Dock is starting.

**States**: `dockTiles` (`:15`, the last good read), `dockRetry` (`:16`), `dockReadsLeft` (`:17`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `read` (every `layoutPanel`), read fails | `dockTiles` kept | schedule one retry in 0.5 s, at most 8 per presentation |
| any | `read` succeeds | `dockTiles` updated | cancel the pending retry (`:36`) |
| any | `presented` (when `visible` becomes true) | `dockReadsLeft` reset | — |
| retry fires | not visible | — | dropped |
| retry fires | Dock answers | — | `relayout` |
| retry fires | Dock silent | — | schedule again |

**Invariants**

- At most one retry is pending (`dockRetry == nil` before scheduling). Checked by: nothing.

**Late and concurrent answers**

- The retry rechecks `isVisible` when it fires.

## The editor and drawings

The editor is a pure reducer (`EditorCore`) driven by a view (`EditorView`) that turns events into inputs and runs the effects it returns. Drawings are stored one file per screenshot by `Drawings`, and the clipboard and drag paths render them through `RenderingQueue`.

### EditorCore (explicit)

Owner: `EditorCore.swift:12`, reducer `reduce` at `EditorCore.swift:477`. Tests: `EditorCoreSequenceTests.testRandomSequencesKeepTheInvariants` (drives `checkShape`, `checkUndo`, `apply`), `EditorCoreTests`, `EditorCoreOpeningTests.testTheNextImageFinishesWithWhatTheBarStillOffers`.

The editor's whole logic: gestures, typing, selection, undo, the 0.3 s save timer, and agent marks joining. `EditorView` sends one `Input` per event and runs the returned `Effect`s in order. A drawing is a screenshot's marks (`Drawing.swift`); a hand-over gives the host the drawing to store.

**States**: the properties that together form the state.

- `isOpen` (`EditorCore.swift:360`): false until `open`, false again after `park`.
- `gesture: Gesture?` (`:370`) with `Phase` (`:425`): `pressed`, `drawing(id)`, `wrapping`, `brushing`, `moving(originals:copies:)`, `resizing(id, pos)`, `draggingEnd(id, kind)`, `bending(id)`.
- `typing: Typing?` (`:372`, type at `:450`): the text mark being typed.
- `edit: MarkEdit?` (`:378`): the open undo step. Set while a gesture has changed marks, or while typing.
- `undoSteps`, `redoSteps` (`:373-374`), `nudging` (`:383`), `heldArrows` (`:381`).
- `noteMark: NoteMark?` (`:385`, type at `:440`): see HeldKey below. `holdsKey` (`:448`) is `noteMark?.toolBefore != nil`.
- `unsaved` (`:387`): the drawing changed since the last hand-over.
- `selection`, `hover`, `tool`, `zoom`, `style`, `metrics`, `markStyle`.
- `finishes` (`:368`): what Return and Cmd+Return do. The host sets it from the toolbar's offer.
- `reportedTool`, `reportedCursor`, `announcedSelection`: what `settle()` (`:549`) last told the view.

**Inputs** (`Input`, `:51`) and who sends them (`EditorView` unless noted): `open` (`EditorView.swift:146`); `pointerMoved`, `pointerExited`, `pointerPressed`, `pointerDragged`, `pointerReleased` (mouse handlers `EditorView.swift:658-731`, `take` `:682`, `zoomCameToRest` `:422`); `modifiersChanged` (`flagsChanged` `:578`); `keyDown`, `keyUp` (`:565`, `:573`, `performKeyEquivalent` `:584`, `typingKey` `:555`, `releaseHeldArrows` `:639`); `setTool` (toolbar, `AnnotationController.swift:90`); `enterCanvas` (`:199`); `zoomChanged` (`pictureMoved` `:411`, `open` `:152`); `tweaksChanged`, `rescaled` (`applyTweaks` `:226-228`); `typingChanged`, `typingEnded` (`TypingField.onChange` and `onResign`, `:452-457`); `timerFired` (`scheduleHandOver` `:314`); `paste` (`.readClipboard` effect `:295`, drop `:831`); `agentMarks` (`EditorView.join` `:858`, from `Drawings.add`); `done`, `send` (toolbar); `park` (`EditorView.park` `:162`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| not open | any but `open` | — | Ignored (`:481`). |
| any | `open(d)` | open, idle (every other property reset, `zoom` and `finishes` kept) | If `typing != nil`: `.endTyping`. Unsaved edits, `undoSteps`, `gesture`, `noteMark`, `heldArrows` are dropped. `.cancelTimer`, `.tool`. Refused, `isOpen` stays false, when the pixels are 0 or `pointScale` is invalid (`:580`). **(fixed)** `finishes` is kept ([editor-1](#editor-1)). |
| open, idle | `pointerPressed` | `gesture = pressed`, or typing begins, or a zoom request | `pressed` (`:733`) ends typing first if any; the press target decides. |
| `pressed` | drag past the drag distance | `drawing`, `moving`, `resizing`, `draggingEnd`, `bending`, `wrapping` or `brushing` | `dragPhase` (`:818`) picks the phase; `startDrag` (`:842`) opens `edit` for the phases that change marks. |
| any gesture | `pointerDragged`, `modifiersChanged` | same gesture, redrawn | `update` (`:868`) redraws from the press to the pointer. |
| any gesture | `pointerReleased` | `gesture = nil` | `released` (`:980`): a big-enough `drawing` commits, otherwise reverts; moves, resizes, end drags and bends commit. A commit calls `changed()`. |
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
| open, idle | `keyDown` Cmd+Z, Shift+Cmd+Z | open | `undo` or `redo` (`:705-722`); `changed()`. |
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
- `finishes` is the host's, and opening an image leaves it alone (comment at `:367`). `open` reset it until [issue 1](#issue-1). Checked by: `EditorCoreOpeningTests.testTheNextImageFinishesWithWhatTheBarStillOffers` ([editor-1](#editor-1))
- A held arrow key is cleared by `park` and by the stale-key guard (`:1335`). Checked by: nothing.
- Any new undo step clears the redo stack, an agent push included (`push` `:700`), so agent marks arriving after Cmd+Z drop the redo history. Checked by: nothing.

**Late and concurrent answers**

- Any input after `park` or before `open`: dropped by `isOpen`, `:481`.
- The 0.3 s save firing after `park`: `park` emits `.cancelTimer` (`:609`) and sets `unsaved = false` (`:611`); a late `timerFired` is dropped by `isOpen`.
- The save firing after another image opens: `.cancelTimer` (`:591`) and `EditorView.stopTimers()` (`EditorView.swift:137`).
- The save firing while a button is held: `timerFired` re-arms (`:620`); `drawingForHost` shows the gesture's marks reverted (`:633`).
- A text with no words is never handed over (`:634`).
- A lost release: a move with no button down cancels the gesture (`:728`); `zoomCameToRest` sends a move only with no button down (`EditorView.swift:420`).
- Agent marks arriving mid-gesture survive Esc: `reverted` re-places only the touched marks (`EditorHistory.swift:42`).
- `step` saves and restores the open edit (`:674-680`), so a join does not end a gesture's or typing's edit.
- `open` on a core that is still open drops its unsaved edits, undo history, gesture and typing (`:574-579`). Nothing guards it. Every `prepare` is preceded by `park()` or `abandon()` today (`AnnotationController.swift:464`, `:477`).

### HeldKey (implicit)

Owner: `EditorCore.startsNote` (`EditorCore.swift:1388`), `holdsKey` (`:448`), `EditorView.heldKeys` (`EditorView.swift:104`). Tests: none.

A tool key pressed right after a box or arrow is drawn may be the first letter of a note. The core switches the tool at once, and the view holds the key event until the next key shows whether the person is typing.

**States**: `noteMark` and `noteMark.toolBefore` in the core; `heldKeys: [NSEvent]` in the view.

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
| Held | any character | None | `tool = toolBefore`, `newNote`, `.passKeysToText` replays `heldKeys` plus the event into the text view (`EditorView.swift:276-282`). |
| Held | pointer move, key up, modifiers, zoom, tweaks, rescale, timer | Held | — (`keepsNoteMark`, `:1631`). |
| Armed or Held | any other input (press, `setTool`, typing, `paste`, `agentMarks`, `done`, `park`, undo key) | None | `tool` stays as picked. `EditorView.handle` clears `heldKeys` when `!core.holdsKey` (`:264`). |
| Held | `park` | Held | `park` does not clear `noteMark`; `heldKeys` stay until the next `open`. Harmless. |

**Invariants**

- `holdsKey` implies the view holds at least one event. Only `keyDown(with:)` passes an event (`.holdKey` ignores nil, `EditorView.swift:275`), and Cmd keys are excluded from `startsNote` (`:1389`). Checked by: nothing.
- A key held for good, with no further key or press, leaves the tool switched. That is the design (comment at `:1384`).

**Late and concurrent answers**

- `newNote` can fail to place (`placed` is nil): `.passKeysToText` then finds no `typingField` and drops the keys (`EditorView.swift:278`); `handle` clears `heldKeys`.

### HeldToolLetter (explicit)

Owner: `HeldToolLetter.swift:7`. Tests: `ToolbarOfferTests` (not covered by this area; the toolbar section owns the field's use).

The same hold for the toolbar's message field. State: `toolBefore: Tool?` (`HeldToolLetter.swift:9`). `key(...)` returns `hold`, `type(restoring:)`, `pass` or `swallow`. `keepTool()` runs on a press or lost keys. `Model.begin` resets it (`AnnotatorToolbar.swift:153`).

### EditorView session (implicit)

Owner: `EditorView.swift:11`. Tests: `EditorViewTests` (park, join, late-bitmap, typing tests).

The view owns the timers, the text view being typed, and the hand-over to the host. It runs `core.reduce` to completion before it runs any effect.

**States**: `core.isOpen`; `handOverTimer` (`:96`); `restTimer`, `zoomMoving` (`:97-98`); `typingField` (`:87`); `lingering` (`:91`); `settling: Tween?` (`:93`); `heldKeys` (`:104`); `heldArrows` (`:102`); `textPress` (`:710`); `revealPending` (`:88`); `settingSize` (`:100`); `placedPicture` (`:85`). Together they make four phases:

- Closed: `core.isOpen == false`; after `park`, `picture.marks.isParked`. Bitmaps already on screen stay; none arrives.
- Open: `core.isOpen`.
- Typing: `typingField != nil`. It equals `core.typing != nil` after each effect run.
- Lingering: `lingering != nil`. The ended session's text view stays over its text until the text's bitmap is drawn or the text is gone (`settleLingering` `:509`). `settling != nil` while the tag springs to balanced lines (`settleLines` `:484`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `open` | Open | `stopTimers`, `heldArrows = []`, new `MarkLayers` through `picture.open`, core `.open`, `dropLingering`. If the core refuses: logs `[editor] error open-refused`, stays Closed. |
| Open | `park()` | Closed | Runs the core's non-hand-over effects, `refresh`, `picture.park()`; returns the drawing. Idempotent: returns nil when not open. |
| Closed after `park` | `clear()` | Closed, reset | No change if `core.isOpen`. Else `stopTimers`, `dropLingering`, `core = EditorCore()`, picture parked and reopened empty. |
| Open | `.beginTyping(id)` | Typing | New `TypingField` unless the id is the same; its text view becomes first responder. |
| Typing | `.endTyping` | Lingering | `typingField = nil` first, first responder back to the view, `lingering = field` (`:468-478`). |
| Typing | text view resigns to another responder | Typing or Open | `onResign` sends `.typingEnded` only if `typingField === field` (`:455`). |
| Lingering | text drawn or mark gone | Open | `dropLingering` (`onTextDrawn` `:117`, `refresh`). |
| Open | zoom or size step | Open | `pictureMoved` (`:402`) sets `zoomMoving`, re-arms `restTimer`. At rest, `zoomCameToRest` re-hovers and redraws texts. |
| Open | `applyTweaks` | Open | `.tweaksChanged` then `.rescaled`. Typing and lingering fields are restyled (`:231-234`), with no check for a composition. ([editor-3](#editor-3)) |
| Typing | Cmd+Z | Typing | `performKeyEquivalent` takes it (`:591-594`) before `typingKey`'s composition check (`:556`); `undo` calls `field.undo.undo()` when `canUndo` (`:605-606`). ([editor-4](#editor-4)) |
| Typing | text view `onChange` | Typing | Sends `.typingChanged` with no check that the field is still `typingField` (`:452`). ([editor-5](#editor-5)) |

**Invariants**

- `typingField` mirrors `core.typing`. Checked by: nothing.
- `park` returns its drawing and never sends it through `onHandOver`. Checked by: `EditorViewTests.testParkAnswersAtOnceWithTheDrawingAndIgnoresInputAfterwards`.
- `join` returns its drawing and sends nothing through `onHandOver`. Checked by: `EditorViewTests.testAJoinAnswersWithTheDrawingAndHandsNothingOver`.

**Late and concurrent answers**

- A timer after `park`: `park` runs `.cancelTimer`; `timerFired` is dropped by `isOpen`; `zoomCameToRest` guards `isOpen` (`:419`).
- A timer after reopen: `open` calls `stopTimers` (`:137`); so does `clear` (`:184`).
- `finishForHost` inside `park` may emit `.scheduleTimer`; the `.cancelTimer` that follows (`EditorCore.swift:609`) leaves no timer.
- Re-entrancy: text-view tracking inside `.passPressToText` runs timers in common run-loop modes (`:320`). A nested `timerFired` cannot overlap a reduce, because `handle` finishes `core.reduce` before it runs effects.
- `onResign` of a field that already ended (`makeFirstResponder(self)` inside `.endTyping`): ignored by the identity guard (`:455`).
- A composition owns every key: `typingKey` refuses while `hasMarkedText()` (`:556`); `placeTypingField` does not restyle during one (`:546`).
- `revealCaretSoon` reads `typingField` after the turn (`:537`), so a session that ended gives no reveal.
- A late image decode: `setImage` has no guard of its own; `AnnotationController.open` drops it by comparing openings (`AnnotationController.swift:226`).

### MarkLayers text bitmap (implicit, one per text mark)

Owner: `MarkLayers.swift:19`; the editor's plan is `EditorPicture.plan` (`EditorLayers.swift:127`). Tests: `EditorViewTests.testABitmapThatArrivesAfterItsTextMovedIsNotShown`, `EditorViewTests.testNoBitmapIsShownAfterParkOrOnAnotherImage`, `CardMarksTests`.

Each text mark's words are drawn off the main thread into a bitmap and shown on a layer. The editor, cards and flights each own a plan of what to ask for.

**States**: per `Text` record (`MarkLayers.swift:116`): `drawn`, `detailDrawn` (what the layers show); `wantWhole`, `wantDetail` (what the plan asks for); `pending: (part, target)?` (one draw on its way); `wanted: Wanted` (what the queue may still draw); `slid`. Per layer: `isParked` (`:43`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| no `pending`, `want != drawn` | `show` calls `schedule` (`:366`) | `pending = (part, target)` | Draw queued on `queue`. |
| `pending` | queue turn | draw runs, or is skipped | Skipped when `wanted` no longer holds the target (`:386`). Else a `recent` cache hit, else a scaled copy, else a full draw. |
| `pending` | draw arrives (`arrived` `:405`) | `pending = nil` | Dropped when parked, the record is gone, or the identity differs (`:406`). Else the bitmap is stored only if `target == wantWhole` or `wantDetail` (`:411`, `:415`); then `update` and `schedule` the next. A draw that returned nil is recorded as drawn (`:396`, `:411-414`). ([editor-8](#editor-8)) |
| any | `park` | parked | `isParked = true`, `wanted = []`, `pending = nil`. No bitmap arrives after (`:176`). `show` is a no-op after (`:213`). |
| any | `clear` | cleared | `park`, then all layers and records dropped. |
| mark renamed by a reload | `show` calls `renamed` (`:312`) | record under the new id | `pending = nil`, so the old draw's answer finds no record at `texts[old]` and is dropped. |
| typing | `plan` | whole hidden | `wantWhole = nil` (`EditorLayers.swift:128-135`). A draw on its way is dropped in `arrived`, since its target is not `wantWhole`. |

**Invariants**

- A bitmap is shown only while its text still wants exactly that target (comment at `:16`). Checked by: `EditorViewTests.testABitmapThatArrivesAfterItsTextMovedIsNotShown`, `testNoBitmapIsShownAfterParkOrOnAnotherImage`.
- A text holds at most two bitmaps, a whole and a detail (comment at `EditorLayers.swift:28`). Checked by: `CardMarksTests` (a card's bitmap size only, `testACardsTextBitmapHasNoMorePixelsThanTheCard`).
- `drawn != nil` implies the whole layer shows that target. Checked by: nothing; a failed draw breaks it. ([editor-8](#editor-8))

**Late and concurrent answers**

- A draw answering after its text moved, was parked, or was renamed: dropped in `arrived` (`:406`, `:411`).
- The `Recent` cache holds surfaces weakly (`:76`).

### TypingField (implicit)

Owner: `EditorTextView.swift:20-60`. Tests: `EditorViewTests` (typing tests).

The text view for a note being typed. Its states are those of the EditorView session's Typing and Lingering phases. Extra properties: `settled`, `balanced`, `balancedColor`, `tag`. Its only operations are `place`, `settle`, `follow`, `setStyle` and `recolor`. `onChange` has no identity guard. ([editor-5](#editor-5))

### Drawings (implicit, per screenshot key)

Owner: `Drawings.swift:21`; files in `DrawingStore.swift:8`. Tests: `DrawingStoreTests`, including `testALoadThatBeganBeforeAWriteDoesNotAnswer`.

`Drawings` is the one writer of a screenshot's stored drawing. A `ScreenshotKey` (see `docs/glossary.md`) names the screenshot.

**States**, per key: the stored file (`keys` `:24`, disk); `revisions[key]` (`:31`); `changedAt[key]` (`:32`); the editor's open drawing for that key (`open` `:29`, a weak `OpenDrawing`); loads in flight.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `write(d with marks)` | stored | Refused when the screenshot file is gone (`:86`). Else the file is written atomically, `keys.insert`, `revisions += 1`, `onChange(key, d)`. |
| any | `write(d with no marks)` | no file | File removed. If the key was known: `keys.remove`, `revisions += 1`, `onChange(key, nil)`. |
| key known | `remove` | no file | Only if `changedAt <= observedAt` (`:106`). Removes the file, `changed(key, nil)`. |
| key known | `sweep` | no file | Only with an inventory that confirms absence and `changedAt <= observedAt` (`:144`). |
| key known, or editor open | `rename(old, new)` (`:119`) | stored under `new` | Store rewrites under `new`; then `open?.rekey`; `onChange(old, nil)`, `onChange(new, d)`. If the store throws, returns before `rekey` (`:123`), and the open editor keeps the old key, so its later writes are refused. ([editor-2](#editor-2)) Then `revisions[old] = nil` (`:137`), which reads as 0 again. ([editor-9](#editor-9)) |
| editor open for key | `add` | stored, open drawing joined | `open.join(made)` returns the joined drawing; `write(joined, "saved")`. Throws `writeFailed` if the write is refused. |
| no editor | `add` | stored | Read the stored drawing (or a new one), append, `write(.., "built")`. |
| any | `load(keys)` | — | Records `revisions` now; reads on `loads`; on the main thread, drops each key whose revision changed (`:73`). |

**Invariants**

- `keys` mirrors the files this build can read: the launch scan, then every write and remove. Checked by: `DrawingStoreTests.testKeysListTheDrawingsThisBuildCanRead`.
- The open editor's drawing wins over the stored one for `current(of:)`. Checked by: `testTheDrawingNowIsTheOpenOneOverTheStoredOne`.
- A load never answers older than a write. Checked by: `testALoadThatBeganBeforeAWriteDoesNotAnswer`.
- A rename moves the stored file and the open drawing. Checked by: `testARenamedScreenshotKeepsItsDrawingUnderTheNewKey`, `testTheOpenDrawingFollowsARenameAndItsLaterWritesLandUnderTheNewKey`. A failing store is not tested. ([editor-2](#editor-2))
- One write per agent push. Checked by: `testAPushToTheOpenDrawingWritesWhatTheJoinAnswersOnce`.
- A file from a newer build is never written or removed (`DrawingStore.swift:215`). Checked by: `testANewerVersionIsReadAsNoDrawingAndNeverOverwritten`.
- A read never moves a file; only the launch scan does (`DrawingStore.swift:187`). Checked by: `testAFileThatDoesNotParseIsSetAsideByTheLaunchScanOnly`.
- `rename` calls `onChange(new, drawing)` with the editor's live drawing while the file holds the stored one until the next hand-over. Checked by: nothing.

**Late and concurrent answers**

- A load that began before a write or remove: its answer for that key is dropped by the revisions compare (`:66-73`).
- A hand-over after the screenshot was trashed: refused at `:86`.
- A removal or sweep with an inventory older than the last change: refused by `observedAt` against `changedAt` (`:106`, `:144`).

### Rendering and clipboard promise (implicit)

Owner: `RenderingQueue.swift:7`, `PendingRendering` (`:122`), `Clipboard.swift:32-52`, `RenderingProvider` (`Clipboard.swift:103`), `DragItems.swift:14`. Tests: `RenderingPromiseTests`, for the promised item and a drag's file made from kept bytes; none for the queue's ordering.

Done, Cmd+C, Copy Drawing and a card drag render a drawing to a PNG on one serial queue. The clipboard holds a promise of the PNG until the rendering finishes. A card drag renders its PNG before the drag, from the hover or the press, and writes only the file when the drag begins.

**States**

- `PendingRendering`: pending, then finished(output) once. `finish` is idempotent (`RenderingQueue.swift:142`). `wait(timeout:)`, `isDone` and `whenDone` read it.
- Queue: each `render` adds one job to `firstJobs` or `jobs` under `lock` and enqueues one block. A block runs whichever job is next, `firstJobs` first (`:42-44`). The block count always equals the job count.
- Clipboard: `copyRendering` clears the pasteboard, writes one item (the path as text now; PNG, TIFF and file URL promised), and records `changeCount`.
- `DragItems`: `kept`, the PNGs rendered for drags, newest last, finished or not, each under its key (screenshot, drawing, text style, mark style); `ahead`, the one rendering `prepare` started that has not finished; `wanted`, the cards `prepare` named last.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `render(.first)` | queued ahead | Overtakes jobs not yet started. Senders: Done (`finishAnnotation`, AppDelegate `:603`), Cmd+C with nothing selected (`copyDrawing` `:611`). |
| any | `render(.inTurn)` | queued behind | Jobs of one order run in request order. Senders: Copy Drawing (`copyAnnotated` `:567`, completing through `finishCopyAnnotated` `:582`), drag (`DragItems.rendering(for:)` `DragItems.swift:83`, as bytes). |
| any | `resultURL` fails | finished (failed) | Finishes at once without queuing (`RenderingQueue.swift:36-38`, `:55-57`). |
| no `ahead`, or `ahead` finished | `prepare(cards)` (hover or press on a card) | `ahead` = the first wanted key not kept | Renders that key's PNG in turn and keeps it. Nothing when every wanted key is kept. |
| `ahead` pending | `prepare(cards)` | `ahead` unchanged | Only `wanted` changes. When `ahead` finishes, `trim` runs and the next wanted key starts. |
| any | drag begins (`items(for:)`) | file pending | Takes the kept PNG for each card's key, or renders one in turn, and calls `file(from:beside:)`, which names the file now and writes it on its own queue once the PNG exists (`RenderingQueue.swift:52`). A kept PNG that failed is rendered again. |
| kept over 32 MB | `trim` (after `prepare` and each rendering) | oldest finished entries dropped | Pending entries and the wanted keys' entries stay, so a wanted PNG is never dropped and rendered again. |
| pending | job runs | finished | Reads the screenshot file now, so a trash or rename before this fails as `unreadableImage`; the card says Not copied. |
| clipboard promised | paste before finish | waits | `RenderingProvider` waits up to 5 s on the main thread (`Clipboard.swift:108`); gives nothing if the rendering failed (`:113-117`). |
| clipboard promised | rendering fails | clipboard cleared, or kept | Cleared only if `changeCount` is unchanged (`Clipboard.swift:35-39`). |
| dragged item | rendering fails | path text stays | Only logged ("the drop gets no image for it", `DragItems.swift:53-55`). The string set at `Clipboard.swift:49` stays on the item. ([editor-6](#editor-6)) |
| Copy Drawing | last rendering done | files on clipboard | `finishCopyAnnotated` calls `Clipboard.copyFiles(urls)` (`:595`) with no `changeCount` check. ([editor-7](#editor-7)) |

**Invariants**

- The later of Done's and Cmd+C's clipboards wins; the earlier one's failure does not clear the later (guard `Clipboard.swift:37`). Checked by: nothing.
- When the last `.inTurn` rendering of a Copy Drawing is done, all of them are (serial queue, FIFO within an order; `finishCopyAnnotated` uses `wait(timeout: 0)` on each, `:586`). Checked by: nothing; no test mixes orders.

**Late and concurrent answers**

- A late failure against a newer clipboard: guard at `Clipboard.swift:37`.
- A paste before the rendering finishes: waits, `Clipboard.swift:119`. Each answer logs `[clipboard] gave` or `[drag] gave` with how long the main thread waited.
- A drop target that asks during the drag: answers from the kept PNG when it was ready (`[drag] cards=… ready=…`), else waits as a paste does.
- Copy Drawing finishing after the person copied something else: overwrites it. ([editor-7](#editor-7))

### DragSourceView press (implicit)

Owner: `DragSourceView.swift:34`, with `StackModel.drag(_:_:)` (`StackModel.swift:125`). Tests: none.

**States**: `downPoint`, `dragging`; in the model, `pressedCard` and `draggedCard`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | mouse down | `downPoint` set, `dragging = false` | `onPress(true)`. |
| pressed | drag past 5 pt, no items | `dragging = true` | `onPress(false)`. |
| pressed | drag past 5 pt | `dragging = true`, `draggedCard` set, `pressedCard` cleared | `items()` (writes the files from kept PNGs), `onDrag(.began)`, begins a drag session. The card keeps the press scale while it is dragged. |
| pressed, not dragging | mouse up | idle | `onPress(false)`, `onClick()`. |
| dragging | mouse up | `dragging` stays true | Swallowed by the session. |
| dragging | session ends | `draggedCard` cleared | `onDrag(.ended(pointerOnCard:))`: the card springs back from the press scale. The hover is cleared when the pointer is off the card and the hover is not held. |

**Invariants**

- `dragging` is reset only by the next mouse down. Checked by: nothing.

## The toolbar and destinations

The toolbar is the bar under the annotator's frame. It holds the tools, a target (the agent session Send goes to), a message field and Send or Reply. This area covers how the bar picks its target and offer, how a send progresses, how the bar comes and goes, and how the agent connections list sessions and take a line.

A destination is an `AgentDestination`: one agent session a line can go to. A startable row is a past Claude Code session, or a new one, that Send would start. A kept list is the last session list a connection answered, kept so the next opening can answer at once.

### AnnotatorToolbar.Model: target and offer (implicit)

Owner: `AnnotatorToolbar.swift:9`. Tests: `ToolbarOfferTests.testTheTargetSettlesOnHerdrsFocusAndStaysWhenCodexAnswersLater`, `testWithNoFocusTheTargetIsTheSessionUsedLastAndIsReplacedOnlyWhenItIsGone`, `testASwapKeepsTheTargetOnTheBarUntilTheNextImagesSettles`.

Holds which session Send goes to for the open image. `AnnotationController.beginDestinations` (`AnnotationController.swift:617`) and `destinationsAnswered` (`:623`) drive it, called from `AppDelegate.refreshDestinations` and `listDestinations` (`AppDelegate.swift:1350`, `:1371`).

**States**: the properties together:
- `destinations` (`:14`): the last list answered for this image. `startable` (`:16`): rows Send would start.
- `listed` (`:18`): every client has answered. `whole` (`:22`): the last complete list, possibly the image before's.
- `replyTo` (`:25`): the session this image came from. `target` (`:27`): the chosen destination.
- `picked` (`:41`): the person chose the target. `carried` (`:44`): the target is the image before's and waits for this image's first deciding answer.
- `offer` (`:131`) is derived (next machine). `reportOffer` (`:139`) calls `onOfferChanged` only when the offer changed.

A `decided` answer is one `DestinationChoice` marks as settled: complete, or any session marked by herdr.

**Transitions**

Events: `begin(replyTo:carryingTarget:)` (`:148`, sent by `beginDestinations` with `carryingTarget: toolbar.model.shown`, right after `annotator.prepare`, `AppDelegate.swift:116-118`); `answered(_:)` (`:167`, once per `SessionListing.deliver`); `pick(_:)` (`:186`, from the target menu a turn later, `AnnotatorToolbar.swift:260-266`).

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `begin(carryingTarget: false)`, or `target == nil` | `replyTo` set; `listed`, `picked`, `carried` false; `destinations`, `startable`, `target`, `whole` cleared | — |
| `target != nil`, not carried | `begin(carryingTarget: true)` | `carried = true`; lists, `target`, `whole` kept; `listed`, `picked` false | — |
| carried | `answered`, not decided | lists replace; `target` refreshed from the new list if same id; stays carried (`:175-177`) | — |
| carried | `answered`, decided | `carried = false`; `target = answer.pick` (may be nil) | — |
| not picked, not carried, `target == nil` | `answered`, decided | `target = answer.pick` | — |
| not picked, not carried, target set | `answered` | target kept, unless the answer is complete, the target is absent from it (`gone`) and the answer is decided: then `target = answer.pick` (`:181`) | — |
| picked | `answered` | lists, `listed`, `whole` update; `target` only refreshed to the object with the same id (`:173`), never replaced | — |
| any | `pick(d)` | `target = d`, `picked = true`, `carried = false`. No check that `d` is in a list or belongs to this image ([toolbar-4](#toolbar-4)) | — |

**Invariants**

- The target settles once, then changes only when its session is gone from a complete list (doc comment `:164-166`). A nil `pick` leaves `target == nil`, so the next decided answer settles it. Checked by: `ToolbarOfferTests.testTheTargetSettlesOnHerdrsFocusAndStaysWhenCodexAnswersLater`, `testWithNoFocusTheTargetIsTheSessionUsedLastAndIsReplacedOnlyWhenItIsGone`. A failed Codex listing can break it ([toolbar-2](#toolbar-2)).
- A pick stays even when the list no longer has it. Checked by: the same two tests.
- A swap keeps the old target until this image's first deciding answer. Checked by: `ToolbarOfferTests.testASwapKeepsTheTargetOnTheBarUntilTheNextImagesSettles`.
- Reply stays Send until the whole list answers. Checked by: the same test.
- The target belongs to the open image, and a carried target still exists. Checked by: nothing ([toolbar-4](#toolbar-4)).

**Late and concurrent answers**

- A list answer for an ended opening: dropped, guard at `AppDelegate.swift:1376` (`annotator.opening == opening`), and again after the off-main read at `:1362`. `Opening` ids are never reused, so closing and reopening the same file is another opening. `annotator.opening` is nil when `current == nil` (`AnnotationController.swift:594`).
- A carried target whose session is gone: Send still shows. A send to it fails at the preflight (`AgentConnection.swift:416-420`, "closed" or "cleared") and never lands on another session.
- A menu pick applied after a newer `begin`: accepted without a check, guard none (`AnnotatorToolbar.swift:260-266`) ([toolbar-4](#toolbar-4)).

### ToolbarOffer (explicit, derived)

Owner: `AnnotatorToolbar.swift:640`. Tests: `ToolbarOfferTests.testEachOfferSaysWhatReturnAndCmdReturnDo`.

What the bar offers for the open image. It is computed from `Model` inputs and never stored. `AnnotationController.offerChanged` passes it to `editor.finishes` (`:639`); the bar's `controls` and `offersTarget` read it.

**States**: `copy`, `choose`, `send(d)`, `reply(d)`.

**Transitions**

The offer is recomputed whenever an input (`replyTo`, destinations, `listed`, `target`, `startable`) changes. First match wins:

| Condition | Offer |
|---|---|
| `replyTo` is set, and not (`listed`, Claude, and absent from the list) | `reply(replyTo)` |
| `target` is set | `send(target)` |
| `listed` and `startable` is not empty | `choose` |
| otherwise | `copy` |

**Invariants**

- Return never sends to a session Vignette picked (`finishes`, `:686`). Checked by: `ToolbarOfferTests.testEachOfferSaysWhatReturnAndCmdReturnDo`.

**Late and concurrent answers**

- None of its own. It follows `Model`.

### Send progress: sending, failure (implicit)

Owner: `Model.sending` (`AnnotatorToolbar.swift:47`), `failure` (`:51`), `failures` (`:54`). Tests: `EditorCoreSendTests`.

Tracks one Send press from the bar to the stored request. `AppDelegate.sendDrawing` (`:1387`) renders and submits.

**States**: idle (`sending == false`, `failure == nil`); sending; notSent (`failure != nil`). A press's destination travels with it, in `EditorCore.Input.send` and `Effect.send(_:to:)`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| idle or notSent | press (button, Cmd+Return, Space on the action, field Return: `AnnotatorToolbar.swift:283,335,795,799,955`) | — | `onSend` calls `editor.send(to:)` (`AnnotationController.swift:99`). The core emits `.send(drawing, to: destination)` only while open, and a key's send with `to: nil`. `editor.onSend` (`:135`) uses that destination, else `offer.destination`, then `sendDrawing` sets `sending = true`, which clears `failure` (`:47`) ([toolbar-1](#toolbar-1)) |
| sending | press | refused at every entry (`!model.sending`, `AppDelegate.swift:1388`) | — |
| sending | render fails, or `requests.send` throws | notSent: `sending = false`, `failure = reason`, `failures += 1` (`sendFailed`, `:56`) | — |
| sending | render answers for an ended opening | dropped (`AppDelegate.swift:1397`); `sending` untouched | next `prepare` resets |
| sending | request stored | stays sending until the bar leaves | next `prepare` calls `resetSend` (`:63`, from `AnnotationController.swift:166`) |

**Invariants**

- `sending` stays on from the press until the bar has left, and `prepare` resets it. Checked by: `prepare` at `AnnotationController.swift:166`.
- A press the editor ignored leaves nothing for the next image. Held by the destination travelling in the input, with no flag outside the core; `EditorCoreSendTests` checks the core's side only ([toolbar-1](#toolbar-1)).

**Late and concurrent answers**

- A rendering that answers after its opening ended: dropped, guard at `AppDelegate.swift:1397`.
- A second press while sending: refused, guard at `AppDelegate.swift:1388`.
- Esc during the render: the opening ends, so the answer is dropped by the same guard.

### Bar presence: shown, hideGeneration, sliding (implicit)

Owner: `AnnotatorToolbar.swift:229` (`hideGeneration`). Tests: none (needs `NSPanel`).

Whether the bar's panel is on screen, and when it fades out. `prepare` calls `place`, `AnnotationController.show` (`:358`) calls `show`, and `hideWindows` (`:519`) calls `hideSoon`.

**States**: the properties `Model.shown` (`:11`), `sliding` (`:503`), `placedBelow` (`:215`), `slideX` and `slideY` (`:499`), `hideGeneration` (`:229`), and `panel.isVisible`. Together:
- absent: panel out, `shown == false`.
- entering: panel in, `shown` false until the next turn.
- up: `shown == true`.
- fading: `shown == false`, panel still in, orderOut pending 0.2 s (scaled by the motion setting).
- sliding: `sliding == true`, springs move the panel.

**Transitions**

Events: `place(below:gap:)` (`:436`), `show()` (`:521`), `hideSoon()` (`:532`), `hide()` (`:542`), `refit()` (`:448`, from SwiftUI `onWidth`).

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
| up or fading | `refit` | — | next turn `position(slide: sliding)` if `shown || !panel.isVisible`; a bar on its way out is left alone (`:450`) |

**Invariants**

- A swap does not hide the next image's bar: `hideSoon` is queued before the next `place` in the same turn. Checked by: comments at `:430-435`, `:528-531`; nothing else. If the order flipped, the bar would be absent during the next flight, not stuck, since `show()` orders it in again.

**Late and concurrent answers**

- A deferred `hide` or orderOut after a newer event: dropped by the generation compare (`:536`, `:549`).
- `show()`'s deferred `shown = true` (`:525`) has no generation check. It is safe today because `hide()` can only run from a `hideSoon` queued after `show()`.

### Keyboard focus: focus, keyed, tookKeysOnOpen, toolLetter, heldLetter (implicit)

Owner: `Model.focus` (`AnnotatorToolbar.swift:100`), `keyed` (`:71`), `tookKeysOnOpen` (`:73`), `toolLetter` (`:75`), `messageAsks` (`:102`); `AnnotatorToolbar.heldLetter` (`:213`); `ToolbarPanel.pressOnField` (`:560`), `wantsKeys` (`:561`). Tests: none for the panel; `HeldToolLetter` below has one.

Decides whether the bar's panel or the editor has the keys. Only a press on the message field or an explicit ask lets the panel take them.

**States**: the panel is key or not (`panel.isKeyWindow`, mirrored by `keyed` through `didBecomeKey` and `didResignKey`, `:289-305`). `focus` is nil, a tool, copy, the target, an action, or `.message`. `tookKeysOnOpen` says the field got the keys without a press.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `didBecomeKey` | `keyed = true`, `focus = .message` | whatever made the panel key |
| any | `didResignKey` | `keyed = false`, `tookKeysOnOpen = false`; `focus = nil` if it was `.message` | `makeFirstResponder(nil)` |
| any | `begin` | `focus = nil`, `tookKeysOnOpen = false`, `toolLetter` reset | `keyed` and `panel.isKeyWindow` untouched |
| panel already key | `typeOnOpen` (`:349`, from `offerTyping`, `AnnotationController.swift:376`) | — | refused (`:350`) |
| any | Tab, Shift+Tab (`move`, `:316`); Space (`activate`, `:326`); M or P (`focusMessage`, `:342`); press (`onPress`, `:275`); `keyDown` (`:365`) | `focus` moves | — |

**Invariants**

- The panel can be key only by `canBecomeKey = pressOnField || wantsKeys || isKeyWindow` (`:572`). Checked by: the guard at `:572`. `pressOnField` is not reset until the next left press ([toolbar-6](#toolbar-6)).

**Late and concurrent answers**

- `offerTyping` runs once per image (`editorUntouched`). `tookKeysOnOpen` is cleared on resign.

### HeldToolLetter (explicit)

Owner: `HeldToolLetter.swift:7`. Tests: `ToolbarOfferTests.testAToolLetterTypedFirstPicksItsToolUntilAWordShowsItBeganOne`.

Holds a tool letter typed first on an untouched field, until the next key shows whether it began a word.

**States**: `toolBefore` is nil (nothing held) or the tool that was active before the held letter.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| nil | `key`, an eligible letter on an untouched field | `toolBefore` set | the key is kept in `heldLetter` |
| held | `key`, a repeat | held | swallow |
| held | `key`, another character | nil | restore the tool, replay the held key into the field |
| held | `key`, a non-character | held | pass |
| held | `keepTool()` (press, resign) | nil | the tool stays |

**Invariants**

- `heldLetter` (toolbar) and `toolBefore` (model) agree where it matters. `begin` resets `toolLetter` but not `heldLetter` (`AnnotatorToolbar.swift:153`), and a stale `heldLetter` is read only after a `hold` sets it again. Checked by: `testAToolLetterTypedFirstPicksItsToolUntilAWordShowsItBeganOne`.

**Late and concurrent answers**

- None.

### Target menu pick (implicit)

Owner: `AnnotatorToolbar.swift:260-266` (`onPick`), `:269-274` (`onMenuKey`), `:333` (Space), `:416` (`showTargetMenu`). Tests: none.

Opens the target menu and applies a pick one turn later.

**States**: closed; open (modal `NSMenu`); pick queued.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| closed | Space, Up or Down in the field, or a click | closed, one turn later | `showTargetMenu` builds an `NSMenu` from `model.destinations + model.startable` and calls `popUp` |
| closed | `showTargetMenu` with no target offer or `targetFrame == nil` | closed | refused (`:417`) |
| open | item chosen | pick queued | `TargetMenuActions.pick` (`:1327`) calls `DispatchQueue.main.async` |
| pick queued | the block runs | closed | `model.pick(destination)` under `withAnimation`; no opening or `shown` check ([toolbar-4](#toolbar-4)) |

**Invariants**

- Space opens the menu a turn later so the menu takes keys (comment `:331-333`). Checked by: nothing.
- A pick belongs to the opening that showed the menu. Checked by: nothing ([toolbar-4](#toolbar-4)). `targetFrame` comes from SwiftUI geometry and is never cleared (`:248`).

**Late and concurrent answers**

- A `begin` between the menu action and the queued pick: the pick lands on the new image ([toolbar-4](#toolbar-4)).

### SessionListing (implicit)

Owner: `SessionListing.swift:6`. Tests: `AgentConnectionTests` listing tests (about lines 714-860).

Asks each agent connection for its sessions and delivers lists to the toolbar. `AppDelegate.listDestinations` calls `list(shown:completion:)` (`:42`); `refreshKeptLists()` (`:80`) is called from `AppDelegate.swift:196,387,1489`.

**States**: `kept: [Source: [AgentDestination]]` (`:107`); `asking: [Source: [callbacks]]` (`:110`); per `list` call, a local `Answers` (`lists`, `fresh`, `herdr`) (`:85`, `:43`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| a client has a kept list | `list` | — | delivers once at once (`:65`), then asks every source |
| no kept list | `list` | — | asks every source; delivers on each fresh answer |
| source not in `asking` | `ask` without id | `asking[source]` set | runs the job |
| source in `asking` | `ask` without id | callback appended | joins the running job (`:141`) |
| any | `ask` with id (the thread the Codex app shows) | — | own job, not joined, not kept (`:134-139`) |
| job answers | main-thread answer (`:123-155`) | `kept[source]` set when `keepsList` (`:149`) even if the list is empty ([toolbar-2](#toolbar-2)); `asking[source]` cleared | all waiters called; `answers.lists`, `fresh`, `herdr` set; `deliver()` sends `complete` (every client has a list) and `fresh` (every list is fresh) |

**Invariants**

- A kept list answers at once and every client is asked afresh; startable rows never hold back; a second ask joins; an ask with an id runs alone and is not kept; herdr decides with Claude's first answer. Checked by: the `AgentConnectionTests` listing tests.
- A failed job does not replace a good kept list. Checked by: nothing ([toolbar-2](#toolbar-2)).
- A job always returns, so `asking[source]` clears. Checked by: nothing. A child that ignored SIGTERM would leave later asks for that source waiting.

**Late and concurrent answers**

- Callbacks are `@MainActor` and capture `self` weakly. A stale answer is dropped by the caller's opening compare.
- Two overlapping `list` calls (a swap) each have their own `Answers`.
- A joined ask carries the herdr focus read when the first caller's job ran, up to about 70 ms old.

### AppDelegate.refreshDestinations and listDestinations (implicit)

Owner: `AppDelegate.swift:1350`, `:1371`. Tests: none.

Starts one listing for the open image, gated by the opening. It reads the `annotator.opening`, calls `begin`, and, if `FocusReturn.shared.previousApp` is the Codex app, reads the shown thread off the main thread (`AgentApp.shownThread`). It then calls `sessions.list`.

**States**: the captured `opening`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| opening current | off-main thread read returns | — | main re-checks the opening (`:1362`), then `sessions.list` |
| opening current | each `deliver` | — | re-checks (`:1376`), then `destinationsAnswered` |
| opening ended | either hop | — | dropped |

**Invariants**

- The `previousApp` read happens once per `prepare`. Checked by: the call order in `refreshDestinations`.

**Late and concurrent answers**

- Both hops compare the opening id: guards at `:1362` and `:1376`.

### DestinationChoice (pure functions, no state)

Owner: `DestinationChoice.swift`. Tests: `DestinationChoiceTests`; Send's rules in `ToolbarOfferTests` and the herdr test in `AgentConnectionTests`.

`choose(_:for:)` is a pure function of `Candidates` and `Asker`. It has no states. Send's pick order is `.app`, `.pane`, `.tab`, else first by `newestFirst` (`:186`). An answer is `decided` when it is complete or any session is marked. A kept Codex list that lacks the shown thread forces `complete = false` (`:123`).

### ClaudeCodeConnection: submit, preflight, start (implicit)

Owner: `AgentConnection.swift:195`; inbox reads `ClaudeInbox.swift:23-52`. Tests: `SessionStartsTests.testASendToASessionThatIsNotRunningStartsItThenWritesTheLineIntoItsInbox`, `SessionStartsTests.testAStartThatFailsOrNeverComesUpSendsNothing`, `AgentConnectionTests+Started`.

Takes a line for a Claude Code session. A running session is listed, checked by a preflight (`:405`), then written (`:443`). A startable row is started in a herdr tab, polled for its inbox, then written. A Claude Code process has an inbox folder; its monitor touches an `alive` file, and `isLive` means touched within 10 s.

**States**: for a running session: listed, preflighted, written. For a startable row: requested, joined (waiting on a start of the same session already under way), launched, polling, then up, failed or timed out (45 s), then written. The start code is in `ClaudeSessionStart.swift`, and the starts under way are in `SessionStartsUnderWay`, which every copy of the connection shares.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| listed | `submit` to a destination with `start != nil` | refused (`:410`) | — |
| listed | `submit`, inbox holds exactly this session now (`listedInbox(of:) ?? liveInbox(holding:)`, `:416`) | written | aside file, then rename (`write`) |
| listed | `submit`, inbox does not hold it | `.destinationChanged` | "cleared" if another running inbox lists it in `past`, else "closed" |
| requested | `startSession` (`:270`), id not a UUID | failed | nothing reaches the shell (`new:<folder>` rows) |
| requested | `startSession`, a start of this session under way | joined | no launch; waits for that start's answer (**fixed**, [toolbar-3](#toolbar-3)) |
| requested | `startSession`, none under way, `liveInbox(holding:)` already live | up | no launch |
| requested | `startSession` otherwise | launched | `before` = inbox folder names now; `launch` (herdr `tab create`, `pane run`) |
| launched | launch returns `.failed` | `.notStarted` | — |
| launched | launch started | polling | `look` (`:288`) every 0.25 s via `later` |
| polling | `look` finds the first folder not in `before` whose `session` equals the id and which `isLive` | up, then written | every joined send gets the same inbox and writes its own line |
| polling | `now - began >= 45` | timed out | nothing sent, by this send or any joined one |
| any read | `liveInboxes()` (`:329`) | — | deletes an inbox folder whose pid is not running |

**Invariants**

- A line is written only if the inbox still holds that exact session immediately before the write (`AddressGuard.preflight`, `:405`). Checked by: the guard.
- A second send after the inbox is live does not launch again. Checked by: `SessionStartsTests.testASendToASessionThatIsNotRunningStartsItThenWritesTheLineIntoItsInbox`.
- One start runs per session at a time: a send to a session already starting joins that start (`SessionStartsUnderWay`). Checked by: `SessionStartsTests.testASecondSendWhileItsSessionIsStillStartingJoinsThatStart` (**fixed**, [toolbar-3](#toolbar-3)).

**Late and concurrent answers**

- `/clear` before the write: caught by the preflight.
- A session resumed by hand after it was listed: caught at `:274`.
- Only folders created since the launch are polled (`:293`).
- Open windows by design (comment on `AddressGuard.preflight`, `:26`): `/clear` between the preflight and `write`, and between `look` success and `write`.
- Left behind: a tab when `pane run` fails after `tab create` (`SessionStarts.swift:213`), and a started `claude` after the 45 s timeout.

### HerdrLauncher.start (implicit)

Owner: `SessionStarts.swift:190-216` (`start` at `:204`). Tests: `SessionStartsTests` (about lines 153-195).

Opens a herdr tab in the project's folder and runs `claude` there. It runs on a pool thread only.

**States**: not started; tab created; pane running; failed.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| not started | `tab create` (10 s timeout) fails | failed | — |
| not started | `tab create` succeeds | tab created | ids parsed |
| tab created | `pane run` fails | failed | the tab stays; no retry |
| tab created | `pane run` succeeds | pane running | — |

**Invariants**

- A failed run leaves no tab. Checked by: nothing; the tab stays on failure after `tab create`.

**Late and concurrent answers**

- Two calls run two launches. `ClaudeCodeConnection` now makes one call per session start, however many sends wait on it (**fixed**, [toolbar-3](#toolbar-3)).

### CodexConnection: discover and submit (implicit)

Owner: `CodexConnection.swift` (`discover` `:56`, `submit` `:123`). Tests: `CodexConnectionTests`, `AppServerTests`.

Lists Codex threads and queues a line to one. Both are linear.

**States**: discover: asked, then answered or empty. Submit: sent, then a `SubmissionOutcome`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| discover | no binary | `[]` | — |
| discover | `converse` fails (no process, timeout, parse) | `[]`, the same as "no threads" ([toolbar-2](#toolbar-2)) | — |
| discover | `converse` answers | threads | with `shown`, appends the read thread if absent |
| submit | no binary | `noAgent` | — |
| submit | `watchingTurn` | — | reads the rollout through another app-server first |
| submit | `codex queue` not run | `sendFailed` | `Subprocess.run` with a 25 s watchdog |
| submit | `codex queue` `timedOut` | `.uncertain` | the watchdog has sent SIGTERM, so no late answer arrives |
| submit | status != 0 | `failure(...)` | — |
| submit | status 0, no writer lock | `.queued` | — |
| submit | status 0, writer lock held | `.accepted` | — |

**Invariants**

- Only a thread UUID is addressed; the engine refuses an unknown UUID. Checked by: `codex queue --thread` (`AddressGuard.runtimeEnforced`).
- A timed out send is reported as uncertain. Checked by: `CodexConnectionTests`.

**Late and concurrent answers**

- `Subprocess.run` sends SIGTERM once (`Subprocess.swift:39`) then waits for exit (`:43`). A child that ignores it holds the pool thread and the completion. `codex` as shipped does not.

### AppServer.converse (implicit)

Owner: `AppServer.swift:138`. Tests: `AppServerTests.testAConversationReturnsWhenItsAnswersHaveArrivedAndNotBefore`, `testAConversationEndsOnAnErrorAnswer`, `testAConversationWithNoProcessIsEmpty`.

Runs one `codex app-server` process per call and reads its answers.

**States**: spawned; collecting lines (a readability handler, `state` under an unfair lock); done.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| spawned | `process.run()` throws | done | returns `[]` (`:150`) |
| collecting | `answers >= wanted`, or EOF, or 8 s | done | handler cleared; `terminate()` if running; stdin closed (the server exits on EOF); returns the lines that arrived |
| collecting | an error answer | done | as above |

**Invariants**

- No path leaves the process running after `run()` returns without `terminate()` and a stdin close. Checked by: `testAConversationReturnsWhenItsAnswersHaveArrivedAndNotBefore`. A server that ignores both stays until it exits on EOF.
- A partial conversation yields partial data. A timeout and an empty store both give no threads ([toolbar-2](#toolbar-2)). Checked by: nothing.

**Late and concurrent answers**

- Lines after done are dropped: the handler is cleared.

### AppServerSession (implicit; live ink's)

Owner: `AppServerSession.swift:10`. Tests: none listed. Live ink uses it; the live ink mappers should read it too.

A long-lived app-server process with request ids.

**States**: running (`process` set); stopped (`process == nil`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| running | `stop()` | stopped | `process` nilled; `replies` cleared |
| running | process ends | stopped | `replies` cleared; `onEnd` called |
| stopped | `call` | stopped | stores its reply closure; writes nothing (`process?.write`) |

**Invariants**

- Every `call` is answered or cleared. Checked by: nothing; a `call` after `stop()` is never answered or cleared.

**Late and concurrent answers**

- `ready` never fires if `stop()` precedes the handshake answer. Whether any caller can `call` after `stop` is unchecked.

### SendOverlay notice animation (implicit)

Owner: `SendOverlay.swift:12`. Tests: none (needs SwiftUI `@State`).

Plays a send notice's states on a card in order. The notice's own state comes from outside (`SendNotice`).

**States**: `@State` `landed`, `shown: SendNotice.State?`, `since`, `logoArrived`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `onChange(of: notice.state)` (`:70`), from `inGrace` | `shown` steps through `[sending, X]` | one `DispatchQueue.main.asyncAfter` per step from `SendNotice.steps(from:to:)` (`CardNotices.swift:39`): 0.45 s hold per step, plus the logo glide when leaving grace |
| any | `onChange`, from another state | `shown = X` after the remaining sending hold | as above |
| before any step has fired | render | shows `notice.state` (`shown ?? notice.state`) | — |

**Invariants**

- The card shows the notice's states in order. Checked by: nothing. Steps queued by an earlier change are not cancelled ([toolbar-5](#toolbar-5)).

**Late and concurrent answers**

- An earlier change's queued step can fire after a later change's and overwrite `shown`, guard none (`:84-93`) ([toolbar-5](#toolbar-5)).

## Requests, replies and the screenshots folder

A request is one Send of a drawing to an agent session, and a reply is the drawing the agent sends back. This area covers the request record, the grace wait before the line leaves, the reply import that turns a reply into a card, and the folder bookkeeping (watcher, writes, caches) that keeps cards, drawings and requests in step with the files on disk. No random-sequence test exists in this area: every test is a table or a hand-written sequence.

Terms used below. A request's **line** is the text Vignette submits to the agent client. The **grace** is the wait of `ui.sendGraceSeconds` between Send and the line leaving. A **receipt** is the file the reply helper polls for the app's answer to one reply attempt. An **inventory** is one folder listing with the time it was observed (`observedAt`).

### Record.Status (explicit)

Owner: `ScreenshotRequestRecords.swift:30`, advanced by `ScreenshotRequests.swift`. Tests: `ScreenshotRequestsTests.testEveryLateSubmissionOutcomeLeavesClearTerminal`, `testALaunchLeavesALineTheClientHasNotAnsweredAlone`, `testQuitDoesNotWaitLongerThanItsLimitForASlowClient`, `testARequestStillPreparedAtLaunchIsClearedBecauseItsLineIsGone`, `testALaunchReplacingACopyLeavesItsWaitingSendsAlone`.

The durable record of one send. `ScreenshotRequests` writes it; the client's answer moves it.

**States**: `prepared` (stored, line not handed over), `uncertain` (handed over, no answer, also the end state of a call that never answered), `submitted` (client accepted or queued), `failed` (client refused, or the destination changed), `cleared` (terminal, takes no replies).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| none | `send` (`ScreenshotRequests.swift:272`) | `prepared` | record stored before the image leaves the editor |
| `prepared` | `handOver` (`:371-377`), from `run(.submit)` (`:333`) or `releaseHeld` (`:448`) | `uncertain` | `handedOver` set before the line leaves |
| `prepared`, `uncertain` | outcome accepted or queued (`recordOutcome` `:391`, via `finishSubmission` `:385` or `releaseHeld` `:464`) | `submitted` | `delivered` called |
| `prepared`, `uncertain` | outcome uncertain | `uncertain` | `delivered` called |
| `prepared`, `uncertain` | outcome not submitted or destination changed | `failed` | `delivered` called |
| `submitted` | outcome uncertain or failed | `uncertain` or `failed` (downgrade, not guarded) | `delivered` called |
| `failed` | outcome accepted, uncertain, failed | `submitted`, `uncertain`, `failed` | `delivered` called |
| any but `cleared` | `clear(_:)` (`:806`): `run(clear:)` `:764`, the 50-request admission `:290`, `load` of a `prepared` record `:131`, `.discard` `:341` | `cleared` | see Clearing and cleanup |
| `cleared` | any outcome | — (status and detail kept) | `delivered` is still called (`:387`, `:393`) |
| `cleared` | `clear` again | — | returns true; `cleanup` replays |
| `uncertain`, `submitted`, `failed`, `cleared` | `run(.submit)` | — (refused, `:333`) | — |
| any but `cleared` | `renamed` (`:223-226`) | same status, new `sourceKey` | record rewritten from the in-memory status ([requests-3](#requests-3)) |

A failed admission in `send` sets `cleared` with a detail (`:297-299`).

**Invariants**

- `cleared` is terminal and a late outcome never reopens it. Checked by: `testEveryLateSubmissionOutcomeLeavesClearTerminal`.
- A record is `uncertain` on disk before the line leaves, so `load` never clears a delivered line as unsent. Checked by: `testALaunchLeavesALineTheClientHasNotAnsweredAlone`, `testQuitDoesNotWaitLongerThanItsLimitForASlowClient`; comment at `:371-372`.
- `prepared` on disk at a normal launch means the line never went, so `load` clears it (`:129-133`). Checked by: `testARequestStillPreparedAtLaunchIsClearedBecauseItsLineIsGone`.
- In-memory status equals on-disk status. Checked by: nothing. A launch that replaced a running copy can hold a stale `prepared` and write it back over the old copy's `uncertain` or `submitted` ([requests-3](#requests-3)).
- `finishSubmission` runs once per request. Checked by: nothing.

**Late and concurrent answers**

- Outcome after a clear: status and detail are kept, `delivered` still runs, guard at `ScreenshotRequests.swift:393`.
- Quit before the client answers: `handOver` stores `uncertain` first (`:371-379`); `releaseHeld` waits up to 2 s (`:460-463`).
- A launch that replaces a running copy leaves its waiting sends alone (`load(clearingUnsent:)`, `:129`).

### SendGrace (explicit)

Owner: `SendGrace.swift:6`. Tests: `SendGraceTests.testACancelledSendIsDiscardedAndItsTimerDoesNothing`, `testAClearTakesAWaitingSendAndItsTimerDoesNothing`, `testTheLineGoesOnceWhenTheDeadlineComes`, `testATimerThatRunsEarlyArmsAgainForWhatIsLeft`, `testCancellingSeveralDiscardsThemInSendOrder`, `testQuitSubmitsEveryWaitInSendOrderOnce`, `testQuitHandsAWaitingSendOverOnceWithoutTouchingCards`.

A pure reducer that holds each send's line until its deadline. `ScreenshotRequests.run(_:)` (`:324`) feeds it events and runs its effects.

**States**: per request id, absent or `Wait(line, deadline, length, sequence)` in `waiting` (`SendGrace.swift:17`). `nextSequence` orders sends. The clock is `systemUptime` (`:89`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| absent | `.sent`, grace > 0 (`ScreenshotRequests.swift:319`) | waiting | `.arm` |
| absent | `.sent`, grace <= 0 | absent | `.submit` now |
| waiting | `.due`, at >= deadline | absent | `.submit` (waited) |
| waiting | `.due`, early | waiting | `.arm` for what is left |
| waiting | `.cancelled(requests:)` (`unsend(file:)` `:425`: Don't send, `vignette://unsend` `AppDelegate.swift:557`, `fileRemoved` `:162`) | absent | `.discard`; every wait of the file, in send order |
| waiting | `.cleared` (`clear(_:)` `:809`) | absent | `.dropped` |
| waiting | `.quit` (`releaseHeld` `:448`) | absent, all waits | `.submit` each, in send order |
| absent | `.due`, `.cancelled`, `.cleared`, `.quit` | — | — (stale, ignored; a cancel after hand-over is refused, no `.discard`) |

How `ScreenshotRequests.run` treats effects: `.arm` schedules a timer; `.submit` first checks `requests[id].status == .prepared`, then logs, calls `callbacks.released` (only when waited) and `submit`; `.discard` calls `clear` then `callbacks.cancelled`; `.dropped` calls `callbacks.cancelled` only.

**Invariants**

- A request is in `waiting` only while its record is `prepared`. Checked by: the re-check in `run(.submit)` at `ScreenshotRequests.swift:333`.
- A stale or doubled timer does nothing. Checked by: `SendGrace.swift:51`, `testACancelledSendIsDiscardedAndItsTimerDoesNothing`, `testAClearTakesAWaitingSendAndItsTimerDoesNothing`.
- The deadline never moves; an early timer re-arms. Checked by: `testATimerThatRunsEarlyArmsAgainForWhatIsLeft`.
- A cancel takes every waiting send of the file, in send order. Checked by: `testCancellingSeveralDiscardsThemInSendOrder`.
- Quit hands every wait over once, in order. Checked by: `testQuitSubmitsEveryWaitInSendOrderOnce`.
- After `.discard` or `.dropped` the record is `cleared`. Checked by: nothing. `clear` sends `.cleared` before its write (`:809`), and `defer { run(stopped) }` runs even if the write throws (comment `:807-808`, pinned by `testClearWriteFailureKeepsStateAndOwnedFiles`). A failed clear still stops the wait and tells the card "cancelled" while the record stays `prepared`.
- A deleted file cancels its waiting send, a removal held back by `FolderWrites` included (**fixed**, [requests-1](#requests-1)).

**Late and concurrent answers**

- `.due` after cancel, clear or quit: ignored, `SendGrace.swift:51`.
- Timer owner gone: `[weak self]`, `ScreenshotRequests.swift:328`.
- The cancel path clears through `clear`, whose `.cleared` event is then a no-op (`SendGrace.swift:63`).

### Send bookkeeping (implicit)

Owner: `AppDelegate.swift:74` (`sentShots`), `ScreenshotRequests.swift:79` (`sendGrace`), `:81` (`watchedTurns`). Tests: `ScreenshotRequestsTests.testARenamedFileIsCancelledByItsNewName`.

Three tables that must agree about one send: which card it was sent from, which record it belongs to, and whether its wait is armed.

**States**: `sentShots[request id]` (`AppDelegate.swift:74`), `requests[id].sourceKey`, `sendGrace.waiting[id]` (`SendGrace.swift:17`), `watchedTurns` (`ScreenshotRequests.swift:81`). Together: no entry; waiting (all four set); handed over (`sentShots` still set until the answer).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| none | `requests.send` returns (`AppDelegate.swift:1430`) | `sentShots[id]` set | same main turn |
| waiting | rename (`renameCards` `AppDelegate.swift:501`, `ScreenshotRequests.renamed` `:223`) | same, new key | Don't send reaches the renamed card |
| waiting or handed over | `delivered` (`AppDelegate.swift:1308`) or `cancelled` (`:1323`) | `sentShots[id]` removed | — |
| waiting | `released` (`:1318`) | — | reads only |
| waiting | `handOver` (`ScreenshotRequests.swift:366`), `.discard`, `.dropped` | `watchedTurns[id]` removed | — |
| waiting | `.submit` skipped by the `prepared` guard (`:333`) | `watchedTurns[id]` kept | harmless leak |

**Invariants**

- `delivered` finds its `sentShots` entry because the client answer always hops through `DispatchQueue.main.async` (`ScreenshotRequests.swift:357`). Checked by: the hop. A missing client would run `finishSubmission` inside `send` (`:359`) before the entry is set; the app registers both clients (`AppDelegate.swift:65`), so only a test with a missing client reaches it.

**Late and concurrent answers**

- Rename during the grace: both tables follow it, see Transitions.
- File removed during the grace: `fileRemoved` (`:161`) cancels, whether the removal is immediate or held back for a newer listing (**fixed**, [requests-1](#requests-1)).

### Reply.Stage (explicit)

Owner: `ScreenshotRequestRecords.swift:71`. Tests: `ScreenshotRequestsTests.testAnImportStoppedBeforePublicationLeavesNoVisibleFile`, `testAnUnknownManagedNameIsHiddenRatherThanTreatedAsACapture`, `testAReplyIsNeverACaptureEvenAfterItIsPublished`, `testAReplyTheCommandPreparesIsAcceptedAndItsRetryMakesNoSecondCard`, `testTheSameReplyIdWithOtherBytesIsRefusedAndLeavesTheFirstAlone`, `testAClearWhileMarksAreAddedCancelsTheImportInsteadOfPublishingIt`, `testLoadReplaysClearCleanupAndCannotPublishAnUncancelledReply`, `testDeletingAPublishedReplyIsARemovalAndNotARebuild`.

The durable record of one reply, from the app accepting its bytes to its card existing. Written by `ScreenshotRequests`.

**States**: `accepted`, `reserved`, `published`, `shown`, `failed`, `cancelled`. Flags beside the stage: `deleted`, `renamedTo`, `needsOutputCleanup`, `errorCode`, `notDrawn`, `destination`. Fail codes: `reserve-failed`, `destination-unknown`, `payload-unreadable`, `destination-changed`, `copy-failed`, `draft-store-failed`, `draft-failed`, `publish-failed`, `request-cleared`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| none | `accept` (`:513-557`) | `accepted` | payload stored, receipt written |
| `accepted` | reserve (`publishCard` `:648-653`) | `reserved` (or `failed` `reserve-failed`) | `destination` fixed |
| `reserved` | reserve again (recovery) | kept | continues from the reserve |
| `reserved` | `commit`, only if `stillReserved` (`:696-703`, `:720`) | `published` | agent attributes written, card presented |
| `accepted` | live ink answer drawn (`publish` `:630-636`) | `shown` | — |
| `accepted`, `reserved` | `fail` (`:731`) | `failed` or `cancelled` | — |
| any but `published` | `cleanup` (`:821-854`) | `cancelled` | `needsOutputCleanup` set; output at `destination` removed (`reserved`) |
| `shown` | `cleanup` | stays `shown`, as `published` does (**fixed**, [requests-2](#requests-2)) | — |
| `cancelled` | live answer's capture fails after a clear (`:629`, `:648`) | `reserved` | stale copy overwrites the record ([requests-4](#requests-4)) |
| `cancelled` | `cleanup` | — (skipped, `:824`) | — |
| `published` | `cleanup` | — (untouched, `:823`) | the file is the person's |
| `published` | file removed (`fileRemoved`, `reconcile` `:161-171`, `:176-180`) | `published`, `deleted` true | — |
| `published` | file renamed (`renamed` `:217-222`) | `published`, `renamedTo` set or cleared | — |

Every `write(Reply)` calls `refreshReceipts` (`:908`), so each accepted attempt's receipt follows the stage. `Reply.publication` (`ScreenshotRequestRecords.swift:113`) maps `deleted` to `removed`; `accepted` and `reserved` to `pending`; `published` and `shown` to `ready`; `failed` to `failed`; `cancelled` to `cancelled`.

**Invariants**

- Nothing is a card until `published`: `isVisible` (`:145`) fails closed for any managed name without a `published` record. Checked by: `testAnImportStoppedBeforePublicationLeavesNoVisibleFile`, `testAnUnknownManagedNameIsHiddenRatherThanTreatedAsACapture`, `testAReplyIsNeverACaptureEvenAfterItIsPublished`.
- One reply id gives at most one card; the same id with the same digest is answered from its record. Checked by: `testAReplyTheCommandPreparesIsAcceptedAndItsRetryMakesNoSecondCard`, `testTheSameReplyIdWithOtherBytesIsRefusedAndLeavesTheFirstAlone`.
- A cleared request never publishes. Checked by: `testAClearWhileMarksAreAddedCancelsTheImportInsteadOfPublishingIt`, `testLoadReplaysClearCleanupAndCannotPublishAnUncancelledReply`.
- A published file is the person's: clear never removes it, and a deletion is a removal, not a rebuild. Checked by: the guard at `:823`, `testDeletingAPublishedReplyIsARemovalAndNotARebuild`.
- `cancelled` is terminal. Checked by: nothing ([requests-4](#requests-4)).
- A `shown` reply stays `shown` after a clear. Checked by: `ScreenshotRequestsClearingTests.testAClearedRequestWhoseAnswerLiveInkDrewStaysDrawnAndIsPrunedAfterAWeek` (**fixed**, [requests-2](#requests-2)).

**Late and concurrent answers**

- The same reply twice: serialized on the main actor and answered from the record (`:521-531`); the id from another request is refused (`:522`, `testAReplyIdFromAnotherRequestIsRefused`).

### Reply import pipeline (implicit)

Owner: `ScreenshotRequests.swift:606` (`importNext`), `:625` (`publish`), `:643` (`publishCard`), `:696` (`commit`). Tests: `ScreenshotRequestsTests.testRecoveryPublishesOneCompleteDrawingAfterInstallationWasInterrupted`, `testChangingFoldersDoesNotPruneAPublishedReplyInTheOriginalFolder`, `testAReservedReplyWithoutLocationFailsAfterStartupReadiness`.

Turns accepted replies into cards, one at a time. The app drives it from `accept`, `load` and `reconcile`.

**States**: the properties `pendingImports` (`:72`, FIFO of reply ids), `importing` (`:73`, one import at a time), `publicationReady` (`:75`, set by the first `reconcile`, `:174`), `replies[id].stage`, `requests[id].takesReplies`, the file at `reply.destination`, the stored drawing, and the outstanding `callbacks.installDrawing` and `callbacks.presentLive`. Together they are: idle (`importing` false), importing (`importing` true until the `done` callback, `:614-620`).

**Transitions** (what a quit or crash after each step leaves)

| After step | On disk | Next launch |
|---|---|---|
| helper attempt, before `write(reply)` (`:552`) | maybe `payloads/<id>.png`, no record | helper times out, retries the same bundle, accepted fresh |
| `write(reply)` `accepted` (`:552`), before receipt | record | `load` adds it to `pendingImports` (`:124`); a helper retry gets "already accepted" (`:521`) |
| reserve (`:648-653`) | `reserved` and `destination` | `load` re-queues it (`:124`); `publishCard` skips the reserve (`:648`) |
| PNG copy (`:671`) | hidden PNG in the watch folder | rewritten atomically, same bytes |
| `installDrawing` (`:678`) | drawing at the destination's key | `Drawings.installReply` reuses a complete checkpoint (`Drawings.swift:177`) |
| `commit` writes `published` (`:702`), before `Agent.record` (`:705-706`) | published | card exists without agent badge or title ([requests-8](#requests-8)) |
| `callbacks.present` (`:708`) | published | the watcher already lists the file |

**Invariants**

- Imports are serial. A path that never calls `done` stalls every later import. All paths in `publishCard` call it; `presentLive` and `installDrawing` are trusted to answer exactly once (`LiveNoteCards.answer` answers `done(nil)` when the note is gone, `LiveNoteCards.swift:179`). Checked by: nothing.
- The reserved name is excluded from every listing until `published`. Checked by: the comment at `:623-624`, and the Reply.Stage tests.
- `stillReserved` re-reads the stage and the request after every async hop. Checked by: the guards at `:682` and `:697`.
- A reply is published in the folder it was reserved in, even if the watch folder changes; `shot(at:)` (`:712`) keys it by its real path. `reconcile` and `prune` need `confirmsAbsence`, which needs the inventory's folder to be the file's folder (`ScreenshotWatcher.swift:41`), so such a reply is never marked deleted and its request never pruned. Checked by: `testChangingFoldersDoesNotPruneAPublishedReplyInTheOriginalFolder`, `testAReservedReplyWithoutLocationFailsAfterStartupReadiness`.

**Late and concurrent answers**

- Clear during `installDrawing`: `stillReserved` (`:682`, `:720`) stops the import; an install failure after a clear is not reported as a failure (`:682` before `:683`).
- A live ink answer whose capture fails after a clear: the nil branch republishes a stale copy (`:629`, [requests-4](#requests-4)).
- Watch folder gone: the reply fails `destination-changed` (`:666-670`).
- `importNext` for a request cleared before the import began: skipped (`:608-613`).

### Clearing and cleanup (implicit)

Owner: `ScreenshotRequests.swift:806` (`clear(_:)`), `:821` (`cleanup(_:inventory:)`), `:777` (`prune`), `:77` (`pendingCleanupWrites`). Tests: `ScreenshotRequestsTests.testClearWriteFailureKeepsStateAndOwnedFiles`, `testLoadReplaysClearCleanupAndCannotPublishAnUncancelledReply`, `testAQueuedInventoryCannotRemoveANewerPublishedReply`.

Ends a request: commits the terminal state, cancels its replies, removes their unpublished output, and later removes the request's folder.

**States**: `requests[id].status == .cleared`, each reply's `stage`, `errorCode` and `needsOutputCleanup`, `publicationReady`, and `pendingCleanupWrites` (reply ids whose cancelled state is not yet written).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| open request | `clear` | `cleared` committed first (`:812-817`) | payloads removed after; a failed write keeps state and files |
| cleared request, `publicationReady` false | `cleanup` | — | output removal waits (`:834`) |
| cleared request, `publicationReady` true | `cleanup` | replies `cancelled` | output removed; a failed removal counts as done only if `inventory.confirmsAbsence` (`:839`) |
| cleared for 7 days (`clearedKept`, `:59`) | `prune` | request folder removed | only if no reply has `needsOutputCleanup` (`:785`) and every published reply's absence is confirmed (`:786-791`) |
| cleared, a reply is `shown` | `cleanup` | reply left `shown` | `prune` removes the request after a week (**fixed**, [requests-2](#requests-2)) |

**Invariants**

- The terminal state is committed before payloads are removed. Checked by: `testClearWriteFailureKeepsStateAndOwnedFiles`.
- An inventory older than a publication cannot remove it (`publishedAt <= observedAt`, `:177`, `:789`). Checked by: `testAQueuedInventoryCannotRemoveANewerPublishedReply`.
- An interrupted cleanup replays at the next launch or `reconcile`. Checked by: `testLoadReplaysClearCleanupAndCannotPublishAnUncancelledReply`.
- Clearing a request with a `shown` reply. Checked by: `ScreenshotRequestsClearingTests` (**fixed**, [requests-2](#requests-2)).

**Late and concurrent answers**

- A cleanup interrupted mid-way is tracked in `pendingCleanupWrites` and replayed.

### Admission limit (implicit)

Owner: `ScreenshotRequests.swift:258-311` (`send`), `:56` (`maxLiveRequests`). Tests: `ScreenshotRequestsTests.testAdmissionFailureDoesNotAccumulatePreparedRequestsOrClearOldPayloads`, `testClearWriteFailureKeepsStateAndOwnedFiles`.

Caps the open requests at 50. `send` drives it.

**States**: the count of records whose status is not `cleared`: under 50, exactly 50, over 50.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| over 50 | `send` | unchanged | refused (`:259`) |
| exactly 50 | `send` | new request stored, oldest cleared (`:288`) | the oldest goes through `clear` |
| exactly 50 | `send`, clear of the oldest fails | the new request removed again, or marked `cleared` if that fails (`:293-307`) | send refused |
| under 50 | `send` | stored | — |

**Invariants**

- A failed admission leaves no extra `prepared` request and clears no older payload. Checked by: `testAdmissionFailureDoesNotAccumulatePreparedRequestsOrClearOldPayloads`.
- A failed clear of the oldest request still ends its wait if it was waiting (`clear` sends `.cleared` before its write). Checked by: nothing; reaching it needs 50 open requests inside the grace.

**Late and concurrent answers**

- The oldest request mid-import is cancelled through the same `clear` (`stillReserved`).

### FolderWrites pending adds (implicit)

Owner: `FolderWrites.swift:53` (`pendingAdds`). Tests: `FolderWritesTests.testAReportBeforeTheMarksJoinPresentsOnceAfterThem`, `testMarksJoiningBeforeTheReportWaitForIt`, `testALiveCardWaitsForItsReportAndItsMarks`.

Holds a card Vignette just wrote into the watch folder until both the watcher has reported it and any agent marks have joined. `FolderWrites.swift:8` owns the class.

**States**: `pendingAdds[ScreenshotKey]` holds one `PendingAdd{annotate, addingMarks, waiting}` per file Vignette put in the folder. `waiting` means the watcher has reported the file.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| none | `add` (`:76`) or `writeCard` (`:166`) | pending | `waiting` set at once only for a file already in the folder |
| pending, `addingMarks` | marks joined (`:134-143`) or `ready` (`:193`) | `addingMarks` false | `presentAdd` |
| pending | `arrived` (`:148`, from the watcher's `onNew`) | `waiting` set | `presentAdd` |
| pending, no marks owed, `waiting` set | `presentAdd` (`:228`) | removed | `callbacks.present` |
| pending | `takeBack` (`:199`), `discard` (`:207`), copy failure (`:109`) | removed | — |

**Invariants**

- A card appears once, after both the watcher's report and the marks. Checked by: the three tests above.
- An entry whose report never comes (watcher gone, folder changed, file deleted first) stays for good. Checked by: nothing; harmless memory.

**Late and concurrent answers**

- The report before the marks, or the marks before the report: both orders present once (tests above).

### FolderWrites held-back reports (implicit)

Owner: `FolderWrites.swift:56` (`writtenAt`), `:57` (`deferredRemovals`), `:58` (`deferredRenames`). Tests: `FolderWritesTests.testARemovalFromAnOlderListingWaitsForANewerOne`, `testAnUnconfirmedRemovalWaitsForALaterListing`, `testARenameFromAnOlderListingWaitsForANewerOneAndComesBeforeTheSweep`, `testAnAddHoldsBackRemovalsFromAnOlderListing`.

Holds back a removal or rename reported by a listing older than the app's own last write, until a newer listing confirms it.

**States**: `writtenAt` (set by `add` `:113`, `writeCard` `:184`, `published` `:222`; not by `writeStitch` `:157` or `trash`), `deferredRemovals`, `deferredRenames`. Per report: current (`writtenAt <= observedAt`) or older (`writtenAt > observedAt`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| current | `removed(keys, inventory)` | — | confirmed keys: `left` (cards, drawings, `fileRemoved`); unconfirmed keys deferred and a rescan asked (`:264-270`) |
| older | `removed` | keys in `deferredRemovals` (`:260-263`) | — |
| current | `renamed(renames, inventory)` | — | `rename` now (`:284`); does not flush `deferredRenames` ([requests-5](#requests-5)) |
| older | `renamed` | in `deferredRenames` (`:282`) | — |
| older | `listed(inventory)` | — | rescan asked only (`:303`) |
| current | `listed(inventory)` | deferreds applied | flush `deferredRenames`, `sweepDrawings`, `reconcileRequests`, then the confirmed deferred removals leave through `left`: cards, drawings and `fileRemoved` (**fixed**, [requests-1](#requests-1)) |
| any | `trash` | — | `left(..., .infinity)` at once (`:253`) |

`rename` (`:287`) sends a rename to a name every listing hides (`callbacks.isVisible`) as a removal. Other renames go to `renameCards`, `renameDrawings`, `renameRequests`, in that order.

**Invariants**

- A held-back report applies once a newer listing confirms it. Checked by: the four tests above.
- A deferred removal reaches every party a direct one reaches. Checked by: `FolderWritesTests.testARemovalFromAnOlderListingWaitsForANewerOne` (**fixed**, [requests-1](#requests-1)).
- Renames apply in watcher order. Checked by: nothing ([requests-5](#requests-5)).
- Deferred keys from a previous watch folder stay (`:318-321`). Harmless leak.

**Late and concurrent answers**

- A removal reported by a listing older than the last write is applied by the next newer listing (`listed`, `:308-316`).

### ScreenshotWatcher (implicit, with explicit pieces)

Owner: `ScreenshotWatcher.swift:11`. Tests: `ScreenshotWatcherTests.testAHeldRenameWaitsForTheDeliveryOfItsOwnScan`, `testADeliveryTakesTheRenamesAnEarlierDeliveryLeft`, `testARenameOfANameWhoseArrivalIsUndeliveredIsARemoval`, `testAQueuedInventoryIsNotDeliveredAfterItsDirectoryDisappears`, `testAReplacementDirectoryReceivesLaterArrivals`, `testAnIndexedFolderThatDisappearsKeepsItsFiles`, `testAFolderThatAppearsLaterIsListedAndThenWatched`, `testTheFirstSuccessfulListingAfterRefusalIsSilent`.

Watches the screenshots folder and reports arrivals, removals, renames and inventories to the app. Confined state (`source`, `directoryID`, `generation`, `openError`, `retryDue`) lives on `queue`; the rest is in `State` under `state` (`:89-102`).

**States**: `Availability` (`:26`): `available`, `missing`, `refused`, `unavailable`. Each `scan` sets it from `read(folder)` (`:279-288`); `start()` also sets denied from the open errno (`:200`). Beside it: `scans` (scan number), `pending[name]` (an `Arrival{id, generation}`), `present`, `held` (`HeldRenames`, `:106`), `missingSince`.

**Transitions**: one scan, in order.

| Step | Event | Next state | Effects |
|---|---|---|---|
| 1 `scan` (queue) | directory source event (`:209`), `rescan(reason:)` (`:232`), 2 s `retryLater` timer (`:220`), launch (`:151`) | directory ID changed: source replaced, `held` reset (`:267-274`) | read a listing (`:276`); on failure set availability, `missingSince`, retry (`:278-288`) |
| 2 under the lock | listing read | `scans` bumped (`:291`); pending arrivals of another generation dropped (`:296-298`); `pending` keeps names still present (`:300`) | first listing only indexes (`:302-307`); renames paired by `held.hold(..., undelivered:)` (`:310`); `added` minus rename targets (`:322`) |
| 3 main queue | delivery (`:332-352`) | generation changed (`:333`): dropped; directory ID or access changed (`:334-338`): dropped, rescan asked; else `held.deliver(through: scanNumber, ...)` and `present = inventory.names` (`:339-342`) | `onRenamed`, `onInventory`, `onRemoved`, in that order |
| 4 arrivals | each added name gets an `Arrival` | `waitUntilComplete` polls every 0.1 s up to 100 times (`:420-433`); then `onNew` on the main queue if generation, `pending[name] == arrival` and directory ID still match (`:367-375`) | else `retryArrival` (`:387`); never stable: logged `never-stable`, forgotten from the index, found again by the next event or stack open (`:376-380`, `:387-394`) |

`HeldRenames` is an array of `(scan, from, to)`. `hold(pairs, scan:, undelivered:)` drops pairs whose `from` has an undelivered arrival, because the app never heard of that name; it leaves as a removal plus an arrival (`:115`). `deliver(through:)` returns held pairs with `scan <= n`, removes them, and returns `removed`: names that left `present`, minus rename sources, limited to candidates (`:122-130`).

**Invariants**

- A held rename waits for the delivery of its own scan. Checked by: `testAHeldRenameWaitsForTheDeliveryOfItsOwnScan`.
- A later delivery takes the renames an earlier one left (`<=` at `:124`). Checked by: `testADeliveryTakesTheRenamesAnEarlierDeliveryLeft`.
- An undelivered arrival's rename is a removal. Checked by: `testARenameOfANameWhoseArrivalIsUndeliveredIsARemoval`.
- A queued inventory is not delivered after its directory disappears. Checked by: `testAQueuedInventoryIsNotDeliveredAfterItsDirectoryDisappears`, the guard at `:334-338`.
- The first listing after a refusal, or of a folder that appears later, is silent. Checked by: `testTheFirstSuccessfulListingAfterRefusalIsSilent`, `testAFolderThatAppearsLaterIsListedAndThenWatched`, `testAnIndexedFolderThatDisappearsKeepsItsFiles`.
- A positive file lookup protects a name an old listing lacks (`Inventory.confirmsAbsence`, `:39-44`). Checked by: the lookup.
- The check at `:367` and the clear at `:373` are one atomic step. Checked by: nothing; they are two lock acquisitions in one main-queue block, so a scan between them sees `pending[name]` set and treats a rename of that name as removal plus arrival, then `onNew` still fires for the old name. The window is microseconds.

**Late and concurrent answers**

- Delivery for a scan whose directory was swapped: dropped, rescan asked, `:334-338`.
- An arrival superseded by a newer scan: `pending[name] != arrival` ends the poll (`:426`) and the delivery (`:367`).
- Callbacks of an old watcher after `startWatching` runs again: the `watcherGeneration` guard at `AppDelegate.swift:1481`, `:1496`, `:1499`, `:1502`.
- After `never-stable`, `pending[name]` stays set until the next scan replaces it (`:326-327`).

### Thumbnailer (implicit)

Owner: `Thumbnailer.swift:13`; all state under `lock` (`:16`). Tests: none.

A decoded-image cache with a byte budget, plus the lookups the main thread is allowed to make. `ThumbnailController` drives it.

**States**: `cache[path]` (one `Entry{modified, maxPixel, space, image, bytes}` per path), `order` (least recently used first), `bytes`, `budget`, `headers[path]` (valid while the modification date matches).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `lookUp(url)` (`:72`) | — | placeholder (`isDataless`, lstat flag): `.notDownloaded(kept header)`; else `.read(header)` or `.unreadable`; never reads a placeholder on the main thread |
| any | `download(url, completion:)` (`:86`) | — | header read on the concurrent queue (downloads the file), then `completion` on the main queue with the header or nil; no de-duplication, no cancellation (callers `ThumbnailController.swift:1259`, `:312`) |
| any | `image(at:maxPixel:space:)` (`:182`) | entry inserted | decode, convert, then `insert`; `insert` replaces any entry for the path (`:272-276`), so the last finished decode wins whatever its size |
| entry present | `cached` (`:141`) | — | served only if `entry.maxPixel >= maxPixel`, same space, `entry.modified == modified(url)` now |
| over budget | `insert` | oldest entries evicted (`evict`, `:287`) | — |

**Invariants**

- Bytes stay at or under `budget`, except for the newest entry. Checked by: `evict` at `:287`.
- A cached entry's pixels are the file's pixels at `entry.modified`. Checked by: nothing. `image(at:)` decodes (`:183-185`) before it reads the date (`:188-190`), so a file replaced in between is cached under the new date with the old pixels ([requests-6](#requests-6)).
- A renamed placeholder is downloaded. Checked by: nothing ([requests-7](#requests-7)).

**Late and concurrent answers**

- A download completion for a card that left the column does nothing: the `loadCard` closure checks `model.cards.contains`; `reshape` re-finds the card by id and refuses cards in the annotator or forming (`ThumbnailController.swift:1274`).
- A file that disappeared reads as a nil header, so `download` completes with nil.

### CaptureOrigin (implicit)

Owner: `CaptureOrigin.swift:106`. Tests: none.

Finds the screen rect a capture was taken from, for the flight into the editor. Its `CaptureRect.locate` is pure; this machine is the monitor and poll that feed it.

**States**: `monitors`, `poll: Timer?`, `pollUntil`, `wasDown`, `press`, `drag`. Together: idle (no poll), polling (30 Hz until `pollUntil`), holding a drag (after release, until used or 3 s old).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| idle | ⌘⇧ flags change (`flagsChanged`, `:128`) | polling for 15 s | — |
| polling | flags change again | `pollUntil` extended | — |
| polling | `tick` (`:144`) | — | records press and release into `press`, `drag` |
| polling | past `pollUntil` and button up (`stopPolling`, `:154`) | idle | `drag` kept |
| holding a drag | `rect(of:pixels:)` (`:162`) | `drag` cleared (`:180`) | the rect is used once |

**Invariants**

- A drag is used once and expires: bounded by `dragLifetime` (3 s) and `arrivedAt >= drag.at` in `locate`. Checked by: those two checks.
- The `recorded` metadata path is bounded by file age (`recordedLifetime`, 10 s). Checked by: that check.
- `rect(of:)` is asked for any presented screenshot with `annotate`, an agent push included (`AppDelegate.swift:1440`), so a cancelled capture drag of nearly the same size within 3 s could give a push a flight origin. Checked by: nothing; visual only.

**Late and concurrent answers**

- A drag outlives `stopPolling` on purpose, so a capture file that arrives after the poll stopped still finds it.

### ReplyCommand and ReplyProtocol (explicit by order)

Owner: `ReplyCommand.swift:78` (`run`), `:95` (`send`). Tests: `ReplyProtocolTests` (parsing and paths only); the app side is covered by the Reply.Stage tests.

The reply helper is the app's own binary, run in a separate process by an agent. It sends one frozen reply bundle and waits for the app's receipt.

**States**: the helper's steps, in order: load the ticket and check its issuer; `prepare` a frozen bundle with a new reply id (or `reread` it for `--retry`); `writeAttempt` with a new attempt id; `dispatch` through `open -g -a <app> vignette://reply?file=…`; `waitForReceipt`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| `waitForReceipt` | receipt `accepted` | exit 0 | for an answer, waits again while `publication == .pending` (`:149-152`) |
| `waitForReceipt` | receipt `rejected` | exit 2 | — |
| `waitForReceipt` | no receipt before the timeout | exit 3 `unconfirmed` | prints a retry command |
| `waitForReceipt` | dispatch exit 0 but no receipt, or a receipt for another attempt | keeps waiting, then exit 3 | receipts are keyed on request, reply, attempt, digest, protocol (`answers`, `:352`) |

App side, per attempt: `readAttempt` (ids, path, version, digest shape), look up the request, check the ticket secret, look up an existing reply by id (same digest returns the record's state), check `takesReplies`, `readBundle`, check the digest, store the payload, `write(reply)`, add to `pendingImports`, write the receipt, `importNext`. Any `Problem` writes a `rejected` receipt, except an unauthorized attempt that would overwrite an existing receipt (`reject`, `:563-574`).

**Invariants**

- A retry is the same bytes under the same reply id, so it cannot become a second card. Checked by: `ScreenshotRequestsTests.testAReplyTheCommandPreparesIsAcceptedAndItsRetryMakesNoSecondCard`.
- A retry after a clear finds no bundle and says the request was cleared. A clear removes the `submissions` folder (`cleanup`, `ScreenshotRequests.swift:856-861`; message at `ReplyCommand.swift:113`). Checked by: nothing named.

**Late and concurrent answers**

- A clear removes the attempt envelope before the app reads it: the envelope is refused, the helper is unconfirmed, and its retry is refused with the cleared message.
- A receipt for another attempt is ignored (`ReplyCommand.answers`, `:352`).

## Setup, settings and launch

This area covers what runs once per launch or once per Mac: the setup window and its model, the menu bar intro that closes it, the settings file and its sync with the app, Apple's screencapture defaults, agent plugin installs, permission requests, the login item, the updater, the disk image move and the order of the launch. Most of it is implicit state in AppKit objects. `SettingsSync` is the one explicit reducer.

Paths are under `Sources/`. Test names are `Class.testName`. A launch that sets `VIGNETTE_SETTINGS` is a test launch (`Launch.isTest`).

### SetupWindowController (implicit)

Owner: `SetupWindow.swift:51`. Tests: none.

Shows the setup window once per Mac, records what the person chose when the window closes, and plays the menu bar intro on the way out. `AppDelegate` drives it; each Setup Lab run makes its own controller.

**States**: properties that together form the state.

- `window: NSWindow?` (`SetupWindow.swift:53`) and `model: SetupModel?` (`:54`). Both nil means no setup. `open` sets both (`:117`, `:132`). `windowWillClose` nils `model` at once (`:196`) and `window` one turn later (`:199`).
- `introducing: Bool` (`:187`). Set by `windowShouldClose`, never reset. Safe only because one controller shows one window.
- `quitting: Bool` (`:57`). Set by `AppDelegate.applicationWillTerminate` (`AppDelegate.swift:211`).
- `applyLoginItem` closure (`:190`), set by `AppDelegate` before `show` (`AppDelegate.swift:176`).
- Persistent: `Settings.data.setup` (`unasked` | `done`), `UserDefaults setupDoneOnThisMac` (`:73`), `launchedHereBefore` (`:75`, read when the controller is built, before the Application Support folder exists), and `setupReturnsToLiveInkPermissions`, which is `SetupModel.returnsToLiveInkSetup` (`:408`).

Whether setup is asked (`isUnasked`, `:67`, non-test launch):

| `setupDoneOnThisMac` | file `setup` | App Support folder existed | asked |
|---|---|---|---|
| true | any | any | no |
| false | done | yes | no |
| false | done | no (synced file, new Mac) | yes |
| false | unasked | any | yes |

A test launch asks only when the file says `unasked` (`:68`). Setting the file back to `unasked` does not re-ask on a Mac that has `setupDoneOnThisMac`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| no window | `show` (once per launch, only when `isUnasked`, `AppDelegate.swift:177`) or Setup Lab `run` | window and model set | `SetupModel` built, `[setup] shown`, window key, app activated |
| window up | `open` again, or `bringToFront()` (reopen, `AppDelegate.swift:206`) | same | window to front (`:102`) |
| window up | `windowShouldClose`, `quitting` or `model == nil` | closes | returns true (`:181`) |
| window up, `introducing` | `windowShouldClose` | unchanged | returns false: a second close during the intro is ignored (`:182`) |
| window up | `windowShouldClose`, menu bar icon visible | `introducing = true` | returns false; `MenuBarIntro.play` closes the window later |
| window up | `windowShouldClose`, no icon | closes | `introduceMenuBar` returned false (`:184`) |
| window up | `windowWillClose` | `model = nil`, `window = nil` next turn | `inkPlayer.stop()`, `record` |
| closed | `granted()` or `folderAnswered(_)` from `SetupModel.look` | — | log line only; `comeBack` guards `model != nil` (`:173`) |

`record(_:)` (`:206`), per close:

- `quitting`: logs `[setup] quit before it was done` and writes nothing. `setup` stays `unasked`, so the next launch asks again.
- Otherwise: `askFolder()` if the last look saw `.ask` (`:212`). One `settings.update` writes `setup = done`, `liveInkOffered = true` if live ink's page was reached, and `launchAtLogin` only if the switch moved (`:213-217`). Then `setupDoneOnThisMac = true` and `returnsToLiveInkSetup = false`. ([setup-2](#setup-2))
- If the agents page was reached (`sawAgents`): install the chosen agents that are not installed (`installAgentPlugin(roots)`), apply `ClaudeReadRule` if Claude's plugin is already in, and write `agentSkill = off` (`:223-231`). The install is only queued; nothing waits for it. ([setup-4](#setup-4)) If the page was not reached, `agentSkill` stays `unasked` and the next launch makes the offer in Settings (`AppDelegate.swift:282`).
- `applyLoginItem()` (defers while the intro plays), then `FocusReturn.restore` next turn.

What a normal close leaves, by the page the window was on:

| Closed on | `setup` | `liveInkOffered` | `agentSkill` | Plugin install |
|---|---|---|---|---|
| welcome, shortcut | done | unchanged | `unasked` | none |
| liveInk, liveInkSetup | done | true | `unasked` unless the agents page was visited | none |
| agents | done | true if visited | `off` | chosen agents not yet installed |

On a quit, none of this is written. `liveInk` was already written when Use Live Ink or Not Now was pressed (`SetupWindow.swift:80`, `SetupModel.useLiveInk`). ([setup-16](#setup-16))

**Invariants**

- Setup is recorded as done when the window closes, not when it opens (`SetupWindow.swift:59`). Checked by: nothing.
- A quit is not an answer (`:55`). Checked by: nothing.
- `record` runs when the window closes, 0.05 s after the intro's picture is up. Checked by: nothing.

**Late and concurrent answers**

- Second close during the intro: ignored, guard at `SetupWindow.swift:182`.
- A grant or folder answer after close: log only, guard at `:173`.
- `windowWillClose` called twice: guard at `:193`.
- The view's poll running one more turn after close: effects are logs only, because the model is still alive.

### SetupModel (implicit)

Owner: `SetupWindow.swift:240`. Tests: `SetupModelTests.testNotNowClosesLiveInkAlone`, `testNotNowInAllOfSetupGoesOnToTheAgents`, `testSetupSavesOpenAtLoginOnlyWhenItsOwnSwitchMoved`, `testAToolFoundAfterSetupOpensTurnsItsSwitchOn`, `testStartingOnLiveInkPermissionsHoldsThemAfterUseLiveInk`.

The pages of setup and the flags that decide what `record` writes. The window's buttons and a 0.5 s poll drive it.

**States**

- `page: Page` (`:269`; `Page` at `:242`): `welcome | shortcut | liveInk | liveInkSetup | agents`. `pages` is derived from `scope`, `usesLiveInk` and `agents.isEmpty` (`:363-373`). `index` is 0 when `page` is not in `pages` (`:374`).
- `usesLiveInk` (`:258`): Use Live Ink was pressed. It brings in `liveInkSetup`.
- `seen: SetupConditions` (`:247`), the last look. `agents` (`:248`), refreshed only on `callbacks.changes`. `chosen: Set<URL>` (`:276`), the agent switches.
- Flags for `record`: `sawLiveInk` (`:280`), `sawAgents` (`:277`), `launchAtLogin` against `launchAtLoginAtOpen` (`:260-264`).
- `forward` (`:273`) only sets the slide direction.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| welcome | Continue, folder `.ask` with a protected area | shortcut | `askFolder()` first (`:649`) |
| shortcut | Continue | liveInk | `sawLiveInk = true`, `responders.look()` |
| liveInk | Use Live Ink | liveInkSetup | `usesLiveInk = true`; `choseLiveInk(true)` writes `liveInk = true` now |
| liveInk | Not Now, not last page | agents | `usesLiveInk = false`; `liveInk = false` written now |
| liveInk | Not Now, last page (no agents, or scope `.liveInk`) | window closes | `done()` (`:387`) |
| liveInkSetup | Continue | agents, or close | `sawAgents = true` on reaching agents |
| agents | Done | close | `done()` |
| any | Back | previous page | — |
| agents | last agent gone | last remaining page | `show(last, forward: false)` (`:328`) |

A page change is deferred one turn (`show`, `:401`). `sawAgents` is set in that deferred block (`:403`) or in `init` (`:295`).

**Invariants**

- Not Now on the last page closes the window. Checked by: `SetupModelTests.testNotNowClosesLiveInkAlone`, `testNotNowInAllOfSetupGoesOnToTheAgents`.
- `launchAtLoginChoice` is nil unless setup's own switch moved. Checked by: `SetupModelTests.testSetupSavesOpenAtLoginOnlyWhenItsOwnSwitchMoved`.
- A tool found after open turns its switch on. Checked by: `SetupModelTests.testAToolFoundAfterSetupOpensTurnsItsSwitchOn`.
- Starting on `.liveInkSetup` keeps that page. Checked by: `SetupModelTests.testStartingOnLiveInkPermissionsHoldsThemAfterUseLiveInk`.
- `look` agrees with what `record` writes. Checked by: nothing.

**Late and concurrent answers**

- `granted()` fires only on the edge `seen.trusted && !before.trusted`, guard at `SetupWindow.swift:330`.
- The folder answer fires only from a prior state that was not `.ask`, guard at `:335`, so an already-allowed folder does not pull the window forward.
- A double Continue before the deferred page change is idempotent: both target the same page.

### SetupBanter (explicit)

Owner: `SetupBanter.swift:8`. Tests: none.

A value type that picks the line the shortcut page's picture says as the person holds the key. The `.hotKeyHeld` notification, the editor closing, and a shortcut or page change drive it.

**States**: `counted: Place` and `shown: Place` (`step`, `holds`, `proven`; `:60-72`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| first hold | `hold(rowReady:)` (`:118-123`) | `counted.step = 0` | — |
| later holds | `hold(rowReady:)` | moves on only while `rowReady && line != nil` (`:75-86`) | — |
| any | `reveal()` (editor closed, or one turn after a hold with no editor open, `:121-126`) | `shown` = `counted` | at the bye line, a 1.2 s timer calls `moveOn` if `saysBye` and `rowReady()` still hold (`:138-140`) |
| any | `leftPage()` (`:127`) | "Bye." turns back into the greeting | — |
| any | `shortcutChanged()` (`SetupWindow.swift:455`) | reset | — |

**Invariants**

- None stated. Checked by: nothing.

**Late and concurrent answers**

- The dwell timer re-checks `saysBye && rowReady()` when it fires, guard at `SetupBanter.swift:139`. Leaving the page inside 1.2 s moves nothing.

### SetupInkPlayer and SetupInkGuide (implicit)

Owner: `SetupInk.swift:12` (demo), `SetupInkGuide.swift:9` (pointer). Tests: `SetupInkDemoTests.testTheSessionsTurnEndsOnlyAfterTheKeysHaveGrown`, `testTheHandFinishesEachStrokeBeforeTheNextBegins`, `testTheNoteIsSentWithAllItsWords`, `testAHandSlowsWhereTheLineTurns` (the demo's beat order only).

The live ink page's scripted demo and the pointer that retires marks. The setup view drives both.

**States**

- `SetupInkPlayer`: `played`, `next` (index into `SetupInkDemo.steps`), `writing`, `loopPen`, `loop`, `note`, `wait: NoteCardWait`, `stage.isRunning`. It plays once per window; a second `play()` calls `rest()`. `stop()` (from `windowWillClose` at `SetupWindow.swift:194`, and when the page is left) clears everything and sets `next = steps.count`.
- `SetupInkGuide`: `pointing`, `aimedAt`, `agent`, `shown`, `leaving`. `point(at:)` retires old marks with a timer (`:109`) that removes only the ids it captured. `leave()` clears all.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| not played | `play()` | playing | steps run in order |
| played | `play()` | — | `rest()` |
| playing | `stop()` | `next = steps.count` | all state cleared |

**Invariants**

- Each demo step finishes before the next begins. Checked by: `SetupInkDemoTests.testTheHandFinishesEachStrokeBeforeTheNextBegins`.

**Late and concurrent answers**

- Three deferred closures are each guarded: `openNote`'s `reveal` by `self?.note === note` (`SetupInk.swift:241`); `done()`'s line-two restore by `self.note == nil` (`:267`); `done()`'s cleanup by `self.loop?.mark.id == loop.mark.id` (`:264`), which `stop()` defeats by nil-ing `loop`.

### MenuBarIntro (implicit)

Owner: `MenuBarIntro.swift:10`. Tests: none.

Plays the picture of the setup window flying into the menu bar icon, then shows a popover. Setup's `windowShouldClose` and the Intro Lab and Setup Lab (debug windows) call it.

**States**

- `finished: (() -> Void)?` (`:32`) is the playing flag (`isPlaying`, `:34`).
- `flight: NSPanel?` (`:27`), `popover: NSPopover?`, `monitors`, `timeout: Timer?`, `shortcutFired` (`:28-31`), and `FunnelClock.begin`.

There is no enum. The phases are idle (`finished == nil`), capturing (up to 0.25 s), flying (the window closes 0.05 s after the panel is up), arrived (panel out, popover 0.12 times the motion scale later) and popover up (5 s).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| idle | `play`, duration 0 (`AppDelegate.introduceMenuBar`, `AppDelegate.swift:907`) | popover | next turn: `close()`, `showPopover` (`:59`) |
| idle | `play`, picture nil or no icon window | popover | `close()`, `showPopover` (`:67`) |
| idle | `play`, picture ok | flying | panel up, `window.hasShadow = false` at +0.02 s, `close()` at +0.05 s |
| flying | arrival | popover | panel out, popover at +0.12 times the motion scale |
| popover | timeout, click on the icon, or `.hotKeyFired` | idle | `dismiss`: `closePopover`, then `finished()` |
| capturing, flying or popover | `play` again | restarts | `dismiss()` runs the first intro's `finished` (`:55`); the first intro's deferred closures still run against the second ([setup-7](#setup-7)) |
| flying | icon hidden by `settingsChanged` | unchanged | the popover still shows on the kept `button` (`:511`) ([setup-11](#setup-11)) |

While an intro plays, `AppDelegate.applyLoginItem` (`AppDelegate.swift:269`) sets `loginItemAfterIntro`. The intro's `finished` clears it and calls `applyLoginItem()` again (`:918-922`). A quit before then drops nothing: every later launch applies the setting.

**Invariants**

- `finished != nil` from `play` until the popover is gone (`MenuBarIntro.swift:33`). Checked by: nothing.

**Late and concurrent answers**

- A second `play` while one is up calls `dismiss()` and orders out the old panel, guard at `MenuBarIntro.swift:55-58`. The first intro's closures at `:65`, `:122`, `:130-145` are not cancelled. ([setup-7](#setup-7))
- The capture races its 250 ms limit through `Gate`, guard at `:679`.
- The popover timer, monitors and shortcut observer are removed together in `closePopover` (`:157`).
- `canSee` is checked once, when setup closes (`AppDelegate.swift:908`). ([setup-11](#setup-11))

### Accessibility.request (implicit)

Owner: `SettingsWindow.swift:857` (in `enum Accessibility`, `:838`). Tests: none.

Raises macOS's Accessibility alert from a button press and brings the asking window back. Callers are setup rows (`SetupWindow.swift:530`, and `callbacks.askAccessibility` in `SetupInk.swift`), Settings rows (`SettingsWindow.swift:272`, `:305`) and the status menu (`AppDelegate.swift:1086`).

**States**: no stored state. The machine is the alert's presence (`alertOwnerPID`, `:909`: a window of `universalAccessAuthWarn`) plus the `Task` started per call.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| alert up | `request` | unchanged | `bringForward(alert)`, no new Task (`:858`) |
| no alert yet | `request` | Task started | `trusted(prompt: true)`; waits up to 1.5 s for the alert; if it came, waits until it is gone; else opens the pane |
| alert already up but not yet seen | `request` | second Task | a second prompt and Task start ([setup-5](#setup-5)) |
| already trusted | `request` | Task started | no alert appears, the wait times out, and System Settings opens ([setup-6](#setup-6)) |
| Task, after alert or pane | System Settings in front | waits | polls every 250 ms for trust or System Settings quitting |
| Task end | not trusted and `asking` visible | — | `makeKeyAndOrderFront` on the asking window |

A grant is left to each window's own poll: `SetupModel.look` 0.5 s, `SettingsView` 1 s, `KeyMonitors` 2 s.

**Invariants**

- One alert at a time. Checked by: the guard at `SettingsWindow.swift:858`, which only sees an alert already on screen ([setup-5](#setup-5)).
- No pane opens for a permission already granted. Checked by: nothing (`ScreenRecording.request` has this guard at `ScreenRecording.swift:12`; this one does not) ([setup-6](#setup-6)).

**Late and concurrent answers**

- A press during the alert: handled by the early return at `:858`.
- The asking window closed during the wait: guard on `asking.isVisible`.
- A grant landing mid-loop: `ModifierTap.trusted` is re-checked on each pass.

### ShortcutRecorderView (implicit)

Owner: `SettingsWindow.swift:644`. Tests: none.

The control that records a key combination for the shortcut. Mouse, key and window events drive it.

**States**: `recording`, `refused`, the `outsideClick` monitor, `recordOnWindow`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| idle | mouseDown, or `viewDidMoveToWindow` with `recordOnWindow` | recording | `begin`: monitor installed |
| recording | key equivalent or keyDown | idle, or refused | `stop()` on accept; a refused combination keeps the refusal text |
| recording | resign or outside click | idle | `stop()`: clears `refused` and its text, removes the monitor |
| any | `deinit` | — | monitor removed |

**Invariants**

- The monitor is present exactly while `recording`; `begin` and `stop` set and clear them together. Checked by: nothing.

**Late and concurrent answers**

- None found.

### SettingsSync (explicit) and Settings (shell)

Owner: `SettingsSync.swift:5` (reducer), `Settings.swift:514` (timers, watchers, `data`). Tests: `SettingsTests.testRandomSequencesKeepTheInvariants`, `testAnUpdateMadeDuringAWritesTakeInIsInThatWrite`, `testWriteComesAfterTheDelayAndItsOwnEchoAppliesNothing`, `testAFileThatDoesNotParseKeepsTheSettingsAndTheNextWriteReplacesIt`, `testNothingIsWrittenWhileReadOnlyButFileEditsStillArrive`, `testAFileFromANewerVersionMakesTheAppReadOnlyMidRun`, `testAFlushTakesInAPendingFileEditBeforeItWrites`.

Keeps `settings.json` and the app's settings in step. The reducer decides; `Settings` runs the timers, the file watchers and the disk reads.

**States**

- Reducer: `syncedBytes` and `syncedData` (what the file and app last agreed on), `changedSinceFlush`, `readOnly` (never cleared).
- Shell: `writeWork` and `reloadWork` (`DispatchWorkItem`s), `directorySource`, `fileSource`, `hold: EventHold`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `appChanged` (from `update`, `restoreAppleDefaults`, `followAppleLocation`) | `changedSinceFlush = true` | `scheduleWrite(0.3)` |
| any | `fileChanged` (directory or file watcher) | — | `scheduleReload(0.15)` |
| any | `reloadDue(file, app)` | — | `takeIn` |
| any | `writeDue(file, app)` | — | `takeIn`, then `writeAppData`; the `appData` answer writes |
| any | `flush(file, app)` | — | `takeIn`, then `writeAppData` |
| `!changedSinceFlush` | `quit` | — | — |
| `changedSinceFlush` | `quit` | — | `cancelWrite`, `readFileAndFlush` |
| not read-only | `appData(d)` | `syncedBytes` and `syncedData` set | `write(raw)`; the shell's write can fail unreported ([setup-3](#setup-3)) |
| read-only | `appData(d)` | — | refused: no write |

`takeIn`:

- No-op when the file read failed or equals `syncedBytes`.
- `.invalid` logs and keeps the app's settings.
- `.loaded` validates, three-way merges when `syncedData != app` (the file wins a double change and logs it), emits `apply(next, "file")`, and stamps a pre-version file.

Effects: `log`, `apply`, `write`, `writeAppData`, `readFileAndFlush`, `scheduleWrite`, `cancelWrite`, `scheduleReload`.

Bootstrap (`Settings.bootstrap`, `Settings.swift:605`): `loaded`; `missing` (create it, or read-only with a notice if that fails); `invalid` (move aside to `.invalid` and use defaults, or read-only if the move fails). A file from a newer version makes the app read-only. Tests: `SettingsTests.testInvalidFileIsSetAsideNotOverwritten`, `testAFileThatCannotBeCreatedIsReadOnlyWithANotice`, `testNewerVersionIsReadOnly`.

**Invariants**

- Nothing is written while read-only; no value is clamped silently; a conflict is logged for exactly the keys both sides changed; every edit survives or loses to a logged file conflict. Checked by: `SettingsTests.testRandomSequencesKeepTheInvariants`.
- A failed `write` is noticed. Checked by: nothing; `Settings.write` discards the error (`Settings.swift:951-953`, `:883`) and a later reload reverts the app to the old file ([setup-3](#setup-3)).
- The directory watch survives the folder being replaced. Checked by: nothing; `directorySource` is made once with mask `.write` (`Settings.swift:975-982`) ([setup-15](#setup-15)).

**Late and concurrent answers**

- Reload and write read the file when the timer fires, not when it is set: `sendReadingFile`, `Settings.swift:941`.
- A write first takes in a pending hand edit (the `writeDue` case). Checked by: `testAFlushTakesInAPendingFileEditBeforeItWrites`.
- `onChange` calling `update` during `apply` is held by `EventHold`, and the write uses the data afterwards: `Settings.swift:931`. Checked by: `testAnUpdateMadeDuringAWritesTakeInIsInThatWrite`.
- The app's own write echoing back as `fileChanged` is a no-op because the bytes are equal. Checked by: `testWriteComesAfterTheDelayAndItsOwnEchoAppliesNothing`.
- A half-written file logs `settings-invalid` and keeps the settings. Checked by: `testAFileThatDoesNotParseKeepsTheSettingsAndTheNextWriteReplacesIt`.
- An atomic write replaces the inode, so `watchFile()` re-arms: `Settings.swift:951`.

### Apple screencapture reconcile (implicit)

Owner: `Settings.swift:822-870` (`handBackAppleThumbnail`, `reconcileApple`, `followAppleLocation`, `pushToApple`), `AppleScreencapture.Observer` (`:1044`). Tests: none.

Keeps Apple's `com.apple.screencapture` defaults the way Vignette needs them: its floating thumbnail off while Vignette runs, its save location followed.

**States**: `data.appleThumbnail`, `data.screenshotsFolder`, `data.appleOriginal`; Apple's `show-thumbnail`, `location` and `target`; the published `appleTarget`; observers `appleLocation` and `appleTargetObserver`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| launch | `reconcileApple()` (`AppDelegate.swift:164`, before the watcher) | — | `show-thumbnail` forced to `data.appleThumbnail`; `followAppleLocation()` once; observers installed for `location` and `target` |
| running | Apple's `location` changes (KVO, async to main) | `screenshotsFolder` follows | `followAppleLocation` re-reads Apple's value; no-op when it equals `data.screenshotsFolder` (`samePath`) |
| running | Apple's `show-thumbnail` turned on | unchanged | no observer, so it stays on until the next launch ([setup-9](#setup-9)) |
| running | a Vignette setting changes (`apply` with `pushApple`) | — | `pushToApple` writes only changed keys (`:864`) |
| quit | `handBackAppleThumbnail()` (`AppDelegate.swift:215`) | — | `show-thumbnail = true` only when Vignette had it off, Apple showed it before, and no other instance of this bundle id runs |

**Invariants**

- Apple's thumbnail is off while Vignette runs. Checked by: only at launch (`Settings.swift:827-830`) ([setup-9](#setup-9)).
- Vignette's own write to `location` coming back is ignored. Checked by: `samePath` in `followAppleLocation`.

**Late and concurrent answers**

- Two quick `location` writes both resolve against the latest value, because `followAppleLocation` re-reads Apple's current value.
- Hand-back is skipped when a newer instance exists, guard at `AppDelegate.swift:214`. The newer launch turns the thumbnail off again.
- A force quit (3 s after `replaceOlderInstances`, `AppDelegate.swift:235`) skips `willTerminate`, so the setting stays off, which the next launch expects.
- Between a Sparkle quit and the relaunch, no second instance exists, so hand-back turns Apple's thumbnail on until the new launch reconciles. A capture in that gap is held by Apple for about 5.6 s. This is by design.

### AgentPlugins (implicit)

Owner: `AgentPlugin.swift:401` (class), `AppDelegate.swift:276-350` (callers). Tests: `AgentPluginTests.testLaunchMigratesTheOldSkillAndUpdatesOlderPlugins`, `testLaunchInstallsNothingWhereNothingWas`, `testOldSkillFolderGoesAndALinkStays`, `testALaunchLeavesThePluginOffAfterTheSwitchTurnedItOffWhereTheOldSkillIsALink`, `testALaunchThatFindsThePluginBesideALinkedSkillLeavesItOffOnceTheSwitchTurnsItOff`.

Installs, updates and removes the Vignette plugin in Claude Code and Codex, one run at a time on a serial `DispatchQueue("vignette.agent-plugin")`.

**States**: per root, the truth is on disk (Claude's `settings.json` `enabledPlugins`; Codex's `config.toml`), read by `AgentPlugin.isInstalled`. UI state: `SettingsView.agentWorking[root]` (disables the switch while a run is out, `SettingsWindow.swift:418`), `agentFailures`, `agentsJustInstalled`, and `AppDelegate.pluginFailures` (`AppDelegate.swift:27`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| plugin not on, legacy skill folder present | `launch` (`startAgentPlugin`, `AppDelegate.swift:282`, only when setup is not unasked) | on | installs the plugin (`AgentPlugin.swift:453-456`); the folder is recorded in `LegacySkillMigrations`, then removed |
| plugin not on, legacy skill is a link, folder not recorded | `launch` | on | installs the plugin and records the folder; the link stays ([setup-1](#setup-1), [issue 12](#issue-12)) |
| plugin not on, legacy skill is a link, folder recorded | `launch` | — | — (the switch's off holds) |
| plugin on, legacy skill present | `launch`, or `install(into:)` succeeding | on | records the folder (`retireLegacySkill`, `AgentPlugin.swift:515`) |
| plugin not on, no legacy skill | `launch` | — | — |
| plugin on, marketplace changed or version differs | `launch` | on | `plugin update` (`:458`) |
| any | `install(into:)` (Settings switch, setup `record`, `install-skill`) | on | stage the marketplace, run the tool's install steps, remove the legacy folder |
| any | `remove(from:)` (Settings switch) | off | the tool's uninstall steps; "not found" counts as done |

**Invariants**

- A launch never removes the plugin, and installs only where the skill from before the plugin is. Checked by: `AgentPluginTests.testLaunchInstallsNothingWhereNothingWas`, `testLaunchMigratesTheOldSkillAndUpdatesOlderPlugins`. The guard at `AgentPlugin.swift:453` counts a link as that skill.
- A launch installs for the old skill at most once per agent folder, so the switch's off holds. Checked by: `testALaunchLeavesThePluginOffAfterTheSwitchTurnedItOffWhereTheOldSkillIsALink`, `testALaunchThatFindsThePluginBesideALinkedSkillLeavesItOffOnceTheSwitchTurnsItOff` ([setup-1](#setup-1)).
- An install started by setup finishes before the app quits. Checked by: nothing; `applicationWillTerminate` (`AppDelegate.swift:210`) waits for `requests.releaseHeld()` and not for this queue ([setup-4](#setup-4)).
- `ClaudeReadRule.set` does not lose a concurrent write to Claude's `settings.json`. Checked by: nothing; it reads and rewrites without a lock.

**Late and concurrent answers**

- A launch update against a switch: both go to the one queue, so they are ordered, and `launch` decides from disk at its own turn.
- Two installs queued: each is idempotent in effect and runs twice.
- The Settings window closed mid-run: its `@State` is discarded and the next open reads the disk again.
- Setup's install failing opens the Agents tab (`installAgentPluginFromSetup`).

### AgentTools (implicit)

Owner: `AgentTools.swift:8`. Tests: `AgentPluginTests.testAToolIsFoundUnderTheNewestNodeAndInTheShellsAnswer`.

Finds the `claude`, `codex` and `herdr` programs. `start()` runs once per launch.

**States**: `started`, `fromShell`, `shellPath`, `shellDone` (a baton semaphore).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| not started | `start()` | started | the login shell runs off the main thread with an 8 s timeout (`:92`) |
| started | `path(...)` on the main thread | — | answers at once from what is known |
| started | `path(...)` off the main thread | — | waits up to 8 s for `shellDone`, then re-signals it (`:36-37`) |
| shell finds a tool | answer | — | `found` posted on main |

**Invariants**

- A tool the login shell finds late is not reported missing. Checked by: nothing; a timeout signals the baton with `fromShell` empty, so a waiter returns nothing and `PluginHost.steps` returns `.noTool` (`AgentPlugin.swift:313`) ([setup-12](#setup-12)).

**Late and concurrent answers**

- A timeout signals the baton early, so later waiters return at once with nothing: `AgentTools.swift:36-37`.

### LoginItem (implicit)

Owner: `LoginItem.swift:7`. Tests: none.

Registers Vignette as a login item. The state is `SMAppService.mainApp.status` plus `UserDefaults loginItemRegisteredPath`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| macOS agrees with the setting | `apply(enabled)` | — | skipped |
| macOS disagrees | `apply(enabled)` | registered or not | logs errors; a test launch changes nothing |
| `.notRegistered` or `.notFound` and the registered path is this copy | launch (`AppDelegate.swift:183`) | `launchAtLogin` off | `removedByPerson` |
| setup unasked | launch | — | the item is left alone; setup's `record` calls `applyLoginItem()` |

**Invariants**

- A login item the person removed is not registered again. Checked by: `removedByPerson`, applied at `AppDelegate.swift:183`.

**Late and concurrent answers**

- Registration waits for the menu bar intro: `loginItemAfterIntro` (see MenuBarIntro).

### Updater and the update dot (implicit)

Owner: `Updater.swift:11` (`waiting`, `:12`), `AppDelegate.swift:1102-1170` (`updateDot`). Tests: none.

Shows a dot on the status item when Sparkle finds an update on a scheduled check.

**States**: `waiting` and `statusItem`, read together each time `showUpdateDot` runs.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `standardUserDriverWillHandleShowingUpdate`, scheduled and not user-initiated, Sparkle not showing it itself | `waiting` set | `showUpdateDot` |
| waiting | `...DidReceiveUserAttention` or `...WillFinishUpdateSession` | `waiting` cleared | dot removed |
| waiting, no status item | `showUpdateDot` | — | `updateDot = nil` (`AppDelegate.swift:1121`) |
| any, test launch | startup | — | no updater unless `VIGNETTE_FEED` is set (`:1103`) |

**Invariants**

- An update that waits always has somewhere to show. Checked by: nothing. Hiding the icon leaves `waiting` set until Sparkle's next scheduled check, which then shows its own window because `hasStatusItem` is false.

**Late and concurrent answers**

- None found.

### AppLocation (explicit, linear)

Owner: `AppLocation.swift:9`. Tests: none.

Runs from `main` before settings exist, when the app starts from a disk image.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| not on a disk image and not translocated | launch | — | returns |
| an installed copy has a newer `CFBundleVersion` | launch | exits | opens the installed copy, ejects the image |
| otherwise | launch | alert | offer to move |
| alert | Quit | exits | — |
| alert | Move | exits | copy to a staging folder, clear quarantine, trash an older copy (`:145`), move into place (`:146`), reopen as a new instance (waits up to 10 s) |
| Move | the final move throws | exits with code 1 | failure alert; the older copy is already in the Trash ([setup-13](#setup-13)) |
| moved copy running | launch | — | ejects the image, 10 retries 0.5 s apart (`:149`) |

**Invariants**

- The installed app survives a failed move. Checked by: nothing; the older copy is trashed before the move (`AppLocation.swift:145-146`) ([setup-13](#setup-13)).

**Late and concurrent answers**

- None found.

### Launch sequence (implicit, ordered)

Owner: `AppDelegate.swift:84-199`. Tests: none.

The order of `applicationDidFinishLaunching`. Order that matters:

1. `replaceOlderInstances` first; its result goes to `startRequests(clearingUnsent: !replacing)`.
2. `AppLocation.ejectDiskImageIfAsked`, `AgentTools.start`, `updateStatusItem`, `startUpdater`.
3. `reconcileApple`, before the watcher.
4. `Leftovers`, `startDrawings`, `startRequests`.
5. `watcherWaitsForSetup`, decided from `isUnasked` (`:131`); `startWatching` unless waiting.
6. `registerHotKey`, `liveInk.setOn`.
7. `settings.onChange` is assigned (`:140`), so changes made earlier, including `followAppleLocation` at launch, never reach `settingsChanged`.
8. Either `setupWindow.show`, or the login item plus `startAgentPlugin` and `offerLiveInk` (`:194`).
9. `sessions.refreshKeptLists`, then `[app] ready` last (`:198`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| `watcherWaitsForSetup` | first launch, protected folder | — | no watcher until setup's Allow…, Continue or close; `askForFolder` (`:1463`) is the only place that clears it |
| `watcherWaitsForSetup` false | `settingsChanged` with a folder in the Desktop, Documents or Downloads | watcher started | macOS's prompt appears with no row in setup to explain it (`:247-249`) ([setup-14](#setup-14)) |
| before `[app] ready` | `application(_:open:)` (`:674`) | command runs | no ready gate ([setup-10](#setup-10)) |

**Invariants**

- After `[app] ready`, every command answers. Checked by: nothing; commands arriving earlier are not held ([setup-10](#setup-10)).
- A first launch with a protected folder starts no watcher until setup asks. Checked by: `watcherWaitsForSetup`, cleared only in `askForFolder` (`AppDelegate.swift:1463`); a later folder change bypasses it ([setup-14](#setup-14)).

**Late and concurrent answers**

- A URL delivered before `applicationDidFinishLaunching` runs on unwired controllers: `thumbnail.actions`, the callbacks, `startDrawings`, `startRequests` and `settings.onChange` are all set inside it ([setup-10](#setup-10); unverified whether macOS delivers it first).

### Hotkey press and hold pair (implicit)

Owner: `AppDelegate.swift:375`. Tests: none.

`fire` records `pressDismissed` and `holdTarget` on each press (`:385-386`); `hold` reads them. `ModifierTap` and `HotKey` guarantee that a hold follows its own `fire`. A hold whose `holdTarget` was trashed since goes to `annotate([shot])`, which `thumbnail.annotate` is expected to refuse. That refusal belongs to the run area and was not traced here.

### Stitch action (implicit)

Owner: `AppDelegate.swift:450-478`. Tests: none.

A stitch request composes off the main thread, then `finishStitch` runs on main: it names the file from the clock to the second, writes it, fills the clipboard, and calls `thumbnail.stitched` or `showCopied`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| composing | pieces gone | — | `ThumbnailController.stitched` returns false (`ThumbnailController.swift:546`); `showCopied` is used |
| composing | two stitches finish in the same second | one file | the second write overwrites the first, with no name check (`AppDelegate.swift:468`, `FolderWrites.swift:157-159`) ([setup-8](#setup-8)) |

**Invariants**

- Each stitch gets its own file. Checked by: nothing (`writeCard` asks `Commands.destination` for a free name at `FolderWrites.swift:169`; stitch does not) ([setup-8](#setup-8)).

### Setup Lab and Intro Lab (debug)

Owner: `SetupLab.swift:18`, `IntroLab.swift`. Tests: none.

Debug windows that run setup and the intro without recording anything. A Setup Lab `Run` holds one controller each, with `closing`, `current` and `replaced`. Its `answerLater` guard compares the override with the value it was asked from (`SetupLab.swift:278`). The Intro Lab uses a stand-in window with 0.4 s and 0.6 s delays. Both share the app's single `MenuBarIntro`, so they can meet its second-play case ([setup-7](#setup-7)).

## Live ink: the hand

Live ink is drawing on the live screen while a two-modifier chord is held. This area is the hand side: the chord, the inking lifecycle, strokes, the event tap that swallows clicks, overlay windows, window tracking, Esc, the focus tour, listening, and the menu hand-off. Asks, notes and responders are in "Live ink: asks and responders".

Almost none of this has an executable contract. `LiveInkTests` covers `HeldChord`, `ListeningEnd`, `SpokenNote`, `InkStroke` and static helpers, and `LiveEscapeTests` covers the pure `LiveEscape.next`. No test constructs `LiveInk`, `LiveInkTap`, `LiveWindows`, `LiveListening` or `LiveInkOverlay`.

### HeldChord (explicit)

Owner: `ModifierChord.swift:8`. Tests: `LiveInkTests.testBeginsOnExactlyControlAndOptionInEitherOrder`, `testAKeyEndsItUntilTheModifiersAreLetGo`, `testLettingGoOfTheRestOfALargerChordDoesNotBeginIt`, `testAnotherModifierJoiningInterruptsItUntilTheModifiersAreLetGo`, `testDoesNotBeginWithAnotherModifierHeld`, `testIgnoresFlagsThatAreNotModifiers`.

A pure value that turns modifier flags and key presses into `Change`s: `.began`, `.ended`, `.interrupted`. `ModifierChord` feeds it.

**States**: idle (`isHeld` false, `waitingForRelease` false), held (`isHeld`, `ModifierChord.swift:10`), waiting-for-release (`waitingForRelease`, `:11`). Waiting means the chord was broken and the pair must be fully released before it can begin again.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| idle | `flagsChanged`, flags equal the pair | held | `.began` |
| idle | `flagsChanged`, flags a strict superset of the pair | waiting | — |
| idle, waiting | `flagsChanged`, flags disjoint from the pair | idle | — |
| waiting | `flagsChanged`, anything else | waiting | — |
| held | `flagsChanged`, flags equal the pair | held | — (the monitor and the poll may both report it) |
| held | `flagsChanged`, flags a superset but not equal | waiting | `.interrupted` |
| held | `flagsChanged`, flags not a superset | idle | `.ended` |
| held | `keyDown()` | waiting | `.interrupted` |
| idle, waiting | `keyDown()` | unchanged | — |

Letting go of one modifier and pressing it again while the other stays down gives `.ended`, then `.began`.

**Invariants**

- It begins only on exactly the pair, in either order. Checked by: `testBeginsOnExactlyControlAndOptionInEitherOrder`.
- A key or another modifier ends it until the pair is released. Checked by: `testAKeyEndsItUntilTheModifiersAreLetGo`, `testAnotherModifierJoiningInterruptsItUntilTheModifiersAreLetGo`.
- Two reports of the same flags give one change. Checked by: the equal-flags return at `ModifierChord.swift:35`.

**Late and concurrent answers**

- The monitor and the 50 ms poll can both report one flag change: the second returns no change, `ModifierChord.swift:35`.

### ModifierChord (implicit)

Owner: `ModifierChord.swift:63`. Tests: none.

Owns a `HeldChord`, the key monitors and a poll that detects a key pressed during the chord. `LiveInk.makeChord` creates it and `LiveInk.takeChord()` replaces it.

**States**: `chord` (`:64`), `keyWatch: Timer?` (`:66`), `beganAt` (`:68`, set only from a monitor event). The states: not held (no `keyWatch`), held (`keyWatch` running).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| not held | monitor `flagsChanged` giving `.began` | held | `keyWatch` created (`apply`, `:94`), `beganAt` set |
| held | monitor `flagsChanged` giving `.ended` or `.interrupted` | not held | `keyWatch` invalidated first |
| held | 50 ms `checkKeys` (`:105`) reads flags or a key | not held or held | `HeldChord.flagsChanged` or `keyDown()`; changes go to `apply` |
| not held | `checkKeys` | — | the poll does not run |

**Invariants**

- The poll timer runs exactly while the chord is held. `apply` invalidates it before every change and creates it only on `.began`. Checked by: nothing.
- The poll never produces `.began`, so `beganAt` always comes from a monitor event. Checked by: nothing.

**Late and concurrent answers**

- Object teardown: `isolated deinit` invalidates the timer, `ModifierChord.swift:80`.
- The URL commands `live-ink-chord-down` and `live-ink-chord-up` (debug only, `AppDelegate.swift:713`) call `chordChanged` directly. The real `ModifierChord` never sees `.began`, so it has no `keyWatch` and nothing ends the inking ([hand-10](#hand-10)).

### LiveInk inking lifecycle (implicit)

Owner: `LiveInk.swift:1760` (`chordChanged`), `:1778` (`startInking`), `:1803` (`stopInking`), `:1928` (`finishInking`). Tests: none.

Decides when the screen takes ink, and what happens to the ink when the hand lets go. Driven by `ModifierChord`, the debug URL commands, and the stack and system events listed below.

**States**: the properties below form the state.

- `isInking` (`LiveInk.swift:13`): the chord is held, and the tap and overlays are up.
- `inking: [Surface]` (`:17`): the surfaces taking presses, fixed by `startInking`. A surface is one overlay window on one screen of one Space.
- `tap: LiveInkTap?` (`:27`), `pressedSurface` (`:30`).
- `fieldTimer` (`:21`), `chordShowsField` (`:23`): the pointer field and listening start together at the first stroke movement or after `ui.liveInkFieldDelay`.
- `releaseWatch: Timer?` (`:25`): non-nil means the chord was let go mid-stroke and the button is awaited.
- `inkings: Int` (`:1951`): counts inkings. `menusWaiting: Int?` (`:1953`): the inking whose note waits for open menus to close.
- `chordInterrupted` (`:68`), `drewWhileInking` (`:66`).
- `strokeBegan` (`:89`), `strokeScreenDiagonal` (`:91`): scratch for the stroke in progress.
- `overMenus` (`:465`), `pinsAfterMenus` (`:468`), each overlay's `keptAboveMenus`.
- `preview`, `justPicked` (`:129`, `:132`): hover preview.

Derived states:

- Idle: `!isInking`, `releaseWatch == nil`, `inking` empty.
- Inking: `isInking`, tap up (or refused), field timer pending or `chordShowsField`.
- Stroking: Inking and some `inking` overlay `isTracking`.
- ReleasePending: `isInking && releaseWatch != nil` (chord up, button down).
- MenuWait: `!isInking && menusWaiting == inkings` (chord up, an open menu is being closed, ink kept above menus).
- Settled: `!isInking`, nothing pending. Idle and Settled differ only in history.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `.began` and `mayInk()` false | unchanged | log only; `HeldChord` stays held (`:1763`) |
| Idle, Settled, MenuWait | `.began` | Inking | `chordInterrupted=false`, `listening?.pressedAgain()`, then `startInking`: `inkings += 1`, `FocusReturn.sessionStarting`, `drewWhileInking=false`, `releaseWatch=nil`, `inking=activeSurfaces()`, overlays `setInking(true)`, `startTap`, hover, `fieldTimer`. A pending `closeMenus` is dropped by the `inkings` mismatch. |
| Inking, Stroking | `.began` (script, or a re-begin) | same | `startInking` runs again: new `inkings`, timer restarted, tap and `pressedSurface` kept (`startTap` guard, `:1826`) |
| ReleasePending | `.began` | Stroking | `releaseWatch` invalidated (`:1783`); the stroke now ends without ending inking |
| Inking | first non-empty `strokeMoved`, or `fieldTimer` fires | Inking, field shown | `showFieldForChord`: `holdField`, `letGoOfFocus("ink")`, `InkBackdrop.refresh`, `listen()` |
| Stroking | tap `.released` | Inking | overlay `endStroke` → `strokeEnded` → `take`; `strokeBegan=nil` |
| Inking | `.ended` or `.interrupted`, no overlay tracking | Settled or MenuWait | `finishInking` |
| Stroking | `.ended` or `.interrupted` | ReleasePending | `watchRelease` |
| ReleasePending | tap `.released` | Settled or MenuWait | `strokeEnded` → `finishInking` (`:1921`) |
| ReleasePending | 50 ms poll finds `!LiveInkTap.isButtonDown` | Settled or MenuWait | `endStroke` on each inking overlay, `finishInking` (`:1987`) |
| any inking state | `spaceChanged`, `willSleep`, `sessionDidResignActive`, `screensChanged` with a changed inking frame, `takeChord()` | Settled | `cutInkingShort`: a note by the pointer closes, `stopListening`, `stopInking`. Stroke dropped (`cancelStroke`), no note ([hand-6](#hand-6)) |
| any inking state | `standAside()` (from `ThumbnailController.onTakesScreen`) | Settled | note hidden, `stopListening`, `stopInking`. No note for ink drawn this hold ([hand-6](#hand-6)) |
| any inking state | `setOn(false)` | Settled | `stopInking`, everything torn down (`:206`) |
| Idle, Settled, MenuWait | `.ended` or `.interrupted` | — | ignored by `guard isInking` (`:1773`) |
| `finishInking` | no open menus | Settled | `pinOverMenus`, `settleInking(opensNote)` |
| `finishInking` | open menus and `opensNote` | MenuWait | surfaces kept at `.screenSaver`; `closeMenus` after the glance or `revealLimit` (0.8 s) |
| MenuWait | first `closeMenus` caller | Settled | `LiveMenus.close`, `pinOverMenus`, then `settleInking(opensNote:true, takingKeys:)`; stops early if `!isOn`; no note if `!mayInk()` ([hand-6](#hand-6)) |
| MenuWait | second `closeMenus` caller | — | ignored: `menusWaiting == nil` (`:1956`) |
| any inking state | a display is added | unchanged | `inking` was fixed at `startInking`; the tap swallows clicks on the new display ([hand-12](#hand-12)) |
| MenuWait | `LiveMenus.close` runs | unchanged | Accessibility reads on the main thread ([hand-13](#hand-13)) |

`finishInking` sets `opensNote` to `noteHangsAtPointer || heardWords` with no new ink, else `drewWhileInking || listening != nil || heardBeforeNote != nil || !chordInterrupted` (`:1930`).

**Invariants**

- The tap exists only while inking. Checked by: `stopInking` → `stopTap` (`LiveInk.swift:1814`).
- Inking never covers the stack or the annotator. Checked by: the `mayInk()` gate at `.began` (`:1762`) and `standAside()` mid-ink.
- A chord let go mid-stroke keeps the overlays raised until the button is up. Checked by: `watchRelease` (`:1982`).
- Ink no ask has been about always has its note. Checked by: nothing; cut-short inking breaks it ([hand-6](#hand-6)).
- No frame shows two copies of a mark handed from a surface to its window. Checked by: `LiveMarksLayer.handOff`, nothing tests it.
- A surface exists only while it has marks, is inking or holds the note. Checked by: `closeEmpty` (`:2050`).

**Late and concurrent answers**

- A press again before the button came up: `releaseWatch` invalidated, `LiveInk.swift:1783`.
- A stale menu closer from an earlier inking: dropped by `menusWaiting == inking, inkings == inking, !isInking`, `:1956`, and again in the closure, `:1960`.
- The two menu-close triggers (the glance `Task` and the 0.8 s `asyncAfter`) run one close: `menusWaiting = nil` after the first, `:1957`.
- A stroke's release after the chord was let go: `chordChanged(.ended)` checks `inking.contains(where: \.overlay.isTracking)`, `:1774`.
- `stopInking` always invalidates `releaseWatch` and `fieldTimer` and resets `chordShowsField`, `:1806`.
- A tap hand-off queued before `stopTap`: dropped by `source != nil` (`LiveInkTap.swift:194`); `pressedSurface = nil` in `stopTap` (`:1835`); `inking` is empty so `under()` finds nothing (`:1847`).
- `setOn(false)` does not clear `menusWaiting`, `fieldTimer` or `releaseWatch` unless inking was on; a pending `closeMenus` after off cancels the menus before it checks `isOn`, `:1958`.

### LiveInk stroke (implicit)

Owner: `LiveInk.swift:1864` (`strokeMoved`), `:1911` (`strokeEnded`); overlay side `LiveInkOverlay.Canvas` (`LiveInkOverlay.swift:182`). Tests: `LiveInkTests` covers `InkStroke` classification and `markToErase` only.

One press-drag-release on an inking overlay. The canvas collects points; `LiveInk` classifies the stroke (`take`, `:398`) as an ellipse, an arrow, a tap (pick, erase or miss) or nothing. A short press is a tap and erases the mark under it.

**States**: per overlay `stroke: [CGPoint]` (`LiveInkOverlay.swift:182`) and `isTracking = !stroke.isEmpty` (`:203`). In `LiveInk`: `strokeBegan`, `strokeScreenDiagonal` (`:89`, `:91`), `pressedSurface` (`:30`), `strokeTimes`, `drawingOn`. States: not tracking, tracking.

**Transitions** (`Canvas.take`, `LiveInkOverlay.swift:265`)

| State | Event | Next state | Effects |
|---|---|---|---|
| not tracking | `.moved` | not tracking | `onHover` |
| tracking | `.moved` | tracking | ignored (`guard !isTracking`); hover freezes ([hand-3](#hand-3)) |
| any | `.pressed` | tracking, `[point]` | restarts without ending a stroke already tracking; `onStrokeMoved` ([hand-1](#hand-1)) |
| not tracking | `.dragged`, `.released` | not tracking | ignored |
| tracking | `.dragged` | tracking | append, `onStrokeMoved` |
| tracking | `.released` | not tracking | `endStroke` → `onStroke(points)` → `strokeEnded` |
| tracking | `endStroke()` (from `watchRelease`) | not tracking | `onStroke(points so far)` |
| tracking | `setInking(false)` | not tracking | `cancelStroke` → `onStrokeMoved([])`, no `onStroke`; the stroke is dropped ([hand-1](#hand-1), [hand-6](#hand-6)) |

`strokeMoved` sets `strokeBegan` and `strokeScreenDiagonal` only when `strokeBegan == nil` and `points` is non-empty. Only `strokeEnded` clears them ([hand-1](#hand-1)). A release that the tap did not see reaches neither the app nor the canvas ([hand-2](#hand-2), [hand-3](#hand-3)).

**Invariants**

- A stroke is dropped, never taken, when inking is cut short. Checked by: `cancelStroke` (`LiveInkOverlay.swift:291`).
- `strokeTimes` records `strokeBegan ?? Date()` (`LiveInk.swift:438`). Checked by: nothing; a stale `strokeBegan` breaks it ([hand-1](#hand-1)).

**Late and concurrent answers**

- `tapped(.dragged)` and `tapped(.released)` guard on `pressedSurface` and `isTracking`, `LiveInk.swift:1845`.
- `strokeEnded` takes the surface weakly, `:2038`.

### LiveInkTap (implicit)

Owner: `LiveInkTap.swift:19`. Tests: none.

A CGEvent tap, created at the start of inking, that swallows mouse down, drag, up and move events and hands them to the overlays. It exists only while inking. Events arrive on a tap thread and move to the main thread through `DispatchQueue.main.async` (`:190`).

**States**: off (no object); on (port and source set); on but disabled by the system. Properties: `link.port` and `source` (nil after `stop`), `onTurnedOff`, static `taken` (`last`, `sessionAtStop`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| off | `start` (`:39`, from `LiveInk.startTap`) | on | tap installed |
| on | mouse event | on | returned nil (swallowed), including a release whose press the tap never saw; handed to main ([hand-2](#hand-2)) |
| on | `.tapDisabledByTimeout` | on | re-enabled on the tap thread, logged (`:179`); a lost mouse-up leaves the stroke tracking ([hand-3](#hand-3)) |
| on | `.tapDisabledByUserInput` | on but disabled | logged; on main `stoppedTaking()` and `onTurnedOff`, which sets `tapTakesPresses=false` on the inking overlays (`LiveInk.swift:1828`) so the overlays take presses. `LiveInk.tap` stays non-nil until `stopTap`. |
| on | `stop()` (`:92`, from `LiveInk.stopTap` or `deinit`) | off | port taken first |

**Invariants**

- Exists only while inking. Checked by: `LiveInk.stopInking` → `stopTap`.
- Process exit removes the tap. Checked by: nothing (measured, `docs/live-ink.md`).

**Late and concurrent answers**

- `stop` takes the port first, so the callback's disabled-event branch does nothing after it, `LiveInkTap.swift:177`.
- A hand-off queued behind `stop`: `handOn` guard `source != nil`, `:194`.
- `info.release()` is queued behind a running callback, `:102`.
- `link.tap` is weak.

### Overlay surfaces (implicit)

Owner: `LiveInk.swift:2030` (`activeSurfaces`), `:2050` (`closeEmpty`); `LiveInkOverlay.swift:63`. Tests: none.

One overlay window per screen per Space holds the strokes and the field. `activeSurfaces` creates them lazily; `closeEmpty` removes those with no marks.

**States**: `surfaces`, `inking`. Per overlay: `takesInk`, `holdsField`, `keptAboveMenus`, `level` (`raise`, `LiveInkOverlay.swift:167`: `.screenSaver` if kept above menus, else the resting level), `ignoresMouseEvents = !inking`, `alphaValue` (0 while `pickerUp`), `notice`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| none for a screen and Space | `activeSurfaces` | created | overlay made |
| surface | `closeEmpty` | closed | removed from `surfaces` at once; the window closes after `fade` and the field's fade-out (`close(after:)`, `LiveInkOverlay.swift:108`) |
| surface | `screensChanged` | refitted | `fit(to:)` (`:90`) |
| surface | its display gone | closed with its marks | `LiveInk.swift:2102` |

**Invariants**

- An overlay is closed, never ordered out. Checked by: nothing.
- A surface closed by `closeEmpty` is never reused, because it leaves `surfaces` first. Checked by: `closeEmpty`.

**Late and concurrent answers**

- Inking again while a surface fades out: `activeSurfaces` looks only at `surfaces`, so a new overlay is made.
- A fading field on a surface that stays is brought back by `holdField(true)` → `comeUp`, which clears `fadeOut` (`PointerField.swift:166`).

### Window picker watch (implicit)

Owner: `LiveInk+WindowPicker.swift:14`. Tests: none.

While a capture may be starting, hides the overlays when macOS's window picker is up so the picker is not covered.

**States**: `pickerWatch: Timer?` (`LiveInk.swift:32`), `pickerWatchUntil` (`:33`), `pickerUp` (`:35`). States: idle, watching, picker up.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| idle | `watchForWindowPicker()` (from `CaptureOrigin.onCaptureKeys`), marks exist | watching | 0.1 s timer `checkWindowPicker` (`:24`) |
| watching | `isCapturing()` true | picker up | surface `alphaValue = 0`, `windows.pickerClear` |
| picker up | `isCapturing()` false | watching | alpha restored |
| watching | not up and past `pickerWatchUntil` | idle | timer stopped |
| watching, picker up | `setOn(false)` | idle | `stopWatchingForWindowPicker` |

**Invariants**

- New overlays and window overlays take their alpha from `pickerUp` and `pickerClear`. Checked by: `LiveInk.swift:2035`, `LiveWindows.swift:249`.
- Overlays at alpha 0 still take ink and the tap still swallows clicks, so a chord held while the picker is up draws invisible ink. Checked by: nothing.

### Menu hand-off: overMenus and LiveMenus (implicit)

Owner: `LiveInk.swift:449` (`place`), `:472` (`pinOverMenus`), `LiveMenus.swift:32` (`close`). Tests: none.

A mark drawn over an open menu cannot belong to the menu's window. It stays on the surface until the menu closes, then moves onto its window.

**States**: `overMenus` (`:465`), `pinsAfterMenus` (`:468`), each overlay's `keptAboveMenus`, `menusWaiting` (`:1953`).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| inking | a mark is drawn over an open menu | mark on the surface | recorded in `overMenus` and `pinsAfterMenus` |
| inking ends | `stopInking(keepingInkAboveMenus: true)` | surfaces kept above menus | level `.screenSaver` |
| menus closed or none | `pinOverMenus` | marks on their windows | one turn, `handOff`; level dropped |

**Invariants**

- No frame shows two copies of a mark. Checked by: `LiveMarksLayer.handOff`, nothing tests it.
- `clear()` empties `overMenus` and the emptied surfaces close, `LiveInk.swift:287`. Checked by: nothing.

**Late and concurrent answers**

- A mark erased or cleared before `pinOverMenus`: filtered by `screenMarks`, `LiveInk.swift:477`.
- Window gone before `pinOverMenus`: the mark stays on the surface (`windows.target(id:)` is nil).
- `LiveMenus.close` makes up to about 41 Accessibility reads per window on the main thread, each with a 0.25 s timeout, `LiveMenus.swift:61` ([hand-13](#hand-13)).

### LiveEscape (explicit) and the Esc hotkey (implicit)

Owner: `LiveEscape.swift:8` (`next`, `:60`), `LiveInk+Escape.swift:23` (`holdEscape`), `LiveInk.swift:1736` (`escapeSnapshot`). Tests: `LiveEscapeTests.testEscBacksOutOneStepAtATimeInOrder`, `testEscIsTheAppsWhileTheNoteIsUpWithoutTheKeys`, `testEscClearsInkAloneAndNothingElse`, `testEscPastTheNoteAndReplysFieldIsTheAppsUnlessThePointerIsOnInk`, `testEscIsNeverTakenWhileTheStackHoldsTheScreenAMenuIsUpOrLiveInkIsOff`.

Esc backs out of live ink one step per press. `LiveEscape.next(Snapshot)` is pure: it returns the step to run, or nil to let the app have the key. `escapeKey: HotKey?` (`LiveInk.swift:105`) is held only while a step exists.

**States**: `Snapshot` (`LiveEscape.swift:29`) in, `Step?` out; and the hotkey, held or not.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| `!isOn`, or the stack holds the screen, or a menu is open, or the note is up without the keys | any | no step | Esc goes to the app |
| note has keys | Esc | step `discardNote` | note discarded |
| Reply field open | Esc | step `closeReplyField` | field closed |
| the pointer is on ink, and an ask is out | Esc | step `cancelAsk` | ask stopped |
| the pointer is on ink, a tour is running | Esc | step `endTour` | tour let go |
| the pointer is on ink, an answer is up | Esc | step `closeAnswer` | answer closed |
| the pointer is on ink, ink exists | Esc | step `clearInk` | ink cleared |
| the pointer is not on ink, none of the first two apply | Esc | no step | Esc goes to the app |

The order in the table is the order of `next`: when two things are open, the earlier step runs first, one per press. A `CFRunLoopObserver` re-evaluates the hotkey before every wait of the main loop (`LiveInk.swift:196`). `escape()` recomputes `next` at press time (`LiveInk+Escape.swift:35`).

**Invariants**

- Esc backs out one step per press, in the order above. Checked by: `LiveEscapeTests.testEscBacksOutOneStepAtATimeInOrder`.
- The hotkey is held exactly while `next(snapshot)` is non-nil. Checked by: nothing; `LiveInk` is not constructible in a test.
- `pointerOnInk` reads `NSEvent.mouseLocation` (`LiveInk+Escape.swift:11`), which stays stale after inking, so the hotkey may not be held and Esc reaches the app ([hand-9](#hand-9)).

**Late and concurrent answers**

- Esc pressed just before the key is held: reaches `escape()` through the note's `onEscape`; `escape()` returns without a log when `next` is nil, `LiveInk+Escape.swift:35`.

### FocusRun, the focus tour (implicit)

Owner: `LiveInk.swift:1371` (`FocusRun`), `pullFocus` `:1389`, `nextFocus` `:1450`, `letGoOfFocus` `:1483`. Tests: `LiveInkTests.testATourHoldsEachStopForItsSentence` covers only `Focus.holds`.

A focus tour dims a window's other marks and shows an answer's stops one at a time. `pullFocus` is called from the answer code, which is covered in the asks area.

**States**: `focusRun: FocusRun?` (`:61`) with `id`, `ask`, `stops`, `holds`, `window`, `index` (-1 until the first stop shows), `timer`, `watch` (event monitors), `origin`. States: none; capturing (`focusRun != nil`, `index == -1`, no monitors); showing(index) (timer and monitors on).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | `pullFocus` | capturing | prior tour let go (`:1398`); no window → `showUnfocused`, none |
| capturing | capture succeeds | showing(0) | stops get the picture; `nextFocus` |
| capturing | capture fails or no picture | none | `showUnfocused` |
| capturing | `focusRun.id` changed | — | ignored, `guard focusRun?.id == run.id` (`:1423`, `:1431`) |
| showing(i) | stop timer | showing(i+1) | previous stop dropped after `Focus.fade * overlap * motionScale` |
| showing(last) | stop timer | none | `letGoOfFocus("read")` |
| showing | key, click, scroll, or pointer beyond `Focus.pointerReach` (120 pt) (`focusHeard`, `:1531`) | none | `letGoOfFocus` |
| capturing | key, click, scroll, pointer | capturing | no monitors yet, so nothing |
| any | Esc `endTour`, `showFieldForChord("ink")`, `removeAnswer`, `setAside`, `endConversation` | none | `letGoOfTour` / `letGoOfFocus` |
| showing | the person draws while a tour is up | showing | not ended: the ink-time `letGoOfFocus` runs only when the field was not already shown, and the tap hides events from the monitors ([hand-4](#hand-4)) |

**Invariants**

- One tour at a time. Checked by: the prior tour let go at `:1398`.
- The stop on screen fades on let-go, and `windows.light` restores the other marks. Checked by: nothing.

**Late and concurrent answers**

- A capture answering after replacement or let-go: run id compare, `LiveInk.swift:1423`, `:1431`.
- The delayed `dropFocus` after the ids left: harmless, it intersects with `asks.answerMarks`, `:1513`.
- `letGoOfFocus` when none: returns at `:1484`.

### Steps tour (implicit)

Owner: `LiveInk.swift:112` (properties), `clicked(at:)` `:1340`, `stopSteps` `:1328`. Tests: none.

An answer with steps is shown one step group at a time; clicking the target of the shown step advances. Set up in the answer code (asks area).

**States**: `stepClicks` nil (none) or non-nil (running: a global `.leftMouseUp` monitor, `watchStepClicks` `:1320`); `steps` holds the groups still to show; `stepsAsk`, `stepsWindow`, `stepsOnTheirWindows`, `stepTargets`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| running | click on the shown step | running, or none after the last | `steps.removeFirst()`, `stopSteps` if empty, then after `stepPause` (0.35 s) remove the done marks and show the next group |
| running | click while inking | running | ignored, `guard !isInking` (`:1341`) |
| running | second click within `stepPause` | running | picks the same step again, pops another group, schedules a second closure ([hand-7](#hand-7)) |
| running | Esc `endTour` within `stepPause` | none | `stopSteps`, but the pending closure still draws the next group ([hand-7](#hand-7)) |

**Invariants**

- A step group that was replaced or removed during the pause does not draw. Checked by: the guard `asks.answer(of: current.id) == id` (`:1356`).

### LiveListening and the transcriber chain (implicit)

Owner: `LiveListening.swift:36`; `LiveInk+Listening.swift:6` (`listen`), `:45` (`doneListening`), `:66` (`stopListening`); `Microphone.swift:16`; `AppleTranscriber.swift:6`. Tests: two, below, cover `ListeningEnd` only.

Captures speech while the chord is held and a short time after, and turns it into the note's words.

**States**: in `LiveInk`: `listening: LiveListening?` (`LiveInk.swift:75`), `typedOver` (`:82`), `spoken` (`:85`), `heardBeforeNote` (`:87`), `speechProblem` (`:77`). In `LiveListening`: `finishing` (`:41`, one-way), `end: ListeningEnd` (`:39`), the 0.1 s timer. `Microphone`: engine, `running`, a shared serial queue. `AppleTranscriber`: `request`, `task`, `latest`, `final`, `waiting`, under one lock. States of a listening: none, starting or listening, finishing (delivered or cancelled).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| none | `listen()`, speech on, permission granted, recognizer present | starting | `LiveListening.start`; `typedOver` set |
| none | `listen()`, speech off | none | `speechProblem = nil` |
| none | `listen()`, no permission or no recognizer | none | `speechProblem` set |
| starting, listening | `pressedAgain()` | same | `end.pressAgain()` |
| listening | first words, chord held, no note or menu | same | note opens by the pointer, no keys (`showNoteOnTheVoice`) |
| starting, listening | `released()` | same | `end.release(at:)`; ends 0.3 s later |
| starting, listening | start fails and `!finishing` | none | `failed` → `LiveInk.listening = nil`, `speechProblem = reason` |
| starting, listening | `finish()` (0.1 s timer says `ListeningEnd.isOver`, or `typedInNote`) | finishing | mic stop queued behind start, `transcriber.finish(timeout: 2)`, then `onFinished` |
| starting, listening | `cancel()` (from `stopListening`) | finishing, cancelled | mic stop, `transcriber.cancel()` |
| finishing | `finish()`, `cancel()` | — | ignored, `guard !finishing` (`:90`, `:107`) |
| finishing | `pressedAgain()`, `released()` | finishing | only edit `end`; no new listening starts because `listen()` returns at `guard listening == nil` (`LiveInk+Listening.swift:7`) ([hand-5](#hand-5)) |
| finishing | transcriber words | — | dropped, `LiveListening.swift:62` |
| finishing (finish) | `onFinished`, `LiveInk.listening === listening` | none | `doneListening`: `listening = nil`; no note → `heardBeforeNote`; note and `!typedOver` → `spoken`, `note.hear`, and `note.send()` when `liveInkSendWhenQuiet` (default true) and the note has ink, which may send while the next stroke is under way ([hand-5](#hand-5)) |
| finishing | `onFinished` after `stopListening` or a new listening | — | dropped by identity, `LiveInk+Listening.swift:25`, `:30` |
| starting | microphone start fails after `finish()` | finishing | the failure is dropped with no `speechProblem` ([hand-11](#hand-11)) |

**Invariants**

- A stop sent while a start is under way turns the mic off after it is on, and one listening's stop finishes before the next one's start. Checked by: the serial queue in `Microphone.swift:16`.
- A listening ends just after the chord is let go, and not if the chord is pressed again. Checked by: `testListeningEndsJustAfterTheChordIsLetGo`, `testPressingTheChordAgainKeepsListening`.
- `LiveListening`, `doneListening`, `heardBeforeNote` and the finishing window. Checked by: nothing.

**Late and concurrent answers**

- Mic start answering after `finish` or `cancel`: `guard !finishing`, `LiveListening.swift:67`.
- Words queued before `finishing` was set: re-checked on main, `:62`.
- `AppleTranscriber.finish` timing out after the real answer: `answer(timedOut:)` no-ops when `waiting` is nil (`AppleTranscriber.swift:117`); the continuation is taken and cleared under the lock.
- A failed `begin()` cancels the transcriber (`Microphone.swift:31`), so a later `finish` returns `latest` at once.
- Heard words with no note: `heardBeforeNote` is reset by the next `listen()` and by `stopListening`.
- Permission is read once, synchronously (`SpeechPermission.granted`, `LiveInk+Listening.swift:11`); no async permission answer reaches live ink.

### LiveWindows Tracked (implicit)

Owner: `LiveWindows.swift:11`; per window `Tracked` (`:40`); `update` `:559`. Tests: `LiveInkTests` covers only `fits` (`testAMarkPastAShrunkWindowsEdgeNoLongerFits`, `testAnArrowFitsByItsHeadNotItsTail`, `testAReplyHangingPastTheWindowStillFits`).

Pins marks to the windows they were drawn on, so marks move, fade and leave with the window. A display link drives it: 10 Hz when idle, display rate while a window is moving.

**States**: per window `frame`, `onScreen`, `showFrom`, `liftedAt`, `minimisingSince`, `pins`, `overlay`. Global: `link`, `monitors`, `observers`, `watchers` (Accessibility, per pid), `activeUntil`, `buttonDown`, `askedForTree`, `pickerClear`. Derived: `isAway = minimisingSince != nil || showFrom != nil`. A pin is drawn when `!isAway && !outside`, and shown when drawn and not aside. Window states: on screen, minimising, away (`!onScreen`, overlay ordered out), landing (`showFrom` set), lifted (`liftedAt` set, level `.floating`), gone.

**Transitions** (`update`, `:559`)

| State | Event | Next state | Effects |
|---|---|---|---|
| on screen | not on screen in the window list | away | `orderOut` |
| away | on screen again | landing | level `.normal`, order above, `minimisingSince = nil`, `showFrom = now + 0.2`, marks faded to 0 |
| landing | `now >= showFrom` | on screen | `showAgain`: fade to opacity (`:317`) |
| on screen | ⌘M or minimise-button release | minimising | `fadeForMinimise` (`:524`) |
| minimising | still on screen 1 s later | landing | `showFrom = now`, marks back |
| any | frame size changed | same | `fitMarks`, `fitOverlay`; pin `outside` toggles |
| any | frame origin changed | same | overlay `move(over:)` |
| any | its app activated | lifted | level `.floating` until its app raises its windows (`keepInPlace`, `:601`) |
| any | id missing from the window list | gone | overlay closed at once, `onGone(ids)` → `LiveInk.forget` |
| any | `pin` of a mark for a moved window before the next tick | same | uses the old `frame`, so the mark is displaced for good ([hand-8](#hand-8)) |
| last window gone | | link stopped | `stop()` |

**Invariants**

- Marks move with the window, fade as it minimises, go when it closes, and hide when the window shrinks past the point. Checked by: `fits` tests only; tracking itself has no test.

**Late and concurrent answers**

- `liftedAt` left set when the window goes away: heals on the next `keepInPlace` (`now - lifted > 0.5`).
- Asking for a page tree: deduped by pid, retried when it could not tell, `LiveWindows.swift:134`.
- The minimise-button Accessibility probe re-looks the window up on main, `:524`.
- A re-pin to a retired window id makes a fresh `Tracked` and overlay, `retire` `:204`, `tracked` `:344`.

### LiveInk.setOn and the chord object (implicit)

Owner: `LiveInk.swift:206`. Tests: none.

Turns live ink on and off. `isOn` is `chord != nil`.

**States**: `chord: ModifierChord?`, `observers` (screen, Space, sleep, session).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| off | `setOn(true)` | on | chord and observers made |
| on | `setOn(false)` | off | `stopInking` if inking, window picker watch stopped, `endConversation`, marks and surfaces dropped, `windows.removeAll` |
| on or off | `setOn` with the same value | — | `guard on != isOn` |
| on | `takeChord()` (`:248`) | on | the chord object replaced; inking cut short |

**Invariants**

- Off does not clear `menusWaiting`, `listing`, `lastTarget`, `typedOver`, `fieldTimer` (invalidated only by `stopInking`, which runs only while inking) or `releaseWatch`. Checked by: nothing.

## Live ink: asks and responders

An ask is one question a person puts to an agent about their live ink: the ink, an optional note and a picture of the screen. This area covers the reducer that tracks every ask, the glue that runs it, the per-agent responders that talk to Claude Code and Codex, and the note cards that wait for a session's reply.

### LiveAsks (explicit)

Owner: `LiveAsks.swift:13`, a value held as `LiveInk.asks` (`LiveInk.swift:146`) and driven only by `reduce` (`LiveAsks.swift:362`). Tests: `LiveAsksTests.testRandomSequencesKeepTheInvariants`, `testAReplyAndAnAnswerFromADismissedAskAreDropped`, `testAPacketFromAClearedAskIsDroppedAndTheNextAskTakesItsOwn`, `testEscStopsTheNewestAskFirstAndTheResponderOnlyForTheOneItHas`, `testStoppingASessionAskWithdrawsItsNoteIfItIsStoredAfterAll`, `testStoppingASessionAskBeforeItsPacketSendsNothing`, `testAnErasedMarkLosesItsRolesAndItsFinish`, `testAnOverlappingFinishIsEndedByTheFirstTimer`, `testAFinishAfterAClearDoesNothing`.

Tracks every ask from the moment ink is sent until its answer is closed. `LiveInk` sends it events and runs the effects it returns. An ask goes either to a responder (an agent process Vignette runs) or, for a `toSession` ask, to a session through Send.

**States**: each ask has `Ask.Phase` (`LiveAsks.swift:17`):
- `looking`: the packet (ink, note, picture) is being taken.
- `waiting`: has its packet, queued behind an earlier responder ask.
- `asking`: with the responder, or pending in it.
- `answered`, `failed`: settled. They stay until closed. `isUnderWay` (line 54) is the first three.

Per ask also: `toSession` (never waits and is never sent to the responder; its phase stays `looking` from `begin` until `sentToSession`, `failed`, `cancelled` or `cleared`), `fresh`, `about`, `say`, `leader`, `actions`, `picked`, `draft`, `findings`, `reason`, `picture`.
Per mark (`Record`, line 77): `roles` (`asked`, `noteInk`), `answer: Ask.ID?`, `finishing`. A record with no roles is deleted.
Side tables: `picks[askID]` (the answer a picked button was picked under, plus `aside`), `withdrawn` (session asks Esc stopped before their send was stored), `lastID` (never reset, so ids are never reused, not even after `cleared`).

**Events** (`Event`, line 257) and senders:
- `begin` (218): `LiveInk.ask` (`LiveInk.swift:794`).
- `drew`: `LiveInk.stroked` (431). `noteDiscarded`: `discardNote` (724).
- `removed`: `LiveInk.remove` (547: tap-erase, pick, `removeAnswer`, `dropFocus`, step advance, `finished`). `windowGone`: `forget` (560).
- `arrived(.packetCame)`: `send` (876), `share` (903). `.replyCame`: `showSay` (1246). `.answerCame`: `answered` (1269). `.failed`: `failed` (1546). `.sentToSession`: the `sendNote` completion (939).
- `pictureSent`: the responder's `content` closure (865). `conversed`: `ask` (811), `say` (1214). `streamed`: `showSay` (1258). `answered`: `answered` (1288). `drafted`: the actions panel (1158). `replyRedrawn`: `restoreAnswer` (1595), `notice` (1608). `answerShown`: `clicked` (1359), focus code.
- `dismissed`: the × (1124). `cancelled`: `cancelAsk` (`LiveInk+Escape.swift:57`). `answerClosed`: Esc (`LiveInk+Escape.swift:44`). `finished`: the finish timer (974). `cleared`: `endConversation` (1728).

**Transitions**

`reduce` always appends `sendNext` (line 364). Anything not listed is ignored with no effects.

| State | Event | Next state | Effects |
|---|---|---|---|
| (new) | `begin` | `looking` | `ended(...)` for a follow-up's replaced answer (`began`); `refused(.noInk)` with `restore` when following |
| `looking`, responder ask | `packetCame` | `waiting` | `sendNext` may then make it `asking` with `send(id)` |
| `looking`, session ask | `packetCame` | `looking` | `share(about)` |
| `waiting`, `asking`, `answered`, `failed`, ended | `packetCame` | — (ignored, line 403) | — |
| `asking` | `replyCame` | `asking` | optional `setAside`, then `showReply` |
| `asking` | `answerCame` | `asking` until LiveInk sends `answered` | optional `removeAnswer`, then `drawAnswer` |
| any present ask | `answered` | `answered`, `picked = nil` | no phase check (line 428); LiveInk sends it only right after a taken `answerCame` |
| under way, follow-up | `failed` | `answered` (old answer put back) | `restore` |
| under way, not a follow-up | `failed` | `failed` | `removeAnswer`, `notice` or `say` |
| session `looking` | `sentToSession` | ended | `finish(about ∪ ink − otherAsks ∪ answer, .dismissed)` |
| any present ask | `dismissed` | ended | `interrupt` only if `asking`; `finish(answer ∪ about − others ∪ aside)` |
| under way | `cancelled` | ended, or restored | `interrupt` only if `asking`; `removeAnswer`; `reopenNote` if ink is given back; session ask: id into `withdrawn` |
| settled | `cancelled`, `failed`, `replyCame`, `answerCame`, `packetCame` | — (ignored) | — |
| newest settled ask with a non-leaving answer mark | `answerClosed` | ended | `finish(answer, .dismissed)` |
| any | `removed`, `windowGone`, `finished` | marks lose roles; settled asks with no answer mark left end (`endAnswersWithNoMarks`, 514); asks under way stay | — |
| any | `cleared` | every ask ended | `ended(id)` for each; `picks` emptied; roles, answers, finishing dropped; `withdrawn` and `lastID` kept; no `interrupt` |

**Invariants**

- Each ask that leaves the list says `ended` first, oldest first. Checked by: `testRandomSequencesKeepTheInvariants` (`LiveAsksTests:1018`).
- Asks go to the responder one at a time, in order, each only when `waiting`. Checked by: the same test.
- What comes back for an ask no longer under way changes nothing. Checked by: the same test, `testAReplyAndAnAnswerFromADismissedAskAreDropped`, `testAPacketFromAClearedAskIsDroppedAndTheNextAskTakesItsOwn`.
- `interrupt` is emitted only for the ask the responder has. Checked by: the same test, `testEscStopsTheNewestAskFirstAndTheResponderOnlyForTheOneItHas`.
- A session ask Esc stopped has its first arrival swallowed and a stored note withdrawn. Checked by: `testStoppingASessionAskWithdrawsItsNoteIfItIsStoredAfterAll`, `testStoppingASessionAskBeforeItsPacketSendsNothing`.
- An erased mark loses its roles and its finish; asks under way are unchanged. Checked by: `testAnErasedMarkLosesItsRolesAndItsFinish`.
- Overlapping finish timers: the first ends the marks. Checked by: `testAnOverlappingFinishIsEndedByTheFirstTimer`, `testAFinishAfterAClearDoesNothing`.
- Ids strictly increase. Checked by: `testRandomSequencesKeepTheInvariants`.
- Every ask ends by answer, failure, stop or clear. Checked by: `LiveResponderTests.testAnAskUnderWayWhenTheSignInGoesFailsOnce` for the sign-out (**fixed**, [asks-1](#asks-1)). The test model drops a responder-held ask only on `clear` (`LiveAsksTests:1817`), so it assumes the responder drops one no other way.
- Erasing the reply mark of an ask under way: the ask keeps `say`, and the next `replyCame` draws it again. Checked by: nothing ([asks-6](#asks-6)).

**Late and concurrent answers**

- A packet, reply, answer or failure after the ask ended, was dismissed, stopped or cleared: dropped, guard at `LiveAsks.swift:399` (`isUnderWay`), phase guards at 403, 407, 410.
- A late arrival for a stopped session ask: swallowed by `withdrawn.remove(id)` (395). If its send is stored later, the reducer emits `.withdraw` (396) and `LiveInk.swift:940-943` withdraws the note.
- Two follow-up picks on one answer: the answered ask leaves `asks` at `begin` (237), so the second `respond` fails its `asks.ask(id)` (`LiveInk.swift:1189`).
- A stale `finished` timer: `guard ids.contains(where: finishing != nil)` (475).
- A draft for a reply the panel was not made for: the `.drafted` guard (440).
- A failed follow-up puts the old answer back only while its reply is among `shown` (563).

### LiveInk ask glue (implicit)

Owner: `LiveInk.swift:574-1366`; effects run in `run` (1557). Tests: none (`LiveInk` is not instantiated in unit tests).

Runs the effects `LiveAsks` returns and keeps per-ask tables that must agree with `asks.asks`.

**States**: `LiveAsks` plus these tables:
- `held[id]` (`LiveInk.swift:101`): what to send the responder. Set in `send` (861), consumed in `sendHeld` (883), cleared in `release` (1581).
- `answerers[id]` (97): agent and display name. Set at `began` (802), cleared in `release` (1582).
- `handing[id]` (note panel waiting to hand over) and `handingTo[id]` (the conversation mark it will become): set at 805 and 747, cleared by `letGoOfNote` (737; from `release`, `failed`, `share`) or the handover closure (750).
- `dismissButton`, `dismissing` (79): the × for one ask. Cleared in `release` (1584) and `hideDismissButton`.
- `actionsPanels[id]` (84): buttons per answered ask. Made in `showActions` (1161), removed by `hideActions` (1165; also from `release`, `removeAnswer`, `setAside`, `restoreAnswer`).
- Step tour (an answer that points at targets one step at a time): `steps`, `stepsAsk`, `stepsWindow`, `stepsOnTheirWindows`, `stepTargets`, `stepClicks` (`LiveInk.swift:149-155`), `stopSteps` (1328), `clicked` (1340), and the delayed advance closure (1354, `stepPause` 1366).
- `prepared` (118): a prefetched packet for the note's ink. Set in `prefetch` (1011), used and cleared in `ask` (820, 824), cancelled in `endConversation` (1730) and by the next `prefetch` (996).
- The Task started in `ask` (826) builds the packet and calls `send`, `share` or `failed`. It is never cancelled when the ask ends; every use re-checks the reducer.

**Transitions** (effects of `run`)

| State | Event | Next state | Effects |
|---|---|---|---|
| any | effect `ended(id)` | tables for `id` cleared | `release`: `held`, `answerers`, note fade, ×, tour, buttons |
| `waiting` | effect `send(id)` | `asking` | `sendHeld` calls `responders.ask`; a failure calls `failed` |
| `asking` | effect `interrupt` | — | `responders.cancel()` (all agents) |
| marks settled | effect `finish(ids)` | — | `finish` (969): `showMarks`, then `asyncAfter(finishDuration)` sends `.finished` |
| step answer showing | click on the step's target | next step after 0.35 s | closure at 1354 removes the done marks and draws the next step. A second click inside the pause skips a step, and Esc or × inside it still draws the next step ([asks-2](#asks-2)) |

**Invariants**

- Every ask that leaves the list releases `held`, `answerers`, `handing`, `handingTo`, ×, buttons and its tour (`release`, 1580-1587). Checked by: reducer-level `ended` ordering only.
- After `.send(id)`, `held[id]` and `answerers[id]` exist (comment at 881). A miss would leave the ask `asking` forever. Checked by: nothing.
- `sendNote` is always set in the app (`AppDelegate.swift:133`); `share` returns without ending the ask if it were nil (`LiveInk.swift:905`). Unreachable now.
- The step advance closure only runs for a tour still held. Checked by: nothing ([asks-2](#asks-2)).

**Late and concurrent answers**

- A packet for an ask no longer `looking`: `send` guard (854); `share` takes `.share` only if the reducer still has the ask (903-904).
- A reply or answer after dismissal: every callback starts with `guard answerers[id]` (`showSay` 1245, `answered` 1268, `say` 1205, `sendHeld` 883), then the reducer's guard.
- The handover closure after the ask ended or failed: `handingTo[id] == reply.id` and `asks.ask(id)?.say` checks (749-754).
- A second click on ×: the second `.dismissed(id)` finds no ask (449).
- `respond` after the answer was replaced: `asks.ask(id)` is nil (1189).
- Clear: `endConversation` (1722) runs `letGoOfTour`, `.cleared`, `responders.stop()`, and cancels `prepared`.

### LiveResponder (implicit)

Owner: `LiveResponder.swift:14`, one per agent. Tests: none.

Runs one agent process and sends it one ask at a time. `LiveResponders` owns one per agent; `LiveInk` reaches it through `sendHeld`.

**States**: these properties together form the state.
- `state` (`State`, `LiveResponder.swift:15`): `stopped`, `starting`, `ready`, `asking`, `failed(reason)`.
- `current` (ask sent, line 99), `pending` (ask not yet sent, 105), `interrupting` (turn of a cancelled ask not yet ended, 102), `restartDue` (107), `starts` (counter, 93), `held` (isolation refusal for one binary, 98), `askTimer`, `idleTimer`, `conversation`, `answered`, `lastSay`.

Valid combinations: `asking` implies `current != nil` or `interrupting`; `current != nil` implies `asking`; `pending != nil` implies not `stopped` once `ask` returns; `interrupting` implies the process is running.

**Events** and senders:
- `ask(Ask)`: `LiveResponders.ask` (75) from `LiveInk.sendHeld`. `prepare()`: `LiveResponders.prepare` at note open (`LiveInk.swift:1889-1908`).
- `cancel()`: `LiveResponders.cancel` from `LiveAsks.Effect.interrupt`.
- `stop()`: `LiveResponders.stop` from `endConversation`, app quit (`LiveResponders.swift:29`), and for Codex `ResponderStatus.onCodexSigningOut` (`LiveResponders.swift:26`).
- `restart(whenIdle:)`: `ResponderStatus.changed(signedIn:)` through `onCodexSignIn` (`LiveResponders.swift:25`).
- Driver `ResponderEvent`s through `handle` (287): `ready`, `startFailed`, `refused`, `output`, `answerSoFar`, `answered`, `turnFailed`, `firstTurnFailed`, `ended`.
- Timers: `askTimer` (45 s for an ask, 3 s for an interrupt; `armTimer` 266), `idleTimer` (4.5 min; `renewIdle` 254). A binary-lookup `Task` in `start` (191).

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| idle, `answered >= 12` | `ask(A)` | `stopped` | `stop()` first (a new conversation), then `pending = A` |
| any | `ask(A)` | `failed` becomes `stopped` | `pending = A` (overwrites a pending ask without telling it), `prepare`, `sendNext` |
| not running, not `failed` | `prepare` | `starting` | timers, binary `Task`; running: `restartIfIdle` |
| `starting` | binary found | — | `launch`: not found or refused: `refuse`, `failed`, `pending` and `current` get `onAnswer(.failure)`; else `driver.start`, `conversation += 1` |
| `starting` | `ready` | `ready` | `restartIfIdle`, `sendNext` (`pending` becomes `current`, state `asking`, `driver.send`, `armTimer`) |
| other | `ready` | — (ignored) | — |
| `asking` | `answerSoFar` | — | `current.onSay` if not interrupting and the text changed |
| `asking` | `answered`, `turnFailed` | `ready` | `turnEnded`: an interrupted turn is swallowed (`interrupting = false`); else `current = nil`, `onAnswer`; then `restartIfIdle`, `sendNext` |
| any | `firstTurnFailed` | `failed` | `current` failed, then `startFailed` (also fails `pending`) |
| any | `startFailed`, `refused`, `ended` | `failed` | `shutDown(failure, .failed)`: `current` and `pending` get `onAnswer(.failure)` |
| `asking` | `cancel()` | stays `asking` | `pending = nil`; if `current`: `current = nil`, `interrupting = true`, `driver.interrupt()`, 3 s timer. No answer, no failure |
| any | `askTimer` 45 s | `stopped` | `shutDown(timeout, .stopped)`: `current` and `pending` failed |
| `interrupting` | `askTimer` 3 s | — | `interruptUnanswered`: `stop()`, then `ask(pending)` again |
| any | `idleTimer` | `stopped` | `stop()` only if no `current` or `pending` |
| any | `stop()` | `stopped` | `shutDown(nil, …)`: `current` and `pending` dropped with no answer and no failure |
| any | `stop(failingAsks: true)` | `stopped` | `current` and `pending` each fail with the driver's `couldNotAnswer` (**fixed**, [asks-1](#asks-1)) |
| any | `restart(whenIdle:)` | — | sets `restartDue`; acts when `current == nil`, not `interrupting`, not `starting`: `shutDown(nil, .stopped)` then `ask(pending)` |

**Invariants**

- One ask at a time (`LiveResponder.swift:7`). Holds only because `LiveAsks.sendNext` sends one; `ask` itself overwrites `pending`. Checked by: nothing here; `LiveAsks` random test covers the sender.
- A `stop()` gives the ask under way or pending no answer and no failure. That is right for `endConversation`, which clears `LiveAsks` first, and for the idle stop and the conversation limit, which hold no ask. The sign-out, which tells `LiveAsks` nothing, stops with `failingAsks` (**fixed**, [asks-1](#asks-1)). Checked by: `LiveResponderTests.testAnAskUnderWayWhenTheSignInGoesFailsOnce`.
- A command found after a stop starts nothing. Checked by: the guard `start == starts, running` (200).
- A driver reports nothing after its own stop. Checked by: `ClaudeDriver.stop` setting `report = nil`; `JSONLinesProcess.stop` clearing `relay.onLine` and `relay.onEnd` (76-77); `CodexDriver.stop` dropping `run`, whose callbacks are weak.

**Late and concurrent answers**

- Cancel while the ask is still pending (warm-up): `pending = nil`, `guard current != nil` (172-173).
- Cancel, then the next ask: it waits in `pending` until the interrupted turn ends (`sendNext` needs `state == .ready`), or 3 s pass and a new process starts (280).
- The interrupted turn's own answer or failure is swallowed (346-351); its stream is ignored (`guard !interrupting`, 303).
- Stop during binary lookup: the `starts` check (200). Restart during start or interrupt waits: `restartIfIdle` guard (152).
- Late events from a killed process: relay cleared (`JSONLinesProcess.swift:75-80`).
- Codex asked to interrupt before the turn id is known: `interruptOnStart` (`CodexDriver.swift:128, 178-183, 317-320`).
- Timeout and interrupt share `askTimer`; each arm replaces the last (267).

### LiveResponders (implicit)

Owner: `LiveResponders.swift:9`. Tests: none.

Owns one `LiveResponder` per agent and remembers what picture each has been sent.

**States**: `all[client]`; `conversing` (set at each `ask`, 83; reset by `stop`); `pictures[client]` = (conversation number, subject, text signature, line ids sent). `content(of:)` (110) records the picture as sent when the ask is written (`LiveResponder.sendNext` calls `ask.content`). Hooks: `status.onCodexSignIn`, `status.onCodexSigningOut`, `willTerminate`.

**Invariants**

- A follow-up about the same window and text sends no picture, and the answer may name only lines already sent (`linesSent`, 126). Holds because `pictures` is keyed by the responder's `conversation` number, which changes with every new process. Checked by: nothing.
- `cancel()` goes to every agent. Safe because only one ask is ever with a responder. Checked by: nothing.

### ClaudeDriver (implicit)

Owner: `ClaudeDriver.swift:8`. Tests: none.

Speaks Claude Code's streaming JSON through a `JSONLinesProcess`.

**States**: `process`, `report`, `warmingUp`, `sawInit`, `partial`. The warm-up result moves it to `ready`; the first output and deltas append to `partial`; a `result` line gives `answered` or `turnFailed`. `interrupt()` writes a control request; its end is a `result` line. `send` resets `partial`.

**Invariants**

- `sawInit` (tools list empty) must be true before `ready`, else `refused(.onceBinaryChanges)`. Checked by: nothing.

### JSONLinesProcess (implicit)

Owner: `JSONLinesProcess.swift:6`. Tests: none.

A child process read and written as lines. Lines hop to the main thread with `DispatchQueue.main.async` and check `relay.onLine` there. `stop()` nils both callbacks, terminates, and closes stdin on the writer queue.

**Late and concurrent answers**

- A write to a dead process: SIGPIPE is disabled, the error is logged and `onEnd` reports, `JSONLinesProcess.swift:44, 82`.
- A line in flight when `stop()` runs: dropped because `relay.onLine` is nil (75-80).

### CodexDriver and CodexRun (explicit phase inside an implicit machine)

Owner: `CodexDriver.swift:16`; the run is `CodexRun` at `CodexDriver.swift:108`, with `Phase` at line 111. Tests: none.

Runs a Codex thread through a local provider and `AppServerSession`.

**States**: `Phase`: `starting`, `checking(thread, model)`, `warming(thread)`, `ready(thread)`. Other state: `turn` (id from `turn/started`), `interruptOnStart`, `firstTurn`, `partial`, `usage`, `lastError`, `check` (local provider), `session`, `catalogClaim`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| `starting` | `launch` (main hop after provider port and catalog), `initialized`, `listed`, `thread/start` reply | `checking` | — |
| `checking` | `checked` reads the provider's recorded request bodies; any refusal | stops | `.refused(.onceBinaryChanges)` |
| `checking`, no ask waiting | `checked` clean | `warming` (a second thread) | warm-up turn |
| `checking`, ask waiting (`askWaiting()`) | `checked` clean | `ready` | warm-up skipped, `firstTurn = true`, `report(.ready)`; a failed first turn fails the start (`firstTurnFailed`) |
| `warming` | `turn/completed` | `ready` | `report(.ready)` |
| `ready` | `turn/started`, deltas, `turn/completed` on the ask thread | `ready` | `answerSoFar`, `answered` or `turnFailed` |
| any | `ended` | — | reported to the responder |

**Invariants**

- Only the ask thread's `turn/completed` completes asks (`notified`, `case .ready(let thread) where onThread == thread`, `CodexDriver.swift:338`). Checked by: nothing.
- `send` does nothing unless `phase == .ready` (`guard case .ready`, 161). `LiveResponder` only sends after `.ready`. Checked by: nothing.

**Late and concurrent answers**

- After stop: `run` is dropped; every callback is weak (`WeakRun`, `[weak self]`).
- A stopped start's catalog write: `CatalogClaim` withdraws it under one lock (`CodexIsolation.swift:62-80`).
- The provider's `ready` fires once: `Once` (`CodexDriver.swift:245-256`).

### ResponderStatus (implicit)

Owner: `ResponderStatus.swift:7`. Tests: none.

Tells Settings, Setup and note waits which agents can answer, and runs Codex sign-in and sign-out.

**States**: `availability[client]` (`checking`, `ready`, `notInstalled`, `signedOut`); `signIn` (`idle`, `waiting`, `signingOut`, `failed(reason)`); `login`; `claudeAsked`, `claudeAsking`.

**Events**: `check` (off-thread read, then a main-thread write, lines 79-84; sent when live ink turns on, when a note opens, when Settings appears or becomes key, and by Setup's 0.5 s poll, `SetupWindow.swift:427,453`), `startSignIn`, `cancelSignIn`, `signOut`, the login outcome.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| `login == nil` | `startSignIn` | `waiting` | starts `CodexLogin`; with `login != nil` it does nothing |
| `waiting` | signed in | `idle` | `availability[.codex] = .ready`, `onCodexSignIn(true)` calls the responder's `restart(whenIdle:)` |
| `waiting` | cancelled | `idle` | — |
| `waiting` | failed | `failed(reason)` | — |
| any | `signOut` | `signingOut` | `onCodexSigningOut()` calls `LiveResponder.stop(failingAsks: true)` at once (**fixed**, [asks-1](#asks-1)); logout runs off-thread (up to 15 s) |
| `signingOut` | logout done | `idle` | `availability = .signedOut`, `onCodexSignIn(false)` |
| any | `check` result lands | — | `availability[client] = found`, unconditionally (line 84). A check that read before a sign-in or sign-out can overwrite its result ([asks-5](#asks-5)) |

**Invariants**

- Only one login at a time. Checked by: the `login == nil` guard.
- A check result is not ordered against a sign-in result. Checked by: nothing ([asks-5](#asks-5)).

### CodexLogin (implicit)

Owner: `CodexSignIn.swift:45`. Tests: none.

One Codex sign-in or sign-out process. **States**: `done` (completion, once), `session`, `loginID`, `limit` timer (15 s to start, 10 min for the sign-in).

**Invariants**

- `finish` is the one exit. It clears `done` first, so cancel, completion, process end and the timer cannot report twice. Checked by: the `guard let done` at `CodexSignIn.swift:156`.

**Late and concurrent answers**

- A notification for a login id that is not the current one: ignored by `notified` (172).
- Port 1455 taken: refused before starting (90).

### LiveNoteCards (implicit)

Owner: `LiveNoteCards.swift:7`. Tests: none (the pure parts are tested under `NoteCardWait`).

Glue between `ScreenshotRequests` and `NoteCardGroups`. After a person sends a live-ink note to a session, it watches the session's turn, then draws the result: a look at the window again, a result card, "Done", or the session's own reply.

**States**: `notes[request]` (`Note`: shot, destination, title, window, ink, `before`, `resultCard`), `waits` (`NoteCardGroups`), `timer` (0.5 s; started on `.watchTurn`, stops itself when nothing is watched, line 257), `readingTurns` (one read in flight), `hold` (`EventHold<Input>`, 48).

**Events**: `Input` (line 22): `.event(NoteCardGroups.Input)`, `.looked(...)`, `.answer(record, answer, done)`. Callbacks from `ScreenshotRequests` (wired at `AppDelegate.swift:1293-1325`): `released` (only for a send that had a grace), `cancelled` (Don't send, or the request cleared while held), `delivered` (once the client answered), `presentLive` (a reply with a `LiveAnswer`; replies import one at a time and `done` must be called once or the import queue stalls).

`EventHold.send` (`AnnotationRun.swift:282`) appends the input; if one is being handled it returns, else it drains in order. An event sent from inside a handler runs after the current one finishes. Direct calls (`released`, `cancelled`, `delivered`, `unsend`) first read or mutate `notes`, then queue.

**Transitions**: `handle` (171) maps the input, runs the actions, drops notes whose wait is gone (186) and clears `before` for notes no longer watching or looking again (187-190).

**Invariants**

- `done` of `.answer` is called exactly once on every path (`handle` 177, `runNote` 241-250, `drawFresh`, `drawOnResultCard`). Checked by: nothing.
- A note whose `.sent` is still in `hold` is not registered: `delivered` reads `waits[request]?.delivered` before the queued events (153-160), and `handle`'s prune ignores unregistered notes (`registered`, 182). Checked by: the guards.
- A window capture held in `Note.resultCard` is released when the note is pruned, but pruning runs only at the end of `handle`, so after the last note it can stay in memory ([asks-3](#asks-3)). Checked by: nothing.
- A reply that arrives while the result card is being written goes on the sent picture, not the result card ([asks-4](#asks-4)). Checked by: nothing.

**Late and concurrent answers**

- `.answer` for a note that is not registered or is gone: `done(nil)` (177).
- A result card for a group whose lead note is gone: `guard … let lead = notes[ids[0]]` returns (199).
- Overlapping turn-read ticks: `readingTurns` (262).

### NoteCardWait (explicit)

Owner: `LiveNoteCardWait.swift:5`, with `Phase` at line 6. Tests: `NoteCardWaitTests.testAnyOrderOfEventsEndsTheWaitOnce` (166), `testAHeldNoteWatchesNoTurnUntilItsLineIsReleased`, `testACancelledHeldNoteIsNeverWaitedFor`, `testANoteIsForgottenOnlyOnceDeliveredAndOver`, `testAFailedDeliveryEndsTheWaitSilently`, and the tests at `NoteCardWaitTests:275-535`.

The wait of one sent note. It decides when the note's turn is over and what to draw.

**States**: `Phase`: `unsent` (initial, never stored), `watching(TurnWatch)`, `unwatched(sent)`, `lookingAgain`, `resultCard(made)`, `over`. Flag `delivered`.

**Events**: `sent`, `delivered(failed)`, `turn(turn, replied)`, `lookedAgain(outcome)`, `cardFailed`, `answer`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| `unsent` | `sent`, route reports turns | `watching` | `watchTurn` |
| `unsent` | `sent`, route does not | `unwatched` | `stopWaiting` |
| `watching` | `turn` `.stillWaiting` | — | — |
| `watching` | `turn` `.ended`, no before-picture | `over` | `turnEnded`, and `replyIsTheResult` or `sayDone` |
| `watching` | `turn` `.ended`, with before-picture | `lookingAgain` | `turnEnded`, `lookAgain` |
| `watching` | `turn` `.stoppedWaiting` | `over` | `stopWaiting` (+ `replyIsTheResult` if replied) |
| `lookingAgain` | `lookedAgain` replied | `over` | reply |
| `lookingAgain` | `lookedAgain` `cardMade` | `resultCard` | — |
| `lookingAgain` | `lookedAgain` `noCard` | `over` | `sayDone` |
| `resultCard` | `cardFailed` | `over` | `sayDone` |
| `watching`, `unwatched`, `lookingAgain`, `resultCard` | `delivered(failed: true)` | `over` | none (silent) |
| any | `delivered` | `delivered = true` | — |
| `over` | `delivered(failed)` | — (ignored) | — |
| `watching`, with window | `answer` | `watching` | `drawReplyOnFreshCapture` |
| `watching` without window, `lookingAgain`, `over` | `answer` | unchanged | `drawReplyOnSentPicture` |
| `resultCard`, within 30 min | `answer` | `resultCard` | `drawReplyOnResultCard` |
| `resultCard`, later | `answer` | `over` | `drawReplyOnSentPicture` |
| `unwatched`, within 3 min | `answer` | `unwatched` | fresh capture if there is a window, else sent picture |
| `unwatched`, later | `answer` | `over` | `drawReplyOnSentPicture` |

`isFinished(at:)` (89) needs `delivered`. `over` is finished at once, `unwatched` after 3 min, `resultCard` after 30 min. `lookingAgain` is never finished.

**Invariants**

- A note ends once, with a card, Done or the reply, after one look. Checked by: `testAnyOrderOfEventsEndsTheWaitOnce` (single wait only).
- A held note watches no turn until released, and a cancelled held note is never waited for. Checked by: `testAHeldNoteWatchesNoTurnUntilItsLineIsReleased`, `testACancelledHeldNoteIsNeverWaitedFor`.
- One look and one card per turn end; notes sent minutes apart end together; a reply is its own result. Checked by: the tests at `NoteCardWaitTests:275-535`.
- `drawReplyOnResultCard` only after a card exists. Checked by: the random test, which asserts `madeCard` equals phase `resultCard`. That is weaker than the need (the card file exists), see [asks-4](#asks-4).
- Nothing bounds `lookingAgain` in time. Checked by: nothing.

**Late and concurrent answers**

- Delivery before or after the end, in either order: `testANoteIsForgottenOnlyOnceDeliveredAndOver` and the random test.

### TurnWatch (implicit)

Owner: `LiveNoteCardWait.swift:180`, `read` at line 208. Tests: `LiveInkTests.testATurnSeenToStartEndsOnceItHasBeenIdleTwoSeconds`, `testABusyMomentBetweenTurnsStartsTheIdleSpellOver`.

Decides from readings of a session (`waiting`, `busy`, `idle`, or nil when it cannot tell) whether its turn has ended.

**States**: `seenBusy`, `idleSince`, `since`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| any | reading `waiting` | `seenBusy`, `idleSince`, `since` reset | `.stillWaiting` |
| any | reading `busy` | `seenBusy = true`, `idleSince` cleared | `.stillWaiting` |
| `seenBusy` | reading `idle` | `idleSince ?? now` | `.ended` after 2 s idle |
| any | reading nil | no change (falls to the limits case) | after 3 min with no turn seen, or 30 min busy or waiting: `.stoppedWaiting` |

**Invariants**

- A nil reading does not reset an idle spell, so `idle, nil, idle` can end the turn without 2 s of continuous idle ([asks-7](#asks-7)). Checked by: nothing.

### NoteCardGroups (explicit)

Owner: `LiveNoteCardGroups.swift:7`. Tests: `NoteCardWaitTests` (as above), `testANoteWhoseSendFailedDuringTheLookIsLeftOut`.

Holds the waits of all sent notes and decides which note makes the result card when several end together.

**States**: `held[request]` (in its grace, not yet a wait), `entries[request]` (a `NoteCardWait` plus session, window and sequence).

**Events** (`Input`): `sent`, `held`, `released`, `cancelled`, `delivered`, `turns`, `looked`, `cardFailed`, `answer`. Each is routed to the entry's `NoteCardWait`. `looked` resolves one maker (the first changed, unreplied, compared member), one `makeResultCard`, and a `sayDone` for each other note made quiet except the newest (`sayingDoneOnce`, 155). Finished entries are pruned at the end of every `handle` (149).

**Invariants**

- A held note is not in `entries`, so `.turns` skips it (111). Checked by: `testAHeldNoteWatchesNoTurnUntilItsLineIsReleased`.
- Entries are pruned only when an input arrives, so a finished `resultCard` can outlive its 30 min until then ([asks-3](#asks-3)). Checked by: nothing.

**Late and concurrent answers**

- A line released twice: `held.removeValue` (91).
- A reading for a note that ended since the tick started: `guard … entry.wait.isWatching` (111).
- A `lookedAgain` for a note whose send failed during the look: the `looking` filter on `isLookingAgain` (127), `testANoteWhoseSendFailedDuringTheLookIsLeftOut`.

### RolloutTurns and CodexTurns (implicit)

Owner: `CodexRollout.swift:16` (`RolloutTurns`) and `CodexRollout.swift:101` (`CodexTurns`). Tests: `CodexRolloutTests` (not mapped in detail).

Reads a Codex session's rollout file to say whether the session is waiting, busy or idle, for `TurnWatch`.

**States**: per thread `Watch`: `turns` (`RolloutTurns`: `pending` lines, `openTurn`, `openTurnHeard`, `owesBusy`, `unreadable`), `path`, `offset`, `partial`, `grew`, `asked`, `askAfter`, `loaded`, `quietTurn`.

**Events**: `sending(line)`, `unsent(line)`, `turn(of:)` (every 0.5 s tick, off the main thread), rollout lines. `reading()` gives `waiting` (a line not yet seen), `busy`, `idle`, or nil when unreadable. Unreadable stays nil until restart, so `.idle` never comes after it.

### LiveNotePopover (implicit)

Owner: `LiveNotePopover.swift:26`. Tests: none.

The note panel a person types into. Created at `showNote` (`LiveInk.swift:616`).

**States**: flags `revealed`, `sent`, `closing`, `handingOver`, `standsAside`, `menuOpen`, `opened`, plus `inkOpacity`, `target`, `handPick`, `candidates`.

**Transitions**

| State | Event | Next state | Effects |
|---|---|---|---|
| created | `reveal` | `revealed` | fade in |
| `revealed` | `send` (Return) with words | `sent` | letter fades, keys returned |
| `revealed` | `send` with empty words | `closing` | `dismiss` |
| `revealed` | `send` with words, no ink (`mayAsk`) | `revealed` | beep |
| `sent` | `handOver(when:)` | `closing`, `handingOver` | delayed `ready`, then close |
| `handingOver` | `fadeAway` | `closing`, `handingOver = false` | closes; the delayed `ready` does not run (392, `guard handingOver` at 380) |
| any | `dismiss` | `closing` | closes |
| `closing` or `sent` | `put`, `takeKeys`, `send`, `hang`, `follow`, `standAside` | — (ignored) | — |

**Invariants**

- Exactly one of `handOver`, `fadeAway`, `dismiss` ends the note. Checked by: the `closing`/`sent` guards.
- During `sent`, Esc and Return do not reach the note: `LiveInk` already set `note = nil` (`letGoOfNotePanel`, `LiveInk.swift:626`), so Esc goes to `cancelAsk` when Esc has a step. An `onAsk` failure calls `fadeAway` (631). Checked by: nothing.

## Findings

The area maps raised 84 invalid states and transitions, and the reviewer found one more. A **confirmed** finding has a traced sequence and a unit test that failed before its fix, and belongs to one of the [issues](#issues). Fourteen are confirmed. A **plausible** finding is traced, but no unit test reaches it yet or one step of it was not checked, and it is not fixed. Each plausible entry ends with how sure its mapper was and what was left unchecked, and with the review's verdict where it gave one.

Line references are to commit 358d988 unless a finding says otherwise. Those in the confirmed findings were checked; the rest are the mappers', partly corrected, and drift as the code changes. Search for the symbol a reference names.

### Confirmed findings

<a id="editor-1"></a>
#### editor-1: Opening an image resets what Return and Cmd+Return do

- **Sequence**: the person pages with Left or Right between two agent replies from the same session,
  or opens another image while the bar offers Send, so the bar's offer does not change. They press
  Return on the Reply card (or Cmd+Return to send).
- **Trace**: `EditorCore.open` replaces the whole core with `self = EditorCore()`
  (`EditorCore.swift:577`), keeping only `zoom` and the pending effects, so `finishes` goes back to
  `Finishes()`, Done for both keys. The comment on `finishes` (`:367`) says opening leaves it alone.
  The host sets it only from `offerChanged` (`AnnotationController.swift:640`), and the bar reports
  its offer only when it changes (`AnnotatorToolbar.swift:139`); a bar that carries its target
  (`Model.begin`'s `carryingTarget`) does not change it. Two replies from one session both offer
  `.reply(S)`, so paging between them never re-reports it. A fresh session list that differs in any
  field re-reports the offer, which hides the bug on the Send path more often than on Reply.
- **Breaks**: Cmd+Return copies and closes instead of sending; Return on a Reply card copies instead of
  replying.
- **Test**: `EditorCoreOpeningTests.testTheNextImageFinishesWithWhatTheBarStillOffers`.
- **Fix**: `open` keeps `finishes`, as it keeps `zoom`.
- **Status**: fixed, [issue 1](#issue-1), in `72f89df`.

<a id="toolbar-3"></a>
#### toolbar-3: A second send to a session that is still starting starts it again

- **Sequence**: the person sends to a "Continue last session" row, which starts `claude --resume` in
  a new herdr tab and waits up to 45 s for its inbox. Before the inbox comes up, they send another
  image to the same row, which stays listed until a live inbox holds the session. Two screenshots
  sent one after the other to a session that takes a few seconds to start is enough.
- **Trace**: each send runs `startSession` on its own pool thread (`AgentConnection.swift:425-437`).
  The only guard is `liveInbox(holding: session)` (`:274`), which is false until the first start's
  inbox is live, so the second send launches again (`:277`). Nothing records a start under way.
- **Breaks**: two Claude Code processes resume one session, which forks its transcript, and a stray
  tab is left. When the first inbox exists but is not live yet, the second start never finds it
  (`look` takes only folders made since its own launch, `:289`) and fails after 45 s. That second
  case is traced, not tested; the test shows the double launch.
- **Test**: `SessionStartsTests.testASecondSendWhileItsSessionIsStillStartingJoinsThatStart`, which sends
  twice while the first start looks for its inbox and expects one launch.
- **Fix**: one start per session id at a time. A send for a session already starting waits for that
  start's answer and writes its line into the same inbox. It adds a state, a start under way, which
  Pete approved ([issue 3](#issue-3)).
- **Status**: fixed, [issue 3](#issue-3), in `f1ea7c3`.

<a id="requests-1"></a>
#### requests-1: A screenshot deleted during its send's grace period is still sent

- **Sequence**: the person sends a screenshot; its line waits `ui.sendGraceSeconds`. Within about one
  listing of an app write to the folder (an agent's push, a reply, a live ink card), they delete the
  screenshot in Finder.
- **Trace**: the watcher's report comes from a listing older than the write, so
  `FolderWrites.removed` holds the removal back (`FolderWrites.swift:259-262`). The next listing
  settles it with `callbacks.removeCards` only (`:315-316`). `fileRemoved`, which cancels a waiting
  send (`ScreenshotRequests.fileRemoved`), is called only from `left` (`:328`).
- **Breaks**: the card goes, but the line still reaches the session when the grace ends, with the
  image the person deleted. Vignette's own Trash goes through `left` directly and still cancels;
  only a deletion from outside, during the grace and the same listing interval as an app write,
  reaches this path.
- **Test**: `FolderWritesTests.testARemovalFromAnOlderListingWaitsForANewerOne`, which pinned the
  card-only removal and now expects the whole removal.
- **Fix**: a held-back removal, once confirmed, leaves through `left` like any other. Its drawing
  and replies are already gone by then, and removing them again does nothing (`Drawings.remove`
  filters on the keys it holds, and `fileRemoved` skips a reply already deleted), so `left` is safe
  to reuse. The test's own comment, which named that second removal as a fault, changes with it.
- **Status**: fixed, [issue 6](#issue-6), in `b9b76b8`.

<a id="asks-1"></a>
#### asks-1: Signing out of Codex while it answers leaves the ask waiting forever

- **Sequence**: live ink asks Codex. While the answer is under way, the person signs out of Codex in
  Settings.
- **Trace**: `ResponderStatus.signOut` calls `onCodexSigningOut` (`ResponderStatus.swift:133`), which
  is `all[.codex]?.stop()` (`LiveResponders.swift:26`). `LiveResponder.stop()` shuts down with no
  failure (`LiveResponder.swift:162-166`), and `shutDown` returns before answering the dropped asks
  (`:369-380`). The ask timer was invalidated, so no timeout comes either.
- **Breaks**: `LiveAsks` keeps the ask `asking`: its thinking light stays on, and every later ask,
  to Claude too, waits behind it until the person presses Esc on each stuck ask.
- **Test**: `LiveResponderTests.testAnAskUnderWayWhenTheSignInGoesFailsOnce`. Before the fix it failed
  through `stop()`, which the sign-out called.
- **Fix**: the sign-out fails the asks it drops: `stop(failingAsks: true)`. Every other caller of
  `stop()` keeps the silent drop. Clearing has already ended its asks in `LiveAsks`
  (`LiveInk.swift:1728-1729`, and `docs/live-ink.md` states the silent drop for it); the idle stop
  and the conversation limit run with nothing held; the restart after an unanswered interrupt asks
  the pending ask again.
- **Status**: fixed, [issue 4](#issue-4), in `95c1a56`.

<a id="run-2"></a>
#### run-2: The shortcut pressed while a zoomed swap parks does not close the editor

- **Sequence**: two or more lone thumbnails in the corner, not a stack. One is open in the editor and
  zoomed in. The person clicks another lone thumbnail, or presses Left or Right, which parks the
  first image while the frame springs back to its fit (0.2 s at motion 1). During that spring they
  press the shortcut, or pick Show Recent Screenshots. With a stack the shortcut dismisses instead,
  which the park already handles. Very rare.
- **Trace**: `CornerPresentation` answers the shortcut with `.closeEditor`
  (`CornerPresentation.swift:109`), which sends `.cancel(.shortcut)` (`ThumbnailController.swift:284`).
  The run empties its queue and forwards `.close`, which `AnnotatorTransition` ignores in
  `parking(o, then: .annotate(o2))` (`AnnotatorTransition.swift:220`). Esc and a click outside cannot
  reach this phase: `AnnotationController.cancel` returns once `hide` has cleared `current`.
- **Breaks**: the next image opens anyway, under the stack the shortcut brought up, and the run
  keeps `.shortcut` as its ending for whatever ends it later.
- **Test**: `AnnotationRunTests.testACancelDuringASwapsParkClosesInsteadOfOpeningTheNextImage`.
- **Fix**: `.close` in `parking(o, then: .annotate)` becomes `parking(o, then: .close)`: a later
  request wins, as it already does the other way round.
- **Status**: fixed, [issue 8](#issue-8), in `b225449`.

<a id="run-3"></a>
#### run-3: The open file deleted while a zoomed swap parks comes back as a card

- **Sequence**: the stack is open with other cards. An image is open and zoomed; the person clicks
  another card, which parks the first while its frame springs back. During that spring the first
  image's file is deleted (Finder, an agent's `trash`). Very rare: the window is about 0.2 s.
- **Trace**: the run empties its queue (`AnnotationRun.swift:136`), but `AnnotatorTransition`
  ignores `.remove(o.key)` in `parking(o, then: .annotate)` (`:211-216`). `ThumbnailController.remove`
  takes the card out of the stack; `parked` then answers `returnCard(o)`, and `returnCard` inserts the
  card back (`ThumbnailController.swift:883-895`) for a file that no longer exists.
- **Breaks**: a card for a deleted file sits in the stack, and every action on it fails.
- **Tests**: `AnnotatorTransitionTests.testRemovingTheFileParkingForASwapHidesItAndOpensNothing`,
  `AnnotationRunTests.testRemovingTheOpenFileDuringASwapsParkEndsTheRun`.
- **Fix**: that row becomes `parking(o, then: .remove)`, as for `close` and `finish`: the annotator
  hides and nothing takes its place, which is the run's own rule (`AnnotationRun.swift:135`).
- **Status**: fixed, [issue 8](#issue-8), in `b225449`.

<a id="run-1"></a>
#### run-1: A card selected while Esc's park runs opens in the editor

- **Sequence**: a stack card is open and zoomed. The person presses Esc; while the frame springs back
  they select a card in the stack.
- **Trace**: `.cancel` empties the queue (`AnnotationRun.swift:121`), but `select` checks only that
  the transition is active (`:255`), so the selected card is queued, and `parked` opens it
  (`continueOrEnd`, `:232`).
- **Breaks**: the editor opens again on the card the person only selected, after they pressed Esc.
- **Test**: `AnnotationRunTests.testACardSelectedWhileEscParksQueuesNothing`;
  `testACardSelectedWhileSendParksIsQueuedNext` keeps Send's queue going.
- **Fix**: a run whose queue was ended (Esc, a dismissal, the open file going) takes no more
  selected files. A click on a card during the same park still opens that card, as a click does
  when nothing is open; only a selection, which opens nothing on its own, is refused.
- **Status**: fixed, [issue 7](#issue-7), in `aaba2a2`.

<a id="run-4"></a>
#### run-4: A list's run reports how an earlier image ended

- **Sequence**: a list of two opens. Done on the first; the second opens. The second then ends with
  no hand: its file is deleted, or the panel goes away.
- **Trace**: `finish` sets `ending = .finished` (`AnnotationRun.swift:127`). The handover in
  `continueOrEnd` (`:240-243`) leaves it, and only the run's end clears it (`:236`). A second path
  carries it too: after Esc, a click on another card during the zoomed park swaps to it
  (`AnnotatorTransition.swift:203`), so the transition never goes idle and `.back` stays set.
- **Breaks**: `endRun(.finished)` reaches `CornerPresentation`, which returns the focus to the app
  before Vignette when no hand asked it to; a stale `.shortcut` keeps it from returning.
- **Test**: `AnnotationRunTests.testAHandoverForgetsHowTheImageBeforeEnded`.
- **Fix**: `ending` is cleared when another image really opens: in `reduce`, after the files that
  cannot open are passed over, and only when a `prepare` is left. Clearing it in the handover
  itself would be wrong: when Done is pressed and no queued file opens, the run must still report
  `.finished` (`AnnotationRunTests.testAQueuedFileThatDoesNotOpenIsPassedOver`).
- **Status**: fixed, [issue 7](#issue-7), in `aaba2a2`.

<a id="corner-1"></a>
#### corner-1: A notice on a file renamed during its hold never goes

- **Sequence**: a card shows Copied (or Not copied, or a failed send). Within the notice's hold the
  file is renamed inside the folder.
- **Trace**: `ThumbnailController.post` schedules `notices.expire(posted.id, on: file)` with the key
  from before the rename (`ThumbnailController.swift:666`). `CardNotices.rename` moves the notice to
  the new key (`CardNotices.swift:157`), so `expire` finds nothing under the old one (`:150`).
- **Breaks**: the renamed card keeps the notice until another replaces it, and a send's countdown it
  covered never comes back. While the notice stays, a lone thumbnail of that file that comes home
  from the editor skips both ways out of the corner (`ThumbnailController.swift:918`, `:925-926`),
  so it stays until something else arms the timer.
- **Test**: `CardNoticesTests.testANoticeOnAFileRenamedDuringItsHoldStillExpires`.
- **Fix**: `expire` takes only the notice's id, which no rename changes.
- **Status**: fixed, [issue 5](#issue-5), in `4e16467`.

<a id="corner-3"></a>
#### corner-3: The focus stays on a card the column dropped

- **Sequence**: the stack is open and has the keys, with the column full (`recentCount` cards). The
  person moves the focus to the oldest card. A capture or an agent's push arrives.
- **Trace**: the new card slides in (`shiftUp`), and the overflow drops the oldest card
  (`ThumbnailController.removeOverflow`, `ThumbnailController.swift:1465-1470`, called at `:1446`).
  It removes the card and deselects it, but leaves `model.focused` on its id. `remove(_:)` repairs
  the focus when a card's file goes (`:487`); this path does not. The stack's next `takeKeys`
  refocuses only when `focused` is nil (`:279`), so a stale id is never replaced.
- **Breaks**: no card wears the focus ring and Space does nothing, while Return, Copy and Trash act
  on the newest card (`targetCards`, `:1081-1082`). The focus stays lost until an arrow key or the
  pointer sets it.
- **Test**: `StackModelTests.testWhenTheFocusedCardLeavesTheNewestTakesTheFocus`.
- **Fix**: `StackModel.removeCards` owns the rule `remove(_:)` states: when the focused card leaves,
  the newest card takes the focus. The stitch, which wants no focus once its pieces leave, clears it
  before it removes them.
- **Status**: fixed, [issue 2](#issue-2), in `fc3077b`.

<a id="corner-9"></a>
#### corner-9: A drag over the oldest card when a capture fills the column crashes the app

- **Sequence**: the stack is open with a full column. The person drags from a selection circle, and
  a capture or an agent's push arrives while the pointer is over the oldest card.
- **Trace**: `insert` ends the sweep (`ThumbnailController.swift:1367`) and `shiftUp` puts the new card
  at index 0, so the column holds one card too many until the next turn, when `springLifts` runs
  `removeOverflow` (`:1446`). A drag move in between anchors the new sweep on the oldest card, at an
  index that `removeOverflow` then takes away. The sweep kept its anchor as an index
  (`StackSweep.swift:17`), so the next move reads `model.cards[anchor]` past the end (`:73`).
- **Breaks**: "Index out of range", which ends the app.
- **Test**: `StackModelTests.testASweepWhoseFirstCardLeavesStartsAgainFromTheCardUnderThePointer`,
  which crashed the test process at `StackSweep.swift:73` before the fix.
- **Fix**: the sweep anchors on the card's id. When that card has left, the sweep ends and the drag
  starts a new one from the card under the pointer, as it does after an insert.
- **Status**: fixed, [issue 9](#issue-9), in `8451a9c`.

<a id="corner-4"></a>
#### corner-4: A capture into a full column drops the card open in the editor

- **Sequence**: the stack is open with a full column, and the oldest card is open in the editor, its
  slot drawn empty. A capture with `annotateOnCapture` off, or an agent's push, arrives. Pushes while
  the person draws are the agent loop's normal case.
- **Trace**: `removeOverflow` dropped `model.cards.last` without checking `outCards` or `forming`
  (`ThumbnailController.swift:1465-1470`), and `removeCards` cleared its marks (`StackModel.swift:87`).
  When the editor closes, `returnCard` finds the card missing and inserts it again at index 0
  (`ThumbnailController.swift:886-892`), and that insert drops the next oldest card.
- **Breaks**: the card comes home to the newest slot, and an unrelated card leaves the column.
- **Test**: `StackModelTests.testTheOverflowKeepsTheCardsInTheEditorAndInAStitch`. The overflow moved
  into `StackModel` unchanged so a test could reach it, and the test failed against it.
- **Fix**: the overflow drops the oldest card that is not in the annotator or in a stitch.
- **Status**: fixed, [issue 10](#issue-10), in `72f89df`0.

<a id="requests-2"></a>
#### requests-2: A cleared request whose answer live ink drew is never pruned

- **Sequence**: live ink asks a session, and its answer becomes live ink's own result card, so the
  reply is `shown`. Later the request is cleared, by `requests?clear=` or by the 50-request limit,
  which clears the oldest on its own.
- **Trace**: `cleanup` treated every reply but a published one as unpublished
  (`ScreenshotRequests.swift:823`). It turned the shown reply `cancelled` and set
  `needsOutputCleanup`, since its stage is not `accepted` (`:828-830`). A shown reply has no
  `destination`, which only `publishCard` sets (`:649`), so its `outputURL` is nil and the flag
  never clears. `prune` skips any request with that flag (`:785`).
- **Breaks**: every such request's folder stays forever, with its records, and `load` reads all of
  them. The drawn answer's receipt also changed from ready to cancelled.
- **Test**: `ScreenshotRequestsClearingTests.testAClearedRequestWhoseAnswerLiveInkDrewStaysDrawnAndIsPrunedAfterAWeek`,
  in a new file because `ScreenshotRequestsTests.swift` is over the size limit.
- **Fix**: clearing leaves a shown reply as it leaves a published one (`Reply.isPresented`).
- **Status**: fixed, [issue 11](#issue-11), in `72f89df`1.

<a id="setup-1"></a>
#### setup-1: A plugin switched off comes back at the next launch when the old skill is a link

- **Sequence**: the person kept the skill from before the plugin as a link, as Pete does
  (`docs/claude-code-without-herdr-2026-09-27.md:415-416`). They turn the plugin off with the Agents
  tab's switch, then Vignette launches again.
- **Trace**: the switch runs `plugin remove`, so `isInstalled` reads false at launch. The launch
  installed wherever an old skill was, folder or link. A link is never
  removed (`removeLegacySkill`, `testOldSkillFolderGoesAndALinkStays`), so every launch installs
  again.
- **Breaks**: the switch's off does not hold. `docs/rules/agent-plugin.md` says the switch is
  the only thing that removes the plugin, and the person's choice is undone at each launch.
- **Test**: `AgentPluginTests.testALaunchLeavesThePluginOffAfterTheSwitchTurnedItOffWhereTheOldSkillIsALink`,
  which launches twice and expects the second launch to install nothing, and
  `testALaunchThatFindsThePluginBesideALinkedSkillLeavesItOffOnceTheSwitchTurnsItOff`, for a plugin
  already in beside a link when the fix arrives. Both failed before the fix.
- **Fix**: the plugin being in beside the old skill, from a launch or a switch, records the agent
  folder in `agent-plugin-migrated.json` in Application Support (`LegacySkillMigrations`), and a
  launch installs for the old skill only in a folder not recorded.
- **Status**: fixed, [issue 12](#issue-12), in `d0fb7c7`.

### Plausible findings

Grouped by area. An entry with no review verdict was skimmed by the reviewer and left as its mapper wrote it.

#### The annotation run

- <a id="run-5"></a>**run-5**: A flight dropped before it arrives never tells the run, so a held Left/Right key stops repeating. Sequence: a lone thumbnail alone in the corner is in the editor (flight in, not arrived, `visible == false`). A new capture arrives: `show` -> `present(cards:)` -> `flights.endAll(except: [])` (`ThumbnailController.swift:1319`). The flight's `dropped:` closure runs. Where: `ThumbnailController.swift:1319`, `AnnotationRun.swift:191-193`. Mapper: medium. I traced `dropped` in `TransitionLayer.end(where:)` (`:379-388`) and the closure; did not run it. **Status**: Review: the same as [flights-1](#flights-1); the variant stuck before `covered` is unreachable. Low. Open.
- <a id="run-6"></a>**run-6**: The reducer counts a removed queued file in `total`. Where: `AnnotationRun.swift:134`. **Status**: Review: refuted: it changes only the log's count, which `AnnotationRunTests.testAFileGoneFromTheQueueSkipsNoNumber` pins.
- <a id="run-7"></a>**run-7**: A stale or late `annotate(from: origin)` leaves or applies capture state. Where: `ThumbnailController.swift:324-338`, `AnnotatorTransition.swift:126/155`. Mapper: low. I did not find a watcher path that reports one file as a capture twice.
- <a id="run-8"></a>**run-8**: A rename during the zoomed park is not passed to the annotator, so the flight home loses the title. Sequence: zoomed editor on `a` (titled image), `Esc`, file renamed during the fit-out. Mapper: low-medium (traced, not run).

#### Flights and zoom

- <a id="flights-1"></a>**flights-1**: A flight dropped between `covered` and `arrived` tells the zoom and the shadow it landed, but the run never gets `.arrived`. Sequence: lone thumbnail opens in the annotator (`.annotate`); the flight covers its target and `.shown` is sent. Where: `ThumbnailController.swift:843`, `ThumbnailController.swift:1319`, `TransitionLayer.swift:382`. Mapper: medium. Traced `endAll` and both closures; did not check how often `kept` excludes the annotating card, nor `AnnotationRun`'s other uses of …. **Status**: Review: downgraded to low: only a new capture or push in the 0.1 to 0.3 s before the flight lands reaches it. Open.
- <a id="flights-2"></a>**flights-2**: `fly` to a new screen re-frames the shared panel under flights and swallow rects whose frames are local to the old screen. Sequence: two displays. A flight is in the air on display 1 (a card flying home, or a swallow rect inside its double-click window). A capture on display 2 presents the corner there (`pinnedScreen`, `ThumbnailController.swift:1302`) and `fly`/`swallowPresses` is called with `screen: display 2`. Where: `ThumbnailController.swift:1302`, `TransitionLayer.swift:429-435`. Mapper: low-medium. Did not check whether `ThumbnailController` forbids a second display while any flight or swallow rect exists.
- <a id="flights-3"></a>**flights-3**: `Tween.animate` drops the previous completion, and `set`/`stop` never call it; one caller relies on exactly-once. Sequence: `fitBeforeHide` starts `zoomTween.animate(to: 1, completion: once)`; before it settles any other `animate`/`set` on `zoomTween` replaces or discards `once`. Where: `Tween.swift:47`, `AnnotationController.swift:188`. Mapper: high that the behavior exists; low that it is a user-visible bug (deadline covers it). **Status**: Review: refuted as a bug: the 0.3 s deadline answers for the replaced completion.
- <a id="flights-4"></a>**flights-4**: `zoom.phase` never returns to `closed`; a zoom-phase read after the editor closed reports `closing`. Sequence: open and close any image. After `hideWindows`, the editor is hidden but `zoom.phase == .closing` until the next `.prepare`. Where: `AnnotatorZoom.swift:187`, `AnnotationController.swift:682`, `TransitionLayer.swift:127`. Mapper: high that it is unreachable; low impact.

#### The corner and the stack

- <a id="corner-2"></a>**corner-2**: `hoveredCard` names a card that was removed, so a lone thumbnail never leaves. Sequence: two or more lone thumbnails in the corner. The pointer is on card A (hover set). A's file is removed (Trash button, Finder delete, `vignette://trash`) so `remove(_:)` runs and other cards remain. Where: `CardView.swift:204`. Mapper: medium. Not checked: SwiftUI hover-exit on view removal. **Status**: Review: plausible: whether SwiftUI ends a hover for a view that is removed is unverified, and AppKit's tracking areas do not, which makes it likely. Open.
- <a id="corner-5"></a>**corner-5**: A shortcut press that finds nothing to list leaves lone thumbnails with no timer. Sequence: lone thumbnails are showing (timer armed) while `recentListing()` returns no shots (watcher index empty or not listed yet, or the card is a file the recent listing excludes). The shortcut is pressed. Mapper: medium. Not checked: how often a card in the corner is absent from the recent listing. **Status**: Review: downgraded to very rare. Open.
- <a id="corner-6"></a>**corner-6**: Dismissing mid-stitch pops the column instead of sliding it out, and skips `slidOut`. Sequence: stitch from the stack, and dismiss (Esc, shortcut, click outside) during the converge. Where: `TransitionLayer.swift:275,283`, `CornerKeys.swift:143`. Mapper: medium. Not checked: how long the other cards actually show offscreen before `present` runs.
- <a id="corner-7"></a>**corner-7**: Cmd+A (or a second Stitch) can select forming cards. Sequence: stitch; during the converge press Cmd+A, then a Stitch key, Copy or Trash. Where: `CardView.swift:60`. Mapper: low-medium. Not checked: `TransitionLayer`'s behaviour for a duplicate id (flights mapper).
- <a id="corner-8"></a>**corner-8**: A card inserted during a converge moves the destination slot. Sequence: stitch; a new screenshot arrives before the converge completes. Mapper: low-medium.
- <a id="corner-10"></a>**corner-10**: A re-sent card loses the first send's failure. Sequence: send card A (request 1, answer slow), reopen and send again (request 2), request 1 then fails. Where: `CardNotices.swift:111`. Mapper: medium (design question). **Status**: Review: refuted: intended, and pinned by `CardNoticesTests.testAnAnswerToAnEarlierSendIsDropped`.
- <a id="corner-11"></a>**corner-11**: `ModifierTap` hold fires after another modifier is pressed. Sequence: double-tap right Shift, keep it down, press another modifier within 0.4 s. Where: `ModifierTap.swift:65`. Mapper: low-medium.
- <a id="corner-12"></a>**corner-12**: `HotKey.isDown` stuck if a release event is never delivered. Sequence: the key release is lost (Carbon release not delivered, as when the key was released while another app held a keyboard grab). Where: `HotKey.swift:62`. Mapper: low.
- <a id="corner-13"></a>**corner-13**: `shiftUp`'s next-turn block un-parks a card after a dismissal in the same turn. Sequence: `show` of a card into an open stack, then `dismiss` (`quickDone` or a URL command) before the next main-queue block. Mapper: low.
- <a id="corner-14"></a>**corner-14**: The open file removed while the stack is up leaves no window with the keys. Sequence: a card from the recent stack is open in the editor; its file is deleted. The run ends with `endRun(nil)` (`AnnotationRun.swift:136`, `hideAnnotator`), so `CornerPresentation` restores no focus (`CornerPresentation.swift:135`), and no card lands to take the keys back (`:139-143`). Vignette stays active with no key window until a click. Found by the reviewer, outside every map; not run. **Status**: Open.

#### The editor and drawings

- <a id="editor-2"></a>**editor-2**: A failed stored-file rename leaves the open editor on a path that no longer exists, and its later saves are dropped. Sequence: screenshot A is open in the editor and has a stored drawing; the file is renamed to B (Finder, or a rename inside the folder); `FolderWrites` calls `Drawings.rename(A -> B)`; `store.rename` throws (target `B` already has a drawing file from a newer build, `refuseNewer`; or the write or the removal of the old file fails); the person keeps drawing. Where: `Drawings.swift:123`, `AppDelegate.swift:497 renameCards`, `AnnotationController.swift:103`. Mapper: high on the trace; reachability is low (needs a failing store write). **Status**: Review: stands, low: it needs the store's rename to throw. Open.
- <a id="editor-3"></a>**editor-3**: A tweak or mark-scale change during an input-method composition restyles the text and ends it. Sequence: a text is being typed with marked text; the tweak panel or a mark-scale rule change calls `AnnotationController.applyTweaks`. Where: `EditorView.swift:231-234`, `EditorTextView.swift:94`. Mapper: low-medium; the `setStyle` effect on marked text is inferred from the existing comment, not measured.
- <a id="editor-4"></a>**editor-4**: Cmd+Z during a composition undoes the session instead of leaving the composition alone. Sequence: typing, an input method has marked text, person presses Cmd+Z. Where: `EditorView.swift:591-594`. Mapper: low.
- <a id="editor-5"></a>**editor-5**: A late change from an ended session's text view is applied to the new session's text. Sequence: person is typing in note 1 with a pending composition, clicks note 2. Where: `EditorCore.swift:750-754`, `EditorView.swift:471`, `EditorCore.swift:1243`. Mapper: low (the guard is missing; the trigger is unverified).
- <a id="editor-6"></a>**editor-6**: A dragged card whose rendering fails still drops its path as text. Sequence: person drags a card with a drawing; `DragItems` renders it ahead or at drag start; the rendering fails (screenshot renamed, trashed, unreadable, disk full); the drop completes onto a terminal or editor. Where: `Clipboard.swift:49`, `DragItems.swift:53-55`. Mapper: medium. The drop target's behavior when the provider returns nothing is not checked; the string is certain.
- <a id="editor-7"></a>**editor-7**: Copy Drawing's late completion overwrites a newer clipboard. Sequence: Copy Drawing on a card with a large drawing (0.6 to 1.2 s render); person copies something else in another app before it finishes. Where: `Clipboard.swift:35-39`. Mapper: medium on the trace; it may be the intended meaning of "copy lands when ready".
- <a id="editor-8"></a>**editor-8**: A text bitmap that failed to allocate is recorded as drawn. Sequence: a text's draw returns `nil` (`IOSurface` or `CGContext` could not be made under memory pressure, or a huge scale). Where: `MarkLayers.swift:477-482`, `EditorView.swift:518`. Mapper: low (needs an allocation failure; resolution caps keep normal sizes small).
- <a id="editor-9"></a>**editor-9**: `Drawings.rename` resets the old key's revision to 0, so a load that began before it is not dropped. Sequence: a card's load starts for key A with no write for A this launch (`started == 0`); A is renamed to B before the load answers. Where: `Drawings.swift:136-137`, `ThumbnailController.swift:438`, `EditorCore.swift:574-579`. Mapper: low (no consumer is hurt).

#### The toolbar and destinations

- <a id="toolbar-1"></a>**toolbar-1**: A Send press the editor ignores leaves `sendingTo` set, and a later Return sends to the old session. Sequence: editor zoomed in, target D1 listed. Esc or Done closes it. Within the zoom's fit-back spring (up to a few hundred ms) or the bar's 0.2 s fade, the person clicks Send (or presses Cmd+Return in the field). Next image opens (swap or reopen) with a different target D2, or as a Reply to R. Where: `AnnotationController.swift:472-477`, `AnnotatorToolbar.swift:532-552`, `AnnotationController.swift:97-100`. Mapper: high on the code path (every step traced, no guard); medium on how often the window is hit (zoomed close is the wide window). **Status**: fixed in `5000257`. The destination travels through the editor's send effect (`EditorCore.Input.send`, `Effect.send(_:to:)`), so an ignored press leaves no flag. Test: `EditorCoreSendTests.testASendPressedAfterTheEditorClosedIsDroppedAndTheNextImagesKeySendsWhereItsOwnBarDoes`.
- <a id="toolbar-2"></a>**toolbar-2**: A failed Codex listing replaces the kept list with an empty one, and the target can change or vanish. Sequence: (a) previous listing left `kept[codex]` = threads incl. T. Open editor; kept list answers at once and T (session used last) becomes the target. The fresh Codex job fails (codex not found at that moment, `process.run()` throws, or 8 s timeout with no listing line). The job returns `[]`. (b) Or: the next opening starts from `kept = []`. Where: `AppServer.swift:150`, `SessionListing.swift:149`, `AnnotatorToolbar.swift:181`. Mapper: medium. Traced every step; not checked whether a hung/failed app-server happens in practice, and an empty store would legitimately empty ….
- <a id="toolbar-4"></a>**toolbar-4**: A menu pick applied a turn later lands on a different opening or a hidden bar. Sequence: target menu open (modal). A queued main-queue block runs `prepare` for another image (an agent `vignette://annotate`, or a card click already queued), which calls `model.begin`. The pick's deferred block then runs. Where: `AnnotatorToolbar.swift:260-266`. Mapper: low. The window is the gap between a menu action and the next main-queue turn; no input reaches it, only a block already queued.
- <a id="toolbar-5"></a>**toolbar-5**: `SendOverlay` step closures from an earlier state change can fire after a later change's and overwrite `shown`. Sequence: notice goes `inGrace -> sent` (steps `[sending, sent]`, `sent` scheduled at about `glide + 0.45 s`). Before that fires, the notice changes again, e.g. `sent -> replyFailed`. Where: `SendOverlay.swift:81`. Mapper: low. A reply failing within a second of a send is not reachable in practice.
- <a id="toolbar-6"></a>**toolbar-6**: `ToolbarPanel.pressOnField` stays true after a press on the field, so the panel stays key-eligible. Sequence: click the message field (`pressOnField = true`). Esc or click on the image gives the keys back; the panel resigns key. Nothing sets `pressOnField` false until the next left press on the panel (`ToolbarPanel.sendEvent`, `:595-602`). Where: `AnnotationController.swift:113-115`. Mapper: low. Traced the flag's lifetime; not checked what AppKit does in each scenario.

#### Requests, replies and the screenshots folder

- <a id="requests-3"></a>**requests-3**: A launch that replaces a running copy keeps a stale `prepared` record and can write it back over the old copy's `uncertain`/`submitted`. Sequence: 1. Copy A: Send with the grace on. The request is `prepared`, the line waits. 2. Copy B launches and replaces A (`AppDelegate.swift:85`), calling `load(clearingUnsent: false)` (`:165`, `ScreenshotRequests.swift:129`). B holds the record as `prepared` in memory. 3. Where: `AppDelegate.swift:85`, `ScreenshotRequests.swift:129`. Mapper: medium-high. I did not check whether anything else makes B reload; I found no caller. **Status**: Review: stands, very low: it needs a replacing launch inside a send's grace and then a rename. Open.
- <a id="requests-4"></a>**requests-4**: A live ink answer whose capture fails after the request was cleared resurrects its cancelled reply as `reserved`. Sequence: a live ink answer is accepted and `presentLive` is outstanding; the request is cleared; `presentLive` then answers nil (the window could not be captured). Where: `ReplyCommand.swift:149-152`. Mapper: medium. Traced fully; I did not check how `LiveNoteCards` times its capture, so I do not know how often the sequence occurs.
- <a id="requests-5"></a>**requests-5**: A fresh rename is applied before an older held-back rename of the same file. Sequence: the app writes a file; the person renames `A` to `B`; that listing is older than the write, so `FolderWrites.renamed` defers it. Before the rescan's flush, a delivery arrives that carries `B` to `C` with a current inventory. Where: `FolderWrites.swift:284`. Mapper: high on the code order. Reaching it needs two renames of one file inside one listing interval, so low in practice.
- <a id="requests-6"></a>**requests-6**: The thumbnail cache stamps a decode with the file's modification date read after the decode. Where: `Thumbnailer.swift:183-185`. Mapper: low. Not run; window is the decode time.
- <a id="requests-7"></a>**requests-7**: A placeholder renamed while its download is in flight is not downloaded again. Where: `ThumbnailController.swift:312`. Mapper: low. I did not check whether the stack's `rename` (`ThumbnailController.rename`) re-queues a lookup.
- <a id="requests-8"></a>**requests-8**: A crash between `commit`'s `published` write and the agent attributes leaves a published reply without its badge and title. Where: `ScreenshotRequests.swift:702`, `ScreenshotRequests.swift:385`. Mapper: medium on the code, very low on likelihood.

#### Setup, settings and launch

- <a id="setup-2"></a>**setup-2**: A person who saw live ink's page in setup and said Not Now is offered live ink again at the next launch. Sequence: first launch, setup, live ink page shown, Not Now (or X), setup closes. Next launch, the agent plugin has nothing to offer. Where: `SetupWindow.swift:215`, `AppDelegate.swift:194`, `AppDelegate+LiveInkOffer.swift:8`. Mapper: high on the trace; medium on intent (the one-time wording may allow a repeat on the next launch; nothing says it does).
- <a id="setup-3"></a>**setup-3**: A settings write that fails is recorded as written, and the next reload reverts the app to the old file. Sequence: the app changes a setting; the 0.3 s write runs while the disk cannot take it (disk full, the file or folder made unwritable). Any directory event follows (the failed atomic write's temp file appears and goes, or another tool touches the folder). Where: `Settings.swift:951-953`. Mapper: medium. The reducer path is certain. Whether a directory event follows a failed atomic write on a full disk was not checked (unverified).
- <a id="setup-4"></a>**setup-4**: Quitting soon after setup closes loses the plugin install, and the offer is already marked made. Sequence: finish setup on the agents page with Claude Code's switch on; quit (or the machine sleeps and the app is killed) within the install's seconds. Where: `SetupWindow.swift:225`, `AgentPlugin.swift:503`, `AppDelegate.swift:210`. Mapper: medium. Not checked: how long the real tool takes; process termination mid-install was not observed.
- <a id="setup-5"></a>**setup-5**: Two quick presses on Allow… queue a second macOS Accessibility alert. Sequence: press an Allow… (setup, Settings, menu) and press it again within about 0.5 s, before macOS has put its alert on screen. Where: `SettingsWindow.swift:858`. Mapper: medium-high on the guard gap; the second alert is as `docs/rules/setup-and-updates.md` describes it, not observed here.
- <a id="setup-6"></a>**setup-6**: `Accessibility.request()` opens System Settings when the app is already trusted. Sequence: the grant lands (the person toggled it earlier or in another window), and a row's Allow… is pressed before the next poll (up to 0.5 s in setup, 1 s in Settings, and the status menu item is built from `missing()` at menu open). Where: `ScreenRecording.swift:12`. Mapper: medium. The window is narrow.
- <a id="setup-7"></a>**setup-7**: A second `MenuBarIntro.play` leaves the first's deferred closures running against the second. Sequence: Intro Lab's Play on Screen, or a Setup Lab run closing, while another intro is in its capture, flight or popover (debug only). For example a lab run closes and plays, then another plays within a second. Where: `MenuBarIntro.swift:55-58`, `AppDelegate.swift:918-922`. Mapper: medium (traced); debug-only trigger.
- <a id="setup-8"></a>**setup-8**: Two stitches in the same second write the same file. Sequence: `vignette://stitch` or the Stitch key pressed twice (or on two selections) so both compositions finish in the same wall-clock second. Where: `AppDelegate.swift:468`, `FolderWrites.swift:157-159`, `FolderWrites.swift:169`. Mapper: medium-low (needs two stitches within one second).
- <a id="setup-9"></a>**setup-9**: Apple's floating thumbnail turned on while Vignette runs is not turned off until the next launch. Sequence: the person turns "Show Floating Thumbnail" on in ⌘⇧5's Options while Vignette runs; takes a screenshot; pastes within about 5.6 s. Where: `Settings.swift:827-830`. Mapper: low-medium. Not checked: whether ⌘⇧5's menu writes the key immediately, and that no other code re-reads the key. **Status**: Review: matches the launch-time reconcile `docs/rules/settings.md` describes: a missing feature, not a state bug.
- <a id="setup-10"></a>**setup-10**: `vignette://` URLs have no ready gate. Sequence: `open -g vignette://state` (or any command) while Vignette is not running. Where: `AppDelegate.swift:674`. Mapper: low. **Status**: Review: may be more serious than low. One cold launch with `vignette://state` and the log's order would settle it; not run, since it launches the app.
- <a id="setup-11"></a>**setup-11**: Hiding the menu bar icon while the intro is flying shows a popover on a button with no window. Sequence: setup closes with the intro; within about 1 s `hideMenuBarIcon` becomes true (settings.json edit reloaded, or the Settings window). Where: `AppDelegate.swift:841-846`, `MenuBarIntro.swift:50`, `AppDelegate.swift:908`. Mapper: low.
- <a id="setup-12"></a>**setup-12**: A slow login shell makes an install report "no claude" although the tool is found moments later. Sequence: launch; within the first 8 s the person turns a switch on, or setup closes, for a tool that only the login shell finds (nvm, fnm). Where: `AgentTools.swift:36-37`, `AgentPlugin.swift:313`. Mapper: low.
- <a id="setup-13"></a>**setup-13**: Moving from the disk image trashes the working copy before the new one is in place. Sequence: a copy already in Applications; the image's copy is run; the person presses Move; `moveItem` into place fails. Where: `AppLocation.swift:145`. Mapper: low (needs a failing move after a successful trash).
- <a id="setup-14"></a>**setup-14**: A protected folder chosen during setup raises macOS's prompt outside setup's explanation. Sequence: first launch with an unprotected folder (watcher started at launch), setup open; the Save to folder is changed to the Desktop (status menu Settings, or ⌘⇧5). Where: `AppDelegate.swift:131`. Mapper: low.
- <a id="setup-15"></a>**setup-15**: The settings directory watch is not re-armed if the folder itself is replaced. Sequence: `~/.config/vignette` is a link into a dotfiles repository and is re-linked, or the folder is deleted and recreated, then the file is edited by hand. Where: `Settings.swift:975-982`. Mapper: low.
- <a id="setup-16"></a>**setup-16**: Live ink is already on when a quit-mid-setup launch asks again. Sequence: first launch, press Use Live Ink, quit before finishing setup (before pressing the Screen Recording Allow…). Where: `SetupWindow.swift:80`, `AppDelegate.swift:259-260`, `SetupInk.swift:387`. Mapper: low-medium (cosmetic, but the state pair `liveInk = true` with `setup = unasked` is reachable).

#### Live ink: the hand

- <a id="hand-1"></a>**hand-1**: A stroke cut short leaves `strokeBegan` and `strokeScreenDiagonal` from the dropped stroke. Sequence: chord down; press and drag on screen A (stroke tracking); Space change (or `standAside`, sleep, display change, `takeChord`); chord down again; draw a stroke on screen B. Where: `LiveInk.swift:1803`, `LiveInkOverlay.swift:292`, `LiveInk.swift:1864`. Mapper: high on the trace. Not run.
- <a id="hand-2"></a>**hand-2**: The tap drops the release of a press it never saw, and passes a release to the app for a press it dropped. Where: `LiveInkTap.swift:188`, `LiveInk.swift:1778-1790`, `LiveInkOverlay.swift:277`. Mapper: medium. The code path is certain; how each app reacts to a missing up is unverified.
- <a id="hand-3"></a>**hand-3**: A lost mouse-up while the chord is still held leaves the stroke tracking. Sequence: chord down; press and drag; macOS disables the tap by timeout (VM stalls are documented); the up arrives while disabled and goes to the app; the tap is re-enabled. Where: `LiveInkTap.swift:179`, `LiveInkOverlay.swift:266-268`. Mapper: medium. The `tapDisabledByUserInput` branch does the same without re-enabling.
- <a id="hand-4"></a>**hand-4**: A focus tour that starts while the person is inking is not ended by the ink. Sequence: an ask is out; the person holds the chord and starts a stroke (`showFieldForChord` runs, `chordShowsField = true`); the answer arrives with focus stops; `pullFocus` captures, `nextFocus` shows stop 1; the person keeps drawing. Where: `LiveInk.swift:2005`, `LiveInkTap.swift:188`, `LiveInkTap.swift:70`. Mapper: medium. Whether the global monitors truly hear nothing for tap-dropped events is inferred from the `NSEvent.pressedMouseButtons` ….
- <a id="hand-5"></a>**hand-5**: A second press while the transcriber is finishing is lost, and the note can send mid-stroke. Sequence: speak and draw; release the chord; 0.3 s later `LiveListening.finish` runs (mic stopped, `transcriber.finish(timeout: 2)` pending); press the chord again and draw more. Where: `LiveListening.swift:89-91`, `LiveInk+Listening.swift:46`, `LiveInk.swift:1771`. Mapper: medium. Trace complete; how often the window opens depends on `transcriber.finish` latency.
- <a id="hand-6"></a>**hand-6**: Unasked ink has no note after inking is cut short, or when the stack takes the screen during the menu wait. Where: `LiveInk.swift:1963`. Mapper: high that the state is reachable; low on whether it is a defect.
- <a id="hand-7"></a>**hand-7**: A double click on a step runs two steps at once, and Esc within 0.35 s does not stop the next step. Where: `LiveInk.swift:1340`. Mapper: medium. Trace complete; the timing windows are real but not run. **Status**: Review: a duplicate of [asks-2](#asks-2), and wrong about the double click: the next step is skipped, not two shown.
- <a id="hand-8"></a>**hand-8**: `LiveWindows.pin` places a mark with a stale frame when the window moved since the last tick. Sequence: a window is already tracked; it is moved (by a script, tiling manager, or the person before the chord); within one idle tick (up to 0.1 s) the person finishes a stroke on it. Where: `LiveInk.swift:450`, `LiveWindows.swift:99-111`. Mapper: low to medium. Window-move timing; not run.
- <a id="hand-9"></a>**hand-9**: The Esc step test reads `NSEvent.mouseLocation`, which stays stale after inking. Sequence: draw a loop, release the chord, type a note, press Return (an ask is under way), leave the pointer where it is, press Esc to stop the ask. Where: `LiveInk.swift:1752`, `LiveInk+Escape.swift:11`, `LiveInkTap.swift:70`. Mapper: medium. Depends on the cited measurement holding on the host Mac.
- <a id="hand-10"></a>**hand-10**: `chordChanged(.began)` from the URL is never ended by the real chord's poll. Sequence: `open -g vignette://live-ink-chord-down` and no `live-ink-chord-up` (a script crashes or is stopped). Where: `AppDelegate.swift:713-715`, `ModifierChord.swift:94`. Mapper: high that it is reachable; low severity.
- <a id="hand-11"></a>**hand-11**: `LiveListening` drops a start failure that arrives after `finish`. Sequence: tap the chord quickly with speech on; the microphone start (80 to 165 ms) fails after `finish` was called at the 0.3 s tail. Where: `LiveListening.swift:67`, `AppleTranscriber.swift:75`. Mapper: medium.
- <a id="hand-12"></a>**hand-12**: A display added during inking has no surface, and the tap swallows clicks there. Sequence: chord held; a display is connected. Where: `LiveInk.swift:2100-2101`, `LiveInkTap.swift:188`. Mapper: medium.
- <a id="hand-13"></a>**hand-13**: `LiveMenus.close` makes Accessibility calls on the main thread. Sequence: chord up with a menu open from an app that is slow to answer. Where: `LiveInk.swift:1959`, `LiveMenus.swift:65-73`, `LiveInk.swift:1783`. Mapper: low to medium; worst case not measured.

#### Live ink: asks and responders

- <a id="asks-2"></a>**asks-2**: A second click on an answer's step within 0.35 s skips a step, and Esc or × during that pause still draws the next step. Where: `LiveInk.swift:1340`, `LiveEscape.swift:66`, `LiveInk.swift:1328`. Mapper: high for A (every step traced, no `pending advance` flag exists), high for B-Esc, medium for B-×.
- <a id="asks-3"></a>**asks-3**: A result card's window capture stays in memory after its note is over, until some later live-ink activity prunes it. Sequence: Send a note to a session on a window. The turn ends, the window changed, a result card is made (`.resultCard(made)`), the send was delivered. No other live-ink note is sent afterwards. Where: `LiveNoteCards.swift:215-219`, `LiveNoteCardWait.swift:89-98`, `LiveNoteCardGroups.swift:149`. Mapper: medium. Verified the retention path and that nothing else releases `resultCard`; not measured how often a session has result cards without ….
- <a id="asks-4"></a>**asks-4**: A reply that arrives while the result card is still being written goes on the sent picture, not on the result card. Sequence: A turn ends; the window changed under the ink; the look says `cardMade`; `makeResultCard` starts writing the PNG (`folder.writeCard`, async). The session's `--answer` reply is imported in the same moment (`presentLive`). Where: `LiveNoteCardWait.swift:131`, `LiveNoteCards.swift:217-219`, `LiveNoteCardWait.swift:155-160`. Mapper: medium on the trace; low on frequency (replies normally come before the turn ends, then the card write takes under ~100 ms).
- <a id="asks-5"></a>**asks-5**: A Codex availability check that started before a sign-in or sign-out can overwrite its result. Sequence: Setup or Settings is open (Setup polls `look()` every 0.5 s, `SetupWindow.swift:427,453`; Settings looks on appear and on becoming key). A `check([.codex])` starts reading `auth.json` off the main thread. The sign-in completes (`changed(signedIn: true)` sets `.ready`, `ResponderStatus.swift:141`) before that check's main-thread write lands. Where: `SetupWindow.swift:427,453`, `ResponderStatus.swift:141`, `ResponderStatus.swift:84`. Mapper: low (window is milliseconds; I did not run it). Traced every step.
- <a id="asks-6"></a>**asks-6**: A tap-erased conversation (reply) of an ask under way comes back when more of the answer streams. Sequence: Ask, with a note. The conversation (the reply mark) appears. The person taps it to erase it while the ask is `asking`. More words stream, or the answer arrives. Where: `LiveInk.swift:422, 547`, `LiveAsks.swift:383-386`, `LiveInk.swift:1250`. Mapper: low (design question).
- <a id="asks-7"></a>**asks-7**: `TurnWatch` does not reset its idle spell on an unreadable (nil) reading. Sequence: Reading `busy` (turn seen), then `idle` (spell starts at t1), then `nil` readings (route cannot tell, for example a Codex rollout turned unreadable or a connection read failing) while the session starts another turn, then `idle` at t4. Where: `LiveNoteCardWait.swift:216-219`. Mapper: low-medium. Does not apply to Codex rollouts (unreadable stays nil forever, so `.idle` never comes).

## Issues

The confirmed findings, grouped by the change that fixes them. An issue keeps its number, which
commit messages cite; the table is in rank order. Rank is impact: how much a person loses, weighed
by how often the sequence comes up. The review moved several of them, and
[What the review changed](#what-the-review-changed) says how. Each issue is fixed in its own commit
with its regression tests.

| Rank | Issue | Findings | What a person hits | Status |
|---|---|---|---|---|
| 1 | [1. The next image forgets what Return and Cmd+Return do](#issue-1) | [editor-1](#editor-1) | Return copies instead of replying when paging between two replies from one session, every time | Fixed in `72f89df` |
| 2 | [10. A capture into a full column drops the card open in the editor](#issue-10) | [corner-4](#corner-4) | the card comes home to the newest slot, and another card leaves the column | Fixed in `72f89df`0 |
| 3 | [2. The focus stays on a card the column dropped](#issue-2) | [corner-3](#corner-3) | with a full column, a capture takes the focus ring away, and Return, Copy and Trash act on the newest card | Fixed in `fc3077b` |
| 4 | [3. A session that is still starting is started again](#issue-3) | [toolbar-3](#toolbar-3) | two sends to a session that is starting run two Claude Code processes on it, which forks its transcript | Fixed in `f1ea7c3` |
| 5 | [11. A cleared request whose answer live ink drew is never pruned](#issue-11) | [requests-2](#requests-2) | a request folder left behind for every such answer, forever | Fixed in `72f89df`1 |
| 6 | [12. A plugin switched off comes back at the next launch when the old skill is a link](#issue-12) | [setup-1](#setup-1) | the Agents tab's off does not hold, at every launch | Fixed in `d0fb7c7` |
| 7 | [9. A drag over the oldest card when a capture fills the column crashes the app](#issue-9) | [corner-9](#corner-9) | the app quits; rare | Fixed in `8451a9c` |
| 8 | [4. A Codex sign-out leaves its ask waiting forever](#issue-4) | [asks-1](#asks-1) | live ink answers nothing more, from Claude too, until Esc is pressed on the stuck ask | Fixed in `95c1a56` |
| 9 | [5. A notice on a renamed file never goes](#issue-5) | [corner-1](#corner-1) | a stale Copied or failure notice, a send's countdown that never comes back, and a lone thumbnail that stays | Fixed in `4e16467` |
| 10 | [7. The run keeps what a hand did after the hand is done](#issue-7) | [run-1](#run-1), [run-4](#run-4) | a card selected after Esc opens in the editor; the focus goes back, or stays, when no hand asked | Fixed in `aaba2a2` |
| 11 | [8. A cancel or a deletion while a swap parks is ignored](#issue-8) | [run-2](#run-2), [run-3](#run-3) | the shortcut does not close the editor; a card for a deleted file stays in the stack; very rare | Fixed in `b225449` |
| 12 | [6. A deleted screenshot is still sent](#issue-6) | [requests-1](#requests-1) | the image the person deleted reaches the agent session; very rare | Fixed in `b9b76b8` |

<a id="issue-1"></a>
### Issue 1: The next image forgets what Return and Cmd+Return do

`EditorCore.open` keeps `finishes` as it keeps `zoom`, so the bar's offer, which the host sets only
when it changes, still holds for the next image. Test:
`EditorCoreOpeningTests.testTheNextImageFinishesWithWhatTheBarStillOffers`. **Status**: fixed in `72f89df`.

<a id="issue-2"></a>
### Issue 2: The focus stays on a card the column dropped

`StackModel.removeCards`, which every removal goes through, now owns the rule that `remove(_:)`
stated alone: when the focused card leaves, the newest card takes the focus. `remove(_:)` no longer
repairs it itself, and the stitch clears the focus before its pieces leave, so a stitch still ends
with no focus. Test: `StackModelTests.testWhenTheFocusedCardLeavesTheNewestTakesTheFocus`. **Status**: fixed in `fc3077b`.

<a id="issue-3"></a>
### Issue 3: A session that is still starting is started again

A start had three states, all local to one send: launching, looking for the inbox, and up or
failed. No send could see another's start. The fix adds one state that every send shares: **a start
under way for session S**, held in `SessionStartsUnderWay` (`ClaudeSessionStart.swift`).

- `ClaudeCodeConnection` holds one table, from session id to the sends waiting on that start. It is
  a class behind a lock, since each send runs `startSession` on its own pool thread, and the
  connection's copies share it. The app has one connection, in `AppDelegate.connections`.
- A send that finds S in the table joins it and launches nothing. The first send checks for a live
  inbox, launches, and looks as before. Checking after joining means a start that answered just
  before is found up rather than started again.
- When the start answers, every send waiting on S gets the same answer: `up(inbox)`, and each writes
  its own line into that inbox, or `failed`, and each card reports it. S then leaves the table, so a
  later send after a failure starts again.

The start code moved to `ClaudeSessionStart.swift`, which keeps `AgentConnection.swift` under its
size. Test: `SessionStartsTests.testASecondSendWhileItsSessionIsStillStartingJoinsThatStart`. Pete
approved the new state on 2026-11-07. **Status**: fixed in `f1ea7c3`.

<a id="issue-4"></a>
### Issue 4: A Codex sign-out leaves its ask waiting forever

The sign-out stops Codex's responder with `stop(failingAsks: true)`, which fails the ask under way
or pending with Codex's "couldn't answer" reason, so `LiveAsks` ends it and the next ask goes. Every
other `stop()` keeps dropping silently, which is right for each of them (see [asks-1](#asks-1)).
Test: `LiveResponderTests.testAnAskUnderWayWhenTheSignInGoesFailsOnce`. **Status**: fixed in `95c1a56`.

<a id="issue-5"></a>
### Issue 5: A notice on a renamed file never goes

`CardNotices.expire` takes only the notice's id, which no rename changes, and finds the file that
holds it. Test: `CardNoticesTests.testANoticeOnAFileRenamedDuringItsHoldStillExpires`. **Status**: fixed in `4e16467`.

<a id="issue-6"></a>
### Issue 6: A deleted screenshot is still sent

A held-back removal, once a listing confirms it, leaves through `FolderWrites.left` like every
other removal, so `fileRemoved` cancels a send still in its grace. Test:
`FolderWritesTests.testARemovalFromAnOlderListingWaitsForANewerOne`, which pinned the card-only
removal. **Status**: fixed in `b9b76b8`.

<a id="issue-7"></a>
### Issue 7: The run keeps what a hand did after the hand is done

`AnnotationRun.select` queues nothing once the run's list has been ended (Esc, a dismissal, the
open file going), and `reduce` clears `ending` when another image really opens. Tests:
`AnnotationRunTests.testACardSelectedWhileEscParksQueuesNothing`,
`testACardSelectedWhileSendParksIsQueuedNext`, `testAHandoverForgetsHowTheImageBeforeEnded`. **Status**: fixed in `aaba2a2`.

<a id="issue-8"></a>
### Issue 8: A cancel or a deletion while a swap parks is ignored

Two rows of `AnnotatorTransition` change. In `parking(o, then: .annotate(o2))`, `close` becomes
`parking(o, then: .close)`, and `remove(o.key)` becomes `parking(o, then: .remove)`. A later request
wins over a swap, as a swap already wins over an earlier close. Tests:
`AnnotatorTransitionTests.testRemovingTheFileParkingForASwapHidesItAndOpensNothing`,
`AnnotationRunTests.testACancelDuringASwapsParkClosesInsteadOfOpeningTheNextImage`,
`testRemovingTheOpenFileDuringASwapsParkEndsTheRun`. **Status**: fixed in `b225449`.

<a id="issue-9"></a>
### Issue 9: A drag over the oldest card when a capture fills the column crashes the app

`StackSweep` keeps the card the drag started on by its id, not its index. When that card has left
the column, the sweep ends and the drag starts a new one from the card under the pointer. Test:
`StackModelTests.testASweepWhoseFirstCardLeavesStartsAgainFromTheCardUnderThePointer`. **Status**: fixed in `8451a9c`.

<a id="issue-10"></a>
### Issue 10: A capture into a full column drops the card open in the editor

The overflow moves into `StackModel.removeOverflow(over:)` and drops the oldest card that is not in
the annotator or in a stitch, since those come back to their slots. Test:
`StackModelTests.testTheOverflowKeepsTheCardsInTheEditorAndInAStitch`. **Status**: fixed in `72f89df`.0

<a id="issue-11"></a>
### Issue 11: A cleared request whose answer live ink drew is never pruned

Clearing leaves a reply the person already has, published or shown, as it is (`Reply.isPresented`),
so the request has nothing left to clean up and is pruned after a week. Test:
`ScreenshotRequestsClearingTests.testAClearedRequestWhoseAnswerLiveInkDrewStaysDrawnAndIsPrunedAfterAWeek`.
**Status**: fixed in `72f89df`.1

<a id="issue-12"></a>
### Issue 12: A plugin switched off comes back at the next launch when the old skill is a link

The launch records, once per agent folder, that the plugin is in beside the skill from before the
plugin, and installs for that skill only in a folder it has not recorded. A link then gets the
plugin at the first launch, as a folder does, and the switch's off holds after that. The record is
`agent-plugin-migrated.json` in Application Support, a list of folder paths
(`LegacySkillMigrations`). An install from the switch or setup beside the skill records it too.
Tests: `AgentPluginTests.testALaunchLeavesThePluginOffAfterTheSwitchTurnedItOffWhereTheOldSkillIsALink`,
`testALaunchThatFindsThePluginBesideALinkedSkillLeavesItOffOnceTheSwitchTurnsItOff`.
**Status**: fixed in `d0fb7c7`.

## What the review changed

One reviewer, an agent that did not write the findings, tried to refute each one against the code
at 358d988 with the new tests. It read the code and did not run it.

- **All ten confirmed findings stand.** Three fixes changed because of it:
  - run-4: clearing `ending` in the handover would break
    `AnnotationRunTests.testAQueuedFileThatDoesNotOpenIsPassedOver`, so it is cleared in `reduce`,
    once a `prepare` is left.
  - requests-1: the test's comment named the second removal of drawings and replies as a fault. That
    second removal does nothing, so the fix keeps `left` and the comment changes.
  - asks-1: the failure moved from `stop()` to the sign-out, so clearing keeps the silent drop that
    `docs/live-ink.md` states.
- **Reach narrowed**: run-1, run-2 and run-3 need a zoomed editor and a second input within 0.2 s.
  run-2 also needs lone thumbnails, not a stack. They moved to the bottom.
- **Reach widened**: editor-1 happens every time two replies from one session are paged through.
  corner-3 rose to second. toolbar-3 is ordinary use.
- **More consequences found**: corner-1 also keeps a lone thumbnail in the corner. toolbar-3's second
  start can wait the full 45 s and fail. run-4 has a second path: a click during Esc's park.
- **Plausible findings upgraded**: corner-4, corner-9, requests-2, setup-1 and toolbar-1. corner-9 is
  a crash. None had a unit test when the review ran.
- **Downgraded**: flights-1 and run-5 to low, corner-5 to very rare, setup-9 to a missing feature.
- **Refuted**: corner-10 and run-6 as intended, and flights-3 as a bug.
- **Merged**: hand-7 duplicates asks-2.
- **Added**: corner-14, which no map had.

After the review, four of the upgraded findings were confirmed by a failing test: corner-9,
corner-4, requests-2 and setup-1. toolbar-1 was not, because no unit test can build
`AnnotationController`, which held its flag. Its fix moved the destination into `EditorCore`'s
send, which `EditorCoreSendTests` covers.
