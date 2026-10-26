import AppKit

/// Where the person types what they ask about their live ink: a popover hung from the newest ink no
/// ask has been about, opened when they let go of the chord after drawing. There is one note for all
/// of that ink, and it stays while the ink does. Drawing more moves it, words, target and caret, to
/// hang from the newest ink (`hang`). Return asks, with or without words; Esc closes it and takes back
/// its ink. A click anywhere else takes the keys and leaves the note where it hangs, inactive
/// (`showsKeys`); a click on it, or the chord, gives them back. Once asked, the person's words are
/// drawn as their note in its place (`settle`).
///
/// It hangs from a view of the overlay its ink is drawn on (`LiveMarksLayer.hang`), as a reply does, so
/// it moves with its ink's window, the windows in front of that window cover it, and it fades as its
/// ink fades (`follow`).
///
/// Under the words, the target: the one picked last, else the responder (`DestinationChoice`
/// decides), which answers on the screen, with the working sessions listed after it
/// (docs/live-ink-integration-2026-10-04.md, decision 7). A click on it or the Down arrow opens the
/// list.
///
/// A popover's window is a non-activating panel, so its field takes the keys while the app the person
/// was in stays frontmost. AppKit still counts Vignette as active while the field has them, and a press
/// with Control held, as the chord's is, makes Vignette frontmost, so closing hands them back through
/// `FocusReturn` at once (`letGoOfKeys`) rather than when AppKit's fade ends.
@MainActor
final class LiveNotePopover: NSObject, NSTextFieldDelegate {
    enum Target: Equatable {
        /// Claude, kept running by Vignette, which draws its answer on the screen.
        case responder
        /// A working session, through Send. Its answer is drawn beside the ink when it comes.
        case session(AgentDestination)

        var session: AgentDestination? {
            if case .session(let destination) = self { return destination }
            return nil
        }
    }

    /// The words typed, trimmed, and the target, when the person presses Return.
    var onAsk: ((String, Target) -> Void)?
    /// The note has the keys again, after a click elsewhere took them.
    var onKeysBack: (() -> Void)?
    /// Esc, when the hotkey did not take it first: live ink decides what it does (`LiveEscape`).
    var onEscape: (() -> Void)?
    /// The person typed in the note, which takes over from what they say.
    var onTyped: (() -> Void)?
    private(set) var target: Target
    /// The note's own pick, which each session list resolves: the session picked last until the
    /// person picks by hand, then their pick. Only the person changes it: a hand-picked session missing
    /// from a list shows the responder, and comes back when a later list has it.
    private var ownPick: DestinationChoice.LiveNotePick

    private let popover = NSPopover()
    /// The overlay's view it hangs from, and where in it, once hung.
    private weak var host: NSView?
    private var hungAt: CGRect = .zero
    private lazy var slide = PopoverSlide(popover)
    private let content = NoteContent()
    private var place: PopoverPlace
    /// How strongly its ink shows: 0 while the ink is hidden with its window.
    private var inkOpacity: CGFloat = 1
    /// Where the caret was when the note lost the keys, which it takes back with them.
    private var caret: NSRange?
    private var sessions: [AgentDestination] = []
    private var closing = false
    /// Waiting to look as the conversation does before handing over to it, which `fadeAway` can stop.
    private var handingOver = false
    private var revealed = false
    /// Sent: the words stay, the keys are let go, and only the handover or `fadeAway` closes it.
    private var sent = false
    /// The target's menu is up. It takes the keys while it is, and `popUp` returns when it closes.
    private(set) var menuOpen = false
    /// Listening to the person, which the empty note says.
    private var listening = false
    private var watching: [NSObjectProtocol] = []

    /// For `SendContext.menu`: when the note opened, and the menu's picks.
    private var openedAt: CFTimeInterval
    private let menuPicks = MenuPickLog(surface: "note")

    static let askPlaceholder = "Ask about this"
    static let sendPlaceholder = "Send to session"
    static let listeningPlaceholder = "Listening…"

    /// The body at the height it is placed for, three lines of words, so it can grow without covering
    /// what it was placed clear of.
    static var placementSize: CGSize { NoteLayout.size(lines: 3) }

    /// A note for `place`, in global top-left points, which shows once hung (`hang`): out of sight until
    /// `reveal`, but with the keys, so what the person types meanwhile is in it when it shows.
    init(at place: PopoverPlace, target: Target) {
        openedAt = CACurrentMediaTime()
        self.place = place
        self.target = target
        ownPick = .remembered(target.session)
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
    }

    /// Hangs it from `rect` in `host`, which is `place` on the screen. The first time, it opens there
    /// with the keys. After that, a new place slides it there on a spring, and the same place with its
    /// layer moved in the window puts it there at once. Into another window, or onto another edge, it
    /// fades out and back in, since AppKit moves a popover shown again in one frame.
    func hang(from host: NSView, at rect: CGRect, place: PopoverPlace) {
        guard !closing else { return }
        let moved = place != self.place
        let edge = place.edge != self.place.edge
        self.place = place
        hungAt = rect
        guard let shown = self.host, popover.isShown else { return open(from: host) }
        let motion = Settings.shared.motionScale
        if shown !== host || edge {
            slide.stop()
            guard revealed, motion > 0, let window = content.window else { return show(from: host) }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeOut * motion
                window.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.closing else { return }
                    self.show(from: self.host ?? host)
                    self.fade(over: Self.fadeIn * motion)
                }
            }
            self.host = host
        } else if moved, revealed, motion > 0 {
            slide.slide(to: rect, duration: Self.slideDuration * motion)
        } else if !slide.isSliding, popover.positioningRect != rect {
            popover.positioningRect = rect
        }
    }

    /// Shows it at `hungAt` in `host`, keeping the keys and the caret when it is up already.
    private func show(from host: NSView) {
        self.host = host
        popover.show(relativeTo: hungAt, of: host, preferredEdge: place.edge.rectEdge(flipped: host.isFlipped))
    }

    /// Opens it out of sight, with the keys, or without them when it comes back with its ink.
    private func open(from host: NSView, takingKeys: Bool = true) {
        show(from: host)
        guard let window = content.window else { return }
        window.alphaValue = 0
        if takingKeys {
            window.makeKey()
            window.makeFirstResponder(content.field)
            restoreCaret()
        }
        stopWatching()
        watching.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resigned() }
        })
        watching.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.becameKey() }
        })
    }

    /// Fades to how strongly its ink shows, `opacity`, over `duration`, as the ink fades with its window.
    /// Hidden, it lets go of the keys. AppKit closes a popover whose window went with its own, so one
    /// that shows again is shown again where it hung.
    func follow(_ opacity: CGFloat, duration: CFTimeInterval) {
        guard !closing, opacity != inkOpacity else { return }
        inkOpacity = opacity
        if opacity > 0, revealed, !popover.isShown, let host { open(from: host, takingKeys: false) }
        if opacity == 0, hasKeys { letGoOfKeys() }
        fade(over: duration)
    }

    /// Fades the window to what it should show, over `duration`.
    private func fade(over duration: CFTimeInterval) {
        guard let window = content.window else { return }
        let alpha = revealed ? inkOpacity : 0
        guard duration > 0 else { window.alphaValue = alpha; return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: alpha > window.alphaValue ? .easeOut : .easeIn)
            window.animator().alphaValue = alpha
        }
    }

    /// How many working sessions it lists after the responder.
    var sessionCount: Int { sessions.count }

    /// The field has the keys.
    var hasKeys: Bool { content.window?.isKeyWindow == true }

    /// Up for Esc to discard: it has the keys, or shows. Not while hidden with its ink.
    var isUp: Bool { !closing && !sent && (hasKeys || revealed && inkOpacity > 0 && popover.isShown) }

    /// Shows where it hangs, with its ink.
    var isShown: Bool { !closing && revealed && inkOpacity > 0 && popover.isShown }

    /// Takes the keys back, with the caret where it was, as a click on it does.
    func takeKeys() {
        guard !closing, !sent, popover.isShown, let window = content.window else { return }
        window.makeKey()
        if window.firstResponder !== content.field.currentEditor() {
            window.makeFirstResponder(content.field)
            restoreCaret()
        }
    }

    private func restoreCaret() {
        let end = NSRange(location: (content.field.stringValue as NSString).length, length: 0)
        content.field.currentEditor()?.selectedRange = caret ?? end
    }

    /// The working sessions to offer after the responder. The list can arrive in several answers, a
    /// kept one and fresh ones; `DestinationChoice` says which target each one starts the note on.
    func setSessions(_ candidates: DestinationChoice.Candidates) {
        let answer = DestinationChoice.choose(candidates, for: .liveNote(ownPick))
        sessions = answer.list
        let found: Target = answer.pick.map(Target.session) ?? .responder
        guard found != target else { return }
        show(found)
    }

    /// Fades out without a word to the callbacks. The keys go back only when it had them: inactive, the
    /// person is in another app by now.
    func dismiss() {
        guard !closing else { return }
        let keyed = hasKeys
        fadeAway()
        if keyed { letGoOfKeys() }
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

    /// The rect it hangs from now, in global top-left points: it moves with its ink's window.
    private var hungFrom: CGRect? {
        guard let host, let window = host.window else { return nil }
        return StateReport.flipped(window.convertToScreen(host.convert(popover.positioningRect, to: nil)))
    }

    /// Shows the note where it hangs, fading in.
    func reveal() {
        guard !revealed, !closing, content.window != nil else { return }
        revealed = true
        fade(over: Self.fadeIn * Settings.shared.motionScale)
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
            let row = SessionMenu.row(of: destination, among: sessions)
            content.session.show(logo: Agent.logo(for: destination.client.rawValue), title: row.title)
            content.session.toolTip = row.tooltip
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
        responder.image = SessionMenu.logo(for: .claude)
        responder.state = target == .responder ? .on : .off
        responder.target = self
        menu.addItem(responder)
        var search: SessionMenuSearch?
        if !sessions.isEmpty {
            menu.addItem(.separator())
            search = SessionMenu.add(SessionMenu.menu(sessions, destination: target.session), to: menu, make: sessionItem)
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
        menuPicks.run(openedAt: openedAt) {
            withExtendedLifetime(search) { _ = menu.popUp(positioning: nil, at: point, in: nil) }
        }
        menuOpen = false
        guard !closing else { return }
        window.makeKey()
        window.makeFirstResponder(content.field)
        // Making the field first responder selects its words; the caret goes back to their end.
        content.field.currentEditor()?.selectedRange = NSRange(location: (content.field.stringValue as NSString).length, length: 0)
    }

    private func sessionItem(_ row: SessionMenu.Row) -> NSMenuItem {
        let item = SessionMenu.item(for: row, selected: target.session?.id == row.id)
        item.action = #selector(pickTarget(_:))
        item.target = self
        item.representedObject = row.destination
        return item
    }

    /// The sessions Tab steps through after the responder, in the menu's order. The submenu's are
    /// left out: Tab goes through a short list.
    private var menuSessions: [AgentDestination] {
        sessions.isEmpty ? [] : SessionMenu.menu(sessions, destination: target.session).topRows.map(\.destination)
    }

    /// Tab, or Shift+Tab with `backward`: the target after this one in the menu's order, or the one
    /// before, round from either end.
    private func step(backward: Bool) {
        let order: [Target] = [.responder] + menuSessions.map { .session($0) }
        guard order.count > 1 else { return }
        // By id, since a session's other fields change as its list is read again.
        let index = order.firstIndex { $0.session?.id == target.session?.id } ?? 0
        pick(order[(index + (backward ? order.count - 1 : 1)) % order.count])
    }

    @objc private func pickTarget(_ item: NSMenuItem) {
        menuPicks.record()
        // The destination travels with the item, so a session that ended while the menu was open is
        // still the target and the send says it ended, rather than falling back to the responder.
        if let picked = item.representedObject as? AgentDestination {
            pick(.session(sessions.first { $0.id == picked.id } ?? picked))
        } else {
            pick(.responder)
        }
    }

    private func pick(_ target: Target) {
        show(target)
        ownPick = .byHand(target.session)
        Log.write("[live-ink] note target \(target == .responder ? "responder" : "session")")
    }

    private func show(_ target: Target) {
        self.target = target
        showTarget()
        refit()
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
        shown.at = hungFrom ?? place.at
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
        slide.stop()
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
        slide.stop()
        let popover = popover
        let duration = duration ?? Self.fadeOut * Settings.shared.motionScale
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [content] in
            guard let window = content.window, duration > 0, window.alphaValue > 0 else {
                popover.close()
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                window.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated { popover.close() }
            }
        }
    }

    /// Lays the thinking light round the body, starting under the arrow.
    private func placeLight() {
        guard let body = globalFrame else { return }
        let dark = content.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        content.light.place(content.bounds, start: RimLight.start(of: body, hungFrom: hungFrom ?? place.at, edge: place.edge), dark: dark)
    }

    /// Gives the keys back to where the person was, now rather than when the window goes.
    private func letGoOfKeys() {
        FocusReturn.shared.restore(reason: "live ink note")
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
        case #selector(NSResponder.cancelOperation(_:)):
            onEscape?()
            return true
        case #selector(NSResponder.moveDown(_:)):
            showTargets()
            return true
        case #selector(NSResponder.insertTab(_:)):
            step(backward: false)
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            step(backward: true)
            return true
        default:
            return false
        }
    }

    /// A click elsewhere took the keys: the note stays where it hangs, inactive, with its words, its
    /// target and the caret's place. The keys go back to the app the person was in only while Vignette
    /// is still the active app (`FocusReturn`), as when the click landed on nothing.
    private func resigned() {
        guard !closing, !menuOpen, !sent else { return }
        caret = content.field.currentEditor()?.selectedRange
        showsKeys(false)
        FocusReturn.shared.restore(reason: "live ink note")
        Log.write("[live-ink] note let go of the keys")
    }

    private func becameKey() {
        guard !closing, !sent, !menuOpen else { return }
        showsKeys(true)
        Log.write("[live-ink] note has the keys")
        onKeysBack?()
    }

    private var keyed = true

    /// Inactive, the popover's glass draws as macOS draws a window that is not key, the caret goes, the
    /// words dim and the ↩ fades, since Return does nothing until the note has the keys again.
    private func showsKeys(_ keys: Bool) {
        guard keys != keyed else { return }
        keyed = keys
        content.showsKeys(keys, duration: Self.focusFade * Settings.shared.motionScale)
    }

    private static let fadeIn: TimeInterval = 0.18
    private static let fadeOut: TimeInterval = 0.16
    /// How long the words and the ↩ take to dim or come back as the note loses or takes the keys.
    private static let focusFade: TimeInterval = 0.18
    /// How long it takes to move to hang from newer ink, at full motion: as long as a reply moving to
    /// its next stop.
    private static let slideDuration: CFTimeInterval = ReplyPopover.slideDuration
    /// How long the target takes to settle into a name once sent, at full motion.
    private static let settleDuration: TimeInterval = 0.18
    private let removal = WindowRemoval()
    /// Between the target and its list, and between the list and the screen's edge, in points.
    private static let menuGap: CGFloat = 4
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

/// The note's field, blended with the popover's glass as a label is. AppKit leaves an editable field
/// out of vibrancy, so its placeholder drew as a flat grey that turned muddy over a light window.
private final class VibrantField: NSTextField {
    override var allowsVibrancy: Bool { true }
}

/// What the note's popover shows: the words, then the target and the key that asks.
@MainActor
private final class NoteContent: NSView {
    let field = VibrantField()
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

    /// Words at full strength and the ↩ shown while the note has the keys, dimmed and faded while it
    /// does not, over `duration`.
    func showsKeys(_ keys: Bool, duration: CFTimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            field.animator().alphaValue = keys ? 1 : Self.inactiveWords
            key.animator().alphaValue = keys ? 1 : 0
        }
    }

    /// How strongly the words show while the note does not have the keys.
    private static let inactiveWords: CGFloat = 0.55

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
