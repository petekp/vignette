# The drawing editor

This is how Vignette's drawing editor behaves. The editor is written in Swift and runs in the app's
own process. `AGENTS.md` has the rules for changing it.

The host is the app around the editor. It is the annotator (`AnnotationController`), which opens,
parks and zooms the editor, and the rest of the app, which stores and renders its drawing.

## Summary

- The editor has four tools: Select, Rectangle, Arrow and Text. It also covers selection, typing,
  keys, undo and the clipboard.
- A drawing is a small JSON file that Vignette owns. Its geometry is in the screenshot's pixels,
  so a drawing looks the same on any display.
- Where there is a choice, the editor takes the most native, fluid option and makes it safe.
- The behaviours that matter most:
  - text wraps at the image's edge;
  - no mark leaves the image;
  - Esc cancels a drag before it closes the editor;
  - one rule decides what a click hits;
  - each Cmd+Z undoes exactly one step;
  - park answers at once, so nothing waits on the editor.

## Units

| Unit | Meaning |
|---|---|
| px | A pixel of the screenshot file. Drawings are stored in px. |
| pt | A drawing point: px divided by the drawing's point scale, per Decision 8. On a Retina capture, 1 pt is 2 px. Stroke width and text size are set in pt. |
| screen pt | A point on the screen. A threshold in screen pt stays the same size at any zoom. |

## Decisions

All eighteen were decided on 2026-09-22.

| # | Question | Answer | Why |
|---|---|---|---|
| 1 | Which tool is active after drawing a mark? | The same tool. The new mark is selected, and its handles work while the tool is active. Over another mark the cursor becomes the Select cursor and the mark gets the hover outline. A press there selects the mark. A press anywhere else draws. V goes back to Select. Section 3 has the details. | Marking several things in a row is common. The cursor and the outline say before the press whether it will select or draw. |
| 2 | What does a click without a drag do with the Rectangle tool? | Nothing is created. | A click gives no size, and a default box would cover part of a small crop. The Arrow tool behaves the same way. |
| 3 | Do arrows attach to the marks they point at? | No. The tip lands exactly where the pointer was released and stays there. | An arrow points at a place, and attaching would move the tip away from it. Revisit if people expect an arrow to follow the box it points at. |
| 4 | Do rectangles and arrows carry text labels? | No. The Text tool is the one way to add words. | One way to add words keeps the tools simple. |
| 5 | Can text be formatted? | No. Text is plain and can run to several lines. | Notes on screenshots are short. Formatting shortcuts fire by accident. |
| 6 | Can marks be rotated? | No. | Marks point at interface elements, which are upright. |
| 7 | Can arrows be curved? | Yes, with the middle dot, which an arrow shows when it is the only mark selected. | A bend takes an arrow around a mark it would otherwise cross. |
| 8 | What sets the size of strokes and text? | Each drawing records its point scale, the px per pt of the display the annotator is on when the drawing's first mark is made. A drawing that an agent's marks start takes the main display's. Every mark in the drawing uses it. | The drawing looks the same on any display it reopens on. A capture file does not say which display took it, so the annotator's display is the best available guess. |
| 9 | Which font does text use? | SF Pro Rounded. | It is the system's own face, so nothing is bundled and macOS supplies every script and emoji. The rounded face reads as a note, apart from the SF Pro text in most screenshots. The app already uses it for the numbers on selected cards. |
| 10 | What do Cmd+C and Cmd+V do? | With marks selected, Cmd+C copies those marks, and Cmd+V pastes them. With nothing selected, Cmd+C copies the drawing as an image, the same PNG Done makes, and the editor stays open. Cmd+V with text adds a text mark. Cmd+V with an image says it cannot paste images. Each copy says what it copied. Section 8 has the details. | The visible selection says what Cmd+C will copy. |
| 11 | Do marks snap to each other and to the image's edges? | Not in the first version. | Marks point at things in the screenshot, so alignment between marks rarely matters. |
| 12 | Can several selected marks be resized together? | No. Several selected marks can be moved, duplicated and deleted. | A group resize would scale the text but not the strokes, which distorts the group. |
| 13 | How is a drawing stored? | In a JSON file of Vignette's own, in px, with a version number. Section 1 has the format. | A format in px does not depend on the display. |
| 14 | How fast does park answer? | At once, in the same turn of the run loop. `ThumbnailController` queues an event that arrives while it is still handling one, and runs it right after. | A swap's park and the next card's opening land in the same frame. Queuing the event keeps the transition's events in order. |
| 15 | Which colour profile does a rendering use? | The screenshot's own. The marks are drawn into that colour space. | The screenshot's pixels come out unchanged. Converting to sRGB shifts saturated colours, so a note about a wrong colour would ship a different colour. |
| 16 | How do cards and flights show a drawing? | They draw its marks with the editor's renderer, over the thumbnail. No preview images are stored. | A card is current the moment its drawing parks, and sharp at any card size. Park has no rendering to wait for. |
| 17 | How does zoom draw? | The editor draws inside the annotator's window, and zoom scales its layers. | One process draws the frame and the drawing, so both move in the same frame. |
| 18 | What does an arrowhead look like? | A filled triangle whose size follows the stroke width. Its proportions are tuned live in the tweaks panel. | It reads at a glance at any capture size. |

## 1. The drawing

### The screenshot

- The screenshot is the fixed background. It is not a mark. Nothing selects, moves, reorders,
  copies or crops it.
- A drawing belongs to one screenshot.
- The image's size is its size as displayed, after any orientation flag in the file. A photo added
  with `add?file=` can carry one.

### Marks

| Kind | Fields | Who makes it |
|---|---|---|
| Rectangle | frame `x y w h` | Rectangle tool, agents |
| Ellipse | frame `x y w h`. The ellipse fills the frame. | Agents |
| Arrow | start `x y`, end `x2 y2`, `bend` | Arrow tool, agents |
| Text | `x y` of the box's top-left corner, `text`, `wrap` width or none, `size` | Text tool, agents, Cmd+V |

Every mark also has:

- `color`, one of the five ids under Style;
- `agent`, true when an agent made it;
- `colorChosen`, true when an agent named its colour, so the colour pass leaves it alone.

Notes:

- **Order.** Marks are drawn in the order they are stored, and the last one is on top. The newest
  mark is the last one.
- **Bend.** The signed distance in px from the middle of the line between the ends to the arc,
  measured on the perpendicular. A bend under 8 pt is drawn straight.
- **Text size.** `size` is the font size in pt. Dragging a text's corner scales it. An agent's text
  starts with a size set from the image's width.
- **Arrowhead.** Every arrow has one head, at its end.

### The file

One file per screenshot, at `~/Library/Application Support/<bundle id>/drawings/<id>.json`. The
`<id>` is a hash of the screenshot's path.

```json
{
  "version": 1,
  "key": "/Users/pete/Dropbox/Screenshots/Screenshot 2026-09-22 at 10.08.24 PM.png",
  "pixels": [3024, 1964],
  "pointScale": 2,
  "marks": [
    { "type": "rectangle", "x": 410, "y": 220, "w": 640, "h": 180, "color": "red" }
  ]
}
```

- `pixels` is the image's size when the drawing was made. A drawing whose `pixels` differ from the
  image's size no longer fits it. The image opens without it, with a log line, and the file stays on
  disk.
- `pointScale` is between 0.5 and 8.
- A mark's fields are the ones its type uses. `bend`, `wrap`, `agent` and `colorChosen` are left out
  at their defaults. `color` and a text's `size` are always written. A mark has no id in the file.
- The host writes the file atomically whenever it receives the drawing: after the 300 ms pause, at
  park, and when the app quits.
- A drawing with no marks has no file.
- Builds from different worktrees share this folder. A file whose `version` is newer than the build
  knows is left alone: the image opens without it, and the build never writes over it.
- Everything read from a file is checked with the same validator as agents' marks. Numbers must be
  finite, types and colours known, a text's `size` at most 1,000 pt, and a text at most 2,000
  characters and 100,000 bytes. A mark that fails is dropped, with a log line. A mark that no longer
  fits inside the image is moved in, with a log line. A file that does not parse is renamed to
  `<id>.json.invalid` at launch, with a log line. If a file stops parsing while the app runs, its
  image opens with no drawing and a log line says so. The file stays where it is until the next
  launch. Nothing in a drawing file can crash the app.

### Style

- Every stroke is 3.5 pt wide and solid, with round caps and joins. Shapes have no fill.
- A mark is drawn in one of five colours:

| Id | Colour | Order in the colour pass |
|---|---|---|
| `red` | `#e03131` | 1, and the colour a new mark starts in |
| `yellow` | `#ffc034` | 2 |
| `light-blue` | `#4dabf7` | 3 |
| `white` | `#f3f3f3` | 4 |
| `violet` | `#ae3ec9` | 5 |

The ids are the ones agents name in `marks=`. The toolbar has no palette. The colour pass picks the
colour.

### Agents' marks

`add?marks=` keeps its format, described in [commands.md](commands.md). Every number is a fraction
of the image. The fractions become px when the marks arrive. A reply's marks take the same path.

## 2. Look

| What | How it looks |
|---|---|
| Stroke | 3.5 pt, centred on the outline, with round caps and joins |
| Rectangle | A closed path with sharp corners |
| Ellipse | Inscribed in its frame |
| Arrow body | A straight line, or a circular arc through both ends and the bend point |
| Arrowhead | A filled triangle at the tip, per Decision 18 |
| Text | SF Pro Rounded at 24 pt, left-aligned, in the mark's colour. Weight and line height are tuned in the tweaks panel, starting at Medium and 1.35 times the size. |
| Text outline | Near-black `hsl(240 5% 6.5%)`, 1 pt outside the letters, on screen and in every rendering |
| Selection outline | A 1.5 screen pt line in `#3182ed` over a light edge, so it shows on blue and dark screenshots. The two together are `ui.selectionOutlineWidth` wide, 3.5 screen pt by default. It runs outside the mark's ink, so the mark's colour shows. The frame around several selected marks uses the same line. |
| Hover | Lighter than the selection outline, so the two can be told apart |
| Resize handles | 8 screen pt squares with a near-black fill and a 1.5 screen pt blue stroke, at the four corners of the selection outline |
| Arrow dots | Circles of radius 4 screen pt, white fill, 1.5 screen pt blue stroke. A hovered dot gets a 12 screen pt halo, blue at 20% opacity. |
| Brush | A rectangle with a 1 screen pt stroke, grey at 25% opacity, over a grey fill at 10% |
| Caret while typing | Near-white, whatever the text's colour |
| Selected text while typing | Blue background, white letters, no outline |
| Cursors | The system's: a crosshair while drawing, the arrow in Select, resize cursors on handles, an open hand on arrow dots, a closed hand while moving |
| Confirmation | A small dark capsule at the bottom centre of the frame, over the picture. It stays up for `ui.toastSeconds` and takes no clicks. |
| Behind the image | `#1a1a1a`, so a screenshot's transparent pixels are never see-through: in the editor, on a card and in flight |

Marks, text and the outline scale with the zoom. Handles, selection and hover outlines, dots, the
brush and hit areas stay the same size on screen. Each step of a zoom moves both in the same frame.

## 3. Tools

### Choosing a tool

| Trigger | Result |
|---|---|
| V, R, A, T, with or without Shift, while not typing | Select, Rectangle, Arrow, Text |
| Any other letter while not typing | Nothing |
| The toolbar's buttons | The same four tools |
| A new screenshot opens | Rectangle |
| A screenshot with a drawing opens | Select, with the newest mark the person drew selected. An agent's mark is never the one picked. |
| A mark is finished | The tool stays, and the new mark is selected, per Decision 1 |
| A right-click | Nothing |

The editor reports the active tool to the host whenever it changes. The toolbar shows it.

### A drawing tool over an existing mark

Per Decision 1, Rectangle, Arrow and Text act on existing marks the way Select does, and draw
everywhere else. The cursor and the hover outline show which will happen before the press:

| Pointer over | Cursor | A press |
|---|---|---|
| Empty space, or the empty inside of a rectangle or ellipse, selected or not | Crosshair | Draws with the tool. A click that draws nothing clears the selection, as in Select. |
| A mark, by the hit rules in section 4 | The arrow, and the hover outline on the mark | Selects the mark. A drag moves it. Shift adds it to the selection. The tool stays. |
| A selected mark's resize handle | That handle's resize cursor | Resizes the mark |
| A selected arrow's dot | The open hand | Drags the dot |
| A text, with the Text tool | The I-beam | Edits the text, with the caret at the click |

- The empty inside of a selected rectangle draws, so a second box can go inside the one just drawn.
  In Select, the same press would move the rectangle.
- An arrow cannot start on a text box, because a press there selects the text. To draw from a note,
  start just outside its box.

### Rectangle

| Trigger | Result |
|---|---|
| Press, then move more than 4 screen pt | A rectangle spans from the press point to the pointer, exactly |
| Drag to the left or upward | The rectangle lies on that side of the press point |
| Shift held during the drag | A square. Its side is the larger of the drag's width and height, in the pointer's quadrant. |
| Option held during the drag | Centred on the press point, twice the drag in each direction |
| Shift and Option | A centred square |
| A modifier pressed or released mid-drag | The rectangle updates at once, without a move |
| Release | The rectangle is created and selected. Creating it is one undo step. |
| Release with either side under 4 screen pt | Nothing is created |
| Click without a drag | Nothing is created, per Decision 2 |
| Pointer beyond the image | The rectangle stops at the image's edge |
| Esc during the drag | The rectangle is removed, and the editor stays open |
| A tool key during the drag | The rectangle is removed, and the new tool is active |
| Cmd+Z during the drag | The rectangle is removed. Nothing else is undone. |

### Arrow

| Trigger | Result |
|---|---|
| Press, then move more than 4 screen pt | An arrow runs from the press point to the pointer, with its head at the pointer |
| Click without a drag | Nothing is created. A click on empty space clears the selection, as with every tool. |
| Shift held while dragging the end | The angle from the start snaps to 15° steps. The length follows the pointer. |
| Release | The arrow is created and selected. One undo step. |
| Release within 8 screen pt of the start | Nothing is created |
| Pointer beyond the image | The end stops at the image's edge |
| Esc during the drag | The arrow is removed, and the editor stays open |
| A tool key during the drag | The arrow is removed, and the new tool is active |
| Cmd+Z during the drag | The arrow is removed. Nothing else is undone. |

### Text

| Trigger | Result |
|---|---|
| Click | A text mark starts at the click, and typing begins at once. The click is the left end of the first line and its vertical centre. |
| Press, wait 150 ms, then drag more than 24 screen pt sideways | A text mark whose wrap width is the drag's width. Vertical movement is ignored. |
| Click on an existing text | That text is edited, with the caret at the click |
| Typing ends with no text | The text mark is removed. Spaces and empty lines count as no text. |
| Esc with the Text tool active and nothing being typed | The editor closes |

Typing itself is in section 5.

### Ellipse

There is no ellipse tool. Ellipses come from agents. An ellipse is selected, moved, resized,
nudged, duplicated and deleted like a rectangle. It is hit on its outline.

## 4. Select

### What a press hits

Hover, press and release use one rule:

| Mark | Hit when the pointer is |
|---|---|
| Rectangle, ellipse, arrow | Within the hit band of the stroke's centre line. The band is the stroke's half-width on screen plus 4 screen pt. |
| Text | Anywhere inside its box |
| A selected rectangle or ellipse | Anywhere inside it, or within its band |
| Any selected mark's handles | Within the handle's hit area, which beats every mark |

- When several marks are hit, the one whose stroke is closest wins. A text box beats strokes under
  it.
- The empty inside of an unselected rectangle is not a hit. A press there starts a brush, and the
  Rectangle tool can draw a box inside a box.

### Hover

- The mark under the pointer gets the hover outline in Select, with a drawing tool per section 3,
  and while a text is being typed.
- A hovered handle changes the cursor.
- In Select, the cursor stays the arrow over a mark. A drawing tool changes it, per section 3.

### Selecting

| Trigger | Result |
|---|---|
| Press on a mark | It alone is selected, on the press |
| Shift+press on an unselected mark | It is added, on the press |
| Shift+click or Cmd+click on a selected mark | It is removed, on release |
| Press on empty space | The selection clears on the press |
| Drag from empty space | A brush. Marks whose outline it crosses, or that lie wholly inside it, are selected as it moves. A brush wholly inside a hollow rectangle does not select the rectangle. A brush inside a text box selects the text. |
| Shift held during a brush | The brush adds to the selection from before it started |
| Esc during a brush | The selection from before the brush comes back, and the editor stays open |
| Cmd+A | Every mark |
| Esc with a selection and no gesture | The editor closes |
| Tab, Shift+Tab | The next or previous mark, in reading order |

### Moving

| Trigger | Result |
|---|---|
| Drag a selected mark, or press a mark and drag, past 4 screen pt | The selection follows the pointer. One undo step. |
| Drag inside the frame of several selected marks | All of them move |
| Click inside the frame of several selected marks, on empty space | The selection clears |
| Shift held while moving | Locked to the axis the pointer has moved further along. Re-chosen on every move. |
| Option at the press, or pressed mid-drag | Copies move and the originals stay. Releasing Option mid-drag removes the copies. |
| Esc while moving | The marks go back to where they started, and the editor stays open |
| A mark moved past the image | It stops at the image's edge. Several marks stop together, so their arrangement holds. |
| A text with no wrap width moved to the right | It stops at the right margin, so its lines keep their breaks |
| Moving near the frame's edge while zoomed in | The view does not scroll |

### Resizing

| Trigger | Result |
|---|---|
| A single rectangle or ellipse is selected | A frame around its ink, four corner squares, and invisible edge handles that change the cursor |
| Corner handle hit area | A 13.5 screen pt square centred on the corner |
| Edge handle hit area | A 9 screen pt strip along the whole side |
| A mark under 16 screen pt a side | All four corners, with hit areas outside the mark |
| A handle at the image's edge | Its hit area is moved inside the image, where the window ends |
| Drag a corner | Both sides change. The opposite corner stays. |
| Drag an edge | One side changes |
| Shift | Keeps the proportions |
| Option | Resizes about the centre |
| Dragging past the opposite side | The mark flips to that side |
| Dragging past the image | The dragged side stops at the image's edge |
| A single text: drag a left or right edge | Sets the wrap width. The text wraps and its height follows. The top stays. |
| A single text: drag a corner, or the top or bottom edge | Scales the whole text, font included |
| Esc while resizing | Back to the size at the start, and the editor stays open |

### A selected arrow

| Trigger | Result |
|---|---|
| Select an arrow on its own | No frame and no corners. The outline on the body and head, a dot at each end, and a dot in the middle. With other marks selected too, it has no dots. |
| Arrow dot hit area | A circle of radius 12 screen pt. The end dots beat the middle dot. |
| Drag an end dot | That end follows the pointer. Shift snaps the angle from the other end to 15° steps. |
| Drag the middle dot | The arrow curves. The bend is the pointer's distance from the line between the ends, measured on the perpendicular through its middle. No snapping. |
| The middle dot on a short arrow | Shown. It sits beside the line, clear of the end dots. |
| The dots while a dot is dragged | Stay visible |
| Option+drag an end dot | A copy of the arrow moves with the pointer, as Option-drag does anywhere |
| A curved arrow's arc | Stays inside the image. The bend stops where the arc would cross an edge. |

### Keyboard on a selection

| Key | Result |
|---|---|
| Arrow keys | Move 1 pt. Two keys together move diagonally. |
| Shift+Arrow, with either Shift key | Move 10 pt |
| Holding an arrow key | Repeats. The whole hold is one undo step. |
| Arrow keys right after the editor opens | Work at once, with no click first |
| Nudging past the image | Stops at the edge |
| Delete, Backspace | Removes the selection. One undo step. |
| Cmd+D | Copies placed 10 pt right and down, kept inside the image, and selected |

### Double-click

The double-click interval is the system's setting, for editing and for zoom.

| Where | Result |
|---|---|
| A text, in Select | Typing starts with all its text selected |
| A selected text, single click inside it | Typing starts with the caret at the click |
| Empty space or the screenshot, in Select | Smart zoom: twice as close at that point, or back to fit from anywhere closer |
| A rectangle, ellipse or arrow | Nothing |
| A double-click that starts on empty space | The first click clears the selection |

## 5. Typing text

### Starting and ending

| Trigger | Result |
|---|---|
| Text tool click or drag | Typing starts in the new text |
| Double-click a text | Typing starts, all text selected |
| Click a selected text | Typing starts, caret at the click |
| Shift+Return or Option+Return with one text selected | Typing starts, all text selected |
| While typing, click another text | Typing moves there, caret at the click |
| While typing, click anywhere else | Typing ends, and the click acts as a normal click |
| Return | Typing ends. The text stays selected. |
| Cmd+Return | Typing ends, then Done |
| Esc | Typing ends and the text is kept. A second Esc closes the editor. |
| A toolbar tool button | Typing ends |
| Done in the toolbar | The typed text is in the PNG |
| Send | Typing ends first, then the drawing is rendered |
| The host parks the drawing while text is being typed | Typing ends first, so an empty text is removed |

### Keys while typing

| Key | Result |
|---|---|
| Letters, digits, punctuation, Space | Typed. V, R, A and T do not switch tools. |
| Shift+Return, Option+Return | A new line |
| Return during an input-method composition, such as Japanese | Confirms the composition, and typing continues |
| Tab | A tab at the caret |
| Arrow keys, with Shift, Option or Cmd | Move the caret and extend the selection. They never move the mark. |
| Delete, Option+Delete, Cmd+Delete | Delete characters, words, lines. Never the mark. |
| Cmd+A | All the text in this mark |
| Cmd+Z, Shift+Cmd+Z | Undo and redo typing within this session. At the session's start, Cmd+Z does nothing. |
| Cmd+C, Cmd+X, Cmd+V | The text clipboard. Paste inserts plain text and keeps its lines as pasted. |
| Cmd+B, Cmd+I, Cmd+U and other formatting keys | Nothing. The text is plain. |
| Cmd+Plus, Cmd+Minus, Cmd+0 | The host's zoom |

- Notes on screenshots often hold code and names. So there is no spell-check, no autocorrect, and no
  automatic replacement of quotes, dashes, links or text shortcuts. What is typed is what is drawn.

### How a text grows

- A text wraps where its right edge would pass the image's right edge, less a margin of 2% of the
  image's width. Agents' texts use the same margin.
- A text that starts with less than 15% of the image's width to its right moves left as it grows,
  instead of wrapping into a narrow column.
- When the text's bottom would pass the image's bottom, the text moves up.
- A text wider or taller than the whole image keeps its start showing.
- The caret stays in view while typing.
- Dragging a text's side edge sets a wrap width. That width is also held inside the image.

### Undo around typing

- Creating a text and its first typing session are one undo step.
- Each later typing session is one undo step, which puts back the text as it was before.
- A session that changes nothing adds no step.

## 6. Keys while not typing

Keys that act on a selection are in section 4. The rest:

| Key | Result |
|---|---|
| Esc | During a drag, brush, move or resize, cancels it. Otherwise closes the editor. |
| Return, Cmd+Return | Done |
| Cmd+Z | Undoes one step |
| Shift+Cmd+Z | Redoes one step |
| Cmd+Plus, Cmd+Minus, Cmd+0 | The host's zoom: in, out, back to fit |
| Cmd+C, Cmd+X, Cmd+V | Section 8 |
| Plain wheel or two-finger scroll | Pans a zoomed-in image |
| Cmd or Ctrl with a wheel or two-finger scroll | The host's zoom |
| Any other key | Nothing |

## 7. Undo and redo

- One owner handles Cmd+Z, Shift+Cmd+Z and any Undo or Redo menu item.
- Each step is one thing the person did:
  - creating a mark;
  - moving, resizing or bending;
  - one nudge press, including its repeats;
  - duplicating;
  - deleting;
  - pasting;
  - cutting;
  - one typing session;
  - agents' marks added to the open drawing.
- Selecting is never a step. Undo and redo put back the selection that belonged to the step.
- Cmd+Z during a drag cancels the drag and undoes nothing more.
- The colour pass is never a step. After an undo, the next pass colours the mark for where it is.
- History starts empty each time a screenshot opens.

## 8. Clipboard, paste and drop

Per Decision 10, Cmd+C copies what is selected, and the whole drawing when nothing is:

| Action | Result |
|---|---|
| Cmd+C with nothing selected | The drawing as a PNG, the same as Done's, and the `-annotated.png` beside the screenshot. The editor stays open. With no marks, the original file. |
| Cmd+C with marks selected | The marks. Any texts among them also go on the clipboard as plain text, so pasting into another app gives their words. |
| Cmd+X with marks selected | Copies them as Cmd+C does, then deletes them. One undo step. |
| Cmd+X with nothing selected | Nothing |
| Cmd+V with copied marks | Pastes them, selected, as one undo step. Where they land is below. |
| Cmd+V with text | A text mark at the pointer, or at the image's centre when the pointer is outside it. It follows the growth rules in section 5. |
| Cmd+V with an image or a file | Nothing is added. The editor says "Images can't be pasted here". |
| Cmd+V with anything else | Nothing is added. The editor says "Only marks and text can be pasted here". |
| A file dropped on the editor | The same as Cmd+V with an image |
| A URL on the clipboard | Pasted as text. Nothing is fetched. |
| Cmd+C, Cmd+X or Cmd+V while typing | The text clipboard, per section 5 |

When the clipboard holds several kinds, Cmd+V reads them in this order: copied marks, a file, text,
a URL, an image. A file comes before text because Finder puts a copied file's name beside it as
text, and that name must not become a text mark.

Copied marks:

- They go on the clipboard in a type of Vignette's own. It holds the marks as the drawing file does,
  with the source drawing's point scale.
- Any app can write that type, so a paste checks the marks with the same validator as a file.
- Pasted into the same screenshot while the originals are still there, they land 10 pt right and
  down, like Cmd+D. Each further paste steps another 10 pt.
- Anywhere else, including another screenshot or after a cut, they land where the originals were.
- Positions and sizes carry over in pt, so a mark keeps its look on a screenshot of another scale.
- Either way they are kept inside the image.
- A pasted mark keeps the original's fields. The colour pass colours it for where it lands, unless an
  agent named its colour.

A mark is selected right after it is drawn, and on reopen the newest mark is selected. So Cmd+C at
those moments copies that mark, not the drawing. The rule stays, because the visible selection
always says what Cmd+C will copy. Two things keep the drawing easy to copy:

- A click on empty space clears the selection, whatever tool is active. So copying the whole drawing
  is always one click and Cmd+C away.
- Every copy and cut shows a short confirmation of what went on the clipboard: "Copied drawing",
  "Copied 1 mark", "Copied 2 marks" or "Cut 2 marks". One key does two different things, and the
  clipboard itself shows nothing.

Return still copies the drawing and closes the editor. It stays the main way to share.

## 9. Around the editor

### Opening

- An image opens fitted to the annotator's frame, with its drawing.
- The tool and the selection follow section 3.
- The editor opens when the card starts its flight, before the image is decoded, so it has the keys
  from the first moment. The image appears when its decode arrives.
- A press on the card while it flies in draws, as a press in the editor would. The stroke starts at
  the point of the picture that was under the pointer, then follows the pointer. It shows when the
  card lands.
- A press on the text being typed, made while the card is still flying, goes to the text. It places
  the caret, a drag selects, a double-click selects a word and a triple-click a paragraph, and Shift
  extends the selection. Such a press cannot drag selected text to move it.
- If the card turns back while the button is down, after Esc or another image opening, that press
  draws nothing.
- A second click where the card was, within a double-click's interval of the click that opened it,
  does nothing. Opening narrows the stack and can slide another card into the slot, so the second click
  would otherwise reach the app behind or open that other card. Opening with Return or a URL has no
  first click, so nothing is swallowed.

### The toolbar

- The native toolbar shows the four tools, then Send and Done.
- For each tool, the editor supplies an id, a label, a key and an SF Symbol:

| Tool | Key | SF Symbol |
|---|---|---|
| Select | V | `cursorarrow` |
| Rectangle | R | `rectangle` |
| Arrow | A | `arrow.up.right` |
| Text | T | `textformat` |

- The editor reports the active tool.
- The host can set the tool.

### Handing the drawing to the host

- The editor hands the drawing to the host 300 ms after the last change, but not while the button is
  held.
- **Park.** The host parks the drawing for Esc, a swap, or a click outside. The editor hands it back
  at once, per Decision 14. Typing ends first, per section 5. A drag in progress ends as if the
  button were released, so what is drawn is kept.
- A drawing with no marks removes its file.
- The editor never hides itself. It asks the host to close, and the host's transition reducer
  decides.

### Rendering

| Output | What it is |
|---|---|
| Done | The screenshot with its marks, at the screenshot's exact pixel size, in its colour profile and with its DPI. With no marks, the host copies the original file and writes nothing. |
| Send | The same rendering. The editor stays open while it renders. Once the request is stored, the card goes home without a copied mark, and a queue opens its next card. A failed rendering sends nothing, and the drawing stays as it is. |
| Copy Drawing | The same rendering for each selected card, without opening them |

- Renderings run off the main thread, one at a time, drawing straight at the output size. The
  largest capture on this Mac is 3102 by 6780 px, about 85 MB as a bitmap.
- Done puts a promised PNG on the clipboard at once and sends the card home. The rendering fills the
  promise, and a paste that comes before it finishes waits for it, for up to 5 seconds. The
  `-annotated.png` file is written when the rendering finishes. Done's rendering goes ahead of any
  that has not started.
- A rendering that fails answers `unreadable-image` or `write-failed`. After Done, it also takes the
  clipboard and the card's copied mark back, and says "Could not copy the drawing; see the log".

### Cards and flights

- A card whose screenshot has a drawing draws the marks over its thumbnail, with the editor's
  renderer, at the card's size. A card in flight does the same, and so does the image of a card
  dragged out of the stack. Per Decision 16, no preview images are stored.
- Cards, flights, stitches and dragged cards draw in the live text style and arrowhead, as the
  editor does.
- A press on a card flying anywhere but into the editor does nothing, up to its release. That is a
  card flying home, one leaving with the stack, or the pieces of a stitch. The card takes clicks
  again once it lands.
- A press on a flying card's shadow, or beside the card, reaches whatever is under it. Right-click
  and scroll on a flying card do nothing.
- [flight-press-2026-09-23.md](flight-press-2026-09-23.md) has the measurements, and two cases in
  which a press can still pass through a flying card.

### The colour pass

A mark is drawn in red unless red is too close to what it covers:

| Step | Rule |
|---|---|
| When | 300 ms after the last change, never while the button is held. A text's colour is picked when typing ends. Also before every park, Done, Send and Cmd+C of the drawing. |
| Which marks | Every mark added or changed since the last pass, except marks whose colour an agent named. Opening a drawing never runs the pass. |
| The sample | The screenshot, scaled to 320 px on its long side |
| A rectangle or ellipse | A 20 by 20 grid over its frame. Only points within 15% of the frame's shorter side from an edge count. |
| An arrow | 41 points along its drawn body, arc included, plus one on each side. The sides are 1% of the sample's long side away. |
| A text | A 20 by 20 grid over each of its lines |
| The measure | CIE76 distance in CIELAB between the colour and each sampled pixel. The distance used is the one at the 10th percentile, so a few stray pixels do not decide. |
| The pick | The first colour in order whose distance is at least 55. If none is, the furthest one. |
| History | Outside undo history |

### Agents' marks

- `add?marks=` adds to a drawing without opening the editor. The marks become px, the colour pass
  runs, and the host writes the file. The command answers once the file is written, and the card
  appears after that.
- If the screenshot already has a drawing, the marks are added to it.
- If the screenshot is open in the editor, the marks join the open drawing as one undo step. Adding
  never waits for the editor and is never refused because of it.
- Every mark is moved inside the image. One that has nothing inside it is dropped, with a log line.
- A mark that names a colour keeps it. Other marks go through the colour pass.
- Agents' marks carry `agent`, so reopening never selects one.
- An agent's text is sized and fitted like this:
  - Its size is 2.2% of the image's width.
  - It wraps in its `w` when it has one, as given. Without `w`, it wraps in the room to the right
    edge less a 2% margin, and never in less than 15% of the width.
  - It is widened until it fits the image's height, in up to four passes.
  - It is then moved inside the image.
  - A text that still does not fit is cut at the edge and named in one
    `[marks] text too long for <name>` log line.

  [pushed-text-2026-09-19.md](pushed-text-2026-09-19.md) has the numbers.

### Zoom

- The host owns the zoom: pinch, Cmd+scroll or Ctrl+scroll, Cmd+Plus, Cmd+Minus, Cmd+0, and the
  two-finger double tap. A plain scroll pans a zoomed-in image.
- A double-click with Select on empty space asks the host for smart zoom.
- The zoom keys and the double-click do nothing until the card has landed, a double-click on the
  flying card included.
- The editor draws at whatever zoom the host sets, per Decision 17. The frame and the drawing move in
  the same frame.

### Inspecting and driving

- `[state]` has an `editor` section: the tool, each mark's type, frame in px and whether an agent
  made it, the selection, whether text is being typed, and the undo and redo depth. It never holds a
  text's words.
- `[annotate] loaded <ms>ms <name>` reports when the editor has the image.

### Failures

- The editor runs in the app's process, so a crash in it would take down the stack and the folder
  watcher too. Anything the editor cannot handle is logged and repaired instead. An invalid mark is
  dropped. An input the editor does not expect in the current gesture cancels the gesture.

### VoiceOver

- The canvas is named for the screenshot it shows. Tool changes and the selected mark are announced.

## 10. Later

- **Sizes from the capturing display.** Decision 8 takes the point scale from the annotator's
  display. Recording the capturing display's scale when the file arrives would be exact on a Mac with
  displays of different scales.
- **Attaching arrows.** Revisit if people expect an arrow to follow the box it points at, per
  Decision 3. The tip would still land exactly where the pointer was released.
- **Snapping.** Revisit per Decision 11.
