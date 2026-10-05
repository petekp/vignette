# Live ink in Vignette: integration plan (2026-10-04)

Status: step 1 is built (overlay, chord, ink, clear). Steps 2 to 4 are a plan. Two spikes stand
behind it: `docs/live-ink-spike-2026-10-04.md`, the prototype on the `spike/live-ink` branch, and
`docs/live-ink-step2-spike-2026-10-04.md`, which measured who should answer and then tried step 2
end to end. "Step 1 as built" records where the build departed from the first plan.

Live ink is drawing straight on the live screen, over any app, asking about what you drew, and
seeing the answer drawn back on the same screen within a few seconds. This note says how it fits
into Vignette as an option, what it reuses, what is new, and the order to build it in.

## The answer in short

- **New:** a `LiveInk` controller owning the screen overlay, the hold-to-draw chord and the ink
  (built in step 1). Step 2 adds the note panel, the packet, and a responder: one `claude`
  process Vignette keeps running to answer live ink.
- **Reused as is:** the mark geometry and rendering, the colours and note style, `AgentTools` to
  find `claude`, and Send with its sessions, for an ask that belongs to a working session.
- **Not changed in step 2:** the reply protocol, the request store and the plugin.

Live ink goes to the responder by default, not to the session Pete is working in. Measured over 7
days of his transcripts, a session was mid-turn 66 to 80% of the time, and ink arriving mid-turn
would wait a median of 6 to 10 minutes. A responder kept running answered in 1.5 to 2 seconds. At
that speed the screen has not moved, so the answer can be drawn on it straight away, and marks
that follow a scroll can come later.

## Decisions

Pete confirmed 2, 3, 4, 6 and 7 on 2026-10-04.

1. **An option, off by default.** A "Live ink" section in the General tab of Settings holds the
   switch and the permission rows. Reason: it needs a permission Vignette does not ask for today,
   it runs a model on the person's Claude account, and the shortcut is a global chord that some
   people already use for other things.
2. **The chord is Control and Option held together, for now.** The spike used it and Pete drew with
   it on his Mac. Something easier to discover will replace it later. It must be exactly ⌃⌥: any
   other key pressed during the hold ends it, because Rectangle and other window managers use ⌃⌥
   with arrows. Step 1 found no conflict with Vignette's own shortcuts (see "Step 1 as built").
3. **Draw on the live screen, not a frozen copy.** An earlier note
   (`docs/live-screen-2026-09-18.md`) proposed freezing the screen when the chord goes down, so
   menus and hover states survive the drawing. Live drawing is chosen for three reasons: the point
   of live ink is that marks stay on the live interface; a freeze costs a full-screen capture before
   the first stroke can show; and catching a moment that does not hold still is what screenshot
   mode already does well.
4. **Screen Recording is required.** The packet's picture is a capture, and without pixels the
   responder has only the window's name. The switch asks for the permission when it is turned on,
   which keeps the rule that only a button press raises a permission dialog. macOS usually needs
   Vignette to relaunch before the grant works, and the row says so. Setup does not ask: setup's
   job is the shortcut.
5. **Live ink stands aside for Vignette's own windows.** While the stack or the annotator is up,
   the chord does nothing. Reason: the overlay must sit at `.screenSaver` level to draw over other
   apps' menus and dialogs, which puts it above the stack (level 25), the annotator (21) and its
   toolbar (26).
6. **A session's reply is a card.** Ink sent to a working session comes back as today's replies
   do, as a card in the stack, since it usually arrives minutes later. Drawing a session's reply on
   the live screen needs anchors and a new reply protocol, and is not planned until sessions answer
   faster.
7. **The responder answers by default.** The note panel's target starts on the responder, and lists
   the working sessions after it, for an ask that needs a session's project, such as "fix this".
   Reason: the measurements above. The cost is that the responder knows only what it is sent: not
   the session's conversation, its project, or its files.

## Step 1 as built

- **No chord setting.** The chord is fixed at ⌃⌥ in `LiveInk`, since it is temporary. A
  `liveInkChord` key and a `HotKeySpec` case wait for the chord that replaces it.
- **No hold threshold.** Inking starts as the chord goes down, so the first press draws. The glow
  waits `ui.liveInkGlowDelay` instead, or shows at the first press, so a window manager's
  ⌃⌥-arrow does not flash it. A key, or another modifier, ends the chord, and it does not begin
  again until its modifiers are let go; neither does letting go of ⌘ out of ⌘⌃⌥ (`HeldChord`).
- **Keys come from the HID state.** A key another app takes as a shortcut never reaches an event
  monitor: measured with a Carbon hotkey on ⌃⌥9, the chord's keyDown monitor saw nothing and
  inking went on. `CGEventSource.secondsSinceLastEventType(.hidSystemState, .keyDown)` counted that
  key and counted no modifier, so `ModifierChord` asks it every 50 ms while the chord is held, in
  place of keyDown monitors.
- **No shortcut refusals.** The double tap of right Option counts a press only while it is the sole
  modifier and resets on any other modifier key (`ModifierTap.flagsChanged`). A chord begun with
  right ⌥ counts only as the second press of a double tap begun just before it, as any press of
  right ⌥ would. A key combination with ⌃⌥ ends the chord when its key goes down, and the
  combination then fires as usual; the stack it opens would end the inking anyway.
- **Erasing is a tap on a mark, not ⌃⌥⌫.** An NSEvent monitor sees a key but cannot keep it from the
  frontmost app, where ⌃⌥⌫ deletes a word. A tap with the chord held erases the topmost mark whose
  stroke it lands on, and "Clear Live Ink" in the menu and `live-ink-clear` erase all.
- **Marks stay on their Space.** An overlay joins no other Space, so there is one per screen per
  Space that has marks, and one for the active Space while the chord is held. Each is up only while
  it is needed, so an idle live ink puts no full-screen window over every app.
- **Captures leave the overlay out** (`sharingType = .none`), so a screenshot shows the screen
  without the marks. Step 2 draws the ink into its own capture, so it loses nothing.
- **The overlays clear while a capture runs.** macOS's window picker (Space during ⌘⇧4) took the
  overlay whenever the pointer was over a mark, and unshared it could not capture it ("Unable to
  capture window image"). Measured with a probe window on macOS 15: the picker takes a window by
  its pixels at any level, passes over one at alpha 0, and reads the windows when Space is pressed,
  before its own window appears. So after ⌘⇧, while there are marks, live ink sets its overlays to
  alpha 0 while a `screencapture` process runs or `screencaptureui` has a window, and the picker
  then took the app window under a mark.
- **The overlay rests at level 1.** Above normal windows and below the dim and Vignette's floating
  windows, so the stack and the annotator cover the marks rather than the other way round. Menus,
  the Dock and other apps' floating windows cover them too, which is accepted for step 1: the marks
  are on app content, and holding the chord brings them over everything. It sets
  `ignoresMouseEvents` at rest. Inking raises it to `.screenSaver` and turns the flag off. The
  spike's faint fill is not needed: measured on macOS 15, a clear panel whose flag was set and then turned off took every
  press over clear pixels, as AGENTS.md's click rule says. A panel whose flag was never set passed
  them through.
- **`OutsideClick` needs no change.** It asks `NSWindow.windowNumber(at:)` for the window under the
  pointer. Measured on macOS 15 with a test copy: over the resting overlay, on a mark and off one,
  that call named the app window below, never the overlay. The landing hover in
  `ThumbnailController` uses the same call.
- **Marks are plain `Mark`s** in global top-left points at a `pointScale` of 1, drawn by
  `ShapeMarkLayer`, the editor's shape layer made top-level, and so is the stroke being drawn.
  Anchors come with step 3.
- **Strokes are read the editor's way.** A loop is the spike's test, but any other stroke is the
  editor's freehand arrow (`Mark.Arrow.freehand`), so a mark looks the same in both.
- **A tap erases generously.** It takes the mark whose stroke it is near, measured as the editor
  measures (`EditorGeometry.strokeDistance`) but 12 pt past the edge rather than the editor's 4, or
  else the smallest ellipse it is inside. Nothing shows which mark a tap would erase, and in Pete's
  first try, two taps meant for marks erased nothing at the editor's reach.


## How it fits, piece by piece

### Overlay and input

- **`LiveInkOverlay`**, one non-activating `NSPanel` per screen per Space, at the levels "Step 1 as
  built" gives.
- **The overlay never becomes key.** The note is its own small non-activating panel,
  `LiveNotePanel`. It takes the keys while it is up, and ordering it out hands them back, as the
  stack panel's do.
- **`ModifierChord`**, beside `ModifierTap`: `flagsChanged` monitors and the HID state for keys.
  Whether it needs Accessibility at all is unmeasured; the plan keeps the wait for it until a test
  copy that was never granted it shows otherwise.

### The ink and the note

- A stroke is read as a loop, an arrow or a tap by `InkStroke`, as step 1 built it.
- Letting go of the chord after drawing opens the note panel beside the newest ink. Its target
  starts on the responder and lists the sessions after it, from `AgentDestination`'s menu. Return
  sends, Esc closes the panel and keeps the ink. A Return with nothing typed sends the ink alone.
- **One ask covers the ink drawn since the last one.** Ink stays on screen until it is erased or
  cleared, so the packet marks which strokes are new.
- While waiting, the ink shows that it was sent, on the ink itself: the no-toasts rule. A failure
  says why in the same place.

### The packet

`LivePacket` is built in the moment the ask is sent, in about 250 ms:

- **The picture:** a ScreenCaptureKit capture of the whole window under the new ink, leaving
  Vignette's own windows out, at the screen's scale (about 60 ms). A crop round the ink cut off
  what the ink was about, such as the row labels beside a circled total. A window too large for
  the reader's resize also sends a crop round the ink at full detail. Sized by
  `Stitch.readerScale`.
- **The text:** Vision's accurate recognition of the capture *before* the ink is drawn in, since
  ink across a line garbles it. Each line gets an id (`t1`, `t2`) and its box as fractions of the
  picture. Fast recognition garbles code, so accurate it is, warmed up when live ink turns on: its
  first call takes 300 to 480 ms, and later ones 100 to 170 ms for a window.
- **The ink**, drawn into the picture after recognition, and its shapes as fractions of the
  picture, with the new strokes marked.
- **Where:** the app's name, the window's title, and the page's URL or the document's path when
  Accessibility gives one.
- **The note.**

Accessibility elements, which the first spike gathered, are not in step 2's packet. In Pete's apps
they are thin (Ghostty gives no element under a point, Dia only after `AXManualAccessibility`, the
Codex app nothing), and Vision reads the same text from any app.

### The responder

- **`LiveResponder` owns one `claude` process**, found by `AgentTools`, started when live ink is
  turned on (about 3 s) and kept running:

  ```
  claude -p --model sonnet --input-format stream-json --output-format stream-json --verbose
    --include-partial-messages --json-schema <the answer's schema>
    --safe-mode --tools "" --system-prompt <its own> --no-session-persistence
  ```

  Each ask is one user message: the picture inline as an image, and the packet as JSON text. The
  answer is the `result` line's `structured_output`, which the schema keeps valid. Sonnet answered
  in 1.7 to 3.3 s, and Haiku was slower, not faster.
- **It runs apart from the person's setup.** Started plainly, the process loaded Pete's hooks,
  plugins and MCP servers, registered itself as a Claude Code session in Vignette's inbox, and had
  about 150 tools, Slack and Notion among them. `--safe-mode` keeps the person's sign-in and drops
  every customisation; `--bare` cannot be used, since it reads only an API key. The working folder
  is an empty one under Application Support.
- **It has no tools.** It answers from what it is sent and cannot read files or run commands. A
  page can carry text written to steer a model. In the spike such text did not steer the answer,
  and the answer said the page had tried; with no tools, a steered answer is the most it can do.
- **Follow-ups share its conversation.** While the marks are on screen, a second ask about the same
  window sends no new picture and costs about $0.01. Clearing the ink starts a new conversation,
  with a fresh process started ahead of time so the next ask is not slowed.
- **Runs on the person's Claude account,** about $0.02 for an ask about a new screen. The Settings
  row says so, with the model (Sonnet).
- **No `claude`, or not signed in:** the target lists the sessions alone, and the row says why.

### The answer on the screen

- **The responder replies with JSON:** `say`, a short answer, and up to four marks. A mark names a
  text line (`loop` around `t3`, `arrow` to `t5` from a side, `point` under `t2`), and may narrow it
  to words within the line (`"words": "surface.markz"`), or gives fractions of the picture. A
  whole line was too coarse: the typo in a 90-character line got a loop round all of it. Vignette
  finds the words' box with Vision's `VNRecognizedText.boundingBox(for:)`, and falls back to the
  line when it cannot.
- **`say` starts drawing as it streams,** about a second before the marks arrive, 1.3 to 2.3 s
  after the ask.
- **Vignette draws it at once, in screen points**, from the picture's place on screen. The marks are
  plain `Mark`s in the agent's colour, on the same surfaces as the person's ink, so a tap erases
  them and Clear clears them.
- **`say` is a note beside the person's ink**, so it reads as the reply to what they drew. Notes
  need `MarkLayers`' text bitmaps, which today draw on an image, so `MarkLayers` learns to draw
  marks on no image.
- **The draw-on:** the agent's strokes grow from their start, the head and the note spring in
  after, and the motion scale applies. The first spike found this is what makes it feel alive.
- **The answer's marks keep clear.** In the spike, the agent's loop sat inside the person's loop,
  and a label covered the number beside it. Marks and labels are placed by the first spike's note
  placement, which scores each spot by what it would cover, the person's ink included. A long line
  gets an underline rather than a loop.
- **An id that names no line drops that mark.**

### Sending to a session

- The note panel's other targets are today's Send. The picture with the ink is the image, and the
  note, the app, the window and the URL go in the message. The reply is a card (decision 6).
- **No new request kind, read rule or skill section.** The packet's text goes in the line, so
  nothing new is read from the request folder.

### Settings, menu, commands and state

- **Settings keys:** `liveInk` (off). The model is fixed for now. Missing keys take the defaults,
  so no migration.
- **Menu:** the "Live Ink" switch and "Clear Live Ink". The menu's `missing()` gains a blocker for
  Screen Recording while the switch is on.
- **Commands:** `live-ink-clear`, and the debug-only `live-ink-stroke?points=`. Step 2 adds a
  debug-only `live-ink-ask?message=`, which asks about the ink on screen as Return would.
- **State:** the `liveInk` section in `[state]` gains the responder (starting, ready, asking,
  failed), the ask under way, and the agent's marks. `app` gains `screenRecording` beside
  `accessibility`.

## Build order

Each step is usable on its own and verified before the next.

1. **Overlay, chord, ink and clear.** Built.
2. **Ask and answer on the screen.** Screen Recording, the note panel, `LivePacket`,
   `LiveResponder`, the answer drawn on with its note, the waiting and failure states on the ink,
   and Send to a session as the second target.
3. **Marks that stay on what they point at.** Anchors to elements and text ranges, the follow tick
   and the clip from the first spike, so marks follow a scroll or a moved window. Accessibility
   elements join the packet as targets. Guided steps.
4. **The edges.** Multiple displays, full-screen apps, Chromium browsers (`AXManualAccessibility`),
   Codex as a responder (`codex exec` took 16 to 23 s cold; a thread kept warm through
   `codex app-server` is unmeasured), and an e2e scenario that holds the chord across a drag (`input.sh` needs a
   chord that stays down for that).

## Tests

- **Unit, permanent:** the chord detector's sequences, stroke classification, the packet's text
  ids, the answer's validation, words resolved to a box or falling back to the line, the marks'
  placement clear of the ink, and an answer's marks placed in screen points.
  These are the parts where a later edit could break behaviour without any visible symptom in a
  quick try.
- **e2e:** a scenario that injects a stroke, asks with `live-ink-ask`, and checks `[state]` for the
  agent's marks. The responder is a fake that `VIGNETTE_CLAUDE` names, as `VIGNETTE_CODEX` names a
  fake codex (`AgentTools.forSessions`): a test launch never runs the person's own `claude`. The
  test copy needs Screen Recording granted once by hand.

## Risks

- **The monthly prompt.** On macOS 15, Screen Recording comes with a reminder about once a month
  that asks whether Vignette may "bypass the system private window picker". People who see it may
  turn the permission off.
- **Cost and quota.** Every ask runs on the person's Claude plan: about $0.02 for a new screen and
  $0.01 for a follow-up, at Sonnet's prices.
- **The CLI is an interface Vignette does not own.** The flags above are `claude` 2.1.289's.
  A later version that changes them breaks the responder, so it checks the `init` line (no tools,
  no MCP servers) before its first ask, and the Settings row says when it cannot start.
- **The responder knows only the screen.** An ask about the person's own code is better sent to a
  session, and the panel has to make that choice easy.
- **A decision hard to reverse.** Asking for Screen Recording, and running a model for the person,
  each deserve an ADR in `docs/adr/` when they are made.
