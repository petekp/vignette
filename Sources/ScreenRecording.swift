import AppKit

/// Screen Recording, which live ink's asks need to capture the window under the ink. Nothing else in
/// Vignette needs it: setup's picture of its own window is ScreenCaptureKit's capture of the app's
/// own windows, which needs no permission.
enum ScreenRecording {
    static var granted: Bool { CGPreflightScreenCaptureAccess() }

    /// Raises macOS's own alert, which it shows once for an app; after that this does nothing, and the
    /// row under the switch opens the pane. Only a switch the person turned on calls this.
    static func request() {
        guard !granted else { return }
        Log.write("[live-ink] asking for Screen Recording")
        _ = CGRequestScreenCaptureAccess()
    }

    static func openSystemSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
}
