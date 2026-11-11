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
}
