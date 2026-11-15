import AppKit
import ScreenCaptureKit

/// macOS 15's question "'Vignette' is requesting to bypass the system private window picker and
/// directly access your screen and audio". The first screen capture after Screen Recording is allowed
/// raises it, so setup's Screen Recording row raises it from its button rather than live ink's first ask.
///
/// macOS tells an app neither that the question was answered nor how. Allow and Open System Settings
/// both stop it coming back (macOS 15.7, `docs/live-ink-setup.md`), so it counts as answered once its
/// window has left the screen, or when none comes up after the capture.
@MainActor
enum PickerQuestion {
    enum Status: Equatable { case ask, waiting, answered }

    static var status: Status {
        guard #available(macOS 15, *) else { return .answered }
        return asking ? .waiting : Identity.defaults.bool(forKey: answeredKey) ? .answered : .ask
    }

    /// How long the question may take to come up after the capture. On macOS 15.7 it came in 0.2 s.
    static let comesUpWithin: Duration = .seconds(2)

    private static var asking = false
    private static let answeredKey = "pickerQuestionAnswered"

    /// Captures the screen once, which raises the question if macOS still has it to ask, and waits
    /// for an answer. A capture that fails leaves the question to ask.
    static func ask() {
        guard status == .ask else { return }
        asking = true
        Log.write("[setup] capturing the screen once for macOS's window picker question")
        Task {
            defer { asking = false }
            guard await captureOnce() else { return }
            let captured = ContinuousClock.now
            var cameUp = false
            while true {
                try? await Task.sleep(for: .milliseconds(100))
                if SystemPrompts.areUp {
                    cameUp = true
                } else if cameUp || ContinuousClock.now - captured > comesUpWithin {
                    break
                }
            }
            Log.write(cameUp ? "[setup] macOS's window picker question answered" : "[setup] macOS asked no window picker question")
            Identity.defaults.set(true, forKey: answeredKey)
        }
    }

    /// A new Screen Recording grant brings the question back.
    static func forget() {
        Identity.defaults.removeObject(forKey: answeredKey)
    }

    private static func captureOnce() async -> Bool {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return false }
            let configuration = SCStreamConfiguration()
            configuration.width = 2
            configuration.height = 2
            _ = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []),
                                                           configuration: configuration)
            return true
        } catch {
            Log.write("[setup] screen capture for the window picker question failed: \(error.localizedDescription)")
            return false
        }
    }
}
