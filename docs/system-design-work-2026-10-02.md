# Vignette system improvement plan

Five concerns are implemented and verified. The remaining efforts have concrete plans, evidence, and decision points. Concurrent site work is outside this change.

## Disposition

| Concern | Intended result | Status |
| --- | --- | --- |
| Deletion safety | Only confirmed absence or successful Trash removes drawings. Unavailable folders preserve inventory, publication records, and marks. Startup cleanup waits for authorized successful inventory. | Verified: 65 owner tests passed; native mixed Trash, folder outage, recovery, and restart passed |
| Request clearing | Clear is durable and terminal before destructive effects. Late delivery cannot reopen it. Owned failed unpublished files are cleaned. | [Request safety plan](request-safety-plan-2026-10-02.md) implemented; durable clearing, delayed outcomes, cleanup replay, and failed admission passed owner coverage |
| Reply replay and locations | Complete drawing installation repeats safely with stable materialized geometry. Reserved and published locations remain explicit across folder changes. | Recorded locations and [complete installation](request-safety-plan-2026-10-02.md) implemented; interrupted publication preserves one complete geometry and scale |
| Send | Discovery answers belong to one opening. Unmarked Send uses the background renderer with correct orientation and DPI. | Implemented; opening guards reviewed and rendering owner coverage passed |
| Promised output files | A rendering's PNG and file identify one immutable result. External-consumer lifetime and cleanup are explicit. | [Unique result filename and lifetime](rendering-result-plan-2026-10-02.md) implemented; exact JSON result paths reach the clipboard, skill, and E2E readback |
| Pending drawings | Reads should prefer the open editor, then pending handovers, then disk. Retry, close, bounds, and quit preserve the intended drawing and report storage failure accurately. | [Pending-drawing ownership and admission plan](pending-drawing-plan-2026-10-02.md) researched; capacity, departure latency, and unresolved-save quit need decisions |
| Mark presentation | A value request replaces mutable text-cache manipulation by the editor. Typing, adoption, bitmap limits, and native motion stay correct. | [Immutable presentation interface](mark-presentation-plan-2026-10-02.md) ready; native continuity verification specified |
| Rename preservation | A rename preserves the drawing and defines every affected editor, queue, reply, notice, and output lifetime. Offline and ambiguous identity behavior are explicit. | [Identity investigation](capture-identity-plan-2026-10-02.md) complete; offline, active, and managed-reply rename scope needs decisions |
| Image loading and retention | Card and screen requests share compatible work while retaining images needed by an active editor and return flight. Changes follow measured cost. | [Standalone loading measurements and native protocol](image-retention-plan-2026-10-02.md) complete; request coalescing justified, cache budgets need native evidence |
| Claude inbox timing | Current monitor-started turns, batches, interruption, no-turn delivery, and reload are observed before changing busy/idle behavior. | [Runtime observation matrix](agent-integration-plan-2026-10-02.md) ready; fresh isolated CLI has no sign-in |
| Agent documentation and cleanup | The onboarding and maintained contracts describe the final code. Temporary probes, test files, and test processes are removed; useful evidence is consolidated. | Agent onboarding, shipped skill, consumer guides, and ADR updated; normal app restored; disposable artifacts removed except the OS-blocked generated Trash image |

[Settings persistence](settings-persistence-plan-2026-10-02.md) and [complete agent-enable outcomes](agent-integration-plan-2026-10-02.md) have bounded follow-up plans. Screenshot-command admission remains conditional: managed replies, pushes, and settings have different authorization contracts, so one blanket predicate is inappropriate. Trailer source-patch removal requires specific tooling approval. No CI, project configuration, build, release, or deployment tooling changes are authorized by this plan.

## Settled contracts and verification

Successful screenshot inventory owns deletion evidence. Unavailable reads retain the prior inventory. Folder identity, watcher generation, observation time, and positive file presence protect against stale removal. Trash cleanup uses successful removals only. Pending arrivals survive access loss and remount. The removal callback uses the same absence guard as the drawing sweep. Suppressed removals remain pending until a later listing observes their presence or confirms their absence.

Reply records persist their actual output location. Current-folder readiness starts recovery; deletion requires evidence from the reply's own folder. Complete drawing installation reuses valid stored geometry and point scale. It rejects partial or corrupt checkpoints and out-of-image shapes. Text anchors are checked without reflowing stored geometry under current typography.

Clear commits before changing memory or removing payloads. Late transport outcomes preserve terminal fields. Exact-location cleanup replays after restart and prevents pruning while an owned output remains unresolved. Completed cancellations skip dictionary mutation and record writes. Failed persistence remains pending for retry. At the normal live-request limit, failed retirement discards the new unsubmitted candidate before transport starts.

Each file rendering has one unique path owned by its pending result. PNG, TIFF, file URL, and terminal path identify that result. Completed files remain until the person deletes them. Allocation respects filename and full-path limits for both the supplied and physical directory paths. The returned JSON paths reach the shipped skill and native readback. Both destination-discovery continuations and Send completion use the existing annotation-opening identity. Empty Send uses the background renderer with displayed orientation and DPI.

Independent critical reviews covered these contracts and their affected consumers. Red checks reproduced destructive cleanup, arrival starvation, fixed-output overwrite, and incomplete checkpoint acceptance. The complete corrected unit suite passed **471 tests, zero failures**. Three focused checks reproduced the repeated-write and long-path failures on the pre-fix sources and passed with the corrections. The result check covers directory symlink expansion and successful atomic writes within the physical path limit.

Eleven isolated native flow checks passed. They covered agent marks, original copy formats, stitch, restart, Done, the annotation queue, zoom, both fake agent reply routes, result lifetime, and empty oriented-JPEG Send. Result filenames containing quotes and commas round-tripped through JSON. Completed files survived clipboard replacement and app restart with unchanged bytes. Empty Send produced the displayed 40 by 80 PNG at 144 DPI. A separate partial-Trash and folder-outage round passed its behavior checks; its command exited with a cleanup error described below. Real Claude monitor timing and native drag/drop-target delivery were not exercised by these checks.

A further isolated native check reproduced drawing loss before the removal fix, then passed four checks after it: a closed card and active editor each survived a case-only rename, and real deletion later retired their drawings and all affected cards.

A standalone cancellation probe verified zero rewrites of 200 completed reply records across four reconciliations. Local unoptimized durations were 53–59 ms, compared with 131–275 ms before the fix. These measurements are workload-dependent storage evidence, not a native UI latency guarantee.

The normal Debug app was rebuilt and relaunched using the existing run script. Tagged state confirmed its exact main bundle and normal settings path. Agent onboarding, the shipped skill, plugin versions, consumer guides, and ADR 0018 describe the implemented contracts. CLAUDE.md continues to import AGENTS.md.

## Decisions and cleanup

Pending drawing admission needs a bounded prototype for departure latency and retained memory. Capacity refusal, unresolved-save quit, and replacement launch behavior need product decisions. The mark-presentation interface is ready for implementation once that ownership boundary is settled.

Rename scope must settle offline, active-editor, and managed-reply behavior. Resource identifiers and bookmarks cannot by themselves distinguish hard-linked directory entries. Image request coalescing has standalone evidence; cache tiers and budgets require native measurements. Settings persistence and agent enablement have bounded follow-up plans, including startup and partial failure consumers. The live Claude matrix requires an isolated signed-in session. Trailer patch removal requires specific tooling approval.

Selected logs and summaries remain under `/private/tmp/vignette-system-work.Idzoy2/evidence/`. The review corrections have separate evidence under `/private/tmp/vignette-review-fixes-b23rvzbq/evidence/`. Disposable scripts, fixtures, caches, unit build output, result bundles, and the completed E2E run were removed. Concurrent site changes and the normal app build were preserved.

One generated test image remains in Trash:

`/Users/petepetrash/.Trash/Seams deletion 797bba291c20412a9c16f4555376ae16 success.png`

macOS refused its removal through filesystem APIs and Finder. It contains only a generated fixture. Other user Trash items were not changed.
