import AppKit

/// A button label that comes out on hover. Measured here with AppKit, in the font the view draws it
/// in, so the room a button makes for its label is the room the label needs.
enum ButtonLabel {
    private static func font(size: CGFloat) -> NSFont { .systemFont(ofSize: size, weight: .semibold) }

    /// Rounded up, with a point of slack: a width a hair under what the text needs would clip its
    /// last column of pixels.
    static func width(_ text: String, size: CGFloat) -> CGFloat {
        ((text as NSString).size(withAttributes: [.font: font(size: size)]).width + 1).rounded(.up)
    }
}

/// Geometry shared by the SwiftUI cards, the transition layer, and the sweep gesture, so all agree
/// on where each card sits. A value over one `UITweaks`, so the math is testable without settings;
/// `StackLayout.current` reads the live tweaks for the debug panel's sliders.
struct StackLayout {
    let ui: UITweaks
    /// How wide the stack is drawn, 1 at rest: the recent stack narrows to make room for the
    /// annotator's frame (see `widthScale(clearing:visibleFrame:)`). Only the cards and the column
    /// change with it. The card box, the spacing, the insets and the panel stay as they are, so a
    /// card casts the same shadow at any width and the panel never has to be resized for it.
    var widthScale: CGFloat = 1

    @MainActor static var current: StackLayout { StackLayout(ui: Settings.shared.data.ui) }

    /// The card box at rest. `Card.size` is measured against this, whatever the stack's width.
    var maxCardWidth: CGFloat { ui.cardMaxWidth }
    var maxCardHeight: CGFloat { ui.cardMaxHeight }
    var minCardSide: CGFloat { ui.cardMinSide }
    var spacing: CGFloat { ui.cardSpacing }
    /// The padding between the column and the edge of the panel. At least `ui.panelInset`, and
    /// always the card's shadow plus a short fade: the column's bottom fade starts below the newest
    /// card's shadow, so a shadow bigger than the inset has to move the column up rather than be
    /// cut off. The cards do not move with it — the panel grows around them (see `panelFrame`).
    var inset: CGFloat { max(ui.panelInset, cardShadowRoom + Self.shadowFade) }
    /// How far a card's shadow reaches below its bottom edge: the offset plus the blur's spread,
    /// which is about twice the radius.
    var cardShadowRoom: CGFloat { max(0, ui.cardShadowY + ui.cardShadowRadius * 2) }
    /// The soft edge the column keeps below a card's shadow, where it fades into the panel.
    static let shadowFade: CGFloat = 7
    var margin: CGFloat { ui.screenMargin }
    /// The column's width on screen: the card box at the stack's current width.
    var columnWidth: CGFloat { maxCardWidth * widthScale }
    /// How narrow the stack goes, and the width it reserves for itself at that narrowest.
    var minWidthScale: CGFloat { min(1, max(0.05, ui.stackMinScale)) }
    /// The row under the column that carries the feedback toast.
    var barHeight: CGFloat { ui.selectionBarHeight }
    /// One column of button-sized rows, padded by the button spacing.
    var stripWidth: CGFloat { ui.buttonSize + ui.buttonSpacing * 2 }
    var stripGap: CGFloat { ui.selectionStripGap }
    /// The size the strip's labels are drawn at. In code, like the size of the icons beside them.
    static let stripLabelSize: CGFloat = 12

    func stripHeight(rows: Int) -> CGFloat {
        CGFloat(rows) * ui.buttonSize + CGFloat(max(0, rows - 1)) * ui.buttonSpacing + ui.buttonSpacing * 2
    }

    /// How far the strip grows to the left when the cursor is on it and the labels come out: the
    /// widest label, plus the room the icons have on their own side. The strip's right edge stays
    /// where it is, so a label never reaches a card. The panel reserves this room whenever the
    /// strip shows (`panelSize`), so the labels always have somewhere to go.
    func stripReveal(labels: [String]) -> CGFloat {
        guard let widest = labels.map({ ButtonLabel.width($0, size: Self.stripLabelSize) }).max(), widest > 0 else { return 0 }
        return widest + ui.buttonSpacing * 2
    }

    func cardSize(for image: NSSize) -> NSSize {
        guard image.width > 0, image.height > 0 else { return NSSize(width: maxCardWidth, height: maxCardHeight) }
        let scale = min(maxCardWidth / image.width, maxCardHeight / image.height)
        let w = max(image.width * scale, minCardSide)
        let h = max(image.height * scale, minCardSide)
        return NSSize(width: w.rounded(), height: h.rounded())
    }

    /// A card on screen at the stack's current width. `Card.size` is the size at rest, so a stack
    /// that narrows and comes back does not re-measure a card or re-decode its thumbnail.
    func drawn(_ size: NSSize) -> NSSize {
        guard widthScale != 1 else { return size }
        return NSSize(width: (size.width * widthScale).rounded(), height: (size.height * widthScale).rounded())
    }

    /// Height of the whole column: every card, plus the bar when shown.
    func contentHeight(cards: [NSSize], showsBar: Bool) -> CGFloat {
        let cardsHeight = cards.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(cards.count - 1, 0))
        return cardsHeight + (showsBar ? barHeight + spacing : 0)
    }

    /// How much of the column fits on screen. The rest is reached by scrolling.
    func viewportHeight(content: CGFloat, visibleFrame: NSRect) -> CGFloat {
        min(content, visibleFrame.height - margin * 2)
    }

    /// The panel makes room for the selection strip on its left while cards are selected: the icon
    /// column, the gap to the cards, and `reveal`, the room the labels grow into. That room is
    /// there whether the labels are out or not, so the reveal never resizes the panel's window.
    /// The panel's right edge never moves, so the cards stay where they are. Always the stack's
    /// width at rest: the panel is transparent outside the column, so a stack that has narrowed for
    /// the annotator simply draws in part of it and no window is resized while it moves.
    func panelSize(viewport: CGFloat, showsStrip: Bool, reveal: CGFloat = 0) -> NSSize {
        let strip = showsStrip ? stripWidth + stripGap + reveal : 0
        return NSSize(width: maxCardWidth + strip + inset * 2, height: viewport + inset * 2)
    }

    /// Panel frame anchored to the bottom-right corner of the screen's visible area.
    func panelFrame(viewport: CGFloat, visibleFrame v: NSRect, showsStrip: Bool, reveal: CGFloat = 0) -> NSRect {
        let size = panelSize(viewport: viewport, showsStrip: showsStrip, reveal: reveal)
        return NSRect(x: v.maxX - size.width - margin + inset, y: v.minY + margin - inset, width: size.width, height: size.height)
    }

    /// Screen frame of card `index` (0 = newest, bottom). `scroll` is how far the column has been
    /// pulled down to reveal older cards.
    func cardFrame(index: Int, cards: [NSSize], panelFrame: NSRect, showsBar: Bool, scroll: CGFloat) -> NSRect {
        var y = panelFrame.minY + inset + (showsBar ? barHeight + spacing : 0) - scroll
        for i in 0..<index { y += cards[i].height + spacing }
        let size = cards[index]
        return NSRect(x: panelFrame.maxX - inset - size.width, y: y, width: size.width, height: size.height)
    }

    /// How fast a drag-select scrolls the column, in points a second, from how far the drag point
    /// sits below the top of the visible column. Zero away from the ends, ramping to the top speed
    /// at each end and capped past it. Positive brings older cards down into view, negative newer
    /// ones. The two bands meet in the middle rather than overlapping on a short column.
    func autoScrollSpeed(fromTop y: CGFloat, viewport: CGFloat) -> CGFloat {
        let zone = min(ui.autoScrollZone, viewport / 2)
        guard zone > 0 else { return 0 }
        let depth: CGFloat
        if y < zone { depth = (zone - y) / zone }
        else if y > viewport - zone { depth = (viewport - zone - y) / zone }
        else { return 0 }
        return ui.autoScrollSpeed * max(-1, min(1, depth))
    }

    /// Which card (0 = newest) sits at `y` measured from the top of the column. Nil between cards.
    func cardIndex(atYFromTop y: CGFloat, cards: [NSSize]) -> Int? {
        var top: CGFloat = 0
        for (k, size) in cards.reversed().enumerated() {   // top of the column is the oldest card
            if y >= top && y < top + size.height { return cards.count - 1 - k }
            top += size.height + spacing
        }
        return nil
    }

    /// Distance from the column bottom to the bottom and top of card `index`.
    func cardSpan(index: Int, cards: [NSSize], showsBar: Bool) -> (bottom: CGFloat, top: CGFloat) {
        var y: CGFloat = showsBar ? barHeight + spacing : 0
        for i in 0..<index { y += cards[i].height + spacing }
        return (y, y + cards[index].height)
    }

    /// Where the selection strip sits. Distances are measured from the column's bottom-right
    /// corner and leave out the scroll, like `cardSpan`.
    struct StripPlacement: Equatable {
        var size: NSSize
        /// Column's right edge to the strip's right edge: the widest selected card, plus the gap.
        var right: CGFloat
        /// Column's bottom to the strip's bottom.
        var bottom: CGFloat
    }

    /// The strip beside the selection: centered on the span from the topmost to the bottommost
    /// selected card, and kept inside the part of the column that is on screen. Nil without a selection.
    func stripPlacement(rows: Int, selection: [Int], cards: [NSSize], showsBar: Bool, scroll: CGFloat, viewport: CGFloat) -> StripPlacement? {
        let picked = selection.filter { cards.indices.contains($0) }
        guard let lowest = picked.min(), let highest = picked.max() else { return nil }
        let size = NSSize(width: stripWidth, height: stripHeight(rows: rows))
        let span = (bottom: cardSpan(index: lowest, cards: cards, showsBar: showsBar).bottom,
                    top: cardSpan(index: highest, cards: cards, showsBar: showsBar).top)
        let center = (span.bottom + span.top) / 2
        let lowestBottom = scroll, highestBottom = scroll + viewport - size.height
        // A strip taller than the visible column has nowhere to sit inside it, so it centers on it.
        let bottom = highestBottom < lowestBottom
            ? scroll + (viewport - size.height) / 2
            : min(max(center - size.height / 2, lowestBottom), highestBottom)
        return StripPlacement(size: size, right: picked.map { cards[$0].width }.max()! + stripGap, bottom: bottom)
    }

    /// The strip's screen frame, for the state report. The view places it from the same numbers.
    /// `reveal` is how far the labels are out: the right edge stays where it is and the strip
    /// grows to the left, into the room the panel keeps for it, so the labels never cover a card.
    func stripFrame(_ strip: StripPlacement, panelFrame: NSRect, scroll: CGFloat, reveal: CGFloat = 0) -> NSRect {
        NSRect(x: panelFrame.maxX - inset - strip.right - strip.size.width - reveal,
               y: panelFrame.minY + inset + strip.bottom - scroll,
               width: strip.size.width + reveal, height: strip.size.height)
    }

    /// How far a card has to travel to the right to leave the screen.
    func offscreenDistance(cardWidth: CGFloat) -> CGFloat { cardWidth + inset + margin }

    /// The strip of the screen the stack keeps for itself at its narrowest, and the gap beside it.
    /// The annotator's frame never enters it, so the stack always has somewhere to be.
    var reservedWidth: CGFloat { margin + maxCardWidth * minWidthScale + ui.stackGap }

    /// The rect the annotator's frame fits and grows within while the recent stack is showing:
    /// the visible frame, less the stack's reserved strip on the right.
    func annotatorRoom(visibleFrame v: NSRect) -> NSRect {
        NSRect(x: v.minX, y: v.minY, width: max(1, v.width - reservedWidth), height: v.height)
    }

    /// How wide the stack may be drawn with the annotator's frame where it is: the largest width
    /// at which the column's left edge still clears the frame's right edge by the gap. 1 when the
    /// frame is far enough away, and never below the minimum, which is the width the room the
    /// frame grows within was reserved for.
    func widthScale(clearing frame: NSRect, visibleFrame v: NSRect) -> CGFloat {
        let free = v.maxX - margin - ui.stackGap - frame.maxX
        return min(1, max(minWidthScale, free / max(maxCardWidth, 1)))
    }

    /// Where the annotator goes: the image's exact aspect, centered in the rect it is given, with
    /// room below for the toolbar. Small crops scale up until the toolbar fits.
    func annotationFrame(for image: NSSize, visibleFrame: NSRect, below: CGFloat = 0) -> NSRect {
        var v = visibleFrame.insetBy(dx: ui.annotationScreenInset, dy: ui.annotationScreenInset)
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
