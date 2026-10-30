import Foundation

struct Screenshot: Sendable {
    let key: ScreenshotKey
    var url: URL { key.url }

    init(key: ScreenshotKey) { self.key = key }

    /// A still image, or a screen recording from Cmd+Shift+5.
    enum Kind: Sendable {
        case image, recording

        /// Read from the extension alone. The name says nothing: macOS names screenshots and
        /// recordings from the same `com.apple.screencapture name` default, which is the user's to change.
        init(of url: URL) {
            self = Screenshot.recordingExtensions.contains(url.pathExtension.lowercased()) ? .recording : .image
        }
    }

    var kind: Kind { Kind(of: url) }

    /// What Cmd+Shift+5 writes (docs/replacing-apple-capture-2026-09-22.md).
    static let recordingExtensions: Set<String> = ["mov"]
}
