# Codex, tested live

Vignette was tested against the real Codex CLI and the Codex desktop app (`/Applications/ChatGPT.app`,
bundle id `com.openai.codex`) on 2026-10-01. The test copy was the E2E build, launched on scratch
settings and a scratch watch folder, with `VIGNETTE_CODEX` naming a real `codex`. It ran without
`CFFIXED_USER_HOME`, so its request folders were under the real `~/Library/Application Support`,
where a real Codex session's reply helper looks for a ticket. Messages went only to threads made for
the test, in `/private/tmp/claude-501/vignette-codex-test`. The issues it found are tracked, with
their progress, in `docs/codex-issues.md`.

Two CLIs are on this Mac:

| CLI | Version | Path |
| --- | --- | --- |
| On the PATH, which Vignette uses | 0.154.0 | `~/.vite-plus/bin/codex` |
| Inside the Codex app | 0.159.2 | `/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex` |

## What works

- **The whole loop with a CLI session.** Send from the editor reached an idle interactive Codex
  session at once. The session read the skill and viewed the image. Asked for a drawing, it ran
  the skill's reply helper, and its circle and note came back as a card with the Codex badge, in
  the agent colour. About 20 s from the request to the card.
- **The whole loop with the Codex app.** The same, through a thread the Codex app holds. The app
  ran the turn 3 s after the send, and its drawing came back as a card.
- **The sandbox and approvals.** Both sessions ran with this Mac's `workspace-write` sandbox and
  `on-request` approvals, reviewed by `guardian_subagent`. The reply helper's first run failed
  inside the sandbox ("cannot write the reply bundle"). Each session then asked to run it outside
  the sandbox, the guardian approved in 4 to 6 s, and the helper answered `accepted`. No person
  had to answer anything.
- **Listing.** Both CLIs list the threads through `codex app-server`'s `thread/list` in 0.05 to
  0.3 s. Send's default target was the thread used last, with either CLI.
- **Installing the plugin.** `install-skill?root=<scratch>/.codex` ran `codex plugin marketplace add`
  and `codex plugin add` with `CODEX_HOME` set to the scratch folder. It installed
  `vignette@vignette-e2e` 6.1.0 in under a second, `codex plugin list --json` reported it, and the
  skill names the copy's own URL scheme and log. The real `~/.codex` was left alone.

## What is wrong

1. **Send no longer starts on the thread the Codex app shows.** Vignette reads the open thread's
   title through Accessibility (`AgentApp.openThread`). The current app (26.928) exposes no page:
   one window titled "ChatGPT", 12 empty groups, and no focused element. `AXManualAccessibility`
   is no longer among its attributes, and setting it or `AXEnhancedUserInterface` fails (-25205,
   -25208). The app now runs on a "Codex Framework" (Chromium 152 and 153) rather than plain
   Electron. So Vignette logs `came from the Codex app, open thread unread` and falls back to the
   Codex thread used last. With the app showing an older thread, Send aimed at a different one.
2. **Vignette never finds the CLI inside the Codex app.** `CodexConnection.binaryPaths` and
   `PluginHost.paths(for:)` do not include
   `/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex`. Someone with the Codex app and
   no separate CLI gets no Codex destinations and cannot install the plugin for Codex. On this Mac,
   Vignette uses the older CLI on the PATH.
3. **A thread that is gone reads as a generic failure.** For an unknown thread id, `codex queue`
   exits 1 with `no rollout found for thread id <id>`. `CodexConnection.failure` matches "thread not
   found", "no such thread", "session not found" and "unknown thread", so it answers
   `notSubmitted` with Codex's raw text, not `destinationChanged` with "This thread is gone. Send to
   another one."
4. **"Sent" can mean "waiting".** When no engine holds the thread, `codex queue` still exits 0
   (`Queued message <id> for thread <id>`). Nothing runs until someone opens or resumes the thread.
   The waiting message then runs first, so nothing is lost. But the card says Sent while the
   session is closed.
5. **The CLI on the PATH cannot run this Mac's model.** `~/.codex/config.toml` names `gpt-6.1-sol`,
   and CLI 0.154.0 refuses it with a ChatGPT account (400). The app's CLI runs it. This is the Mac's
   setup rather than Vignette's, but a CLI session started from the PATH fails its first turn here.

Two smaller observations:

- An editor opened from the Codex app waits for the open-thread read, which now answers nothing:
  `open thread unread after=281ms` without Accessibility and `491ms` with it. `openThread` returns
  at once when untrusted, so the 281 ms is spent elsewhere in that path; it was not traced.
- A drawing is keyed by the path as given, so `file=/private/tmp/x.png` and `file=/tmp/x.png`
  reach different drawings of one file. Captures always arrive by the watch folder's own spelling,
  so only a script meets this.

`codex exec` threads are not listed. `thread/list` with no `sourceKinds` returns interactive
sources only (`cli`, `vscode`). That is right for Send, since an `exec` run is not a session a
person sends to.

## Not tested

- The card for a send to a thread deleted after the bar picked it. `codex delete` refuses a thread
  the Codex app holds, so the case could not be set up. The wording it would show is item 3.
- Sending while the Codex app is not running. That needed quitting your app.

## Left behind

The Codex app's test thread, "Reply ready" in the project `vignette-codex-test`, could not be deleted
or archived from the CLI while the app holds it. Delete it in the app. The other test threads,
the scratch folders and the test copy's files under the home folder are removed.
