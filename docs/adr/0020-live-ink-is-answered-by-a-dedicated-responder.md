# Live ink is answered by a responder Vignette runs

An ask about live ink goes to one `claude` process Vignette keeps running, on the person's own
Claude Code sign-in, not to the session they are working in. Over 7 days of Pete's transcripts a
session was mid-turn 66 to 80% of the time, so ink sent to it waited a median of 6 to 10 minutes;
the responder answers in about 2 seconds, while the screen is as it was, so its answer can be drawn
on the screen. Sending to a working session stays a choice in the note, and its answer is drawn on the window too
(ADR 0021).

The responder runs with `--safe-mode --tools ""` and its own system prompt: started plainly, it
loaded the person's hooks, plugins and MCP servers, registered itself as a session in Vignette's
inbox, and could read files. It stops before any screen content is sent unless its `init` line lists
no tool but the answer's. Every ask costs the person about $0.01 to $0.02 at Sonnet's prices.

## Considered options

- The person's working session, which is usually mid-turn.
- Codex through `codex exec`, which took 16 to 23 s cold.
- Haiku, which was slower than Sonnet, not faster.
- `claude --bare`, which reads only an API key, not the person's sign-in.

Sources: docs/live-ink-integration-2026-10-04.md (decision 7), docs/live-ink-step2-spike-2026-10-04.md.
