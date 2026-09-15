import AppKit

/// Geometry shared by the SwiftUI cards and the panel animation, so both agree on where each card sits.
/// All numbers come from `settings.ui` so the debug panel can change them live.
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
        // Fit inside the max box. Very thin crops keep a minimum side and letterbox instead of growing.
        let scale = min(maxCardWidth / image.width, maxCardHeight / image.height)
        let w = max(image.width * scale, minCardSide)
        let h = max(image.height * scale, minCardSide)
        return NSSize(width: w.rounded(), height: h.rounded())
    }

    /// Panel size for a column of cards. Newest card is index 0 and sits at the bottom.
    static func panelSize(cards: [NSSize], showsBar: Bool = false) -> NSSize {
        let height = cards.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(cards.count - 1, 0))
        let bar = showsBar ? barHeight + spacing : 0
        return NSSize(width: maxCardWidth + inset * 2, height: height + bar + inset * 2)
    }

    /// Frame of card `index` (0 = newest, bottom) in screen coordinates for a panel at `panelFrame`.
    static func cardFrame(index: Int, cards: [NSSize], panelFrame: NSRect, showsBar: Bool = false) -> NSRect {
        var y = panelFrame.minY + inset + (showsBar ? barHeight + spacing : 0)
        for i in 0..<index { y += cards[i].height + spacing }
        let size = cards[index]
        return NSRect(x: panelFrame.maxX - inset - size.width, y: y, width: size.width, height: size.height)
    }

    /// Which card (0 = newest) sits at a y measured from the top of the panel's content. Nil between cards.
    static func cardIndex(atYFromTop y: CGFloat, cards: [NSSize]) -> Int? {
        var top = inset
        for (k, size) in cards.reversed().enumerated() {   // top of the column is the oldest card
            if y >= top && y < top + size.height { return cards.count - 1 - k }
            top += size.height + spacing
        }
        return nil
    }

    static func restingFrame(size: NSSize, on screen: NSScreen) -> NSRect {
        let v = screen.visibleFrame
        return NSRect(x: v.maxX - size.width - margin + inset, y: v.minY + margin - inset, width: size.width, height: size.height)
    }

    static func offscreenFrame(size: NSSize, on screen: NSScreen) -> NSRect {
        var f = restingFrame(size: size, on: screen)
        f.origin.x = screen.frame.maxX + inset
        return f
    }

    /// Frame for the annotation window: exactly the image's aspect, so the image is flush with the
    /// window. Fits the screen minus `avoidRight` (the stack's column). Small crops are scaled up until
    /// the floating toolbar fits.
    static func annotationFrame(for image: NSSize, on screen: NSScreen, avoidRight: CGFloat = 0) -> NSRect {
        var v = screen.visibleFrame.insetBy(dx: ui.annotationScreenInset, dy: ui.annotationScreenInset)
        v.size.width -= avoidRight
        let w0 = max(image.width, 1), h0 = max(image.height, 1)
        let fit = min(v.width / w0, v.height / h0)
        let floor = max(1, ui.annotationMinWidth / w0, ui.annotationMinHeight / h0)
        let scale = min(fit, max(1, floor) == 1 ? min(fit, 1) : floor)
        let w = w0 * scale, h = h0 * scale
        return NSRect(x: v.midX - w / 2, y: v.midY - h / 2, width: w, height: h).integral
    }
}
