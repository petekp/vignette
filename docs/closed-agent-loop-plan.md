# Closed agent loop implementation plan

Status: revised proposal with the four adversarial review findings addressed in the design. The first-release session ownership choice and reply trust model remain explicit decision gates. The defined contracts require implementation and live verification; this document does not authorize product or build/configuration changes.

The goal is to send a drawing to a particular coding session, receive an image with editable agent marks, and reply to that same session. The first release should prove that interaction in ordinary use before adding more providers, session management, or history features.

Evidence: [the original loop spike](screenshot-loop-spike-2026-09-20.md), [the Codex image-path queue test](codex-queue-image-paths-2026-09-20.md), and [the existing Herdr send exploration](send-to-agent-exploration-2026-09-17.md).

## Implementation model recommendation

Recommendation: Claude Opus 5 at high effort for the first bounded implementation slice. Anthropic positions Opus 5 for complex agentic coding and recommends starting there before moving to Fable for work where it falls short. This is a starting recommendation, not a Vignette-specific comparative benchmark. If implementing in Codex, use GPT-6 Astra at high effort instead. No model or effort setting has been changed.

The main risks are exact session addressing, Swift/AppKit and web-editor coordination, persistence, and failure recovery. Keep one implementation owner and prove one complete native Codex screenshot round trip before expanding the feature. The complexity mistakes in the earlier plan were planning failures; changing models does not by itself prevent them.

Sources: [Claude model guidance](https://platform.claude.com/docs/en/models/overview), [Claude effort guidance](https://code.claude.com/docs/en/model-config#choose-an-effort-level), and [GPT-6 Astra](https://developers.openai.com/api/docs/models/gpt-6-astra).

## 1. Connect directly to agent sessions

The planned loop uses the agent's native connection. The terminal displaying that agent is not part of the delivery path. A Codex session with a known native connection can appear inside Herdr, Ghostty, or another terminal without a corresponding Vignette terminal adapter.

Do not add Herdr-specific discovery, pane targeting, terminal drivers, or a generic PTY launcher for this feature. The existing debug Herdr send command remains unchanged; deleting or refactoring it is unrelated to delivering the new native loop. The earlier Herdr experiment remains useful historical evidence, not a requirement to build another integration.

The first demonstrated native send route is `codex queue` with an image path, addressed by conversation UUID at its owning App Server endpoint. The spike proved idle wakeup, busy-session ordering, multiple recipients, and delivery into an attached TUI. It did not prove automatic connection to arbitrary existing CLI or desktop sessions.

The remaining setup decision is specific: establish a supported way to obtain an existing session's native endpoint, or explicitly choose Vignette-created Codex sessions. The latter starts a dedicated App Server and creates threads that the user can open with `codex resume <UUID> --remote <endpoint>`. It changes session ownership and requires decisions about server lifetime and native approvals. Do not select it silently or add it merely because discovery is unproved.

If Vignette-created sessions are selected, keep approval decisions in the native agent interface. Closing Vignette is not implicit permission to terminate active coding work. Do not implement a generic launcher or session-management framework to support this one concrete route.

**Gate:** settle native Codex connection setup and prove the exact session binding plus the private-directory image/reply probe. If that fails, report the concrete limitation. Do not automatically add a terminal integration as a workaround. Claude's native channel remains a later, explicitly approved integration because of its preview restrictions.

## 2. Keep only necessary components

For each proposed component, name the current requirement and why a simpler existing capability is insufficient. Do not retain an alternate architecture merely because it could be useful to some future integration.

| Component | Current reason to retain it |
| --- | --- |
| Native agent connection | Submit a request to the selected conversation. |
| Fixed image and request record | Preserve what was sent and where replies belong. |
| Reply authorization and receipt | Reject mismatched replies and let the sender know whether Vignette accepted them. |
| Deferred import and publication state | Keep an accepted reply intact while the editor is busy and prevent incomplete cards. |
| Send/Reply controls | Make the exchange usable from the existing product. |

The general MCP server deferred in `docs/TODOS.md` is not a prerequisite for the first Codex route. A future provider may require MCP or another native mechanism; justify that mechanism for that integration when it is needed.

The earlier Herdr recommendation was an alternative implementation of sending, not a dependency of native agent integration. It is removed from planned work. Keep existing code untouched and preserve historical notes rather than maintaining two new send architectures.

A small native connection boundary is enough for another agent to be added later. Do not prebuild terminal transports, interaction drivers, a plugin registry, a marketplace, or an external executable protocol.

## 3. Limit the first release

Build:

- User-initiated exchanges with one selected recipient per send.
- Multiple independent requests, each pinned to its original recipient.
- A minimal Send action and Reply action on returned cards.
- Fixed outgoing PNGs.
- A fresh watch-folder file for every accepted reply, with editable agent marks.
- Receipt correlation, duplicate-reply protection, visible submission uncertainty, and deferred import while the editor is occupied.
- Preservation of Done, copy, existing shortcuts, and ordinary screenshot handling.

Defer:

- Agent-initiated exchanges with no preceding request.
- Native Claude channels and ChatGPT.
- General session discovery outside the selected native connection.
- Managed session restart/reconnection, automatic resubmission, and offline delivery guarantees.
- Multi-recipient broadcast, merged annotation branches, a history browser, and a general agent-settings dashboard.
- New plugin-install/uninstall machinery unless the selected route actually requires it.

Persist accepted request/reply records so Vignette does not report success and immediately forget them. After restart, restore their status and identify interrupted operations. Do not promise automatic transport recovery or replay accepted/uncertain sends. Resume a locally persisted pending import only when its payload is complete and its request is still valid.

## 4. Set the file and card rules

Every reply is a new file and therefore a new card. The current app has one draft per file path; the plan does not introduce several visible revisions of a single file or merge replies into the user's current draft.

| Artifact | Location | Lifetime and display rule |
| --- | --- | --- |
| Original screenshot | Existing watch folder | Remains a normal screenshot controlled by the user. |
| Fixed sent PNG | Application Support, under the request ID | Delivery artifact only. Never offered to the editor or stack from this location. Kept until the request is explicitly cleared in the alpha. |
| Request record and reply ticket | Same private request directory | Holds destination, status, reply authorization, and references to app-owned reply records. No duplicated original image or separate draft history. |
| Submission bundle and per-attempt receipt | Issued request directory, in separate submission and receipt subdirectories | The helper freezes the bundle once and retains it until an accepted receipt. Vignette alone writes receipts at derived paths. |
| Accepted reply payload | Private request directory | Vignette owns the PNG and canonical marks bytes before acceptance. Keep this recovery copy until publication succeeds; do not depend on helper temporary files. |
| Imported reply PNG | Watch-folder root | The reserved name `Agent reply <full reply UUID>.png`; never a name ending in `-annotated.png`. Keep the human-readable title in card metadata. A durable import record excludes it from all normal Vignette paths until publication. |
| Editable agent marks and preview | Existing DraftStore/cache | Associated with the new reply file's path. |

The original screenshot and sent PNG are intentionally separate: editing or deleting the watch-folder original must not change an already-issued request. The private sent copy is not a second gallery item. `LocalServer` does not need to serve it.

For a reply on the sent image, copy that fixed PNG into the watch folder under the reply's unique name, then apply the agent's marks. Earlier human marks are already rendered into that PNG. Only the newly supplied agent marks are editable in this first version. Preserving all earlier human marks as editable shapes is a later feature, not a property proved by the spike.

A reply may instead provide a new PNG plus marks. Validate and import it under the same fresh-file rule. Never overwrite the active drawing or reuse the request's input path as its reply path.

Tidying the screenshot folder can delete an imported reply like any screenshot. Do not recreate it automatically. Its request metadata may remain for diagnosis, but should indicate that the visible file is gone. Retain the originating reply destination while its card exists.

Bound pending bytes and request count. At the alpha limit, stop accepting additional work and offer explicit clearing rather than silently deleting a PNG that an agent may still read. Choose measured limits before implementing this store.

## 5. Reply authorization and receipts

A `vignette://` URL has no authenticated sender. Neither `agent=codex` nor a model-supplied session UUID proves authorship. The proposed first-release authorization is a local per-request bearer ticket. It permits a reply to one request; it does not prove which agent process produced that reply.

Vignette generates a random secret bound to the request and fixed destination. The agent receives a restricted ticket-file path. The raw secret need not be in the prompt, but the agent's tools can read it. This does not isolate mutually untrusted processes running as the same macOS user with access to those files. Request IDs are correlation values, not secrets; there is no verified-author badge.

Cancelled, cleared, or expired requests reject new replies. Clearing a request with accepted but unpublished replies explicitly cancels those imports, records that outcome, and removes only task-owned files. Existing accepted receipts remain historical acknowledgements; they are not rewritten as “never accepted.” Keep a minimal tombstone for the defined retention period. Choose expiry and retention limits before implementation.

**Decision gate:** accept this capability model, or require a separately proved runtime-bound authentication mechanism. The receipt and publication contracts below apply in either case. Do not replace authorization with an agent-name field.

### Helper submission and stable identity

The helper has separate prepare and submit operations. Preparing freezes a bundle containing `protocolVersion`, `requestId`, a new `replyId`, the base-image reference or copied new PNG, canonical marks/text, and a payload digest. The digest covers the request identity, image bytes/reference, marks, and text, not mutable source paths. The authorization secret is carried separately and is excluded from logs and image metadata.

A submit retry reuses that prepared bundle, reply ID, and digest. It never re-reads a changed source file or generates a new reply ID. A deliberate new reply requires a new prepare operation. On uncertainty, return the prepared-bundle location so the caller can retry that operation. This is the helper contract; repeatedly creating new bundles is not a deduplicated retry.

Each actual dispatch has a distinct `attemptId`. The helper writes its envelope under the issued request's restricted submission directory, then invokes `vignette://reply?file=<envelope>`. The URL carries no raw secret. The app validates the canonical path, file type, size, IDs, version, authorization, and digest. It refuses path traversal and symlink escapes and never accepts a caller-selected receipt destination.

Within the selected local trust boundary, the helper writes submission files; Vignette owns the authoritative request/reply records and receipts. Setup verifies the helper's necessary read/write/launch access, not just image reading. A returned PNG is fully staged before dispatch so an agent can clean up its original temporary file without changing a retry.

### App acknowledgement

Vignette writes an atomic JSON receipt at the derived request-owned path `receipts/<attemptId>.json`. No new listening server is required. This is an explicit extension of the existing URL command contract: URL dispatch remains one-way, and the receipt file supplies the application response.

A receipt includes:

```text
protocolVersion, requestId, replyId, attemptId, payloadDigest
acceptance: accepted | rejected
publication: pending | ready | failed | cancelled | removed | null
errorCode: optional machine-readable reason
```

For an accepted reply, Vignette first copies every required image/marks byte into app-owned storage and atomically commits the reply record. Only then does it acknowledge acceptance. Receipt creation can be retried from that authoritative record. A crash after commit but before receipt creation is recovered by submitting the same reply ID/digest again.

- New valid reply: persist its owned payload and record, then acknowledge `accepted/pending`.
- Same reply ID and same digest: return its recorded acceptance/publication state. Do not create another card.
- Same reply ID and different digest: reject the new attempt without modifying the existing reply or its receipts.
- Known issued request with invalid, expired, or revoked authorization: reject that attempt. No payload acceptance or import occurs.
- Unknown request, unsafe envelope location, or an envelope from which no valid issued attempt can be identified: refuse it without writing to an arbitrary location. The helper may observe uncertainty rather than a specific rejection.

Per-attempt receipts prevent a malformed or conflicting attempt from overwriting the acknowledgement another caller is waiting for. Validate all correlation fields and the digest when reading a receipt. A stale receipt for another attempt does not satisfy the wait.

The helper waits up to 30 seconds by default for a matching receipt. A nonzero URL-dispatch result is a dispatch error, not necessarily proof that acceptance never occurred. Missing receipt after the deadline is `unconfirmed`; retain the bundle and retry only with the same reply ID/digest. Do not infer application acceptance from `open` exiting zero or from an unrelated log line. An older app without the command therefore cannot produce a false success.

An `accepted` receipt transfers payload ownership to Vignette; the helper may release its bundle. It means received for import, not visible or rendered. Import failure after acceptance retains app ownership and is reported through publication status/UI, not by resending a new reply. A status query or duplicate submission can return the current publication state; a late `ready` receipt is not required to keep the helper process alive.

Use atomic writes for helper bundles, app records, and receipts. Protocol version checks fail closed. Keep restricted permissions, finite payload/attempt limits, and redacted errors. Local hostile same-user processes remain outside the bearer-ticket guarantee.

**Receipt tests:** invalid ticket on a known request, conflicting digest, old app/no command, delayed URL handling, mismatched receipt IDs, crash before acceptance commit, crash after commit before receipt, and repeated dispatch after lost acknowledgement. Accepted payloads must remain importable after deleting all helper source files.

The reply helper remains a bundled skill resource where possible. Do not add a daemon, general MCP server, or interpreter installation without a concrete need and the applicable approval.

## 6. Make file access part of connection setup

The spike's image files were readable in the test thread's working directory. That does not establish read access to Application Support or the screenshots folder in another session. Conversely, access denial is not universal: it depends on that session's configured policy.

Before marking a connection usable:

1. Put a synthetic probe image and ticket in the actual private delivery directory the feature will use. Build the minimal prepare/submit/receipt helper first; setup is not complete while that path is missing.
2. Ask the selected session to read the image and return a correlated probe answer through the helper.
3. Verify the image-only answer, authorization, and matching application receipt, including the helper's required filesystem writes. The route also has to satisfy the automatic-delivery eligibility policy; a successful probe alone cannot waive it.
4. If the runtime requests permission, the user grants only the required access in its own interface. Do not widen sandbox permissions silently or assume Vignette can grant them.

Setup may submit its fixed, non-sensitive probe after the route's conversation guard is established and the user invokes Connect, even while file access is not yet verified. That limited probe does not authorize sending real drawings. Create the usable `AutomaticBinding` only after the complete probe succeeds. A route without a conversation guard uses manual handoff even for its probe.

For Vignette-created Codex threads, explicitly configure the intended file access through supported permission settings and verify it. Test that ordinary project work still uses its native approval workflow.

Show only access or approval states the native connection actually reports. If no positive acknowledgement or specific failure exists, show awaiting reply/connection unverified. A timeout does not establish that a permission prompt occurred.

Do not report “Read” from successful subprocess exit. For ordinary requests, distinguish runtime acceptance from a later reply. Detailed read receipts can wait if the chosen route cannot report them reliably.

## Native connections and extensibility

Use the terms in [CONTEXT.md](../CONTEXT.md). An agent session is the recipient. A terminal is where its UI happens to be displayed; it is not another required integration layer.

### One shared screenshot workflow

Vignette owns export, fixed request storage, reply validation, receipts, deferred import, and cards. Native connections own the provider-specific addressing and submission calls. Neither native connection should manipulate the drawing UI or implement another reply store.

Keep the connection boundary small:

```text
AgentConnection
  verify(destination) -> connection status
  submit(automaticBinding, preparedRequest) -> submission outcome
```

A prepared request contains its ID, fixed image reference, user instruction when supplied, and reply instructions. An automatic binding contains the native conversation identity, owning endpoint/installation scope, and relevant connection generation. The connection translates the request to its native mechanism. For Codex this is the queue command with a conversation UUID and image path.

Keep versioned native address data with its implementation. The coordinator should not branch on terminal names, and the native implementation should not depend on them. Submission outcomes distinguish runtime acceptance, definite non-submission, changed/unavailable destination, and uncertainty after possible acceptance. A healthy connection is not proof that a model read the image.

Explicit setup supplies known connections. Add enumeration or session creation only when the selected native mechanism requires and supports it. There is no generic discovery registry, session-launching framework, or static catalog to build before the first route works.

### Adding another agent

Implement its native connection and any instructions it needs to read images and return replies. Reuse the request records, reply validation, receipts, import queue, and UI. An agent displayed in several terminals still uses that one native integration.

Prove the actual missing capability before adding anything else. If the runtime cannot receive an external message or return the required data, mark that integration unsupported or use manual copy/paste. Do not automatically introduce a terminal adapter, wrapper, or new service to fill the gap.

Native Claude channels and ChatGPT remain separately gated. Ordinary MCP tools do not by themselves supply a portable push-to-session API. A future cloud integration needs real file transfer; a local path cannot be presented as that capability. No extension runtime or plugin loader is part of this plan.

The earlier agent-driver/terminal-transport design is withdrawn. The review finding about duplicating agent-specific terminal behavior is resolved by excluding raw terminal injection from this feature, rather than constructing another reusable layer to support it. Revisit that problem only if a concrete approved requirement cannot be met natively.

**Extension check:** a second native integration must reuse the core screenshot and reply workflow. Verify the same native connection from sessions displayed in different terminals without changes to Vignette's delivery code. This establishes terminal independence without implementing terminal support.

### Automatic-Send eligibility policy

Automatic means Vignette submits input without the person pasting and pressing Enter in the agent UI. It does not mean delivery without the person's Send/Reply action.

| Connection evidence | Automatic Send/Reply | Allowed behavior |
| --- | --- | --- |
| Native immutable conversation address enforced by the receiving runtime | Eligible after the read/reply probe and endpoint binding check | Submit to that exact conversation. A changed selected tab is irrelevant; a missing/archived/unavailable conversation is an error, not a replacement target. |
| Session-scoped receiver with an atomic expected-conversation/generation check before acceptance | Eligible after its guard and read/reply probe are proved | Reject old generations before writing or queueing any input. |
| Unknown conversation identity or a preflight check without a receiver-side guard | Ineligible | Manual copy/paste only. Do not add terminal input as a workaround. |
| Unknown/failed image access, reply setup, required native capability, or stale endpoint | Ineligible until repaired and reprobed | Explain the unavailable capability and retain the request. |

A native queue may accept input while the model is working only if that is the runtime's proved queue behavior. An interactive approval prompt must not receive synthetic text. Unsupported native busy behavior keeps automatic submission disabled; Vignette does not substitute terminal input. A valid reply ticket does not establish outbound readiness.

An `AutomaticBinding` is invalidated when its receiver connection generation changes, its conversation handle is replaced, its process exits where process lifetime is part of the proof, or required access is revoked. The receiver must address the immutable conversation or validate the expected generation during acceptance; a delayed lifecycle hook cannot provide that guarantee by itself. `/clear`, resume into a different conversation, and pane reuse cannot inherit the former binding. A new binding requires explicit selection/setup; do not silently redirect queued requests.

A temporary transport disconnect does not change request ownership. It blocks new delivery pending a verified reconnect. Do not interpret a recycled port or pane ID as the original receiver. Timeout after possible acceptance stays unknown and never causes automatic cross-route retry.

For current evidence, Codex queueing by UUID at the known owning endpoint is the conversation-addressed candidate. The new loop does not add a pane-based fallback. The legacy debug send command remains outside this guarantee and outside this implementation scope.

**Eligibility tests:** change the conversation after connection verification and before submission; resume another conversation; reconnect to a different server at a reused endpoint; revoke read access; deliver while busy or awaiting approval. Verify that the native receiver enforces the selected conversation or Vignette refuses automatic submission.

### One reply path

The first-release URL/helper feeds the existing request coordinator's reply-validation path. A later provider-specific reply tool should translate into the same internal input and supply its actual authorization evidence. It cannot bypass request matching, limits, deduplication, or deferred import. Bearer authorization never becomes verified authorship just because a different native transport supports stronger identity.

Keep the receipt and publication contracts below. They address observed failures in the core workflow and do not depend on a terminal abstraction.

## 7. Implement the smallest complete slice

### A. Target connection and read probe

Implement the selected native connection from section 1. Supply it directly to the screenshot request coordinator. Leave the existing Herdr debug command untouched; no catalog, terminal discovery, or legacy extraction is needed.

**Pass:** two distinct sessions, the minimal helper and matching-receipt path, a successful private-directory read/write/reply probe, and a proved automatic eligibility decision. A target change detected before acceptance is refused; uncertainty is reserved for an operation that may already have been accepted, not permission to send to a possibly different conversation.

### B. Non-closing export and submission

Add an export operation that returns the current image as PNG or a typed error without calling `window.vignette.finish()`.

The existing Done path is unsuitable: `renderDone` sends `cancel` on rendering failure, and native `finishAnnotation` eventually invokes the finish transition even when writing the output failed. Do not change Done's existing contract as a side effect of Send.

Capture the image key, recipient, and operation generation at the click. Commit text editing and take a consistent snapshot through the canvas queue. Prevent overlapping sends and define whether input is briefly disabled during snapshot capture. A late result must never refer to a newly selected image or close it.

Keep the annotator open until the fixed PNG and request record are safely stored. Then close the same image through the existing close/park path, without copied feedback. Submission proceeds against the saved request. On export/storage error, leave the drawing open. Closing or switching during preparation cancels that pending send; after runtime acceptance, cancellation cannot be represented as guaranteed cancellation of the agent's work.

Represent submission IO in the send operation, separately from the flight reducer. A new reducer phase is not assumed. Add behavior sequences first for export failure, late completion after switching, double Send, close during preparation, and successful close without a copied badge. If the existing reducer cannot express the chosen behavior, specify the additional event before editing its table.

For a known owning Codex endpoint, use `codex queue` with UUID and quoted image path as one argv element, storing its returned message ID. Do not route that request through Herdr or another terminal. Runtime acceptance does not mean the image has been read.

A definite pre-submission failure may be retried. A timeout after possible submission produces “Delivery uncertain”; do not automatically resubmit or claim exactly-once delivery.

**Pass:** the exact current drawing reaches the selected session, the editor stays intact on failure, and uncertain submission never causes an automatic duplicate.

### C. Transactional reply acceptance and publication

Implement the reply command after the trust-model gate is resolved. Use the prepare/submit/receipt protocol above. Acceptance transfers ownership of a complete payload to Vignette; publication makes the card eligible for normal use. These are different durable events.

Choose a durable visibility ledger rather than expanding LocalServer's file allowlist. Reserve a final watch-folder path in the reply record before placing a PNG there. Every non-published managed reply path is excluded from normal Vignette presentation and actions, even if the PNG itself is valid. The private accepted payload is a recovery copy, not a directly rendered gallery item.

Import sequence:

1. Copy the submitted PNG (or the request's fixed base PNG), canonical marks, and text into an app-owned staging directory. Check bytes, dimensions, and digest. Atomically commit `accepted`; then an accepted receipt may be written. Never acknowledge an envelope whose referenced bytes remain owned only by the helper.
2. Under the serialized coordinator, reserve the final filename and record `reserved`. Persist its exclusion and install it in the live visibility policy before copying. Use exclusive creation/no-overwrite semantics; an unexpected existing file is a collision to resolve before committing a different reserved name.
3. Copy the owned PNG atomically to that reserved path and record `imageStored`. The path remains excluded. The renderer can read it under the existing watch-folder access rule.
4. When the canvas is free, build the requested marks using that final path, then persist the snapshot and produce a usable preview. Draft saving must return success or throw; do not treat the current logging-only `storeDraft` method as a durable acknowledgement. An image-only reply explicitly requires no draft.
5. Once the PNG, required draft, and initial usable preview are confirmed, atomically commit `published` in the authoritative reply record. That commit is the single publication point. Only afterward release the visibility exclusion and ensure the card is present once.
6. Update receipt/status to `accepted/ready`. A failure writing this derived receipt does not undo publication; a repeated request reconstructs it from the authoritative record.

Preview files remain derived cache data. Later eviction may require rebuilding a preview from the durable image/draft. While that happens, show a loading/preview-unavailable state for a managed reply instead of presenting its unannotated base as the finished drawing.

On startup, load and validate the visibility ledger before starting the watcher, warming thumbnails, restoring cards, or processing image actions. If the ledger is corrupt/unavailable, fail closed for managed reply files until it is repaired; do not reinterpret the reserved managed-reply namespace as ordinary captures. Use the exact managed filename shape `Agent reply <full reply UUID>.png` so those files remain identifiable when the index needs repair; it is reserved for this feature. Do not classify all files starting with “Agent” as managed replies. Preserve ordinary screenshot behavior outside that namespace.

Apply the visibility policy at every consumer, including live `onNew`, recent/newest queries, warm-up, explicit annotate/copy commands, and card insertion. Filtering only the directory listing is insufficient because cached results and delayed watcher events may already exist. Renderer-internal access to the reserved path remains permitted for the importer.

Persist managed-file attribution after publication. A late watcher event for that file must not trigger copy-on-capture or annotate-on-capture. Repeated watcher/import events resolve to the same reply ID and reserved path, so they cannot create a second card. Do not reuse `Commands.destination` on each retry and produce numbered duplicate files.

Before publication, any copy/draft/preview failure leaves the file excluded and the app-owned payload retained with a precise failed/pending stage. Restart or retry resumes that same reply and path after rechecking its bytes. If the configured watch folder changes during import, stop with a destination-changed state rather than publish into an unverified folder. Recovery remains local import recovery, not automatic agent resubmission or session reconnection.

After publication, deleting the reply file is a user removal: record `removed` and never recreate it from the recovery copy. Explicit request clearing cancels unpublished imports and revokes new replies. Remove only owned files. Keep enough status/receipt history to report that an accepted reply was later cancelled or removed.

**Pass:** stop the app after acceptance, reservation, PNG copy, draft write, preview creation, publication commit, and before card insertion. Restart and open Recent/newest and exercise explicit file actions. There must be no normal managed card before publication and exactly one afterward. Inject a draft-write error, late watcher events, duplicate submissions, changed source files, helper-source deletion after acceptance, and ledger corruption. None may produce a false ready state or an ordinary capture side effect.

### D. Minimal interface

- Add Send and a visible target selector to the annotator. Enable automatic submission only for `AutomaticBinding`; weaker destinations get an explicit Copy for manual handoff action.
- Returned cards expose Reply with the recorded target.
- Show enough session title/provider/project information to distinguish targets.
- Show Sending, Sent, Reply waiting for editor, and actionable failure/uncertainty as supported by real state.
- Keep Done and existing shortcuts. Defer a separate send shortcut until the flow is stable.
- Defer the optional text composer from the alpha; the agent uses the existing task context and may ask for clarification. A later composer must be a separate key-capable surface because the toolbar panel cannot take keys.
- Do not add a full settings dashboard. Add only the setup controls required by the chosen session route.

Old agent-labelled cards do not gain a guessed return address. An unavailable destination does not redirect to the focused pane or another recent session.

**Pass:** draw → Send → new reply card → edit → Reply works through the real interface, alongside a second independent exchange, without managing request IDs or filenames.

### E. Verification and handoff

Extend existing command, send, render, draft-store, and transition tests for the new contracts. Add narrowly scoped request/ticket tests where there is no existing coverage. Keep live provider checks opt-in and use isolated settings, identity/data, and known synthetic images.

Required checks: the automatic eligibility race cases; the receipt/ownership and stable-retry matrix; publication crash/failure stages across every watcher/action consumer; two same-named sessions; private-directory read/write access; current draft capture; export failure; filename spaces; changed image dimensions; queue ordering; and multiple distinct replies. Verify that the native connection works independently of the terminal displaying the agent. Raw-terminal adapters are outside scope.

Record the native connection and session setup that actually passed. The earlier Herdr experiment neither proves nor gates the new native loop. A session being visible in a terminal does not establish that its native endpoint is reachable.

Use existing build/test commands. Any necessary build target, bundling, signing, or deployment changes still require specific approval before editing; the plan does not waive those rules.

## Proposed file map

These are proposed ownership boundaries, not a file quota or implemented APIs. Co-locate small related code rather than create a file for each operation. Only add the selected native integration. There is no Herdr adapter, terminal transport, agent interaction driver, generic launcher, or plugin registry in this work.

| Proposed file | Current responsibility | Main functions/methods |
| --- | --- | --- |
| `Sources/AgentConnection.swift` | Small native connection contract, destination/binding types, and eligibility checks. | `verify(destination:)`, `submit(request:to:)`, `deliveryEligibility(for:)`. Co-locate concrete types until sharing them is useful. |
| `Sources/CodexConnection.swift` | Direct Codex queue submission and native endpoint checks. | `verify(destination:)`, `submit(request:to:)`, argument construction, receipt/error parsing. Add concrete server/session lifecycle methods here only if Vignette-owned sessions are explicitly selected. |
| `Sources/ScreenshotRequests.swift` | Coordinate Send/Reply, accept reply commands, and expose request status/visibility to the product. | `send(shot:to:)`, `retrySubmission(requestID:)`, `cancel(requestID:)`, `clear(requestID:)`, `receiveReply(envelopeURL:)`, `isVisible(_:)`, `shouldHandleAsCapture(_:)`. Visibility is derived from the store, not another durable ledger. |
| `Sources/RequestStore.swift` | Single writer for fixed images, request/reply records, reservations, and receipts. | `load()`, `createRequest(...)`, `recordSubmission(...)`, `acceptReply(...)`, `reserveReplyPath(...)`, `recordImportStage(...)`, `commitPublication(...)`, `writeReceipt(...)`. |
| `Sources/ReplyProtocol.swift` | Envelope/receipt types, canonical payload identity, authorization, and safe paths. | `decodeEnvelope(at:)`, `validateEnvelope(...)`, `payloadDigest(for:)`, `issueTicket(for:)`, `verifyTicket(...)`, `receipt(for:)`. Ticket methods remain conditional on the trust-model decision. |
| `Sources/ReplyImporter.swift` | Render accepted replies when the editor is free and commit publication. | `resumePendingImports()`, `canvasBecameAvailable()`, `importNext()`, `retryImport(replyID:)`, `finishImport(...)`, `failImport(...)`. |
| `Sources/AgentDestinationPicker.swift` | Minimal selection of configured native destinations. | SwiftUI `body`, filtering, selection, and connection/setup actions. No discovery framework or routing logic in the view. |
| `skills/vignette/scripts/reply` | Agent-facing prepare/submit/receipt helper. Language and packaging still need a concrete decision. | `prepare(...)`, `submit(bundle:)`, `waitForReceipt(attempt:)`, `validateReceipt(...)`, `main()`. |

The separate receiver, visibility, connection-catalog, terminal-driver, and host-transport files previously listed are removed. Their necessary work either belongs to the coordinator/store or is outside scope. Do not reintroduce them merely to follow the old file map.

Extend existing command, render, watcher, stack, and transition tests. Add focused connection, request-store, reply-protocol, and importer tests only for contracts those suites do not already cover. No separate generic-adapter conformance framework is required.

Existing files still need targeted changes:

- `AppDelegate.swift`: wire the coordinator, route replies, and restore import visibility before watching.
- `AnnotationController.swift`, `web/src/App.tsx`, and `web/src/render.ts`: non-closing current-image export with explicit errors.
- `Bridge.swift` and `web/src/bridge.ts`: mirror and version any changed export contract.
- `AnnotatorToolbar.swift`: Send/Reply and destination selection while preserving Done and focus behavior.
- `ThumbnailController.swift`, `StackView.swift`, and `ScreenshotWatcher.swift`: shared visibility checks and managed-reply status/event handling.
- `Commands.swift`: the new reply command without changing existing command meanings.
- `DraftStore.swift`: use the existing throwing save API; change only what the new persistence contract actually requires.
- `StateReport.swift` and `skills/vignette/SKILL.md`: observable non-secret state and accurate helper instructions.

`Sources/Send.swift` needs no Herdr extraction or rewrite for this feature. Build, signing, and packaging changes remain conditional and require specific approval before editing.

## 8. Later work

Evaluate Claude's native connection when its preview setup and distribution constraints can be accepted explicitly. Verify conversation identity across changes before enabling automatic Send. ChatGPT needs its own native connection/file-transfer proof. Neither requires a Herdr or Ghostty integration simply because an agent UI appears there.

Agent-initiated images, automatic reconnect/restart recovery, broader native session discovery, complete editable history, and text composition are candidates to evaluate after the basic loop is used. A future need is not an instruction to build their supporting abstractions now.

## Review disposition

The four findings from [the adversarial review](closed-agent-loop-plan-review.md) are addressed in the design below. This is not a claim that the future implementation or portability tests have passed.

| Adversarial finding | Design resolution |
| --- | --- |
| No automatic-delivery eligibility policy | Mandatory conversation identity, receiver-enforced dispatch guard, separate automatic/manual binding types, and concrete invalidation tests. Current weak pane routes are not grandfathered in. |
| No application acknowledgement for replies | Prepared immutable bundles, stable reply IDs, per-attempt atomic receipt files, explicit ownership transfer, and timeout/rejection/conflicting-payload rules. |
| Incomplete replies visible after interrupted import | Durable path reservation and visibility ledger, explicit draft-write result, a single publication commit, startup ordering, and filtering of all listing/action consumers. |
| Agent-specific terminal behavior would be duplicated | Remove raw terminal delivery from scope. Native integrations avoid that behavior entirely; no driver/transport framework is required. |

Earlier review findings:

| Finding | Revision |
| --- | --- |
| Native discovery was not demonstrated | Native endpoint setup remains a gate. Managed Codex means creating and owning sessions and requires an explicit choice; terminal integration is not the fallback. |
| Claude preview restrictions were understated | Native channels deferred; restrictions stated directly. No alternate terminal route is added to avoid that decision. |
| Existing decisions were silently reversed | No general MCP server is required for the first Codex route. The Herdr experiment stays historical and its code remains untouched; it is not a dependency of the native loop. |
| Sender authentication was unspecified | Concrete per-request capability proposal with a named trust boundary and a decision gate; no verified-process claim. |
| Multiple revisions were not representable by cards | Every reply becomes a new watch-folder file; full editable history deferred. |
| Image storage/display rules conflicted | Private fixed delivery PNGs versus visible watch-folder replies are separated; no LocalServer allowlist expansion assumed. |
| Image-read permissions were not established | Positive read/reply probe from the actual delivery directory; generic blocked and timeout signals are not overinterpreted. |
| Send failure needed a real lifecycle design | Non-closing export with operation identity; Done path not reused; specific transition sequences required. |
| First-release scope was too broad | One selected route, user-initiated requests, fresh-file replies, minimal Send/Reply UI, and only necessary local persistence. |
