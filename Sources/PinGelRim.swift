import AppKit

/// A rim of gel round a pin's hover card or popover, in the pin's colour: a rod `ui.pinGelRim` wide
/// along the inside of the card's edge or of the popover's outline.
@MainActor
final class PinGelRim: NSView {
    /// Where the rim runs.
    enum Edge: Equatable {
        /// Along the view's edge, its corners `radius` round but the one `sharp` names.
        case box(radius: CGFloat, sharp: PinGel.Corner?)
        /// Along the outline of the popover the view is in, its arrow included. The view covers the
        /// popover's frame and reads the outline from the shape layer AppKit draws the popover's glass
        /// with, so the rim follows it as it grows and as its arrow moves. Where AppKit draws no such
        /// layer, as before macOS 26, there is no rim.
        case popover
    }

    private let gel = PinGel(scale: 2)
    private var wearing: (color: SRGB, edge: Edge)?
    /// The popover's outline, watched for its changes.
    private weak var outline: CAShapeLayer? {
        didSet { if outline == nil { outlineWatch = nil } }
    }
    private var outlineWatch: NSKeyValueObservation?

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        gel.host = self
        layer?.addSublayer(gel)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func wear(_ color: SRGB, edge: Edge) {
        guard wearing.map({ $0.color != color || $0.edge != edge }) ?? true else { return }
        wearing = (color, edge)
        autoresizingMask = edge == .popover ? [] : [.width, .height]
        place()
    }

    /// The popover came up: its outline is read again, since AppKit may give the glass its shape
    /// layer only as it shows.
    func popoverShown() {
        outline = nil
        place()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // A popover's rim sets its own frame in `place`, which goes on from there.
        if wearing?.edge != .popover { place() }
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        if wearing?.edge == .popover { place() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        gel.setScale(window?.backingScaleFactor ?? 2)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        place()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { gel.setScale(window.backingScaleFactor) }
        outline = nil
        place()
    }

    private func place() {
        guard let wearing else { return }
        let width = Settings.shared.data.ui.pinGelRim
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let tint = PinGel.Tint(color: wearing.color, deepness: dark ? 0 : 1)
        switch wearing.edge {
        case .box(let radius, let sharp):
            guard bounds.width > 0, bounds.height > 0 else { return }
            let rect = bounds.insetBy(dx: width / 2, dy: width / 2)
            gel.show([PinGel.Shape(rect: rect, radius: max(radius - width / 2, 0), sharp: sharp, rod: width, tint: tint)], drifting: false)
        case .popover:
            guard let line = popoverLine(inset: width / 2) else {
                gel.show([], drifting: false)
                return
            }
            gel.show([.rod(along: line, width: width, tint: tint)], drifting: false)
        }
    }

    /// The popover's outline in this view's coordinates, moved `inset` in, after the view is made to
    /// cover the popover's frame.
    private func popoverLine(inset: CGFloat) -> [CGPoint]? {
        guard let superview, window != nil else { return nil }
        var frameView = superview
        while let above = frameView.superview { frameView = above }
        guard frameView !== superview, let frameLayer = frameView.layer else { return nil }
        let cover = superview.convert(frameView.bounds, from: frameView)
        if frame != cover { frame = cover }
        let shape = outline ?? findOutline(in: frameView)
        guard let shape, let path = shape.path else { return nil }
        let points = Self.points(of: path) { self.convert(shape.convert($0, to: frameLayer), from: frameView) }
        return points.flatMap { Self.inset($0, by: inset) }
    }

    /// The shape layer under the popover's content whose path holds the content, which AppKit draws
    /// the glass in, watched so the rim moves when the path changes.
    private func findOutline(in frameView: NSView) -> CAShapeLayer? {
        guard let content = sequence(first: self as NSView, next: { $0.superview }).first(where: { $0.superview === frameView }),
              let frameLayer = frameView.layer else { return nil }
        let holds = content.frame.insetBy(dx: 1, dy: 1)
        func search(_ layer: CALayer) -> CAShapeLayer? {
            if layer === content.layer { return nil }
            if let shape = layer as? CAShapeLayer, let path = shape.path,
               shape.convert(path.boundingBoxOfPath, to: frameLayer).contains(holds) { return shape }
            for sublayer in layer.sublayers ?? [] {
                if let found = search(sublayer) { return found }
            }
            return nil
        }
        guard let found = search(frameLayer) else { return nil }
        outline = found
        outlineWatch = found.observe(\.path, options: []) { [weak self] _, _ in
            guard let rim = self else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { rim.place() } }
        }
        return found
    }
}
