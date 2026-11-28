import AppKit

/// The composer's field, which keeps where its caret was when its editing ended.
final class ComposerField: NSTextField {
    var endedSelection: NSRange?

    override func textDidEndEditing(_ notification: Notification) {
        endedSelection = (notification.object as? NSTextView)?.selectedRange()
        super.textDidEndEditing(notification)
    }
}

/// The field's capsule, with a hairline edge round the field and its post button, so it reads as a
/// place to type. A press on it outside the field puts the caret in the field.
final class ComposerCapsule: NSView {
    var press: (() -> Void)?

    /// Its corners are `radius` round, a one-line capsule's, however many lines it grows to.
    init(radius: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.tertiaryLabelColor.cgColor
            layer?.backgroundColor = NSColor.quinaryLabelColor.cgColor
        }
        layer?.borderWidth = 1 / (window?.backingScaleFactor ?? 2)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) { press?() }
}

/// The popover's view, which takes its Command keys as key equivalents: Cmd+Return, which may never
/// reach the field as a new line, and the editor's zoom keys, which the field has no use for.
class CommandKeyView: NSView {
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
/// on it and VoiceOver's Delete comment action do. On the pin's first comment a ✓ before the trash
/// resolves the pin, shown with the trash, or reopens it, shown always (`ResolveAction`). The
/// buttons fade in and out and stay in the accessibility tree while they are clear. With Full
/// Keyboard Access on, Tab reaches the comment and Space or Return edits it, as a button.
final class CommentRow: NSView {
    var press: (() -> Void)?
    var delete: (() -> Void)?
    /// The ✓, pressed.
    var resolve: (() -> Void)?
    /// Who wrote the comment, as its name says: a row whose writer changed is made again.
    let author: String
    private let trash = RowButton()
    private let check = RowButton()
    private let words: NSTextField
    /// Sending, queued, unconfirmed or failed, after the time.
    private let status = NSTextField(labelWithString: "")
    /// Why a delivery is queued, unconfirmed or failed, under the words.
    private let note = NSTextField(wrappingLabelWithString: "")
    private lazy var wordsAtBottom = words.bottomAnchor.constraint(equalTo: bottomAnchor)
    private lazy var noteAtBottom = note.bottomAnchor.constraint(equalTo: bottomAnchor)
    private let deleteSize: CGFloat
    private var action: ResolveAction?
    private var pointerInside = false
    private var fade: Double { Settings.shared.motionUI.pinPopoverDuration }

    /// The avatar, the name, the time, the status and the buttons share the top line, and the words,
    /// then any note, start under the name's left edge, so the avatar's column holds only avatars.
    init(author: String, avatar: NSImageView, name: NSTextField, time: NSTextField, words: NSTextField, width: CGFloat,
         avatarSize: CGFloat, deleteSize: CGFloat, gaps: (name: CGFloat, words: CGFloat, trash: CGFloat)) {
        self.author = author
        self.words = words
        self.deleteSize = deleteSize
        super.init(frame: .zero)
        for (button, symbol, help, action) in [(trash, "trash", "Delete comment", #selector(deletePressed)),
                                               (check, "checkmark.circle", ResolveAction.resolve(replying: false).help, #selector(checkPressed))] {
            button.isBordered = false
            button.image = Self.symbol(symbol, size: deleteSize, accessibility: help)
            button.imageScaling = .scaleProportionallyDown
            button.contentTintColor = .secondaryLabelColor
            button.toolTip = help
            button.target = self
            button.action = action
            button.focusChanged = { [weak self] in self?.focusChanged() }
            button.alphaValue = 0
        }
        check.isHidden = true
        status.font = time.font
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        note.font = .preferredFont(forTextStyle: .subheadline)
        note.textColor = .secondaryLabelColor
        note.isSelectable = false
        note.preferredMaxLayoutWidth = words.preferredMaxLayoutWidth
        note.isHidden = true
        for view in [avatar, name, time, status, words, note, check, trash] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        time.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        status.setContentCompressionResistancePriority(.defaultLow - 2, for: .horizontal)
        for constraint in [widthAnchor.constraint(equalToConstant: width),
                           avatar.leadingAnchor.constraint(equalTo: leadingAnchor), avatar.topAnchor.constraint(equalTo: topAnchor),
                           avatar.widthAnchor.constraint(equalToConstant: avatarSize), avatar.heightAnchor.constraint(equalToConstant: avatarSize),
                           avatar.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
                           name.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: gaps.name),
                           name.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
                           time.leadingAnchor.constraint(equalTo: name.trailingAnchor, constant: gaps.name),
                           time.firstBaselineAnchor.constraint(equalTo: name.firstBaselineAnchor),
                           status.leadingAnchor.constraint(equalTo: time.trailingAnchor),
                           status.firstBaselineAnchor.constraint(equalTo: name.firstBaselineAnchor),
                           status.trailingAnchor.constraint(lessThanOrEqualTo: check.leadingAnchor, constant: -gaps.trash),
                           words.leadingAnchor.constraint(equalTo: name.leadingAnchor),
                           words.topAnchor.constraint(equalTo: avatar.bottomAnchor, constant: gaps.words),
                           words.trailingAnchor.constraint(equalTo: trailingAnchor),
                           note.leadingAnchor.constraint(equalTo: name.leadingAnchor),
                           note.topAnchor.constraint(equalTo: words.bottomAnchor),
                           note.trailingAnchor.constraint(equalTo: trailingAnchor),
                           wordsAtBottom,
                           check.trailingAnchor.constraint(equalTo: trash.leadingAnchor, constant: -gaps.name),
                           check.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
                           check.widthAnchor.constraint(equalToConstant: deleteSize), check.heightAnchor.constraint(equalToConstant: deleteSize),
                           trash.trailingAnchor.constraint(equalTo: trailingAnchor), trash.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
                           trash.widthAnchor.constraint(equalToConstant: deleteSize), trash.heightAnchor.constraint(equalToConstant: deleteSize)] {
            constraint.isActive = true
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityHelp("Edit this comment")
        showActions()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private static func symbol(_ name: String, size: CGFloat, accessibility: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: accessibility)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size * 0.75, weight: .regular))
    }

    /// The comment's words in `color`, its delivery's `status` after the time and its `note` under
    /// the words, and what its ✓ does, nil on every comment but the first. A change fades over `duration`.
    func show(words text: String, color: NSColor, status statusWords: String?, note noteWords: String?, resolve action: ResolveAction?,
              over duration: Double) {
        if words.stringValue != text || words.textColor != color {
            PopoverFade.change(words, over: duration) {
                words.stringValue = text
                words.textColor = color
            }
        }
        let statusText = statusWords.map { " · \($0)" } ?? ""
        if status.stringValue != statusText { PopoverFade.change(status, over: duration) { status.stringValue = statusText } }
        showNote(noteWords, over: duration)
        if self.action != action {
            self.action = action
            check.isHidden = action == nil
            if let action {
                check.toolTip = action.help
                check.setAccessibilityLabel(action.name)
                PopoverFade.change(check, over: duration) {
                    check.image = Self.symbol(action.symbol, size: deleteSize, accessibility: action.name)
                }
            }
            showActions()
        }
        showButtons(over: duration)
    }

    private func showNote(_ text: String?, over duration: Double) {
        let shown = !note.isHidden
        guard text != (shown ? note.stringValue : nil) else { return }
        if let text {
            if shown {
                PopoverFade.change(note, over: duration) { note.stringValue = text }
            } else {
                note.stringValue = text
                note.isHidden = false
                PopoverFade.alpha(note, from: 0, to: 1, over: duration)
            }
        } else {
            PopoverFade.fadeOut(note.attributedStringValue, like: note, over: duration)
            note.isHidden = true
        }
        wordsAtBottom.isActive = note.isHidden
        noteAtBottom.isActive = !note.isHidden
    }

    /// The trash, and the ✓ on an open pin, while the pointer or the keyboard focus is on the comment;
    /// the ✓ on a resolved pin always.
    private func showButtons(over duration: Double) {
        let near = pointerInside || focusInside
        PopoverFade.alpha(trash, to: near ? 1 : 0, over: duration)
        let checkShown = action == .reopen || (action != nil && near)
        PopoverFade.alpha(check, to: checkShown ? 1 : 0, over: duration)
    }

    private func showActions() {
        var actions = [NSAccessibilityCustomAction(name: "Delete comment") { [weak self] in
            self?.delete?()
            return self?.delete != nil
        }]
        if let action {
            actions.append(NSAccessibilityCustomAction(name: action.name) { [weak self] in
                self?.resolve?()
                return self?.resolve != nil
            })
        }
        setAccessibilityCustomActions(actions)
    }

    private var focusInside: Bool {
        guard let responder = window?.firstResponder else { return false }
        return responder === self || responder === trash || responder === check
    }

    /// The window names its new first responder after the old one resigns and the new one takes it.
    private func focusChanged() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self.map { $0.showButtons(over: $0.fade) } }
        }
    }

    override func becomeFirstResponder() -> Bool {
        let took = super.becomeFirstResponder()
        focusChanged()
        return took
    }

    override func resignFirstResponder() -> Bool {
        let gave = super.resignFirstResponder()
        focusChanged()
        return gave
    }

    /// Whether the pointer is on the comment, for a row that came or moved under a pointer that stood
    /// still, which tracking areas do not report.
    func readPointer(over duration: Double? = nil) {
        guard let window else { return }
        let inside = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        guard inside != pointerInside else { return }
        pointerInside = inside
        showButtons(over: duration ?? fade)
    }

    /// A popover that opens under the pointer shows the buttons of the comment it is on.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.readPointer(over: 0) }
        }
    }

    override var acceptsFirstResponder: Bool { NSApp.isFullKeyboardAccessEnabled }
    override var canBecomeKeyView: Bool { NSApp.isFullKeyboardAccessEnabled }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { bounds.fill() }

    override func mouseEntered(with event: NSEvent) {
        pointerInside = true
        showButtons(over: fade)
    }

    override func mouseExited(with event: NSEvent) {
        pointerInside = false
        showButtons(over: fade)
    }

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
    @objc private func checkPressed() { resolve?() }

    override func accessibilityPerformPress() -> Bool {
        press?()
        return press != nil
    }
}

/// A button on a comment's top line. Full Keyboard Access reaches it, and its comment shows its
/// buttons while it has the focus.
final class RowButton: NSButton {
    var focusChanged: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let took = super.becomeFirstResponder()
        focusChanged?()
        return took
    }

    override func resignFirstResponder() -> Bool {
        let gave = super.resignFirstResponder()
        focusChanged?()
        return gave
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
