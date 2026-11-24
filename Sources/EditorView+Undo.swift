import AppKit

/// Cmd+Z and Shift+Cmd+Z, the toolbar's Undo and Redo and the Edit menu's. A text being typed and a
/// gesture under way take their own step. Otherwise the timeline decides whether the editor's step
/// is next or one of its own, such as closing the image this opening began with.
extension EditorView {
    @objc func undo(_ sender: Any?) { walk(redo: false) }
    @objc func redo(_ sender: Any?) { walk(redo: true) }

    /// `repeated`: the key is held down, which walks only the editor's own steps.
    func walk(redo: Bool, repeated: Bool = false) {
        guard typingField == nil, core.gesture == nil, let timeline else { return step(redo: redo) }
        timeline.walk(redo: redo, repeated: repeated)
    }

    /// How many steps the drawing's history holds to undo and to redo, also once it is parked.
    var steps: (undo: Int, redo: Int) { (core.undoSteps.count, core.redoSteps.count) }

    /// A drawing is open, not parked.
    var isOpen: Bool { core.isOpen }
}
