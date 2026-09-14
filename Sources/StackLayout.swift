import AppKit

/// Geometry shared by the SwiftUI cards and the panel animation, so both agree on where each card sits.
struct StackLayout {
    static let maxCardWidth: CGFloat = 220
    static let maxCardHeight: CGFloat = 150
    static let minCardSide: CGFloat = 56
    static let spacing: CGFloat = 10
    static let inset: CGFloat = 24      // room for the shadow inside the panel
    static let margin: CGFloat = 16     // distance from the screen corner

    static func cardSize(for image: NSSize) -> NSSize {
        guard image.width > 0, image.height > 0 else { return NSSize(width: maxCardWidth, height: maxCardHeight) }
        // Fit inside the max box. Very thin crops keep a minimum side and letterbox instead of growing.
        let scale = min(maxCardWidth / image.width, maxCardHeight / image.height)
        let w = max(image.width * scale, minCardSide)
        let h = max(image.height * scale, minCardSide)
        return NSSize(width: w.rounded(), height: h.rounded())
    }

    /// Panel size for a column of cards. Newest card is index 0 and sits at the bottom.
    static func panelSize(cards: [NSSize]) -> NSSize {
        let height = cards.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(cards.count - 1, 0))
        return NSSize(width: maxCardWidth + inset * 2, height: height + inset * 2)
    }

    /// Frame of card `index` (0 = newest, bottom) in screen coordinates for a panel at `panelFrame`.
    static func cardFrame(index: Int, cards: [NSSize], panelFrame: NSRect) -> NSRect {
        var y = panelFrame.minY + inset
        for i in 0..<index { y += cards[i].height + spacing }
        let size = cards[index]
        return NSRect(x: panelFrame.maxX - inset - size.width, y: y, width: size.width, height: size.height)
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

    /// Centered frame for the annotation window: the image at 1x points, shrunk to fit the screen.
    static func annotationFrame(for image: NSSize, on screen: NSScreen) -> NSRect {
        let v = screen.visibleFrame.insetBy(dx: 60, dy: 60)
        let scale = min(1, v.width / max(image.width, 1), v.height / max(image.height, 1))
        let w = max(image.width * scale, 320)
        let h = max(image.height * scale, 200)
        return NSRect(x: v.midX - w / 2, y: v.midY - h / 2, width: w, height: h).integral
    }
}
