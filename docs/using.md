# Using Vignette

## The stack

Press Cmd+Shift+6 to show your recent screenshots in a column in the corner. It holds 30 by
default. The stack takes keyboard focus, and your app keeps its own focus. Opening the annotator
does activate Vignette, and closing it hands focus back to the app you came from.

The newest card has focus as soon as the stack is up, and focus follows the mouse. Move onto a
card and keys act on that card.

The column runs down to the bottom of the screen. Where the Dock is under it, the bottom card
rests above the Dock, and a card scrolled down past it fades out at the Dock's top edge. A Dock
the column does not reach over, on a side, or hidden, costs the stack nothing.

Opening a card in the annotator narrows the stack to make room for it, down to half its width.
The cards keep their corner and only change size, and they come back when the annotator closes.
The annotator never grows into the width the stack keeps, however far you zoom in.

## Selecting

Hover a card for a selection circle. Click the circle, or drag from it down the column, to
select. Once you are selecting, clicking a card toggles it.

Drag into the band at the top or bottom of the column and the column scrolls on its own, faster
the closer to the edge you hold. It selects the cards that come past, until you leave the band,
stop at the end of the column, or let go.

A selected circle shows the card's place in the selection, counting in the order you picked them.
Every action receives the cards in that order. Picking a card again puts it last. Cmd+A uses the
column's order instead: oldest first.

Keyboard:

- Arrows move focus.
- Shift+arrow extends the selection in the direction you travel. Turning back drops the card it
  added last.
- Space toggles the card.
- Cmd+A selects all.
- Esc clears the selection, then dismisses the stack.

Space over one card after another builds a selection without clicking. A key runs on the
selection when there is one, else on the focused card.

## Actions on a selection

The selected cards get a control strip to their left: copy, draw, stitch, delete. It stays
centered between the topmost and the bottommost selected card, and follows the selection. Put the
cursor on it and it grows to the left to name each button. The row under the cursor is still the
button you press. Selecting with the keyboard, by Shift+arrow, Space or Cmd+A, brings the names
out too, each with its shortcut beside it, and the mouse takes over as soon as it moves onto a
card or the strip. While you are annotating the strip hides. The cards stay selected and it comes
back when you are done.

- Cmd+C copies the selection as files, as paths in text, and as the first image's pixels. Chat
  apps attach all of them, and terminals paste the paths.
- Option+Cmd+C copies only the paths.
- Cmd+Shift+C copies with the drawing rendered in.
- Cmd+Delete trashes the selection.
- Return opens the card to draw on.

Cmd+S stitches the selection into one image with numbered badges, saved next to the originals and
copied. Two or three pieces stack, and more go in a grid. Each badge is the number the card's
circle showed. The selected cards fly together into the new card, which takes their place at the
bottom of the stack, or opens in the annotator when Draw on New Screenshots is on.

Drag a card out to drop it as a file on a chat window, Finder, or a terminal. A selected card
drags the whole selection.

## The annotator

Press Return, or click Draw in the strip, to open a card and draw on it.

Return on several selected cards opens them one after another, in the order you picked them. Each
Done sends that card home and opens the next. They stay selected the whole time, so Cmd+C or
Cmd+S afterwards still takes all of them. Selecting another card while one is open adds it to the
end of that run, and deselecting it takes it out. Esc, or closing the stack, drops the rest of
the queue.

A card on its way to the annotator can be turned around. In the stack, press Esc or click another
card, and it goes straight home from wherever it is. The editor never appears, and a drawing you
parked earlier stays as it was.

Pinch, Cmd+scroll, or Cmd+plus and Cmd+minus zoom the image. Cmd+0 fits it again. The window
grows with the image and does not keep its shape. Each side widens or heightens until it reaches
the edge of the space the annotator has. A two-finger double tap, or a double-click with the
selection tool, zooms in twice on the point you are on, and comes home to the fitted size from
anywhere above it. A double-click on a mark is the editor's, not the zoom's.

A mark is drawn in red unless red is what it sits on. Then it is drawn in yellow, light blue,
white or violet, whichever is far enough from the pixels under it. The colour is measured when
you draw the mark and again when you let go of it.

Reopening a card you have already drawn on starts on the selection tool with the mark you drew
last already picked up, so a drag or Delete acts on it without a click first. A fresh image
starts on the rectangle tool.

A card whose drawing you parked with Esc or a swap shows the drawing in its thumbnail. Reopen the
card and the drawing is back. Copy Drawing renders it without opening the editor.

## The shortcut

The shortcut is either a key combination, which needs no permission, or `double-rshift`, a double
tap of right Shift. `double-rshift` needs Vignette trusted for Accessibility, under System
Settings → Privacy & Security → Accessibility; the app asks the first time. Hold the key, or the
second tap, and the newest screenshot lifts out of the stack into the annotator: capture,
tap-tap-hold, draw. The menu bar shows the same two commands, Show Recent Screenshots and Draw on
Last Screenshot, with the shortcut beside them. [Settings](settings.md) covers changing the
shortcut.

## Cards from an agent

A card with a purple badge was pushed in by an agent (`add?agent=<name>`), not captured. Hover it
to see which one. The name is stored on the file itself, so it survives a rename. This is
experimental.
