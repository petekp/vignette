# Live ink: marks that stay on their window (spike, 2026-10-04)

Status: done. The probes are in `spikes/live-ink-anchors/`. They are disposable and separate from
the app. Each one builds on its own with `swiftc -O -swift-version 5 <file>.swift`.

Step 3 of live ink (`docs/live-ink-integration-2026-10-04.md`) keeps a mark on what it points at.
In this note, an **anchor** is what a mark is attached to. A mark anchored to a window should move
with that window, scroll with its content, and sit in its layer, so a window in front covers the
mark. It should also go away when the window does. This spike asked how much of that macOS allows,
and how well it works.

The short answer is that all of it works.

- A mark can sit in the annotated window's own layer. Each annotated window gets its own clear
  overlay window, ordered directly above it.
- A mark follows a window drag within a third of a frame.
- A mark anchored to a text range through Accessibility follows scrolling, resizing and rewrapped
  text.
- Where Accessibility gives no positions, two other anchors work: the text of a terminal line, and
  the window's pixels.

## How it was measured

Three probe processes ran on Pete's Mac, macOS 15.7, a 120 Hz display:

- **A target app.** A titled window with a scrolling text view of numbered, varied lines and one
  green block. It moves, resizes and scrolls itself on command.
- **An overlay.** It rings the green block from another process.
- **A recorder.** ScreenCaptureKit, filtered to the probe processes alone, so none of Pete's
  windows were captured. It found the block and the ring in every frame and logged the distance
  between them.

Pete then used the anchor lab (`lab.swift`) on real windows. In the lab, holding Right Option pins
a mark at the pointer. Each pin draws two rings, one per follow method:

- **Magenta** follows through Accessibility.
- **Cyan** follows by registering captures of the window, in memory only.

## Results

### 1. Layering: a window of its own, ordered above the target

The overlay is a clear, borderless window at the normal level. It ignores the mouse and is placed
with `order(.above, relativeTo: <target's window number>)`. Ordering relative to another process's
window works.

- **A third app's window in front.** It cuts the mark cleanly where the two overlap. Nothing has
  to compute a clip.
- **The target raised by a click or by activation.** The target goes above the overlay. The
  overlay sees this on its next display tick and orders itself back. In all three tries the mark
  was missing for exactly one frame, 8 ms.
- **The target's own windows between it and the overlay.** That is normal. A titled window on
  macOS 15 has a 52 by 20 pt window of its own over its title bar, and sheets and popovers are
  windows too. So the test for "in place" is that every window between the target and the overlay
  belongs to the target's process.
- **Cost of checking the order.** It is about 1 ms per tick. The cost is
  `CGWindowListCreate(.optionOnScreenAboveWindow)`, which Swift marks unavailable and the probe
  calls through `dlsym`, plus a description of the windows in between.

The alternative from spike 1 was one overlay above everything, clipped by the windows in front. It
needs no reordering, so it has no one-frame gap. But it must track every window's frame on every
tick, and it lags while another window is dragged over the mark. Ordering is simpler and correct
by construction. The one-frame gap on raise is its cost.

### 2. Moving and resizing the window

`CGWindowListCreateDescriptionFromArray` for the annotated windows on every display tick gives the
frame and whether the window is on screen. It costs 0.4 to 0.7 ms.

| Driven by | Error while moving (median, p90) | Lag in frames (median, p90) |
|---|---|---|
| The window moving itself | 1.1 pt, 3.7 pt | 0.34, 1.10 |
| Pete dragging the title bar | felt right, not measured | |

On resize, a mark anchored to a text range followed the content through every case: growing,
shrinking, and a narrower width that moved the green block to another line. Pete's first try had
visual-only pins, and those broke. The fix is in section 3.

### 3. Scrolling

| Method | Error while moving (median, p90) | Lag in frames (median) | Cost |
|---|---|---|---|
| Accessibility text range (`AXBoundsForRange`, polled per tick) | 1.7 pt, 4.8 pt | 0.37 | 0.1 ms per tick, main thread |
| Visual registration | 3.9 pt, 7.5 pt | 0.79 | about 7 ms per frame, own queue, unoptimised |

- **Accessibility needs no scroll notification.** Polling the anchor's bounds every display tick
  is cheap enough, and it is also right after a resize or a rewrap.
- **Visual registration** captures the target window with `SCContentFilter(desktopIndependentWindow:)`
  at the window's pixel size. It finds where a patch round the mark has moved. Two details make it
  hold:
  - It compares against a reference frame that is replaced only after 100 pt of movement. With
    that, drift came back to 0 after 1,600 pt of fast and slow scrolling.
  - The patch moves onto visible content while the mark is scrolled out of view.
- **Visual registration needs reasonably varied content.** On a test page where every line was the
  same sentence, it locked onto the wrong line.
- **On resize, visual registration must stop.** Until the stream is reconfigured, its frames are
  scaled to the old size. Once the new size has held for 0.15 s and the stream has switched to it,
  the follower searches the new frame for the content in x and y. That takes 3 to 55 ms. If the
  content is not found, as when text rewraps, the mark stays hidden. It comes back only when the
  content is found again, for example when the width returns. Both bugs Pete found came from
  breaking these rules: matching scaled frames, and resuming from a frame taken after the content
  was lost.
- Pete's trackpad scrolling, with momentum, was not compared against these numbers. The scrolls
  above were driven by the target app.

### 4. Apps without text positions: Ghostty

Ghostty's terminal is an `AXTextArea`. It gives `AXValue`, `AXVisibleCharacterRange` and
`AXLineForIndex`, but no `AXBoundsForRange` or `AXRangeForPosition`. Its value is only the visible
screen: 46 lines in Pete's window, not the scrollback.

That supports a third kind of anchor, a **line anchor**:

- Keep the pinned line's text and the lines above and below it.
- On each tick, find that line in the visible text.
- Place it by row, at the text area's height divided by the number of lines.

It survives scrolling, new output and resizing for as long as the line is on screen. It is hidden
once the line scrolls off. A pin on a blank line gets no line anchor. Pete has not tried this
anchor yet.

### 5. The window going away

| Event | What the probe saw | What step 3 should do |
|---|---|---|
| Closed | Gone from the window list; the mark lingered one frame | Remove the window's marks |
| Minimised | The genie animation takes 370 ms, and the mark trails it badly until the window is off screen | Fade the marks out when minimising starts; Accessibility's `AXWindowMiniaturized` notification is the signal to measure |
| Restored or reopened | The mark came back 110 ms after the window | Fade back in; the delay is not explained yet |
| Another Space or full screen | Not tried | See "Not yet known" |

## What this means for step 3

1. **One overlay window per annotated window, ordered just above it.** Each is sized to its
   window's frame and clips to it. One full-screen overlay per window would cost about 24 MB of
   backing store each at 2x. The overlay's collection behaviour is `.moveToActiveSpace`,
   `.transient` and `.ignoresCycle`, so it stays out of Mission Control and the window cycle.
2. **One display-link tick for every anchored window.** Each tick reads the frames, checks the
   order, and places the marks.
3. **Anchors, best first:**
   1. A text range, through `AXBoundsForRange`.
   2. A web text marker, through `AXBoundsForTextMarkerRange`.
   3. A line anchor, for terminals that give visible text without positions.
   4. An element's frame.
   5. Visual registration, last.

   The packet already resolves an answer's marks to text lines, so an agent's marks can carry the
   same anchors.
4. **A mark that loses its anchor hides.** This covers text rewrapped away, a line scrolled off,
   and content not found after a resize. A hidden mark comes back if its anchor returns, and it is
   never left floating over the wrong content.
5. **Marks clip to the scroll area that holds their anchor**, when Accessibility gives one.

## Not yet known

- **Real gestures, measured.** Pete's title bar drag felt right, but its lag was not recorded.
  Trackpad scrolling with momentum, in Safari, Chrome and Notes, has not been compared between the
  two rings.
- **Web pages.** The text-marker anchor is written but has not run against Safari or Chrome.
  Chrome may update its accessibility positions late while scrolling. Comparing the two rings
  there would show it.
- **Spaces and full screen.** The overlay's `.moveToActiveSpace` should follow the target when it
  is ordered again on the target's Space. Untried.
- **The one-frame gap when the target is raised.** It could be removed by reordering the overlay
  before the raise is composited. No hook was found for that yet.
- **The 110 ms delay** before a mark reappears with its window.
- **Visual registration cost.** It runs at about 7 ms a frame in plain Swift. vImage, a smaller
  patch, or the GPU would cut that, and it matters with several pinned windows.
