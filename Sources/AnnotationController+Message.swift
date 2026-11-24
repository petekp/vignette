import AppKit

// MARK: The message kept with a screenshot

extension AnnotationController {
    /// Stores the editor's drawing with the words in the message field.
    func handOver(_ drawing: Drawing, reason: String) {
        stopMessageTimer()
        storedWords = toolbar.model.message
        onDrawing?(drawing, storedWords, reason)
    }

    /// The message field changed: its words are stored once they rest, as the editor's drawing is.
    func messageChanged() {
        stopMessageTimer()
        guard current != nil, toolbar.model.message != storedWords else { return }
        // Common modes, so the pause also runs out while the field tracks a drag.
        let timer = Timer(timeInterval: EditorCore.handOverDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.messageTimer = nil
                self?.storeMessage()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        messageTimer = timer
    }

    func stopMessageTimer() {
        messageTimer?.invalidate()
        messageTimer = nil
    }

    /// The image opens with the words it was last left with.
    func restoreMessage(_ words: String) {
        stopMessageTimer()
        storedWords = words
        toolbar.model.restore(message: words)
    }

    private func storeMessage() {
        guard let shot = current, let drawing = editor.drawing(of: shot.key) else { return }
        storedWords = toolbar.model.message
        onMessage?(storedWords, drawing)
    }
}
