import AppKit

/// A global mouse monitor that fires only for clicks outside every window of this app. Global
/// monitors also report clicks on this app's own floating windows, so the topmost window under the
/// cursor is checked before the handler runs.
///
/// One instance holds one monitor, and the token never leaves this file: the stack and the
/// annotator each own one and say only when to start and stop. The check above had to be added
/// once, after a click inside the annotator closed it; the next such subtlety is one edit here
/// rather than one per watcher.
@MainActor
final class OutsideClick {
    private var monitor: Any?

    /// Starts watching, replacing whatever this holder was watching.
    func start(_ handler: @escaping () -> Void) {
        stop()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            let number = NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0)
            if NSApp.window(withWindowNumber: number) != nil { return }
            handler()
        }
    }

    /// Stops watching. A no-op when nothing is installed, so a caller may stop what it never started.
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
