import AppKit

/// Remembers the last app other than Vignette that was active, so windows we open can hand focus back.
/// Tracked continuously because opening via URL activates Vignette before any window appears.
@MainActor
final class FocusReturn {
    static let shared = FocusReturn()
    private(set) var previousApp: NSRunningApplication?
    /// When `restore` last handed the keys to `previousApp`, in seconds of system uptime. The app's
    /// activation follows, and tells nobody it was not the person's.
    private(set) var handedBackAt: TimeInterval?
    /// Vignette's own titled window (Settings, setup, the tweaks) that was key when the stack or the
    /// annotator came up. Closing those goes back to it; going to another app forgets it.
    private weak var ownWindow: NSWindow?
    private var observer: Any?
    /// Posted just before `restore` hands the keys to the app that is the notification's object.
    static let handingBack = Notification.Name("FocusReturn.handingBack")

    private init() {
        previousApp = NSWorkspace.shared.frontmostApplication
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            // Only an app the person works in. macOS's permission alerts run as apps of their own
            // (universalAccessAuthWarn for Accessibility) and take the focus while they are up, and
            // Vignette opens System Settings for a permission; closing setup after a grant should go
            // back to the app the person was in, not to either.
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app != NSRunningApplication.current, app.activationPolicy == .regular,
                  app.bundleIdentifier != "com.apple.systempreferences" else { return }
            // NSWorkspace delivers notifications registered with queue: .main on the main thread.
            MainActor.assumeIsolated {
                self?.previousApp = app
                self?.ownWindow = nil
            }
        }
    }

    /// The stack, the annotator or setup's demo note is coming up. Called before it can take the keys,
    /// while the window the person was in is still key.
    func sessionStarting() {
        guard NSApp.isActive, let window = NSApp.keyWindow, window.styleMask.contains(.titled) else { return }
        ownWindow = window
    }

    /// Goes back to the Vignette window the session started in, or else gives the keys back to the
    /// previous app if Vignette is currently the active one.
    func restore(reason: String) {
        if let window = ownWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            Log.write("[focus] \(reason): returned to \(window.title)")
            return
        }
        guard NSApp.isActive, let app = previousApp, !app.isTerminated else { return }
        NotificationCenter.default.post(name: Self.handingBack, object: app)
        // A non-activating panel takes the keys while that app stays frontmost, and activating a
        // frontmost app leaves the keys with Vignette; letting go hands them back.
        if NSWorkspace.shared.frontmostApplication == app { NSApp.deactivate() } else { app.activate() }
        handedBackAt = ProcessInfo.processInfo.systemUptime
        Log.write("[focus] \(reason): returned to \(app.localizedName ?? "?")")
    }
}
