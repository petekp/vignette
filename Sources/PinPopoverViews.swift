import AppKit

/// The composer's field, which keeps where its caret was when its editing ended.
final class ComposerField: NSTextField {
    var endedSelection: NSRange?

    override func textDidEndEditing(_ notification: Notification) {
        endedSelection = (notification.object as? NSTextView)?.selectedRange()
        super.textDidEndEditing(notification)
    }
}

/// The popover's view, which takes its Command keys as key equivalents: Cmd+Return, which may never
/// reach the field as a new line, and the editor's zoom keys, which the field has no use for.
final class CommandKeyStack: NSStackView {
    var commandReturn: (() -> Void)?
    var zoom: ((EditorCore.ZoomRequest) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else { return super.performKeyEquivalent(with: event) }
        if [36, 76].contains(event.keyCode), let commandReturn {
            commandReturn()
            return true
        }
        if let zoom, case .character(let character)? = EditorCore.Key(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers),
           let request = EditorCore.zoomRequest(for: character) {
            zoom(request)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// A comment in the popover, which a click edits. A trash button at its trailing edge, shown while
/// the pointer is on the comment, deletes it, as Delete Comment in its contextual menu, the Delete key
/// on it and VoiceOver's Delete comment action do. With Full Keyboard Access on, Tab reaches it and Space or
/// Return edits it, as a button.
final class CommentRow: NSView {
    var press: (() -> Void)?
    var delete: (() -> Void)?
    private let trash = NSButton()

    /// The avatar, the name, the time and the trash button share the top line, and the words start
    /// under the name's left edge, so the avatar's column holds only avatars.
    init(avatar: NSImageView, name: NSTextField, time: NSTextField, words: NSTextField, avatarSize: CGFloat, deleteSize: CGFloat,
         gaps: (name: CGFloat, words: CGFloat, trash: CGFloat)) {
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
        for view in [avatar, name, time, words, trash] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        time.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        for constraint in [avatar.leadingAnchor.constraint(equalTo: leadingAnchor), avatar.topAnchor.constraint(equalTo: topAnchor),
                           avatar.widthAnchor.constraint(equalToConstant: avatarSize), avatar.heightAnchor.constraint(equalToConstant: avatarSize),
                           avatar.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
                           name.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: gaps.name),
                           name.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
                           time.leadingAnchor.constraint(equalTo: name.trailingAnchor, constant: gaps.name),
                           time.firstBaselineAnchor.constraint(equalTo: name.firstBaselineAnchor),
                           time.trailingAnchor.constraint(lessThanOrEqualTo: trash.leadingAnchor, constant: -gaps.trash),
                           words.leadingAnchor.constraint(equalTo: name.leadingAnchor),
                           words.topAnchor.constraint(equalTo: avatar.bottomAnchor, constant: gaps.words),
                           words.trailingAnchor.constraint(equalTo: trailingAnchor),
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

extension PinPopover {
    /// Where the words start: past the avatars' column, at the writers' names.
    static var wordsIndent: CGFloat {
        let ui = Settings.shared.data.ui
        return ui.pinAvatarSize + ui.pinNameGap
    }

    /// The line between two rows, `width` wide, from the names' left edge to its right end.
    static func separator(width: CGFloat) -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        let row = NSView()
        row.addSubview(line)
        for constraint in [row.widthAnchor.constraint(equalToConstant: width),
                           line.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: wordsIndent),
                           line.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                           line.topAnchor.constraint(equalTo: row.topAnchor), line.bottomAnchor.constraint(equalTo: row.bottomAnchor)] {
            constraint.isActive = true
        }
        return row
    }
}
