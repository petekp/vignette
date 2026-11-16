# Live ink flickering over Dia on send, 2026-11-15

Pete reported that over Dia, sending a note made the ink's gel ring and the note's popover flicker.
Over Herdr they stayed steady. This was on macOS 27.2.

## Cause

A mark drawn on a window lives in that window's overlay (`WindowOverlay`). The overlay sits at the
normal level, ordered just above the window. The note and the reply hang from that overlay as child
windows, so they share its level and its place in the order.

Sending hands the keys back to the app under the ink twice, through `FocusReturn.restore`. The note
lets go when Return is pressed, and the reply that takes the note's place lets go when it becomes
key. Dia is still frontmost, so `restore` calls `NSApp.deactivate()`. macOS posts no
`didActivateApplicationNotification`, and `LiveWindows` lifted overlays only on that notification.
Dia then brings its window to the front, over the overlay and its popovers. The overlay stayed
covered until `LiveWindows.keepInPlace` noticed on a later tick. At rest, that tick runs about ten
times a second. Why the second recovery took 150 ms, longer than one idle tick, was not measured.

## Evidence

A read-only poll of `CGWindowListCopyWindowInfo` every 4 ms recorded the order of the Dia, Herdr and
Vignette windows during one ask over Dia. Timestamps match `~/Library/Logs/Vignette.log`. A
`screencapture -v` recording could not show this, because a build that is not a test launch leaves
its overlays out of captures.

| Log | Window order |
|---|---|
| 22:51:36.696 `[focus] live ink note: returned to Dia` | 36.721: Dia's window in front of the note (11658) and the overlay (11657). 36.762: back behind them. Covered for 41 ms. |
| 22:51:36.940 `[focus] live ink reply: returned to Dia` | 36.961: Dia's window in front of the reply (11663) and the overlay. 37.111: back behind them. Covered for 150 ms. |

The overlay stayed at layer 0 throughout, so nothing lifted it. After each hand-back, Dia's window
came forward 21 to 25 ms later.

A separate check used an off-screen panel with an `NSPopover` shown from it, and another with a
child panel. In both, the popover's or the child's window took the host window's level in the
window server, at level 3, level 1 and back at 0. So lifting the overlay lifts the note and the
reply with it.

## Fix

`FocusReturn.restore` posts `FocusReturn.handingBack` just before it hands the keys back. When the
app is already frontmost, `LiveWindows` lifts the overlay of that app's front window
(`LiveWindows.Lift.Cause.keysBack`). The app's windows behind it keep covering their own marks. The
overlay goes back down, just above its window, once another app's window overlaps that window from
above, or after `Lift.limit` (0.5 s).

Both lifts now rise to level 1, the screen overlay's resting level, instead of `.floating` (3). Level
1 is over every app's normal windows, and under the dim (2) and Vignette's floating windows. So a
lift never puts marks over the dim as the stack closes. The lift for an app coming forward
(`activating`) still ends once no other app's window overlaps the window from above. It now counts
only windows that overlap, and it leaves out Vignette's own panels at the normal level, such as the
answer's dismiss button.

## Not checked

The fixed build has not been run over Dia. Vignette's rules forbid launching another copy on Pete's
Mac. The drop back to the normal level at 0.5 s is the same step the activation lift already took.
A lifted overlay shares level 1 with the screen's overlay and goes in front of it for up to 0.5 s.
Ink drawn on no window, on that overlay, then sits under the window's marks where the two overlap.
