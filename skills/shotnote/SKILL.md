---
name: shotnote
description: Show the user an image through Shotnote, the screenshot tool on this Mac, and read back what they drew on it. Use when you want the user to see a screenshot or rendering you produced (a browser capture, screencapture, a before-and-after), when they ask to see what something looks like, or when you need their circled answer. Not for images the user captured themselves; Shotnote already shows those.
---

# Shotnote

Shotnote watches the user's screenshots folder, shows each new image as a thumbnail in the
corner, keeps the recent ones in a stack, and lets the user draw on one and press Return. Every
command is a `shotnote://` URL. Each one answers with one line in `~/Library/Logs/Shotnote.log`:
`[<command>] ok <detail>` or `[<command>] error <code> <detail>`.

## Show the user an image

```sh
path=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "/abs/path/Checkout at 390px.png")
open -g "shotnote://add?file=$path&agent=claude"
```

- `add` copies the file into the watch folder and shows its thumbnail. It leaves the clipboard
  alone and does not open the editor, whatever the user's capture settings say. Add `&annotate`
  to open the editor instead, only when you are asking for marks right away.
- `&agent=<name>` says who pushed it. The card gets a badge naming you.
- `open -g` keeps the focus where it is. Always percent-encode the path; `open` does not.
- The file may be anywhere. Every other command takes files inside the watch folder only.
- Wait for `[add] ok <name>` in the log. The name gains a counter (`x 2.png`) when one is taken.
  Errors end with `missing-file`, `unreadable-image`, `unsupported-type` (png, jpg, jpeg, or heic
  only, and never a `-annotated` name), `write-failed`, `invalid-marks`, or `page-not-ready`.
- Push what the user should see, not every image you make. Name the file for them: what it shows,
  at what size or state.

## Draw on it yourself

`&marks=` takes the path to a JSON file, or the JSON itself. The marks become a draft before the
card appears, so the card shows them and the user edits them like their own. Every number is a
fraction of the image: `x`,`y` is a shape's top-left corner or an arrow's tail, `w`,`h` its size,
`x2`,`y2` an arrow's head.

```json
[{"type": "ellipse", "x": 0.12, "y": 0.30, "w": 0.20, "h": 0.10},
 {"type": "arrow", "x": 0.50, "y": 0.50, "x2": 0.70, "y2": 0.60},
 {"type": "text", "x": 0.10, "y": 0.80, "text": "This header should not scroll"}]
```

- Types: `ellipse`, `rectangle`, `arrow`, `text`. At most 100 marks and 256 KB.
- A mark with no `color` is coloured from the pixels it covers. To choose: `red`, `yellow`,
  `light-blue`, `white`, `violet`.
- `[add] ok <name> … marks=<n>` says they landed. `invalid-marks` names the mark and the field.
- `page-not-ready` means the editor is busy with the user's own image. Wait and send it again.

## Read back what they drew

The user draws and presses Return. Shotnote writes `<name>-annotated.png` beside the copy in the
watch folder and logs `[annotate] done <name>-annotated.png …`. Read that file. The folder is
`screenshotsFolder` in `~/.config/shotnote/settings.json`.

Nothing arrives if the user ignores the thumbnail, so do not block on it. Ask for the drawing when
you need it, then carry on and look for the file.

## Is Shotnote running, and does it have `add`

`open -g shotnote://help` logs one `[help]` line per command and one `[help] ok` line; nothing
within a second means it is not running. If the list has no `add`, the app is older than this
skill: write your file straight into `screenshotsFolder`, which any version shows as a capture.

`open -g "shotnote://state?tag=<id>"` logs one `[state] {json}` line carrying your tag, with the
watch folder, the stack, and what is in the editor.
