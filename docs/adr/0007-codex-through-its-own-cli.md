# Codex is reached through its own command line tool, by thread UUID, on this Mac only

Vignette sends to Codex with `codex queue --thread <uuid>`, passing the image as a path. It lists
threads by starting a short-lived, read-only `codex app-server` of its own. Codex keeps its threads
on disk, so that server answers for every session, the Codex app's included. There are no
configured endpoints, no remote sessions and no long-running connection. A send to a thread that
no Codex engine has open is stored by Codex and reported as queued.

## Considered options

- Driving the app server directly, which takes image attachments but means more protocol to keep.
- Endpoints written by hand in settings, `--remote`, and a control socket. Removed once the local
  listing answered for every session, since nothing needed them after that.

Sources: `docs/codex-discovery-2026-09-21.md`, commit 5229766.
