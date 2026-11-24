import AppKit

extension AppDelegate {
    /// The stack's Undo and Redo move files through `folderWrites`, and keep each file's drawing
    /// while it is in the Trash.
    func connectStackUndo() {
        thumbnail.history.files = StackUndo.Files(
            trash: { [unowned self] in folderWrites.trash($0) },
            putBack: { [unowned self] in folderWrites.putBack($0) },
            drawing: { [unowned self] in drawings.current(of: $0.key, style: settings.data.ui.textStyle) },
            restore: { [unowned self] in drawings.write($0, reason: "put back") })
    }

    func moveToTrash(_ shots: [Screenshot]) {
        thumbnail.history.trash(shots)
    }

    /// The cards of `shots` conjoin into the stitch `key`'s card when the stack shows them, and the
    /// stack's Undo can take the stitch back. True when they conjoined.
    func conjoin(_ shots: [Screenshot], into key: ScreenshotKey) -> Bool {
        let column = thumbnail.history.cards.column()
        let conjoined = thumbnail.stitched(shots, into: key)
        thumbnail.history.stitched(Screenshot(key: key), takenOut: conjoined ? shots : [], column: column)
        return conjoined
    }
}
