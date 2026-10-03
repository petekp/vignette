# A destination is an agent session, never the terminal showing it

Send addresses the conversation itself: a Codex thread by its UUID, and a Claude Code session by
its session id. A pane can show different sessions over time, so a send addressed to a pane can
reach the wrong conversation. A terminal host such as herdr only says which session has the focus.

## Considered options

- An adapter that delivers through herdr's panes, or one adapter per terminal. Rejected because
  each adds a layer for a terminal, and every agent client can be reached without one.

Sources: `docs/glossary.md`, `docs/closed-agent-loop-implementation-2026-09-20.md`.
