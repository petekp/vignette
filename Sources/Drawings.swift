import AppKit

/// The drawing open in the editor. Its marks are ahead of the stored file until the editor's next
/// hand-over, so it is the drawing as it is now.
@MainActor
protocol OpenDrawing: AnyObject {
    /// The drawing open for `key` as the editor would hand it over now, or nil when that screenshot
    /// is not open.
    func drawing(of key: ScreenshotKey) -> Drawing?
    /// Joins `marks`, already in the open drawing's px, as one undo step. Answers the drawing to
    /// store in place of a hand-over, or nil when none of them joined.
    func join(_ marks: [Mark]) -> Drawing?
    /// The screenshot `old` was renamed to `new`: an open drawing for `old` is now for `new`.
    func rekey(_ old: ScreenshotKey, to new: ScreenshotKey)
}

/// The app's drawings: the store on disk, the screenshots that have one, and every change a drawing
/// takes outside the editor's own hand-over — agents' marks, a screenshot that goes, and the sweep at
/// launch. Every change to the set is one `[drawings] <n>` line, every write one `[drawing]` line.
@MainActor
final class Drawings {
    let store: DrawingStore
    /// The screenshots with a drawing on disk.
    private(set) var keys: Set<ScreenshotKey>
    /// A screenshot's drawing changed on disk: written, with the drawing as it is now, or removed
    /// (nil). Every write and removal calls it, whether or not the set of keys changed.
    var onChange: ((_ key: ScreenshotKey, _ drawing: Drawing?) -> Void)?
    /// The editor's drawing, which `current` and `add` take over the stored one.
    weak var open: OpenDrawing?
    /// Counts the writes and removals of each key, so a `load` that began before one is dropped.
    private var revisions: [ScreenshotKey: Int] = [:]
    private var changedAt: [ScreenshotKey: TimeInterval] = [:]
    /// Where `load` reads, several at once, so the cards of a stack are read together.
    nonisolated static let loads = DispatchQueue(label: "vignette.drawing-loads", qos: .userInitiated, attributes: .concurrent)

    init(store: DrawingStore) {
        self.store = store
        keys = Set(store.scan().map { ScreenshotKey(asGiven: $0) })
    }

    /// The stored drawing for the screenshot `key`, whose size as displayed is `pixels`.
    func read(_ key: ScreenshotKey, pixels: PixelSize, style: TextStyle) -> Drawing? {
        store.read(key: key.path, pixels: pixels, style: style)
    }

    /// The drawing of the screenshot `key` as it is now: the editor's when it is open there, else
    /// the stored one. Only a screenshot with a stored drawing has its file read, so one without
    /// never has its image header read either, which would download it from iCloud.
    func current(of key: ScreenshotKey, style: TextStyle) -> Drawing? {
        current(of: key) { [self] in
            guard keys.contains(key), let pixels = PixelSize(imageAt: key.url) else { return nil }
            return read(key, pixels: pixels, style: style)
        }
    }

    /// `current(of:style:)` for a caller that already holds the stored drawing, as a card does.
    func current(of key: ScreenshotKey, stored: () -> Drawing?) -> Drawing? {
        open?.drawing(of: key) ?? stored()
    }

    /// The stored drawings for the screenshots `keys`, read together off the main thread: checking
    /// and placing a drawing of long texts takes milliseconds. `completion` runs once on the main
    /// thread with each key's drawing, or nil, and leaves out a key whose drawing was written or
    /// removed while it was read, since `onChange` said then what it is now.
    func load(_ keys: [ScreenshotKey], style: TextStyle, completion: @escaping @MainActor @Sendable ([ScreenshotKey: Drawing?]) -> Void) {
        let started = keys.map { revisions[$0, default: 0] }, store = store
        Self.loads.async {
            let read = keys.map { key in PixelSize(imageAt: key.url).flatMap { store.read(key: key.path, pixels: $0, style: style) } }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    guard let self else { return }
                    var current: [ScreenshotKey: Drawing?] = [:]
                    for (i, key) in keys.enumerated() where revisions[key, default: 0] == started[i] { current[key] = read[i] }
                    if !current.isEmpty { completion(current) }
                }
            }
        }
    }

    /// Writes a drawing, or removes its file when it has no marks. `reason` names the moment in the
    /// log line: saved after a change, parked, or built from an agent's marks. A drawing for a file
    /// that is gone is not written: the editor can hand one over after its file was trashed.
    @discardableResult
    func write(_ drawing: Drawing, reason: String) -> Bool {
        let key = ScreenshotKey(asGiven: drawing.key), name = key.name
        if !drawing.marks.isEmpty, !FileManager.default.fileExists(atPath: drawing.key) {
            Log.write("[drawing] dropped \(name): its screenshot is gone")
            return false
        }
        do { try store.write(drawing) } catch { return false }
        if drawing.marks.isEmpty {
            guard keys.remove(key) != nil else { return true }
            Log.write("[drawing] removed \(name)")
            Log.write("[drawings] \(keys.count)")
            changed(key, nil)
        } else {
            Log.write("[drawing] \(reason) \(name)")
            if keys.insert(key).inserted { Log.write("[drawings] \(keys.count)") }
            changed(key, drawing)
        }
        return true
    }

    /// The screenshots went: moved to the Trash by the app, or removed from the folder.
    func remove(_ removing: [ScreenshotKey], observedAt: TimeInterval = .infinity) {
        let had = removing.filter { keys.contains($0) && changedAt[$0, default: 0] <= observedAt }
        guard !had.isEmpty else { return }
        let removed = had.filter { (try? store.remove(key: $0.path)) != nil }
        for key in removed { keys.remove(key) }
        Log.write("[drawing] removed \(had.map(\.name).joined(separator: ", "))")
        Log.write("[drawings] \(keys.count)")
        for key in removed { changed(key, nil) }
    }

    /// The screenshot `old` was renamed to `new`. Its stored drawing is rewritten under the new key and
    /// the old file goes, and the drawing open in the editor for it is for `new` from here on, so the
    /// editor's next hand-over writes there. `onChange` says the old key has none and the new one has
    /// the drawing as it is now.
    func rename(from old: ScreenshotKey, to new: ScreenshotKey, style: TextStyle) {
        guard old != new else { return }
        var pixels: PixelSize?
        if keys.contains(old) {
            do { pixels = try store.rename(from: old.path, to: new.path) } catch { return }
        }
        let editing = open?.drawing(of: old)
        open?.rekey(old, to: new)
        guard pixels != nil || editing?.marks.isEmpty == false else { return }
        if pixels != nil {
            keys.remove(old)
            keys.insert(new)
            Log.write("[drawing] renamed \(old.name) to \(new.name)")
            Log.write("[drawings] \(keys.count)")
        }
        revisions[new] = revisions.removeValue(forKey: old)
        let drawing = open?.drawing(of: new) ?? pixels.flatMap { store.read(key: new.path, pixels: $0, style: style) }
        changed(old, nil)
        revisions[old] = nil
        changedAt[old] = nil
        changed(new, drawing)
    }

    /// Only a successful listing of the screenshot's own folder can authorize deletion.
    func sweep(_ inventory: ScreenshotWatcher.Inventory) {
        for key in keys.sorted() where changedAt[key, default: 0] <= inventory.observedAt
            && inventory.confirmsAbsence(of: key.url) {
            guard (try? store.remove(key: key.path)) != nil else { continue }
            keys.remove(key)
            Log.write("[drawing] swept \(key.name)")
            changed(key, nil)
        }
        Log.write("[drawings] \(keys.count) dir=\(store.directory.path)")
    }

    private func changed(_ key: ScreenshotKey, _ drawing: Drawing?) {
        revisions[key, default: 0] += 1
        changedAt[key] = ProcessInfo.processInfo.systemUptime
        onChange?(key, drawing)
    }

    // MARK: Agents' marks

    /// Why agents' marks did not become part of a drawing, with the code the command answers.
    struct Failure: Error, CustomStringConvertible {
        let code: CommandError
        let description: String
    }

    /// A reserved reply has one complete materialization. Recovery reuses it before publication,
    /// rather than joining the raw marks again under a different screen scale or text style.
    func installReply(_ agentMarks: [AgentMark], from agent: String?, at key: ScreenshotKey,
                      style: TextStyle, newScreen: DrawingScreen, rule: MarkScaleRule) throws {
        let url = key.url
        guard let pixels = PixelSize(imageAt: url) else {
            throw Failure(code: .unreadableImage, description: "\(url.lastPathComponent) is not an image this Mac can read")
        }
        do {
            if let stored = try store.readComplete(key: key.path, pixels: pixels, style: style) {
                guard stored.marks.count == agentMarks.count else {
                    throw DrawingStore.Refusal.incomplete("the checkpoint does not contain every reply mark")
                }
                keys.insert(key)
                changed(key, stored)
                return
            }
        } catch {
            throw Failure(code: .writeFailed, description: "\(url.lastPathComponent): \(error)")
        }
        var drawing = Drawing(key: url.path, pixels: pixels, sizedFor: newScreen, rule: rule)
        let made = marks(agentMarks, from: agent, in: pixels, pointScale: drawing.pointScale, style: style, rule: rule, name: url.lastPathComponent)
        guard made.count == agentMarks.count, !made.isEmpty else {
            throw Failure(code: .writeFailed, description: "the complete drawing for \(url.lastPathComponent) could not be constructed")
        }
        drawing.marks = made
        guard write(drawing, reason: "built") else {
            throw Failure(code: .writeFailed, description: "the drawing for \(url.lastPathComponent) could not be written")
        }
    }

    /// Adds an agent's marks to the drawing of the screenshot `key`, and answers how many joined.
    /// When the editor has that screenshot open, the marks join its drawing as one undo step.
    /// Otherwise they are added to the stored drawing, or a new one sized for `newScreen`. Either way the
    /// file is written before this returns, or it throws. `agent` names the agent they are from.
    func add(_ agentMarks: [AgentMark], from agent: String?, to key: ScreenshotKey, style: TextStyle, newScreen: DrawingScreen,
             rule: MarkScaleRule) throws -> Int {
        let url = key.url, name = key.name
        if let open, let before = open.drawing(of: key) {
            let made = marks(agentMarks, from: agent, in: before.pixels, pointScale: before.pointScale, style: style, rule: rule, name: name)
            guard let joined = open.join(made) else { return 0 }
            guard write(joined, reason: "saved") else {
                throw Failure(code: .writeFailed, description: "the drawing for \(name) could not be written")
            }
            return joined.marks.count - before.marks.count
        }
        guard let pixels = PixelSize(imageAt: url) else {
            throw Failure(code: .unreadableImage, description: "\(name) is not an image this Mac can read")
        }
        var drawing = read(key, pixels: pixels, style: style) ?? Drawing(key: key.path, pixels: pixels, sizedFor: newScreen, rule: rule)
        let made = marks(agentMarks, from: agent, in: pixels, pointScale: drawing.pointScale, style: style, rule: rule, name: name)
        guard !made.isEmpty else { return 0 }
        drawing.marks += made
        guard write(drawing, reason: "built") else {
            throw Failure(code: .writeFailed, description: "the drawing for \(name) could not be written")
        }
        return made.count
    }

    /// `AgentMark.marks`, with its one line for texts that do not fit, and one for colours named.
    private func marks(_ agentMarks: [AgentMark], from agent: String?, in pixels: PixelSize, pointScale: CGFloat, style: TextStyle,
                       rule: MarkScaleRule, name: String) -> [Mark] {
        if agentMarks.contains(where: { $0.color != nil }) {
            Log.write("[marks] color ignored for \(name): an agent's marks are drawn in the agent's colour")
        }
        let made = AgentMark.marks(agentMarks, from: agent, in: pixels, pointScale: pointScale, style: style,
                                   smallestText: rule.smallestNoteText)
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
