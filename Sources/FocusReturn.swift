import AppKit

/// Remembers the last app other than Vignette that was active, so windows we open can hand focus back.
/// Tracked continuously because opening via URL activates Vignette before any window appears.
@MainActor
final class FocusReturn {
    static let shared = FocusReturn()
    private(set) var previousApp: NSRunningApplication?
    /// Vignette's own titled window (Settings, setup, the tweaks) that was key when the stack or the
    /// annotator came up. Closing those goes back to it; going to another app forgets it.
    private weak var ownWindow: NSWindow?
    private var observer: Any?

    private init() {
        previousApp = NSWorkspace.shared.frontmostApplication
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app != NSRunningApplication.current else { return }
            // NSWorkspace delivers notifications registered with queue: .main on the main thread.
            MainActor.assumeIsolated {
                self?.previousApp = app
                self?.ownWindow = nil
            }
        }
    }

    /// The stack or the annotator is coming up. Called before either takes the keys, while the
    /// window the person was in is still key.
    func sessionStarting() {
        guard NSApp.isActive, let window = NSApp.keyWindow, window.styleMask.contains(.titled) else { return }
        ownWindow = window
    }

    /// Goes back to the Vignette window the session started in, or else activates the previous app
    /// if Vignette is currently the active one.
    func restore(reason: String) {
        if let window = ownWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            Log.write("[focus] \(reason): returned to \(window.title)")
            return
        }
        guard NSApp.isActive, let app = previousApp, !app.isTerminated else { return }
        app.activate()
        Log.write("[focus] \(reason): returned to \(app.localizedName ?? "?")")
    }
}
