import AppKit

/// Cmd+Z in the stack: undoes what Vignette last did to a screenshot, and Shift+Cmd+Z redoes it, as
/// Finder's Undo does. Two actions make a step. Delete's files come back from the Trash with their
/// drawings, and their cards come back where they were. Stitch's file goes to the Trash, and the
/// cards it took out of the column come back. The steps last while the app runs, through the stack
/// closing and opening again. A step whose file has moved since is used up with a beep and a log
/// line, as Finder uses one up with an alert.
///
/// The steps are an `UndoManager`'s, the stack panel's own (`ThumbnailPanel.undoManager`), so the
/// Edit menu's items name the step while the stack has the keys.
@MainActor
final class StackUndo: NSObject {
    /// What a step does to the watch folder: `FolderWrites` in the app.
    struct Files {
        var trash: ([Screenshot]) -> [FolderWrites.Trashed] = { _ in [] }
        var putBack: ([FolderWrites.Trashed]) -> (back: [Screenshot], failed: [String]) = { _ in ([], []) }
        var exists: (Screenshot) -> Bool = { FileManager.default.fileExists(atPath: $0.url.path) }
        /// A screenshot's drawing as it is now, which the Trash does not keep.
        var drawing: (Screenshot) -> Drawing? = { _ in nil }
        /// Writes a drawing back for a screenshot put back in the folder.
        var restore: (Drawing) -> Void = { _ in }
    }

    /// What a step does to the open stack: `ThumbnailController` in the app.
    struct Cards {
        /// The files the open stack shows, newest first, or none when it is closed.
        var column: () -> [ScreenshotKey] = { [] }
        /// Puts the cards of files back in the open stack, each where it was in `column`.
        var putBack: ([Screenshot], _ column: [ScreenshotKey]) -> Void = { _, _ in }
        /// Takes the cards of files out of the open stack, leaving the files where they are.
        var takeOut: ([Screenshot]) -> Void = { _ in }
    }

    /// A step's name in the Edit menu, in Finder's words where Finder has the action.
    enum Name: String {
        case moveToTrash = "Move to Trash"
        case stitch = "Stitch"
    }

    let manager = UndoManager()
    var files = Files()
    var cards = Cards()
    private let beep: () -> Void
    /// Tells VoiceOver what an Undo or a Redo just did, in the Edit menu's words.
    var announce: (String) -> Void = { _ in }
    /// The step that just ran could not, so there is nothing to announce.
    private var refused = false
    /// The name each file had when a step recorded it, to its name now, for the files Finder or
    /// another app renamed in the folder since.
    private var renamed: [ScreenshotKey: ScreenshotKey] = [:]

    init(beep: @escaping () -> Void = { NSSound.beep() }) {
        self.beep = beep
        super.init()
        manager.groupsByEvent = false
    }

    // MARK: Steps

    /// Delete: the files go to the Trash, and undoing it puts them back.
    func trash(_ shots: [Screenshot]) {
        let column = cards.column()
        let trashed = moveToTrash(shots)
        guard !trashed.isEmpty else {
            if manager.isRedoing { refuse(.moveToTrash, "none of \(names(shots)) is in the folder") }
            return
        }
        if manager.isRedoing { Log.write("[undo] redid \(Name.moveToTrash.rawValue): \(names(trashed.map(\.file.shot)))") }
        record(.moveToTrash, PutBack(trashed: trashed, column: column))
    }

    /// A stitch was written. `takenOut` are the pieces whose cards it took out of the column, and
    /// `column` the stack as it was before.
    func stitched(_ stitch: Screenshot, takenOut: [Screenshot], column: [ScreenshotKey]) {
        record(.stitch, Unstitch(stitch: stitch, pieces: takenOut, column: column))
    }

    /// Files renamed in the folder: the steps that name them follow.
    func rename(_ pairs: [(from: ScreenshotKey, to: ScreenshotKey)]) {
        guard manager.canUndo || manager.canRedo else {
            renamed = [:]
            return
        }
        for (old, new) in pairs where old != new {
            for (recorded, now) in renamed where now == old { renamed[recorded] = new }
            if renamed[old] == nil { renamed[old] = new }
        }
    }

    // MARK: Keys and menu

    /// Cmd+Z. With nothing to undo, it beeps, as a disabled menu item's shortcut does.
    func undo() {
        guard manager.canUndo else { return beep() }
        let words = manager.undoMenuItemTitle
        refused = false
        manager.undo()
        if !refused { announce(words) }
    }

    /// Shift+Cmd+Z.
    func redo() {
        guard manager.canRedo else { return beep() }
        let words = manager.redoMenuItemTitle
        refused = false
        manager.redo()
        if !refused { announce(words) }
    }

    /// The Edit menu's title for `undo:` or `redo:`, naming the step that would run.
    func menuTitle(for action: Selector?) -> String? {
        switch action {
        case Self.undoAction: return manager.canUndo ? manager.undoMenuItemTitle : "Undo"
        case Self.redoAction: return manager.canRedo ? manager.redoMenuItemTitle : "Redo"
        default: return nil
        }
    }

    func canRun(_ action: Selector?) -> Bool {
        action == Self.undoAction ? manager.canUndo : action == Self.redoAction ? manager.canRedo : false
    }

    static let undoAction = #selector(ThumbnailPanel.undo(_:))
    static let redoAction = #selector(ThumbnailPanel.redo(_:))

    /// Where a card for `key` goes among the cards `now`, newest first, given the column it was in:
    /// before the first older card still there, else after the first newer one.
    static func place(of key: ScreenshotKey, in column: [ScreenshotKey], among now: [ScreenshotKey]) -> Int {
        guard let was = column.firstIndex(of: key) else { return 0 }
        if let older = column[(was + 1)...].first(where: now.contains), let index = now.firstIndex(of: older) { return index }
        if let newer = column[..<was].reversed().first(where: now.contains), let index = now.firstIndex(of: newer) { return index + 1 }
        return min(was, now.count)
    }

    // MARK: Running a step

    /// What a step will do when it runs. Its values are a class so the undo manager can hold one
    /// without a closure.
    private class Step: NSObject {}

    /// A file a step moved to the Trash, with its drawing as it was then.
    private struct Gone {
        let file: FolderWrites.Trashed
        let drawing: Drawing?
    }

    private final class PutBack: Step {
        let trashed: [Gone], column: [ScreenshotKey]
        init(trashed: [Gone], column: [ScreenshotKey]) { (self.trashed, self.column) = (trashed, column) }
    }

    private final class TrashAgain: Step {
        let shots: [Screenshot]
        init(shots: [Screenshot]) { self.shots = shots }
    }

    private final class Unstitch: Step {
        let stitch: Screenshot, pieces: [Screenshot], column: [ScreenshotKey]
        init(stitch: Screenshot, pieces: [Screenshot], column: [ScreenshotKey]) { (self.stitch, self.pieces, self.column) = (stitch, pieces, column) }
    }

    private final class Restitch: Step {
        let trashed: Gone, pieces: [Screenshot], column: [ScreenshotKey]
        init(trashed: Gone, pieces: [Screenshot], column: [ScreenshotKey]) {
            (self.trashed, self.pieces, self.column) = (trashed, pieces, column)
        }
    }

    /// One step, named. Outside an undo or a redo it is a new step of its own; inside one it is what
    /// undoes that, which the manager files as the redo, or as the undo after a redo.
    private func record(_ name: Name, _ step: Step) {
        let opens = !manager.isUndoing && !manager.isRedoing
        if opens { manager.beginUndoGrouping() }
        manager.registerUndo(withTarget: self, selector: #selector(run(_:)), object: step)
        manager.setActionName(name.rawValue)
        if opens { manager.endUndoGrouping() }
    }

    @objc private func run(_ step: Step) {
        switch step {
        case let step as PutBack: putBack(step)
        case let step as TrashAgain: trash(step.shots.map(current))
        case let step as Unstitch: unstitch(step)
        case let step as Restitch: restitch(step)
        default: break
        }
    }

    private func putBack(_ step: PutBack) {
        let (back, failed) = moveBack(step.trashed)
        guard !back.isEmpty else { return refuse(.moveToTrash, failed.joined(separator: "; ")) }
        log(.moveToTrash, "put back \(names(back))", failed)
        cards.putBack(back, step.column.map(current))
        record(.moveToTrash, TrashAgain(shots: back))
    }

    /// The pieces' cards come back first, so the column never empties and closes between the two.
    private func unstitch(_ step: Unstitch) {
        let column = cards.column()
        let stitch = current(step.stitch)
        let pieces = step.pieces.map(current).filter(files.exists)
        if !pieces.isEmpty { cards.putBack(pieces, step.column.map(current)) }
        let trashed = files.exists(stitch) ? moveToTrash([stitch]) : []
        guard let inTrash = trashed.first else {
            guard !pieces.isEmpty else { return refuse(.stitch, "\(stitch.url.lastPathComponent) is not in the folder") }
            log(.stitch, "put back the cards of \(names(pieces))", ["\(stitch.url.lastPathComponent) is not in the folder"])
            return
        }
        log(.stitch, "moved \(stitch.url.lastPathComponent) to the Trash" + (pieces.isEmpty ? "" : ", put back the cards of \(names(pieces))"), [])
        record(.stitch, Restitch(trashed: inTrash, pieces: pieces, column: column))
    }

    private func restitch(_ step: Restitch) {
        let column = cards.column()
        let (back, failed) = moveBack([step.trashed])
        guard let stitch = back.first else { return refuse(.stitch, failed.joined(separator: "; ")) }
        cards.putBack(back, step.column.map(current))
        let shown = Set(cards.column())
        let pieces = step.pieces.map(current).filter { shown.contains($0.key) }
        if !pieces.isEmpty { cards.takeOut(pieces) }
        log(.stitch, "put back \(stitch.url.lastPathComponent)", [])
        record(.stitch, Unstitch(stitch: stitch, pieces: pieces, column: column))
    }

    /// Each drawing is read before its file goes, since the drawing is forgotten once the file has left.
    private func moveToTrash(_ shots: [Screenshot]) -> [Gone] {
        var drawings: [ScreenshotKey: Drawing] = [:]
        for shot in shots { drawings[shot.key] = files.drawing(shot) }
        return files.trash(shots).map { Gone(file: $0, drawing: drawings[$0.shot.key]) }
    }

    private func moveBack(_ gone: [Gone]) -> (back: [Screenshot], failed: [String]) {
        let result = files.putBack(gone.map(\.file))
        let back = Set(result.back.map(\.key))
        for item in gone where back.contains(item.file.shot.key) {
            if let drawing = item.drawing { files.restore(drawing) }
        }
        return result
    }

    private func current(_ shot: Screenshot) -> Screenshot { renamed[shot.key].map(Screenshot.init(key:)) ?? shot }
    private func current(_ key: ScreenshotKey) -> ScreenshotKey { renamed[key] ?? key }

    private var verb: String { manager.isRedoing ? "redid" : "undid" }

    private func log(_ name: Name, _ what: String, _ failed: [String]) {
        Log.write("[undo] \(verb) \(name.rawValue): \(what)" + (failed.isEmpty ? "" : "; can't \(failed.joined(separator: "; "))"))
    }

    /// A step that can no longer run is used up: the next Cmd+Z goes to the one before it.
    private func refuse(_ name: Name, _ why: String) {
        Log.write("[undo] can't \(manager.isRedoing ? "redo" : "undo") \(name.rawValue): \(why)")
        refused = true
        beep()
    }

    private func names(_ shots: [Screenshot]) -> String { shots.map(\.url.lastPathComponent).joined(separator: ", ") }
}
