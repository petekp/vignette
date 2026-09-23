# Using Vignette

## The stack

Press the Vignette shortcut to show your recent screenshots in a column in the corner. It holds 30
by default. The stack answers your keys and the app you were in stays frontmost. Opening the
annotator activates Vignette, and closing it hands focus back.

The newest card has focus as soon as the stack is up, and the focus follows the mouse: move onto a
card and the keys act on that card.

The column runs down to the bottom of the screen. Where the Dock is under it, the bottom card rests
above the Dock, and a card scrolled past it fades out at the Dock's top edge.

Opening a card in the annotator narrows the stack to make room, down to half its width. The cards
keep their right edge and shrink, and they come back when the annotator closes. However far you
zoom in, the annotator never grows into the width the stack keeps.

## Selecting

Hover a card and a selection circle appears. Click the circle, or drag from it down the column, to
select. Once you are selecting, clicking a card toggles it.

Drag into the band at the top or bottom of the column and the column scrolls on its own, faster the
closer to the edge you hold. It selects the cards that come past, until you leave the band, reach
the end of the column, or let go.

A selected card's circle shows its place in the selection, counting in the order you picked them.
Every action receives the cards in that order. Picking a card again puts it last. Cmd+A uses the
column's order instead: oldest first.

Keyboard:

- Arrows move focus.
- Shift+arrow extends the selection in the direction you travel. Turning back drops the card it
  added last.
- Space toggles the card.
- Cmd+A selects all.
- Esc clears the selection, then dismisses the stack.

Space over one card after another builds a selection without clicking. A shortcut runs on the
selection when there is one, and on the focused card otherwise.

## Actions on a selection

The selected cards get a control strip to their left: Copy, Draw, Stitch, Delete. It stays centered
between the topmost and the bottommost selected card, and follows the selection. Each button names
itself and shows its shortcut for as long as anything is selected. The strip hides while you are
annotating. The cards stay selected and it comes back when you are done.

- Cmd+C copies the selection as files, as paths in text, and as the first image's pixels. Chat apps
  attach all of them, and terminals paste the paths.
- Option+Cmd+C copies only the paths.
- Cmd+Shift+C copies with the drawing rendered in.
- Cmd+Delete trashes the selection.
- Return opens the card to draw on.

Cmd+S stitches two or more selected screenshots into one image with numbered badges, saved next to
the originals and copied. Two or three pieces stack, and more go in a grid. Each badge is the number
the card's circle showed. The selected cards fly together into the new card, which takes their place
at the bottom of the stack, or opens in the annotator when Draw on New Screenshots is on.

Drag a card out to drop it as a file on a chat window, Finder, or a terminal. A selected card drags
the whole selection.

## The annotator

Press Return, or click Draw in the strip, to open a card and draw on it.

Return on several selected cards opens them one after another, in the order you picked them. Each
Done sends that card home and opens the next. They stay selected the whole time, so Cmd+C or Cmd+S
afterwards still takes all of them. Selecting another card while one is open adds it to the end of
that run, and deselecting it takes it out. Esc, or closing the stack, drops the rest of the queue.

A card on its way to the annotator can be turned around. In the stack, press Esc or click another
card, and it goes straight home from wherever it is. Anything drawn on it is kept.

The editor has four tools: V selects, R draws rectangles, A arrows, and T text. A fresh image opens
on the rectangle tool. Reopening a card you have already drawn on opens on the selection tool with
the mark you drew last already selected, so a drag, an arrow key or Delete acts on it without a
click first. Return copies the drawing and sends the card home. Esc cancels a drag in progress, and
at rest closes the editor without copying. [The drawing editor](editor.md) lists every key and
gesture.

Cmd+C with nothing selected copies the drawing, the same image Return copies, and leaves the editor
open. With marks selected it copies the marks, which paste into this image or another one.

A mark is drawn in red unless red is what it sits on. Then it is drawn in yellow, light blue, white
or violet, whichever is far enough from the pixels under it. The colour is picked a moment after you
stop changing a mark, and for a text when you stop typing.

Pinch, Cmd+scroll, or Cmd+plus and Cmd+minus zoom the image. Cmd+0 fits it again. A plain scroll
moves around a zoomed-in image. The window grows with the image: each side widens or heightens until
it reaches the edge of the space the annotator has. A two-finger double tap, or a double-click on
empty space with the selection tool, zooms in twice on the point you are on, and comes home to the
fitted size from anywhere above it. A double-click on a text edits it instead.

A card whose drawing you parked with Esc or a swap shows the drawing in its thumbnail. Reopen the
card and the drawing is back. Copy Drawing renders it without opening the editor.

## The shortcut

The shortcut is either a double tap of right Shift, which is the default, or a key combination.
The first launch opens a window to choose, and that window is the only thing that asks for
permission: the double tap needs Vignette trusted for Accessibility, under System Settings →
Privacy & Security → Accessibility. A key combination needs none. The window says when the grant
lands and waits for you to press the keys once.

Hold the key, or the second tap, and the newest screenshot lifts out of the stack into the
annotator: capture, tap-tap-hold, draw. The menu bar shows the same two commands, Show Recent
Screenshots and Draw on Last Screenshot, with the shortcut beside them. [Settings](settings.md)
covers changing it.

## Screen recordings

A recording from Cmd+Shift+5 gets a card too, showing its first frame with its length in the
corner. Click it, or press Return, to open it in QuickTime Player, or in whichever app your Mac
opens movies with.

Copy, Copy Paths, and Delete work on recordings. Draw, Copy Drawing, and Stitch work only on
screenshots. With a recording in the selection, Draw and Stitch are greyed in the strip, and
hovering one says why. Their shortcuts beep. When every selected card is a recording, Draw becomes
Open.

Cmd+C copies a recording as a file, which chat apps attach and terminals paste as its path. Draw on
Last Screenshot and the held shortcut skip recordings and open the newest screenshot. Draw on New
Screenshots leaves a new recording in the stack.

## Cards from an agent

A card with a white tab in its top corner was pushed in by an agent (`add?agent=<name>`), not
captured. The tab names the agent and carries its logo. The name is stored on the file itself, so it
survives a rename. This is experimental.
