# The recent stack

Cmd+Shift+6 shows your recent screenshots in the corner (30 by default). The stack takes
keyboard focus without stealing your app's focus. Opening the annotator does activate Vignette,
and closing it hands focus back to the app you came from.

- Hover a card for a selection circle. Click it, or drag from it down the column, to select.
  In selection mode clicking a card toggles it. Drag into the band at the top or bottom of the
  column and it scrolls on its own, faster the closer to the edge you hold, selecting the cards
  that come past until you leave the band, stop at the end of the column, or let go.
- A selected circle carries the card's place in the selection, counting in the order you picked
  them. That is the order every action receives them; picking a card again puts it last. Cmd+A
  has nobody's order to follow, so it takes the column's: oldest first.
- The selected cards get a control strip to their left: copy, draw, stitch, delete.
  It stays centered between the topmost and the bottommost selected card, and follows the selection.
  Put the cursor on it and it grows to the left to name each button, so the names never cover a
  thumbnail. The row under the cursor is still the button you press. Selecting with the keyboard —
  Shift+arrow, Space, Cmd+A — brings the names out too, each with its shortcut beside it, and the
  mouse takes over as soon as it moves onto a card or the strip. While you are annotating, the
  strip steps out of the annotator's way; the cards stay selected and it comes back when you are done.
- The column runs down to the bottom of the screen. Where the Dock is under it, the bottom card
  rests above the Dock instead, and a card scrolled down past it fades out at the Dock's top edge.
  A Dock the column does not reach over, on a side, or hidden, costs the stack nothing.
- Opening a card in the annotator narrows the stack to make room for it, down to half its width.
  The cards keep their corner; only their size changes, and they come back when the annotator
  closes. The annotator never grows into the width the stack keeps, however far you zoom in.
- A card on its way to the annotator can be turned around. In the recent stack, Esc — or clicking
  another card — sends it straight home from wherever it is and the editor never appears. Nothing is
  lost: nobody could draw on an image that was never on screen, and a drawing you parked earlier
  stays as it was.
- Drag a card out to drop it as a file on a chat window, Finder, or a terminal. A selected card
  drags the whole selection.
- Cmd+C copies the selection as files, paths as text, and the first image's pixels, so chat apps
  attach all of them and terminals paste the paths. Option+Cmd+C copies only the paths.
- Cmd+S stitches the selection into one image with numbered badges, saved next to the originals
  and copied. Two or three pieces stack; more go in a grid, because a very tall image loses more of
  itself when a model resizes it to read it. Each badge is the number the card's circle showed. The
  selected cards fly together into the new card, which takes their place at the bottom of the
  stack, or opens in the annotator when Draw on New Captures is on.
- The newest card has the focus as soon as the stack is up, and the focus follows the mouse: move
  onto a card and keys act on that one. So Space over one card after another builds a selection
  without clicking, and Return opens the card the mouse is on. A key runs on the selection when
  there is one, else on the focused card.
- Arrows move focus, Shift extends in the direction you travel (turning back drops the card it
  added last), Space toggles, Cmd+A selects all, Return opens the card to draw on, Cmd+Shift+C
  copies with the drawing rendered in, Cmd+Delete trashes, Esc clears then dismisses.
- Return on several selected cards, or Draw in the strip, opens them one after another, in
  the order you picked them: each Done sends that card home and opens the next. They stay selected
  the whole time, so Cmd+C or Cmd+S afterwards still takes all of them. Selecting another card
  while one is open adds it to the end of that run, and deselecting it takes it out. Esc, or
  closing the stack, drops the rest of the queue.
- A card whose drawing you parked with Esc or a swap shows it in its thumbnail. That
  thumbnail is a preview PNG in `~/Library/Caches`; if macOS clears the folder, the next launch
  renders it again from the draft. Reopen the card and the drawing is back either way;
  Copy Drawing renders it without opening the editor.
- Reopening a card you have already drawn on starts on the selection tool with the mark you
  drew last already picked up, so a drag or Delete acts on it without a click first.
  A fresh image starts on the rectangle tool.
- Pinch, Cmd+scroll, or Cmd+plus and Cmd+minus zoom the image in the annotator; Cmd+0 fits it
  again. The window grows with the image and does not keep its shape: each side widens or
  heightens until it reaches the edge of the space the annotator has, so zooming into a tall
  narrow screenshot keeps the whole width of it in view until the window is as wide as the screen.
  A two-finger double tap, or a double-click with the selection tool, zooms in twice on the
  point you are on and comes home to the fitted size from anywhere above it. A double-click on a
  mark is the editor's, not the zoom's.
- A mark is drawn in red unless red is what it sits on. The editor measures the pixels under each
  mark, when you draw it and when you let go of it, and moves to yellow, light blue, white, or
  violet, whichever is far enough from them.
- A card with a purple badge was pushed in by an agent (`add?agent=<name>`), not captured. Hover
  it to see which one. The name is stored on the file itself, so it survives a rename.

The hotkey is either a key combination (no permission needed) or `double-rshift`, a double tap
of right Shift, which needs Vignette trusted for Accessibility (System Settings → Privacy &
Security → Accessibility); the app asks the first time. Hold the key, or the second tap, and the
newest screenshot lifts out of the stack into the annotator: capture, tap-tap-hold, draw. The
menu bar has the same command.
