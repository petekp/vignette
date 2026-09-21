# Screenshot reply loop spike — 2026-09-20

The local loop works. Claude Code and Codex received a drawing, returned editable marks, and received a revised drawing in the same sessions. A separate test woke an idle interactive Claude Code session through an MCP channel and completed the same round trip without terminal input for either screenshot request.

Follow-up: [`codex queue` with image paths passed](codex-queue-image-paths-2026-09-20.md) in persistent sessions, including idle wakeup, two concurrent recipients, ordered follow-ups, and delivery to an attached CLI. Prefer this simpler send adapter when the owning App Server endpoint is known. The attachment and ephemeral-thread failures below do not rule out this route.

This is experimental evidence, not a shipped integration. No application source, build scripts, agent rules, or infrastructure configuration was changed.

## Question and budget

Can Vignette address a particular live agent session, receive its marks, let a person change the drawing, and deliver that change back to the same session? Can simultaneous sessions be kept separate when replies finish out of order?

Budget: 30 minutes of experimentation, then recording and cleanup. A positive result required real image input and real model responses. Correct answers had to include a code word visible only in the image, the selected tile, and marks aimed at that tile. A negative transport result was also useful: it would eliminate a proposed adapter before implementation.

## What ran

- Existing Vignette build `107f0b7-dirty`, bridge protocol 15. This was the already-built bundle, not a rebuild of the checkout. Its build stamp is not proof of an exact clean source revision.
- Claude Code `2.1.278`. The successful headless responses used its default Opus 5 model; the successful interactive channel session displayed Sonnet 5. The spike did not force a model override.
- Codex CLI `0.154.0`, using a separate App Server and ephemeral threads.
- Python 3.14, Pillow, and Node 24.21.0. No new dependencies were installed.
- A synthetic 1000 × 640 PNG with the code `VESPER-4829` and teal, magenta, and orange tiles. The code and correct selected color were not supplied in the agent prompt.

The test driver made the person's drawing through the actual tldraw editor in Vignette's WKWebView. It called the real finish/export path. This exercised the editor, export, file handling, model image input, reply parsing, draft import, and second-turn delivery. It did not test a human drawing with a mouse or a finished Send/Reply interface.

## Observed results

| Experiment | Observation | What it establishes |
| --- | --- | --- |
| Two-provider loop | Claude and Codex each identified orange, returned marks, then identified teal after the drawing changed. Each kept its own user-provided experiment label. | Real image input and two turns in the same distinct sessions. |
| Editable reply | The native editor contained an agent arrow and text with `meta.agent: true`. The driver deleted them and drew a new ellipse. The exported PNG showed the new selection. | Returned marks were editable shapes, not a flattened overlay. |
| Two Codex threads on one server | `codex-a` received orange and `codex-b` received teal. B finished before A. Each response retained its own request ID and correct image answer. | Concurrent native thread routing and out-of-order response correlation. |
| Invalid Codex recipient | `turn/start` with an unknown UUID returned `thread not found`, code `-32600`. | That path failed rather than falling back to another thread. |
| Interactive Claude channel | An HTTP event woke the idle TUI. Claude called `fetch_image`, then `reply`. The reply was imported into Vignette, edited, exported, and pushed again. Both answers were correct. | A real push route into a running interactive session, independent of Herdr. |
| Busy Vignette editor | `add?marks=` returned `page-not-ready` before copying the incoming file. The same request imported after the editor closed. | A reply needs to be retained and retried by the adapter. |
| `codex queue -i` | Exit 1: `codex queue does not support image attachments`. | The advertised shared help flag is not implemented by this command. |
| Text-only queue into an ephemeral thread | Rejected: `ephemeral thread does not support queued submissions`. | This spike cannot establish queued delivery to persistent or ordinary TUI sessions. |

The successful two-provider sessions were:

- Claude: `25eccfc3-a698-4f02-baa9-73c47364fbad`.
- Codex: `01a0c15e-3ab9-7a92-87b1-620965e31a47`.

The successful interactive channel session was `5b506aa0-e088-4f30-b887-e6d566ae2f4e`. It received both screenshot requests through channel notifications. Terminal input was used for setup and exit, not delivery of those requests.

The channel's first notification was written at epoch `1789951311.568`; the image was fetched at `1789951314.015`; the reply was stored at `1789951316.971`: about 5.4 seconds from notification to reply. These are single-run observations, not latency guarantees.

## Working transports

### Codex

The driver launched `codex app-server --listen stdio://`, initialized the JSON-RPC connection, created an ephemeral thread, and submitted each screenshot through `turn/start`:

```json
{
  "threadId": "<exact thread UUID>",
  "input": [
    { "type": "text", "text": "<request with correlation ID>" },
    { "type": "localImage", "path": "<exported PNG>" }
  ]
}
```

It collected the final `agentMessage` and checked `turn/completed`. A second experiment submitted images to two threads on the same server and associated notifications by `threadId`.

This proves delivery through an App Server that the integration can reach. It does not prove attaching to an arbitrary existing Codex desktop or TUI process. Starting another App Server or resuming stored history must not be mistaken for connecting to the engine that already owns a live turn.

### Claude streaming input

The driver kept one `claude -p --input-format stream-json --output-format stream-json` process alive, with `--no-session-persistence`. It sent two user messages containing image content blocks. The session ID stayed unchanged. No built-in tools were available in this small vision test.

This proves a bridge-owned Claude process can keep the conversation across drawings. It is not an attach API for an unrelated terminal session.

### Claude interactive channel

A temporary MCP server implemented the actual JSON-RPC protocol over stdio. It declared `experimental.claude/channel`, exposed `fetch_image` and `reply`, and sent `notifications/claude/channel` with a request ID in `meta`.

`fetch_image` returned the PNG as MCP image content. `reply` stored the request ID, observed code, selected color, and normalized arrow coordinates. The adapter imported the original fixture plus those marks through Vignette's existing `add` command.

The server listened on a temporary loopback port with a generated request credential. The credential was not placed in the notification, model input, evidence archive, or Vignette URL.

The working launch combined:

- An approved `.mcp.json` registration in the disposable folder.
- Explicit `--strict-mcp-config --mcp-config <scratch config>`.
- `--dangerously-load-development-channels server:vignette_spike`.
- Only the two named MCP tools permitted for this experiment.

The development-channel confirmation was accepted for the locally authored server. Pete explicitly approved trusting the disposable folder. No trust was granted to the Vignette repository during this spike.

Earlier configurations connected an MCP tool server but did not deliver channel events. One interactive startup said `no MCP server configured with that name`. A headless notification returned HTTP 200 and was written to MCP, but produced no image fetch or reply within 45 seconds. A project-only configuration also did not produce a reachable test listener. The successful combination is recorded above; this run did not isolate whether registration, loading order, launch mode, or another configuration detail explained all earlier failures. Do not generalize those failed attempts into a claim that headless channels are unsupported.

## Learnings for implementation

1. **Use an exact session address and a separate request ID.** The two Codex threads completed in reverse order. Provider names, reply order, and the latest screenshot are insufficient. Keep the session association in the adapter, not solely in model-generated text.
2. **Distinguish an attachment from a path in text.** Codex `localImage` worked. `codex queue -i` explicitly did not. The later image-path test passed: the agent opened the file through `view_image`. The attachment failure does not disqualify queueing a path.
3. **A connected tool server is not proof of push delivery.** A channel startup notice is also insufficient. Require an image-fetch acknowledgement or reply for the specific request.
4. **HTTP 200 is a transport acknowledgement.** In the failed channel attempt it meant only that the local receiver wrote a notification. It did not mean the agent consumed it.
5. **Keep recipient failures independent.** Early driver versions stopped processing results when one provider failed. The corrected driver recorded a recipient failure and continued collecting other results.
6. **Check error fields, not just a success label.** Claude twice returned `subtype: success` with `is_error: true`, `terminal_reason: api_error`, and `stop_reason: refusal`. Treat that as a failed response.
7. **Avoid artificial secret-recall prompts in the transport test.** The first such prompt and a reworded experiment-label prompt were rejected on the second turn with `reasoning_extraction`. A normal follow-up about the changed circle succeeded. This does not establish the refusal's underlying cause. Record the provider error without treating it as successful delivery or silently changing models.
8. **Snapshot the image at Send.** Vignette's ordinary `-annotated.png` is overwritten on later finishes. The driver copied each completed export before giving it to an agent. A real exchange needs an immutable image revision.
9. **Bind marks to a base image.** This spike used one known fixture and applied each agent's marks to that original. It did not preserve a full annotation history. A real reply must identify its base image or carry a new image explicitly.
10. **Do not confuse pixels with canvas points.** The 1000 × 640 PNG occupied a 500 × 320 tldraw image shape. The first driver's circle was outside the screenshot and therefore absent from export. The fix used the image shape's actual dimensions. Both image-only and drawn-image results were real; the failure was in the driver.
11. **Normalized marks worked across this scale difference.** Agent arrow coordinates were passed to the existing `marks=` importer, which placed them on the intended tile. This only verifies the tested orientation and aspect ratio, not cropping or rotated images.
12. **Use `%20` for spaces in Vignette URLs.** Python's default `urlencode` used `+`, which Vignette interpreted literally. `reply-claude 2.png` became a missing `reply-claude+2.png`. `quote_via=urllib.parse.quote` fixed the driver.
13. **A file path is not a portable identity.** Python imports resolved `/var` through `/private/var`, while the launch environment retained `/var`. The safety guard correctly stopped that mismatch. The driver then reused its recorded launch path. Exchange IDs should survive equivalent paths, duplicate filenames, and moves.
14. **Incoming marks need backpressure.** While the annotator was occupied, `add?marks=` refused the request. Retain the response and retry after the editor is free. Avoid repeated notification or duplicate cards on retry.
15. **Do not recover ephemeral history through `thread/read(includeTurns: true)`.** App Server explicitly rejects it. Capture live events during an ephemeral experiment.
16. **The provider session can survive multiple drawing turns.** Both successful headless sessions retained separate experiment labels across the changed image. The interactive channel also stayed in one session across both pushes.
17. **Reply rendering is not a finished visual design.** The arrows hit their targets, but one agent's text overlapped the fixture heading. The spike proves transport and editability, not collision-free annotation placement.
18. **Scratch settings alone do not isolate every Vignette side effect.** Draft storage follows bundle identity. `agentSkill: off` invokes skill removal, and the installer treats any decodable ownership marker as its own without comparing the app name. The test copy used a separate identity and omitted its bundled skill with `agentSkill: on`, producing a harmless missing-skill log instead of running install/removal. This was read-only analysis and test isolation; the installer was not changed.

## Isolation and remaining limits

The copied app was named `VignetteSpike`, with bundle ID `com.petepetrash.vignettespike`, URL scheme `vignettespike`, its own log, and separate draft/cache directories. Only the copied bundle's metadata and signature were changed. Its settings were seeded from Pete's file and redirected to a task-owned screenshot folder. Apple save-location synchronization and launch-at-login were disabled for the copy.

Every action checked the test process's launch environment and a tagged native state response. The original Vignette process stayed running. Done and Copy Drawing intentionally exercised the real clipboard, so the clipboard was changed to a synthetic test image.

The experiment does not establish:

- ChatGPT conversation integration. No plugin was installed in ChatGPT and no hosted conversation was connected.
- Delivery to an arbitrary already-open Codex TUI or desktop task.
- Retrofitting a Claude channel into a session that did not enable it at startup.
- Offline delivery, restart recovery, cancellation, durable deduplication, or multi-device transfer.
- A new screenshot captured by an agent after changing a real product. Replies here were structured marks on a known synthetic image.
- A production session picker, Reply button, annotation history, or transport service.

## Decision

The shared exchange format is feasible. Build the next implementation around exact recipient IDs, immutable image revisions, explicit reply correlation, image-fetch acknowledgement, and retained responses while the editor is busy.

Claude channels deserve an adapter: the live interactive loop worked without Herdr. The follow-up supports `codex queue` with an image path as the simpler Codex send adapter when the live engine is reachable. Direct App Server image input remains an option when attachments or detailed turn control are needed. Keep generic MCP read/reply tools independent of the mechanism that wakes an agent. ChatGPT remains a separate integration proof.

## Evidence

Evidence is in [spikes/screenshot-loop-2026-09-20](spikes/screenshot-loop-2026-09-20/):

- `events.jsonl`: timestamped successful rounds, failed attempts, native routing, and busy-editor results.
- `claude-round*.json` and `codex-round*.json`: actual model responses and normalized marks.
- `multi-thread-results.json`: the two native Codex replies, in completion order.
- `round1.png` and `round2.png`: the actual exported images sent to the models.
- `round2-shapes.txt` and `channel-human-round2-shapes.txt`: agent shapes before deletion and the replacement human ellipse in the real editor.
- `*-final-render.png`: Vignette exports containing returned agent marks.
- `codex-reply-native.png`: a capture of the actual native annotator window.
- `channel-server-events.jsonl`, `interactive-channel-requests.jsonl`, `channel-reply-*.json`, and `interactive-terminal.json`: real notification, image-fetch, reply, and TUI evidence.
- `cleanup.json`: final checks on the original app and settings.

The disposable scripts and failed-attempt images are retained in a separate evidence archive outside this repository, on the machine the spike ran on. They contain absolute scratch paths and a test PID, have limited error recovery, and are not an installable integration. The archive omits runtime credentials, copied personal settings, and the app bundle.

Cleanup verified that the original app PID `32185` was still running and that both the SHA-256 and modification time of Pete's settings were unchanged. The test app was terminated, and its screenshot folder and draft list were empty. The approved scratch-folder trust entry and Claude's own interactive session histories remain. The clipboard contains a synthetic test image.

Relevant protocol references: [Codex App Server](https://learn.chatgpt.com/docs/app-server), [Claude streaming input](https://code.claude.com/docs/en/agent-sdk/streaming-vs-single-mode), and [Claude channels](https://code.claude.com/docs/en/channels-reference). Runtime observations above take precedence over inferred support from help text.
