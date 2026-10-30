import AppKit

/// Where Return sends the note: the agent's logo, the project, and a chevron, since a click picks
/// another.
@MainActor
final class SessionButton: NSView {
    var onClick: (() -> Void)?
    private let logo = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let chevron = NSImageView()

    static let height = NoteLayout.buttonHeight
    /// How far the logo sits inside the button's edge, in points.
    static let pad: CGFloat = 6
    private static let chevronWidth: CGFloat = 8
    private var settled = false

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 60, height: Self.height))
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        logo.imageScaling = .scaleProportionallyUpOrDown
        label.font = NoteLayout.labelFont
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 8, weight: .bold))
        chevron.contentTintColor = .secondaryLabelColor
        for view in [logo, label, chevron] { addSubview(view) }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = settled ? nil : NSColor.labelColor.withAlphaComponent(0.07).cgColor
    }

    // One pop-up button to VoiceOver, named by its label, rather than a logo, a title and a chevron.
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .popUpButton }
    override func accessibilityChildren() -> [Any]? { [] }
    override func accessibilityPerformPress() -> Bool {
        guard !settled, let onClick else { return false }
        onClick()
        return true
    }

    /// Shows `title` after `image`, and fits itself round them.
    func show(logo image: NSImage?, title: String) {
        logo.image = image
        label.stringValue = title
        let words = NoteLayout.labelWidth(title)
        var x = Self.pad
        logo.frame = CGRect(x: x, y: (Self.height - NoteLayout.logoSize) / 2, width: NoteLayout.logoSize, height: NoteLayout.logoSize)
        x += NoteLayout.logoSize + NoteLayout.gap
        let lineHeight = ceil(label.intrinsicContentSize.height)
        label.frame = CGRect(x: x, y: (Self.height - lineHeight) / 2, width: words, height: lineHeight)
        x += words + NoteLayout.gap
        chevron.frame = CGRect(x: x, y: 0, width: Self.chevronWidth, height: Self.height)
        setFrameSize(CGSize(width: x + Self.chevronWidth + Self.pad, height: Self.height))
    }

    /// Sent: it settles into a name, as the conversation's row shows it, over `duration`. Its
    /// background and chevron fade and its name greys; it takes no more clicks.
    func settle(duration: CFTimeInterval) {
        guard !settled else { return }
        settled = true
        let background = layer?.backgroundColor
        layer?.backgroundColor = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            chevron.animator().alphaValue = 0
        }
        guard duration > 0 else { label.textColor = .secondaryLabelColor; return }
        if let background {
            let fade = CABasicAnimation(keyPath: "backgroundColor")
            fade.fromValue = background
            fade.toValue = CGColor(gray: 0, alpha: 0)
            fade.duration = duration
            layer?.add(fade, forKey: "settle")
        }
        label.wantsLayer = true
        let fade = CATransition()
        fade.type = .fade
        fade.duration = duration
        label.layer?.add(fade, forKey: "settle")
        label.textColor = .secondaryLabelColor
    }

    /// A press anywhere on it is its own, not its label's or its logo's.
    override func hitTest(_ point: NSPoint) -> NSView? { !settled && frame.contains(point) ? self : nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The list opens a turn after the press: opened inside it, the menu closed at once (measured).
    override func mouseDown(with event: NSEvent) {
        DispatchQueue.main.async { [weak self] in self?.onClick?() }
    }
}
