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
| How the person's ink looks | `LiveInkHand.swift` |
| How an agent's shapes look | `LiveInkLight.swift` |
| The note: opening, placing, sending, waiting on a session | `LiveInk.swift` (Asking), `LiveNotePanel.swift` |
| What an ask sends | `LivePacket.swift` |
| Speaking while drawing | `LiveInk.swift` (Listening), `LiveListening.swift`, `Microphone.swift`, `Transcriber.swift`, `AppleTranscriber.swift` |
| Claude on the screen, the `claude` process | `LiveResponder.swift` |
| The answer: reading it, drawing it, steps | `LiveAnswer.swift`, `LiveInk.swift` (Answering) |
| The reply's popover: its header, its words, what it is laid over | `LiveReplyPopover.swift`, `LiveInkOverlay.swift` (`LiveMarksLayer.showPopover`) |
| Where the person's note, the reply, labels and pointing marks go | `LiveAnswerLayout.swift` (Pointing, Notes) |
| The agent pulling focus: rack focus, the tour, the loupe | `LiveFocus.swift`, `LiveInk.swift` (Pulling focus) |
| The answer's ×, its buttons and Reply's field, pointing at an action | `LiveInk.swift` (Dismissing and actions), `LiveAnswerActions.swift`, `LiveDismissButton.swift` |
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
- While inking, the edge glow (`EdgeGlow`) says the screen takes ink: a thin line on each edge in a
  lighter shade of the person's colour, with a soft falloff inward that is a third as strong
  `ui.liveInkGlowWidth` points in. It is brightest near the pointer and a third as bright far from
  it. Each edge is a strip with its own radial mask that follows the pointer, so a move composites
  four thin strips again rather than the whole screen. The strips' pictures are drawn once for each
  screen size, width and colour.
- Marks are `Mark`s in global top-left points at a `pointScale` of 1. `InkStroke` reads a stroke: a loop is the ellipse round it, and any other stroke the editor's freehand arrow
  (`Mark.Arrow.freehand`, at the editor's tolerances). A stroke under `ui.shortestArrow` is a tap,
  which erases the topmost mark whose stroke it is within `LiveInk.eraseReach` of, measured as the
  editor measures (`EditorGeometry.strokeDistance`), or else the smallest ellipse it is inside. The
  reach is wider than the editor's, since nothing shows which mark a tap would erase.
- The person's marks are ink (`InkMarkLayer`), and so is the stroke being drawn, on every screen it
  crosses. Ink is a filled outline whose width follows the hand: wider where it slowed, read from
  the spacing of the pointer's events before smoothing (`InkHand.stroke`). It tapers where the pen
  landed and, on a loop, where it lifted. Its edge is darker than its middle, it casts a soft
  shadow, and while it is wet a lighter streak trails the pen. On release the stroke eases onto the
  shape it became over `LiveMarksLayer.inkEase`, each point keeping its width, so the ellipse or
  arrow still looks drawn by hand. `LiveInk.hands` keeps each mark's `InkHand`, its widths and
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
- While an ask waits, the ink and the note it is about carry the thinking light
  (`LiveMarksLayer.think`): a 40 pt band of light runs along each stroke every 1.15 s, and a sheen
  crosses the note a third of a beat later. Every band counts from one start, so marks that began
  waiting at different moments move together. The light fades in and out over 0.2 s. With motion
  off the ink brightens and holds. While a follow-up waits, after the person answers the reply with
  an action or Reply, the reply carries it too (`ReplyView.think`): its words dim to 45%, and a band at full
  strength crosses them on the note's beat. The band is the words' own opacity rather than a light
  colour, so it shows on a light popover and a dark one. With motion off the words dim to 60% and
  hold.
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
- Every ask's picture numbers the person's strokes in the order drawn, with a badge beside each
  (`LivePacket.numbers`), and the responder's ink carries the same `n`. A spoken note sent as it was
  said gets `[n]` after the word said as stroke `n` was drawn (`SpokenNote.marked`, from
  `strokeTimes`), for the agent only; the note on screen keeps the person's words.
- An ask sent to a session goes through Send, as one line that names the app, the window and its
  URL. The person's words stay beside their ink as their own note, and both carry the thinking
  light until the session's turn ends (`LiveInk.watchWorking`, from the `turn` file the plugin's hooks write in its
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
  (`LiveAnswer.schema`, fixed text that lists `say` first, the field that streams in as the reply).
  Started plainly, the process registered itself as a session in Vignette's
  inbox and could read files, so those flags are the isolation, and the process stops before any
  screen content is sent unless its `init` line lists no tool but `StructuredOutput` and no MCP
  server. It starts at the first inking and sends a short warm-up ask ($0.001 to $0.01) that checks
  that line and caches the prompt. `docs/live-ink-ask-cost-2026-10-06.md` has what an ask costs and
  why. It runs on Claude's 5-minute prompt cache (`CLAUDE_CODE_PROMPT_CACHE_TTL=5m`) and stops 4.5
  minutes after its last request, since an ask after the cache ends would write the whole
  conversation again. It also stops when the ink is cleared or live ink is turned off, and starts a
  new conversation after 12 asks. In a test launch it runs only the `claude` that
  `VIGNETTE_CLAUDE` names, since any other runs on the person's account;
  `scripts/e2e/fake_claude.py` stands in for it.
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
  Ink across a line garbled what Vision read of it, and the fast level garbled code
  (`docs/live-ink-step2-spike-2026-10-04.md`). A follow-up to the same window showing the same text,
  in the same conversation, sends no picture, only the nearby lines not sent yet. Capturing needs Screen Recording, which the switch asks
  for when turned on (`ScreenRecording.request`, macOS's own alert, once); a row under the switch and
  the menu's first item open its pane. On macOS 15 the first capture also raised macOS's "bypass the
  system private window picker" alert.
- The answer streams in: `say` shows as the reply as its words arrive (`LiveAnswer.partialSay`).
  The reply is a popover from the overlay it is drawn on (`ReplyPopover`): the agent's logo and
  name and the person's question in quotes on one line, then the reply's words, which wrap at
  `ui.liveInkTextWidth`. The window's background at 75% backs them (`ReplyView.backing`), since the
  glass alone turns dark over a dark window and left dark text at 2 to 3:1; the quote is black or
  white at 70% by appearance (`ReplyContent.quoteColor`). The person's note goes as the reply comes, and `Mark.quote` keeps its words
  for the header; it is never written to a file. A whole answer hangs the reply from its first
  pointing mark, off the middle of a circle's or a box's side or from an arrow's tail, so the words
  lead along the mark to what it points at. That mark's label is placed with the reply, so neither
  covers the other. An answer that points at nothing, an answer in steps, and a reply that streams
  in hang it from the person's ink, and a streamed reply stays where it hangs as it grows
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
  field is up, as the note does. Return sends what was typed; Cancel, Esc, Return with nothing typed
  or a click elsewhere puts the buttons back. The field keeps its words when it closes, and the next
  Reply opens with them; a send clears them. The words belong to the answer (`AskState.draft`), not
  the panel, since the panel goes whenever the reply is out of sight, as when its window is
  minimized, and comes back with it. An action's click and a typed reply are one follow-up (`LiveInk.respond`):
  every button is disabled, the one used gains a checkmark (`LiveAnswerActions.pick`), and the reply
  quotes the person's words and carries the thinking light with the answer's marks. A session gets
  the words with a fresh picture, as "… Picked under your answer on …" or "… Replied under your
  answer on …"; the responder takes them as a follow-up ask. The next answer takes the reply's
  place where it hangs, with buttons of its own, and the earlier answer stays until it is drawn. With no answer drawn, they
  go when the session's turn ends. A follow-up that fails leaves the answer as it was
  (`LiveInk.restoreFollowed`): the buttons come back, typed words wait in Reply again, and the
  reply's header gives the reason where it quoted them (`Mark.notice`), wrapped so all of it shows.
  Once the next answer has started to come in, it has replaced the earlier one, so a failure after
  that is a note beside the ink, as for any ask. A follow-up whose send to a Codex thread is queued
  or not confirmed may still arrive, so the answer stays as the follow-up left it, with the button
  checked and the thinking light on, and the header says so (`LiveInk.noteOnFollowUp`). Its ×
  shows, unlike a follow-up's still under way, since its answer may not come until someone opens
  the thread (`LiveInk.offersDismiss`). Closing the field lets go of the keys with
  `NSApp.deactivate()`: the app the person was in never stopped being the active one, so activating
  it does nothing. A popover's window can be key, and macOS makes the reply's key when a panel that
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
  the agent's badge, so only the reply names the agent. The reply follows the mark it hangs from or
  the ink it was about, a pointing mark is anchored to what it points at, and a label follows its
  mark: marks that all
  followed the ink drifted off their targets when the session's edit moved the content under the
  ink. The person's ink counts as its strokes, not its bounding box (`LiveAnswerLayout.strokes`),
  so a loop round a whole page leaves room inside it. While the session works, and while the done
  animation plays, the marks hold still whatever the content under them does
  (`LiveWindows.holding`): following it read as the answer shifting around. An action
  may name the marks it acts on (`LiveAnswer.Action`, `{"title", "marks"}`, by index), and pointing
  at its button fades the answer's other findings (`LiveWindows.light`). They are agent `Mark`s on the same surfaces, so a tap
  erases them (a note's tag counts) and Clear clears them, and the next ask takes them off. Notes on
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
  so a mark hidden by a resize or its content moving comes back faint. They come back when the
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
- Vignette's own words about an ask (sending, sent, failed, why) are a note beside the ink in the
  person's colour without a badge, not an agent mark, and are not ink: the next ask is not about them.
  The exception is a follow-up, whose failure, queued send or unconfirmed send is said in its
  answer's header.
- A session picked in the note's target gets the picture through `ScreenshotRequests.send`, as Send
  sends a drawing, with the words and where the ink is in the line. The client's answer goes to the
  ink (`LiveInk.delivered`) rather than a card.
- `live-ink-ask?message=` (debug) asks as Return does, and `&session=<id>` sends to that session.
  `[state] liveInk` adds `new` (ink not yet asked about), `note`, `actions` (each button's words,
  frame, and whether it is enabled and picked), `replyField` and `replyCancel` (the field's and Cancel's frames while they are up),
  `responder` and `ask` (phase, whether it sent a picture, the reply's length), and each mark's
  `id` and `agent`. A script that polls asks for `state?section=liveInk`: the whole report runs to tens of KB, and twice a second it rotated the 5 MB log twice in one take; `app.screenRecording`
  says whether captures are allowed. A test launch with `VIGNETTE_SHARE_LIVE_INK` set lets captures
  see the overlays, so a script can look at what was drawn; the overlay rests under floating
  windows, so a test window that floats keeps the ask on it and must be lowered to be looked at.
