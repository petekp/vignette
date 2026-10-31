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
- The host writes the file atomically whenever it receives the drawing: after the 300 ms pause, at
  park, and when the app quits.
- A drawing with no marks has no file.
- Builds from different worktrees share this folder. A file whose `version` is newer than the build
  knows is left alone: the image opens without it, and the build never writes over it.
- Everything read from a file is checked with the same validator as agents' marks. Numbers must be
  finite, types known, a text's `size` at most 1,000 pt, and a text at most 2,000 characters and
  100,000 bytes. A mark that fails is dropped, with a log line. A mark that no longer
  fits inside the image is moved in, with a log line. A file that does not parse is renamed to
  `<id>.json.invalid` at launch, with a log line. If a file stops parsing while the app runs, its
  image opens with no drawing and a log line says so. The file stays where it is until the next
  launch. Nothing in a drawing file can crash the app.
