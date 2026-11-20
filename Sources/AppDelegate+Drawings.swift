import AppKit

extension AppDelegate {
    /// Connects stored drawings before request recovery or the watcher can update cards.
    func startDrawings() {
        thumbnail.drawings = drawings
        drawings.open = annotator.editor
        drawings.onChange = { [weak self] key, drawing in self?.thumbnail.setDrawing(drawing, for: key) }
        annotator.onDrawing = { [weak self] drawing, reason in self?.drawings.handOver(drawing, reason: reason) }
        drawings.onWriteFailed = { [weak self] key in self?.thumbnail.showNotSaved(Screenshot(key: key)) }
    }
}
