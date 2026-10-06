import AppKit
import ScreenCaptureKit

/// Where a live ink mark's content is in another app's window, found through Accessibility when the
/// mark is pinned and read again after the content moved (docs/live-ink-step3-2026-10-05.md). Every
/// call blocks on the other app, so none runs on the main thread: Dia once held one for 627 ms.
final class LiveAnchor: @unchecked Sendable {
    enum Kind {
        /// One character of a text view (`AXBoundsForRange`).
        case range(AXUIElement, CFRange)
        /// One character of a WebKit page, as a text marker range.
        case marker(AXUIElement, CFTypeRef)
        /// A line of a terminal that gives its visible text and no positions, such as Ghostty.
        case line(LineAnchor)
        /// An element that moves with the content, such as a run of text in a Chromium page.
        case element(AXUIElement)
    }

    let kind: Kind
    /// The window's element, whose position the anchor's is read against, so a reading taken while
    /// the window is dragged does not count as the content moving.
    let window: AXUIElement?
    /// The scroll area or web area the anchor scrolls in: the mark shows only inside it.
    let scrollArea: AXUIElement?
    /// The anchor's rect when pinned, from the window's top-left. Chromium reports an element that is
    /// partly scrolled out clipped to the viewport, so its height is kept to tell that apart.
    let pinned: CGRect
    /// The point the anchor was found at, in the same coordinates, which keeps its place inside an
    /// element that changes size.
    let focus: CGPoint?

    var name: String {
        switch kind {
        case .range: "text"
        case .marker: "web text"
        case .line: "terminal line"
        case .element: "element"
        }
    }

    private init(kind: Kind, window: AXUIElement?, scrollArea: AXUIElement?, pinned: CGRect, focus: CGPoint? = nil) {
        self.focus = focus
        self.kind = kind
        self.window = window
        self.scrollArea = scrollArea
        self.pinned = pinned
    }

    /// What one reading found, from the window's top-left, in points.
    struct Reading: Equatable, Sendable {
        /// Where the anchor is now; nil when it is gone, as text scrolled out of a terminal is.
        var rect: CGRect?
        /// The scroll area's visible rect.
        var clip: CGRect?

        /// How far the content under the anchor moved since it was pinned. An element that changed
        /// size, as a page's layout does when it changes, moves `focus` to the same place inside it,
        /// so a mark on the right of a bar that grew leftwards stays on the right.
        func shift(from pinned: CGRect, focus: CGPoint? = nil) -> CGVector? {
            guard let rect, rect.width > 0, rect.height >= 1 else { return nil }
            var top = rect.minY
            // Clipped at the viewport's top edge: its top stays put while its height shrinks, so its
            // real top is its bottom less its height.
            let clipped = clip.map { rect.height < pinned.height - 1 && rect.minY <= $0.minY + 1 } ?? false
            if clipped { top = rect.maxY - pinned.height }
            var shift = CGVector(dx: rect.minX - pinned.minX, dy: top - pinned.minY)
            guard let focus, pinned.width > 0, pinned.height > 0 else { return shift }
            if abs(rect.width - pinned.width) > 1 {
                let along = min(max((focus.x - pinned.minX) / pinned.width, 0), 1)
                shift.dx = rect.minX + along * rect.width - focus.x
            }
            if !clipped, abs(rect.height - pinned.height) > 1 {
                let down = min(max((focus.y - pinned.minY) / pinned.height, 0), 1)
                shift.dy = rect.minY + down * rect.height - focus.y
            }
            return shift
        }
    }

    /// Reads where the anchor is now. `windowOrigin` is the window's top-left from the window list,
    /// used when the app gives no position for its window.
    func read(windowOrigin: CGPoint) -> Reading {
        let origin = window.flatMap { Self.frame(of: $0)?.origin } ?? windowOrigin
        func local(_ rect: CGRect?) -> CGRect? { rect.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) } }
        return Reading(rect: local(rect()), clip: local(scrollArea.flatMap(Self.frame(of:))))
    }

    private func rect() -> CGRect? {
        switch kind {
        case .range(let element, var range):
            guard let value = AXValueCreate(.cfRange, &range) else { return nil }
            return Self.rect(Self.parameter(element, kAXBoundsForRangeParameterizedAttribute, value))
        case .marker(let element, let range):
            return Self.rect(Self.parameter(element, "AXBoundsForTextMarkerRange", range))
        case .element(let element):
            return Self.frame(of: element)
        case .line(let line):
            return line.rect()
        }
    }

    // MARK: Finding

    /// The anchor for the content at `point`, in global top-left points, in the window `windowID` of
    /// the app `pid`, whose top-left is `windowOrigin`; nil when Accessibility gives nothing that
    /// moves with the content there.
    static func find(at point: CGPoint, pid: pid_t, windowID: CGWindowID, windowOrigin: CGPoint) -> LiveAnchor? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        // Chromium and Electron build their tree for Accessibility only when asked.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) == .success, let element = hit else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.25)
        let window = Self.window(of: element, id: windowID)
        let origin = window.flatMap { frame(of: $0)?.origin } ?? windowOrigin
        let scrollArea = enclosing(element, roles: ["AXScrollArea", "AXWebArea"])
        func anchor(_ kind: Kind, _ rect: CGRect) -> LiveAnchor {
            LiveAnchor(kind: kind, window: window, scrollArea: scrollArea, pinned: rect.offsetBy(dx: -origin.x, dy: -origin.y),
                       focus: CGPoint(x: point.x - origin.x, y: point.y - origin.y))
        }
        // A rect counts only near the point it was asked about: some apps answer with the start of the
        // text, or with nothing at all as a zero rect.
        func near(_ rect: CGRect?) -> CGRect? {
            guard let rect, rect.width > 0, rect.height > 0, rect.insetBy(dx: -40, dy: -40).contains(point) else { return nil }
            return rect
        }
        var at = point
        guard let position = AXValueCreate(.cgPoint, &at) else { return nil }
        let names = parameterNames(element)
        if names.contains(kAXRangeForPositionParameterizedAttribute),
           let value = parameter(element, kAXRangeForPositionParameterizedAttribute, position) {
            var range = CFRange()
            AXValueGetValue(value as! AXValue, .cfRange, &range)
            range.length = 1
            let kind = Kind.range(element, range)
            if let rect = near(LiveAnchor(kind: kind, window: nil, scrollArea: nil, pinned: .zero).rect()) { return anchor(kind, rect) }
        }
        if names.contains("AXTextMarkerForPosition"), let marker = parameter(element, "AXTextMarkerForPosition", position),
           let next = parameter(element, "AXNextTextMarkerForTextMarker", marker),
           let range = parameter(element, "AXTextMarkerRangeForUnorderedTextMarkers", [marker, next] as CFArray),
           let rect = near(rect(parameter(element, "AXBoundsForTextMarkerRange", range))) {
            return anchor(.marker(element, range), rect)
        }
        if !names.contains(kAXBoundsForRangeParameterizedAttribute), let line = LineAnchor(element, at: point), let rect = line.rect() {
            return anchor(.line(line), rect)
        }
        // The element itself, when it is a part of the content rather than the area it scrolls in.
        let isScrollArea = scrollArea.map { CFEqual($0, element) } ?? false
        if !isScrollArea, let rect = frame(of: element), rect.width > 0, rect.height > 0 {
            let area = scrollArea.flatMap(frame(of:)) ?? .null
            if area.isNull || rect.width * rect.height < area.width * area.height * 0.5 {
                return anchor(.element(element), rect)
            }
        }
        return nil
    }

    /// The window `element` is in: its `AXWindow`, checked against the window list's id.
    private static func window(of element: AXUIElement, id: CGWindowID) -> AXUIElement? {
        guard let window = attribute(element, kAXWindowAttribute).map({ $0 as! AXUIElement }) else { return nil }
        if let windowID = Self.windowID(window), windowID != id { return nil }
        return window
    }

    /// `_AXUIElementGetWindow`, which every window manager uses to match an element to the window
    /// list. Private, so looked up rather than linked, and a nil answer leaves the element unchecked.
    private static let getWindow: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError).self)
    }()

    static func windowID(_ window: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard let getWindow, getWindow(window, &id) == .success else { return nil }
        return id
    }

    private static func enclosing(_ element: AXUIElement, roles: Set<String>) -> AXUIElement? {
        var current: AXUIElement? = element
        for _ in 0..<40 {
            guard let element = current else { return nil }
            if let role = attribute(element, kAXRoleAttribute) as? String, roles.contains(role) { return element }
            current = attribute(element, kAXParentAttribute).map { $0 as! AXUIElement }
        }
        return nil
    }

    // MARK: Accessibility calls

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    static func parameter(_ element: AXUIElement, _ name: String, _ parameter: CFTypeRef) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyParameterizedAttributeValue(element, name as CFString, parameter, &value) == .success ? value : nil
    }

    static func parameterNames(_ element: AXUIElement) -> Set<String> {
        var names: CFArray?
        AXUIElementCopyParameterizedAttributeNames(element, &names)
        return Set((names as? [String]) ?? [])
    }

    static func rect(_ value: CFTypeRef?) -> CGRect? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(value as! AXValue, .cgRect, &rect) ? rect : nil
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: point, size: extent)
    }
}

/// A line of a terminal that gives its visible text and no positions (Ghostty): found again by its
/// words, with the lines round it to tell repeats apart, and placed by row, since every row of a
/// terminal is the same height. The text stays on this Mac; it is only compared.
final class LineAnchor: @unchecked Sendable {
    private let element: AXUIElement
    private let line: String, before: String, after: String
    private var row: Int

    init?(_ element: AXUIElement, at point: CGPoint) {
        guard let lines = Self.lines(element), lines.count > 2, let frame = LiveAnchor.frame(of: element) else { return nil }
        let row = Int((point.y - frame.minY) / (frame.height / CGFloat(lines.count)))
        guard lines.indices.contains(row), !lines[row].trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        self.element = element
        self.row = row
        line = lines[row]
        before = row > 0 ? lines[row - 1] : ""
        after = row + 1 < lines.count ? lines[row + 1] : ""
    }

    private static func lines(_ element: AXUIElement) -> [String]? {
        (LiveAnchor.attribute(element, kAXValueAttribute) as? String).map { $0.components(separatedBy: "\n") }
    }

    /// Where the line is now, or nil once it has scrolled off the screen.
    func rect() -> CGRect? {
        guard let lines = Self.lines(element), !lines.isEmpty, let frame = LiveAnchor.frame(of: element) else { return nil }
        var best: (row: Int, score: Int)?
        for (index, text) in lines.enumerated() where text == line {
            var score = 4
            if index > 0, lines[index - 1] == before { score += 2 }
            if index + 1 < lines.count, lines[index + 1] == after { score += 2 }
            score -= min(3, abs(index - row) / 10)
            if best.map({ score > $0.score }) ?? true { best = (index, score) }
        }
        guard let found = best else { return nil }
        row = found.row
        let height = frame.height / CGFloat(lines.count)
        return CGRect(x: frame.minX, y: frame.minY + CGFloat(row) * height, width: frame.width, height: height)
    }
}
