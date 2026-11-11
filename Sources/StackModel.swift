import AppKit
import SwiftUI

extension Notification.Name {
    static let annotatingChanged = Notification.Name("\(Identity.bundleID).annotating.changed")
}

@MainActor
final class StackModel: ObservableObject {
    @Published var cards: [Card] = []          // index 0 is newest, drawn at the bottom
    @Published var offscreen: Set<UUID> = []   // cards parked past the right screen edge
    @Published var entering: UUID? = nil       // the one card joining a visible column, for the length of its entrance
    @Published var lift: [UUID: CGFloat] = [:] // how far below its slot a card shifting up starts, drawn times `liftFraction`
    /// The part of each card's `lift` still drawn: 1 when the lifts are set, springing to 0. Every
    /// card shares it, so a card the column builds in mid-spring is drawn where the spring is (`CardColumn`).
    @Published var liftFraction: CGFloat = 0
    /// Where each card entering a column that already shows cards falls in the slide-in's stagger,
    /// so the first to enter goes at once rather than after the cards that stayed (`StackEntrance`).
    @Published var entranceRanks: [UUID: Int] = [:]
    var slidingOut = false                     // picks the exit stagger order and curve for `offscreen`
    @Published var outCards: Set<UUID> = []    // cards currently in the annotator; their slots stay empty
    @Published var forming: Set<UUID> = []     // cards whose image is in the transition layer, mid-stitch; drawn as nothing
    @Published var hoveredCard: UUID? = nil {
        didSet {
            guard hoveredCard != oldValue else { return }
            onHover(hoveredCard)
            prepareDrag(of: hoveredCard)
        }
    }
    /// The wheel is moving the column: the cards passing under the pointer do not take the hover.
    /// `ThumbnailController` clears it once the column stops, and tests the pointer itself then.
    var holdsHover = false
    @Published var pressedCard: UUID? = nil { didSet { if pressedCard != oldValue, pressedCard != nil { prepareDrag(of: pressedCard) } } }
    /// The card whose drag image is out. It stays as the press left it until the drag ends, so the
    /// card and the drag image never change size against each other.
    @Published var draggedCard: UUID? = nil
    @Published var overControl = false         // the mouse is on a card's button or circle, where a click does not draw
    /// A card is in the annotator. The strip stands aside for it: the strip hangs to the left of
    /// the column, which is further left than the room the annotator's frame is kept out of, so
    /// the two would overlap. The selection is untouched and the strip comes back when the session
    /// ends. Set from `send`, which is the one place the session changes. Each change posts
    /// `.annotatingChanged`.
    @Published var annotating = false {
        didSet { if annotating != oldValue { NotificationCenter.default.post(name: .annotatingChanged, object: self) } }
    }
    @Published var notices = CardNotices()     // what each card says: copied, not copied, or where a send went
    /// The selected cards, in the order they were selected. Every action, Stitch included, takes
    /// them in this order, and a card's circle shows its place here.
    @Published private(set) var selection: [UUID] = []
    @Published var focused: UUID? = nil        // keyboard focus ring
    /// The recent stack, as against thumbnails in the corner. It stays through a slide-out, which
    /// the view draws as the column it was.
    @Published private(set) var isStack = false
    /// How far the column is pulled down to show older cards. Every change is reported to
    /// `scrolled`, true toward older cards, whatever moved it: a wheel, a key, a capture's spring
    /// back, a stitch, a drag-select's auto-scroll or the panel's clamp.
    @Published var scroll: CGFloat = 0 {
        didSet { if scroll != oldValue { scrolled(scroll > oldValue) } }
    }
    var scrolled: (_ towardOlder: Bool) -> Void = { _ in }
    /// The card a drag-select began on. Its selection circle carries the sweep's gesture, which
    /// ends if the card's view goes.
    var sweepCard: UUID?
    /// The cards a removal's relayout carries through the view, kept built while it runs
    /// (`ThumbnailController.removeCards(where:)`).
    var carried: Set<UUID> = []
    /// The cards the column builds wherever they are (`CardColumn`): one in the annotator or in a
    /// stitch, whose slot a flight lands in; one pressed, dragged out, hovered or carrying a
    /// drag-select, whose gesture or hover would end with its view; one showing a notice, whose
    /// overlay keeps its own state; the focused and entering card; and those a relayout carries.
    var keptBuilt: Set<UUID> {
        outCards.union(forming).union(carried).union([pressedCard, draggedCard, hoveredCard, focused, entering, sweepCard].compactMap { $0 })
            .union(cards.lazy.filter { self.notices.notice(on: $0.shot.key) != nil }.map(\.id))
    }
    /// Sets each card's lift, drawn whole until `liftFraction` springs.
    func setLifts(_ lifts: [UUID: CGFloat]) {
        lift = lifts
        liftFraction = lifts.isEmpty ? 0 : 1
    }
    /// How far a two-finger swipe moves the column toward the screen's edge (`StackSwipe`).
    @Published var swipe: CGFloat = 0
    /// The swipe carries the column off the screen, or back, as one piece; the cards' own slide-out is off.
    @Published var swipeExit = false
    @Published var viewport: CGFloat = 0       // visible height of the column, at the stack's full width
    /// The room the Dock keeps at the bottom of the panel when the column is over it. The column
    /// sits this far above the panel's bottom edge, and its mask ends there. See `StackArea`.
    @Published var safeBottom: CGFloat = 0
    /// How wide the stack is drawn, 1 at rest. It narrows while the annotator's frame comes near
    /// it; the column keeps its right edge, so the cards stay in their corner. See `StackLayout`.
    @Published var widthScale: CGFloat = 1

    /// No other card is in the column. The card itself may be out of it, as one in the annotator is.
    func isAlone(_ id: UUID) -> Bool { cards.allSatisfy { $0.id == id } }

    /// The card Left or Right in the editor opens from the screenshot `key`: the next older or newer
    /// one in the column that the editor can open. Nil at either end, or when `key` has no card here.
    func neighbor(of key: ScreenshotKey, _ page: EditorCore.Page) -> Card? {
        let images = cards.filter { $0.shot.kind == .image }
        guard let index = images.firstIndex(where: { $0.shot.key == key }) else { return nil }
        let next = page == .older ? index + 1 : index - 1
        return images.indices.contains(next) ? images[next] : nil
    }

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
    /// What the cards a drag out of the stack drop. Each card's file when there is none.
    var drags: DragItems?
    var onHover: (UUID?) -> Void = { _ in }
    /// The selection changed: the cards that joined it, in the order they were picked, and the
    /// cards that left it.
    var onSelectionChanged: (_ added: [UUID], _ removed: [UUID]) -> Void = { _, _ in }

    /// Takes cards out of the column for good and lets their marks go, with every text still being
    /// drawn for them. A lone thumbnail that leaves for the annotator comes back, and does not come here.
    /// The focused card is where keys act; when it leaves, the newest card takes the focus.
    func removeCards(where leaves: (Card) -> Bool) {
        for card in cards where leaves(card) { card.marks?.clear() }
        cards.removeAll(where: leaves)
        if let focused, !cards.contains(where: { $0.id == focused }) { self.focused = cards.first?.id }
    }

    /// Drops the oldest card when the column holds more than `limit`. True when it did. A card in
    /// the annotator or in a stitch is passed over: it is coming back to its slot.
    func removeOverflow(over limit: Int) -> Bool {
        let away = outCards.union(forming)
        guard cards.count > limit, let oldest = cards.last(where: { !away.contains($0.id) }) else { return false }
        removeCards { $0.id == oldest.id }
        deselect([oldest.id])
        return true
    }

    /// The cards a drag that starts on `id` carries: the whole selection, in the order it was
    /// selected, when `id` is in it.
    func dragCards(from id: UUID) -> [Card] {
        isSelected(id) ? selectedCards() : cards.filter { $0.id == id }
    }

    /// The items the drag of `cards` carries, asked for as the drag begins.
    func dragItems(_ cards: [Card]) -> [NSPasteboardWriting] {
        drags?.items(for: cards) ?? cards.map { $0.shot.url as NSURL }
    }

    /// The drag that started on `id` began or ended. The press becomes the drag, so the card keeps
    /// its size. The card may not have heard that the pointer left it during the drag, so at the end
    /// it loses the hover unless the pointer is on it.
    func drag(_ id: UUID, _ phase: DragSourceView.Phase) {
        switch phase {
        case .began:
            draggedCard = id
            if pressedCard == id { pressedCard = nil }
        case .ended(let pointerOnCard):
            if draggedCard == id { draggedCard = nil }
            if !pointerOnCard, !holdsHover, hoveredCard == id { hoveredCard = nil }
        }
    }

    private func prepareDrag(of id: UUID?) {
        drags?.prepare(id.map(dragCards(from:)) ?? [])
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
