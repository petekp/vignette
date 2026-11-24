import AppKit

extension ThumbnailController {
    /// What an Undo or a Redo does to the cards and the annotator (`StackUndo.Cards`).
    func connectHistory() {
        history.cards = StackUndo.Cards(
            column: { [unowned self] in visible ? model.cards.map(\.shot.key) : [] },
            putBack: { [unowned self] shots, column in putBack(shots, in: column) },
            takeOut: { [unowned self] in remove($0) },
            draw: { [unowned self] in draw($0) },
            isStack: { [unowned self] in keys.isStack })
    }

    /// The timeline hears what the run does to the editor, once the editor has done it: an image
    /// opening, one leaving it, and the run ending.
    func follow(_ effect: AnnotationRun.Effect, _ perform: () -> Void) {
        perform()
        switch effect {
        case .prepare(let opening): history.editorOpened(opening.key)
        case .park(let opening), .abandon(let opening): history.editorLeft(opening.key)
        case .endRun: history.editorEnded()
        default: break
        }
    }

    /// Opens `key` in the annotator as a click on its card does, or with nil closes the image there,
    /// leaving the keys with the stack. A queue still waiting keeps its files: going back puts the
    /// image in the editor at its front again, and going forward to a queued file leaves the ones after
    /// it. False when nothing started.
    private func draw(_ key: ScreenshotKey?) -> Bool {
        guard let key else {
            guard model.annotating, keys.isStack else { return false }
            send(.undo)
            return true
        }
        guard PixelSize(imageAt: key.url) != nil else { return false }
        var list = [key]
        if let at = run.queue.firstIndex(of: key) { list += run.queue[(at + 1)...] }
        else if !run.queue.isEmpty { list += (run.key.map { [$0] } ?? []) + run.queue }
        annotate(list.map(Screenshot.init(key:)))
        return model.annotating
    }
}
