import AppKit

/// Geometry shared by the SwiftUI cards, the transition layer, and the sweep gesture, so all agree
/// on where each card sits. Numbers come from `settings.ui` so the debug panel can change them live.
@MainActor
struct StackLayout {
    static var ui: UITweaks { Settings.shared.data.ui }
    static var maxCardWidth: CGFloat { ui.cardMaxWidth }
    static var maxCardHeight: CGFloat { ui.cardMaxHeight }
    static var minCardSide: CGFloat { ui.cardMinSide }
    static var spacing: CGFloat { ui.cardSpacing }
    static var inset: CGFloat { ui.panelInset }
    static var margin: CGFloat { ui.screenMargin }
    static var barHeight: CGFloat { ui.selectionBarHeight }

    static func cardSize(for image: NSSize) -> NSSize {
        guard image.width > 0, image.height > 0 else { return NSSize(width: maxCardWidth, height: maxCardHeight) }
        let scale = min(maxCardWidth / image.width, maxCardHeight / image.height)
        let w = max(image.width * scale, minCardSide)
        let h = max(image.height * scale, minCardSide)
        return NSSize(width: w.rounded(), height: h.rounded())
    }

    /// Height of the whole column: every card, plus the bar when shown.
    static func contentHeight(cards: [NSSize], showsBar: Bool) -> CGFloat {
        let cardsHeight = cards.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(cards.count - 1, 0))
        return cardsHeight + (showsBar ? barHeight + spacing : 0)
    }

    /// How much of the column fits on screen. The rest is reached by scrolling.
    static func viewportHeight(content: CGFloat, on screen: NSScreen) -> CGFloat {
        min(content, screen.visibleFrame.height - margin * 2)
    }

    static func panelSize(viewport: CGFloat) -> NSSize {
        NSSize(width: maxCardWidth + inset * 2, height: viewport + inset * 2)
    }

    /// Panel frame anchored to the bottom-right corner. Only the height varies.
    static func panelFrame(viewport: CGFloat, on screen: NSScreen) -> NSRect {
        let v = screen.visibleFrame
        let size = panelSize(viewport: viewport)
        return NSRect(x: v.maxX - size.width - margin + inset, y: v.minY + margin - inset, width: size.width, height: size.height)
    }

    /// Screen frame of card `index` (0 = newest, bottom). `scroll` is how far the column has been
    /// pulled down to reveal older cards.
    static func cardFrame(index: Int, cards: [NSSize], panelFrame: NSRect, showsBar: Bool, scroll: CGFloat) -> NSRect {
        var y = panelFrame.minY + inset + (showsBar ? barHeight + spacing : 0) - scroll
        for i in 0..<index { y += cards[i].height + spacing }
        let size = cards[index]
        return NSRect(x: panelFrame.maxX - inset - size.width, y: y, width: size.width, height: size.height)
    }

    /// Which card (0 = newest) sits at `y` measured from the top of the column. Nil between cards.
    static func cardIndex(atYFromTop y: CGFloat, cards: [NSSize]) -> Int? {
        var top: CGFloat = 0
        for (k, size) in cards.reversed().enumerated() {   // top of the column is the oldest card
            if y >= top && y < top + size.height { return cards.count - 1 - k }
            top += size.height + spacing
        }
        return nil
    }

    /// Distance from the column bottom to the bottom and top of card `index`.
    static func cardSpan(index: Int, cards: [NSSize], showsBar: Bool) -> (bottom: CGFloat, top: CGFloat) {
        var y: CGFloat = showsBar ? barHeight + spacing : 0
        for i in 0..<index { y += cards[i].height + spacing }
        return (y, y + cards[index].height)
    }

    /// How far a card has to travel to the right to leave the screen.
    static func offscreenDistance(cardWidth: CGFloat) -> CGFloat { cardWidth + inset + margin }

    /// Where the annotator goes: the image's exact aspect, centered in the screen area left of the
    /// stack, with room below for the toolbar. Small crops scale up until the toolbar fits.
    static func annotationFrame(for image: NSSize, on screen: NSScreen, avoidRight: CGFloat = 0, below: CGFloat = 0) -> NSRect {
        var v = screen.visibleFrame.insetBy(dx: ui.annotationScreenInset, dy: ui.annotationScreenInset)
        v.size.width -= avoidRight
        v.origin.y += below
        v.size.height -= below
        let w0 = max(image.width, 1), h0 = max(image.height, 1)
        let fit = min(v.width / w0, v.height / h0)
        let floor = max(1, ui.annotationMinWidth / w0, ui.annotationMinHeight / h0)
        let scale = min(fit, floor)
        let w = w0 * scale, h = h0 * scale
        return NSRect(x: v.midX - w / 2, y: v.midY - h / 2, width: w, height: h).integral
    }
}
