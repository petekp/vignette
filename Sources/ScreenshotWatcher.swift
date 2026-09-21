import Foundation
import ImageIO
import os

/// Watches a folder and reports screenshot files as they arrive and leave. A new file is reported
/// once it is fully written; one that never settles is logged and forgotten so the next event tries again.
/// It also keeps an index of the folder (every candidate with its modification date), so the stack
/// and the newest-screenshot lookups read memory instead of listing the folder on the main thread.
/// `@unchecked Sendable`: `source` is confined to `queue`, the index sits behind a lock, and
/// `onNew`/`onRemoved` only ever run after an explicit hop to the main queue.
final class ScreenshotWatcher: @unchecked Sendable {
    private let folder: URL
    private let onNew: (URL) -> Void
    private let onRemoved: ([URL]) -> Void
    private var source: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "vignette.watcher")

    private struct State {
        var files: [String: Date] = [:]   // candidate name -> modification date
        var watching = false              // the directory source is live
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(folder: URL, onNew: @escaping (URL) -> Void, onRemoved: @escaping ([URL]) -> Void) {
        self.folder = folder
        self.onNew = onNew
        self.onRemoved = onRemoved
        state.withLock { $0.files = ScreenshotWatcher.listing(of: folder) }
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
        state.withLock { $0.watching = true }
    }

    /// Compares the folder with what was last seen. Called on every directory event, on wake, and on
    /// every stack open, which is how a file changed in place or one that never settled is picked up.
    func rescan(reason: String) {
        queue.async { [weak self] in
            Log.write("[watcher] rescan \(reason)")
            self?.scan()
        }
    }

    /// The newest `limit` screenshots and how many candidates the folder holds, from the index.
    /// While the folder cannot be watched (a volume that is not mounted yet) it lists the folder
    /// instead, and the next rescan retries the watch. `include` filters before the limit is
    /// taken, so a file the app is hiding does not cost the stack one of its cards.
    func recent(limit: Int, include: (URL) -> Bool = { _ in true }) -> (recent: [URL], files: Int) {
        let snapshot = state.withLock { $0.watching ? $0.files : nil }
        return ScreenshotWatcher.recent(from: snapshot ?? ScreenshotWatcher.listing(of: folder), in: folder, limit: limit, include: include)
    }

    func newest(include: (URL) -> Bool = { _ in true }) -> URL? {
        recent(limit: 1, include: include).recent.first
    }

    private func scan() {
        if source == nil { start() }
        let current = ScreenshotWatcher.listing(of: folder)
        let change = state.withLock { s -> (added: [String], removed: [String]) in
            let change = ScreenshotWatcher.diff(known: Set(s.files.keys), current: Set(current.keys))
            s.files = current
            return change
        }
        if !change.removed.isEmpty {
            let urls = change.removed.map { folder.appendingPathComponent($0) }
            DispatchQueue.main.async { self.onRemoved(urls) }
        }
        for name in change.added {
            let url = folder.appendingPathComponent(name)
            waitUntilComplete(url) { [weak self] complete in
                guard let self else { return }
                if complete {
                    // A streamed file's date settles with its content; the index keeps the final one.
                    if let date = ScreenshotWatcher.modificationDate(of: url) {
                        self.state.withLock { if $0.files[name] != nil { $0.files[name] = date } }
                    }
                    DispatchQueue.main.async { self.onNew(url) }
                } else if FileManager.default.fileExists(atPath: url.path) {
                    // Forget it so the next directory event or stack open picks it up again.
                    Log.write("[watcher] error never-stable \(name)")
                    self.state.withLock { $0.files.removeValue(forKey: name) }
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

    /// The formats screencapture can write that the app can decode. Outputs of the annotator are not candidates.
    static let candidateExtensions: Set<String> = ["png", "jpg", "jpeg", "heic"]

    static func isCandidate(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard !lower.hasPrefix("."), !lower.contains(Config.annotatedSuffix) else { return false }
        return candidateExtensions.contains((lower as NSString).pathExtension)
    }

    /// Every candidate in `folder` with its modification date, from one bulk listing. Asking the
    /// listing for the date is what keeps this cheap: a per-file attribute call reads extended
    /// attributes too and costs about 20 times more (measured on 1300 files: 7 ms against 110 ms).
    static func listing(of folder: URL) -> [String: Date] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)) ?? []
        var files: [String: Date] = [:]
        for url in urls where isCandidate(url.lastPathComponent) {
            if let date = modificationDate(of: url) { files[url.lastPathComponent] = date }
        }
        return files
    }

    static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// The newest `limit` of `files`, newest first, plus the candidate count. Ties fall to the name,
    /// which carries the capture time for a screenshot.
    static func recent(from files: [String: Date], in folder: URL, limit: Int,
                       include: (URL) -> Bool = { _ in true }) -> (recent: [URL], files: Int) {
        let visible = files
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key > $1.key }
            .map { folder.appendingPathComponent($0.key) }
            .filter(include)
        return (Array(visible.prefix(max(0, limit))), visible.count)   // prefix traps on a negative count
    }

    /// A fresh listing sorted like the index; for tests and for a folder that is not watched.
    static func recent(in folder: URL, limit: Int) -> (recent: [URL], files: Int) {
        recent(from: listing(of: folder), in: folder, limit: limit)
    }
}
