# The trailer on a desktop (2026-09-26)

Pete watched the second cut and asked for three things: motion and choreography that are much
more refined, a history that does not repeat one picture, and the game shown on a desktop beside
a terminal and a browser instead of full screen. This plan does all three. The desktop is also what
the storyboard in `docs/trailer-2026-09-24.md` drew: Claude Code on the left, the game in a
browser on the right.

## Why the second cut looks stiff

- **The camera has nowhere to go.** The game fills the screen, so every move is a zoom into the
  same flat picture. It reads as a crop changing, not a camera.
- **Every move has the same shape.** Each is a symmetric ease of about a second between two
  framings, followed by a hold where nothing moves. The rhythm is mechanical.
- **The camera reacts instead of leading.** It waits for the flight to land, then moves. A directed
  shot arrives just before the action.
- **The hand keeps a metronome.** Every glide uses one curve whatever its length, and every pause
  is a fixed number.

## The desktop

- **A wallpaper,** drawn by the stage's own window at the desktop's level, so neither your
  wallpaper nor your desktop icons show. The Dock stays hidden during a take. The camera stays below
  the menu bar.
- **A terminal on the left,** about 40% of the width: Ghostty, attached to a herdr session named
  `vignette-trailer`. herdr's named sessions have their own server, so the stage copy of Vignette
  talks to that session through a wrapper for `herdr --session vignette-trailer` and never lists
  your panes. Real Claude Code runs in it.
- **A browser on the right,** about 60%, with the game at 16:10. Chrome with a fresh profile made
  for the take, so none of your tabs, bookmarks or extensions show. Safari would look more native
  but shows your profile.
- **Vignette** works over both, as it would on any desktop: the thumbnail in the corner, the
  editor over the middle of the screen.

## The history

The earlier captures differ in shape and colour, as a real afternoon's would:

1. The cat's sprite test page (`cat-test.html` in Mew), a square crop.
2. A tall crop of the terminal: Claude's plan for level 4.
3. Level 3 of the game, wide, with a box you drew.
4. Claude's sketch, which the beat opens.

## The motion

- **The camera is a spring,** critically damped like Vignette's own `Tween.spring`. A move starts
  briskly and settles softly. A move started before the last one has settled keeps its speed and
  bends toward the new target, instead of stopping and starting again.
- **The camera leads the action.** Each move is timed to settle as the action it frames begins: on
  the browser as the region drag starts, on the terminal as Send's prompt lands, on the corner as
  Claude's card arrives.
- **Holds are not frozen.** During a hold the camera drifts in by about 2%, so the frame keeps
  moving without drawing the eye.
- **The camera travels between places,** which the desktop gives it: from the browser to the editor,
  to the terminal when the prompt arrives, back to the browser as the game reloads, to the corner
  for Claude's card.
- **The hand varies.** A glide's length sets its duration, as a hand's does. A long glide overshoots
  a little and settles. Pauses vary around their value, from a generator seeded by the take's
  config, so a take repeats exactly.

## The beats on the desktop

1. **Take screenshots as usual ⌘⇧4.** Wide on the desktop, then in on the browser for the region
   drag. The thumbnail slides in, and a click lifts it into the editor.
2. **Mark it up.** In on the moon's box and its note. The other two marks dissolve in as the camera
   pulls back.
3. **Send it to your agent ⌘↩.** The editor closes. The camera travels to the terminal, where the
   prompt lands in Claude Code with the image, and Claude starts.
4. **It builds what you marked.** Across to the browser as the game reloads with the moon, the city
   and the water tower. Claude's working time is skipped.
5. **It sketches the next step.** Claude's card slides into the corner and the camera goes to it.
   Then the card slides away.
6. **Double-tap right Shift to get it back ⇧⇧.** The history slides in, with the four captures
   above. A click lifts Claude's sketch into the editor.
7. **Change what you don't like.** The middle ledge dragged onto the water tower.
8. **Send it back ↩.** Reply, the card flies home, and the terminal takes the reply.

## Decided

1. **Real Claude Code runs in the terminal** (Pete, 2026-09-26). Send and Reply reach it, it edits
   the game, and it pushes its sketch through Vignette. `CLAUDE.md` in the stage folder keeps its
   edits to the level's data, so the art stays as drawn. A take lasts several minutes and varies
   with Claude, and the cut skips the waiting. It runs on its own config in `out/stage/claude`,
   signed in once with `trailer.py claude`.
2. **Chrome, with a fresh profile** (Pete, 2026-09-26).
