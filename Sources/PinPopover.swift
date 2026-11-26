import AppKit

/// The popover beside an open pin: its comments, oldest first, each one a click away from being
/// edited and with a Delete of its own, and under them the composer, the field a comment is written in, with its post button. Its keys are the composer's
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
    private let field = ComposerField()
    private let post = NSButton()
    private let send: (EditorCore.ComposerInput) -> Void
    private var shown: (comments: [Pin.Comment], editing: Int?)?
    private var anchor = CGRect.null
    /// One line of the field's words, and the field's height, which grows with them up to
    /// `ui.pinComposerLines` lines.
    private var lineHeight: CGFloat = 0
    private var fieldHeight: NSLayoutConstraint?
    /// Closed by the core, so the popover's own close says nothing back.
    private var closing = false
    /// The window that keeps the keys while the popover the editor opened on its own comes up.
    private weak var keepsKeys: NSWindow?

    init(pin: Pin, composer: EditorCore.Composer, send: @escaping (EditorCore.ComposerInput) -> Void) {
        self.pin = pin.id
        self.send = send
        super.init()
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = .labelColor
        field.isEditable = true
        let body = NSFont.preferredFont(forTextStyle: .body)
        field.font = body
        field.placeholderAttributedString = NSAttributedString(string: "Add a comment", attributes: [
            .font: body, .foregroundColor: NSColor.secondaryLabelColor,
        ])
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
        list.addArrangedSubview(comments)
        list.addArrangedSubview(composerRow(postSize: size, gap: ui.pinPopoverSpacing))
        list.widthAnchor.constraint(equalToConstant: Self.width).isActive = true
        controller.view = list
        popover.contentViewController = controller
        popover.behavior = .applicationDefined
        popover.delegate = self
        update(pin, composer: composer)
    }

    /// The field and the post button. The button is centred on the field's last line, so one line of
    /// words, its placeholder and its caret sit on the row's centre line with the button, and the
    /// button stays beside the last line as the words wrap.
    private func composerRow(postSize: CGFloat, gap: CGFloat) -> NSView {
        let row = NSView()
        for view in [field, post] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(view)
        }
        lineHeight = field.intrinsicContentSize.height
        let lift = max(0, (postSize - lineHeight) / 2)
        let height = field.heightAnchor.constraint(equalToConstant: lineHeight)
        fieldHeight = height
        for constraint in [field.leadingAnchor.constraint(equalTo: row.leadingAnchor), field.widthAnchor.constraint(equalToConstant: Self.fieldWidth), height,
                           field.topAnchor.constraint(equalTo: row.topAnchor, constant: lift),
                           field.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -lift),
                           post.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: gap), post.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                           post.centerYAnchor.constraint(equalTo: field.bottomAnchor, constant: -lineHeight / 2),
                           post.widthAnchor.constraint(equalToConstant: postSize), post.heightAnchor.constraint(equalToConstant: postSize)] {
            constraint.isActive = true
        }
        return row
    }

    /// The field's width: the popover's, less its insets, the post button and the gap before it.
    private static var fieldWidth: CGFloat {
        let ui = Settings.shared.data.ui
        return width - 2 * inset - ui.pinPostSize - ui.pinPopoverSpacing
    }

    /// Opens to the right of the pin, or to its left when the screen has no room there. With
    /// `takesKeys` false the keys stay with `view`'s window until the person clicks into the popover.
    func show(from rect: CGRect, of view: NSView, takesKeys: Bool) {
        anchor = rect
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxX)
        field.window?.autorecalculatesKeyViewLoop = true
        guard takesKeys else {
            keepsKeys = view.window
            keepsKeys?.makeKey()
            return
        }
        field.window?.makeFirstResponder(field)
    }

    func popoverDidShow(_ notification: Notification) {
        keepsKeys?.makeKey()
        keepsKeys = nil
    }

    /// A press on the picture took the keys, as a resize does: they come back to the field, with the
    /// caret or the selection where it was, where AppKit would select all the words.
    func takeKeys() {
        guard let window = field.window, popover.isShown else { return }
        window.makeKey()
        guard field.currentEditor() == nil else { return }
        window.makeFirstResponder(field)
        guard let editor = field.currentEditor() else { return }
        let length = (editor.string as NSString).length
        let kept = field.endedSelection ?? NSRange(location: length, length: 0)
        let location = min(kept.location, length)
        editor.selectedRange = NSRange(location: location, length: min(kept.length, length - location))
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
            if let window = field.window, window.isKeyWindow, field.currentEditor() == nil { window.makeFirstResponder(field) }
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

    /// A comment: the writer's avatar, as the pin's hover card shows it, then their name, "You" or the
    /// agent's as "Claude", and under it their words, all in the system's face. Pressing it edits it, and
    /// its Delete, which shows while the pointer is on it, deletes it.
    private func row(_ comment: Pin.Comment, index: Int) -> NSView {
        let ui = Settings.shared.data.ui
        let author = PinHoverCard.Words.writer(comment, capitalized: true)
        let avatar = NSImageView()
        avatar.imageScaling = .scaleProportionallyUpOrDown
        avatar.wantsLayer = true
        avatar.layer?.cornerRadius = ui.pinAvatarSize / 2
        avatar.layer?.masksToBounds = true
        PinHoverCard.paint(avatar, as: comment.writer)
        let small = NSFont.preferredFont(forTextStyle: .subheadline)
        let name = NSTextField(labelWithString: author)
        name.font = .systemFont(ofSize: small.pointSize, weight: .semibold)
        name.textColor = .labelColor
        name.lineBreakMode = .byTruncatingTail
        let words = NSTextField(wrappingLabelWithString: comment.text)
        words.font = .preferredFont(forTextStyle: .body)
        words.textColor = .labelColor
        words.isSelectable = false
        words.preferredMaxLayoutWidth = Self.width - 2 * Self.inset - ui.pinAvatarSize - ui.pinDeleteSize - 2 * ui.pinPopoverSpacing
        let row = CommentRow(avatar: avatar, name: name, words: words, avatarSize: ui.pinAvatarSize, deleteSize: ui.pinDeleteSize,
                             gap: ui.pinPopoverSpacing)
        row.widthAnchor.constraint(equalToConstant: Self.width - 2 * Self.inset).isActive = true
        row.press = { [weak self] in self?.send(.edit(index)) }
        row.delete = { [weak self] in self?.send(.delete(index)) }
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
        fieldHeight?.constant = wrappedHeight
        list.layoutSubtreeIfNeeded()
        controller.preferredContentSize = list.fittingSize
    }

    /// The field's words as they wrap at its width, up to `ui.pinComposerLines` lines, past which the
    /// field scrolls. While the field is edited its words are the field editor's, which the field's
    /// own size does not follow.
    private var wrappedHeight: CGFloat {
        let lines = max(1, Settings.shared.data.ui.pinComposerLines.rounded())
        guard let font = field.font else { return lineHeight }
        let line = NSLayoutManager().defaultLineHeight(for: font)
        let wrapped: CGFloat
        if let editor = field.currentEditor() as? NSTextView, let layout = editor.layoutManager, let container = editor.textContainer {
            layout.ensureLayout(for: container)
            wrapped = layout.usedRect(for: container).height
        } else if let cell = field.cell {
            wrapped = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: Self.fieldWidth, height: .greatestFiniteMagnitude)).height
                - (lineHeight - line)
        } else {
            wrapped = line
        }
        let extraLines = min(max(0, ((wrapped - line) / line).rounded()), lines - 1)
        return lineHeight + extraLines * line
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

/// A comment in the popover, which a click edits. A trash button at its trailing edge, shown while
/// the pointer is on the comment, deletes it, as Delete Comment in its contextual menu, the Delete key
/// on it and VoiceOver's Delete comment action do. With Full Keyboard Access on, Tab reaches it and Space or
/// Return edits it, as a button.
private final class CommentRow: NSView {
    var press: (() -> Void)?
    var delete: (() -> Void)?
    private let trash = NSButton()

    init(avatar: NSImageView, name: NSTextField, words: NSTextField, avatarSize: CGFloat, deleteSize: CGFloat, gap: CGFloat) {
        super.init(frame: .zero)
        trash.isBordered = false
        trash.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete comment")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: deleteSize * 0.75, weight: .regular))
        trash.imageScaling = .scaleProportionallyDown
        trash.contentTintColor = .secondaryLabelColor
        trash.toolTip = "Delete comment"
        trash.target = self
        trash.action = #selector(deletePressed)
        // The row takes Delete from the keyboard itself, so Tab never stops on a button that is not shown.
        trash.refusesFirstResponder = true
        trash.alphaValue = 0
        for view in [avatar, name, words, trash] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for constraint in [avatar.leadingAnchor.constraint(equalTo: leadingAnchor), avatar.topAnchor.constraint(equalTo: topAnchor),
                           avatar.widthAnchor.constraint(equalToConstant: avatarSize), avatar.heightAnchor.constraint(equalToConstant: avatarSize),
                           avatar.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
                           name.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: gap),
                           name.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
                           name.trailingAnchor.constraint(lessThanOrEqualTo: trash.leadingAnchor, constant: -gap),
                           words.leadingAnchor.constraint(equalTo: name.leadingAnchor),
                           words.topAnchor.constraint(equalTo: avatar.bottomAnchor, constant: 2),
                           words.trailingAnchor.constraint(equalTo: trash.leadingAnchor, constant: -gap),
                           words.bottomAnchor.constraint(equalTo: bottomAnchor),
                           trash.trailingAnchor.constraint(equalTo: trailingAnchor), trash.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
                           trash.widthAnchor.constraint(equalToConstant: deleteSize), trash.heightAnchor.constraint(equalToConstant: deleteSize)] {
            constraint.isActive = true
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityHelp("Edit this comment")
        setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "Delete comment") { [weak self] in
            self?.delete?()
            return self?.delete != nil
        }])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { NSApp.isFullKeyboardAccessEnabled }
    override var canBecomeKeyView: Bool { NSApp.isFullKeyboardAccessEnabled }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { bounds.fill() }

    override func mouseEntered(with event: NSEvent) { trash.alphaValue = 1 }
    override func mouseExited(with event: NSEvent) { trash.alphaValue = 0 }

    override func mouseDown(with event: NSEvent) {}

    /// As a button: the press counts where it is let go inside.
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { press?() }
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " || [36, 76].contains(event.keyCode) { press?() }
        else if [51, 117].contains(event.keyCode) { delete?() }
        else { super.keyDown(with: event) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Delete Comment", action: #selector(deletePressed), keyEquivalent: "").target = self
        return menu
    }

    @objc private func deletePressed() { delete?() }

    override func accessibilityPerformPress() -> Bool {
        press?()
        return press != nil
    }
}

/// The composer's field, which keeps where its caret was when its editing ended.
private final class ComposerField: NSTextField {
    var endedSelection: NSRange?

    override func textDidEndEditing(_ notification: Notification) {
        endedSelection = (notification.object as? NSTextView)?.selectedRange()
        super.textDidEndEditing(notification)
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
