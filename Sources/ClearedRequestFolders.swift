import Darwin
import Foundation

/// What `ScreenshotRequests` remembers about its cleared requests' folders between inventories of
/// the screenshots folder, which every stack open takes on the main thread. Each fact only lets a
/// check be skipped that would have found nothing to do. Nothing is removed on a remembered fact.
struct ClearedRequestFolders {
    let root: URL
    /// `root`'s path, so a request folder's stamp is read without building its URL.
    private let rootPath: String
    /// `request.json`'s modification date, which is when its request was cleared, as last read.
    /// Every write of a record calls `forget`. Pruning skips a request this date says is too young,
    /// and reads the date from disk again before it removes anything.
    private var clearedOn: [String: Date] = [:]
    /// The request folder's stamp when its sent image and submissions were last found gone. A
    /// reply helper can stage a submission after the clear. That adds an entry to the folder, which
    /// changes the stamp, so the next inventory looks again.
    private var payloadsGone: [String: Stamp] = [:]

    init(root: URL) {
        self.root = root
        rootPath = root.path
    }

    struct Stamp: Equatable {
        let inode: UInt64
        let seconds: Int
        let nanoseconds: Int

        var date: Date { Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(nanoseconds) / 1e9) }

        init?(_ path: String) {
            var info = stat()
            guard stat(path, &info) == 0 else { return nil }
            inode = UInt64(info.st_ino)
            seconds = info.st_mtimespec.tv_sec
            nanoseconds = info.st_mtimespec.tv_nsec
        }
    }

    /// When the request was cleared. `fresh` reads the date from disk even when one is remembered.
    mutating func clearedOn(_ id: String, fresh: Bool = false) -> Date? {
        if !fresh, let date = clearedOn[id] { return date }
        let file = ReplyProtocol.requestDirectory(root: root, requestID: id).appendingPathComponent(ScreenshotRequests.recordFileName)
        let date = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        clearedOn[id] = date
        return date
    }

    /// Removes the sent image, its pins and the submissions from a cleared request's folder, unless a pass
    /// found them gone and the folder's stamp has not changed since.
    mutating func removePayloads(of id: String, now: Date = Date()) {
        let before = Stamp(rootPath + "/" + id)
        if let before, payloadsGone[id] == before { return }
        let directory = ReplyProtocol.requestDirectory(root: root, requestID: id)
        var allAbsent = true
        for name in ["image.png", "pins.json", "submissions"] {
            let url = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else {
                // `fileExists` is false on any failure, such as a folder that cannot be searched
                // or a dangling link. Only a missing name lets the pass count as finished.
                if !Self.isMissing(url.path) { allAbsent = false }
                continue
            }
            allAbsent = false
            do { try FileManager.default.removeItem(at: url) }
            catch { Log.write("[requests] error cleanup \(id): \(error.localizedDescription)") }
        }
        // The stamp is read before the pass looks, so an entry added during the pass changes it.
        // It is kept only once it is two seconds old, so a file system that stores whole seconds
        // still gives a later change a different stamp.
        let settled = allAbsent && before.map { now.timeIntervalSince($0.date) > 2 } == true
        payloadsGone[id] = settled ? before : nil
    }

    private static func isMissing(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) != 0 && errno == ENOENT
    }

    /// Drops both facts, when the request's record is written or its folder removed.
    mutating func forget(_ id: String) {
        clearedOn[id] = nil
        payloadsGone[id] = nil
    }
}
