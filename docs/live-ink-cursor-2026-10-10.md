# A magic cursor for live ink (2026-10-10)

It can be done. Build the magic cursor as an aura (a ring, glow or nib) drawn around the real cursor inside the live-ink overlay that already covers the screen while Control+Option is held. That needs only public API. It works over every app and cannot leave the cursor stuck. It plugs in beside `EdgeGlow`. The main limit is that macOS gives a background app no public way to change the real arrow's own pixels, so the aura is drawn by Vignette and trails the arrow by about one frame. One small experiment decides whether we can also swap the arrow itself for a pen cursor with no lag.

**Evidence labels used below:**
- **[Mac]**: verified on this Mac by the probe, a grep of the live-ink worktree, or the SDK headers.
- **[Source]**: a research report read it in the cited source. The probe could not recheck it. This label covers GitHub repos, forum threads, the Tahoe VM numbers and the display-link timing.
- **[Inferred]**: reasoned, not observed. Every claim about runtime behaviour is in this group, because nothing was driven.

**Terms:**
- **Real cursor**: the arrow macOS draws.
- **Hotspot**: the one point of the cursor image that is the click point.
- **WindowServer**: the macOS process that composites every window on screen and draws the cursor.
- **Commit**: one batch of Core Animation layer changes sent to WindowServer.
- **Display link**: a callback that runs once per screen refresh.
- **Connection property**: a setting on the app's own private link to WindowServer.

## What macOS allows

| Technique | Over other apps? | Lag behind the hand | Permission or private API | Risk |
|---|---|---|---|---|
| A. Aura drawn in the overlay around the visible real cursor | Yes, while inking [Inferred from code] | About 1 frame [Inferred] | None new. Public API. | Low |
| B. `NSCursor.set` from the overlay, public API only | Probably not [Source] | None, if it works | None | Fails silently |
| C. `NSCursor.set` plus the `SetsCursorInBackground` property | Sources disagree | None [Inferred] | Private connection property | Medium |
| D. Activate Vignette, then use `NSCursor` normally | Yes [Inferred] | None | None | Takes focus from the person's app. Reject. |
| E. Hide the real cursor, draw our own | Yes, except over the Dock [Source] | The whole pointer lags | Private property plus public hide | High: the cursor can stay hidden |
| F. Scale the real cursor (`SLSSetCursorScale`) | Yes, it is global [Source] | None [Inferred] | Private | Medium: the size survives a crash |
| G. Register new system cursor images (Mousecape's method) | Partly [Source] | None, but flipbook animation only | Private | High: survives a crash, mixed results on Tahoe |
| H. Accessibility pointer size and colour settings | System-wide | Not a live effect | Writes the person's own preference | Reject |
| I. Warp the cursor (`CGWarpMouseCursorPosition`) | Not a visual technique | Not applicable | Public | Reject: moves the person's pointer |

**A. Aura in the overlay.** While the chord is held, each screen's `LiveInkOverlay` is a non-activating panel that never becomes key. It rises to `.screenSaver` level (1000) with `ignoresMouseEvents = false`. Its Canvas has a `.mouseMoved/.activeAlways` tracking area, and `EdgeGlow.follow` already moves with the pointer from those events, with no smoothing [Mac: LiveInkOverlay.swift lines 46, 73-74, 90-91, 153, 189-208]. So the plumbing for a pointer-following effect already exists. The real arrow stays on top: the cursor's window level is `INT32_MAX - 17` [Mac: CGWindowLevel.h], and the overlay sits at 1000. The header does not say the cursor is drawn above every window, so that part is [Inferred]. The aura arrives at least one commit after the arrow moves [Inferred]. A large, springy aura makes that lag read as following. A tight ring on the hotspot shows it.

**B and C. Changing the arrow's image.** AppKit says `.activeAlways` is "Not supported for NSTrackingCursorUpdate" [Mac: NSTrackingArea.h:29]. Vignette is never the active app (LSUIElement, `.accessory`) [Mac: project.yml:69, AppDelegate.swift:82], so plain `NSCursor.set` is expected to do nothing visible. An Apple DTS (Developer Technical Support) thread reports that set, push, cursor rects and cursorUpdate all fail for an inactive app's panel [Source: forums 738051]. The private property `SetsCursorInBackground` is the known workaround, and the sources disagree about it:
- Wox, codenotch and ColorTxt each say that once the property is set, `NSCursor.set` from a background panel changes the real cursor [Source].
- tungsten-edge says `NSCursor.set` is ignored even with the property set [Source].

Neither covers our exact case, where the pointer is over the app's own `.screenSaver` window. If it works, there is no lag, because WindowServer still draws the cursor. The cost is that the animation becomes swapped whole images, and the app under the pointer may re-assert its own cursor [Source: codenotch re-sets on every drag step]. The property reads as unset by default here [Mac: `SLSCopyConnectionProperty` returned nil]. Setting it was not tried.

**E. Hide and replace.** `CGDisplayHideCursor` works only for the foreground app "in most cases" [Mac: Apple docs JSON]. It also keeps a hide count that every exit path must balance [Mac: CGDirectDisplay.h:395-398]. A background app can hide the cursor with the private property, and Ice, Vimac, Mac Mouse Fix, warpd and Snapzy ship this [Source]. Its failures:
- Over the Dock, WindowServer gives cursor control back to the Dock and the arrow returns [Source: DTS, forums 756199].
- The hide count is per thread, and a leaked count left the cursor missing in IceMelt on 26.6.1 [Source: IceMelt #28].
- The drawn replacement is now the cursor the person aims with, so its lag becomes the cursor's lag [Inferred].
- Live-ink overlays are `sharingType .none` [Mac: line 52], so screenshots and recordings would show no cursor at all [Inferred].

**F. Cursor scale.** `SLSSetCursorScale` (and `CGSSetCursorScale`, re-exported from it) resolves here [Mac]. `SLSGetCursorScale` writes a 4-byte float and reads 1.0 [Mac]. NUIKit's CGFloat declaration is wrong. The scale is global and lives in WindowServer, so a crash mid-animation leaves the arrow enlarged unless a helper process restores it [Source: mouse-teleportation docs]. Nobody has measured how smoothly it animates. It can only scale the whole arrow: no colour, no glow.

**G. Registration.** Mousecape-style registration can animate the real cursor natively, but only as a flipbook of whole frames. Apple's own `busybutclickable` cursor works that way: 15 frames at 0.033 s each [Mac: its info.plist]. Registrations outlive the process. On Tahoe, each cursor needs extra name variants, one per name the system uses, and removing the Arrow registration fails, so restoring means re-registering a saved copy. One project found that registration never changed the screen on Tahoe [Source: CursorForge, MaCursor, RetroMac]. This is the wrong scope for a hold-to-ink mode.

**Probe corrections and claims dropped:**
- `CoreCursorSet` and `CoreCursorUnregisterAll` are in HIServices, not SkyLight or CoreGraphics [Mac].
- `CGCursorIsDrawnInFramebuffer` is unavailable since 10.9, so its return value proves nothing [Mac].
- The keys `cursorFill` and `cursorOutline` do not exist in `com.apple.universalaccess`. Only `mouseDriverCursorSize = 1` is there [Mac].
- The `SLSHardwareCursorActive` readings rest on a guessed return type, so they are dropped.
- The `NSScreen` displayLink declaration is at NSScreen.h:132.

## Options for the look

**1. Ink nib and halo (recommended).**
- **What it looks like:**
  - A small nib in the person's ink colour sits at the hotspot.
  - A soft ring follows on a critically damped spring.
  - When the chord goes down, the ring grows in, borrowing the feel of shake-to-locate.
  - On a press, it shrinks and darkens, as the iPadOS pointer does [Source: WWDC20 10640].
  - Over a mark a tap would erase or pick, it changes tint.
- **How to build it:**
  - Add a layer next to `glow` in Canvas (LiveInkOverlay.swift, near line 151).
  - Feed it from the same `mouseMoved`, `mouseDown` and `mouseDragged` handlers (lines 189-208).
  - Seed its position from `NSEvent.mouseLocation`, as `showGlow` does (LiveInk.swift:1604).
  - Animate the spring with `Tween.swift`.
  - Take the tint from `hover(at:)` (LiveInk.swift:454).
  - Gate it with the glow delay and `Settings.motionUI` (Reduce Motion means 0), or Control+Option shortcuts will flash it.
- **How it feels:** native. The iPad separates a visible pointer from the model pointer and lets the visible one spring after it, so a trailing halo matches Apple's own pointer vocabulary [Source: WWDC20 10640].
- **The nib also lags:** it trails the arrow exactly as the halo does. Its real benefit is narrower. The nib and the stroke head come from the same event, so no gap opens between them [Inferred].
- **Risk:** low. It is public API, and if the overlay goes, the aura goes with it.
- **Two details to handle:**
  - Each screen's overlay only hears the pointer over its own screen, so the aura needs a hand-over when the pointer crosses screens.
  - Fast scribbling may trigger shake-to-locate, which would enlarge the arrow under the halo [Inferred].

**2. Comet trail or particle wake.**
- **How to build it:** the same plumbing as option 1, keeping a short history of positions. Use a `CAEmitterLayer`, or Metal if needed (docs/live-ink-look-2026-10-07.md already names Metal as the next step up).
- **How it feels:** fluid and playful.
- **Risk:** Apple warns that decorative pointers "distract and even irritate" [Source: WWDC20 10640]. The GPU cost is unmeasured. Best as a short burst at chord-down rather than all the time.

**3. Pen cursor swap.**
- **What it looks like:** while inking, the arrow becomes a nib cursor, with a few states: idle, pressing, over a mark.
- **How to build it:** `NSCursor(image:hotSpot:)` set from the Canvas handlers, maybe with `SetsCursorInBackground`, then `NSCursor.arrow.set()` in `stopInking`.
- **How it feels:** the most native, because WindowServer draws it with no lag [Inferred].
- **Depends on spike 2.** It leaves no hide count, so it cannot strand an invisible cursor [Inferred]. It pairs well with option 1: an exact nib cursor plus a springy halo.

**4. Grow-in pulse of the real arrow.**
- **How to build it:** animate `SLSSetCursorScale` from a helper process that restores the scale if Vignette dies.
- **How it feels:** very native, since it is the shake-to-locate mechanism itself [Inferred].
- **Risk:** medium. It is private and global, and the size survives a crash. Keep it for a later spike, not the first build.

**5. Hide the arrow and draw a full custom cursor.** Reject it:
- The pointer itself lags.
- The arrow comes back over the Dock.
- A leaked hide count leaves the cursor missing.
- Recordings lose the cursor.
- The app under the pointer can no longer show its I-beam or resize cursors.

**Recommendation: option 1, with option 3 added if spike 2 passes.** Option 1 is the only treatment that is public, fluid, safe on every exit path and buildable today on code that already exists. It also matches how Presentify and Mouseposé present a pointer [Source], and Apple's own pointer vocabulary. Whether it replaces the edge glow or joins it is a product call, best made in a lab build.

## What to spike first

**Spike 1: how far the aura trails the arrow at 120 Hz.**
- **Method:** in a lab copy, drive the halo two ways.
  - Per event, as `EdgeGlow` is driven today.
  - From a display link that reads `NSEvent.mouseLocation` once per refresh. That property returns the location "regardless of the current event or pending events" [Mac: Apple docs JSON].
- **Measuring:** film the built-in display with an iPhone in 240 fps slow motion. `screencapture -v` with `frames.sh` cannot measure this, because capture draws its own cursor at sample time [Source: OBS thread]. The VM cannot measure it either, because VNC may draw the cursor on the client [Inferred].
- **What would change the decision:**
  - About 1 frame (8.3 ms or less) means a tight ring is fine. One research probe measured an 8.33 ms tick here [Source: not rechecked].
  - 2 frames or more means the ring must stay large and springy, and option 3 becomes the centre of the design.
- **A launch-path check:** the same test shows whether Vignette pays the reported one-refresh penalty for apps launched through `open` [Source: peeknext.com, forums 841189].
- **Budget:** half a day.

**Spike 2: can the overlay change the real cursor's image?**
- **Method:** a lab copy with its own bundle id and scratch settings. While inking, set a pen `NSCursor` from `mouseMoved` and `mouseEntered`:
  - (a) plain;
  - (b) after setting `SetsCursorInBackground`.
- **Where to try it:**
  - over TextEdit;
  - over an open menu;
  - over the Dock area;
  - with the overlay's pixels fully clear, and again with a near-zero alpha. DTS says fully clear windows are treated differently [Source: forums 756199].
- **Which machines:** this Mac (15.7.3) and the Tahoe VM (26.6.2). The VM can answer "did the image change?" through its own `screencapture`, not through the VNC view.
- **What would change the decision:**
  - (a) works: option 3 is public and goes in.
  - Only (b) works: option 3 is a private but low-risk opt-in.
  - Both fail: aura only.
- **Before running it:** this spike changes the real cursor, so it needs Pete's go-ahead. Restore with `NSCursor.arrow.set()` on every exit path.
- **Budget:** half a day.

## Sources

**Apple documentation and SDK (Xcode SDK 26.2 headers on this Mac):**
- NSTrackingArea.h:29; NSCursor.h:27; CGDirectDisplay.h:395-398; CGRemoteOperation.h:216; CGWindowLevel.h; NSView.h:611; NSWindow.h:822; NSScreen.h:132; CVDisplayLink.h; NSEvent.h:523
- CGDisplayHideCursor: https://developer.apple.com/documentation/coregraphics/cgdisplayhidecursor(_:)
- NSEvent.mouseLocation: https://developer.apple.com/documentation/appkit/nsevent/mouselocation
- CADisplayLink: https://developer.apple.com/documentation/quartzcore/cadisplaylink
- CAMetalDisplayLink: https://developer.apple.com/documentation/quartzcore/cametaldisplaylink
- AppKit release notes for macOS 14 (display link): https://developer.apple.com/documentation/macos-release-notes/appkit-release-notes-for-macos-14
- Quartz Display Services, the mouse cursor: https://developer.apple.com/library/mac/documentation/GraphicsImaging/Conceptual/QuartzDisplayServicesConceptual/Articles/MouseCursor.html
- WWDC20 10640, Design for the iPadOS pointer: https://developer.apple.com/videos/play/wwdc2020/10640/
- Apple Support, pointer accessibility settings and shake to locate: https://support.apple.com/en-gb/guide/mac-help/mchlp2920/mac

**Apple Developer Forums:**
- https://developer.apple.com/forums/thread/738051 (inactive app cursor)
- https://developer.apple.com/forums/thread/739874 (cursorUpdate flicker)
- https://developer.apple.com/forums/thread/756199 (DTS on the Dock exception)
- https://developer.apple.com/forums/thread/841189 (launch-path latency)

**Open source:**
- Snapzy: https://github.com/duongductrong/Snapzy
- Wox: https://github.com/Wox-launcher/Wox/blob/main/wox.core/ui/runtime/internal/window/overlay_cursor_darwin.m
- codenotch: https://github.com/vinzdg/codenotch/blob/main/Sources/Notch/BackgroundCursor.swift
- ColorTxt: https://github.com/ssnangua/ColorTxt
- tungsten-edge: https://github.com/moonbai-studio/tungsten-edge
- Vimac: https://github.com/nchudleigh/vimac
- Mac Mouse Fix: https://github.com/noah-nuebling/mac-mouse-fix
- IceMelt issue 28: https://github.com/pnikolaidis/icemelt/issues/28
- mouse-teleportation: https://github.com/jeonghyeon-net/mouse-teleportation
- MaCursor: https://github.com/writronic/MaCursor
- Mousecape: https://github.com/alexzielenski/Mousecape
- CGSInternal: https://github.com/NUIKit/CGSInternal/blob/master/CGSCursor.h
- CursorForge: https://github.com/LemonNekoGH/cursor-forge
- mac-mouse-highlighter: https://github.com/nikhilbhansali/mac-mouse-highlighter

**Other:**
- Raycast mouse-cursor-toggle: https://www.raycast.com/Dhaiwat10/mouse-cursor-toggle
- Presentify: https://presentifyapp.com/
- Mouseposé: https://boinx.com/mousepose/
- OBS cursor lag thread: https://obsproject.com/forum/threads/display-capture-show-cursor-input-lag.97650
- Launch-path latency write-up: https://peeknext.com/blog/investigating-macos-latency/

**This Mac:**
- Probe files in `/private/tmp/claude-501/-Users-petepetrash-Code-vignette/420649e0-b2a7-4191-8624-24a0a0f81fa6/scratchpad/cursor-probe/`: `probe.c`, `where.c`, `tc.swift`, `tc2.swift`.
- Live-ink worktree `/Users/petepetrash/Code/worktrees/vignette/live-ink-app`, branch `live-ink`, b2f20ca: Sources/LiveInkOverlay.swift, Sources/LiveInk.swift, Sources/Tween.swift, docs/live-ink.md, docs/live-ink-look-2026-10-07.md.
