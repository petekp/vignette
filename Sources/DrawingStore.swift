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
    /// Each mark and each pin is checked and placed inside the image.
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
        let pinned = Pin.read(stored.pins, nextPin: stored.nextPin, in: pixels) { what, why in log("[drawing] \(what) \(name): \(why)") }
        guard !marks.isEmpty || !pinned.pins.isEmpty else { return nil }
        return Drawing(key: key, pixels: pixels, pointScale: stored.pointScale, markScale: stored.markScale, marks: marks,
                       pins: pinned.pins, nextPin: pinned.nextPin)
    }

    /// The message stored with the screenshot at `key`, whose size is `pixels`: the words last left in
    /// the editor's message field for it, or "" when there are none. A file this build cannot use
    /// holds none; `read` logs why.
    func readMessage(key: String, pixels: PixelSize) -> String {
        guard case .stored(let stored) = contents(of: url(for: key)), stored.key == key, stored.pixels == pixels else { return "" }
        return stored.message
    }

    /// The undo and redo history stored with the screenshot at `key`, whose size is `pixels`, for the
    /// drawing read from its file, whose marks are `marks` and pins `pins`: empty when there is none, or
    /// when the marks, the pins or the message changed since the editor wrote it, such as by a reply's
    /// drawing installed while it was closed.
    func readHistory(key: String, pixels: PixelSize, marks: [Mark], pins: [Pin] = []) -> EditorHistory {
        guard case .stored(let stored) = contents(of: url(for: key)), stored.key == key, stored.pixels == pixels,
              let history = stored.object["history"] else { return EditorHistory() }
        do {
            let written = try stored.marks.map { try Mark(validating: $0) }
            guard written.count == marks.count else { throw MarkProblem("a mark was dropped as the file was read") }
            let writtenPins = try stored.pins.map { try Pin(validating: $0) }
            guard writtenPins.count == pins.count else { throw MarkProblem("a pin was dropped as the file was read") }
            let basis = try EditorHistory.basis(marks: written, pins: writtenPins, nextPin: Pin.writtenNextPin(stored.nextPin) ?? 1,
                                                message: stored.message)
            return try EditorHistory(fileObject: history, marks: marks, basis: basis)
        } catch {
            log("[drawing] history dropped \((key as NSString).lastPathComponent): \(error)")
            return EditorHistory()
        }
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
            guard !stored.marks.isEmpty || !stored.pins.isEmpty else { return nil }
            guard stored.pixels == pixels else { throw Refusal.incomplete("the image size does not match") }
            var pinProblem: String?
            let pinned = Pin.read(stored.pins, nextPin: stored.nextPin, in: pixels) { what, why in pinProblem = pinProblem ?? "\(what): \(why)" }
            if let pinProblem { throw Refusal.incomplete(pinProblem) }
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
            return Drawing(key: key, pixels: pixels, pointScale: stored.pointScale, markScale: stored.markScale, marks: marks,
                           pins: pinned.pins, nextPin: pinned.nextPin)
        } catch {
            log("[drawing] error incomplete \((key as NSString).lastPathComponent): \(error)")
            throw error
        }
    }

    /// Writes `drawing` atomically with `message`, or with the message the file holds when `message` is
    /// nil, and with `history`, the editor's, which ends at them; any history the file held goes. A higher
    /// `nextPin` in the file is kept, so a pin number is never used twice while the file exists. Removes
    /// the file when there is no mark, no pin and no message. Answers whether the file holds a message now.
    /// Throws, after its one log line, when the write fails or the file is from a newer build, which is
    /// left as it is.
    @discardableResult
    func write(_ drawing: Drawing, message: String? = nil, history: EditorHistory = EditorHistory()) throws -> Bool {
        let url = url(for: drawing.key)
        let name = (drawing.key as NSString).lastPathComponent
        let existing = contents(of: url)
        try refuse(existing, name: name)
        let kept = message ?? Self.message(in: existing, fitting: drawing)
        guard !drawing.isEmpty || !kept.isEmpty else {
            try remove(key: drawing.key)
            return false
        }
        var drawing = drawing
        drawing.nextPin = max(drawing.nextPin, Self.nextPin(in: existing, fitting: drawing))
        try put(Self.encoded(drawing, message: kept, history: history), at: url, name: name)
        return !kept.isEmpty
    }

    /// Writes `message` into the file of `drawing`'s screenshot, with `history`, which ends at
    /// `drawing`'s marks, pins and `message`, and leaves its stored marks and pins as they are. With no file
    /// that fits the image, a file with no marks and no pins holds the message; with no mark, no pin and
    /// no message the file goes.
    /// Answers whether the file holds a message now. Throws like `write`.
    @discardableResult
    func writeMessage(_ message: String, for drawing: Drawing, history: EditorHistory = EditorHistory()) throws -> Bool {
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
            empty.pins = []
            try put(Self.encoded(empty, message: message, history: history, endingAt: drawing), at: url, name: name)
            return true
        }
        guard !stored.marks.isEmpty || !stored.pins.isEmpty || !message.isEmpty else {
            try remove(key: drawing.key)
            return false
        }
        var object = stored.object
        object["message"] = message.isEmpty ? nil : message
        // Until the next hand-over writes the marks, the file's may lag the history's; reading it then
        // drops the history.
        object["history"] = try history.fileObject(endingAt: drawing, message: message)
        let aboutPins = !stored.pins.isEmpty || (Pin.writtenNextPin(stored.nextPin) ?? 1) > 1 || EditorHistory.mentionsPins(object["history"])
        object["version"] = Drawing.fileVersion(aboutPins: aboutPins)
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

    /// `drawing`'s file, with `message` under "message" when there is one and `history` under "history"
    /// when it has steps. The history ends at `end`, the drawing itself unless given. A history step about
    /// pins makes the file version 2.
    private static func encoded(_ drawing: Drawing, message: String, history: EditorHistory, endingAt end: Drawing? = nil) throws -> Data {
        let file = try drawing.encoded()
        let historyObject = try history.fileObject(endingAt: end ?? drawing, message: message)
        guard !message.isEmpty || historyObject != nil, var object = try DrawingJSON.object(from: file) as? [String: Any] else { return file }
        object["message"] = message.isEmpty ? nil : message
        object["history"] = historyObject
        if EditorHistory.mentionsPins(historyObject) { object["version"] = Drawing.fileVersion(aboutPins: true) }
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

    /// The `nextPin` a file holds for `drawing`'s image, or 1 when it holds none or does not fit it.
    private static func nextPin(in contents: Contents, fitting drawing: Drawing) -> Int {
        guard case .stored(let stored) = contents, stored.key == drawing.key, stored.pixels == drawing.pixels else { return 1 }
        return Pin.writtenNextPin(stored.nextPin) ?? 1
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
        /// The keys whose file holds a drawing: marks, pins or both.
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
                if !stored.marks.isEmpty || !stored.pins.isEmpty { keys.drawings.insert(stored.key) }
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
}
