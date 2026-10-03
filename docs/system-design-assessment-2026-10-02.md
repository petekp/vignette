# Vignette system design assessment

This assessment describes source `468b483`. [The system improvement plan](system-design-work-2026-10-02.md) records implemented fixes, current verification, and remaining decisions.

Vignette has strong deep modules for editing, geometry, annotation runs, and agent delivery. Its largest opportunities are where those modules share lifecycle knowledge: file availability, drawing persistence, rendering snapshots, and the handoff between a flight and the annotator.

Repair deletion authority, reply location and recovery, and promised output identity first. Then define drawing persistence and preparation contracts. Larger presentation and discovery changes are design candidates whose priority depends on the caller knowledge they remove and native verification.

Reviewed checkout: `468b483`, on October 2, 2026. Recommendations are proposals. Evidence comes from current source, callers, existing tests, and two isolated checks: the trailer parser and the production rendering queue with a temporary renderer. Other failure scenarios follow from code traces. No app build, app launch, native interaction, full test suite, or performance measurement was run.

An **interface** includes the ordering, identity, errors, threading, and performance facts a caller must know. A **seam** is where that interface lives. **Depth** is the behavior available through a small interface. **Locality** means that a change and its verification concentrate in one owner.

## Current system map

| System | Assessment | Seam to preserve or improve |
| --- | --- | --- |
| Folder capture and recent inventory | Substantial depth, with an unsafe interpretation of unavailable input. Startup cleanup also bypasses inventory authority. | Separate availability from confirmed removal across watching, launch sweeping, and retention. [ScreenshotWatcher:144](../Sources/ScreenshotWatcher.swift#L144), [AppDelegate:441](../Sources/AppDelegate.swift#L441). |
| Image metadata, thumbnails, and cloud files | Useful behavior is centralized, but callers choose methods with different download and thread rules. | Deepen card and screen-image requests. Preserve color conversion, cache bounds, and recording behavior. [Thumbnailer:42](../Sources/Thumbnailer.swift#L42). |
| Recent stack, selection, and layout | Ordered selection and shared geometry are strong. Presentation state remains widely writable. | Keep selection and `StackLayout`. Revisit the view snapshot after handoff ownership improves. [ThumbnailController:25](../Sources/ThumbnailController.swift#L25), [StackLayout:28](../Sources/StackLayout.swift#L28). |
| Annotation run and transition decisions | Deep modules with useful event/effect interfaces. | Keep `AnnotationRun` owning the queue and `AnnotatorTransition` private to it. [AnnotationRun:12](../Sources/AnnotationRun.swift#L12). |
| Flights, input, shadows, and window handoff | Native rendering constraints are well understood. Their coordination crosses several owners. | Preserve `TransitionLayer` and `FlightPress`. Evaluate direct annotator composition through a concrete interface and native checks. [ThumbnailController:114](../Sources/ThumbnailController.swift#L114). |
| Annotator zoom | Strong separation between rules, geometry, and native effects. | Keep `AnnotatorZoom`, `Zoom`, and `Tween`. Verify frame and picture placement together. [AnnotatorZoom:12](../Sources/AnnotatorZoom.swift#L12). |
| Editor gestures, typing, history, and agent joins | High depth despite a large implementation. | Keep the reducer's event/effect interface and touched-mark undo behavior. Do not make each tool an externally coordinated module. [EditorCore:494](../Sources/EditorCore.swift#L494), [EditorHistory:9](../Sources/EditorHistory.swift#L9). |
| Drawing model and mark geometry | Shared validation and geometry produce consistency across consumers. | Keep `Drawing`, `Mark.shape`, and `TextLayout` as canonical owners. [Drawing:1](../Sources/Drawing.swift#L1), [MarkRendering:325](../Sources/MarkRendering.swift#L325). |
| On-screen mark rendering | Deep implementation behind an interface that exposes mutable cache records. | Move bitmap planning, retention, and visibility inside `MarkLayers`. [MarkLayers:45](../Sources/MarkLayers.swift#L45). |
| Drawing storage and live state | `DrawingStore` is useful. Completed handovers can lose their persistence outcome. | Keep active editing in the editor. Give `Drawings` pending-write reads, retry, and shutdown responsibilities. [Drawings:38](../Sources/Drawings.swift#L38). |
| Copy, drag, Send, and Stitch | Serialization and promised pasteboard data are useful seams. Fixed bytes can disagree with a reused output filename. | Establish immutable output identity and explicit preparation results before sharing workflow implementation. [AppDelegate:463](../Sources/AppDelegate.swift#L463), [Clipboard:120](../Sources/Clipboard.swift#L120). |
| Agent discovery and delivery | Two real adapters justify `AgentConnection`. Discovery lifetime is spread across the app and toolbar. | Preserve exact session addressing and distinct delivery outcomes. Tie discovery to one annotator opening. [AgentConnection:199](../Sources/AgentConnection.swift#L199). |
| Request acceptance and reply publication | Strong overall ownership, with gaps in durable transitions, file location, and replay. | Keep tickets, receipts, visibility, and recovery in `ScreenshotRequests`. Record actual reply locations and preserve materialized drawings during replay. [ScreenshotRequests:400](../Sources/ScreenshotRequests.swift#L400). |
| Agent plugin and image-read permission | Packaging and native client installation are useful modules. Complete enablement is assembled outside them. | Return installation and permission outcomes together. Preserve the narrower script installation operation. [AppDelegate:252](../Sources/AppDelegate.swift#L252). |
| Settings and Apple screenshot preferences | Defaults, migration, live reload, and motion policy are useful depth. Runtime validation and save outcomes are inconsistent. | Keep one settings owner. Separate live application from durable save status. [Settings:667](../Sources/Settings.swift#L667). |
| Setup, shortcut, focus, and permissions | Native mechanisms have useful specialized owners. Setup completion contains application effects. | Preserve `HotKeySpec`, Carbon/modifier adapters, `Accessibility`, and `FocusReturn`. Share readiness facts before considering a setup refactor. [SetupWindow:159](../Sources/SetupWindow.swift#L159), [AppDelegate:807](../Sources/AppDelegate.swift#L807). |
| Install location, login, and updates | Specialized native modules hide meaningful platform behavior. | Preserve `AppLocation`, `LoginItem`, and `Updater`. Their mechanisms do not need a generic window or lifecycle framework. [AppLocation:13](../Sources/AppLocation.swift#L13), [Updater:12](../Sources/Updater.swift#L12). |
| Commands, state reports, logs, and verification | URL parsing and structured state are useful automation seams. Cross-module failure coverage has gaps. | Keep command policy and correlated state reports. Verify composition with real local stores. [Commands:1](../Sources/Commands.swift#L1), [StateReport:1](../Sources/StateReport.swift#L1). |
| Build, release, trailer, and site | Build identity and isolated product verification are deliberate. Trailer source rewriting bypasses an existing seam. | Use existing launch controls for trailer isolation. Keep the static site simple. Build/release tooling changes require separate approval. [trailer.py:120](../media/trailer/trailer.py#L120), [building](building.md). |

## Ranked opportunities

**1. Require confirmed deletion across watching, startup, and retention. Fix first.**

An unavailable folder can report every screenshot as removed. The watcher distinguishes unreadable input from an empty listing, then collapses unreadable input to an empty inventory after indexing. Its removal callback deletes stored drawings and updates reply tracking.

Evidence: [ScreenshotWatcher:156](../Sources/ScreenshotWatcher.swift#L156), [ScreenshotWatcher:243](../Sources/ScreenshotWatcher.swift#L243), [AppDelegate:1368](../Sources/AppDelegate.swift#L1368), [Drawings:102](../Sources/Drawings.swift#L102).

Startup has independent destructive consumers. Drawing sweeping checks whether the current screenshots folder exists, then tests every stored drawing's path. The current folder being available does not establish that another drawing's folder is available. Request loading marks published replies deleted from `fileExists`, then runs retention pruning. A restart while a volume is absent can discard the record that keeps an aged cleared request's published reply visible.

Evidence: [AppDelegate:128](../Sources/AppDelegate.swift#L128), [AppDelegate:441](../Sources/AppDelegate.swift#L441), [Drawings:115](../Sources/Drawings.swift#L115), [ScreenshotRequests:165](../Sources/ScreenshotRequests.swift#L165), [ScreenshotRequests:627](../Sources/ScreenshotRequests.swift#L627).

Use one confirmed-absence rule across those consumers. Distinguish successful listing, missing folder, refused access, and other unavailability. Retain the last successful inventory during unavailability. Report folder status separately. Destructive reconciliation must concern each file's actual folder and wait until that folder can establish absence. Request records must still load before visibility consumers; loading them need not perform deletion.

Track enumerated presence separately from modification dates. A successful listing currently omits a candidate whose date cannot be read, which can also become a false removal. Keep it present with its known date or an explicit unknown date. Evidence: [ScreenshotWatcher:259](../Sources/ScreenshotWatcher.swift#L259).

The explicit Delete action has a distinct outcome bug. It records failed Trash operations, then removes every requested card and drawing. Cleanup should receive only successfully removed screenshots. Repair this separately through the action result. Evidence: [AppDelegate:474](../Sources/AppDelegate.swift#L474).

Preserve silent initial indexing, background permission reads, stable-file polling, and the missing-then-mounted capture cutoff. Deepen the existing inventory and reconciliation interfaces; no general filesystem framework is required.

Verify failed listing after indexing, failed metadata for an enumerated file, cold launch with an unavailable folder, and return of an aged cleared request's published reply. Assert drawing preservation, card visibility, and reply destination. Verify confirmed later deletion and partial Trash failure as separate cases. Extend the existing watcher, drawing, and retention coverage at their owners.

**2. Preserve reply location and complete drawing installation during recovery. Fix first.**

Published replies need their actual file location. Pruning checks only the current screenshots folder. Publish in folder A, clear the request, switch to B, then prune after seven days: the file in A remains, but its request and publication records can be deleted. Returning to A hides the managed image and loses its destination. Both folders can be fully available.

Evidence: [ScreenshotRequests:595](../Sources/ScreenshotRequests.swift#L595), [ScreenshotRequests:629](../Sources/ScreenshotRequests.swift#L629), [ScreenshotRequests:636](../Sources/ScreenshotRequests.swift#L636), [ScreenshotRequests:183](../Sources/ScreenshotRequests.swift#L183), [ScreenshotRequests:206](../Sources/ScreenshotRequests.swift#L206).

Record the actual location of reserved and published replies inside `ScreenshotRequests`. Clearing, recovery, removal detection, and retention must use that location. Published records remain while their file exists or its absence is unconfirmed. The destination policy for a new accepted reply after a folder change is a separate choice. Once a file is reserved, its cleanup and recovery cannot guess a new location from current settings.

Publication also needs repeatable drawing installation. The drawing is written before the published record commits. Recovery of a reserved reply calls the additive mark operation again, appending the same marks.

Evidence: [ScreenshotRequests:502](../Sources/ScreenshotRequests.swift#L502), [ScreenshotRequests:551](../Sources/ScreenshotRequests.swift#L551), [AppDelegate:1158](../Sources/AppDelegate.swift#L1158), [Drawings:160](../Sources/Drawings.swift#L160).

Keep two distinct operations at the drawing seam. An ordinary agent push appends marks, including into an open editor as one undo step. A hidden reserved reply installs its complete drawing. Repeating installation must preserve one set of marks, its first materialized scale, and its stored mark sizes.

`pointScale` is the number of image pixels per drawing point. Construction samples current text settings and the main display's scale. Rebuilding raw marks after a display or settings change can alter a drawing even when its mark count is unchanged. Preserve the materialized drawing or the construction state needed to reproduce its stored geometry. Current rendering styles can continue restyling and reflowing it.

Evidence: [AppDelegate:452](../Sources/AppDelegate.swift#L452), [AgentMarks:59](../Sources/AgentMarks.swift#L59), [DrawingStore:80](../Sources/DrawingStore.swift#L80), [MarkRendering:369](../Sources/MarkRendering.swift#L369).

Complete installation belongs in `Drawings`. Publication, location, and visibility remain in `ScreenshotRequests`. These are separate focused repairs within existing owners. Acceptance still means ownership of payload bytes; publication permits the card to appear.

Extend recovery coverage with a real scratch `DrawingStore`. Restart after the drawing is written but before publication commits. Change display scale and construction text size, then check stored scale, geometry, one set of marks, and one published reply. Separately verify A-to-B folder changes, pruning, and return to A.

**3. Make request clearing terminal and durably committed. Fix first.**

A delayed submission answer can reopen a cleared request. `clear` sets its status to cleared. `finishSubmission` later replaces that status without checking it. The resulting record can take replies again.

Evidence: [ScreenshotRequests:323](../Sources/ScreenshotRequests.swift#L323), [ScreenshotRequests:337](../Sources/ScreenshotRequests.swift#L337), [ScreenshotRequests:647](../Sources/ScreenshotRequests.swift#L647).

Clear and failure transitions also ignore write errors. Clear can remove owned files and answer success while the durable request still has its earlier state. Acceptance and publication already check persistence before proceeding.

Copied files remain owned after an unpublished reply fails. Publication can write its PNG, then move the record to failed. Clear currently removes the PNG only for a reserved record, leaving a failed reply's hidden file behind. Cleanup must cover all owned unpublished files at their recorded locations. Evidence: [ScreenshotRequests:527](../Sources/ScreenshotRequests.swift#L527), [ScreenshotRequests:579](../Sources/ScreenshotRequests.swift#L579), [ScreenshotRequests:652](../Sources/ScreenshotRequests.swift#L652).

Consolidate transitions inside the existing request module. Each transition should specify allowed starting states, durable commit, and subsequent effects. Clear must remain terminal when client submission answers. Record uncertainty when an external submission may have started but its result was not stored. Preserve the rule against automatic delivery retries.

Use the existing connection adapter to delay an answer, clear the request, release the answer, and restart. Verify that it remains cleared and refuses a new reply. Verify write refusal before destructive effects and cleanup after failure following PNG creation. Preserve published files. Existing clear coverage delays drawing installation, which exercises a different lifecycle.

**4. Give drawing handovers explicit persistence and lifetime. Define the contract before changing ownership.**

A drawing handed to the host is not necessarily stored. The editor clears its handoff flag when it emits a drawing. The app discards the write result. An agent join also changes the live editor before storage succeeds, so a failed command can leave marks present in memory.

Evidence: [EditorCore:636](../Sources/EditorCore.swift#L636), [EditorView:851](../Sources/EditorView.swift#L851), [AppDelegate:116](../Sources/AppDelegate.swift#L116), [Drawings:146](../Sources/Drawings.swift#L146).

Keep the editor as owner of the active edit. Its host snapshot excludes a gesture still being drawn. Let `Drawings` own completed handovers, pending persistence, and durable revision metadata. Presentation keeps the parked mark layers used by a flight; those layers are not a drawing store.

Reads should resolve from the open editor, then a pending handover, then disk. Route annotator reopening, cards, and output preparation through that contract. Reopening currently reads disk directly, so retaining a failed write alone would not make its drawing available.

Evidence: [EditorCore:643](../Sources/EditorCore.swift#L643), [EditorView:844](../Sources/EditorView.swift#L844), [ThumbnailController:1004](../Sources/ThumbnailController.swift#L1004), [AnnotationController:156](../Sources/AnnotationController.swift#L156), [AppDelegate:112](../Sources/AppDelegate.swift#L112).

Define the following inside the persistence owner before implementation:

- Retain the latest pending drawing per screenshot. Preserve one undo step, unrelated typing, and selection.
- Specify when a handover updates cards. Current visible state and durable state must remain distinguishable.
- Retry pending writes without replaying an editor mutation. A retry cannot add the same agent marks again.
- Bound pending memory without silently dropping an unsaved drawing. Keep durable revision metadata rather than another complete durable drawing unless a caller needs it.
- Keep pending handovers after editor park and clear. On quit, attempt their final write independently of whether the annotator is open. Return an unresolved storage outcome when that write fails.

Quit currently asks only an annotator with a current screenshot to store its drawing, then flushes settings. That does not flush a new pending drawing owner after close. Evidence: [AnnotationController:566](../Sources/AnnotationController.swift#L566), [AppDelegate:179](../Sources/AppDelegate.swift#L179).

In-memory retention does not survive process termination or a crash. Claim persistence only after a durable write succeeds. A stronger crash-survival requirement would need a separate justified design.

Verify failed save, close, reopen before retry, storage recovery, final quit write, and reopen in a new process. Also verify unresolved storage failure. Extend existing live-editor precedence, stale-load, and agent-join coverage rather than exposing filesystem policy to `EditorCore`.

**5. Stabilize promised outputs, then define rendering preparation. Repair output identity first.**

Fixed rendering bytes can disagree with their output file. Each source reuses one annotated filename. A priority rendering can overtake an older queued job, then that older job overwrites the newer rendering's file. A pasteboard item keeps fixed PNG bytes but returns the shared file URL.

Evidence: [AppDelegate:463](../Sources/AppDelegate.swift#L463), [RenderingQueue:27](../Sources/RenderingQueue.swift#L27), [RenderingQueue:38](../Sources/RenderingQueue.swift#L38), [Clipboard:120](../Sources/Clipboard.swift#L120).

An isolated check used the production queue with a temporary renderer. It held one job, queued an earlier ordinary rendering and a later priority rendering, then released them. The later result's PNG held `later drawing`; its file held `earlier drawing`. The check compiled and exited successfully. No app or native pasteboard interaction was involved.

A promised rendering must have one result identity for its PNG and backing file. An immutable backing file per result is a credible design. If the named annotated file remains part of the output contract, treat it as a separate convenience output. Queue ordering alone cannot protect references to a shared path.

The file lifetime must cover external consumers. A pasted terminal path can be read after clipboard replacement or app restart. Define an owned on-disk retention policy before implementing backing files. Active promises must remain valid; fulfilling a promise or ending a drag does not prove the external file is no longer needed. The retention duration and storage limit remain decisions, not implicit deletion rules.

Send already stores fixed bytes under a unique request directory. Preserve that useful depth. Evidence: [ScreenshotRequests:296](../Sources/ScreenshotRequests.swift#L296).

Drawing preparation needs its own explicit result. Copy Drawing, Stitch, drag, and Send assemble drawing selection, styles, scheduling, output paths, and completion handling. Stored retrieval can read image headers and lay out text on the main actor; drag uses a cached card drawing instead.

Evidence: [AppDelegate:395](../Sources/AppDelegate.swift#L395), [AppDelegate:494](../Sources/AppDelegate.swift#L494), [AppDelegate:546](../Sources/AppDelegate.swift#L546), [AppDelegate:577](../Sources/AppDelegate.swift#L577), [Drawings:43](../Sources/Drawings.swift#L43).

An asynchronous preparation interface must define the chosen drawing revision, source revision, styles, and an ordered result or failure for every selected screenshot. The existing `Drawings.load` omits answers overtaken by writes because cards also receive change events. An output batch cannot silently omit those items.

Evidence: [Drawings:62](../Sources/Drawings.swift#L62), [RenderingQueue:23](../Sources/RenderingQueue.swift#L23).

Capture the open editor's completed host snapshot and styles when the action starts. For stored drawings, either preserve a selected revision through an owned snapshot or resolve a revision during preparation and identify it explicitly. Those timings must be part of the interface. Do not call later disk reads an action-time snapshot.

Source pixels also need a defined lifetime. Rendering opens the image later, and its dimension check cannot detect a same-size replacement. Frozen source bytes give a stronger guarantee at a memory or storage cost. A source revision check can instead return a changed-source failure. Choose the required guarantee before sharing workflow implementation.

Evidence: [MarkRendering:526](../Sources/MarkRendering.swift#L526).

The drawing owner should hide open-versus-pending-versus-stored precedence. Rendering should hide batch completion and scheduling. Preserve immediate drag data through a prepared value or native promise. Clipboard and delivery remain with their owners.

Keep output intent explicit: an unmarked Copy uses the original, Send requires PNG bytes, and Stitch deliberately scales and composites. A shared preparation module must preserve those differences.

Rendering and Stitch also need the same displayed-image contract. Rendering applies orientation. Stitch uses raw dimensions, so oriented agent images can lose or misplace marks. Share displayed dimensions and transforms internally while retaining Rendering's color, alpha, DPI, and untouched pixels, and Stitch's bounded output and one-piece decoding.

Evidence: [MarkRendering:476](../Sources/MarkRendering.swift#L476), [Stitch:98](../Sources/Stitch.swift#L98), [Stitch:121](../Sources/Stitch.swift#L121).

[TODOs](TODOS.md) records the orientation limitation as deferred. Its small repair is independent of the output redesign and less urgent than deletion, recovery, and promised-file failures.

Verify overlapping priority renderings and agreement between PNG bytes and file contents. For preparation, change drawings and source files between action, preparation, and render; include a same-size replacement. Assert one result or explicit failure per selected item. Reuse existing rendering, drawing, and Stitch coverage. Measure responsiveness before claiming a performance gain.

**6. Guard opening-scoped work, then evaluate complete handoff ownership. Fix the generation check independently.**

A screenshot path identifies the file. It does not identify a particular opening. Decode and Send already use an opening generation. Destination discovery guards only on file path, so a late answer can affect a later opening of the same image.

Evidence: [AnnotationController:145](../Sources/AnnotationController.swift#L145), [AnnotationController:503](../Sources/AnnotationController.swift#L503), [AppDelegate:1220](../Sources/AppDelegate.swift#L1220), [AppDelegate:1235](../Sources/AppDelegate.swift#L1235).

The immediate discovery correction can capture and compare the existing `AnnotationController.session`. It needs no new counter and can be verified independently of presentation restructuring. Then make that opening identity consistent across the presentation interface. Replace competing generation conventions where their lifetimes are the same. Retain file identity for storage and request/reply identity for durable agent work.

The visual handoff also exposes prepare, show, land, hide, abandon, press, marks, and toolbar-space callbacks. The caller must wire them correctly. The controller separately tracks loaded images, window input readiness, parked marks, and flights.

Evidence: [AppDelegate:95](../Sources/AppDelegate.swift#L95), [ThumbnailController:114](../Sources/ThumbnailController.swift#L114), [ThumbnailController:171](../Sources/ThumbnailController.swift#L171), [ThumbnailController:475](../Sources/ThumbnailController.swift#L475).

Direct annotator composition is a credible candidate for removing the lifecycle callback interface. Define the external drawing intents and outcomes first. Compare how much image, marks, shadow, and input knowledge that interface removes from callers. Keep `AnnotationRun` as the queue owner and avoid parallel phase state. The generation-check repair does not depend on this larger change.

Preserve `TransitionLayer`'s separate covered, arrived, and lifted moments. They represent different native behaviors. Keep keys during flight, buffered press delivery, midflight reversal, and atomic shadow transfer.

Sequence tests should exercise readiness arriving in different orders and stale work after reopening. Real product verification must prove frame, shadow, and input ownership. Pure reducer tests cannot establish window-server behavior. Set the priority of the larger composition change after comparing the concrete interface and native verification cost.

**7. Hide mark cache decisions behind a presentation request. Strong candidate for deepening.**

`MarkLayers` exposes its mutable text cache to an editor planning closure. The caller changes desired bitmaps, clears layers, checks pending work, enforces memory bounds, and decides visibility. That is implementation knowledge crossing the seam.

Evidence: [MarkLayers:45](../Sources/MarkLayers.swift#L45), [EditorLayers:127](../Sources/EditorLayers.swift#L127).

Let the caller supply a value describing viewport, resolution, motion, typing, and covered mark identities. `MarkLayers` should own cache retention, pending targets, arrival, and layer visibility. Whole-image cards/flights and a zoomed editor are two real presentation requirements.

Keep this change within the existing module. A private pure planner may help. An external rendering protocol would add no useful variation.

Existing editor and card tests cover adoption, stale work, parking, continuous text visibility, and bitmap bounds. Keep that proof through the smaller interface. Preserve separate queues so card work cannot delay the note being edited.

**8. Centralize validation and report complete settings and agent outcomes. Medium priority.**

Settings validates boot and external file input, but `update` applies the caller's mutation directly. Live save errors are suppressed. It updates its last-written state and logs UI values as written before checking whether the write succeeded.

Evidence: [Settings:668](../Sources/Settings.swift#L668), [Settings:807](../Sources/Settings.swift#L807).

Route every settings mutation through the same validation rule. Publish live settings immediately for fluid controls, but track durable save status separately. Advance last-written state only after success. Keep differences-only UI storage, reload behavior, Apple reconciliation direction, and motion policy.

The settings module can take its file location and Apple preference implementation internally. Production and scratch launches are real variation. No protocol is needed for every setting or filesystem operation. Existing tests already use temporary files for loading and boot behavior; runtime save failure is the missing independent contract.

Agent enablement has a similar incomplete outcome. Turning Claude Code on installs the plugin and adds its read permission. The app ignores the permission operation's failure and returns plugin success. Removing it does the same for permission removal.

Evidence: [AppDelegate:252](../Sources/AppDelegate.swift#L252), [AppDelegate:272](../Sources/AppDelegate.swift#L272), [ClaudeReadRule:32](../Sources/ClaudeReadRule.swift#L32).

Have `AgentPlugins` own complete enablement and return plugin and permission outcomes together. Preserve install-plugin-only for the script command, whose authorization is narrower. Setup and Settings should display the complete outcome.

These are separate changes in existing owners. Do not combine them into a general transaction abstraction.

**9. Deepen image requests and destination discovery after their identities are clear. Medium priority.**

Card warming, hover, flights, and the annotator can independently request the same screen decode. They also implement cache and fallback choices themselves.

Evidence: [Thumbnailer:291](../Sources/Thumbnailer.swift#L291), [ThumbnailController:397](../Sources/ThumbnailController.swift#L397), [ThumbnailController:1076](../Sources/ThumbnailController.swift#L1076), [AnnotationController:152](../Sources/AnnotationController.swift#L152).

Evaluate coalescing pending work inside `Thumbnailer` while preserving its existing card and screen purposes. The image request owns file revision, required resolution, color space, and shared cache behavior. Presentation still decides how long its editor and flights need a decode. Make those consumer lifetimes explicit rather than treating all requests as one annotator opening. Preserve placeholder recordings remaining undownloaded and placeholder images downloading in the background.

Destination discovery similarly spreads cached/fresh/complete interpretation between requests, the app, destination values, and the toolbar. A session-discovery module could own caching, focus evidence, and opening-scoped answers. Keep the person's explicit selection in the toolbar and delivery in `AgentConnection`.

Evidence: [ScreenshotRequests:212](../Sources/ScreenshotRequests.swift#L212), [AppDelegate:1207](../Sources/AppDelegate.swift#L1207), [AnnotatorToolbar:106](../Sources/AnnotatorToolbar.swift#L106).

Return a typed discovery result that distinguishes empty success, partial answers, and failure. App-server errors currently collapse into an empty list. Subprocess deadlines also need a firm completion contract: sending termination followed by an unbounded EOF/exit wait does not guarantee the advertised timeout.

Evidence: [AppServer:106](../Sources/AppServer.swift#L106), [AgentConnection:237](../Sources/AgentConnection.swift#L237).

Use small local responder programs for process/protocol verification. Keep JSON-RPC in `AppServer`. A persistent transport or new agent integration is unnecessary.

**10. Use the existing launch seam in trailer tooling. Small, concrete improvement.**

The trailer rewrites private tool-search arrays in copied Swift source. Its parser expects a static array declaration. Codex's paths are now a computed property, so the patch fails before the build.

Evidence: [trailer.py:87](../media/trailer/trailer.py#L87), [trailer.py:125](../media/trailer/trailer.py#L125), [AgentConnection:559](../Sources/AgentConnection.swift#L559).

An isolated invocation of that parser against current source confirmed the error: `build: no binaryPaths in CodexConnection; the stage patch needs updating`. This check executed only the parser. It did not build or launch the trailer.

The app already suppresses real Codex and Herdr discovery on a scratch-settings launch unless an explicit tool is supplied. Use that existing requirement and launch interface. Remove the superseded source patches rather than repairing their pattern.

Evidence: [AgentTools:35](../Sources/AgentTools.swift#L35), [drive.py:775](../media/trailer/drive.py#L775).

The separate bundle identity and staged media remain useful. Keep E2E and trailer scenario orchestration separate unless a concrete shared need appears. Editing build or release tooling requires specific approval.

## Holistic design and sequence

The recurring problem is an owner receiving a weaker fact and treating it as a stronger one.

| Fact crossing a seam | Stronger claim currently made | Owner that should decide |
| --- | --- | --- |
| A file's folder is unavailable | The file was deleted | Inventory and destructive reconciliation |
| Trash was attempted | Every selected screenshot was removed | Delete action result |
| Drawing was handed over | The latest drawing is durable | `Drawings` |
| Reply filename is absent in the current folder | A published reply can be pruned | Recorded reply location and retention |
| Reply drawing was written | Repeating publication preserves the drawing | Complete drawing installation plus request publication |
| Rendering produced fixed PNG bytes | Its shared file still contains those bytes | Promised output identity |
| Client answered | Any previous request state can be replaced | `ScreenshotRequests` transitions |
| File path matches | The asynchronous answer belongs to this opening | Annotator opening identity |
| Plugin installed | The client can read a sent image | Complete agent enablement |
| Save was attempted | Settings were written | Settings persistence |

Application composition belongs in `AppDelegate`. Request records must load before the watcher and thumbnail warming so unfinished replies remain hidden. Destructive launch reconciliation must wait for confirmed absence at each file's actual location. Focus tracking starts before the first window, and Apple reconciliation precedes capture admission. Preserve those useful orderings without treating startup cleanup as safe merely because it runs early.

What should leave the app delegate is implementation policy: bitmap queue completion, renderer fallback sequences, destination freshness interpretation, and visual handoff timing. Moving these behind their owners will make the composition shorter as a consequence.

Preserve distinct identities and outcomes throughout the changes:

- A file path identifies a stored screenshot and its drawing. A source revision identifies the pixels chosen for one output.
- An opening identity identifies one period in the annotator.
- A request, reply, and attempt each have their own durable identity. A reserved or published reply also has a recorded file location.
- A promised rendering has a result identity shared by its bytes and backing file.
- Live changes, stored drawings, accepted replies, published replies, and client delivery are separate facts.
- Visual coverage, settled arrival, image readiness, and input readiness are separate moments.
- Displayed image pixels and screen points are separate coordinate systems.

Published reply location is a correctness contract. Folder changes cannot justify discarding its publication record. Reservation and publication must establish actual locations used by cleanup, recovery, and retention. Separately decide where a newly accepted reply should go after a folder change. Promised output retention and source snapshot timing are also required interface decisions before rendering preparation changes.

Dependency choices should follow actual variation. Pure reducers and geometry need no adapters. Local stores can be verified in temporary folders. AppKit and ImageIO remain concrete internal implementations with native verification. Claude Code and Codex already justify two agent adapters. Add no new port merely to give a class a protocol.

Recommended sequence:

1. Repair confirmed deletion across watching, startup, and retention. Correct published reply locations and partial Delete cleanup as separate changes.
2. Repair terminal clearing and complete reply installation. Clean owned failed unpublished files and preserve the materialized drawing's scale during replay.
3. Stabilize promised rendering identity and define backing-file retention. Verify priority overtaking and PNG/file agreement before the workflow redesign.
4. Guard discovery with the existing annotator session. Define pending handover reads, retry, bounds, and shutdown behavior. These are independent changes.
5. Define preparation timing, source revisions, and ordered per-item results. Then deepen rendering workflows and `MarkLayers` presentation. Keep any chosen Stitch orientation repair separate.
6. Compare concrete interfaces for presentation, image loading, and destination discovery. Rank them by caller knowledge removed, native verification cost, and measured performance. Tighten settings and complete agent outcomes in their own modules. Apply the trailer simplification with specific tooling approval.
7. Reassess remaining stack flags and setup effects after the selected changes. Extract only responsibility that remains shared.

For each slice, retain existing behavior tests and extend the owner whose interface changes. Use real scratch storage for cross-module durability, sequence tests for pure state, and isolated native launches for pixels, focus, permissions, and responsiveness. Avoid a second test layer that repeats the same contract with callbacks that supply the behavior being tested.

The assessment was checked against current callers and existing coverage. The trailer parser failure and rendering queue/file mismatch were executed in isolation. Native race repairs and performance improvements remain unmeasured. Production code, tests, settings, build tooling, and running apps were left unchanged.
