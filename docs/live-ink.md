# Live ink

Live ink is drawing straight on the screen, over any app, while Control and Option are held, and
asking an agent about what was drawn. This file has its rules and says where each part of it lives.
`docs/live-ink-integration-2026-10-04.md` has the plan, and the dated `docs/live-ink-*.md` notes
have the measurements.

## Where the code is

The names in brackets are `// MARK:` sections.

| To change | Look in |
|---|---|
| The chord, inking, the overlays per screen and Space | `LiveInk.swift` (Inking, Surfaces), `LiveInkOverlay.swift`, `ModifierChord.swift` |
| What a stroke becomes, and erasing | `InkStroke.swift`, `LiveInk.swift` (Strokes) |
| The note: opening, placing, sending, waiting on a session | `LiveInk.swift` (Asking), `LiveNotePanel.swift` |
| What an ask sends | `LivePacket.swift` |
| Speaking while drawing | `LiveInk.swift` (Listening), `LiveListening.swift`, `Microphone.swift`, `Transcriber.swift`, `AppleTranscriber.swift` |
| Claude on the screen, the `claude` process | `LiveResponder.swift` |
| The answer: reading it, drawing it, steps, the quote | `LiveAnswer.swift`, `LiveInk.swift` (Answering) |
| Where the person's note, the reply, labels and pointing marks go | `LiveAnswerLayout.swift` (Pointing, Notes) |
| The answer's ×, its action buttons, pointing at an action | `LiveInk.swift` (Dismissing and actions), `LiveAnswerActions.swift`, `LiveDismissButton.swift` |
| Marks following their window, holding still, hiding | `LiveWindows.swift`, `LiveAnchor.swift` (Accessibility), `LivePatch.swift` (pixels) |

## Checking a change

- `Tests/LiveInkTests.swift` holds the unit tests: the chord, strokes, placement and anchoring.
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

- Live ink is an option (`liveInk`), and `LiveInk` owns it: the chord, and a surface per screen per
  Space, each a `LiveInkOverlay` and the marks on it. A mark drawn on a window belongs to that window
  (`LiveWindows`): it moves with it, the windows above it cover it, it hides while the content
  scrolls or resizes and comes back on its spot, and it goes when the window closes
  (`docs/live-ink-step3-2026-10-05.md`). A mark drawn on no window stays at its place on the screen.
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
  flag off and takes every press, over clear pixels too, as the matte rule in `AGENTS.md` says.
- Inking never covers the stack or the annotator. The chord does nothing while
  `ThumbnailController.holdsScreen`, and either coming up while it is held ends the inking
  (`onTakesScreen`). A chord let go mid-stroke keeps the overlays raised until the button is up,
  read from the button's state as well as the release.
- The chord is `HeldChord`, a pure value with tests: exactly ⌃⌥, ended by any key or another
  modifier, and not begun again until its modifiers are let go, so a window manager's ⌃⌥-arrow
  never inks, and neither does letting go of ⌘ out of ⌘⌃⌥. A key another app takes as a shortcut
  reaches no event monitor (measured with a Carbon hotkey), so `ModifierChord` reads keys from the
  HID state, every 50 ms while the chord is held. It has no hold threshold; the glow waits
  `ui.liveInkGlowDelay` instead, or shows at the first press. An overlay never becomes key. Erasing
  is a tap on a mark with the chord held, not a key: Vignette sees a key but cannot keep it from the
  frontmost app, where ⌃⌥⌫ deletes a word.
- Marks are `Mark`s in global top-left points at a `pointScale` of 1, drawn by `ShapeMarkLayer` as
  the editor draws them, and so is the stroke being drawn, on every screen it crosses. `InkStroke`
  reads a stroke: a loop is the ellipse round it, and any other stroke the editor's freehand arrow
  (`Mark.Arrow.freehand`, at the editor's tolerances). A stroke under `ui.shortestArrow` is a tap,
  which erases the topmost mark whose stroke it is within `LiveInk.eraseReach` of, measured as the
  editor measures (`EditorGeometry.strokeDistance`), or else the smallest ellipse it is inside. The
  reach is wider than the editor's, since nothing shows which mark a tap would erase.
- `vignette://live-ink-clear` erases every mark, and `live-ink-stroke?points=x,y;x,y` (debug) takes
  a stroke as if by hand, whether the stack is up or not, so a script can test without posting
  input; it answers what the stroke did. `[state]` has a `liveInk` section: `on`, `inking`, `chord`,
  the surfaces with their frames, whether each is on the active Space and how many marks it has, and
  every mark once with its frame.
- Letting go of the chord after drawing opens `LiveNotePanel` beside the new ink, a non-activating
  panel that takes the keys as the stack's does. It is drawn as the note it becomes, and its target
  is a chip under it. Return asks about the ink drawn since the last ask, or, with none, about the
  ink asked about last. Its target starts on the one picked last, else the responder, and lists the
  sessions Send lists after it. The words stay beside the ink as the person's own note, whichever
  target answers: the chip fades and the panel hands over to the drawn note without the words
  moving (`settle`). The note opens against its ink, where a hand writes one
  (`LiveAnswerLayout.noteSpot`): touching an arrow's tail on the side away from its head, or beside a
  loop's edge. It may cover the window's text there, and never moves elsewhere, since a note away from
  its ink reads as being about something else. Left of the ink it grows to the left. Placing it needs
  the window's frame and text, which `LivePacket.Glance` gives in about 20 ms after the capture:
  Vision's fast level, for where the lines are, not what they say.
- With `liveInkSpeech` on, live ink listens while the person draws
  (`docs/live-ink-speech-input-2026-10-06.md`). Listening starts when the glow shows, so the chord on
  its way to a shortcut never turns the microphone on, and a press of the chord while it listens goes
  on with the same listening, so "this" and "that" drawn in two strokes are one note. The note opens
  on release with what was said so far and fills as the person talks. A key typed in it ends
  listening and keeps the words; Esc, an ask, standing aside and clearing drop them. `ListeningEnd`
  decides the end: `liveInkListenUntil` is `release` (0.3 s after the chord is let go) or `pause`
  (the input under `ui.liveInkSpeechQuiet` for `ui.liveInkSpeechPause` after release), and never
  past 60 s. With `liveInkSendWhenQuiet`, the final words are sent as Return sends them. Speech is
  turned into words on the Mac only: `Transcriber` is the interface every engine conforms to,
  `SpeechEngine.make` picks one, and `AppleTranscriber` refuses to run without an on-device model
  rather than send audio to Apple. The Settings switch asks for the microphone and speech
  recognition; nothing else does. `[speech]` lines log listening, and `[state] liveInk.listening`
  says whether it is.
- An ask sent to a session goes through Send, as one line that names the app, the window and its
  URL. The person's words stay beside their ink as their own note, and both shimmer until the
  session's turn ends (`LiveInk.watchWorking`, from the `turn` file the plugin's hooks write in its
  inbox; a route that cannot tell stops after 3 minutes). A send that went says nothing more. The
  session sees its own change land, so the skill asks it to answer on the window only when pointing
  helps. It does that with `scripts/reply --answer`: words, and up to four marks that each
  name words on the window (`LiveAnswer`, in the reply's bundle). `LiveInk.showAnswer` captures the
  window the ink is on afresh (`LivePacket.build(window:)`), finds each mark's words in its text,
  since the session has usually changed what it shows, and draws the answer beside the ink as the
  responder's are drawn. The reply's stage is then `shown`, with no file. An answer that cannot be
  drawn there, because the ink was cleared, a newer ask is under way or the app relaunched, becomes
  a card with the words in its corner (`Reply.cardMarks`). `docs/adr/0021-a-sessions-answer-to-live-ink-is-drawn-on-the-window.md`
  has the reasons.
- An ask is answered by `LiveResponder`: one `claude -p` process in stream-json mode, run with
  `--safe-mode --tools ""`, its own system prompt, and `--json-schema` for the answer
  (`LiveAnswer.schema`). Started plainly, the process registered itself as a session in Vignette's
  inbox and could read files, so those flags are the isolation, and the process stops before any
  screen content is sent unless its `init` line lists no tool but `StructuredOutput` and no MCP
  server. It starts at the first inking and sends a short warm-up ask ($0.001 to $0.008) that checks
  that line and caches the prompt. It stops after 10 minutes with nothing asked, and when the ink is
  cleared or live ink is turned off, and starts a new conversation after 12 asks. In a test launch it runs only the `claude` that
  `VIGNETTE_CLAUDE` names, since any other runs on the person's account;
  `scripts/e2e/fake_claude.py` stands in for it.
- `LivePacket` is the ask's content, built in about 300 ms: a ScreenCaptureKit capture of the
  topmost window under the ink below the Dock's level (the Dock has a window over the whole screen at
  its level), Vision's accurate text lines read before the ink is drawn in, with ids, the person's
  ink drawn into the picture and listed as boxes, and the app, title and the Accessibility document
  or web area URL. Ink across a line garbled what Vision read of it, and the fast level garbled code
  (`docs/live-ink-step2-spike-2026-10-04.md`). A follow-up to the same window showing the same text,
  in the same conversation, sends no picture. Capturing needs Screen Recording, which the switch asks
  for when turned on (`ScreenRecording.request`, macOS's own alert, once); a row under the switch and
  the menu's first item open its pane. On macOS 15 the first capture also raised macOS's "bypass the
  system private window picker" alert.
- The answer streams in: `say` is drawn as a note under the person's note as its words arrive
  (`LiveAnswer.partialSay`), left-aligned with it, so the question, the reply and its actions read
  as one thread. The reply takes the note's place and the note goes: its words are the reply's
  first line, small, muted and cut to the reply's width (`Mark.quote`, never written to a file).
  Without a note, the reply goes beside the ink. It wraps at `ui.liveInkTextWidth`, and the marks draw themselves on when the
  answer is whole (`ShapeMarkLayer.drawOn`). `LiveAnswerLayout` places them in global points inside
  the page (a browser's web area, from Accessibility, else the window), clear of the person's ink,
  the window's text and each other, and no note covers what the answer points at: a circle round a
  long line is a box, and a circle on a loop of the person's is an arrow. A label touches its mark
  where a hand writes one (`LiveAnswerLayout.handSpots`, which places the person's note too): at an
  arrow's tail, on the side away from its head, or against a circle's edge, with the arrow's side
  chosen for where its label fits. Later arrows come from the first one's side, with their tails
  level with its tail, so the labels stand in a column. Labels are `Mark.isLabel`, drawn without
  the agent's badge, so only the reply names the agent. The reply follows the ink it was about, a
  pointing mark is anchored to what it points at, and a label follows its mark: marks that all
  followed the ink drifted off their targets when the session's edit moved the content under the
  ink. The person's ink counts as its strokes, not its bounding box (`LiveAnswerLayout.strokes`),
  so a loop round a whole page leaves room inside it. While the session works, and while the done
  animation plays, the marks hold still whatever the content under them does
  (`LiveWindows.holding`): following it read as the answer shifting around. An action
  may name the marks it acts on (`LiveAnswer.Action`, `{"title", "marks"}`, by index), and pointing
  at its button fades the answer's other findings (`LiveWindows.light`). They are agent `Mark`s on the same surfaces, so a tap
  erases them (a note's tag counts) and Clear clears them, and the next ask takes them off. Notes on
  the overlay are `NoteLayer`s, a bitmap `Mark.draw` makes on the main thread, not `MarkLayers`,
  which draws a drawing on an image.
- Vignette's own words about an ask (sending, sent, failed, why) are a note beside the ink in the
  person's colour without a badge, not an agent mark, and are not ink: the next ask is not about them.
- A session picked in the note's target gets the picture through `ScreenshotRequests.send`, as Send
  sends a drawing, with the words and where the ink is in the line. The client's answer goes to the
  ink (`LiveInk.delivered`) rather than a card.
- `live-ink-ask?message=` (debug) asks as Return does, and `&session=<id>` sends to that session.
  `[state] liveInk` adds `new` (ink not yet asked about), `note`, `responder` and `ask` (phase,
  whether it sent a picture, the reply's length), and each mark's `id` and `agent`. A script that polls asks for `state?section=liveInk`: the whole report runs to tens of KB, and twice a second it rotated the 5 MB log twice in one take; `app.screenRecording`
  says whether captures are allowed. A test launch with `VIGNETTE_SHARE_LIVE_INK` set lets captures
  see the overlays, so a script can look at what was drawn; the overlay rests under floating
  windows, so a test window that floats keeps the ask on it and must be lowered to be looked at.
