# Using Vignette

## Installing

Open the disk image and drag Vignette to Applications. If you open Vignette from the disk image
instead, it offers to move itself to Applications, reopens from there, and ejects the disk image.
If Applications already holds a newer Vignette, that copy opens instead.

The first launch opens a setup window, one step per page: a welcome, [the shortcut](#the-shortcut),
and your coding agents when Claude Code or Codex is installed. Open at login starts on, so Vignette
is running after a restart. The window adds the login item when you close it.

While Vignette runs, it replaces macOS's floating thumbnail with its own. Quitting Vignette turns
macOS's thumbnail back on.

If your screenshots save to the Desktop, Documents or Downloads, macOS asks once whether Vignette
may read that folder. The welcome page asks for it, with Allow…, and says why. If you answered
Don't Allow, the row says so, and its Allow… opens Privacy & Security → Files and Folders. Switch
Vignette on there, and it starts watching the folder without a relaunch. Settings → Screenshots
says so too, under Save to, and the menu bar menu starts with Allow Access to Your Screenshots….

Vignette watches the folder macOS saves screenshots to. Pick another in the Options menu of
Cmd+Shift+5, or with Save to in Settings → Screenshots, and both change to it. If Cmd+Shift+5 is
set to save to the Clipboard, Mail or Preview, no screenshot reaches the folder. The menu bar menu
then starts with Save Screenshots to a Folder, and setup and Settings → Screenshots offer Save to
Folder.

Report a Problem…, in the menu bar menu, opens a new GitHub issue with Vignette's version and
your Mac filled in. It also shows Vignette's log in Finder, with any Vignette crash reports, so you
can drag them onto the form. The log lists your screenshots' file names and folder paths.

Vignette checks for updates once a day. When one is ready, a dot appears on the menu bar icon and
the menu offers Update Available…. Nothing installs until you choose to.

With Show in menu bar off, in Settings → General, open Vignette again from Finder or Spotlight to
get back to Settings.

## After a screenshot

Take screenshots with Cmd+Shift+3, 4 or 5, as usual. Each new screenshot goes to the clipboard and
comes up as a card in the corner of the screen. This card is the lone thumbnail. It leaves after 5
seconds, unless the pointer is on it. Click it to draw on it. Hover it to show Copy in its
bottom-left corner and Delete in its bottom-right.

Take several in a row and their cards gather in the corner. Select one and the corner becomes the
recent stack.

The menu bar menu has two switches under After a Screenshot, and Settings → Screenshots has the
same two:

- Copy to Clipboard puts each new screenshot on the clipboard. It is on by default.
- Instant Draw opens each new screenshot in the annotator instead of showing its card. The image
  flies in from the part of the screen you captured. It is off by default.

Settings → Screenshots also sets how long the card stays, with Show the thumbnail for.

## The stack

Press the Vignette shortcut to show your recent screenshots in a column in the corner. This column
is the recent stack. It holds 30 cards, and How many to show in Settings → General changes that.
Press the shortcut again, or click outside the stack, to close it. The stack answers your keys and
the app you were in stays frontmost. Opening the annotator activates Vignette, and closing it hands
focus back.

Click a card to draw on it. Hover a card to show Copy and Delete in its bottom corners.

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

- Up and Down arrows move focus.
- Shift+arrow extends the selection in the direction you travel. Turning back drops the card it
  added last.
- Space toggles the card.
- Cmd+A selects all, and Cmd+Shift+A clears the selection.
- Esc clears the selection, then dismisses the stack.

Space over one card after another builds a selection without clicking. A shortcut runs on the
selection when there is one, and on the focused card otherwise.

## Actions on a selection

The selected cards get a selection strip to their left: Copy, Draw, Stitch, Delete. It stays
centered between the topmost and the bottommost selected card, and follows the selection. Each
button names itself and shows its shortcut for as long as anything is selected. The strip hides
while you are drawing. The cards stay selected and it comes back when you are done.

- Cmd+C copies the selection as files, as paths in text, and as the first image's pixels. Chat apps
  attach all of them, and terminals paste the paths.
- Option+Cmd+C copies only the paths.
- Cmd+Shift+C copies with the drawing rendered in.
- Cmd+Delete trashes the selection.
- Return opens the card to draw on.

Cmd+S stitches two or more selected cards into one image with numbered badges, saved next to
the originals and copied. Vignette picks the number of columns that keeps the pieces largest once an
AI model shrinks the image to read it. Each badge is the number the card's circle showed. The
selected cards fly together into the new card, which takes their place at the bottom of the stack,
or opens in the annotator when Instant Draw is on.

Drag a card out to drop it on a chat window, Finder, or a terminal. A card you drew on drops the
drawing, and any other card drops the screenshot. A selected card drags the whole selection.

## The annotator

Click a card, press Return, or click Draw in the strip to open a card and draw on it.

Return on several selected cards opens them one after another, in the order you picked them.
Copying or sending each one sends it home and opens the next. They stay selected the whole time,
so Cmd+C or Cmd+S afterwards still takes all of them. Selecting another card while one is open adds
it to the end of that run, and deselecting it takes it out. Esc, or closing the stack, drops the
rest of the queue.

A card on its way to the annotator can be turned around. Press Esc, or click another card in the
stack, and it goes straight home from wherever it is. Anything drawn on it is kept.

The editor has four tools: V selects, R draws rectangles, A arrows, and T text. A fresh image opens
on the rectangle tool. Reopening a card you have already drawn on opens on the selection tool with
the mark you drew last already selected, so a drag, an arrow key or Delete acts on it without a
click first. Return copies the drawing and sends the card home. Esc cancels a drag in progress, and
at rest closes the editor without copying. A card opened from the stack goes back to its place
there. A lone thumbnail leaves the screen, since there is nothing left to do with it; the
screenshot and its drawing are still in the recent stack. With Close after copying a drawing on, in
Settings → General, Return also closes the stack. [The drawing editor](editor.md) lists every key
and gesture.

When a coding agent session can take the drawing, the toolbar shows that session, with the agent's
logo and the project's folder, then a message field and Send. It starts on the session you were
last in, and a click on it picks another. Type in Add a message to send words with the drawing.
Cmd+Return sends, and so does Return in the message field. On a card an agent sent you, the toolbar
has the message field and Reply, and Return sends your drawing back to that session. After a send,
the card says where the drawing went and whether it arrived. A Claude Code session takes a drawing
through the Vignette plugin, in any terminal. A Codex thread needs the Codex app or its `codex`
command-line tool. [For agents](agents.md) covers installing the plugin.

Cmd+C with nothing selected copies the drawing, the same image Return copies, and leaves the editor
open. With marks selected it copies the marks, which paste into this image or another one.

Your marks are red and an agent's are indigo. Every mark has a thin white edge and a soft shadow, so
it shows on any screenshot. An agent's note becomes yours when you change its words.

Pinch, Cmd+scroll, or Cmd+plus and Cmd+minus zoom the image. Cmd+0 fits it again. A plain scroll
moves around a zoomed-in image. The window grows with the image: each side widens or heightens until
it reaches the edge of the space the annotator has. A two-finger double tap, or a double-click on
empty space with the selection tool, zooms in to twice the size on the point you are on. Zoomed in,
the same gesture returns to the fitted size. A double-click on a text edits it instead.

A card you drew on shows its drawing, however you left the editor. Reopen the card and the drawing
is back. Cmd+Shift+C copies it without opening the editor.

## The shortcut

The shortcut is either a double tap, of right Shift by default, or a key combination. Pick one
from the Shortcut menu in the setup window or in Settings → General. Key Combination…, at the
bottom, sets Cmd+Shift+2 and asks you to press the keys you want. It refuses Cmd with a single key,
the screenshot keys Cmd+Shift+3, 4 and 5, and the Control shortcuts macOS uses, and says why under
the box.

The double tap needs Vignette trusted for Accessibility, and a key combination needs no permission.
Allow… brings up macOS's request, and its Open System Settings button opens Privacy & Security →
Accessibility with Vignette listed. Switch it on, and the setup window comes back and waits for you
to press the keys once. Until the double tap has the permission, the menu bar menu starts with
Allow Accessibility for the Shortcut….

Hold the key, or the second tap, and the newest screenshot lifts out of the stack into the
annotator: capture, tap-tap-hold, draw. The menu bar shows the same two commands, Show Recent
Screenshots and Draw on Newest Screenshot, with the shortcut beside them. [Settings](settings.md)
covers changing it.

## Live ink

Live ink lets you draw straight on your screen, over any app, without taking a screenshot. Turn it
on in Settings → General, or with Live Ink in the menu bar menu.

Hold Control and Option and draw. The screen's edges glow while you hold the keys. A loop becomes
an ellipse round what you circled, and any other stroke becomes an arrow, in your red. To erase a
mark, click on it or inside its circle with the keys held. Clear Live Ink in the menu erases them all, and so does turning
live ink off.

Your marks stay at their place on the screen, on the Space you drew them on. They don't follow the
window under them, and they're gone when Vignette quits. Screenshots leave them out, and they step
out of sight while you take one, so Cmd+Shift+4 and Space pick the window under a mark. Menus, the Dock and floating windows cover
them until you hold the keys again.

While you hold the keys, a click draws instead of reaching the app under it. Let go and every click
works as usual. A shortcut that starts with Control and Option, such as a window manager's, still
works: pressing its key ends the drawing. Live ink doesn't draw while the stack or the annotator is
open.

Like the double tap, live ink needs Accessibility. Until it has it, the menu bar menu starts with
Allow Accessibility for Live Ink….

### Asking about your ink

When you let go of the keys after drawing, a note opens beside your ink. Type a question, or
nothing, and press Return: Claude looks at the window under your ink and answers on the screen. Its
reply appears beside your ink as it's written, and its own marks draw themselves on, in its colour,
pointing at what it means. Esc, or a click anywhere else, closes the note and keeps your ink.

Ask again with no new ink and it's a follow-up about the same thing. A new question replaces the
last answer, and Clear Live Ink starts over. Erase an answer's mark or note as you erase your own.

The note's target starts on Claude. Click it, or press the Down arrow, to send your ink to one of
your coding agent sessions instead: the picture goes as Send sends a drawing, and the session's
reply comes back as a card. A note on your ink says whether it went.

Claude answers through Claude Code, which must be installed and signed in, on your own Claude
account, without your settings, plugins or tools. It sees only the window under your ink. Asking
needs Screen Recording: turning live ink on asks for it, and until it's allowed the menu bar menu
starts with Allow Screen Recording for Live Ink….

## Screen recordings

A recording from Cmd+Shift+5 gets a card too, showing its first frame with its length in the
corner. Click it, or press Return, to open it in QuickTime Player, or in whichever app your Mac
opens movies with.

Copy, Copy Paths, and Delete work on recordings. Stitch takes a recording's first frame, the
picture its card shows. Draw and Copy Drawing work only on screenshots. With a recording in the
selection, Draw is greyed in the strip, and hovering it says why. Their shortcuts beep. When every
selected card is a recording, Draw becomes Open.

Cmd+C copies a recording as a file, which chat apps attach and terminals paste as its path. Draw on
Newest Screenshot and the held shortcut skip recordings and open the newest screenshot. Instant
Draw shows a new recording as a card in the corner.

## Cards from an agent

A card with a white tab in its top corner was pushed in by an agent (`add?agent=<name>`), not
captured. The tab names the agent and carries its logo. The name is stored on the file itself, so it
survives a rename. This is experimental.
