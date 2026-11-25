# Pins are kept in the drawing file

Status: accepted, 2026-11-25, and built: `Pin.swift` and `DrawingFile.swift` read and write pins,
`nextPin` and the version. `docs/screenshot-comments-2026-11-24.md` is the plan it belongs to.

A screenshot's pins, the numbered points and areas that hold comments, are kept in its drawing file,
under `pins`, beside its marks and its message. Each pin has a random `id` that never changes, a
number, its place in px of the screenshot, and its comments in order. `nextPin` is the number the
next pin takes. It is written whenever it is above 1, and it never goes down while the file exists.

A file is written as `version` 2 when it holds pins, a `nextPin`, or a history step about pins.
Every other file stays version 1. A build that predates pins treats a version 2 file as one from a
newer build. It opens the image without the drawing and never writes over the file. Builds from
several worktrees share the drawings folder. A version 1 write would drop the person's comments, or
drop a history that holds a deleted pin's words, since an older build drops a history with a step it
does not know.

One loss is accepted. An older build never lists a newer file, so it cannot follow a rename of a
pinned screenshot. The drawing stays under the old name, and the newer build's launch sweep removes
it. That needs an older build to rename a pinned screenshot, which only happens while several builds
share the folder.

A pin stores its place, never how it is drawn. Its teardrop's orientation is worked out each time it
is drawn, so a change to the pin's look needs no change to the file.

A drawing with pins is a drawing everywhere. Today "no drawing" means "no marks" in 33 places.
`Drawing.isEmpty` covers marks and pins, and those places move to it.

A pin is not a mark. A mark is drawn in the picture, grows with the zoom, stacks in list order and
is named in the undo history by its index. A pin keeps one size on screen, sits above every mark,
and is named in the history by its `id`. So the history's marks step becomes a drawing step that
holds marks and pins. `basis`, the hash that checks the history, also covers the pins and `nextPin`.

A drawing with pins and no marks keeps its file, as one with only a message does. A file with no
marks, no pins and no message is removed, whatever its `nextPin`, unless it is a stitch's and
keeps where its pieces wear their numbers (`pieceNumbers`). A screenshot whose file was removed
starts again at pin 1.

Reversing this means teaching readers to accept a version 2 file and ignore `pins` and `nextPin`.
Until a build does that, it cannot open any pinned drawing.

## Considered options

- Pins as a fifth kind of mark. Selection, moving, the clipboard and the validator would come for
  free. Every place that treats a mark as part of the picture would need an exception. These are the
  zoom, the stacking order, the history's indices, and Copy, Send and Stitch, which carry a pin's
  words and no mark's.
- A file of their own beside the drawing. A rename, a removal, the launch sweep and the Trash's undo
  would each move or remove two files, and the two could disagree after a crash. ADR 0028 turned
  down the same split for the history.
- Keeping the version at 1, as ADR 0028 did for `history`. A build that drops `history` loses undo
  steps. One that drops `pins` loses what the person wrote.
- Version 2 for every file. Every drawing would become unreadable to an older build at its next
  write, pins or not.
- Keeping `nextPin` in a file with nothing else in it, so a number is never used twice on a
  screenshot. A file kept for a counter alone needs its own place in the launch sweep and the
  rename. With every pin gone, nothing in Vignette refers to an old number, and a copy pasted
  elsewhere carries its own words beside its numbers.
