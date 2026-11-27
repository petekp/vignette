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
    let folder: URL
    private let onNew: (ScreenshotKey) -> Void
    private let onRemoved: ([ScreenshotKey], Inventory) -> Void
    private let onReadState: () -> Void
    private let onRenamed: ([(from: ScreenshotKey, to: ScreenshotKey)], Inventory) -> Void
    private let onInventory: (Inventory) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var directoryID: DirectoryID?
    private var generation = 0
    private let queue = DispatchQueue(label: "vignette.watcher")
    /// Confined to `queue`, like `source`: the last reason the folder could not be opened, so a
    /// retry every `retryDelay` logs a change rather than every attempt, and whether one is due.
    private var openError: Int32?
    private var retryDue = false
    private let openFolder: FolderOpen

    /// Opens a folder for its events: a descriptor, or the error the open failed with.
    typealias FolderOpen = @Sendable (String) -> Result<Int32, POSIXError>
    static let openForEvents: FolderOpen = { path in
        let fd = open(path, O_EVTONLY)
        return fd >= 0 ? .success(fd) : .failure(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO))
    }

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
        var identities: [String: FileIdentity] = [:]

        func confirmsAbsence(of url: URL) -> Bool {
            // A positive lookup protects equivalent names and files created after the listing. It
            // comes first because it is the cheap test and most callers' files are still listed.
            !names.contains(url.lastPathComponent)
                && url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL
                && !FileManager.default.fileExists(atPath: url.path)
        }

        func candidates(retaining previous: [String: Date]) -> [String: Date] {
            Dictionary(uniqueKeysWithValues: names.filter(ScreenshotWatcher.isCandidate).map {
                ($0, dates[$0] ?? previous[$0] ?? .distantPast)
            })
        }

        func captures(since cutoff: Date) -> Set<String> {
            Set(names.filter { ScreenshotWatcher.isCandidate($0) && dates[$0].map { $0 >= cutoff } == true })
        }
    }

    /// What tells one file from another when its name changes: the same file keeps its inode, size
    /// and modification date under a new name.
    struct FileIdentity: Hashable, Sendable {
        let file: UInt64
        let size: Int
        let modified: Date
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
        var identities: [String: FileIdentity] = [:]
        var present: Set<String> = []
        var presentScan = 0               // the scan whose listing `present` is
        var watching = false              // the directory source is live
        var indexed = false               // a successful listing or a missing-folder capture cutoff exists
        var denied = false                // macOS refused this app the folder
        var missingSince: Date?           // when a listing first found no folder, until one finds it
        var unreadableSince: Date?        // when an open or a listing first failed, until a listing works
        var availability = Availability.unavailable
        var generation = 0
        var pending: [String: Arrival] = [:]
        var scans = 0
        var held = HeldRenames()
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// How long launch waits for the first listing, and how often an unopenable folder is tried
    /// again. In code: a cadence for system calls, not a number a user would tune.
    private static let firstListingWait: TimeInterval = 0.5
    private static let retryDelay: TimeInterval = 2
    /// A delivery on the main thread longer than this costs a frame at 120 Hz, so it is logged.
    private static let slowHandOffMs = 8

    init(folder: URL, onNew: @escaping (ScreenshotKey) -> Void,
         onRemoved: @escaping ([ScreenshotKey], Inventory) -> Void, onInventory: @escaping (Inventory) -> Void = { _ in },
         onRenamed: @escaping ([(from: ScreenshotKey, to: ScreenshotKey)], Inventory) -> Void = { _, _ in },
         onReadState: @escaping () -> Void = {}, openFolder: @escaping FolderOpen = ScreenshotWatcher.openForEvents) {
        self.folder = folder
        self.openFolder = openFolder
        self.onNew = onNew
        self.onRemoved = onRemoved
        self.onRenamed = onRenamed
        self.onReadState = onReadState
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

    /// Why the folder can't be read, once every open or listing since `grace` ago has failed: nil
    /// while it reads, before anything has tried, and for a failure younger than `grace`, which a
    /// slow first read or a volume still mounting can be.
    func unreadable(at now: Date = Date(), after grace: TimeInterval) -> Availability? {
        state.withLock { s in
            guard let since = s.unreadableSince, now.timeIntervalSince(since) >= grace else { return nil }
            return s.availability
        }
    }

    /// When every open or listing began failing, or nil while the folder reads. `onReadState` runs
    /// on the main thread when this starts, ends, or its reason changes.
    var unreadableSince: Date? { state.withLock { $0.unreadableSince } }

    /// Opens the folder and watches it. Nil once it is watched, else the error the open failed with.
    private func start() -> Int32? {
        let fd: Int32
        switch openFolder(folder.path) {
        case .success(let opened):
            fd = opened
        case .failure(let failure):
            let error = failure.code.rawValue
            if error != openError {
                Log.write("[watcher] error cannot open \(folder.path): \(String(cString: strerror(error)))")
                openError = error
            }
            retryLater()
            return error
        }
        Log.write("[watcher] watching \(folder.path)\(openError == nil ? "" : " after an error")")
        openError = nil
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .revoke], queue: queue)
        src.setEventHandler { [weak self] in self?.scan() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
        directoryID = DirectoryID(descriptor: fd)
        generation += 1
        state.withLock { $0.watching = true; $0.denied = false; $0.generation = generation }
        return nil
    }

    private static let sharedWithListing: [Int32: Availability] = [
        EINTR: .unavailable, ENOENT: .missing, EPERM: .refused, EACCES: .refused,
    ]

    /// A scan that could not read the folder. A missing folder counts as indexed and empty from
    /// `now`, so the files dated before it are taken in silently when it comes back.
    private func failed(_ availability: Availability, at now: Date) {
        let changed = state.withLock { s in
            let changed = s.unreadableSince == nil || s.availability != availability
            s.availability = availability
            s.denied = availability == .refused
            s.unreadableSince = s.unreadableSince ?? now
            if availability == .missing {
                s.missingSince = s.missingSince ?? now
                s.indexed = true
            }
            return changed
        }
        if changed { DispatchQueue.main.async { [weak self] in self?.onReadState() } }
        retryLater()
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
    func recent(limit: Int, include: (ScreenshotKey) -> Bool = { _ in true }) -> (recent: [ScreenshotKey], files: Int) {
        Self.recent(from: candidates(), in: folder, limit: limit, include: include)
    }

    /// Whether any candidate passes `include`, read as `recent` reads them. It stops at the first.
    func contains(where include: (ScreenshotKey) -> Bool) -> Bool {
        candidates().keys.contains { include(ScreenshotKey(folder: folder, name: $0)) }
    }

    func candidates() -> [String: Date] {
        let snapshot = state.withLock { ($0.files, $0.watching || !$0.indexed) }
        if !snapshot.1, case .available(let inventory) = Self.read(folder) {
            return inventory.candidates(retaining: snapshot.0)
        }
        return snapshot.0
    }

    func newest(include: (ScreenshotKey) -> Bool = { _ in true }) -> ScreenshotKey? {
        recent(limit: 1, include: include).recent.first
    }

    private func scan() {
        if source != nil, directoryID != DirectoryID(folder.path) {
            source?.cancel()
            source = nil
            directoryID = nil
            generation += 1
            // A rename paired in the directory that was replaced is not one in this directory.
            state.withLock { $0.watching = false; $0.generation = generation; $0.held = HeldRenames() }
        }
        // After these a listing meets the same refusal or absence, or waits on the same daemon that
        // did not answer the open, which doubled each failing scan (about 5.4 s each). After any
        // other, such as a volume that can't be watched for events, the folder may still list.
        if source == nil, let error = start(), let failure = Self.sharedWithListing[error] { return failed(failure, at: Date()) }
        let listing = Self.read(folder)
        let now = Date()
        guard case .available(let inventory) = listing else { return failed(listing.availability, at: now) }
        let recovered = state.withLock { $0.unreadableSince != nil }
        let (arrivals, scanNumber, base) = state.withLock { s -> ([(String, Arrival)], Int, (names: Set<String>, scan: Int)) in
            s.scans += 1
            let scanNumber = s.scans
            let base = (names: s.present, scan: s.presentScan)
            s.availability = .available
            s.denied = false
            s.unreadableSince = nil
            let undelivered = Set(s.pending.keys)
            for (name, arrival) in s.pending where arrival.generation != generation {
                s.files[name] = nil
            }
            let current = inventory.candidates(retaining: s.files)
            s.pending = s.pending.filter { current[$0.key] != nil }
            let identities = inventory.identities.filter { current[$0.key] != nil }
            guard s.indexed else {
                s.files = current
                s.identities = identities
                s.indexed = true
                return ([], scanNumber, base)
            }
            var renames: [(from: String, to: String)] = []
            if s.missingSince == nil {
                renames = s.held.hold(Self.renames(removed: Set(s.files.keys).subtracting(current.keys),
                                                   added: Set(current.keys).subtracting(s.files.keys),
                                                   before: s.identities, after: identities),
                                      scan: scanNumber, undelivered: undelivered)
            }
            var known = Set(s.files.keys)
            if let since = s.missingSince {
                // A remount makes old files silent, but previously admitted arrivals are still owed.
                known.formUnion(Set(current.keys).subtracting(inventory.captures(since: since)).subtracting(s.pending.keys))
                s.missingSince = nil
            }
            let renamedTo = Set(renames.map(\.to))
            let added = Self.diff(known: known, current: Set(current.keys)).added.filter { !renamedTo.contains($0) }
            s.files = current
            s.identities = identities
            return (added.map { name in
                let arrival = Arrival(generation: generation)
                s.pending[name] = arrival
                return (name, arrival)
            }, scanNumber, base)
        }
        if recovered { DispatchQueue.main.async { [weak self] in self?.onReadState() } }
        let started = generation, left = Self.left(base.names, for: inventory.names)
        DispatchQueue.main.async {
            let began = ProcessInfo.processInfo.systemUptime
            defer {
                let ms = Int((ProcessInfo.processInfo.systemUptime - began) * 1000)
                if ms > Self.slowHandOffMs { Log.write("[main] slow inventory \(ms)ms") }
            }
            guard self.state.withLock({ $0.generation == started }) else { return }
            guard inventory.directoryID == DirectoryID(self.folder.path),
                  access(self.folder.path, R_OK | X_OK) == 0 else {
                self.rescan(reason: "directory changed before delivery")
                return
            }
            let (renames, removed) = self.state.withLock { s in
                defer { (s.present, s.presentScan) = (inventory.names, scanNumber) }
                let gone = s.presentScan == base.scan ? left : Self.left(s.present, for: inventory.names)
                return s.held.deliver(through: scanNumber, left: gone)
            }
            if !renames.isEmpty {
                self.onRenamed(renames.map {
                    (from: ScreenshotKey(folder: self.folder, name: $0.from), to: ScreenshotKey(folder: self.folder, name: $0.to))
                }, inventory)
            }
            self.onInventory(inventory)
            if !removed.isEmpty {
                self.onRemoved(removed.map { ScreenshotKey(folder: self.folder, name: $0) }, inventory)
            }
        }
        for (name, arrival) in arrivals {
            let key = ScreenshotKey(folder: folder, name: name), url = key.url
            waitUntilComplete(url, arrival: arrival) { [weak self] complete in
                guard let self else { return }
                if complete {
                    // A streamed file's date settles with its content; the index keeps the final one.
                    if let identity = ScreenshotWatcher.identity(of: url) {
                        self.state.withLock {
                            if $0.files[name] != nil { $0.files[name] = identity.modified; $0.identities[name] = identity }
                        }
                    } else if let date = ScreenshotWatcher.modificationDate(of: url) {
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
                        self.onNew(key)
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

    /// The folder's inventory, from one bulk listing. Asking the listing for each file's date is what
    /// keeps this cheap: a per-file attribute call reads extended attributes too and costs about 20
    /// times more (measured on 1300 files: 7 ms against 110 ms).
    private static func read(_ folder: URL) -> Listing {
        let observedAt = ProcessInfo.processInfo.systemUptime
        let before = DirectoryID(folder.path)
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .fileIdentifierKey, .fileSizeKey])
        } catch CocoaError.fileReadNoSuchFile {
            return .unavailable(.missing)
        } catch {
            let posix = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError
            let refused = (error as? CocoaError)?.code == .fileReadNoPermission
                || (posix?.domain == NSPOSIXErrorDomain && [Int(EPERM), Int(EACCES)].contains(posix?.code))
            return .unavailable(refused ? .refused : .unavailable)
        }
        var files: [String: Date] = [:]
        var identities: [String: FileIdentity] = [:]
        for url in urls where isCandidate(url.lastPathComponent) {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileIdentifierKey, .fileSizeKey])
            guard let date = values?.contentModificationDate else { continue }
            files[url.lastPathComponent] = date
            if let identity = identity(from: values) { identities[url.lastPathComponent] = identity }
        }
        guard let before, before == DirectoryID(folder.path) else { return .unavailable(.unavailable) }
        return .available(Inventory(folder: folder, names: Set(urls.map(\.lastPathComponent)), dates: files,
                                    observedAt: observedAt, directoryID: before, identities: identities))
    }
}
