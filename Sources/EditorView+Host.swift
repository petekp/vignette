import AppKit

/// What the host reads from the editor: the drawing and the history open, and the Edit menu's words.
extension EditorView {
    /// The undo and redo steps of the drawing open now, or last parked.
    var history: EditorHistory { core.history }

    /// The Edit menu's Undo and Redo say the step they take: the typing session's own while a text is
    /// typed, the timeline's otherwise (`UndoTimeline`).
    func undoTitle(redo: Bool) -> (title: String, enabled: Bool) {
        if typingField == nil, let timeline { return timeline.title(redo: redo) }
        return stepTitle(redo: redo)
    }

    /// The editor's own next step, in the Edit menu's words.
    func stepTitle(redo: Bool) -> (title: String, enabled: Bool) {
        if let field = typingField {
            return redo ? (field.undo.redoMenuItemTitle, field.undo.canRedo) : (field.undo.undoMenuItemTitle, field.undo.canUndo)
        }
        return redo ? (core.redoTitle, core.isOpen && core.canRedo) : (core.undoTitle, core.isOpen && core.canUndo)
    }
}

extension EditorView: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let undo = item.action == #selector(undo(_:)), redo = item.action == #selector(redo(_:))
        guard undo || redo else { return true }
        let (title, enabled) = undoTitle(redo: redo)
        item.title = title
        return enabled
    }
}

extension EditorView {
    func drawing(of key: ScreenshotKey) -> Drawing? {
        guard core.isOpen, core.drawing.key == key.path else { return nil }
        return core.drawingForHost
    }

    func history(of key: ScreenshotKey) -> EditorHistory? {
        guard core.isOpen, core.drawing.key == key.path else { return nil }
        return core.history
    }
}
