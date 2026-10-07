import AppKit

/// Where a live answer's reply hangs as a popover, in the coordinates of the marks: the rect its
/// arrow points at, the edge of that rect it hangs from, and where its body is expected. AppKit
/// places the popover itself, centred on its arrow, so `body` is the layout's estimate, which the
/// answer's other marks keep clear of (docs/live-ink-look-2026-10-07.md, plan step 6).
struct PopoverPlace: Equatable {
    enum Edge: CaseIterable {
        case below, above, right, left
    }

    /// The mark it hangs from, which it follows on its window, or nil for the person's ink.
    var anchor: Mark.ID?
    var at: CGRect
    var edge: Edge
    var body: CGRect
    /// Room kept at the foot of its body, for the answer's actions, in points.
    var foot: CGFloat

    func offsetBy(dx: CGFloat, dy: CGFloat) -> PopoverPlace {
        var moved = self
        moved.at = at.offsetBy(dx: dx, dy: dy)
        moved.body = body.offsetBy(dx: dx, dy: dy)
        return moved
    }

    /// A body of `size` hung from `at` on `edge`, centred on it, as AppKit centres a popover on its arrow.
    static func body(_ size: CGSize, hungFrom at: CGRect, edge: Edge) -> CGRect {
        let gap = ReplyContent.arrowLength
        let origin: CGPoint
        switch edge {
        case .below: origin = CGPoint(x: at.midX - size.width / 2, y: at.maxY + gap)
        case .above: origin = CGPoint(x: at.midX - size.width / 2, y: at.minY - gap - size.height)
        case .right: origin = CGPoint(x: at.maxX + gap, y: at.midY - size.height / 2)
        case .left: origin = CGPoint(x: at.minX - gap - size.width, y: at.midY - size.height / 2)
        }
        return CGRect(origin: origin, size: size)
    }
}

/// What a reply's popover shows: the agent's logo and name and the question in quotes on one line,
/// then the reply's words. Measured here without a view, so the layout knows the body's size, and
/// drawn by `ReplyView` from the same measures.
enum ReplyContent {
    static let insets = NSEdgeInsets(top: 12, left: 14, bottom: 13, right: 14)
    /// Between the header and the words, and between the header's logo, name and question, in points.
    static let spacing: CGFloat = 5
    static let logoSize: CGFloat = 12
    /// How far a popover's body stands off what its arrow points at, in points.
    static let arrowLength: CGFloat = 12

    static var nameFont: NSFont { .systemFont(ofSize: 11, weight: .semibold) }
    static var quoteFont: NSFont { .systemFont(ofSize: 11) }
    static var wordsFont: NSFont { .systemFont(ofSize: NSFont.systemFontSize) }

    static let measuring: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

    static func name(_ agent: String?) -> NSAttributedString {
        NSAttributedString(string: NoteBadge.label(for: agent), attributes: [.font: nameFont, .foregroundColor: NSColor.secondaryLabelColor])
    }

    static func quote(_ words: String?) -> NSAttributedString? {
        guard let words = words?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty else { return nil }
        return NSAttributedString(string: "·  \u{201C}\(words)\u{201D}", attributes: [.font: quoteFont, .foregroundColor: NSColor.secondaryLabelColor])
    }

    /// The header after the logo: the agent's name, then the question, cut at the end to one line.
    static func header(agent: String?, quote words: String?) -> NSAttributedString {
        let header = NSMutableAttributedString(attributedString: name(agent))
        if let quote = quote(words) {
            header.append(NSAttributedString(string: " ", attributes: [.font: quoteFont]))
            header.append(quote)
        }
        let line = NSMutableParagraphStyle()
        line.lineBreakMode = .byTruncatingTail
        header.addAttribute(.paragraphStyle, value: line, range: NSRange(location: 0, length: header.length))
        return header
    }

    static func words(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: wordsFont, .foregroundColor: NSColor.labelColor])
    }

    /// The header's height: one line of its font.
    static var headerHeight: CGFloat {
        ceil(max(logoSize, name(nil).boundingRect(with: CGSize(width: 1000, height: 1000), options: measuring).height))
    }

    /// The size the words take wrapped at `wrap` points.
    static func wordsSize(_ text: String, wrap: CGFloat) -> CGSize {
        let size = words(text).boundingRect(with: CGSize(width: wrap, height: .greatestFiniteMagnitude), options: measuring).size
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    /// The header's width before any of the question is cut.
    static func headerWidth(agent: String?, quote words: String?) -> CGFloat {
        let one = CGSize(width: 10_000, height: 100)
        let logo = agent.map { _ in logoSize + spacing } ?? 0
        return logo + ceil(header(agent: agent, quote: words).boundingRect(with: one, options: measuring).width)
    }

    /// The body's size for `text` wrapped at `wrap` points, with `foot` points kept at its foot.
    static func size(_ text: String, agent: String?, quote: String?, wrap: CGFloat, foot: CGFloat) -> CGSize {
        let words = wordsSize(text, wrap: wrap)
        let inner = min(wrap, max(words.width, headerWidth(agent: agent, quote: quote)))
        let height = insets.top + headerHeight + spacing + words.height + insets.bottom + foot
        return CGSize(width: ceil(insets.left + inner + insets.right), height: ceil(height))
    }
}

/// The popover's content: the header and the words, laid out by `ReplyContent`'s measures. The words
/// cross-fade when they change.
@MainActor
final class ReplyView: NSView {
    private let logo = NSImageView()
    private let header = Drawn()
    private let words = Drawn()

    override var isFlipped: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.contentTintColor = .secondaryLabelColor
        for view in [logo, header, words] as [NSView] { addSubview(view) }
        words.wantsLayer = true
        words.layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Shows `text` from `agent`, under the question's `quote`, wrapped at `wrap`, in a body of `size`.
    /// With `fade`, the words cross-fade from the last ones over that many seconds.
    func show(_ text: String, agent: String?, quote: String?, wrap: CGFloat, size: CGSize, fade: CFTimeInterval) {
        let insets = ReplyContent.insets
        let inner = size.width - insets.left - insets.right
        let line = ReplyContent.headerHeight
        logo.image = agent.flatMap { Agent.logo(for: $0) }
        logo.isHidden = logo.image == nil
        logo.frame = CGRect(x: insets.left, y: insets.top + (line - ReplyContent.logoSize) / 2,
                            width: ReplyContent.logoSize, height: ReplyContent.logoSize)
        let headerX = insets.left + (logo.isHidden ? 0 : ReplyContent.logoSize + ReplyContent.spacing)
        self.header.frame = CGRect(x: headerX, y: insets.top, width: insets.left + inner - headerX, height: line)
        self.header.text = ReplyContent.header(agent: agent, quote: quote)
        self.header.options = [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine]
        let measured = ReplyContent.wordsSize(text, wrap: wrap)
        let changed = words.text?.string != text
        if changed, fade > 0, words.text != nil {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = fade
            words.layer?.add(transition, forKey: "words")
        }
        words.frame = CGRect(x: insets.left, y: insets.top + line + ReplyContent.spacing, width: inner, height: measured.height)
        words.text = ReplyContent.words(text)
        if let light = words.layer?.mask {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            light.frame = words.bounds
            CATransaction.commit()
        }
    }

    /// The thinking light on the words: they dim, and a band of full strength crosses them on the beat
    /// of the light on the marks, a third of a beat behind the band on the ink, as a note's sheen is.
    /// The band is the words' own opacity, so it reads on a light popover and a dark one. With motion
    /// off they dim and hold. It fades in and out as the light on the marks does.
    func think(_ on: Bool) {
        guard on != thinking, let layer = words.layer else { return }
        thinking = on
        let fade = LiveMarksLayer.thinkingFade * Settings.shared.motionScale
        let still = Settings.shared.motionScale == 0
        let whole = [CGColor(gray: 0, alpha: 1), CGColor(gray: 0, alpha: 1), CGColor(gray: 0, alpha: 1)]
        let dim = CGColor(gray: 0, alpha: still ? Self.stillDim : Self.dim)
        let lit = [dim, still ? dim : CGColor(gray: 0, alpha: 1), dim]
        let light = layer.mask as? CAGradientLayer ?? CAGradientLayer()
        if on {
            light.frame = words.bounds
            light.startPoint = CGPoint(x: 0, y: 0.3)
            light.endPoint = CGPoint(x: 1, y: 0.7)
            light.colors = lit
            light.locations = [-0.3, -0.15, 0]
            layer.mask = light
            if !still {
                let sweep = CABasicAnimation(keyPath: "locations")
                sweep.fromValue = [-0.3, -0.15, 0]
                sweep.toValue = [1, 1.15, 1.3]
                sweep.duration = LiveMarksLayer.thinkingPeriod
                sweep.repeatCount = .infinity
                sweep.beginTime = light.convertTime(LiveMarksLayer.thinkingEpoch, from: nil)
                sweep.timeOffset = LiveMarksLayer.thinkingPeriod * 0.65
                light.add(sweep, forKey: "think")
            }
            guard fade > 0 else { return }
            let dimming = CABasicAnimation(keyPath: "colors")
            dimming.fromValue = whole
            dimming.duration = fade
            light.add(dimming, forKey: "fade")
        } else {
            guard layer.mask === light else { return }
            let from = light.presentation()?.colors ?? light.colors
            light.colors = whole
            guard fade > 0 else { layer.mask = nil; return }
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                guard self?.thinking == false, layer.mask === light else { return }
                layer.mask = nil
            }
            let brightening = CABasicAnimation(keyPath: "colors")
            brightening.fromValue = from
            brightening.duration = fade
            light.add(brightening, forKey: "fade")
            CATransaction.commit()
        }
    }

    private var thinking = false
    /// How far the words dim around the band, and with motion off.
    private static let dim: CGFloat = 0.45
    private static let stillDim: CGFloat = 0.6

    /// Draws an attributed string in its bounds, as `ReplyContent` measured it.
    private final class Drawn: NSView {
        var text: NSAttributedString? { didSet { needsDisplay = true } }
        var options: NSString.DrawingOptions = ReplyContent.measuring
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) { text?.draw(with: bounds, options: options) }
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
    private var shown: (text: String, quote: String?, agent: String?, wrap: CGFloat, foot: CGFloat)?
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
        let frame = window.convertToScreen(view.convert(view.bounds, to: nil))
        return CGRect(x: frame.minX, y: StateReport.primaryHeight - frame.maxY, width: frame.width, height: frame.height)
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
        // A reply always wraps where the layout measured it.
        guard case .text(let text) = mark.geometry, let wrap = text.wrap, let host, !closing else { return }
        let motion = Settings.shared.motionScale
        let size = ReplyContent.size(text.text, agent: mark.agentName, quote: mark.quote, wrap: wrap, foot: place.foot)
        let next = (text: text.text, quote: mark.quote, agent: mark.agentName, wrap: wrap, foot: place.foot)
        if shown.map({ $0 != next }) ?? true {
            view.show(text.text, agent: mark.agentName, quote: mark.quote, wrap: wrap, size: size,
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
                popover.show(relativeTo: rect, of: host, preferredEdge: Self.edge(place.edge, flipped: host.isFlipped))
            } else if motion > 0, place.anchor != anchor || slidingTo != nil {
                slide(to: rect, duration: Self.slideDuration * motion)
            } else if popover.positioningRect != rect {
                popover.positioningRect = rect
            }
            anchor = place.anchor
            return
        }
        guard host.window?.isVisible == true else { return }
        popover.animates = appearing && motion > 0
        popover.contentSize = size
        view.frame = CGRect(origin: .zero, size: size)
        popover.show(relativeTo: rect, of: host, preferredEdge: Self.edge(place.edge, flipped: host.isFlipped))
        edge = place.edge
        anchor = place.anchor
        if let window {
            window.ignoresMouseEvents = true
            window.sharingType = sharing
            window.alphaValue = alpha
            watching = [NSWindow.didMoveNotification, NSWindow.didResizeNotification].map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { _ in
                    NotificationCenter.default.post(name: .liveReplyChanged, object: nil)
                }
            }
        }
        NotificationCenter.default.post(name: .liveReplyChanged, object: nil)
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

    /// Whether the reply carries the thinking light, as the marks it answers do while the session works.
    func think(_ on: Bool) { view.think(on) }

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

    /// AppKit's edge in the host's coordinates: a flipped host's bottom is its max y.
    private static func edge(_ edge: PopoverPlace.Edge, flipped: Bool) -> NSRectEdge {
        switch edge {
        case .below: flipped ? .maxY : .minY
        case .above: flipped ? .minY : .maxY
        case .right: .maxX
        case .left: .minX
        }
    }

    /// How long the words take to cross-fade when they change, at full motion.
    static let wordsFade: CFTimeInterval = 0.2
    /// How long it takes to move to another mark, at full motion: as long as a focus takes to come
    /// in, so a tour's reply arrives as its next target sharpens.
    static let slideDuration: CFTimeInterval = Focus.fade
}
