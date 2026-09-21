# Codex queue with image paths — 2026-09-20

`codex queue` can deliver an image path to a persistent Codex session. The agent opens the file with `view_image`. No image attachment flag is needed.

This corrects the earlier spike's recommendation. Rejecting `-i` and ephemeral threads was not evidence against queueing a file path to a persistent thread.

## Tested setup

- Codex CLI and App Server 0.154.0; the displayed model was `gpt-6-astra low`.
- Two disposable persistent threads on a separate loopback App Server.
- Read-only sandbox, approval policy `never`, and synthetic PNGs in the working directory.
- Image paths containing spaces, passed inside one `--message` argument using a subprocess argument list.
- A Codex TUI attached to the first thread through `codex resume <UUID> --remote <endpoint>`.

Actual send shape:

```sh
codex queue --remote ws://127.0.0.1:54970 \
  --thread 01a0c176-bfab-7662-9ffb-a30cc3490835 \
  --message 'Open "/path/input 47.png" with view_image and describe the circled tile.'
```

The endpoint and UUID above belonged to this disposable run. They are not reusable connection settings.

## Results

| Check | Result |
| --- | --- |
| Idle session | Queue acceptance automatically started a turn. No further user message or explicit `turn/start` call was needed. |
| Two recipients | A read the orange selection; B read the teal selection. Both read the image-only code `VESPER-4829`. Each emitted an `imageView` event for its own file. |
| Busy session | Q3 and Q4 were queued 75 ms apart to A. Q4 started after Q3 completed. They remained separate turns and answered teal, then orange. |
| Open CLI | After attaching the TUI to A, Q5 arrived through the queue, appeared in that CLI, opened the image, and returned the correct teal selection plus arrow coordinates. |
| Names versus UUIDs | Exact-name lookup refused delivery because it could not establish uniqueness across server pages. The same request succeeded immediately with the verified UUID. |

Five successful messages produced five image-read events and five correct visual answers. Q3, Q4, and Q5 used filenames and request IDs that did not disclose the selected color. All sends used text paths, not image attachments. The driver observed native events but did not manually start any of the five turns.

Q3 completed at epoch `1789952245.934`; Q4 started at `1789952245.943`. That demonstrates queued next-turn behavior rather than steering the active turn. The initial idle requests finished in roughly 10 seconds each; this is a single-run timing observation.

Q5 returned:

```json
{"request_id":"Q5","code_word":"VESPER-4829","selected_color":"teal","marks":[{"type":"arrow","x":0.35,"y":0.27,"x2":0.185,"y2":0.54}]}
```

The exact-name failure was:

```text
Cannot verify a unique session label across server pages; matching session UUID:
01a0c176-bfab-7662-9ffb-a30cc3490835. Use it only if this is the session you want.
```

This did not establish that duplicate names existed. It established that this lookup could not prove uniqueness. Use UUIDs in the adapter.

## Limits and setup findings

The test used `--remote` with the known endpoint of the engine owning the threads. The default local daemon socket was absent on this Mac. Discovering and reaching arbitrary existing desktop or ordinary CLI sessions is still unverified; passing a thread UUID alone does not establish that the queue command is talking to its owning engine.

Files were readable under the test thread's existing sandbox. This does not establish access to arbitrary screenshot folders, files on another machine, or files deleted before the agent reads them. Keep a fixed exported image until receipt is confirmed.

Remote TUI resume rejected explicit `--sandbox` and `--ask-for-approval` overrides. Attaching without those flags succeeded and retained the thread's existing permissions. A CLI update prompt was skipped; no update was installed.

This follow-up tested the send path and the ability to return mark data. It did not relaunch Vignette or repeat the already-proven draft import. No application source or user task was changed. The two test threads were archived after evidence capture, and the test CLI and server were stopped.

## Decision

Prefer `codex queue --thread <UUID> --message <image path plus request>` as Vignette's Codex send adapter when the owning endpoint is available. It handles idle wakeup and busy-session ordering without requiring Vignette to drive `turn/start` or `turn/steer` itself. Retain a separate reply tool and request correlation for the return path.

Evidence: [queue-path-summary.json](spikes/screenshot-loop-2026-09-20/queue-path-summary.json) and [queue-path-events.jsonl](spikes/screenshot-loop-2026-09-20/queue-path-events.jsonl). The disposable driver, terminal capture, and thread snapshots were archived outside the repository on the machine the spike ran on; they are not part of this checkout.
