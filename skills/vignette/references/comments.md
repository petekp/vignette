# Read a card's pins and comments

The `comments` command in SKILL.md reads one card's pins and comments back. It changes nothing.
Name one screenshot in the user's screenshots folder, percent-encoded as for `show`.

Wait for `[comments] ok <name> pins=<n> comments=<n> file=<path>` in the log. The path runs to the
end of the line. It is a JSON file Vignette wrote for this call and keeps for a day. Errors end
with `missing-file`, `outside-watch-folder`, `too-many-files` or `write-failed`.

The file holds:

- `file`: the card's path.
- `pins`: in number order. Each has its `id`, its `number` ("Pin 2"), and `x`, `y`, plus `w`, `h`
  and `corner` for an area, in the fractions `&pins=` takes.
- Each pin's `comments`, oldest first. Each has an `id`, `text`, and `writer`, `person` or `agent`.
  An edit keeps the `id` and makes the words the user's, so `writer` turns `person`. An agent's
  comment adds `agentName`, and `session` and `sessionName` when it named its session, so you can
  tell your comments from another session's.
  `at` is when it was written, in UTC. `sentIn` lists the ids of the user's sends that carried it.
- A pin's `resolved`, when its ask is done: `resolver` (`person` or `agent`), `agentName` for an
  agent's, and `at`. Vignette leaves resolved pins out of what the user sends you.
- `sends`: the card's sends that reached an agent session, or may have (`status` `uncertain`),
  oldest first. A send that failed, or that the user took back out of the session's queue, is left
  out. Each has its `id`, `at`, `status`, `to` (the session's title on the card), `agent`, `session`,
  and `message`, the words the user typed with it.
- `message`: the newest send's message, left out when it had none.

A comment with an empty `sentIn` has not reached any session yet. A comment written after the
send that carried it, by `at`, was edited since. To answer a pin, use its `number` or `id` in
`&pins=` on `show`, or in `--comments` on a reply.

When your answer finishes what a pin asked, resolve it: add `"resolve": true` to the answer in
`&pins=` (`{"pin": 2, "text": "Moved the date under the title", "resolve": true}`), or pass
`--resolve 2,5` on a reply, naming pins your `--comments` answer. The pin turns grey and stays
out of the user's next sends until they reopen it. Leave it off when you are unsure or ask a
question back. An answer without it reopens a resolved pin.
