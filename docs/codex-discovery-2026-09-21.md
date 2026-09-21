# Discovering Codex sessions (2026-09-21)

Claude Code sessions fill the Send menu by themselves, because herdr reports every pane's session
id. Codex sessions had to be typed into `settings.json`. This is what it took to make them
discoverable, and what still has to be true for it to work.

## What the app-server already offers

`codex app-server generate-json-schema --out <dir>` prints the protocol, and it has exactly the two
calls this needs:

- `thread/list` returns `Thread` objects: `id`, `name`, `cwd`, `status`, `model`, `originator`,
  `recencyAt`. `cwd` is the project the menu groups by, and `name` is the session's own title.
- `thread/loaded/list` returns *"thread ids for sessions currently loaded in memory"*.

`ThreadStatus` is `notLoaded`, `idle`, `active` (with flags), or `systemError`. Loaded is per
server: a server started fresh reports every thread `notLoaded`, because it has just started and
holds none of them. Only the server that owns a session can say it is live.

## The transport, and why it is a socket

`codex app-server proxy --sock <path>` proxies stdio to a running app-server's control socket, at
`~/.codex/app-server-control/app-server-control.sock`. That is one subprocess speaking newline
JSON-RPC, which is the same shape as the herdr calls the Claude route already makes, so discovery
did not need a new kind of machinery.

The handshake is `initialize` (with `clientInfo`), the `initialized` notification, then the call.
Standard input has to stay open until the answers are in: a batch written with the pipe already
closed is answered only as far as `initialize`, because the server exits on EOF. Measured, that
batch came back in 0.1 s with one answer and no listing.

`thread/list` costs, on this Mac, through the proxy:

| `limit` | time | threads |
| --- | --- | --- |
| 5 | 0.12 s | 5 |
| 15 | 0.50 s | 15 |
| 30 | 2.89 s | 30 |
| 50 | 3.05 s | 50 |

It runs every time an image opens, so `AppServer.listLimit` is 15. The cost is not linear and a
menu of fifty is not one a person reads.

## What is running on this Mac, and what is not

- The ChatGPT desktop app runs its own `codex app-server`. Its standard input and output are
  socketpairs to the app itself; it listens on nothing. It is private to that app by construction,
  and it is the process that holds the live threads.
- `~/.codex/app-server-control/app-server-control.sock` does not exist. `codex app-server daemon
  start` still refuses: no managed standalone install at `~/.codex/packages/standalone/current`.
- `~/.codex/ipc/ipc.sock` is live and held by ChatGPT.app, but it is that app's own IPC, not the
  app-server protocol.
- Disk is not a substitute. `~/.codex/sessions` holds two entries; thread history moved to
  paginated storage, and `thread-writer-locks/<uuid>.lock` says a thread existed, not that it lives.

So discovery finds nothing here until a daemon is running. That is why the configured entries stay:
they are the answer when there is no server, and Vignette starts nothing to change that.

## What was verified

A disposable control socket was stood up: a unix socket relaying to a `codex app-server` started
for the test, which is what a daemon's control socket does. `~/.codex/app-server-control` was
symlinked to it for the length of the run and removed afterwards, along with the socket, the
server, and the scratch settings. The ChatGPT app's own server was not touched.

- Through `codex app-server proxy --sock`, the three request lines came back answered in 0.77 s
  with 15 threads carrying name, cwd, and status.
- The app, launched on scratch settings, showed those sessions in the Send menu grouped by their
  own projects: `loop-test` and `pdk-ui` appeared, which no Claude Code pane is in, and
  `loop-test` held one row, `Open drawing`, which is the Codex thread's own name.

## What is still unproven

Sending. `codex queue --thread <uuid> --remote unix://<socket>` is the documented way to reach a
thread through a named endpoint, and the address discovery writes is exactly that. It was not
exercised against a discovered thread here, because no daemon owns one on this Mac. The earlier
caveat therefore still stands: reaching an ordinary Codex session, rather than one on a server
started for a test, has not been shown.
