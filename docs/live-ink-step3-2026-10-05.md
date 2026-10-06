# Live ink step 3: marks that stay on their window (2026-10-05)

Status: built on `live-ink`, not yet committed. The measurements that chose the design are in
`docs/live-ink-anchoring-spike-2026-10-04.md`; the ones of the built version are at the end.

## The rule

A mark belongs to the window it was drawn on. It moves with that window, other windows cover it,
and it never shows over the wrong content.

- **Moving the window: the marks follow.** The window list gives the frame every display frame,
  and the marks keep up within half a frame.
- **Scrolling or resizing: the marks hide.** They fade out as the content starts to move and come
  back once it is still, on the spot they point at. Pete chose this on 2026-10-04. Following the
  content works in native apps, but Chromium apps report positions only 2 to 5 times per scroll, so
  marks there trailed the content and jumped.
- **The window goes away: the marks go with it.** Minimised, hidden, or on another Space, they
  fade with the window and come back with it. Closed, they are erased.
- **A session edits the page: the marks hold still.** While a session works on an ask, and while
  its marks play their done animation, a change of the content under them moves nothing
  (`LiveWindows.holding`). The person is watching the change land. Marks that faded, then glided
  to where their content went, read as the answer shifting around (Pete, 2026-10-05). They finish
  where they are when the turn ends. Moving or resizing the window still carries them.

## Pieces

- **`LiveWindows`** owns the windows that have marks. For each one it keeps an overlay window
  ordered just above it, the marks in the window's own coordinates, and their anchors. One display
  link reads every window's frame and moves the overlays. It runs at the display's rate while
  something may be moving (a press, a scroll, a key, an app coming forward) and at 10 Hz otherwise.
- **`LiveAnchor`** finds and reads where a mark's content is, off the main thread:
  1. a text range (`AXBoundsForRange`);
  2. a web text marker (`AXBoundsForTextMarkerRange`);
  3. a terminal line, for apps such as Ghostty that give their visible text and no positions;
  4. an element's frame, unless the element is the scroll area itself or covers half of it;
  5. a patch of the window's pixels (`LivePatch`), 160 by 64 pt round the mark, found again with
     one capture once the content is still.

  Each Accessibility call has a 0.25 s timeout and runs on the window's own queue, since Dia once
  held a call for 627 ms. An element anchor also keeps a patch. Chromium moves an element's frame
  late and only to the nearest run of text, so its reading says where to look and the pixels say
  where the mark goes. Chrome refuses `AXManualAccessibility`, so its page is an empty scroll area
  and its marks are anchored by their pixels alone.
- **Finding a patch.** Normalised cross-correlation, on a copy four times smaller first and then at
  full detail round the eight best places. The column the content was in is searched before the
  whole window. A match must score 0.8, and of matches within 0.03 of the best the one nearest the
  scroll's own distance wins, so a page of lines that look alike resolves to the right line. The
  top and bottom five eighths are tried too, for content cut off at the window's edge. A capture
  takes about 40 ms and a search about 30 ms in a Debug build.
- **Motion.** A window's content is moving from the first scroll event over it, the first change
  in its size, or the first anchor that moved within it. It is still once the scroll has been quiet
  for 0.15 s, the size for 0.2 s and the anchors for 0.1 s. The marks then take their anchors' new
  places and fade back in. A mark whose anchor is lost, or is outside its scroll area, stays hidden.
  A window whose app reports positions late (Chromium's element anchors, or any window caught
  doing it) waits 0.3 s and 0.25 s instead. A reading that has not changed after more than 24 pt of
  scroll is taken as stale, and waited on for up to 0.6 s.
- **Moves with no scroll event.** A key that scrolls (Space, the arrows, Page Up and Down, Home and
  End) or a click can move the content with nothing on the trackpad. Accessibility anchors see it
  in their readings, polled every 0.1 s while active. Pixel anchors are looked at every 80 ms for
  0.6 s after the key or click: one comparison says whether the content is still under the mark,
  and the mark fades out as soon as it is not. It comes back once two looks in a row agree.
- **Clipping.** A mark drawn inside a scroll area is cut off at its edge as the content is, so a
  mark scrolled under Chrome's toolbar does not draw over it.
- **Fades.** Hiding takes `liveInkHideFade` (0.12 s) and showing `liveInkShowFade` (0.22 s), both
  scaled by `ui.motion` and tunable in the tweaks panel. An erased or cleared mark fades over one
  and a half hide fades, and its overlay closes after it.
- **Minimising.** ⌘M and a release over the yellow button fade the window's marks as the window
  leaves. If the window is still there a second later, they come back. A window back on screen
  waits 0.2 s before its marks show.
- **Hiding without a jump.** For the length of the fade-out, the marks ride along with the
  trackpad's scroll deltas, which match the content's movement 1:1 while the page moves. So a mark
  leaves with its content rather than sliding off it.
- **Layering.** As in the spike: an overlay at the normal level, ordered above its window, moved
  back above it whenever another of that app's windows has come between. When the window's app
  comes forward, the overlay floats for the moment the app takes to raise its windows.

## What each mark is anchored to

| Mark | Anchored at |
|---|---|
| The person's loop or box | its centre |
| The person's arrow | its head |
| An answer's loop, box or arrow | the line it points at, when the window has not moved since the ask; otherwise the ink it answers |
| An answer's note, and Vignette's own notes | the ink they answer |

## Not in this step

- Marks over no window (the desktop) stay on the screen's surface, as in step 1.
- Following the content while it moves. It may come back for windows whose readings are proven to
  keep up on every frame.

## Measured, 2026-10-05

Recorded at 120 Hz with a recorder that captures only the test windows.

| Case | Result |
|---|---|
| Text view, 150 pt scroll over 0.8 s | hidden at the first event, back 0.2 s after the content stopped, within 1.7 pt |
| Text view, fling with 0.8 s of momentum | rides within 3 pt while fading, back 0.16 s after the last event |
| Window moved 220 pt in 0.8 s | median error 3.6 to 3.9 pt, of which 1.7 pt is a fixed offset |
| Resize | hidden, then back on its word |
| Covered by another app's window, then raised | covered, and no missing frame after the raise |
| ⌘M, then restored | fades with the window, back 0.2 s after it lands |
| Chrome without Accessibility, fling | found 6 of 6 by its pixels, back 0.23 to 0.3 s after the last event |
| Chrome with Accessibility, scroll | element and patch, right every time, no second flicker; cut off at the toolbar |
| Chrome without Accessibility, arrow keys | fades 80 ms after the page jumps, back about 0.2 s later on its line |
| Chrome without Accessibility, Page Down then Page Up | gone, then back 0.3 s after the page returned |
