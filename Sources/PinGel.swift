import AppKit
import Metal
import QuartzCore

/// A comment's gel in the editor: live ink's material (`InkGel.metal`) on a pin's teardrop, on its
/// area's outline and on the rim of its hover card and popover, in the pin's colour and lit from the
/// pointer. Each shape is a rounded box: a teardrop is its square with every corner but the tip's
/// rounded to half its side, bevelled and domed on top, and an outline or a rim is a rod along a
/// box's edge. The shapes of one layer are one surface, as live ink's line and its head are, so an
/// area and its pin join. It draws on live ink's clock (`InkClock`), which redraws it as the pointer
/// moves and while its material drifts.
@MainActor
final class PinGel: CALayer, GelLayer {
    /// A corner of a box, with y down.
    enum Corner: Int {
        case topLeft, topRight, bottomRight, bottomLeft

        init(right: Bool, bottom: Bool) {
            self = bottom ? (right ? .bottomRight : .bottomLeft) : (right ? .topRight : .topLeft)
        }
    }

    struct Shape: Equatable {
        var rect: CGRect
        var radius: CGFloat
        /// The corner drawn square, as a teardrop's tip is.
        var sharp: Corner?
        /// The rod's width along the box's edge, or nil for the box itself.
        var rod: CGFloat?

        /// The body of `teardrop`.
        static func body(of teardrop: PinTeardrop) -> Shape {
            let square = teardrop.square
            let tip = Corner(right: teardrop.tip.x > square.midX, bottom: teardrop.tip.y > square.midY)
            return Shape(rect: square, radius: min(square.width, square.height) / 2, sharp: tip, rod: nil)
        }

        /// A rod `width` wide centred on `rect`'s edge, square at its inner corners.
        static func outline(_ rect: CGRect, width: CGFloat) -> Shape {
            Shape(rect: rect, radius: 0, sharp: nil, rod: width)
        }

        func offsetBy(dx: CGFloat, dy: CGFloat) -> Shape {
            var moved = self
            moved.rect = rect.offsetBy(dx: dx, dy: dy)
            return moved
        }
    }

    struct Look: Equatable {
        var color: SRGB
        /// 0 for the gel's light edge, over dark content, and 1 for its deep edge, over light content.
        var deepness: CGFloat
        /// The radius of the dome on a pin's top, in pt.
        var dome: CGFloat
        /// Whether the material keeps drifting, as it does on an open pin's outline.
        var drifting: Bool
    }

    /// The view whose window the gel is shown in, for the pointer's place over it.
    weak var host: NSView?
    private let gel = CAMetalLayer()
    /// The shapes, from the corner of the gel's frame, and how they look.
    private var shown: (shapes: [Shape], look: Look)?
    private var vertices: MTLBuffer?
    private var vertexCount = 0
    private var targets: (field: MTLTexture, depth: MTLTexture)?
    private(set) var needsGel = false
    private var clocked = false

    init(scale: CGFloat) {
        super.init()
        anchorPoint = .zero
        gel.anchorPoint = .zero
        gel.actions = ["position": NSNull(), "bounds": NSNull()]
        gel.isOpaque = false
        gel.framebufferOnly = true
        gel.pixelFormat = .bgra8Unorm
        gel.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        gel.maximumDrawableCount = 3
        gel.presentsWithTransaction = true
        gel.device = InkGel.metal?.device
        addSublayer(gel)
        setScale(scale)
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setScale(_ scale: CGFloat) {
        guard scale != contentsScale else { return }
        contentsScale = scale
        gel.contentsScale = scale
        if let shown { show(shown.shapes.map { $0.offsetBy(dx: gel.frame.minX, dy: gel.frame.minY) }, look: shown.look, redraw: true) }
    }

    /// Draws `shapes`, in this layer's coordinates, as `look` says, unless they are drawn already. Shapes
    /// that only moved together move the drawing, which then waits for the clock to light it from the
    /// pointer's new place.
    func show(_ shapes: [Shape], look: Look) {
        show(shapes, look: look, redraw: false)
    }

    private func show(_ shapes: [Shape], look: Look, redraw: Bool) {
        let ui = Settings.shared.data.ui
        guard let reach = shapes.map({ $0.rect.insetBy(dx: -($0.rod ?? 0), dy: -($0.rod ?? 0)) }).reduce(nil, { $0?.union($1) ?? $1 }) else {
            shown = nil
            gel.isHidden = true
            return
        }
        let scale = contentsScale
        let margin = ui.inkGelGlowRadius + 2
        let wide = reach.insetBy(dx: -margin, dy: -margin)
        let frame = CGRect(x: (wide.minX * scale).rounded(.down) / scale, y: (wide.minY * scale).rounded(.down) / scale,
                           width: (wide.width * scale).rounded(.up) / scale, height: (wide.height * scale).rounded(.up) / scale)
        let local = shapes.map { $0.offsetBy(dx: -frame.minX, dy: -frame.minY) }
        let same = !redraw && shown?.shapes == local && shown?.look == look && gel.frame.size == frame.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gel.isHidden = false
        gel.frame = frame
        CATransaction.commit()
        if !clocked {
            clocked = true
            InkClock.shared.add(self)
        }
        guard !same else {
            needsGel = true
            InkClock.shared.wake()
            return
        }
        shown = (local, look)
        vertices = nil
        // The new shape and its frame reach the screen in the same transaction, as live ink's do.
        drawNow()
    }

    private func drawNow() {
        guard let frame = encode(at: CACurrentMediaTime(), time: InkClock.shared.time) else { return }
        frame.commands.commit()
        frame.commands.waitUntilScheduled()
        frame.drawable.present()
    }

    // MARK: GelLayer

    var readsScreen: Bool { false }
    var keepsDrifting: Bool { shown?.look.drifting == true && isVisible }

    var isVisible: Bool {
        guard let window = host?.window, window.isVisible, window.occlusionState.contains(.visible), !gel.isHidden else { return false }
        var layer: CALayer? = self
        while let current = layer {
            if current.isHidden || current.opacity <= 0 { return false }
            if current.superlayer == nil { return current !== self }
            layer = current.superlayer
        }
        return false
    }

    func isEasing(at now: CFTimeInterval) -> Bool { false }

    func settingsChanged() {
        vertices = nil
        needsGel = true
    }

    func backdropChanged() {}

    func encode(at now: CFTimeInterval, time: CFTimeInterval) -> (commands: MTLCommandBuffer, drawable: CAMetalDrawable)? {
        guard let metal = InkGel.metal, let shown, !gel.isHidden, gel.bounds.width > 0, gel.bounds.height > 0 else { return nil }
        needsGel = false
        let ui = Settings.shared.data.ui
        let scale = contentsScale
        let size = CGSize(width: (gel.bounds.width * scale).rounded(), height: (gel.bounds.height * scale).rounded())
        if gel.drawableSize != size { gel.drawableSize = size }
        if vertices == nil { build(shown.shapes, margin: ui.inkGelGlowRadius + 2, device: metal.device) }
        let width = Int(size.width), height = Int(size.height)
        if targets.map({ $0.field.width != width || $0.field.height != height }) ?? true {
            targets = InkGel.targets(width: width, height: height, device: metal.device)
        }
        guard let vertices, let targets, let drawable = gel.nextDrawable(), let commands = metal.queue.makeCommandBuffer() else { return nil }
        let look = shown.look
        var uniforms = InkGel.uniforms(ui, size: size, scale: scale, time: time, override: look.color.cgColor, deepness: look.deepness,
                                       deepShare: Float(min(max(ui.pinGelDeep, 0), 1)))
        uniforms.headMore = SIMD4(0, Float(max(ui.pinGelBevel, 0.1) * scale), Float(max(look.dome, 0) * scale), 0)
        if let place = onScreen() {
            let mouse = LiveInkTap.pointer
            uniforms.pointer = SIMD4(Float((mouse.x - place.minX) * scale), Float((StateReport.primaryHeight - mouse.y - place.minY) * scale),
                                     Float(ui.inkGelPointerHeight * scale), Float(ui.inkGelPointerLight))
        }
        guard InkGel.encode([(vertices, 0, vertexCount)], uniforms: uniforms, targets: targets, into: drawable, commands: commands) else { return nil }
        return (commands, drawable)
    }

    /// The gel's frame on the screen, in global top-left points.
    private func onScreen() -> CGRect? {
        guard let view = host, let viewLayer = view.layer, let window = view.window else { return nil }
        // A view's layer runs as the view does, so the rect is in the view's coordinates.
        let inView = gel.convert(gel.bounds, to: viewLayer)
        return StateReport.flipped(window.convertToScreen(view.convert(inView, to: nil)))
    }

    /// Lays `shapes` out in px as triangles over the pixels their light reaches: a box's whole rect, and
    /// a rod's band along each side, each `margin` pt wider. A vertex is 10 floats (`GelVertex`): its
    /// place, the box's centre, its half size, its corners' radius, its square corner or -1, the rod's
    /// half width or 0, and kind 2.
    private func build(_ shapes: [Shape], margin: CGFloat, device: MTLDevice) {
        let scale = contentsScale
        var out: [Float] = []
        for shape in shapes {
            let rect = shape.rect
            let centre = CGPoint(x: rect.midX * scale, y: rect.midY * scale)
            let half = CGSize(width: rect.width / 2 * scale, height: rect.height / 2 * scale)
            let radius = min(shape.radius, rect.width / 2, rect.height / 2) * scale
            let rod = (shape.rod ?? 0) / 2 * scale
            let tail: [Float] = [Float(centre.x), Float(centre.y), Float(half.width), Float(half.height), Float(radius),
                                 Float(shape.sharp?.rawValue ?? -1), Float(rod), 2]
            func quad(_ r: CGRect) {
                let r = CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale)
                for p in [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY),
                          CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)] {
                    out += [Float(p.x), Float(p.y)] + tail
                }
            }
            guard let width = shape.rod else {
                quad(rect.insetBy(dx: -margin, dy: -margin))
                continue
            }
            // A band reaches past the rod by the margin, and in past a rounded corner's curve.
            let band = width / 2 + margin + shape.radius
            let outer = rect.insetBy(dx: -band, dy: -band)
            quad(CGRect(x: outer.minX, y: outer.minY, width: outer.width, height: 2 * band))
            quad(CGRect(x: outer.minX, y: outer.maxY - 2 * band, width: outer.width, height: 2 * band))
            quad(CGRect(x: outer.minX, y: outer.minY + 2 * band, width: 2 * band, height: max(outer.height - 4 * band, 0)))
            quad(CGRect(x: outer.maxX - 2 * band, y: outer.minY + 2 * band, width: 2 * band, height: max(outer.height - 4 * band, 0)))
        }
        vertexCount = out.count / 10
        vertices = out.isEmpty ? nil : device.makeBuffer(bytes: out, length: out.count * MemoryLayout<Float>.stride)
    }
}

/// A rim of gel round a pin's hover card or popover, in the pin's colour: a rod `ui.pinGelRim` wide
/// along the inside of the view's edge, whose corners are `radius` round but the one `sharp` names.
@MainActor
final class PinGelRim: NSView {
    private let gel = PinGel(scale: 2)
    private var wearing: (color: SRGB, radius: CGFloat, sharp: PinGel.Corner?)?

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        gel.host = self
        layer?.addSublayer(gel)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func wear(_ color: SRGB, radius: CGFloat, sharp: PinGel.Corner?) {
        guard wearing.map({ $0.color != color || $0.radius != radius || $0.sharp != sharp }) ?? true else { return }
        wearing = (color, radius, sharp)
        place()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        place()
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
        place()
    }

    private func place() {
        guard let wearing, bounds.width > 0, bounds.height > 0 else { return }
        let width = Settings.shared.data.ui.pinGelRim
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let rect = bounds.insetBy(dx: width / 2, dy: width / 2)
        gel.show([PinGel.Shape(rect: rect, radius: max(wearing.radius - width / 2, 0), sharp: wearing.sharp, rod: width)],
                 look: PinGel.Look(color: wearing.color, deepness: dark ? 0 : 1, dome: 0, drifting: false))
    }
}
