import Foundation
import ImageIO
import os

/// Watches a folder and reports screenshot files as they arrive and leave. A new file is reported
/// once it is fully written; one that never settles is logged and forgotten so the next event tries again.
/// It also keeps an index of the folder (every candidate with its modification date), so the stack
/// and the newest-screenshot lookups read memory instead of listing the folder on the main thread.
/// `@unchecked Sendable`: `source` is confined to `queue`, the index sits behind a lock, and
/// callbacks only run after an explicit hop to the main queue.
final class ScreenshotWatcher: @unchecked Sendable {
    private let folder: URL
    private let onNew: (URL) -> Void
    private let onRemoved: ([URL], Inventory) -> Void
    private let onInventory: (Inventory) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var directoryID: DirectoryID?
    private var generation = 0
    private let queue = DispatchQueue(label: "vignette.watcher")
    /// Confined to `queue`, like `source`: the last reason the folder could not be opened, so a
    /// retry every `retryDelay` logs a change rather than every attempt, and whether one is due.
    private var openError: Int32?
    private var retryDue = false

    enum Availability: Equatable {
        case available, missing, refused, unavailable
    }

    struct Inventory: Sendable {
        let folder: URL
        let names: Set<String>
        let dates: [String: Date]
        /// Earlier app writes may be reconciled; writes made after this read began may not.
        let observedAt: TimeInterval
        var directoryID: DirectoryID?

        func confirmsAbsence(of url: URL) -> Bool {
            // A positive lookup protects equivalent names and files created after the listing.
            url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL
                && !names.contains(url.lastPathComponent)
                && !FileManager.default.fileExists(atPath: url.path)
        }

        func candidates(retaining previous: [String: Date] = [:]) -> [String: Date] {
            Dictionary(uniqueKeysWithValues: names.filter(ScreenshotWatcher.isCandidate).map {
                ($0, dates[$0] ?? previous[$0] ?? .distantPast)
            })
        }

        func captures(since cutoff: Date) -> Set<String> {
            Set(names.filter { ScreenshotWatcher.isCandidate($0) && dates[$0].map { $0 >= cutoff } == true })
        }
    }

    struct DirectoryID: Equatable, Sendable {
        let device: dev_t
        let inode: ino_t

        init?(_ path: String) {
            var info = stat()
            guard stat(path, &info) == 0 else { return nil }
            device = info.st_dev
            inode = info.st_ino
        }

        init?(descriptor: Int32) {
            var info = stat()
            guard fstat(descriptor, &info) == 0 else { return nil }
            device = info.st_dev
            inode = info.st_ino
        }
    }

    private struct Arrival: Equatable, Sendable {
        let id = UUID()
        let generation: Int
    }

    private struct State {
        var files: [String: Date] = [:]   // candidate name -> modification date
        var present: Set<String> = []
        var watching = false              // the directory source is live
        var indexed = false               // a successful listing or a missing-folder capture cutoff exists
        var denied = false                // macOS refused this app the folder
        var missingSince: Date?           // when a listing first found no folder, until one finds it
        var availability = Availability.unavailable
        var generation = 0
        var pending: [String: Arrival] = [:]
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// How long launch waits for the first listing, and how often an unopenable folder is tried
    /// again. In code: a cadence for system calls, not a number a user would tune.
    private static let firstListingWait: TimeInterval = 0.5
    private static let retryDelay: TimeInterval = 2

    init(folder: URL, onNew: @escaping (URL) -> Void,
         onRemoved: @escaping ([URL], Inventory) -> Void, onInventory: @escaping (Inventory) -> Void = { _ in }) {
        self.folder = folder
        self.onNew = onNew
        self.onRemoved = onRemoved
        self.onInventory = onInventory
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

    /// False during unavailability, even when an earlier successful inventory is retained.
    var isReadable: Bool { availability == .available }
    var availability: Availability { state.withLock { $0.availability } }

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
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .revoke], queue: queue)
        src.setEventHandler { [weak self] in self?.scan() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
        directoryID = DirectoryID(descriptor: fd)
        generation += 1
        state.withLock { $0.watching = true; $0.denied = false; $0.generation = generation }
    }

    /// A folder that cannot be opened now may open later: a volume mounts, or the user allows the
    /// app in System Settings. Nothing announces either, so the watch is tried again.
    private func retryLater() {
        guard !retryDue else { return }
        retryDue = true
        queue.asyncAfter(deadline: .now() + ScreenshotWatcher.retryDelay) { [weak self] in
            guard let self else { return }
            self.retryDue = false
            self.scan()
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
        let snapshot = state.withLock { ($0.files, $0.watching || !$0.indexed) }
        if !snapshot.1, case .available(let inventory) = Self.read(folder) {
            return Self.recent(from: inventory.candidates(retaining: snapshot.0), in: folder, limit: limit, include: include)
        }
        return Self.recent(from: snapshot.0, in: folder, limit: limit, include: include)
    }

    func newest(include: (URL) -> Bool = { _ in true }) -> URL? {
        recent(limit: 1, include: include).recent.first
    }

    private func scan() {
        if source != nil, directoryID != DirectoryID(folder.path) {
            source?.cancel()
            source = nil
            directoryID = nil
            generation += 1
            state.withLock { $0.watching = false; $0.generation = generation }
        }
        if source == nil { start() }
        let listing = Self.read(folder)
        let now = Date()
        guard case .available(let inventory) = listing else {
            state.withLock { s in
                s.availability = listing.availability
                s.denied = listing.availability == .refused
                if listing.availability == .missing {
                    s.missingSince = s.missingSince ?? now
                    s.indexed = true
                }
            }
            retryLater()
            return
        }
        let arrivals = state.withLock { s -> [(String, Arrival)] in
            s.availability = .available
            s.denied = false
            for (name, arrival) in s.pending where arrival.generation != generation {
                s.files[name] = nil
            }
            let current = inventory.candidates(retaining: s.files)
            s.pending = s.pending.filter { current[$0.key] != nil }
            guard s.indexed else {
                s.files = current
                s.indexed = true
                return []
            }
            var known = Set(s.files.keys)
            if let since = s.missingSince {
                // A remount makes old files silent, but previously admitted arrivals are still owed.
                known.formUnion(Set(current.keys).subtracting(inventory.captures(since: since)).subtracting(s.pending.keys))
                s.missingSince = nil
            }
            let added = Self.diff(known: known, current: Set(current.keys)).added
            s.files = current
            return added.map { name in
                let arrival = Arrival(generation: generation)
                s.pending[name] = arrival
                return (name, arrival)
            }
        }
        let started = generation
        DispatchQueue.main.async {
            guard self.state.withLock({ $0.generation == started }) else { return }
            guard inventory.directoryID == DirectoryID(self.folder.path),
                  access(self.folder.path, R_OK | X_OK) == 0 else {
                self.rescan(reason: "directory changed before delivery")
                return
            }
            let removed = self.state.withLock { s in
                let removed = Self.diff(known: s.present, current: inventory.names).removed.filter(Self.isCandidate)
                s.present = inventory.names
                return removed
            }
            self.onInventory(inventory)
            if !removed.isEmpty {
                self.onRemoved(removed.map { self.folder.appendingPathComponent($0) }, inventory)
            }
        }
        for (name, arrival) in arrivals {
            let url = folder.appendingPathComponent(name)
            waitUntilComplete(url, arrival: arrival) { [weak self] complete in
                guard let self else { return }
                if complete {
                    // A streamed file's date settles with its content; the index keeps the final one.
                    if let date = ScreenshotWatcher.modificationDate(of: url) {
                        self.state.withLock { if $0.files[name] != nil { $0.files[name] = date } }
                    }
                    DispatchQueue.main.async {
                        guard self.state.withLock({ $0.generation == arrival.generation && $0.pending[name] == arrival }),
                              inventory.directoryID == DirectoryID(self.folder.path),
                              access(self.folder.path, R_OK | X_OK) == 0 else {
                            self.retryArrival(name, arrival: arrival)
                            return
                        }
                        self.state.withLock { $0.pending[name] = nil }
                        self.onNew(url)
                    }
                } else if FileManager.default.fileExists(atPath: url.path) {
                    // Forget it so the next directory event or stack open picks it up again.
                    Log.write("[watcher] error never-stable \(name)")
                    self.retryArrival(name, arrival: arrival, rescan: false)
                } else {
                    self.retryArrival(name, arrival: arrival, rescan: false)
                }
            }
        }
    }

    private func retryArrival(_ name: String, arrival: Arrival, rescan: Bool = true) {
        let released = state.withLock { s -> Bool in
            guard s.pending[name] == arrival else { return false }
            // Its admission remains pending until main-queue delivery succeeds.
            s.files[name] = nil
            return true
        }
        if released && rescan { self.rescan(reason: "retry undelivered arrival") }
    }

    /// Sorted names that appeared and disappeared since the last scan.
    static func diff(known: Set<String>, current: Set<String>) -> (added: [String], removed: [String]) {
        (current.subtracting(known).sorted(), known.subtracting(current).sorted())
    }

    /// screencapture writes the file in one go, but Dropbox and other syncers stream it in. Wait
    /// until the size holds across two polls and the file reads whole, for up to ten seconds.
    private func waitUntilComplete(_ url: URL, arrival: Arrival, attempts: Int = 100, last: Int = -1,
                                   done: @escaping @Sendable (Bool) -> Void) {
        guard generation == arrival.generation else {
            retryArrival(url.lastPathComponent, arrival: arrival)
            return
        }
        guard state.withLock({ $0.pending[url.lastPathComponent] == arrival }) else { return }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
        if size > 0 && size == last && ScreenshotWatcher.isComplete(url) { done(true); return }
        guard attempts > 0 else { done(false); return }
        queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.waitUntilComplete(url, arrival: arrival, attempts: attempts - 1, last: size, done: done)
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
    static func listing(of folder: URL) -> [String: Date] {
        guard case .available(let inventory) = read(folder) else { return [:] }
        return inventory.candidates()
    }

    private enum Listing {
        case available(Inventory)
        case unavailable(Availability)

        var availability: Availability {
            switch self {
            case .available: return .available
            case .unavailable(let reason): return reason
            }
        }
    }

    private static func read(_ folder: URL) -> Listing {
        let observedAt = ProcessInfo.processInfo.systemUptime
        let before = DirectoryID(folder.path)
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
        } catch CocoaError.fileReadNoSuchFile {
            return .unavailable(.missing)
        } catch {
            let posix = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError
            let refused = (error as? CocoaError)?.code == .fileReadNoPermission
                || (posix?.domain == NSPOSIXErrorDomain && [Int(EPERM), Int(EACCES)].contains(posix?.code))
            return .unavailable(refused ? .refused : .unavailable)
        }
        var files: [String: Date] = [:]
        for url in urls where isCandidate(url.lastPathComponent) {
            if let date = modificationDate(of: url) { files[url.lastPathComponent] = date }
        }
        guard let before, before == DirectoryID(folder.path) else { return .unavailable(.unavailable) }
        return .available(Inventory(folder: folder, names: Set(urls.map(\.lastPathComponent)), dates: files,
                                    observedAt: observedAt, directoryID: before))
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
