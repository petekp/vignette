# Presses are routed by the window server's pixel rule

The annotator's window spans the visible screen and is clear outside the image's frame. The window
server gives a press to a window only where its pixel is not clear. So every press on the frame
reaches the editor, and a click outside reaches the app behind, which is how a click outside closes
the editor. The flight layer works the same way. Neither window ever sets `ignoresMouseEvents`,
because set either way it overrides the pixels.

Sources: `docs/flight-press-2026-09-23.md`, commit 80c73d5.
