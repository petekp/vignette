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
/// the chord is held, and the wake that follows the pen while it draws, each in one of several
/// styles (docs/live-ink-pointer-variants-2026-10-10.md). A Metal shader draws both over a live
/// picture of the screen, which they bend. Without that picture, because Screen Recording is refused
/// or the stream stopped, their light still draws and nothing bends.
///
/// It is hidden until its holder shows it, and fades in once its first frame is drawn, so it never
/// shows the screen as it was before the chord went down. It reads the pointer and the button
/// itself, once a refresh, from its display link, and draws only from there. The ring has a layer
/// only as big as it, moved with it, so a frame draws and composites a few hundred points square
/// rather than the screen. Drawing from each
/// frame's arrival queued a main-thread block per frame: the run loop never got back to commit the
/// layer, so every `nextDrawable()` waited out its one-second timeout and the app stopped answering.
@MainActor
final class PointerField: NSObject {
    private static let metal: (device: MTLDevice, queue: MTLCommandQueue, ring: MTLRenderPipelineState, wake: MTLRenderPipelineState, blank: MTLTexture)? = {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { return nil }
        func pipeline(_ fragment: String) -> MTLRenderPipelineState? {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "fieldVertex")
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            return try? device.makeRenderPipelineState(descriptor: descriptor)
        }
        // Drawing with no picture of the screen still binds one; the shader reads none of it.
        let blankDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        guard let ring = pipeline("ringFragment"), let wake = pipeline("wakeFragment"),
              let blank = device.makeTexture(descriptor: blankDescriptor) else { return nil }
        return (device, queue, ring, wake, blank)
    }()

    /// What the overlay hosts, under the marks so the ink stays sharp, and what fades.
    let layer = CALayer()
    /// The ring's layer, as big as the ring can reach, over the wake's, which covers the screen and is
    /// hidden while no ring of it spreads. Each presents in the transaction that places it, so the
    /// ring's picture and its place change in the same frame.
    private let ringLayer: CAMetalLayer
    private let wakeLayer: CAMetalLayer
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
        ringLayer = Self.metalLayer(scale: scale)
        wakeLayer = Self.metalLayer(scale: scale)
        super.init()
        layer.anchorPoint = .zero
        layer.opacity = 0
        layer.addSublayer(wakeLayer)
        layer.addSublayer(ringLayer)
        if let metal = Self.metal {
            CVMetalTextureCacheCreate(nil, nil, metal.device, nil, &textures)
        }
        feed.onStopped = { [weak self] error in
            Log.write("[live-ink] field feed stopped: \(error)")
            self?.lostPicture()
        }
    }

    private static func metalLayer(scale: CGFloat) -> CAMetalLayer {
        let layer = CAMetalLayer()
        layer.contentsScale = scale
        layer.anchorPoint = .zero
        layer.isOpaque = false
        layer.isHidden = true
        layer.framebufferOnly = true
        layer.pixelFormat = .bgra8Unorm
        layer.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
        layer.maximumDrawableCount = 3
        layer.presentsWithTransaction = true
        layer.device = metal?.device
        return layer
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
        // The last time's rings are gone; the ring draws again before it shows.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wakeLayer.isHidden = true
        CATransaction.commit()
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
        // Each part draws only when the screen, its motion or the settings changed.
        let all = dirty || picture?.fresh == true
        guard all || moved.ring || moved.wake else { return }
        dirty = false
        draw(picture?.frame, ring: all || moved.ring, wake: all || moved.wake, at: now)
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

    /// Draws the ring, the wake or both, and places and presents them in one transaction.
    private func draw(_ frame: CVPixelBuffer?, ring: Bool, wake: Bool, at now: CFTimeInterval) {
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
        let uniforms = uniforms(size: size, hasPicture: frame != nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        var drawn: [(commands: MTLCommandBuffer, drawable: CAMetalDrawable)] = []
        if ring {
            let area = ringArea(on: size)
            ringLayer.isHidden = area == nil
            if let area, let ring = render(ringLayer, metal.ring, area: area, screen: screen, uniforms: uniforms) { drawn.append(ring) }
        }
        if wake {
            // Without a picture of the screen, only a wake with light of its own draws.
            let showing = !motion.trail.isEmpty && (frame != nil || ui.wakeLights)
            wakeLayer.isHidden = !showing
            if showing {
                let buffers = wakeBuffers(at: now)
                if let wake = render(wakeLayer, metal.wake, area: CGRect(origin: .zero, size: size), screen: screen,
                                     uniforms: uniforms, buffers: [buffers.first, buffers.second]) { drawn.append(wake) }
            }
        }
        drawn.forEach { $0.commands.commit() }
        // A layer that presents with its transaction shows a drawable only once it is scheduled.
        drawn.forEach { $0.commands.waitUntilScheduled(); $0.drawable.present() }
    }

    /// The part of the screen the ring can reach, stretched as far as it goes, on the screen's pixels
    /// so its picture is not resampled; nil when none of it is on this screen or it is off.
    private func ringArea(on size: CGSize) -> CGRect? {
        guard ui.ringShows else { return nil }
        let scale = ringLayer.contentsScale
        let reach = ui.ringReach
        let square = CGRect(x: motion.centre.x - reach, y: motion.centre.y - reach, width: reach * 2, height: reach * 2)
            .intersection(CGRect(origin: .zero, size: size))
        guard !square.isNull, square.width > 0, square.height > 0 else { return nil }
        let left = floor(square.minX * scale) / scale, top = floor(square.minY * scale) / scale
        return CGRect(x: left, y: top, width: ceil(square.maxX * scale) / scale - left, height: ceil(square.maxY * scale) / scale - top)
    }

    /// The wake's two buffers, one entry per point of the trail. For Ripples, the first holds each
    /// point's place, its age in seconds and its weight. For the other styles it holds each point's
    /// place, 1 over its radius and its height, and the second holds the pen's direction there,
    /// scaled by its speed, and the point's age as a fraction of its life.
    private func wakeBuffers(at now: CFTimeInterval) -> (first: [SIMD4<Float>], second: [SIMD4<Float>]) {
        let trail = motion.trail
        let second = [SIMD4<Float>](repeating: .zero, count: trail.count)
        if ui.wakeStyle == 4 {
            // Less where points crowd, so slow drawing does not stack rings.
            return (trail.map { SIMD4(Float($0.point.x), Float($0.point.y), Float(now - $0.born), Float(min($0.length / 12, 1))) }, second)
        }
        let life = max(ui.liveInkWakeDuration, 0.01)
        let size = CGFloat(ui.liveInkWakeSize), widen = CGFloat(ui.liveInkWakeWiden)
        let rise = ui.wakeRise, hold = max(ui.liveInkWakeHold, rise)
        return (trail.map { point in
            let age = min(max((now - point.born) / life, 0), 1)
            // It widens as the square root of its age and flattens as it widens, as a drop of honey spreads.
            let radius = max(size * ((1 - widen) + widen * CGFloat(age.squareRoot())), 1)
            let envelope = Self.smootherstep(0, rise, age) * (1 - Self.smootherstep(hold, 1, age))
            // One bump's integral along a line through it is 0.914 R (32/35), so along a stroke the
            // field is the envelope whatever the spacing of its points.
            let height = envelope * Double(point.length / (0.914 * radius))
            return SIMD4(Float(point.point.x), Float(point.point.y), Float(1 / radius), Float(height))
        }, trail.map { point in
            let speed = hypot(point.velocity.dx, point.velocity.dy)
            let gain = 0.3 + 0.7 * Self.smootherstep(0, 500, Double(speed))
            let direction = speed > 0 ? CGVector(dx: point.velocity.dx / speed, dy: point.velocity.dy / speed) : .zero
            let age = min(max((now - point.born) / life, 0), 1)
            return SIMD4(Float(direction.dx * gain), Float(direction.dy * gain), Float(age), 0)
        })
    }

    private static func smootherstep(_ from: Double, _ to: Double, _ x: Double) -> Double {
        guard to > from else { return x >= to ? 1 : 0 }
        let t = min(max((x - from) / (to - from), 0), 1)
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    /// Draws `pipeline` into `target`, placed over `area` of the screen, and answers what to present.
    /// `buffers` go to the fragment shader from index 1.
    private func render(_ target: CAMetalLayer, _ pipeline: MTLRenderPipelineState, area: CGRect, screen: MTLTexture,
                        uniforms: FieldUniforms, buffers: [[SIMD4<Float>]] = []) -> (commands: MTLCommandBuffer, drawable: CAMetalDrawable)? {
        guard let queue = Self.metal?.queue else { return nil }
        target.frame = area
        target.drawableSize = CGSize(width: area.width * target.contentsScale, height: area.height * target.contentsScale)
        guard let drawable = target.nextDrawable(), let commands = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        var uniforms = uniforms
        uniforms.origin = SIMD2(Float(area.minX), Float(area.minY))
        uniforms.area = SIMD2(Float(area.width), Float(area.height))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(screen, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FieldUniforms>.stride, index: 0)
        for (index, buffer) in buffers.enumerated() where !buffer.isEmpty {
            var buffer = buffer
            encoder.setFragmentBytes(&buffer, length: MemoryLayout<SIMD4<Float>>.stride * buffer.count, index: index + 1)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        // The capture's buffer must outlive the GPU's read of it.
        commands.addCompletedHandler { [gpuTimes, texture] buffer in
            withExtendedLifetime(texture) {}
            gpuTimes.add(buffer.gpuEndTime - buffer.gpuStartTime)
        }
        return (commands, drawable)
    }

    private func uniforms(size: CGSize, hasPicture: Bool) -> FieldUniforms {
        var uniforms = FieldUniforms()
        uniforms.color = ink
        uniforms.size = SIMD2(Float(size.width), Float(size.height))
        uniforms.hasPicture = hasPicture ? 1 : 0
        let trail = motion.trail
        if let first = trail.first {
            uniforms.wakeCount = UInt32(trail.count)
            uniforms.wakeStyle = UInt32(ui.wakeStyle)
            uniforms.wakeStrength = Float(ui.liveInkWakeStrength)
            uniforms.wakeSize = Float(ui.liveInkWakeSize)
            uniforms.wakeLife = Float(ui.liveInkWakeDuration)
            // Without a picture of the screen there is nothing to move, only light to draw.
            uniforms.wakeLift = hasPicture ? Float(ui.wakeLift) : 0
            uniforms.wakeBlur = hasPicture ? Float(ui.liveInkWakeBlur * ui.liveInkWakeStrength) : 0
            uniforms.wakeLook = SIMD4(Float(ui.liveInkWakeSwell), Float(ui.liveInkWakeSplit),
                                      Float(ui.liveInkWakeLight * ui.liveInkWakeStrength), Float(ui.liveInkWakeMist))
            uniforms.wakeMaskRadius = ui.ringShows ? Float(1.3 * motion.radius) : 0
            var box = (min: first.point, max: first.point)
            for point in trail.dropFirst().map(\.point) {
                box = (CGPoint(x: min(box.min.x, point.x), y: min(box.min.y, point.y)), CGPoint(x: max(box.max.x, point.x), y: max(box.max.y, point.y)))
            }
            // A point reaches its size; a ripple's packet of waves reaches 24 pt past it.
            let reach = ui.liveInkWakeSize + (ui.wakeStyle == 4 ? 24 : 0)
            uniforms.wakeBox = SIMD4(Float(box.min.x - reach), Float(box.min.y - reach), Float(box.max.x + reach), Float(box.max.y + reach))
        }
        if ui.ringShows {
            uniforms.ringStyle = UInt32(ui.ringStyle)
            uniforms.ringCentre = SIMD2(Float(motion.centre.x), Float(motion.centre.y))
            uniforms.ringVelocity = SIMD2(Float(motion.velocity.dx), Float(motion.velocity.dy))
            uniforms.ringHotspot = SIMD2(Float(motion.hotspot.x), Float(motion.hotspot.y))
            uniforms.ringRadius = Float(motion.radius)
            uniforms.ringReach = Float(ui.ringReach)
            uniforms.ringBend = hasPicture ? Float(ui.liveInkFieldBend) : 0
            uniforms.ringSplit = hasPicture ? Float(ui.liveInkFieldSplit) : 0
            uniforms.ringGlow = Float(ui.liveInkFieldGlow)
            uniforms.ringStretch = Float(ui.liveInkFieldStretch)
            uniforms.ringGlass = SIMD4(Float(ui.liveInkFieldZoom), Float(ui.liveInkFieldClear),
                                       Float(ui.liveInkFieldShine), Float(ui.liveInkFieldShade))
            uniforms.ringShape = SIMD4(Float(ui.liveInkFieldSquareness), Float(ui.liveInkFieldBreak),
                                       Float(ui.liveInkFieldSpread), Float(ui.liveInkFieldDepth))
            // Brighter while the ring is smaller than its size: as it grows in, and while pressing.
            let ringSize = max(CGFloat(ui.liveInkFieldSize), 1)
            uniforms.ringPress = Float(min(max((ringSize - motion.radius) / (ringSize * 0.2), 0), 1))
        }
        return uniforms
    }
}

/// How the ring round the pointer and the wake move, stepped once a refresh. Lengths are in the
/// screen's points, y down from its top-left corner.
struct PointerFieldMotion {
    /// A point the pen passed while drawing.
    struct WakePoint: Equatable {
        var point: CGPoint
        var born: CFTimeInterval
        /// The length of the pen's path the point stands for, so a stroke is as strong however far
        /// apart its points are.
        var length: CGFloat
        /// How fast the pen moved there, in points a second; zero at a stroke's first point.
        var velocity: CGVector
        /// The stroke it is on. Only points on one stroke merge.
        var stroke: Int
    }

    /// From the arrow's tip, its hotspot, to about the middle of the arrow, so the ring sits round
    /// the arrow rather than round its tip.
    static let ringOffset = CGVector(dx: 4, dy: 6)
    /// The most wake points the shader takes, which fits `setFragmentBytes`' 4 KB.
    static let trailLimit = 96
    /// How many of the oldest points merge in pairs when the trail is full.
    static let mergedAtOnce = 32
    /// The most points a long step between two refreshes is filled in with.
    static let fillLimit = 6

    /// The ring's centre, how fast it moves in points a second, and its radius.
    private(set) var centre = CGPoint.zero
    private(set) var velocity = CGVector.zero
    private(set) var radius: CGFloat = 0
    private var radiusVelocity: CGFloat = 0
    /// The points the pen passed while drawing, oldest first.
    private(set) var trail: [WakePoint] = []
    /// The newest point of the stroke being drawn, nil while the button is up.
    private var strokeLast: (point: CGPoint, born: CFTimeInterval)?
    private var stroke = 0
    private var last: CFTimeInterval = 0

    /// The arrow's tip under the ring, which Lens magnifies about. Below a radius of 18 pt it moves
    /// toward the ring's centre, so it stays inside the part a lens leaves flat.
    var hotspot: CGPoint {
        let pull = min(1, 0.5 * radius / (hypot(Self.ringOffset.dx, Self.ringOffset.dy) * 1.25))
        return CGPoint(x: centre.x - Self.ringOffset.dx * pull, y: centre.y - Self.ringOffset.dy * pull)
    }

    /// Starts over round `pointer` at `now`, with no ring, so the ring grows in.
    mutating func reset(at pointer: CGPoint, now: CFTimeInterval) {
        centre = Self.ring(at: pointer)
        velocity = .zero
        (radius, radiusVelocity) = (0, 0)
        trail = []
        strokeLast = nil
        last = now
    }

    /// What a step changed that is drawn. The wake changes while any of it lasts, and once more when
    /// the last of it is gone, so none of it stays.
    struct Changes: Equatable {
        var ring = false
        var wake = false
    }

    /// Moves everything on to `now`, with the pointer at `pointer` and the button down there or not.
    /// The ring follows the pointer over `liveInkFieldFollow` and springs to its size, smaller while
    /// pressed, over `liveInkFieldFade`. The wake gains points along the pen's path, one every
    /// `wakeSpacing`, and loses those older than its duration.
    mutating func step(to now: CFTimeInterval, pointer: CGPoint, pressed: Bool, ui: UITweaks) -> Changes {
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
        let lasting = !trail.isEmpty
        trail.removeAll { now - $0.born >= ui.liveInkWakeDuration }
        if pressed, ui.wakeShows { wake(at: pointer, now: now, spacing: ui.wakeSpacing) } else { strokeLast = nil }
        return Changes(ring: moved, wake: lasting || !trail.isEmpty)
    }

    private mutating func wake(at point: CGPoint, now: CFTimeInterval, spacing: CGFloat) {
        guard let from = strokeLast else {
            // The field at a stroke's end has the stroke on one side only, so its first point stands for twice as much.
            stroke += 1
            add(WakePoint(point: point, born: now, length: 2 * spacing, velocity: .zero, stroke: stroke))
            strokeLast = (point, now)
            return
        }
        let distance = hypot(point.x - from.point.x, point.y - from.point.y)
        guard distance >= spacing else { return }
        let elapsed = max(now - from.born, 0.001)
        let velocity = CGVector(dx: (point.x - from.point.x) / elapsed, dy: (point.y - from.point.y) / elapsed)
        // A long step is filled in, so a flick leaves one smooth stroke rather than beads.
        let count = min(Int((distance / spacing).rounded(.up)), Self.fillLimit)
        let length = min(distance / CGFloat(count), max(40, 2 * spacing))
        for i in 1...count {
            let f = CGFloat(i) / CGFloat(count)
            add(WakePoint(point: CGPoint(x: from.point.x + (point.x - from.point.x) * f, y: from.point.y + (point.y - from.point.y) * f),
                          born: from.born + elapsed * Double(f), length: length, velocity: velocity, stroke: stroke))
        }
        strokeLast = (point, now)
    }

    /// Adds a point. A full trail merges its oldest points in pairs rather than dropping them, since a
    /// point dropped while its part of the field still shows would make that part jump. The oldest
    /// are the widest and faintest, so a merge does not show.
    private mutating func add(_ point: WakePoint) {
        trail.append(point)
        guard trail.count > Self.trailLimit else { return }
        let oldest = min(Self.mergedAtOnce, trail.count)
        var merged: [WakePoint] = []
        var i = 0
        while i < oldest {
            if i + 1 < oldest, trail[i].stroke == trail[i + 1].stroke {
                merged.append(Self.merge(trail[i], trail[i + 1]))
                i += 2
            } else {
                merged.append(trail[i])
                i += 1
            }
        }
        trail = merged + trail[oldest...]
        // Points that are each a stroke of their own cannot merge, so the oldest of them go.
        if trail.count > Self.trailLimit { trail.removeFirst(trail.count - Self.trailLimit) }
    }

    private static func merge(_ a: WakePoint, _ b: WakePoint) -> WakePoint {
        let length = a.length + b.length
        let wa = a.length / max(length, 0.001), wb = 1 - wa
        return WakePoint(point: CGPoint(x: (a.point.x + b.point.x) / 2, y: (a.point.y + b.point.y) / 2),
                         born: (a.born + b.born) / 2, length: length,
                         velocity: CGVector(dx: a.velocity.dx * wa + b.velocity.dx * wb, dy: a.velocity.dy * wa + b.velocity.dy * wb),
                         stroke: a.stroke)
    }

    private static func ring(at pointer: CGPoint) -> CGPoint {
        CGPoint(x: pointer.x + ringOffset.dx, y: pointer.y + ringOffset.dy)
    }
}

/// The shader's uniforms, in the order and alignment of `FieldUniforms` in PointerField.metal.
struct FieldUniforms {
    var color = SIMD4<Float>(repeating: 0)
    var wakeBox = SIMD4<Float>(repeating: 0)
    var ringGlass = SIMD4<Float>(repeating: 0)
    var ringShape = SIMD4<Float>(repeating: 0)
    var wakeLook = SIMD4<Float>(repeating: 0)
    var size = SIMD2<Float>(repeating: 0)
    var origin = SIMD2<Float>(repeating: 0)
    var area = SIMD2<Float>(repeating: 0)
    var ringCentre = SIMD2<Float>(repeating: 0)
    var ringVelocity = SIMD2<Float>(repeating: 0)
    var ringHotspot = SIMD2<Float>(repeating: 0)
    var wakeCount: UInt32 = 0
    var ringStyle: UInt32 = 0
    var wakeStyle: UInt32 = 0
    var hasPicture: UInt32 = 0
    var wakeStrength: Float = 0
    var wakeSize: Float = 0
    var wakeLife: Float = 0
    var wakeLift: Float = 0
    var wakeMaskRadius: Float = 0
    var wakeBlur: Float = 0
    var ringRadius: Float = 0
    var ringBend: Float = 0
    var ringSplit: Float = 0
    var ringGlow: Float = 0
    var ringStretch: Float = 0
    var ringPress: Float = 0
    var ringReach: Float = 0
}

// What the field draws, decided from the settings in one place. The styles are numbers in the file,
// so they are rounded and kept in range here.
extension UITweaks {
    /// 0 Glass, 1 Lens, 2 Squircle, 3 Droplet, 4 Lamp, 5 Caustic.
    fileprivate var ringStyle: Int { min(max(Int(liveInkFieldStyle.rounded()), 0), 5) }
    /// 0 Ribbon, 1 Silk, 2 Mist, 3 Frost, 4 Ripples.
    fileprivate var wakeStyle: Int { min(max(Int(liveInkWakeStyle.rounded()), 0), 4) }

    /// The wake follows the pen while drawing. Reduce Motion turns it off, since its duration is motion.
    fileprivate var wakes: Bool { liveInkWakeStrength > 0 && liveInkWakeDuration > 0 && liveInkWakeSize > 0 }
    /// The wake moves the screen, which needs a live picture of it.
    fileprivate var wakeBends: Bool {
        guard wakes else { return false }
        switch wakeStyle {
        case 0: return liveInkWakeLift > 0 && (liveInkWakeSwell != 0 || liveInkWakeSplit > 0)
        case 1: return liveInkWakeLift > 0
        case 2: return liveInkWakeLift > 0 && liveInkWakeSwell != 0
        case 3: return liveInkWakeBlur > 0 || (liveInkWakeLift > 0 && liveInkWakeSwell != 0)
        default: return true
        }
    }
    /// The wake has light of its own, which draws without a picture of the screen.
    fileprivate var wakeLights: Bool { wakes && [0, 2, 3].contains(wakeStyle) && liveInkWakeLight > 0 }
    fileprivate var wakeShows: Bool { wakeBends || wakeLights }
    /// How far apart the wake's points are. Ripples keep one ring every 6 pt; the other styles need a
    /// point every 0.4 of the narrowest radius for a smooth stroke.
    fileprivate var wakeSpacing: CGFloat {
        wakeStyle == 4 ? 6 : max(2, 0.4 * CGFloat(liveInkWakeSize * (1 - liveInkWakeWiden)))
    }
    /// How long a point of the wake takes to come in, a fraction of its duration. Silk comes in later,
    /// since it moves the screen under the pen's own ink.
    fileprivate var wakeRise: Double { wakeStyle == 1 ? max(liveInkWakeRise, 0.25) : liveInkWakeRise }
    /// The most the wake moves the screen, in points: no more than a quarter of its narrowest radius,
    /// and 4 pt for Silk.
    fileprivate var wakeLift: Double {
        let narrowest = liveInkWakeSize * (1 - liveInkWakeWiden)
        return min(liveInkWakeLift, 0.25 * narrowest, wakeStyle == 1 ? 4 : .infinity) * liveInkWakeStrength
    }

    /// The ring bends the screen, which needs a live picture of it.
    fileprivate var ringBends: Bool {
        guard liveInkFieldSize > 0 else { return false }
        switch ringStyle {
        case 1: return liveInkFieldBend > 0 || liveInkFieldSplit > 0 || liveInkFieldZoom > 1
        case 4: return false
        case 5: return liveInkFieldBend > 0
        default: return liveInkFieldBend > 0 || liveInkFieldSplit > 0
        }
    }
    /// The ring shows round the pointer while the chord is held.
    fileprivate var ringShows: Bool {
        liveInkFieldSize > 0 && (ringBends || liveInkFieldGlow > 0
            || ([1, 5].contains(ringStyle) && (liveInkFieldShine > 0 || liveInkFieldShade > 0)))
    }
    /// How far from its centre the ring draws anything, at its most stretched. The ring's layer is
    /// this far each way, so it is capped at 600 pt.
    fileprivate var ringReach: CGFloat {
        let size = CGFloat(liveInkFieldSize), stretch = CGFloat(liveInkFieldStretch)
        let glass = (size * 1.8 + 24) * (1 + 1.5 * stretch)
        let reach: CGFloat
        switch ringStyle {
        case 3: reach = max(glass, size * (2.5 + 2.4 * stretch) + 8)
        case 4: reach = (3 * CGFloat(liveInkFieldSpread) * size + 8) * (1 + 0.5 * stretch)
        default: reach = glass
        }
        return min(reach, 600)
    }
    fileprivate var drawsField: Bool { wakeShows || ringShows }
    fileprivate var capturesScreen: Bool { wakeBends || ringBends }
}
