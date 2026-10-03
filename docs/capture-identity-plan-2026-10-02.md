# Preserve screenshots through renames

Preserve a screenshot's drawing and active work when its filename changes. Start by settling the supported rename cases. A watcher rename event and a drawing-file move alone cannot meet this requirement.

This is an investigation and implementation proposal. App source, tests, and tooling have not changed for this effort. Standalone probes used temporary files and opened no app windows.

## Evidence and affected consumers

A screenshot currently contains one URL. A drawing uses its path as its key. The watcher compares filenames, so an ordinary rename becomes a removal and an arrival. The removal deletes the stored drawing. The arrival can copy the renamed file and show or open it as a new capture. This follows from the code; it has not been reproduced in the native app during this effort.

| Consumer | Current identity and consequence | Source |
|---|---|---|
| Screenshot value | It contains a URL and derives image versus recording from the extension. A rename must preserve kind eligibility and update location. | `Sources/Settings.swift:6-18` |
| Screenshot inventory | Names identify entries. Directory device/inode identify the watched folder, not each screenshot. | `Sources/ScreenshotWatcher.swift:29-69`, `234-278` |
| Drawing storage | The path determines the JSON filename and must match the stored key. | `Sources/Drawing.swift:23-34`; `Sources/DrawingStore.swift:28-60` |
| Drawing updates | Loads capture path and revision. Writes and removals update those revisions. Rename must invalidate work for the previous location. | `Sources/Drawings.swift:58-75`, `100-128` |
| Cards | A presentation has a UUID, but its screenshot URL is immutable. Selection and focus use the UUID. Retaining that UUID avoids a new entrance and lost selection. | `Sources/ThumbnailController.swift:4-21`, `25-54` |
| Annotation run | Open image, queue, swap target, and failed-copy state use path strings. | `Sources/AnnotationRun.swift:13-24`, `46-63`, `85-120`; `Sources/AnnotatorTransition.swift` |
| Active editor | Drawing lookup and loaded-image callbacks compare the path. The opening has a separate generation. | `Sources/EditorView.swift:843-858`; `Sources/AnnotationController.swift:143-175`, `503-506` |
| Notices and loading | Notices, flight images, image cache, and drawing reads use paths. A later completion must still reach the same screenshot. | `Sources/CardNotices.swift:66-90`; `Sources/ThumbnailController.swift:521-543`, `1076-1104`; `Sources/Thumbnailer.swift:137-144` |
| Queued renderings | The job captures its source URL when queued. A rename before the job opens that URL can make Copy or Send fail. | `Sources/RenderingQueue.swift:23-38` |
| Pushes and Send outcomes | Pending pushes use filenames; sent screenshots retain their original URL until delivery answers. Rename must not attach a delayed result to a different file with that name. | `Sources/AppDelegate.swift:55-72`, `1103-1145`, `1175-1192` |
| Managed replies | Reply identity is encoded in a reserved filename. Visibility, origin, and deletion also require the recorded output URL. Renaming a published reply crosses this contract. | `Sources/ReplyProtocol.swift:54-65`; `Sources/ScreenshotRequests.swift:129-135`, `181-225` |
| Command admission | Paths are normalized to the screenshots folder's spelling. Physical identity must retain this admission policy. | `Sources/Commands.swift:113-149` |

The current drawing-storage policy names files by hashed paths. Changing it requires a new ADR. The policy permits changing the drawing format without retaining older-build compatibility readers.

Source: `docs/adr/0011-drawings-belong-to-the-app.md`.

Local metadata probes established a narrow result. A same-directory rename retained its resource identifier. A hard link shared that identifier. A copy had a different identifier. A minimal bookmark resolved the resource in another process, but selected its hard-link pathname. After removing that link, a second resolution selected the renamed pathname. These probes used one local filesystem. They did not test iCloud, another volume, a system restart, or permission loss.

Apple documents resource identifiers as objects compared by equality. Paths to the same inode on the same filesystem compare equal. The identifier is not persistent across system restarts. Directory enumeration can prefetch this property alongside dates. That establishes an available mechanism, not its cost on a provider-backed folder.

Sources: [resource identifiers](https://developer.apple.com/documentation/foundation/urlresourcekey/fileresourceidentifierkey), [directory enumeration](https://developer.apple.com/documentation/foundation/filemanager/contentsofdirectory(at:includingpropertiesforkeys:options:)).

Retained probe results: `/private/tmp/vignette-capture-probes.1qwz_ddj/identity-results.json`, `bookmark-results.json`, and `bookmark-without-hardlink-results.json`. Compile and run commands exited successfully. The observations and fixture operations are recorded above.

## Proposed scope and next evidence

Settle these product and contract choices before implementation:

1. **Preserve renames made while Vignette is closed.** Recommended. The screenshot is the same file to the person. Runtime matching alone cannot support this. A persistent locator needs validation before choosing bookmarks or file metadata.
2. **Keep active annotation continuous during a rename.** Recommended. Preserve marks, undo, selection, queue order, focus, and flights. Editor history stores mark edits rather than full drawing keys, which helps this change. Closing and reopening would lose active work and interrupt the native interaction.
3. **Define managed-reply renames explicitly.** Recommend preserving the reply's origin and publication identity. Publication filenames remain derived during import. A verified later rename changes the output location. The current stored-location validation and filename-derived lookup must change together under an approved contract.
4. **Define moves, replacement saves, and hard links.** Recommend a first scope of in-folder renames. A move out of the screenshots folder changes listing eligibility. Hard links represent multiple entries for one resource. An atomic replacement may be a new resource. These cases need explicit rules rather than guessed one-to-one matching.

Use unambiguous resource matching to report a verified rename before emitting removals or arrivals. Preserve folder availability, mount cutoffs, pending-arrival tokens, and delayed-delivery checks from the deletion-safety work. Unavailable enumeration still cannot authorize a rename or deletion.

For active state, separate screenshot identity from its current location. Introduce a stable identifier only where the approved rename behavior requires it. The screenshot owner should resolve that identifier to its current URL. Retain presentation UUIDs and annotation-open identity. Those identify a card and one opening, respectively.

The implementation must replace path identity across the affected consumers in one coherent slice. Moving only the drawing JSON is insufficient. A drawing re-key needs atomic storage behavior and revision invalidation for both paths. Queued renderings must resolve or pin their source through the same owner before reading. Late decode, destination, notice, and drawing callbacks must use screenshot and open identity rather than the previous pathname. Preserve historical request labels; changing a current screenshot's location does not rename an image already sent in a durable request.

The cheaper alternative is a same-launch rename event followed by transactional re-keying of existing path-based state. It is appropriate only if the approved scope excludes offline renames. It still needs the full consumer list above. A broad file-locator protocol is unnecessary until there are concrete locator implementations to compare.

The next cheap probe should create a real PNG and sidecar drawing in a temporary folder. Compare resource identifiers and bookmark resolution through rename, process restart, atomic replacement, hard links, and a folder symlink. Record ambiguity and missing-resource outcomes. A separate authorized native round should then rename an inactive drawn screenshot and an image open in the annotator. Check persisted marks, unchanged selection and clipboard count, queue continuation, and late callbacks. Managed replies need their own origin and publication check.

Permanent coverage belongs at the chosen screenshot-identity module's interface and the affected existing reducers/stores. Add only cases that protect the approved contract. Keep native motion and pointer verification because a storage test cannot establish flight continuity.

Critical review: this plan requires a persistent-locator decision for offline behavior, a complete active-state update, and explicit managed-reply handling. The local bookmark result does not justify choosing bookmarks alone. Missing identifiers and ambiguous matches need a conservative unresolved state rather than a guessed transfer of marks. Native rename frequency, provider behavior, and listing cost remain unmeasured.
