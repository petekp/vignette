# Screenshot comments: Pins in the editor

Part of [the screenshot comments plan](../screenshot-comments-2026-11-24.md).

## How pins and marks live together

**Choice 1, decided 2026-11-25: keep today's tools and add Comment.** Pete's words: "Keep all, add
Comment". A box with a short note stays the fastest way to point at one thing someone will see at a
glance. Pins are for many things in one area, or for words too long to sit on the picture. Replacing
the Text tool, or keeping pins only, would have lost the quick drawn screenshot.

The editor works like this:

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

**Choice 2, decided 2026-11-25: a popover beside the pin.** Pete's words: "Popover by the pin".

- The popover points at the pin's body, flips to whichever side has room, and holds the comments
  above the composer. The picture keeps its full size, and the comments sit next to what they are
  about.
- It is built on the popover live ink's notes already use (`HangingPopover`, `PopoverPlace`,
  `LiveNoteContent`). AppKit moves a popover in one frame when its anchor moves, and closes it in
  one frame when its window hides. `HangingPopover` slides it on a spring instead, and shows it
  again where it was. A pin moves at every zoom and pan step, so a popover that jumped would show at
  each one.
- The popover fades with the pin before the annotator hides at park.
- The list of every pin is a button on the toolbar, after the tools, showing how many pins there
  are. It opens a menu listing each pin's teardrop and the start of its first comment. The button
  slides in on a spring with the first pin and out with the last.

### What a pin looks like

**Choice 3, decided 2026-11-25: a teardrop.** Pete's words: "Teardrop". He chose it over the circle
at the area's corner that this plan recommended. A teardrop points at its place, so the place is
exact for a point pin, and Figma users already read the shape.

- The teardrop is a 24 pt circle with one quarter squared off into a point, the tip. The tip is the
  corner of the 24 pt square the shape fits in. Its number sits in the middle of the round part,
  which this plan calls the body.
- It has the note tag's look at its smallest: the person's red, a 1.5 pt white edge, the tag's
  shadows, and a white number in SF Pro Rounded. An agent's pin is indigo with its number in SF
  Mono, as an agent's note is.
- A point pin's tip sits on its point. An area pin's tip sits on the area's top-left corner, and its
  body rises up and to the right, outside the area, so the pin covers nothing the area holds.
- The body has four orientations, with the tip at its bottom-left, bottom-right, top-left or
  top-right. Bottom-left is the default. When the body would cross the picture's top edge, it flips
  below the tip. When it would cross the right edge, it flips to the left of the tip. For an area
  pin at the top edge, the flip puts the body inside the area's corner.
- The orientation is worked out from the picture's edges at the size the picture fits the frame, so
  the editor, the card, the flight and the PNG agree. It is not stored. It changes only when a move
  or a resize crosses an edge, and the body turns about the tip on a spring.
- An area's outline fades in while its pin is hovered, selected or open. A selected or open pin also
  gets a 2 pt ring in the selection blue, following the teardrop's outline.
- A press hits a pin when it lands on the teardrop or within 4 screen pt of it, the same band a
  stroke has. A pin is always on top, so it beats every mark's stroke and every note's tag. A
  selected pin's handles beat the pin, as a selected mark's handles do.
- An area pin's outline is a hit only while it shows, by the rectangle's rule for a stroke. The
  inside of an area is never a hit, so a person can still draw a box or a note inside it.
- Dragging the teardrop moves the pin and its area. A selected area pin has a rectangle's corner and
  edge handles on its outline.

The pin's size, its outline's width and the cluster distance are tuning settings in `UITweaks` and
`TweakCatalog`, as `docs/rules/settings.md` asks of any number a person might tune.

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

- Two pins form a cluster when their teardrops' bodies overlap by more than a third of their width,
  at the zoom on screen.
- A cluster is a teardrop widened into a capsule that names its pins in number order, such as "3 ·
  4". Past three it names three and counts the rest, as in "3 · 4 · 7 +2". Its tip sits at the tip
  of its lowest-numbered pin, and its orientation follows the same edge rule.
- When the zoom pulls the pins apart, they slide out of the cluster on a spring, and the capsule
  narrows back into each teardrop. They slide back in when the zoom pushes them together.
- The open pin and a selected pin never join a cluster, so the popover's anchor and the selection
  handles never vanish. A pin that is closed or deselected joins its cluster then, on a spring.
- A click on a cluster opens a menu listing its pins, each with its teardrop and the start of its
  first comment. Choosing one opens that pin. Pins on the same point stay a cluster at every zoom,
  so this list always reaches them.
- Cards cluster pins by the same rule at the card's size.
- The toolbar's list of pins reaches every pin, including one off screen while zoomed in. Opening a
  pin from a list scrolls the picture to show it. The zoom changes only when the area is larger than
  the view.
- Tab and Shift+Tab move through marks and pins in reading order, as they move through marks today.
  A pin inside a cluster is reached that way too.
- Renderings never draw clusters. Copy and Send place each teardrop on its own (see [Copy, Send,
  Stitch and Reply](outputs.md)).

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
