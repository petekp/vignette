import CryptoKit
import Foundation

/// Drawings on disk, owned by the app: one JSON file per screenshot at `<directory>/<id>.json`.
/// Builds from different worktrees share the folder, so a file from a newer build is read as no
/// drawing and is never written over or removed. Every problem a read or a write meets is one
/// `[drawing]` line.
struct DrawingStore {
    let directory: URL
    private let log: @Sendable (String) -> Void

    init(directory: URL, log: @escaping @Sendable (String) -> Void = { Log.write($0) }) {
        self.directory = directory
        self.log = log
    }

    /// Why a drawing was not written.
    enum Refusal: Error, CustomStringConvertible {
        case newerVersion(Int)

        var description: String {
            switch self {
            case .newerVersion(let version): return "the file is version \(version), newer than this build's \(Drawing.version)"
            }
        }
    }

    /// The file name for a key: a hash, so any path fits and the name is stable across launches.
    static func id(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    func url(for key: String) -> URL { directory.appendingPathComponent(Self.id(for: key) + ".json") }

    /// The drawing stored for the screenshot at `key`, whose size is `pixels`, or nil when there is
    /// none this build can use. A file that does not parse is set aside as `<id>.json.invalid`; any
    /// other file it cannot use stays where it is. Each mark is checked and placed inside the image.
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
            let aside = url.appendingPathExtension("invalid")
            try? FileManager.default.removeItem(at: aside)
            do {
                try FileManager.default.moveItem(at: url, to: aside)
                log("[drawing] error invalid \(name): \(reason); kept as \(aside.lastPathComponent)")
            } catch {
                log("[drawing] error invalid \(name): \(reason); could not set it aside: \(error.localizedDescription)")
            }
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
        return Drawing(key: key, pixels: pixels, pointScale: stored.pointScale, marks: marks)
    }

    /// Writes `drawing` atomically, or removes its file when it has no marks. Throws, after its one
    /// log line, when the write fails or the file is from a newer build, which is left as it is.
    func write(_ drawing: Drawing) throws {
        guard !drawing.marks.isEmpty else { return try remove(key: drawing.key) }
        let url = url(for: drawing.key)
        let name = (drawing.key as NSString).lastPathComponent
        try refuseNewer(url, name: name)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try drawing.encoded().write(to: url, options: .atomic)
        } catch {
            log("[drawing] error write-failed \(name): \(error.localizedDescription)")
            throw error
        }
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

    /// The key of every drawing this build can read, so the drawings of screenshots that are gone
    /// can be removed. A file that does not parse or is from a newer build is not listed.
    func keys() -> Set<String> {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var keys = Set<String>()
        for file in files where file.pathExtension == "json" {
            // A file under another key's name would be read, written and removed as that key's.
            if case .stored(let stored) = contents(of: file), file.deletingPathExtension().lastPathComponent == Self.id(for: stored.key) {
                keys.insert(stored.key)
            }
        }
        return keys
    }

    private func refuseNewer(_ url: URL, name: String) throws {
        guard case .newer(let version) = contents(of: url) else { return }
        let refusal = Refusal.newerVersion(version)
        log("[drawing] warning not-written \(name): \(refusal)")
        throw refusal
    }

    /// A file's top level, checked; its marks are checked one at a time by `read`.
    private struct Stored {
        let key: String
        let pixels: PixelSize
        let pointScale: CGFloat
        let marks: [Any]
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
        guard let marks = object["marks"] as? [Any] else { return .invalid("marks must be a list") }
        return .stored(Stored(key: key, pixels: PixelSize(width: width, height: height), pointScale: pointScale, marks: marks))
    }
}
