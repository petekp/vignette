import AppKit

/// A global mouse monitor that fires only for clicks outside every window of this app.
/// Global monitors also report clicks on this app's own floating windows, so the topmost window
/// under the cursor is checked before the handler runs.
@MainActor
enum OutsideClick {
    static func monitor(_ handler: @escaping () -> Void) -> Any? {
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            let number = NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0)
            if NSApp.window(withWindowNumber: number) != nil { return }
            handler()
        }
    }
}
