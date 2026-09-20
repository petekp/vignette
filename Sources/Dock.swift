import AppKit
import ApplicationServices

/// Where the Dock's tiles are, for the stack's safe area.
///
/// AppKit says how much room the Dock takes along a screen's bottom edge (`visibleFrame` against
/// `frame`) but not how wide it is or where along that edge it sits, and the stack only has to step
/// around a Dock its own column is over. `CGWindowListCopyWindowInfo` does not help: on macOS 15 the
/// Dock's layer-20 window is the whole screen (verified: 0,0,1512,982 with 966 points of tiles), so
/// its bounds say nothing about the tiles. The Accessibility API is the one source for the tiles'
/// own rect — the Dock process has a single `AXList` child, and it is the row of tiles.
///
/// That needs the app trusted for Accessibility, which is the trust the modifier-tap hotkey already
/// needs. Untrusted, `tiles` is nil and the caller takes the Dock to span the whole edge, which is
/// the room AppKit reserves anyway.
enum Dock {
    /// The tiles in global AppKit points (origin at the bottom-left of the primary display), or nil
    /// when the Dock cannot be read. The list widens with magnification while the cursor is on it,
    /// so only its left and right edges are worth reading; how far the Dock reaches up is AppKit's
    /// number, which magnification does not move.
    @MainActor
    static func tiles() -> NSRect? {
        guard let app = element() else { return nil }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &children) == .success,
              let list = (children as? [AXUIElement])?.first(where: { role(of: $0) == kAXListRole }),
              let rect = frame(of: list) else { return nil }
        // Accessibility reports global top-left points; the rest of the layout is AppKit's.
        return StateReport.fromTopLeft(rect, primaryHeight: StateReport.primaryHeight)
    }

    @MainActor
    private static var cached: (pid: pid_t, element: AXUIElement)?

    /// How long one read waits, not how long a pass does: a wedged Dock is waited on once for the
    /// application's children, once for each child's role until the list is found, and twice more
    /// for that list's position and size, so a pass can take several times this on the main thread.
    /// The caller treats no answer as no Dock. Set on every element this file reads, not once on
    /// the application: the timeout belongs to the object it is set on and is not inherited by the
    /// children that come back from it.
    private static let readTimeout: Float = 0.25

    @MainActor
    private static func element() -> AXUIElement? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let pid = dock.processIdentifier
        if let cached, cached.pid == pid { return cached.element }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, readTimeout)
        cached = (pid, element)
        return element
    }

    private static func role(of element: AXUIElement) -> String? {
        AXUIElementSetMessagingTimeout(element, readTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        AXUIElementSetMessagingTimeout(element, readTimeout)
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }
}
