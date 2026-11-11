import AppKit

/// The recent stack's column reaching back past its first `recentCount`: older screenshots come in
/// above the oldest card a chunk at a time (`OlderShots`), and cards far from the view let their
/// pictures go (`CardPictures`).
extension ThumbnailController {
    /// How near the column's top the view comes, in viewports, before the next chunk is asked for.
    /// A chunk takes a few milliseconds to read, so a fling arrives to cards already there.
    private static let olderLead: CGFloat = 1.5

    /// Only the stack the shortcut opened loads older cards; the corner's own cards made into the
    /// stack by a selection are the person's latest captures and nothing more.
    private var isRecentStack: Bool { visible && keys.presentation.mode == .stack(recent: true) }

    /// The stack shows a new column: it holds the newest `recentCount` again, and a chunk still
    /// being read for the old one is dropped.
    func newColumn() {
        older.reset()
        pictures.reset()
    }

    /// The column moved, or older cards were asked for by a scroll toward them: the next chunk loads
    /// once the top is near, and the pictures follow the view.
    func columnMoved(towardOlder: Bool) {
        let above = drawnContentHeight - model.scroll - model.viewport
        if towardOlder, isRecentStack, above < model.viewport * Self.olderLead { loadOlder() }
        keepPictures()
    }

    /// Arrow up on the top card: the focus moves on once the next chunk is in. True when it waits.
    func waitsForOlder(toward delta: Int, extend: Bool) -> Bool {
        guard delta > 0, isRecentStack, !older.reachedOldest, let top = model.cards.last, model.focused == top.id else { return false }
        older.afterChunk { [weak self] in
            guard let self, self.model.focused == top.id, self.model.cards.last?.id != top.id else { return }
            self.moveFocus(toward: 1, extend: extend)
        }
        loadOlder()
        return true
    }

    private func loadOlder() {
        older.load(shown: Set(model.cards.map(\.shot.key)), limit: Settings.shared.data.recentCount) { [weak self] looked in
            self?.addOlder(looked)
        }
    }

    /// The chunk joins the top of the column. The layout changes with animations off, as `present`
    /// changes it, and the cards below keep their places: the scroll counts from the newest card,
    /// so a column growing at its top moves nothing in view. The new cards slide in from the
    /// screen's edge, staggered from the lowest, as cards entering above a column do.
    private func addOlder(_ looked: [(Screenshot, Thumbnailer.Lookup)]) {
        guard isRecentStack else { return }
        let have = Set(model.cards.map(\.shot.key))
        let cards = looked.filter { !have.contains($0.0.key) }.compactMap { makeCard($0.0, lookup: $0.1) }
        older.took(cards.count)
        Log.write("[stack] older cards=\(cards.count) column=\(model.cards.count + cards.count)\(older.reachedOldest ? " reached-oldest" : "")")
        guard !cards.isEmpty else { return }
        let ids = cards.map(\.id)
        layoutPanel(shrinkLater: false, animated: false) {
            model.cards.append(contentsOf: cards)
            model.offscreen.formUnion(ids)
            for (rank, id) in ids.enumerated() { model.entranceRanks[id] = rank }
        }
        DispatchQueue.main.async { [weak self] in self?.model.offscreen.subtract(ids) }
        keepPictures()
    }

    /// Lets the pictures of cards far from the view go and asks for the ones coming near
    /// (`CardPictures.plan`). A card in the annotator, in a stitch, pressed, dragged or hovered
    /// keeps its own.
    func keepPictures() {
        guard visible, model.cards.count > CardPictures.keptAlways else { return }
        let held: Set<UUID> = model.outCards.union(model.forming)
            .union([model.pressedCard, model.draggedCard, model.hoveredCard, model.focused].compactMap { $0 })
        let cards = model.cards
        let plan = CardPictures.plan(heights: cardSizes.map(\.height), spacing: layout.spacing,
                                     view: model.scroll...(model.scroll + model.viewport),
                                     holding: cards.map { $0.image != nil || pictures.arrived[$0.id] != nil },
                                     keeps: { held.contains(cards[$0].id) })
        for index in plan.want where !pictures.asked.contains(cards[index].id) { askPicture(of: cards[index]) }
        guard !plan.drop.isEmpty else { return }
        let dropped = Set(plan.drop.map { cards[$0].id })
        model.cards = model.cards.map { dropped.contains($0.id) ? $0.with(image: nil) : $0 }
    }

    /// The card's picture from the cache at once, or decoded on the thumbnail queue and given to the
    /// card with the others that arrive in the same turn.
    private func askPicture(of card: Card) {
        let url = card.shot.url
        let maxPixel = Thumbnailer.isDataless(url) ? cloudThumbnailPixels : thumbnailPixels(size: card.size, pointSize: card.pointSize)
        if let image = Thumbnailer.cached(at: url, maxPixel: maxPixel, space: screenSpace) { return arrive(image, for: card.id) }
        pictures.asked.insert(card.id)
        Thumbnailer.loadCard(at: url, maxPixel: maxPixel, space: screenSpace) { [weak self] image, _ in
            guard let self, self.pictures.asked.remove(card.id) != nil, let image else { return }
            self.arrive(image, for: card.id)
        }
    }

    private func arrive(_ image: NSImage, for id: UUID) {
        if pictures.arrived.isEmpty {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let arrived = self.pictures.arrived
                self.pictures.arrived = [:]
                self.model.cards = self.model.cards.map { card in arrived[card.id].map { card.with(image: $0) } ?? card }
            }
        }
        pictures.arrived[id] = image
    }
}
