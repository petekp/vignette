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
/// ink fades (`follow`). While the stack or the annotator holds the screen it hides, and it comes back
/// as it was once they are gone (`standAside`).
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

    /// The words typed, trimmed, the target, and the title a card sent to it shows, when the person
    /// presses Return.
    var onAsk: ((String, Target, _ title: String) -> Void)?
    /// The note has the keys again, after a click elsewhere took them.
    var onKeysBack: (() -> Void)?
    /// Esc, when the hotkey did not take it first: live ink decides what it does (`LiveEscape`).
    var onEscape: (() -> Void)?
    /// The person typed in the note, which takes over from what they say.
    var onTyped: (() -> Void)?
    private(set) var target: Target
    /// Why Claude cannot answer, or nil when it can. A note aimed at Claude says why in place of its
    /// prompt, and Claude's row in the target menu says why and cannot be picked.
    var responderProblem: String? {
        didSet { if responderProblem != oldValue { showPlaceholder() } }
    }
    /// Why speech cannot listen, or nil when it can. The empty note says so in place of its prompt.
    var speechProblem: String? {
        didSet { if speechProblem != oldValue { showPlaceholder() } }
    }
    /// The title a card sent to the target shows, as the target is shown now (`SessionMenu.cardTitle`).
    private var targetTitle = ""
    /// The note's own pick, which each session list resolves: the session picked last until the
    /// person picks by hand, then their pick. Only the person changes it: a hand-picked session missing
    /// from a list shows the responder, and comes back when a later list has it.
    private var ownPick: DestinationChoice.LiveNotePick

    /// Out of sight until `reveal`.
    private let hanging = HangingPopover(reshow: .fadingThrough, alpha: 0)
    private var popover: NSPopover { hanging.popover }
    private let content = NoteContent()
    private var place: PopoverPlace
    /// How strongly its ink shows: 0 while the ink is hidden with its window.
    private var inkOpacity: CGFloat = 1
    /// Hidden while the stack or the annotator holds the screen.
    private(set) var standsAside = false
    private var opacity: CGFloat { standsAside ? 0 : inkOpacity }
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
    private var watching: [NSObjectProtocol] = []

    /// For `SendContext.menu`: when the note opened, and the menu's picks.
    private var openedAt: CFTimeInterval
    private let menuPicks = MenuPickLog(surface: "note")

    static let askPlaceholder = "Ask about this"
    /// Until the first ask to Claude, the prompt says what Claude sees (`SetupInkCopy.costNote`).
    static let firstAskPlaceholder = "Ask about this. Claude sees the window's picture, title and URL."
    static let sendPlaceholder = "Send to session"

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
        popover.animates = false
        content.field.delegate = self
        content.session.onClick = { [weak self] in self?.showTargets() }
        showTarget()
        content.layOut()
        popover.contentSize = content.frame.size
    }

    /// Hangs it from `rect` in `host`, which is `place` on the screen. The first time, it opens there
    /// with the keys when `takingKeys`, unless it stands aside; without them, the window that had the
    /// keys keeps them. After that, a new place slides it there on a spring, and the same place with its
    /// layer moved in the window puts it there at once. Into another window, or onto another edge, it
    /// fades out and back in, since AppKit moves a popover shown again in one frame.
    func hang(from host: NSView, at rect: CGRect, place: PopoverPlace, takingKeys: Bool = true) {
        guard !closing else { return }
        self.place = place
        let key = NSApp.keyWindow
        guard hanging.hang(from: host, at: rect, place: place, animated: revealed) == .shown else { return }
        // A popover's window takes the keys as it shows, so they go back to the window that had them,
        // and its field gives up the caret, which it draws while its parent window is key.
        if !takingKeys, key !== content.window {
            content.window?.makeFirstResponder(nil)
            key?.makeKey()
        }
        // Shown again after AppKit closed it with its ink's window, it waits for a click or the chord.
        watchWindow(takingKeys: takingKeys && !opened && !standsAside)
        opened = true
    }

    private var opened = false

    /// Watches its window, each time AppKit shows it, for the keys coming and going, and takes them when
    /// `takingKeys`.
    private func watchWindow(takingKeys: Bool) {
        guard let window = content.window else { return }
        if takingKeys {
            takesKeys(window)
            window.makeFirstResponder(content.field)
            restoreCaret()
        }
        stopWatching()
        watching.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resigned() }
        })
        // Run as the window becomes key, so the press that made it key is still the current event.
        watching.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.becameKey() }
        })
    }

    /// Fades to how strongly its ink shows, `opacity`, over `duration`, as the ink fades with its window.
    /// Hidden, it lets go of the keys.
    func follow(_ opacity: CGFloat, duration: CFTimeInterval) {
        guard !closing, opacity != inkOpacity else { return }
        inkOpacity = opacity
        showOpacity(over: duration)
    }

    /// Hides it while the stack or the annotator holds the screen, letting go of the keys, or shows it
    /// again, without them, once they are gone.
    func standAside(_ aside: Bool) {
        guard !closing, aside != standsAside else { return }
        standsAside = aside
        showOpacity(over: (aside ? HangingPopover.fadeOut : HangingPopover.fadeIn) * Settings.shared.motionScale)
    }

    private func showOpacity(over duration: CFTimeInterval) {
        if opacity == 0 { letGoOfKeys() }
        fade(over: duration)
    }

    /// Fades the window to what it should show, over `duration`.
    private func fade(over duration: CFTimeInterval) {
        if hanging.fade(to: revealed ? opacity : 0, duration: duration) { watchWindow(takingKeys: false) }
    }

    /// How many working sessions it lists after the responder.
    var sessionCount: Int { sessions.count }

    /// The field has the keys.
    var hasKeys: Bool { content.window?.isKeyWindow == true }

    /// Shows where it hangs, with its ink.
    var isShown: Bool { !closing && revealed && opacity > 0 && popover.isShown }

    /// No words typed or heard.
    var isEmpty: Bool { content.field.stringValue.isEmpty }

    /// Takes the keys back, with the caret where it was, as a click on it does.
    func takeKeys() {
        guard !closing, !sent, !standsAside, popover.isShown, let window = content.window else { return }
        takesKeys(window)
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
        // The menu lists the sessions Vignette can start after the running ones (`SessionMenu.ranked`).
        sessions = answer.list + answer.startable
        // Without Claude, a note with no session picked has nothing to answer it, so it opens on the first session.
        let defaultTarget: Target = responderProblem == nil ? .responder : sessions.first.map(Target.session) ?? .responder
        let found: Target = answer.pick.map(Target.session) ?? defaultTarget
        guard found != target else { return }
        show(found)
    }

    /// Fades out without a word to the callbacks, giving the keys back when it has them.
    func dismiss() {
        guard !closing else { return }
        fadeAway()
        letGoOfKeys()
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

    /// Shows the note where it hangs, fading in.
    func reveal() {
        guard !revealed, !closing, content.window != nil else { return }
        revealed = true
        fade(over: HangingPopover.fadeIn * Settings.shared.motionScale)
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
            content.session.setAccessibilityLabel("Goes to Claude")
            targetTitle = "Claude"
        case .session(let destination):
            let row = SessionMenu.row(of: destination, among: sessions)
            content.session.show(logo: Agent.logo(for: destination.client.rawValue), title: row.title)
            content.session.toolTip = row.tooltip
            content.session.setAccessibilityLabel("Goes to \(row.title)")
            targetTitle = SessionMenu.cardTitle(of: row)
        }
        showPlaceholder()
    }

    /// What the empty note says: what Return does with its target.
    private func showPlaceholder() {
        let targetProblem = target == .responder ? responderProblem : nil
        let askedClaude = Settings.shared.data.liveInkAskedClaude
        let prompt = target == .responder ? (askedClaude ? Self.askPlaceholder : Self.firstAskPlaceholder) : Self.sendPlaceholder
        content.field.placeholderString = targetProblem ?? speechProblem ?? prompt
        refit()
    }

    /// The list of targets, under the target, or beside the note when the screen has no room below it,
    /// so it never covers the words being typed.
    private func showTargets() {
        guard let window = content.window else { return }
        let menu = NSMenu()
        // The menu enables every item whose action it can send, so Claude's row has none while it cannot answer.
        let responder = NSMenuItem(title: "Claude, on the screen", action: responderProblem == nil ? #selector(pickTarget(_:)) : nil, keyEquivalent: "")
        responder.image = SessionMenu.logo(for: .claude)
        responder.state = target == .responder ? .on : .off
        if let responderProblem {
            responder.toolTip = responderProblem
            if #available(macOS 14.4, *) { responder.subtitle = responderProblem }
        }
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
        takesKeys(window)
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
    func step(backward: Bool) {
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
    func hear(_ words: String) { put(words) }

    /// Puts `words` in the field, the caret after them.
    func put(_ words: String) {
        guard !sent, !closing else { return }
        content.field.stringValue = words
        // The caret follows the words, so typing after them adds to the end.
        (content.field.currentEditor() as? NSTextView)?.setSelectedRange(NSRange(location: (words as NSString).length, length: 0))
        refit()
    }

    /// Asks as Return does.
    func send() {
        guard !sent, !closing else { return }
        let words = content.field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let (target, title) = (target, targetTitle)
        if words.isEmpty { dismiss() } else { showSent() }
        onAsk?(words, target, title)
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
        shown.at = hanging.hungFrom ?? place.at
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
        hanging.stop()
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
    /// over its own short fade. A handover still waiting for the note to settle is called off. `gone`
    /// runs once it is off the screen.
    func fadeAway(after delay: CFTimeInterval = 0, over duration: CFTimeInterval? = nil, then gone: (() -> Void)? = nil) {
        guard !closing || handingOver else {
            gone?()
            return
        }
        closing = true
        handingOver = false
        stopWatching()
        hanging.stop()
        let popover = popover
        let duration = duration ?? HangingPopover.fadeOut * Settings.shared.motionScale
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [content] in
            guard let window = content.window, duration > 0, window.alphaValue > 0 else {
                popover.close()
                gone?()
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                window.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated {
                    popover.close()
                    gone?()
                }
            }
        }
    }

    /// Lays the thinking light round the body, starting under the arrow.
    private func placeLight() {
        guard let body = globalFrame else { return }
        let dark = content.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        content.light.place(content.bounds, start: RimLight.start(of: body, hungFrom: hanging.hungFrom ?? place.at, edge: place.edge), dark: dark)
    }

    /// Gives the keys back to where the person was, now rather than when the window goes, when it has
    /// them. Without them, the person's app has them, and nothing is taken from it. A popover's window
    /// also reads as key while its parent window is, so only the app's key window counts.
    private func letGoOfKeys() {
        guard let window = content.window, NSApp.keyWindow === window else { return }
        FocusReturn.shared.restore(reason: "live ink note")
        window.resignKey()
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
        content.showsKeys(false, duration: Self.focusFade * Settings.shared.motionScale)
        FocusReturn.shared.restore(reason: "live ink note")
        Log.write("[live-ink] note let go of the keys")
    }

    /// Makes its window key, as the note asking for the keys.
    private func takesKeys(_ window: NSWindow) {
        askedForKeys = true
        window.makeKey()
        askedForKeys = false
    }

    private var askedForKeys = false

    /// The note asked for the keys, or the person pressed on it. macOS also makes it key on its own when
    /// another window of Vignette's that had the keys closes, as the annotator's does, while the person
    /// is back in their app: it gives those keys back at once.
    private func becameKey() {
        guard !closing, !sent, !menuOpen else { return }
        let pressed = NSApp.currentEvent.map { [.leftMouseDown, .rightMouseDown].contains($0.type) && $0.window === content.window } == true
        guard askedForKeys || pressed else {
            Log.write("[live-ink] note gave back keys macOS handed it")
            letGoOfKeys()
            return
        }
        content.showsKeys(true, duration: Self.focusFade * Settings.shared.motionScale)
        Log.write("[live-ink] note has the keys")
        onKeysBack?()
    }

    /// How long the words and the ↩ take to dim or come back as the note loses or takes the keys.
    private static let focusFade: TimeInterval = 0.18
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
        field.setAccessibilityLabel("Note")
        key.setAccessibilityElement(false)
        for view in [field, session, key] { addSubview(view) }
        wantsLayer = true
        layer?.addSublayer(light)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// The words' own rect, without the field's inset.
    var wordsFrame: CGRect { field.frame.insetBy(dx: NoteLayout.fieldTextInset, dy: 0) }

    /// Sizes the field to its words, or its prompt while empty, from one line to `mostLines`, and itself round them.
    func layOut() {
        let typed = field.currentEditor()?.string ?? field.stringValue
        // Empty, the field shows its prompt, which can say why Claude cannot answer in two lines.
        let words = NoteLayout.wordsHeight(typed.isEmpty ? field.placeholderString ?? "" : typed)
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
