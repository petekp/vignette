import AppKit

/// A menu item that names its shortcut at its right, in grey, as AppKit draws a key equivalent:
/// for a shortcut no key equivalent can say, such as a double tap or a held chord.
///
/// The hint is part of the attributed title, after a right-aligned tab. It carries a colour of its
/// own, which AppKit leaves alone on the highlighted row, so the highlight sets it
/// (`ShortcutHints.highlight`).
@MainActor
final class ShortcutHintItem: NSMenuItem {
    /// The title without its hint. `title` reads the attributed title once one is set.
    let text: String
    var hint: String? {
        didSet { render() }
    }
    var tabStop: CGFloat = 0
    var drawsHighlighted = false

    static let font = NSFont.menuFont(ofSize: 0)

    override init(title: String, action: Selector?, keyEquivalent: String) {
        text = title
        super.init(title: title, action: action, keyEquivalent: keyEquivalent)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var titleWidth: CGFloat { (text as NSString).size(withAttributes: [.font: Self.font]).width }
    var hintWidth: CGFloat { hint.map { ($0 as NSString).size(withAttributes: [.font: Self.font]).width } ?? 0 }

    func render() {
        guard let hint else {
            attributedTitle = nil
            return
        }
        let color: NSColor = drawsHighlighted ? .selectedMenuItemTextColor : .secondaryLabelColor
        let styled = NSMutableAttributedString(string: text + "\t", attributes: [.font: Self.font])
        styled.append(NSAttributedString(string: hint, attributes: [.font: Self.font, .foregroundColor: color]))
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: tabStop)]
        styled.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: styled.length))
        attributedTitle = styled
    }
}

@MainActor
enum ShortcutHints {
    /// The least space between an item's title and its hint.
    static let gap: CGFloat = 24

    /// Sets one tab stop for every hint in `menu`: past the widest title and its hint, or at the
    /// right of the widest title without one, so the hints end together at the titles' right.
    /// AppKit draws key equivalents in a column of their own to the right of every title, so a hint
    /// ends at that column's left edge, not where ⌘Q ends. Call it after the items change.
    static func align(_ menu: NSMenu) {
        let hinted = menu.items.compactMap { $0 as? ShortcutHintItem }.filter { $0.hint != nil }
        let others = menu.items.filter { item in
            !hinted.contains { $0 === item } && !item.isSeparatorItem && !item.isSectionHeader
        }.map { item in
            max((item.title as NSString).size(withAttributes: [.font: ShortcutHintItem.font]).width,
                SessionMenu.subtitleWidth(of: item))
        }
        let stop = max(hinted.map { $0.titleWidth + gap + $0.hintWidth }.max() ?? 0, others.max() ?? 0)
        for item in hinted {
            item.tabStop = stop
            item.render()
        }
    }

    /// Draws each hint in `menu` white on the row about to be highlighted, and grey on the rest.
    static func highlight(_ highlighted: NSMenuItem?, in menu: NSMenu) {
        for case let item as ShortcutHintItem in menu.items where item.hint != nil {
            let lit = item === highlighted
            guard item.drawsHighlighted != lit else { continue }
            item.drawsHighlighted = lit
            item.render()
        }
    }
}
