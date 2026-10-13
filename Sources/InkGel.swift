import AppKit
import Combine
import Metal
import QuartzCore
import ScreenCaptureKit

/// Draws the person's live ink as adaptive ice (`InkGel.metal`, docs/live-ink-gel-2026-10-12.md):
/// each line a triangle strip whose vertices carry their place across and along it, so the shader
/// lights it as a rod, and its colour turns from luminous ice to deep blue with the brightness behind
/// it (`InkBackdrop`). A halo strip under it, wider by the glow's reach, draws the glow and the shadow.
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
        var light: SIMD4<Float>
        var deep: SIMD4<Float>
        var glow: SIMD4<Float>
        var more: SIMD4<Float>
        var behind: SIMD4<Float>
        var mapNow: SIMD4<Float>
        var mapBefore: SIMD4<Float>
        /// xy: px taken off every vertex's place, so a line laid out once can be drawn as its layer moves.
        var offset: SIMD4<Float>
        var material: SIMD4<Float>
        var lightPlace: SIMD4<Float>
    }

    /// What a layer draws: its line in points of the layer, its head's corners, and how far the
    /// head has come in.
    struct Shape {
        var stroke: InkHand.Stroke
        var width: CGFloat
        var head: [CGPoint]
    }

    /// Vertices for the halo pass and the body pass. A vertex is 10 floats: its place in px, across,
    /// along, its half width, its tangent, the strip's half width, its kind and its pass (`GelVertex`).
    struct Vertices {
        var halo: [Float] = []
        var body: [Float] = []

        mutating func append(_ other: Vertices) {
            halo += other.halo
            body += other.body
        }
    }

    /// Lays a line's vertices out in px from `origin`.
    struct Builder {
        let width: CGFloat
        let origin: CGPoint
        let scale: CGFloat
        let reach: CGFloat

        /// The whole of `shape`: its line, its round ends and its head.
        func vertices(_ shape: Shape) -> Vertices {
            var out = ends(of: shape.stroke, length: InkHand.lengths(shape.stroke.points).last ?? 0, hasHead: shape.head.count > 2)
            out.append(segments(shape.stroke, 0..<max(shape.stroke.points.count - 1, 0), startLength: 0).vertices)
            out.append(head(shape))
            return out
        }

        /// The quads of segments `range` of `stroke`, segment `i` joining points `i` and `i + 1`, with
        /// the length along the line at the range's first point, and the length at its last.
        func segments(_ stroke: InkHand.Stroke, _ range: Range<Int>, startLength: CGFloat) -> (vertices: Vertices, endLength: CGFloat) {
            var out = Vertices()
            let points = stroke.points
            guard points.count > 1, !range.isEmpty else { return (out, startLength) }
            out.halo.reserveCapacity(range.count * 60)
            out.body.reserveCapacity(range.count * 60)
            var along = startLength
            for index in range {
                let next = index + 1
                let alongNext = along + hypot(points[next].x - points[index].x, points[next].y - points[index].y)
                let ta = tangent(points, index), tb = tangent(points, next)
                let ha = half(stroke, index), hb = half(stroke, next)
                for (pass, grow) in [(Float(0), reach), (Float(1), 1.5 / scale)] {
                    let ea = ha + grow, eb = hb + grow
                    let a0 = side(points[index], ta, 1, ea), a1 = side(points[index], ta, -1, ea)
                    let b0 = side(points[next], tb, 1, eb), b1 = side(points[next], tb, -1, eb)
                    func vertex(_ p: CGPoint, _ u: Float, _ at: Bool) {
                        let a = at ? (along, ha, ta, ea) : (alongNext, hb, tb, eb)
                        if pass == 0 {
                            put(&out.halo, p, u: u, along: a.0, half: a.1, tangent: a.2, extent: a.3, kind: 0, pass: pass)
                        } else {
                            put(&out.body, p, u: u, along: a.0, half: a.1, tangent: a.2, extent: a.3, kind: 0, pass: pass)
                        }
                    }
                    vertex(a0, 1, true); vertex(a1, -1, true); vertex(b0, 1, false)
                    vertex(a1, -1, true); vertex(b1, -1, false); vertex(b0, 1, false)
                }
                along = alongNext
            }
            return (out, along)
        }

        /// Round ends, each a fan whose middle is across 0 and whose rim is across 1. An arrow's end is
        /// under its head. `length` is the line's.
        func ends(of stroke: InkHand.Stroke, length: CGFloat, hasHead: Bool) -> Vertices {
            var out = Vertices()
            let points = stroke.points
            guard points.count > 1 else { return out }
            for (index, sign, along) in [(0, CGFloat(-1), CGFloat(0)), (points.count - 1, 1, length)] where !(index == points.count - 1 && hasHead) {
                let t = tangent(points, index), h = half(stroke, index), p = points[index]
                for (pass, grow) in [(Float(0), reach), (Float(1), 1.5 / scale)] {
                    let e = h + grow
                    let base = atan2(t.y, t.x) - .pi / 2
                    for k in 0..<10 {
                        let a0 = base + .pi * CGFloat(k) / 10 * sign, a1 = base + .pi * CGFloat(k + 1) / 10 * sign
                        for (q, u) in [(p, Float(0)), (CGPoint(x: p.x + cos(a0) * e, y: p.y + sin(a0) * e), 1),
                                       (CGPoint(x: p.x + cos(a1) * e, y: p.y + sin(a1) * e), 1)] {
                            if pass == 0 {
                                put(&out.halo, q, u: u, along: along, half: h, tangent: t, extent: e, kind: 0, pass: pass)
                            } else {
                                put(&out.body, q, u: u, along: along, half: h, tangent: t, extent: e, kind: 0, pass: pass)
                            }
                        }
                    }
                }
            }
            return out
        }

        /// A filled head, a fan round its middle.
        func head(_ shape: Shape) -> Vertices {
            var out = Vertices()
            guard shape.head.count > 2 else { return out }
            let s = Float(scale)
            let along = Float(InkHand.lengths(shape.stroke.points).last ?? 0) * s
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
                head(&out.halo, middle, u: 0, half: Float(radius) * s, pass: 0)
                head(&out.halo, grown(corner), u: 1, half: Float(radius) * s, pass: 0)
                head(&out.halo, grown(next), u: 1, half: Float(radius) * s, pass: 0)
                head(&out.body, middle, u: 0, half: Float(radius) * s, pass: 1)
                head(&out.body, corner, u: 1, half: Float(radius) * s, pass: 1)
                head(&out.body, next, u: 1, half: Float(radius) * s, pass: 1)
            }
            return out
        }

        private func tangent(_ points: [CGPoint], _ index: Int) -> CGPoint {
            let a = points[max(index - 1, 0)], b = points[min(index + 1, points.count - 1)]
            let length = max(hypot(b.x - a.x, b.y - a.y), .ulpOfOne)
            return CGPoint(x: (b.x - a.x) / length, y: (b.y - a.y) / length)
        }

        private func half(_ stroke: InkHand.Stroke, _ index: Int) -> CGFloat { max(stroke.widths[index] * width / 2, 0.05) }

        private func side(_ point: CGPoint, _ tangent: CGPoint, _ sign: CGFloat, _ extent: CGFloat) -> CGPoint {
            CGPoint(x: point.x - tangent.y * extent * sign, y: point.y + tangent.x * extent * sign)
        }

        private func put(_ into: inout [Float], _ p: CGPoint, u: Float, along: CGFloat, half: CGFloat, tangent: CGPoint, extent: CGFloat,
                         kind: Float, pass: Float) {
            let s = Float(scale)
            into.append(Float(p.x - origin.x) * s); into.append(Float(p.y - origin.y) * s); into.append(u)
            into.append(Float(along) * s); into.append(Float(half) * s); into.append(Float(tangent.x)); into.append(Float(tangent.y))
            into.append(Float(extent) * s); into.append(kind); into.append(pass)
        }
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

    /// The tweaks' values as the shader takes them, for a gel at `gel` on the screen, in global
    /// top-left points. `override` is the done state's colour, which takes the ice's place and,
    /// darkened, the deep blue's.
    static func uniforms(_ ui: UITweaks, gel: CGRect, size: CGSize, scale: CGFloat, time: CFTimeInterval, override: CGColor?,
                         headOpacity: CGFloat, backdrop: InkBackdrop.Reading) -> Uniforms {
        let light = rgb(override ?? SRGB(hex: ui.inkGelLight)?.cgColor ?? CGColor(srgbRed: 0.55, green: 0.78, blue: 1, alpha: 1))
        let deep = override.map { rgb($0) * 0.45 } ?? rgb(SRGB(hex: ui.inkGelDeep)?.cgColor ?? CGColor(srgbRed: 0.14, green: 0.3, blue: 0.62, alpha: 1))
        let half = ui.inkGelSwitchWidth / 2
        func rect(_ map: InkBackdrop.Map?) -> SIMD4<Float> {
            // No map reads as dark everywhere, so the ink is the ice until one comes.
            guard let map else { return SIMD4(0, 0, 1, 1) }
            return SIMD4(Float((map.frame.minX - gel.minX) * scale), Float((map.frame.minY - gel.minY) * scale),
                         Float(map.frame.width * scale), Float(map.frame.height * scale))
        }
        return Uniforms(size: SIMD2(Float(size.width), Float(size.height)), scale: Float(scale), time: Float(time),
                        light: SIMD4(light, Float(ui.inkGelCore)), deep: SIMD4(deep, 0),
                        glow: SIMD4(Float(ui.inkGelGlow), Float(ui.inkGelBloom), Float(ui.inkGelGlowRadius * scale), Float(ui.inkGelShadow)),
                        more: SIMD4(Float(headOpacity), Float(ui.inkGelWander), Float(ui.inkGelShimmer), Float(ui.inkGelSheen)),
                        behind: SIMD4(Float(ui.inkGelSwitch - half), Float(ui.inkGelSwitch + half), backdrop.fade, Float(ui.inkGelSheathDepth)),
                        mapNow: rect(backdrop.now), mapBefore: rect(backdrop.before), offset: .zero,
                        material: SIMD4(Float(ui.inkGelHighlightSharpness), Float(ui.inkGelGlowFalloff), Float(ui.inkGelDeepEdge), Float(ui.inkGelEdgeOpacity)),
                        lightPlace: SIMD4(Float(ui.inkGelShimmerLength), Float(ui.inkGelShimmerSpeed), Float(ui.inkGelLightAngle * .pi / 180),
                                          Float(ui.inkGelLightHeight)))
    }

    private static func rgb(_ colour: CGColor) -> SIMD3<Float> {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let c = colour.converted(to: space, intent: .defaultIntent, options: nil)?.components, c.count >= 3 else { return SIMD3(0.55, 0.78, 1) }
        return SIMD3(Float(c[0]), Float(c[1]), Float(c[2]))
    }
}

/// A line's settled start, laid out once in px and kept in buffers that only grow, so a line under the
/// pen costs the same to draw at every length. A frame the GPU is still drawing reads only vertices
/// that were there when it was encoded, and those are never written again.
@MainActor
final class SettledLine {
    let builder: InkGel.Builder
    /// The segments laid out, from the line's start, and the length along the line to their end.
    private(set) var segments = 0
    private(set) var length: CGFloat = 0
    private(set) var halo = GrowingBuffer()
    private(set) var body = GrowingBuffer()

    init(builder: InkGel.Builder) {
        self.builder = builder
    }

    /// Lays out the segments of `stroke` that its first `settled` points fix. A segment's end takes its
    /// tangent from the point after it, so the last settled point ends no segment yet.
    func extend(_ stroke: InkHand.Stroke, settled: Int, device: MTLDevice) {
        let fixed = min(settled, stroke.points.count) - 2
        guard fixed > segments else { return }
        let laid = builder.segments(stroke, segments..<fixed, startLength: length)
        halo.append(laid.vertices.halo, device: device)
        body.append(laid.vertices.body, device: device)
        segments = fixed
        length = laid.endLength
    }

    /// Vertices in a shared buffer that only grows: a bigger one takes a copy of what is there.
    struct GrowingBuffer {
        private(set) var buffer: MTLBuffer?
        private(set) var vertexCount = 0

        mutating func append(_ floats: [Float], device: MTLDevice) {
            guard !floats.isEmpty else { return }
            let used = vertexCount * 10 * MemoryLayout<Float>.stride, adding = floats.count * MemoryLayout<Float>.stride
            if (buffer?.length ?? 0) < used + adding {
                guard let bigger = device.makeBuffer(length: max(2 * (buffer?.length ?? 0), used + adding, 1 << 16), options: .storageModeShared) else { return }
                if let buffer, used > 0 { bigger.contents().copyMemory(from: buffer.contents(), byteCount: used) }
                buffer = bigger
            }
            guard let buffer else { return }
            floats.withUnsafeBytes { buffer.contents().advanced(by: used).copyMemory(from: $0.baseAddress!, byteCount: adding) }
            vertexCount += floats.count / 10
        }
    }
}

/// How light the screen is behind the person's ink, so the gel takes the colour that stands out
/// there: luminous ice over dark content and deep blue over light. Each display is captured without
/// Vignette's own windows when inking starts and after an answer is drawn, and kept as a grid of
/// 8 pt cells (`LivePacket.Luminance`). A new map fades in over the one before. Without Screen
/// Recording there is no map, and the ink is the ice.
@MainActor
final class InkBackdrop {
    static let shared = InkBackdrop()

    struct Map {
        /// The display it covers, in global top-left points.
        let frame: CGRect
        let texture: MTLTexture
        let luminance: LivePacket.Luminance
    }

    /// The maps a layer reads: the newest, the one it fades in from, and how far it has come.
    struct Reading {
        var now: Map?
        var before: Map?
        var fade: Float
    }

    private var maps: [Map] = []
    private var earlier: [Map] = []
    private var changed: CFTimeInterval = 0
    private var fadeDuration: CFTimeInterval = 0
    private var capturing: Task<Void, Never>?
    /// What a texture is bound to when there is no map: one cell of black, read as dark.
    private lazy var none: MTLTexture? = {
        guard let device = InkGel.metal?.device else { return nil }
        let texture = device.makeTexture(descriptor: .texture2DDescriptor(pixelFormat: .r8Unorm, width: 1, height: 1, mipmapped: false))
        texture?.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: [UInt8(0)], bytesPerRow: 1)
        return texture
    }()

    /// The size of a map's cell, in points.
    static let cell: CGFloat = 8

    /// Captures the displays again, and calls `read` once the new maps are in. A capture still on its
    /// way is dropped, and its `read` with it.
    func refresh(then read: (() -> Void)? = nil) {
        capturing?.cancel()
        let started = CACurrentMediaTime()
        capturing = Task { [weak self] in
            let captured = await Self.capture()
            guard !Task.isCancelled, let self, !captured.isEmpty else { return }
            self.take(captured)
            Log.write("[live-ink] backdrop read displays=\(captured.count) ms=\(Int((CACurrentMediaTime() - started) * 1000))")
            read?()
        }
    }

    /// The newest map's mean luminance, 0 to 1, under `rect` in global top-left points, or nil with no
    /// map there.
    func brightness(in rect: CGRect) -> CGFloat? {
        maps.lazy.compactMap { $0.luminance.mean(in: rect) }.first
    }

    /// What a layer covering `rect`, in global top-left points, reads at `now`.
    func reading(for rect: CGRect, at now: CFTimeInterval) -> Reading {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        func map(in list: [Map]) -> Map? { list.first { $0.frame.contains(centre) } ?? list.first { $0.frame.intersects(rect) } }
        let fade = fadeDuration > 0 ? min(max((now - changed) / fadeDuration, 0), 1) : 1
        return Reading(now: map(in: maps), before: map(in: earlier), fade: Float(fade))
    }

    /// The textures to bind for `reading`: the newest map's, and the one before's.
    func textures(for reading: Reading) -> (now: MTLTexture, before: MTLTexture)? {
        guard let none else { return nil }
        return (reading.now?.texture ?? none, reading.before?.texture ?? none)
    }

    /// A map is fading in, so every gel draws each frame.
    func isFading(at now: CFTimeInterval) -> Bool {
        // A frame past the end, so the last drawing is the map alone.
        now < changed + fadeDuration + 0.05
    }

    private func take(_ captured: [(frame: CGRect, luminance: LivePacket.Luminance)]) {
        guard let device = InkGel.metal?.device else { return }
        let made = captured.compactMap { frame, luminance -> Map? in
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: luminance.columns,
                                                                      height: luminance.rows, mipmapped: false)
            guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
            texture.replace(region: MTLRegionMake2D(0, 0, luminance.columns, luminance.rows), mipmapLevel: 0,
                            withBytes: luminance.cells, bytesPerRow: luminance.columns)
            return Map(frame: frame, texture: texture, luminance: luminance)
        }
        let now = CACurrentMediaTime()
        earlier = maps
        maps = made
        changed = now
        fadeDuration = 0.2 * Settings.shared.motionScale
        InkClock.shared.wake()
    }

    /// Each display behind the ink, drawn down to its map's cells. Vignette's own windows are left
    /// out, so the ink and its glow never brighten their own map.
    nonisolated private static func capture() async -> [(frame: CGRect, luminance: LivePacket.Luminance)] {
        guard CGPreflightScreenCaptureAccess(),
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return [] }
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        var maps: [(frame: CGRect, luminance: LivePacket.Luminance)] = []
        for display in content.displays {
            let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            // A pixel every two points gives each cell sixteen to take its mean from.
            configuration.width = max(1, Int(display.frame.width / 2))
            configuration.height = max(1, Int(display.frame.height / 2))
            configuration.showsCursor = false
            guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration),
                  let luminance = LivePacket.Luminance(image, frame: display.frame, columns: max(1, Int(display.frame.width / cell))) else { continue }
            maps.append((display.frame, luminance))
        }
        return maps
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
        var moving = InkBackdrop.shared.isFading(at: now)
        for layer in shown {
            let easing = moving || layer.isEasing(at: now)
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
