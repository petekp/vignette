import AppKit

/// What an agent's file says above the image in the editor: the sender's line, the agent's logo and
/// "From <sender>" as the card's tab says it, in the secondary label colour; then the title in
/// semibold and the description under it in the same colour, fainter. A file without a title shows
/// the sender's line alone. The block is drawn straight on the editor's backdrop, the blur and its
/// dim. Its ink is white or black, whichever stands out more from that backdrop (`TitleInk`), and the
/// sender's line takes the label colour of the appearance that matches it. Its left edge
/// is where the frame's top edge comes out of its rounded corner, and it wraps at
/// `StackLayout.titleWrapWidth`. Its text keeps its size at any zoom. It lives in the annotator's
/// window beside the frame, and `AnnotationController.moveFrame` places it, so it moves with the
/// frame in the same commit. Only `AnnotationController` makes one, so nothing outside the editor
/// draws it: not a card, a rendering, a stitch or a send. The flight home carries a picture of it
/// (`picture`).
@MainActor
final class AgentTitleView: NSView {
    /// Who the file is from: the vendor whose logo the line shows, and the tab's words.
    struct Sender: Equatable {
        let agent: String
        let words: String

        /// The sender of the file at `url`, or nil for a file no agent pushed.
        static func of(_ url: URL) -> Sender? {
            Agent.of(url).map { Sender(agent: $0, words: Agent.label(for: $0, sender: Agent.sender(of: url))) }
        }
    }

    /// What the block says: nil for a file no agent pushed, which has no block.
    struct Content: Equatable {
        var sender: Sender?
        var title: AgentTitle?

        static func of(_ url: URL) -> Content? {
            let content = Content(sender: .of(url), title: Agent.title(of: url))
            return content.sender == nil && content.title == nil ? nil : content
        }
    }

    private let logoView = NSImageView()
    private let senderField = AgentTitleView.label(wrapping: false)
    private let titleField = AgentTitleView.label()
    private let descriptionField = AgentTitleView.label()
    private(set) var content: Content?
    private var title: AgentTitle? { content?.title }
    private(set) var ink = TitleInk.white
    private var ui = UITweaks()
    private var visible = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        alphaValue = 0
        logoView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(logoView)
        addSubview(senderField)
        addSubview(titleField)
        addSubview(descriptionField)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// What the image's block says, or nil for an image no agent pushed, which hides the block at once.
    func set(_ content: Content?, ui: UITweaks) {
        self.content = content
        self.ui = ui
        if content == nil { show(false, duration: 0) }
        applyText()
    }

    /// Draws the text in `ink`.
    func set(ink: TitleInk) {
        self.ink = ink
        applyText()
    }

    private func applyText() {
        appearance = NSAppearance(named: ink == .white ? .darkAqua : .aqua)
        let logo = content?.sender.flatMap { Agent.logo(for: $0.agent) }
        logoView.image = logo ?? NSImage(systemSymbolName: Agent.fallbackSymbol, accessibilityDescription: nil)
        logoView.contentTintColor = .secondaryLabelColor
        senderField.attributedStringValue = Self.text(content?.sender?.words, Self.senderFont(ui), .secondaryLabelColor)
        let colour = ink == .white ? NSColor.white : NSColor.black
        titleField.attributedStringValue = Self.text(title?.title, Self.titleFont(ui), colour)
        descriptionField.attributedStringValue = Self.text(title?.description, Self.descriptionFont(ui),
                                                           colour.withAlphaComponent(Self.descriptionOpacity))
    }

    /// How much fainter the description is than the title.
    private static let descriptionOpacity: CGFloat = 0.72

    /// Puts the block above `frame`, in this view's superview's coordinates: its left edge where the
    /// frame's top edge comes out of its rounded corner, its bottom `ui.agentTitleGap` above the
    /// frame's top, and its text wrapping at `wrap`.
    func place(above frame: NSRect, wrap: CGFloat, ui: UITweaks) {
        guard let content else { return }
        let parts = Self.parts(of: content, wrap: wrap, ui: ui)
        let size = Self.size(of: parts, ui: ui)
        self.frame = NSRect(x: frame.minX + ui.annotationCornerRadius, y: frame.maxY + ui.agentTitleGap,
                            width: size.width, height: size.height)
        logoView.isHidden = parts.sender == .zero
        senderField.isHidden = parts.sender == .zero
        titleField.isHidden = parts.title == .zero
        descriptionField.isHidden = parts.description == .zero
        var top = bounds.height
        if parts.sender != .zero {
            let line = max(parts.sender.height, ui.agentSenderLogoSize)
            top -= line
            logoView.frame = NSRect(x: 0, y: top + (line - ui.agentSenderLogoSize) / 2,
                                    width: ui.agentSenderLogoSize, height: ui.agentSenderLogoSize)
            senderField.frame = NSRect(x: ui.agentSenderLogoSize + ui.agentSenderLogoGap, y: top + (line - parts.sender.height) / 2,
                                       width: parts.sender.width, height: parts.sender.height)
            top -= ui.agentSenderGap
        }
        if parts.title != .zero {
            top -= parts.title.height
            titleField.frame = NSRect(x: 0, y: top, width: parts.title.width, height: parts.title.height)
            top -= ui.agentTitleLineGap
        }
        if parts.description != .zero {
            descriptionField.frame = NSRect(x: 0, y: top - parts.description.height,
                                            width: parts.description.width, height: parts.description.height)
        }
    }

    /// Fades the block in or out over `duration`. A later call takes over the fade.
    func show(_ shown: Bool, duration: Double) {
        let target: CGFloat = shown && content != nil ? 1 : 0
        visible = target == 1
        guard alphaValue != target, duration > 0 else { return fade.set(target) }
        fade.animate(to: target, duration: duration)
    }

    private lazy var fade = Tween(initial: 0) { [weak self] alpha in self?.alphaValue = alpha }

    /// The block as drawn, at full opacity, or nil while none of it shows.
    func picture() -> NSImage? {
        guard content != nil, alphaValue > 0, let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    /// The block's frame for `[state]`, in the window's coordinates, or nil while it is not shown.
    var shownFrame: NSRect? { visible ? frame : nil }

    // MARK: Measuring

    /// How much room the block takes above the frame when it wraps at `wrap`: its own height and the
    /// gap under it. What the editor's room keeps for it (`StackLayout.annotationFrame`,
    /// `AnnotationController.prepare`).
    static func spaceAbove(_ content: Content, wrap: CGFloat, ui: UITweaks) -> CGFloat {
        size(of: parts(of: content, wrap: wrap, ui: ui), ui: ui).height + ui.agentTitleGap
    }

    /// The least room between the block and the top of the zoom's room: twice the gap under it.
    static func marginAbove(_ ui: UITweaks) -> CGFloat { 2 * ui.agentTitleGap }

    private typealias Parts = (sender: NSSize, title: NSSize, description: NSSize)

    /// The block's size: as wide as its widest line, and as tall as its lines.
    private static func size(of parts: Parts, ui: UITweaks) -> NSSize {
        let senderLine = parts.sender == .zero ? NSSize.zero
            : NSSize(width: ui.agentSenderLogoSize + ui.agentSenderLogoGap + parts.sender.width,
                     height: max(parts.sender.height, ui.agentSenderLogoSize))
        let titled = parts.title != .zero || parts.description != .zero
        let both = parts.title != .zero && parts.description != .zero
        let height = senderLine.height + (senderLine != .zero && titled ? ui.agentSenderGap : 0)
            + parts.title.height + parts.description.height + (both ? ui.agentTitleLineGap : 0)
        return NSSize(width: ceil(max(senderLine.width, parts.title.width, parts.description.width)), height: ceil(height))
    }

    /// Each part's size as its label draws it, the title and description wrapping at `wrap` and the
    /// sender's words cut short beside the logo. `.zero` for a part the content lacks.
    private static func parts(of content: Content, wrap: CGFloat, ui: UITweaks) -> Parts {
        let wrap = max(1, wrap)
        func measure(_ string: String?, _ font: NSFont, width: CGFloat) -> NSSize {
            guard let string, let cell = measuring.cell else { return .zero }
            measuring.attributedStringValue = text(string, font, .labelColor)
            let size = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude))
            return NSSize(width: min(width, ceil(size.width)), height: ceil(size.height))
        }
        var sender = NSSize.zero
        if let words = content.sender?.words, let cell = measuringLine.cell {
            measuringLine.attributedStringValue = text(words, senderFont(ui), .labelColor)
            let size = cell.cellSize
            sender = NSSize(width: min(max(1, wrap - ui.agentSenderLogoSize - ui.agentSenderLogoGap), ceil(size.width)),
                            height: ceil(size.height))
        }
        return (sender, measure(content.title?.title, titleFont(ui), width: wrap),
                measure(content.title?.description, descriptionFont(ui), width: wrap))
    }

    private static let measuring = label()
    private static let measuringLine = label(wrapping: false)

    private static func label(wrapping: Bool = true) -> NSTextField {
        let field = wrapping ? NSTextField(wrappingLabelWithString: "") : NSTextField(labelWithString: "")
        field.isSelectable = false
        field.lineBreakMode = wrapping ? .byWordWrapping : .byTruncatingTail
        field.cell?.truncatesLastVisibleLine = !wrapping
        return field
    }

    /// The subheadline text style in semibold, at `ui.agentSenderSize`: a byline under the title's size.
    private static func senderFont(_ ui: UITweaks) -> NSFont {
        let semibold = NSFont.preferredFont(forTextStyle: .subheadline).fontDescriptor
            .addingAttributes([.traits: [NSFontDescriptor.TraitKey.weight: NSFont.Weight.semibold]])
        return NSFont(descriptor: semibold, size: ui.agentSenderSize) ?? .systemFont(ofSize: ui.agentSenderSize, weight: .semibold)
    }

    private static func titleFont(_ ui: UITweaks) -> NSFont { .systemFont(ofSize: ui.agentTitleSize, weight: .semibold) }
    private static func descriptionFont(_ ui: UITweaks) -> NSFont { .systemFont(ofSize: ui.agentDescriptionSize) }

    private static func text(_ string: String?, _ font: NSFont, _ colour: NSColor) -> NSAttributedString {
        NSAttributedString(string: string ?? "", attributes: [.font: font, .foregroundColor: colour])
    }
}
