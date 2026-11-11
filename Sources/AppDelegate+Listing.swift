import Foundation

/// The screenshots the stack and the shortcuts list, from the watcher's index.
extension AppDelegate {
    /// The newest screenshots a person may act on: the folder's, less any agent reply whose import
    /// has not committed. Every listing goes through here rather than through the index directly.
    func recentShots(limit: Int, where fits: (Screenshot) -> Bool = { _ in true }) -> (recent: [ScreenshotKey], files: Int) {
        watcher?.recent(limit: limit, include: { [weak self] key in
            (self?.isShown(key) ?? true) && fits(Screenshot(key: key))
        }) ?? (recent: [], files: 0)
    }

    /// A file in the folder is shown unless it is an agent's reply that is not published yet.
    func isShown(_ key: ScreenshotKey) -> Bool { requests.isVisible(key.url) }

    func newestShot(where fits: (Screenshot) -> Bool = { _ in true }) -> ScreenshotKey? {
        recentShots(limit: 1, where: fits).recent.first
    }

    /// Whether anything is there to show, by the same rule as `recentShots`.
    var hasScreenshots: Bool { watcher?.contains(where: isShown) ?? false }

    /// The older chunks the recent stack loads as it nears its top, by the same rule as `recentShots`.
    func listOlderShots() {
        thumbnail.older.listing = { [weak self] in
            guard let watcher = self?.watcher else { return nil }
            return { after, shown, limit in watcher.older(after: after, shown: shown, limit: limit) }
        }
        thumbnail.older.isShown = { [weak self] key in self?.isShown(key) ?? true }
    }
}
