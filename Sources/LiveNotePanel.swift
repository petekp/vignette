import AppKit

/// Where the person types what they ask about their live ink: their note, drawn as the note it
/// becomes, beside the newest ink, opened when they let go of the chord after drawing. Return asks,
/// with or without words; Esc, or a click anywhere else, closes it and keeps the ink.
///
/// The target, on a chip under the note, starts on the one picked last, else the responder, which
/// answers on the screen, and lists the working sessions after it
/// (docs/live-ink-integration-2026-10-04.md, decision 7). A click on it or the Down arrow opens the
/// list. Sent to a session, the chip fades, the pill narrows to its words, and the drawn note takes
/// its place (`settle`).
///
/// A non-activating panel that takes the keys while it is up, as the stack's does, so the app the
/// person was in stays frontmost and gets the keys back when it closes.
@MainActor
final class LiveNotePanel: NSPanel, NSTextFieldDelegate {
    enum Target: Equatable {
        /// Claude, kept running by Vignette, which draws its answer on the screen.
        case responder
        /// A working session, through Send. Its answer is drawn beside the ink when it comes.
        case session(AgentDestination)

        var label: String {
            switch self {
            case .responder: "Claude"
            case .session(let destination): destination.project
            }
        }
    }

    /// The words typed, trimmed, and the target, when the person presses Return.
    var onAsk: ((String, Target) -> Void)?
    /// Esc, or the keys went elsewhere.
    var onClose: (() -> Void)?
    private(set) var target: Target
    /// The target picked last, which a session list resolves until the person picks by hand.
    private let remembered: Target
    private var pickedByHand = false

    private let field = NSTextField()
    private let pill = NSView()
    private let chip = TargetChip()
    private let font: NSFont
    private var sessions: [AgentDestination] = []
    private var closing = false
    private var revealed = false
    /// Sent: the words stay, the keys are let go, and only `settle` or its time limit closes it.
    private var sent = false
    /// It sits left of the ink, so it grows to the left, keeping its right edge where it touches it,
    /// with the pill and the chip against the panel's right edge.
    private var growsLeft = false
    /// The tag once sent, which `tagFrame` answers while the pill narrows to it.
    private var sentTag: CGRect?
    /// One line of the person's note at the size it is drawn, whose tag, padding and baseline the
    /// pill copies, and the white edge outside the tag.
    private let layout: TextLayout
    private let edge: CGFloat
    /// The target's menu is up. It takes the keys while it is, and `popUp` returns when it closes.
    private var menuOpen = false

    static let placeholder = "Ask about this"
    /// The widest the pill grows, in points.
    private static let maxWidth: CGFloat = 520
    /// The gap between the pill and the chip under it, and how far the chip sits in from the pill's
    /// left edge, in points.
    private static let chipGap: CGFloat = 5
    private static let chipIndent: CGFloat = 6
    /// Room after the words for the caret.
    private static let caretRoom: CGFloat = 3
    /// Where an `NSTextField` without a border starts its words, past its frame's left edge.
    private static let fieldTextInset: CGFloat = 2

    /// Opens beside `ink`, in global top-left points, on the screen that holds it, with its words in
    /// the person's style at `textSize` pt.
    init(beside ink: CGRect, textSize: CGFloat, style: TextStyle, markStyle: MarkStyle, target: Target) {
        layout = TextLayout(Mark.Text(origin: .zero, text: Self.placeholder, wrap: nil, size: textSize),
                            imageWidth: .greatestFiniteMagnitude, pointScale: 1, style: style.person)
        edge = markStyle.edgeWidth
        font = layout.font as NSFont
        self.target = target
        remembered = target
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none

        pill.wantsLayer = true
        // The tag the note draws, with its edge outside it, so the drawn note can take its place.
        pill.layer?.backgroundColor = markStyle.color(.person)
        pill.layer?.borderColor = markStyle.edgeColor.cgColor
        pill.layer?.borderWidth = edge
        pill.layer?.cornerRadius = height / 2
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = font
        field.textColor = .white
        field.placeholderAttributedString = NSAttributedString(string: Self.placeholder,
            attributes: [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.72)])
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self
        chip.onClick = { [weak self] in self?.showTargets() }
        pill.addSubview(field)
        let content = NSView()
        content.addSubview(pill)
        content.addSubview(chip)
        contentView = content
        showTarget()

        place(beside: ink)
        // Out of sight until `reveal` puts it clear of the window's text, but key, so what the
        // person types meanwhile is in it when it shows.
        alphaValue = 0
        orderFrontRegardless()
        makeKey()
        makeFirstResponder(field)
        (field.currentEditor() as? NSTextView)?.insertionPointColor = .white
        NotificationCenter.default.addObserver(self, selector: #selector(resigned), name: NSWindow.didResignKeyNotification, object: self)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// The working sessions to offer after the responder, newest first. The list can arrive in two
    /// answers, a kept one and a fresh one; a session picked stays picked while the list has it.
    /// The session picked last is found again by its id, or, after `/clear` gave it a new id, as the
    /// one session of its agent in its project.
    func setSessions(_ list: [AgentDestination]) {
        sessions = list
        if !pickedByHand {
            let found: Target = switch remembered {
            case .responder: .responder
            case .session(let last): Self.find(last, in: list).map(Target.session) ?? .responder
            }
            if found != target { show(found) }
        } else if case .session(let picked) = target, !list.contains(where: { $0.id == picked.id }) {
            pick(.responder)
        }
    }

    private static func find(_ session: AgentDestination, in list: [AgentDestination]) -> AgentDestination? {
        if let same = list.first(where: { $0.id == session.id }) { return same }
        let alike = list.filter { $0.client == session.client && !$0.detail.isEmpty && $0.detail == session.detail }
        return alike.count == 1 ? alike[0] : nil
    }

    /// Closes without a word to the callbacks.
    func dismiss() {
        guard !closing else { return }
        closing = true
        NotificationCenter.default.removeObserver(self)
        orderOut(nil)
        close()
    }

    // MARK: Layout

    /// The width a note is placed for before its words are typed, so it can grow without covering
    /// what it was placed clear of.
    static let roomyWidth: CGFloat = 320

    /// The pill and the chip under it, in global top-left points.
    var globalFrame: CGRect {
        CGRect(x: frame.minX, y: StateReport.primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    /// The tag inside the pill's edge, in global top-left points: where the drawn note's tag goes.
    var tagFrame: CGRect {
        sentTag ?? pillFrame.insetBy(dx: edge, dy: edge)
    }

    /// The pill with its edge, in global top-left points.
    var pillFrame: CGRect {
        CGRect(x: frame.minX + pill.frame.minX, y: StateReport.primaryHeight - frame.maxY, width: pill.frame.width, height: height)
    }

    /// The pill's height, and the panel's, which holds the chip under it.
    private var height: CGFloat { layout.box.height + edge * 2 }
    private var panelHeight: CGFloat { height + Self.chipGap + TargetChip.height }
    /// From the pill's left edge to its words.
    private var inset: CGFloat { edge + layout.padding.side }

    private func appKit(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: StateReport.primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Shows the note with its pill in `spot`, in global top-left points, against its left edge or,
    /// when it `growsLeft`, its right; or where it opened. It fades in as it rises a few points into
    /// place, and does not move after.
    func reveal(at spot: CGRect?, growsLeft: Bool = false) {
        guard !revealed, !closing else { return }
        revealed = true
        var rect = frame
        if let spot {
            self.growsLeft = growsLeft
            layoutContent()
            let x = growsLeft ? spot.maxX - frame.width : spot.minX
            rect.origin = CGPoint(x: x, y: StateReport.primaryHeight - spot.minY - frame.height)
        }
        let motion = Settings.shared.motionScale
        setFrame(rect.offsetBy(dx: 0, dy: motion > 0 ? -6 : 0), display: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18 * motion
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrame(rect, display: true)
        }
        Log.write("[live-ink] note shown\(spot == nil ? "" : " beside its ink")")
    }

    private func wordsWidth(_ words: String) -> CGFloat {
        ceil((words as NSString).size(withAttributes: [.font: font]).width)
    }

    /// As wide as the words and the caret, and never narrower than the placeholder while typing, so
    /// the first letters do not shrink it.
    private var pillWidth: CGFloat {
        let words = max(wordsWidth(field.stringValue), wordsWidth(Self.placeholder))
        return min(words + Self.caretRoom + inset * 2, Self.maxWidth)
    }

    private var fittedWidth: CGFloat { max(pillWidth, Self.chipIndent + chip.frame.width) }

    /// Right of the ink, or left of it when the right has no room, centred on it and kept on its screen.
    private func place(beside ink: CGRect) {
        let primaryHeight = StateReport.primaryHeight
        let centre = CGPoint(x: ink.midX, y: primaryHeight - ink.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(centre) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let width = fittedWidth
        let gap: CGFloat = 14
        var x = ink.maxX + gap
        if x + width > visible.maxX - 8 { x = ink.minX - gap - width }
        x = min(max(x, visible.minX + 8), visible.maxX - 8 - width)
        // The pill's middle on the ink's; the chip hangs under it.
        var y = centre.y + height / 2 - panelHeight
        y = min(max(y, visible.minY + 8), visible.maxY - 8 - panelHeight)
        setFrame(CGRect(x: x, y: y, width: width, height: panelHeight), display: true)
        layoutContent()
    }

    /// Grows or shrinks to fit, keeping the edge nearest the ink: its left edge, unless it sits left
    /// of the ink against the screen's right.
    private func refit() {
        var rect = frame
        rect.size.width = fittedWidth
        if growsLeft {
            rect.origin.x = frame.maxX - rect.width
        } else if rect.maxX > (screen?.visibleFrame.maxX ?? .greatestFiniteMagnitude) - 8 {
            rect.origin.x -= rect.width - frame.width
        }
        if rect != frame { setFrame(rect, display: true) }
        layoutContent()
    }

    /// The pill along the panel's top, `width` wide, and the chip under it, both against the edge
    /// nearest the ink. The words stand where the drawn note sets them: `inset` from the pill's left,
    /// on the layout's baseline.
    private func layoutContent(pillWidth width: CGFloat? = nil) {
        let width = width ?? pillWidth
        let panelWidth = frame.width
        pill.frame = CGRect(x: growsLeft ? panelWidth - width : 0, y: panelHeight - height, width: width, height: height)
        chip.setFrameOrigin(CGPoint(x: growsLeft ? panelWidth - Self.chipIndent - chip.frame.width : Self.chipIndent, y: 0))
        let fieldHeight = field.intrinsicContentSize.height
        let baseline = edge + (layout.lines.first?.baseline ?? 0) - layout.box.minY
        let top = baseline - field.firstBaselineOffsetFromTop
        field.frame = CGRect(x: inset - Self.fieldTextInset, y: height - top - fieldHeight,
                             width: width - inset * 2 + Self.fieldTextInset + Self.caretRoom, height: fieldHeight)
    }

    private func showTarget() {
        switch target {
        case .responder:
            chip.show(logo: Agent.logo(for: "claude"), title: "Claude")
            chip.toolTip = "Claude answers on the screen."
        case .session(let destination):
            chip.show(logo: Agent.logo(for: destination.client.rawValue), title: destination.project)
            chip.toolTip = "The session answers here when it's done."
        }
    }

    // MARK: Targets

    @objc private func showTargets() {
        let menu = NSMenu()
        let responder = NSMenuItem(title: "Claude, on the screen", action: #selector(pickTarget(_:)), keyEquivalent: "")
        responder.image = Agent.logo(for: "claude").map(Self.menuSized)
        responder.state = target == .responder ? .on : .off
        responder.target = self
        responder.tag = -1
        menu.addItem(responder)
        let shown = sessions.isEmpty ? [] : AgentDestination.menu(sessions, target: currentSession ?? sessions[0])
        if !shown.isEmpty {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "Send to a session"))
        }
        for (index, session) in shown.enumerated() {
            let item = NSMenuItem(title: session.project, action: #selector(pickTarget(_:)), keyEquivalent: "")
            item.image = Agent.logo(for: session.client.rawValue).map(Self.menuSized)
            if #available(macOS 14.4, *) { item.subtitle = session.name }
            item.state = currentSession?.id == session.id ? .on : .off
            item.target = self
            item.tag = index
            item.representedObject = session.id
            menu.addItem(item)
        }
        menuOpen = true
        menu.popUp(positioning: nil, at: CGPoint(x: chip.frame.minX, y: chip.frame.minY - 4), in: contentView)
        menuOpen = false
        if !closing {
            makeKey()
            makeFirstResponder(field)
            // Making the field first responder selects its words; the caret goes back to their end.
            field.currentEditor()?.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0)
        }
    }

    private var currentSession: AgentDestination? {
        if case .session(let destination) = target { return destination }
        return nil
    }

    @objc private func pickTarget(_ item: NSMenuItem) {
        if let id = item.representedObject as? String, let session = sessions.first(where: { $0.id == id }) {
            pick(.session(session))
        } else {
            pick(.responder)
        }
    }

    private func pick(_ target: Target) {
        pickedByHand = true
        show(target)
        Log.write("[live-ink] note target \(target == .responder ? "responder" : "session")")
    }

    private func show(_ target: Target) {
        self.target = target
        showTarget()
        refit()
    }

    private static func menuSized(_ image: NSImage) -> NSImage {
        let copy = image.copy() as! NSImage
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }

    // MARK: Keys

    func controlTextDidChange(_ notification: Notification) { refit() }

    /// Sent to a session: the chip fades and the pill narrows to the words, which stay put. It waits
    /// for `settle`, or closes itself after a few seconds.
    private func showSent(_ words: String) {
        sent = true
        field.isEditable = false
        field.isSelectable = false
        makeFirstResponder(nil)
        let width = min(wordsWidth(words) + inset * 2, pill.frame.width)
        // Left of the ink, it narrows from the left, so its edge stays at the ink.
        var narrowed = pill.frame
        if growsLeft { narrowed.origin.x = narrowed.maxX - width }
        narrowed.size.width = width
        sentTag = CGRect(x: frame.minX + narrowed.minX, y: pillFrame.minY, width: width, height: height).insetBy(dx: edge, dy: edge)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22 * Settings.shared.motionScale
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            chip.animator().alphaValue = 0
            pill.animator().frame = narrowed
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.settle(into: nil) }
    }

    /// Hands over to the note drawn at `tag`, in global top-left points, under the pill: the pill
    /// takes the tag's exact frame and fades, so the words never move. Nil fades it where it is.
    func settle(into tag: CGRect?) {
        guard !closing else { return }
        closing = true
        NotificationCenter.default.removeObserver(self)
        let motion = Settings.shared.motionScale
        NSAnimationContext.runAnimationGroup { context in
            context.duration = tag == nil ? 0 : 0.14 * motion
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            guard let tag else { return }
            let target = appKit(tag.insetBy(dx: -edge, dy: -edge))
            animator().setFrameOrigin(CGPoint(x: frame.minX, y: target.maxY - frame.height))
            pill.animator().frame = CGRect(x: target.minX - frame.minX, y: pill.frame.minY, width: target.width, height: pill.frame.height)
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16 * motion
                self.animator().alphaValue = 0
            } completionHandler: {
                self.orderOut(nil)
                self.close()
            }
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            let words = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let target = target
            if words.isEmpty { dismiss() } else { showSent(words) }
            onAsk?(words, target)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss()
            onClose?()
            return true
        case #selector(NSResponder.moveDown(_:)):
            showTargets()
            return true
        default:
            return false
        }
    }

    @objc private func resigned() {
        guard !closing, !menuOpen, !sent else { return }
        dismiss()
        onClose?()
    }
}

/// Under the note, where Return sends it: the agent's logo, the project, and a chevron, since a click
/// picks another. White on any app, as the note's own edge is.
@MainActor
private final class TargetChip: NSView {
    var onClick: (() -> Void)?
    private let logo = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let chevron = NSImageView()

    static let height: CGFloat = 20
    private static let font = NSFont.systemFont(ofSize: 11, weight: .medium)
    private static let logoSize: CGFloat = 12
    private static let pad: CGFloat = 7
    private static let gap: CGFloat = 4
    private static let chevronWidth: CGFloat = 8
    /// The widest a project's name is shown; past it the name is cut in the middle.
    private static let longestLabel: CGFloat = 180

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 60, height: Self.height))
        wantsLayer = true
        layer?.backgroundColor = CGColor(gray: 1, alpha: 1)
        layer?.cornerRadius = Self.height / 2
        layer?.borderColor = CGColor(gray: 0, alpha: 0.1)
        layer?.borderWidth = 0.5
        logo.imageScaling = .scaleProportionallyUpOrDown
        label.font = Self.font
        label.textColor = NSColor(white: 0.2, alpha: 1)
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 7.5, weight: .bold))
        chevron.contentTintColor = NSColor(white: 0.45, alpha: 1)
        for view in [logo, label, chevron] { addSubview(view) }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Shows `title` after `image`, and fits the chip round them.
    func show(logo image: NSImage?, title: String) {
        logo.image = image
        label.stringValue = title
        // A label's cell draws its words a couple of points in from each side.
        let words = min(ceil((title as NSString).size(withAttributes: [.font: Self.font]).width) + 4, Self.longestLabel)
        var x = Self.pad
        logo.frame = CGRect(x: x, y: (Self.height - Self.logoSize) / 2, width: Self.logoSize, height: Self.logoSize)
        x += Self.logoSize + Self.gap
        let lineHeight = ceil(label.intrinsicContentSize.height)
        label.frame = CGRect(x: x, y: (Self.height - lineHeight) / 2, width: words, height: lineHeight)
        x += words + Self.gap
        chevron.frame = CGRect(x: x, y: 0, width: Self.chevronWidth, height: Self.height)
        setFrameSize(CGSize(width: x + Self.chevronWidth + Self.pad, height: Self.height))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { onClick?() }
}
