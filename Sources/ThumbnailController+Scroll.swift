import SwiftUI

extension ThumbnailController {
    /// Scrolls the column, on a spring, just far enough that card `index` is in view.
    func scrollToReveal(_ index: Int) {
        let span = layout.cardSpan(index: index, cards: cardSizes)
        var target = model.scroll
        if span.top - model.scroll > model.viewport { target = span.top - model.viewport }
        if span.bottom - model.scroll < 0 { target = span.bottom }
        target = min(maxScroll, max(0, target))
        guard target != model.scroll else { return }
        withAnimation(Anim.spring(ui.relayoutDuration)) { model.scroll = target }
    }

    /// Takes cards out of the visible column. The cards above them slide down by their height,
    /// which can be more than the margin the column builds past the view, so every card whose slot
    /// passes through the view on the way stays built until the relayout is over (`StackModel.carried`).
    func removeCards(where leaves: (Card) -> Bool) {
        let sizes = cardSizes, reach = model.viewport * StackLayout.reach
        let builtTop = model.scroll + model.viewport + reach
        var bottom: CGFloat = 0, fall: CGFloat = 0
        for (card, size) in zip(model.cards, sizes) {
            if bottom < builtTop && leaves(card) { fall += size.height + layout.spacing }
            bottom += size.height + layout.spacing
        }
        let passing = layout.cards(meeting: (model.scroll - reach)...(builtTop + fall), sizes: sizes)
        let carried = Set(passing.map { model.cards[$0] }.filter { !leaves($0) }.map(\.id))
        model.carried = carried
        model.removeCards(where: leaves)
        // The cards above slide down with no scroll, which can bring cards without pictures into view.
        keepPictures()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2 * ui.relayoutDuration) { [weak self] in
            guard let self, self.model.carried == carried else { return }
            self.model.carried = []
        }
    }
}
