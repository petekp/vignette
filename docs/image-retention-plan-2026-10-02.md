# Own image loading and retention by display purpose

Consolidate repeated image requests and give card and screen images explicit owners. Measure product latency and retained memory before choosing cache budgets. A hidden stack can still have an active annotator and a return flight that need its screen image.

This is an investigation and implementation proposal. App source, tests, and tooling have not changed for this effort. The measurements below came from a standalone executable using the current `Thumbnailer` source. It opened no windows and did not read Pete's settings or screenshots.

## Current behavior and probe results

| Consumer | Responsibility currently carried by the caller | Source |
|---|---|---|
| Warm-up and card creation | Choose cloud behavior, read header readiness, calculate resolution, request a card image, and start image downloads. | `Sources/ThumbnailController.swift:397-410`, `1340-1375` |
| Hover and flights | Keep a second four-entry image collection, request screen resolution, replace flight images, and reject completions after hiding. | `Sources/ThumbnailController.swift:146-149`, `1076-1104` |
| Annotator opening | Read source pixel dimensions, inspect the screen cache, start another request, and check opening generation before delivery. | `Sources/AnnotationController.swift:143-175` |
| Live tweaks | Resize cards and synchronously request decoded images on the main actor. | `Sources/ThumbnailController.swift:580-599` |
| Stitch presentation | Decode its card synchronously because the convergence flight needs the destination image in the same turn. | `Sources/ThumbnailController.swift:649-656` |
| Recording readiness and stitch | Use recording metadata and poster frames. These include waits on platform loaders. | `Sources/ScreenshotWatcher.swift:347-348`; `Sources/Stitch.swift:126-138`; `Sources/Thumbnailer.swift:105-124`, `251-264` |
| Editor lifetime | Retain the screen image in the screenshot layer until native removal clears the editor. | `Sources/EditorLayers.swift:82-96`; `Sources/AnnotationController.swift:428-445`; `Sources/EditorView.swift:173-182` |

The image cache contains one entry per path. Resolution and color space decide whether that entry satisfies a lookup. A later insertion replaces it. The comment claiming resolution and color space are dictionary keys needs correction.

Source: `Sources/Thumbnailer.swift:15-31`, `137-144`, `169-171`, `179-189`, `269-288`.

The standalone probe compiled that module unchanged with the exact `Screenshot` definition extracted from settings. Its fixture was one solid sRGB PNG. Card resolution was supplied explicitly; no screen geometry was queried.

| Observation | Result |
|---|---|
| Card request with a 440-pixel limit | A 440 by 293 image; 515,680 bytes in cache accounting. |
| Screen request with a 3000-pixel limit | A 3000 by 2000 image; 24,000,000 bytes in cache accounting. |
| Card lookup after the screen request | Returned the same screen-sized `NSImage` object. |
| Original card reference retained before that request | Remained 440 by 293. Hover does not automatically replace the card's existing reference. |
| Cache eviction while a screen reference was retained | The screen cache lookup missed; the retained screen image remained usable. Cache accounting then reported 1,024 bytes. |
| Five pairs of concurrent cold screen requests | Each pair returned two different `NSImage` objects. The module did not combine those requests. |

These results establish replacement, reuse, external ownership, and concurrent allocation behavior for this fixture. The byte figures are the module's RGBA estimate. They are not resident memory measurements. The probe does not establish shimmer, a product stall, or the cost of a real screenshot decode. ImageIO may perform additional internal reuse that this probe does not inspect.

Source hash for the probed module:

`45cc25953ea84f2ca0d84cfad57d45e1081c7105224993b521b14dadaecbe94c`

Retained probe results: `/private/tmp/vignette-capture-probes.1qwz_ddj/image-results.json`. Compile and run commands exited successfully. The fixture, request sequence, and source hash are recorded above.

Earlier native measurements found long main-thread waits when reading iCloud placeholders. The current lookup path avoids those reads for card construction. Opening an image before its background download finishes can still read its header on the main thread. This older evidence justifies preserving cloud behavior; it does not measure the proposed loading change.

Source: `docs/icloud-files-2026-09-25.md`; `Sources/Thumbnailer.swift:56-88`; `Sources/AnnotationController.swift:147`.

## Proposed implementation and measurement protocol

Begin with shared pending-request ownership inside `Thumbnailer`. Combine compatible requests for the same source revision, color space, and display purpose. One result should satisfy the waiting card, flight, and editor consumers that requested it. Keep ImageIO, AVFoundation, and Quick Look implementation details private. Their actual format and availability differences justify internal seams; a general public decoder protocol adds no current capability.

Use the existing card and screen purposes to decide retention. Card requests should receive an appropriately downsampled image. Screen requests should share a decode between flight and editor. A source revision must invalidate stale results. Choose its metadata after checking replacement-file behavior; modification date alone is the current cache contract.

The active annotation run owns its screen-image retention through outbound motion, editing, and the return flight. Stack hover owns temporary prefetch retention. Clearing hover references when the stack hides must leave the active run's image available. The return path already relies on the shared screen cache after a lone thumbnail's panel hides.

Source: `Sources/ThumbnailController.swift:1081-1085`.

Separate card and screen entries only if native measurements show harmful replacement or eviction. A simpler first implementation can combine pending requests and preserve the existing completed-cache policy. The measured duplicate requests justify that slice. Hard-coded new budgets do not yet have evidence.

A separate slice can make live-tweak decoding asynchronous. Keep the old image visible until the replacement is ready. Validate card identity, source revision, screen color space, and tweak generation before applying it. Stitch convergence has a different timing requirement; arrange its image readiness before starting the flight rather than replacing the synchronous call with an uncoordinated request.

Settle whether card requests require a dedicated small image even when a screen image exists. The recommendation is to keep card resolution suitable for its display while letting screen consumers share their larger image. This uses extra memory briefly, so choose the policy with actual card sizes, source sizes, and resident memory measurements. Also decide the acceptable offline cloud response and memory-pressure behavior before adding cancellation or eviction policy. Combining requests must retain each consumer's readiness and failure notification. Any later cancellation should release one consumer without discarding an image another still needs.

For the next authorized native round:

1. Build an isolated E2E copy using the existing script. Use its own bundle identity, scratch home, settings file, and screenshots folder. Acquire the shared native-test lock. Keep the screen, defaults, fixture files, and build configuration fixed.
2. Record three baseline repetitions per sequence: warm and open the recent stack; hover the same four cards; open a lone thumbnail and keep its annotator active after the panel hides; return that image; reopen the stack; change card size while images are uncached. Run the same sequences after a proposed change.
3. Capture each sequence's state and log timestamps. Record stack-open time and `decoding`, annotator load time, thumbnail cache accounting, and resident memory. Measure peak and settled memory separately. A falling cache count alone does not prove image memory was released.
4. Use the existing Time Profiler and Core Animation Commits workflow. Attribute main-thread waits to source frames and compare commit durations with the current display's refresh budget. Use Allocations to distinguish retained card, flight, and editor images where cache counters cannot. Profiling requires a separate native round; none has run for this effort.
5. Record the flight region for the lone-thumbnail return. Verify picture, text, and shadow continuity. Apply Reduce Motion and repeat the readiness ordering. Run placeholder-image and placeholder-recording cases in a disposable isolated folder only after authorizing eviction of those fixtures. Confirm recordings remain placeholders until opened by their movie application.

Keep the existing DPI, color-space, PNG-byte, and eviction tests. Add request-combination and stale-result cases only if the module now owns those behaviors. Replace duplicated consumer-level checks when equivalent coverage moves to this interface. Native verification still owns window-server handoff and visible continuity.

Critical review: request combination is supported by the standalone observation. Cache-tier budgets, RSS improvements, visual sharpness, and main-thread timing still need native evidence. Active-editor retention prevents an unconditional screen-cache purge. The rename plan's source identity must inform loading revisions before either implementation adds another incompatible path convention.
