import AppKit

/// The drag from a card's selection circle, which selects every card it passes, and the
/// auto-scroll that carries it past either end of the column. An NSObject because the auto-scroll
/// takes its ticks from a display link, which calls a target and a selector.
@MainActor
final class StackSweep: NSObject {
    /// The column as it is drawn now: its layout at the stack's width, each card's drawn size, the
    /// column's height, and how far it can scroll.
    struct Column {
        let layout: StackLayout
        let cards: [NSSize]
        let contentHeight: CGFloat
        let maxScroll: CGFloat
    }

    /// The card the drag started on. A card is named by id, since the column's indexes shift as
    /// cards come and go.
    private var anchor: UUID?
    private var selecting = true
    private var before: [UUID] = []
    /// How far the drag point sits below the top of the visible column, kept while a sweep runs so
    /// the auto-scroll can re-select from it without a mouse event. Nil when no sweep is running.
    private var fromTop: CGFloat?
    private var autoScrollLink: CADisplayLink?
    private var autoScrollTick: CFTimeInterval = 0

    private let model: StackModel
    private let screen: () -> NSScreen
    private let column: () -> Column
    private let isVisible: () -> Bool
    /// The drag selected in the corner, which turns the corner into the stack.
    private let selected: () -> Void
    private let relayout: () -> Void

    init(model: StackModel, screen: @escaping () -> NSScreen, column: @escaping () -> Column,
         isVisible: @escaping () -> Bool, selected: @escaping () -> Void, relayout: @escaping () -> Void) {
        self.model = model
        self.screen = screen
        self.column = column
        self.isVisible = isVisible
        self.selected = selected
        self.relayout = relayout
    }

    /// The drag is over: it ended, or the column changed under it. The selection stays as it is.
    func end() {
        anchor = nil
        fromTop = nil
        stopAutoScroll()
    }

    /// The drag moved. Its place in the column is kept as a distance from the top of what is on
    /// screen, so the auto-scroll can keep selecting from the same point while the cards move under it.
    func move(toYFromTop y: CGFloat) {
        // A selection begun in the corner turns the corner into the stack, with the cards it holds.
        selected()
        fromTop = y - column().contentHeight + model.viewport + model.scroll
        select(toYFromTop: y)
        updateAutoScroll()
    }

    /// Dragging from a circle selects (or deselects) every card between the start and the cursor,
    /// in the order the drag reached them. Backing up restores cards the drag passed over.
    private func select(toYFromTop y: CGFloat) {
        let column = self.column()
        guard let index = column.layout.cardIndex(atYFromTop: y, cards: column.cards) else { return }
        // A card that left the column ends the sweep it started, and the drag starts a new one here.
        let anchored = anchor.flatMap { anchor in model.cards.firstIndex { $0.id == anchor } }
        if anchored == nil {
            anchor = model.cards[index].id
            selecting = !model.isSelected(model.cards[index].id)
            before = model.selection
        }
        let start = anchored ?? index
        let passed = stride(from: start, through: index, by: index < start ? -1 : 1).map { model.cards[$0].id }
        let next = selecting ? before + passed : before.filter { !passed.contains($0) }
        // The auto-scroll runs this every frame; a relayout that changes nothing would still move
        // the panel and animate the strip.
        guard next != model.selection || model.focused != model.cards[index].id else { return }
        model.setSelection(next)
        model.focused = model.cards[index].id
        relayout()
    }

    /// While the drag sits in a band at either end of the column, the column scrolls on its own and
    /// the cards passing under the drag keep joining the selection. This is the user's own drag, so
    /// the motion scale leaves it alone; it stops at the ends of the column and when the drag leaves
    /// the band or ends.
    private func updateAutoScroll() {
        let speed = fromTop.map { column().layout.autoScrollSpeed(fromTop: $0, viewport: model.viewport) } ?? 0
        guard speed != 0, isVisible(), model.isStack else { stopAutoScroll(); return }
        guard autoScrollLink == nil else { return }
        autoScrollTick = CACurrentMediaTime()
        let link = screen().displayLink(target: self, selector: #selector(autoScrollStep))
        link.add(to: .main, forMode: .common)
        autoScrollLink = link
    }

    private func stopAutoScroll() {
        autoScrollLink?.invalidate()
        autoScrollLink = nil
    }

    @objc private func autoScrollStep(_ link: CADisplayLink) {
        guard let fromTop, isVisible(), model.isStack else { stopAutoScroll(); return }
        let column = self.column()
        let speed = column.layout.autoScrollSpeed(fromTop: fromTop, viewport: model.viewport)
        guard speed != 0 else { stopAutoScroll(); return }
        let now = CACurrentMediaTime()
        // A stalled run loop would otherwise scroll the whole column in one step.
        let dt = min(0.1, now - autoScrollTick)
        autoScrollTick = now
        let next = min(column.maxScroll, max(0, model.scroll + speed * dt))
        guard next != model.scroll else { return }
        model.scroll = next
        select(toYFromTop: fromTop + column.contentHeight - model.viewport - model.scroll)
    }
}
