import AppKit
import CoreText

/// One typing session: a plain-text view over a text mark, laid out and drawn as `TextLayout` and the
/// renderer lay the mark out and draw it, tag and all, so nothing moves or changes when typing ends.
/// The view is laid out in image px and scaled by the zoom.
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
    /// The caret or the selection moved, by typing, a key or a click.
    var onCaretMoved: (() -> Void)?

    /// Where `TextLayout` puts each line's baseline below the line's top, in px. TextKit would put it
    /// lower (27.4 px against 25.27 at 24 px); every line fragment is given this one instead.
    private var baseline: CGFloat = 0
    /// Room around the tag, in px, for its edge, its shadows and its badge.
    private var margin: CGFloat = 0
    /// The tag's edge, in px.
    private var edge: CGFloat = 0
    /// How the tag and its words are painted.
    private var paint = MarkStyle.standard
    /// Where the words start in the view, in px: whole numbers, since the text view puts its text at
    /// a whole number and would otherwise move the words off where the renderer draws them.
    private var inset = CGSize.zero
    /// The view's top-left corner in image px, where `place` last put it.
    private var origin: CGPoint = .zero
    /// The size the words are set at, in pt: the text's, which shrinks as it grows while typing.
    private(set) var size: CGFloat = 0

    /// The tag drawn under the words, as `place` last laid it out.
    private var tag: (layout: TextLayout, color: MarkColor)?
    /// Once typing ends: the lines as the renderer draws them, balanced, which the view moves to as
    /// `settled` goes from 0 to 1 (`settle(to:rect:)`).
    private var balanced: TextLayout?
    /// The tag's colour once it has settled: another than `tag`'s when the note stopped being an agent's.
    private var balancedColor = MarkColor.person
    /// How far the view has moved from the lines as typed to `balanced`: the tag's rect, and the
    /// typed words fading out as the balanced ones fade in.
    var settled: CGFloat = 0 {
        didSet {
            (textView.layoutManager as? FilledLayoutManager)?.wordsAlpha = 1 - settled
            textView.needsDisplay = true
        }
    }
    /// The view's rect in image px, where `place` or `settle` last put it.
    private var frame = CGRect.zero

    /// The lines as the view last laid them out, while typing, and their tag's colour.
    var layout: TextLayout? { tag?.layout }
    var color: MarkColor? { tag?.color }
    /// Whether the view has begun moving to the balanced lines.
    var isSettling: Bool { balanced != nil }

    /// The tag's rect in image px while settling, `settled` of the way from the typed lines' to the
    /// balanced lines'. Both sets of words are clipped to it, so neither shows outside the tag.
    var settlingBox: CGRect? {
        guard let from = tag?.layout.box, let to = balanced?.box else { return nil }
        let t = settled
        return CGRect(x: from.minX + (to.minX - from.minX) * t, y: from.minY + (to.minY - from.minY) * t,
                      width: from.width + (to.width - from.width) * t, height: from.height + (to.height - from.height) * t)
    }

    init(id: Mark.ID, text: Mark.Text, color: MarkColor, pointScale: CGFloat, imageWidth: CGFloat, style: TextStyle, paint: MarkStyle) {
        self.id = id
        let storage = NSTextStorage(string: text.text)
        let layoutManager = FilledLayoutManager()
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
        setStyle(style, paint: paint, size: text.size, pointScale: pointScale, imageWidth: imageWidth)
        textView.configurePlainText()
        textView.onResign = { [weak self] in self?.onResign?() }
        textView.drawTag = { [weak self] ctx in
            guard let self, let tag else { return }
            ctx.saveGState()
            ctx.translateBy(x: -origin.x, y: -origin.y)
            if let balanced, let box = settlingBox {
                // A note that stopped being an agent's changes colour and loses its badge as it settles.
                NoteTag.drawTag(balanced, color: paint.color(tag.color), box: box, edge: edge, style: paint, in: ctx)
                if balancedColor != tag.color {
                    ctx.setAlpha(settled)
                    NoteTag.fill(balanced, color: paint.color(balancedColor), box: box, in: ctx)
                    ctx.setAlpha(1)
                }
                if let badge = balanced.badge {
                    NoteTag.draw(badge, on: box, style: paint, in: ctx)
                } else if let badge = tag.layout.badge {
                    ctx.setAlpha(1 - settled)
                    NoteTag.draw(badge, on: box, style: paint, in: ctx)
                }
            } else {
                NoteTag.draw(tag.layout, color: paint.color(tag.color), edge: edge, style: paint, in: ctx)
            }
            ctx.restoreGState()
        }
        layoutManager.clipWords = { [weak self] ctx in
            guard let self, let balanced, let box = settlingBox else { return }
            ctx.translateBy(x: -origin.x, y: -origin.y)
            ctx.addPath(TextLayout.tagPath(box, radius: balanced.radius))
            ctx.translateBy(x: origin.x, y: origin.y)
            ctx.clip()
        }
        textView.drawOver = { [weak self] ctx in
            guard let self, let balanced, let box = settlingBox, settled > 0 else { return }
            ctx.saveGState()
            ctx.translateBy(x: -origin.x, y: -origin.y)
            ctx.addPath(TextLayout.tagPath(box, radius: balanced.radius))
            ctx.clip()
            ctx.setAlpha(settled)
            NoteTag.drawWords(balanced.lines, ink: paint.wordColor.cgColor, in: ctx)
            ctx.restoreGState()
        }
    }

    /// Sets the words in `style` at `size` pt, as `TextLayout` sets them, and paints the tag and the
    /// words as `paint` says. For a new style while typing, the words, the caret, the selection and
    /// the undo stay, and `place` puts the view where the text's new box is.
    func setStyle(_ style: TextStyle, paint: MarkStyle, size: CGFloat, pointScale: CGFloat, imageWidth: CGFloat) {
        let probe = TextLayout(Mark.Text(origin: .zero, text: "", wrap: nil, size: size), imageWidth: imageWidth, pointScale: pointScale, style: style)
        self.size = size
        baseline = probe.lines[0].baseline - probe.lines[0].rect.minY
        self.paint = paint
        edge = paint.edgeWidth * pointScale
        margin = NoteTag.reach(fontSize: CTFontGetSize(probe.font), edge: edge)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = probe.lineHeight
        paragraph.maximumLineHeight = probe.lineHeight
        let words = NSColor(cgColor: paint.wordColor.cgColor) ?? .white
        let attributes: [NSAttributedString.Key: Any] = [.font: probe.font as NSFont, .paragraphStyle: paragraph, .foregroundColor: words]
        if let storage = textView.textStorage { storage.addAttributes(attributes, range: NSRange(location: 0, length: storage.length)) }
        textView.typingAttributes.merge(attributes) { $1 }
        textView.insertionPointColor = words
        textView.needsDisplay = true
        inset = CGSize(width: (margin + probe.padding.side).rounded(.up), height: (margin + probe.padding.top).rounded(.up))
        textView.textContainerInset = inset
    }

    /// Puts the view over `layout`, the core's layout of the text, with its words wrapping where the
    /// layout wraps them, on a tag of `color`. `rect` turns a rect in image px into the editor's
    /// coordinates.
    func place(_ layout: TextLayout, color: MarkColor, rect: (CGRect) -> CGRect) {
        let lineWidth = max(layout.wrapWidth, 1)
        if textView.textContainer?.containerSize.width != lineWidth {
            textView.textContainer?.containerSize = CGSize(width: lineWidth, height: .greatestFiniteMagnitude)
        }
        let box = layout.box
        // The words at `inset` in the view, and the tag with its margin all inside it. As wide as the
        // room the words wrap in, so a caret after trailing spaces is still drawn.
        let left = box.minX + layout.padding.side - inset.width, top = box.minY + layout.padding.top - inset.height
        let px = CGRect(x: left, y: top, width: max(box.maxX + margin, box.minX + layout.padding.side + lineWidth + inset.width) - left,
                        height: box.maxY + margin - top)
        setFrame(px, rect: rect)
        if tag?.layout.box != box { textView.needsDisplay = true }
        tag = (layout, tag?.color ?? color)
        recolor(color)
    }

    /// Moves from the lines as typed to `layout`, the same words balanced, on a tag of `color`, as
    /// `settled` goes from 0 to 1. The view grows to hold both, and the typed words stay where they are
    /// in it.
    func settle(to layout: TextLayout, color: MarkColor, rect: (CGRect) -> CGRect) {
        guard let typed = tag?.layout else { return }
        let both = typed.box.union(layout.box).insetBy(dx: -margin, dy: -margin)
        let words = CGPoint(x: typed.box.minX + typed.padding.side, y: typed.box.minY + typed.padding.top)
        inset = CGSize(width: (words.x - both.minX).rounded(.up), height: (words.y - both.minY).rounded(.up))
        textView.textContainerInset = inset
        let left = words.x - inset.width, top = words.y - inset.height
        setFrame(CGRect(x: left, y: top, width: max(both.maxX, frame.maxX) - left, height: max(both.maxY, frame.maxY) - top), rect: rect)
        balanced = layout
        balancedColor = color
        settled = 0
    }

    /// Keeps the view where it is in the image, for a new zoom.
    func follow(rect: (CGRect) -> CGRect) {
        setFrame(frame, rect: rect)
    }

    private func setFrame(_ px: CGRect, rect: (CGRect) -> CGRect) {
        textView.frame = rect(px)
        textView.bounds = CGRect(origin: .zero, size: px.size)
        frame = px
        origin = px.origin
    }

    /// Sets the tag in `color`, the colour of whoever the text belongs to now.
    func recolor(_ color: MarkColor) {
        guard let current = tag, current.color != color else { return }
        tag = (current.layout, color)
        textView.needsDisplay = true
    }

    /// The caret, or the start of the selection, in image px: a line tall and no wide.
    func caretRect() -> CGRect? {
        guard let window = textView.window else { return nil }
        let onScreen = textView.firstRect(forCharacterRange: NSRange(location: textView.selectedRange().location, length: 0), actualRange: nil)
        guard onScreen.height > 0, onScreen.minX.isFinite, onScreen.minY.isFinite else { return nil }
        let inView = textView.convert(window.convertFromScreen(onScreen), from: nil)
        return inView.offsetBy(dx: origin.x, dy: origin.y)
    }

    /// Moves the caret, or selects every word. `.at` is in image px.
    func setCaret(_ caret: EditorCore.Caret) {
        let length = (textView.string as NSString).length
        switch caret {
        case .at(let point):
            let inView = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
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

    func textViewDidChangeSelection(_ notification: Notification) {
        onCaretMoved?()
    }

    func undoManager(for view: NSTextView) -> UndoManager? { undo }

    // MARK: NSLayoutManagerDelegate

    nonisolated func layoutManager(_ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
                       lineFragmentUsedRect: UnsafeMutablePointer<NSRect>, baselineOffset: UnsafeMutablePointer<CGFloat>,
                       in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
        // Laid out on the main thread, as the text view that asks for it is.
        baselineOffset.pointee = MainActor.assumeIsolated { baseline }
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
    /// Draws the tag under the words, in the view's coordinates.
    var drawTag: ((CGContext) -> Void)?
    /// Draws over the words, in the view's coordinates.
    var drawOver: ((CGContext) -> Void)?

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        if let ctx = NSGraphicsContext.current?.cgContext { drawTag?(ctx) }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let ctx = NSGraphicsContext.current?.cgContext { drawOver?(ctx) }
    }

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

/// Draws a text's letters as the renderer does: every glyph's outline filled, in the text's colour,
/// and white where selected. A glyph with no outline, such as a colour emoji, is drawn as the font
/// draws it.
private final class FilledLayoutManager: NSLayoutManager {
    /// How much of the words shows, from 0 to 1, as they fade out when typing ends.
    var wordsAlpha: CGFloat = 1
    /// Clips the words while they fade out, in the text view's coordinates.
    var clipWords: ((CGContext) -> Void)?
    private enum Pass { case system, fill, selected }
    private var pass = Pass.system

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        let selected = selectedGlyphRanges(within: glyphsToShow)
        let unselected = Self.subtract(selected, from: glyphsToShow)
        for (pass, ranges) in [(Pass.fill, unselected), (.selected, selected)] {
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
        let letters = CGMutablePath()
        for i in 0..<count {
            // Glyph outlines are drawn y up; `textMatrix` turns them the right way up at each position.
            var transform = CGAffineTransform(a: textMatrix.a, b: textMatrix.b, c: textMatrix.c, d: textMatrix.d, tx: positions[i].x, ty: positions[i].y)
            guard let path = CTFontCreatePathForGlyph(font, glyphs[i], &transform) else {
                pictures.append((glyphs[i], positions[i]))
                continue
            }
            letters.addPath(path)
        }
        ctx.saveGState()
        clipWords?(ctx)
        ctx.setAlpha(wordsAlpha)
        ctx.setFillColor(pass == .fill ? (attributes[.foregroundColor] as? NSColor)?.cgColor ?? CGColor(gray: 1, alpha: 1) : NSColor.white.cgColor)
        ctx.addPath(letters)
        ctx.fillPath()
        ctx.restoreGState()
        if !pictures.isEmpty {
            ctx.saveGState()
            clipWords?(ctx)
            ctx.setAlpha(wordsAlpha)
            super.showCGGlyphs(pictures.map(\.0), positions: pictures.map(\.1), count: pictures.count, font: font,
                               textMatrix: textMatrix, attributes: attributes, in: ctx)
            ctx.restoreGState()
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
