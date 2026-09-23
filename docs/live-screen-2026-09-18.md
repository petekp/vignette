# Drawing on the live screen, both directions: an exploration

Not built. Two throwaway demos ran on 2026-09-18 and their source is in
`docs/live-screen-demo/` (`swiftc -O -o point point.swift`, then `./point ghostty 20`;
`./arrow ghostty screenshots 30`). Everything else here is the shape of the work and the
tradeoffs, written down so it can be picked up later.

## What was demonstrated

**A ring around another app's window** (`point.swift`, 70 lines). A transparent, borderless,
non-activating panel at `.screenSaver` level with `ignoresMouseEvents`, `canJoinAllSpaces` and
`fullScreenAuxiliary`, drawing a red rounded rectangle at the window's bounds. The window is
found by owner name in `CGWindowListCopyWindowInfo`, which needs no permission and returns every
on-screen window's bounds, owner, layer, and front-to-back order in global top-left points, the
same convention as `[state]` and `scripts/input.sh`. A 30 Hz poll follows the window through
moves and resizes; Pete confirmed it tracked a live resize. Clicks pass through.

**An arrow at a word inside a terminal** (`arrow.swift`, 100 lines). The Herdr sidebar is
terminal text with no accessibility elements, so the demo captured the window
(`screencapture -x -R`), ran Vision's text recognizer, found "screenshots", took its box as a
fraction of the window, and drew an arrow at it on the same kind of panel. It found the sidebar
entry (59% down) rather than the tab of the same name at the top because it takes the first
match in reading order; a real version needs a way to say which. The recognizer re-runs when the
window changes size, since terminal text reflows.

## Agent to human: pointing at the live screen

Three ways to anchor a mark, in order of precision:

1. **A window**, from the window list. No permission. Bounds, owner, title (title needs Screen
   Recording permission on macOS 15), stacking order.
2. **An element inside a window**, from the Accessibility API: frames of buttons, fields, menu
   items, in screen coordinates. Needs the app trusted for Accessibility, which the double-tap
   hotkey already needs. AppKit, SwiftUI, Safari, and most Electron apps expose elements; Chrome
   exposes web content only once an accessibility client asks; custom canvases, games, and
   terminals expose nothing below the window.
3. **Recognized text**, from Vision over a capture of the window. Covers everything the second
   route cannot. Ambiguous when a word appears twice; a phrase or a nearby word disambiguates.

Following the target: Accessibility posts moved, resized, and minimized notifications; a poll at
the display rate is the fallback and lags a frame. One overlay panel per display.

Limits, so nobody rediscovers them:

- Nothing draws inside another app's window, only over it. A region under another window is
  invisible until that window moves. The overlay can clip the mark to the target's visible
  region using the stacking order and draw a callout at the visible edge. Raising the target
  means activating its app, which the app's panels never do on their own.
- A covered window can still be captured: ScreenCaptureKit renders one window's contents
  regardless of occlusion. That needs Screen Recording permission (one prompt; macOS 15 asks
  again periodically). So "show me the thing under Chrome" is a card pushed to the stack, not an
  overlay.
- Full-screen Metal games and the lock screen cannot be overlaid. Mission Control hides overlays.
- Click-through is per window. A mark that is itself clickable needs the alpha-hit trick the
  stack panel uses.

The command, roughly: `vignette://point?app=Safari&window=<title>&marks=<json>`, the marks in
fractions of the window, or anchored to an element or a phrase, drawn until Esc or a timeout,
clipped to what is visible. If the window is covered, the same command captures it and pushes
the card with the marks. The marks format is unchanged; the anchor is new. Effort: overlay and
window tracking in a day or two, element anchoring a day, the covered-window capture a day with
the new permission. Reused: the panels, the coordinate convention, the marks parser, the springs.

## Human to agent: drawing on the live screen

The question Pete raised: does the agent need the whole window, or is a crop around the marks
enough? The answer is that the live screen gives the agent something a screenshot cannot, which
is what the mark is on, and the crop question mostly follows from that.

**What the agent receives per mark.** The crop, plus a record: app name, window title, the
accessibility element under the box (role, title, value, identifier), the recognized text inside
the box, the URL if a browser, and the position as screen coordinates and as a fraction of the
window. "This button" becomes Safari, the checkout page, button "Place order", 62% across, 18%
down. The agent often needs no pixels, and when it acts it has coordinates `input.sh` can click.

**Crop versus window.** Crop around the marks by default, sized by the number the app already
has: `Stitch.readerScale`. Pad the union of the marks until the crop reaches the model at a scale
where its text survives, and stop. Add the whole window as a second image at the 1568 px cap when
context matters; it is cheap. The evidence for the default is Pete's own habit: 55 of 55 images
sent to agents between August and September 2026 were hand-made crops, median 840 px wide.

**Tradeoffs.**

- The overlay takes the mouse while drawing, so menus and hover states close. Freeze first: the
  hotkey captures the screen and the window list, the drawing happens on the frozen frame,
  Return crops and emits. This also removes the timing problem, since the UI cannot change
  between the circle and the capture.
- Privacy: the live screen has everything. The crop limits exposure; a clip to the target
  window's bounds limits it further. State the rule: nothing outside the window drawn on leaves
  the machine.
- A live mark is ephemeral; at Return it becomes a card like any capture, with a draft. Then the
  live mode is a capture whose region was chosen by drawing, with anchors attached, and the
  stack, the draft, copy, and send are unchanged.
- Where it goes is the same question as `send`: the clipboard today, the `ask` command later,
  where the agent asked first and the drawing is the answer.
- Anchors are only as good as the app: a terminal gives recognized text and nothing else, which
  is still a crop with a position.

**The shape to build.** Hotkey, freeze, draw, Return. Out comes the crop sized for the reader,
the marks as fractions of the crop and of the window, the anchor record, and optionally the
window thumbnail. One new command, the existing editor, the existing marks format, the two
demos' code for the window and text anchors.

**The open question.** How often the agent needs the anchor rather than the crop. For a browser
probably always, since the element is what it will edit; for a native app it is a bonus. The
first build should log which fields an agent reads.

## Related

- `docs/stitch-2026-09-17.md`: the reader scale that sizes a crop.
- The latent-potential assessment of 2026-09-18: the return leg (a structured readback and a
  waiting `ask`) is the piece both directions here depend on.
