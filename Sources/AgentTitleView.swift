import AppKit

/// An agent's title above the image in the editor: the title in semibold, the description under it
/// in the secondary label colour, on the toolbar's glass, left-aligned on the frame and wrapping at
/// its width. Its text keeps its size at any zoom. It lives in the annotator's window beside the
/// frame, and `AnnotationController.moveFrame` places it, so it moves with the frame in the same
/// commit. Nothing else draws it: not a card, a flight, a rendering, a stitch or a send.
@MainActor
final class AgentTitleView: NSView {
    private let glass = NSVisualEffectView()
    private let tint = NSView()
    private let titleField = AgentTitleView.label()
    private let descriptionField = AgentTitleView.label()
    private(set) var title: AgentTitle?
    private var visible = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        alphaValue = 0
        // The toolbar's glass: a blur of what is behind the window under a neutral grey, so the
        // text reads over a light picture behind the dim as well as a dark one.
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = Self.cornerRadius
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 0.5
        tint.wantsLayer = true
        addSubview(glass)
        glass.addSubview(tint)
        glass.addSubview(titleField)
        glass.addSubview(descriptionField)
        applyAppearance()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    private func applyAppearance() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        tint.layer?.backgroundColor = NSColor(white: dark ? 0.14 : 0.95, alpha: 0.72).cgColor
        glass.layer?.borderColor = NSColor.black.withAlphaComponent(dark ? 0.35 : 0.12).cgColor
    }

    /// The toolbar's corner, so the two read as one set.
    private static let cornerRadius: CGFloat = 12

    /// The image's title, or nil for an image without one, which hides the block at once.
    func set(_ title: AgentTitle?, ui: UITweaks) {
        self.title = title
        titleField.attributedStringValue = Self.text(title?.title, Self.titleFont(ui), .labelColor)
        descriptionField.attributedStringValue = Self.text(title?.description, Self.descriptionFont(ui), .secondaryLabelColor)
        if title == nil { show(false, duration: 0) }
    }

    /// Puts the block above `frame`, in this view's superview's coordinates: its left edge on the
    /// frame's, its bottom `ui.agentTitleGap` above the frame's top, and its text wrapping at the
    /// frame's width.
    func place(above frame: NSRect, ui: UITweaks) {
        guard let title else { return }
        let size = Self.size(of: title, width: frame.width, ui: ui)
        self.frame = NSRect(x: frame.minX, y: frame.maxY + ui.agentTitleGap, width: size.width, height: size.height)
        glass.frame = bounds
        tint.frame = glass.bounds
        let parts = Self.parts(of: title, width: frame.width, ui: ui)
        var top = bounds.height - ui.agentTitlePaddingY
        titleField.isHidden = parts.title == .zero
        descriptionField.isHidden = parts.description == .zero
        if parts.title != .zero {
            top -= parts.title.height
            titleField.frame = NSRect(x: ui.agentTitlePaddingX, y: top, width: parts.title.width, height: parts.title.height)
            top -= ui.agentTitleLineGap
        }
        if parts.description != .zero {
            descriptionField.frame = NSRect(x: ui.agentTitlePaddingX, y: top - parts.description.height,
                                            width: parts.description.width, height: parts.description.height)
        }
    }

    /// Fades the block in or out over `duration`, then answers, also when a later fade takes over.
    /// At 0, or with nothing to fade, it answers at once.
    func show(_ shown: Bool, duration: Double, then done: (() -> Void)? = nil) {
        let target: CGFloat = shown && title != nil ? 1 : 0
        visible = target == 1
        guard alphaValue != target, duration > 0 else {
            fade.set(target)
            done?()
            return
        }
        fade.animate(to: target, duration: duration) { done?() }
    }

    private lazy var fade = Tween(initial: 0) { [weak self] alpha in self?.alphaValue = alpha }

    /// The block's frame for `[state]`, in the window's coordinates, or nil while it is not shown.
    var shownFrame: NSRect? { visible ? frame : nil }

    // MARK: Measuring

    /// How much room the block takes above a frame `width` wide: its own height and the gap under
    /// it. What the editor's room keeps for it (`StackLayout.annotationFrame`, `AnnotationController.prepare`).
    static func spaceAbove(_ title: AgentTitle, width: CGFloat, ui: UITweaks) -> CGFloat {
        size(of: title, width: width, ui: ui).height + ui.agentTitleGap
    }

    /// The block's size when it wraps at a frame `width` wide: as wide as its longest line, padding
    /// included, and never wider than the frame.
    static func size(of title: AgentTitle, width: CGFloat, ui: UITweaks) -> NSSize {
        let parts = parts(of: title, width: width, ui: ui)
        let both = parts.title != .zero && parts.description != .zero
        let text = NSSize(width: max(parts.title.width, parts.description.width),
                          height: parts.title.height + parts.description.height + (both ? ui.agentTitleLineGap : 0))
        return NSSize(width: ceil(text.width + 2 * ui.agentTitlePaddingX), height: ceil(text.height + 2 * ui.agentTitlePaddingY))
    }

    /// Each part's size as its label draws it, wrapping at the frame's width less the padding.
    /// `.zero` for a part the title lacks.
    private static func parts(of title: AgentTitle, width: CGFloat, ui: UITweaks) -> (title: NSSize, description: NSSize) {
        let wrap = max(1, width - 2 * ui.agentTitlePaddingX)
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
