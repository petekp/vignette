import AppKit

/// The card a pin grows into in the editor while the pointer rests on it: the avatar of whoever wrote
/// its first comment where the teardrop's body was, and beside it their name, the pin's number, how
/// long ago they wrote, the comment's first line, and how many replies it has. It grows from the
/// teardrop, its tip the card's square corner unless the card turned away from an edge, and goes
/// back into the teardrop when the pointer leaves. It takes no clicks: a click on the pin opens its popover. VoiceOver reads the pin itself.
@MainActor
final class PinHoverCard: NSView {
    /// What the card says.
    struct Words: Equatable {
        /// "You", or the agent's name, as "Claude".
        let name: String
        /// "Pin 3 · 1 min. ago", or "Pin 3" for a comment from a file that kept no time.
        let detail: String
        let firstLine: String
        /// "1 reply from Claude", "2 replies from you", or "3 replies" from more than one writer. Nil
        /// for a pin with one comment.
        let replies: String?

        init(_ pin: Pin, now: Date) {
            let first = pin.comments.first
            name = Self.writer(first, capitalized: true)
            let ago = first?.at.map { Self.ago.localizedString(for: min($0, now), relativeTo: now) }
            detail = ["Pin \(pin.number)", ago].compactMap { $0 }.joined(separator: " · ")
            firstLine = first?.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            let later = pin.comments.dropFirst()
            guard !later.isEmpty else { replies = nil; return }
            let count = later.count == 1 ? "1 reply" : "\(later.count) replies"
            let writers = Set(later.map { Self.writer($0, capitalized: false) })
            replies = writers.count == 1 ? "\(count) from \(writers.first ?? "")" : count
        }

        /// Who wrote `comment`: "You", or the agent's name, as "Claude".
        static func writer(_ comment: Pin.Comment?, capitalized: Bool) -> String {
            guard let comment, comment.agent else { return capitalized ? "You" : "you" }
            let name = (comment.agentName ?? "").trimmingCharacters(in: .whitespaces)
            guard let letter = name.first else { return capitalized ? "An agent" : "an agent" }
            return letter.uppercased() + name.dropFirst()
        }

        private static let ago: RelativeDateTimeFormatter = {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            formatter.dateTimeStyle = .named
            return formatter
        }()
    }

    let pin: Pin.ID
    private let clip = FlippedView()
    private let glass = NSVisualEffectView()
    private let content = FlippedView()
    private let avatar = NSImageView()
    private let name = NSTextField(labelWithString: ""), detail = NSTextField(labelWithString: "")
    private let firstLine = NSTextField(labelWithString: ""), replies = NSTextField(labelWithString: "")
    private var shown: (words: Words, maker: PinMaker, body: CGRect, card: CGRect)?
    /// The card's corner the teardrop's body sits in: on its right, at its bottom. The tip is that
    /// corner, drawn square, unless the card turned away from an edge of the view.
    private var bodyCorner = (right: false, bottom: true), sharp = true
    private lazy var growth = Tween(initial: 0) { [weak self] progress in self?.grow(to: progress) }

    init(pin: Pin.ID) {
        self.pin = pin
        super.init(frame: .zero)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        clip.clipsToBounds = true
        clip.autoresizingMask = [.width, .height]
        addSubview(clip)
        glass.material = .popover
        glass.blendingMode = .withinWindow
        glass.state = .active
        glass.autoresizingMask = [.width, .height]
        clip.addSubview(glass)
        clip.addSubview(content)
        content.addSubview(avatar)
        avatar.imageScaling = .scaleProportionallyUpOrDown
        avatar.wantsLayer = true
        name.font = .preferredFont(forTextStyle: .headline)
        detail.font = .preferredFont(forTextStyle: .subheadline)
        detail.textColor = .secondaryLabelColor
        firstLine.font = .preferredFont(forTextStyle: .body)
        replies.font = .preferredFont(forTextStyle: .subheadline)
        replies.textColor = .secondaryLabelColor
        for label in [name, detail, firstLine, replies] {
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            content.addSubview(label)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { [] }

    /// Shows `pin` growing out of its teardrop, whose square is `body` in the superview's coordinates,
    /// facing `orientation`. The card covers the body and reaches the way the body faces from the tip,
    /// or the other way on an axis where that would leave `bounds` and the other way would not.
    func show(_ pin: Pin, body: CGRect, orientation: PinTeardrop.Orientation, inside bounds: CGRect) {
        let words = Words(pin, now: Date()), ui = Settings.shared.data.ui
        let side = body.height, inset = ui.pinPopoverInset
        let column = max(ui.pinHoverWidth - side - inset * 1.5, 0)
        let (size, rows) = measure(words, maker: pin.maker, side: side, inset: inset, column: column)
        let facesRight = orientation == .upRight || orientation == .downRight, facesUp = orientation == .upRight || orientation == .upLeft
        var right = facesRight, up = facesUp
        if right, body.minX + size.width > bounds.maxX, body.maxX - size.width >= bounds.minX { right = false }
        else if !right, body.maxX - size.width < bounds.minX, body.minX + size.width <= bounds.maxX { right = true }
        if up, body.maxY - size.height < bounds.minY, body.minY + size.height <= bounds.maxY { up = false }
        else if !up, body.minY + size.height > bounds.maxY, body.maxY - size.height >= bounds.minY { up = true }
        let card = CGRect(x: right ? body.minX : body.maxX - size.width, y: up ? body.maxY - size.height : body.minY,
                          width: size.width, height: size.height)
        guard shown.map({ $0.words != words || $0.maker != pin.maker || $0.body != body || $0.card != card }) ?? true else {
            growth.animate(to: 1, duration: Settings.shared.motionUI.pinHoverDuration)
            return
        }
        bodyCorner = (right: !right, bottom: up)
        sharp = right == facesRight && up == facesUp
        shown = (words, pin.maker, body, card)
        content.frame.size = card.size
        place(rows: rows, side: side, inset: inset, column: column)
        glass.maskImage = Self.mask(radius: side / 2, sharp: sharp ? bodyCorner : nil)
        grow(to: growth.value)
        growth.animate(to: 1, duration: Settings.shared.motionUI.pinHoverDuration)
    }

    /// Goes back into the teardrop, then out of the view.
    func leave() {
        growth.animate(to: 0, duration: Settings.shared.motionUI.pinHoverDuration) { [weak self] in self?.removeFromSuperview() }
    }

    /// Sets the words and the avatar, and answers the card's size and each row's height.
    private func measure(_ words: Words, maker: PinMaker, side: CGFloat, inset: CGFloat, column: CGFloat) -> (size: CGSize, rows: [CGFloat]) {
        name.stringValue = words.name
        detail.stringValue = words.detail
        firstLine.stringValue = words.firstLine
        replies.stringValue = words.replies ?? ""
        replies.isHidden = words.replies == nil
        showAvatar(of: maker, side: side)
        let rows = [max(name.fittingSize.height, detail.fittingSize.height), firstLine.fittingSize.height]
            + (words.replies == nil ? [] : [replies.fittingSize.height])
        let height = max(side, inset + rows.reduce(0, +) + Self.rowGap * CGFloat(rows.count - 1) + inset)
        return (CGSize(width: side + inset * 1.5 + column, height: height), rows)
    }

    /// Puts the words beside the teardrop's body, on the side away from the tip.
    private func place(rows: [CGFloat], side: CGFloat, inset: CGFloat, column: CGFloat) {
        let leading = bodyCorner.right ? inset : side + inset / 2
        let nameWidth = min(name.fittingSize.width, column), detailGap: CGFloat = 6
        var y = inset
        name.frame = CGRect(x: leading, y: y, width: nameWidth, height: rows[0])
        detail.frame = CGRect(x: leading + nameWidth + detailGap, y: y, width: max(column - nameWidth - detailGap, 0), height: rows[0])
        y += rows[0] + Self.rowGap
        firstLine.frame = CGRect(x: leading, y: y, width: column, height: rows[1])
        if rows.count > 2 { replies.frame = CGRect(x: leading, y: y + rows[1] + Self.rowGap, width: column, height: rows[2]) }
    }

    private static let rowGap: CGFloat = 2

    private func showAvatar(of maker: PinMaker, side: CGFloat) {
        let diameter = side * 0.8
        avatar.frame.size = CGSize(width: diameter, height: diameter)
        avatar.layer?.cornerRadius = diameter / 2
        Self.paint(avatar, as: maker)
    }

    /// A writer's avatar: the person's silhouette, or the agent's logo in black on white. `avatar` is
    /// layer-backed and round. The pin's popover shows the same beside each comment.
    static func paint(_ avatar: NSImageView, as maker: PinMaker) {
        switch maker {
        case .person:
            avatar.image = NSImage(systemSymbolName: "person.crop.circle.fill", accessibilityDescription: nil)
            avatar.contentTintColor = .secondaryLabelColor
            avatar.layer?.backgroundColor = nil
        case .agent(let agent):
            avatar.image = Agent.logo(for: agent) ?? NSImage(systemSymbolName: Agent.fallbackSymbol, accessibilityDescription: nil)
            avatar.contentTintColor = .black
            avatar.layer?.backgroundColor = NSColor.white.cgColor
        }
    }

    /// The card `progress` of the way from the teardrop's square to its whole size, the words fading in.
    private func grow(to progress: CGFloat) {
        guard let shown else { return }
        let p = min(max(progress, 0), 1)
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * p }
        frame = CGRect(x: mix(shown.body.minX, shown.card.minX), y: mix(shown.body.minY, shown.card.minY),
                       width: mix(shown.body.width, shown.card.width), height: mix(shown.body.height, shown.card.height))
        clip.frame = bounds
        let corner = bodyCorner
        content.frame.origin = CGPoint(x: corner.right ? bounds.width - shown.card.width : 0, y: corner.bottom ? bounds.height - shown.card.height : 0)
        let side = shown.body.height
        avatar.frame.origin = CGPoint(x: (corner.right ? shown.card.width - side : 0) + (side - avatar.frame.width) / 2,
                                      y: (corner.bottom ? shown.card.height - side : 0) + (side - avatar.frame.height) / 2)
        alphaValue = min(1, p * 2)
        for label in [name, detail, firstLine, replies] { label.alphaValue = p }
        layer?.shadowPath = Self.outline(of: CGRect(origin: .zero, size: bounds.size), radius: side / 2, sharp: nil)
    }

    /// The card's outline: a rounded rect whose corner `sharp`, at the tip, is square, as the teardrop's
    /// is, in a space whose y runs down, so `bottom` is the greatest y.
    private static func outline(of rect: CGRect, radius: CGFloat, sharp: (right: Bool, bottom: Bool)?) -> CGPath {
        let r = min(radius, rect.width / 2, rect.height / 2)
        let path = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        guard let sharp else { return path }
        let corner = CGRect(x: sharp.right ? rect.maxX - r : rect.minX, y: sharp.bottom ? rect.maxY - r : rect.minY, width: r, height: r)
        return path.union(CGPath(rect: corner, transform: nil))
    }

    /// The glass's mask, `outline` drawn in an image whose y runs down, as the card's does, stretched
    /// between its corners.
    private static func mask(radius: CGFloat, sharp: (right: Bool, bottom: Bool)?) -> NSImage {
        let side = 2 * radius + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            NSGraphicsContext.current?.cgContext.addPath(outline(of: rect, radius: radius, sharp: sharp))
            NSColor.black.setFill()
            NSGraphicsContext.current?.cgContext.fillPath()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// A view whose y runs down, as the card's does, so the words are laid out from the top.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
