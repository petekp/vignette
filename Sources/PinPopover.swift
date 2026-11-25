import AppKit

/// The popover by an open pin: its comments, oldest first, each one a click away from being edited,
/// and under them the composer, the field a comment is written in. Its keys are the composer's
/// (`EditorCore.ComposerInput`): Return posts, Shift+Return or Option+Return breaks the line,
/// Cmd+Return posts and finishes, and Esc posts and closes.
@MainActor
final class PinPopover: NSObject, NSPopoverDelegate, NSTextFieldDelegate {
    static var width: CGFloat { Settings.shared.data.ui.pinPopoverWidth }
    let pin: Pin.ID
    private let popover = NSPopover()
    private let controller = NSViewController()
    private let list = CommandReturnStack()
    private let comments = NSStackView()
    private let field = NSTextField()
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
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.usesSingleLineMode = false
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.lineBreakMode = .byWordWrapping
        field.preferredMaxLayoutWidth = Self.width - 24
        field.delegate = self
        field.setAccessibilityLabel(pin.number > 0 ? "Comment on pin \(pin.number)" : "Comment on new pin")
        comments.orientation = .vertical
        comments.alignment = .leading
        comments.spacing = 8
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 10
        list.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        list.commandReturn = { [weak self] in self?.send(.finish) }
        list.addArrangedSubview(comments)
        list.addArrangedSubview(field)
        list.widthAnchor.constraint(equalToConstant: Self.width).isActive = true
        field.widthAnchor.constraint(equalToConstant: Self.width - 24).isActive = true
        controller.view = list
        popover.contentViewController = controller
        popover.behavior = .applicationDefined
        popover.delegate = self
        update(pin, composer: composer)
    }

    func show(from rect: CGRect, of view: NSView) {
        anchor = rect
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
        field.window?.makeFirstResponder(field)
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
                comments.addArrangedSubview(row(comment, index: index))
            }
            comments.isHidden = comments.arrangedSubviews.isEmpty
        }
        if field.stringValue != composer.draft { field.stringValue = composer.draft }
        fit()
    }

    func close() {
        closing = true
        popover.close()
    }

    /// A comment: who wrote it when it was an agent, then its words. A click on it edits it.
    private func row(_ comment: Pin.Comment, index: Int) -> NSView {
        let words = NSTextField(wrappingLabelWithString: comment.text)
        words.preferredMaxLayoutWidth = Self.width - 24
        words.isSelectable = false
        let row = NSStackView(views: [words])
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 2
        if comment.agent {
            let name = NSTextField(labelWithString: comment.agentName ?? "Agent")
            name.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
            name.textColor = .secondaryLabelColor
            row.insertArrangedSubview(name, at: 0)
        }
        row.addGestureRecognizer(CommentClick(target: self, action: #selector(clicked(_:)), index: index))
        row.setAccessibilityElement(true)
        row.setAccessibilityRole(.button)
        row.setAccessibilityLabel(comment.text)
        row.setAccessibilityHelp("Edit this comment")
        return row
    }

    @objc private func clicked(_ click: CommentClick) { send(.edit(click.index)) }

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
        fit()
    }

    func popoverDidClose(_ notification: Notification) {
        if !closing { send(.close) }
    }
}

/// A click on one of the popover's comments, which knows which.
private final class CommentClick: NSClickGestureRecognizer {
    let index: Int

    init(target: AnyObject, action: Selector, index: Int) {
        self.index = index
        super.init(target: target, action: action)
    }

    required init?(coder: NSCoder) { fatalError("not used") }
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
