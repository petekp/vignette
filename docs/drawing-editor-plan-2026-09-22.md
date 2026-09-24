# Drawing editor plan

2026-09-22. Vignette's drawing editor moves from a web page to Swift. [The
spec](editor.md), now `docs/editor.md`, says how the editor behaves. This plan sets the order of the
work and lists what each step deletes.

## Why

The web editor is tldraw, running in a WKWebView served from 127.0.0.1. Its license allows a public
download only with a production key. An annual key that expires hides the editor in every copy
already downloaded, and Vignette has no updater. So the first download waits on this work.

## Rules for the work

- Take the most native, fluid, refined option, and make it safe.
- All the steps after step 0 happen on one branch, and it merges only when every step is done. So
  `main` never holds two editors, dead code, or a doc that describes either.
- Each step deletes what it replaces, in that step. There is no cleanup phase at the end.
- Before deleting a symbol, find every caller. After deleting it, confirm nothing refers to it.
- A comment in a surviving file that describes the web editor is rewritten or removed in the step
  that makes it false.
- A step is done when `scripts/build.sh --test` passes and its behaviour has been driven on a
  scratch instance, as AGENTS.md describes.

## Step 0: what is already dead

This step is independent of the editor and lands on `main` first.

- **The debug `send` command.** It handed a file to a herdr pane by name or focus. The agent loop
  replaced it: it sends to a session, and a session is never a pane. Delete:
  - `sendToAgent` and its `case "send"` in `AppDelegate.swift`;
  - the `send` entry in `Commands.swift`, and its test in `CommandsTests.swift`;
  - `Send.swift` and `SendTests.swift`. The parts the agent connections use move into
    `AgentConnection.swift`: `Subprocess` runs a command line tool, and
    `ClaudeCodeConnection.HerdrAgent` is one row of `herdr agent list`. Their tests move into
    `AgentConnectionTests.swift`;
  - the `send` line in `docs/commands.md` and `docs/settings.md`, and the `send` rule in AGENTS.md.
- **Agent run reports:** `docs/run-*.md` and `overnight-2026-09-17.md`.
- **Notes on earlier iterations:** `foundation-review-2026-09-15.md`,
  `send-to-agent-exploration-2026-09-17.md`, `zoom-native-brief.md`,
  `comment-markers-exploration-2026-09-15.md`, `agent-skill-2026-09-18.md`,
  `hover-reveal-2026-09-17.md`, `codex-queue-image-paths-2026-09-20.md`,
  `screenshot-loop-spike-2026-09-20.md` and `docs/spikes/`.
- Every link to those files is removed. A rule that cited one keeps its reason inline.
- `docs/TODOS.md` lists only open items.
- Waiting, in the setup repository: the `vignette-todo-run` skill still commits a run report,
  marks items landed in `TODOS.md` instead of removing them, and sends the architecture sweep to
  `foundation-review-2026-09-15.md`.

## Step 1: the drawing

- Swift types for a drawing and its marks, the file format in spec section 1, and one validator for
  drawing files, `add?marks=`, replies and the clipboard.
- A store for drawings in `drawings/`, written atomically, with the version rule.
- Tests: the validator and a file round trip.

## Step 2: the renderer

- A function that draws a drawing over its image at any size, in the image's colour space: strokes,
  arrowheads, and text in SF Pro Rounded with its outline.
- The colour pass in Swift, with the numbers in spec section 9.
- Agents' text sizing and fitting in Swift, with the numbers in spec section 9.
- Tests: the colour pass's picks, text fitting, and a rendering's size and colour profile.

## Step 3: the editor's core

- A reducer with no AppKit in it. The drawing, the tool, the gesture and an input event go in. The
  new state and its effects come out.
- The spec's acceptance checks for tools, selection, keys, undo and the clipboard are its unit tests.
- A random-sequence test checks four things after every input:
  - no mark lies outside the image;
  - one Cmd+Z undoes exactly one step;
  - Esc during a gesture restores the drawing exactly;
  - a change of selection never adds an undo step.
- Typing is one effect with a before and an after. The text view owns the inside of a typing
  session.

## Step 4: the switch

The editor goes into the annotator, and the web editor goes in the same step. It is four parts, in
order, each built, tested and driven before the next starts.

### 4a: the editor view

New files only. Nothing is wired into the annotator yet.

- An AppKit view that hosts the core. It turns mouse, key and modifier events into the core's
  inputs, runs its effects in order, and draws what the core's state says. It decides nothing.
- It draws with Core Animation layers: the screenshot, the marks, and the core's overlay of
  outlines, handles, dots and the brush. Rectangles, ellipses and arrows are shape layers holding
  the renderer's own paths. Texts are bitmaps the renderer draws off the main thread. Zoom scales
  the picture's layers. The overlay is redrawn at the same size on screen in the same frame.
- Text is typed in a plain-text `NSTextView` with every automatic substitution off. It is laid out
  at the layout's font size in px and scaled by the zoom. Each line's baseline is `TextLayout`'s,
  so a text does not move when typing ends.
- Cursors, the short confirmations, the clipboard, and VoiceOver.

### 4b: the switch

- The annotator hosts the editor view in place of the web view. Opening, park, Esc, Done, Send and
  the toolbar go through the core. The zoom keys and the double-click smart zoom come from the view.
- Drawings are read from and written to `DrawingStore`.
- Done puts a promised PNG on the clipboard and sends the card home at once. Send and Copy Drawing
  render with the renderer, one at a time, off the main thread.
- `add?marks=` and replies turn agents' marks into px with `AgentMark.marks`, and add them to the
  stored drawing, or to the open drawing as one undo step.
- The colour pass's sample is made off the main thread when an image opens.
- `ThumbnailController.send` holds an event that arrives while it is still handling one, and runs
  it right after.
- Every launch removes `drafts/` under Application Support and under Caches, if they are there.
- Delete everything in the list below. Cards show the plain screenshot until 4c.

### 4c: cards and flights

- A card and a card in flight draw the drawing's marks over the image with the renderer. No
  preview images are stored or cached. 4b already deleted the preview code.

### 4d: tweaks, inspection, and the driven round

- The core's metrics, the text style and the arrowhead's proportions are `UITweaks`, each with a
  `Bound` and a slider, and a change reaches the open editor.
- `[state]` gains its `editor` section, and is written without waiting for anything.
- The last of the dead code the switch leaves, and a driven round of the acceptance checks that
  need the running app.

### 4e: flights without dropped frames

Pete asked for this on 2026-09-23, after 4c measured the flights that narrow the stack.

- The flight image is decoded in the display's colour space before the flight starts. Core
  Animation converted it at the flight's first commit: about 20 ms, and 55 ms on the second open.
  Built.
- The stack's per-frame relayout while it narrows was measured, and the options went to Pete. He
  left it for later: `docs/TODOS.md` lists it, and `docs/stack-narrowing-2026-09-23.md` has the
  numbers.
- A press on a card flying into the editor never reaches the app behind. It goes to the editor once
  the editor is up, so a drag begun during the flight draws. A press on any other flight is
  swallowed. Built, with the review's fixes. The second click of a double-click on a card could land
  where the narrowing column had been and reach the app behind; Pete had it fixed, and the card's
  slot now swallows presses for the double-click interval.

### Decisions made while planning 4

| Decision | Why |
|---|---|
| The transition reducer's `parking` phase stays. | Park still waits for the zoom to spring back to fit, so the card flies home from the fitted frame. Without a zoom, park answers in the same turn. |
| The annotator's window still comes up invisible at `prepare`. | It holds the keys during the flight, so Esc during the flight turns the card around. |
| The flight's wait for `loaded` stays, with the editor as its source. | 4b measured it. At motion 0 the flight arrived 34 ms before the screenshot's decode. |
| `dismiss` sets `slidingOut` before it sends the event. | A park that answers in the same turn otherwise ends the card's flight offscreen. |
| A drawing made from agents' marks keeps the stored drawing's point scale. A new one takes the main screen's, inside `Drawing.pointScales`. | Decision 8's best guess when no annotator is open. |
| Replies waiting at launch are imported as soon as their records load. | Today the page's `ready` starts them. A build no longer waits for anything. |
| `FocusReturn` is created at launch by `AppDelegate`. | The web view's preload was the only thing that created it early enough to record the frontmost app. |
| The drafts folders are removed at every launch they exist, with no flag. | Once they are gone, the check costs one lookup. |
| Cards draw marks live over the image, rather than keeping a composited image. | A card is current the moment its drawing parks and sharp at any size, with nothing to invalidate. |

### Decisions made while building 4a and 4b

`reports/` in the run folder has the measurements behind each one.

| Decision | Why |
|---|---|
| Rectangles, ellipses and arrows are shape layers built from `Mark.shape`, the paths the renderer draws. | They stay sharp at any zoom with nothing redrawn. A bitmap per mark cost 20 ms per drag step when zoomed in, and 25 MB for a rectangle that spans the image. |
| Texts are bitmaps the renderer draws on a serial queue of their own, off the main thread. | A long text held the main thread for up to 1.9 s. Done, Send and Copy Drawing use another queue, so a long export never delays the screen. |
| Text bitmaps are IOSurfaces. No text bitmap has more pixels than the view, and a text holds at most two. | Core Animation copied a `CGImage` on the main thread, up to 22 ms, and doubled its memory. The cap bounds memory at any zoom. |
| When typing ends, the text view stays until the text's bitmap is on screen. | The words never vanish for a frame. |
| The selection and hover outline runs outside the mark's ink, and the handles sit on its corners. | On the stroke, the outline's light edge hid the mark's colour. |
| The renderer strokes each letter's outline on its own, then fills every letter. | Stroking all the letters as one path took 240 ms for 2,000 characters. Now it takes 61 ms. |
| A Command key the core has no command for, such as Cmd+W, goes to the app's menu. | The editor otherwise took Cmd+W, Cmd+Q and Cmd+, away from the menu. |
| The clipboard is read in this order: copied marks, a file, text, a URL, an image. | Finder puts a file's name as text beside its URL. Pasting a copied file must not add its name as a text mark. |
| The editor opens at `prepare`, before the screenshot's decode arrives. | Its keys work during the flight, so Esc turns the card around. An agent's push while the card flies joins the open drawing. |
| `abandon` parks and writes the drawing. | A key pressed during the flight can change it. |
| A toast is a small dark capsule at the bottom centre of the frame. | It shows where the eye already is, and nothing in the toolbar moves for it. |
| A plain scroll pans a magnified picture. The zoom keys and smart zoom do nothing during the flight. | tldraw panned on scroll. A zoom during the flight would move the frame the card is landing on. |
| Cmd+C with nothing selected gives Done's clipboard, and writes the `-annotated.png`. | Decision 10 says it is the same PNG as Done's. |
| Card previews were deleted in 4b. | They existed only to show drafts. |
| Reply receipts keep the codes `draft-failed` and `draft-store-failed`. | They are part of the reply protocol. |
| The editor, the cards and the flights draw marks with one drawer, `MarkLayers`. A flight and the editor share text bitmaps. | One implementation of what a mark looks like on screen, and nothing steps when the flight hands over to the editor. |
| A card's marks live in its existing `DragSource` view, rasterized at the card's size at rest and scaled while the stack narrows. | SwiftUI updates every AppKit view in the stack on every animation frame. One view per card, rasterized, cost the least main-thread time measured. |
| A stitch draws each piece's marks into its pixels, and has no drawing of its own. Pete decided the first part on 2026-09-23. | A stroke is a fixed 3.5 pt, so marks copied into a new drawing would look thicker wherever a piece is scaled down. |
| A stitch is composed off the main thread. | It used to run on the main thread. |
| The editor's sizes, the text's weight and line height, and the arrowhead's proportions are live tweaks. The weight snaps to the nine named weights, 100 to 900. | The rounded system font draws only its nine named weights. |
| `textDragDelay` is a threshold, not motion, so the motion scale does not shorten it. | Scaling it would change what a gesture means: at `motion: 0` every Text press followed by a sideways drag would set a width. |
| Done, Send, Copy Drawing and `add?marks=` lay text out with the live tweaks. | A copy breaks its lines where the person saw them break. |

### Delete in 4b

- Code:
  - all of `web/`, including the license key in `web/.env.local`;
  - `LocalServer.swift`, `Bridge.swift`, `StandIn.swift` and `DraftStore.swift`. `ToolInfo` goes
    with Bridge: the toolbar takes its tools from the core's `Tool`;
  - in `AnnotationController.swift`: the web view, `preload`, `queryPage`, `evalForDebug`,
    `presentEmpty`, `canvasMaybeFreed`, `onCanvasFree`, `canvasRefusal`, `onProblem`, the stand-in
    and overlay code, `setView`, `pagePlace`, the script message handler, and the navigation and
    process-termination delegate methods;
  - `Config.overlayMaxPixel`;
  - in `AppDelegate.swift`: `renderMissingPreviews`, the `onCanvasFree` wiring, the `pageState`
    checks, `LocalServer.FileAccess`, and `port=` in the ready line;
  - in `ScreenshotRequests.swift`: `canvasRefusal` and `canvasBecameAvailable`, since a build no
    longer waits;
  - the `eval` and `show-editor` commands, `CommandRequest.query`, and their mention in the `debug`
    setting's comment;
  - the error codes `page-not-ready`, `export-timeout`, `export-failed` and `eval-failed`;
  - `[state]`'s `page` section and the annotator's `webPid`, `port`, `pageState`, stand-in and
    overlay fields;
  - every `[web]` and `[annotate] view` log line.
- Tests: `RenderTests`, `BridgeTests`, `LocalServerTests`, `DraftStoreTests`, the page query in
  `StateReportTests`, the `eval` cases in `CommandsTests`, and the cases in
  `ScreenshotRequestsTests` that wait for the page.
- Build and release:
  - `project.yml`: the `web/dist` resources on both targets and `LICENSE-tldraw.md`, with the
    comment above them;
  - `scripts/build.sh`: the pnpm build and its comments;
  - `scripts/release.sh`: the tldraw key, the pnpm build, and their comments;
  - `.gitignore`: `web/node_modules/`, `web/dist/` and `web/.env.local`;
  - `LICENSE-tldraw.md`, and the tldraw lines in `LICENSE`.

## Step 5: guidance and docs

- AGENTS.md is reviewed as a whole. Rules that describe the web editor go, and rules for the native
  editor replace them. That covers: the `web/` and bridge entries in Layout; the tldraw license and
  watermark; the screenshot served by LocalServer; preloading the web view; building a draft on a
  borrowed canvas; the zoom stand-in; the stand-in's share of the memory rule; the tldraw upgrade
  checklist; exports not using `toImage`; `web/dist` before xcodegen; `window.vignette.snapshot` in
  the Send rule; and the Adding things entries for editor tools and bridge messages. The loop's
  mentions of `eval`, `[web] ready`, `webPid` and `page` go too.
- `README.md`: How it works, Build it yourself without pnpm, and the tldraw line.
- `site/index.html`, `docs/building.md`, `docs/commands.md`, `docs/settings.md`, `docs/using.md` and
  `skills/vignette/SKILL.md`. The skill's `page-not-ready` advice goes, and its log line becomes
  `[marks] text too long`. The app rewrites installed copies of the skill at the next launch.
- `docs/TODOS.md` loses its tldraw-era items.
- The `vignette-todo-run` skill in the setup repository: the `pnpm install` in `setup-run.sh` and
  `INTEGRATOR.md`, the `window.editor` line in `BRIEF.md`, and the page in `ITEM-example.md`.
- Dated notes:

| Note | Action |
|---|---|
| `tldraw-reference/`, local research that was never committed | Delete |
| `zoom-2026-09-17.md` | Delete. Carry any rule it still supports into AGENTS.md. |
| `zoom-input-2026-09-19.md`, `handover-2026-09-18.md` | Keep a note only if its measurements still describe the native editor. Otherwise delete it. |
| `pushed-text-2026-09-19.md`, `annotation-colour-2026-09-17.md` | Keep. Point their code references at the Swift files. |
| `flight-interrupt-2026-09-18.md`, `shadow-2026-09-17.md` | Keep. Rewrite what they say about the page. |
| This plan | Delete |

- The spec either becomes `docs/editor.md`, kept current like `commands.md`, or is deleted if
  AGENTS.md and the core's tests cover it. Decide at this step.

## Step 6: the final check

- `git grep -i -E "tldraw|WKWebView|WebKit|LocalServer|StandIn|stand-in|web/dist|pnpm|VITE_|page-not-ready|eval-failed|\[web\]"`
  returns only the launch cleanup that removes WebKit's old data folders (`AppDelegate`, `Drawings`
  and its test), and the dated notes in `docs/` that record history.
- `scripts/build.sh --test` passes.
- A driven round on a scratch instance covers the acceptance checks that need the running app.
- Idle memory is measured. Before this work, the app used 57 MB and WebKit's three processes 132 MB.

## References for the build

No maintained macOS library covers these four tools. What exists is iOS-only, archived, or a whole
app.

| Project | License | What to take from it |
|---|---|---|
| [Drawsana](https://github.com/Asana/Drawsana) | MIT | Its split into shapes, tools, a Codable drawing, and undo kept as operations. It is UIKit and unmaintained, so follow its design and do not depend on it. |
| [Snapzy](https://github.com/duongductrong/Snapzy) | BSD-3-Clause | AppKit details: an `NSView` canvas with resize handles |
| [better-shot](https://github.com/KartikLabhshetwar/better-shot) | BSD-3-Clause | A canvas over an `NSView` that takes the mouse and keys |
| [Capso](https://github.com/lzhgus/Capso) | Business Source License 1.1 | Its grant excludes screen capture products. Do not read it or copy from it. |

Code copied from a BSD or MIT project keeps that project's copyright notice.
