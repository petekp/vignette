# `show` points an agent at screenshots already in the folder, and `add` refuses the person's own

Status: accepted, 2026-11-25, and partly superseded by ADR 0033 (2026-11-26): `show` now joins its
marks and pins to the drawing at once, and Keep and Clear are gone. Built: `AppDelegate+Show.swift`, `ThumbnailController+Show.swift`,
`Shown.swift` and the refusal in `FolderWrites.add`. `docs/agent-single-out-api-2026-11-25.md` is
the spec, with Pete's answers to its open choices.

An agent needed a way to point the person at screenshots they already have. The only command that
could bring one to the corner was `add`. Given a file inside the screenshots folder, `add`
relabels it: it records the agent on it, drops its Sent record and its title, and drops the
fingerprint Reply uses. That turned the person's own capture into "From Claude".

## The new command

`vignette://show?file=<path>[&file=…]&agent=<name>&session=<id>&message=<text>&marks=<json>&pins=<json>&tag=<tag>`
is a new URL command, and its names are a contract scripts rely on:

- the parameters above, with `message=` read as a form encodes it, at most 60 characters, and
  `marks=` and `pins=` in `add`'s format;
- the answer `[show] ok files=[…] agent= session= joined= inColumn= inEditor= marks= [pins=] after=<ms> tag=`,
  or `[show] error <code> …` with the codes the actions use and one new one, `too-many-files`;
- the lines `[show] waits for <reason>`, `[show] warning …`, `[show] ended <name> by=left|opened|replaced`,
  `[show] kept marks=<n> [pins=<n>] <name>` and `[show] cleared marks=<n> [pins=<n>] <name>`;
- in `[state]`, each card's `shown` and `agentMarks`, and the stack's `showsWaiting` and `dimsUnshown`.

`show` writes nothing. What it sets, the shown state and the agent's marks and pins, lives in
memory, with the marks and new pins drawn on top. They reach the drawing file only when the person presses Keep, and then through `add`'s own
path, as one undo step. The new pins take their numbers then, so a pin the person made meanwhile
does not share one. An answer on a pin goes in with them, and one whose pin is gone by then is left
out with a `[pins] dropped` line. A `pins=` list that names a pin the screenshot does not hold, or
more new pins than it has room for, answers `invalid-pins` and shows nothing.

## The change to `add`

`add` answers `unsupported-type` for a file inside the folder that has no agent attribute, and the
error names `show`. A file an agent pushed carries the attribute, so an agent can still push its
own image again, with new marks or a new title.

## What was weighed

- A flag on `add` that skips the relabel. It would give one command two meanings, decided by where
  the file is, and the relabel stays one wrong call away.
- An action in `Config.actions`. An action receives only the screenshots, so it cannot read
  `agent=`, `session=` or `message=`, and it belongs to a place in the strip or under a key.
- Folding `show` into `last` with files. That changes a working contract for no one's gain.
- Leaving `add` as it was. The refusal breaks a script that pushed the person's capture through
  `add`. That use was the defect: it rewrote a file the person owns.

Reversing this means removing a URL command agents call and letting `add` relabel captures again.
