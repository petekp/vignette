# Screenshot comments: What a pin is, and how it is stored

Part of [the screenshot comments plan](../screenshot-comments-2026-11-24.md).

A pin belongs to one drawing, beside its marks. It is not a mark.

| Field | Meaning |
|---|---|
| `id` | A random id that never changes. A request's `pins.json` and an agent's answer name a pin by it. |
| `number` | Its pin number, from 1 |
| `x`, `y` | A point pin's point, or an area pin's top-left corner, in px of the screenshot |
| `w`, `h` | An area pin's size in px. A point pin has neither. |
| `comments` | One or more comments, oldest first |

A comment holds `text`, plain like a note's, at most 2,000 characters. When an agent wrote it, it
also holds `agent` and `agentName`, as a mark does. It has no date, since nothing shows one. A
screenshot holds at most 99 pins.

Pins are a list of their own, apart from the marks, for four reasons.

- A mark is drawn in the picture and grows with the zoom. A pin keeps one size on screen, like a
  handle, so zooming in pulls a cluster apart. Figma's pins behave the same way.
- A mark's place in the list is its stacking order. Pins are always drawn above every mark.
- Undo names a mark by its index in the list, because a mark's id lives only while the app runs (ADR
  0028). A pin keeps its `id` in the file, so a step can name it by that.
- Copy, Send and Stitch each carry a pin's words, which they never do for a mark.

### A drawing is its marks and its pins

Today "no drawing" is written as "no marks" all through the app. `marks.isEmpty` appears 33 times in
17 files. `DrawingStore.read` returns nothing for a file without marks. `Drawings.keys` holds only
screenshots with marks, so `current(of:)`, Stitch, Copy Drawing and a drag see no drawing.
`Drawings.saved` then answers nothing, so undoing Move to Trash would bring the screenshot back
without its pins. `Agent.fingerprint` hashes no drawing when it has no marks, so Reply could not see
a new pin.

Step 1 adds one `Drawing.isEmpty`, true when there are no marks and no pins, and moves every one of
those sites to it. `keys` comes to mean "has a drawing". A drawing that holds only pins then behaves
like any other drawing everywhere.

### In the drawing file

A drawing with pins adds two keys to the file in `docs/drawing-file.md`:

```json
{
  "version": 2,
  "key": "/Users/pete/Dropbox/Screenshots/Screenshot 2026-11-14 at 9.53.23 PM.png",
  "pixels": [1136, 966],
  "pointScale": 1.31,
  "markScale": 0.656,
  "marks": [],
  "pins": [
    { "id": "6F1C…", "number": 1, "x": 1040, "y": 130, "w": 36, "h": 360,
      "comments": [{ "text": "remove extra margin" }] },
    { "id": "A93B…", "number": 3, "x": 925, "y": 232, "w": 125, "h": 185,
      "comments": [{ "text": "the shimmer effect is too narrow; needs more width and spread." },
                   { "text": "can we have the dot indicator pulse gently with a subtle glow?" }] }
  ],
  "nextPin": 4
}
```

- `nextPin` is the number the next pin takes. It is written whenever it is above 1, so deleting
  every pin never frees their numbers while the file exists.
- A file is written as `version` 2 when it holds pins, a `nextPin`, or a history step about pins.
  Every other file stays version 1. A build that predates pins leaves a version 2 file alone, as it
  does any newer file. That build opens the image without its drawing, and never writes over the
  file. Builds from several worktrees share the drawings folder, so this happens. A version 1 write
  would drop the pins, or drop a history that holds a deleted pin's words.
- An older build cannot follow a rename of a version 2 file. It never lists a newer file, so the
  drawing stays under the old name, and the newer build's launch sweep removes it. ADR 0030 takes
  this as a cost: it needs an older build renaming a pinned screenshot.
- A drawing with pins and no marks keeps its file, as one with only a message does today. A file
  with no marks, no pins and no message is removed, as now, whatever its `nextPin`.
- A screenshot whose drawing file was removed starts again at pin 1. Nothing in Vignette points at
  an old number then. A copy already pasted elsewhere carries its own words beside its numbers, and
  an agent's answer names a pin by its `id`.
- `basis`, the hash that checks the stored undo history, covers the pins and `nextPin` too.
- The validator that reads files, pastes and agents' marks checks pins. A pin outside the image is
  moved in. A pin with no comment, a repeated number or `id`, or a comment over the limit is
  dropped, with a log line. `nextPin` is raised past the highest number kept.
- Old drawings need no migration, since a file without `pins` has none. Vignette does not keep
  drawings from an earlier build readable, so no reader for an older shape is added.

### Numbers stay put

- A pin takes `nextPin` when its first comment is posted, and `nextPin` goes up by one. A pin
  dropped before its first comment never took a number, so a cancelled pin leaves no gap.
- Deleting a pin leaves its number unused. Undo brings the pin back with the same number, and redo
  deletes it again. `nextPin` never goes down while the file exists.
- A deleted pin's number is never reused, and the others are never renumbered. A pasted image that
  says "3" keeps meaning pin 3.
- A pin pasted with Cmd+V takes a new number and a new `id`, since its original may still be on the
  screenshot.
- Stitch is the one place numbers change (Question 6).
