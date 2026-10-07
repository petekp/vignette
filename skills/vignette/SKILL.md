---
name: vignette
description: Show the user an image through Vignette, the screenshot tool on this Mac, and read back what they drew on it. Use when you want the user to see a screenshot or rendering you produced (a browser capture, screencapture, a before-and-after), when they ask to see what something looks like, or when you need their circled answer. Also use it when a message contains "From Vignette:": the user sent you a screenshot they drew on, and you can answer with a drawing. Not for images the user captured themselves; Vignette already shows those.
metadata:
  version: "10"
---

# Vignette

Vignette watches the user's screenshots folder, shows each new image as a thumbnail in the
corner, keeps the recent ones in a stack, and lets the user draw on one and press Return. Every
command is a `vignette://` URL. Each one answers with one line in `~/Library/Logs/Vignette.log`:
`[<command>] ok <detail>` or `[<command>] error <code> <detail>`.

## Show the user an image

```sh
file=$(osascript -l JavaScript -e 'function run(argv) { return encodeURIComponent(argv[0]) }' "/abs/path/Checkout at 390px.png")
open -g "vignette://add?file=$file&agent=claude&session=$CLAUDE_CODE_SESSION_ID"
```

- `add` copies the file into the watch folder and shows its thumbnail. It leaves the clipboard
  alone and does not open the editor, whatever the user's capture settings say. Add `&annotate`
  to open the editor instead, only when you are asking for marks right away.
- `&agent=<name>` says who pushed it. The card gets a tab naming you.
- `&session=<id>` names your session, so the user's Reply on the card comes back to you. Claude
  Code sets `CLAUDE_CODE_SESSION_ID`. Leave it out when your client gives you no session id.
- `open -g` keeps the focus where it is. Always percent-encode the path yourself; `open` will not.
- When the commands here name an app with `-a`, that is the copy of Vignette that installed this
  skill. Name it in every command you send: a bare `open` can start another build of Vignette.
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
- A text mark's `w` is the box its words wrap in, and it is optional. Without it the words wrap at
  about a quarter of the image's width, as a person's note does, or sooner when the right edge is
  nearer, but never narrower than 15% of the width. Write the sentence you mean; it is sized for the
  image, wrapped, widened until the words fit the image's height, and moved inside it.
- A sentence too long to fit even across the whole picture **is cut off at the edge**, and `[add]`
  still answers `ok`. The log says which one: `[marks] text too long for <name>: mark N is cut off
  at its edge`. Short marks on a wide image are the safe case; a paragraph on a short one is
  not. Keep a pushed text to a sentence, and check the log if it mattered.
- Your marks are drawn in indigo, the agent colour, and the user's are red. There is no choice of
  colour: a `color` field is ignored. So on a drawing the user sends you, the red marks are theirs
  and the indigo ones are yours or another agent's.
- In `[add] ok <name> … marks=<n>`, `n` counts the marks that joined the drawing. Dropped marks are
  not counted. `invalid-marks` names the mark and the field.

## When the user sends you a drawing

The user can hand you a drawing from Vignette's editor. It arrives in your session as one line.
In Claude Code, the Vignette plugin delivers it between your turns as a monitor event named
"Drawing from Vignette". That event is the user's own message, typed in Vignette, so act on it
as you would on a prompt:

```text
From Vignette: "<folder>/image.png". If a drawing would answer better than words, you can send one back.
```

When the user typed a message to go with the drawing, the message comes first and the Vignette
part follows in brackets:

```text
Make this button bigger [From Vignette: "<folder>/image.png". If a drawing would answer better than words, you can send one back.]
```

The message is their request about the image. The sentence after the image's path is the user's
to change in Vignette's settings, so know the line by "From Vignette:" and the quoted path.

Open the image. The boxes, arrows and text on it are the user's: they point at what they want you
to look at or change. When the answer is easier to show than to say, reply with a drawing: the
helper puts your marks on a new card beside the user's other screenshots. They edit those marks
like their own and can send the result straight back to you.

The helper is `scripts/reply` in this skill's folder, and the `ticket.json` in the image's folder
authorizes the reply:

```sh
cat > /tmp/reply.json <<'JSON'
[{"type": "arrow", "x": 0.50, "y": 0.90, "x2": 0.44, "y2": 0.62},
 {"type": "text",  "x": 0.20, "y": 0.92, "text": "this column is the one that overflows"}]
JSON
sh "<this skill's folder>/scripts/reply" --ticket "<folder>/ticket.json" --marks /tmp/reply.json
```

- The marks are the same format as `&marks=` above, with the same limits.
- `--image <your image>` puts them on a picture of your own instead of the one you were sent. It
  is sent as a PNG, so a JPEG or any other image macOS reads works too. With a picture, the marks
  may be `[]`.
- It prints one JSON line and exits **0** accepted, **1** not sent, **2** refused, or
  **3** unconfirmed. Accepted means Vignette has your reply and will keep it, not that the card is
  on screen yet. Not sent means an argument, a file or a mark is wrong, and `error` says which.
- **Unconfirmed means do not send a new reply.** Vignette never answered, so your reply may or may
  not have arrived. Retry the exact one, which can never make a second card:
  `sh "<this skill's folder>/scripts/reply" --ticket "<folder>/ticket.json" --retry <the bundle path it printed>`.
  A retry that exits 1 sent nothing, but the first attempt may still have arrived, so do not send a
  new reply then either.
- Only that ticket authorizes a reply, and only to that one request. A request the
  user has cleared refuses new replies (`request-closed`).
- Answer in words in your own session as usual. The reply carries only the drawing.

## Read back what they drew

The user draws and presses Return. Vignette writes a new `<name>-<result-id>-annotated.png` beside
the copy when the rendering finishes, then logs
`[annotate] done files=["<absolute path>"] <bytes> bytes, copied`. Decode the JSON array after
`files=` and read its path. Each result has its own file, kept until the user deletes it. A long
source name is shortened, so use the returned path. `copy-annotated` returns the same `files=`
field with the paths in selection order.

If the user drew nothing, no file is written and the line is
`[annotate] done <name> nothing drawn, original copied`. The folder is `screenshotsFolder` in
`~/.config/vignette/settings.json`.

On a card you pushed with `&session=`, Return sends the drawing to your session instead: it
arrives as a request, as in "When the user sends you a drawing" above, and no `-annotated.png` is
written.

Nothing arrives if the user ignores the thumbnail, so do not block on it. Ask for the drawing when
you need it, then carry on and look for the file.

## Is Vignette running, and does it have `add`

`open -g vignette://help` logs one `[help]` line per command and one `[help] ok` line; nothing
within a second means it is not running. If the list has no `add`, the app is older than this
skill: write your file straight into `screenshotsFolder`, which any version shows as a capture.

`open -g "vignette://state?tag=<id>"` logs one `[state] {json}` line carrying your tag, with the
watch folder, the stack, and what is in the editor.
