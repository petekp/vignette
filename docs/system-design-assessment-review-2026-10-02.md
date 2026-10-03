# Adversarial review of the system design assessment

The main bug diagnoses survived review. The repair plan needs correction. It misses destructive startup paths, understates published reply lifetime, and leaves the snapshot and pending-write contracts incomplete.

Reviewed [assessment](system-design-assessment-2026-10-02.md) against checkout `468b483` on October 2, 2026. The assessment remains intact. This review changes documentation only.

## Findings

**1. High: watcher retention does not protect startup cleanup.**

Assessment locations: lines 43–53, 206, and 225.

The assessment protects drawings from unavailable watcher input, but startup performs destructive reconciliation before the watcher exists. `startDrawings` sweeps every stored drawing key. Its guard checks only the current screenshots folder. An available current folder does not establish whether a drawing's actual folder is available.

Request recovery has another path. It marks a published reply deleted when `fileExists` returns false, then immediately runs retention pruning. A published reply to a request cleared more than seven days ago can lose its publication record during a restart with its volume absent. When the volume returns, the existing managed image is hidden because its published record is gone.

Evidence: [AppDelegate:128](../Sources/AppDelegate.swift#L128), [AppDelegate:441](../Sources/AppDelegate.swift#L441), [Drawings:115](../Sources/Drawings.swift#L115), [ScreenshotRequests:165](../Sources/ScreenshotRequests.swift#L165), [ScreenshotRequests:627](../Sources/ScreenshotRequests.swift#L627), [ScreenshotRequests:183](../Sources/ScreenshotRequests.swift#L183).

Correction: apply confirmed-absence semantics to launch sweeping, request removal detection, and retention. Preserve record loading before visibility consumers. Defer destructive reconciliation until the relevant folder can establish absence. A watcher-only repair leaves these paths active.

Verification must include a cold launch with an unavailable folder and an aged cleared request that has a published reply. Restore the folder and verify the drawing, card visibility, and reply destination remain available.

**2. High: folder identity is already a published-card contract, not only an open reservation decision.**

Assessment locations: line 219 and the repair sequence at 225–229.

The assessment mentions current-folder lookup but mainly frames the decision around reserved replies. It omits a concrete failure for published replies. Publish in folder A, clear the request, switch to folder B, and prune after seven days. Pruning checks B, then deletes the records that keep the file in A visible. Returning to A hides that file and loses its destination.

This violates the current clearing contract, which leaves published cards alone. Unlike finding 1, both folders may be fully available. The failure comes from looking in the wrong folder.

Evidence: [ScreenshotRequests:595](../Sources/ScreenshotRequests.swift#L595), [ScreenshotRequests:629](../Sources/ScreenshotRequests.swift#L629), [ScreenshotRequests:636](../Sources/ScreenshotRequests.swift#L636), [ScreenshotRequests:183](../Sources/ScreenshotRequests.swift#L183), [ScreenshotRequests:206](../Sources/ScreenshotRequests.swift#L206).

Correction: define actual location identity for reserved and published replies before changing recovery or retention. Retention must follow the published file's location and confirmed deletion. Include this in the early correctness work. The policy for where a new pending reply goes after a folder change can remain a separate decision.

Verify publication in A, a change to B, retention pruning, and return to A. Keep this distinct from the unavailable-folder case.

**3. High: the snapshot proposal does not protect promised output files.**

Assessment locations: lines 99–101 and 109.

The proposal freezes drawing values but leaves output lifetime unspecified. Every rendering for a source uses the same annotated filename. Priority rendering can overtake an older queued job. A completed pasteboard item retains fixed PNG bytes while its file URL names the shared file. The older job can overwrite that file after the newer result completes.

Evidence: [AppDelegate:463](../Sources/AppDelegate.swift#L463), [RenderingQueue:27](../Sources/RenderingQueue.swift#L27), [RenderingQueue:38](../Sources/RenderingQueue.swift#L38), [Clipboard:120](../Sources/Clipboard.swift#L120). Send already stores bytes under a unique request directory: [ScreenshotRequests:296](../Sources/ScreenshotRequests.swift#L296).

An isolated check executed the production `RenderingQueue` with a temporary renderer that returned distinguishable bytes. It held one job, queued an earlier ordinary render and a later priority render, then let them finish. The later result's PNG contained `later drawing`; its file contained `earlier drawing`. Compilation and execution both exited successfully. No Vignette app was launched.

Correction: make a promised rendering's bytes and file identity refer to the same result. An immutable backing file per promised result is a credible design. The named annotated file can be a separate convenience output. Specify how long backing files remain usable for external file consumers. Queue ordering alone cannot make a shared path immutable.

Verify overlapping renderings to the same source, priority overtaking, and PNG versus file content. This is a correctness requirement before the larger output workflow refactor.

**4. Medium: pending drawing ownership omits reopening, closing, and quitting.**

Assessment locations: lines 85–89.

The active edit must remain the editor's. Its host snapshot deliberately excludes a gesture still being drawn. After park, the open-drawing adapter returns no drawing, while presentation keeps frozen mark layers for the flight home. Reopening reads the disk directly. A pending failed write owned by `Drawings` would therefore remain invisible to that read unless the interface changes too.

Quit currently asks only an annotator with a current screenshot to store its drawing, then flushes settings. Closing can clear that screenshot before quit. Retaining an accepted drawing in memory does not define how it reaches disk after close, or what happens if the process ends while storage still fails.

Evidence: [EditorCore:643](../Sources/EditorCore.swift#L643), [EditorView:844](../Sources/EditorView.swift#L844), [ThumbnailController:1004](../Sources/ThumbnailController.swift#L1004), [AnnotationController:156](../Sources/AnnotationController.swift#L156), [AppDelegate:112](../Sources/AppDelegate.swift#L112), [AnnotationController:566](../Sources/AnnotationController.swift#L566), [AppDelegate:179](../Sources/AppDelegate.swift#L179).

Correction: `Drawings` should own accepted handovers and pending persistence, while the editor owns the active edit and presentation owns parked layers. Resolve reads from the open editor, then pending accepted state, then disk. Define card updates, retry, pending-memory bounds, final flush, and unresolved-failure behavior. Retain durable revision metadata rather than another complete durable drawing unless a caller needs it.

Verify failed save, close, reopen before retry, storage recovery, quit, and reopen in a new process. State separately what can survive a crash.

**5. Medium: complete reply installation needs a scale invariant, not just a mark-count invariant.**

Assessment locations: lines 61–65.

Replacing a reply's drawing can prevent duplicate marks while changing its stored scale. Reply records hold raw agent marks. Materialization reads current text settings and the main display's scale. Rebuilding after a display change can produce a different drawing even when the mark count stays the same.

The current additive path preserves the existing drawing's `pointScale`, the number of image pixels per drawing point. Stored drawings use that scale across displays. Stored text size also derives from the scale and construction settings.

Evidence: [ScreenshotRequests:101](../Sources/ScreenshotRequests.swift#L101), [AppDelegate:452](../Sources/AppDelegate.swift#L452), [Drawings:159](../Sources/Drawings.swift#L159), [AgentMarks:59](../Sources/AgentMarks.swift#L59), [DrawingStore:80](../Sources/DrawingStore.swift#L80), [MarkRendering:369](../Sources/MarkRendering.swift#L369).

Correction: preserve the first materialized drawing's scale and stored mark sizes during replay, or persist the construction state needed to reproduce them. Current rendering styles can still restyle and reflow marks. This does not require preserving appearance across builds.

Verify recovery with changed display scale and construction text size. Check stored geometry and scale alongside count and publication.

**6. Medium: asynchronous preparation needs an explicit snapshot time and one result per selection.**

Assessment location: line 99.

Capturing open marks immediately and reading stored drawings later gives those inputs different snapshot times. The existing asynchronous drawing loader reads the file when its worker runs and omits results overtaken by writes. That is useful for cards, which also receive change events. An output batch needs a result or failure for every selected screenshot.

The renderer also reads source image bytes later. Its dimension check cannot detect a same-size source replacement. Freezing a drawing value and styles does not freeze the image those marks address.

Evidence: [Drawings:62](../Sources/Drawings.swift#L62), [RenderingQueue:23](../Sources/RenderingQueue.swift#L23), [MarkRendering:526](../Sources/MarkRendering.swift#L526).

Correction: define the chosen drawing revision, source revision, styles, and ordered per-item results. Decide which inputs freeze when the action begins and which resolve during preparation. Preserve the selected state through an owned snapshot or reject a change during preparation. Freezing source bytes has a storage or memory cost; revision checks can return a changed-source failure. A generic asynchronous `current` method does not settle this contract.

Verify edits and source replacement between action, preparation, and rendering. Assert a result or explicit failure for each selected item.

## Recommendations that survived

The watcher false-removal, failed Trash cleanup, repeated reply append, late submission reopening clear, ignored drawing write, stale opening discovery, suppressed settings writes, and incomplete agent-enable results are supported by their current code paths.

The `MarkLayers` recommendation removes actual implementation knowledge from callers. Its planning closure exposes mutable cache records, pending bitmap targets, retention, and layer visibility. Moving those decisions behind a value request is a credible deepening.

Direct annotator composition is also credible. It can remove lifecycle callbacks while preserving `AnnotationRun`, `AnnotatorZoom`, `TransitionLayer`, and native handoff moments. The opening-generation correction is independent and should land first. The larger composition change still needs an explicit interface and native verification before its priority is treated as settled.

The trailer parser finding and use of the existing scratch-launch control survived inspection. The deferred Stitch orientation limitation remains a separate change. Neither authorizes a tooling change or expands another repair's scope.

## Revised repair order

1. Extend confirmed absence across live indexing, startup reconciliation, and retention. Correct published-file location identity and partial Delete cleanup as separate changes.
2. Repair terminal clearing and repeatable reply installation. Include copied files left by failed unpublished replies in clear cleanup. Preserve drawing scale during replay.
3. Guard discovery with the existing opening identity. Specify pending handover reads and termination behavior.
4. Establish promised output identity and snapshot preparation semantics. Then deepen output workflows and mark presentation.
5. Compare concrete interfaces for larger presentation, image, and discovery changes. Rank them by caller knowledge removed and measured cost, alongside settings and complete agent outcomes.

The evidence is source tracing plus one isolated production-queue check. No app build, native interaction, permission test, full suite, or performance measurement was run. Production source, tests, settings, build tooling, and the original assessment were unchanged.
