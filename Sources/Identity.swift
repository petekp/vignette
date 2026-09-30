import Foundation

/// Everything that names this app on a machine, read from the bundle so a fork renames only
/// project.yml. The settings path stays literal (`~/.config/vignette/settings.json`): it is
/// documented and lives in dotfiles. The unit-test bundle has none of these keys and gets the
/// same defaults as the shipped app.
enum Identity {
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.petepetrash.vignette"
    static let name = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Vignette"
    static let urlScheme = urlScheme(in: Bundle.main.infoDictionary ?? [:]) ?? "vignette"
    static let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/\(name).log")
    static let applicationSupportURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/\(bundleID)")
    static let cachesURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/\(bundleID)")
    static let statusItemAutosaveName = bundleID
    static let hotKeySignature = hotKeySignature(for: bundleID)

    /// The first scheme under CFBundleURLTypes.
    static func urlScheme(in info: [String: Any]) -> String? {
        (info["CFBundleURLTypes"] as? [[String: Any]])?.first.flatMap { ($0["CFBundleURLSchemes"] as? [String])?.first }
    }

    /// A stable four-byte code for the Carbon hotkey, so two apps with different bundle ids never
    /// share a registration. djb2 over the bundle id.
    static func hotKeySignature(for bundleID: String) -> UInt32 {
        bundleID.utf8.reduce(UInt32(5381)) { ($0 &* 33) &+ UInt32($1) }
    }
}
