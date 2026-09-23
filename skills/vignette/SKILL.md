---
name: vignette
description: Show the user an image through Vignette, the screenshot tool on this Mac, and read back what they drew on it. Use when you want the user to see a screenshot or rendering you produced (a browser capture, screencapture, a before-and-after), when they ask to see what something looks like, or when you need their circled answer. Not for images the user captured themselves; Vignette already shows those.
---

# Vignette

Vignette watches the user's screenshots folder, shows each new image as a thumbnail in the
corner, keeps the recent ones in a stack, and lets the user draw on one and press Return. Every
command is a `vignette://` URL. Each one answers with one line in `~/Library/Logs/Vignette.log`:
`[<command>] ok <detail>` or `[<command>] error <code> <detail>`.

## Show the user an image

```sh
path=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "/abs/path/Checkout at 390px.png")
open -g "vignette://add?file=$path&agent=claude"
```

- `add` copies the file into the watch folder and shows its thumbnail. It leaves the clipboard
  alone and does not open the editor, whatever the user's capture settings say. Add `&annotate`
  to open the editor instead, only when you are asking for marks right away.
- `&agent=<name>` says who pushed it. The card gets a tab naming you.
- `open -g` keeps the focus where it is. Always percent-encode the path yourself; `open` will not.
- The file may be anywhere. Every other command takes files inside the watch folder only.
- Wait for `[add] ok <name>` in the log. The name gains a counter (`x 2.png`) when one is taken.
  Errors end with `missing-file`, `unreadable-image`, `unsupported-type` (png, jpg, jpeg, or heic
  only, and never a `-annotated` name), `write-failed`, or `invalid-marks`.
- Push what the user should see, not every image you make. Name the file for them: what it shows,
  at what size or state.

## Draw on it yourself

`&marks=` takes the path to a JSON file, or the JSON itself. The marks join the image's drawing
before the card appears, so the card shows them and the user edits them like their own. Every
number is a fraction of the image: `x`,`y` is a shape's top-left corner or an arrow's tail, `w`,`h`
its size, `x2`,`y2` an arrow's head.

```json
[{"type": "ellipse", "x": 0.12, "y": 0.30, "w": 0.20, "h": 0.10},
 {"type": "arrow", "x": 0.50, "y": 0.50, "x2": 0.70, "y2": 0.60},
 {"type": "text", "x": 0.10, "y": 0.80, "w": 0.50, "text": "This header should not scroll"}]
```

- Types: `ellipse`, `rectangle`, `arrow`, `text`. At most 100 marks and 256 KB.
- Every mark is moved inside the image. A mark with nothing inside it is dropped, with a
  `[marks] dropped` line.
- A text mark's `w` is the box its words wrap in, and it is optional: the default is the room
  between `x` and the right edge. Write the sentence you mean; it is sized for the image, wrapped,
  widened until the words fit the image's height, and moved inside it.
- A sentence too long to fit even across the whole picture **is cut off at the edge**, and `[add]`
  still answers `ok`. The log says which one: `[marks] text too long for <name>: mark N is cut off
  at its edge`. Short marks on a wide image are the safe case; a paragraph on a short one is
  not. Keep a pushed text to a sentence, and check the log if it mattered.
- A mark with no `color` is coloured from the pixels it covers. To choose: `red`, `yellow`,
  `light-blue`, `white`, `violet`.
- `[add] ok <name> … marks=<n>` says they landed. `invalid-marks` names the mark and the field.

## When the user sends you a drawing

The user can hand you a drawing from Vignette's editor. It arrives in your session as one line:

```text
Vignette request <id>: open the drawing at "<path>" and do what it asks. To answer with a drawing
of your own, run: python3 "<helper>" --ticket "<ticket>" --marks <marks.json>; …
```

Open that image and answer what it asks. When the answer is easier to show than to say, reply with
a drawing: the helper puts your marks on a new card beside the user's other screenshots. They edit
those marks like their own and can send the result straight back to you.

```sh
cat > /tmp/reply.json <<'JSON'
[{"type": "arrow", "x": 0.50, "y": 0.90, "x2": 0.44, "y2": 0.62},
 {"type": "text",  "x": 0.20, "y": 0.92, "text": "this column is the one that overflows"}]
JSON
python3 "<helper>" --ticket "<ticket>" --marks /tmp/reply.json
```

- The marks are the same format as `&marks=` above, with the same limits.
- `--image <your.png>` puts them on a picture of your own instead of the one you were sent.
- It prints one JSON line and exits **0** accepted, **2** refused, **3** unconfirmed. Accepted means
  Vignette has your reply and will keep it, not that the card is on screen yet.
- **Unconfirmed means do not send a new reply.** Vignette never answered, so your reply may or may
  not have arrived. Retry the exact one, which can never make a second card:
  `python3 "<helper>" --ticket "<ticket>" --retry <the bundle path it printed>`.
- Only the ticket you were given authorizes a reply, and only to that one request. A request the
  user has cleared refuses new replies (`request-closed`).
- Answer in words in your own session as usual. The reply carries only the drawing.

## Read back what they drew

The user draws and presses Return. Vignette writes `<name>-annotated.png` beside the copy in the
watch folder when the rendering finishes, a moment later, and then logs
`[annotate] done <name>-annotated.png <bytes> bytes, copied`. Read that file once the line is
there. If the user drew nothing, no file is written and the line is
`[annotate] done <name> nothing drawn, original copied`. The folder is `screenshotsFolder` in
`~/.config/vignette/settings.json`.

Nothing arrives if the user ignores the thumbnail, so do not block on it. Ask for the drawing when
you need it, then carry on and look for the file.

## Is Vignette running, and does it have `add`

`open -g vignette://help` logs one `[help]` line per command and one `[help] ok` line; nothing
within a second means it is not running. If the list has no `add`, the app is older than this
skill: write your file straight into `screenshotsFolder`, which any version shows as a capture.

`open -g "vignette://state?tag=<id>"` logs one `[state] {json}` line carrying your tag, with the
watch folder, the stack, and what is in the editor.
