# Live ink

Live ink is drawing straight on the screen, over any app, while a pair of modifiers is held, and
asking an agent about what was drawn. This file has its rules and says where each part of it lives.
`docs/live-ink-integration-2026-10-04.md` has the plan, and the dated `docs/live-ink-*.md` notes
have the measurements.

## Before it ships

Live ink ships from main. What has to happen first, in order, and what waits on Pete is in
`docs/live-ink-release-plan-2026-10-24.md`.

## Where the code is

The names in brackets are `// MARK:` sections.

| To change | Look in |
|---|---|
| The chord, inking, the overlays per screen and Space | `LiveInk.swift` (Inking, Surfaces), `LiveInkOverlay.swift`, `ModifierChord.swift` |
| Inking over an open menu: the event tap, closing the menu before the note | `LiveInkTap.swift`, `LiveMenus.swift`, `LiveInk.swift` (Inking) |
| What a stroke becomes, and erasing | `InkStroke.swift`, `LiveInk.swift` (Strokes) |
| How the person's ink looks | `LiveInkHand.swift` |
| How an agent's shapes look | `LiveInkLight.swift` |
| The note: opening, placing, sending, handing over to the conversation | `LiveInk.swift` (Asking), `LiveNotePopover.swift`, `LiveAnswerLayout.noteHang`, `WindowRemoval.swift` |
| The asks: each one's phase, their turns at the responder, which late callbacks they drop, the answer put back after a failure, and each mark's role and the answer it belongs to, which erasing takes away | `LiveAsks.swift`, `LiveInk.swift` (Asking, Answering) |
| A note sent to a session: its card, its turn, its result card | `LiveInk.swift` (Asking), `LiveNoteCards.swift`, `LiveNoteCardWait.swift`, `LiveNoteCardGroups.swift` |
| Where an answer's marks and words go on a result card | `ResultCard.swift`, `LiveAnswer.swift` (`cardMarks`), `AgentMarks.swift` (`AgentMark.note`) |
| What an ask sends | `LivePacket.swift` |
| Speaking while drawing | `LiveInk.swift` (Listening), `LiveListening.swift`, `Microphone.swift`, `Transcriber.swift`, `AppleTranscriber.swift` |
| Claude on the screen, the `claude` process, stopping one turn | `LiveResponder.swift` |
| Esc: which step is next, the hotkey that holds it | `LiveEscape.swift`, `LiveInk.swift` (Esc), `HotKey.swift` |
| The answer: reading it, drawing it, steps | `LiveAnswer.swift`, `LiveInk.swift` (Answering) |
| The reply's popover, the conversation: its question, its row, its words, what it is laid over | `LiveReplyPopover.swift`, `LiveInkOverlay.swift` (`LiveMarksLayer.showPopover`) |
| The thinking light round a popover's rim | `LiveRimLight.swift` |
| Where the person's note, the reply, labels and pointing marks go | `LiveAnswerLayout.swift` (Pointing, Notes) |
| The agent pulling focus: rack focus, the tour, the loupe | `LiveFocus.swift`, `LiveInk.swift` (Pulling focus) |
| The answer's ×, its buttons and Reply's field, pointing at an action | `LiveInk.swift` (Dismissing and actions), `LiveAnswerActions.swift`, `LiveDismissButton.swift` |
| Marks staying on their window: moving with it, covered by windows in front, fading as it minimises | `LiveWindows.swift` |
| The pointer field (the lamp round the pointer) while inking | `PointerField.swift`, `PointerField.metal`, `LiveInk.swift` (The pointer field) |
| Whether a session's turn changed what the ink was on | `LiveChange.swift`, `LiveNoteCards.swift` (`look(again:)`, which compares the notes on one window; `before`) |

## Checking a change

- `Tests/LiveInkTests.swift` holds the unit tests: the chord, strokes, placement and result cards.
  `Tests/NoteCardWaitTests.swift` holds how a note card's wait ends, in any order of reply, turn end and delivery. It also covers a turn end that answers several notes.
  `Tests/LiveAsksTests.swift` holds the asks' sequences: asks waiting their turn, answers on the screen together, late
  callbacks, erasing, follow-ups, dismiss, finish and clear, and random sequences that check the invariants.
- A script reaches the note without a hand on the keys: `live-ink-chord-down`, then
  `live-ink-stroke` for each stroke, then `live-ink-chord-up` (all need `debug`). A VM's VNC cannot
  press ⌃⌥, so this is the only way a VM check opens the note.
- A take performs the developer demo on a stage and records it
  (`docs/live-ink-dev-demo-plan-2026-10-05.md`). It takes over the screen for several minutes. From
  `media/live-ink-demo/`: `python3 ../trailer/trailer.py build`, then `python3 dev.py up`, left
  running until it prints "the stage is up", then `python3 devtake.py [--only BEAT]`, then
  `python3 dev.py down`.
- A take prints a `[check]` line for each mark that moved on its window, each note that moved while
  open or opened away from its ink, and each label that had no room, and keeps them as `findings`
  in `<take>.beats.json`. Read them before reading frames. The labels come from the log:
  `[live-ink] drew answer … labels=<drawn>/<asked>` counts the labels that found room.

## Rules

- Live ink is an option (`liveInk`), turned on as `docs/live-ink-setup.md` says. `LiveInk` owns it: the chord, and a surface per screen per
  Space, each a `LiveInkOverlay` and the marks on it. A mark drawn on a window belongs to that window
  (`LiveWindows`) and keeps its offset from the window's top-left, whatever the window's content
  does: a scroll or a page's own change leaves it where it is, and so does a resize. It moves with
  the window, the windows above it cover it, it fades out as the window minimises and back once the
  window is on the screen again, 0.2 s after it lands, and it goes when the window closes. When the
  window shrinks past a mark's point (`LiveWindows.point(of:)`), the mark fades out until the window
  grows over that point again (`LiveWindows.fits`); a reply, a popover that may hang past the edge,
  stays (ADR 0024). A mark drawn on no window stays at its place on the screen.
  When a smaller resolution leaves it with no part on any screen, it moves the least way back onto
  its screen, as macOS moves a window (`[live-ink] moved <n> onto the screen`).
  The note's URL and the page an answer keeps to come from the app's Accessibility tree. Only an
  Electron app is asked to build its page's tree (`AXManualAccessibility`,
  `WindowAccessibility.requestTree`), and only when a mark lands where it has none, since it keeps
  the tree until it quits (`[live-ink] accessibility tree requested`). A Chromium browser such as
  Chrome or Dia is not asked, so its page gives the note no URL, unless it runs with
  `--force-renderer-accessibility`, as the demo's Chrome does.
- An overlay joins no other Space, so macOS keeps it where it was put up; it is closed, never
  ordered out, since ordered in again it would come up on the active Space. A surface exists while
  it has marks, and the active Space's while the chord is held, so an idle live ink puts no
  full-screen window over every app. An overlay is shared with no capture (`sharingType = .none`), so
  a screenshot leaves the marks out. macOS's window picker (Space during ⌘⇧4, or ⌘⇧5's window
  capture) still takes the window whose pixels are under the pointer, at any level, and reads the
  windows when Space is pressed; over a mark it took the overlay and could not capture it. So after
  ⌘⇧ (`CaptureOrigin.onCaptureKeys`), while there are marks, live ink clears its overlays (alpha 0,
  which the picker passes over) for as long as a `screencapture` process runs or `screencaptureui`
  has a window up (`LiveInk.watchForWindowPicker`). At rest it sits at level 1, above normal windows and below
  the dim (2) and Vignette's floating windows, so the stack and the annotator cover the marks, and
  so do menus, the Dock and other apps' floating windows. It passes every press then
  (`ignoresMouseEvents`). While the chord is held it is inking: it rises to `.screenSaver` with the
  flag off. The pointer's events then come from an event tap (the next rule). The overlay takes
  presses itself, over clear pixels too, as the matte rule in `AGENTS.md` says, only when macOS
  refuses the tap.
- While inking, an active event tap takes the pointer's presses, drags, releases and moves before
  any app hears them (`LiveInkTap`). It drops each one, and hands the left button's events and the
  moves to the inking (`LiveInk.tapped`). An open menu hears every press on the screen, whatever
  window is under the pointer, so a press the overlay takes closes a menu being drawn on. With the
  tap, the menu stays open and highlights nothing as the pen crosses its items. The same holds for
  anything else that closes when a press lands elsewhere, so the tap needs no list of element kinds.
  Measured 2026-10-26 in a VM, on Finder's File menu, a desktop right-click menu and Control
  Center's panel.
  While the tap is on, no app on the Mac hears a click. So it exists only while inking:
  `startInking` makes it, and `stopInking` stops it, whatever ended the inking. A process that exits
  takes its taps with it (checked with `kill -9` mid-press). The callback runs on a thread of its
  own and only hands each event to the main thread. macOS turns off a tap whose callback is slow to
  answer. With the callback on the main thread, a 4.8 s stall as inking started turned the tap off
  in the VM, and the menu under the ink then highlighted an item. A tap turned off that way goes on
  again while inking lasts. Without Accessibility, macOS refuses the tap and the overlay takes the
  presses. Each change logs one line: `[live-ink] tap on ms=<n>`, the time since inking started,
  `tap off`, `tap turned off by macOS: …` or `error tap refused by macOS; the overlay takes the
  presses`. A press that reaches an overlay while the tap is on is one the tap missed, and it logs
  `[live-ink] error a press reached the overlay while the tap is on`.
  The session's button state, which `NSEvent.pressedMouseButtons` reads, never counts a press the
  tap dropped. So the missed release (`watchRelease`) and the pointer field read the hardware's
  state instead (`LiveInkTap.isButtonDown`).
- A window over every app's windows is one above the status bar's level that does not cover its
  screen (`LiveMenus.open`, `LivePacket.menuBarLevel`). Menus, context menus and Control Center's
  panel are at level 101. A window's marks are drawn just above that window, so they would sit under
  a menu. Ink drawn over a menu while inking therefore stays on the screen's surface
  (`LiveInk.place`, `overMenus`), and the surface stays at the inking level until the menu has
  closed. Then each of those marks moves onto the window under it, in place, and no frame shows two
  copies (`pinOverMenus`, `LiveMarksLayer.handOff`). A mark with no window under it stays on the
  surface.
  An open menu would take the note's keys, so letting go of the chord closes the menus before the
  note opens. They close once the note's capture has the screen, menu included, or after
  `revealLimit` (0.8 s). `LiveMenus.close` performs Accessibility's cancel action on the outermost
  `AXMenu` under each, then waits up to 0.5 s for their windows to leave. Escape is never posted:
  once the menu is gone, it would reach the frontmost app. Control Center's panel has no `AXMenu`.
  It closes on its own when the note takes the keys. When a cancel is refused, or a menu is still
  open after the wait, the note opens without the keys
  (`[live-ink] note open without the keys: a menu is still open`). The log says
  `[live-ink] menus closing count=<n> refused=<n>`, then `menus closed` or
  `menus still open after 0.5 s`, and `pinned <n> of <m> marks drawn over a menu` once the marks
  have moved.
- Esc backs out of live ink one step per press, the first of these that applies (`LiveEscape.next`,
  a pure function of a snapshot of what is up; `Tests/LiveInkTests.swift`):
  1. Discard the note, while it has the keys: listening stops and its ink, all the ink no ask has
     been about, goes. Ink an ask was about stays. Or close Reply's field, which keeps its draft.
  2. Stop the newest ask under way or waiting its turn (`LiveInk.cancelAsk`, `LiveAsks.cancellable`),
     one per press. Its sent note and any reply leave, and its ink is as it was before the ask
     (`LiveAsks.Event.cancelled`): ink that was new when the ask began is new again. The note opens
     on that ink with the keys and the words the ask was sent with (`LiveAsks.Effect.reopenNote`). A
     note that is up already takes the keys and keeps its own words. A follow-up from a button puts the earlier answer back as it was, with no failure sentence, even
     once its reply has started to stream. Nothing
     says the ask failed, since the person stopped it. Stopping the ask the responder is answering
     interrupts its turn (`LiveResponder.cancel`), and the next ask waiting goes; one still waiting was
     never sent. An ask to a session is a step only until its send is stored, and only
     with a send grace: if the send is stored after all, it is withdrawn with Don't send
     (`LiveNoteCards.unsend`). Once it is stored the ink has left with it, and Don't send on the card
     is the way back.
  3. End the tour: the focus run, and the steps still to show.
  4. Close the newest answer, one per press: its reply, buttons and the agent's marks leave
     (`LiveAsks.Event.answerClosed`). A failure's reply counts as an answer. The person's ink stays,
     unlike the ×, which takes the ink it answered too.
  5. Clear what is left, as `clear()` does, which also ends the conversation.

  While the note is up without the keys, shown or hidden with its ink, none of these steps applies.
  The person is in another app, and Esc there is that app's. So a press meant for a terminal never
  takes the note's words, and never stops, closes or clears anything else.

  `LiveInk` holds Esc as a Carbon hotkey on plain Esc (`HotKey`, no permission needed) only while
  `LiveEscape.next` has a step, and lets it go at once when it has none, so Esc is the frontmost
  app's again. Esc that reached a terminal would interrupt the agent running there. Live ink never holds it
  while the stack or the annotator holds the screen, since they use Esc, while the note's target menu
  is up, which closes on Esc and gives the note's field the keys back, or while live ink is off.
  Whether to hold the key is decided before each wait of the main run loop (`LiveInk.holdEscape`, a
  `CFRunLoopObserver`), so it follows every change to what the snapshot reads without each change
  having to report it. A held key takes the press before any window sees it (measured: with the note's
  field key, one press reached the hotkey alone), so the note's and Reply's `cancelOperation:` reach
  `LiveInk.escape` only when the key does not take it: a press in the moment before the key is held,
  or a key that registered but never fires, since `RegisterEventHotKey` answers success for a key
  another app already holds (the `HotKey` comment). Each press logs
  `[live-ink] esc <step>`. `[state] liveInk.escape` is the next step or null, and `escapeHeld` says
  whether the key is held. Several `HotKey`s can exist at once: one Carbon handler hears every
  hotkey's events and hands each to its own key by id.
- Inking never covers the stack or the annotator. The chord does nothing while
  `ThumbnailController.holdsScreen`, and either coming up while it is held ends the inking
  (`onTakesScreen`). A chord let go mid-stroke keeps the overlays raised until the button is up,
  read from the button's state as well as the release.
- The chord is `HeldChord`, a pure value with tests: exactly its pair, ended by any key or another
  modifier, and not begun again until its modifiers are let go, so a window manager's ⌃⌥-arrow
  never inks, and neither does letting go of ⌘ out of ⌘⌃⌥. A key another app takes as a shortcut
  reaches no event monitor (measured with a Carbon hotkey), so `ModifierChord` reads keys from the
  HID state, every 50 ms while the chord is held. It has no hold threshold; the pointer field
  waits `ui.liveInkFieldDelay` instead, or shows at the first press. An overlay never becomes key. Erasing
  is a tap on a mark with the chord held, not a key: Vignette sees a key but cannot keep it from the
  frontmost app, where ⌃⌥⌫ deletes a word.
- While inking, the pointer field says the screen takes ink (`PointerField`, a Metal layer under
  the marks; `docs/live-ink-cursor-2026-10-10.md`). It is a ring round the pointer.
  Nothing follows the pen while it draws: a wake that rippled the screen behind the stroke was
  removed on 2026-10-12 as too much. The default style is Lamp, a soft pool of light in the ink's
  colours, the ice over dark content and deep blue over light, that breathes, brightens with the
  pointer's speed and has light drifting inside it
  (`docs/live-ink-lamp-and-stroke-colour-2026-10-12.md`). It is the only style: the other five (Glass,
  Lens, Squircle, Droplet and Caustic) were removed, with the screen picture they bent. The lamp
  draws no picture of the screen, so the field never starts Screen Recording.
  It is centred a little below and right of the arrow's tip, round the arrow's middle, and macOS
  draws the real arrow above it. It grows in as it shows, tightens and brightens while the button
  is down, and stretches along the way it moves. Each refresh the field reads the pointer and the
  button from its display link (`NSEvent.mouseLocation`, `LiveInkTap.isButtonDown`), so the
  ring is sprung towards where the pointer is then, not where the last event put it. Its motion is
  a pure value, `PointerFieldMotion`.
- The field fades in from its first frame. It draws only from its display link: drawing on each
  frame's arrival starved the main thread until the app hung. The ring has a layer only as big as it
  can reach, moved with it and presented in the same transaction, so a frame draws a few hundred
  points square rather than the screen. Its numbers are in the Pointer section of Tweak UI
  (`ui.liveInkField*`, `ui.liveInkLamp*`).
  `LiveInk.holdField` is the one place that holds the field up: on the surfaces taking ink while
  the chord shows it. An overlay closes only once its
  field has faded out (`PointerField.whenHidden`).
- Marks are `Mark`s in global top-left points at a `pointScale` of 1. `InkStroke` reads a stroke: a loop is the ellipse round it, and any other stroke the editor's freehand arrow
  (`Mark.Arrow.freehand`, at the editor's tolerances). A stroke under `ui.shortestArrow` is a tap,
  which erases the topmost mark whose stroke it is within `LiveInk.eraseReach` of, measured as the
  editor measures (`EditorGeometry.strokeDistance`), or else the smallest ellipse it is inside. The
  reach is wider than the editor's, since nothing shows which mark a tap would erase.
- The person's marks are ink (`InkMarkLayer`), and so is the stroke being drawn, on every screen it
  crosses. Ink is a filled outline whose width follows the hand: wider where it slowed, read from
  the spacing of the pointer's events before smoothing (`InkHand.stroke`). It tapers where the pen
  landed and, on a loop, where it lifted. The pen keeps `ui.inkLengthDiagonals` (2) diagonals of the
  screen the stroke began on, about 3600 pt on a 1512 by 982 pt screen, so a loop can go round as much
  of a large screen as of a small one. Past that the start recedes as the pen goes on, tapering where
  it now starts, and the mark is made from what is still drawn (`InkHand.trailing`).
  The pen's layer then draws only that part of its settled line and shrinks to it. A gel layer's
  resize goes in the same transaction as the drawing for its new size (`InkMarkLayer.changingGel`):
  a resize committed on its own put the old drawing over the new frame for one refresh, a flash of
  the whole line each time a pen's layer grew a step (measured 2026-10-25). Its edge is
  darker than its middle, it casts a soft shadow, and while it is wet a lighter streak trails the pen. On release the stroke settles onto the
  shape it became on a spring (`InkSettle`), each point keeping its width, so the ellipse or arrow
  still looks drawn by hand. `ui.inkSettle` is the spring's length and `ui.inkSettleBounce` how far
  it swings past the shape. The line's end lets go first, and its start `ui.inkSettleStagger` later.
  A shape that changes while the line settles, as a tweak can change it, adds its own offset, so the
  line carries on from where it is. `LiveInk.hands` keeps each mark's `InkHand`, its widths and
  where each point sits on the shape, for as long as the mark is on the screen. A mark no hand drew,
  such as an answer's mark the person picked, gets an even hand that starts at its upper left
  (`InkHand.even`) and draws itself on.
- An agent's rectangle, ellipse or arrow is drawn as light, not ink (`LightMarkLayer`): a core that
  is lighter along its middle, a bloom cast by two shadows, and while it draws itself on, a glint
  at its head. The bloom settles over `LiveMarksLayer.lightSettle` once it has drawn on. The overlay
  cannot add light to another app's pixels, so the window behind decides the form. The ask's
  capture keeps a coarse grid of its luminance (`LivePacket.Luminance`). A shape whose surroundings
  average 0.45 or less (`LivePacket.Luminance.dark`) gets a white core, a rim of its colour and a glow;
  over a lighter window its core darkens towards the edge and the bloom tints what is behind. A
  tap would make it the person's, so while the pointer rests on it the light gives way to the
  person's ink. The person's marks stay ink, so the material says who drew a mark as the colour
  does (`docs/live-ink-look-2026-10-07.md`).
- While an ask waits, for the responder or for its turn, the ink and the note it is about carry the thinking light
  (`LiveMarksLayer.think`): a 40 pt band of light runs along each stroke every 1.15 s, and a sheen
  crosses the note a third of a beat later. Every band counts from one start, so marks that began
  waiting at different moments move together. The light fades in and out over 0.2 s. With motion
  off the ink brightens and holds. A popover waiting on an answer, the sent note and then its
  conversation, carries the light round its rim (`RimLight`): a soft light that leaves from under the
  arrow and goes round clockwise once every two beats, seen through a thin ring at the body's edge
  and a fainter, wider one for its glow. It is white on a dark popover and the ink's light colour
  (`ui.inkGelLight`) on a light one, where white would not show. It keeps time with the band on the
  ink, so the note and the conversation that takes its place show the light at the same point.
  With motion off the whole rim glows at 35% and holds.
- `vignette://live-ink-clear` erases every mark, and `live-ink-stroke?points=x,y;x,y` (debug) takes
  a stroke as if by hand, whether the stack is up or not, so a script can test without posting
  input; it answers what the stroke did. `[state]` has a `liveInk` section: `on`, `inking`, `chord`, `pair`, `claude`,
  the surfaces with their frames, whether each is on the active Space and how many marks it has, and
  every mark once with its frame.
- Ink no ask has been about always has its note, `LiveNotePopover`, a macOS popover. There is one
  note for all of that ink, since what is typed applies to all of it (`LiveAsks.noteInk`: drawn or
  picked, and taken out of the note by an ask about it). Letting go of the chord after drawing opens
  it, hung from the newest ink. Drawing more while it is up keeps the same note, with its words, its
  target and its caret, and slides it on a spring to hang from the newest ink, as a
  reply slides between stops. The note leaves only when its ink does: Return asks about it, Esc takes
  it back, or it is erased, cleared, gone with its window, or live ink is turned off. While the stack or
  the annotator holds the screen, the note hides and lets go of the keys (`LiveNotePopover.standAside`).
  It comes back as it was, without the keys, once they are gone (`LiveInk.bringNoteBack`). That is
  checked before each wait of the main run loop, as Esc's hotkey is. A click elsewhere takes the keys and leaves the
  note where it hangs, inactive: its glass draws as macOS draws a window that is not key, the caret
  goes, the words dim to 55% and the ↩ fades, since Return does nothing until the note has the keys
  again. A click on it, or the chord let go, gives them back with the caret where it was, and the
  list of targets is read again, so a session started meanwhile is there; a target picked by hand
  stays (`DestinationChoice`). A chord cut short by a key, as a window manager's ⌃⌥-arrow is
  (`HeldChord.Change.interrupted`), gives the note the keys only when ink was drawn. The note hangs
  from a view of the overlay that draws its newest ink (`LiveMarksLayer.hang`), as a reply does, so it
  moves with that ink's window, the windows in front of it cover it, it stays on its Space, and it
  fades as the ink fades with a minimised window (`LiveNotePopover.follow`). The note and the reply
  are both a `HangingPopover`, which owns where a popover hangs: its host view, edge and mark, the
  slide, the fade with its mark, and showing it again when its window comes back. It follows the system's
  appearance. Its window is a non-activating panel, so its field takes the keys while the app the
  person was in stays in front. Closing it while it has them gives the keys back at once
  (`letGoOfKeys`), because AppKit counts Vignette as active while the field has them. A press with
  Control held makes Vignette the frontmost app even on a non-activating panel (measured on macOS 15:
  the chord's press activated it, and the same press without modifiers did not). The tap's presses
  reach no window, so inking leaves the app the person was in at the front. Only when macOS refuses
  the tap does each press of the chord activate Vignette. The keys go back through `FocusReturn`, as the annotator's do: to the Vignette window
  that was key when the chord went down (`sessionStarting`), or else to the app the person was in:
  activated when Vignette is frontmost, and by Vignette letting go when that app still is, since
  activating a frontmost app leaves the keys where they are.
  The note does it when it closes or loses the keys, and inking that leaves the note without them
  does it when the chord is let go (`[focus] live ink …: returned to …`). Under the words
  is its target: the agent's logo and the project, on a button that opens the list of targets, as
  Down does. Return asks about the ink no ask has been about, or, with none, about the
  ink asked about last. A follow-up from an answer's button or its Reply field is about the ink asked
  about, never the note's ink, and the note stays with its words. Esc, while the note has the keys,
  discards it: it closes, and its ink goes. ⌘⌫ deletes the typed line, as in any text field. Its target starts on the one picked last, else the
  responder, and lists the sessions Send lists after it. Tab picks the next target in that list and
  Shift+Tab the one before, round from either end, without opening it. Down opens it. Return settles the note into the look of
  the conversation over 0.18 s (`NoteContent.settle`): the target's button loses its background and
  chevron, its label greys, the ↩ fades and the rim light starts. The conversation, the reply's
  popover, then comes up over it at the same size with the same pixels, and the note goes three
  display refreshes later (`LiveNotePopover.handOver`, `WindowRemoval`). The note's alpha drops to
  0 in the commit that shows the conversation, because two glass popovers over each other darken for
  the frame they share. On the screen the person's words stay in a popover and never turn into a
  drawn note; a card still draws them as a note tag. For a session the conversation leaves with the
  ink, as a card (below). A session can take the note before the handover is done (about 40 ms in
  the VM). The handover then stops, and the note itself leaves with the ink, on the conversation's
  timing (`LiveMarksLayer.popoverLeave`).
- Vignette picks the side the note hangs on, where a hand writes one (`LiveAnswerLayout.noteHang`):
  from an arrow's tail on the side away from its head, or off a loop's or a box's side, right first.
  The popover is a window of its own, so it may hang past the window's edge onto the rest of the
  visible screen. It keeps clear of the person's ink and notes, and may cover the window's text
  beside the ink, because a note away from its ink reads as being about something else. AppKit
  flips a popover whose side has no room, without knowing where the ink is, so Vignette chooses the
  side before the popover shows. Below or above its anchor, AppKit also slides the body sideways to
  keep the popover's window inside the visible frame. The window reaches 13 pt past the body
  (measured on macOS 15). `PopoverPlace.body` slides it the same way, so the layout knows where the
  body lands. A scene with no screen keeps the note inside its room, and there AppKit would not
  slide it, so the arrow moves along the ink's side to where the body fits (`PopoverPlace.hung`).
  Setup's live ink page uses this, and it plays a real note with no hand. The page hangs it through
  its stage's `LiveMarksLayer.hang` with `takingKeys: false`, so the setup window keeps the keys,
  gives it targets through `setSessions`, and `put`, `step(backward:)` and `send` fill in its words,
  step its target and ask. The note opens out
  of sight, placed from the ink alone. It moves, before it shows or as it slides to newer ink, once
  `LivePacket.Glance` gives the window's frame and text, about 20 ms after the capture (Vision's fast
  level, for where the lines are, not what they say), and shows after 0.8 s without it. The list of
  targets opens under the target, or beside the note when the screen has no room below, so it never
  covers the words. Beside the note it can cover some of the ink while it is open.
- With `liveInkSpeech` on, live ink listens while the person draws
  (`docs/live-ink-speech-input-2026-10-06.md`). Listening starts when the pointer field shows, so the chord on
  its way to a shortcut never turns the microphone on, and a press of the chord while it listens goes
  on with the same listening, so "this" and "that" drawn in two strokes are one note. The note opens
  on release with what was said so far and fills as the person talks. A key typed in it ends
  listening and keeps the words; Esc, an ask and clearing drop them. Standing aside stops listening,
  and the note keeps what it heard. Words already in the note when listening starts stay, and what is
  said then does not replace them. `ListeningEnd`
  decides the end: listening stops 0.3 s after the chord is let go, and never past 60 s. With `liveInkSendWhenQuiet`, the final words are sent as Return sends them. Speech is
  turned into words on the Mac only: `Transcriber` is the interface every engine conforms to,
  `SpeechEngine.make` picks one, and `AppleTranscriber` refuses to run without an on-device model
  rather than send audio to Apple. The Settings switch asks for the microphone and speech
  recognition; nothing else does. `[speech]` lines log listening, and `[state] liveInk.listening`
  says whether it is.
- Every ask's picture numbers the person's strokes in the order drawn, with a badge beside each
  (`LivePacket.numbers`), and the responder's ink carries the same `n`. A spoken note sent as it was
  said gets `[n]` after the word said as stroke `n` was drawn (`SpokenNote.marked`, from
  `strokeTimes`), for the agent only; the note on screen keeps the person's words.
- A note sent to a session leaves the window as a card (`docs/live-ink-note-cards-2026-10-08.md`,
  ADR 0023). Send gets one line that names the app, the window and its URL, with the picture the
  responder would get: the window with the ink drawn in and its strokes numbered. The card is the
  window without the ink, written to the watch folder as `Live ink note <date> at <time>.png`
  (`LiveNoteCards.send`), with the person's ink and words as its drawing
  (`LivePacket.drawingMarks`), so it opens, copies and sends again like any drawn-on screenshot.
  Copy on capture and Draw on capture leave it alone, as they leave an `add`, and the card shows the
  send as a send from the editor does. Once the request is stored, the card slides into the corner
  as a new screenshot's card does, with the drawing on it from its first frame
  (`ThumbnailController.show(_:drawing:)`), and the ink on the window undraws. It does not fly from
  the window: a flight from a whole window moves most of the screen at once, which disorients
  (Pete, 2026-10-10). A send refused before the request is stored
  takes the file back, and the ink stays, with the reason beside it.
- Each note's turn is read twice a second, once per session per tick (`LiveNoteCards`), off the main
  thread. A Claude Code session's comes from the `turn` file the plugin's hooks write in the inbox it
  was listed from (`ClaudeCodeConnection.turn(of:)`, `AgentDestination.inbox`), only while that inbox
  is live and holds that session. A Codex thread's comes from its rollout, the file its engine
  appends each turn's start and end to (`CodexTurns`), read from its size just before the send,
  until the line shows as a user message and its turn ends. `thread/read` names the file again when
  it stops growing for 30 s. A rollout shape `RolloutTurns` does not know reads as no turn
  (`[live-ink] codex rollout … unreadable`). A tick due while the last one's reads run is skipped,
  and each tick's readings reach the waits as one input. Clearing the ink or drawing a new note
  leaves it running. Vignette stops waiting 3 minutes after the session takes the request when it
  sees no turn start, 30 minutes into a turn it saw start, or 30 minutes after the ask while the
  request is still queued (`TurnWatch`). `[state] liveInk.watching` counts the notes watched. One
  pure value, `NoteCardGroups`, holds every wait and groups the notes that end in one reading on one
  window. `NoteCardWait` decides each note, in any order of its reply, its turn's end and its
  delivery.
- A session's answer with `scripts/reply --answer`, words and up to four marks that each name words
  on the window (`LiveAnswer`, in the reply's bundle), becomes the note's result card
  (`LiveNoteCards.answer`): the window captured afresh, since the session has usually changed what it
  shows, with each mark at the words it names in that capture (`ResultCard.marks`). It finds them by
  the rule the screen uses for an answer's marks (`AnswerMark.target`). A ring keeps room round the
  words, and an arrow is the one the screen would draw (`LiveAnswerLayout.arrows`), ending at the
  words themselves and covering as little of the capture's text as it can. In a
  browser the labels and words keep to the page (`LiveAnswer.Canvas.page`), off the toolbar and
  tabs. An arrow may cross the toolbar, as on the screen, since above a word in the page's first
  line is often the one way to it that crosses no other text. The labels
  go beside their marks and the words beside the first mark, or beside the ink when no mark was
  found, each measured as the card sets it and placed where it covers the least of the rest and of the
  text Vision read in the capture (`AgentMark.note`). How many marks there are
  never depends on that measuring, since a reply's stored drawing is checked against the count after
  a relaunch. The card is from the session: `LiveNoteCards` records the
  agent and the session on it as an `add` does, so it wears the agent's tab and Reply on it goes
  back there (`Agent.origin`). A Codex thread goes in the thread attribute, as a Codex push's does
  (`Agent.record(origin:)`). The reply's stage is then `shown`, with no file of its own. A window off the screen,
  or a relaunch since the note went, makes the reply a card on the picture the session was sent,
  with a ring or an arrow for each mark that gave a box (`Reply.cardMarks`), laid out the same way
  on that picture (`ScreenshotRequests.Callbacks.cardCanvas`).
- A card live ink makes draws its marks at full size, however small the window
  (`UITweaks.liveInkMarkScaleRule`). A screenshot's marks shrink when it is smaller than the screen
  (`docs/mark-scale-2026-10-27.md`). A live ink card shows the window as live ink drew on it, at
  the screen's own size. Its marks are laid out in the capture's points at the capture's scale
  (`ResultCard`, `cardCanvas`), so the layout and the drawing must use the same point scale. A note
  card's drawing is made at mark scale 1 (`LiveNoteCards.send`). A result card's and a reply card's
  are made by the rule. An agent's note on any card keeps the floor every agent's note has: a model
  that resizes the card reads its text at no less than `ui.smallestNoteText` px.
- When a session's turn ends with no reply, Vignette looks at the window again (`LiveNoteCards`,
  `LiveChange`).
  - **The before picture.** The note's own capture gives the part of the window round the ink: the
    ink's shapes with 64 pt round them, inside the web page when there is one (`LiveNoteCards.before`).
  - **The comparison.** At the turn's end it captures the window twice, half a second apart, and
    compares that same part of the window on a grid of 3 pt cells of colour. A cell counts when its
    red, green or blue moved more than 24 of 255 and did not move between the two later captures.
    That leaves out a caret or a spinner. Grey alone missed a green button turned red, since the
    two are about as bright. Only the cells under the ink, its shapes with a 12 pt margin, decide.
    The ink's part changed when at least 2% of those cells counted, and at least 4.
  - **Changed.** The window as it is now becomes the result card, from the session
    (`[live-ink] result card`, with `notes=` for the notes on that window it answers). The notes it
    answers say nothing more, whether or not their own part changed, and each takes a late answer
    on the card. An answer that comes after it, for as long as a turn may run (30 minutes), is
    drawn on that card, each mark at the words it names in the card's picture,
    with no page to keep the words to. It joins the card's drawing rather than making a second card.
  - **Unchanged, or can't tell.** No result card. The note's card says Done in *project*
    (`[live-ink] done with no result card`). A window that closed, was minimized or changed size
    can't be told.
  - **Vignette stopped waiting.** Nothing more. The card already said Sent to.
  - **One known gap.** The part compared stays at its place in the window. So content the session
    moved away counts as a change there, and so does content the person scrolled.
  - **The log.** `[live-ink] landed changed=` or `[live-ink] nothing changed under the ink` gives
    the outcome.
- Asks go to the responder one at a time, in the order sent, in the same conversation, so each
  knows the ones before it (`LiveAsks`, `Effect.send`). Each takes its picture as it is sent, so it
  shows what the person circled then, and waits with its ink carrying the thinking light until the
  ask before it has answered, failed or been stopped (`[live-ink] waiting`, then `sending`). `LiveInk`
  holds what each waiting ask will send (`LiveInk.held`). A note to a session waits for none of them.
  Every answer stays beside its own ink until its own × or Esc closes it, and a new ask takes none
  off. The × finishes its answer and the ink only it was about: ink another answer on the screen is
  about stays. On the ask the responder is answering, the × also stops the responder's turn, so the
  next ask goes at once and no turn is spent on an answer nobody will see. A new reply, its marks
  and the next note keep clear of the answers already up, which `LiveInk.scene` adds to the
  person's notes as things to avoid. Only one answer's focus or steps run at a time: a newer
  answer's take over. However an ask ends, `LiveAsks` says so first (`Effect.ended`).
  `LiveInk.release` then lets go of what was kept for it: what it would have sent, its note, its ×,
  its buttons, and its steps or focus. The responder holds at most one ask it has not sent: during
  its warm-up, or until an interrupted turn ends (`LiveResponder.pending`). Clearing the ink ends
  every ask, those waiting too, and stops the responder, which drops the ask it holds with no answer
  and no failure.
- An ask is answered by `LiveResponder`: one `claude -p` process in stream-json mode, run with
  `--safe-mode --tools ""`, its own system prompt, and `--json-schema` for the answer
  (`LiveAnswer.schema`, fixed text that lists `say` first, the field that streams in as the reply).
  Started plainly, the process registered itself as a session in Vignette's
  inbox and could read files, so those flags are the isolation, and the process stops before any
  screen content is sent unless its `init` line lists no tool but `StructuredOutput` and no MCP
  server. It starts as a stroke moves, for a note aimed at Claude, and sends a short warm-up ask ($0.001 to $0.01) that checks
  that line and caches the prompt. `docs/live-ink-ask-cost-2026-10-06.md` has what an ask costs and
  why. It runs on Claude's 5-minute prompt cache (`CLAUDE_CODE_PROMPT_CACHE_TTL=5m`) and stops 4.5
  minutes after its last request, since an ask after the cache ends would write the whole
  conversation again. It also stops when the ink is cleared or live ink is turned off, and starts a
  new conversation after 12 asks. Esc stops one turn and keeps the conversation: `cancel()` writes a
  `control_request` with `subtype` `interrupt`, which ends the turn within milliseconds and keeps the
  process (measured on Claude Code 2.1.302). The turn then ends with a `result` that has `is_error` true
  and `subtype` `error_during_execution`, which is not an answer or a failure. Its deltas and its result
  are dropped, nothing new is sent until the result arrives, and the process stops if it takes more than
  3 s. The warm-up is never interrupted. In a test launch it runs only the `claude` that
  `VIGNETTE_CLAUDE` names, since any other runs on the person's account;
  `scripts/e2e/fake_claude.py` stands in for it. In `[live-ink] answered … marks=<n> thrownOut=<n>`,
  `thrownOut` counts the marks the responder gave that point at nothing, such as a box in pixels
  rather than thousandths. They are thrown out as the answer is read, before `drew answer` counts.
  A session's answer is read strictly instead (`LiveAnswer(json:strict:)`): the reply helper
  refuses one with a mark it would throw out and names the mark, since the session can fix it. A
  mark whose words are not found on the window falls back to its box (`AnswerMark.target`), and is
  left out without one, counted in `drew answer … dropped=<n>`. Once the answer is drawn, on the
  window or as a card, Vignette writes its receipt again with `notDrawn`, the indexes of the marks
  left out, and the helper, which waits up to 5 s for that, prints them with their words.
- `LivePacket` is the ask's content, built in about 300 ms: a ScreenCaptureKit capture of the
  topmost window under the ink below the Dock's level (the Dock has a window over the whole screen at
  its level), Vision's accurate text lines read before the ink is drawn in, with ids, the person's
  ink drawn into the picture and listed as boxes, and the app, title and the Accessibility document
  or web area URL. An ask sends the pictures, then the lines of the window's text nearest the ink, up
  to 4,500 characters, as plain lines (`t2 12 34 640 14 words`: id, box, words), then the rest as
  JSON, so the note comes after the long parts. Boxes are in
  thousandths of the picture both ways; as JSON objects the same lines cost nearly twice the tokens.
  An answer names a line by id only among those sent, and other text by its words or a box
  (`docs/live-ink-ask-cost-2026-10-06.md`).
  Ink asked about on more than one window, or on a window and on none, gets a picture of the screen
  instead. So does ink over a window above the status bar's level, such as an open menu, because a
  window's own capture leaves the menu out. The picture then covers the menu as well. The note's ink
  is planned and captured as its last stroke ends, while the menu is still open. An ask about that
  same ink uses that plan and capture. `LivePacket.Plan` decides which picture an ask gets, and
  `Tests/LiveInkTests.swift` tests it. The screen's picture is the
  part of the newest ink's display that those windows' frames cover. It is captured as the person
  sees it, without Vignette's windows, with every stroke drawn in and numbered. A stroke is covered
  when a normal window in front of its own window overlaps it. A window of the stroke's own app
  covers it only when it is at least 200 by 200 pt (`LivePacket.ownAppCoverSize`), since an app's
  sheets and title bar windows sit over its own window. A stroke is outside when it is past that
  display. Each window that holds a covered or outside stroke is also sent alone, with its
  ink drawn in and numbered as in the screen's picture. The JSON's `alone` says which strokes each
  of those windows holds, and which of them are covered or outside. The answer's marks go on the
  screen's picture only, each pinned to the window under it (`LiveInk.put`, `eachOnItsWindow`). The
  responder is told to say in words what it finds at a covered stroke. The text lines are Vision's
  reading of the screen's picture, so they hold only what the person can see. No page or URL is
  read. A note to a session gets the screen's picture, and its line says which strokes a window
  covers. The person's ink is kept in the order it was drawn, across windows (`LiveInk.shownMarks`).
  That order numbers the strokes and decides which is the newest.
  Ink across a line garbled what Vision read of it, and the fast level garbled code
  (`docs/live-ink-step2-spike-2026-10-04.md`). A follow-up to the same window showing the same text,
  in the same conversation, sends no picture, only the nearby lines not sent yet. Capturing needs Screen Recording, which the switch asks
  for when turned on (`ScreenRecording.request`, macOS's own alert, once); a row under the switch and
  the menu's first item open its pane. On macOS 15 the first capture also raised macOS's "bypass the
  system private window picker" alert.
- The answer streams in: `say` shows as the reply as its words arrive (`LiveAnswer.partialSay`).
  The reply is a popover from the overlay it is drawn on (`ReplyPopover`), and for an ask with words
  it is the conversation the note became: the person's question where the note's field had it, then
  a row with the agent's logo and the name where the note's target had them, then the reply's words
  under the row. `ReplyContent.layout` and `NoteLayout` share every size, so the question and the row
  do not move when the note hands over or when the answer comes. The question greys once the answer
  has words. A follow-up puts its words in as the question and empties the answer. The conversation
  is the note's width, 300 pt, or as wide as its buttons. It has no backing: it keeps the note's
  translucency. Its words take the glass's vibrancy, as the question's label does, so over a dark
  window they stay darker than the greyed question (`docs/live-ink-conversation-2026-10-17.md` has
  the contrast). `Mark.quote` keeps the question and `Mark.answerer` the row's name, which for a
  session is the title the note's target showed; neither is written to a file. Beside its ink, as
  on any side edge, AppKit keeps the body centred on its arrow, so a conversation that grows
  downwards also rises. A whole
  answer with no reply up yet hangs the reply from its first pointing mark, off the middle of a
  circle's or a box's side or from an arrow's tail, so the words lead along the mark to what it
  points at. That mark's label is placed with the reply, so neither covers the other. An answer that
  points at nothing, an answer in steps, and a reply that streams in hang it from the person's ink.
  A reply already up, a conversation or a streamed reply, stays where it hangs as it grows
  (`LiveAnswerLayout.grown`). It is tried below, above, right and left of what it hangs from, and
  may hang past the window onto the visible screen (`Scene.screen`). The reply is still a text
  `Mark`, with where it hangs in `Mark.popover`, so it follows its window, a tap erases it, and
  Clear clears it. Its window lets every click through, as a note on the overlay does. The answer's
  × and actions are panels of their own, child windows of the popover's window
  (`ReplyPopover.carry`), so they take its layer: a window raised over the answer covers them, and
  they move with it. On macOS 15 a button inside the popover took the person's keys from their app
  (`docs/live-ink-look-2026-10-07.md`, step 6). The buttons are the answer's actions, then Reply,
  as AppKit's push buttons (`LiveAnswerActions`). macOS draws them as it draws controls in an app
  that is not frontmost, which Vignette never is while an answer shows, so none is filled with the
  accent colour. The reply is never narrower than the row, or than the field with Cancel (`ReplyContent.size`'s
  `foot`, from `LiveAnswerActions.room`). Reply
  gives the row's place to a field and Cancel in the same panel, which takes the keys only while the
  field is up, as the note does. Return sends what was typed; Cancel, Esc (the Esc rule below), Return with nothing typed
  or a click elsewhere puts the buttons back. The field keeps its words when it closes, and the next
  Reply opens with them; a send clears them. The words belong to the answer (`LiveAsks.Ask.draft`),
  not the panel, since the panel goes whenever the reply is out of sight, as when its window is
  minimized, and comes back with it. An action's click and a typed reply are one follow-up (`LiveInk.respond`):
  every button is disabled, the one used gains a checkmark (`LiveAnswerActions.pick`), and the reply
  quotes the person's words and carries the thinking light with the answer's marks. The responder
  takes them as a follow-up ask. The next answer takes the reply's place where it hangs, with
  buttons of its own. While the next reply streams, the earlier answer's other marks are set aside
  (`LiveAsks.Effect.setAside`, `LiveWindows.setAside`): they are hidden where they are. They go once the next answer is drawn, and the × finishes them
  with the rest. A follow-up that fails or is stopped before then puts the answer back as it was
  (`LiveAsks.Effect.restore`, `LiveInk.restoreAnswer`): the set-aside marks show again,
  the buttons come back, typed words wait in Reply again, and the reply's header gives the reason
  where it quoted them (`Mark.notice`), wrapped so all of it shows. A failure after the next answer
  is drawn says why in the reply's row, as for any ask. Closing the field gives the keys back through
  `FocusReturn`, as the note does. A popover's window can be key, and macOS makes the reply's key when a panel that
  held Vignette's keys closes, even after Vignette let go; the keys would stay with Vignette and the
  glass turn light, so the reply lets go at once (`ReplyPopover.letGoOfKeys`, `[live-ink] reply let
  go of the keys`). The marks draw themselves on when the answer is
  whole (`LightMarkLayer.drawOn`). `LiveAnswerLayout` places them in global points inside
  the page (a browser's web area, from Accessibility, else the window), clear of the person's ink,
  the window's text and each other, and no note covers what the answer points at: a circle round a
  long line is a box, and a circle on a loop of the person's is an arrow. A label touches its mark
  where a hand writes one (`LiveAnswerLayout.handSpots`, which places the person's note too): at an
  arrow's tail, on the side away from its head, or against a circle's edge, with the arrow's side
  chosen for where its label fits. Later arrows come from the first one's side, with their tails
  level with its tail, so the labels stand in a column. Labels are `Mark.isLabel`, drawn without
  the agent's badge, so only the reply names the agent. Each of an answer's marks keeps its offset on
  the window it was placed on, as the person's ink does. The person's ink counts as its strokes, not
  its bounding box (`LiveAnswerLayout.strokes`), so a loop round a whole page leaves room inside it.
  An action
  may name the marks it acts on (`LiveAnswer.Action`, `{"title", "marks"}`, by index), and pointing
  at its button fades the answer's other findings (`LiveWindows.light`). They are agent `Mark`s on the same surfaces, so a tap
  erases them (a note's tag counts) and Clear clears them, and they stay until their answer's × or Esc
  closes it. Notes on
  the overlay are `NoteLayer`s, a bitmap `Mark.draw` makes on the main thread, not `MarkLayers`,
  which draws a drawing on an image. The reply is the exception: its popover draws it.
- An answer's `focus` mark pulls the person's eye to its target, as a camera racks focus
  (`LiveFocus.swift`). It draws no stroke. The layout gives it the target's rect, padded 8 by 6 pt,
  or with `zoom` the lens's rect, so labels, the reply and the other marks keep clear of it and the
  reply can hang from it. When the answer is shown, Vignette captures the window once, without its
  own overlays, and `FocusPicture.make` softens it off the main thread. Rack focus blurs the window
  5 pt, keeps 20% of its colour and dims it 10%, or 35% on a dark window. A mask cuts the target out
  of that picture with an edge that softens over 16 pt. The loupe blurs the window lightly, dims it
  22%, or 45% on a dark window, and shows the target at 1.7× under a lens with a rim and a shadow.
  The picture sits under every other mark, so the person's ink, the labels and the reply stay sharp.
  Several focus marks make a tour. One shows at a time, and the next comes in before the last goes.
  Each holds for the reply's sentence about it, read at 0.3 s a word, at least 2 s; the last holds
  at least 2.5 s and then lets go. The reply moves to hang from each stop, with that stop's label
  put back beside it (`LiveAnswerLayout.placed`'s `tour`). It keeps its side when it can and
  slides there on a spring over 0.45 s (`ReplyPopover.slide`), since AppKit moves a popover in one
  frame when its positioning rect changes; it stays at the last stop when the tour ends. While a
  stop shows, the window's other marks fade to 20% over 0.18 s (`LiveInk.lightStop`): all but the
  stop, the reply, and the person's ink centred on the stop's target or round it; ink that only
  grazes it, as a loop round the next line does, fades. `LiveWindows` keeps each mark's strength,
  so a mark hidden with its minimised window comes back faint. They come back when the
  focus lets go. The focus
  lets go at once on a key, a click, a scroll, the ink chord, or the pointer moving 120 pt from
  where it was when the focus came in. A key is heard only while Vignette is trusted for
  Accessibility, which the chord already needs. A focus comes in over 0.45 s and leaves as every
  answer mark leaves (`LiveMarksLayer.removalFade`). A tap erases it. In an answer in steps it is a
  circle, since a step is something to click. It is a circle too on no window, such as the desktop,
  since there is no capture to blur, and when the capture fails every stop shows at once as a
  circle with its label (`LiveInk.showUnfocused`). `Mark.focus` carries the target and the picture and is
  never written to a file. A mark pinned to a window moves into the window's coordinates with its
  focus (`LiveWindows.translated`). `[state] liveInk.focus` names the stop shown and whether it
  zooms, and `[live-ink] focus` lines log each stop and why the focus let go.
- Vignette's own words about an ask (a failure and why) go in the conversation's row, after the
  name (`Mark.notice`, `LiveAsks.Effect.notice`), and wrap there. A reason whose subject is the
  answerer, such as "Claude couldn't answer", goes on from the name in the row instead of repeating
  it. "Claude Code isn't signed in" names something else and follows a dot.
  An ask with no conversation says it in a reply of its own hung from its ink, which is that ask's
  answer, with its own ×. It is not ink: the next ask is not about it.
- A session picked in the note's target gets the picture through `ScreenshotRequests.send`, as Send
  sends a drawing, with the words and where the ink is in the line. The client's answer goes to the
  note's card, as a send's does.
- `live-ink-ask?message=` (debug) asks as Return does, and `&session=<id>` sends to that session.
  `[state] liveInk` adds `new` (ink not yet asked about), `note`, `reply` (the newest ask's reply
  popover's frame while it is up), `actions` (each button's words,
  frame, and whether it is enabled and picked, for the newest answer with buttons), `replyField` and `replyCancel` (that
  answer's field's and Cancel's frames while they are up),
  `responder`, `asks` (each ask, oldest first: its id, phase, how many marks it is about, whether
  it sent a picture, whether it went to a session, why it failed, and the reply's length), `ask`
  (the newest of them), `queued` (how many asks to the responder wait for an earlier one), `escape` and
  `escapeHeld`, and each mark's
  `id` and `agent`. A script that polls asks for `state?section=liveInk`: the whole report runs to tens of KB, and twice a second it rotated the 5 MB log twice in one take; `app.screenRecording`
  says whether captures are allowed. A test launch with `VIGNETTE_SHARE_LIVE_INK` set lets captures
  see the overlays, so a script can look at what was drawn; the overlay rests under floating
  windows, so a test window that floats keeps the ask on it and must be lowered to be looked at.
