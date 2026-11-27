---
name: vignette
description: >-
  Show the user an image through Vignette, the screenshot tool on this Mac, and read back what they drew on it. Use when you want the user to see a screenshot or rendering you produced (a browser capture, screencapture, a before-and-after), when they ask to see what something looks like, or when you need their circled answer. Also use it when a message contains "From Vignette:": the user sent you a screenshot they drew on, and you can answer with a drawing. Not for images the user captured themselves; Vignette already shows those.
metadata:
  version: "35"
---

# Vignette

Vignette watches the user's screenshots folder, shows each new image as a thumbnail in the
corner, keeps the recent ones in a stack, and lets the user draw on one and press Return. Every
command is a `vignette://` URL. Each one answers with one line in `~/Library/Logs/Vignette.log`:
`[<command>] ok <detail>` or `[<command>] error <code> <detail>`.

## Show the user an image

```sh
file=$(osascript -l JavaScript -e 'function run(argv) { return encodeURIComponent(argv[0]) }' "/abs/path/Checkout at 390px.png")
title=$(osascript -l JavaScript -e 'function run(argv) { return encodeURIComponent(argv[0]) }' "Checkout at 390 px")
description=$(osascript -l JavaScript -e 'function run(argv) { return encodeURIComponent(argv[0]) }' "After the fix: the total stays on one line")
open -g "vignette://add?file=$file&title=$title&description=$description&agent=claude&session=$CLAUDE_CODE_SESSION_ID"  # from Claude Code
open -g "vignette://add?file=$file&title=$title&description=$description&agent=codex&session=$CODEX_THREAD_ID"          # from Codex
```

- `add` copies the file into the watch folder and shows its thumbnail. It leaves the clipboard
  alone and does not open the editor, whatever the user's capture settings say. Add `&annotate`
  to open the editor instead, only when you are asking for marks right away.
- `&agent=<name>` says who pushed it: `claude` or `codex`. The card gets a tab naming you.
- `&from=<name>` is your session's name as the user knows it, such as the name of the Herdr tab
  you run in, in a few words. The card's tab then says "From <name>" in place of "From Claude". It
  takes up to 40 characters, and longer text is cut at a word with a warning. Leave it out when you
  do not know the name: with `&session=`, Vignette looks it up from the user's session list.
  Percent-encode it, as you do the path.
- `&session=<id>` names your session, so the user's Reply on the card comes back to you. Claude
  Code sets `CLAUDE_CODE_SESSION_ID`, and Codex sets `CODEX_THREAD_ID` to your thread's id. Leave
  it out when your client gives you no session id.
- `&title=<text>` and `&description=<text>` say what the screenshot shows. The editor shows the
  title above the image and the description under it in a lighter line. Use them to name what the
  user is looking at, such as "Checkout at 390 px, after the fix". Keep marks for pointing at a
  place in the image. The title takes up to 60 characters and the description up to 140. Longer
  text is cut at a word with an ellipsis, and `[add]` still answers `ok` with a warning. They show
  only in the editor: the card, a copy and what the user sends back leave them out. Percent-encode
  both, as you do the path.
- `open -g` keeps the focus where it is. Always percent-encode the path yourself; `open` will not.
- When the commands here name an app with `-a`, that is the copy of Vignette that installed this
  skill. Name it in every command you send: a bare `open` can start another build of Vignette.
- In Codex, invoke `open` as a direct tool command. Python may encode URL arguments. A sandboxed
  Python subprocess can return `kLSNoExecutableErr` for an intact app; request approved host
  execution if Python must launch it.
- If `open -a` fails, read `CFBundleExecutable` from that app's `Contents/Info.plist` and check
  `Contents/MacOS/<executable>` before reporting a missing installation. If the bundle or executable
  is absent, tell the user its path is missing and go on without the image. Keep `-a` on retries:
  a bare `open` can start another build on the user's settings.
- The file may be anywhere outside the watch folder. Every other command takes files inside it
  only. For a screenshot already in the folder, use `show` (below).
- Wait for `[add] ok <name>` in the log. The name gains a counter (`x 2.png`) when one is taken.
  Errors end with `missing-file`, `unreadable-image`, `unsupported-type` (png, jpg, jpeg, or heic
  only, and never a `-annotated` name), `write-failed`, or `invalid-marks`.
- Push what the user should see, not every image you make. Name the file for them: what it shows,
  at what size or state.

## Point the user at screenshots they already have

When the screenshot is already in the user's screenshots folder, such as one they took earlier,
use `show`, never `add`. `add` would label the user's own screenshot as yours, so it refuses one
with `unsupported-type`. `[state]` gives the folder as `app.watchFolder`.

```sh
a=$(osascript -l JavaScript -e 'function run(argv) { return encodeURIComponent(argv[0]) }' "/abs/path/Screenshots/Checkout.png")
b=$(osascript -l JavaScript -e 'function run(argv) { return encodeURIComponent(argv[0]) }' "/abs/path/Screenshots/Cart.png")
message=$(osascript -l JavaScript -e 'function run(argv) { return encodeURIComponent(argv[0]) }' "The total wraps in both")
open -g "vignette://show?file=$a&file=$b&message=$message&agent=claude&session=$CLAUDE_CODE_SESSION_ID"  # from Claude Code
open -g "vignette://show?file=$a&file=$b&message=$message&agent=codex&session=$CODEX_THREAD_ID"          # from Codex
```

- `show` brings each card to the corner in the order you name the files, or marks it where it
  already is, and dims the others. The card says "From <your session's name>", or "From Claude"
  when the name is unknown, with your message under it. It takes no keys from the user.
- `&from=<name>` is your session's name, as for `add`.
- `&message=<text>` is one line of up to 60 characters. Longer text is cut at a word, and `[show]`
  still answers `ok` with a warning. Percent-encode it, as you do the paths.
- `&marks=` takes marks in the format under "Draw on it yourself", for the first file. They join the
  user's drawing at once, as one step the user can undo, as with `add`.
- `&pins=` takes pins as under "Leave comment pins", for the first file. They join with your marks.
- `&session=<id>` names your session, as for `add`. Send on a card you showed then starts on your
  session.
- Name at most as many files as the user's column keeps (`app.recentCount` in `[state]`, 30 by
  default). More answers `too-many-files`.
- Wait for `[show] ok files=[…] … joined=<n> inColumn=<n> inEditor=<n>`. While the user's hand is in
  the corner, the call waits (`[show] waits for drag`), so the answer can come a few seconds late.
  Errors end with `missing-file`, `outside-watch-folder`, `unreadable-image`, `too-many-files`,
  `invalid-marks` or `invalid-pins`.

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
  nearer, but never narrower than 15% of the width. Write the sentence you mean; it is sized,
  wrapped and moved to fit the image.
- A sentence too long to fit even across the whole picture **is cut off at the edge**, and `[add]`
  still answers `ok`. The log says which one: `[marks] text too long for <name>: mark N is cut off
  at its edge`. Keep a pushed text to a sentence, and check the log if it mattered.
- Your marks are drawn in indigo, the agent colour, and the user's are red. There is no choice of
  colour: a `color` field is ignored. So on a drawing the user sends you, the red marks are theirs
  and the indigo ones are yours or another agent's.
- In `[add] ok <name> … marks=<n>`, `n` counts the marks that joined the drawing. Dropped marks are
  not counted. `invalid-marks` names the mark and the field.

## Leave comment pins

`&pins=` on `add` or `show` leaves comment pins, like the user's, or answers theirs. It
takes a JSON file's path, or the JSON itself, in the fractions `&marks=` uses:

```json
[{"x": 0.42, "y": 0.18, "text": "This label wraps at 390 px"},
 {"x": 0.10, "y": 0.55, "w": 0.30, "h": 0.12, "text": "These rows should line up"},
 {"pin": 2, "text": "Fixed: the margin is 8 pt now"}]
```

- `x`,`y` is a pin at a point. With `w`,`h` it is about that area, its teardrop at the
  bottom-right corner or the one `corner` names (`topLeft`, `topRight`, `bottomLeft`).
- `pin` answers the user's pin by its number ("Pin 2") or its `id` from `pins.json`, with no place.
- New pins take the next numbers, in the agent colour. At most 99 per call and 2,000 characters
  each. `ok` counts them as `pins=<n>`; `invalid-pins` names the comment and what is wrong.
- Answer on the user's own screenshot with `show`.

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
to change in Vignette's settings, so know the line by "From Vignette:" and the quoted path. A
sentence after the path may name the apps it shows, largest first: "The screenshot shows Safari."

Open the image. The boxes, arrows and text on it are the user's: they point at what they want you
to look at or change. When the answer is easier to show than to say, reply with a drawing: the
helper puts your marks on a new card beside the user's other screenshots. They edit those marks
like their own and can send the result straight back to you.

When the user pinned comments on the image, the line carries their words after the message, pin
by pin: `Pin 1: remove extra margin. Pin 3: too narrow. / can it pulse?` "Pin 3" is the teardrop
numbered 3 on the image. Its pointed tip marks the place the comment is about, and a pin about an
area has that area outlined in its colour. A teardrop that would cover another sits a little
away, joined to its place by a short line. One pin's comments are joined with " / ", oldest
first. Answer a pin in words, or on the pin itself with `--comments` (below).

When the user answers an image you sent with words alone, and left your marks as they were, the
line names that image and sends no new picture:

```text
Make the total bigger [From Vignette: about your image "<watch folder>/Checkout.png" ("Checkout at 390 px"), unchanged since you sent it. The reply ticket is "<folder>/ticket.json". If a drawing would answer better than words, you can send one back.]
```

The quoted path is the file your push or your reply made: the name in `[add] ok <name>`, or
`Agent reply <id>.png` for a reply. The title in brackets is the one you gave, and the line leaves
it out when you gave none. You have already seen this image, so do not open it: act on the
message. To answer with a drawing, use the ticket the line names. Without `--image`, your marks go
on the picture without the marks you sent before.

The helper is `scripts/reply` in this skill's folder. The `ticket.json` in the image's folder, or
the one the line names, authorizes the reply:

```sh
cat > /tmp/reply.json <<'JSON'
[{"type": "arrow", "x": 0.50, "y": 0.90, "x2": 0.44, "y2": 0.62},
 {"type": "text",  "x": 0.20, "y": 0.92, "text": "this column is the one that overflows"}]
JSON
sh "<this skill's folder>/scripts/reply" --ticket "<folder>/ticket.json" --marks /tmp/reply.json
```

- The marks are the same format as `&marks=` above, with the same limits.
- `--image <your image>` puts them on a picture of your own instead of the one you were sent. A
  JPEG or any image macOS reads works too. With a picture, the marks may be `[]`.
- `--comments '{"3": "Widened the band"}'` answers the user's pins by number. Each answer joins its
  pin on the new card, under the user's words. It needs no `--marks` and does not go with `--image`.
- `--title <text>` and `--description <text>` say what your reply shows, as `&title=` and
  `&description=` do for `add`, with the same limits. The JSON line names a part that was cut under
  `cut`. Neither goes with `--answer`.
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

### When the drawing was made with live ink

Live ink is drawn on the user's screen itself, over a running app, not on a screenshot. Its message
says where the ink is:

```text
Move these under the title, smaller. Drawn with Vignette's live ink on Google Chrome, "Postcard", http://localhost:5173/. [From Vignette: "<folder>/image.png". …]
```

When they asked without drawing, the message says so and there is no ink; a line such as "The pointer
was at 74% across and 32% down the picture", when present, marks the spot they asked about, from the
image's top-left corner.

The image is the whole window, or the screen when no window is under the point, with their ink
drawn in, each stroke numbered; an ask without drawing has no ink in it. Once the note is sent,
the ink leaves the user's screen and becomes a card in Vignette's corner. When your turn
ends, Vignette looks at the window again. If it changed under the ink, that window becomes a card
from you, and Reply on it comes back to you as a new drawing. If nothing changed there, their card
says you are done. So you do not need to confirm a change on the window. Answer in your session as
usual.

Answer with `--answer` only when pointing at something helps them: what they asked about is
somewhere on the screen, a change landed where they would not look, or you need them to choose
between things they can see. Your answer becomes the card from you: Vignette captures the window
afresh when it arrives, writes your words in its corner, and draws each mark at the words it names:

```sh
cat > /tmp/answer.json <<'JSON'
{"say": "Two more things break at this width.",
 "marks": [{"kind": "circle", "words": "Share", "label": "Share cut off"},
           {"kind": "arrow", "words": "20 km", "label": "Map cropped"}]}
JSON
sh "<this skill's folder>/scripts/reply" --ticket "<folder>/ticket.json" --answer /tmp/answer.json
```

- Make one finding per mark, and give each a `label` that names it in their terms: "Share cut
  off", "Map cropped". The labels carry the details.
- `say` is one short sentence, two at most, that ties the marks together, as in "Two more things
  break at this width." Do not repeat the labels in it. Without marks, it is what you did or what
  they should know.
- List the marks in reading order, top to bottom.
- Vignette finds each mark's `words` in a fresh capture of the window when your reply arrives, so
  name text that is on screen after your change. Copy it exactly, from one line, and pick words
  that show in full and appear once on the screen. For something cut off at the window's edge,
  name the nearest whole words. A mark whose words are not found is left out, unless it has a box.
- `kind` is `circle` for one thing and `arrow` for a place or an edge. A `label` is one to four
  words. At most four marks.
- `box` is `[x, y, w, h]` as fractions of the image you were sent. Give it as well as `words` for a
  number, a price or a table cell, which the capture can misread: Vignette uses the box when it
  cannot find the words, so put it where they will be after your change. For something with no
  text, give `box` alone.
- `--answer` comes alone, without `--marks` or `--image`. The exit codes are the same. A mark
  Vignette could not draw, such as an unknown `kind`, a fifth mark or a box outside the picture,
  is not sent: the helper exits 1 and `error` names the mark. Accepted waits until the card is
  made, about a second. When the line has `notDrawn`, those marks are not on the card, since their
  words were not found: say those findings in your words in your session.
- If Vignette cannot capture the window when your answer arrives, because it was closed or
  minimized or Vignette restarted, the card is the picture you were sent, with your words in its
  corner and the marks that have a box.

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
