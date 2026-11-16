# Live ink under Vignette's own Settings window, 2026-11-16

Pete drew a ring on Vignette's Settings window. While he held the chord, the ring showed over
Settings. Once he let go, it went under Settings. Over other apps' windows, the ring stayed on top.

## Cause

A mark goes on the topmost window under it (`LiveWindows.window(under:)`). That lookup passed over
every window Vignette owns, since Vignette's overlays, the note and the corner must never take
marks. Settings, setup and the tweaks were passed over with them. So a ring drawn on Settings went
on the window of another app behind it, and that window's overlay sat just above that window,
under Settings.

While a stroke is drawn, it is on the screen's surface, which is at the screen saver's level during
inking (`LiveInkOverlay.setInking`). That is why the ring showed over Settings while Pete drew it.
When the stroke ends, the mark goes on the window under it (`LiveInk.place`).

## Evidence

- `.scratch/log-settings-ink.txt` in the `ink-over-settings` worktree is the 10:33 attempt from
  Pete's log: `inking`, `drew ellipse`, `tap off`, `note open`, then
  `[focus] live ink note: returned to Live Ink`. Live Ink is the Settings tab, so Settings was the
  key window when the inking began (`FocusReturn.sessionStarting`).
- In the code, the guard `pid != own` in `window(under:in:own:ordinary:)` skipped Settings. The
  unit test `testVignettesTitledWindowTakesTheMarkAndItsOtherWindowsAreSeenThrough` shows the
  lookup without Vignette's titled windows returns the window behind Settings.
- Settings was not open when this was looked into, so no window list was recorded during the
  attempt. The ring's window was not read from `[state]`.

## Fix

Vignette's titled windows on the screen (`LiveWindows.titledWindows`) now take marks as any app's
window does: Settings, setup, the tweaks and the labs. They take them up to the floating level,
where the tweaks and the labs are. An alert of Vignette's, at the modal panel level, takes none, as
another app's panel takes none. Its other windows are still passed over.

The overlay of one of Vignette's own windows is that window's child window (`Tracked.host`).
`FocusReturn.restore` orders Settings to the front when the note closes. AppKit then keeps the
child just above it, at its level, and moves it with it. So `keepInPlace`, the lifts and the
Accessibility watch for moves leave these overlays alone. `WindowOverlay.close` takes the overlay
off its window first, because a window orders its children back in whenever it is ordered in.

A check in a script used a titled window and a borderless child panel, placed off the screen.
AppKit moved the titled windows onto the screen. After another window came forward, `orderFront`
and `makeKeyAndOrderFront` put the child straight back above its parent. Setting the parent to
`.floating` moved the child to level 3, and back to `.normal` moved it back to level 0. Moving the
parent moved the child. After the parent was closed and ordered in again, the child came back
above it.

## Not checked

The fixed build has not been run on Settings. Vignette's rules forbid launching another copy on
Pete's Mac.

An ask about ink on Settings should now get a picture of Settings alone, since the plan names that
window. This relies on ScreenCaptureKit listing Vignette's own windows, which was not checked.

Ink on Settings and on another window gets a picture of the screen. That picture still leaves
Vignette's windows out (`LivePacket.listed`, the `asSeen` filter), so Settings is missing from it.
For the same reason, Settings in front of another app's inked window does not count as covering
that ink.

How an overlay that is a child window behaves when its window is on another Space was not checked.
