import AppKit
import QuartzCore

/// Draws the note's waveform caret over its field.
@MainActor
final class VoiceCaretView: NSView {
    private var bars: [CALayer] = []
    private let caret = CALayer()

    override var isFlipped: Bool { true }

    /// Lies over the field, so a click on the words reaches the field.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        bars = (0..<(VoiceCaret.bars + 2)).map { _ in
            let bar = CALayer()
            bar.cornerRadius = VoiceCaret.barWidth / 2
            layer?.addSublayer(bar)
            return bar
        }
        layer?.addSublayer(caret)
        colour()
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        colour()
    }

    private func colour() {
        var ink = NSColor.labelColor.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { ink = NSColor.labelColor.cgColor }
        bars.forEach { $0.backgroundColor = ink }
        caret.backgroundColor = ink
    }

    /// Draws `wave`, with the caret it folds into only `withCaret`: a field with no keys shows no caret.
    func draw(_ wave: VoiceCaret, withCaret: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let shown = wave.bars
        for (index, bar) in bars.enumerated() {
            guard index < shown.count else {
                bar.opacity = 0
                continue
            }
            let drawn = shown[index]
            bar.frame = CGRect(x: drawn.x, y: drawn.top, width: VoiceCaret.barWidth, height: drawn.height)
            bar.opacity = Float(drawn.opacity)
        }
        if withCaret, let line = wave.caret {
            caret.frame = CGRect(x: line.x, y: line.top, width: 1.5, height: line.height)
            caret.opacity = 1
        } else {
            caret.opacity = 0
        }
        CATransaction.commit()
    }
}

/// What the note shows while live ink listens: the words a letter at a time, and the waveform caret
/// after them, until listening ends and the waveform folds into the field's own caret.
@MainActor
final class NoteVoice: NSObject {
    private weak var content: NoteContent?
    private var letters = HeardLetters()
    private var wave: VoiceCaret
    private var levels = VoiceLevels()
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval?
    private var ending = false
    private var listening = true
    private let layout = NoteWordsLayout()
    /// The field editor's caret colour, hidden while the waveform stands in for it.
    private var hiddenCaret: (editor: NSTextView, colour: NSColor)?
    /// The words were last drawn by the field editor, rather than the field's cell.
    private var inEditor = false
    /// The words' height changed, so the note springs to it.
    var onResize: (() -> Void)?
    /// The waveform has folded away and the field shows its words as typed words.
    var onDone: (() -> Void)?

    init(content: NoteContent) {
        self.content = content
        wave = VoiceCaret(lineWidth: NoteLayout.wordsWidth, edge: layout.edge(after: 0))
        super.init()
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let link = screen.displayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    var text: String { letters.text }

    /// The words' height as far as they show.
    var shownHeight: CGFloat { layout.height(through: letters.shown) }

    func hear(_ text: String) {
        guard listening else { return }
        letters.hear(text)
        layout.set(text)
        content?.field.stringValue = text
        inEditor = false
        show(at: CACurrentMediaTime())
    }

    func add(levels new: [Float]) { levels.add(new) }

    /// Listening ended: the last letters show, then the waveform folds into the caret.
    func end() {
        ending = true
        listening = false
    }

    /// The person typed: the words are theirs now, all shown, and the waveform folds away.
    func yield() {
        listening = false
        ending = true
        letters.showAll(at: CACurrentMediaTime())
        layout.set(content?.field.currentEditor()?.string ?? content?.field.stringValue ?? letters.text)
    }

    /// Stops at once, with the words as they are, all shown.
    func cancel() { stop() }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let seconds = lastTick.map { min(now - $0, 0.1) } ?? 0
        lastTick = now
        let motion = Settings.shared.motionScale
        levels.advance(seconds)
        letters.tick(at: now, motion: motion)
        if ending, letters.allShown { wave.fold() }
        wave.tick(seconds, edge: layout.edge(after: letters.shown), level: listening ? levels.current : 0, motion: motion)
        show(at: now)
        if wave.isFolded { finish() }
    }

    private func show(at now: TimeInterval) {
        guard let content else { return }
        let motion = Settings.shared.motionScale
        paint(content.field, at: now, motion: motion)
        hideCaret(in: content.field)
        content.voiceView.draw(wave, withCaret: content.field.currentEditor() != nil)
        if content.voiceHeight != shownHeight {
            content.voiceHeight = shownHeight
            onResize?()
        }
    }

    /// Colours each letter by how strongly it shows, and the newest word lighter while the recognizer
    /// may still change it. The field editor keeps plain text and takes the colours as temporary
    /// attributes, so typing after the words types in the field's own colour.
    private func paint(_ field: NSTextField, at now: TimeInterval, motion: Double) {
        let text = letters.text
        let colours = colourRanges(of: text, at: now, motion: motion)
        if let editor = field.currentEditor() as? NSTextView, let manager = editor.layoutManager {
            if !inEditor {
                inEditor = true
                editor.string = text
                editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            }
            let whole = NSRange(location: 0, length: (editor.string as NSString).length)
            manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: whole)
            for (range, colour) in colours where NSMaxRange(range) <= whole.length {
                manager.addTemporaryAttribute(.foregroundColor, value: colour, forCharacterRange: range)
            }
        } else {
            inEditor = false
            let words = NSMutableAttributedString(string: text, attributes: [.font: NoteLayout.font, .foregroundColor: NSColor.labelColor])
            for (range, colour) in colours { words.addAttribute(.foregroundColor, value: colour, range: range) }
            field.attributedStringValue = words
        }
    }

    private func colourRanges(of text: String, at now: TimeInterval, motion: Double) -> [(NSRange, NSColor)] {
        var colours: [(NSRange, NSColor)] = []
        let newest = listening ? letters.newestWord : Int.max
        var index = 0
        for (offset, character) in text.enumerated() {
            let length = String(character).utf16.count
            defer { index += length }
            let strength = letters.strength(of: offset, at: now, motion: motion)
            let base: NSColor = offset >= newest ? .secondaryLabelColor : .labelColor
            guard strength < 1 || offset >= newest else { continue }
            colours.append((NSRange(location: index, length: length), strength < 1 ? base.withAlphaComponent(base.alphaComponent * strength) : base))
        }
        return colours
    }

    private func hideCaret(in field: NSTextField) {
        guard let editor = field.currentEditor() as? NSTextView, hiddenCaret?.editor !== editor else { return }
        restoreCaret()
        hiddenCaret = (editor, editor.insertionPointColor)
        editor.insertionPointColor = .clear
    }

    private func restoreCaret() {
        if let hiddenCaret { hiddenCaret.editor.insertionPointColor = hiddenCaret.colour }
        hiddenCaret = nil
    }

    private func finish() {
        stop()
        // A turn later, so whoever lets go of the voice then does it outside the link's tick.
        DispatchQueue.main.async { [weak self] in self?.onDone?() }
    }

    /// Stops ticking and hands the words back to the field as plain text.
    private func stop() {
        link?.invalidate()
        link = nil
        if let content, let editor = content.field.currentEditor() as? NSTextView, let manager = editor.layoutManager {
            manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: (editor.string as NSString).length))
        } else if let content {
            content.field.stringValue = content.field.stringValue
        }
        restoreCaret()
    }
}

/// The note's words laid out as its field lays them out, to find where the letters shown end.
@MainActor
final class NoteWordsLayout {
    private let storage = NSTextStorage()
    private let manager = NSLayoutManager()
    private let container = NSTextContainer(size: CGSize(width: NoteLayout.wordsWidth, height: .greatestFiniteMagnitude))

    init() {
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
    }

    func set(_ text: String) {
        guard storage.string != text else { return }
        storage.setAttributedString(NSAttributedString(string: text, attributes: [.font: NoteLayout.font]))
    }

    /// The middle of the lowercase letters, down from a line's top.
    private var middle: CGFloat {
        let font = NoteLayout.font
        return manager.defaultBaselineOffset(for: font) - font.xHeight / 2
    }

    /// Where the first `letters` characters end.
    func edge(after letters: Int) -> VoiceCaret.Edge {
        let line = NoteLayout.lineHeight
        guard letters > 0, storage.length > 0 else { return VoiceCaret.Edge(x: 0, lineTop: 0, middle: middle, lineHeight: line) }
        let end = characterEnd(letters)
        let glyphs = manager.glyphRange(forCharacterRange: NSRange(location: end - 1, length: 1), actualCharacterRange: nil)
        let fragment = manager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let box = manager.boundingRect(forGlyphRange: glyphs, in: container)
        return VoiceCaret.Edge(x: box.maxX + 1, lineTop: fragment.minY, middle: fragment.minY + middle, lineHeight: fragment.height)
    }

    /// The height of the lines the first `letters` characters are on, at least a line and at most the
    /// note's `mostLines`.
    func height(through letters: Int) -> CGFloat {
        let line = NoteLayout.lineHeight
        guard letters > 0, storage.length > 0 else { return line }
        let glyph = manager.glyphIndexForCharacter(at: characterEnd(letters) - 1)
        let bottom = ceil(manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).maxY)
        return min(max(bottom, line), line * CGFloat(NoteLayout.mostLines))
    }

    /// The UTF-16 offset after the first `letters` characters.
    private func characterEnd(_ letters: Int) -> Int {
        let string = storage.string
        let index = string.index(string.startIndex, offsetBy: min(letters, string.count))
        return string.utf16.distance(from: string.utf16.startIndex, to: index.samePosition(in: string.utf16) ?? string.utf16.endIndex)
    }
}
