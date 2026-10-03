# Stable rendering results

Each copied or dragged rendering needs one identity shared by its PNG, TIFF, file URL, and terminal path. Those consumers may read the file after the clipboard changes or the app restarts.

The current fixed output name allows an older queued rendering to overwrite a newer result's file. Serial execution does not prevent this because Copy's priority jobs overtake waiting jobs. The isolated queue check reproduced different bytes in a completed result's PNG and its file.

## Recommended contract

Write one immutable output beside its source:

`<source>-<result-id>-annotated.png`

Keep completed files until the person deletes them. They are externally referenced outputs, not cache entries. Only incomplete temporary files from failed writes may be cleaned automatically. Source deletion, clipboard replacement, and app restart cannot establish that an external consumer finished reading a result.

This preserves the existing output folder and watcher exclusion. It adds visible versions and changes the fixed-filename readback contract. Bound the source-name prefix to filename and full-path limits while preserving the complete unique identifier and suffix. Count the caller's path and the physical path behind directory symlinks, including the separator and terminating NUL.

The alternative is to preserve the fixed-name export as a latest-result projection and add immutable backing files for promises. Existing fixed-name readers justify that alternative, but it introduces two outputs and requires generation-aware projection updates. A stale job must never replace the latest export. The single-output cutover has fewer ownership and failure rules.

## Interface and consumer changes

`RenderingQueue` allocates the result identifier and output URL when accepting a file-rendering request. `PendingRendering` owns that reserved URL and the eventual result. Byte-only Send stays byte-only.

`Clipboard.copyRendering` and `renderingItem` take the pending result alone. They cannot receive a second URL that disagrees with its bytes. Path text is available immediately; PNG, TIFF, and the file URL remain native promises fulfilled after successful rendering.

AppDelegate's Copy Drawing, Done, and drag paths stop constructing output filenames. The completed command/log answer gives the exact output path. Keep the existing command names and log event tags.

Consumers that must change with the contract:

- [Shipped skill](../skills/vignette/SKILL.md): read the returned result path instead of reconstructing a fixed filename. Bump its metadata and both plugin manifests with the changed agent instructions.
- [Agent guide](agents.md), [editor guide](editor.md), and [README](../README.md): describe distinct completed files and their lifetime.
- [E2E scenarios](../scripts/e2e/scenarios.py): follow the command/log result and verify its image. Preserve the build and runner tooling.
- [Agent onboarding](../AGENTS.md): describe the actual allocation owner, immutable result identity, output exclusion, and cleanup policy.

Verification extends the existing rendering and clipboard coverage. Use two drawings of one screenshot, priority overtaking, clipboard replacement, delayed file reads, and restart. PNG data must equal the referenced file, and completed files must remain unchanged. Verify failure gives no promised image/file and preserves newer clipboard content. Native checks cover Copy, Copy Drawing, and drag data through the isolated test app.

## Approval and state

The filename cutover and retention of completed versions are approved. The implementation passed the complete unit suite and isolated native verification.

`RenderingQueue.render` takes `output: .file` or `.bytes`. It allocates file results before queuing,
and `PendingRendering` owns that URL. Clipboard methods consume the pending result alone. Completed
command and log answers return absolute paths in a JSON `files=` array.

The shipped skill, both plugin manifests, current guides and E2E consumers follow the returned
paths. Byte-only Send now renders an empty drawing through the same background renderer. Destination
discovery compares the existing annotator opening identity. Bare Copy still carries original bytes.

The existing rendering tests were extended for unmarked orientation and DPI, separate files for
two drawings of one source, delayed consumption, multibyte source names, and real write refusal.
The complete suite passed 471 tests. Eleven native flow checks passed, including distinct result files through clipboard replacement and restart, quoted JSON paths, and unmarked oriented-JPEG Send at 144 DPI. Native drag delivery remains covered by the existing promised-item contract and requires a dedicated drop-target check for further changes.
