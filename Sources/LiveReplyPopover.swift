import AppKit

/// Where a live answer's reply hangs as a popover, in the coordinates of the marks: the rect its
/// arrow points at, the edge of that rect it hangs from, and where its body is expected. AppKit
/// places the popover itself, centred on its arrow, so `body` is the layout's estimate, which the
/// answer's other marks keep clear of (docs/live-ink-look-2026-10-07.md, plan step 6).
struct PopoverPlace: Equatable {
    enum Edge: CaseIterable {
        case below, above, right, left

        /// AppKit's edge in a view's coordinates: a flipped view's bottom is its max y.
        func rectEdge(flipped: Bool = false) -> NSRectEdge {
            switch self {
            case .below: flipped ? .maxY : .minY
            case .above: flipped ? .minY : .maxY
            case .right: .maxX
            case .left: .minX
            }
        }
    }

    /// The mark it hangs from, which it follows on its window, or nil for the person's ink.
    var anchor: Mark.ID?
    var at: CGRect
    var edge: Edge
    var body: CGRect
    /// Room kept at the foot of its body for the answer's buttons, in points: as wide as their row,
    /// which the body is never narrower than, and as tall.
    var foot: CGSize
    /// The visible screen it hangs on, in global top-left points, which AppKit keeps its window
    /// inside. Nil leaves the body centred on its arrow.
    var screen: CGRect? = nil

    /// How far a popover's window reaches past its body on every side, holding the arrow and the
    /// shadow (measured on macOS 15).
    static let windowMargin: CGFloat = 13

    func offsetBy(dx: CGFloat, dy: CGFloat) -> PopoverPlace {
        var moved = self
        moved.at = at.offsetBy(dx: dx, dy: dy)
        moved.body = body.offsetBy(dx: dx, dy: dy)
        return moved
    }

    /// A body of `size` hung from `at` on `edge`, centred on it, as AppKit centres a popover on its
    /// arrow, then slid along that edge, as AppKit slides it, until its window is on `screen`.
    static func body(_ size: CGSize, hungFrom at: CGRect, edge: Edge, on screen: CGRect?) -> CGRect {
        let gap = ReplyContent.arrowLength
        let origin: CGPoint
        switch edge {
        case .below: origin = CGPoint(x: at.midX - size.width / 2, y: at.maxY + gap)
        case .above: origin = CGPoint(x: at.midX - size.width / 2, y: at.minY - gap - size.height)
        case .right: origin = CGPoint(x: at.maxX + gap, y: at.midY - size.height / 2)
        case .left: origin = CGPoint(x: at.minX - gap - size.width, y: at.midY - size.height / 2)
        }
        var body = CGRect(origin: origin, size: size)
        guard let room = screen?.insetBy(dx: windowMargin, dy: windowMargin) else { return body }
        switch edge {
        case .below, .above: body.origin.x = min(max(body.minX, room.minX), room.maxX - size.width)
        case .right, .left: body.origin.y = min(max(body.minY, room.minY), room.maxY - size.height)
        }
        return body
    }
}

/// What a reply's popover shows, as a conversation that carries on in the note the person typed in:
/// their question where they typed it, then who answers, in the row where the note's target was, then
/// the answer's words. The note hands over to it unseen, so the two share `NoteLayout`. Measured here
/// without a view, so the layout knows the body's size, and drawn by `ReplyView` from the same measures.
enum ReplyContent {
    static let insets = NSEdgeInsets(top: NoteLayout.top, left: NoteLayout.inset, bottom: 13, right: NoteLayout.inset)
    /// How far a popover's body stands off what its arrow points at, in points.
    static let arrowLength: CGFloat = 12
    /// The row's top with no question above it, so its name sits where a header would.
    static let rowTopAlone: CGFloat = 2
    /// The answer's words start this far up into the row's bottom, under the name.
    static let wordsIntoRow: CGFloat = 6
    /// The name's place in the row: inside the note's target button, which is centred in the row.
    static var nameInset: CGFloat { NoteLayout.logoSize + NoteLayout.gap }
    static var buttonTop: CGFloat { (NoteLayout.row - NoteLayout.buttonHeight) / 2 }

    static var wordsFont: NSFont { NoteLayout.font }
    static var noticeFont: NSFont { .systemFont(ofSize: 12) }
    static let measuring: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

    /// Where each part goes in a body `size` big, in its own coordinates with y growing downwards.
    struct Layout: Equatable {
        var size: CGSize
        var question: CGRect?
        var rowTop: CGFloat
        var rowHeight: CGFloat
        var words: CGRect?
    }

    static func layout(_ text: String, quote: String?, notice: String?, answerer: String, foot: CGSize) -> Layout {
        let width = max(NoteLayout.width, ceil(foot.width) + insets.left + insets.right)
        let inner = width - insets.left - insets.right
        var question: CGRect?
        var rowTop = rowTopAlone
        if let quote = shown(quote) {
            let frame = NoteLayout.fieldFrame(height: NoteLayout.wordsHeight(quote))
            question = frame
            rowTop = frame.maxY + NoteLayout.belowWords
        }
        var rowHeight = NoteLayout.row
        if shown(notice) != nil {
            let line = row(answerer: answerer, notice: notice)
                .boundingRect(with: CGSize(width: inner - nameInset, height: .greatestFiniteMagnitude), options: measuring)
            rowHeight = max(rowHeight, ceil(line.height) + buttonTop * 2 + 6)
        }
        var bottom = rowTop + rowHeight
        var words: CGRect?
        if !text.isEmpty {
            let measured = wordsSize(text, wrap: inner)
            let frame = CGRect(x: insets.left, y: bottom - wordsIntoRow, width: inner, height: measured.height)
            words = frame
            bottom = frame.maxY + insets.bottom
        }
        return Layout(size: CGSize(width: width, height: ceil(bottom + foot.height)), question: question, rowTop: rowTop,
                      rowHeight: rowHeight, words: words)
    }

    /// The body's size, as `layout` lays it out.
    static func size(_ text: String, agent: String?, answerer: String? = nil, quote: String?, notice: String? = nil, foot: CGSize) -> CGSize {
        layout(text, quote: quote, notice: notice, answerer: name(agent: agent, answerer: answerer), foot: foot).size
    }

    /// Who the row says answers.
    static func name(agent: String?, answerer: String?) -> String { answerer ?? NoteBadge.label(for: agent) }

    /// The row's words: who answers, as the note's target named them, then Vignette's `notice`, which wraps.
    /// A notice is written to stand alone on the ink, so one whose subject is the answerer ("Claude
    /// couldn't answer.", "Claude's usage limit…") goes on from the name already in the row instead of
    /// repeating it. "Claude Code isn't signed in." names something else and follows a dot.
    static func row(answerer: String, notice: String?) -> NSAttributedString {
        let row = NSMutableAttributedString(string: answerer, attributes: [.font: NoteLayout.labelFont, .foregroundColor: NSColor.secondaryLabelColor])
        if let notice = shown(notice) {
            let predicate = subjectIs(answerer, of: notice) ? String(notice.dropFirst(answerer.count)) : nil
            row.append(NSAttributedString(string: predicate ?? "  ·  \(notice)", attributes: [.font: noticeFont, .foregroundColor: NSColor.secondaryLabelColor]))
        }
        return row
    }

    /// Whether `sentence` opens with `name` as its subject: the name, then "'s" or a word in lower case.
    private static func subjectIs(_ name: String, of sentence: String) -> Bool {
        guard sentence.hasPrefix(name) else { return false }
        let rest = sentence.dropFirst(name.count)
        return rest.hasPrefix("'s ") || (rest.first == " " && rest.dropFirst().first?.isLowercase == true)
    }

    static func words(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: wordsFont, .foregroundColor: NSColor.labelColor])
    }

    /// The size the words take wrapped at `wrap` points.
    static func wordsSize(_ text: String, wrap: CGFloat) -> CGSize {
        let size = words(text).boundingRect(with: CGSize(width: wrap, height: .greatestFiniteMagnitude), options: measuring).size
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    private static func shown(_ words: String?) -> String? {
        guard let words = words?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty else { return nil }
        return words
    }
}

/// The popover's content, laid out by `ReplyContent`: the question in a field set up as the note's,
/// the row with the answerer's logo and name, and the answer's words, which cross-fade when they
/// change. The question greys once there are words under it, so the answer leads. While the agent
/// works, the thinking light runs round its rim.
@MainActor
final class ReplyView: NSView {
    private let question = NSTextField()
    private let logo = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let words = Drawn()
    let light = RimLight()

    override var isFlipped: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        NoteLayout.configure(question)
        question.isEditable = false
        question.isSelectable = false
        question.wantsLayer = true
        question.maximumNumberOfLines = NoteLayout.mostLines
        question.cell?.truncatesLastVisibleLine = true
        logo.imageScaling = .scaleProportionallyUpOrDown
        name.font = NoteLayout.labelFont
        name.textColor = .secondaryLabelColor
        name.wantsLayer = true
        for view in [question, logo, name, words] as [NSView] { addSubview(view) }
        wantsLayer = true
        words.wantsLayer = true
        words.layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.addSublayer(light)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Shows `text` from `agent`, named `answerer`, under the person's `quote`, with Vignette's
    /// `notice` in the row, in a body laid out as `layout`. With `fade`, what changed cross-fades over
    /// that many seconds.
    func show(_ text: String, agent: String?, answerer: String, quote: String?, notice: String?, layout: ReplyContent.Layout,
              fade: CFTimeInterval) {
        let insets = ReplyContent.insets
        question.isHidden = layout.question == nil
        if let frame = layout.question {
            if question.stringValue != quote ?? "" { question.stringValue = quote ?? "" }
            question.frame = frame
        }
        let questionColor: NSColor = text.isEmpty ? .labelColor : .secondaryLabelColor
        if question.textColor != questionColor {
            if fade > 0 { question.layer?.add(Self.crossFade(fade), forKey: "colour") }
            question.textColor = questionColor
        }
        let button = layout.rowTop + ReplyContent.buttonTop
        logo.image = agent.flatMap { Agent.logo(for: $0) }
        logo.frame = CGRect(x: insets.left, y: button + (NoteLayout.buttonHeight - NoteLayout.logoSize) / 2, width: NoteLayout.logoSize, height: NoteLayout.logoSize)
        let x = insets.left + ReplyContent.nameInset
        let row = ReplyContent.row(answerer: answerer, notice: notice)
        if name.attributedStringValue != row {
            if fade > 0, !name.stringValue.isEmpty { name.layer?.add(Self.crossFade(fade), forKey: "row") }
            name.attributedStringValue = row
        }
        if notice == nil || notice?.isEmpty == true {
            // As the note's target names it, so the one hands over to the other unseen.
            name.maximumNumberOfLines = 1
            name.lineBreakMode = .byTruncatingMiddle
            let line = ceil(name.intrinsicContentSize.height)
            name.frame = CGRect(x: x, y: button + (NoteLayout.buttonHeight - line) / 2, width: NoteLayout.labelWidth(answerer), height: line)
        } else {
            name.maximumNumberOfLines = 0
            name.lineBreakMode = .byWordWrapping
            let width = layout.size.width - insets.right - x
            let height = ceil(row.boundingRect(with: CGSize(width: width - 4, height: .greatestFiniteMagnitude), options: ReplyContent.measuring).height)
            name.frame = CGRect(x: x, y: button + 3, width: width, height: height)
        }
        let changed = words.text?.string != text
        if changed, fade > 0, words.text != nil, !(words.text?.string.isEmpty ?? true) {
            words.layer?.add(Self.crossFade(fade), forKey: "words")
        }
        words.isHidden = layout.words == nil
        words.frame = layout.words ?? .zero
        words.text = ReplyContent.words(text)
    }

    private static func crossFade(_ duration: CFTimeInterval) -> CATransition {
        let fade = CATransition()
        fade.type = .fade
        fade.duration = duration
        return fade
    }

    /// Draws an attributed string in its bounds, as `ReplyContent` measured it.
    private final class Drawn: NSView {
        var text: NSAttributedString? { didSet { needsDisplay = true } }
        override var isFlipped: Bool { true }
        /// Blended with the glass as the question's label is, or over a dark window the answer drew
        /// lighter than the greyed question above it.
        override var allowsVibrancy: Bool { true }
        override func draw(_ dirtyRect: NSRect) { text?.draw(with: bounds, options: ReplyContent.measuring) }
    }
}

extension Notification.Name {
    /// A reply's popover moved, changed size, or faded in or out: the × and the actions laid over it follow.
    static let liveReplyChanged = Notification.Name("LiveReplyChanged")
}

/// A reply shown as a popover from a view of the overlay it is drawn on. It holds only words: its
/// window lets every click through, as a note on the overlay does, and the answer's × and actions
/// are panels of their own, children of its window (`carry`). A button inside it would take the person's keys on
/// macOS 15 (docs/live-ink-look-2026-10-07.md, plan step 6).
@MainActor
final class ReplyPopover {
    private let popover = NSPopover()
    private let view = ReplyView(frame: .zero)
    private weak var host: NSView?
    private let sharing: NSWindow.SharingType
    private var shown: (text: String, quote: String?, notice: String?, agent: String?, answerer: String, foot: CGSize)?
    /// The edge it hangs from now, and the mark.
    private var edge: PopoverPlace.Edge?
    private var anchor: Mark.ID?
    /// Where it is sliding to, in the host's coordinates, while it moves to hang from another mark.
    private var slidingTo: CGRect?
    private lazy var slideX = Tween(initial: 0) { [weak self] _ in self?.applySlide() }
    private lazy var slideY = Tween(initial: 0) { [weak self] _ in self?.applySlide() }
    private var alpha: CGFloat = 1
    private var closing = false
    private var watching: [NSObjectProtocol] = []

    init(host: NSView, sharing: NSWindow.SharingType) {
        self.host = host
        self.sharing = sharing
        let controller = NSViewController()
        controller.view = view
        popover.contentViewController = controller
        popover.behavior = .applicationDefined
    }

    /// The popover's window, once it has been shown.
    private var window: NSWindow? { view.window }

    /// The body, in global top-left points, or nil while it is not up or faded out.
    var globalFrame: CGRect? {
        guard popover.isShown, !closing, alpha > 0.5, let window else { return nil }
        return StateReport.flipped(window.convertToScreen(view.convert(view.bounds, to: nil)))
    }

    /// Lays `panel` over the popover as a child of its window, so the panel takes the popover's
    /// layer: a window raised over the answer covers both, and the panel moves with it.
    func carry(_ panel: NSWindow) {
        guard let window, panel.parent !== window else { return }
        panel.level = window.level
        window.addChildWindow(panel, ordered: .above)
    }

    /// Shows `mark`'s words hung from `rect`, in the host view's coordinates, on `place`'s edge, or
    /// moves it there and updates its words. `appearing` lets AppKit animate it in.
    func show(_ mark: Mark, place: PopoverPlace, at rect: CGRect, appearing: Bool) {
        guard case .text(let text) = mark.geometry, let host, !closing else { return }
        let motion = Settings.shared.motionScale
        let answerer = ReplyContent.name(agent: mark.agentName, answerer: mark.answerer)
        let layout = ReplyContent.layout(text.text, quote: mark.quote, notice: mark.notice, answerer: answerer, foot: place.foot)
        let size = layout.size
        let next = (text: text.text, quote: mark.quote, notice: mark.notice, agent: mark.agentName, answerer: answerer, foot: place.foot)
        if shown.map({ $0 != next }) ?? true {
            view.show(text.text, agent: mark.agentName, answerer: answerer, quote: mark.quote, notice: mark.notice, layout: layout,
                      fade: shown == nil ? 0 : Self.wordsFade * motion)
            shown = next
        }
        if popover.isShown {
            popover.animates = motion > 0
            if popover.contentSize != size { popover.contentSize = size }
            // AppKit keeps the edge it was shown on, so hanging from another one means showing it again.
            if place.edge != edge {
                stopSliding()
                edge = place.edge
                popover.show(relativeTo: rect, of: host, preferredEdge: place.edge.rectEdge(flipped: host.isFlipped))
            } else if motion > 0, place.anchor != anchor || slidingTo != nil {
                slide(to: rect, duration: Self.slideDuration * motion)
            } else if popover.positioningRect != rect {
                popover.positioningRect = rect
            }
            anchor = place.anchor
            placeLight()
            return
        }
        guard host.window?.isVisible == true else { return }
        popover.animates = appearing && motion > 0
        popover.contentSize = size
        view.frame = CGRect(origin: .zero, size: size)
        popover.show(relativeTo: rect, of: host, preferredEdge: place.edge.rectEdge(flipped: host.isFlipped))
        edge = place.edge
        anchor = place.anchor
        placeLight()
        if let window {
            window.ignoresMouseEvents = true
            window.sharingType = sharing
            window.alphaValue = alpha
            watching = [NSWindow.didMoveNotification, NSWindow.didResizeNotification].map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    NotificationCenter.default.post(name: .liveReplyChanged, object: nil)
                    MainActor.assumeIsolated { self?.placeLight() }
                }
            }
            // Run as the window becomes key, so its glass never draws as key.
            watching.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: nil) { [weak window] _ in
                MainActor.assumeIsolated { window.map(Self.letGoOfKeys) }
            })
        }
        NotificationCenter.default.post(name: .liveReplyChanged, object: nil)
    }

    /// A popover's window can be key, and macOS makes it key when a panel of Vignette's that held the
    /// keys, such as the reply field's, closes, though Vignette had let go of them: the keys would stay
    /// with Vignette, and the glass turns light. Nothing in the reply takes keys, so it lets go at
    /// once. The app the person was in never stopped being the active one, so letting go hands the
    /// keys back to it, and resigning redraws the glass.
    private static func letGoOfKeys(_ window: NSWindow) {
        Log.write("[live-ink] reply let go of the keys")
        if NSApp.isActive { NSApp.deactivate() }
        window.resignKey()
    }

    /// Moves it along a spring to hang at `rect`, from wherever it is, as a tour moves the reply from
    /// one stop to the next: AppKit moves a popover whose positioning rect changes in one frame.
    private func slide(to rect: CGRect, duration: CFTimeInterval) {
        guard rect != slidingTo else { return }
        if slidingTo == nil {
            slideX.set(popover.positioningRect.minX)
            slideY.set(popover.positioningRect.minY)
        }
        slidingTo = rect
        let settled = { [weak self] in
            guard let self, let target = self.slidingTo, self.slideX.value == target.minX, self.slideY.value == target.minY else { return }
            self.slidingTo = nil
        }
        slideX.animate(to: rect.minX, duration: duration, completion: settled)
        slideY.animate(to: rect.minY, duration: duration, completion: settled)
    }

    private func applySlide() {
        guard let target = slidingTo else { return }
        popover.positioningRect = CGRect(origin: CGPoint(x: slideX.value, y: slideY.value), size: target.size)
    }

    private func stopSliding() {
        slideX.stop()
        slideY.stop()
        slidingTo = nil
    }

    /// Whether the reply carries the thinking light, as the marks it answers do while the agent works.
    func think(_ on: Bool) {
        placeLight()
        // One that comes up lit takes over from the note, whose light was already on.
        view.light.think(on, fades: popover.isShown)
    }

    /// Lays the thinking light round the body as it is now, starting under the arrow.
    private func placeLight() {
        guard let window, let edge, let host, let hostWindow = host.window else { return }
        let body = StateReport.flipped(window.convertToScreen(view.convert(view.bounds, to: nil)))
        let at = StateReport.flipped(hostWindow.convertToScreen(host.convert(popover.positioningRect, to: nil)))
        let dark = view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        view.light.place(view.bounds, start: RimLight.start(of: body, hungFrom: at, edge: edge), dark: dark)
    }

    /// Fades the popover to `target` over `duration`, as its mark fades.
    func fade(to target: CGFloat, duration: CFTimeInterval) {
        guard target != alpha else { return }
        alpha = target
        NotificationCenter.default.post(name: .liveReplyChanged, object: nil)
        guard let window else { return }
        guard duration > 0 else { window.alphaValue = target; return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: target > window.alphaValue ? .easeOut : .easeIn)
            window.animator().alphaValue = target
        }
    }

    /// Fades it out over `fade`, after `delay`, and closes it.
    func close(after delay: CFTimeInterval = 0, fade: CFTimeInterval) {
        guard !closing else { return }
        closing = true
        stopSliding()
        watching.forEach(NotificationCenter.default.removeObserver)
        watching = []
        NotificationCenter.default.post(name: .liveReplyChanged, object: nil)
        let popover = popover
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let window = self?.window, fade > 0 else { popover.animates = false; popover.close(); return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = fade
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                window.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated {
                    popover.animates = false
                    popover.close()
                }
            })
        }
    }

    /// How long the words take to cross-fade when they change, at full motion.
    static let wordsFade: CFTimeInterval = 0.2
    /// How long it takes to move to another mark, at full motion: as long as a focus takes to come
    /// in, so a tour's reply arrives as its next target sharpens.
    static let slideDuration: CFTimeInterval = Focus.fade
}
