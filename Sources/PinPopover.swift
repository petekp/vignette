import AppKit

/// The popover beside an open pin: its comments, oldest first, each one a click away from being
/// edited, and under them the composer, the field a comment is written in, with its post button. Its keys are the composer's
/// (`EditorCore.ComposerInput`): Return posts, Shift+Return or Option+Return breaks the line,
/// Cmd+Return posts and finishes, and Esc posts and closes.
@MainActor
final class PinPopover: NSObject, NSPopoverDelegate, NSTextFieldDelegate {
    static var width: CGFloat { Settings.shared.data.ui.pinPopoverWidth }
    private static var inset: CGFloat { Settings.shared.data.ui.pinPopoverInset }
    let pin: Pin.ID
    private let popover = NSPopover()
    private let controller = NSViewController()
    private let list = CommandReturnStack()
    private let comments = NSStackView()
    private let field = NSTextField()
    private let post = NSButton()
    private let send: (EditorCore.ComposerInput) -> Void
    private var shown: (comments: [Pin.Comment], editing: Int?)?
    private var anchor = CGRect.null
    /// Closed by the core, so the popover's own close says nothing back.
    private var closing = false

    init(pin: Pin, composer: EditorCore.Composer, send: @escaping (EditorCore.ComposerInput) -> Void) {
        self.pin = pin.id
        self.send = send
        super.init()
        field.placeholderString = "Add a comment"
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = .labelColor
        field.isEditable = true
        field.font = .preferredFont(forTextStyle: .body)
        field.usesSingleLineMode = false
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.lineBreakMode = .byWordWrapping
        field.preferredMaxLayoutWidth = Self.fieldWidth
        field.delegate = self
        field.setAccessibilityLabel(pin.number > 0 ? "Comment on pin \(pin.number)" : "Comment on new pin")
        comments.orientation = .vertical
        comments.alignment = .leading
        let ui = Settings.shared.data.ui
        comments.spacing = ui.pinPopoverSpacing
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = ui.pinPopoverSpacing
        list.edgeInsets = NSEdgeInsets(top: Self.inset, left: Self.inset, bottom: Self.inset, right: Self.inset)
        list.commandReturn = { [weak self] in self?.send(.finish) }
        let size = ui.pinPostSize
        post.isBordered = false
        post.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: "Post comment")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .regular))
        post.imageScaling = .scaleProportionallyDown
        post.target = self
        post.action = #selector(postPressed)
        post.toolTip = "Post comment"
        let composerRow = NSStackView(views: [field, post])
        composerRow.alignment = .bottom
        composerRow.spacing = ui.pinPopoverSpacing
        list.addArrangedSubview(comments)
        list.addArrangedSubview(composerRow)
        list.widthAnchor.constraint(equalToConstant: Self.width).isActive = true
        field.widthAnchor.constraint(equalToConstant: Self.fieldWidth).isActive = true
        post.widthAnchor.constraint(equalToConstant: size).isActive = true
        post.heightAnchor.constraint(equalToConstant: size).isActive = true
        controller.view = list
        popover.contentViewController = controller
        popover.behavior = .applicationDefined
        popover.delegate = self
        update(pin, composer: composer)
    }

    /// The field's width: the popover's, less its insets, the post button and the gap before it.
    private static var fieldWidth: CGFloat {
        let ui = Settings.shared.data.ui
        return width - 2 * inset - ui.pinPostSize - ui.pinPopoverSpacing
    }

    /// Opens to the right of the pin, or to its left when the screen has no room there.
    func show(from rect: CGRect, of view: NSView) {
        anchor = rect
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxX)
        field.window?.autorecalculatesKeyViewLoop = true
        field.window?.makeFirstResponder(field)
    }

    /// A press on the picture took the keys, as a resize does: they come back to the field.
    func takeKeys() {
        guard let window = field.window, popover.isShown else { return }
        window.makeKey()
        if field.currentEditor() == nil { window.makeFirstResponder(field) }
    }

    /// The pin's teardrop moved with the zoom or a drag: the popover moves with it.
    func follow(_ rect: CGRect?) {
        guard let rect, rect != anchor, popover.isShown else { return }
        anchor = rect
        popover.positioningRect = rect
    }

    func update(_ pin: Pin, composer: EditorCore.Composer) {
        if shown?.comments != pin.comments || shown?.editing != composer.editing {
            shown = (pin.comments, composer.editing)
            for row in comments.arrangedSubviews { row.removeFromSuperview() }
            for (index, comment) in pin.comments.enumerated() where index != composer.editing {
                if !comments.arrangedSubviews.isEmpty { comments.addArrangedSubview(separator()) }
                comments.addArrangedSubview(row(comment, index: index))
            }
            comments.isHidden = comments.arrangedSubviews.isEmpty
            // A row pressed from the keyboard had the focus, and went with the rows.
            if let window = field.window, field.currentEditor() == nil { window.makeFirstResponder(field) }
        }
        if field.stringValue != composer.draft { field.stringValue = composer.draft }
        showPostable()
        fit()
    }

    /// The post button works only when the field holds words: an empty Return is how a comment is deleted or the popover closed.
    private func showPostable() {
        post.isEnabled = !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        post.contentTintColor = post.isEnabled ? .controlAccentColor : .tertiaryLabelColor
    }

    @objc private func postPressed() { send(.post) }

    func close() {
        closing = true
        popover.close()
    }

    /// A comment: who wrote it, in the system's red for a person or indigo for an agent, then its
    /// words, an agent's in the system's monospaced face, as an agent's pin number is. Pressing it edits it.
    private func row(_ comment: Pin.Comment, index: Int) -> NSView {
        let body = NSFont.preferredFont(forTextStyle: .body), small = NSFont.preferredFont(forTextStyle: .subheadline)
        let author = comment.agent ? comment.agentName ?? "Agent" : "You"
        let words = NSMutableAttributedString(string: author + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: small.pointSize, weight: .semibold),
            .foregroundColor: comment.agent ? NSColor.systemIndigo : NSColor.systemRed,
        ])
        words.append(NSAttributedString(string: comment.text, attributes: [
            .font: comment.agent ? NSFont.monospacedSystemFont(ofSize: body.pointSize, weight: .regular) : body,
            .foregroundColor: NSColor.labelColor,
        ]))
        let label = NSTextField(wrappingLabelWithString: "")
        label.attributedStringValue = words
        label.preferredMaxLayoutWidth = Self.width - 2 * Self.inset
        label.isSelectable = false
        let row = CommentRow(label)
        row.press = { [weak self] in self?.send(.edit(index)) }
        row.setAccessibilityLabel("\(author): \(comment.text)")
        return row
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.widthAnchor.constraint(equalToConstant: Self.width - 2 * Self.inset).isActive = true
        return line
    }


    private func fit() {
        field.invalidateIntrinsicContentSize()
        list.layoutSubtreeIfNeeded()
        controller.preferredContentSize = list.fittingSize
    }

    // MARK: The composer's keys

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if flags.contains(.command) { send(.finish) } else if !flags.isDisjoint(with: [.shift, .option]) {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else { send(.post) }
            return true
        case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), #selector(NSResponder.insertLineBreak(_:)):
            textView.insertNewlineIgnoringFieldEditor(nil)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            send(.close)
            return true
        default:
            return false
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        send(.changed(field.stringValue))
        showPostable()
        fit()
    }

    func popoverDidClose(_ notification: Notification) {
        if !closing { send(.close) }
    }
}

/// A comment in the popover, which a click edits. With Full Keyboard Access on, Tab reaches it and
/// Space or Return edits it, as a button.
private final class CommentRow: NSView {
    var press: (() -> Void)?

    init(_ label: NSTextField) {
        super.init(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        for constraint in [label.leadingAnchor.constraint(equalTo: leadingAnchor), label.trailingAnchor.constraint(equalTo: trailingAnchor),
                           label.topAnchor.constraint(equalTo: topAnchor), label.bottomAnchor.constraint(equalTo: bottomAnchor)] {
            constraint.isActive = true
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityHelp("Edit this comment")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { NSApp.isFullKeyboardAccessEnabled }
    override var canBecomeKeyView: Bool { NSApp.isFullKeyboardAccessEnabled }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { bounds.fill() }

    override func mouseDown(with event: NSEvent) {}

    /// As a button: the press counts where it is let go inside.
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { press?() }
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " || [36, 76].contains(event.keyCode) { press?() } else { super.keyDown(with: event) }
    }

    override func accessibilityPerformPress() -> Bool {
        press?()
        return press != nil
    }
}

/// The popover's view: Cmd+Return is a key equivalent, which may never reach the field as a new line.
private final class CommandReturnStack: NSStackView {
    var commandReturn: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard [36, 76].contains(event.keyCode), flags.contains(.command), let commandReturn else { return super.performKeyEquivalent(with: event) }
        commandReturn()
        return true
    }
}
