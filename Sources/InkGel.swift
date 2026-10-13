import AppKit
import Combine
import Metal
import QuartzCore
import ScreenCaptureKit

/// Draws the person's live ink as adaptive ice (`InkGel.metal`, docs/live-ink-gel-2026-10-12.md): one
/// soft rod whose width follows the hand, its colour turning from luminous ice to deep blue with what
/// is behind it (`InkBackdrop`). A mark is laid out as capsules, one a segment of its line, and its
/// head as a rounded polygon. The field pass keeps each pixel's distance to the nearest, so the line,
/// its joins and its head are one shape, and the light pass lights that shape as one surface, with
/// its glow and its shadow (docs/live-ink-one-material-2026-10-13.md).
@MainActor
enum InkGel {
    static let metal: (device: MTLDevice, queue: MTLCommandQueue, field: MTLRenderPipelineState, nearest: MTLDepthStencilState,
                       light: MTLRenderPipelineState)? = {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { return nil }
        let field = MTLRenderPipelineDescriptor()
        field.vertexFunction = library.makeFunction(name: "gelFieldVertex")
        field.fragmentFunction = library.makeFunction(name: "gelField")
        field.colorAttachments[0].pixelFormat = fieldFormat
        field.depthAttachmentPixelFormat = .depth32Float
        let light = MTLRenderPipelineDescriptor()
        light.vertexFunction = library.makeFunction(name: "gelFieldVertex")
        light.fragmentFunction = library.makeFunction(name: "gelLight")
        light.colorAttachments[0].pixelFormat = .bgra8Unorm
        let nearest = MTLDepthStencilDescriptor()
        nearest.depthCompareFunction = .less
        nearest.isDepthWriteEnabled = true
        guard let fieldState = try? device.makeRenderPipelineState(descriptor: field),
              let lightState = try? device.makeRenderPipelineState(descriptor: light),
              let depthState = device.makeDepthStencilState(descriptor: nearest) else {
            Log.write("[live-ink] error gel pipelines did not build")
            return nil
        }
        return (device, queue, fieldState, depthState, lightState)
    }()

    /// The field's distance, half width and shimmer phase, a pixel each.
    static let fieldFormat = MTLPixelFormat.rgba16Float
    /// What the field reads where no part of the mark is near.
    static let far: Double = 10_000

    /// A field pass's targets for a layer `width` by `height` px.
    static func targets(width: Int, height: Int, device: MTLDevice) -> (field: MTLTexture, depth: MTLTexture)? {
        let field = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: fieldFormat, width: width, height: height, mipmapped: false)
        field.usage = [.renderTarget, .shaderRead]
        field.storageMode = .private
        let depth = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: width, height: height, mipmapped: false)
        depth.usage = .renderTarget
        // The depth only picks the nearest part within the field pass, so on Apple's GPUs it never
        // needs memory.
        depth.storageMode = device.supportsFamily(.apple7) ? .memoryless : .private
        guard let fieldTexture = device.makeTexture(descriptor: field), let depthTexture = device.makeTexture(descriptor: depth) else { return nil }
        return (fieldTexture, depthTexture)
    }

    struct Uniforms {
        var size: SIMD2<Float>
        var scale: Float
        var time: Float
        var light: SIMD4<Float>
        var deep: SIMD4<Float>
        var glow: SIMD4<Float>
        var more: SIMD4<Float>
        var behind: SIMD4<Float>
        /// xy: px taken off every vertex's place, so a line laid out once can be drawn as its layer moves.
        var offset: SIMD4<Float>
        var material: SIMD4<Float>
        var lightPlace: SIMD4<Float>
        /// The head's corners in px, two to each, moved in by its rounding.
        var head: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) = (.zero, .zero, .zero, .zero)
        /// The corner count, the rounding in px, how far the head is shrunk in px, and px along the line at it.
        var headShape: SIMD4<Float> = .zero
        /// x: the line's half width where it meets the head, px.
        var headMore: SIMD4<Float> = .zero
        /// The pointer's place in px of the layer, its light's height over the screen in px, and how
        /// much of the light it gives: 0 where the layer's place on the screen is not known.
        var pointer: SIMD4<Float> = .zero
    }

    /// What a layer draws: its line in points of the layer, and its head's corners.
    struct Shape {
        var stroke: InkHand.Stroke
        var width: CGFloat
        var head: [CGPoint]
    }

    /// The most corners a head can have.
    static let headCorners = 8

    /// Lays a mark's pieces out in px from `origin`, each as triangles over the pixels its distance
    /// matters to: its edge and the glow's reach past it. A vertex is 10 floats: its place, the
    /// segment's ends, their half widths, the length along the line at the segment's start, and its
    /// kind, 0 a segment and 1 the head (`GelVertex`).
    struct Builder {
        let width: CGFloat
        let origin: CGPoint
        let scale: CGFloat
        let reach: CGFloat

        /// The whole of `shape`: its line, its round ends and its head.
        func vertices(_ shape: Shape) -> [Float] {
            ends(of: shape.stroke, length: InkHand.lengths(shape.stroke.points).last ?? 0)
                + segments(shape.stroke, 0..<max(shape.stroke.points.count - 1, 0), startLength: 0).vertices
                + head(shape)
        }

        /// Segments `range` of `stroke`, segment `i` joining points `i` and `i + 1`, with the length
        /// along the line at the range's first point, and the length at its last. Each segment covers
        /// a quad mitred to its neighbours, so together they cover the line's reach without gaps; at a
        /// turn too sharp to mitre, a square round the point covers what the quads miss.
        func segments(_ stroke: InkHand.Stroke, _ range: Range<Int>, startLength: CGFloat) -> (vertices: [Float], endLength: CGFloat) {
            var out: [Float] = []
            let points = stroke.points
            guard points.count > 1, !range.isEmpty else { return (out, startLength) }
            out.reserveCapacity(range.count * 60)
            var along = startLength
            for index in range {
                let next = index + 1
                let length = hypot(points[next].x - points[index].x, points[next].y - points[index].y)
                let n = normal(points, index)
                let (ma, la) = miter(points, at: index, stroke: stroke), (mb, lb) = miter(points, at: next, stroke: stroke)
                let a0 = CGPoint(x: points[index].x + ma.x * la, y: points[index].y + ma.y * la)
                let a1 = CGPoint(x: points[index].x - ma.x * la, y: points[index].y - ma.y * la)
                let b0 = CGPoint(x: points[next].x + mb.x * lb, y: points[next].y + mb.y * lb)
                let b1 = CGPoint(x: points[next].x - mb.x * lb, y: points[next].y - mb.y * lb)
                let segment = (index, next, along)
                for p in [a0, a1, b0, a1, b1, b0] { put(&out, p, segment, stroke) }
                if index > 0, ma.x * n.x + ma.y * n.y < Self.sharpest {
                    let before = (index - 1, index, along - hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y))
                    square(&out, round: points[index], half: extent(stroke, index), before, stroke)
                    square(&out, round: points[index], half: extent(stroke, index), segment, stroke)
                }
                along += length
            }
            return (out, along)
        }

        /// The line's round ends: a square round each end, lit as its segment's capsule. `length` is
        /// the line's.
        func ends(of stroke: InkHand.Stroke, length: CGFloat) -> [Float] {
            var out: [Float] = []
            let points = stroke.points
            guard let last = points.indices.last else { return out }
            let start = (0, min(1, last), CGFloat(0))
            square(&out, round: points[0], half: extent(stroke, 0), start, stroke)
            if last > 0 {
                let end = (last - 1, last, length - hypot(points[last].x - points[last - 1].x, points[last].y - points[last - 1].y))
                square(&out, round: points[last], half: extent(stroke, last), end, stroke)
            }
            return out
        }

        /// The head: a square over its corners and the glow's reach past them.
        func head(_ shape: Shape) -> [Float] {
            guard shape.head.count > 2, let first = shape.head.first else { return [] }
            let box = shape.head.reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
                .insetBy(dx: -reach - 2, dy: -reach - 2)
            let s = Float(scale)
            var out: [Float] = []
            for p in [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY), CGPoint(x: box.minX, y: box.maxY),
                      CGPoint(x: box.maxX, y: box.minY), CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)] {
                out += [Float(p.x - origin.x) * s, Float(p.y - origin.y) * s, 0, 0, 0, 0, 0, 0, 0, 1]
            }
            return out
        }

        /// A miter's cosine below this is too sharp to mitre: the quads would reach twice the line's
        /// extent and on past it.
        private static let sharpest: CGFloat = 0.5

        /// The direction a point's quad corners lie in from it, and how far: the mean of its two
        /// segments' normals, as far as keeps each quad's edge the line's extent from its segment.
        private func miter(_ points: [CGPoint], at index: Int, stroke: InkHand.Stroke) -> (CGPoint, CGFloat) {
            let e = extent(stroke, index)
            let after = normal(points, min(index, points.count - 2))
            guard index > 0, index < points.count - 1 else { return (after, e) }
            let before = normal(points, index - 1)
            let sum = CGPoint(x: before.x + after.x, y: before.y + after.y)
            let length = hypot(sum.x, sum.y)
            guard length > 1e-3 else { return (after, e) }
            let m = CGPoint(x: sum.x / length, y: sum.y / length)
            return (m, e / max(m.x * after.x + m.y * after.y, Self.sharpest))
        }

        /// The unit normal of segment `index`, or of the nearest segment with a length.
        private func normal(_ points: [CGPoint], _ index: Int) -> CGPoint {
            var i = index
            while i >= 0 {
                let dx = points[i + 1].x - points[i].x, dy = points[i + 1].y - points[i].y
                let length = hypot(dx, dy)
                if length > 1e-4 { return CGPoint(x: -dy / length, y: dx / length) }
                i -= 1
            }
            return CGPoint(x: 0, y: 1)
        }

        /// How far past point `index` its pieces reach: the widest of it and its neighbours, and the glow.
        private func extent(_ stroke: InkHand.Stroke, _ index: Int) -> CGFloat {
            let near = max(index - 1, 0)...min(index + 1, stroke.points.count - 1)
            return near.map { half(stroke, $0) }.max()! + reach + 2
        }

        private func half(_ stroke: InkHand.Stroke, _ index: Int) -> CGFloat { max(stroke.widths[index] * width / 2, 0.05) }

        private func square(_ into: inout [Float], round p: CGPoint, half: CGFloat, _ segment: (Int, Int, CGFloat), _ stroke: InkHand.Stroke) {
            for (dx, dy) in [(-1, -1), (1, -1), (-1, 1), (1, -1), (1, 1), (-1, 1)] as [(CGFloat, CGFloat)] {
                put(&into, CGPoint(x: p.x + dx * half, y: p.y + dy * half), segment, stroke)
            }
        }

        private func put(_ into: inout [Float], _ p: CGPoint, _ segment: (Int, Int, CGFloat), _ stroke: InkHand.Stroke) {
            let s = Float(scale)
            let a = stroke.points[segment.0], b = stroke.points[segment.1]
            into += [Float(p.x - origin.x) * s, Float(p.y - origin.y) * s, Float(a.x - origin.x) * s, Float(a.y - origin.y) * s,
                     Float(b.x - origin.x) * s, Float(b.y - origin.y) * s, Float(half(stroke, segment.0)) * s,
                     Float(half(stroke, segment.1)) * s, Float(segment.2) * s, 0]
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
        return Array(corners.prefix(headCorners))
    }

    /// Puts `shape`'s head into `uniforms`, laid out from `origin`: its corners moved in by its
    /// rounding, which is a share of the line's width where it meets the head so the two read as one
    /// soft shape, and shrunk toward its middle by `1 - grown` of the way, so it grows out of the line.
    static func head(of shape: Shape, origin: CGPoint, scale: CGFloat, grown: CGFloat, into uniforms: inout Uniforms) {
        let corners = shape.head
        guard corners.count > 2 else { uniforms.headShape = .zero; return }
        let lineHalf = max((shape.stroke.widths.last ?? 1) * shape.width / 2, 0.5)
        // The middle a rounding keeps its edges parallel round: a triangle's incentre, else the mean.
        var middle = CGPoint(x: corners.map(\.x).reduce(0, +) / CGFloat(corners.count), y: corners.map(\.y).reduce(0, +) / CGFloat(corners.count))
        if corners.count == 3 {
            let (a, b, c) = (corners[0], corners[1], corners[2])
            let la = hypot(b.x - c.x, b.y - c.y), lb = hypot(a.x - c.x, a.y - c.y), lc = hypot(a.x - b.x, a.y - b.y)
            let sum = max(la + lb + lc, .ulpOfOne)
            middle = CGPoint(x: (la * a.x + lb * b.x + lc * c.x) / sum, y: (la * a.y + lb * b.y + lc * c.y) / sum)
        }
        let inradius = zip(corners, corners.dropFirst() + [corners[0]]).map { a, b -> CGFloat in
            let dx = b.x - a.x, dy = b.y - a.y
            return abs((middle.x - a.x) * dy - (middle.y - a.y) * dx) / max(hypot(dx, dy), .ulpOfOne)
        }.min() ?? 0
        guard inradius > 0.1 else { uniforms.headShape = .zero; return }
        let rounding = min(lineHalf * headRounding, inradius * 0.8)
        let keep = 1 - rounding / inradius
        let px = corners.map { p -> SIMD2<Float> in
            SIMD2(Float((middle.x + (p.x - middle.x) * keep - origin.x) * scale), Float((middle.y + (p.y - middle.y) * keep - origin.y) * scale))
        }
        func pair(_ i: Int) -> SIMD4<Float> {
            SIMD4(lowHalf: i < px.count ? px[i] : .zero, highHalf: i + 1 < px.count ? px[i + 1] : .zero)
        }
        uniforms.head = (pair(0), pair(2), pair(4), pair(6))
        uniforms.headShape = SIMD4(Float(px.count), Float(rounding * scale), Float((1 - min(max(grown, 0), 1)) * inradius * scale),
                                   Float((InkHand.lengths(shape.stroke.points).last ?? 0) * scale))
        uniforms.headMore = SIMD4(Float(lineHalf * scale), 0, 0, 0)
    }

    /// How round a head's corners are, a share of the line's half width where it meets the head.
    static let headRounding: CGFloat = 0.6

    /// The tweaks' values as the shader takes them. `override` is the done state's colour, which
    /// takes the ice's place and, darkened, the deep blue's.
    static func uniforms(_ ui: UITweaks, size: CGSize, scale: CGFloat, time: CFTimeInterval, override: CGColor?,
                         deepness: CGFloat) -> Uniforms {
        let light = rgb(override ?? SRGB(hex: ui.inkGelLight)?.cgColor ?? defaultIce)
        let deep = override.map { rgb($0) * 0.45 } ?? rgb(SRGB(hex: ui.inkGelDeep)?.cgColor ?? defaultDeep)
        return Uniforms(size: SIMD2(Float(size.width), Float(size.height)), scale: Float(scale), time: Float(time),
                        light: SIMD4(light, Float(ui.inkGelCore)), deep: SIMD4(deep, 0),
                        glow: SIMD4(Float(ui.inkGelGlow), Float(ui.inkGelBloom), Float(ui.inkGelGlowRadius * scale), Float(ui.inkGelShadow)),
                        more: SIMD4(0, Float(ui.inkGelWander), Float(ui.inkGelShimmer), Float(ui.inkGelSheen)),
                        behind: SIMD4(Float(deepness), 0, 0, Float(ui.inkGelSheathDepth)), offset: .zero,
                        material: SIMD4(Float(ui.inkGelHighlightSharpness), Float(ui.inkGelGlowFalloff), Float(ui.inkGelDeepEdge), Float(ui.inkGelEdgeOpacity)),
                        lightPlace: SIMD4(Float(ui.inkGelShimmerLength), Float(ui.inkGelShimmerSpeed), Float(ui.inkGelLightAngle * .pi / 180),
                                          Float(ui.inkGelLightHeight)))
    }

    /// The ice and the deep blue when the settings' colours do not parse.
    static let defaultIce = CGColor(srgbRed: 0.55, green: 0.78, blue: 1, alpha: 1)
    static let defaultDeep = CGColor(srgbRed: 0.14, green: 0.3, blue: 0.62, alpha: 1)

    /// How deep a stroke over content of both kinds goes: far enough that its deep sheath starts a
    /// little past the middle of the line, leaving a light middle, at `sheathDepth`.
    static func mixedDeepness(sheathDepth: Double) -> CGFloat { CGFloat(min(0.57 / max(sheathDepth, 0.01), 1)) }

    private static func rgb(_ colour: CGColor) -> SIMD3<Float> {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let c = colour.converted(to: space, intent: .defaultIntent, options: nil)?.components, c.count >= 3 else { return SIMD3(0.55, 0.78, 1) }
        return SIMD3(Float(c[0]), Float(c[1]), Float(c[2]))
    }
}

/// A line's settled start, laid out once in px and kept in a buffer that only grows, so a line under
/// the pen costs the same to lay out at every length. A frame the GPU is still drawing reads only
/// vertices that were there when it was encoded, and those are never written again.
@MainActor
final class SettledLine {
    let builder: InkGel.Builder
    /// The segments laid out, from the line's start, and the length along the line to their end.
    private(set) var segments = 0
    private(set) var length: CGFloat = 0
    private(set) var vertices = GrowingBuffer()

    init(builder: InkGel.Builder) {
        self.builder = builder
    }

    /// Lays out the segments of `stroke` that its first `settled` points fix. A segment's end is
    /// mitred to the segment after it, so the last settled point ends no segment yet.
    func extend(_ stroke: InkHand.Stroke, settled: Int, device: MTLDevice) {
        let fixed = min(settled, stroke.points.count) - 2
        guard fixed > segments else { return }
        let laid = builder.segments(stroke, segments..<fixed, startLength: length)
        vertices.append(laid.vertices, device: device)
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

/// How light the screen is behind the person's ink, so each stroke takes the colour that stands out
/// there (`InkContrast`). Each display is captured without Vignette's own windows when inking starts,
/// after an answer is drawn, and, while ink is on the screen, shortly after the person clicks,
/// scrolls, types or brings another app forward, since any of those can change what is behind the
/// ink. Each capture lights macOS's screen recording indicator for a moment, so nothing captures on a
/// timer. A capture is kept as a grid of 8 pt cells (`LivePacket.Luminance`). A stroke eases to the colour a
/// new map gives it. Without Screen Recording there is no map, and the ink is the ice.
@MainActor
final class InkBackdrop {
    static let shared = InkBackdrop()

    struct Map {
        /// The display it covers, in global top-left points.
        let frame: CGRect
        let luminance: LivePacket.Luminance
    }

    private var maps: [Map] = []
    private var capturing: Task<Void, Never>?
    /// Counts the captures taken in, so a stroke knows its colour was chosen from an older one.
    private(set) var generation = 0

    /// The size of a map's cell, in points.
    static let cell: CGFloat = 8

    /// How long after the person's last click, scroll or key the maps are read again, in seconds, so
    /// a scroll or a burst of typing is read once it stops and what it changed has drawn.
    static let settle: TimeInterval = 0.3

    private var interactions: Any?
    private var appCameForward: NSObjectProtocol?
    private var settling: DispatchWorkItem?

    /// Reads the maps again after the person's interactions while ink is on the screen, and stops once
    /// none is. Keys reach the monitor only while Vignette is trusted for Accessibility.
    func keepFresh() {
        guard interactions == nil else { return }
        let events: NSEvent.EventTypeMask = [.leftMouseUp, .rightMouseUp, .otherMouseUp, .scrollWheel, .keyDown]
        interactions = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            MainActor.assumeIsolated { self?.interacted() }
        }
        appCameForward = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.interacted() }
        }
    }

    private func interacted() {
        guard InkClock.shared.showsInk else {
            interactions.map(NSEvent.removeMonitor)
            appCameForward.map(NSWorkspace.shared.notificationCenter.removeObserver)
            interactions = nil
            appCameForward = nil
            settling?.cancel()
            return
        }
        settling?.cancel()
        let read = DispatchWorkItem { [weak self] in self?.refresh() }
        settling = read
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle, execute: read)
    }

    /// Captures the displays again, and calls `read` once the new maps are in. A capture still on its
    /// way is dropped, and its `read` with it.
    func refresh(then read: (() -> Void)? = nil) {
        capturing?.cancel()
        let started = CACurrentMediaTime()
        capturing = Task { [weak self] in
            let captured = await Self.capture()
            guard !Task.isCancelled, let self, !captured.isEmpty else { return }
            self.maps = captured.map { Map(frame: $0.frame, luminance: $0.luminance) }
            self.generation += 1
            InkClock.shared.backdropChanged()
            Log.write("[live-ink] backdrop read displays=\(captured.count) ms=\(Int((CACurrentMediaTime() - started) * 1000))")
            read?()
        }
    }

    /// The brightness of the cell under `point`, in global top-left points, sRGB encoded from 0 to 1,
    /// or nil with no map there.
    func cell(at point: CGPoint) -> CGFloat? {
        maps.lazy.compactMap { $0.luminance.value(at: point) }.first
    }

    /// The mean brightness, 0 to 1, under `rect` in global top-left points, or nil with no map there.
    func brightness(in rect: CGRect) -> CGFloat? {
        maps.lazy.compactMap { $0.luminance.mean(in: rect) }.first
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
        InkBackdrop.shared.keepFresh()
        watchPointer()
        wake()
    }

    /// The gel is lit from the pointer, so a move draws it again, whatever the motion setting: the
    /// light follows the hand rather than animating. The link rests while nothing moves, so the
    /// pointer's moves wake it, in Vignette's windows and over every other app's.
    private var pointerWatch: [Any] = []
    private var lastPointer = CGPoint(x: -1, y: -1)

    private func watchPointer() {
        guard pointerWatch.isEmpty else { return }
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.wake() }
        }) { pointerWatch.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.wake() }
            return event
        }) { pointerWatch.append(local) }
    }

    private func stopWatchingPointer() {
        pointerWatch.forEach(NSEvent.removeMonitor)
        pointerWatch = []
    }

    /// Whether any ink is on the screen.
    var showsInk: Bool { layers.values.contains { $0.layer?.isVisible == true } }

    func remove(_ layer: InkMarkLayer) {
        layers[ObjectIdentifier(layer)] = nil
    }

    /// The backdrop was read again: every gel chooses its colour again.
    func backdropChanged() {
        layers.values.forEach { $0.layer?.backdropChanged() }
        wake()
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
        let pointer = NSEvent.mouseLocation
        let pointerMoved = ui.inkGelPointerLight > 0 && pointer != lastPointer
        lastPointer = pointer
        var drawn: [(commands: MTLCommandBuffer, drawable: CAMetalDrawable)] = []
        var moving = pointerMoved
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
        if layers.isEmpty { stopWatchingPointer() }
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
