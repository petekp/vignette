import AppKit
import Metal
import QuartzCore

/// Comments' gel in the editor: live ink's material (`InkGel.metal`) on the pins' teardrops, on their
/// areas' outlines and on the rim of a hover card or popover, each in its pin's colour and lit from the
/// pointer. Each shape is a rounded box: a teardrop is its square with every corner but the tip's
/// rounded to half its side, bevelled and domed on top, and an outline or a rim is a rod along a
/// box's edge. The shapes of one layer are one surface, as live ink's line and its head are, so an
/// area and its pin join. One layer holds every pin of the editor, so a redraw costs two passes
/// however many pins there are. It draws on live ink's clock (`InkClock`), which redraws it as the
/// pointer moves and while its material drifts.
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
        /// The radius of the dome on the box's top, in pt; a rod has none.
        var dome: CGFloat = 0
        var tint: Tint
        /// The rod's centre line, closed, when the rod runs along it rather than along `rect`'s edge;
        /// `rect` is then the line's bounds.
        var line: [CGPoint]? = nil

        /// The body of `teardrop`, domed `dome` pt.
        static func body(of teardrop: PinTeardrop, dome: CGFloat, tint: Tint) -> Shape {
            let square = teardrop.square
            let tip = Corner(right: teardrop.tip.x > square.midX, bottom: teardrop.tip.y > square.midY)
            return Shape(rect: square, radius: min(square.width, square.height) / 2, sharp: tip, rod: nil, dome: dome, tint: tint)
        }

        /// A rod `width` wide centred on `rect`'s edge, square at its inner corners.
        static func outline(_ rect: CGRect, width: CGFloat, tint: Tint) -> Shape {
            Shape(rect: rect, radius: 0, sharp: nil, rod: width, tint: tint)
        }

        /// A rod `width` wide centred on `line`, a closed line.
        static func rod(along line: [CGPoint], width: CGFloat, tint: Tint) -> Shape {
            let xs = line.map(\.x), ys = line.map(\.y)
            let minX = xs.min() ?? 0, minY = ys.min() ?? 0
            let bounds = CGRect(x: minX, y: minY, width: (xs.max() ?? 0) - minX, height: (ys.max() ?? 0) - minY)
            return Shape(rect: bounds, radius: 0, sharp: nil, rod: width, tint: tint, line: line)
        }

        func offsetBy(dx: CGFloat, dy: CGFloat) -> Shape {
            var moved = self
            moved.rect = rect.offsetBy(dx: dx, dy: dy)
            moved.line = line?.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            return moved
        }
    }

    struct Tint: Equatable {
        var color: SRGB
        /// 0 for the gel's light edge, over dark content, and 1 for its deep edge, over light content.
        var deepness: CGFloat
    }

    /// The most colours one layer draws; a shape in a colour past them takes the last one's.
    static let colours = 8

    /// The view whose window the gel is shown in, for the pointer's place over it.
    weak var host: NSView?
    private let gel = CAMetalLayer()
    /// The shapes, from the corner of the gel's frame, and whether the material keeps drifting, as it
    /// does on an open pin's outline.
    private var shown: (shapes: [Shape], drifting: Bool)?
    private var vertices: MTLBuffer?
    private var palette: [SIMD4<Float>] = []
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
        if let shown {
            show(shown.shapes.map { $0.offsetBy(dx: gel.frame.minX, dy: gel.frame.minY) }, drifting: shown.drifting, within: clip, redraw: true)
        }
    }

    /// Where the gel may reach, in this layer's coordinates.
    private var clip: CGRect?

    /// Draws `shapes`, in this layer's coordinates, unless they are drawn already, cut to `within` when
    /// it is given. Shapes that only moved together move the drawing, which then waits for the clock to
    /// light it from the pointer's new place.
    func show(_ shapes: [Shape], drifting: Bool, within: CGRect? = nil) {
        show(shapes, drifting: drifting, within: within, redraw: false)
    }

    private func show(_ shapes: [Shape], drifting: Bool, within: CGRect?, redraw: Bool) {
        let ui = Settings.shared.data.ui
        clip = within
        let margin = ui.inkGelGlowRadius + 2
        let reach = shapes.map { $0.rect.insetBy(dx: -($0.rod ?? 0) - margin, dy: -($0.rod ?? 0) - margin) }
            .reduce(nil) { $0?.union($1) ?? $1 }
            .map { within.map($0.intersection) ?? $0 }
        guard let reach, !reach.isEmpty else {
            shown = nil
            gel.isHidden = true
            return
        }
        // On a grid of `frameStep`, so a zoom or a drag changes the frame's size, and the textures it
        // takes, only now and then.
        let step = Self.frameStep
        let minX = (reach.minX / step).rounded(.down) * step, minY = (reach.minY / step).rounded(.down) * step
        let frame = CGRect(x: minX, y: minY, width: ((reach.maxX - minX) / step).rounded(.up) * step,
                           height: ((reach.maxY - minY) / step).rounded(.up) * step)
        let local = shapes.map { $0.offsetBy(dx: -frame.minX, dy: -frame.minY) }
        let same = !redraw && shown?.shapes == local && shown?.drifting == drifting && gel.frame.size == frame.size
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
        shown = (local, drifting)
        vertices = nil
        // The new shape and its frame reach the screen in the same transaction, as live ink's do.
        drawNow()
    }

    private static let frameStep: CGFloat = 32

    private func drawNow() {
        guard let frame = encode(at: CACurrentMediaTime(), time: InkClock.shared.time) else { return }
        frame.commands.commit()
        frame.commands.waitUntilScheduled()
        frame.drawable.present()
    }

    // MARK: GelLayer

    var readsScreen: Bool { false }
    var keepsDrifting: Bool { shown?.drifting == true && isVisible }

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
        var uniforms = InkGel.uniforms(ui, size: size, scale: scale, time: time, override: nil, deepness: 0)
        uniforms.headMore = SIMD4(0, Float(max(ui.pinGelBevel, 0.1) * scale), Float(min(max(ui.pinGelShade, 0), 1)),
                                  Float(min(max(ui.pinGelEdge, 0), 1)))
        if let place = onScreen() {
            let mouse = LiveInkTap.pointer
            uniforms.pointer = SIMD4(Float((mouse.x - place.minX) * scale), Float((StateReport.primaryHeight - mouse.y - place.minY) * scale),
                                     Float(ui.inkGelPointerHeight * scale), Float(ui.inkGelPointerLight))
        }
        guard InkGel.encode([(vertices, 0, vertexCount)], uniforms: uniforms, targets: targets, into: drawable, commands: commands,
                            palette: palette) else { return nil }
        return (commands, drawable)
    }

    /// The gel's frame on the screen, in global top-left points.
    private func onScreen() -> CGRect? {
        guard let view = host, let viewLayer = view.layer, let window = view.window else { return nil }
        // A view's layer runs as the view does, so the rect is in the view's coordinates.
        let inView = gel.convert(gel.bounds, to: viewLayer)
        return StateReport.flipped(window.convertToScreen(view.convert(inView, to: nil)))
    }

    /// Lays `shapes` out in px as triangles over the pixels their light reaches: a box's whole rect, a
    /// rod's band along each side, and a rod along a line's rect round each of its segments (kind 3), each
    /// `margin` pt wider. A vertex is 10 floats (`GelVertex`): its
    /// place, the box's centre, its half size, its corners' radius, its tint (`BoxTint`), the rod's
    /// half width or the dome's radius negated, and kind 2. Each colour goes in the palette once, light
    /// and then deep, the deep one `ui.pinGelDeep` of the light one.
    private func build(_ shapes: [Shape], margin: CGFloat, device: MTLDevice) {
        let scale = contentsScale
        let share = CGFloat(min(max(Settings.shared.data.ui.pinGelDeep, 0), 1))
        var colours: [SRGB] = []
        var out: [Float] = []
        for shape in shapes {
            let colour = colours.firstIndex(of: shape.tint.color) ?? {
                guard colours.count < Self.colours else { return Self.colours - 1 }
                colours.append(shape.tint.color)
                return colours.count - 1
            }()
            let depth = Int((min(max(shape.tint.deepness, 0), 1) * 63).rounded())
            let tint = (shape.sharp.map { $0.rawValue + 1 } ?? 0) + colour * 8 + depth * 64
            let rect = shape.rect
            let centre = CGPoint(x: rect.midX * scale, y: rect.midY * scale)
            let half = CGSize(width: rect.width / 2 * scale, height: rect.height / 2 * scale)
            let radius = min(shape.radius, rect.width / 2, rect.height / 2) * scale
            let rodOrDome = shape.rod.map { $0 / 2 * scale } ?? -max(shape.dome, 0) * scale
            let tail: [Float] = [Float(centre.x), Float(centre.y), Float(half.width), Float(half.height), Float(radius),
                                 Float(tint), Float(rodOrDome), 2]
            func quad(_ r: CGRect, _ tail: [Float] = tail) {
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
            if let line = shape.line {
                let reach = width / 2 + margin
                for (index, a) in line.enumerated() {
                    let b = line[(index + 1) % line.count]
                    let piece: [Float] = [Float(a.x * scale), Float(a.y * scale), Float(b.x * scale), Float(b.y * scale),
                                          Float(width / 2 * scale), Float(tint), 0, 3]
                    quad(CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
                        .insetBy(dx: -reach, dy: -reach), piece)
                }
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
        palette = colours.flatMap { c -> [SIMD4<Float>] in
            [SIMD4(Float(c.red), Float(c.green), Float(c.blue), 1), SIMD4(Float(c.red * share), Float(c.green * share), Float(c.blue * share), 1)]
        }
        vertexCount = out.count / 10
        vertices = out.isEmpty ? nil : device.makeBuffer(bytes: out, length: out.count * MemoryLayout<Float>.stride)
    }
}
