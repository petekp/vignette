import AppKit
import Combine
import Metal
import QuartzCore

/// Draws the person's live ink as opal gel (`InkGel.metal`, docs/live-ink-gel-2026-10-12.md): each
/// line a triangle strip whose vertices carry their place across and along it, so the shader lights
/// it as a rod and its colour follows the line. A halo strip under it, wider by the glow's reach,
/// draws the glow and the shadow.
@MainActor
enum InkGel {
    static let metal: (device: MTLDevice, queue: MTLCommandQueue, halo: MTLRenderPipelineState, body: MTLRenderPipelineState)? = {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { return nil }
        func pipeline(max: Bool) -> MTLRenderPipelineState? {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "gelVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "gelFragment")
            let colour = descriptor.colorAttachments[0]!
            colour.pixelFormat = .bgra8Unorm
            colour.isBlendingEnabled = true
            if max {
                // A loop that crosses itself, or a halo that folds on a tight bend, would be brighter
                // there with over blending.
                colour.rgbBlendOperation = .max
                colour.alphaBlendOperation = .max
                colour.sourceRGBBlendFactor = .one
                colour.sourceAlphaBlendFactor = .one
                colour.destinationRGBBlendFactor = .one
                colour.destinationAlphaBlendFactor = .one
            } else {
                colour.sourceRGBBlendFactor = .one
                colour.sourceAlphaBlendFactor = .one
                colour.destinationRGBBlendFactor = .oneMinusSourceAlpha
                colour.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return try? device.makeRenderPipelineState(descriptor: descriptor)
        }
        guard let halo = pipeline(max: true), let body = pipeline(max: false) else {
            Log.write("[live-ink] error gel pipelines did not build")
            return nil
        }
        return (device, queue, halo, body)
    }()

    struct Uniforms {
        var size: SIMD2<Float>
        var scale: Float
        var time: Float
        var body: SIMD4<Float>
        var look: SIMD4<Float>
        var glow: SIMD4<Float>
        var more: SIMD4<Float>
    }

    /// What a layer draws: its line in points of the layer, its head's corners, and how far the
    /// head has come in.
    struct Shape {
        var stroke: InkHand.Stroke
        var width: CGFloat
        var head: [CGPoint]
    }

    /// The vertices of `shape` in px from `origin`, the halo's first and then the body's, and how many
    /// of each. A line's vertex is 10 floats: its place, across, along, its half width, its tangent,
    /// the strip's half width, its kind and its pass (`GelVertex`).
    static func vertices(_ shape: Shape, origin: CGPoint, scale: CGFloat, reach: CGFloat) -> (floats: [Float], halo: Int, body: Int) {
        var halo: [Float] = [], body: [Float] = []
        let points = shape.stroke.points
        let s = Float(scale)
        func put(_ into: inout [Float], _ p: CGPoint, u: Float, along: CGFloat, half: CGFloat, tangent: CGPoint, extent: CGFloat, kind: Float, pass: Float) {
            into += [Float(p.x - origin.x) * s, Float(p.y - origin.y) * s, u, Float(along) * s, Float(half) * s,
                     Float(tangent.x), Float(tangent.y), Float(extent) * s, kind, pass]
        }
        if points.count > 1 {
            let lengths = InkHand.lengths(points)
            let tangents = points.indices.map { index -> CGPoint in
                let a = points[max(index - 1, 0)], b = points[min(index + 1, points.count - 1)]
                let length = max(hypot(b.x - a.x, b.y - a.y), .ulpOfOne)
                return CGPoint(x: (b.x - a.x) / length, y: (b.y - a.y) / length)
            }
            let halves = shape.stroke.widths.map { max($0 * shape.width / 2, 0.05) }
            for (pass, grow) in [(Float(0), reach), (Float(1), 0)] {
                var out: [Float] = []
                func side(_ index: Int, _ sign: CGFloat, _ extent: CGFloat) -> CGPoint {
                    CGPoint(x: points[index].x - tangents[index].y * extent * sign, y: points[index].y + tangents[index].x * extent * sign)
                }
                for index in 0..<(points.count - 1) {
                    let next = index + 1
                    let ea = halves[index] + grow, eb = halves[next] + grow
                    let a0 = side(index, 1, ea), a1 = side(index, -1, ea), b0 = side(next, 1, eb), b1 = side(next, -1, eb)
                    for (p, u, i, e) in [(a0, Float(1), index, ea), (a1, -1, index, ea), (b0, 1, next, eb),
                                         (a1, -1, index, ea), (b1, -1, next, eb), (b0, 1, next, eb)] {
                        put(&out, p, u: u, along: lengths[i], half: halves[i], tangent: tangents[i], extent: e, kind: 0, pass: pass)
                    }
                }
                // Round ends, each a fan whose middle is across 0 and whose rim is across 1. An arrow's
                // end is under its head.
                for (index, sign) in [(0, CGFloat(-1)), (points.count - 1, CGFloat(1))] where !(index == points.count - 1 && !shape.head.isEmpty) {
                    let t = tangents[index], e = halves[index] + grow
                    let base = atan2(t.y, t.x) - .pi / 2
                    for k in 0..<10 {
                        let a0 = base + .pi * CGFloat(k) / 10 * sign, a1 = base + .pi * CGFloat(k + 1) / 10 * sign
                        let p = points[index]
                        put(&out, p, u: 0, along: lengths[index], half: halves[index], tangent: t, extent: e, kind: 0, pass: pass)
                        put(&out, CGPoint(x: p.x + cos(a0) * e, y: p.y + sin(a0) * e), u: 1, along: lengths[index], half: halves[index],
                            tangent: t, extent: e, kind: 0, pass: pass)
                        put(&out, CGPoint(x: p.x + cos(a1) * e, y: p.y + sin(a1) * e), u: 1, along: lengths[index], half: halves[index],
                            tangent: t, extent: e, kind: 0, pass: pass)
                    }
                }
                if pass == 0 { halo += out } else { body += out }
            }
        }
        if shape.head.count > 2 {
            let along = Float(InkHand.lengths(points).last ?? 0) * s
            let middle = CGPoint(x: shape.head.map(\.x).reduce(0, +) / CGFloat(shape.head.count),
                                 y: shape.head.map(\.y).reduce(0, +) / CGFloat(shape.head.count))
            let radius = shape.head.map { hypot($0.x - middle.x, $0.y - middle.y) }.reduce(0, +) / CGFloat(shape.head.count)
            // The halo's fan is the head grown until it holds the glow's circle round the head's middle.
            let nearest = zip(shape.head, shape.head.dropFirst() + [shape.head[0]]).map { a, b -> CGFloat in
                let dx = b.x - a.x, dy = b.y - a.y, length = max(hypot(dx, dy), .ulpOfOne)
                return abs((middle.x - a.x) * dy - (middle.y - a.y) * dx) / length
            }.min() ?? radius
            let share = max(nearest, 0.5) / (radius + reach * 1.5)
            let centre = [Float(middle.x - origin.x) * s, Float(middle.y - origin.y) * s]
            func head(_ into: inout [Float], _ p: CGPoint, u: Float, half: Float, pass: Float) {
                into += [Float(p.x - origin.x) * s, Float(p.y - origin.y) * s, u, along, half, centre[0], centre[1], 0, 1, pass]
            }
            func grown(_ p: CGPoint) -> CGPoint { CGPoint(x: middle.x + (p.x - middle.x) / share, y: middle.y + (p.y - middle.y) / share) }
            for (index, corner) in shape.head.enumerated() {
                let next = shape.head[(index + 1) % shape.head.count]
                head(&halo, middle, u: 0, half: Float(radius) * s, pass: 0)
                head(&halo, grown(corner), u: 1, half: Float(radius) * s, pass: 0)
                head(&halo, grown(next), u: 1, half: Float(radius) * s, pass: 0)
                head(&body, middle, u: 0, half: Float(radius) * s, pass: 1)
                head(&body, corner, u: 1, half: Float(radius) * s, pass: 1)
                head(&body, next, u: 1, half: Float(radius) * s, pass: 1)
            }
        }
        return (halo + body, halo.count / 10, body.count / 10)
    }

    /// The corners of a filled head, in order.
    static func corners(of path: CGPath?) -> [CGPoint] {
        var corners: [CGPoint] = []
        path?.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint: corners.append(element.pointee.points[0])
            case .addQuadCurveToPoint: corners.append(element.pointee.points[1])
            case .addCurveToPoint: corners.append(element.pointee.points[2])
            default: break
            }
        }
        if corners.count > 1, let first = corners.first, let last = corners.last, hypot(first.x - last.x, first.y - last.y) < 0.01 { corners.removeLast() }
        return corners
    }

    /// The tweaks' values as the shader takes them. `override` is the done state's colour.
    static func uniforms(_ ui: UITweaks, size: CGSize, scale: CGFloat, time: CFTimeInterval, override: CGColor?, headOpacity: CGFloat) -> Uniforms {
        let body = rgb(override ?? SRGB(hex: ui.inkGelColor)?.cgColor ?? CGColor(gray: 0.86, alpha: 1))
        return Uniforms(size: SIMD2(Float(size.width), Float(size.height)), scale: Float(scale), time: Float(time),
                        body: SIMD4(body, override == nil ? 0 : 1),
                        look: SIMD4(Float(ui.inkGelIridescence), Float(ui.inkGelFilm), Float(ui.inkGelSheen), Float(ui.inkGelRim)),
                        glow: SIMD4(Float(ui.inkGelGlow), Float(ui.inkGelBloom), Float(ui.inkGelGlowRadius * scale), Float(ui.inkGelShadow)),
                        more: SIMD4(Float(headOpacity), Float(ui.inkGelWander), Float(ui.inkGelShimmer), 0))
    }

    private static func rgb(_ colour: CGColor) -> SIMD3<Float> {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let c = colour.converted(to: space, intent: .defaultIntent, options: nil)?.components, c.count >= 3 else { return SIMD3(0.86, 0.86, 0.9) }
        return SIMD3(Float(c[0]), Float(c[1]), Float(c[2]))
    }
}

/// The clock every gel layer draws from: one display link, running while a layer moves. The light
/// and the film drift on the material's own time, which runs at `inkGelMotion` times the motion
/// scale, so motion 0 holds them still. Idle ink redraws at about 30 frames a second; ink that is
/// easing onto its shape redraws every frame.
@MainActor
final class InkClock: NSObject {
    static let shared = InkClock()

    private var layers: [ObjectIdentifier: Weak] = [:]
    private var link: CADisplayLink?
    private var last = CACurrentMediaTime()
    private var lastIdle: CFTimeInterval = 0
    /// The material's time, in seconds of drift.
    private(set) var time: CFTimeInterval = 0
    private var settingsChanged: AnyCancellable?

    private struct Weak { weak var layer: InkMarkLayer? }

    private override init() {
        super.init()
        // A tweak redraws every gel, and at motion 0 nothing else would.
        settingsChanged = Settings.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.layers.values.forEach { $0.layer?.settingsChanged() } }
        }
    }

    func add(_ layer: InkMarkLayer) {
        layers[ObjectIdentifier(layer)] = Weak(layer: layer)
        wake()
    }

    func remove(_ layer: InkMarkLayer) {
        layers[ObjectIdentifier(layer)] = nil
    }

    /// Ticks again, after being paused for want of anything moving.
    func wake() {
        if link == nil, let screen = NSScreen.screens.first {
            link = screen.displayLink(target: self, selector: #selector(tick))
            link?.add(to: .main, forMode: .common)
        }
        link?.isPaused = false
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        let ui = Settings.shared.data.ui
        let rate = Settings.shared.motionScale * ui.inkGelMotion
        time += min(now - last, 0.1) * rate
        last = now
        layers = layers.filter { $0.value.layer != nil }
        let shown = layers.values.compactMap(\.layer).filter(\.isVisible)
        let idle = rate > 0 && now - lastIdle >= 1.0 / 30
        if idle { lastIdle = now }
        var drawn: [(commands: MTLCommandBuffer, drawable: CAMetalDrawable)] = []
        var moving = false
        for layer in shown {
            let easing = layer.isEasing(at: now)
            moving = moving || easing
            guard easing || idle || layer.needsGel else { continue }
            if let frame = layer.encode(at: now, time: time) { drawn.append(frame) }
        }
        drawn.forEach { $0.commands.commit() }
        // A layer that presents with its transaction shows a drawable only once it is scheduled.
        drawn.forEach { $0.commands.waitUntilScheduled(); $0.drawable.present() }
        // Nothing drifts at motion 0, so the link rests until a layer changes. With no layer showing,
        // it rests and looks again twice a second, since a holder fading back in says nothing here.
        if layers.isEmpty || (!moving && rate <= 0 && !shown.contains(where: \.needsGel)) {
            link?.isPaused = true
        } else if shown.isEmpty {
            link?.isPaused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if self?.layers.isEmpty == false { self?.wake() }
            }
        }
    }
}
