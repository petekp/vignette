import Foundation
@preconcurrency import CoreFoundation

/// Apple's screenshot defaults (`defaults read com.apple.screencapture`). A launch with
/// `VIGNETTE_SETTINGS` reads and writes `<bundle id>.screencapture` instead, so a test copy never
/// takes or moves the user's save location. macOS itself never reads that domain.
enum AppleScreencapture {
    static let domainName = Launch.isTest ? "\(Identity.bundleID).screencapture" : "com.apple.screencapture"
    private static let domain = domainName as CFString

    static func string(_ key: String) -> String? { CFPreferencesCopyAppValue(key as CFString, domain) as? String }
    static func bool(_ key: String) -> Bool? { CFPreferencesCopyAppValue(key as CFString, domain) as? Bool }

    /// Where macOS sends a capture: `file`, or `clipboard`, `mail` or `preview` when ⌘⇧5's Options
    /// name those. Unset means a file.
    static var target: String { string("target") ?? "file" }

    /// The target as the Screenshot app's Options menu names it.
    static func targetName(_ target: String) -> String {
        switch target {
        case "clipboard": "the Clipboard"
        case "mail": "Mail"
        case "preview": "Preview"
        default: target
        }
    }

    /// Where macOS saves screenshots: the `location` key, or the Desktop when it is unset.
    static var location: String { string("location") ?? SettingsData().screenshotsFolder }

    /// Two folder paths name the same folder, whatever their tildes and trailing slashes.
    static func samePath(_ a: String, _ b: String) -> Bool {
        func standard(_ path: String) -> String {
            URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
        }
        return standard(a) == standard(b)
    }

    /// Calls `changed` on the main thread whenever `key` changes, whoever changed it: the
    /// preferences daemon tells every process observing the key. Measured for `location` with a
    /// `defaults write` from another process: 10 to 35 ms.
    static func observe(_ key: String, _ changed: @escaping @MainActor @Sendable () -> Void) -> Observer? {
        UserDefaults(suiteName: domainName).map { Observer(defaults: $0, key: key, changed: changed) }
    }

    final class Observer: NSObject {
        private let defaults: UserDefaults
        private let key: String
        private let changed: @MainActor @Sendable () -> Void

        init(defaults: UserDefaults, key: String, changed: @escaping @MainActor @Sendable () -> Void) {
            self.defaults = defaults
            self.key = key
            self.changed = changed
            super.init()
            defaults.addObserver(self, forKeyPath: key, options: [], context: nil)
        }

        deinit { defaults.removeObserver(self, forKeyPath: key) }

        override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                   change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
            // Delivered on whichever thread the change arrived on.
            DispatchQueue.main.async { [changed] in MainActor.assumeIsolated { changed() } }
        }
    }

    static func set(_ key: String, _ value: Any) {
        CFPreferencesSetAppValue(key as CFString, value as CFPropertyList, domain)
        CFPreferencesAppSynchronize(domain)
        Log.write("[settings] apple \(key)=\(value)")
    }

    static func remove(_ key: String) {
        CFPreferencesSetAppValue(key as CFString, nil, domain)
        CFPreferencesAppSynchronize(domain)
        Log.write("[settings] apple \(key) unset")
    }
}

/// The `com.apple.screencapture` values Vignette found before it wrote any of its own, so
/// `vignette://restore-apple-defaults` can put them back. nil means the key was not set.
struct AppleOriginal: Codable, Equatable {
    var location: String?
    var showThumbnail: Bool?
    var disableShadow: Bool?
    var type: String?

    static func capture() -> AppleOriginal {
        AppleOriginal(location: AppleScreencapture.string("location"),
                      showThumbnail: AppleScreencapture.bool("show-thumbnail"),
                      disableShadow: AppleScreencapture.bool("disable-shadow"),
                      type: AppleScreencapture.string("type"))
    }
}
