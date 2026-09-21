# Adversarial review of the closed agent loop plan

Original reviewed plan: [closed-agent-loop-plan.md](closed-agent-loop-plan.md), SHA-256 `9de3fc48bd9b839e7662d4c8f7429f2f6356ebac1939f8c88a8f3dd784d39718`.

Scope: the saved plan, its glossary, recorded spike results, and the current Vignette and Herdr code paths relevant to delivery and reply import. This is a design review. The failures below identify missing or contradictory contracts; they are not claims that a new implementation was run and failed.

Original verdict: the reviewed snapshot was not ready for implementation because four contracts were unresolved. The first-release route and reply trust model were already explicitly gated decisions and were not counted as new defects. The finding locations below refer to that original snapshot.

## Resolution after Pete requested all findings be addressed

All four findings are addressed in the implementation plan's design. Updated plan SHA-256: `25dedec9e2c14c1c437429d7d738318ef6ea4eb45d996295cb4b962851417a55`. This records a document/contract resolution, not implemented behavior or a passed live test.

| Finding | Resolution | Verification still required during implementation |
| --- | --- | --- |
| 1. Automatic delivery eligibility | [Mandatory policy](closed-agent-loop-plan.md#automatic-send-eligibility-policy), distinct automatic/manual binding types, receiver-enforced conversation identity, and lifecycle invalidation. The implementation uses native connections; a terminal route is not added as a workaround. | Real same-process conversation switch, pane/process replacement, busy/approval state, and stale endpoint tests. |
| 2. Reply acknowledgement | [Prepared bundles and app receipts](closed-agent-loop-plan.md#5-reply-authorization-and-receipts), stable reply IDs/digests, per-attempt receipt paths, 30-second default wait, and explicit app ownership before acceptance. | Invalid authorization, conflicting payload, missing/old receiver, lost receipt, and acceptance crash/retry matrix. |
| 3. Partial reply publication | [Transactional import](closed-agent-loop-plan.md#c-transactional-reply-acceptance-and-publication), durable path reservation/exclusion loaded before watcher startup, explicit persistence outcomes, and a single publication commit. | Crash every import stage; test all listing/action consumers, delayed events, draft-write failure, helper-source deletion, and ledger corruption. |
| 4. Agent-specific interaction behavior | [Native connections](closed-agent-loop-plan.md#native-connections-and-extensibility) remove raw terminal delivery from scope. No terminal-driver framework is built to solve a problem created by an unnecessary layer. | Verify the native connection independently of the terminal displaying its UI. Generic raw-terminal support is not claimed. |

Contract trace checks covered the four counterexamples in this review. The plan now defines refusal/manual handling for a changed conversation, an unconfirmed outcome when no application receipt exists, exclusion of unfinished files after restart, and removal of the raw-terminal behavior that required a client-by-terminal abstraction. Application code, runtime configuration, and the historical spike evidence were not changed.

The native connection ownership/setup and authorization-model choices remain visible gates. They have not been approved or silently selected. Following Pete's complexity correction, Herdr-specific work, raw-terminal drivers, and a generic launcher were removed from the plan; the existing debug command is untouched. Native agent integration is the direction, regardless of the terminal used.

## 1. High: exact-session delivery has no enforceable eligibility policy

**Location:** plan lines 183–198 and 243–254; first-route gate at lines 24–28.

The plan permits bindings whose expected agent-session identity is known only optionally. It lists native-conversation addressing, checked panes, unavailable guards, and unknown busy behavior, then says the core will decide what action to offer. It never specifies which combinations may use automatic Send.

That omission leaves a concrete unsafe case: inspect a terminal while it contains conversation A, switch to conversation B in the same agent process, then submit. The terminal ID, executable, agent kind, and cwd can all remain valid. A successful image-read probe in A does not protect a later send to B.

The plan itself records that the inspected Herdr prompt API has no expected-conversation-ID parameter. The source supports that observation: `AgentPromptParams` contains only target, text, and wait options. Submission checks the recognized foreground agent and blocked state, not a caller-supplied conversation ID.

**Why it matters:** a connector can satisfy the proposed interface while delivering a request to a different conversation than the one associated with its reply ticket. Describing the route as weaker does not define whether the UI should permit that action.

**Smallest fix:** add an explicit automatic-delivery eligibility table. State what conversation evidence and submission guard are required, when only manual handoff is allowed, and whether any checked-pane race is an accepted product limitation. Define invalidation on conversation changes within the same process. Do not equate a healthy transport with a valid recipient.

**Verification:** change the conversation between inspection and submission without replacing the process; repeat with agent exit to a shell and pane reuse. Every supported route must either refuse/rebind or meet its explicitly accepted delivery guarantee. A mock adapter merely returning `targetChanged` is not proof that the real connector can detect it.

**Code evidence:** `Sources/Send.swift:43`, Herdr `src/api/schema/agents.rs:179`, and Herdr `src/app/api/agents.rs:138`–`199`.

## 2. High: the reply helper has no acknowledgement protocol

**Location:** plan lines 94–97 and 318–324.

The helper creates an envelope and invokes `vignette://reply?file=...`. The plan then promises acknowledgement after persistence and returning an existing result on duplicate reply IDs. No channel carries those results back to the helper.

Launching a URL hands a request to an application; it does not return the application's command result. Vignette's current URL handler returns no result to the caller. `Commands.ok` and `Commands.error` write log lines. The existing spike drivers obtained results by separately observing those logs.

An invalid ticket, unsupported command version, or failed persistence can therefore occur after URL dispatch appears successful. Without a specified receipt path, the helper cannot know whether to report success, retain its files, or retry. The duplicate-ID rule also needs the helper to preserve the same reply ID across those retries, rather than regenerate an ID on every invocation.

**Why it matters:** the return half of the loop can falsely report success or produce duplicates even when the core's ticket validation and deduplication are correct.

**Smallest fix:** define a durable receipt keyed by request ID and reply ID, plus how the helper obtains it. A bounded file-based receipt protocol can preserve the URL-only first release; alternatively, explicitly choose correlated log observation or another response mechanism. Specify accepted/pending-import versus ready versus rejected, helper timeout behavior, payload ownership, and stable retry IDs. URL-dispatch success alone must never count as acceptance.

**Verification:** launch against a receiver that rejects the ticket, an older app without the command, and a receiver that crashes immediately before or after persisting acceptance. The helper must distinguish rejection from uncertainty and retry an uncertain submission with the same reply ID and unchanged payload.

**Code evidence:** `Sources/AppDelegate.swift:459`–`472` and `Sources/Commands.swift:241`–`247`.

## 3. High: the reply publication boundary does not cover the watcher and restart path

**Location:** plan lines 73–80 and 318–320.

The plan puts each reply in the watched root, applies marks, and promises that no ordinary card appears before those marks are stored. The existing import path copies the image into that root before the draft build completes. Its suppression state, `pendingAdds`, exists only in memory.

A crash after the PNG copy and before draft persistence leaves a valid ordinary screenshot filename. After restart, the watcher can index it without the missing in-memory suppression. Opening Recent takes the watcher's indexed files directly; it does not filter out unfinished reply imports. A durable envelope alone does not keep that file out of the stack.

There is also an import outcome issue at the same boundary: `storeDraft` currently catches a write failure and returns no success value, while the caller can continue toward an `ok` result. The planned acceptance/publication logic cannot rely on the existing helper's return as proof that the draft is durable.

**Why it matters:** an incomplete reply can appear as an ordinary unannotated image, or the importer can declare it ready without a stored draft. Retrying can then create another file/card instead of finishing the original import.

**Smallest fix:** define import states and the single publication point across the request record, file, draft, preview, watcher, and stack. Either use staging that is not eligible for listing until commit, or load a durable pending-file exclusion before starting the watcher and apply it to every listing path. Persist the final filename before copying and reuse it on retry. Make draft-write success observable. Account for LocalServer's existing file-access rules if staging is used.

Acceptance of the reply payload and publication of its card should remain separate. Before acknowledging acceptance, Vignette must own every referenced image/marks byte needed to complete the import, not rely on an agent retaining temporary source files.

**Verification:** stop the app after each of: acceptance, final-name reservation, PNG copy, draft write, preview write, and publication. Restart and open Recent. Expect zero normal cards before the publication condition and exactly one complete card afterward. Inject a draft-write failure and delete the agent's source image after accepted receipt.

**Code evidence:** `Sources/AppDelegate.swift:33`–`42`, `:689`–`729`, `:787`–`820`, and `Sources/ScreenshotWatcher.swift:151`–`156`.

## 4. Medium: prompt-only profiles do not isolate agent-specific terminal behavior

**Location:** plan lines 200–206, 212–216, and 272–288.

The portability claim is that another terminal needs one adapter while existing agent profiles remain reusable. But profiles are explicitly limited to image/reply instructions; they cannot describe input submission, readiness, or retry behavior. The plan provides no reusable home for those agent-specific interaction differences when the host itself does not supply them.

Herdr already contains a concrete example: its prompt submission special-cases GitHub Copilot by sending a focus-gained event before text/Enter, because otherwise Enter can be ignored after focus loss. Herdr also separates paste data and Enter with a submission delay. A generic Ghostty text/key adapter does not acquire those behaviors from an instruction-only profile.

**Why it matters:** the next terminal adapter can accumulate its own switches for every agent client. That recreates the client-by-terminal maintenance matrix the architecture is intended to avoid. This does not require adding all known clients now; it requires a boundary capable of housing the demonstrated distinction.

**Smallest fix:** distinguish agent interaction behavior from terminal IO, or explicitly narrow the portability promise to hosts that already implement agent-aware submission. A reusable agent driver can govern readiness/submission over a small terminal transport. Herdr may encapsulate that behavior internally; a native API route can bypass terminal IO entirely. Keep the driver focused on actual behavior rather than adding a speculative framework.

**Verification:** exercise two clients with different submission behavior through two terminal transports. Prove that changing the agent-specific behavior has one implementation and does not require editing the core screenshot loop or copying it into both terminal adapters. This proof can be a disposable integration experiment before freezing the contract.

**Code evidence:** Herdr `src/app/api/agents.rs:13`–`24` and `:175`–`198`; Ghostty's inspected `input text` and `send key` scripting commands are terminal input operations.

## Original fix order

1. Define the delivery guarantees and automatic-Send eligibility policy.
2. Complete the reply helper's acceptance/receipt and retry contract.
3. Specify atomic reply publication and startup visibility rules.
4. Prove the reusable agent-behavior/terminal-IO boundary with a second transport.

Do not reopen already-explicit limits as if they were new findings: native discovery remains unproved, a shared launcher remains an unspiked option, channels remain deferred, and bearer tickets are explicitly not verified authorship. The narrow alpha scope, fixed sent PNG, new-file reply rule, typed submission uncertainty, and separation of session creation from discovery remain useful.

The original review changed no application code or implementation-plan text and ran no new live experiment. The follow-up revised the implementation plan and added the resolution table above; it also ran no live agent or UI tests. The evidence for the original findings remains the saved snapshot, earlier experiments, and current source inspection.
