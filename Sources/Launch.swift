import Foundation

/// A launch with `VIGNETTE_SETTINGS` set is a test launch. It reads and writes that settings file and
/// its own screenshot defaults, and reaches nothing else of the person's: no login item, no folder
/// under `Library` the person's own app stores data in, and no update feed, agent folder or agent
/// tool the environment does not name. Where it would share the person's own app's folders, it
/// keeps its defaults apart too (`Identity.defaults`).
enum Launch {
    static let settingsPath = settingsPath(in: ProcessInfo.processInfo.environment)
    static let isTest = settingsPath != nil

    static func isTest(in environment: [String: String]) -> Bool {
        settingsPath(in: environment) != nil
    }

    /// Whether this is a test launch on the person's own home folder, one without `CFFIXED_USER_HOME`.
    static func isOnPersonsHome(_ home: URL, environment: [String: String], personHome: URL) -> Bool {
        isTest(in: environment) && comparablePath(home) == comparablePath(personHome)
    }

    /// The folders under a home where the app keeps what it stores, one folder per bundle id in each.
    static let storedDataFolders = ["Library/Application Support", "Library/Caches", "Library/WebKit"]

    /// The folder that stands in for the home folder under `storedDataFolders`. It is `home`, except
    /// in a test launch on the person's own home, where `home`'s would be the person's own app's
    /// folders whenever the bundle id is the same. There it is the settings file's folder, laid out
    /// as a home, so the reply helper run with `HOME` set to it takes the copy's tickets. In a test
    /// launch, when that folder is not an absolute folder below the root, or its folders would still
    /// be the person's own or inside them, it is `<temporary>/<bundle id>`.
    static func dataHome(bundleID: String, home: URL, environment: [String: String], personHome: URL, temporary: URL) -> URL {
        guard let settings = settingsPath(in: environment) else { return home }
        let settingsFile = (settings as NSString).expandingTildeInPath
        let beside = URL(fileURLWithPath: settingsFile).deletingLastPathComponent()
        let isOnPersonsHome = isOnPersonsHome(home, environment: environment, personHome: personHome)
        let settingsFolderIsBelowTheRoot = settingsFile.hasPrefix("/") && beside.path != "/"
        let folder = isOnPersonsHome ? beside : home
        let sharesThePersonsFolders = storedDataFolders.contains { stored in
            let own = comparablePath(personHome.appendingPathComponent(stored).appendingPathComponent(bundleID))
            let copy = comparablePath(folder.appendingPathComponent(stored).appendingPathComponent(bundleID))
            return copy == own || copy.hasPrefix(own + "/")
        }
        let folderIsTheCopysOwn = (!isOnPersonsHome || settingsFolderIsBelowTheRoot) && !sharesThePersonsFolders
        return folderIsTheCopysOwn ? folder : temporary.appendingPathComponent(bundleID, isDirectory: true)
    }

    /// `url`'s path with every link resolved, as far as its folders exist, and without case, as APFS
    /// compares names by default. Foundation resolves no link in a path that does not exist yet, so
    /// the deepest folder that exists is resolved and the rest added back.
    static func comparablePath(_ url: URL) -> String {
        var existing = url.standardizedFileURL.path
        var rest: [String] = []
        while existing.count > 1, !FileManager.default.fileExists(atPath: existing) {
            rest.insert((existing as NSString).lastPathComponent, at: 0)
            existing = (existing as NSString).deletingLastPathComponent
        }
        let resolved = realpath(existing, nil).map { pointer in
            defer { free(pointer) }
            return String(cString: pointer)
        } ?? existing
        return rest.reduce(resolved) { ($0 as NSString).appendingPathComponent($1) }.lowercased()
    }

    private static func settingsPath(in environment: [String: String]) -> String? {
        environment["VIGNETTE_SETTINGS"].flatMap { $0.isEmpty ? nil : $0 }
    }
}
