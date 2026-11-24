import AppKit

/// What the undo timeline acts on, which the app connects, and the words it names its steps with.
extension StackUndo {
    /// A step's name in the Edit menu, in Finder's words where Finder has the action.
    enum Name: String {
        case moveToTrash = "Move to Trash"
        case stitch = "Stitch"
        case openDrawing = "Open Drawing"
        case closeDrawing = "Close Drawing"
    }

    /// Where a card for `key` goes among the cards `now`, newest first, given the column it was in:
    /// before the first older card still there, else after the first newer one.
    static func place(of key: ScreenshotKey, in column: [ScreenshotKey], among now: [ScreenshotKey]) -> Int {
        guard let was = column.firstIndex(of: key) else { return 0 }
        if let older = column[(was + 1)...].first(where: now.contains), let index = now.firstIndex(of: older) { return index }
        if let newer = column[..<was].reversed().first(where: now.contains), let index = now.firstIndex(of: newer) { return index + 1 }
        return min(was, now.count)
    }

    /// What a step does to the watch folder: `FolderWrites` in the app.
    struct Files {
        var trash: ([Screenshot]) -> [FolderWrites.Trashed] = { _ in [] }
        var putBack: ([FolderWrites.Trashed]) -> (back: [Screenshot], failed: [String]) = { _ in ([], []) }
        var exists: (Screenshot) -> Bool = { FileManager.default.fileExists(atPath: $0.url.path) }
        /// Which file is at a screenshot's path, so a step can tell it from a file that took the name.
        var identity: (Screenshot) -> FileIdentity? = FileIdentity.init(of:)
        /// A screenshot's drawing, message and history as they are now, which the Trash does not keep.
        var saved: (Screenshot) -> Drawings.Saved? = { _ in nil }
        /// Writes them back for a screenshot put back in the folder.
        var restore: (Drawings.Saved) -> Void = { _ in }
    }

    /// What a step does to the open stack: `ThumbnailController` in the app.
    struct Cards {
        /// The files the open stack shows, newest first, or none when it is closed.
        var column: () -> [ScreenshotKey] = { [] }
        /// Puts the cards of files back in the open stack, each where it was in `column`.
        var putBack: ([Screenshot], _ column: [ScreenshotKey]) -> Void = { _, _ in }
        /// Takes the cards of files out of the open stack, leaving the files where they are.
        var takeOut: ([Screenshot]) -> Void = { _ in }
        /// Opens a screenshot in the annotator, on the flights a click on its card starts, or with nil
        /// closes the one there. False when nothing could start.
        var draw: (ScreenshotKey?) -> Bool = { _ in false }
        /// The corner is the stack, which keeps the keys once the annotator closes.
        var isStack: () -> Bool = { true }
    }

    /// The editor in the annotator: `AnnotationController` in the app.
    struct Editor {
        /// The screenshot open in the editor, nil when none is.
        var open: () -> EditorPlace? = { nil }
        /// How many steps the editor's history holds to undo, also once it has parked its screenshot.
        var depth: () -> Int = { 0 }
        /// The editor's own Undo, or with `true` its Redo.
        var step: (_ redo: Bool) -> Void = { _ in }
        /// The editor's own words for Undo or Redo: "Undo Arrow".
        var title: (_ redo: Bool) -> String = { $0 ? "Redo" : "Undo" }
    }

    /// A screenshot in the editor at one point in the timeline: how many of its history's steps
    /// there were to undo then, and which file it was.
    struct Shown: Equatable {
        var key: ScreenshotKey
        var depth: Int
        var file: FileIdentity?
    }

    /// A screenshot open in the editor, and how many steps its history holds to undo and to redo.
    struct EditorPlace: Equatable {
        var key: ScreenshotKey
        var undo: Int
        var redo: Int
    }
}

/// The Edit menu's items for the timeline, which `validateMenuItem` names.
extension StackUndo {
    /// The Edit menu's title for `undo:` or `redo:`, naming the step that would run.
    func menuTitle(for action: Selector?) -> String? {
        Self.redo(action).map { title(redo: $0).title }
    }

    func canRun(_ action: Selector?) -> Bool {
        Self.redo(action).map { title(redo: $0).enabled } ?? false
    }

    static let undoAction = #selector(ThumbnailPanel.undo(_:))
    static let redoAction = #selector(ThumbnailPanel.redo(_:))

    private static func redo(_ action: Selector?) -> Bool? {
        action == undoAction ? false : action == redoAction ? true : nil
    }
}

/// The file at a path, by its size and when it last changed, so a step can tell the file it recorded
/// from another that took its name since. A sync client can replace a file with the same one under a
/// new file number, so the number is not part of it.
struct FileIdentity: Equatable {
    let size: Int
    let modified: Date

    init(size: Int, modified: Date) {
        (self.size, self.modified) = (size, modified)
    }

    init?(of shot: Screenshot) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: shot.url.path),
              let size = (attributes[.size] as? NSNumber)?.intValue,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        self.init(size: size, modified: modified)
    }
}
