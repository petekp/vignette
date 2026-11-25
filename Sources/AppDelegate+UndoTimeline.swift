import AppKit

extension AppDelegate {
    /// The undo timeline moves files through `folderWrites`, keeps each file's drawing while it is in
    /// the Trash, and walks the editor's own steps in the annotator.
    func connectUndo() {
        thumbnail.timeline.files = UndoTimeline.Files(
            trash: { [unowned self] in folderWrites.trash($0) },
            putBack: { [unowned self] in folderWrites.putBack($0) },
            saved: { [unowned self] in drawings.saved(of: $0.key, style: settings.data.ui.textStyle) },
            restore: { [unowned self] in drawings.write($0.drawing, message: $0.message, history: $0.history, reason: "put back") })
        thumbnail.timeline.editor = UndoTimeline.Editor(
            open: { [unowned self] in
                guard let key = annotator.opening?.key, annotator.editor.isOpen else { return nil }
                let steps = annotator.editor.steps
                return UndoTimeline.EditorPlace(key: key, undo: steps.undo, redo: steps.redo)
            },
            depth: { [unowned self] in annotator.editor.steps.undo },
            step: { [unowned self] in annotator.editor.step(redo: $0) },
            title: { [unowned self] in annotator.editor.stepTitle(redo: $0).title })
        annotator.editor.timeline = thumbnail.timeline
    }

    func moveToTrash(_ shots: [Screenshot]) {
        thumbnail.timeline.trash(shots)
    }

    /// The cards of `shots` conjoin into the stitch `key`'s card when the stack shows them, and the
    /// stack's Undo can take the stitch back. True when they conjoined. The card says Copied once
    /// `copied`, the stitch's first copy, is done.
    func conjoin(_ shots: [Screenshot], into key: ScreenshotKey, copied: PendingRendering? = nil) -> Bool {
        let column = thumbnail.timeline.cards.column()
        let conjoined = thumbnail.stitched(shots, into: key, copied: copied)
        thumbnail.timeline.stitched(Screenshot(key: key), takenOut: conjoined ? shots : [], column: column)
        return conjoined
    }
}
