# Vignette system design synthesis

This assessment describes source `468b483`. [The system improvement plan](system-design-work-2026-10-02.md) records implemented fixes, current verification, and remaining decisions.

Preserve the existing reducers, shared mark geometry, native rendering, and agent adapters. Improve the seams where file identity, an annotator opening, durable state, and output lifetime cross those modules.

The two independent assessments add useful opportunities. The strongest new repair is unmarked Send: use the existing renderer so image orientation and DPI are handled consistently. Rename preservation is also a real data issue, but its design reaches several owners. Cache tiers and new presentation values need stronger lifetime contracts before implementation.

Inputs: [Opus 5.5 at max effort](system-design-opus-5-5-2026-10-02.md) and [Fable 5.1 at max effort](system-design-fable-5-1-2026-10-02.md). Each received the same short instructions and read-only filesystem access. Neither was given the existing assessments or the other model's result. Both completed successfully with no stderr output. The reviewed source and maintained context stayed unchanged at `468b48397dff0cc776c36b6a01199cc886f4167b`.

The [system assessment](system-design-assessment-2026-10-02.md) remains the detailed system map. This synthesis records the verified interpretation of the two additional opinions.

## Agreements and differences

| Concern | Opus | Fable | Synthesis |
| --- | --- | --- | --- |
| Pure decisions and geometry | Preserve the reducers and shared renderer. | Preserve them; their interfaces already concentrate behavior. | Agree. Keep editing, history, queue continuation, zoom, notices, and geometry with their current owners. |
| Durable requests and drawings | Describes them as deep and safe to preserve. | Describes them as strong modules worth keeping unchanged. | Preserve ownership, then repair current implementation failures. Depth and test counts do not prove deletion, replay, clear, or output safety. |
| File identity and arrival | Add rename events, then classify arrivals. | Concentrate pending pushes and source-notice mappings. | Define identity and completion at the arrival seam. Supported files, managed replies, and pushes waiting for marks are distinct facts. |
| Send | Reuse background rendering for unmarked images and guard discovery by opening identity. | Extract push/Send state and reduce destination-settling coordination. | Make the two small correctness repairs first. A new Send module is unnecessary for them. |
| Discovery | Keep most wiring; use the existing generation guard. | Concentrate cached/fresh/focus settlement. | Immediate guard is settled. A smaller typed discovery interface is a candidate; explicit target selection stays in the toolbar. |
| Image loading | Separate card and screen cache entries. | Preserve the cache; improve callers when needed. | Separate purposes where justified. The active editor and return flight must retain compatible screen images. Measure memory and decode churn. |
| Native handoff | Leave callbacks; a direct reference can merely move wiring. | Add a small flight-landing value when touching this area. | Neither callback count nor a new value establishes depth. Require a complete handoff interface that removes caller knowledge and avoids duplicate arrival state. |
| Settings | Global reads are acceptable when outputs capture styles. | Inject values through existing tweak paths gradually. | Use value snapshots where consistency requires them. Avoid a blanket singleton-removal campaign and preserve independent Reduce Motion updates. |
| Tooling and tests | Did not assess trailer tooling in depth. | Remove source patches; investigate ScreenCaptureKit for pixel tests. | Trailer simplification is supported. Native capture replacement needs feasibility proof on supported macOS versions. |

## Priorities and proposed seams

**1. Keep deletion, recovery, and output safety first. High confidence from code traces and the earlier queue check.**

The independent reports praise useful module shapes, but the current implementation still has four urgent contracts to repair:

- Unavailable inventory becomes removal. Startup sweeping and request retention also infer deletion from failed existence checks.
- Reply files are reconstructed in the current folder, so switching folders can discard the record that keeps a published reply visible.
- Reserved reply recovery repeats additive mark installation, and late submission answers can overwrite cleared requests.
- Fixed PNG results share a mutable annotated output filename, so older work can overwrite a newer result's backing file.

Evidence: [ScreenshotWatcher:156](../Sources/ScreenshotWatcher.swift#L156), [AppDelegate:441](../Sources/AppDelegate.swift#L441), [ScreenshotRequests:165](../Sources/ScreenshotRequests.swift#L165), [ScreenshotRequests:636](../Sources/ScreenshotRequests.swift#L636), [ScreenshotRequests:533](../Sources/ScreenshotRequests.swift#L533), [ScreenshotRequests:337](../Sources/ScreenshotRequests.swift#L337), [RenderingQueue:27](../Sources/RenderingQueue.swift#L27), [Clipboard:120](../Sources/Clipboard.swift#L120).

Keep these repairs inside the existing owners. Complete reply installation must preserve materialized scale and geometry. Published records follow actual file locations and confirmed absence. A promised rendering's bytes and file must identify one result. The corrected assessment specifies their verification.

**2. Unify unmarked Send with the existing renderer. Confirmed mechanism and isolated reproduction.**

Unmarked Send synchronously calls a conversion helper. For a non-PNG source, the helper decodes raw pixels and writes PNG without orientation or DPI properties. The drawn path applies displayed orientation and retains DPI.

Evidence: [AppDelegate:1257](../Sources/AppDelegate.swift#L1257), [Thumbnailer:146](../Sources/Thumbnailer.swift#L146), [MarkRendering:526](../Sources/MarkRendering.swift#L526).

A disposable check executed the unchanged production conversion methods with a generated JPEG. ImageIO displayed it as 2×4 pixels with orientation 6 and DPI 144. The converted PNG was 4×2, with orientation and DPI unset. This proves the conversion divergence, not its performance cost.

Use the existing `RenderingQueue` and `Rendering` for an empty drawing. Retain the opening guard and existing failure handling. Preserve unmarked Copy's original-file behavior. PNG byte pass-through can remain an internal optimization if it satisfies the displayed-image contract; routing through the renderer otherwise re-encodes PNGs and can change representation or ancillary metadata.

The same conversion helper has clipboard and reply-helper consumers. Inspect their distinct contracts before changing it globally. Verify Send with an oriented source through the real product path.

**3. Concentrate opening-scoped discovery and exact source identity. High confidence on the identity defects.**

Both reports identify the path-only guard for destination answers. Capture and compare the existing `AnnotationController.session` at both asynchronous continuations. This is independent of any discovery redesign.

Evidence: [AppDelegate:1220](../Sources/AppDelegate.swift#L1220), [AppDelegate:1235](../Sources/AppDelegate.swift#L1235), [AppDelegate:1272](../Sources/AppDelegate.swift#L1272).

The exact source URL captured at Send is stronger than the current folder plus a basename. Reject Fable's smaller alternative of making delivery notices reconstruct the URL that way. Moving the map into `ScreenshotRequests` is reasonable only if its lifetime covers later reply failures, not just delivery. An in-memory mapping also cannot resolve source identity after restart.

Evidence: [AppDelegate:1167](../Sources/AppDelegate.swift#L1167), [AppDelegate:1178](../Sources/AppDelegate.swift#L1178).

A deeper discovery interface can own listing freshness, focus evidence, and subscribers for an opening. The toolbar retains the person's explicit selection and target-carrying policy. Avoid hiding several different facts behind a single `settles` boolean.

**4. Design rename preservation across affected owners. Confirmed data-loss path; complete solution unresolved.**

The watcher diffs filenames. A rename becomes removal plus a new arrival, deleting the stored drawing and applying capture behavior to the new path.

Evidence: [ScreenshotWatcher:173](../Sources/ScreenshotWatcher.swift#L173), [AppDelegate:1368](../Sources/AppDelegate.swift#L1368), [DrawingStore:28](../Sources/DrawingStore.swift#L28).

A rename event and `Drawings.rename` cover only part of the contract. Define what happens to the active edit, undo and selection, pending handovers, annotation queue, flights, notices, stale callbacks, and queued output work. Existing promised outputs keep their own identities. Sent requests already own independent bytes.

Live file identifiers can help correlate an observed rename, but they do not settle offline renames or persistent identity. At launch, sweeping precedes watcher construction. Either define the limitation of live-only rename preservation or choose persistent screenshot identity deliberately. Missing or ambiguous identifiers and replacement saves need explicit behavior.

Ordinary screenshots and managed replies also differ: reply visibility and origin currently depend on the filename. A generic rekey must preserve the publication record rather than turn a renamed reply into an ordinary capture.

This work follows confirmed-deletion and pending-drawing contracts. Do not present it as a two-method local repair.

**5. Treat push coordination as operation ownership. Supported opportunity, narrower than a new import system.**

Fable correctly identifies two independently ordered events: watcher arrival and marks joining. A small value can own when presentation is ready. Its key must include the operation and destination identity, rather than just the filename.

Evidence: [AppDelegate:1101](../Sources/AppDelegate.swift#L1101), [AppDelegate:1138](../Sources/AppDelegate.swift#L1138), [AppDelegate:1352](../Sources/AppDelegate.swift#L1352).

Clearing pending pushes on a folder change does not cancel callbacks already queued by the old watcher. Those callbacks can reach new filename-keyed state. Specify whether a push completes in its original folder or is explicitly cancelled. Existing cards carry full URLs and may remain usable after a folder change, so dismissing the stack is a product choice.

The watcher's constructor can wait up to half a second. Removing that wait trades immediate inventory availability for a pending listing. Expose availability/loading correctly before promising an instantaneous folder switch. No hitch was measured.

**6. Deepen rendering and image requests without duplicating native lifecycle state. Architecture candidate.**

The strongest rendering opportunity remains `MarkLayers`' mutable planning interface. The editor reads pending and drawn cache records, changes targets, and manipulates layer visibility. A value request describing viewport, scale, gesture, and covered text can move those implementation decisions inside the existing module.

Evidence: [MarkLayers:45](../Sources/MarkLayers.swift#L45), [EditorLayers:127](../Sources/EditorLayers.swift#L127).

Opus's cache facts are correct: one path entry can be replaced by a larger decode, and larger decodes satisfy card requests. Its eviction and shimmer conclusions are unmeasured. Four example RGBA images account for about 90.6 MiB, below the 96 MiB cache budget before other entries. Cache accounting also excludes images retained by views.

Evidence: [Thumbnailer:137](../Sources/Thumbnailer.swift#L137), [Thumbnailer:269](../Sources/Thumbnailer.swift#L269).

Reject unconditional screen-cache purging on stack hide. The lone annotator's return flight deliberately uses the shared screen decode after local flight storage was cleared. Retention must follow the editor and return flight as well as the stack.

Evidence: [ThumbnailController:1081](../Sources/ThumbnailController.swift#L1081).

Fable's `FlightLanding` could duplicate arrival ownership already in `TransitionLayer`. Opus's argument against merely replacing callbacks with a direct reference is sound. Evaluate a concrete complete handoff interface that owns readiness, mark adoption, input, and shadow transfer while preserving existing reducers and native motion. Pixel and event checks must prove the replacement.

**7. Probe Claude inbox timing before changing its turn state. Runtime hypothesis.**

The monitor checks whether it is between turns once, then drains a batch of lines. It does not recheck the state after each message. The repository's historical investigation reports different behavior for idle and mid-turn notifications.

Evidence: [inbox.sh:23](../agent-plugin/plugins/vignette/scripts/inbox.sh#L23), [inbox.sh:30](../agent-plugin/plugins/vignette/scripts/inbox.sh#L30), [investigation:320](claude-code-without-herdr-2026-09-27.md#L320).

Current monitor-triggered hook behavior was not observed. Opus's proposed busy write after printing can overwrite a fast idle answer or hold later messages forever if no turn starts. An arbitrary timeout is not proof that a turn ended.

Verify two queued sends, a second send during a monitor-started turn, interruption, no-turn delivery, and plugin reload using an isolated signed-in scratch session. Then choose the smallest monitor change. Preserve acceptance as inbox handoff. A line disappearing proves consumption by the monitor, not that the model acted on it.

## Decisions and verification limits

**Implementation readiness**

Several repairs are clear enough to start. Larger interface changes need a specific contract, and runtime hypotheses need a targeted check. Routine verification is still required for every implementation.

| Item | Readiness | What remains before implementation |
| --- | --- | --- |
| Deletion safety and failed Trash cleanup | Ready for bounded repairs | Apply confirmed absence across live and startup consumers. Keep unavailable folders and missing metadata distinct from deletion. |
| Terminal clearing | Ready for a bounded repair | Commit clear before destructive effects and reject later submission state changes. Verify failed unpublished-file cleanup. |
| Reply replay and actual file locations | Direction established; narrow design needed | Choose how materialized drawings and reservation locations are stored. Specify replay, published-file retention, and folder-change behavior. |
| Stable promised output files | Lifetime decision needed | Select immutable backing-file ownership, external-consumer retention, and storage limits. |
| Opening guard and unmarked Send | Ready for bounded repairs | Reuse the existing session guard and renderer. Verify oriented Send through the product and the PNG representation tradeoff. |
| Pending drawing persistence | Persistence contract needed | Specify open/pending/disk reads, retry, card updates, memory bounds, final quit write, and unresolved failure. |
| `MarkLayers` interface | Concrete interface design needed | Define a presentation value that hides mutable cache records and preserves adoption, typing, bitmap bounds, and queues. |
| Rename preservation | Identity mapping and focused feasibility checks needed | Cover active editing, pending work, managed reply names, offline renames, and ambiguous file identifiers. |
| Image cache changes | Measurement needed | Establish decode churn and retained memory; define editor and return-flight retention before changing tiers. |
| Claude inbox timing | Current-runtime probe needed | Observe monitor-started turns, queued sends, interruption, no-turn delivery, and reload before changing busy/idle state. |

Output preparation separately needs a snapshot policy for drawing revisions, source pixels, and styles, with one ordered result or failure per selected item. Larger source-notice, discovery, and handoff changes need explicit lifetime interfaces. Those requirements do not block the existing opening guard or unmarked Send repairs.

The practical sequence is:

1. Repair confirmed deletion, reply location/recovery, terminal clearing, and promised output identity.
2. Reuse the existing opening guard and rendering path for Send.
3. Define pending handover persistence, closing, and shutdown. Then specify rename and push lifetimes.
4. Deepen output preparation and mark presentation through explicit chosen revisions and ordered per-item results.
5. Measure image retention and main-actor byte work. Moving request preparation off-thread requires commit-time checks for clear, duplicate attempts, folder changes, and editor closure.
6. Probe inbox timing. Evaluate larger discovery and handoff interfaces only when their responsibility and verification cost are concrete.

Several smaller suggestions remain conditional. Screenshot-action admission can become one function, but reply authorization, external pushes, and settings commands have different input contracts. Settings injection should preserve live Reduce Motion updates. ScreenCaptureKit could replace the legacy pixel-test adapter only after offscreen capture, resolution, color, and supported macOS behavior are verified. Broadly skipping capture failures would weaken useful proof. Trailer source patch removal is supported by the existing launch/staging seams and the previously confirmed parser failure; changing that tooling requires specific approval.

Both models state that they ran nothing and inspected some areas only lightly. I verified material recommendations against current source with parallel reviews. I ran the isolated image conversion check; the prior review also ran the rendering queue/file mismatch and trailer parser checks. No app build, native interaction, live Claude session test, full suite, or performance measurement was performed. No production code, settings, or tooling changed.
