import AppKit
import CoreVideo
import Metal
import QuartzCore

/// The GPU time of each drawing, added from Metal's completion threads, so the log can say whether
/// the field keeps up with the display.
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

/// Live ink's pointer field (docs/live-ink-cursor-2026-10-10.md): the ring round the pointer while
/// the chord is held, and the wake, rings that spread behind the pen while it draws. A Metal shader
/// draws both over a live picture of the screen, which they bend. Without that picture, because
/// Screen Recording is refused or the stream stopped, the ring still glows and nothing bends.
///
/// It is hidden until its holder shows it, and fades in once its first frame is drawn, so it never
/// shows the screen as it was before the chord went down. It reads the pointer and the button
/// itself, once a refresh, from its display link, and draws only from there. Drawing from each
/// frame's arrival queued a main-thread block per frame: the run loop never got back to commit the
/// layer, so every `nextDrawable()` waited out its one-second timeout and the app stopped answering.
@MainActor
final class PointerField: NSObject {
    private static let metal: (device: MTLDevice, queue: MTLCommandQueue, pipeline: MTLRenderPipelineState, blank: MTLTexture)? = {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "fieldVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "fieldFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        // Drawing with no picture of the screen still binds one; the shader reads none of it.
        let blankDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
              let blank = device.makeTexture(descriptor: blankDescriptor) else { return nil }
        return (device, queue, pipeline, blank)
    }()

    /// What the overlay hosts, under the marks so the ink stays sharp.
    let layer = CAMetalLayer()
    private let feed = ScreenFeed()
    /// How long the GPU took over each drawing since the field came up, logged with the feed's frames.
    private let gpuTimes = GPUTimes()
    private var textures: CVMetalTextureCache?
    /// The texture made from the newest frame, kept while that frame is the newest.
    private var texture: (frame: CVPixelBuffer, texture: CVMetalTexture)?
    private var link: CADisplayLink?
    private var ui = UITweaks()
    private var ink = SIMD4<Float>(1, 1, 1, 1)
    private var motion = PointerFieldMotion()

    /// The screen it covers, in AppKit's global points, which the pointer is read against; its size
    /// in pixels, which the picture is taken at; its display; and the window the picture leaves out.
    private var screenFrame = CGRect.zero
    private var pixels = CGSize.zero
    private var display: CGDirectDisplayID?
    private var excluding: CGWindowID = 0

    /// Its holder wants it up.
    private var held = false
    /// The chord went down: the picture starts now, so it is there by the time the field shows.
    private var prepared = false
    /// Held or prepared at the last update, so a new chord tries the picture again.
    private var readied = false
    /// Ticking and drawing. It fades in at its first drawing.
    private var isUp = false
    /// Its opacity is on, or on its way there.
    private var faded = false
    /// Fading out; a fade-out that ends after the field came up again changes nothing.
    private var fadeOut: Int?
    private var fades = 0
    private var hidden: [() -> Void] = []
    private var streaming = false
    /// The screen's picture could not be had since the chord went down, so nothing bends: Screen
    /// Recording is refused, or the stream stopped.
    private var pictureFailed = false
    /// The settings changed since the last drawing.
    private var dirty = false
    /// When the field came up, and when its picture was asked for, for the first frame's log line.
    private var started: CFTimeInterval = 0
    private var asked: CFTimeInterval = 0

    init(scale: CGFloat) {
        super.init()
        layer.contentsScale = scale
        layer.anchorPoint = .zero
        layer.isOpaque = false
        layer.framebufferOnly = true
        layer.pixelFormat = .bgra8Unorm
        layer.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
        layer.maximumDrawableCount = 3
        layer.opacity = 0
        if let metal = Self.metal {
            layer.device = metal.device
            CVMetalTextureCacheCreate(nil, nil, metal.device, nil, &textures)
        }
        feed.onStopped = { [weak self] error in
            Log.write("[live-ink] field feed stopped: \(error)")
            self?.lostPicture()
        }
    }

    /// Covers `screen`, whose picture leaves out the window `excluding`. Again when the screens change.
    func place(on screen: NSScreen, display: CGDirectDisplayID, excluding window: CGWindowID) {
        screenFrame = screen.frame
        pixels = CGSize(width: screen.frame.width * screen.backingScaleFactor, height: screen.frame.height * screen.backingScaleFactor)
        self.display = display
        excluding = window
        guard Self.metal != nil else { return }
        link?.invalidate()
        link = screen.displayLink(target: self, selector: #selector(tick))
        link?.add(to: .main, forMode: .common)
        link?.isPaused = !isUp
    }

    /// The settings it draws with. It starts or stops the screen's picture as they now need it.
    func apply(_ ui: UITweaks) {
        self.ui = ui
        let color = ui.markStyle.color(.person).mixed(with: .white, 0.3)
        if let c = color.converted(to: CGColorSpace(name: CGColorSpace.displayP3)!, intent: .defaultIntent, options: nil)?.components, c.count >= 3 {
            ink = SIMD4(Float(c[0]), Float(c[1]), Float(c[2]), 1)
        }
        dirty = true
        update()
    }

    /// Readies it as the chord goes down, so its picture is there by the time it shows.
    func prepare() {
        prepared = true
        update()
    }

    /// Holds it up, or lets it go: it fades out, and the picture stops once it has.
    func show(_ on: Bool) {
        held = on
        if !on { prepared = false }
        update()
    }

    /// Runs `run` once the field is hidden: at once when it is, else when its fade-out ends.
    func whenHidden(_ run: @escaping () -> Void) {
        if isUp || fadeOut != nil { hidden.append(run) } else { run() }
    }

    /// Stops for good, at once: the overlay is closing.
    func tearDown() {
        held = false
        prepared = false
        isUp = false
        fadeOut = nil
        link?.invalidate()
        link = nil
        update()
        settled()
    }

    private func update() {
        let readying = held || prepared
        // Each chord tries the picture again: a refusal or a stream error may be over by now.
        if readying, !readied { pictureFailed = false }
        readied = readying
        let wanted = held && Self.metal != nil && ui.drawsField
        if wanted, !isUp { comeUp() } else if !wanted, isUp { goDown() }
        let wantsPicture = (readying || fadeOut != nil) && Self.metal != nil && ui.capturesScreen && !pictureFailed
        if wantsPicture, !streaming { startFeed() } else if !wantsPicture, streaming { stopFeed() }
    }

    /// Up from the pointer, with the ring growing in from nothing.
    private func comeUp() {
        isUp = true
        fadeOut = nil
        started = CACurrentMediaTime()
        gpuTimes.reset()
        motion.reset(at: pointer, now: started)
        dirty = true
        link?.isPaused = false
    }

    private func goDown() {
        isUp = false
        link?.isPaused = true
        guard faded else { settled(); return }
        fades += 1
        let generation = fades
        fadeOut = generation
        fade(in: false) { [weak self] in
            guard let self, self.fadeOut == generation else { return }
            self.fadeOut = nil
            self.update()
            self.settled()
        }
    }

    /// Hidden: whoever waited for that goes on.
    private func settled() {
        let waiting = hidden
        hidden = []
        waiting.forEach { $0() }
    }

    private func startFeed() {
        guard let display else { return }
        streaming = true
        asked = CACurrentMediaTime()
        Task { @MainActor [weak self, feed, pixels, excluding] in
            do {
                try await feed.start(display: display, pixels: pixels, excluding: [excluding])
            } catch {
                Log.write("[live-ink] field feed could not start: \(error)")
                self?.lostPicture()
            }
        }
    }

    private func stopFeed() {
        streaming = false
        feed.stop()
        texture = nil
        if let textures { CVMetalTextureCacheFlush(textures, 0) }
        Log.write("[live-ink] field feed stopped frames=\(feed.frameCount) \(gpuTimes.take())")
    }

    /// Draws on without the screen's picture: the ring glows and nothing bends.
    private func lostPicture() {
        streaming = false
        texture = nil
        pictureFailed = true
        dirty = true
    }

    /// The pointer now, in the layer's points.
    private var pointer: CGPoint {
        let mouse = NSEvent.mouseLocation
        return CGPoint(x: mouse.x - screenFrame.minX, y: screenFrame.maxY - mouse.y)
    }

    @objc private func tick() {
        guard isUp else { link?.isPaused = true; return }
        let now = CACurrentMediaTime()
        let pointer = self.pointer
        // The button is global, so only the screen the pointer is on draws a wake.
        let pressed = NSEvent.pressedMouseButtons & 1 != 0 && CGRect(origin: .zero, size: screenFrame.size).contains(pointer)
        let moved = motion.step(to: now, pointer: pointer, pressed: pressed, ui: ui)
        let needsPicture = ui.capturesScreen && !pictureFailed
        let picture = needsPicture ? feed.take() : nil
        // Bending waits for the first frame of the screen.
        if needsPicture, picture == nil { return }
        // Draws only when the screen, the motion or the settings changed.
        guard dirty || moved || picture?.fresh == true else { return }
        dirty = false
        draw(picture?.frame, at: now)
        if !faded {
            // `ms` is how long the field waited for the picture once it was wanted, `stream-ms` how long
            // since the picture was asked for, as the chord went down.
            if needsPicture { Log.write("[live-ink] field first frame ms=\(Int((now - started) * 1000)) stream-ms=\(Int((now - asked) * 1000))") }
            fade(in: true)
        }
    }

    private func fade(in on: Bool, then done: (() -> Void)? = nil) {
        faded = on
        let target: Float = on ? Float(ui.liveInkFieldOpacity) : 0
        let from = layer.presentation()?.opacity ?? layer.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock(done)
        layer.opacity = target
        if ui.liveInkFieldFade > 0 {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = from
            fade.toValue = target
            fade.duration = ui.liveInkFieldFade
            layer.add(fade, forKey: "opacity")
        } else {
            layer.removeAnimation(forKey: "opacity")
        }
        CATransaction.commit()
    }

    private func draw(_ frame: CVPixelBuffer?, at now: CFTimeInterval) {
        guard let metal = Self.metal, let textures else { return }
        let size = layer.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        var screen = metal.blank
        if let frame {
            if texture?.frame !== frame {
                var made: CVMetalTexture?
                CVMetalTextureCacheCreateTextureFromImage(nil, textures, frame, nil, .bgra8Unorm,
                                                          CVPixelBufferGetWidth(frame), CVPixelBufferGetHeight(frame), 0, &made)
                texture = made.map { (frame, $0) }
            }
            guard let read = texture.flatMap({ CVMetalTextureGetTexture($0.texture) }) else { return }
            screen = read
        }
        layer.drawableSize = CGSize(width: size.width * layer.contentsScale, height: size.height * layer.contentsScale)
        guard let drawable = layer.nextDrawable(), let commands = metal.queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        var uniforms = uniforms(size: size, hasPicture: frame != nil)
        // Each point: where, its age in seconds, its weight. The shader reads none when the count is 0,
        // but Metal wants a buffer bound.
        var points = motion.trail.map { SIMD4<Float>(Float($0.point.x), Float($0.point.y), Float(now - $0.born), $0.weight) }
        if points.isEmpty { points = [SIMD4(repeating: 0)] }
        encoder.setRenderPipelineState(metal.pipeline)
        encoder.setFragmentTexture(screen, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FieldUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&points, length: MemoryLayout<SIMD4<Float>>.stride * points.count, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        // The capture's buffer must outlive the GPU's read of it.
        commands.addCompletedHandler { [gpuTimes, texture] buffer in
            withExtendedLifetime(texture) {}
            gpuTimes.add(buffer.gpuEndTime - buffer.gpuStartTime)
        }
        commands.present(drawable)
        commands.commit()
    }

    private func uniforms(size: CGSize, hasPicture: Bool) -> FieldUniforms {
        var uniforms = FieldUniforms()
        uniforms.color = ink
        uniforms.size = SIMD2(Float(size.width), Float(size.height))
        // Without a picture of the screen there is nothing to bend, only light to draw.
        let trail = motion.trail
        if hasPicture, let first = trail.first {
            uniforms.wakeCount = UInt32(trail.count)
            uniforms.wakeStrength = Float(ui.liveInkWakeStrength)
            uniforms.wakeSize = Float(ui.liveInkWakeSize)
            uniforms.wakeLife = Float(ui.liveInkWakeDuration)
            var box = (min: first.point, max: first.point)
            for point in trail.dropFirst().map(\.point) {
                box = (CGPoint(x: min(box.min.x, point.x), y: min(box.min.y, point.y)), CGPoint(x: max(box.max.x, point.x), y: max(box.max.y, point.y)))
            }
            // A ring reaches its size, and its packet of waves 24 pt past it.
            let reach = ui.liveInkWakeSize + 24
            uniforms.wakeBox = SIMD4(Float(box.min.x - reach), Float(box.min.y - reach), Float(box.max.x + reach), Float(box.max.y + reach))
        }
        if ui.ringShows {
            uniforms.ringCentre = SIMD2(Float(motion.centre.x), Float(motion.centre.y))
            uniforms.ringVelocity = SIMD2(Float(motion.velocity.dx), Float(motion.velocity.dy))
            uniforms.ringRadius = Float(motion.radius)
            uniforms.ringBend = hasPicture ? Float(ui.liveInkFieldBend) : 0
            uniforms.ringSplit = hasPicture ? Float(ui.liveInkFieldSplit) : 0
            uniforms.ringGlow = Float(ui.liveInkFieldGlow)
            uniforms.ringStretch = Float(ui.liveInkFieldStretch)
            // Brighter while the ring is smaller than its size: as it grows in, and while pressing.
            let ringSize = max(CGFloat(ui.liveInkFieldSize), 1)
            uniforms.ringPress = Float(min(max((ringSize - motion.radius) / (ringSize * 0.2), 0), 1))
        }
        return uniforms
    }
}

/// How the ring round the pointer and the wake's rings move, stepped once a refresh. Lengths are in
/// the screen's points, y down from its top-left corner.
struct PointerFieldMotion {
    struct WakePoint: Equatable {
        var point: CGPoint
        var born: CFTimeInterval
        /// Less where points crowd, so slow drawing does not stack rings.
        var weight: Float
    }

    /// From the arrow's tip, its hotspot, to about the middle of the arrow, so the ring sits round
    /// the arrow rather than round its tip.
    static let ringOffset = CGVector(dx: 4, dy: 6)
    /// The most wake points the shader takes, which fits `setFragmentBytes`' 4 KB.
    static let trailLimit = 96

    /// The ring's centre, how fast it moves in points a second, and its radius.
    private(set) var centre = CGPoint.zero
    private(set) var velocity = CGVector.zero
    private(set) var radius: CGFloat = 0
    private var radiusVelocity: CGFloat = 0
    /// The points the pen passed while drawing, oldest first, each the centre of one of the wake's rings.
    private(set) var trail: [WakePoint] = []
    private var last: CFTimeInterval = 0

    /// Starts over round `pointer` at `now`, with no ring, so the ring grows in.
    mutating func reset(at pointer: CGPoint, now: CFTimeInterval) {
        centre = Self.ring(at: pointer)
        velocity = .zero
        (radius, radiusVelocity) = (0, 0)
        trail = []
        last = now
    }

    /// Moves everything on to `now`, with the pointer at `pointer` and the button down there or not.
    /// The ring follows the pointer over `liveInkFieldFollow` and springs to its size, smaller while
    /// pressed, over `liveInkFieldFade`. The wake gains a point where the pen is, unless the last one
    /// is under 6 pt away, and loses those whose ring has spread. Answers whether anything drawn
    /// changed: also while rings spread, and once more when the last is gone, so none of it stays.
    mutating func step(to now: CFTimeInterval, pointer: CGPoint, pressed: Bool, ui: UITweaks) -> Bool {
        let dt = now - last
        last = now
        var moved = false
        if ui.ringShows {
            let before = (centre, radius)
            let target = Self.ring(at: pointer)
            let x = Tween.spring(value: centre.x, velocity: velocity.dx, target: target.x, settling: ui.liveInkFieldFollow, dt: dt)
            let y = Tween.spring(value: centre.y, velocity: velocity.dy, target: target.y, settling: ui.liveInkFieldFollow, dt: dt)
            centre = CGPoint(x: x.value, y: y.value)
            velocity = CGVector(dx: x.velocity, dy: y.velocity)
            let size = CGFloat(ui.liveInkFieldSize) * (pressed ? 0.8 : 1)
            (radius, radiusVelocity) = Tween.spring(value: radius, velocity: radiusVelocity, target: size, settling: ui.liveInkFieldFade, dt: dt)
            moved = hypot(centre.x - before.0.x, centre.y - before.0.y) > 0.01 || abs(radius - before.1) > 0.01
        }
        let rippling = !trail.isEmpty
        trail.removeAll { now - $0.born >= ui.liveInkWakeDuration }
        if pressed, ui.wakes { wake(at: pointer, now: now) }
        return moved || rippling || !trail.isEmpty
    }

    private mutating func wake(at point: CGPoint, now: CFTimeInterval) {
        let spacing = trail.last.map { hypot(point.x - $0.point.x, point.y - $0.point.y) } ?? 12
        guard spacing >= 6 else { return }
        trail.append(WakePoint(point: point, born: now, weight: Float(min(spacing / 12, 1))))
        if trail.count > Self.trailLimit { trail.removeFirst(trail.count - Self.trailLimit) }
    }

    private static func ring(at pointer: CGPoint) -> CGPoint {
        CGPoint(x: pointer.x + ringOffset.dx, y: pointer.y + ringOffset.dy)
    }
}

/// The shader's uniforms, in the order and alignment of `FieldUniforms` in PointerField.metal.
struct FieldUniforms {
    var color = SIMD4<Float>(repeating: 0)
    var wakeBox = SIMD4<Float>(repeating: 0)
    var size = SIMD2<Float>(repeating: 0)
    var ringCentre = SIMD2<Float>(repeating: 0)
    var ringVelocity = SIMD2<Float>(repeating: 0)
    var wakeCount: UInt32 = 0
    var wakeStrength: Float = 0
    var wakeSize: Float = 0
    var wakeLife: Float = 0
    var ringRadius: Float = 0
    var ringBend: Float = 0
    var ringSplit: Float = 0
    var ringGlow: Float = 0
    var ringStretch: Float = 0
    var ringPress: Float = 0
}

extension UITweaks {
    /// The wake follows the pen while drawing. Reduce Motion turns it off, since its duration is motion.
    fileprivate var wakes: Bool { liveInkWakeStrength > 0 && liveInkWakeDuration > 0 && liveInkWakeSize > 0 }
    /// The ring shows round the pointer while the chord is held.
    fileprivate var ringShows: Bool { liveInkFieldSize > 0 && (liveInkFieldBend > 0 || liveInkFieldSplit > 0 || liveInkFieldGlow > 0) }
    /// The ring bends the screen, which needs a live picture of it.
    fileprivate var ringBends: Bool { liveInkFieldSize > 0 && (liveInkFieldBend > 0 || liveInkFieldSplit > 0) }
    fileprivate var drawsField: Bool { wakes || ringShows }
    fileprivate var capturesScreen: Bool { wakes || ringBends }
}
