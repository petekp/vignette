# The drawing file

How Vignette stores a screenshot's drawing. [The drawing editor](editor.md) says how the editor
makes and changes it.

One file per screenshot, at `~/Library/Application Support/<bundle id>/drawings/<id>.json`. The
`<id>` is a hash of the screenshot's path.

```json
{
  "version": 1,
  "key": "/Users/pete/Dropbox/Screenshots/Screenshot 2026-09-22 at 10.08.24 PM.png",
  "pixels": [3024, 1964],
  "pointScale": 2,
  "marks": [
    { "type": "rectangle", "x": 410, "y": 220, "w": 640, "h": 180 }
  ]
}
```

- `pixels` is the image's size when the drawing was made. A file whose `pixels` differ from the
  image's size, or whose `key` names another screenshot, does not fit the image. The image opens
  without it, with a log line, and the file stays on disk.
- `pointScale` is between 0.5 and 8.
- `markScale` is the drawing's mark scale, from 0.05 to 1, and is left out at 1. `pointScale`
  includes it, so `pointScale` divided by `markScale` is the display's px per screen pt.
- A mark's fields are the ones its type uses. `bend`, `via`, `wrap`, `agent` and `agentName` are
  left out at their defaults. A text's `size` is always written. A mark has no id and no colour in
  the file.
- `pins` holds the drawing's pins, in number order, and is left out when there are none. A pin has
  a random `id` in UUID form, which never changes, a `number` from 1, `x` and `y` in px, and
  `comments`, a list of at least one, oldest first. A point pin's `x` and `y` are its point. An
  area pin adds `w` and `h`, and its `x` and `y` are the area's top-left corner. It also adds
  `corner`, the corner its teardrop's tip sits on: `topLeft`, `topRight`, `bottomLeft` or
  `bottomRight`. A file without it reads as `topLeft`. A comment has
  `text`, at most 2,000 characters, and `agent` and `agentName` as a mark has them, left out for
  a person's. It also has `at`, when it was written, in ISO 8601 in UTC to the second, such as
  `2026-11-25T18:04:05Z`. An edit gives it a new `at`. A comment without `at`, as every one written
  before times were kept, or with one that does not read, has no time and is kept. An agent's
  comment also has `session`, the id of the agent session that wrote it: a Claude Code session id
  or a Codex thread id, a UUID in lower case. Its client is the one `agentName` names, `claude` or
  `codex` in any case, and a `session` beside any other `agentName` is not read. `sessionName` is
  that session's name as the person knows it, its Herdr tab's label or its own name, one line of
  at most 40 characters. Both are left out when unknown. A comment without them, as every one
  written before they were kept, or with a `session` that is not a UUID, reads without them and is
  kept. Neither raises the version. A file holds at most 99 pins.
- `pieceNumbers` is a stitch's: where each piece wears its number, as `[x, y, w, h]` in px, so a
  teardrop turns away from it. It is left out when there are none, and does not raise the version.
- `nextPin` is the number the next pin gets, and is left out at 1. It never goes down while the
  file exists, so a deleted pin's number is never given again. A write keeps the file's `nextPin`
  when it is higher than the drawing's.
- `message` is what was last typed in the editor's message field for the screenshot, as typed,
  and is left out when the field is empty. The screenshot opens in the editor with it. A file can
  hold a message and no marks or pins, and then has no drawing. A file without `message`, as every file
  written before it was kept, opens with an empty field.
- The host writes the file atomically whenever it receives the drawing: after the 300 ms pause, at
  park, and when the app quits. The message is written 300 ms after it last changed, beside the
  marks the file holds, and with the drawing at each of those writes.
- `history` is the editor's undo and redo steps for the screenshot ([undo and redo](editor-undo.md)), and is left out when there are none. The editor writes it with the drawing or the
  message, and agents' marks added while the screenshot is closed add one step to it. `undo` and `redo` are lists, oldest first. A step has a `name` and either the marks
  and pins it changed or the message's words `before` and `after`. Each changed mark is a `mark` number, with
  its `before` and `after` as an `index` in the marks and the `mark`; a step also lists the
  `selectionBefore` and `selectionAfter` as mark numbers. A step that changed pins lists them under
  `pins`, each by its `id` with its `before` and `after` as the file writes a pin, and leaves out
  `changes` when no mark changed. A mark's number is its index in `marks`,
  or from the count of `marks` on for a mark the drawing no longer holds.
- `basis` is a SHA-256 of the marks as stored and the message the history ends at, and of the pins
  and `nextPin` when there are pins or `nextPin` is over 1. When a file's drawing or message no
  longer match it, the screenshot opens without its history, with a log line.
  Every other writer, such as a reply's install or live ink, writes the file without one. A rename
  keeps it. At most 100 steps and about 256 KB, as written, are kept: the oldest undo steps go first, then the
  farthest redo steps. A file without `history`, as every file written before it was kept, opens
  with an empty history.
- `version` is 2 when the file holds pins, a `nextPin`, or a history step that changed pins, and
  1 otherwise, so a build from before pins still reads every file without them. A build from before
  pins leaves a version 2 file alone, as below.
- A file with no marks, no pins and no message is removed, with its history, whatever its
  `nextPin`.
- Builds from different worktrees share this folder. A file whose `version` is newer than the build
  knows is left alone: the image opens without it, and the build never writes over it.
- Everything read from a file is checked with the same validator as agents' marks. Numbers must be
  finite, types known, a text's `size` at most 1,000 pt, and a text at most 2,000 characters and
  100,000 bytes. A mark that fails is dropped, with a log line. A mark that no longer
  fits inside the image is moved in, with a log line. A pin is dropped, with a log line, when it
  fails, has no comment, repeats the `number` or the `id` of a pin before it, or comes after the
  99th. A pin outside the image is moved in, with a log line. A `nextPin` at or below a kept
  pin's number is raised past the highest. A file that does not parse is renamed to
  `<id>.json.invalid` at launch, with a log line. If a file stops parsing while the app runs, its
  image opens with no drawing and a log line says so. The file stays where it is until the next
  launch. Nothing in a drawing file can crash the app.
