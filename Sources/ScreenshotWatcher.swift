import Foundation
import ImageIO

/// Watches a folder and reports screenshot files as they arrive and leave. A new file is reported
/// once it is fully written; one that never settles is logged and forgotten so the next event tries again.
/// `@unchecked Sendable`: every mutable access (`known`, `source`) is confined to `queue`, and
/// `onNew`/`onRemoved` only ever run after an explicit hop to the main queue.
final class ScreenshotWatcher: @unchecked Sendable {
    private let folder: URL
    private let onNew: (URL) -> Void
    private let onRemoved: ([URL]) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var known: Set<String>
    private let queue = DispatchQueue(label: "shotnote.watcher")

    init(folder: URL, onNew: @escaping (URL) -> Void, onRemoved: @escaping ([URL]) -> Void) {
        self.folder = folder
        self.onNew = onNew
        self.onRemoved = onRemoved
        self.known = Set(ScreenshotWatcher.candidateNames(in: folder))
        start()
    }

    deinit { source?.cancel() }

    private func start() {
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            Log.write("[watcher] error cannot open \(folder.path): \(String(cString: strerror(errno)))")
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: queue)
        src.setEventHandler { [weak self] in self?.scan() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    /// Compares the folder with what was last seen. Called on every directory event and on wake.
    func rescan(reason: String) {
        queue.async { [weak self] in
            Log.write("[watcher] rescan \(reason)")
            self?.scan()
        }
    }

    private func scan() {
        let current = Set(ScreenshotWatcher.candidateNames(in: folder))
        let change = ScreenshotWatcher.diff(known: known, current: current)
        known = current
        if !change.removed.isEmpty {
            let urls = change.removed.map { folder.appendingPathComponent($0) }
            DispatchQueue.main.async { self.onRemoved(urls) }
        }
        for name in change.added {
            let url = folder.appendingPathComponent(name)
            waitUntilComplete(url) { [weak self] complete in
                guard let self else { return }
                if complete {
                    DispatchQueue.main.async { self.onNew(url) }
                } else if FileManager.default.fileExists(atPath: url.path) {
                    // Forget it so the next directory event or stack open picks it up again.
                    Log.write("[watcher] error never-stable \(name)")
                    self.known.remove(name)
                }
            }
        }
    }

    /// Sorted names that appeared and disappeared since the last scan.
    static func diff(known: Set<String>, current: Set<String>) -> (added: [String], removed: [String]) {
        (current.subtracting(known).sorted(), known.subtracting(current).sorted())
    }

    /// screencapture writes the file in one go, but Dropbox and other syncers stream it in. Wait
    /// until the size holds across two polls and ImageIO sees a complete image, for up to ten seconds.
    private func waitUntilComplete(_ url: URL, attempts: Int = 100, last: Int = -1, done: @escaping @Sendable (Bool) -> Void) {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
        if size > 0 && size == last && ScreenshotWatcher.isCompleteImage(url) { done(true); return }
        guard attempts > 0 else { done(false); return }
        queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.waitUntilComplete(url, attempts: attempts - 1, last: size, done: done)
        }
    }

    /// True when ImageIO can decode the file. A file still being written fails to decode; ImageIO's
    /// status calls do not tell the two apart (measured: both report complete), so this decodes once.
    static func isCompleteImage(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }

    static func candidateNames(in folder: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter(isCandidate)
    }

    /// The formats screencapture can write that the app can decode. Outputs of the annotator are not candidates.
    static let candidateExtensions: Set<String> = ["png", "jpg", "jpeg", "heic"]

    static func isCandidate(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard !lower.hasPrefix("."), !lower.contains(Config.annotatedSuffix) else { return false }
        return candidateExtensions.contains((lower as NSString).pathExtension)
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
            .prefix(max(0, limit))   // prefix traps on a negative count
            .map(\.0)
    }

    static func newestScreenshot(in folder: URL) -> URL? {
        recentScreenshots(in: folder, limit: 1).first
    }
}
