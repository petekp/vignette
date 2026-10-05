import AppKit

/// Where the person types what they ask about their live ink: a pill in their colour beside the newest
/// ink, opened when they let go of the chord after drawing. Return asks, with or without words; Esc,
/// or a click anywhere else, closes it and keeps the ink.
///
/// The target at its right end starts on the responder, which answers on the screen, and lists the
/// working sessions after it (docs/live-ink-integration-2026-10-04.md, decision 7). A click on it or
/// the Down arrow opens the list.
///
/// A non-activating panel that takes the keys while it is up, as the stack's does, so the app the
/// person was in stays frontmost and gets the keys back when it closes.
@MainActor
final class LiveNotePanel: NSPanel, NSTextFieldDelegate {
    enum Target: Equatable {
        /// Claude, kept running by Vignette, which draws its answer on the screen.
        case responder
        /// A working session, through today's Send. Its reply comes back as a card.
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
    private(set) var target: Target = .responder

    private let field = NSTextField()
    private let pill = NSView()
    private let targetButton = NSButton()
    private let font: NSFont
    private let targetFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    private var sessions: [AgentDestination] = []
    private var closing = false
    /// The target's menu is up. It takes the keys while it is, and `popUp` returns when it closes.
    private var menuOpen = false

    static let placeholder = "Ask about this"
    /// The pill's height, side padding, and widths, in points.
    private static let height: CGFloat = 34
    private static let inset: CGFloat = 15
    private static let minField: CGFloat = 140
    private static let maxWidth: CGFloat = 520

    /// Opens beside `ink`, in global top-left points, on the screen that holds it.
    init(beside ink: CGRect, style: TextStyle, color: CGColor, edge: CGColor) {
        font = CTFontCreateCopyWithAttributes(style.person.font(size: 15), 15, nil, nil) as NSFont
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
        pill.layer?.backgroundColor = color
        pill.layer?.borderColor = edge
        pill.layer?.borderWidth = 1.5
        pill.layer?.cornerRadius = Self.height / 2
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
        targetButton.isBordered = false
        targetButton.target = self
        targetButton.action = #selector(showTargets)
        targetButton.refusesFirstResponder = true
        targetButton.imagePosition = .imageLeading
        pill.addSubview(field)
        pill.addSubview(targetButton)
        contentView = pill
        showTarget()

        place(beside: ink)
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
    func setSessions(_ list: [AgentDestination]) {
        sessions = list
        if case .session(let picked) = target, !list.contains(where: { $0.id == picked.id }) { pick(.responder) }
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

    private var targetWidth: CGFloat { ceil(targetButton.intrinsicContentSize.width) }

    private var fittedWidth: CGFloat {
        let shown = field.stringValue.isEmpty ? Self.placeholder : field.stringValue
        let text = max(ceil((shown as NSString).size(withAttributes: [.font: font]).width) + 6, Self.minField)
        return min(text + Self.inset * 2 + 10 + targetWidth, Self.maxWidth)
    }

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
        var y = centre.y - Self.height / 2
        y = min(max(y, visible.minY + 8), visible.maxY - 8 - Self.height)
        setFrame(CGRect(x: x, y: y, width: width, height: Self.height), display: true)
        layoutContent()
    }

    /// Grows or shrinks to fit, keeping the edge nearest the ink: its left edge, unless it sits left
    /// of the ink against the screen's right.
    private func refit() {
        let width = fittedWidth
        guard abs(width - frame.width) > 0.5 else { return }
        var rect = frame
        if rect.maxX + (width - rect.width) > (screen?.visibleFrame.maxX ?? .greatestFiniteMagnitude) - 8 { rect.origin.x -= width - rect.width }
        rect.size.width = width
        setFrame(rect, display: true)
        layoutContent()
    }

    private func layoutContent() {
        let height = field.intrinsicContentSize.height
        let button = targetWidth
        targetButton.frame = CGRect(x: frame.width - Self.inset - button, y: (Self.height - 20) / 2, width: button, height: 20)
        field.frame = CGRect(x: Self.inset, y: (Self.height - height) / 2, width: frame.width - Self.inset * 2 - button - 10, height: height)
    }

    private func showTarget() {
        let title = NSAttributedString(string: "to \(target.label) ▾", attributes: [
            .font: targetFont, .foregroundColor: NSColor.white.withAlphaComponent(0.85),
        ])
        targetButton.attributedTitle = title
        targetButton.toolTip = target == .responder ? "Claude answers on the screen." : "The session's reply comes back as a card."
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
        menu.popUp(positioning: nil, at: CGPoint(x: targetButton.frame.minX, y: -4), in: pill)
        menuOpen = false
        if !closing {
            makeKey()
            makeFirstResponder(field)
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
        self.target = target
        showTarget()
        refit()
        Log.write("[live-ink] note target \(target == .responder ? "responder" : "session")")
    }

    private static func menuSized(_ image: NSImage) -> NSImage {
        let copy = image.copy() as! NSImage
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }

    // MARK: Keys

    func controlTextDidChange(_ notification: Notification) { refit() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            let words = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let target = target
            dismiss()
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
        guard !closing, !menuOpen else { return }
        dismiss()
        onClose?()
    }
}
