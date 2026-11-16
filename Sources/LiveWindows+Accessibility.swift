import AppKit

/// Accessibility calls on another app. Each blocks on that app.
enum WindowAccessibility {
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    /// `_AXUIElementGetWindow`, which every window manager uses to match an element to the window
    /// list. Private, so looked up rather than linked.
    private static let getWindow: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError).self)
    }()

    static func windowID(_ window: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard let getWindow, getWindow(window, &id) == .success else { return nil }
        return id
    }

    static func isElectron(pid: pid_t) -> Bool {
        guard let bundle = NSRunningApplication(processIdentifier: pid)?.bundleURL else { return false }
        return FileManager.default.fileExists(atPath: bundle.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path)
    }

    /// An Electron app builds its page's tree only when asked, and keeps it until it quits, at a cost
    /// in memory and CPU. The note's URL and the page an answer keeps to come from that tree, so the
    /// app is asked when a mark lands at `point`, in global top-left points, where it has no page yet.
    /// No other app is. False when it could not tell, without Accessibility, so a later mark asks again.
    @discardableResult
    static func requestTree(pid: pid_t, at point: CGPoint) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard isElectron(pid: pid) else { return true }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var hit: AXUIElement?
        if AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) != .success { hit = nil }
        if let hit {
            AXUIElementSetMessagingTimeout(hit, 0.25)
            guard !isInWebArea(hit) else { return true }
        }
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        let name = NSRunningApplication(processIdentifier: pid)?.bundleURL?.deletingPathExtension().lastPathComponent ?? "?"
        Log.write("[live-ink] accessibility tree requested app=\(name)")
        return true
    }

    private static func isInWebArea(_ element: AXUIElement) -> Bool {
        var current: AXUIElement? = element
        for _ in 0..<40 {
            guard let element = current else { return false }
            if attribute(element, kAXRoleAttribute) as? String == "AXWebArea" { return true }
            current = attribute(element, kAXParentAttribute).map { $0 as! AXUIElement }
        }
        return false
    }
}
