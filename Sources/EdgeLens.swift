import AppKit
import CoreMedia
import CoreVideo
import Metal
import QuartzCore
import ScreenCaptureKit

/// A live picture of one display without live ink's overlay, for the pointer field and the wake,
/// which bend the screen's own pixels. ScreenCaptureKit sends a frame only when something on the display changed,
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

/// Live ink's pointer field and wake, drawn by a Metal shader over a live picture of the screen
/// (docs/live-ink-cursor-2026-10-10.md): a ring round the pointer while the chord is held, and rings
/// that spread behind the pen while it draws. It fades in once the first frame is drawn, so it never
/// shows the screen as it was before the chord went down. Without a picture of the screen, because
/// Screen Recording is refused or the stream stopped, the ring still glows and nothing bends.
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
        // Drawing with no picture of the screen still binds one; the shader reads none of it.
        let blankDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
              let blank = device.makeTexture(descriptor: blankDescriptor) else { return nil }
        return (device, queue, pipeline, blank)
    }()

    /// Whether this Mac can draw it at all.
    static var isAvailable: Bool { metal != nil }

    private let feed = ScreenFeed()
    /// How long the GPU took over each drawing since the field came up, logged with the feed's frames.
    private let gpuTimes = GPUTimes()
    private var textures: CVMetalTextureCache?
    private var link: CADisplayLink?
    private var ui = UITweaks()
    private var color = SIMD4<Float>(1, 1, 1, 1)
    private var wanted = false
    private var shown = false
    private var started: CFTimeInterval = 0
    private var asked: CFTimeInterval = 0
    private var streaming = false
    /// The screen's picture could not be had since the chord went down, so nothing bends: Screen
    /// Recording is refused, or the stream stopped.
    private var pictureFailed = false
    /// The settings or the colour changed since the last drawing.
    private var dirty = false
    /// The points the pen passed while drawing, oldest first, each the centre of one of the wake's
    /// rings. Weight is less where points crowd, so slow drawing does not stack rings.
    private var trail: [(point: CGPoint, born: CFTimeInterval, weight: Float)] = []
    /// The most points the shader takes, which fits `setFragmentBytes`' 4 KB.
    private static let trailLimit = 96
    /// The screen's frame in AppKit's global points, which the pointer is read against.
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
            self?.lostPicture()
        }
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Readies the field on `screen` as the chord goes down. With `capture` it starts the screen's
    /// picture now, so the first frame is there by the time the field shows. Each chord tries the
    /// picture again: a refusal or a stream error may be over by now.
    func prepare(display: CGDirectDisplayID, screen: NSScreen, excluding window: CGWindowID, capture: Bool) {
        guard Self.metal != nil else { return }
        screenFrame = screen.frame
        pictureFailed = false
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
                self?.lostPicture()
            }
        }
    }

    /// Draws on without the screen's picture: the ring glows and nothing bends.
    private func lostPicture() {
        streaming = false
        pictureFailed = true
        dirty = true
    }

    /// Stops the screen's picture. The field is gone by then.
    func stopFeed() {
        guard streaming else { return }
        streaming = false
        feed.stop()
        link?.isPaused = true
        Log.write("[live-ink] edge feed stopped frames=\(feed.frameCount) \(gpuTimes.take())")
    }

    func show(_ on: Bool, ui: UITweaks, color: CGColor) {
        self.ui = ui
        if let components = color.converted(to: CGColorSpace(name: CGColorSpace.displayP3)!, intent: .defaultIntent, options: nil)?.components,
           components.count >= 3 {
            self.color = SIMD4(Float(components[0]), Float(components[1]), Float(components[2]), 1)
        }
        wanted = on
        dirty = true
        if !on { trail = [] }
        if on {
            if started == 0 {
                started = CACurrentMediaTime()
                gpuTimes.reset()
                // The ring grows in from the pointer each time the field comes up.
                fieldAt = pointer
                fieldVelocity = .zero
                (fieldRadius, fieldRadiusVelocity, fieldTick) = (0, 0, started)
            }
            link?.isPaused = false
        } else {
            started = 0
            fade(in: false)
            // The feed stops once the fade is over, unless the field was asked for again by then.
            DispatchQueue.main.asyncAfter(deadline: .now() + ui.liveInkGlowFade + 0.05) { [weak self] in
                guard let self, !self.wanted else { return }
                self.stopFeed()
            }
        }
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
        let needsPicture = (ui.wakes || ui.pointerFieldBends) && !pictureFailed
        let picture = needsPicture ? feed.take() : nil
        // Bending waits for the first frame of the screen.
        if needsPicture, picture == nil { return }
        // Draws only when the screen, the ring or the settings changed, or while rings spread.
        guard dirty || fieldMoved || picture?.fresh == true || !trail.isEmpty else { return }
        dirty = false
        draw(picture?.frame, at: now)
        if !shown {
            // `ms` is how long the field waited for the picture once it was wanted, `stream-ms` how long
            // since the picture was asked for, as the chord went down.
            if needsPicture { Log.write("[live-ink] edge first frame ms=\(Int((now - started) * 1000)) stream-ms=\(Int((now - asked) * 1000))") }
            fade(in: true)
        }
    }

    /// The pointer now, in the layer's points, moved from the arrow's tip to its middle.
    private var pointer: CGPoint {
        let mouse = NSEvent.mouseLocation
        return CGPoint(x: mouse.x - screenFrame.minX + Self.fieldOffset.x, y: screenFrame.maxY - mouse.y + Self.fieldOffset.y)
    }

    /// Moves the ring round the pointer on its springs to `now`: its centre after the pointer, over
    /// `ui.liveInkFieldFollow`, and its radius to its size, smaller while pressing, over the field's
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

    private func uniforms(size: CGSize, at now: CFTimeInterval, hasPicture: Bool) -> EdgeUniforms {
        var uniforms = EdgeUniforms()
        uniforms.color = color
        uniforms.size = SIMD2(Float(size.width), Float(size.height))
        // Without a picture of the screen there is nothing to bend, only light to draw.
        if hasPicture, !trail.isEmpty {
            uniforms.wakeCount = Float(trail.count)
            uniforms.wakeStrength = Float(ui.liveInkWakeStrength)
            uniforms.wakeSize = Float(ui.liveInkWakeSize)
            uniforms.wakeLife = Float(ui.liveInkWakeDuration)
            // A ring reaches its size, and its packet of waves 24 pt past it.
            let reach = ui.liveInkWakeSize + 24
            uniforms.wakeLeft = Float(trail.map(\.point.x).min()! - reach)
            uniforms.wakeTop = Float(trail.map(\.point.y).min()! - reach)
            uniforms.wakeRight = Float(trail.map(\.point.x).max()! + reach)
            uniforms.wakeBottom = Float(trail.map(\.point.y).max()! + reach)
        }
        if ui.pointerField {
            uniforms.fieldX = Float(fieldAt.x)
            uniforms.fieldY = Float(fieldAt.y)
            uniforms.fieldRadius = Float(fieldRadius)
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
        return uniforms
    }
}

/// The shader's uniforms, in the order and alignment of `EdgeUniforms` in EdgeLens.metal.
struct EdgeUniforms {
    var color = SIMD4<Float>(repeating: 0)
    var size = SIMD2<Float>(repeating: 0)
    var wakeCount: Float = 0
    var wakeStrength: Float = 0
    var wakeSize: Float = 0
    var wakeLife: Float = 0
    var wakeLeft: Float = 0
    var wakeTop: Float = 0
    var wakeRight: Float = 0
    var wakeBottom: Float = 0
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

extension UITweaks {
    /// Whether the wake follows the pen while drawing. Reduce Motion turns it off, since its
    /// duration is motion.
    var wakes: Bool { liveInkWakeStrength > 0 && liveInkWakeDuration > 0 && liveInkWakeSize > 0 }
    /// Whether the ring round the pointer shows while the chord is held.
    var pointerField: Bool { liveInkFieldSize > 0 && (liveInkFieldBend > 0 || liveInkFieldSplit > 0 || liveInkFieldGlow > 0) }
    /// Whether that ring bends the screen, which needs a live picture of it.
    var pointerFieldBends: Bool { liveInkFieldSize > 0 && (liveInkFieldBend > 0 || liveInkFieldSplit > 0) }
}
