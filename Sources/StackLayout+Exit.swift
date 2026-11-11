import CoreGraphics

extension StackLayout {
    /// How far right the whole column moves to clear the screen.
    var columnExitDistance: CGFloat { offscreenDistance(cardWidth: columnWidth) }

    /// How far right the selection strip moves to clear the screen: it starts a column's width
    /// further left, and its labels reach further still.
    var stripExitDistance: CGFloat {
        offscreenDistance(cardWidth: columnWidth + stripGap + stripWidth + stripReveal(rows: StackLayout.stripRows))
    }

    /// How far the column can move away from the screen's edge before the panel cuts off the
    /// widest card's shadow: the inset, less the shadow's blur, which spreads about twice its radius.
    var pullRoom: CGFloat { max(0, inset - ui.cardShadowRadius * 2) }
}
