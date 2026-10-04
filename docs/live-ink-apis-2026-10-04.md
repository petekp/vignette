# Live ink: the macOS APIs behind it (research, 2026-10-04)

This note answers the platform questions behind the live ink spike
(`docs/live-ink-spike-2026-10-04.md`). The target Mac runs macOS 15.7 on Apple silicon.

"Live ink" means three steps:

- The person draws on the live screen, in a transparent overlay window above every app.
- Vignette builds a context packet about what the drawing points at and sends it to Claude Code or Codex.
- The agent draws back on the live screen.

Every claim has a source. Each is tagged with how firm it is:

- **source**: read in Apple's documentation, a header, or the project's own code.
- **Apple engineer**: an Apple engineer said it in a WWDC session or a forums answer.
- **vendor**: a product's maker said it about their own product.
- **third-party**: someone else reported it.
- **inferred**: my conclusion from the cited material, not stated anywhere.
- **unverified**: I could not confirm it.

All research was on the web. Nothing here was measured on the target Mac.

**macOS 27 is out.** The brief calls macOS 26 current, but third-party reports say macOS 27 was announced at WWDC on 2026-06-08 and released on 2026-09-14. It drops Intel Macs. (third-party: https://www.mactrast.com/2026/09/apple-announces-27-operating-systems-public-release-date/, https://www.mactech.com/2026/09/09/macos-27-will-arrive-on-september-14-along-with-other-os-updates/amp/) Where an API is new in macOS 27, this note says so.

## What most affects the design

1. **Leave the overlay out of the capture with a content filter.**
   - Use `SCContentFilter(display:excludingApplications:exceptingWindows:)` with Vignette's own app, together with `SCScreenshotManager.captureImage(contentFilter:configuration:)` (macOS 14+).
   - Do not rely on `NSWindow.sharingType = .none`. Apple has an open bug about ScreenCaptureKit showing those windows.
   - Do not use the rect-only `captureImage(in:)` (macOS 15.2+). It takes no filter, so it would capture the ink.
2. **Shipping this means a new permission and a recurring prompt.**
   - Capturing other apps needs Screen Recording, which Vignette does not ask for today.
   - On macOS 15 the system then asks the person again about once a month, in words about bypassing "the system private window picker."
   - The picker (`SCContentSharingPicker`) avoids that prompt, but it is a modal choice, which does not suit a capture taken on every stroke.
   - Accessibility, which Vignette already holds, covers everything in point 3 below with no new prompt.
3. **Accessibility gives most of the packet, but nothing reports scrolling.**
   - Available: the element under a point, its frame, its role and title, Safari's and Chromium browsers' URL (`AXURL` on the web area), a document's path (`AXDocument`), and selected text.
   - No Accessibility notification exists for scrolling, and window move and resize notifications arrive only at the end of the gesture.
   - So marks pinned to content must poll the anchor's position while they are on screen.
   - Chromium builds its web tree lazily, on first contact, so the first query into a page can come back shallow.
4. **The overlay pattern has an Apple engineer's answer.**
   - Use a non-activating `NSPanel` at `.screenSaver` level, with `.canJoinAllSpaces`, `.canJoinAllApplications`, `.fullScreenAuxiliary` and `.stationary`, in an accessory app.
   - Click-through comes either from toggling `ignoresMouseEvents` or from Vignette's own measured rule: the window server passes presses through clear pixels.
5. **What stays on device depends on the macOS version.**
   - On macOS 15: Vision OCR takes roughly 130 to 230 ms per image in third-party tests, and `SFSpeechRecognizer` can run on device.
   - Foundation Models (a 4096-token window) and `SpeechAnalyzer` need macOS 26.
   - Handwriting recognition (`PKStrokeRecognizer`) needs macOS 27.
   - There is no public shape recognizer, so recognizing a circle or an arrow is Vignette's own geometry.
6. **No source publishes the latency of these calls.**
   - Unmeasured: `captureImage`, `SCShareableContent`, an Accessibility hit test, and Foundation Models on a Mac.
   - Measure each on 15.7 before deciding whether Send needs a waiting state.

## 1. ScreenCaptureKit

### Capturing a region without Vignette's own windows

- **Filters.** `SCContentFilter` has two initializers that leave things out: `init(display:excludingWindows:)` and `init(display:excludingApplications:exceptingWindows:)`. It also has `contentRect` (in screen points), `pointPixelScale` and `includeMenuBar`. (source: https://developer.apple.com/tutorials/data/documentation/screencapturekit/sccontentfilter.json)
- **Finding Vignette's own entry.** Look up its `SCRunningApplication` in `SCShareableContent.applications` by pid or bundle id, and pass it in `excludingApplications`. (inferred from the API shape)
- **One-shot capture.**
  - `SCScreenshotManager.captureImage(contentFilter:configuration:completionHandler:)` returns a `CGImage` and needs macOS 14.0. (source: https://developer.apple.com/tutorials/data/documentation/screencapturekit/scscreenshotmanager.json)
  - The region is set with `SCStreamConfiguration.sourceRect`, and the output size with `width` and `height` in pixels. (inferred)
  - WWDC23 says the old `CGWindowList` image options moved into `SCStreamConfiguration`. (Apple engineer: https://developer.apple.com/videos/play/wwdc2023/10136/)
- **The rect-only call.**
  - `SCScreenshotManager.captureImage(in:completionHandler:)` needs macOS 15.2. It captures "the contents of the rectangle in points, specified in display space." (source: https://developer.apple.com/tutorials/data/documentation/screencapturekit/scscreenshotmanager/captureimage(in:completionhandler:).json)
  - It takes no content filter, so it cannot leave the overlay out. (inferred)
- **macOS 26 additions.**
  - `SCScreenshotConfiguration` adds `contentType` (HEIC, JPEG or PNG), `fileURL`, `sourceRect`, `destinationRect`, `dynamicRange`, `showsCursor`, `ignoreShadows`, `ignoreClipping` and `includeChildWindows`. (source: https://developer.apple.com/tutorials/data/documentation/screencapturekit/scscreenshotconfiguration.json)
  - `captureScreenshot(contentFilter:configuration:)` and `captureScreenshot(rect:configuration:)` return an `SCScreenshotOutput`. Both are macOS 26.0. (source: availability read from https://developer.apple.com/tutorials/data/documentation/screencapturekit/scscreenshotmanager/captureScreenshot(contentFilter:configuration:completionHandler:).json)
- **Windows above or below a given window.**
  - `SCShareableContent` has `getExcludingDesktopWindows(_:onScreenWindowsOnlyAbove:)` and `…Below:`, which list the windows above or below a given window. (source: https://developer.apple.com/tutorials/data/documentation/screencapturekit/scshareablecontent.json)
  - `…Below:` with the overlay gives the windows under the ink. (inferred)
- **Capturing Vignette's own windows.** `getCurrentProcessShareableContent` is macOS 14.4. It is what lets Vignette capture its own windows without Screen Recording, which the menu bar intro already relies on. It does not cover other apps' windows. (source: availability read from https://developer.apple.com/tutorials/data/documentation/screencapturekit/scshareablecontent/getcurrentprocessshareablecontent(completionhandler:).json; Vignette's use: `AGENTS.md`)

### Latency

- No Apple or forum source gives a number for any of these:
  - `captureImage`
  - an `SCShareableContent` fetch
  - a running `SCStream` compared with one-shot calls
- (unverified)
- Each one-shot call sets up a capture. A warm `SCStream` cropped by `sourceRect` should therefore answer faster for repeated captures while ink is on screen. (inferred)
- Measure both on 15.7.

### `sharingType = .none`

- **No reliable source says it still hides a window from ScreenCaptureKit.**
  - A forum report: ScreenCaptureKit (Apple's sample app) left `.none` windows out at first and showed them after the filter was toggled, while QuickTime showed them at once.
  - An Apple DTS engineer replied that engineering needs to investigate and asked for a bug report (FB21115847).
  - (Apple engineer reply; the behaviour is a third-party report: https://developer.apple.com/forums/thread/808016)
- **An earlier report.** `.none` blocked screenshots but not screen recording. (third-party: https://developer.apple.com/forums/thread/770585)
- **The `screencapture` command.** I found no primary source on whether it honours `.none` on 15+. (unverified)
- **For live ink.** Leave the overlay out with the filter, which Vignette controls. Do not rely on `.none`. (inferred)

### Permissions

- **The calls.**
  - `CGPreflightScreenCaptureAccess()` checks without prompting. `CGRequestScreenCaptureAccess()` prompts. Both are macOS 10.15+. (source: https://developer.apple.com/tutorials/data/documentation/coregraphics/cgrequestscreencaptureaccess().json, https://developer.apple.com/tutorials/data/documentation/coregraphics/cgpreflightscreencaptureaccess().json)
- **The macOS 15 re-confirmation prompt.**
  - It reads "[App] is requesting to bypass the system private window picker and directly access your screen and audio." (third-party: https://support.dropshare.app/hc/en-us/articles/20871477694354)
  - During the 15.0 betas it went from daily to weekly to monthly, and it stopped asking again after every restart. (third-party: https://9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly/, https://talk.tidbits.com/t/apple-reduces-excessive-sequoia-permission-requests-shifts-to-monthly/28621)
  - macOS 15.1 added an MDM key, `forceBypassScreenCaptureAlert`, for managed Macs only. (third-party: https://heise.de/-9973354)
  - Vignette's own E2E notes record this prompt holding the test copy inactive on macOS 15. (`AGENTS.md`)
- **The system picker.**
  - `SCContentSharingPicker` (macOS 14) is the system picker. Its documentation says nothing about TCC. (source: https://developer.apple.com/tutorials/data/documentation/screencapturekit/sccontentsharingpicker.json)
  - The prompt's wording implies that capture through the picker is not asked about again. (inferred)
- **The entitlement.**
  - `com.apple.developer.persistent-content-capture` (macOS 14.4) is meant for remote-desktop (VNC) apps and needs Apple's approval. (source: https://developer.apple.com/tutorials/data/documentation/bundleresources/entitlements/com.apple.developer.persistent-content-capture.json)
  - A drawing tool is unlikely to qualify. (inferred)
- **Window titles.**
  - `kCGWindowName` from `CGWindowListCopyWindowInfo` has required Screen Recording since 10.15. (third-party: https://mjtsai.com/blog/2019/11/22/detecting-screen-recording-permission-on-catalina/)
  - One poster reports macOS 26 returned no `kCGWindowOwnerName` without the permission, while macOS 27 betas did. DTS says the reference documents no gating of these keys. (Apple engineer and third-party: https://developer.apple.com/forums/thread/839069)

## 2. Accessibility for context

### The element under a point

- **Coordinates.** `AXUIElementCopyElementAtPosition` takes global coordinates with the origin at the top left, the convention Vignette's `[state]` frames use. (source: https://developer.apple.com/tutorials/data/documentation/applicationservices/1462077-axuielementcopyelementatposition.json; https://www.hammerspoon.org/docs/hs.axuielement.html)
- **What it hits.**
  - It hit-tests "based on window z-order" and returns the object from "whichever window is topmost."
  - With the system-wide element, the test is not limited to one app.
  - With an application element, it is limited to the app that contains the point.
  - `kAXErrorNoValue` means nothing is at that point.
  - (source: AXUIElement.h, https://raw.githubusercontent.com/phracker/MacOSX-SDKs/master/MacOSX11.3.sdk/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/Headers/AXUIElement.h)
- **Whether the overlay gets hit.**
  - Nothing documents whether a window with `ignoresMouseEvents` set, or a clear window, is skipped. (unverified; a claim at https://github.com/anthropics/claude-code/issues/85110 cites no Apple source)
  - Quick Look windows are reported as skipped. (third-party: https://github.com/sbmpost/AutoRaise/issues/292)
- **Keeping Vignette's own windows out.** (inferred from the header)
  - Find the topmost window under the point other than the overlay, with `CGWindowListCopyWindowInfo`.
  - Hit-test on `AXUIElementCreateApplication(pid)` for that window's app.
  - Check `AXUIElementGetPid` on the answer.
- **Timeout.**
  - `AXUIElementSetMessagingTimeout` on the system-wide element sets the timeout for the whole process. On another element it sets it for that element only.
  - A timeout returns `kAXErrorCannotComplete`. (source: AXUIElement.h, as above)
  - The default is commonly given as 6 s. (third-party: https://support.touch-base.com/Print50647.aspx)
  - Run these calls off the main thread with a short timeout. (inferred)
- **Latency.** No published numbers. (unverified)
- **A hazard.** On macOS 26.6.2, a single hit test into a SwiftUI `LazyVStack` hung that app's main thread on its next scroll. (third-party: https://github.com/journey-ad/AccessibilityLazyVStackPoC)

### URL, document, text and frames

- **A browser's URL through Accessibility.**
  - WebKit exposes `AXURL` on the web area and on links. (source: https://raw.githubusercontent.com/WebKit/WebKit/main/Source/WebCore/accessibility/mac/WebAccessibilityObjectWrapperMac.mm)
  - Chromium's `AXWebArea` returns the document's URL. (source: https://chromium.googlesource.com/chromium/src/+/main/ui/accessibility/platform/ax_platform_node_cocoa.mm)
  - AltTab reads "`AXDocument` on the window, or `AXURL` on the tab's `AXWebArea`." That path is "tested unchanged in Safari, Safari Technology Preview, Chrome, Orion and Firefox," at about 3 to 5% more Chrome CPU. (third-party: https://github.com/lwouis/alt-tab-macos/pull/6039)
  - Arc is Chromium, so it should behave the same. (inferred)
- **A browser's URL through AppleScript.**
  - Chromium browsers have a scripting dictionary: `URL of active tab of front window`. (source: https://www.chromium.org/developers/design-documents/applescript/)
  - Firefox has no supported way to read tab URLs. (source: https://wiki.mozilla.org/Mac:AppleScript)
  - AppleScript needs `NSAppleEventsUsageDescription` and an Automation consent for each browser. (source: https://developer.apple.com/tutorials/data/documentation/bundleresources/information-property-list/nsappleeventsusagedescription.json)
  - Prefer Accessibility, which needs no new consent. (inferred)
- **A document's path.**
  - `kAXDocumentAttribute` (`AXDocument`) is in AXAttributeConstants.h, with no comment. (source: https://raw.githubusercontent.com/phracker/MacOSX-SDKs/master/MacOSX11.3.sdk/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/Headers/AXAttributeConstants.h)
  - Full-screen windows and background tabs can be missing from `AXWindows`. (third-party: https://developer.apple.com/forums/thread/121114)
  - Electron's `setRepresentedFilename`, which VS Code calls, sets a window's represented file. (source: https://github.com/electron/electron/blob/main/docs/api/base-window.md) That it then shows up as `AXDocument` is inferred.
- **Text, frames and identifiers.**
  - Header definitions: `kAXSelectedTextAttribute`, `kAXSelectedTextRangeAttribute` (in characters), `kAXBoundsForRangeParameterizedAttribute`, `kAXPositionAttribute` (the global top-left corner) and `kAXSizeAttribute`. (source: AXAttributeConstants.h, as above)
  - `AXFrame` is not in the header. Use position plus size. (source)
  - Web content uses text markers (`AXSelectedTextMarkerRange`). (source: https://chromium.googlesource.com/chromium/src/+/main/ui/accessibility/platform/browser_accessibility_cocoa.mm)
  - `AXTitle`, `AXDescription`, `AXRole` and `AXIdentifier` are in the header.
  - Chromium and WebKit also expose `AXDOMIdentifier` and `AXDOMClassList`. (source: the Chromium and WebKit files above)
  - WebKit reads a default, `AXEnableWebKitDOMIdentifier`. What it gates is unverified. (source: https://raw.githubusercontent.com/WebKit/WebKit/main/Source/WebCore/accessibility/mac/AXObjectCacheMac.mm)

### Following elements and windows

- **The notifications that exist.** `AXMoved`, `AXResized`, `AXWindowMoved`, `AXWindowResized`, `AXFocusedWindowChanged`, `AXUIElementDestroyed`, `AXValueChanged`, `AXLayoutChanged`, `AXSelectedChildrenChanged`, `AXTitleChanged`, `AXCreated`, among others. (source: https://raw.githubusercontent.com/phracker/MacOSX-SDKs/master/MacOSX11.3.sdk/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/Headers/AXNotificationConstants.h)
- **What the header says about them.**
  - A window move or resize is "sent at the end of the window move, not continuously."
  - `AXValueChanged` fires only for the value attribute.
  - A destroyed element is no longer valid. (source: same header)
- **Scrolling.**
  - No scroll notification exists. (source: same header)
  - Chromium's macOS mapper lists its scroll-position events as "currently unused on this platform." (source: https://chromium.googlesource.com/chromium/src/+/main/ui/accessibility/platform/browser_accessibility_manager_mac.mm)
  - WebKit's macOS `handleScrolledToAnchor` is empty. (source: AXObjectCacheMac.mm, as above)
- **Following content anyway.** (inferred)
  - Poll the anchor's `AXPosition` on a display-link tick while marks are shown.
  - Observe `AXValueChanged` on an `AXScrollBar` as a hint. Whether native scrollers post it is unverified.
  - Find the element again after `AXUIElementDestroyed` or `AXLayoutChanged`.
- **Following a window drag live.**
  - Poll `kCGWindowBounds` from `CGWindowListCopyWindowInfo`. Apple calls generating these dictionaries "relatively expensive." (source: https://developer.apple.com/tutorials/data/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:).json)
  - The 2026-09-18 demo followed a live resize at 30 Hz this way. (`docs/live-screen-2026-09-18.md`)
- **App switches.** `NSWorkspace.didActivateApplicationNotification` arrives only on `NSWorkspace.shared.notificationCenter`. (source: https://developer.apple.com/tutorials/data/documentation/appkit/nsworkspace/didactivateapplicationnotification.json)

### Chromium and Electron

- **What turns on Chromium's accessibility.**
  - It turns on when a client sets `AXEnhancedUserInterface`, or with `--force-renderer-accessibility`. (source: https://www.chromium.org/developers/design-documents/accessibility/)
  - On macOS 14+, a client reading `accessibilityRole` turns on a basic mode. (source: https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/chrome_browser_application_mac.mm)
  - Reaching the web contents and asking its role enables the basic tree for that process "so that the AT can descend further." (source: https://chromium.googlesource.com/chromium/src/+/main/content/app_shim_remote_cocoa/render_widget_host_view_cocoa.mm)
  - So the first hit test into a page may stop at the container. Retry after a short delay. (inferred)
- **Electron.**
  - `AXManualAccessibility` is Electron's own attribute. Setting it to true on the app element turns on the full tree; Electron treats it like `AXEnhancedUserInterface`. (source: https://github.com/electron/electron/blob/main/shell/browser/mac/electron_application.mm, https://www.electronjs.org/docs/latest/tutorial/accessibility)
  - Electron's docs once warned that the full tree "can significantly affect the performance of your app." (source: https://ayakael.net/mirrors/electron/commit/e6733b4b23ccad59bdb199d08ac3048d6bdb5279)
  - This applies to VS Code, Slack and Cursor. (inferred)
- **Side effects of `AXEnhancedUserInterface`.** Rectangle turns it off while moving windows, because its animated updates "produce incorrect frames," and Chromium may start "expensive web accessibility processing." (third-party: https://github.com/rxhanson/Rectangle/blob/main/TerminalCommands.md) Do not set it. Use `AXManualAccessibility` only for Electron apps, and only when the basic tree is not enough. (inferred)
- **Permission.**
  - All of this runs under the Accessibility trust Vignette already has (`AXIsProcessTrustedWithOptions`). (source: https://developer.apple.com/tutorials/data/documentation/applicationservices/1459186-axisprocesstrustedwithoptions.json)
  - Accessibility does not work in sandboxed apps. Vignette is not sandboxed. (Apple engineer: https://developer.apple.com/forums/thread/794253)
- **macOS 26 changes to Accessibility.** I found no primary source on any. (unverified)

## 3. Text recognition

### `VNRecognizeTextRequest`

- **The two levels.**
  - `.fast` uses character detection and "a small machine learning model."
  - `.accurate` uses "a neural network to find text in terms of strings and lines."
  - Language correction is optional at both levels and can be steered with `customWords`.
  - (source: https://developer.apple.com/tutorials/data/documentation/vision/recognizing-text-in-images.json, https://developer.apple.com/tutorials/data/documentation/vision/vnrequesttextrecognitionlevel.json)
- **Revisions.** Revision 3 is current. (source: https://developer.apple.com/tutorials/data/documentation/vision/vnrecognizetextrequest.json)
- **Limiting the region.**
  - `regionOfInterest` is normalized to the image, with the origin at the lower left. (source: https://developer.apple.com/documentation/vision/vnimagebasedrequest/regionofinterest)
  - So the circled area can be recognized inside a larger capture without cropping first. (inferred)
- **`minimumTextHeight`.** A fraction of the image height. Raising it skips small text. (source: as above)

### The newer Swift API

- **`RecognizeTextRequest`** is macOS 15.0. It has `recognitionLevel`, `usesLanguageCorrection`, `minimumTextHeightFraction`, `recognitionLanguages`, `automaticallyDetectsLanguage` and `customWords`. (source: https://developer.apple.com/tutorials/data/documentation/vision/recognizetextrequest.json)
- **WWDC24 on the Swift API.** It is async, and `performAll` streams the results of several requests. "New features will only be introduced in Swift going forward." No speed claim. (Apple engineer: https://developer.apple.com/videos/play/wwdc2024/10163/)
- **macOS 26: `RecognizeDocumentsRequest`.** It groups text into words, lines and paragraphs, and finds tables, lists, emails, phone numbers and URLs, in 26 languages. No speed claim. (source and Apple engineer: https://developer.apple.com/tutorials/data/documentation/vision/recognizedocumentsrequest.json, https://developer.apple.com/videos/play/wwdc2025/272/)

### Speed

- **ocrmac, a Python wrapper, on an M3 Max.**
  - Accurate: 207 ms. Fast: 131 ms. The VisionKit "livetext" path: 174 ms.
  - The test image is 1105 by 858 px.
  - (third-party: https://github.com/straussmaximilian/ocrmac)
- **An older figure.** A 2021 14-inch MacBook Pro: 233 ms accurate, 200 ms fast. (third-party, unverified)
- **A ~1500 px crop.**
  - No timing has been published. (unverified)
  - Expect roughly 150 to 300 ms with `.accurate` on M1-class hardware, and a slower first call. (inferred) Measure it.
- **A design consequence.** Accessibility text where it exists, with OCR only for what it misses, fits inside a 200 ms budget more often than OCR alone. (inferred)

### VisionKit

- **`ImageAnalyzer`** (macOS 13) analyzes `.text`, `.machineReadableCode` and `.visualLookUp`. `ImageAnalysis.transcript` gives the plain text. (source: https://developer.apple.com/tutorials/data/documentation/visionkit/imageanalyzer.json, https://developer.apple.com/tutorials/data/documentation/visionkit/imageanalysis.json)
- **`ImageAnalysisOverlayView`** adds Live Text selection, data detectors, subject lifting and visual look up over an image. (source: https://developer.apple.com/tutorials/data/documentation/visionkit/imageanalysisoverlayview.json)
- **Speed.** The only number is ocrmac's 174 ms above.

## 4. Overlay windows

### Level and Spaces

- **An Apple DTS engineer's answer** on drawing over full-screen apps (Apple engineer: https://developer.apple.com/forums/thread/826308):
  - "macOS doesn't layer regular foreground apps above other apps' full-screen Spaces." Overlay utilities use the accessory activation policy.
  - "An NSWindow activates its app when ordered front, which can cause a full-screen app to exit its Space. An NSPanel with the .nonactivatingPanel style mask doesn't."
  - "You need .screenSaver (level 1000) — .floating (3) and .statusBar (25) both sit below full-screen content."
  - The engineer's sample uses `isFloatingPanel = true`, `hidesOnDeactivate = false` and `level = .screenSaver`. It sets `collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary]` and calls `orderFrontRegardless()`. It was tested over full-screen Safari, QuickTime and YouTube.
- **The menu bar.** `.screenSaver` sits above it. (inferred)
- **Window cycling.** Add `.ignoresCycle` so ⌘` passes over the overlay. (inferred)
- **Displays.** Use one panel per display. (`docs/live-screen-2026-09-18.md`)
- **Apple's other levels.** I found no Apple guidance on `CGShieldingWindowLevel` or `kCGOverlayWindowLevel` for this use. (unverified)
- **Matches what Vignette already does.** The 2026-09-18 demo used a non-activating panel at `.screenSaver` with `canJoinAllSpaces` and `fullScreenAuxiliary`.

### Click-through

- **Apple's documentation.** `ignoresMouseEvents` is described only as "whether the window is transparent to mouse events." (source: https://developer.apple.com/tutorials/data/documentation/appkit/nswindow/ignoresmouseevents.json)
- **Vignette's own measurements.**
  - The window server gives a press to a window only where its pixel is not clear, and shadows pass presses through.
  - Setting `ignoresMouseEvents` either way overrides that: the window then takes or passes every press, whatever its pixels.
  - (`AGENTS.md`, the matte rule)
- **Two ways to switch between drawing and passing clicks.** (inferred)
  - Set `ignoresMouseEvents` to false while ink mode is on, and true otherwise.
  - Or leave it unset, and paint a nearly invisible fill (Vignette's "hair of alpha") over the screen while drawing.
- **The press lag.**
  - Vignette measured 6 to 97 ms between a window becoming visible and the window server giving it presses. (`AGENTS.md`, flight rules)
  - So arm ink mode before the first stroke, or hold the first press as the flight layer does. (inferred)

### Other apps

- **KeyCastr** (open source). Its overlays are borderless windows at `NSScreenSaverWindowLevel`, not opaque, with a clear background, and the click visualizer adds `CanJoinAllSpaces`. (source: https://github.com/keycastr/keycastr/blob/master/keycastr/KCMouseEventVisualizer.m, https://github.com/keycastr/keycastr/blob/master/keycastr/KCDefaultVisualizer.m)
- **macos-screenannotator.** It describes full-screen transparent panels per display, toggled with ⌃⌥A. I could not read its window setup. (third-party: https://github.com/nfunky/macos-screenannotator)
- **adammcarter/annotate.** An MCP server for macOS 14+ that draws circles, underlines, highlights, arrows and text on a click-through Core Animation overlay on each screen. Its `annotate_locate` tool finds a real element's position "so nothing is guessed." It is the closest open-source match to "the agent draws back," but it is one commit old. (source: https://github.com/adammcarter/annotate)
- **Closed-source tools.** Presentify, ScreenBrush, Epic Pen and DemoPro publish nothing on how they work. (unverified)
- **Apple's own overlays.** Apple documents nothing about how Screen Sharing's drawing or Markup overlays are built. (unverified)

## 5. Input

### Force Touch trackpad

- **`NSEvent.pressure`.**
  - Pressure runs 0 to 1 within each stage, and a mouse reports only 0 or 1.
  - Reading it on events other than mouse down, up or drag, tablet point, or pressure raises an exception.
  - (source: https://developer.apple.com/tutorials/data/documentation/appkit/nsevent/pressure.json)
- **`stage`.** It is 0, 1 or 2, and stage 2 is a force click. (source: https://developer.apple.com/tutorials/data/documentation/appkit/nsevent/stage.json)
- **`PressureBehavior.primaryGeneric`.**
  - Apple calls it "ideal for drawing, painting." Variable pressure arrives throughout the gesture, on "a separate event stream from the mouse events."
  - The default behavior turns stage 2 off once dragging starts.
  - (source: https://developer.apple.com/documentation/appkit/nsevent/pressurebehavior-swift.enum)
- **Apple's sample.** ForceTouchCatalog's drawing view sets `pressureConfiguration = NSPressureConfiguration(pressureBehavior: .primaryGeneric)` "so that the user does not get force clicks when drawing." It reads `pressureChange` events alongside `leftMouseDragged`. (source: https://developer.apple.com/library/archive/samplecode/ForceTouchCatalog/Listings/ForceTouchCatalog_DrawingView_swift.html)
- **Untested.** Whether a non-activating overlay panel receives pressure events. (unverified) Test it.

### Apple Pencil through Sidecar

- **Events.**
  - Pencil events "come in basically as normal mouse events" with subtype `.tabletPoint`, carrying pressure.
  - The predicted and estimated updates that iOS gives are "not present on the Mac."
  - (Apple engineer: https://developer.apple.com/videos/play/wwdc2019/210/)
- **Double-tap.**
  - It arrives as `NSResponder.changeMode(with:)` (macOS 10.15). (source: https://developer.apple.com/documentation/appkit/nsresponder/changemode(with:))
  - It must be turned on in Sidecar settings and needs a second-generation Pencil or later. (source: https://support.apple.com/en-us/102597)
  - One developer reports `changeMode` never firing on 15.2 with a Pencil Pro. (third-party: https://developer.apple.com/forums/thread/771628)
- **Tilt.** `NSEvent.tilt` is valid for tablet points. Whether Sidecar fills it in is unverified.
- **macOS 27.** Sidecar finger touch reaches apps only through gesture recognizers, not through event monitors or `sendEvent`. (source: https://developer.apple.com/documentation/technotes/tn3212-adopting-gesture-recognizers-for-sidecar-touch-support)

### Handwriting and shape recognition

- **PencilKit on the Mac.**
  - The framework is on macOS 10.15+. (source: https://developer.apple.com/documentation/pencilkit)
  - `PKCanvasView` is a `UIScrollView`, so it is iOS and Mac Catalyst only. (source: https://developer.apple.com/documentation/pencilkit/pkcanvasview)
  - Native AppKit can build a `PKDrawing` from its own `PKStroke` and `PKStrokePoint` values (location, time, force, azimuth, altitude) and render it. (source: https://developer.apple.com/documentation/pencilkit/pkdrawing-swift.struct, https://developer.apple.com/documentation/pencilkit/pkstrokepoint-swift.struct)
- **`PKStrokeRecognizer`.**
  - An on-device handwriting recognizer and search over a `PKDrawing`.
  - **macOS 27.0+ only.** It works best on writing "scaled as if drawn on standard US Letter or A4 paper in points."
  - (source: https://developer.apple.com/documentation/pencilkit/pkstrokerecognizer)
- **macOS 15 and 26.** No public handwriting recognizer. (inferred from the above)
- **Smart Script.** No public API found. (unverified)
- **Scribble.** `UIScribbleInteraction` is iOS and Mac Catalyst only. (source: https://developer.apple.com/documentation/uikit/uiscribbleinteraction)
- **Shapes.**
  - `VNDetectContoursRequest` finds edge contours in an image. It is not a shape classifier. (source: https://developer.apple.com/documentation/vision/vndetectcontoursrequest)
  - Telling a circle from an arrow or an underline is Vignette's own stroke geometry. (inferred)

## 6. On-device intelligence

### Foundation Models (macOS 26+)

- **Availability.**
  - `SystemLanguageModel` is macOS 26.0.
  - Availability can fail as `.deviceNotEligible`, `.appleIntelligenceNotEnabled` or `.modelNotReady`.
  - (source: https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
- **Context window.**
  - "4096 tokens per language model session," counting instructions, prompts, tool and `@Generable` schemas, and every response.
  - Going over throws `.exceededContextWindowSize`.
  - For long text, chunk it and summarize each chunk in a new session.
  - A token is about 3 to 4 characters of English.
  - (source: https://developer.apple.com/tutorials/data/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)
- **The model.**
  - About 3B parameters, at 2 bits per weight.
  - It is "not designed to be a chatbot for general world knowledge." It is good at summarization and extraction.
  - (source: https://machinelearning.apple.com/research/apple-foundation-models-2025-updates)
- **Latency.**
  - Apple's only figures are from 2024, on iPhone 15 Pro: about 0.6 ms per prompt token to the first token, then 30 tokens per second. (source: https://machinelearning.apple.com/research/introducing-apple-foundation-models)
  - No Mac benchmark found. (unverified)
- **Which Macs.** A Mac with M1 or later, up to 8 GB of storage, and the device and Siri languages must match. (source: https://support.apple.com/en-us/121115)
- **macOS 27.**
  - Prompts can carry images.
  - The session's example prints a `contextSize` of 8192.
  - Private Cloud Compute has a 32,000-token window.
  - (Apple engineer: https://developer.apple.com/videos/play/wwdc2026/241/)
  - Reports say the 8192 window applies only to newer hardware. (third-party, unverified)
- **For live ink.** A context packet's text (window title, element path, URL, OCR of one crop) should fit in 4096 tokens without chunking. (inferred) The agent itself reads the packet, so a local summary is optional.

### Speech on macOS 15: `SFSpeechRecognizer`

- **Requirements.**
  - It needs `NSSpeechRecognitionUsageDescription`, the Speech Recognition prompt, and a separate Microphone prompt.
  - `requiresOnDeviceRecognition` is honoured only when `supportsOnDeviceRecognition` is true, and "on-device requests won't be as accurate."
  - (source: https://developer.apple.com/documentation/speech/sfspeechrecognizer, https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition, https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition)
- **Limits.** Server requests are limited to one minute of audio and to daily per-device quotas. "With on-device recognition, these limits do not apply." (Apple engineer: https://developer.apple.com/videos/play/wwdc2019/256/)

### Speech on macOS 26: `SpeechAnalyzer`

- **The API.**
  - `SpeechAnalyzer`, `SpeechTranscriber` and `DictationTranscriber` are macOS 26.0.
  - Models install through `AssetInventory`, and `prepareToAnalyze` preloads one.
  - (source: https://developer.apple.com/documentation/speech/speechanalyzer, https://developer.apple.com/documentation/speech/speechtranscriber)
- **WWDC25.**
  - The model is "faster and more flexible" than `SFSpeechRecognizer`.
  - Rough "volatile results" arrive "almost as soon as they're spoken."
  - The model runs outside the app's memory.
  - (Apple engineer: https://developer.apple.com/videos/play/wwdc2025/277/)
- **Permission.**
  - Apple's permission article says the Speech Recognition flow applies to `SFSpeechRecognizer`. (source: the permission article above)
  - The WWDC sample checks only the microphone.
  - Whether `SpeechAnalyzer` raises the Speech Recognition prompt is unverified.
- **Speed.** A 34-minute video took 45 s, against 1 min 41 s for MacWhisper Large V3 Turbo. (third-party: https://www.macstories.net/stories/hands-on-how-apples-new-speech-apis-outpace-whisper-for-lightning-fast-transcription/)
- **For "say what you mean while you circle it."** On 15.7, `SFSpeechRecognizer` on device is the available path. Its volatile partial results can be shown beside the ink as the person speaks. (inferred)

## 7. Visual language

### Liquid Glass (macOS 26+)

- **`NSGlassEffectView`.**
  - It "embeds its content view in a dynamic glass effect."
  - Its properties are `contentView`, `cornerRadius`, `style` (`.regular` or `.clear`) and `tintColor`.
  - (source: https://developer.apple.com/documentation/appkit/nsglasseffectview, https://developer.apple.com/documentation/appkit/nsglasseffectview/style-swift.enum)
- **`NSGlassEffectContainerView`.** It merges glass views that come within `spacing` of each other, in one sampling pass. (source: https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview)
- **WWDC25 session 310.**
  - It shows `glass.contentView = view` and `glass.cornerRadius = 999`.
  - It says to remove `NSVisualEffectView` where glass replaces it.
  - (Apple engineer: https://developer.apple.com/videos/play/wwdc2025/310/)
- **SwiftUI.** The equivalent is `glassEffect(_:in:)`. (source: https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:))
- **On macOS 15.**
  - The fallback is `NSVisualEffectView` with `.behindWindow` blending, which blurs what is behind an overlay. (source: https://developer.apple.com/documentation/appkit/nsvisualeffectview)
  - Gate the glass behind `#available(macOS 26, *)`. (inferred)
- **Vignette's toolbar.** Vignette's toolbar is drawn its own way today. Glass would apply to the ink's controls and any message bubble, not to the ink. (inferred)

### The screen-edge glow

- **What Apple describes.** Apple's macOS 15.1 notes describe Siri as "a glowing light wrapping around the edge of the screen." (vendor, quoted at https://www.iclarified.com/95263/macos-sequoia-151-release-notes/amp)
- **No API.** Apple publishes no API or guidance for reproducing the glow. (inferred from finding none)
- **Apple's guidance on feedback.** The HIG page on generative AI says nothing about glows. It asks for "specific, reassuring feedback during generation." (source: https://developer.apple.com/design/human-interface-guidelines/generative-ai)
- **How open-source reproductions do it.**
  - Layered strokes of a rotating angular gradient at different widths and blurs (a sharp core, a bloom and a wide wash), in SwiftUI, sometimes with a Metal layer effect.
  - jacobamobin/AppleIntelligenceGlowEffect moves its gradient stops on a timer. (source: https://github.com/jacobamobin/AppleIntelligenceGlowEffect)
  - Livsy90/IntelligenceGlow rotates the gradient and respects Reduce Motion. (source: https://github.com/Livsy90/IntelligenceGlow)
  - A walkthrough gives sizes: a 4 pt core, a 14 pt bloom, a 30 pt wash. (third-party: https://vp0.com/blogs/apple-intelligence-siri-overlay-clone-swiftui)
  - GlowEffectKit uses a Metal shader. (third-party: https://swiftpackageregistry.com/didisouzacosta/GlowEffectKit)
- **In Core Animation.**
  - `CAGradientLayer` with `type = .conic` (macOS 10.14+) gives the angular gradient. (source: https://developer.apple.com/documentation/quartzcore/cagradientlayertype/conic)
  - Masking it with a stroked `CAShapeLayer` and blurring copies of it reproduces the SwiftUI approach. (inferred)
  - Vignette's motion rule applies: the glow's animation goes through `Settings.motionUI`, and Reduce Motion turns it into a still or a pulse. (`AGENTS.md`)
- **Related Apple APIs.**
  - WWDC24 "Create custom visual effects with SwiftUI" covers `TextRenderer`, `MeshGradient` and Metal shader effects. (Apple engineer: https://developer.apple.com/videos/play/wwdc2024/10151/)
  - `NSWritingToolsCoordinator` (macOS 15.2) hosts Writing Tools' own text animations in a custom view. It does not expose the screen glow. (source: https://developer.apple.com/documentation/appkit/nswritingtoolscoordinator)
- **Prior art for agents.** EdgeGlow glows the screen edges while Claude Code works, driven by hooks over local HTTP. (third-party: https://hunted.space/product/edgeglow)

## 8. Prior art

### Assistants that read other apps

- **ChatGPT for Mac, "Work with Apps."**
  - It reads apps through Accessibility.
  - VS Code needs an extension.
  - From terminals it takes the last 200 lines of each open pane, and a selection takes priority.
  - (vendor, from search snippets because the page refused the fetch: https://help.openai.com/en/articles/10119604-work-with-apps-on-macos)
- **ChatGPT Record.** It transcribes and summarizes microphone and system audio, up to 120 minutes, and needs Screen & System Audio Recording. (vendor: https://help-lb.openai.com/en/articles/11487532)
- **Claude desktop Quick Entry.** Double-tap Option. It can attach a screenshot or a window you click, and Caps Lock dictates. (vendor: https://support.claude.com/en/articles/12626668-use-quick-entry-with-claude-desktop-on-mac)
- **Claude Code computer use (macOS research preview).**
  - A built-in `computer-use` MCP server.
  - It needs Accessibility and Screen Recording, with per-app approval each session.
  - It hides other apps while it works, and keeps the terminal out of its screenshots.
  - It downscales screenshots (3456×2234 to about 1372×887).
  - Esc stops it from anywhere, and one session at a time holds a lock on the computer.
  - (source: https://code.claude.com/docs/en/computer-use)
- **Claude in Chrome.** An extension that reads, clicks and navigates pages from a side panel. (vendor: https://support.claude.com/en/articles/12012173-get-started-with-claude-in-chrome)
- **Highlight.** Spun out of Medal in 2024. It attaches the focused window as a screenshot plus extracted text. (third-party: https://techcrunch.com/2024/10/22/desktop-ai-assistant-app-highlight-spins-out-of-medal-with-10m-in-funding)
- **Rewind / Limitless.** Rewind recorded the screen continuously and ran OCR on device. After Meta acquired Limitless, screen and audio capture in the Rewind Mac app stopped on 2025-12-19. (third-party: https://9to5mac.com/2025/12/05/rewind-limitless-meta-acquisition/)
- **Superwhisper.**
  - Its context modes take three things: the selected text when recording starts, the focused field's text and the window title, and anything copied within 3 s.
  - The same idea as "say it while you circle it," without the circle.
  - (vendor: https://superwhisper.com/docs/common-issues/context)

### Picking an element in a preview

- **Cursor.**
  - The browser visual editor: click an element and describe the change, and the agent edits the code. (vendor: https://cursor.com/blog/browser-visual-editor)
  - Its Design Mode is reported to send the element's HTML, applied CSS and bounding box. (third-party: https://pasqualepillitteri.it/en/news/3794/cursor-design-mode-what-it-is-how-it-works-cursor-3)
- **Windsurf Previews, now Devin Desktop.** "Send element" puts the picked element or error into the prompt as an @-mention. (source: https://docs.devin.ai/desktop/previews)
- **v0 Design Mode and Lovable Visual Edits.** Hover highlights an element, a click selects it, and edits are written back to the code. (vendor: https://237.v0.build/docs/design-mode, https://docs.lovable.dev/features/visual-edit)
- **For live ink.** These all work inside a browser they own, where the DOM is available. Live ink has to get the same packet (element, identifiers, bounds) from outside, through Accessibility, which gives roles, titles, frames and, in Chromium and WebKit, `AXDOMIdentifier` and `AXDOMClassList`, but not the CSS. (inferred)

### Agents that act on or point at the screen

- **Anthropic's computer-use reference implementation.** A Linux desktop in Docker, driven by screenshots and xdotool, with no pointer overlay. (source: https://github.com/anthropics/claude-quickstarts/tree/main/computer-use-demo)
- **OpenAI Operator, now ChatGPT agent.** It acts in its own virtual browser with a virtual cursor, and hands control back for logins and payments. (vendor: https://openai.com/index/introducing-operator/)
- **Google Project Mariner and Perplexity Comet.** Both act in the browser and show their steps in a side panel. (third-party: https://techcrunch.com/2024/12/11/google-unveils-project-mariner-ai-agents-to-use-the-web-for-you/, https://techcrunch.com/2025/07/09/perplexity-launches-comet-an-ai-powered-web-browser/)
- **Microsoft Copilot Vision "Highlights" (2025).** You ask "show me how," and it highlights where to click in a shared app window. This is the closest shipped product to an agent pointing at the live screen. (vendor: https://blogs.windows.com/windows-insider/2025/05/12/copilot-on-windows-windows-insiders-can-now-use-vision-with-2-apps-and-new-highlights-feature-with-1-app/)
- **Apple's onscreen awareness.**
  - Apps publish what is on screen as app entities, through `appEntityIdentifier` on a responder or `NSUserActivity` (macOS 15.2+). (source: https://developer.apple.com/documentation/appintents/providing-contextual-cues-to-apple-intelligence-and-siri)
  - macOS 27 adds `appEntityIdentifier(forSelectionType:)` for collections. (Apple engineer: https://developer.apple.com/videos/play/wwdc2026/343/)
  - Only content an app chooses to publish is visible this way. A third-party overlay cannot read other apps through it. (inferred)
- **Encircle.** A Mac app where circling a region opens an AI prompt beside it. (third-party: https://www.producthunt.com/p/encircle-2/encircle-2)
- **adammcarter/annotate.** Described under section 4: an MCP server that lets an agent draw on a click-through overlay. (source)

## Open questions to measure in the spike

- Latency of `captureImage` with a filter, of an `SCShareableContent` fetch, and of a warm `SCStream`, on 15.7.
- Whether `AXUIElementCopyElementAtPosition` on the system-wide element hits a clear or `ignoresMouseEvents` overlay.
- Accessibility hit-test latency, and the shallow first answer from Chromium.
- Whether native scrollers post `AXValueChanged` on their scroll bar.
- OCR time for a ~1500 px crop, fast against accurate, first call included.
- Whether a non-activating panel receives trackpad pressure events.
- Whether Sidecar delivers tilt and `changeMode` on 15.7.
- Whether `SpeechAnalyzer` raises the Speech Recognition prompt (macOS 26+).
