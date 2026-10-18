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
    /// Waiting to look as the conversation does before handing over to it, which `fadeAway` can stop.
    private var handingOver = false
    private var revealed = false
    /// Sent: the words stay, the keys are let go, and only the handover or `fadeAway` closes it.
    private var sent = false
    /// The target's menu is up. It takes the keys while it is, and `popUp` returns when it closes.
    private var menuOpen = false
    /// Listening to the person, which the empty note says.
    private var listening = false
    /// Whether Vignette was the active app before the note took the keys, so closing gives them back
    /// only to another app.
    private let wasActive: Bool
    private var watching: [NSObjectProtocol] = []

    static let askPlaceholder = "Ask about this"
    static let sendPlaceholder = "Send to session"
    static let listeningPlaceholder = "Listening…"

    /// The body at the height it is placed for, three lines of words, so it can grow without covering
    /// what it was placed clear of.
    static var placementSize: CGSize { NoteLayout.size(lines: 3) }

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
        popover.show(relativeTo: host.spot, of: host.anchor, preferredEdge: place.edge.rectEdge())
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
        return StateReport.flipped(window.convertToScreen(content.convert(content.bounds, to: nil)))
    }

    /// The words, in global top-left points: where the drawn note's tag goes once they are asked.
    var tagFrame: CGRect? {
        guard let window = content.window else { return nil }
        return StateReport.flipped(window.convertToScreen(content.convert(content.wordsFrame, to: nil)))
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
            popover.show(relativeTo: host.spot, of: host.anchor, preferredEdge: place.edge.rectEdge())
        } else {
            popover.positioningRect = host.spot
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
        showPlaceholder()
    }

    /// What the empty note says: that it is listening, else what Return does with its target.
    private func showPlaceholder() {
        content.field.placeholderString = listening ? Self.listeningPlaceholder
            : target == .responder ? Self.askPlaceholder : Self.sendPlaceholder
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
        self.listening = listening
        showPlaceholder()
    }

    /// Asks as Return does.
    func send() {
        guard !sent, !closing else { return }
        let words = content.field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = target
        if words.isEmpty { dismiss() } else { showSent() }
        onAsk?(words, target)
    }

    /// Sent: the words stay, the target settles into the name the conversation's row shows, the key
    /// that asks fades, and the thinking light runs round the rim while the ask is handed on. The keys
    /// go back to the app the person was in. Only `handOver` or `fadeAway` closes it.
    private func showSent() {
        sent = true
        content.field.isEditable = false
        content.field.isSelectable = false
        letGoOfKeys()
        content.settle(duration: Self.settleDuration * Settings.shared.motionScale)
        placeLight()
        content.light.think(true)
        settledAt = CACurrentMediaTime() + Self.settleDuration * Settings.shared.motionScale
    }

    /// When the target has settled, so the note looks as the conversation that takes its place does.
    private var settledAt: CFTimeInterval = 0

    /// Where it hangs now, with its body where AppKit put it, in global top-left points.
    var shownPlace: PopoverPlace? {
        guard let body = globalFrame else { return nil }
        var shown = place
        shown.body = body
        return shown
    }

    /// Hands over to the conversation that takes its place: `ready` runs once the note looks as the
    /// conversation will, and shows it there; the note goes a few display refreshes later, once the
    /// conversation is on the screen, with no fade, since the two look the same.
    func handOver(when ready: @escaping () -> Void) {
        guard !closing else { return ready() }
        closing = true
        handingOver = true
        stopWatching()
        let wait = max(settledAt - CACurrentMediaTime(), 0)
        // Held until it is gone, whoever lets go of it meanwhile.
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [self] in
            guard handingOver else { return }
            handingOver = false
            ready()
            // In the commit that shows the conversation, since the two glasses over each other darken
            // the note for the frame they share. The window goes once the display has shown that.
            content.window?.alphaValue = 0
            removal.start(on: content.window?.screen) { [self] in
                popover.close()
                host.orderOut(nil)
            }
        }
    }

    /// Fades out where it is, with nothing to take its place, after `delay` and over `duration`, or
    /// over its own short fade. A handover still waiting for the note to settle is called off.
    func fadeAway(after delay: CFTimeInterval = 0, over duration: CFTimeInterval? = nil) {
        guard !closing || handingOver else { return }
        closing = true
        handingOver = false
        stopWatching()
        let popover = popover, host = host
        let duration = duration ?? Self.fadeOut * Settings.shared.motionScale
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [content] in
            guard let window = content.window, duration > 0 else {
                popover.close()
                host.orderOut(nil)
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                window.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated {
                    popover.close()
                    host.orderOut(nil)
                }
            }
        }
    }

    /// Lays the thinking light round the body, starting under the arrow.
    private func placeLight() {
        guard let body = globalFrame else { return }
        let dark = content.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        content.light.place(content.bounds, start: RimLight.start(of: body, hungFrom: place.at, edge: place.edge), dark: dark)
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
    /// How long the target takes to settle into a name once sent, at full motion.
    private static let settleDuration: TimeInterval = 0.18
    private let removal = WindowRemoval()
    /// Between the target and its list, and between the list and the screen's edge, in points.
    private static let menuGap: CGFloat = 4

    /// The clear window a note's popover hangs from, a little bigger than the rect it hangs from and
    /// on whole points, with that rect, `spot`, inside it: a window's frame is rounded, and a popover
    /// hung from a window one point wide sat a point off the conversation hung from the same rect.
    private final class Host: NSPanel {
        let anchor = NSView()
        private(set) var spot: CGRect = .zero

        init(at rect: CGRect) {
            super.init(contentRect: Self.frame(rect), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            spot = Self.spot(rect, in: frame)
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

        func move(to rect: CGRect) {
            setFrame(Self.frame(rect), display: false)
            spot = Self.spot(rect, in: frame)
        }

        private static func frame(_ rect: CGRect) -> CGRect { StateReport.flipped(rect).insetBy(dx: -4, dy: -4).integral }

        /// `rect` in the coordinates of a window whose frame is `frame`.
        private static func spot(_ rect: CGRect, in frame: CGRect) -> CGRect {
            StateReport.flipped(rect).offsetBy(dx: -frame.minX, dy: -frame.minY)
        }
    }
}

/// What the note and the conversation that takes its place share, so the one hands over to the
/// other without a seam: the width, the words' font and place, and the row under them.
enum NoteLayout {
    static let width: CGFloat = 300
    static let inset: CGFloat = 12
    static let top: CGFloat = 11
    static let belowWords: CGFloat = 4
    static let row: CGFloat = 34
    static let mostLines = 5
    /// Where an `NSTextField` without a border starts its words, past its frame's left edge: its text
    /// container's line fragment padding.
    static let fieldTextInset: CGFloat = 2
    static var font: NSFont { .systemFont(ofSize: NSFont.systemFontSize) }
    static var lineHeight: CGFloat { ceil(font.ascender - font.descender + font.leading) }
    /// How wide the words wrap.
    static var wordsWidth: CGFloat { width - inset * 2 }
    static var fieldWidth: CGFloat { wordsWidth + fieldTextInset * 2 }

    /// The note's body with `lines` lines of words.
    static func size(lines: Int) -> CGSize {
        CGSize(width: width, height: top + CGFloat(lines) * lineHeight + belowWords + row)
    }

    /// The height of `text`'s lines wrapped as the field wraps them, from one line to `mostLines`.
    static func wordsHeight(_ text: String) -> CGFloat {
        let measured = NSAttributedString(string: text, attributes: [.font: font])
            .boundingRect(with: CGSize(width: wordsWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
        return min(max(ceil(measured.height), lineHeight), lineHeight * CGFloat(mostLines))
    }

    /// The field's frame for words `height` high, in a flipped view.
    static func fieldFrame(height: CGFloat) -> CGRect {
        CGRect(x: inset - fieldTextInset, y: top, width: fieldWidth, height: height)
    }

    /// Sets `field` up to show the person's words as the note does.
    @MainActor
    static func configure(_ field: NSTextField) {
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = font
        field.textColor = .labelColor
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.cell?.usesSingleLineMode = false
        field.lineBreakMode = .byWordWrapping
    }

    /// The row's target: its logo, `logoSize` square, `inset` from the left, then its name, `gap`
    /// after it, in `labelFont`.
    static let logoSize: CGFloat = 14
    static let gap: CGFloat = 5
    static var labelFont: NSFont { .systemFont(ofSize: 12, weight: .medium) }
    /// The target button's height, centred in the row.
    static let buttonHeight: CGFloat = 22
    /// The widest a target's name is shown; past it the name is cut in the middle.
    private static let longestLabel: CGFloat = 180

    /// The width a label of `title` takes in the row, cut at `longestLabel`. A label's cell draws its
    /// words a couple of points in from each side.
    static func labelWidth(_ title: String) -> CGFloat {
        min(ceil((title as NSString).size(withAttributes: [.font: labelFont]).width) + 4, longestLabel)
    }
}

/// What the note's popover shows: the words, then the target and the key that asks.
@MainActor
private final class NoteContent: NSView {
    let field = NSTextField()
    let session = SessionButton()
    private let key = NSTextField(labelWithString: "↩")
    let light = RimLight()

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: CGRect(origin: .zero, size: NoteLayout.size(lines: 1)))
        NoteLayout.configure(field)
        key.font = NoteLayout.labelFont
        key.textColor = .secondaryLabelColor
        key.toolTip = "Return asks"
        for view in [field, session, key] { addSubview(view) }
        wantsLayer = true
        layer?.addSublayer(light)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// The words' own rect, without the field's inset.
    var wordsFrame: CGRect { field.frame.insetBy(dx: NoteLayout.fieldTextInset, dy: 0) }

    /// Sizes the field to its words, from one line to `mostLines`, and itself round them.
    func layOut() {
        let words = NoteLayout.wordsHeight(field.currentEditor()?.string ?? field.stringValue)
        field.frame = NoteLayout.fieldFrame(height: words)
        let rowY = NoteLayout.top + words + NoteLayout.belowWords
        session.setFrameOrigin(CGPoint(x: NoteLayout.inset - SessionButton.pad, y: rowY + (NoteLayout.row - SessionButton.height) / 2))
        key.sizeToFit()
        key.setFrameOrigin(CGPoint(x: NoteLayout.width - NoteLayout.inset - key.frame.width, y: rowY + (NoteLayout.row - key.frame.height) / 2))
        setFrameSize(CGSize(width: NoteLayout.width, height: rowY + NoteLayout.row))
    }

    /// Sent: the target settles into the row the conversation shows, a name rather than a button, and
    /// the key that asks fades, over `duration`.
    func settle(duration: CFTimeInterval) {
        session.settle(duration: duration)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            key.animator().alphaValue = 0
        }
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

    static let height = NoteLayout.buttonHeight
    /// How far the logo sits inside the button's edge, in points.
    static let pad: CGFloat = 6
    private static let chevronWidth: CGFloat = 8
    private var settled = false

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 60, height: Self.height))
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        logo.imageScaling = .scaleProportionallyUpOrDown
        label.font = NoteLayout.labelFont
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
        layer?.backgroundColor = settled ? nil : NSColor.labelColor.withAlphaComponent(0.07).cgColor
    }

    /// Shows `title` after `image`, and fits itself round them.
    func show(logo image: NSImage?, title: String) {
        logo.image = image
        label.stringValue = title
        let words = NoteLayout.labelWidth(title)
        var x = Self.pad
        logo.frame = CGRect(x: x, y: (Self.height - NoteLayout.logoSize) / 2, width: NoteLayout.logoSize, height: NoteLayout.logoSize)
        x += NoteLayout.logoSize + NoteLayout.gap
        let lineHeight = ceil(label.intrinsicContentSize.height)
        label.frame = CGRect(x: x, y: (Self.height - lineHeight) / 2, width: words, height: lineHeight)
        x += words + NoteLayout.gap
        chevron.frame = CGRect(x: x, y: 0, width: Self.chevronWidth, height: Self.height)
        setFrameSize(CGSize(width: x + Self.chevronWidth + Self.pad, height: Self.height))
    }

    /// Sent: it settles into a name, as the conversation's row shows it, over `duration`. Its
    /// background and chevron fade and its name greys; it takes no more clicks.
    func settle(duration: CFTimeInterval) {
        guard !settled else { return }
        settled = true
        let background = layer?.backgroundColor
        layer?.backgroundColor = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            chevron.animator().alphaValue = 0
        }
        guard duration > 0 else { label.textColor = .secondaryLabelColor; return }
        if let background {
            let fade = CABasicAnimation(keyPath: "backgroundColor")
            fade.fromValue = background
            fade.toValue = CGColor(gray: 0, alpha: 0)
            fade.duration = duration
            layer?.add(fade, forKey: "settle")
        }
        label.wantsLayer = true
        let fade = CATransition()
        fade.type = .fade
        fade.duration = duration
        label.layer?.add(fade, forKey: "settle")
        label.textColor = .secondaryLabelColor
    }

    /// A press anywhere on it is its own, not its label's or its logo's.
    override func hitTest(_ point: NSPoint) -> NSView? { !settled && frame.contains(point) ? self : nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The list opens a turn after the press: opened inside it, the menu closed at once (measured).
    override func mouseDown(with event: NSEvent) {
        DispatchQueue.main.async { [weak self] in self?.onClick?() }
    }
}
