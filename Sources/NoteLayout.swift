import AppKit

/// What the note and the conversation that takes its place share, so the one hands over to the
/// other without a seam: the width, the words' font and place, and the row under them.
enum NoteLayout {
    static let width: CGFloat = 300
    static let inset: CGFloat = 12
    static let top: CGFloat = 11
    static let belowWords: CGFloat = 4
    static let row: CGFloat = 34
    static let mostLines = 5
    /// Where an `NSTextField` without a border starts its words, past its frame's left edge: its text
    /// container's line fragment padding.
    static let fieldTextInset: CGFloat = 2
    static var font: NSFont { .systemFont(ofSize: NSFont.systemFontSize) }
    static var lineHeight: CGFloat { ceil(font.ascender - font.descender + font.leading) }
    /// How wide the words wrap.
    static var wordsWidth: CGFloat { width - inset * 2 }
    static var fieldWidth: CGFloat { wordsWidth + fieldTextInset * 2 }

    /// The note's body with `lines` lines of words.
    static func size(lines: Int) -> CGSize {
        CGSize(width: width, height: top + CGFloat(lines) * lineHeight + belowWords + row)
    }

    /// The height of `text`'s lines wrapped as the field wraps them, from one line to `mostLines`.
    static func wordsHeight(_ text: String) -> CGFloat {
        let measured = NSAttributedString(string: text, attributes: [.font: font])
            .boundingRect(with: CGSize(width: wordsWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
        return min(max(ceil(measured.height), lineHeight), lineHeight * CGFloat(mostLines))
    }

    /// The field's frame for words `height` high, in a flipped view.
    static func fieldFrame(height: CGFloat) -> CGRect {
        CGRect(x: inset - fieldTextInset, y: top, width: fieldWidth, height: height)
    }

    /// Sets `field` up to show the person's words as the note does.
    @MainActor
    static func configure(_ field: NSTextField) {
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = font
        field.textColor = .labelColor
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.cell?.usesSingleLineMode = false
        field.lineBreakMode = .byWordWrapping
    }

    /// The row's target: its logo, `logoSize` square, `inset` from the left, then its name, `gap`
    /// after it, in `labelFont`.
    static let logoSize: CGFloat = 14
    static let gap: CGFloat = 5
    static var labelFont: NSFont { .systemFont(ofSize: 12, weight: .medium) }
    /// The target button's height, centred in the row.
    static let buttonHeight: CGFloat = 22
    /// The widest a target's name is shown; past it the name is cut in the middle.
    private static let longestLabel: CGFloat = 180

    /// The width a label of `title` takes in the row, cut at `longestLabel`. A label's cell draws its
    /// words a couple of points in from each side.
    static func labelWidth(_ title: String) -> CGFloat {
        min(ceil((title as NSString).size(withAttributes: [.font: labelFont]).width) + 4, longestLabel)
    }
}
