import AppKit
import CoreText

/// One typing session: a plain-text view over a text mark, laid out and drawn as `TextLayout` and the
/// renderer lay the mark out and draw it, so nothing moves or changes when typing ends. The view is
/// laid out in image px and scaled by the zoom.
@MainActor
final class TypingField: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {
    let id: Mark.ID
    let textView: EditorTextView
    /// The session's own undo, so Cmd+Z never reaches past the session's start.
    let undo = UndoManager()
    /// The text changed; the core takes it.
    var onChange: ((String) -> Void)?
    /// The text view gave up the keys to something else, ending the session on its own.
    var onResign: (() -> Void)?

    /// Where `TextLayout` puts each line's baseline below the line's top, in px. TextKit would put it
    /// lower (27.4 px against 25.27 at 24 px); every line fragment is given this one instead.
    private let baseline: CGFloat
    /// Room around the box, in px, for the outline and for glyphs that reach past their line.
    private let margin: CGFloat

    init(id: Mark.ID, text: Mark.Text, color: MarkColor, pointScale: CGFloat, imageWidth: CGFloat, style: TextStyle) {
        self.id = id
        let probe = TextLayout(Mark.Text(origin: .zero, text: "", wrap: nil, size: text.size), imageWidth: imageWidth, pointScale: pointScale, style: style)
        baseline = probe.lines[0].baseline
        let outline = 2 * Mark.Text.outlineWidth * pointScale
        margin = outline + CTFontGetSize(probe.font) / 4
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = probe.lineHeight
        paragraph.maximumLineHeight = probe.lineHeight
        let attributes: [NSAttributedString.Key: Any] = [.font: probe.font as NSFont, .paragraphStyle: paragraph,
                                                         .foregroundColor: NSColor(cgColor: color.cgColor) ?? .red]
        let storage = NSTextStorage(string: text.text, attributes: attributes)
        let layoutManager = OutlinedLayoutManager()
        layoutManager.outlineWidth = outline
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 1, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        layoutManager.addTextContainer(container)
        textView = EditorTextView(frame: .zero, textContainer: container)
        super.init()
        layoutManager.delegate = self
        textView.delegate = self
        textView.typingAttributes = attributes
        textView.textContainerInset = CGSize(width: margin, height: margin)
        textView.configurePlainText()
        textView.onResign = { [weak self] in self?.onResign?() }
    }

    /// Puts the view over `box`, the core's box for the text, with its words wrapping where
    /// `TextLayout` wraps them. `rect` turns a rect in image px into the editor's coordinates.
    func place(_ text: Mark.Text, box: CGRect, imageWidth: CGFloat, rect: (CGRect) -> CGRect) {
        let lineWidth = max(TextLayout.lineWidth(of: text, imageWidth: imageWidth), 1)
        if textView.textContainer?.containerSize.width != lineWidth {
            textView.textContainer?.containerSize = CGSize(width: lineWidth, height: .greatestFiniteMagnitude)
        }
        // As wide as the room the words wrap in, so a caret after trailing spaces is still drawn.
        let px = CGRect(x: box.minX - margin, y: box.minY - margin,
                        width: max(box.width, lineWidth) + 2 * margin, height: box.height + 2 * margin)
        textView.frame = rect(px)
        textView.bounds = CGRect(origin: .zero, size: px.size)
    }

    /// Moves the caret, or selects every word. `.at` is in image px; `origin` is the box's.
    func setCaret(_ caret: EditorCore.Caret, boxOrigin origin: CGPoint) {
        let length = (textView.string as NSString).length
        switch caret {
        case .at(let point):
            let inView = CGPoint(x: point.x - origin.x + margin, y: point.y - origin.y + margin)
            textView.setSelectedRange(NSRange(location: textView.characterIndexForInsertion(at: inView), length: 0))
        case .end:
            textView.setSelectedRange(NSRange(location: length, length: 0))
        case .selectAll:
            textView.setSelectedRange(NSRange(location: 0, length: length))
        }
    }

    // MARK: NSTextViewDelegate

    /// Refuses a change that would make the text longer than a drawing file may hold.
    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
        guard let text else { return true }
        let result = (textView.string as NSString).replacingCharacters(in: range, with: text)
        return result.utf8.count <= MarkFields.maxTextBytes && result.count <= MarkFields.maxTextLength
    }

    func textDidChange(_ notification: Notification) {
        onChange?(textView.string)
    }

    func undoManager(for view: NSTextView) -> UndoManager? { undo }

    // MARK: NSLayoutManagerDelegate

    nonisolated func layoutManager(_ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
                       lineFragmentUsedRect: UnsafeMutablePointer<NSRect>, baselineOffset: UnsafeMutablePointer<CGFloat>,
                       in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
        baselineOffset.pointee = baseline
        return true
    }
}

/// The text view of a typing session. Every key goes to the editor first, which takes the few that
/// end typing or zoom; a press reaches it only when the editor passes one on.
@MainActor
final class EditorTextView: NSTextView {
    /// Asked for every key; true when the editor took it.
    var takeKey: ((NSEvent) -> Bool)?
    var onResign: (() -> Void)?

    /// Plain text, typed exactly as drawn: no rich text, and no automatic change of any kind.
    fileprivate func configurePlainText() {
        isRichText = false
        importsGraphics = false
        allowsImageEditing = false
        usesFontPanel = false
        usesRuler = false
        usesFindBar = false
        allowsUndo = true
        drawsBackground = false
        isHorizontallyResizable = false
        isVerticallyResizable = false
        minSize = .zero
        maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        smartInsertDeleteEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticTextCompletionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        enabledTextCheckingTypes = 0
        inlinePredictionType = .no
        if #available(macOS 15.0, *) {
            mathExpressionCompletionType = .no
            writingToolsBehavior = .none
        }
        insertionPointColor = NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1)
        selectedTextAttributes = [.backgroundColor: EditorStyle.selectionBlue, .foregroundColor: NSColor.white]
    }

    override func keyDown(with event: NSEvent) {
        if takeKey?(event) != true { super.keyDown(with: event) }
    }

    /// A key the text has no use for, such as Cmd+B, does nothing, without the beep.
    override func doCommand(by selector: Selector) {
        if selector != Selector(("noop:")) { super.doCommand(by: selector) }
    }

    /// The editor sets the cursor over the whole canvas, text included.
    override func resetCursorRects() {}

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        onResign?()
        return true
    }
}

/// Draws a text's letters as the renderer does: every glyph's outline stroked in the outline's
/// near-black, then the glyph filled over it with the same path, so the outline lies wholly outside the
/// letters. Selected letters are white with no outline. A glyph with no outline, such as a colour
/// emoji, is drawn as the font draws it.
private final class OutlinedLayoutManager: NSLayoutManager {
    /// The outline's stroke width in px: twice what shows outside the letters.
    var outlineWidth: CGFloat = 0
    private enum Pass { case system, outline, fill, selected }
    private var pass = Pass.system

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        let selected = selectedGlyphRanges(within: glyphsToShow)
        let unselected = Self.subtract(selected, from: glyphsToShow)
        // Every outline first, so no glyph's outline covers a neighbour's fill.
        for (pass, ranges) in [(Pass.outline, unselected), (.fill, unselected), (.selected, selected)] {
            self.pass = pass
            for range in ranges { super.drawGlyphs(forGlyphRange: range, at: origin) }
        }
        pass = .system
    }

    override func showCGGlyphs(_ glyphs: UnsafePointer<CGGlyph>, positions: UnsafePointer<CGPoint>, count: Int, font: NSFont,
                               textMatrix: CGAffineTransform, attributes: [NSAttributedString.Key: Any] = [:], in ctx: CGContext) {
        guard pass != .system else {
            return super.showCGGlyphs(glyphs, positions: positions, count: count, font: font, textMatrix: textMatrix, attributes: attributes, in: ctx)
        }
        var pictures: [(CGGlyph, CGPoint)] = []
        ctx.saveGState()
        switch pass {
        case .outline:
            ctx.setStrokeColor(Mark.Text.outlineColor)
            ctx.setLineWidth(outlineWidth)
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)
        case .fill:
            ctx.setFillColor((attributes[.foregroundColor] as? NSColor)?.cgColor ?? MarkColor.start.cgColor)
        case .selected, .system:
            ctx.setFillColor(NSColor.white.cgColor)
        }
        for i in 0..<count {
            // Glyph outlines are drawn y up; `textMatrix` turns them the right way up at each position.
            var transform = CGAffineTransform(a: textMatrix.a, b: textMatrix.b, c: textMatrix.c, d: textMatrix.d, tx: positions[i].x, ty: positions[i].y)
            guard let path = CTFontCreatePathForGlyph(font, glyphs[i], &transform) else {
                pictures.append((glyphs[i], positions[i]))
                continue
            }
            ctx.addPath(path)
            // One glyph at a time: Core Graphics strokes a whole line's outlines several times slower.
            if pass == .outline { ctx.strokePath() } else { ctx.fillPath() }
        }
        ctx.restoreGState()
        if pass != .outline, !pictures.isEmpty {
            super.showCGGlyphs(pictures.map(\.0), positions: pictures.map(\.1), count: pictures.count, font: font,
                               textMatrix: textMatrix, attributes: attributes, in: ctx)
        }
    }

    /// The glyphs of the text view's selection inside `range`.
    private func selectedGlyphRanges(within range: NSRange) -> [NSRange] {
        guard let textView = firstTextView else { return [] }
        // Glyphs are drawn on the main thread, as the text view that asks for them is.
        let selection = MainActor.assumeIsolated { textView.selectedRanges.map(\.rangeValue) }
        return selection.compactMap { characters in
            guard characters.length > 0 else { return nil }
            let glyphs = glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
            let overlap = NSIntersectionRange(glyphs, range)
            return overlap.length > 0 ? overlap : nil
        }.sorted { $0.location < $1.location }
    }

    /// `range` less the sorted, disjoint `parts`.
    private static func subtract(_ parts: [NSRange], from range: NSRange) -> [NSRange] {
        var result: [NSRange] = []
        var start = range.location
        for part in parts {
            if part.location > start { result.append(NSRange(location: start, length: part.location - start)) }
            start = max(start, NSMaxRange(part))
        }
        if start < NSMaxRange(range) { result.append(NSRange(location: start, length: NSMaxRange(range) - start)) }
        return result
    }
}
