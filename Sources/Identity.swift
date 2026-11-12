import Foundation

/// Everything that names this app on a machine, read from the bundle so a fork renames only
/// project.yml. The settings file is `~/.config/<URL scheme>/settings.json`, so Vignette's stays at
/// the documented `~/.config/vignette/settings.json`, which people keep in dotfiles, and a fork gets
/// its own.
enum Identity {
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.petepetrash.vignette"
    static let name = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Vignette"
    static let urlScheme = urlScheme(in: Bundle.main.infoDictionary ?? [:]) ?? "vignette"
    static let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/\(name).log")
    /// The folder whose `Library` holds what this launch stores (`Launch.dataHome`): the home
    /// folder, or for a test launch on the person's own home, one of the test's.
    static let dataHome: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folder = Launch.dataHome(bundleID: bundleID, home: home, environment: ProcessInfo.processInfo.environment,
                                     personHome: AgentPlugin.personHome, temporary: FileManager.default.temporaryDirectory)
        if folder != home {
            Log.write("[app] test launch: \(home.path) is the person's own home folder, so this copy stores its data under \(folder.path)/Library; launch with CFFIXED_USER_HOME to choose the folder")
        }
        return folder
    }()
    static let applicationSupportURL = dataHome.appendingPathComponent("Library/Application Support/\(bundleID)")
    static let cachesURL = dataHome.appendingPathComponent("Library/Caches/\(bundleID)")
    static let webKitURL = dataHome.appendingPathComponent("Library/WebKit/\(bundleID)")
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
