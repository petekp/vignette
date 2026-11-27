import Foundation

extension ScreenshotWatcher {
    /// The folder macOS asks about before an app may read a folder inside it, or nil for a folder
    /// it doesn't protect. Named as the setup window says it: "your Desktop". Besides the three
    /// home folders, macOS asks for iCloud Drive, a cloud provider's folder under
    /// `~/Library/CloudStorage`, and another volume. Taking a folder as protected when macOS does
    /// not ask costs one Allow… that answers at once; missing one puts macOS's prompt up at launch
    /// with nothing saying why.
    static func protectedArea(of folder: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        let path = folder.standardizedFileURL.resolvingSymlinksInPath().path
        func inside(_ area: String) -> Bool { path == area || path.hasPrefix(area + "/") }
        func homePath(_ name: String) -> String { home.appendingPathComponent(name).standardizedFileURL.path }
        for (name, spoken) in [("Desktop", "your Desktop"), ("Documents", "your Documents folder"),
                               ("Downloads", "your Downloads folder"), ("Library/Mobile Documents", "your iCloud Drive")] {
            if inside(homePath(name)) { return spoken }
        }
        let cloud = homePath("Library/CloudStorage")
        if path.hasPrefix(cloud + "/") {
            // `Dropbox`, or `GoogleDrive-name@example.com`: the provider is the part before the account.
            let provider = path.dropFirst(cloud.count + 1).split(separator: "/").first?.split(separator: "-").first
            return provider.map { "your \($0) folder" } ?? "that folder"
        }
        if path.hasPrefix("/Volumes/") { return "that disk" }
        return nil
    }
}
