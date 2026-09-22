# Recordings: the opportunity

Vignette turns Apple's screenshot thumbnail off, so a Cmd+Shift+5 recording currently lands with
nothing shown. This note says what recordings are for, and what 0.1.0 does about them.

## The boundary

**Vignette does not play video. It takes screenshots from it.**

That sentence is what keeps a screenshot tool from growing a video editor. Playback, trimming and
sharing belong to macOS and the apps that already do them well. Vignette's interest in a recording
is the frames inside it.

## The opportunity

Debugging an animation means finding the few frames where the motion is wrong and drawing on those.

Today that means recording, opening the file in a player, scrubbing, and screenshotting the screen,
which captures the player's own window along with the frame. The tedious part is getting frames out.

Everything after a frame exists is already built. A frame is an ordinary screenshot: it gets a card,
it gets drawn on, the drawing is kept, several of them open one after another, and several of them
stitch into one numbered image.

That last one is the part worth noticing. **An agent cannot watch a recording. It can read a
sequence of frames.** Vignette already makes exactly that artifact, and already sends it into an
agent session with a drawing on it. So "look at this animation" becomes a thing an agent can answer,
out of pieces that exist.

The north star:

**A recording becomes the few frames worth looking at, for you and for an agent.**

How frames get picked is open. Nothing about it is decided here.

## 0.1.0

Only that a recording stops being silent.

- A card appears, so the capture is acknowledged and the file is findable.
- Clicking it hands off to macOS, opening the recording the way the system would.
- Copy and Delete, like any card.
- No drawing, no frame extraction, no stitching.

Handing off on click closes the gap this change opened. Apple's thumbnail offered trim and share;
the app macOS opens the recording in offers the same. Vignette says the capture happened and gets
out of the way.
