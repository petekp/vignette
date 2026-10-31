# Codex answers live ink too

Live ink's quick answers come from Claude Code or Codex. Each is a responder Vignette keeps
running. A note starts on the agent the person used last among those that can answer, worked out
as Send works it out (`DestinationChoice`). Until the ink is cleared, a note starts on the agent
the last ask went to, so a conversation never moves to the other agent by itself. The note's target
menu lists both, so one note can go to the other. When the chosen agent cannot answer, the note
says why and names the other when it can.

ADR 0021 rejected Codex because `codex exec` took 16 to 23 s cold. A `codex app-server` that keeps
one thread warm answered 12 asks with a median of 2.8 to 3.6 s on `gpt-6-astra` at `low` effort,
which is about what Sonnet takes through `claude -p`. The model is `gpt-6-astra` when `model/list`
offers it, else the account's default.

Codex's responder runs on a Codex home of Vignette's own, under Application Support, never the
person's. Codex sends its home's `AGENTS.md` to the model on every turn, whatever its config says.
Arguments turn off every feature, and the model catalog Vignette writes leaves the model no tool.
Before any screen content is sent, a warm-up runs on a thread whose model provider is a listener
inside Vignette. The real thread opens only if that request has `tools: []` and nothing in its
input but Vignette's prompt. Otherwise Codex cannot answer, and the note says why.

That home is signed in once, through Codex's own browser login (`account/login/start` with type
`chatgpt`). Codex keeps and renews the sign-in in `auth.json` there. Vignette never reads the
person's own sign-in. On a ChatGPT sign-in, an ask counts against the plan's usage limit.

## Considered options

- The person's own Codex home, with every feature turned off by arguments. Their `AGENTS.md`
  would go with every ask, and the isolation check refused a home that had one.
- A home of Vignette's own with a link to the person's `auth.json`, which the spike used. Codex
  0.165 writes `auth.json` in place. A build that wrote it by rename would turn a renewal in
  Vignette into the person being signed out of the Codex app and CLI.
- Passing the person's tokens over the protocol (`account/login/start` with type
  `chatgptAuthTokens`). Codex 0.165's schema marks it "[UNSTABLE] FOR OPENAI INTERNAL USE ONLY -
  DO NOT USE", and its binary carries the switch that turns it off: "Access token login is
  disabled. Use API key login instead."
- A setting for which agent answers. The agent used last is already worked out for Send, and the
  target menu covers a single note.

Sources: `docs/live-ink-release-plan-2026-10-24.md` (decision 11), `docs/codex-issues.md`
(progress log, 2026-10-30). Supersedes: 0021.
