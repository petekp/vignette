import AppKit

/// An agent's title above the image in the editor: the title in semibold, the description under it
/// in the same colour, fainter, drawn straight on the editor's backdrop, the blur and its dim. Its
/// ink is white or black, whichever stands out more from that backdrop (`TitleInk`). Its left edge
/// is where the frame's top edge comes out of its rounded corner, and it wraps at
/// `StackLayout.titleWrapWidth`. Its text keeps its size at any zoom. It lives in the annotator's
/// window beside the frame, and `AnnotationController.moveFrame` places it, so it moves with the
/// frame in the same commit. Only `AnnotationController` makes one, so nothing outside the editor
/// draws it: not a card, a rendering, a stitch or a send. The flight home carries a picture of it
/// (`picture`).
@MainActor
final class AgentTitleView: NSView {
    private let titleField = AgentTitleView.label()
    private let descriptionField = AgentTitleView.label()
    private(set) var title: AgentTitle?
    private(set) var ink = TitleInk.white
    private var ui = UITweaks()
    private var visible = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        alphaValue = 0
        addSubview(titleField)
        addSubview(descriptionField)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// The image's title, or nil for an image without one, which hides the block at once.
    func set(_ title: AgentTitle?, ui: UITweaks) {
        self.title = title
        self.ui = ui
        if title == nil { show(false, duration: 0) }
        applyText()
    }

    /// Draws the text in `ink`.
    func set(ink: TitleInk) {
        self.ink = ink
        applyText()
    }

    private func applyText() {
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
        guard let title else { return }
        let parts = Self.parts(of: title, wrap: wrap, ui: ui)
        let size = Self.size(of: parts, ui: ui)
        self.frame = NSRect(origin: Self.origin(above: frame, ui: ui), size: size)
        titleField.isHidden = parts.title == .zero
        descriptionField.isHidden = parts.description == .zero
        var top = bounds.height
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

    /// The block's bottom-left corner above `frame`.
    static func origin(above frame: NSRect, ui: UITweaks) -> NSPoint {
        NSPoint(x: frame.minX + ui.annotationCornerRadius, y: frame.maxY + ui.agentTitleGap)
    }

    /// Fades the block in or out over `duration`. A later call takes over the fade.
    func show(_ shown: Bool, duration: Double) {
        let target: CGFloat = shown && title != nil ? 1 : 0
        visible = target == 1
        guard alphaValue != target, duration > 0 else { return fade.set(target) }
        fade.animate(to: target, duration: duration)
    }

    private lazy var fade = Tween(initial: 0) { [weak self] alpha in self?.alphaValue = alpha }

    /// The block as drawn, at full opacity, or nil while none of it shows.
    func picture() -> NSImage? {
        guard title != nil, alphaValue > 0, let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
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
    static func spaceAbove(_ title: AgentTitle, wrap: CGFloat, ui: UITweaks) -> CGFloat {
        size(of: parts(of: title, wrap: wrap, ui: ui), ui: ui).height + ui.agentTitleGap
    }

    /// The least room between the block and the top of the zoom's room: twice the gap under it.
    static func marginAbove(_ ui: UITweaks) -> CGFloat { 2 * ui.agentTitleGap }

    /// The block's size: as wide as its longest line, and as tall as its lines.
    private static func size(of parts: (title: NSSize, description: NSSize), ui: UITweaks) -> NSSize {
        let both = parts.title != .zero && parts.description != .zero
        return NSSize(width: ceil(max(parts.title.width, parts.description.width)),
                      height: ceil(parts.title.height + parts.description.height + (both ? ui.agentTitleLineGap : 0)))
    }

    /// Each part's size as its label draws it, wrapping at `wrap`. `.zero` for a part the title lacks.
    private static func parts(of title: AgentTitle, wrap: CGFloat, ui: UITweaks) -> (title: NSSize, description: NSSize) {
        let wrap = max(1, wrap)
        func measure(_ string: String?, _ font: NSFont) -> NSSize {
            guard let string else { return .zero }
            measuring.attributedStringValue = text(string, font, .labelColor)
            let size = measuring.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: wrap, height: .greatestFiniteMagnitude))
            return NSSize(width: min(wrap, ceil(size.width)), height: ceil(size.height))
        }
        return (measure(title.title, titleFont(ui)), measure(title.description, descriptionFont(ui)))
    }

    private static let measuring = label()

    private static func label() -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: "")
        field.isSelectable = false
        field.lineBreakMode = .byWordWrapping
        field.cell?.truncatesLastVisibleLine = false
        return field
    }

    private static func titleFont(_ ui: UITweaks) -> NSFont { .systemFont(ofSize: ui.agentTitleSize, weight: .semibold) }
    private static func descriptionFont(_ ui: UITweaks) -> NSFont { .systemFont(ofSize: ui.agentDescriptionSize) }

    private static func text(_ string: String?, _ font: NSFont, _ colour: NSColor) -> NSAttributedString {
        NSAttributedString(string: string ?? "", attributes: [.font: font, .foregroundColor: colour])
    }
}
