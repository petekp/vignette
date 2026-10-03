# Pending drawing persistence

Keep the editor responsible for active edits. Let `Drawings` retain the latest completed handover when its write fails. Read that handover before the older stored drawing. A close or swap may proceed once the drawing is stored or retained. It must stay in the editor when neither succeeds.

This plan proposes one persistence effort. Source changes are not implemented. Request publication, output files and mark presentation have separate owners and plans.

## Ownership and evidence

A **handover** is the editor's completed drawing snapshot. It excludes a gesture still being drawn and an empty note being typed. A **pending drawing** is a retained handover awaiting storage or retrying a failed write. A **stored drawing** has completed its atomic file write. These states are separate.

The current editor clears its handover flag when it emits the drawing. The host discards the write result. Closing then parks the editor and removes its active state. Reopening reads disk, which can still contain an older drawing.

| Current owner | Evidence | Contract to preserve or change |
| --- | --- | --- |
| `EditorCore` | [handOver](../Sources/EditorCore.swift#L636), [drawingForHost](../Sources/EditorCore.swift#L643) | Keep gestures, typing, selection and undo here. Distinguish requesting a handover from its admission. |
| `EditorView` | [park](../Sources/EditorView.swift#L150), [clear](../Sources/EditorView.swift#L173), [join](../Sources/EditorView.swift#L851) | Prepare a completed snapshot before the final park. A refused handover must leave the editor usable. |
| `AnnotationController` | [hide](../Sources/AnnotationController.swift#L396), [park](../Sources/AnnotationController.swift#L412) | Keep the opening and its window until departure is admitted. It currently clears `current` before parking. |
| `AnnotationRun` and its host | [reduce](../Sources/AnnotationRun.swift#L69), [presentation effects](../Sources/ThumbnailController.swift#L822) | Keep queue and transition decisions here. A failed departure must not consume the queue or begin a flight home. |
| `Drawings` | [write](../Sources/Drawings.swift#L82), [load](../Sources/Drawings.swift#L63), [add](../Sources/Drawings.swift#L143) | Own pending handovers, write outcomes and read precedence. Keep additive pushes distinct from complete reply installation. |
| `DrawingStore` | [write](../Sources/DrawingStore.swift#L85) | Keep atomic writes, empty-drawing removal and newer-format refusal. Return the actual failure. |
| Presentation | [homeFlightMarks](../Sources/ThumbnailController.swift#L1004) | Keep parked layers and bitmap adoption. Those layers are needed for a flight and are not persistence. |
| Application termination | [normal quit](../Sources/AppDelegate.swift#L179), [replacement](../Sources/AppDelegate.swift#L195) | Flush all pending drawings before normal quit. Replacement currently forces an older instance to terminate after three seconds. |

Use an in-memory pending owner for this effort. The requirement is to preserve failed handovers while the process continues. Crash survival of a failed write is not required.

A durable spool would add a second namespace, authority rules and restart recovery. A spool on the same filesystem cannot be assumed to survive disk-full or access failures that refused the original write. A refusal of a newer-format file must not be bypassed through a second path. A spool would be justified only by a separate requirement and an identified failure class it can handle.

## Proposed interface and lifecycle

`Drawings` should accept a completed snapshot and return one of these outcomes:

| Outcome | Meaning | Departure |
| --- | --- | --- |
| Stored | The latest admitted revision completed its atomic write or removal. | Allowed. |
| Retained | The pending owner accepted that revision within its budget. Its write is awaiting completion or failed. | Allowed. Persistence status remains distinct. |
| Refused | The pending owner could not accept the snapshot, or storage policy refused it. | The editor keeps the drawing. |

The outcome names whether a drawing is retained and whether it is durable. Returning a success boolean loses that distinction. A command that promises storage still answers a storage failure for a retained drawing.

Keep the pending interface in `Drawings`. Each entry holds one latest immutable drawing snapshot, its source key, its admitted revision and its storage status. Replace an older entry for the same screenshot only after the new entry is admitted. Successful storage releases the payload and records the durable revision. The next experiment should choose retained `Drawing` values or encoded bytes. Encoded bytes give a countable payload budget, but producing them can delay admission. Neither representation bounds total process memory.

The admission required before motion should reserve a snapshot cheaply. Heavy encoding and writing should follow admission. The bounded probe below found that encoding a large freehand drawing can itself take time. An encode-and-write preflight would make the first returning frame wait for that work. The current park already writes synchronously, so neither the current behavior nor the proposed departure gate proves fluidity.

Compare cheap snapshot retention and conservative capacity accounting with encoded admission before settling the storage implementation. If writes move to a queue, keep it inside `Drawings`, serialize store operations and coalesce repeated handovers for the currently open screenshot. Bound accepted payloads rather than creating an unbounded queue of complete snapshots. Refuse other operations before accepting more payload when capacity is unavailable. A storage queue is an implementation choice to validate, not a new external interface.

Keep source validation and storage policy in their existing owners. A confirmed deletion removes the pending entry and invalidates older reads. An unavailable source folder does not prove deletion. A change in displayed image dimensions must return a source-change result rather than silently applying pending marks to different pixels.

**Read precedence.** Resolve the open editor's host snapshot first, the latest pending drawing second, and disk third. A pending drawing with no marks suppresses the older disk drawing. It represents a removal awaiting persistence. Keep `keys` as a fact about stored files; add an effective-drawing query for callers that currently inspect those keys.

Route annotator opening, card loading, agent additions and output preparation through this precedence. Annotator opening currently receives the stored drawing directly. Change that callback to the effective drawing read. For cards, retain their current asynchronous-load contract and drop results overtaken by an admitted handover. Output preparation requires one result or failure for each selected screenshot; it must not reuse the card loader's omitted-result behavior.

**Card updates.** An admitted handover updates cards immediately, even when persistence failed. Increment the effective revision at admission, so earlier loads cannot restore old marks. A successful retry changes persistence status without replacing an unchanged card drawing. A refused handover stays authoritative in the open editor and produces a storage failure; it is not announced as a stored card change. Keep current visible drawing state and durable status separate in the state report.

**Departure.** Add a prepare-for-handover operation to the editor. It finalizes a gesture and typing in the same way as Done, Send and park. It returns a snapshot and its edit revision while leaving the core open. Final park runs only after admission. It stops input and freezes mark layers for the flight, as it does now.

The presentation owner must request admission before submitting an event that relinquishes the editor to `AnnotationRun`. This covers Done, Send, Esc, outside click, stack dismissal, swap and abandonment. Keep the original event and opening identity while preparation is underway. Leave the run's queue and phase unchanged until admission succeeds. This gate belongs in the existing presentation event handler, not a second transition coordinator. Once cheap retention succeeds, start the existing motion without waiting for its storage write.

When an asynchronous admission answers, compare both the opening identity and the editor's edit revision. A stale answer cannot close a later opening. If the person or an agent changed the drawing meanwhile, prepare and admit the new completed revision before leaving. Do not disable the editor to make this ordering easier. Duplicate departure requests should coalesce rather than start competing departures.

The editor's handover bookkeeping also needs an acknowledgment. A refusal leaves its latest revision unhanded. An acknowledgment for an earlier revision does not clear a later edit. Timer handovers can retain the editor's current gesture and typing; preparation for departure finalizes them. Keep this distinction in the reducer's interface.

**Send.** Drawing admission and request submission are separate outcomes. Reserve the completed snapshot before starting a new Send when possible. Send's own PNG and request record become durable before the annotation run departs. After that point, transport may proceed even if a later local-drawing write fails. A storage retry must never call `requests.send`, replay the message, create another request, or reset an already submitted send to not sent. Keep the request identity with the departure intent.

The person can continue editing while Send renders. Before departure, admit that newer local revision too. If its admission is refused after the request was already stored, keep the editor open with a submitted request and an unresolved local drawing. Retry only drawing admission. Keep Send disabled for that existing operation until departure succeeds or the person deliberately starts a separate Send. This differs from a failure before request creation and requires explicit presentation state, not a shared failure boolean. Evidence: [sendDrawing](../Sources/AppDelegate.swift#L1250), [submit](../Sources/AppDelegate.swift#L1290).

**Agent additions.** For an open drawing, preserve the existing one-step join and its unchanged selection. If storage fails, report that the mutation was applied and either retained or remains in the open editor. Retrying persistence writes the resulting snapshot; it does not join the raw marks again. A closed-drawing addition prepares a prospective drawing, attempts storage, and admits it before notifying cards. A capacity refusal leaves its prior effective drawing unchanged. Complete reply installation remains a separate operation in the request-safety effort.

**Retry.** Attempt storage on each new handover. Retry retained snapshots on an explicit retry, reopening their screenshot and normal quit. A newer admitted handover supersedes an older pending revision. Use the stored failure to distinguish permanent policy refusals from failures that can be retried. Avoid a continuous timer retry after a refusal. Keep retry inside `Drawings`, so callers never need to replay an edit.

**Quit.** Add a termination preflight before `applicationWillTerminate`. Prepare the current editor's snapshot, then flush every pending drawing, including ones whose annotator is already closed. Quit can proceed when all are stored. If storage remains refused, allow retry, cancel quit, or an explicit discard and quit. An in-memory entry does not survive process termination.

Replacement has the same obligation. A new instance currently requests quit and forcibly terminates the older instance after three seconds. The smallest safe consequence is to let an older instance with unresolved storage keep running and have the new instance stop before it starts its watcher, hotkey and Apple preference changes. This changes the documented newer-instance-wins behavior and requires Pete's approval. Do not leave two fully active instances while waiting for a decision.

## Budget, decisions and validation

Use **16 MiB** as the encoded-payload comparison budget in the next experiment, with one latest entry per source. It is not an RSS guarantee or a settled product cap. Cheap retention needs its own conservative accounting rule. If capacity cannot admit a snapshot, an actual write can still permit departure, but that fallback may wait. Never evict another unsaved entry to make room. At capacity, preserve the active editor and offer storage retry or an explicit discard. An older pending entry remains when a larger replacement cannot be admitted.

A temporary bounded Swift probe used the current `Drawing`, `Mark` and record-encoder declarations. It created data and encoded it without launching the app. Each case ran once through the Swift interpreter. The measured RSS deltas include allocator and encoding effects; they are not native-app retained-memory measurements.

| Synthetic drawing | Encoded payload | Encoding time |
| --- | ---: | ---: |
| 100 rectangles | 10,523 bytes | 1.1 ms |
| 1,000 notes of about 2,000 ASCII characters | 2,098,383 bytes | 7.5 ms |
| 1,000 arrows with 500 intermediate points each | 24,881,038 bytes | 767 ms |

The largest case exceeded the proposed admission budget and produced about a 93 MB RSS increase during encoding. The model's mark stride was 96 bytes. The drawing currently has no total mark-count limit, so a single drawing can exceed any fixed pending budget. The proposed budget can retain several large note drawings and many small drawings, while requiring an explicit failure path for larger unsaved data. Measure native retained payload and peak encoding memory before setting the final default.

Pete needs to decide whether the proposed capacity refusal and quit behavior fit the product. The recommendation is to preserve the editor at capacity and cancel normal quit after an unresolved save unless the person explicitly discards. Approve the older-instance replacement exception separately. No new setting or durable spool is proposed.

The next cheapest experiment is a bounded local harness using the current drawing types and encoder. Compare retaining the value directly, modifying the editor's copy afterward, and retaining encoded bytes. Measure admission time, retained payload, peak heap and the cost of replacing a pending entry. Include a full-budget refusal and one oversized drawing. Delay a store write independently so the first motion gate can be timed without waiting for encoding. Add one sequence in which Send already has a durable request before a newer local revision is refused. This does not require an app launch or a permanent benchmark. Native frame verification follows only after the representation and admission rule are chosen.

Implementation changes are confined to the drawing owner, its existing storage implementation, editor handover acknowledgment, annotator departure, the presentation event gate, and application termination. Update state-report and voice documentation for their new outcomes. Keep rendering file identity, reply recovery and mark-cache changes in their own efforts.

Extend existing tests at the owning interfaces:

- `DrawingStoreTests`: a failed write retains the latest handover; success releases it; an empty pending drawing suppresses disk; reopening reads pending; a larger refused replacement preserves the earlier entry; retries write once without rejoining marks.
- `EditorCoreTests` and `EditorViewTests`: preparation finalizes a gesture and typing while keeping input usable; refusal leaves the latest revision unhanded; an earlier acknowledgment cannot clear later edits; final park preserves its current behavior.
- `AnnotationRunTests`: refused departure leaves queue and phase intact. Readiness and a later edit can arrive during preparation without an older admission closing them.
- Existing card tests: older loads cannot replace pending marks, and persistence-only completion preserves current bitmaps.
- Native scratch verification: force a real temporary drawing-store write failure, draw, close, reopen, retry and quit. Verify normal motion, key focus, continuous note visibility and exact marks. Verify a replacement launch refuses to force away an unresolved drawing.

Use real scratch storage for write refusal. Use a bounded local queue stand-in for delayed acknowledgments, not a mock that supplies the editor mutation. Keep a temporary measurement for the payload budget and main-thread encoding. No app sources, tests, settings or running processes were changed for this plan.
