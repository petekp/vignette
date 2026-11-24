import AppKit

extension ThumbnailController {
    /// What a stack Undo or Redo does to the cards (`StackUndo.Cards`).
    func connectHistory() {
        history.cards = StackUndo.Cards(
            column: { [unowned self] in visible ? model.cards.map(\.shot.key) : [] },
            putBack: { [unowned self] shots, column in putBack(shots, in: column) },
            takeOut: { [unowned self] in remove($0) })
    }
}
