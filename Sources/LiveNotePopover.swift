import AppKit

/// Where the person types what they ask about their live ink: a popover hung from the newest ink,
/// opened when they let go of the chord after drawing. Return asks, with or without words; a click
/// anywhere else closes it and keeps the ink; Esc and ⌘⌫ close it and take back the ink it was opened
/// for. Once asked, the person's words are drawn as their note in its place (`settle`).
///
/// Under the words, the target: the one picked last, else the responder (`DestinationChoice`
/// decides), which answers on the screen, with the working sessions listed after it
/// (docs/live-ink-integration-2026-10-04.md, decision 7). A click on it or the Down arrow opens the
/// list.
///
/// A popover's window is a non-activating panel, so its field takes the keys while the app the person
/// was in stays frontmost. AppKit still counts Vignette as active while the field has them, so closing
/// hands them back at once (`letGoOfKeys`) rather than when AppKit's fade ends.
@MainActor
final class LiveNotePopover: NSObject, NSTextFieldDelegate {
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
    /// A click elsewhere took the keys.
    var onClose: (() -> Void)?
    /// Esc or ⌘⌫: the person takes back the note and the ink drawn for it.
    var onDiscard: (() -> Void)?
    /// The person typed in the note, which takes over from what they say.
    var onTyped: (() -> Void)?
    private(set) var target: Target
    /// The note's own pick, which each session list resolves: the session picked last until the
    /// person picks by hand, then their pick, the responder once a hand-picked session leaves the list.
    private var ownPick: DestinationChoice.LiveNotePick

    private let popover = NSPopover()
    /// The window the popover hangs from: clear, a point at `place.at`, never key, letting every click through.
    private let host: Host
    private let content = NoteContent()
    private var place: PopoverPlace
    private var sessions: [AgentDestination] = []
    private var closing = false
    private var revealed = false
    /// Sent: the words stay, the keys are let go, and only `settle` or its time limit closes it.
    private var sent = false
    /// The target's menu is up. It takes the keys while it is, and `popUp` returns when it closes.
    private var menuOpen = false
    /// Whether Vignette was the active app before the note took the keys, so closing gives them back
    /// only to another app.
    private let wasActive: Bool
    private var watching: [NSObjectProtocol] = []

    static let placeholder = "Ask about this"
    static let listeningPlaceholder = "Listening…"

    /// The body at the height it is placed for, three lines of words, so it can grow without covering
    /// what it was placed clear of.
    static var placementSize: CGSize { NoteContent.size(lines: 3) }

    /// Opens hung from `place`, in global top-left points, out of sight until `reveal`, but with the
    /// keys, so what the person types meanwhile is in it when it shows.
    init(at place: PopoverPlace, target: Target) {
        self.place = place
        self.target = target
        ownPick = if case .session(let destination) = target { .remembered(destination) } else { .remembered(nil) }
        host = Host(at: place.at)
        wasActive = NSApp.isActive
        super.init()
        let controller = NSViewController()
        controller.view = content
        popover.contentViewController = controller
        popover.behavior = .applicationDefined
        popover.animates = false
        content.field.delegate = self
        content.session.onClick = { [weak self] in self?.showTargets() }
        showTarget()
        content.layOut()
        popover.contentSize = content.frame.size
        host.orderFrontRegardless()
        popover.show(relativeTo: host.anchor.bounds, of: host.anchor, preferredEdge: Self.edge(place.edge))
        guard let window = content.window else { return }
        window.alphaValue = 0
        window.makeKey()
        window.makeFirstResponder(content.field)
        watching.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resigned() }
        })
    }

    /// The working sessions to offer after the responder. The list can arrive in several answers, a
    /// kept one and fresh ones; `DestinationChoice` says which target each one starts the note on.
    func setSessions(_ candidates: DestinationChoice.Candidates) {
        let answer = DestinationChoice.choose(candidates, for: .liveNote(ownPick))
        sessions = answer.list
        let found: Target = answer.pick.map(Target.session) ?? .responder
        guard found != target else { return }
        if case .byHand = ownPick { pick(found) } else { show(found) }
    }

    /// Closes without a word to the callbacks.
    func dismiss() {
        guard !closing else { return }
        closing = true
        stopWatching()
        letGoOfKeys()
        popover.animates = false
        popover.close()
        host.orderOut(nil)
    }

    // MARK: Placing

    /// The body, in global top-left points, or nil while it is not up.
    var globalFrame: CGRect? {
        guard popover.isShown, let window = content.window else { return nil }
        return Self.topLeft(window.convertToScreen(content.convert(content.bounds, to: nil)))
    }

    /// The words, in global top-left points: where the drawn note's tag goes once they are asked.
    var tagFrame: CGRect? {
        guard let window = content.window else { return nil }
        return Self.topLeft(window.convertToScreen(content.convert(content.wordsFrame, to: nil)))
    }

    /// Hangs it from `place` instead, before it shows; the note does not move once it has.
    func move(to place: PopoverPlace) {
        guard !revealed, !closing, place.at != self.place.at || place.edge != self.place.edge else { return }
        let edge = place.edge != self.place.edge
        self.place = place
        host.move(to: place.at)
        // AppKit keeps the edge it was shown on, so another edge means showing it again. That keeps the
        // keys and the caret.
        if edge {
            popover.show(relativeTo: host.anchor.bounds, of: host.anchor, preferredEdge: Self.edge(place.edge))
        } else {
            popover.positioningRect = host.anchor.bounds
        }
    }

    /// Shows the note where it hangs. It fades in, and does not move after.
    func reveal() {
        guard !revealed, !closing, let window = content.window else { return }
        revealed = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeIn * Settings.shared.motionScale
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
        Log.write("[live-ink] note shown edge=\(place.edge)")
    }

    private static func edge(_ edge: PopoverPlace.Edge) -> NSRectEdge {
        switch edge {
        case .below: .minY
        case .above: .maxY
        case .right: .maxX
        case .left: .minX
        }
    }

    private static func topLeft(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: StateReport.primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Grows or shrinks to fit the words.
    private func refit() {
        content.layOut()
        if popover.contentSize != content.frame.size { popover.contentSize = content.frame.size }
    }

    // MARK: Targets

    private func showTarget() {
        switch target {
        case .responder:
            content.session.show(logo: Agent.logo(for: "claude"), title: "Claude")
            content.session.toolTip = "Claude answers on the screen."
        case .session(let destination):
            content.session.show(logo: Agent.logo(for: destination.client.rawValue), title: destination.project)
            content.session.toolTip = "The session answers here when it's done."
        }
    }

    /// The list of targets, under the target, or beside the note when the screen has no room below it,
    /// so it never covers the words being typed.
    private func showTargets() {
        guard let window = content.window else { return }
        let menu = NSMenu()
        let responder = NSMenuItem(title: "Claude, on the screen", action: #selector(pickTarget(_:)), keyEquivalent: "")
        responder.image = Agent.logo(for: "claude").map(Self.menuSized)
        responder.state = target == .responder ? .on : .off
        responder.target = self
        menu.addItem(responder)
        let shown = sessions.isEmpty ? [] : DestinationChoice.menu(sessions, target: currentSession ?? sessions[0])
        if !shown.isEmpty {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "Send to a session"))
        }
        for session in shown {
            let item = NSMenuItem(title: session.project, action: #selector(pickTarget(_:)), keyEquivalent: "")
            item.image = Agent.logo(for: session.client.rawValue).map(Self.menuSized)
            if #available(macOS 14.4, *) { item.subtitle = session.name }
            item.state = currentSession?.id == session.id ? .on : .off
            item.target = self
            item.representedObject = session.id
            menu.addItem(item)
        }
        let button = window.convertToScreen(content.session.convert(content.session.bounds, to: nil))
        let visible = window.screen?.visibleFrame ?? .zero
        var point = CGPoint(x: button.minX, y: button.minY - Self.menuGap)
        if point.y - menu.size.height < visible.minY + Self.menuGap {
            let body = window.frame
            let left = body.minX - Self.menuGap - menu.size.width
            point = CGPoint(x: left >= visible.minX + Self.menuGap ? left : body.maxX + Self.menuGap,
                            y: max(visible.minY + Self.menuGap, button.minY) + menu.size.height)
        }
        menuOpen = true
        menu.popUp(positioning: nil, at: point, in: nil)
        menuOpen = false
        guard !closing else { return }
        window.makeKey()
        window.makeFirstResponder(content.field)
        // Making the field first responder selects its words; the caret goes back to their end.
        content.field.currentEditor()?.selectedRange = NSRange(location: (content.field.stringValue as NSString).length, length: 0)
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
        show(target)
        ownPick = .byHand(currentSession)
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

    func controlTextDidChange(_ notification: Notification) {
        refit()
        onTyped?()
    }

    /// Shows what the person is saying, until they type: a word typed is theirs to keep.
    func hear(_ words: String) {
        guard !sent, !closing else { return }
        content.field.stringValue = words
        // The caret follows the words, so typing after them adds to the end.
        (content.field.currentEditor() as? NSTextView)?.setSelectedRange(NSRange(location: (words as NSString).length, length: 0))
        refit()
    }

    /// Says in the empty note that it is listening, or that it is waiting for typing.
    func setListening(_ listening: Bool) {
        content.field.placeholderString = listening ? Self.listeningPlaceholder : Self.placeholder
    }

    /// Asks as Return does.
    func send() {
        guard !sent, !closing else { return }
        let words = content.field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = target
        if words.isEmpty { dismiss() } else { showSent() }
        onAsk?(words, target)
    }

    /// Sent: the words stay and the target dims while it waits for `settle`, and the keys go back to
    /// the app the person was in. It closes itself after a few seconds.
    private func showSent() {
        sent = true
        content.field.isEditable = false
        content.field.isSelectable = false
        letGoOfKeys()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeOut * Settings.shared.motionScale
            content.session.animator().alphaValue = 0.4
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.settle(into: nil) }
    }

    /// Fades out over the note drawn at `tag`, in global top-left points, which takes its place; nil
    /// fades it where it is.
    func settle(into tag: CGRect?) {
        guard !closing else { return }
        closing = true
        stopWatching()
        let popover = popover, host = host
        guard let window = content.window, Settings.shared.motionScale > 0 else {
            popover.close()
            host.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeOut * Settings.shared.motionScale
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                popover.close()
                host.orderOut(nil)
            }
        }
    }

    /// Gives the keys back to the app the person was in, now rather than when the window goes.
    private func letGoOfKeys() {
        if !wasActive, NSApp.isActive { NSApp.deactivate() }
        if let window = content.window, window.isKeyWindow { window.resignKey() }
    }

    private func stopWatching() {
        watching.forEach(NotificationCenter.default.removeObserver)
        watching = []
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            send()
            return true
        // Esc, and ⌘⌫, which in a text field deletes the line: here both delete the whole note, ink and
        // all. A click elsewhere is the way to close it and keep the ink.
        case #selector(NSResponder.cancelOperation(_:)), #selector(NSResponder.deleteToBeginningOfLine(_:)):
            dismiss()
            onDiscard?()
            return true
        case #selector(NSResponder.moveDown(_:)):
            showTargets()
            return true
        default:
            return false
        }
    }

    private func resigned() {
        guard !closing, !menuOpen, !sent else { return }
        dismiss()
        onClose?()
    }

    private static let fadeIn: TimeInterval = 0.18
    private static let fadeOut: TimeInterval = 0.16
    /// Between the target and its list, and between the list and the screen's edge, in points.
    private static let menuGap: CGFloat = 4

    /// The clear window a note's popover hangs from.
    private final class Host: NSPanel {
        let anchor = NSView()

        init(at rect: CGRect) {
            super.init(contentRect: Self.frame(rect), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            isOpaque = false
            backgroundColor = .clear
            ignoresMouseEvents = true
            level = .popUpMenu
            collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace, .ignoresCycle]
            isReleasedWhenClosed = false
            animationBehavior = .none
            contentView = anchor
        }

        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }

        func move(to rect: CGRect) { setFrame(Self.frame(rect), display: false) }

        private static func frame(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: StateReport.primaryHeight - rect.maxY, width: max(rect.width, 1), height: max(rect.height, 1))
        }
    }
}

/// What the note's popover shows: the words, then the target and the key that asks.
@MainActor
private final class NoteContent: NSView {
    let field = NSTextField()
    let session = SessionButton()
    private let key = NSTextField(labelWithString: "↩")

    static let width: CGFloat = 300
    private static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    private static let inset: CGFloat = 12
    private static let top: CGFloat = 11
    private static let belowWords: CGFloat = 4
    private static let row: CGFloat = 34
    private static let mostLines = 5
    /// Where an `NSTextField` without a border starts its words, past its frame's left edge.
    private static let fieldTextInset: CGFloat = 2
    private static var lineHeight: CGFloat { ceil(font.ascender - font.descender + font.leading) }

    /// The body with `lines` lines of words.
    static func size(lines: Int) -> CGSize {
        CGSize(width: width, height: top + CGFloat(lines) * lineHeight + belowWords + row)
    }

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: CGRect(origin: .zero, size: Self.size(lines: 1)))
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Self.font
        field.textColor = .labelColor
        field.placeholderString = LiveNotePopover.placeholder
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.cell?.usesSingleLineMode = false
        field.lineBreakMode = .byWordWrapping
        key.font = .systemFont(ofSize: 12, weight: .medium)
        key.textColor = .secondaryLabelColor
        key.toolTip = "Return asks"
        for view in [field, session, key] { addSubview(view) }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// The words' own rect, without the field's inset.
    var wordsFrame: CGRect { field.frame.insetBy(dx: Self.fieldTextInset, dy: 0) }

    /// Sizes the field to its words, from one line to `mostLines`, and itself round them.
    func layOut() {
        let fieldWidth = Self.width - Self.inset * 2 + Self.fieldTextInset * 2
        // While the field is being edited its cell still holds the words from before, so a copy of it
        // holding the editor's words measures them.
        let measuring = field.cell?.copy() as? NSTextFieldCell
        measuring?.stringValue = field.currentEditor()?.string ?? field.stringValue
        let measured = measuring?.cellSize(forBounds: CGRect(x: 0, y: 0, width: fieldWidth, height: .greatestFiniteMagnitude)).height ?? 0
        let wordsHeight = min(max(ceil(measured), Self.lineHeight), Self.lineHeight * CGFloat(Self.mostLines))
        field.frame = CGRect(x: Self.inset - Self.fieldTextInset, y: Self.top, width: fieldWidth, height: wordsHeight)
        let rowY = Self.top + wordsHeight + Self.belowWords
        session.setFrameOrigin(CGPoint(x: Self.inset - 6, y: rowY + (Self.row - SessionButton.height) / 2))
        key.sizeToFit()
        key.setFrameOrigin(CGPoint(x: Self.width - Self.inset - key.frame.width, y: rowY + (Self.row - key.frame.height) / 2))
        setFrameSize(CGSize(width: Self.width, height: rowY + Self.row))
    }
}

/// Where Return sends the note: the agent's logo, the project, and a chevron, since a click picks
/// another.
@MainActor
private final class SessionButton: NSView {
    var onClick: (() -> Void)?
    private let logo = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let chevron = NSImageView()

    static let height: CGFloat = 22
    private static let font = NSFont.systemFont(ofSize: 12, weight: .medium)
    private static let logoSize: CGFloat = 14
    private static let pad: CGFloat = 6
    private static let gap: CGFloat = 5
    private static let chevronWidth: CGFloat = 8
    /// The widest a project's name is shown; past it the name is cut in the middle.
    private static let longestLabel: CGFloat = 180

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 60, height: Self.height))
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        logo.imageScaling = .scaleProportionallyUpOrDown
        label.font = Self.font
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
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07).cgColor
    }

    /// Shows `title` after `image`, and fits itself round them.
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

    /// A press anywhere on it is its own, not its label's or its logo's.
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The list opens a turn after the press: opened inside it, the menu closed at once (measured).
    override func mouseDown(with event: NSEvent) {
        DispatchQueue.main.async { [weak self] in self?.onClick?() }
    }
}
