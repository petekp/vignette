import Foundation

/// Watches a folder and reports new screenshot files once they are fully written.
final class ScreenshotWatcher {
    private let folder: URL
    private let onNew: (URL) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var known: Set<String>
    private let queue = DispatchQueue(label: "shotnote.watcher")

    init(folder: URL, onNew: @escaping (URL) -> Void) {
        self.folder = folder
        self.onNew = onNew
        self.known = Set(ScreenshotWatcher.candidateNames(in: folder))
        start()
    }

    deinit { source?.cancel() }

    private func start() {
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: queue)
        src.setEventHandler { [weak self] in self?.scan() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func scan() {
        let current = Set(ScreenshotWatcher.candidateNames(in: folder))
        let added = current.subtracting(known)
        known = current
        for name in added.sorted() {
            let url = folder.appendingPathComponent(name)
            waitUntilStable(url) { [weak self] in
                DispatchQueue.main.async { self?.onNew(url) }
            }
        }
    }

    /// screencapture writes the file in one go, but Dropbox and other syncers can touch it.
    /// Wait until the size stops changing across two polls.
    private func waitUntilStable(_ url: URL, attempts: Int = 20, last: Int = -1, done: @escaping () -> Void) {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
        if size > 0 && size == last { done(); return }
        guard attempts > 0 else { return }
        queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.waitUntilStable(url, attempts: attempts - 1, last: size, done: done)
        }
    }

    static func candidateNames(in folder: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter(isCandidate)
    }

    static func isCandidate(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard !lower.hasPrefix("."), !lower.contains(Config.annotatedSuffix) else { return false }
        return lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg")
    }

    static func recentScreenshots(in folder: URL, limit: Int) -> [URL] {
        let fm = FileManager.default
        return candidateNames(in: folder)
            .map { folder.appendingPathComponent($0) }
            .compactMap { url -> (URL, Date)? in
                guard let date = try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date else { return nil }
                return (url, date)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    static func newestScreenshot(in folder: URL) -> URL? {
        let fm = FileManager.default
        return candidateNames(in: folder)
            .map { folder.appendingPathComponent($0) }
            .compactMap { url -> (URL, Date)? in
                guard let date = try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date else { return nil }
                return (url, date)
            }
            .max { $0.1 < $1.1 }?.0
    }
}
