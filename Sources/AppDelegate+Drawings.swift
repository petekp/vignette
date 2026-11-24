import AppKit

extension AppDelegate {
    /// Connects stored drawings before request recovery or the watcher can update cards.
    func startDrawings() {
        thumbnail.drawings = drawings
        drawings.open = annotator.editor
        drawings.onChange = { [weak self] key, drawing in self?.thumbnail.setDrawing(drawing, for: key) }
        annotator.onDrawing = { [weak self] drawing, message, reason in self?.drawings.handOver(drawing, message: message, reason: reason) }
        annotator.onMessage = { [weak self] message, drawing in self?.drawings.keepMessage(message, for: drawing) }
        annotator.storedMessage = { [weak self] key, pixels in self?.drawings.message(of: key, pixels: pixels) ?? "" }
        drawings.onWriteFailed = { [weak self] key in self?.thumbnail.showNotSaved(Screenshot(key: key)) }
    }
}
