import Foundation

struct Screenshot {
    let url: URL
}

final class Settings {
    private let key = "watchFolder"

    var watchFolder: URL {
        get {
            if let path = UserDefaults.standard.string(forKey: key) { return URL(fileURLWithPath: path) }
            return Settings.appleScreenshotFolder()
        }
        set { UserDefaults.standard.set(newValue.path, forKey: key) }
    }

    private static let appleDomain = "com.apple.screencapture" as CFString

    /// Where Cmd+Shift+3/4 saves. Falls back to the Desktop, which is Apple's default.
    static func appleScreenshotFolder() -> URL {
        if let raw = CFPreferencesCopyAppValue("location" as CFString, appleDomain) as? String {
            return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    /// Apple's own floating thumbnail. When it is on, the file is written only after the thumbnail
    /// dismisses, which delays ours by about five seconds. Off means the file lands immediately.
    static var appleThumbnailEnabled: Bool {
        get {
            if let v = CFPreferencesCopyAppValue("show-thumbnail" as CFString, appleDomain) as? Bool { return v }
            return true
        }
        set {
            CFPreferencesSetAppValue("show-thumbnail" as CFString, newValue as CFBoolean, appleDomain)
            CFPreferencesAppSynchronize(appleDomain)
        }
    }
}
