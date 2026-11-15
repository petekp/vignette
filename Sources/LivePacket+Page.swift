import AppKit

extension LivePacket {
    /// The window's document or page, from Accessibility: its `AXDocument`, or the `AXURL` of a web
    /// area within a few levels of it. Nil when the app gives neither, or without the permission.
    /// Where a window's content comes from, and a browser's page area.
    struct Page {
        var location: String?
        var area: CGRect?
    }

    /// The window at `frame`'s document or page, from Accessibility.
    static func page(pid: pid_t, frame: CGRect) -> Page? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        guard let windows = WindowAccessibility.attribute(app, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        let window = windows.first { window in
            guard let position = WindowAccessibility.attribute(window, kAXPositionAttribute),
                  let size = WindowAccessibility.attribute(window, kAXSizeAttribute) else { return false }
            var origin = CGPoint.zero, extent = CGSize.zero
            AXValueGetValue(position as! AXValue, .cgPoint, &origin)
            AXValueGetValue(size as! AXValue, .cgSize, &extent)
            return abs(origin.x - frame.minX) < 2 && abs(origin.y - frame.minY) < 2 && abs(extent.width - frame.width) < 2
        }
        guard let window else { return nil }
        let document = (WindowAccessibility.attribute(window, kAXDocumentAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
        var queue: [(AXUIElement, Int)] = [(window, 0)], visited = 0
        while !queue.isEmpty, visited < 200 {
            let (element, depth) = queue.removeFirst()
            visited += 1
            if WindowAccessibility.attribute(element, kAXRoleAttribute) as? String == "AXWebArea" {
                let url = (WindowAccessibility.attribute(element, kAXURLAttribute) as? URL)?.absoluteString
                return Page(location: url ?? document, area: area(of: element)?.intersection(frame))
            }
            guard depth < 8, let children = WindowAccessibility.attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { continue }
            queue += children.map { ($0, depth + 1) }
        }
        return document.map { Page(location: $0) }
    }

    /// An element's frame, in global top-left points.
    private static func area(of element: AXUIElement) -> CGRect? {
        guard let position = WindowAccessibility.attribute(element, kAXPositionAttribute),
              let size = WindowAccessibility.attribute(element, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return extent.width > 0 && extent.height > 0 ? CGRect(origin: origin, size: extent) : nil
    }
}
