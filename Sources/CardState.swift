import Foundation

/// What a card shows besides its picture, as the column reads it from the model. A card takes this
/// rather than observing the model, so its body runs again only when its own state changes: a scroll
/// step runs no card's body, and a hover runs the two cards it moves between.
struct CardState: Equatable {
    var hovered: Bool
    var pressed: Bool
    /// The card's drag image is out.
    var dragged: Bool
    /// The card's place in the selection, counting from 1, or nil when it is not selected.
    var selectionNumber: Int?
    var focused: Bool
    var isOut: Bool
    /// The card's image is in the transition layer, flying into or out of a stitch. The slot keeps
    /// its place in the column and draws nothing, so the image is never on screen twice.
    var isForming: Bool
    var offscreen: Bool
    var lift: CGFloat
    var notice: CardNotices.Notice?
    var entering: Bool
    var entranceRank: Int?
    // The same on every card.
    var offersSelection: Bool
    var inSelectionMode: Bool
    var slidingOut: Bool
    var cardCount: Int

    @MainActor init(of card: Card, in model: StackModel) {
        hovered = model.hoveredCard == card.id
        pressed = model.pressedCard == card.id
        dragged = model.draggedCard == card.id
        selectionNumber = model.selectionNumber(of: card.id)
        focused = model.focused == card.id
        isOut = model.outCards.contains(card.id)
        isForming = model.forming.contains(card.id)
        // A swipe carries the column off as one piece, so the card does not slide on its own.
        offscreen = model.offscreen.contains(card.id) && !model.swipeExit
        lift = model.lift[card.id] ?? 0
        notice = model.notices.notice(on: card.shot.key)
        entering = model.entering == card.id
        entranceRank = model.entranceRanks[card.id]
        offersSelection = model.offersSelection
        inSelectionMode = model.inSelectionMode
        slidingOut = model.slidingOut
        cardCount = model.cards.count
    }
}
