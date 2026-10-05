# Live ink in Vignette: integration plan (spike, 2026-10-04)

Status: step 1 is built (overlay, chord, ink, clear). Steps 2 to 4 are a plan. The prototype is
`spikes/live-ink/` on the `spike/live-ink` branch, and its results are in
`docs/live-ink-spike-2026-10-04.md`. "Step 1 as built" below records where the build departed
from this plan.

Live ink is drawing straight on the live screen, over any app, and sending that to an agent
session, which draws its answer back on the same screen. This note says how it fits into Vignette
as an option, what it reuses, what is new, and the order to build it in. It was planned from
reading the code; step 1 has since been built.

## The answer in short

Live ink fits Vignette with one new owner and three extensions:

- **New:** a `LiveInk` controller owning the screen overlay, the hold-to-draw chord, the person's
  ink, the context packet, and the anchors that keep marks on their targets.
- **Extended:** Send takes a second kind of request, the reply protocol learns marks that name a
  target, and the mark layers learn to draw a mark on.
- **Reused as is:** the session discovery and delivery, the request store, the reply helper's
  security, the mark geometry and rendering, the colours and note style.

It can ship in steps. Step 2 below sends live ink to an agent with no protocol change: the
agent's reply comes back as an ordinary card. Only step 3, the reply drawn on the live screen,
changes the reply protocol.

## Decisions

Pete confirmed 2, 3, 4 and 6 on 2026-10-04.

1. **An option, off by default.** A "Live ink" section in the General tab of Settings holds the
   switch and the permission rows: Accessibility from step 1, Screen Recording from step 2. Reason:
   it needs a permission Vignette does not ask for today, and the shortcut is a global chord that
   some people already use for other things.
2. **The chord is Control and Option held together, for now.** The spike used it and Pete drew with
   it on his Mac. Something easier to discover will replace it later. It must be exactly ⌃⌥: any
   other key pressed during the hold ends it, because Rectangle and other window managers use ⌃⌥
   with arrows. Step 1 found no conflict with Vignette's own shortcuts (see "Step 1 as built").
3. **Draw on the live screen, not a frozen copy.** An earlier note
   (`docs/live-screen-2026-09-18.md`) proposed freezing the screen when the chord goes down, so
   menus and hover states survive the drawing. Live drawing is chosen here for three reasons: the
   point of live ink is that marks stay on the live interface; a freeze costs a full-screen capture
   before the first stroke can show; and catching a moment that does not hold still is what
   screenshot mode already does well. A press on the overlay probably closes an open menu, as any
   press outside a menu does; that is not measured yet. If it does, a menu stays a screenshot's job.
4. **Screen Recording is required.** Without pixels, the agent gets only Accessibility text,
   which is thin in apps that draw their own content. The switch asks for the permission when it
   is turned on, which keeps the rule that only a button press raises a permission dialog. macOS
   usually needs Vignette to relaunch before the grant works, and the row says so. Setup does not
   ask: setup's job is the shortcut.
5. **Live ink stands aside for Vignette's own windows.** While the stack or the annotator is up,
   the chord does nothing. Reason: the overlay must sit at `.screenSaver` level to draw over other
   apps' menus and dialogs, which puts it above the stack (level 25), the annotator (21) and its
   toolbar (26).
6. **A reply draws live when its targets are still on screen, and becomes a card otherwise.** A card
   for every exchange would fill the stack with questions that were answered in place. A card when
   the targets are gone means a slow answer is never lost: Claude Code reads a request only between
   turns, and a Codex thread that nobody has open keeps it queued, so a late reply will be common.

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
- **Captures leave the overlay out** (`sharingType = .none`). Pete found that ⌘⇧4's window picker
  took the resting overlay for a window; with the overlay unshared, `screencapture` left a mark out
  of its picture. Step 2 draws the ink into its own capture, so it loses nothing.
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

- **`LiveInkOverlay`**, one non-activating `NSPanel` per screen, joining all Spaces, at the levels
  "Step 1 as built" gives.
- **The overlay never becomes key.** The spike made it key to catch ⌃⌥⌫ and to type the note,
  then had to hand the keys back with a trick. In Vignette the note is its own small
  non-activating panel, `LiveNotePanel`. It takes the keys while it is up, and ordering it out
  hands them back, as the stack panel's do.
- **`ModifierChord`**, beside `ModifierTap`: global and local `flagsChanged` monitors, the HID
  state for keys, and no permission prompt. Both install their monitors through `KeyMonitors`,
  which waits for Accessibility. Its rules are the pure `HeldChord`.

### The person's ink and the note

- A stroke is read as a loop, an arrow or a tap by `InkStroke`, as step 1 built it.
- Letting go opens the note panel beside the ink. It shows the destination the way the annotator
  toolbar does, using `AgentDestination.defaultTarget` and its menu. Return sends, Esc drops that
  ink, and the typed note stays on the ink in the person's note style.
- While waiting, the sent ink carries the destination's logo and a progress mark. This follows the
  no-toasts rule: the news is said on the ink, which is already on screen. A failure says why in
  the same place, using the `SubmissionOutcome` reasons that `SendNotice` uses.

### Marks and anchors

- **A live mark is a `Mark` plus an anchor.** `LiveMark { anchor: LiveAnchor; mark: Mark }`, the
  mark in points relative to the anchor's corner, with `pointScale` 1. Adding a case to
  `Mark.Geometry` instead would touch 17 switches, and live marks are never stored as a `Drawing`.
- **`LiveAnchor`** is an element (an `AXUIElement` and an offset), a range of text in a text view,
  or a window. It carries the window id for clipping.
- **`AnchorTracker`** polls the anchors 30 times a second, since nothing announces a scroll. The
  clip is a pure function of frames: the mark's window, its scroll area, and the windows in front
  at every level, skipping clear windows and full-screen windows above normal level (the Dock on
  macOS 15 reports one). It is tested like `AnnotatorZoom`.
- **Each anchor's marks move as one layer**, by its position each tick inside a disabled-actions
  transaction, with a mask for the clip. Shapes are `ShapeMarkLayer`s, as in step 1. Notes need
  `MarkLayers`' text bitmaps, and `MarkLayers` today shows a drawing on an image, so step 3 decides
  whether it learns to show marks on no image. Moving the container keeps
  every shape path and text bitmap as it is, so a tick costs a transform. Three adjustments:
  - Live texts always set `wrap`, since a text without it wraps at the image's width.
  - An agent's text gets an explicit size: `AgentMarks` sizes it as a fraction of the image width,
    which means nothing on a screen.
  - `Mark.placed(in:)` is skipped, since it clamps marks into an image.
- **The draw-on** goes into `ShapeMarkLayer`: `strokeEnd` grows on the edge and stroke layers, the head
  and the note spring in after it, and the motion scale applies. Its length is a `UITweaks` value
  with a `Bound` and a slider.

### The packet

- **`LivePacket`** builds what the spike built: Accessibility for each mark (role, title, value,
  identifier, path to the window, the URL or document), a ScreenCaptureKit capture of the crop and
  the window that leaves Vignette's own windows out, the ink drawn into the crop, and Vision's text
  afterwards. The crop is sized by `Stitch.readerScale`.
- **It is a request with an extra file.** `ScreenshotRequests.send` takes an optional context and
  writes `context.json` beside `image.png`, atomically, before the line goes out. Nothing parses
  the line, so the transport needs no change.
- **Claude Code needs a second read rule.** `ClaudeReadRule` allows only `requests/*/image.png`,
  so reading `context.json` would stop the session on a permission prompt. It becomes a list of
  rules, and turning Claude Code on adds both.
- **The request line** starts "From Vignette:" as before, names `context.json`, and carries the
  person's note. Its instruction text is its own, not `sendInstructions`, which is the person's
  setting for screenshot sends.
- **The request record gains an optional `kind`**, absent meaning a screenshot. An optional field
  decodes in older builds and newer ones alike, and a required one would make every stored request
  unreadable. `delivered` and `replyFailed` look up a screenshot today, so a live kind routes them
  to the ink instead.
- **Live requests get their own cap.** `maxLiveRequests` (50) is one pool, and a send past it
  clears the oldest. Frequent live sends would push out an editor request that is still waiting.
  Live requests are capped at 10 among themselves.
- **Cleanup removes `context.json`** with `image.png`, since it holds window titles, URLs and the
  text on screen.

### The reply

- **Step 2 needs no reply change.** An agent that answers a live request with today's fraction
  marks gets a card: the crop with both drawings. That is the fallback in decision 6, available
  before anything draws live.
- **Step 3 raises `ReplyProtocol.version` to 2.** The bundle gains `say` and `steps`, and a mark
  may name a target instead of a position: `loop` with `around`, `arrow` with `to` and `from`,
  `point` with `at`, `note` with `near`. The helper checks each id against the request's
  `context.json` through `ticket.requestDirectory`, so a bad id fails before anything is sent.
  Raising the version makes tickets from before the update unanswerable, which is acceptable for
  requests that live for minutes.
- **The app resolves targets when it accepts the reply** and stores the result as today's fraction
  marks, keeping the target ids beside them. The stored `Reply` then still decodes in an older
  build, which needs `x` and `y`.
- **The branch is in `importNext`**, after the reply is accepted and before `publish`. When the
  request is live and its targets resolve on screen, `LiveInk` draws the reply and the record gets
  a new stage, shown live. Otherwise it falls through to `publish` and becomes a card, with `say`
  as a note on it.
- **The skill** gets a section for live requests: what `context.json` holds, the targeted marks,
  `say` and `steps`. Its `metadata.version` goes up, and so do both plugin manifests.

### Settings, menu, commands and state

- **Settings keys:** `liveInk` (off). Missing keys take the defaults, so no migration.
- **Menu:** a "Live Ink" switch and "Clear Live Ink" near "Draw on Newest Screenshot". The menu's
  `missing()` gains a blocker for Screen Recording while the switch is on.
- **Commands:** `live-ink-clear`, and a debug-only `live-ink-stroke?points=`
  that injects a stroke as if drawn, so a scenario can test without posting input. New error codes
  go into `CommandError` first.
- **State:** a `liveInk` section in `[state]` (on, drawing, note open, marks with their anchors
  and frames, packets waiting), and `screenRecording` beside `accessibility` in `app`.

## Build order

Each step is usable on its own and verified before the next.

1. **Overlay, chord, ink and clear.** No sending. Settles the click rule, `OutsideClick`, the
   level, the chord conflicts, and focus. Verified by driving the app with the debug stroke command
   and by hand.
2. **The packet and Send.** Screen Recording, `LivePacket`, the request kind, `context.json`, the
   read rule, the request line and the skill's first live section. Replies come back as cards.
3. **Replies on the live screen.** Protocol version 2, targeted marks, anchors, the clip, the
   draw-on, `say`, and guided steps.
4. **The edges.** Multiple displays, Spaces and full-screen apps, Chrome and Electron
   (`AXManualAccessibility`), the waiting state, and an e2e scenario that holds the chord across a
   drag (`input.sh` needs a chord that stays down for that).

## Tests

- **Unit, permanent:** the chord detector's sequences, stroke classification, the clip function,
  anchor offsets, targeted mark validation, target resolution, and an older record or reply
  decoding after the change. These are the parts where a later edit could break behaviour without
  any visible symptom in a quick try.
- **e2e:** a scenario per step that uses the debug stroke command and a fake session, then checks
  `[state]` and the request files. The test copy needs Screen Recording granted once by hand, as
  it needs Accessibility now.

## Risks

- **The monthly prompt.** On macOS 15, Screen Recording comes with a reminder about once a month
  that asks whether Vignette may "bypass the system private window picker". People who see it may
  turn the permission off.
- **Late replies.** Claude Code reads between turns, so a busy session answers minutes later.
  Most live replies may end up as cards until sessions answer faster.
- **Apps with little Accessibility.** Canvases, games and some Electron apps give a window and
  nothing inside it, so their marks pin to the window and do not follow a scroll.
- **A decision hard to reverse.** Asking for Screen Recording, and protocol version 2, each
  deserve an ADR in `docs/adr/` when they are made.
