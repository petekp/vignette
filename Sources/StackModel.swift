import AppKit
import SwiftUI

@MainActor
final class StackModel: ObservableObject {
    @Published var cards: [Card] = []          // index 0 is newest, drawn at the bottom
    @Published var offscreen: Set<UUID> = []   // cards parked past the right screen edge
    @Published var entering: UUID? = nil       // the one card joining a visible column, for the length of its entrance
    @Published var lift: [UUID: CGFloat] = [:] // how far below its slot a card shifting up is drawn, springing to 0
    /// Where each card entering a column that already shows cards falls in the slide-in's stagger,
    /// so the first to enter goes at once rather than after the cards that stayed (`StackEntrance`).
    @Published var entranceRanks: [UUID: Int] = [:]
    var slidingOut = false                     // picks the exit stagger order and curve for `offscreen`
    @Published var outCards: Set<UUID> = []    // cards currently in the annotator; their slots stay empty
    @Published var forming: Set<UUID> = []     // cards whose image is in the transition layer, mid-stitch; drawn as nothing
    @Published var hoveredCard: UUID? = nil { didSet { if hoveredCard != oldValue { onHover(hoveredCard) } } }
    /// The wheel is moving the column: the cards passing under the pointer do not take the hover.
    /// `ThumbnailController` clears it once the column stops, and tests the pointer itself then.
    var holdsHover = false
    @Published var pressedCard: UUID? = nil
    @Published var overControl = false         // the mouse is on a card's button or circle, where a click does not draw
    /// A card is in the annotator. The strip stands aside for it: the strip hangs to the left of
    /// the column, which is further left than the room the annotator's frame is kept out of, so
    /// the two would overlap. The selection is untouched and the strip comes back when the session
    /// ends. Set from `send`, which is the one place the session changes.
    @Published var annotating = false
    @Published var notices = CardNotices()     // what each card says: copied, not copied, or where a send went
    /// The selected cards, in the order they were selected. Every action, Stitch included, takes
    /// them in this order, and a card's circle shows its place here.
    @Published private(set) var selection: [UUID] = []
    @Published var focused: UUID? = nil        // keyboard focus ring
    /// The recent stack, as against thumbnails in the corner. It stays through a slide-out, which
    /// the view draws as the column it was.
    @Published private(set) var isStack = false
    @Published var scroll: CGFloat = 0         // how far the column is pulled down to show older cards
    @Published var viewport: CGFloat = 0       // visible height of the column, at the stack's full width
    /// The room the Dock keeps at the bottom of the panel when the column is over it. The column
    /// sits this far above the panel's bottom edge, and its mask ends there. See `StackArea`.
    @Published var safeBottom: CGFloat = 0
    /// How wide the stack is drawn, 1 at rest. It narrows while the annotator's frame comes near
    /// it; the column keeps its right edge, so the cards stay in their corner. See `StackLayout`.
    @Published var widthScale: CGFloat = 1

    /// No other card is in the column. The card itself may be out of it, as one in the annotator is.
    func isAlone(_ id: UUID) -> Bool { cards.allSatisfy { $0.id == id } }

    func follow(_ presentation: CornerPresentation) {
        if presentation.mode != .hidden, isStack != presentation.isStack { isStack = presentation.isStack }
    }

    var inSelectionMode: Bool { !selection.isEmpty }
    /// Cards show the selection circle. A corner holding two or more cards offers it too, and
    /// selecting there makes the corner the stack (`CornerPresentation`'s `.selected`). Not while
    /// a corner card is in the annotator, when the corner cannot become the stack.
    var offersSelection: Bool { isStack || (cards.count > 1 && !annotating) }
    var onAction: (ShotAction, [Card]) -> Void = { _, _ in }
    var onSweep: (CGFloat) -> Void = { _ in }       // y from the column top, during a drag from a circle
    var onSweepEnd: () -> Void = {}
    var onClickImage: (Card) -> Void = { _ in }
    /// What the cards a drag out of the stack carries drop, one item per card, asked for as the drag
    /// begins. Each card's file unless the owner says otherwise.
    var dragItems: ([Card]) -> [NSPasteboardWriting] = { cards in cards.map { $0.shot.url as NSURL } }
    var onHover: (UUID?) -> Void = { _ in }
    /// The selection changed: the cards that joined it, in the order they were picked, and the
    /// cards that left it.
    var onSelectionChanged: (_ added: [UUID], _ removed: [UUID]) -> Void = { _, _ in }

    /// Takes cards out of the column for good and lets their marks go, with every text still being
    /// drawn for them. A lone thumbnail that leaves for the annotator comes back, and does not come here.
    func removeCards(where leaves: (Card) -> Bool) {
        for card in cards where leaves(card) { card.marks?.clear() }
        cards.removeAll(where: leaves)
    }

    /// Cards for a bulk action, in the order they were selected.
    func selectedCards() -> [Card] { selection.compactMap { id in cards.first { $0.id == id } } }
    /// Where the selected cards sit in the column; 0 is the newest, at the bottom.
    func selectedIndices() -> [Int] { cards.indices.filter { isSelected(cards[$0].id) } }

    /// A selected card's place in `selectedCards()`, counting from 1: the first card selected is 1,
    /// which is the order every action receives them and the badge `Stitch` draws on each one.
    func selectionNumber(of id: UUID) -> Int? { selection.firstIndex(of: id).map { $0 + 1 } }

    func isSelected(_ id: UUID) -> Bool { selection.contains(id) }
    /// Puts the cards that are not selected yet at the end of the selection, in the order given.
    func select(_ ids: [UUID]) { setSelection(selection + ids) }
    func deselect(_ ids: [UUID]) { setSelection(selection.filter { !ids.contains($0) }) }
    /// A card selected again goes to the end: its number is where it was picked this time.
    func toggleSelection(of id: UUID) { isSelected(id) ? deselect([id]) : select([id]) }
    func clearSelection() { setSelection([]) }
    /// Replaces the selection, keeping the given order. A card named twice keeps its first place.
    func setSelection(_ ids: [UUID]) {
        var seen = Set<UUID>()
        let was = selection
        selection = ids.filter { seen.insert($0).inserted }
        let added = selection.filter { !was.contains($0) }, removed = was.filter { !selection.contains($0) }
        if !added.isEmpty || !removed.isEmpty { onSelectionChanged(added, removed) }
    }
}
