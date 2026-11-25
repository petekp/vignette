# Screenshot comments: Pins in the editor

Part of [the screenshot comments plan](../screenshot-comments-2026-11-24.md).

## How pins and marks live together

**Question 1: keep today's marks?** Pete asked whether the old way should stay, for a quick drawn
screenshot.

- (a) Keep every tool, and add Comment as a fifth. **Recommended.** A box and a short note is still
  the fastest way to say one thing someone will see at a glance. Pins are for many things in one
  area, or for words too long to sit on the picture.
- (b) Replace the Text tool with Comment, and keep Rectangle and Arrow. There are fewer tools, but a
  quick screenshot can then show words only through the copy.
- (c) Pins only. This is the simplest editor, and it loses the quick drawn screenshot Pete wants to
  keep.

With (a), the editor works like this:

- The tools are Select, Rectangle, Arrow, Text and Comment. Comment's key is C and its symbol is
  `text.bubble`. C is free today: the tool keys are V, R, A and T, and M and P go to the message
  field.
- `docs/editor.md` Decision 4, "The Text tool is the one way to add words", becomes "The Text and
  Comment tools are the two ways".
- The Comment tool follows Decision 1, as every drawing tool does. Over a mark or a pin it selects.
  Everywhere else it makes a pin.
- A click makes a point pin. A drag past 4 screen pt makes an area pin, with the Rectangle tool's
  rules for Shift, Option, the image's edges, Esc and Cmd+Z during the drag. On release the pin's
  composer, the field where a comment is written, opens with the caret in it.
- Typing right after a box or an arrow still starts a note for it. A Comment tool drag never starts
  a note, since its keys go to the composer.
- Pins and marks can be selected together, moved together with the mouse or the arrow keys, and
  deleted together. An area pin resizes like a rectangle when it is the only thing selected. A point
  pin does not resize.
- Cmd+C with pins selected copies them with their comments, in Vignette's own clipboard type, and
  their words as plain text.
- An agent's comment is indigo and set in SF Mono, as an agent's note is. A person's is red and set
  in SF Pro Rounded. A person who edits an agent's comment makes it theirs, as with a note.

### Writing comments

| Trigger | Result |
|---|---|
| Release after a Comment tool click or drag | The pin's composer opens, empty, with the caret |
| Double-click a pin | The composer opens on that pin, with the caret in a new comment. With any tool once the `text-edit` change merges, which lets a double-click edit a note with any tool. Until then, in Select. |
| Shift+Return or Option+Return with one pin selected | The same, as for a selected note |
| Return in the composer | Posts the comment. The composer stays open on the pin, empty, for another. |
| Return in the empty composer | Closes it. The pin stays selected, so a second Return copies, as after a note. |
| Shift+Return or Option+Return in the composer | A new line |
| Cmd+Return in the composer | Posts the comment, then sends or copies, as Cmd+Return after typing a note does |
| Cmd+Z, Shift+Cmd+Z in the composer | Undo and redo typing in this comment. At its start, Cmd+Z does nothing, as in a note. |
| Esc in the composer | Posts what was typed and closes the composer. The pin stays selected. A second Esc closes the editor. |
| A press elsewhere, a tool key outside the field, Send, Copy, or the host parking the drawing | Posts what was typed first, as typing a note ends |
| Closing on a new pin with nothing typed | The pin shrinks away on a spring, and takes no number |
| Click a comment's words in an open pin | Edits that comment. Emptying it and closing deletes it. Deleting a pin's last comment deletes the pin. |

These keys follow the ones Vignette's notes and message field already have. Return finishes,
Shift+Return and Option+Return break a line, Cmd+Return sends, and what was typed is kept. So there
is no draft, no save button and no question at Copy or Send. The composer, like a note, has no
spell-check, autocorrect or replacements, holds plain text, and lets an input method compose.

### Where an open pin's comments show

**Question 2 (mock 1).**

- (a) A popover beside the pin. It points at the pin, flips to whichever side has room, and holds
  the comments above the composer. **Recommended.** The picture keeps its full size, and the
  comments sit next to what they are about. It is built on the popover live ink's notes already use
  (`HangingPopover`, `PopoverPlace`, `LiveNoteContent`). AppKit moves a popover in one frame when
  its anchor moves, and closes it in one frame when its window hides. `HangingPopover` slides it on
  a spring instead, and shows it again where it was. A pin moves at every zoom and pan step, so a
  popover that jumped would show at each one. The popover fades with the pin before the annotator
  hides at park.
- (b) A panel beside the annotator's frame, listing every pin, with the open one expanded. The
  picture stays uncovered. It takes room from the picture on every screenshot with pins, and the eye
  travels between a place and its words.
- (c) The open pin's comments drawn as note tags beside its area, with the composer as the last tag.
  It looks like the notes people already write, and collapses back to the number when closed. In a
  dense area the open tags cover the things they are about.

With (a), the list of every pin is a button on the toolbar, after the tools, showing how many pins
there are. It opens a popover listing each pin's number and the start of its first comment. The
button slides in on a spring with the first pin and out with the last.

### What a pin looks like

**Question 3 (mock 2).**

- (a) A filled circle in the person's red with the white number, at an area pin's top-left corner.
  The area's outline fades in while the pin is hovered, selected or open. **Recommended.** It is the
  note tag's look at its smallest, with the same red, white 1.5 pt edge, shadows and SF Pro Rounded.
  Hiding the outline keeps a dense area clear.
- (b) A teardrop that points at the place, as Figma's pins do. The tip is exact for a point pin. For
  an area, the tip sits on a corner and the shape stands taller over the picture.
- (c) The area always outlined in a thin line, with the number on a small tab at its corner. Every
  area shows at once, which helps when the areas themselves matter. A dense area becomes a mesh of
  lines.

In every option an agent's pin is indigo, as its marks are. The pin's size, its outline's width and
the cluster distance are tuning settings in `UITweaks` and `TweakCatalog`, as
`docs/rules/settings.md` asks of any number a person might tune.

## Size and zoom

- In the editor a pin keeps one size on screen at every zoom, so zooming in pulls a cluster apart.
  That size is the pin's size in the picture when the picture fits the frame. A screenshot opens at
  that zoom and lands there after a flight. So the editor draws a pin exactly as the card and the
  flight do, and nothing changes size at the hand-over.
- On a card, in a flight and in every rendering, a pin is drawn in the picture at the drawing's mark
  scale, as a note is, by the one renderer (ADR 0010). `MarkLayers` draws pins for the editor, the
  cards and the flights, and `MarkRendering` for the PNGs.
- An area pin's outline is a mark's stroke at mark scale, so it grows with the zoom like a
  rectangle.

## Dense areas

- Two pins whose circles overlap by more than a third of their width, at the zoom on screen, form a
  cluster. A cluster is one circle naming its pins, such as "3 · 4". When the zoom pulls them apart,
  the pins slide out of the cluster on a spring, and slide back in when it pushes them together.
- The open pin and a selected pin never join a cluster, so the popover's anchor and the selection
  handles never vanish. A pin that is closed or deselected joins its cluster then, on a spring.
- A click on a cluster opens a popover listing its pins, each with its number and the start of its
  first comment. Choosing one opens that pin. Pins on the same point stay a cluster at every zoom,
  so this list always reaches them.
- Cards cluster pins by the same rule at the card's size.
- The toolbar's list of pins reaches every pin, including one off screen while zoomed in. Opening a
  pin from a list scrolls the picture to show it. The zoom changes only when the area is larger than
  the view.
- Tab and Shift+Tab move through marks and pins in reading order, as they move through marks today.
  A pin inside a cluster is reached that way too.
- Renderings never draw clusters. They move colliding numbers apart with short leader lines.

## Keyboard

- C picks Comment.
- With nothing selected, Return copies and Cmd+Return sends, as now. With one pin selected, Return
  still copies. Opening a pin is Shift+Return, Option+Return or a double-click, as for a note.
- With the Comment tool and nothing selected, Shift+Return opens a new point pin at the middle of
  the visible picture. `docs/editor.md` gives Shift+Return a meaning only with one text selected, so
  this takes no key from anything.
- Arrow keys move the selected pin, and Shift with an arrow moves it 10 pt, as with marks.
- In the popover, Tab moves between the comments' edit controls and the composer. Esc closes it.

## VoiceOver

Today the canvas is one image named for its screenshot. Tool changes, the selected mark, and undo
and redo are announced.

- Each pin is an accessibility element inside the canvas, such as "Pin 3, area, 2 comments", with
  its first comment as its value. VoiceOver's item chooser and a "Pins" rotor reach every pin,
  clusters included.
- A pin's actions are Open, Delete and Move. The canvas gains Add Pin, which does what Shift+Return
  does with the Comment tool. Open opens the composer, named "Comment on pin 3".
- Making, deleting and opening a pin are announced, as in "Pin 3 added". An opened pin's comments
  are read in order. Undo and redo of a pin step are announced with the step's name.
- Closing the composer puts the VoiceOver cursor back on the pin.
