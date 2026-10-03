# Claude Code receives sends through the plugin's monitor, in any terminal

Every send to Claude Code is written to an inbox folder that the plugin's monitor reads between
turns. The monitor runs in every Claude Code session. The route is the same in every terminal, and
the person sees a clean prompt. Nothing on this route refuses a stale session, so Vignette checks
that the inbox still holds that exact session just before it writes.

## Considered options

- Typing into the terminal, through herdr or through Accessibility.
- Claude Code's cross-session socket, whose message format is undocumented.
- Channels, which need a launch flag on every session.
- A `UserPromptSubmit` hook, or `claude --resume -p`.
- Starting the monitor only after a session used the skill. Rejected because a session that had
  not used the skill yet could not receive a send.

Sources: `docs/claude-code-without-herdr-2026-09-27.md`, commit 72695f0.
