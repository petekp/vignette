# Codex issues

This file tracks every known problem between Vignette and Codex, the CLI and the Codex desktop app
(`/Applications/ChatGPT.app`, bundle id `com.openai.codex`), until each is fixed and verified. Each
issue has a status, what happens, the cause, the fix, and how it is verified. The progress log at
the end records what was done, newest first.

The live test that found these is `docs/codex-live-test-2026-10-01.md`. The end-to-end tests fake
Codex with `scripts/e2e/fake_codex.py`. A fix is verified against the real CLI and the real app,
and gets an end-to-end scenario wherever the fake can show it.

## Status

| ID | Issue | Severity | Status |
| --- | --- | --- | --- |
| C1 | Send no longer starts on the thread the Codex app shows | High | Fixed and verified live |
| C2 | Vignette never finds the CLI inside the Codex app | High | Fixed and verified live |
| C3 | A thread that is gone reads as a generic failure | Medium | Fixed; verified with the fake codex |
| C4 | "Sent" can mean the message is only waiting | Medium | Fixed; Sent verified live, Queued with the fake codex |
| C5 | Opening the editor from the Codex app waits 0.3 to 0.5 s for nothing | Low | Fixed with C1: 9 to 20 ms |
| C6 | Two spellings of one path reach two drawings | Low | Fixed |
| X1 | The CLI on this Mac's PATH cannot run the configured model | Not Vignette's | Noted |

Still untested:

| ID | Case | Why it is untested |
| --- | --- | --- |
| U1 | The card for a send to a thread deleted after the bar picked it | The real app refuses to delete a thread it holds; `send_codex_thread_gone` covers it with the fake |
| U2 | Sending while the Codex app is not running | It needs the app quit |

## How Codex works, as of CLI 0.159.2 and app 26.928

These facts decide the fixes. Each was read in the Codex source at tag `rust-v0.159.2` or checked
on this Mac on 2026-10-01.

- **The app's engine is private.** The Codex app runs `codex app-server` as a child process over
  standard input and output. It listens on no socket and no port, so nothing outside the app can
  ask it anything.
- **`codex queue` writes to a shared queue, not to an engine.** It sends `thread/queue/add` to a
  server of its own, which stores the message in `~/.codex/queue_1.sqlite`. Every engine checks that
  queue every 10 s and when it loads a thread, and starts a turn for any thread it has loaded and
  that is idle. A thread no engine has loaded keeps its message until someone opens it. Codex's
  maintainers call that intended (openai/codex#44491). The command prints the same line and exits
  0 either way.
- **An engine locks each thread it has loaded.** It holds an exclusive `flock` on
  `~/.codex/thread-writer-locks/<thread id>.lock` while it has the thread and deletes the file when it
  lets go (`codex-rs/rollout/src/writer_lock.rs`). On this Mac the app's engine held exactly the
  four lock files there.
- **Nothing in the protocol says which thread a window shows.** The app-server protocol has no
  focus or visible-thread concept, and no notification for the app moving between threads.
- **The app's accessibility tree is empty.** Since it left Electron the app shows one window with
  12 empty groups, and refuses `AXManualAccessibility` and `AXEnhancedUserInterface`. VoiceOver does
  not change that. The issue is openai/codex#25740, open since 2026-06-02 with no reply.
- **The app's log names each page its window moves to.** The main process logs
  `received browser sidebar owner sync … ownerRoutePath=<route>` on every page change, in
  `~/Library/Logs/com.openai.codex/<year>/<month>/<day>/codex-desktop-<run>-<pid>-<part>.log`, with
  the day in UTC. A Codex thread on this Mac is `/local/<id>`. Other routes are the home page (`/`),
  a new thread not sent yet (`/local/client-new-thread:<id>`), a ChatGPT chat (`/c/<id>`) and a
  "dot" page (`/dots/<id>`), whose id the thread store does not have. The app has logged the line
  since at least 2026-09-18, the oldest log on this Mac, before and after the move off Electron.
- **`thread/read` finds a thread by id whatever its age.** It answers for a thread no engine has
  loaded, with `status: notLoaded`, and refuses an id the store does not have.

## What changed in Codex plugins, and what Vignette takes from it

Vignette's Codex plugin carries the skill and nothing else. Codex plugins can now also carry
hooks (`SessionStart`, `UserPromptSubmit`, `Stop` and others, run after the person trusts them), MCP
servers and app connectors, and one plugin directory serves ChatGPT and Codex
(developers.openai.com/codex/plugins/build). The app also gives its own agents an MCP server,
`codex_app`, with tools such as `list_threads` and `send_message_to_thread`. It is for agents inside
the app, undocumented for other apps, and has broken between builds (openai/codex#49676).

None of that is needed now. A hook could tell Vignette which thread the person last typed in,
which the thread list's `recencyAt` already says. It cannot tell which thread a window shows, and
the lock files already say which threads are loaded. A hook becomes worth adding if the app's log
stops naming its pages: "the thread you last typed in" is then the best signal left.

## Issues

### C1: Send no longer starts on the thread the Codex app shows

**What happens.** When the Codex app was in front before Vignette, Send should start on the thread
the app shows. It started on the Codex thread used last, because the app's accessibility tree no
longer has the page whose title Vignette read.

**Fix.** Vignette reads the thread from the app's log instead (`AgentApp.shownThread`). It takes the
log files of the app's own process, newest first, back to the day the process started, finds the
last page-change line, and keeps a `/local/<id>` route. Discovery then reads that thread by id
(`thread/read`), so a thread older than the five used last is still offered. A route that is not a
thread on this Mac, or a log with no such line, gives the thread used last. This replaces the
Accessibility read and the title search (`AppServer.searchTerms`, `AgentDestination.isNamed`),
which are deleted. The read took 2.7 ms on this Mac's real log.

**The risk.** The log is the app's own, not an interface. Codex can rename or drop
the line in any build, and the field is marked sensitive in the app's code, so a build could strip
it. The fallback is the behaviour before the fix. No other source exists: the protocol has no focus
concept, the app's engine is private, and the app's IPC socket carries whole conversations to its
clients.

**Verified live.** With the app brought forward on a thread by `codex://threads/<id>`, the editor
opened over it logged `[send] came from the Codex app, showing <id>` and Send's target was that
thread. A thread from 2026-09-18, older than the five used last, was found by its read and became
the target when the fresh list arrived, 216 ms after the editor asked. A route the store does not
have (`/dots/<id>`) gave no thread, so the target was the thread used last.

### C2: Vignette never finds the CLI inside the Codex app

**What happens.** Vignette looked for `codex` in the installers' folders, the version managers'
folders and the login shell's `PATH`, never inside the app. Someone with the app and no separate
CLI got no Codex destinations and could not install the plugin for Codex.

**Fix.** `AgentApp.codexCLI` finds the app by its bundle id wherever it is installed, and its CLI
(`Contents/Resources/codex-cli/bin/codex`) comes first in `CodexConnection.binaryPaths`, which the
plugin installer shares. It comes first because the app updates it with itself, so it matches the
engine that holds the app's threads. A CLI installed on its own falls behind: 0.154.0 beside the
app's 0.159.2 on this Mac. The lookup costs 0.1 ms after the first, which was 43 ms.

**Verified live.** On this Mac the lookup answers the app's CLI, and `install-skill` in a test launch
installed the plugin into a scratch Codex folder with it.

### C3: A thread that is gone reads as a generic failure

**What happens.** For a thread that no longer exists, `codex queue` exits 1 and prints `Error:
failed to queue session message: thread/queue/add failed: failed to read thread: invalid
thread-store request: no rollout found for thread id <id> (code -32603)`. Vignette did not
recognise it, so the card quoted Codex's words.

**Fix.** `CodexConnection.failure` recognises `no rollout found`, and the card says "Codex can't
find this thread. You can send it to another one." The unit test uses the text above, captured from 0.159.2. The fake
codex fails a queue to any thread listed in its `gone` file, and `send_codex_thread_gone` sends to
one.

**Verified.** `send_codex_thread_gone` passes, and its card says "Not sent" and the reason. The real
app refuses to delete a thread it holds, so the live case is U1.

### C4: "Sent" can mean the message is only waiting

**What happens.** A send to a thread no engine has loaded is stored and read by nobody until the
thread is opened, and the card said "Sent".

**Fix.** After `codex queue` answers, Vignette looks for the thread's lock file
(`CodexConnection.isLoaded`). Without one the outcome is `queued`, and the card says "Queued for
<project>" with a clock and "Codex reads it when you open this thread." It holds as a failure does,
and comes back as the lone thumbnail when its card has left the screen, since the person has
something to do. A lock file a crashed engine left behind reads as loaded, which is how every send
read before. The fake codex writes the lock for its thread unless told not to, and
`send_codex_queued` sends to a thread without one.

**Verified.** `send_codex_queued` passes, and its card shows the clock and the reason. A live send to
the test thread, which the app held, logged `[send] ok`; the app took it from the queue and ran the
turn within 15 s.

### C5: Opening the editor from the Codex app waits for nothing

**What happens.** Opened with the Codex app in front, the editor waited 281 ms without Accessibility
and 491 ms with it before the target could settle. The Accessibility read that caused at least the
second is gone with C1. The first was never traced.

**Fixed with C1.** The log read takes about 3 ms. In the live run the target was set 9 to 20 ms after
the editor asked. The first editor after a launch took 138 ms, because the main thread was busy
opening the editor for the first time, not because of this read.

### C6: Two spellings of one path reach two drawings

**What happens.** A drawing is keyed by the path. `file=/private/tmp/x.png` and `file=/tmp/x.png`
named one file and reached two drawings.

**Fix.** A `file=` inside the watch folder is taken by the folder's own spelling
(`Commands.inWatchFolder`), which is how every capture arrives. A file outside the folder is left as
given. `CommandsTests` covers a link to the folder.

### X1: The CLI on this Mac's PATH cannot run the configured model

**What happens.** `~/.codex/config.toml` names `gpt-6.1-sol`. CLI 0.154.0 refuses it with a ChatGPT
account (400), and the app's CLI runs it. Vignette's own calls (`app-server`, `queue`, `plugin`) run
no model, and since C2 Vignette uses the app's CLI. A CLI session started from the PATH fails its
first turn. Updating that CLI is the fix, and it is outside Vignette.

## Progress log

### 2026-10-01, night

- Ran the end-to-end suite with input: 18 scenarios, 90 checks, all passing, including
  `send_and_reply_codex`, `send_codex_thread_gone` and `send_codex_queued`. The queued card's clock
  was drawn white on its white ring; it is orange now.
- Ran the live checks against ChatGPT.app (C1, C2, C4, C5), above. The test thread "Reply ready"
  took one more message and answered it.
- Softened every send, reply and copy message, and recorded them with the rules they follow in
  `docs/voice.md`. Pete asked for words that are clear, short and humble, with a deep underlying
  optimism.

### 2026-10-01, evening

- Researched with three agents: the Codex source at 0.159.2, ChatGPT.app's files and processes on
  this Mac, and what changed in Codex and its plugins. The findings are under "How Codex works" and
  "What changed in Codex plugins".
- Fixed C2, C3, C4 and C6, and C1 in code. Unit tests pass. The end-to-end run without input
  passed, 48 checks.
- Added the end-to-end scenarios `send_codex_thread_gone` and `send_codex_queued`. Both post keys
  and have not run.
- Waiting on Pete for three things. The first is approval to depend on the Codex app's log for C1.
  The second is a live run of about three minutes that brings the Codex app forward, opens the
  editor over it and sends one message to the test thread "Reply ready". The third is the `--input`
  end-to-end run.

### 2026-10-01

- Tested Vignette live against the real CLI and the Codex app, and found C1 to C6 and X1
  (`docs/codex-live-test-2026-10-01.md`). The whole loop works with a CLI session and with the app:
  a drawing sent from Vignette reached the session, and its reply came back as a card.
- Added a fake codex to the end-to-end tests, and the scenarios `send_target_codex` and
  `send_and_reply_codex`. `send_and_reply_codex` posts keys and has not run yet.
