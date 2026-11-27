import AppKit
import Collaboration

/// The card a pin grows into in the editor while the pointer rests on it: the teardrop, rim and all,
/// widened into a card whose tip stays its square corner unless the card turned away from an edge. Its
/// top line holds the avatar of whoever wrote the first comment, their name and how long ago, as a
/// comment's top line in the popover does. Under it are the comment's first line and how many replies
/// it has. It goes back into the teardrop when the pointer leaves. It takes no clicks: a click on the pin opens its popover. VoiceOver reads the pin itself.
/// It draws in a borderless panel of its own, a child of the editor's window, so it reaches past the
/// picture's frame over whatever is beside the editor, as the pin's popover does.
@MainActor
final class PinHoverCard: NSView {
    /// What the card says.
    struct Words: Equatable {
        /// "You", or the agent's name, as "Claude".
        let name: String
        /// "1 min. ago", or nil for a comment from a file that kept no time.
        let time: String?
        let firstLine: String
        /// "1 reply from Claude", "2 replies from you", or "3 replies" from more than one writer. Nil
        /// for a pin with one comment.
        let replies: String?

        init(_ pin: Pin, now: Date) {
            let first = pin.comments.first
            name = Self.writer(first, capitalized: true)
            time = first.flatMap { Self.ago($0, now: now) }
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

        /// How long before `now` `comment` was written, as "1 min. ago". Nil for a comment from a file that
        /// kept no time.
        static func ago(_ comment: Pin.Comment, now: Date) -> String? {
            comment.at.map { formatter.localizedString(for: min($0, now), relativeTo: now) }
        }

        private static let formatter: RelativeDateTimeFormatter = {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            formatter.dateTimeStyle = .named
            return formatter
        }()
    }

    let pin: Pin.ID
    /// The window the card draws in: as large as the card's whole growth and its shadow, and passing
    /// every event to what is under it.
    private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private let clip = FlippedView()
    private let glass = NSVisualEffectView()
    private let content = FlippedView()
    private let avatar = NSImageView()
    private let name = NSTextField(labelWithString: ""), time = NSTextField(labelWithString: "")
    private let firstLine = NSTextField(labelWithString: ""), replies = NSTextField(labelWithString: "")
    /// `start` is the teardrop's square widened by its rim, which the card grows from, and `room` the
    /// panel's rect. All three are in the editor's coordinates.
    private var shown: (words: Words, maker: PinMaker, start: CGRect, card: CGRect, room: CGRect)?
    /// The card's corner at the teardrop's tip: on its right, at its bottom. It is drawn square unless
    /// the card turned away from an edge of the view.
    private var tipCorner = (right: false, bottom: true), sharp = true
    private lazy var growth = Tween(initial: 0) { [weak self] progress in self?.grow(to: progress) }

    init(pin: Pin.ID) {
        self.pin = pin
        super.init(frame: .zero)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        // Above the stack's column (`.statusBar`), as the toolbar is, so a card reaching past the frame
        // is not under the stack's cards.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.setAccessibilityElement(false)
        panel.contentView = FlippedView()
        panel.contentView?.addSubview(self)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        clip.clipsToBounds = true
        clip.autoresizingMask = [.width, .height]
        addSubview(clip)
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.autoresizingMask = [.width, .height]
        clip.addSubview(glass)
        clip.addSubview(content)
        content.addSubview(avatar)
        avatar.imageScaling = .scaleProportionallyUpOrDown
        avatar.wantsLayer = true
        name.font = .preferredFont(forTextStyle: .headline)
        time.font = .preferredFont(forTextStyle: .subheadline)
        time.textColor = .secondaryLabelColor
        firstLine.font = .preferredFont(forTextStyle: .body)
        replies.font = .preferredFont(forTextStyle: .subheadline)
        replies.textColor = .secondaryLabelColor
        for label in [name, time, firstLine, replies] {
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

    /// Shows `pin` growing out of its teardrop, whose square is `body` in `editor`'s coordinates, facing
    /// `orientation`. The card covers the teardrop and its rim and reaches the way the body faces from the
    /// tip, past the editor's frame if need be, or the other way on an axis where that would leave the
    /// screen's visible frame and the other way would not.
    func show(_ pin: Pin, body square: CGRect, orientation: PinTeardrop.Orientation, in editor: NSView) {
        guard let window = editor.window else { return }
        let onScreen = window.convertToScreen(editor.convert(square, to: nil))
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: onScreen.midX, y: onScreen.midY)) }) ?? window.screen else { return }
        let bounds = editor.convert(window.convertFromScreen(screen.visibleFrame), from: nil)
        let words = Words(pin, now: Date()), ui = Settings.shared.data.ui, style = ui.markStyle.pin
        let rim = style.side > 0 ? square.height * style.rimWidth / style.side : 0
        let body = square.insetBy(dx: -(rim + Self.pastRim), dy: -(rim + Self.pastRim))
        let size = measure(words, maker: pin.maker, width: max(ui.pinHoverWidth, body.width), least: body.height)
        let facesRight = orientation == .upRight || orientation == .downRight, facesUp = orientation == .upRight || orientation == .upLeft
        var right = facesRight, up = facesUp
        if right, body.minX + size.width > bounds.maxX, body.maxX - size.width >= bounds.minX { right = false }
        else if !right, body.maxX - size.width < bounds.minX, body.minX + size.width <= bounds.maxX { right = true }
        if up, body.maxY - size.height < bounds.minY, body.minY + size.height <= bounds.maxY { up = false }
        else if !up, body.minY + size.height > bounds.maxY, body.maxY - size.height >= bounds.minY { up = true }
        let card = CGRect(x: right ? body.minX : body.maxX - size.width, y: up ? body.maxY - size.height : body.minY,
                          width: size.width, height: size.height)
        let room = body.union(card).insetBy(dx: -Self.shadowRoom, dy: -Self.shadowRoom)
        let panelFrame = window.convertToScreen(editor.convert(room, to: nil))
        if panel.frame != panelFrame { panel.setFrame(panelFrame, display: false) }
        if panel.parent !== window { window.addChildWindow(panel, ordered: .above) }
        guard shown.map({ $0.words != words || $0.maker != pin.maker || $0.start != body || $0.card != card }) ?? true else {
            growth.animate(to: 1, duration: Settings.shared.motionUI.pinHoverDuration)
            return
        }
        tipCorner = (right: !right, bottom: up)
        sharp = right == facesRight && up == facesUp
        shown = (words, pin.maker, body, card, room)
        content.frame.size = card.size
        glass.maskImage = Self.mask(radius: body.height / 2, sharp: sharp ? tipCorner : nil)
        grow(to: growth.value)
        growth.animate(to: 1, duration: Settings.shared.motionUI.pinHoverDuration)
    }

    /// Goes back into the teardrop, then off the screen.
    func leave() {
        growth.animate(to: 0, duration: Settings.shared.motionUI.pinHoverDuration) { [weak self] in self?.close() }
    }

    /// Goes off the screen at once.
    func close() {
        growth.stop()
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        removeFromSuperview()
    }

    /// Sets the words and the avatar, lays them out across a card `width` wide, and answers the card's
    /// size, at least `least` tall.
    private func measure(_ words: Words, maker: PinMaker, width: CGFloat, least: CGFloat) -> CGSize {
        let ui = Settings.shared.data.ui, inset = ui.pinPopoverInset, gap = ui.pinNameGap, side = ui.pinAvatarSize
        name.stringValue = words.name
        time.stringValue = words.time ?? ""
        firstLine.stringValue = words.firstLine
        replies.stringValue = words.replies ?? ""
        replies.isHidden = words.replies == nil
        avatar.frame = CGRect(x: inset, y: inset, width: side, height: side)
        avatar.layer?.cornerRadius = side / 2
        Self.paint(avatar, as: maker)
        let column = max(width - 2 * inset, 0), afterAvatar = inset + side + gap
        let nameSize = name.fittingSize, nameWidth = min(nameSize.width, max(column - side - gap, 0))
        name.frame = CGRect(x: afterAvatar, y: avatar.frame.midY - nameSize.height / 2, width: nameWidth, height: nameSize.height)
        let timeSize = time.fittingSize
        let timeTop = name.frame.minY + name.firstBaselineOffsetFromTop - time.firstBaselineOffsetFromTop
        time.frame = CGRect(x: name.frame.maxX + gap, y: timeTop, width: max(inset + column - name.frame.maxX - gap, 0), height: timeSize.height)
        let topLine = max(avatar.frame.maxY, name.frame.maxY)
        firstLine.frame = CGRect(x: inset, y: topLine + ui.pinWordsGap, width: column, height: firstLine.fittingSize.height)
        var bottom = firstLine.frame.maxY
        if words.replies != nil {
            replies.frame = CGRect(x: inset, y: bottom + Self.rowGap, width: column, height: replies.fittingSize.height)
            bottom = replies.frame.maxY
        }
        return CGSize(width: width, height: max(least, bottom + inset))
    }

    private static let rowGap: CGFloat = 2
    /// How far the card reaches past the teardrop's rim, so the rim's soft outer edge stays under the
    /// card instead of showing as a white hairline along it.
    private static let pastRim: CGFloat = 1
    /// How far the panel reaches past the card on every side, so the card's shadow is not cut off.
    private static let shadowRoom: CGFloat = 24

    /// A writer's avatar. The person's is their macOS account picture, or their initial on their pins'
    /// colour when the account has none. An agent's is what its pin wears (`PinFace`) on its pins'
    /// colour: its logo, or the first letter of its name, in the words' colour. `avatar` is layer-backed
    /// and round. The pin's popover shows the same beside each comment.
    static func paint(_ avatar: NSImageView, as maker: PinMaker) {
        let style = Settings.shared.data.ui.markStyle.painting(maker)
        switch (maker, PinFace(maker)) {
        case (.person, _):
            avatar.image = accountPicture ?? letter(accountInitial, on: style.personColor, in: style.wordColor)
        case (.agent, .letter(let first)):
            avatar.image = letter(first, on: style.agentColor, in: style.wordColor)
        case (.agent(let agent), _):
            avatar.image = logo(agent, on: style.agentColor, in: style.wordColor, filling: style.pin.logoSize)
        }
    }

    /// The picture of the macOS account the app runs in, as Users & Groups shows it.
    private static let accountPicture = CBIdentity(name: NSUserName(), authority: .default())?.image

    private static let accountInitial: String = {
        let name = NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()
        return name.first.map { String($0).uppercased() } ?? "?"
    }()

    /// `letter` centred on a square of `fill`, which the avatar's round layer clips to a coin.
    private static func letter(_ letter: String, on fill: SRGB, in color: SRGB) -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor(srgbRed: fill.red, green: fill.green, blue: fill.blue, alpha: 1).setFill()
            rect.fill()
            let words = NSAttributedString(string: letter, attributes: [
                .font: NSFont.systemFont(ofSize: rect.height * 0.55, weight: .semibold),
                .foregroundColor: NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1),
            ])
            let size = words.size()
            words.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
            return true
        }
    }

    /// The logo of the agent named `name` (`AgentLogos`, the fallback symbol for one without a name) in
    /// `color`, `fraction` of the side across as on its pin, centred on a square of `fill`, which the
    /// avatar's round layer clips to a coin.
    private static func logo(_ name: String, on fill: SRGB, in color: SRGB, filling fraction: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor(srgbRed: fill.red, green: fill.green, blue: fill.blue, alpha: 1).setFill()
            rect.fill()
            guard let shape = AgentLogos.shared.image(for: name), let ctx = NSGraphicsContext.current?.cgContext else { return true }
            let side = rect.width * fraction
            let box = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            ctx.draw(shape, in: box)
            ctx.setBlendMode(.sourceIn)
            ctx.setFillColor(NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1).cgColor)
            ctx.fill(box)
            ctx.endTransparencyLayer()
            return true
        }
    }

    /// The card `progress` of the way from the teardrop to its whole size, the avatar and words fading in.
    private func grow(to progress: CGFloat) {
        guard let shown else { return }
        let p = min(max(progress, 0), 1)
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * p }
        frame = CGRect(x: mix(shown.start.minX, shown.card.minX) - shown.room.minX, y: mix(shown.start.minY, shown.card.minY) - shown.room.minY,
                       width: mix(shown.start.width, shown.card.width), height: mix(shown.start.height, shown.card.height))
        clip.frame = bounds
        content.frame.origin = CGPoint(x: tipCorner.right ? bounds.width - shown.card.width : 0,
                                       y: tipCorner.bottom ? bounds.height - shown.card.height : 0)
        panel.alphaValue = min(1, p * 2)
        content.alphaValue = p
        layer?.shadowPath = Self.outline(of: CGRect(origin: .zero, size: bounds.size), radius: shown.start.height / 2, sharp: nil)
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
