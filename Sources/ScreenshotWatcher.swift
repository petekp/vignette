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
    /// Confined to `queue`, like `source`: the last reason the folder could not be opened, so a
    /// retry every `retryDelay` logs a change rather than every attempt, and whether one is due.
    private var openError: Int32?
    private var retryDue = false

    private struct State {
        var files: [String: Date] = [:]   // candidate name -> modification date
        var watching = false              // the directory source is live
        var indexed = false               // `files` came from a listing that worked, or the folder is missing
        var denied = false                // macOS refused this app the folder
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// How long launch waits for the first listing, and how often an unopenable folder is tried
    /// again. In code: a cadence for system calls, not a number a user would tune.
    private static let firstListingWait: TimeInterval = 0.5
    private static let retryDelay: TimeInterval = 2

    init(folder: URL, onNew: @escaping (URL) -> Void, onRemoved: @escaping ([URL]) -> Void) {
        self.folder = folder
        self.onNew = onNew
        self.onRemoved = onRemoved
        // macOS holds the first read of a folder it protects (the Desktop, Documents, Downloads)
        // until the user answers its prompt, so that read runs on the queue. An ordinary folder
        // lists in milliseconds, so the index is still ready when this returns.
        let listed = DispatchSemaphore(value: 0)
        queue.async { [weak self] in
            self?.scan()
            listed.signal()
        }
        _ = listed.wait(timeout: .now() + ScreenshotWatcher.firstListingWait)
    }

    deinit { source?.cancel() }

    /// Whether macOS refused this app the folder: the user answered Don't Allow, or turned the
    /// app off under Privacy & Security > Files and Folders.
    var isDenied: Bool { state.withLock { $0.denied } }

    private func start() {
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            let error = errno
            if error != openError {
                Log.write("[watcher] error cannot open \(folder.path): \(String(cString: strerror(error)))")
                openError = error
            }
            state.withLock { $0.denied = error == EPERM || error == EACCES }
            retryLater()
            return
        }
        if openError != nil {
            Log.write("[watcher] watching \(folder.path) after an error")
            openError = nil
        }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: queue)
        src.setEventHandler { [weak self] in self?.scan() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
        state.withLock { $0.watching = true; $0.denied = false }
    }

    /// A folder that cannot be opened now may open later: a volume mounts, or the user allows the
    /// app in System Settings. Nothing announces either, so the watch is tried again.
    private func retryLater() {
        guard !retryDue else { return }
        retryDue = true
        queue.asyncAfter(deadline: .now() + ScreenshotWatcher.retryDelay) { [weak self] in
            guard let self else { return }
            self.retryDue = false
            if self.source == nil { self.scan() }
        }
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
    /// instead, and the watch is retried. Before any listing has worked it answers from the empty
    /// index: that listing may be waiting on macOS's permission prompt, and a read here would wait
    /// with it on the main thread. `include` filters before the limit is taken, so a file the app
    /// is hiding does not cost the stack one of its cards.
    func recent(limit: Int, include: (URL) -> Bool = { _ in true }) -> (recent: [URL], files: Int) {
        let snapshot = state.withLock { $0.watching || !$0.indexed ? $0.files : nil }
        return ScreenshotWatcher.recent(from: snapshot ?? ScreenshotWatcher.listing(of: folder), in: folder, limit: limit, include: include)
    }

    func newest(include: (URL) -> Bool = { _ in true }) -> URL? {
        recent(limit: 1, include: include).recent.first
    }

    private func scan() {
        if source == nil { start() }
        let read = ScreenshotWatcher.read(folder)
        let change = state.withLock { s -> (added: [String], removed: [String]) in
            // A folder that could not be read held its files all along, so the first listing that
            // works is the folder as it was, not a batch of new captures: after a grant every file
            // would otherwise be copied and shown. A missing folder was indexed as empty, and what
            // arrives in it later is reported.
            guard s.indexed else {
                if let read { s.files = read; s.indexed = true }
                return ([], [])
            }
            let current = read ?? [:]
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
    /// until the size holds across two polls and the file reads whole, for up to ten seconds.
    private func waitUntilComplete(_ url: URL, attempts: Int = 100, last: Int = -1, done: @escaping @Sendable (Bool) -> Void) {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
        if size > 0 && size == last && ScreenshotWatcher.isComplete(url) { done(true); return }
        guard attempts > 0 else { done(false); return }
        queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.waitUntilComplete(url, attempts: attempts - 1, last: size, done: done)
        }
    }

    /// True when ImageIO can decode the file. A file still being written fails to decode; ImageIO's
    /// status calls do not tell the two apart (measured: both report complete), so this decodes once.
    /// An image ImageIO can decode, or a recording AVFoundation finds a video track in. The second
    /// also stores the recording's size, so the card made for it next does not read it again.
    static func isComplete(_ url: URL) -> Bool {
        Screenshot(url: url).kind == .recording ? Thumbnailer.pointSize(of: url) != nil : isCompleteImage(url)
    }

    static func isCompleteImage(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }

    /// The formats screencapture can write that the app can show. Outputs of the annotator are not candidates.
    static let candidateExtensions: Set<String> = Set(["png", "jpg", "jpeg", "heic"]).union(Screenshot.recordingExtensions)

    static func isCandidate(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard !lower.hasPrefix("."), !lower.contains(Config.annotatedSuffix) else { return false }
        return candidateExtensions.contains((lower as NSString).pathExtension)
    }

    /// Every candidate in `folder` with its modification date, from one bulk listing. Asking the
    /// listing for the date is what keeps this cheap: a per-file attribute call reads extended
    /// attributes too and costs about 20 times more (measured on 1300 files: 7 ms against 110 ms).
    static func listing(of folder: URL) -> [String: Date] { read(folder) ?? [:] }

    /// The listing; empty for a folder that does not exist, which is what it holds; nil for a folder
    /// that is there but could not be read, such as one macOS has not let the app into yet.
    private static func read(_ folder: URL) -> [String: Date]? {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)
        } catch CocoaError.fileReadNoSuchFile {
            return [:]
        } catch {
            return nil
        }
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
