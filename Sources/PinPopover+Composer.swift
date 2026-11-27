import AppKit

extension PinPopover {
    /// The capsule round the field and the post button. The button sits inside its trailing end,
    /// `padding` from its edge, centred on the field's last line, so one line of words, its placeholder
    /// and its caret sit on the capsule's centre line with the button, and the button stays beside the
    /// last line as the words wrap. The capsule starts at the writers' names' left edge.
    func composerRow(postSize: CGFloat, padding: CGFloat) -> NSView {
        let row = NSView()
        let capsule = ComposerCapsule(radius: Self.capsuleHeight / 2)
        capsule.press = { [weak self] in self?.takeKeys() }
        for (view, parent) in [(capsule, row), (field, capsule), (post, capsule)] as [(NSView, NSView)] {
            view.translatesAutoresizingMaskIntoConstraints = false
            parent.addSubview(view)
        }
        lineHeight = field.intrinsicContentSize.height
        let lift = max(0, (Self.capsuleHeight - lineHeight) / 2)
        let height = field.heightAnchor.constraint(equalToConstant: lineHeight)
        fieldHeight = height
        [row.widthAnchor.constraint(equalToConstant: Self.rowWidth),
                                     capsule.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: Self.wordsIndent),
                                     capsule.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                                     capsule.topAnchor.constraint(equalTo: row.topAnchor), capsule.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                                     field.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: Self.textInset),
                                     field.widthAnchor.constraint(equalToConstant: Self.fieldWidth), height,
                                     field.topAnchor.constraint(equalTo: capsule.topAnchor, constant: lift),
                                     field.bottomAnchor.constraint(equalTo: capsule.bottomAnchor, constant: -lift),
                                     post.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -padding),
                                     post.centerYAnchor.constraint(equalTo: field.bottomAnchor, constant: -lineHeight / 2),
                                     post.widthAnchor.constraint(equalToConstant: postSize), post.heightAnchor.constraint(equalToConstant: postSize)].forEach { $0.isActive = true }
        return row
    }

    /// A one-line capsule's height: the post button with the padding round it.
    private static var capsuleHeight: CGFloat {
        let ui = Settings.shared.data.ui
        return ui.pinPostSize + 2 * ui.pinFieldPadding
    }

    /// Where the words start inside the capsule, clear of its round end.
    private static var textInset: CGFloat { capsuleHeight / 2 * 0.7 }

    /// The field's width: the capsule's, less where its words start, the post button and the padding
    /// on each side of the button.
    static var fieldWidth: CGFloat {
        let ui = Settings.shared.data.ui
        return rowWidth - wordsIndent - textInset - ui.pinPostSize - 2 * ui.pinFieldPadding
    }

    /// The field's words as they wrap at its width, up to `ui.pinComposerLines` lines, past which the
    /// field scrolls. While the field is edited its words are the field editor's, which the field's
    /// own size does not follow.
    var wrappedHeight: CGFloat {
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

    /// "Reply to reopen" on a resolved pin, "Comment" on a new one, and "Reply" on one with comments.
    /// The field editor takes a new placeholder only while the field is empty, so a pin resolved or
    /// reopened while the field holds words changes it once the field is empty again. The old words
    /// fade out over the new.
    func showPlaceholder(resolved: Bool, over duration: Double) {
        let placeholder = resolved ? "Reply to reopen" : (shown?.comments.isEmpty ?? true) ? "Comment" : "Reply"
        guard field.stringValue.isEmpty, field.placeholderAttributedString?.string != placeholder else { return }
        let oneLine = NSMutableParagraphStyle()
        oneLine.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: field.font ?? NSFont.preferredFont(forTextStyle: .body), .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: oneLine,
        ]
        if let old = field.placeholderAttributedString { PopoverFade.fadeOut(old, like: field, over: duration) }
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: attributes)
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
        let duration = Settings.shared.motionUI.pinPopoverDuration
        showPostable(over: duration)
        fit(over: duration)
    }
}
