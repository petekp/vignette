import AppKit

/// The app's drawings: the store on disk, the screenshots that have one, and every change a drawing
/// takes outside the editor's own hand-over — agents' marks, a screenshot that goes, and the sweep at
/// launch. Every change to the set is one `[drawings] <n>` line, every write one `[drawing]` line.
@MainActor
final class Drawings {
    let store: DrawingStore
    /// The screenshots with a drawing on disk, by path.
    private(set) var keys: Set<String>
    /// The set changed.
    var onChange: ((Set<String>) -> Void)?
    /// The last drawing `write` was given, and whether it is on disk: how a push to the open drawing
    /// learns what the editor's hand-over did with it.
    private var lastWrite: (key: String, written: Bool)?

    init(store: DrawingStore) {
        self.store = store
        keys = store.keys()
    }

    /// The stored drawing for the screenshot at `url`, whose size as displayed is `pixels`.
    func read(_ url: URL, pixels: PixelSize, style: TextStyle) -> Drawing? {
        store.read(key: url.path, pixels: pixels, style: style)
    }

    /// Writes a drawing, or removes its file when it has no marks. `reason` names the moment in the
    /// log line: saved after a change, parked, or built from an agent's marks. A drawing for a file
    /// that is gone is not written: the editor can hand one over after its file was trashed.
    @discardableResult
    func write(_ drawing: Drawing, reason: String) -> Bool {
        let name = (drawing.key as NSString).lastPathComponent
        lastWrite = (drawing.key, false)
        if !drawing.marks.isEmpty, !FileManager.default.fileExists(atPath: drawing.key) { return false }
        do { try store.write(drawing) } catch { return false }
        lastWrite = (drawing.key, true)
        if drawing.marks.isEmpty {
            guard keys.remove(drawing.key) != nil else { return true }
            Log.write("[drawing] removed \(name)")
        } else {
            Log.write("[drawing] \(reason) \(name)")
            guard keys.insert(drawing.key).inserted else { return true }
        }
        changed()
        return true
    }

    /// The screenshots went: moved to the Trash by the app, or removed from the folder.
    func remove(_ urls: [URL]) {
        let had = urls.filter { keys.contains($0.path) }
        guard !had.isEmpty else { return }
        for url in had where (try? store.remove(key: url.path)) != nil { keys.remove(url.path) }
        Log.write("[drawing] removed \(had.map(\.lastPathComponent).joined(separator: ", "))")
        changed()
    }

    /// Removes the drawings whose screenshot is gone. Once, at launch.
    func sweep(keeping exists: (String) -> Bool) {
        for key in keys.sorted() where !exists(key) {
            guard (try? store.remove(key: key)) != nil else { continue }
            keys.remove(key)
            Log.write("[drawing] swept \((key as NSString).lastPathComponent)")
        }
        Log.write("[drawings] \(keys.count) dir=\(store.directory.path)")
        onChange?(keys)
    }

    private func changed() {
        Log.write("[drawings] \(keys.count)")
        onChange?(keys)
    }

    // MARK: Agents' marks

    /// Why agents' marks did not become part of a drawing, with the code the command answers.
    struct Failure: Error, CustomStringConvertible {
        let code: CommandError
        let description: String
    }

    /// Adds an agent's marks to the drawing of the screenshot at `url`, and answers how many joined.
    /// When `editor` has that screenshot open, the marks join its drawing as one undo step, and the
    /// editor hands the drawing over at once, which must reach `write`. Otherwise they are added to
    /// the stored drawing, or a new one at `newPointScale`, and the colour pass runs over the ones
    /// without a named colour. Either way the file is written before this returns, or it throws.
    /// `sample` is the colour pass's sample of that screenshot; without one the marks keep the
    /// colour they start in.
    func add(_ agentMarks: [AgentMark], to url: URL, editor: EditorView?, sample: ColorSample?,
             style: TextStyle, newPointScale: CGFloat) throws -> Int {
        let name = url.lastPathComponent
        if let editor, editor.core.isOpen, editor.core.drawing.key == url.path {
            let open = editor.core.drawing
            let made = marks(agentMarks, in: open.pixels, pointScale: open.pointScale, style: editor.core.style, name: name)
            lastWrite = nil
            editor.addAgentMarks(made)
            let joined = editor.core.drawing.marks.count - open.marks.count
            guard joined > 0 else { return 0 }
            guard let lastWrite, lastWrite.key == url.path, lastWrite.written else {
                throw Failure(code: .writeFailed, description: "the drawing for \(name) could not be written")
            }
            return joined
        }
        guard let pixels = PixelSize(imageAt: url) else {
            throw Failure(code: .unreadableImage, description: "\(name) is not an image this Mac can read")
        }
        let pointScale = min(max(newPointScale, Drawing.pointScales.lowerBound), Drawing.pointScales.upperBound)
        var drawing = read(url, pixels: pixels, style: style) ?? Drawing(key: url.path, pixels: pixels, pointScale: pointScale, marks: [])
        var made = marks(agentMarks, in: pixels, pointScale: drawing.pointScale, style: style, name: name)
        if let sample {
            for index in made.indices where !made[index].colorChosen {
                made[index].color = sample.pick(for: made[index], pointScale: drawing.pointScale, style: style)
            }
        }
        guard !made.isEmpty else { return 0 }
        drawing.marks += made
        guard write(drawing, reason: "built") else {
            throw Failure(code: .writeFailed, description: "the drawing for \(name) could not be written")
        }
        return made.count
    }

    /// `AgentMark.marks`, with its one line for texts that do not fit.
    private func marks(_ agentMarks: [AgentMark], in pixels: PixelSize, pointScale: CGFloat, style: TextStyle, name: String) -> [Mark] {
        let made = AgentMark.marks(agentMarks, in: pixels, pointScale: pointScale, style: style)
        if !made.tooLong.isEmpty {
            Log.write("[marks] text too long for \(name): mark \(made.tooLong.map(String.init).joined(separator: ", ")) is cut off at its edge")
        }
        return made.marks
    }

    // MARK: What the web editor left

    /// Removes the folders the web editor kept, where they are still there: its drafts, which are
    /// not carried over, and WebKit's data. Nothing reads them now. Every launch asks; once they are
    /// gone that is one lookup each.
    static func removeWebEditorData(_ folders: [URL]) {
        for folder in folders where FileManager.default.fileExists(atPath: folder.path) {
            do {
                try FileManager.default.removeItem(at: folder)
                Log.write("[app] removed web editor data \(folder.path)")
            } catch {
                Log.write("[app] error write-failed could not remove web editor data \(folder.path): \(error.localizedDescription)")
            }
        }
    }
}
