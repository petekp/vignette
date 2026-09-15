import AppKit

/// Remembers the last app other than Shotnote that was active, so windows we open can hand focus back.
/// Tracked continuously because opening via URL activates Shotnote before any window appears.
@MainActor
final class FocusReturn {
    static let shared = FocusReturn()
    private(set) var previousApp: NSRunningApplication?
    private var observer: Any?

    private init() {
        previousApp = NSWorkspace.shared.frontmostApplication
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app != NSRunningApplication.current else { return }
            // NSWorkspace delivers notifications registered with queue: .main on the main thread.
            MainActor.assumeIsolated { self?.previousApp = app }
        }
    }

    /// Activates the previous app if Shotnote is currently the active one.
    func restore(reason: String) {
        guard NSApp.isActive, let app = previousApp, !app.isTerminated else { return }
        app.activate()
        Log.write("[focus] \(reason): returned to \(app.localizedName ?? "?")")
    }
}
