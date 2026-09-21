# Discovering Codex sessions (2026-09-21)

Claude Code sessions fill the Send menu by themselves, because herdr reports every pane's session
id. Codex sessions had to be typed into `settings.json`. This is what it took to make them
discoverable, and what is now proven about it.

## What the app-server already offers

`codex app-server generate-json-schema --out <dir>` prints the protocol. `thread/list` returns
`Thread` objects: `id`, `name`, `cwd`, `status`, `model`, `originator`, `recencyAt`. `cwd` is the
project the menu groups by, and `name` is the session's own title. That is the whole of discovery.

`thread/list` reads the thread store on disk, so **any** app-server can answer it, including one
Vignette starts for the length of one listing. That is the fact the design rests on: Vignette does
not have to reach the process that owns a session in order to list it.

`ThreadStatus` is `notLoaded`, `idle`, `active` (with flags), or `systemError`, and it is per
server: a server started fresh reports every thread `notLoaded`, because it has just started and
holds none of them. So the status says nothing useful about a session another process owns, and
discovery does not read it beyond keeping the thread.

## The transport

One child process speaking newline JSON-RPC over stdio, which is the same shape as the herdr calls
the Claude route already makes. `AppServer.converse` writes the requests, reads until every request
carrying an id has been answered, and ends the process.

`codex app-server` on its own is the ordinary case. `codex app-server proxy --sock <path>` is used
instead when `~/.codex/app-server-control/app-server-control.sock` exists, which is a server already
running: asking it is cheaper than starting another. Nothing else differs between the two.

The handshake is `initialize` (with `clientInfo`), the `initialized` notification, then the call.
Standard input has to stay open until the answers are in: a batch written with the pipe already
closed is answered only as far as `initialize`, because the server exits on EOF.

`thread/list` costs, on this Mac:

| `limit` | time | threads |
| --- | --- | --- |
| 5 | 0.12 s | 5 |
| 15 | 0.50 s | 15 |
| 30 | 2.89 s | 30 |
| 50 | 3.05 s | 50 |

It runs every time an image opens, so `AppServer.listLimit` is 15. The cost is not linear and a menu
of fifty is not one a person reads. A spawned server measured 0.42–0.74 s for the whole
conversation, handshake included.

## Sending needs no endpoint either

`codex queue --thread <uuid>` finds the engine that owns the thread by itself. It was run with no
`--remote` against a Codex Desktop thread, and the message arrived in that session (confirmed by
the person reading it). The desktop app's own app-server listens on nothing, so this is the case an
endpoint could never have covered.

`endpoint` therefore stays a setting rather than something discovery writes: it is for a server that
is not this Mac's. A discovered destination carries `endpoint: nil`.

## What was verified

On 2026-09-21, against the live store and a real Codex Desktop session:

- A freshly spawned `codex app-server`, with no control socket present and no daemon running, listed
  15 threads in 0.74 s with name, cwd, and status.
- The app, launched on scratch settings with `codexSessions: []`, showed those sessions in the Send
  menu grouped by project alongside the herdr panes. The `vignette` group held four rows: two Claude
  Code panes and two Codex threads, one of which was the desktop session `Handle greeting`.
- Choosing it stored and submitted the request:
  `[send] ok … Handle greeting thread=01a0c4a6-… ` with `guard: runtime-enforced` and no endpoint.

## What is still unproven

A Codex session drawing back. The request above sits submitted; completing it needs that desktop
session to run its turn and call the reply helper, which no test can make it do. The return leg
itself is the same code the Claude Code loop exercises end to end, and it is addressed by ticket
rather than by agent, so nothing about it is Codex-specific.
