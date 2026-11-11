import CoreGraphics

extension StackLayout {
    /// How far right the whole column moves to clear the screen.
    var columnExitDistance: CGFloat { offscreenDistance(cardWidth: columnWidth) }

    /// How far right the selection strip moves to clear the screen: it starts a column's width
    /// further left, and its labels reach further still.
    var stripExitDistance: CGFloat {
        offscreenDistance(cardWidth: columnWidth + stripGap + stripWidth + stripReveal(rows: StackLayout.stripRows))
    }
}
