# Drawing editor plan

2026-09-22. Vignette's drawing editor moves from a web page to Swift. [The
spec](drawing-editor-spec-2026-09-22.md) says how the editor behaves. This plan sets the order of the
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

The editor goes into the annotator, and the web editor goes in the same step.

Build:

- An AppKit view that hosts the core. It draws with Core Animation layers and handles hit testing,
  cursors and handles. Text is typed in a plain-text `NSTextView` with every automatic substitution
  off.
- The thresholds in the spec go in `UITweaks`, each with a `Bound` and a slider: the drag
  thresholds, hit bands, handle and dot sizes, text sizes, and the arrowhead's proportions.
- Zoom scales the view's layers. Handles and outlines are redrawn in the same frame.
- Park and build answer at once. `ThumbnailController.send` holds an event that arrives while it is
  still handling one, and runs it right after.
- Done puts a promised PNG on the clipboard and sends the card home at once.
- Cards and flights draw marks with the renderer.
- `[state]` gains its `editor` section.
- The first launch deletes `drafts/` under Application Support and under Caches.

Delete:

- Code:
  - all of `web/`, including the license key in `web/.env.local`;
  - `LocalServer.swift`, `Bridge.swift`, `StandIn.swift` and `DraftStore.swift`;
  - in `AnnotationController.swift`: the web view, `preload`, `queryPage`, `evalForDebug`,
    `presentEmpty`, `canvasMaybeFreed`, `onCanvasFree`, `canvasRefusal`, the stand-in and overlay
    code, `setView`, the script message handler, and the navigation and process-termination
    delegate methods;
  - `Config.overlayMaxPixel` and `Config.previewMaxPixel`;
  - in `AppDelegate.swift`: `renderMissingPreviews`, the `onCanvasFree` wiring, the `pageState`
    checks, and `port=` in the ready line;
  - in `ScreenshotRequests.swift`: `canvasRefusal` and `canvasBecameAvailable`, since a build no
    longer waits;
  - the `eval` and `show-editor` commands, and their mention in the `debug` setting's comment;
  - the error codes `page-not-ready`, `export-timeout`, `export-failed` and `eval-failed`;
  - `[state]`'s `page` section and the annotator's `webPid`, `port`, `pageState`, stand-in and
    overlay fields;
  - every `[web]` and `[annotate] view` log line.
- Tests: `RenderTests`, `BridgeTests`, `LocalServerTests`, `DraftStoreTests`, and the cases in
  `ScreenshotRequestsTests` that wait for the page.
- Build and release:
  - `project.yml`: the `web/dist` resources and `LICENSE-tldraw.md`, with the comment above them;
  - `scripts/build.sh`: the pnpm build and its comment;
  - `scripts/release.sh`: the tldraw key;
  - `.gitignore`: `web/node_modules/`, `web/dist/` and `web/.env.local`;
  - `LICENSE-tldraw.md`, and the tldraw line in `LICENSE`.

Check, and delete if they no longer do anything:

- the transition reducer's `parking` phase, which exists because park used to take a round trip;
- the flight's wait for `loaded` before it lifts;
- ordering the annotator's window in, invisible, so the page could draw during the flight.

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
  returns nothing.
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
