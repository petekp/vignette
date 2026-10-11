import AppKit
import CoreMedia
import CoreVideo
import Metal
import QuartzCore
import ScreenCaptureKit

/// A live picture of one display without live ink's overlay, for the edge looks that bend the
/// screen's own pixels. ScreenCaptureKit sends a frame only when something on the display changed,
/// so a still screen costs nothing after the first. Frames are kept, not announced: whoever draws
/// takes the newest one at its own pace.
final class ScreenFeed: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    enum Failure: Error { case noPermission, noDisplay }

    private let queue = DispatchQueue(label: "vignette.edge-feed", qos: .userInteractive)
    private let lock = NSLock()
    private var stream: SCStream?
    private var latest: CVPixelBuffer?
    private var fresh = false
    private var frames = 0
    /// Runs on the main thread when the stream stops on its own.
    var onStopped: ((Error) -> Void)?

    /// Starts the stream of `display` at `pixels`, leaving out the windows `excluding` names.
    func start(display: CGDirectDisplayID, pixels: CGSize, excluding: [CGWindowID]) async throws {
        guard CGPreflightScreenCaptureAccess() else { throw Failure.noPermission }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let screen = content.displays.first(where: { $0.displayID == display }) else { throw Failure.noDisplay }
        let left = content.windows.filter { excluding.contains($0.windowID) }
        let filter = SCContentFilter(display: screen, excludingWindows: left)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(pixels.width)
        configuration.height = Int(pixels.height)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.displayP3
        configuration.showsCursor = false
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 4
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        // A new stream starts with no picture, and only its own frames are kept, so a frame of an
        // earlier stream, still on its way when that one stopped, is never drawn as the screen now.
        lock.withLock { self.stream = stream; latest = nil; fresh = false; frames = 0 }
        do {
            try await stream.startCapture()
        } catch {
            detach(stream)
            throw error
        }
    }

    func stop() {
        detach()?.stopCapture { _ in }
    }

    /// Forgets the stream and its last picture, about 24 MB on a 3024 by 1964 display, and answers
    /// the stream it forgot. Given a stream, forgets only that one, so a stream this feed already
    /// stopped or replaced changes nothing.
    @discardableResult
    private func detach(_ stream: SCStream? = nil) -> SCStream? {
        lock.withLock {
            guard let current = self.stream, stream.map({ $0 === current }) ?? true else { return nil }
            self.stream = nil
            latest = nil
            fresh = false
            return current
        }
    }

    /// The newest frame, and whether it arrived since the last time this was asked.
    func take() -> (frame: CVPixelBuffer, fresh: Bool)? {
        lock.withLock {
            guard let latest else { return nil }
            defer { fresh = false }
            return (latest, fresh)
        }
    }

    var frameCount: Int { lock.withLock { frames } }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: status) == .complete,
              let buffer = sampleBuffer.imageBuffer else { return }
        lock.withLock {
            guard stream === self.stream else { return }
            latest = buffer
            fresh = true
            frames += 1
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // A stream this feed already stopped or replaced says nothing.
        guard detach(stream) != nil else { return }
        DispatchQueue.main.async { [weak self] in self?.onStopped?(error) }
    }
}

/// The GPU time of each drawing, added from Metal's completion threads, so the log can say whether a
/// look keeps up with the display.
final class GPUTimes: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var total: CFTimeInterval = 0
    private var worst: CFTimeInterval = 0

    func add(_ seconds: CFTimeInterval) {
        guard seconds > 0 else { return }
        lock.withLock { count += 1; total += seconds; worst = max(worst, seconds) }
    }

    func reset() { lock.withLock { count = 0; total = 0; worst = 0 } }

    /// `drawn=<n> gpu-ms mean=<m> max=<m>` for the drawings so far, and starts again.
    func take() -> String {
        lock.withLock {
            defer { count = 0; total = 0; worst = 0 }
            let mean = count > 0 ? total / Double(count) * 1000 : 0
            return String(format: "drawn=%d gpu-ms mean=%.2f max=%.2f", count, mean, worst * 1000)
        }
    }
}

/// Live ink's edge drawn by a Metal shader over a live picture of the screen: glass, and the other
/// looks the edge lab tries, and the wake that follows the pen while drawing
/// (docs/live-ink-edge-lab-2026-10-08.md). It fades in once the first frame is drawn, so it never
/// shows the screen as it was before the chord went down.
///
/// It draws only from its display link, at most once a refresh. Drawing from each frame's arrival
/// queued a main-thread block per frame: the run loop never got back to commit the layer, so every
/// `nextDrawable()` waited out its one-second timeout and the app stopped answering.
@MainActor
final class EdgeLensLayer: CAMetalLayer {
    private static let metal: (device: MTLDevice, queue: MTLCommandQueue, pipeline: MTLRenderPipelineState, blank: MTLTexture)? = {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "edgeVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "edgeFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        // A look that draws only light still binds a picture of the screen; it reads none.
        let blankDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
              let blank = device.makeTexture(descriptor: blankDescriptor) else { return nil }
        return (device, queue, pipeline, blank)
    }()

    /// Whether this Mac can draw it at all; without it the plain glow shows.
    static var isAvailable: Bool { metal != nil }

    private let feed = ScreenFeed()
    /// How long the GPU took over each drawing since the look came up, logged with the feed's frames.
    private let gpuTimes = GPUTimes()
    private var textures: CVMetalTextureCache?
    private var link: CADisplayLink?
    private var ui = UITweaks()
    private var color = SIMD4<Float>(1, 1, 1, 1)
    private var pen = CGPoint.zero
    private var wanted = false
    private var shown = false
    private var started: CFTimeInterval = 0
    private var asked: CFTimeInterval = 0
    private var streaming = false
    /// Something besides the screen changed since the last drawing: the pen, the settings, or the look.
    private var dirty = false
    /// The points the pen passed while drawing, oldest first, each the centre of one of the wake's
    /// rings. Weight is less where points crowd, so slow drawing does not stack rings.
    private var trail: [(point: CGPoint, born: CFTimeInterval, weight: Float)] = []
    /// The display's corners and notch, taken when the look is readied on it.
    private var shape = DisplayShape()
    /// The screen's frame in AppKit's global points, which the pointer field reads the pointer against.
    private var screenFrame = CGRect.zero
    /// The ring round the pointer: where its centre is and how fast it moves, in the layer's points,
    /// its radius, and the last refresh that moved them. It is sprung once a refresh from where the
    /// pointer is then, not from the last event.
    private var fieldAt = CGPoint.zero
    private var fieldVelocity = CGVector.zero
    private var fieldRadius: CGFloat = 0
    private var fieldRadiusVelocity: CGFloat = 0
    private var fieldTick: CFTimeInterval = 0
    private var pressing = false
    /// From the arrow's tip, its hotspot, to about the middle of the arrow, so the ring sits round
    /// the arrow rather than round its tip.
    private static let fieldOffset = CGPoint(x: 4, y: 6)
    /// The most points the shader takes, which fits `setFragmentBytes`' 4 KB.
    private static let trailLimit = 96
    /// Runs when the look cannot be drawn, so the plain glow can show in its place.
    var onUnavailable: (() -> Void)?

    init(scale: CGFloat) {
        super.init()
        contentsScale = scale
        anchorPoint = .zero
        isOpaque = false
        framebufferOnly = true
        pixelFormat = .bgra8Unorm
        colorspace = CGColorSpace(name: CGColorSpace.displayP3)
        maximumDrawableCount = 3
        opacity = 0
        if let metal = Self.metal {
            device = metal.device
            CVMetalTextureCacheCreate(nil, nil, metal.device, nil, &textures)
        }
        feed.onStopped = { [weak self] error in
            Log.write("[live-ink] edge feed stopped: \(error)")
            self?.streaming = false
            self?.onUnavailable?()
        }
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Readies the look on `screen` as the chord goes down. A look that draws from the screen starts its
    /// picture now, so the first frame is there by the time the look shows.
    func prepare(display: CGDirectDisplayID, screen: NSScreen, excluding window: CGWindowID, capture: Bool) {
        guard Self.metal != nil else { return }
        shape = DisplayShape(of: screen)
        screenFrame = screen.frame
        if link == nil {
            link = screen.displayLink(target: self, selector: #selector(tick))
            link?.add(to: .main, forMode: .common)
            link?.isPaused = true
        }
        guard capture, !streaming else { return }
        streaming = true
        asked = CACurrentMediaTime()
        let pixels = CGSize(width: screen.frame.width * screen.backingScaleFactor, height: screen.frame.height * screen.backingScaleFactor)
        Task { @MainActor [weak self, feed] in
            do {
                try await feed.start(display: display, pixels: pixels, excluding: [window])
            } catch {
                Log.write("[live-ink] edge feed could not start: \(error)")
                self?.streaming = false
                self?.onUnavailable?()
            }
        }
    }

    /// Stops the screen's picture. The look is gone by then.
    func stopFeed() {
        guard streaming else { return }
        streaming = false
        feed.stop()
        link?.isPaused = true
        Log.write("[live-ink] edge feed stopped frames=\(feed.frameCount) \(gpuTimes.take())")
    }

    func show(_ on: Bool, ui: UITweaks, color: CGColor, pen: CGPoint?) {
        self.ui = ui
        if let components = color.converted(to: CGColorSpace(name: CGColorSpace.displayP3)!, intent: .defaultIntent, options: nil)?.components,
           components.count >= 3 {
            self.color = SIMD4(Float(components[0]), Float(components[1]), Float(components[2]), 1)
        }
        if let pen { self.pen = pen }
        wanted = on
        dirty = true
        if !on { trail = [] }
        if on {
            if started == 0 {
                started = CACurrentMediaTime()
                gpuTimes.reset()
                // The ring grows in from the pointer each time the look comes up.
                fieldAt = pointer
                fieldVelocity = .zero
                (fieldRadius, fieldRadiusVelocity, fieldTick) = (0, 0, started)
            }
            link?.isPaused = false
        } else {
            started = 0
            fade(in: false)
            // The feed stops once the fade is over, unless the look was asked for again by then.
            DispatchQueue.main.asyncAfter(deadline: .now() + ui.liveInkGlowFade + 0.05) { [weak self] in
                guard let self, !self.wanted else { return }
                self.stopFeed()
            }
        }
    }

    func follow(_ pen: CGPoint) {
        guard wanted else { return }
        self.pen = pen
        dirty = true
    }

    /// The button went down or up: the ring tightens and brightens while it is down.
    func press(_ down: Bool) {
        pressing = down
    }

    /// Starts one of the wake's rings where the pen is drawing, unless the last one is under 6 pt away.
    func wake(_ point: CGPoint) {
        guard wanted, ui.wakes else { return }
        let spacing = trail.last.map { hypot(point.x - $0.point.x, point.y - $0.point.y) } ?? 12
        guard spacing >= 6 else { return }
        trail.append((point, CACurrentMediaTime(), Float(min(spacing / 12, 1))))
        if trail.count > Self.trailLimit { trail.removeFirst(trail.count - Self.trailLimit) }
    }

    @objc private func tick() {
        guard wanted else { link?.isPaused = true; return }
        let now = CACurrentMediaTime()
        let rippling = !trail.isEmpty
        trail.removeAll { now - $0.born >= ui.liveInkWakeDuration }
        // One more drawing once the last ring is gone, so none of it stays.
        if rippling, trail.isEmpty { dirty = true }
        let fieldMoved = stepField(at: now)
        let needsPicture = look.drawsFromScreen || ui.wakes || ui.pointerFieldBends
        let picture = needsPicture ? feed.take() : nil
        // A look that draws from the screen waits for its first frame.
        if needsPicture, picture == nil { return }
        // A still look draws only when the screen, the pen, the ring round the pointer or the settings
        // changed; a moving look, or a wake with rings, every refresh.
        guard dirty || fieldMoved || picture?.fresh == true || (look.moves && ui.liveInkEdgeSpeed > 0) || !trail.isEmpty else { return }
        dirty = false
        draw(picture?.frame, at: now)
        if !shown {
            // `ms` is how long the look waited for the picture once it was wanted, `stream-ms` how long
            // since the picture was asked for, as the chord went down.
            if needsPicture { Log.write("[live-ink] edge first frame ms=\(Int((now - started) * 1000)) stream-ms=\(Int((now - asked) * 1000))") }
            fade(in: true)
        }
    }

    private var look: Style { Style(rawValue: Int(ui.liveInkEdgeStyle.rounded())) ?? .glass }

    /// The pointer now, in the layer's points, moved from the arrow's tip to its middle.
    private var pointer: CGPoint {
        let mouse = NSEvent.mouseLocation
        return CGPoint(x: mouse.x - screenFrame.minX + Self.fieldOffset.x, y: screenFrame.maxY - mouse.y + Self.fieldOffset.y)
    }

    /// Moves the ring round the pointer on its springs to `now`: its centre after the pointer, over
    /// `ui.liveInkFieldFollow`, and its radius to its size, smaller while pressing, over the look's
    /// fade. Answers whether it moved.
    private func stepField(at now: CFTimeInterval) -> Bool {
        let dt = now - fieldTick
        fieldTick = now
        guard ui.pointerField else { return false }
        let before = (fieldAt, fieldRadius)
        let target = pointer
        if ui.liveInkFieldFollow > 0 {
            let omega = 6.6 / ui.liveInkFieldFollow
            let x = Tween.spring(value: fieldAt.x, velocity: fieldVelocity.dx, target: target.x, omega: omega, dt: dt)
            let y = Tween.spring(value: fieldAt.y, velocity: fieldVelocity.dy, target: target.y, omega: omega, dt: dt)
            fieldAt = CGPoint(x: x.value, y: y.value)
            fieldVelocity = CGVector(dx: x.velocity, dy: y.velocity)
        } else {
            fieldAt = target
            fieldVelocity = .zero
        }
        let size = CGFloat(ui.liveInkFieldSize) * (pressing ? 0.8 : 1)
        if ui.liveInkGlowFade > 0 {
            let r = Tween.spring(value: fieldRadius, velocity: fieldRadiusVelocity, target: size, omega: 6.6 / ui.liveInkGlowFade, dt: dt)
            (fieldRadius, fieldRadiusVelocity) = (r.value, r.velocity)
        } else {
            (fieldRadius, fieldRadiusVelocity) = (size, 0)
        }
        return hypot(fieldAt.x - before.0.x, fieldAt.y - before.0.y) > 0.01 || abs(fieldRadius - before.1) > 0.01
    }

    private func fade(in on: Bool) {
        guard on != shown else { return }
        shown = on
        let target: Float = on ? Float(ui.liveInkGlowOpacity) : 0
        let from = presentation()?.opacity ?? opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        opacity = target
        CATransaction.commit()
        guard ui.liveInkGlowFade > 0 else { removeAnimation(forKey: "opacity"); return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.toValue = target
        fade.duration = ui.liveInkGlowFade
        add(fade, forKey: "opacity")
    }

    private func draw(_ frame: CVPixelBuffer?, at now: CFTimeInterval) {
        guard let metal = Self.metal, let textures else { return }
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        var picture: (texture: CVMetalTexture, frame: CVPixelBuffer)?
        var screen = metal.blank
        if let frame {
            var texture: CVMetalTexture?
            CVMetalTextureCacheCreateTextureFromImage(nil, textures, frame, nil, .bgra8Unorm,
                                                      CVPixelBufferGetWidth(frame), CVPixelBufferGetHeight(frame), 0, &texture)
            guard let texture, let read = CVMetalTextureGetTexture(texture) else { return }
            picture = (texture, frame)
            screen = read
        }
        drawableSize = CGSize(width: size.width * contentsScale, height: size.height * contentsScale)
        guard let drawable = nextDrawable(), let commands = metal.queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        var uniforms = uniforms(size: size, at: now, hasPicture: frame != nil)
        // Each point: where, its age in seconds, its weight. The shader reads none when the count is 0,
        // but Metal wants a buffer bound.
        var points = trail.map { SIMD4<Float>(Float($0.point.x), Float($0.point.y), Float(now - $0.born), $0.weight) }
        if points.isEmpty { points = [SIMD4(repeating: 0)] }
        encoder.setRenderPipelineState(metal.pipeline)
        encoder.setFragmentTexture(screen, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<EdgeUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&points, length: MemoryLayout<SIMD4<Float>>.stride * points.count, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        // The capture's buffer must outlive the GPU's read of it.
        commands.addCompletedHandler { [gpuTimes] buffer in
            withExtendedLifetime(picture) {}
            gpuTimes.add(buffer.gpuEndTime - buffer.gpuStartTime)
        }
        commands.present(drawable)
        commands.commit()
    }

    /// A `#rrggbb` setting in the layer's Display P3, black for one that does not parse.
    private static func layerColor(_ hex: String) -> SIMD3<Float> {
        guard let components = SRGB(hex: hex)?.cgColor.converted(to: CGColorSpace(name: CGColorSpace.displayP3)!, intent: .defaultIntent, options: nil)?.components,
              components.count >= 3 else { return .zero }
        return SIMD3(Float(components[0]), Float(components[1]), Float(components[2]))
    }

    private func uniforms(size: CGSize, at now: CFTimeInterval, hasPicture: Bool) -> EdgeUniforms {
        var uniforms = EdgeUniforms()
        uniforms.color = color
        uniforms.size = SIMD2(Float(size.width), Float(size.height))
        uniforms.pen = SIMD2(Float(pen.x), Float(pen.y))
        uniforms.scale = Float(contentsScale)
        uniforms.style = Float(ui.liveInkEdgeStyle)
        uniforms.width = Float(ui.liveInkEdgeWidth)
        uniforms.bend = Float(ui.liveInkEdgeBend)
        uniforms.split = Float(ui.liveInkEdgeSplit)
        uniforms.shine = Float(ui.liveInkEdgeShine)
        uniforms.frost = Float(ui.liveInkEdgeFrost)
        uniforms.tint = Float(ui.liveInkEdgeTint)
        uniforms.speed = Float(ui.liveInkEdgeSpeed)
        uniforms.focus = Float(ui.liveInkEdgeFocus)
        uniforms.time = Float(now - started)
        uniforms.light = Float(ui.liveInkEdgeLight)
        uniforms.colors = Float(ui.liveInkEdgeColors)
        uniforms.repeats = Float(ui.liveInkEdgeRepeats)
        uniforms.variation = Float(ui.liveInkEdgeVariation)
        uniforms.hue = Float(ui.liveInkEdgeHue)
        uniforms.saturation = Float(ui.liveInkEdgeSaturation)
        uniforms.brightness = Float(ui.liveInkEdgeBrightness)
        uniforms.drift = Float(ui.liveInkEdgeDrift)
        uniforms.blend = Float(ui.liveInkEdgeBlend)
        let top = Float(shape.roundedTop ? ui.liveInkEdgeCorner : 0)
        (uniforms.radiusTopLeft, uniforms.radiusTopRight) = (top, top)
        if let notch = shape.notch {
            uniforms.notchLeft = Float(notch.minX)
            uniforms.notchRight = Float(notch.maxX)
            uniforms.notchHeight = Float(notch.height)
            uniforms.notchRadius = Float(DisplayShape.notchRadius)
        }
        let first = Self.layerColor(ui.liveInkEdgeColor1), second = Self.layerColor(ui.liveInkEdgeColor2)
        (uniforms.color1R, uniforms.color1G, uniforms.color1B) = (first.x, first.y, first.z)
        (uniforms.color2R, uniforms.color2G, uniforms.color2B) = (second.x, second.y, second.z)
        if ui.pointerField {
            uniforms.fieldX = Float(fieldAt.x)
            uniforms.fieldY = Float(fieldAt.y)
            uniforms.fieldRadius = Float(fieldRadius)
            // Without a picture of the screen there is nothing to bend, only light to draw.
            uniforms.fieldBend = hasPicture ? Float(ui.liveInkFieldBend) : 0
            uniforms.fieldSplit = hasPicture ? Float(ui.liveInkFieldSplit) : 0
            uniforms.fieldGlow = Float(ui.liveInkFieldGlow)
            uniforms.fieldVX = Float(fieldVelocity.dx)
            uniforms.fieldVY = Float(fieldVelocity.dy)
            uniforms.fieldStretch = Float(ui.liveInkFieldStretch)
            // Brighter while the ring is smaller than its size: as it grows in, and while pressing.
            let size = max(CGFloat(ui.liveInkFieldSize), 1)
            uniforms.fieldPress = Float(min(max((size - fieldRadius) / (size * 0.2), 0), 1))
        }
        uniforms.wakeCount = Float(trail.count)
        uniforms.wakeStrength = Float(ui.liveInkWakeStrength)
        uniforms.wakeSize = Float(ui.liveInkWakeSize)
        uniforms.wakeLife = Float(ui.liveInkWakeDuration)
        if !trail.isEmpty {
            // A ring reaches its size, and its packet of waves 24 pt past it.
            let reach = ui.liveInkWakeSize + 24
            uniforms.wakeLeft = Float(trail.map(\.point.x).min()! - reach)
            uniforms.wakeTop = Float(trail.map(\.point.y).min()! - reach)
            uniforms.wakeRight = Float(trail.map(\.point.x).max()! + reach)
            uniforms.wakeBottom = Float(trail.map(\.point.y).max()! + reach)
        }
        return uniforms
    }
}

/// The shader's uniforms, in the order and alignment of `EdgeUniforms` in EdgeLens.metal.
struct EdgeUniforms {
    var color = SIMD4<Float>(repeating: 0)
    var size = SIMD2<Float>(repeating: 0)
    var pen = SIMD2<Float>(repeating: 0)
    var scale: Float = 1
    var style: Float = 0
    var width: Float = 0
    var bend: Float = 0
    var split: Float = 0
    var shine: Float = 0
    var frost: Float = 0
    var tint: Float = 0
    var speed: Float = 0
    var focus: Float = 0
    var time: Float = 0
    var light: Float = 0
    var wakeCount: Float = 0
    var wakeStrength: Float = 0
    var wakeSize: Float = 0
    var wakeLife: Float = 0
    var wakeLeft: Float = 0
    var wakeTop: Float = 0
    var wakeRight: Float = 0
    var wakeBottom: Float = 0
    var colors: Float = 0
    var repeats: Float = 0
    var variation: Float = 0
    var hue: Float = 0
    var saturation: Float = 0
    var brightness: Float = 0
    var drift: Float = 0
    var blend: Float = 0
    var color1R: Float = 0
    var color1G: Float = 0
    var color1B: Float = 0
    var color2R: Float = 0
    var color2G: Float = 0
    var color2B: Float = 0
    var radiusTopLeft: Float = 0
    var radiusTopRight: Float = 0
    var radiusBottomRight: Float = 0
    var radiusBottomLeft: Float = 0
    var notchLeft: Float = 0
    var notchRight: Float = 0
    var notchHeight: Float = 0
    var notchRadius: Float = 0
    var fieldX: Float = 0
    var fieldY: Float = 0
    var fieldRadius: Float = 0
    var fieldBend: Float = 0
    var fieldSplit: Float = 0
    var fieldGlow: Float = 0
    var fieldVX: Float = 0
    var fieldVY: Float = 0
    var fieldStretch: Float = 0
    var fieldPress: Float = 0
}

/// The display's own shape, which the band follows: its notch, and whether its top corners are
/// rounded. macOS reports the notch, through the menu bar's areas either side of it, but not the
/// corners' radius. The MacBook displays with a notch round their top corners and not their bottom
/// ones, so a display with a notch gets top corners of `ui.liveInkEdgeCorner`, and any other display
/// square ones.
struct DisplayShape {
    var roundedTop = false
    /// The notch in the screen's points, y down from its top.
    var notch: CGRect?
    /// The notch's bottom corners, an estimate: macOS does not report them either.
    static let notchRadius: CGFloat = 8

    init() {}

    init(of screen: NSScreen) {
        guard screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
              right.minX > left.maxX else { return }
        roundedTop = true
        notch = CGRect(x: left.maxX - screen.frame.minX, y: 0, width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
    }
}

extension UITweaks {
    /// Whether the wake follows the pen while drawing. Reduce Motion turns it off, since its
    /// duration is motion.
    var wakes: Bool { liveInkWakeStrength > 0 && liveInkWakeDuration > 0 && liveInkWakeSize > 0 }
    /// Whether the ring round the pointer shows while the chord is held.
    var pointerField: Bool { liveInkFieldSize > 0 && (liveInkFieldBend > 0 || liveInkFieldSplit > 0 || liveInkFieldGlow > 0) }
    /// Whether that ring bends the screen, which needs a live picture of it.
    var pointerFieldBends: Bool { liveInkFieldSize > 0 && (liveInkFieldBend > 0 || liveInkFieldSplit > 0) }
}

extension EdgeLensLayer {
    /// The edge looks the lab tries, as `ui.liveInkEdgeStyle`. Glow is drawn by `EdgeGlow`; the rest
    /// are this layer's.
    enum Style: Int, CaseIterable {
        case glow, glass, lens, aurora, ripple, frost, auroraRipple, none

        var name: String {
            switch self {
            case .glow: "Glow"
            case .glass: "Glass"
            case .lens: "Lens"
            case .aurora: "Aurora"
            case .ripple: "Ripple"
            case .frost: "Frost"
            case .auroraRipple: "Aurora ripple"
            case .none: "None"
            }
        }

        var summary: String {
            switch self {
            case .glow: "A thin bright line along the edges, with a soft glow that is brightest near the pointer."
            case .glass: "A pane of glass whose rim curves down to the edges. The rim bends what is under it and catches the light."
            case .lens: "The edges squeeze the screen like the rim of a wide lens. The colours split where it squeezes most."
            case .aurora: "Coloured light flows round the edges, swelling and thinning as it goes."
            case .ripple: "Waves run along the edges and bend what is under them. Rings spread from the pointer."
            case .frost: "A band of frosted glass along the edges, with a bright rim."
            case .auroraRipple: "Ripple's waves bend the screen, and aurora's coloured light rides on their crests."
            case .none: "Nothing along the edges: only the wake and the pointer field show."
            }
        }

        /// Whether it draws from a live picture of the screen, which needs Screen Recording.
        var drawsFromScreen: Bool { self != .glow && self != .aurora && self != .none }
        /// Whether it moves on its own, at `ui.liveInkEdgeSpeed`.
        var moves: Bool { self == .aurora || self == .ripple || self == .auroraRipple }

        struct Slider {
            let label: String
            let path: WritableKeyPath<UITweaks, Double>
            let range: ClosedRange<Double>
            var step = 0.01
            var unit = ""
        }

        /// The values the lab starts this look from when it is picked, so each look shows at its best
        /// at once. The looks share their sliders, so without these one look kept another's.
        var startingValues: [(WritableKeyPath<UITweaks, Double>, Double)] {
            switch self {
            case .glow: [(\.liveInkGlowWidth, UITweaks().liveInkGlowWidth)]
            case .glass: [(\.liveInkEdgeWidth, 28), (\.liveInkEdgeBend, 0.5), (\.liveInkEdgeSplit, 0.3), (\.liveInkEdgeShine, 0.6),
                          (\.liveInkEdgeFrost, 0), (\.liveInkEdgeTint, 0.15), (\.liveInkEdgeFocus, 0.5)]
            case .lens: [(\.liveInkEdgeWidth, 70), (\.liveInkEdgeBend, 1.1), (\.liveInkEdgeSplit, 0.5), (\.liveInkEdgeShine, 0.2),
                         (\.liveInkEdgeTint, 0.1), (\.liveInkEdgeFocus, 0.3)]
            case .aurora: [(\.liveInkEdgeWidth, 60), (\.liveInkEdgeShine, 0.6), (\.liveInkEdgeSpeed, 0.6),
                           (\.liveInkEdgeFocus, 0.4), (\.liveInkEdgeColors, 1), (\.liveInkEdgeRepeats, 2),
                           (\.liveInkEdgeHue, 0), (\.liveInkEdgeSaturation, 0.75), (\.liveInkEdgeBrightness, 1), (\.liveInkEdgeDrift, 0.05)]
            case .ripple: [(\.liveInkEdgeWidth, 48), (\.liveInkEdgeBend, 1.2), (\.liveInkEdgeSplit, 0.4), (\.liveInkEdgeShine, 0.5),
                           (\.liveInkEdgeSpeed, 0.8), (\.liveInkEdgeFocus, 0.5)]
            case .frost: [(\.liveInkEdgeWidth, 36), (\.liveInkEdgeFrost, 0.7), (\.liveInkEdgeShine, 0.6), (\.liveInkEdgeTint, 0.1),
                          (\.liveInkEdgeFocus, 0.3)]
            case .auroraRipple: [(\.liveInkEdgeWidth, 38), (\.liveInkEdgeBend, 2), (\.liveInkEdgeLight, 1), (\.liveInkEdgeSplit, 0.5),
                                 (\.liveInkEdgeShine, 0.89), (\.liveInkEdgeSpeed, 1.51),
                                 (\.liveInkEdgeFocus, 0.5), (\.liveInkEdgeColors, 0), (\.liveInkEdgeRepeats, 2),
                                 (\.liveInkEdgeVariation, 0), (\.liveInkEdgeHue, 0), (\.liveInkEdgeSaturation, 1), (\.liveInkEdgeBrightness, 1),
                                 (\.liveInkEdgeDrift, 0.05), (\.liveInkEdgeBlend, 0)]
            case .none: []
            }
        }

        /// The sliders that change this look, besides its width, opacity and fade.
        var sliders: [Slider] {
            let bend = Slider(label: self == .ripple || self == .auroraRipple ? "Wave height" : self == .lens ? "Squeeze" : "Bend",
                              path: \.liveInkEdgeBend, range: 0...2)
            let split = Slider(label: "Colour split", path: \.liveInkEdgeSplit, range: 0...1)
            let shine = Slider(label: self == .aurora || self == .auroraRipple ? "Line" : "Shine", path: \.liveInkEdgeShine, range: 0...1)
            let light = Slider(label: "Light", path: \.liveInkEdgeLight, range: 0...1)
            let frost = Slider(label: "Frost", path: \.liveInkEdgeFrost, range: 0...1)
            let tint = Slider(label: "Tint", path: \.liveInkEdgeTint, range: 0...1)
            let speed = Slider(label: "Speed", path: \.liveInkEdgeSpeed, range: 0...3)
            let focus = Slider(label: "Pointer focus", path: \.liveInkEdgeFocus, range: 0...1)
            switch self {
            case .glow, .none: return []
            case .glass: return [bend, split, shine, frost, tint, focus]
            case .lens: return [bend, split, shine, tint, focus]
            case .aurora: return [shine, speed, focus]
            case .ripple: return [bend, split, shine, speed, focus]
            case .frost: return [frost, shine, tint, focus]
            case .auroraRipple: return [bend, light, split, shine, speed, focus]
            }
        }

        /// Whether the Colour section tunes its light.
        var hasAuroraLight: Bool { self == .aurora || self == .auroraRipple }
    }

    /// Where the aurora's colours come from, as `ui.liveInkEdgeColors`.
    enum Palette: Int, CaseIterable {
        case ink, rainbow, twoColours

        var name: String {
            switch self {
            case .ink: "Ink"
            case .rainbow: "Rainbow"
            case .twoColours: "Two colours"
            }
        }
    }

    /// How aurora ripple's light meets the screen under it, as `ui.liveInkEdgeBlend`. Each is CSS's
    /// blend mode of that name.
    enum Blend: Int, CaseIterable {
        case normal, add, screen, overlay, softLight, colorDodge, multiply, color, difference

        var name: String {
            switch self {
            case .normal: "Normal"
            case .add: "Add"
            case .screen: "Screen"
            case .overlay: "Overlay"
            case .softLight: "Soft light"
            case .colorDodge: "Colour dodge"
            case .multiply: "Multiply"
            case .color: "Colour"
            case .difference: "Difference"
            }
        }
    }
}
