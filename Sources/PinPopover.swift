import AppKit

/// The popover beside an open pin: its comments, oldest first, each one a click away from being
/// edited and with a Delete of its own, and under them the composer, the field a comment is written in, with its post button.
/// Under the field, Resolve, or Reply and Resolve while the field holds words, says the pin's ask is
/// done. A resolved pin's popover opens on who resolved it, with Reopen, and its comments are muted. Its keys are the composer's
/// (`EditorCore.ComposerInput`): Return posts, Shift+Return or Option+Return breaks the line,
/// Cmd+Return posts and finishes, and Esc posts and closes.
@MainActor
final class PinPopover: NSObject, NSPopoverDelegate, NSTextFieldDelegate {
    static var width: CGFloat { Settings.shared.data.ui.pinPopoverWidth }
    private static var inset: CGFloat { Settings.shared.data.ui.pinPopoverInset }
    let pin: Pin.ID
    private let popover = NSPopover()
    private let controller = NSViewController()
    private let list = CommandKeyStack()
    private let comments = NSStackView()
    private let field = ComposerField()
    private let post = NSButton()
    /// Who resolved the pin, with Reopen, over its comments, and Resolve under the field.
    private let resolveControls: PinResolveControls
    /// The state the popover shows, set by `showState`.
    private var shownState: (resolved: Pin.Resolution?, number: Int)?
    private let rim = PinGelRim()
    private let send: (EditorCore.ComposerInput) -> Void
    private var shown: (comments: [Pin.Comment], editing: Int?)?
    private var anchor = CGRect.null
    /// When the popover opened: each comment's time is said as of then, and holds still while it is open.
    private let opened = Date()
    private var aroundArea = false
    /// One line of the field's words, and the field's height, which grows with them up to
    /// `ui.pinComposerLines` lines.
    private var lineHeight: CGFloat = 0
    private var fieldHeight: NSLayoutConstraint?
    /// Closed by the core, so the popover's own close says nothing back.
    private var closing = false
    /// The view that keeps the keys while the popover the editor opened on its own comes up.
    private weak var keepsKeys: NSView?

    /// `zoom` takes the editor's zoom keys while the field has the keys.
    init(pin: Pin, composer: EditorCore.Composer, send: @escaping (EditorCore.ComposerInput) -> Void,
         zoom: @escaping (EditorCore.ZoomRequest) -> Void) {
        self.pin = pin.id
        self.send = send
        resolveControls = PinResolveControls(width: Self.width - 2 * Self.inset, gap: Settings.shared.data.ui.pinPopoverSpacing, send: send)
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
        // The field editor's clip view reaches 2 points above the field, so a field scrolled past
        // `ui.pinComposerLines` lines would show the bottom of the line above its first.
        field.clipsToBounds = true
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
        list.zoom = zoom
        let size = ui.pinPostSize
        post.isBordered = false
        post.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: "Post comment")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .regular))
        post.imageScaling = .scaleProportionallyDown
        post.target = self
        post.action = #selector(postPressed)
        post.toolTip = "Post comment"
        list.addArrangedSubview(resolveControls.resolvedLine)
        list.addArrangedSubview(comments)
        list.addArrangedSubview(composerRow(postSize: size, gap: ui.pinPopoverSpacing))
        list.addArrangedSubview(resolveControls.resolveLine)
        list.widthAnchor.constraint(equalToConstant: Self.width).isActive = true
        controller.view = list
        // The content view is the popover's body, so the rim goes round the body and not its arrow.
        list.addSubview(rim)
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

    /// Opens by the pin's teardrop, `rect` in `view`, as `PinPopoverPlace` says from the pin's `area`
    /// and the room on the screen. With `takesKeys` false the keys stay with `view`'s window until
    /// the person clicks into the popover.
    func show(from rect: CGRect, area: CGRect?, of view: NSView, takesKeys: Bool) {
        let onScreen = view.window.map { $0.convertToScreen(view.convert(rect, to: nil)) }
        let screen = view.window?.screen?.visibleFrame
        let roomOnRight = onScreen.flatMap { drop in screen.map { drop.maxX + PinPopoverPlace.reach(width: Self.width) <= $0.maxX } } ?? true
        let place = PinPopoverPlace(teardrop: rect, area: area, roomOnRight: roomOnRight)
        anchor = place.rect
        aroundArea = place.aroundArea
        popover.show(relativeTo: place.rect, of: view, preferredEdge: place.edge)
        field.window?.autorecalculatesKeyViewLoop = true
        guard takesKeys else {
            keepsKeys = view
            holdNoFocus()
            return
        }
        field.window?.makeFirstResponder(field)
    }

    func popoverDidShow(_ notification: Notification) {
        holdNoFocus()
        keepsKeys = nil
    }

    /// Opened without the keys, the popover focuses none of its views, so with Full Keyboard Access
    /// on no comment shows a focus ring before the person moves there, and the view it opened from
    /// is the first responder again, so the tool letters and Esc reach the editor.
    private func holdNoFocus() {
        guard let keepsKeys, let window = keepsKeys.window else { return }
        field.window?.makeFirstResponder(nil)
        window.makeKey()
        window.makeFirstResponder(keepsKeys)
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

    /// The pin's teardrop, and its area, moved with the zoom or a drag: the popover moves with them.
    func follow(_ rect: CGRect?, area: CGRect?) {
        guard let rect, popover.isShown else { return }
        let place = PinPopoverPlace(teardrop: rect, area: area, aroundArea: aroundArea)
        guard place.rect != anchor else { return }
        anchor = place.rect
        popover.positioningRect = place.rect
    }

    func update(_ pin: Pin, composer: EditorCore.Composer) {
        let stateChanged = shownState.map { $0.resolved != pin.resolved || $0.number != pin.number } ?? true
        if stateChanged { showState(of: pin) }
        if stateChanged || shown?.comments != pin.comments || shown?.editing != composer.editing {
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
        showPlaceholder(resolved: pin.isResolved)
        showPostable()
        fit()
    }

    /// The post button works only when the field holds words: an empty Return is how a comment is deleted or the popover closed.
    /// Resolve says Reply and Resolve while it does.
    private func showPostable() {
        post.isEnabled = !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        post.contentTintColor = post.isEnabled ? .controlAccentColor : .tertiaryLabelColor
        resolveControls.showReplying(post.isEnabled)
    }

    /// Whether the pin is resolved, and by whom: the line over its comments, its rim's colour, and
    /// Resolve, which a new pin and a resolved one go without.
    private func showState(of pin: Pin) {
        shownState = (pin.resolved, pin.number)
        let ui = Settings.shared.data.ui
        resolveControls.show(pin, now: opened)
        rim.wear(PinShading.color(of: pin.maker, resolved: pin.isResolved, markStyle: ui.markStyle), radius: RimLight.cornerRadius, sharp: nil)
    }

    /// Reply to reopen on a resolved pin. The field editor takes a new placeholder only while the
    /// field is empty, so a pin resolved or reopened while the field holds words changes it once
    /// the field is empty again.
    private func showPlaceholder(resolved: Bool) {
        let placeholder = resolved ? "Reply to reopen" : "Add a comment"
        guard field.stringValue.isEmpty, field.placeholderAttributedString?.string != placeholder else { return }
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .font: field.font ?? NSFont.preferredFont(forTextStyle: .body), .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    @objc private func postPressed() { send(.post) }

    func close() {
        closing = true
        popover.close()
    }

    /// A comment: a line with the writer's avatar, as the pin's hover card shows it, their name, "You" or
    /// the agent's as "Claude", and how long ago they wrote, and under it their words, all in the system's
    /// face. Pressing it edits it, and its Delete, which shows while the pointer is on it, deletes it.
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
        let ago = PinHoverCard.Words.ago(comment, now: opened)
        let time = NSTextField(labelWithString: ago ?? "")
        time.font = small
        time.textColor = .secondaryLabelColor
        time.lineBreakMode = .byTruncatingTail
        let words = NSTextField(wrappingLabelWithString: comment.text)
        words.font = .preferredFont(forTextStyle: .body)
        // A resolved pin's comments are done with, so they step back.
        words.textColor = shownState?.resolved == nil ? .labelColor : .secondaryLabelColor
        words.isSelectable = false
        words.preferredMaxLayoutWidth = Self.width - 2 * Self.inset
        let row = CommentRow(avatar: avatar, name: name, time: time, words: words, avatarSize: ui.pinAvatarSize, deleteSize: ui.pinDeleteSize,
                             gaps: (name: ui.pinNameGap, words: ui.pinWordsGap, trash: ui.pinPopoverSpacing))
        row.widthAnchor.constraint(equalToConstant: Self.width - 2 * Self.inset).isActive = true
        row.press = { [weak self] in self?.send(.edit(index)) }
        row.delete = { [weak self] in self?.send(.delete(index)) }
        row.setAccessibilityLabel([author, ago].compactMap { $0 }.joined(separator: ", ") + ": \(comment.text)")
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
