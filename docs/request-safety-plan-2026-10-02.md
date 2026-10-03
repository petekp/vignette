# Durable request clearing and reply installation

The request record owns whether replies may arrive. A successful transport result does not reopen a request that the person cleared. Publication owns a complete image and drawing at its recorded location.

## Terminal clearing

Persist the cleared request before changing memory or deleting payloads. If that write fails, retain the current state and files and report a write failure. An unknown request remains a separate missing-request result.

After the cleared record commits, cancel unpublished imports and delete only their owned output files at recorded locations. This includes failed imports whose PNG was already copied. Published files remain the person's. Then remove the sent image and submission files.

Cleared records replay any unfinished cancellation cleanup at load. Cleanup interruption cannot undo the terminal request state. Completed cancellation records remain untouched on later scans. Failed record writes stay pending in memory and retry even when their cancellation state has not changed again. A reply record that failed to become cancelled cannot authorize publication while its request is cleared.

Late submission results may still report what the transport actually did, but cannot replace a cleared record's status or detail. Clearing cannot retract a message already handed to a client. It must not claim that message was never sent.

The live-request limit must preserve this ordering. If saving the new request succeeds but clearing an old one fails, handle the new unsubmitted request explicitly rather than accumulating prepared records or silently deleting an old payload. A failed new Send must not clear an unrelated old request merely to make space.

Verification uses a delayed connection adapter, each transport outcome, clear, release, and restart. Add real store-write refusal, interrupted cleanup, failed unpublished-file cleanup, and the live-request limit. Assert durable records, payload presence, and refusal of new replies rather than private call counts.

## Complete reply drawings

Keep additive `Drawings.add` for pushes and marks joining an open editor. A reserved reply uses a separate complete-install operation.

A valid existing materialization at that exact hidden output is a recovery checkpoint. Reuse its stored point scale and mark geometry instead of normalizing raw agent marks again. If no materialization exists, construct the complete drawing once and atomically write it before publication.

The installation read must distinguish a complete valid drawing from a partially recovered file. Ordinary drawing reads may drop individual invalid marks; reply recovery must fail closed rather than publishing a partial drawing as complete.

Current rendering styles remain live. Reusing stored geometry does not freeze fonts or colors across builds. Image-only replies need no drawing installation.

Verification extends the existing request recovery scenario with a real scratch drawing store. Stop after drawing storage and before publication, reopen with changed construction style and scale, and verify one complete set of marks at the persisted geometry. Exercise corrupt materialization, clear during installation, and additive pushes as separate contracts.

## Review and boundaries

The deletion slice supplies actual reply destinations and successful inventory reconciliation. This work preserves those interfaces and does not introduce a generic transaction layer, transport retry, or new delivery route.

Critical review checks durable-before-destructive ordering, cancellation recovery, request limits, location ownership, complete-versus-partial drawing validation, and late effects. Native verification uses scratch app settings and fake sessions.

State: implemented and critically reviewed. The complete unit suite passed 471 tests. Recovery uses a strict checkpoint read, including complete mark count and shape placement. Text anchors are validated without reflowing their stored geometry under the current style. Terminal clearing retains unresolved owned-output cleanup through restart and pruning. At the ordinary live-request limit, failed retirement discards the new unsubmitted candidate; a pre-existing over-limit store requires explicit clearing before admission.
