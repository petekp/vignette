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

    /// The scroll changed, by any path. Checked on the next turn, since the scroll often changes
    /// in the middle of a change to the cards.
    func scrolled(towardOlder: Bool) {
        DispatchQueue.main.async { [weak self] in self?.columnMoved(towardOlder: towardOlder) }
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
        older.load(top: model.cards.last?.shot.key, shown: Set(model.cards.map(\.shot.key)),
                   limit: Settings.shared.data.recentCount) { [weak self] looked in
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
        let cards = looked.filter { !have.contains($0.0.key) }.compactMap { makeCard($0.0, lookup: $0.1, caches: false) }
        older.took(cards.count)
        Log.write("[stack] older cards=\(cards.count) column=\(model.cards.count + cards.count)\(older.reachedOldest ? " reached-oldest" : "")")
        guard !cards.isEmpty else { return }
        let ids = cards.map(\.id)
        layoutPanel(shrinkLater: false, animated: false) {
            model.cards.append(contentsOf: cards)
            model.offscreen.formUnion(ids)
            for (rank, id) in ids.enumerated() { model.entranceRanks[id] = rank }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.visible else { return }
            self.model.offscreen.subtract(ids)
        }
        keepPictures()
    }

    /// Whether the picture of the card at `index` is decoded into `Thumbnailer`'s cache: only for the
    /// newest `recentCount`, so the cards of older chunks never push their pictures out.
    func cachesPicture(at index: Int) -> Bool { index < Settings.shared.data.recentCount }

    /// Lets the pictures of cards far from the view go and asks for the ones coming near
    /// (`CardPictures.plan`). A card in the annotator, in a stitch, selected, pressed, dragged,
    /// hovered or focused keeps its own, since a flight out of the column carries the card's picture.
    /// So do the newest `recentCount`, which a capture or a stitch springs the column back to. A
    /// column that removals made too short to let pictures go still takes back the ones it let go.
    func keepPictures() {
        let recentCount = Settings.shared.data.recentCount
        if !pictures.dropped.isEmpty { pictures.dropped.formIntersection(model.cards.map(\.id)) }
        let letsPicturesGo = model.cards.count > max(CardPictures.keptAlways, recentCount)
        guard visible, letsPicturesGo || !pictures.dropped.isEmpty else { return }
        let held: Set<UUID> = model.outCards.union(model.forming).union(model.selection)
            .union([model.pressedCard, model.draggedCard, model.hoveredCard, model.focused].compactMap { $0 })
        let cards = model.cards
        let plan = CardPictures.plan(heights: cardSizes.map(\.height), spacing: layout.spacing,
                                     view: model.scroll...(model.scroll + model.viewport),
                                     holding: cards.map { $0.image != nil || pictures.arrived[$0.id] != nil },
                                     keepsAll: recentCount, keeps: { $0 < recentCount || held.contains(cards[$0].id) })
        for index in plan.want where !pictures.asked.contains(cards[index].id) { askPicture(of: cards[index]) }
        guard !plan.drop.isEmpty else { return }
        let dropped = Set(plan.drop.map { cards[$0].id })
        pictures.dropped.formUnion(dropped)
        model.cards = model.cards.map { dropped.contains($0.id) ? $0.with(image: nil) : $0 }
    }

    /// The card's picture from the cache, or decoded on the thumbnail queue, given to the card with
    /// the others that arrive within `CardPictures.arrivalWindow`. A picture that does not decode is
    /// not asked for again in this column.
    private func askPicture(of card: Card) {
        let url = card.shot.url
        let maxPixel = Thumbnailer.isDataless(url) ? cloudThumbnailPixels : thumbnailPixels(size: card.size, pointSize: card.pointSize)
        if let image = Thumbnailer.cached(at: url, maxPixel: maxPixel, space: screenSpace) { return arrive(image, for: card.id) }
        pictures.asked.insert(card.id)
        Thumbnailer.loadCard(at: url, maxPixel: maxPixel, space: screenSpace, caches: false) { [weak self] image, _ in
            guard let self, self.pictures.asked.contains(card.id) else { return }
            guard let image else { self.pictures.dropped.remove(card.id); return }
            self.pictures.asked.remove(card.id)
            self.arrive(image, for: card.id)
        }
    }

    private func arrive(_ image: NSImage, for id: UUID) {
        if pictures.arrived.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + CardPictures.arrivalWindow) { [weak self] in
                guard let self else { return }
                let arrived = self.pictures.arrived
                self.pictures.arrived = [:]
                self.pictures.dropped.subtract(arrived.keys)
                self.model.cards = self.model.cards.map { card in arrived[card.id].map { card.with(image: $0) } ?? card }
            }
        }
        pictures.arrived[id] = image
    }
}
