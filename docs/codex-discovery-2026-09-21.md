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
holds none of them. So the status says nothing about a session another process owns, and discovery
drops it rather than storing a number that cannot mean anything.

## The transport

One child process speaking newline JSON-RPC over stdio, which is the same shape as the herdr calls
the Claude route already makes. `AppServer.converse` runs `codex app-server`, writes the requests,
reads until every request carrying an id has been answered, and ends the process.

`codex app-server proxy --sock <path>` would reach a server already running instead of starting
one, and was built and then removed: the socket it needs does not exist on this Mac, `codex
app-server daemon start` refuses to create one, and the two paths measured the same anyway (0.77 s
through a proxy stood up by hand, 0.42–0.74 s spawning). A branch that never runs is not a fallback.

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

It runs every time an image opens, so `AppServer.listLimit` was 15. It is 5 since 2026-09-25, and the
last list is kept between openings (`docs/send-and-reply-2026-09-24.md`). The cost is not linear and a menu
of fifty is not one a person reads. Those numbers were measured through a proxy; a spawned server
came back in 0.42–0.74 s for the whole conversation, handshake included.

## Finding the thread the Codex app shows (2026-09-25)

`thread/list` takes a `searchTerm`, "a substring filter for the extracted thread title". The
extracted title is the thread's name, or for a thread with none its whole first message as typed.
With `useStateDbOnly` a search takes about 2 ms.

The Codex app shows something else. Its rule, in its bundle, starts from the name, or else the
first message. From a message an IDE sent, it takes the part after "## My request for Codex:".
It renders that from markdown to plain text, joins whitespace to one space, and cuts it to 79
characters and "…" when it is longer than 80. Links keep their text, and tags,
divider lines and the marks that start a heading or a list item go. A tag whose name has an
underscore, such as `<environment_context>`, is not HTML to markdown, so it stays.

So the title as shown is a poor search term. Over the 144 threads on this Mac:

| Search terms | Threads found |
| --- | --- |
| The title as shown | 0 of the 97 cut with "…" |
| The title without "…" | 83 of 144 |
| The title and its first three words | 129 of 144 |
| The title and its two longest words | 144 of 144 |

`AppServer.searchTerms` sends the last, ten results each. `CodexConnection.name(of:)` follows the
app's rule, and its names equal the app's titles for all 144 threads. The app's titles were read from its
own catalog, `local_thread_catalog.display_title` in `~/.codex/sqlite/codex-dev.db`. Vignette
does not read that file, because it is the app's private store.

## Sending needs no endpoint either

`codex queue --thread <uuid>` finds the engine that owns the thread by itself. It was run with no
`--remote` against a Codex Desktop thread, and the message arrived in that session (confirmed by
the person reading it). The desktop app's own app-server listens on nothing, so this is the case an
endpoint could never have covered.

So a Codex destination is a thread UUID and nothing else. `endpoint`, `--remote`, and the
hand-written `codexSessions` they existed for are gone: discovery finds every session on the
machine, and a session on some other machine's server was never designed for or tested.

## What was verified

On 2026-09-21, against the live store and a real Codex Desktop session:

- A freshly spawned `codex app-server`, with no control socket present and no daemon running, listed
  15 threads in 0.74 s with name, cwd, and status.
- The app, launched on scratch settings with no Codex sessions configured, showed those sessions in
  the Send menu grouped by project alongside the herdr panes. The `vignette` group held four rows:
  two Claude Code panes and two Codex threads, one of which was the desktop session
  `Handle greeting`.
- Choosing it stored and submitted the request:
  `[send] ok … Handle greeting thread=01a0c4a6-…` with `guard: runtime-enforced`.

## What is still unproven

A Codex session drawing back. The request above sits submitted; completing it needs that desktop
session to run its turn and call the reply helper, which no test can make it do. The return leg
itself is the same code the Claude Code loop exercises end to end, and it is addressed by ticket
rather than by agent, so nothing about it is Codex-specific.
