import CryptoKit
import Foundation

/// Drawings on disk, owned by the app: one JSON file per screenshot at `<directory>/<id>.json`.
/// Builds from different worktrees share the folder, so a file from a newer build is read as no
/// drawing and is never written over or removed. Every problem a read or a write meets is one
/// `[drawing]` line.
struct DrawingStore: Sendable {
    let directory: URL
    private let log: @Sendable (String) -> Void

    init(directory: URL, log: @escaping @Sendable (String) -> Void = { Log.write($0) }) {
        self.directory = directory
        self.log = log
    }

    /// Why a drawing was not written.
    enum Refusal: Error, CustomStringConvertible {
        case newerVersion(Int)
        case incomplete(String)

        var description: String {
            switch self {
            case .newerVersion(let version): return "the file is version \(version), newer than this build's \(Drawing.version)"
            case .incomplete(let reason): return "the complete drawing could not be read: \(reason)"
            }
        }
    }

    /// The file name for a key: a hash, so any path fits and the name is stable across launches.
    static func id(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    func url(for key: String) -> URL { directory.appendingPathComponent(Self.id(for: key) + ".json") }

    /// The drawing stored for the screenshot at `key`, whose size is `pixels`, or nil when there is
    /// none this build can use. A file it cannot use stays where it is: a read runs beside the main
    /// thread's writes, and a set-aside here could move the file a write had just put in its place.
    /// Each mark is checked and placed inside the image.
    func read(key: String, pixels: PixelSize, style: TextStyle) -> Drawing? {
        let url = url(for: key)
        let name = (key as NSString).lastPathComponent
        let stored: Stored
        switch contents(of: url) {
        case .missing:
            return nil
        case .unreadable(let reason):
            log("[drawing] error unreadable \(name): \(reason)")
            return nil
        case .invalid(let reason):
            log("[drawing] error invalid \(name): \(reason); opened without it")
            return nil
        case .newer(let version):
            log("[drawing] warning newer \(name): version \(version) is newer than this build's \(Drawing.version); opened without it")
            return nil
        case .stored(let contents):
            stored = contents
        }
        guard stored.key == key else {
            log("[drawing] warning other-key \(name): the file holds another screenshot's drawing; opened without it")
            return nil
        }
        guard stored.pixels == pixels else {
            log("[drawing] dropped \(name): made on \(stored.pixels.width)x\(stored.pixels.height), the image is \(pixels.width)x\(pixels.height)")
            return nil
        }
        var marks: [Mark] = []
        for (index, item) in stored.marks.enumerated() {
            do {
                let mark = try Mark(validating: item)
                guard let placed = mark.placed(in: pixels, pointScale: stored.pointScale, style: style) else {
                    throw MarkProblem("nothing of it fits inside the image")
                }
                if placed != mark { log("[drawing] moved mark=\(index + 1) \(name): it did not fit where it was") }
                marks.append(placed)
            } catch {
                log("[drawing] dropped mark=\(index + 1) \(name): \(error)")
            }
        }
        guard !marks.isEmpty else { return nil }
        return Drawing(key: key, pixels: pixels, pointScale: stored.pointScale, markScale: stored.markScale, marks: marks)
    }

    /// The message stored with the screenshot at `key`, whose size is `pixels`: the words last left in
    /// the editor's message field for it, or "" when there are none. A file this build cannot use
    /// holds none; `read` logs why.
    func readMessage(key: String, pixels: PixelSize) -> String {
        guard case .stored(let stored) = contents(of: url(for: key)), stored.key == key, stored.pixels == pixels else { return "" }
        return stored.message
    }

    /// A reply checkpoint must preserve every stored mark and its geometry. Ordinary reads may
    /// recover individual marks; using that partial result would publish an incomplete reply.
    func readComplete(key: String, pixels: PixelSize, style: TextStyle) throws -> Drawing? {
        do {
            let file = url(for: key)
            let stored: Stored
            switch contents(of: file) {
            case .missing:
                guard !FileManager.default.fileExists(atPath: file.appendingPathExtension("invalid").path) else {
                    throw Refusal.incomplete("the launch scan set its invalid file aside")
                }
                return nil
            case .unreadable(let reason), .invalid(let reason): throw Refusal.incomplete(reason)
            case .newer(let version): throw Refusal.newerVersion(version)
            case .stored(let contents): stored = contents
            }
            guard stored.key == key else { throw Refusal.incomplete("the key does not match") }
            guard !stored.marks.isEmpty else { return nil }
            guard stored.pixels == pixels else { throw Refusal.incomplete("the image size does not match") }
            let marks: [Mark]
            do {
                marks = try stored.marks.map {
                    let mark = try Mark(validating: $0)
                    switch mark.geometry {
                    case .text(let text):
                        // Typography can change after installation. Check the anchor without
                        // reflowing the stored note under the current style.
                        guard text.origin.x >= 0, text.origin.x < CGFloat(pixels.width),
                              text.origin.y >= 0, text.origin.y < CGFloat(pixels.height) else {
                            throw Refusal.incomplete("a note's anchor is outside the image")
                        }
                    default:
                        guard mark.placed(in: pixels, pointScale: stored.pointScale, style: style)?.geometry == mark.geometry else {
                            throw Refusal.incomplete("a shape is outside the image")
                        }
                    }
                    return mark
                }
            }
            catch { throw Refusal.incomplete("\(error)") }
            return Drawing(key: key, pixels: pixels, pointScale: stored.pointScale, markScale: stored.markScale, marks: marks)
        } catch {
            log("[drawing] error incomplete \((key as NSString).lastPathComponent): \(error)")
            throw error
        }
    }

    /// Writes `drawing` atomically with `message`, or with the message the file holds when `message` is
    /// nil, and removes the file when there is neither a mark nor a message. Answers whether the file
    /// holds a message now. Throws, after its one log line, when the write fails or the file is from
    /// a newer build, which is left as it is.
    @discardableResult
    func write(_ drawing: Drawing, message: String? = nil) throws -> Bool {
        let url = url(for: drawing.key)
        let name = (drawing.key as NSString).lastPathComponent
        let existing = contents(of: url)
        try refuse(existing, name: name)
        let kept = message ?? Self.message(in: existing, fitting: drawing)
        guard !drawing.marks.isEmpty || !kept.isEmpty else {
            try remove(key: drawing.key)
            return false
        }
        try put(Self.encoded(drawing, message: kept), at: url, name: name)
        return !kept.isEmpty
    }

    /// Writes `message` into the file of `drawing`'s screenshot and leaves its stored marks as they are.
    /// With no file that fits the image, a file with no marks holds the message; with no marks and no
    /// message the file goes. Answers whether the file holds a message now. Throws like `write`.
    @discardableResult
    func writeMessage(_ message: String, for drawing: Drawing) throws -> Bool {
        let url = url(for: drawing.key)
        let name = (drawing.key as NSString).lastPathComponent
        let existing = contents(of: url)
        try refuse(existing, name: name)
        if case .unreadable(let reason) = existing {
            log("[drawing] error write-failed \(name): the file could not be read: \(reason)")
            throw Refusal.incomplete(reason)
        }
        guard case .stored(let stored) = existing, stored.key == drawing.key, stored.pixels == drawing.pixels else {
            guard !message.isEmpty else { return false }
            var empty = drawing
            empty.marks = []
            try put(Self.encoded(empty, message: message), at: url, name: name)
            return true
        }
        guard !stored.marks.isEmpty || !message.isEmpty else {
            try remove(key: drawing.key)
            return false
        }
        var object = stored.object
        object["message"] = message.isEmpty ? nil : message
        try put(Self.data(of: object), at: url, name: name)
        return !message.isEmpty
    }

    private func put(_ data: @autoclosure () throws -> Data, at url: URL, name: String) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data().write(to: url, options: .atomic)
        } catch {
            log("[drawing] error write-failed \(name): \(error.localizedDescription)")
            throw error
        }
    }

    /// `drawing`'s file, with `message` under "message" when there is one.
    private static func encoded(_ drawing: Drawing, message: String) throws -> Data {
        let file = try drawing.encoded()
        guard !message.isEmpty, var object = try DrawingJSON.object(from: file) as? [String: Any] else { return file }
        object["message"] = message
        return try data(of: object)
    }

    private static func data(of object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// The message a file holds for `drawing`'s image, or "" when it holds none or does not fit it.
    private static func message(in contents: Contents, fitting drawing: Drawing) -> String {
        guard case .stored(let stored) = contents, stored.key == drawing.key, stored.pixels == drawing.pixels else { return "" }
        return stored.message
    }

    /// Removes the drawing stored for `key`, if there is one. Throws like `write`.
    func remove(key: String) throws {
        let url = url(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let name = (key as NSString).lastPathComponent
        try refuseNewer(url, name: name)
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            log("[drawing] error write-failed \(name): \(error.localizedDescription)")
            throw error
        }
    }

    /// Moves the drawing stored for `old` to `new`: the file under `new`'s name carries `new` as its
    /// key, and the one under `old`'s name goes. Answers the drawing's pixel size, or nil when none is
    /// stored for `old`. Throws like `write`, and leaves `old` in place when `new` could not be written.
    func rename(from old: String, to new: String) throws -> PixelSize? {
        guard old != new, case .stored(let stored) = contents(of: url(for: old)), stored.key == old else { return nil }
        let target = url(for: new), name = (new as NSString).lastPathComponent
        try refuseNewer(target, name: name)
        var object = stored.object
        object["key"] = new
        try put(Self.data(of: object), at: target, name: name)
        try remove(key: old)
        return stored.pixels
    }

    /// The files this build can read, by the key of their screenshot.
    struct Scan: Equatable {
        /// The keys whose file holds marks.
        var drawings: Set<String> = []
        /// The keys whose file holds a message.
        var messages: Set<String> = []
    }

    /// The key of every file this build can read, so the files of screenshots that are gone can be
    /// removed. A file from a newer build is not listed. A file that does not parse is set
    /// aside as `<id>.json.invalid`, here and nowhere else: this runs once, at launch, before
    /// anything reads or writes a drawing, so nothing can have put a good file in its place.
    func scan() -> Scan {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var keys = Scan()
        for file in files where file.pathExtension == "json" {
            switch contents(of: file) {
            case .stored(let stored):
                // A file under another key's name would be read, written and removed as that key's.
                guard file.deletingPathExtension().lastPathComponent == Self.id(for: stored.key) else { break }
                if !stored.marks.isEmpty { keys.drawings.insert(stored.key) }
                if !stored.message.isEmpty { keys.messages.insert(stored.key) }
            case .invalid(let reason):
                setAside(file, reason: reason)
            case .missing, .unreadable, .newer:
                break
            }
        }
        return keys
    }

    private func setAside(_ file: URL, reason: String) {
        let aside = file.appendingPathExtension("invalid")
        try? FileManager.default.removeItem(at: aside)
        do {
            try FileManager.default.moveItem(at: file, to: aside)
            log("[drawing] error invalid \(file.lastPathComponent): \(reason); kept as \(aside.lastPathComponent)")
        } catch {
            log("[drawing] error invalid \(file.lastPathComponent): \(reason); could not set it aside: \(error.localizedDescription)")
        }
    }

    private func refuseNewer(_ url: URL, name: String) throws {
        try refuse(contents(of: url), name: name)
    }

    private func refuse(_ contents: Contents, name: String) throws {
        guard case .newer(let version) = contents else { return }
        let refusal = Refusal.newerVersion(version)
        log("[drawing] warning not-written \(name): \(refusal)")
        throw refusal
    }

    /// A file's top level, checked; its marks are checked one at a time by `read`.
    private struct Stored {
        let key: String
        let pixels: PixelSize
        let pointScale: CGFloat
        let markScale: CGFloat
        let marks: [Any]
        /// What was typed in the message field for the screenshot, or "".
        let message: String
        /// The whole file, as parsed.
        let object: [String: Any]
    }

    private enum Contents {
        case missing
        case unreadable(String)
        case invalid(String)
        case newer(Int)
        case stored(Stored)
    }

    private func contents(of url: URL) -> Contents {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        let data: Data
        do { data = try Data(contentsOf: url) } catch { return .unreadable(error.localizedDescription) }
        let object: [String: Any]
        do {
            guard let decoded = try DrawingJSON.object(from: data) as? [String: Any] else { return .invalid("the top level is not an object") }
            object = decoded
        } catch {
            // The debug description says where parsing stopped; the localized one says only that it did.
            return .invalid((error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? "not JSON")
        }
        guard let version = DrawingJSON.wholeNumber(object["version"]), version >= 1 else {
            return .invalid("version must be a whole number from 1")
        }
        if version > Drawing.version { return .newer(version) }
        guard let key = object["key"] as? String else { return .invalid("key must be a string") }
        guard let pixels = object["pixels"] as? [Any], pixels.count == 2,
              let width = DrawingJSON.wholeNumber(pixels[0]), let height = DrawingJSON.wholeNumber(pixels[1]),
              width > 0, height > 0 else {
            return .invalid("pixels must be two whole numbers above 0")
        }
        guard let pointScale = DrawingJSON.number(object["pointScale"]), Drawing.pointScales.contains(pointScale) else {
            let range = Drawing.pointScales
            return .invalid("pointScale must be a number from \(String(format: "%g", range.lowerBound)) to \(String(format: "%g", range.upperBound))")
        }
        let markScale = object["markScale"] == nil ? 1 : DrawingJSON.number(object["markScale"])
        guard let markScale, Drawing.markScales.contains(markScale) else {
            let range = Drawing.markScales
            return .invalid("markScale must be a number from \(String(format: "%g", range.lowerBound)) to \(String(format: "%g", range.upperBound))")
        }
        guard let marks = object["marks"] as? [Any] else { return .invalid("marks must be a list") }
        // A file written before the message was kept has none.
        let message = (object["message"] as? String).map { String($0.prefix(MarkFields.maxTextLength)) } ?? ""
        return .stored(Stored(key: key, pixels: PixelSize(width: width, height: height), pointScale: pointScale, markScale: markScale,
                              marks: marks, message: message, object: object))
    }
}
