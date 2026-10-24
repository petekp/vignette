import Foundation

/// A screenshot's identity: its path as the watch folder spells it, the folder's setting
/// as stored plus the file's name as the listing gives it. The drawings, the cards' notices, the
/// annotation run and the capture origin are keyed by it, and a drawing's file is named by a hash
/// of `path`, so a key must spell a path exactly as the watcher always has.
struct ScreenshotKey: Hashable, Sendable, Comparable {
    let path: String

    var url: URL { URL(fileURLWithPath: path, isDirectory: false) }
    var name: String { (path as NSString).lastPathComponent }

    /// The watcher's spelling of `name` listed in `folder`.
    init(folder: URL, name: String) {
        path = folder.appendingPathComponent(name).path
    }

    /// The key of a file named from outside the folder (a URL command, an agent's push, a request
    /// record): `file` by the folder's own spelling after resolving symlinks on both sides, so
    /// `/tmp/x.png` and `/private/tmp/x.png` reach one screenshot. Nil for a file outside `folder`.
    init?(resolving file: URL, in folder: URL) {
        var root = Commands.realPath(folder)
        if !root.hasSuffix("/") { root += "/" }
        let real = Commands.realPath(file)
        guard real.hasPrefix(root) else { return nil }
        self.init(folder: folder, name: String(real.dropFirst(root.count)))
    }

    /// `file` as the folder spells it, or as given when it is outside the folder: a debug-mode
    /// command's target, or a reply reserved before the folder changed, which keeps its location.
    init(naming file: URL, in folder: URL) {
        self = ScreenshotKey(resolving: file, in: folder) ?? ScreenshotKey(asGiven: file)
    }

    /// A key read back as it was stored (a drawing's, a request's source, a reply's reserved
    /// location), or a file outside the watch folder that a debug-mode command names.
    init(asGiven path: String) {
        self.path = path
    }

    init(asGiven url: URL) {
        path = url.path
    }

    static func < (a: ScreenshotKey, b: ScreenshotKey) -> Bool { a.path < b.path }
}
