# Plan: a capture opens in the editor from where it was taken

With Instant Draw (`annotateOnCapture`) on, a new capture flies into the editor from the rect it
was taken from, instead of from the corner. `docs/capture-origin-spike-2026-10-03.md` has the
measurements this plan rests on.

## Behaviour

- **Selection (⌘⇧4, drag).** The flight starts at the selected rect.
- **Window (⌘⇧4, Space, click).** The flight starts at the window's frame. With the window shadow
  on, which is macOS's default, the image has a transparent margin around the window: 34 pt each
  side, 26 above and 42 below for an inactive window, and 56, 38 and 74 for the active one. The
  flight starts at the window's frame grown by that margin, with no matte behind the transparent
  pixels, so the shadow lies over the screen as the real one did. A margin past the screen's edge
  is cut off there, as the real shadow was.
- **Full screen (⌘⇧3).** The flight starts at the display's frame.
- **Anything else** flies from the corner, as today. That covers ⌘⇧5's toolbar when its rect
  does not match, a capture made by another tool, and a match that fails.
- **The flight starts looking like the screen:** corner radius 0, no shadow, no border ring and no
  matte, because the captured pixels have none of them. On the way to the editor the corners morph to the
  editor's radius (`ui.annotationCornerRadius`), the ring fades in, and the shadow grows to the
  editor's.
- **The editor opens on the display of the capture.** Today it opens on the display with the
  active window. The flight cannot cross displays, and the person is looking at the display they
  captured on.
- **Esc and Done send the card home through the corner, as today.** The editor's place is
  unchanged.
- **A capture with Instant Draw off is unchanged.** Its thumbnail still slides into the corner.
  A thumbnail that flies from the capture is a possible follow-up, not part of this.

## How Vignette finds the rect

- **The poll.** A `flagsChanged` monitor sees ⌘ and ⇧ held together, which needs no permission.
  That starts a 30 Hz poll of `NSEvent.pressedMouseButtons` and `NSEvent.mouseLocation`. The poll
  ends when a capture uses it, or after 15 s.
- **The rect.** The file gives the exact size: pixels over the display's scale. The release point
  is one corner, with the capture including the point under the cursor. The press gives only the
  direction of the drag.
- **The match.** The polled drag counts only for a file that arrives within 3 s of the release,
  with a size within 12 pt of the drag. If it does not count, Vignette tries the window under the
  cursor at the file's size, with or without the shadow margin, then the display's frame.
- **The code.** The geometry is a pure function, `CaptureRect.locate`, so tests can drive it with
  no window server. `CaptureOrigin` holds the monitor and the poll, and reads the window list.

## The flight

- **The starting frame.** `ThumbnailController.annotate(_:from:)` keeps the rect for that one
  file, and the `.prepare` effect uses it as the flight's `from`. The run and the transition
  reducers do not change.
- **The ring and the matte.** `TransitionLayer.Look` carries the ring's opacity and the matte's,
  so the starting look can have neither. `Look.screen` is that look.
- **No hold.** The spike's flight seemed to hold still for 2 to 7 frames. Those were frames in which
  only the ring showed. Timed in the app, the spring starts 8 ms after the flight is added.
- **The picture is there from the first frame.** A new capture has no decode cached, so the flight
  began with an empty image. In `Look.screen` an empty flight is invisible, so it travelled unseen
  and appeared 25 to 35 pt along its path. `annotate(_:from:)` now waits for the screen-size
  decode before the run starts: 20 to 60 ms from the match to the flight in these takes. The
  screen shows the same pixels meanwhile, and the editor opens with the decode at once.

## Tests and verification

- **Unit tests for `CaptureRect.locate`:** four drag directions, the release-edge point, a stale
  drag, a size that does not match, a window with and without its shadow margin, and the display.
- **An `--input` scenario in the end-to-end suite.** It posts ⌘⇧, runs `screencapture -i` into the
  scratch watch folder, drags, and checks the flight's starting rect in the log.
- **Recordings at 60 fps.** Check the start against the pixels beneath, the ring, and that the
  motion starts at once. Check a forward drag, a reverse drag and a window capture.
- **A real ⌘⇧4 by Pete** at the end, since synthetic input is not the person's hand.

## Docs

- A rule in AGENTS.md under "Shortcut and capture": how the rect is found, why it polls, and the
  fallback.
- The spike note stays as the measurements.

## Open

Pete's real ⌘⇧4 captures looked right on 2026-10-03, and the end-to-end suite, `capture_origin`
included, passed with `--input` that day.

- **A one-frame doubled shadow at the landing**, seen once in Pete's recording of this build. It
  did not reproduce in 28 recorded takes on 2026-10-03: Release and Debug, all cores busy, a Send
  target in the toolbar, and flights from the corner and from a full-screen capture.
- **A display at scale 1, and a second display.** Covered by unit tests only.
- **⌘⇧3 with two displays.** It writes one file per display, and each file matches its own
  display. Check what happens today when two captures arrive at once with Instant Draw on, and
  keep it.
