# Opus 5.5 system design assessment

Independent consultation at max effort. Source: `468b48397dff0cc776c36b6a01199cc886f4167b`. Date: October 2, 2026.

The consultation body is reproduced unchanged. [The synthesis](system-design-synthesis-2026-10-02.md) verifies and qualifies its recommendations.

I reviewed source `468b483` read-only: `Sources/`, `Tests/`, `agent-plugin/`, `skills/vignette/`, AGENTS.md, the glossary and the ADRs. Nothing was built, run or measured.

## Overall judgment

The core that decides things is in good shape, and I would not restructure it:
- **The state machines are pure reducers.** The annotator transition, annotation run, editor, zoom, card notices and toolbar offer all have sequence and random-sequence tests (ADR 0003).
- **The durable modules are deep.** Drawings and the screenshot requests/replies fail closed and are tested through their own interfaces.
- **One renderer draws marks everywhere**, so they look the same in the editor, on cards, in flight and in output.

The risk sits at the seams no module owns:
1. **File identity.** Everything is keyed by the screenshot's path, and the watcher reports a rename as a deletion plus a new capture.
2. **`AppDelegate`.** It is the real owner of three use cases: what a new file means, the Send pipeline, and outbound renderings. Their ordering rules can only be tested end to end.
3. **One timing gap between processes.** The Claude Code plugin's inbox script can deliver a second send in the middle of a turn.
4. **One cache-keying slip** that breaks a documented memory rule.

Each has a small, local fix. None needs a new layer, dependency or process.

## Key-system map

| System | Deep owners | How the rest reaches it | Identity | Durable state |
|---|---|---|---|---|
| Capture and images | `ScreenshotWatcher` (index, stability, folder permission), `Thumbnailer` (decode cache, iCloud) | `onNew`/`onRemoved` closures into `AppDelegate` | file path | none |
| Stack, flights, annotator | `ThumbnailController`, `AnnotationRun`/`AnnotatorTransition`, `TransitionLayer`/`FlightPress`, `AnnotationController`/`AnnotatorZoom` | about a dozen closures wired in `Sources/AppDelegate.swift:95-119` | card UUID per presentation; run key = path; open = `openGeneration` | none |
| Editor, drawings, output | `EditorCore`/`EditorView`, `Drawings`/`DrawingStore` (`OpenDrawing`), `Rendering`/`MarkLayers`, `RenderingQueue`, `Clipboard`, `Stitch` | `Drawings.current`, plus `RenderingQueue.render` from four `AppDelegate` sites | drawing key = hashed path | `drawings/*.json`, `-annotated.png` |
| Settings, startup, platform | `Settings`, `HotKey`/`ModifierTap`, `FocusReturn`, `LoginItem`, `Updater` | `Settings.shared` read directly; `settingsChanged` fans out | — | settings.json, Apple's screencapture domain |
| Agent loop | `AgentConnection` (Claude inbox, Codex queue), `ScreenshotRequests`, `ReplyProtocol`/`ReplyCommand`, `AgentPlugins`, `inbox.sh`/`turn.sh` | `Callbacks`; files and URLs across processes | request/reply/attempt UUIDs; session id or thread UUID | `requests/<id>/`, `claude-sessions/<pid>/` |

## Prioritized opportunities

### 1. Report renames at the watcher, and decide what counts as a capture
**High severity.** Confidence is high on the code path; how often it happens is unmeasured.

**Observed.**
- The watcher's index maps name to date (`Sources/ScreenshotWatcher.swift:22-28`) and diffs by name (`:156-176`). A Finder rename therefore produces `onRemoved(old)` plus `onNew(new)` (`:177-197`).
- On removal, `AppDelegate` deletes the drawing (`Sources/AppDelegate.swift:1368-1373` → `Sources/Drawings.swift:102-110`).
- On a new file, it puts the image on the clipboard and shows or opens it (`AppDelegate.swift:1361-1367`). `copyOnCapture` is on by default (`Sources/Settings.swift:51`).
- The same happens for any png, jpg, heic or mov that any app saves into the folder, which is `~/Desktop` by default.
- The agent badge is documented to survive a rename (`Sources/Agent.swift:3-6`); the drawing does not.
- Whether a file is a capture is decided in three places: `ScreenshotWatcher.isCandidate` (`:232-236`), `ScreenshotRequests.isCapture` (`:191-193`) and `AppDelegate.pendingAdds` (`:55-64`, `1353-1357`).

**What callers carry today.** Everything keyed by path (drawings, the run's queue, notices, flight images) experiences a rename as data loss followed by a fresh capture.

**Proposed.**
- The index also stores a file identity from the same bulk listing (`.fileResourceIdentifierKey`), and the watcher reports `renamed(from:to:)`.
- `AppDelegate` maps that to a new `Drawings.rename(from:to:)` (rewrite `key`, move the file) and replaces the card with no capture side effects.
- Later, fold the three capture checks into one pure classification: capture, push, reply, stitch or rename.

**Smaller alternative.** Detect renames only, and leave the capture policy as it is.

**Tradeoff.** File identity is not stable across iCloud re-downloads or apps that save by replacing the file. Those cases fall back to today's behavior.

**Verification.**
- Watcher test: renaming a file in a temp folder gives one rename report and no new or removed report.
- Drawings test: the marks survive under the new key.
- E2E: rename a drawn screenshot. `[state] drawings` should show the new path, there should be no `[watcher] new` line, and the pasteboard change count should be unchanged.

### 2. Claude Code: deliver one send per idle period
**Medium-high severity, medium confidence.**

**Observed.**
- `agent-plugin/plugins/vignette/scripts/inbox.sh:23-37` prints every queued `.line` file whenever `turn` is not `busy`.
- Only `UserPromptSubmit` sets `busy` (`scripts/turn.sh:21-25`, `hooks/hooks.json:4`). The repo's own investigation says that hook fires "only when the person types" (`docs/claude-code-without-herdr-2026-09-27.md:18`).
- A line that arrives mid-task "is treated as untrusted background data" (same doc, `:320-324`).
- Vignette reports `.accepted` as soon as the line is in the inbox (`Sources/AgentConnection.swift:380-403`), and Send carries on to the next image in the annotation queue (`AGENTS.md:1188-1190`).

**Inference.** If the person sends a second drawing to the same session while the turn started by the first is still running, the second line is printed mid-turn. The agent may ignore it while the card says Sent. Sending each image of a queued run is the common way to hit this.

**Proposed (the monitor owns this).** After printing one line, `inbox.sh` writes `busy` and prints nothing more until the Stop hook (or the existing interrupt fallback) says the turn is over. The wire format is unchanged. Bump both plugin manifests (`AGENTS.md:1232-1233`).

**Smaller alternative.** Rely on Claude Code batching lines printed in the same tick. This is unverified.

**Tradeoff.** If a printed line never starts a turn (a dialog is up, or the session is signed out), later sends wait. Bound that with a staleness check.

**Verification.**
- Run the staged `inbox.sh` against a temp inbox with a sleeping `CLAUDE_PID`. With two lines queued, one should print; the second should print only after `turn` is set to idle.
- Live, with a scratch config: two sends during one turn should start two turns.

### 3. Thumbnail cache: keep card and screen-size decodes apart
**Medium severity.** Confidence is high on the mechanism; the size of the effect is unmeasured.

**Observed.**
- The cache holds one entry per path (`Sources/Thumbnailer.swift:15-19`). An insert replaces it (`:269-275`), and `cached` accepts any entry at least as large as requested (`:137-144`).
- Hovering a card loads a screen-size decode into that shared cache (`Sources/ThumbnailController.swift:225-227`, `1091-1105`), and so does opening the editor (`Sources/AnnotationController.swift:157-176`).
- Hiding the stack clears only the controller's own `flightImages` (`ThumbnailController.swift:146-150`).
- Two sources say otherwise. AGENTS.md says "screen-size flight decodes are dropped whenever the stack hides" (`:986-988`). The cache's own comment says it is "keyed on `maxPixel` and the colour space" and "would silently hold two" (`Thumbnailer.swift:169-171`).

**Inference.**
- A 3024×1964 capture decodes to about 24 MB, so four hovers fill the 96 MB budget (`:31`). That evicts the warmed card thumbnails, and the next stack open decodes them again.
- Cards that were hovered or opened come back showing screen-size decodes. The header says that wastes memory and shimmers (`:6-10`), and while the stack is up the cards hold them outside the budget's control.

**Proposed.** Key entries by path and tier (card or screen). The card tier stays under the budget. The screen tier gets a small cap and is dropped when the stack hides, which makes the AGENTS.md rule true. Callers do not change.

**Smaller alternative.** Never let a screen decode replace a card entry.

**Tradeoff.** A hovered image briefly has two decodes in memory; the extra card-size one is roughly 0.5 MB.

**Verification.**
- Unit: after a card decode and then a screen decode of the same file, `cached(card size)` still returns the card-size image, and screen decodes do not evict card entries.
- Runtime: hover four cards, dismiss, reopen. `[stack] shown … decoding=` should be 0, and `[state] memory.thumbnails` should stay flat.

### 4. Send: one identity per open image, and no main-thread conversion
**Medium severity, high confidence.**

**Observed.**
- Send's rendering is guarded by the editor session (`AppDelegate.swift:1272`). That guard exists because after Esc and reopening the same image, "the path matches and the session does not" (`AnnotationController.swift:503-506`).
- The answers to the destination listing are guarded by path instead (`AppDelegate.swift:1220`, `1235`). A stale answer from the earlier open can therefore settle the toolbar's target.
- With nothing drawn, Send runs `Thumbnailer.png(from:)` on the main thread (`:1257-1263`). For a non-PNG file that is a full decode and re-encode, and it drops EXIF orientation and DPI (`Thumbnailer.swift:161-167`). The drawn path does apply orientation (`Sources/MarkRendering.swift:540-553`).
- Two separate records map a request back to its card: `sentShots` (`AppDelegate.swift:69`, `1167-1177`) and `watchFolder + record.source` (`:1178-1184`).

**What callers carry today.** `AppDelegate` juggles three identities for one send (session, path, request id), maps outcomes to card states, and keeps a second ledger beside the request records.

**Proposed, smallest first.**
- (a) Guard the list answers on `annotator.session`, as the rendering already is.
- (b) Send with nothing drawn as an empty-drawing rendering on `RenderingQueue`, which is off the main thread and upright.
- (c) `ScreenshotRequests` keeps the sent `Screenshot` for live requests and passes it to both callbacks.
- (d) Add `SendNotice.State(outcome)` beside `CardNotices`.

A separate `Sending` owner is only worth it if more send rules arrive.

**Tradeoff.** For PNG files, (b) re-encodes instead of passing the bytes through. It is slower, but it runs off the main thread, and the person already waits that long for a drawn send.

**Verification.**
- Unit: the outcome-to-state mapping, and that `delivered` carries its source.
- E2E: send a JPEG with orientation 6 and nothing drawn; `image.png` should have swapped dimensions.
- With a slow fake codex: Esc, reopen, and check that only the new session's list settles the target.

### 5. Request and reply bytes on the main thread
**Low-medium severity.** The facts are certain; the stalls are unmeasured.

**Observed.** `ScreenshotRequests` runs on the main actor, and three steps move image bytes there:
- `send` writes the PNG (`Sources/ScreenshotRequests.swift:304-308`).
- `accept` reads, hashes and writes a reply image of up to 64 MB (`:422-438`; `Sources/ReplyProtocol.swift:20-25`).
- `publish` reads it again and writes it into the folder (`:518-528`).

**What callers carry today.** Nothing at the interface. The cost is main-thread time while a person may be drawing.

**Proposed.** Keep the step order and durability, but do the byte work on one serial queue owned by `ScreenshotRequests`. Apply each state change on the main thread in order, the way `Drawings.load` already drops stale answers.

**Smaller alternative.** Move only the image copy and the digest.

**Tradeoff.** `send` becomes asynchronous, so do this after #4.

**Verification.** A Time Profiler run while a 20 MB reply lands during a mark drag should show no main-thread stretch over 8 ms in these frames.

### 6. Make command admission one tested function
**Low-medium severity, high confidence.**

**Observed.** The first error an agent sees comes from a fixed order inside `AppDelegate.run` (`:610-674`): known command, debug, newest-file default, kinds, watch-folder policy, reserved reply, minimum count, readable or missing. The error codes are a contract with agents (`Sources/Commands.swift:4-22`). `CommandsTests` cover the individual checks but not their order.

**Proposed.** `Commands.admit(request, context) -> Result<[Screenshot], (CommandError, String)>`, tested with real temp files.

**Smaller alternative.** Pin the order with E2E checks only.

**Tradeoff.** One more function.

**Verification.** Table tests of which error comes first for mixed inputs.

## Strong modules to preserve
- **The reducers and their event hold:** `AnnotatorTransition`, `AnnotationRun` (with `EventHold`), `EditorCore`, `AnnotatorZoom`, `CardNotices`, `ToolbarOffer` and `FlightPress`.
- **`Drawings` and `DrawingStore`:** one write path, revision checks that drop stale loads, and refusal of files from newer builds. The `OpenDrawing` seam is real: `EditorView` and the tests' `FakeEditor` both implement it.
- **One renderer:** `Rendering`, `Mark.shape` and `MarkLayers` (ADR 0010), plus `RenderingQueue`/`PendingRendering` and the promised clipboard.
- **The request and reply loop:** `ScreenshotRequests` with `ReplyProtocol`, `ReplyCommand` and `scripts/reply`. It keeps acceptance separate from publication, derives every path itself, identifies a reply by a digest of its bytes, hides unpublished files by default, and makes retries safe. It has 24 behavior tests.
- **`AgentConnection`:** a real seam with two production adapters and injected runners for tests.
- **The watcher's index** and its handling of protected folders and unmounted volumes.
- **`AgentPlugins`**, which stages the marketplace beside the old copy and swaps it in whole.

## How the systems interact
- **Path as identity runs through every system.** Only the watcher can see a rename, so #1 gives every path-keyed owner a single event to re-key on.
- **All outbound images start correctly from `Drawings.current`.** But four `AppDelegate` sites (`:494-599`, `1250-1284`) each take their own copy of the current style and decide for themselves what "nothing drawn" means. Item #4 (b) fixes the one case that actually diverges.
- **For Claude Code, "Sent" means accepted into the inbox, not read in a turn.** Item #2 closes the case where an accepted line becomes background data.
- **I would leave the annotator-to-stack handover closures as they are.** They have one adapter on each side, the timing behind them was measured frame by frame, and a direct reference would move the wiring without removing any complexity.
- **Turning an agent on** pairs the plugin with `ClaudeReadRule` and remembers failures (`AppDelegate.swift:239-279`). That could move into `AgentPlugins` the next time it changes.
- **`Settings.shared` is read directly everywhere.** That is acceptable, because renderings capture their style when they are requested.

## Order of work
1. #2 and #3: independent and small.
2. #1: handle renames before changing any capture policy.
3. #4, then #5, since #5 changes `send`'s synchronous contract.
4. #6 at any time, ideally before the next command is added.

## Open decisions
- **What counts as a capture.** Options:
  - any new image (today's behavior);
  - files carrying macOS's screen-capture metadata (I believe `com.apple.metadata:kMDItemIsScreenCapture`, unverified on macOS 14/15 and for recordings);
  - the `screencapture name` prefix.

  Under either stricter rule, stitches would need to be marked as captures explicitly.
- **Whether Claude Code's "Sent" should wait** until the monitor has consumed the line (Vignette could watch the file disappear).
- **Byte pass-through versus re-encode** for a PNG sent with nothing drawn.

## Limits and missing evidence
- Nothing was run, so I have no frequencies for renames, saves to the Desktop or back-to-back sends.
- How Claude Code's hooks behave for turns started by the monitor is inferred from the repo's investigation doc, not observed.
- The cost of adding `.fileResourceIdentifierKey` to the folder listing is unmeasured.
- Unverified: whether `Drawings.sweep` and `ScreenshotRequests.load`, which check paths inside the folder on the main thread at launch, can block on macOS's folder-permission prompt while that permission is undecided.
- `inbox.sh` spawns `cat` and `sleep` roughly every 0.3 s per Claude Code session; the energy cost is unmeasured.
- `applyTweaks` re-decodes every card on the main thread (`ThumbnailController.swift:587-597`).
- I only skimmed the Settings, setup, menu-bar intro and stack views, and `EditorCore`'s internals. I did not assess `media/trailer/` or the E2E harness beyond scenario names.
