import AppKit

/// The drawing open in the editor. Its marks are ahead of the stored file until the editor's next
/// hand-over, so it is the drawing as it is now.
@MainActor
protocol OpenDrawing: AnyObject {
    /// The drawing open for `key` as the editor would hand it over now, or nil when that screenshot
    /// is not open.
    func drawing(of key: ScreenshotKey) -> Drawing?
    /// Joins `marks`, already in the open drawing's px, and `pins` with comments by `author`, as one
    /// undo step (`AgentPin.join`). Answers the drawing to store in place of a hand-over, or nil when
    /// none of them joined.
    func join(_ marks: [Mark], pins: [AgentPin], by author: AgentAuthor) -> Drawing?
    /// Gives `sender` as the session's name to the open drawing's comments `session` wrote that have
    /// none, and to its history's (`EditorCore.name`). Answers the drawing to store, or nil when no
    /// comment changed.
    func name(_ sender: String, of session: AgentAddress) -> Drawing?
    /// The screenshot `old` was renamed to `new`: an open drawing for `old` is now for `new`.
    func rekey(_ old: ScreenshotKey, to new: ScreenshotKey)
    /// The undo and redo history open for `key`, or nil when that screenshot is not open.
    func history(of key: ScreenshotKey) -> EditorHistory?
}

/// The app's drawings: the store on disk, the screenshots that have one, and every change a drawing
/// takes outside the editor's own hand-over — agents' marks, a screenshot that goes, and the sweep at
/// launch. Every change to the set is one `[drawings] <n>` line, every write one `[drawing]` line.
@MainActor
final class Drawings {
    let store: DrawingStore
    /// The screenshots with a drawing on disk.
    private(set) var keys: Set<ScreenshotKey>
    /// The screenshots whose file holds a message: what was last typed in the editor's message field
    /// for them. A file can hold a message and no drawing.
    private(set) var messages: Set<ScreenshotKey>
    /// A screenshot's drawing changed on disk: written, with the drawing as it is now, or removed
    /// (nil). Every write and removal calls it, whether or not the set of keys changed.
    var onChange: ((_ key: ScreenshotKey, _ drawing: Drawing?) -> Void)?
    /// The editor's drawing could not be written, so its file still holds the drawing as last stored.
    /// Only `handOver` calls it; the other writers answer their own callers.
    var onWriteFailed: ((ScreenshotKey) -> Void)?
    /// What a card says when its drawing could not be written.
    static let notSaved = "Vignette couldn't save the drawing. The log has details."
    /// The editor's drawing, which `current` and `add` take over the stored one.
    weak var open: OpenDrawing?
    /// Counts the writes and removals of each key, so a `load` that began before one is dropped.
    private var revisions: [ScreenshotKey: Int] = [:]
    private var changedAt: [ScreenshotKey: TimeInterval] = [:]
    /// Where `load` reads, several at once, so the cards of a stack are read together.
    nonisolated static let loads = DispatchQueue(label: "vignette.drawing-loads", qos: .userInitiated, attributes: .concurrent)

    init(store: DrawingStore) {
        self.store = store
        let scan = store.scan()
        keys = Set(scan.drawings.map { ScreenshotKey(asGiven: $0) })
        messages = Set(scan.messages.map { ScreenshotKey(asGiven: $0) })
    }

    /// The message stored for the screenshot `key`, whose size as displayed is `pixels`, or "".
    /// Only a screenshot with a stored message has its file read.
    func message(of key: ScreenshotKey, pixels: PixelSize) -> String {
        messages.contains(key) ? store.readMessage(key: key.path, pixels: pixels) : ""
    }

    /// The undo and redo history stored for the screenshot `key`, whose size as displayed is `pixels`,
    /// for `drawing` as it was read from its file. Empty when it has no file.
    func history(of key: ScreenshotKey, pixels: PixelSize, drawing: Drawing) -> EditorHistory {
        guard keys.contains(key) || messages.contains(key) else { return EditorHistory() }
        return store.readHistory(key: key.path, pixels: pixels, marks: drawing.marks, pins: drawing.pins)
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

    /// Writes a drawing, or removes its file when it is empty. `reason` names the moment in the
    /// log line: saved after a change, parked, or built from an agent's marks. A drawing for a file
    /// that is gone is not written: the editor can hand one over after its file was trashed.
    @discardableResult
    func write(_ drawing: Drawing, message: String? = nil, history: EditorHistory = EditorHistory(), reason: String) -> Bool {
        (try? save(drawing, message: message, history: history, reason: reason)) ?? false
    }

    /// What a screenshot's file holds, as it is now.
    struct Saved {
        let drawing: Drawing
        let message: String
        let history: EditorHistory
    }

    /// The drawing, the message and the history of the screenshot `key` as they are now: the
    /// editor's drawing and history when it is open there, else the stored ones. A file with no marks
    /// and no pins, which holds only a message or a stitch's piece numbers, gives an empty drawing with
    /// its numbering. Nil when it has no file and is not open.
    func saved(of key: ScreenshotKey, style: TextStyle) -> Saved? {
        guard let drawing = current(of: key, style: style) ?? unmarked(of: key) else { return nil }
        let message = message(of: key, pixels: drawing.pixels)
        let history = open?.history(of: key) ?? history(of: key, pixels: drawing.pixels, drawing: drawing)
        return Saved(drawing: drawing, message: message, history: history)
    }

    /// The stored drawing of the screenshot `key` with its marks and pins left out. Only a screenshot
    /// with a file has it read.
    private func unmarked(of key: ScreenshotKey) -> Drawing? {
        guard keys.contains(key) || messages.contains(key), let pixels = PixelSize(imageAt: key.url) else { return nil }
        return store.readUnmarked(key: key.path, pixels: pixels)
    }

    /// Writes the editor's drawing with `message`, the words in its message field, and `history`, its
    /// undo and redo steps, and calls
    /// `onWriteFailed` when that fails after the editor let go of it. While the editor holds it, the
    /// next hand-over writes it again. An empty drawing with no message that a newer build's file
    /// refuses is not a failure: nothing of the person's is lost.
    func handOver(_ drawing: Drawing, message: String? = nil, history: EditorHistory = EditorHistory(), reason: String) {
        do { _ = try save(drawing, message: message, history: history, reason: reason) }
        catch DrawingStore.Refusal.newerVersion where drawing.isEmpty && (message ?? "").isEmpty {
        } catch {
            let key = ScreenshotKey(asGiven: drawing.key)
            if open?.drawing(of: key) == nil { onWriteFailed?(key) }
        }
    }

    /// Writes what was typed in the message field for the screenshot of `drawing`, the editor's open
    /// drawing, into its file with the editor's `history`. The stored marks stay as they are: the
    /// editor's next hand-over writes its own. Logs `[drawing] message saved`, or `message removed`
    /// when the field was emptied.
    func keepMessage(_ message: String, for drawing: Drawing, history: EditorHistory = EditorHistory()) {
        let key = ScreenshotKey(asGiven: drawing.key), name = key.name
        if !message.isEmpty, !FileManager.default.fileExists(atPath: drawing.key) {
            Log.write("[drawing] dropped \(name): its screenshot is gone")
            return
        }
        guard let keeps = try? store.writeMessage(message, for: drawing, history: history) else { return }
        changedAt[key] = ProcessInfo.processInfo.systemUptime
        let had = keeps ? !messages.insert(key).inserted : messages.remove(key) != nil
        if keeps { Log.write("[drawing] message saved \(name)") } else if had { Log.write("[drawing] message removed \(name)") }
    }

    private func save(_ drawing: Drawing, message: String? = nil, history: EditorHistory, reason: String) throws -> Bool {
        let key = ScreenshotKey(asGiven: drawing.key), name = key.name
        if drawing.isFiled || message?.isEmpty == false, !FileManager.default.fileExists(atPath: drawing.key) {
            Log.write("[drawing] dropped \(name): its screenshot is gone")
            return false
        }
        let keepsMessage = try store.write(drawing, message: message, history: history)
        if keepsMessage, messages.insert(key).inserted { Log.write("[drawing] message saved \(name)") }
        if !keepsMessage, messages.remove(key) != nil { Log.write("[drawing] message removed \(name)") }
        changedAt[key] = ProcessInfo.processInfo.systemUptime
        if !drawing.isFiled {
            guard keys.remove(key) != nil else { return true }
            Log.write("[drawing] removed \(name)")
            Log.write("[drawings] \(keys.count)")
            changed(key, nil)
        } else {
            Log.write("[drawing] \(reason) \(name)")
            if keys.insert(key).inserted { Log.write("[drawings] \(keys.count)") }
            changed(key, drawing.isEmpty ? nil : drawing)
        }
        return true
    }

    /// The screenshots went: moved to the Trash by the app, or removed from the folder.
    func remove(_ removing: [ScreenshotKey], observedAt: TimeInterval = .infinity) {
        let had = removing.filter { (keys.contains($0) || messages.contains($0)) && changedAt[$0, default: 0] <= observedAt }
        guard !had.isEmpty else { return }
        let removed = had.filter { (try? store.remove(key: $0.path)) != nil }
        for key in removed {
            keys.remove(key)
            messages.remove(key)
        }
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
        let hadDrawing = keys.contains(old), hadMessage = messages.contains(old)
        if hadDrawing || hadMessage {
            do { pixels = try store.rename(from: old.path, to: new.path) } catch { return }
        }
        let editing = open?.drawing(of: old)
        open?.rekey(old, to: new)
        if pixels != nil, hadMessage {
            messages.remove(old)
            messages.insert(new)
            changedAt[new] = ProcessInfo.processInfo.systemUptime
            if !hadDrawing { Log.write("[drawing] renamed \(old.name) to \(new.name)") }
        }
        let moved = pixels != nil && hadDrawing
        guard moved || editing?.isEmpty == false else { return }
        if moved {
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
        let gone = keys.union(messages).filter { changedAt[$0, default: 0] <= inventory.observedAt && inventory.confirmsAbsence(of: $0.url) }
        for key in gone.sorted() {
            guard (try? store.remove(key: key.path)) != nil else { continue }
            keys.remove(key)
            messages.remove(key)
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

    /// A reserved reply has one complete materialization. Recovery reuses it before publication,
    /// rather than joining the raw marks again under a different screen scale or text style.
    func installReply(_ agentMarks: [AgentMark], pins: [Pin] = [], from agent: String?, at key: ScreenshotKey,
                      style: TextStyle, newScreen: DrawingScreen, rule: MarkScaleRule) throws {
        let url = key.url
        guard let pixels = PixelSize(imageAt: url) else {
            throw Failure(code: .unreadableImage, description: "\(url.lastPathComponent) is not an image this Mac can read")
        }
        do {
            if let stored = try store.readComplete(key: key.path, pixels: pixels, style: style) {
                guard stored.marks.count == agentMarks.count, stored.pins.count == pins.count else {
                    throw DrawingStore.Refusal.incomplete("the checkpoint does not contain every reply mark and pin")
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
        guard made.count == agentMarks.count, !made.isEmpty || !pins.isEmpty else {
            throw Failure(code: .writeFailed, description: "the complete drawing for \(url.lastPathComponent) could not be constructed")
        }
        drawing.marks = made
        drawing.pins = pins
        drawing.nextPin = (pins.map(\.number).max() ?? 0) + 1
        guard write(drawing, reason: "built") else {
            throw Failure(code: .writeFailed, description: "the drawing for \(url.lastPathComponent) could not be written")
        }
    }
}
