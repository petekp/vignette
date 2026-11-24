import AppKit

extension AppDelegate {
    /// Connects stored drawings before request recovery or the watcher can update cards.
    func startDrawings() {
        thumbnail.drawings = drawings
        drawings.open = annotator.editor
        drawings.onChange = { [weak self] key, drawing in self?.thumbnail.setDrawing(drawing, for: key) }
        annotator.onDrawing = { [weak self] drawing, message, history, reason in
            self?.drawings.handOver(drawing, message: message, history: history, reason: reason)
        }
        annotator.onMessage = { [weak self] message, drawing, history in self?.drawings.keepMessage(message, for: drawing, history: history) }
        annotator.storedHistory = { [weak self] key, pixels, drawing in
            self?.drawings.history(of: key, pixels: pixels, drawing: drawing) ?? EditorHistory()
        }
        annotator.storedMessage = { [weak self] key, pixels in self?.drawings.message(of: key, pixels: pixels) ?? "" }
        drawings.onWriteFailed = { [weak self] key in self?.thumbnail.showNotSaved(Screenshot(key: key)) }
    }
}
