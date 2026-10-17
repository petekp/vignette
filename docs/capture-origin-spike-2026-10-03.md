# Where a capture was taken: spike, 2026-10-03

The question: with Instant Draw (`annotateOnCapture`) on, can the flight into the editor start
at the rect the person just captured instead of the corner? That needs the capture's rect on
screen. Vignette has no Accessibility or Screen Recording to spend on it. macOS also records it in
the file's metadata, except for stretches when it stops. "The file's metadata" at the end has the
measurements.

## Result

Vignette can learn the rect without any permission, for the selection and window captures tested.

- **Selection (⌘⇧4, drag).** Poll `NSEvent.pressedMouseButtons` and `NSEvent.mouseLocation`. The
  press and the release give the rect, within 1 to 2 pt of the file's size in points. The drag
  direction does not matter.
- **Window (⌘⇧4, Space, click).** The file's size in points matched the bounds of the window under
  the cursor, from `CGWindowListCopyWindowInfo`, exactly: 1409 × 871 pt for a Ghostty window at
  (10, 38, 1409, 871). That was with `disable-shadow` on.

## What does not work

- **The file, that morning.** The ⌘⇧4 PNGs tested carried no screen position: no extended
  attribute, and the eXIf chunk holds only the pixel size. macOS had stopped writing its capture
  metadata on that Mac since 2026-09-01 and started again after a reboot at 16:40 that day. See
  "The file's metadata" below.
- **Apple's defaults.** `com.apple.screencapture` has `last-selection`, but ⌘⇧4 captures did not
  update it. Neither its value nor the preferences file's write time matched the captures. It
  appears to be ⌘⇧5's remembered selection.
- **A global mouse monitor.** `NSEvent.addGlobalMonitorForEvents` saw ordinary clicks in an app
  without Accessibility. It saw nothing of a real ⌘⇧4 drag. The capture overlay keeps the drag
  from other apps. The monitor did see ⌘ and ⇧ go down, as `flagsChanged` events, without Accessibility.

## Measurements

The logger was a separate ad-hoc-signed app bundle, launched with `open`, so it reported
`AXIsProcessTrusted() == false`. The display was 1512 × 982 pt at scale 2. Coordinates are global
top-left points.

| Capture | Polled press → release | Polled rect (x, y, w, h) | File (pt) |
| --- | --- | --- | --- |
| Drag ↘ | (24.8, 63.6) → (1496.6, 900.0) | 24.8, 63.6, 1471.8, 836.3 | 1473 × 837 |
| Drag ↖ | (1492.9, 908.5) → (7.0, 40.9) | 7.0, 40.9, 1486.0, 867.6 | 1487 × 869 |
| Window | (no drag) | Ghostty 10, 38, 1409, 871 | 1409 × 871 |

The file appeared in the folder 150 ms after the release in both drags. The cursor at that moment
was still at the release point. The file's size is the rect snapped outward to whole pixels.

## Limits

- Not tested: ⌘⇧3 full screen, ⌘⇧5's toolbar, a second display, a display at scale 1, Space held
  during a drag to move the selection, and ⌥ held to resize it from the centre.
- A window capture with the shadow on includes a transparent margin around the window. Measured
  with `screencapture -iW`: 34 pt each side, 26 above and 42 below for an inactive window, and 56,
  38 and 74 for the active one. `screencapture -l` gives the smaller margin even for the active
  window.
- The two drags in the table were real ⌘⇧4 captures. A `screencapture -i` capture driven by
  synthetic CGEvents ran before the poll existed, so it says nothing about the poll.

## The flight from the capture

A second spike started the editor's flight at the capture's rect. It is on the branch
`spike/capture-origin`, uncommitted in `~/Code/worktrees/vignette/capture-origin-spike`. It took
about 40 lines:

- `CaptureOrigin` holds the ⌘⇧ monitor, the poll and the match.
- `AppDelegate.present` asks it for the rect of a capture that opens in the editor.
- `ThumbnailController.annotate(_:from:)` keeps the rect for that one file. The `.prepare` effect
  uses it as the flight's `from`, with a `Look` that has square corners and no shadow.
- The run, the transition and the flight are unchanged. Esc and Done send the card home through
  the corner as before.

It ran on the E2E test copy, with `screencapture -i` and synthetic ⌘⇧ and drags, recorded at
60 fps. What it showed:

- The rect was right. The poll started on ⌘⇧ and stopped 15 s later. Drags in both directions
  matched, and the flight started on the captured rect. The first version placed it 1 pt off: the
  capture includes the point under the cursor, so the edge on the release side is 1 pt past the
  release point. The spike corrects for that.
- The start is seamless only while the screen under the rect is unchanged. Over a static screen
  the first frames matched the pixels beneath. Over a terminal that scrolled after the capture,
  the flight showed the captured pixels over newer ones. That is the screenshot, so it reads
  correctly, but it is not invisible.
- The flight draws the card's border ring from its first frame. `FlightsView` strokes it at
  `ui.cardBorderOpacity` whatever the `Look` says, so a thin light line outlines the rect before
  it moves. A real version needs the ring's opacity in `Look`, 0 at the start.
- The flight seemed to hold still for 2 to 7 frames before the spring moved it. Those were frames
  in which only the ring showed. Timed in the app, the spring starts 8 ms after the flight is
  added. With the ring and the matte at 0, a 60 fps take shows the picture moving one frame before
  the dim starts.

## What it means for an implementation

- Poll only around a capture. ⌘ and ⇧ held together, seen through the `flagsChanged` monitor, can
  start a 30 Hz poll of the button state, which ends after a timeout. 30 Hz is enough because the
  rect comes from the release point and the file's size; the press gives only the direction.
  This needs no permission and avoids a timer that runs all the time.
- Match before trusting. Use the polled rect only for a file that arrives within about a second of
  the release and whose size in points is within 2 pt of the rect. The size in points is the
  pixel size over the scale of the display under the rect. Otherwise try the window under the cursor by size, then the display's frame. With
  no match, fly from the corner as today.
- The flight's start point is `from` in `ThumbnailController.perform(.prepare)`'s call to
  `flights.fly`. It would also start with square corners and no shadow, because the captured
  pixels are still on screen there.

## The file's metadata, 2026-10-17

macOS writes three extended attributes on a capture, each a binary property list:
`com.apple.metadata:kMDItemIsScreenCapture` (true), `kMDItemScreenCaptureGlobalRect` and
`kMDItemScreenCaptureType` (`selection`, `window` or `display`). The rect is in global top-left
points, the same convention as `[state]`. A window capture's rect is the file's footprint,
shadow included: 713 × 603 pt for a 1426 × 1206 px file at scale 2.

**They are there when the watcher sees the file.** A probe polled a folder every 2 ms in the
`vignette-e2e` VM (macOS 15.7.7) during real ⌘⇧4 selection and window captures and a ⌘⇧3 full
screen capture, and on the host for `screencapture -x` and `-R`. Each capture is written as
`..<name>-XXXX`, renamed to `.<name>`, then renamed to its final name. The attributes are set
before the last rename: they were present at the first poll that saw the final name, 0 to 4 ms
after it appeared, never later. The watcher skips names that start with a dot
(`ScreenshotWatcher.swift:361`), so it never sees a capture without them.

| Capture | Rect | Type |
| --- | --- | --- |
| ⌘⇧4 drag in the VM | 150, 150, 151, 101 | selection |
| ⌘⇧4, Space, click on TextEdit | 23, 14, 713, 603 | window |
| ⌘⇧3 | 0, 0, 1024, 768 | display |
| `screencapture -x -R 0,0,200,120` | 0, 0, 200, 120 | selection |

**macOS sometimes stops writing them.** In Pete's `~/Dropbox/Screenshots`, every capture from
February to August 2026 has them. None has them from 2026-01-10 to 01-15, or from 2026-09-01 at
22:14 until 2026-10-03 at 16:40, when the Mac rebooted; every capture since has them. No macOS
update was installed at either boundary, and the second gap began before Vignette existed.
Screen recordings (`.mov`) never carry them, and neither do Vignette's `-annotated.png` files or
agent pushes.

So the metadata is exact whenever it is present, and it can be missing for weeks. It can give a
capture's origin first, with `CaptureRect.locate` as the fallback, and it covers captures the poll
cannot see: ⌘⇧3, ⌘⇧5's toolbar and `screencapture` itself. Its absence cannot mark a file as not
a capture.
