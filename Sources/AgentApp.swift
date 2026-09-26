import AppKit
import ApplicationServices

/// An agent client's own app. When it was the app in front before Vignette, it is where you came
/// from, and the session it shows is where Send starts (`AgentDestination.cameFrom`).
enum AgentApp {
    /// The Codex app. Its process and its window are both named ChatGPT.
    static let codexBundleID = "com.openai.codex"

    /// The client whose own app this is, or nil for any other app.
    static func client(of app: NSRunningApplication?) -> AgentClient? {
        app?.bundleIdentifier == codexBundleID ? .codex : nil
    }

    /// The name of the thread the Codex app shows: the title of the page in its focused window, read
    /// through Accessibility. Nil when Vignette is not trusted, the app has no window, or nothing
    /// answers within `deadline`. It blocks for up to about `deadline`, so call it off the main thread.
    static func openThread(pid: pid_t, deadline: TimeInterval = 0.25) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        // The app is Electron, which builds its accessibility tree only once an assistive app asks,
        // and then keeps it until it quits. The first read after asking found the page at once
        // (measured 2026-09-25).
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        let start = Date()
        while Date().timeIntervalSince(start) < deadline {
            guard let window = value(app, kAXFocusedWindowAttribute) ?? value(app, kAXMainWindowAttribute) else { return nil }
            if let page = webArea(in: window as! AXUIElement, start: start, deadline: deadline) {
                let title = (value(page, kAXTitleAttribute) as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return title.isEmpty ? nil : title
            }
            Thread.sleep(forTimeInterval: 0.03)
        }
        return nil
    }

    /// The page in a window, searched breadth first: it sits a few levels down, above the thread's
    /// own long tree.
    private static func webArea(in window: AXUIElement, start: Date, deadline: TimeInterval) -> AXUIElement? {
        var queue = [window], seen = 0
        while !queue.isEmpty, seen < 200, Date().timeIntervalSince(start) < deadline {
            let element = queue.removeFirst()
            seen += 1
            if value(element, kAXRoleAttribute) as? String == "AXWebArea" { return element }
            queue += value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        return nil
    }

    private static func value(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var result: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
    }
}
