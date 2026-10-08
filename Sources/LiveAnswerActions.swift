import AppKit

/// The buttons under an answer's reply: one for each action it offered, such as "Fix both", then
/// Reply. AppKit's own push buttons, so they look as a popover's buttons do on each version of macOS.
/// A click on an action sends its words back to whoever answered (`onPick`); Reply gives the row's
/// place to a field and Cancel, and Return there sends what was typed (`onReply`), while Cancel, Esc
/// or a click elsewhere puts the buttons back and reports what was typed (`onDraft`), which the next
/// Reply opens with. Either way
/// the buttons then stay, all disabled, with a checkmark on the one used (`pick`). A panel of its own, so a click on it never reaches the window under the answer. It
/// takes the keys only while the field is up, as the note does, so the app the person was in stays
/// in front. It is a child of the reply's window, so a window raised over the answer covers it too.
/// Pointing at an action's button reports its action (`onPoint`), and leaving the buttons reports nil.
///
/// macOS draws them as it draws any control in an app that is not frontmost, which Vignette never is
/// while an answer shows, so none is filled with the accent colour, the recommended first one included.
@MainActor
final class LiveAnswerActions: NSPanel, NSTextFieldDelegate {
    /// The button the person used.
    enum Pick: Equatable {
        case action(String)
        /// Words typed in the field Reply opens.
        case reply
    }

    var onPick: ((String) -> Void)?
    var onReply: ((String) -> Void)?
    var onDraft: ((String) -> Void)?
    var onPoint: ((LiveAnswer.Action?) -> Void)?

    private var hiding = false
    private let row: NSStackView
    private let replyButton = ActionButton(title: LiveAnswerActions.replyTitle)
    /// The field and Cancel, which take the row's place while the person types.
    private let fieldRow = NSView()
    private let field = NSTextField()
    private let cancelButton = ActionButton(title: LiveAnswerActions.cancelTitle)
    /// The field is up in the row's place, and the panel has the keys.
    private var typing = false
    /// The reply's width inside its padding, which the field spans.
    private var width: CGFloat

    static let replyTitle = "Reply"
    static let cancelTitle = "Cancel"
    /// A button's height on this version of macOS, in points.
    static let height: CGFloat = ActionButton(title: "").intrinsicContentSize.height
    /// The room round the row for the buttons' shadows and the field's focus ring, in points.
    private static let margin: CGFloat = 6
    private static let spacing: CGFloat = 8

    /// The narrowest the field gets, in points: room for its placeholder and the first words typed.
    private static let fieldMinWidth: CGFloat = 200

    /// The room an answer keeps under its reply for the row of `actions` and Reply: as wide as the row,
    /// and as the field Reply opens with Cancel beside it, so the reply is never narrower than either.
    static func room(for actions: [LiveAnswer.Action]) -> CGSize {
        let titles = actions.map(\.title) + [replyTitle]
        let buttons = titles.reduce(0) { $0 + ActionButton(title: $1).intrinsicContentSize.width } + spacing * CGFloat(titles.count - 1)
        let field = fieldMinWidth + spacing + ActionButton(title: cancelTitle).intrinsicContentSize.width
        return CGSize(width: ceil(max(buttons, field)), height: height + 8)
    }

    /// Opens with its first button's top-left corner at `corner`, in global top-left points, over
    /// `reply`, whose words are `width` wide, with the button `picked` already checked. `answerer`
    /// names who answered, for the field's placeholder, and `draft` is what the field opens with.
    init(_ actions: [LiveAnswer.Action], answerer: String, at corner: CGPoint, width: CGFloat, over reply: ReplyPopover, picked: Pick?,
         draft: String) {
        row = NSStackView()
        self.width = width
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none

        for action in actions {
            let button = ActionButton(title: action.title)
            button.target = self
            button.action = #selector(clicked(_:))
            button.onHover = { [weak self] inside in self?.onPoint?(inside ? action : nil) }
            row.addArrangedSubview(button)
        }
        replyButton.target = self
        replyButton.action = #selector(openField)
        row.addArrangedSubview(replyButton)
        row.spacing = Self.spacing
        row.edgeInsets = NSEdgeInsets(top: Self.margin, left: Self.margin, bottom: Self.margin, right: Self.margin)
        row.wantsLayer = true
        field.bezelStyle = .roundedBezel
        field.controlSize = .large
        field.font = .systemFont(ofSize: NSFont.systemFontSize(for: .large))
        field.placeholderString = "Reply to \(answerer)"
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self
        field.stringValue = draft
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        fieldRow.addSubview(field)
        fieldRow.addSubview(cancelButton)
        fieldRow.isHidden = true
        fieldRow.alphaValue = 0
        let content = NSView()
        content.wantsLayer = true
        content.addSubview(row)
        content.addSubview(fieldRow)
        contentView = content
        if let picked { check(picked) }
        fit()
        place(at: corner, width: width)
        NotificationCenter.default.addObserver(self, selector: #selector(resigned), name: NSWindow.didResignKeyNotification, object: self)

        let motion = Settings.shared.motionScale
        alphaValue = 0
        reply.carry(self)
        orderFrontRegardless()
        // The buttons drop into place on their layer, not by moving the window: a streamed reply grows
        // as they appear, and a frame animation would carry the window back over `place`'s moves.
        if motion > 0, let layer = content.layer {
            let drop = CABasicAnimation(keyPath: "transform.translation.y")
            drop.fromValue = 4
            drop.toValue = 0
            drop.duration = 0.2 * motion
            drop.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(drop, forKey: "drop")
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2 * motion
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    override var canBecomeKey: Bool { typing }
    override var canBecomeMain: Bool { false }

    private var buttonViews: [ActionButton] { row.arrangedSubviews.compactMap { $0 as? ActionButton } }

    /// The buttons, in global top-left points.
    var globalFrame: CGRect {
        CGRect(x: frame.minX, y: StateReport.primaryHeight - frame.maxY, width: frame.width, height: frame.height)
            .insetBy(dx: Self.margin, dy: Self.margin)
    }

    /// Each button's words, its frame as drawn, in global top-left points, and whether it was picked,
    /// for `[state]`.
    var buttons: [(title: String, frame: CGRect, enabled: Bool, picked: Bool)] {
        buttonViews.map { button in
            let rect = convertToScreen(button.convert(button.alignmentRect(forFrame: button.bounds), to: nil))
            return (button.title, CGRect(x: rect.minX, y: StateReport.primaryHeight - rect.maxY, width: rect.width, height: rect.height),
                    button.isEnabled, button.image != nil)
        }
    }

    /// The field, in global top-left points, while it is up, for `[state]`.
    var fieldFrame: CGRect? {
        guard typing else { return nil }
        return global(field.bounds, in: field)
    }

    /// Cancel, as drawn, in global top-left points, while the field is up, for `[state]`.
    var cancelFrame: CGRect? {
        guard typing else { return nil }
        return global(cancelButton.alignmentRect(forFrame: cancelButton.bounds), in: cancelButton)
    }

    private func global(_ rect: CGRect, in view: NSView) -> CGRect {
        let rect = convertToScreen(view.convert(rect, to: nil))
        return CGRect(x: rect.minX, y: StateReport.primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Puts the first button's top-left corner at `corner`, in global top-left points, as the
    /// answer moves with its window, or as near it as keeps the row on the screen. `width` is the
    /// reply's words' width, which the field spans.
    func place(at corner: CGPoint, width: CGFloat) {
        if width != self.width {
            self.width = width
            if typing { fit() }
        }
        var origin = CGPoint(x: corner.x - Self.margin, y: StateReport.primaryHeight - corner.y - frame.height + Self.margin)
        let point = CGPoint(x: origin.x, y: origin.y + frame.height / 2)
        if let visible = (NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main)?.visibleFrame {
            origin.x = max(visible.minX + 8 - Self.margin, min(origin.x, visible.maxX - 8 + Self.margin - frame.width))
            origin.y = max(visible.minY + 8 - Self.margin, origin.y)
        }
        guard abs(origin.x - frame.minX) > 0.25 || abs(origin.y - frame.minY) > 0.25 else { return }
        setFrameOrigin(origin)
    }

    /// Sizes the panel to the row, or, with the field up, to the reply's words when they are wider,
    /// keeping its top-left corner. The field spans it inside the margin, at the row's middle, up to
    /// Cancel, which sits where the row's last button does.
    private func fit() {
        let size = row.fittingSize
        let width = typing ? max(size.width, self.width + Self.margin * 2) : size.width
        row.frame = CGRect(origin: .zero, size: size)
        fieldRow.frame = CGRect(x: 0, y: 0, width: width, height: size.height)
        let cancel = cancelButton.intrinsicContentSize
        cancelButton.frame = cancelButton.frame(forAlignmentRect: CGRect(x: width - Self.margin - cancel.width, y: Self.margin,
                                                                         width: cancel.width, height: cancel.height))
        let fieldHeight = field.intrinsicContentSize.height
        field.frame = CGRect(x: Self.margin, y: (size.height - fieldHeight) / 2,
                             width: width - Self.margin * 2 - cancel.width - Self.spacing, height: fieldHeight)
        let rect = CGRect(x: frame.minX, y: frame.maxY - size.height, width: width, height: size.height)
        if rect != frame { setFrame(rect, display: true) }
    }

    /// The person used `pick`: every button is disabled and that one gains a checkmark, which
    /// widens it, so the row cross-fades to its new layout and the panel grows to the right.
    func pick(_ pick: Pick) {
        let fade = 0.15 * Settings.shared.motionScale
        if fade > 0 {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = fade
            row.layer?.add(transition, forKey: "pick")
        }
        check(pick)
        fit()
    }

    private func check(_ pick: Pick) {
        for button in buttonViews {
            button.isEnabled = false
            let picked = switch pick {
            case .action(let title): button !== replyButton && button.title == title
            case .reply: button === replyButton
            }
            if picked {
                button.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
                button.imagePosition = .imageLeading
            }
        }
    }

    @objc private func clicked(_ sender: ActionButton) { onPick?(sender.title) }

    // MARK: The field

    /// Reply's click: the field takes the row's place, with the keys and with what was typed before,
    /// the caret after it.
    @objc private func openField() {
        guard !typing, !hiding else { return }
        typing = true
        fit()
        show(field: true)
        makeKey()
        makeFirstResponder(field)
        let end = (field.stringValue as NSString).length
        field.currentEditor()?.selectedRange = NSRange(location: end, length: 0)
        Log.write("[live-ink] reply field open draft=\(field.stringValue.count)")
    }

    @objc private func cancel() { closeField() }

    /// The buttons come back, the keys go back to the app the person was in, and the field's words
    /// are reported as the draft.
    private func closeField() {
        guard typing else { return }
        typing = false
        makeFirstResponder(nil)
        letGoOfKeys()
        show(field: false)
        fit()
        onDraft?(field.stringValue)
        Log.write("[live-ink] reply field closed draft=\(field.stringValue.count)")
    }

    /// Gives the keys back to the app the person was in, which never stopped being the active one, so
    /// activating it would do nothing. A click elsewhere has let go already.
    private func letGoOfKeys() {
        if NSApp.isActive { NSApp.deactivate() }
    }

    private func show(field shown: Bool) {
        fieldRow.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12 * Settings.shared.motionScale
            row.animator().alphaValue = shown ? 0 : 1
            fieldRow.animator().alphaValue = shown ? 1 : 0
        } completionHandler: {
            MainActor.assumeIsolated { if !self.typing { self.fieldRow.isHidden = true } }
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            let words = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !words.isEmpty { field.stringValue = "" }
            closeField()
            if !words.isEmpty { onReply?(words) }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            closeField()
            return true
        default:
            return false
        }
    }

    @objc private func resigned() { closeField() }

    /// Fades out and closes, letting go of the keys first when the field has them and reporting its
    /// words as the draft.
    func hide() {
        guard !hiding else { return }
        hiding = true
        NotificationCenter.default.removeObserver(self)
        if typing {
            typing = false
            letGoOfKeys()
            onDraft?(field.stringValue)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15 * Settings.shared.motionScale
            animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                self.parent?.removeChildWindow(self)
                self.orderOut(nil)
                self.close()
            }
        }
    }

    /// A push button that takes a click without activating the app, and reports the pointer while enabled.
    private final class ActionButton: NSButton {
        var onHover: ((Bool) -> Void)?
        private var hoverArea: NSTrackingArea?

        convenience init(title: String) {
            self.init(frame: .zero)
            self.title = title
            bezelStyle = .push
            controlSize = .large
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        // The app is never active while the answer shows, so the area tracks whatever app is.
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            hoverArea.map(removeTrackingArea)
            let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
            addTrackingArea(area)
            hoverArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            if isEnabled { onHover?(true) }
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            if isEnabled { onHover?(false) }
        }
    }
}
