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
    ///
    /// `settling` ignores clicks for that long after this call. The check below asks the window
    /// server which window is under the cursor, and a window ordered in a moment ago is not in that
    /// answer yet, so a press on it reads as a press on whatever was behind it. A caller that starts
    /// watching in the same turn as it orders its window in has to wait out that gap; a caller whose
    /// window has been up for a while passes nothing.
    func start(settling: TimeInterval = 0, _ handler: @escaping () -> Void) {
        stop()
        let watching = Date().addingTimeInterval(settling)
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            if Date() < watching { return }
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
