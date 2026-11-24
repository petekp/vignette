import AppKit

// MARK: The message kept with a screenshot

extension AnnotationController {
    /// Stores the editor's drawing with the words in the message field.
    func handOver(_ drawing: Drawing, reason: String) {
        stopMessageTimer()
        storedWords = toolbar.model.message
        onDrawing?(drawing, storedWords, editor.history, reason)
    }

    /// The message field changed: its words are stored once they rest, as the editor's drawing is.
    func messageChanged() {
        if current != nil, !restoringMessage {
            editor.message(.messageChanged(String(toolbar.model.message.prefix(AnnotatorToolbar.Model.messageLimit)), messageEdit ?? .typing))
            messageEdit = nil
        }
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
        restoringMessage = true
        toolbar.model.restore(message: words)
        restoringMessage = false
    }

    /// Cmd+V or Cmd+X in the field: the change it makes is a Paste or a Cut step. A paste that
    /// changes nothing leaves no step, so the name lasts only until the field has taken the key.
    func noteMessageEdit(_ name: StepName) {
        messageEdit = name
        DispatchQueue.main.async { [weak self] in self?.messageEdit = nil }
    }

    private func storeMessage() {
        guard let shot = current, let drawing = editor.drawing(of: shot.key) else { return }
        storedWords = toolbar.model.message
        onMessage?(storedWords, drawing, editor.history)
    }
}
