import AppKit

/// Where on screen a capture was taken, from what Vignette saw around it. Pure, so a test drives
/// it with no window server. Every rect and point is in global Cocoa points: origin at the bottom
/// left of the primary display, y up.
enum CaptureRect {
    enum Kind: String { case selection, window, display }

    /// A press and release of the left button, as the poll saw them, and when it saw the release.
    struct Drag: Equatable {
        var press: CGPoint
        var release: CGPoint
        var at: Date
    }

    struct Display: Equatable {
        var frame: CGRect
        var scale: CGFloat
    }

    /// Apple's window shadow in points, outside the window's frame: a window capture with the
    /// shadow on is this much larger. The active window casts the larger one. Measured on macOS 15
    /// at scale 2 with ⌘⇧4's window mode, the same for every window size.
    static let shadows: [(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat)] = [
        (top: 26, left: 34, bottom: 42, right: 34),
        (top: 38, left: 56, bottom: 74, right: 56),
    ]
    /// How long after a release the file may arrive and still be that drag's. Measured at 150 ms.
    static let dragLifetime: TimeInterval = 3
    /// The poll sees the press up to a tick late, so the drag it saw is short by what the pointer
    /// moved in that tick. The rect itself comes from the release and the file's exact size.
    static let dragTolerance: CGFloat = 12

    /// The capture's rect, or nil when nothing seen matches its size. `cursor` is where the
    /// pointer is as the file arrives, which is where the capture's click or release was;
    /// `window` is the frame of the topmost ordinary window under it.
    static func locate(pixels: CGSize, arrivedAt: Date, drag: Drag?, cursor: CGPoint, window: CGRect?,
                       displays: [Display]) -> (rect: CGRect, kind: Kind)? {
        guard let display = displays.first(where: { contains($0.frame, cursor) }) else { return nil }
        let size = CGSize(width: pixels.width / display.scale, height: pixels.height / display.scale)
        func matches(_ other: CGSize, within tolerance: CGFloat) -> Bool {
            abs(other.width - size.width) <= tolerance && abs(other.height - size.height) <= tolerance
        }

        if let drag, arrivedAt >= drag.at, arrivedAt.timeIntervalSince(drag.at) <= dragLifetime,
           matches(CGSize(width: abs(drag.release.x - drag.press.x), height: abs(drag.release.y - drag.press.y)),
                   within: dragTolerance) {
            // The capture includes the point under the release, so a release on its right or
            // bottom edge lies one point inside that edge.
            let r = drag.release
            let x = drag.press.x < r.x ? r.x + 1 - size.width : r.x
            let y = drag.press.y < r.y ? r.y - size.height : r.y - 1
            return (CGRect(x: x, y: y, width: size.width, height: size.height), .selection)
        }
        if let window {
            if matches(window.size, within: 1) { return (window, .window) }
            for shadow in shadows {
                let shadowed = CGRect(x: window.minX - shadow.left, y: window.minY - shadow.bottom,
                                      width: window.width + shadow.left + shadow.right,
                                      height: window.height + shadow.top + shadow.bottom)
                if matches(shadowed.size, within: 1) { return (shadowed, .window) }
            }
        }
        if matches(display.frame.size, within: 1) { return (display.frame, .display) }
        return nil
    }

    /// `NSMouseInRect` without the flipped argument: the left and bottom edges are inside.
    private static func contains(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x < rect.maxX && point.y > rect.minY && point.y <= rect.maxY
    }
}

/// Watches for a capture being taken, so the flight into the editor can start where it was.
/// macOS's capture overlay keeps its drag from every other app's event monitors, but not the
/// button's state, so ⌘⇧ held together starts a short poll of the button and the pointer.
/// None of it needs a permission: a `flagsChanged` monitor works without Accessibility.
@MainActor
final class CaptureOrigin {
    private var monitors: [Any] = []
    private var poll: Timer?
    private var pollUntil = Date.distantPast
    private var wasDown = false
    private var press: CGPoint?
    private var drag: CaptureRect.Drag?
    /// Long enough to choose ⌘⇧3, 4 or 5, take a selection, and press Space for a window.
    static let pollSeconds: TimeInterval = 15
    /// ⌘⇧ went down together: a capture may be starting.
    var onCaptureKeys: (() -> Void)?

    init() {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.flagsChanged(event) }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            self?.flagsChanged(event)
            return event
        }) { monitors.append(monitor) }
    }

    private func flagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), flags.contains(.shift) else { return }
        onCaptureKeys?()
        pollUntil = Date().addingTimeInterval(Self.pollSeconds)
        guard poll == nil else { return }
        wasDown = NSEvent.pressedMouseButtons & 1 != 0
        // 30 Hz is enough: the press gives only the drag's direction.
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.005
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    private func tick() {
        let isDown = NSEvent.pressedMouseButtons & 1 != 0
        if isDown != wasDown {
            wasDown = isDown
            let point = NSEvent.mouseLocation
            if isDown { press = point } else if let press { drag = .init(press: press, release: point, at: Date()) }
        }
        if Date() > pollUntil, !isDown { stopPolling() }
    }

    private func stopPolling() {
        poll?.invalidate()
        poll = nil
        press = nil
    }

    /// The rect of a capture of `pixels` that has just arrived, or nil, which flies it from the
    /// corner. A drag is used once.
    func rect(of name: String, pixels: CGSize) -> CGRect? {
        let cursor = NSEvent.mouseLocation
        let displays = NSScreen.screens.map { CaptureRect.Display(frame: $0.frame, scale: $0.backingScaleFactor) }
        guard let found = CaptureRect.locate(pixels: pixels, arrivedAt: Date(), drag: drag, cursor: cursor,
                                             window: windowFrame(under: cursor), displays: displays) else {
            Log.write("[origin] none \(name) \(Int(pixels.width))x\(Int(pixels.height))px")
            return nil
        }
        if found.kind == .selection { drag = nil }
        Log.write("[origin] \(found.kind.rawValue) \(name) \(StateReport.topLeft(found.rect, primaryHeight: StateReport.primaryHeight))")
        return found.rect
    }

    /// The frame of the topmost ordinary window under `point`, which is the one a window capture
    /// takes. Window bounds need no Screen Recording permission; only their titles do.
    private func windowFrame(under point: CGPoint) -> CGRect? {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in windows {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"], let w = bounds["Width"], let h = bounds["Height"] else { continue }
            let frame = CGRect(x: x, y: primaryHeight - y - h, width: w, height: h)
            if NSMouseInRect(point, frame, false) { return frame }
        }
        return nil
    }
}
