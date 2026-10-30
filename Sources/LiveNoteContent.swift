import AppKit

/// The note's field, blended with the popover's glass as a label is. AppKit leaves an editable field
/// out of vibrancy, so its placeholder drew as a flat grey that turned muddy over a light window.
final class VibrantField: NSTextField {
    override var allowsVibrancy: Bool { true }
}

/// What the note's popover shows: the words, then the target and the key that asks.
@MainActor
final class NoteContent: NSView {
    let field = VibrantField()
    let session = SessionButton()
    private let key = NSTextField(labelWithString: "↩")
    let light = RimLight()
    /// The popover's height, which springs to the words' as they change (`fit`).
    private var height: Tween?

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: CGRect(origin: .zero, size: NoteLayout.size(lines: 1)))
        NoteLayout.configure(field)
        key.font = NoteLayout.labelFont
        key.textColor = .secondaryLabelColor
        key.toolTip = "Return asks"
        field.setAccessibilityLabel("Note")
        key.setAccessibilityElement(false)
        for view in [field, session, key] { addSubview(view) }
        wantsLayer = true
        layer?.addSublayer(light)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// How long the popover takes to grow or shrink to the words, at full motion.
    static let resize: TimeInterval = 0.2

    /// Sizes `popover` round the words, on a spring over `duration`. With NSPopover's own `animates`
    /// on, a change of `contentSize` still steps the window from one height to the next.
    func fit(_ popover: NSPopover, over duration: TimeInterval) {
        let size = layOut(over: duration)
        let spring = height ?? Tween(initial: popover.contentSize.height) { [weak popover] in
            popover?.contentSize = CGSize(width: NoteLayout.width, height: $0)
        }
        height = spring
        spring.animate(to: size.height, duration: duration)
    }

    /// The words' own rect, without the field's inset.
    var wordsFrame: CGRect { field.frame.insetBy(dx: NoteLayout.fieldTextInset, dy: 0) }

    /// Sizes the field to its words, or its prompt while empty, from one line to `mostLines`, and
    /// answers its own size round them. Once it is in the popover, the popover sizes it (`fit`): a
    /// view that sets its own frame resizes the popover's window at once.
    /// The target and the ↩ move to their row over `duration`, as `fit` springs the height under them.
    @discardableResult func layOut(over duration: TimeInterval = 0) -> CGSize {
        let typed = field.currentEditor()?.string ?? field.stringValue
        // Empty, the field shows its prompt, which can say why Claude cannot answer in two lines.
        let words = NoteLayout.wordsHeight(typed.isEmpty ? field.placeholderString ?? "" : typed)
        field.frame = NoteLayout.fieldFrame(height: words)
        let rowY = NoteLayout.top + words + NoteLayout.belowWords
        key.sizeToFit()
        let (session, key) = duration > 0 ? (self.session.animator(), self.key.animator()) : (self.session, self.key)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            session.setFrameOrigin(CGPoint(x: NoteLayout.inset - SessionButton.pad, y: rowY + (NoteLayout.row - SessionButton.height) / 2))
            key.setFrameOrigin(CGPoint(x: NoteLayout.width - NoteLayout.inset - key.frame.width, y: rowY + (NoteLayout.row - key.frame.height) / 2))
        }
        let size = CGSize(width: NoteLayout.width, height: rowY + NoteLayout.row)
        if window == nil { setFrameSize(size) }
        return size
    }

    /// Words at full strength and the ↩ shown while the note has the keys, dimmed and faded while it
    /// does not, over `duration`.
    func showsKeys(_ keys: Bool, duration: CFTimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            field.animator().alphaValue = keys ? 1 : Self.inactiveWords
            key.animator().alphaValue = keys ? 1 : 0
        }
    }

    /// How strongly the words show while the note does not have the keys.
    private static let inactiveWords: CGFloat = 0.55

    /// Sent: the target settles into the row the conversation shows, a name rather than a button, and
    /// the key that asks fades, over `duration`.
    func settle(duration: CFTimeInterval) {
        session.settle(duration: duration)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            key.animator().alphaValue = 0
        }
    }
}

extension NoteContent {
    static let askPlaceholder = "Ask about this"
    /// Until the first ask to a responder, the prompt says what it sees (`SetupInkCopy.costNote`).
    static func firstAskPlaceholder(_ name: String) -> String { "Ask about this. \(name) sees the window's picture, title and URL." }
    static let sendPlaceholder = "Send to session"

    /// What the empty note says. Aimed at a responder, why it cannot answer comes first, `problem`.
    /// Before the first ask to it, what it sees comes next, ahead of why speech cannot listen, since it
    /// says what leaves the Mac.
    static func prompt(to responder: LiveNotePopover.Responder?, problem: String?, speechProblem: String?) -> String {
        guard let responder else { return speechProblem ?? Self.sendPlaceholder }
        if let problem { return problem }
        if !LiveResponders.asked(responder.client) { return Self.firstAskPlaceholder(responder.name) }
        return speechProblem ?? Self.askPlaceholder
    }

    /// Shows `text` as the empty field's prompt, cross-fading from the one before when `fading`.
    func showPrompt(_ text: String, fading: Bool) {
        guard field.placeholderString != text else { return }
        let duration = Self.promptFade * Settings.shared.motionScale
        if fading, duration > 0 {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = duration
            field.wantsLayer = true
            field.layer?.add(fade, forKey: "prompt")
        }
        field.placeholderString = text
    }

    private static let promptFade: TimeInterval = 0.2
}
