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
/// the chord is held, in one of several styles (docs/live-ink-pointer-variants-2026-10-10.md). A
/// Metal shader draws it over a live picture of the screen, which it bends. Without that picture,
/// because Screen Recording is refused or the stream stopped, its light still draws and nothing bends.
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
    private static let metal: (device: MTLDevice, queue: MTLCommandQueue, ring: MTLRenderPipelineState, blank: MTLTexture)? = {
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
        guard let ring = pipeline("ringFragment"), let blank = device.makeTexture(descriptor: blankDescriptor) else { return nil }
        return (device, queue, ring, blank)
    }()

    /// What the overlay hosts, under the marks so the ink stays sharp, and what fades.
    let layer = CALayer()
    /// The ring's layer, as big as the ring can reach. It presents in the transaction that places it,
    /// so the ring's picture and its place change in the same frame.
    private let ringLayer: CAMetalLayer
    private let feed = ScreenFeed()
    /// How long the GPU took over each drawing since the field came up, logged with the feed's frames.
    private let gpuTimes = GPUTimes()
    private var textures: CVMetalTextureCache?
    /// The texture made from the newest frame, kept while that frame is the newest.
    private var texture: (frame: CVPixelBuffer, texture: CVMetalTexture)?
    private var link: CADisplayLink?
    private var ui = UITweaks()
    /// The ink's two colours in the layer's colour space, the ice and the deep blue, and which of them
    /// stands out from what content (`InkContrast`).
    private var ice = SIMD3<Float>(1, 1, 1)
    private var deep = SIMD3<Float>(0, 0, 1)
    private var contrast = InkContrast(UITweaks())
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
        super.init()
        layer.anchorPoint = .zero
        layer.opacity = 0
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
        func p3(_ hex: String, _ fallback: CGColor) -> SIMD3<Float> {
            let colour = SRGB(hex: hex)?.cgColor ?? fallback
            guard let c = colour.converted(to: CGColorSpace(name: CGColorSpace.displayP3)!, intent: .defaultIntent, options: nil)?.components,
                  c.count >= 3 else { return SIMD3(1, 1, 1) }
            return SIMD3(Float(c[0]), Float(c[1]), Float(c[2]))
        }
        ice = p3(ui.inkGelLight, InkGel.defaultIce)
        deep = p3(ui.inkGelDeep, InkGel.defaultDeep)
        contrast = InkContrast(ui)
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
        let wanted = held && Self.metal != nil && ui.ringShows
        if wanted, !isUp { comeUp() } else if !wanted, isUp { goDown() }
        let wantsPicture = (readying || fadeOut != nil) && Self.metal != nil && ui.ringBends && !pictureFailed
        if wantsPicture, !streaming { startFeed() } else if !wantsPicture, streaming { stopFeed() }
    }

    /// Up from the pointer, with the ring growing in from nothing.
    private func comeUp() {
        isUp = true
        fadeOut = nil
        started = CACurrentMediaTime()
        gpuTimes.reset()
        motion.reset(at: pointer, now: started, deep: deepUnderPointer())
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

    /// Whether the deep blue stands out more than the ice from the content under the pointer, from
    /// the backdrop the ink reads; with no backdrop the field is the ice.
    private func deepUnderPointer() -> Bool {
        let mouse = NSEvent.mouseLocation
        let global = CGPoint(x: mouse.x, y: StateReport.primaryHeight - mouse.y)
        return InkBackdrop.shared.cell(at: global).map(contrast.deepWins(behind:)) ?? false
    }

    @objc private func tick() {
        guard isUp else { link?.isPaused = true; return }
        let now = CACurrentMediaTime()
        let pointer = self.pointer
        // The button is global, so only the screen the pointer is on shrinks its ring for a press.
        let pressed = NSEvent.pressedMouseButtons & 1 != 0 && CGRect(origin: .zero, size: screenFrame.size).contains(pointer)
        let moved = motion.step(to: now, pointer: pointer, pressed: pressed, deep: deepUnderPointer(), ui: ui,
                                colourSettling: 0.3 * Settings.shared.motionScale)
        let needsPicture = ui.ringBends && !pictureFailed
        let picture = needsPicture ? feed.take() : nil
        // Bending waits for the first frame of the screen.
        if needsPicture, picture == nil { return }
        // It draws only when the screen, its motion or the settings changed, or every refresh while the
        // lamp breathes or drifts.
        guard dirty || picture?.fresh == true || moved || ui.lampLives else { return }
        dirty = false
        draw(picture?.frame)
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

    /// Draws the ring, and places and presents it in one transaction.
    private func draw(_ frame: CVPixelBuffer?) {
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
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let area = ringArea(on: size)
        ringLayer.isHidden = area == nil
        guard let area, let ring = render(ringLayer, metal.ring, area: area, screen: screen,
                                          uniforms: uniforms(size: size, hasPicture: frame != nil)) else { return }
        ring.commands.commit()
        // A layer that presents with its transaction shows a drawable only once it is scheduled.
        ring.commands.waitUntilScheduled()
        ring.drawable.present()
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

    /// Draws `pipeline` into `target`, placed over `area` of the screen, and answers what to present.
    private func render(_ target: CAMetalLayer, _ pipeline: MTLRenderPipelineState, area: CGRect, screen: MTLTexture,
                        uniforms: FieldUniforms) -> (commands: MTLCommandBuffer, drawable: CAMetalDrawable)? {
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
        let colour = ice + (deep - ice) * Float(motion.deepness)
        uniforms.color = SIMD4(colour, 1)
        // The lamp's own clock, wrapped so a float keeps its precision.
        uniforms.time = Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 3600))
        uniforms.ringEnergy = Float(motion.energy)
        uniforms.lampLife = SIMD4(Float(ui.liveInkLampBreath), Float(max(ui.liveInkLampBreathSeconds, 0.1)),
                                  Float(ui.liveInkLampEnergy), Float(ui.liveInkLampDrift))
        uniforms.size = SIMD2(Float(size.width), Float(size.height))
        uniforms.hasPicture = hasPicture ? 1 : 0
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

/// How the ring round the pointer moves, stepped once a refresh. Lengths are in the screen's points,
/// y down from its top-left corner.
struct PointerFieldMotion {
    /// From the arrow's tip, its hotspot, to about the middle of the arrow, so the ring sits round
    /// the arrow rather than round its tip.
    static let ringOffset = CGVector(dx: 4, dy: 6)

    /// The ring's centre, how fast it moves in points a second, and its radius.
    private(set) var centre = CGPoint.zero
    private(set) var velocity = CGVector.zero
    private(set) var radius: CGFloat = 0
    private var radiusVelocity: CGFloat = 0
    /// How fast the pointer itself has moved lately, 0 at rest to 1 at `fastSpeed`; it rises within
    /// about 0.15 s and settles over about 0.6 s.
    private(set) var energy: CGFloat = 0
    /// Its colour, 0 the ice and 1 the deep blue, eased toward the one that stands out under the pointer.
    private(set) var deepness: CGFloat = 0
    private var deepnessVelocity: CGFloat = 0
    private var lastPointer: CGPoint?
    private var last: CFTimeInterval = 0

    /// A pointer speed, in points a second, that gives the lamp all its energy.
    static let fastSpeed: CGFloat = 1600

    /// The arrow's tip under the ring, which Lens magnifies about. Below a radius of 18 pt it moves
    /// toward the ring's centre, so it stays inside the part a lens leaves flat.
    var hotspot: CGPoint {
        let pull = min(1, 0.5 * radius / (hypot(Self.ringOffset.dx, Self.ringOffset.dy) * 1.25))
        return CGPoint(x: centre.x - Self.ringOffset.dx * pull, y: centre.y - Self.ringOffset.dy * pull)
    }

    /// Starts over round `pointer` at `now`, with no ring, so the ring grows in.
    mutating func reset(at pointer: CGPoint, now: CFTimeInterval, deep: Bool = false) {
        centre = Self.ring(at: pointer)
        velocity = .zero
        (radius, radiusVelocity) = (0, 0)
        energy = 0
        (deepness, deepnessVelocity) = (deep ? 1 : 0, 0)
        lastPointer = pointer
        last = now
    }

    /// Moves the ring on to `now`, with the pointer at `pointer`, the button down there or not, and
    /// the deep blue standing out more there or not, and answers whether anything drawn changed. It
    /// follows the pointer over `liveInkFieldFollow`, springs to its size, smaller while pressed, over
    /// `liveInkFieldFade`, and eases to its colour over `colourSettling`.
    mutating func step(to now: CFTimeInterval, pointer: CGPoint, pressed: Bool, deep: Bool = false, ui: UITweaks,
                       colourSettling: CFTimeInterval = 0.3) -> Bool {
        let dt = now - last
        last = now
        guard ui.ringShows else { return false }
        let before = (centre, radius, energy, deepness)
        let travelled = lastPointer.map { hypot(pointer.x - $0.x, pointer.y - $0.y) } ?? 0
        lastPointer = pointer
        let speed = dt > 0 ? travelled / CGFloat(dt) : 0
        let wanted = min(speed / Self.fastSpeed, 1)
        // Quick to rise, slower to settle, so a flick lights it and it dims after: time constants of
        // 0.05 s and 0.2 s, three of which reach the 0.15 s and 0.6 s above.
        let rate: CGFloat = wanted > energy ? 1 / 0.05 : 1 / 0.2
        energy += (wanted - energy) * min(CGFloat(dt) * rate, 1)
        if wanted == 0, energy < 0.002 { energy = 0 }
        (deepness, deepnessVelocity) = Tween.spring(value: deepness, velocity: deepnessVelocity, target: deep ? 1 : 0,
                                                    settling: colourSettling, dt: dt)
        let target = Self.ring(at: pointer)
        let x = Tween.spring(value: centre.x, velocity: velocity.dx, target: target.x, settling: ui.liveInkFieldFollow, dt: dt)
        let y = Tween.spring(value: centre.y, velocity: velocity.dy, target: target.y, settling: ui.liveInkFieldFollow, dt: dt)
        centre = CGPoint(x: x.value, y: y.value)
        velocity = CGVector(dx: x.velocity, dy: y.velocity)
        let size = CGFloat(ui.liveInkFieldSize) * (pressed ? 0.8 : 1)
        (radius, radiusVelocity) = Tween.spring(value: radius, velocity: radiusVelocity, target: size, settling: ui.liveInkFieldFade, dt: dt)
        return hypot(centre.x - before.0.x, centre.y - before.0.y) > 0.01 || abs(radius - before.1) > 0.01
            || abs(energy - before.2) > 0.001 || abs(deepness - before.3) > 0.001
    }

    private static func ring(at pointer: CGPoint) -> CGPoint {
        CGPoint(x: pointer.x + ringOffset.dx, y: pointer.y + ringOffset.dy)
    }
}

/// The shader's uniforms, in the order and alignment of `FieldUniforms` in PointerField.metal.
struct FieldUniforms {
    var color = SIMD4<Float>(repeating: 0)
    var ringGlass = SIMD4<Float>(repeating: 0)
    var ringShape = SIMD4<Float>(repeating: 0)
    var size = SIMD2<Float>(repeating: 0)
    var origin = SIMD2<Float>(repeating: 0)
    var area = SIMD2<Float>(repeating: 0)
    var ringCentre = SIMD2<Float>(repeating: 0)
    var ringVelocity = SIMD2<Float>(repeating: 0)
    var ringHotspot = SIMD2<Float>(repeating: 0)
    var ringStyle: UInt32 = 0
    var hasPicture: UInt32 = 0
    var ringRadius: Float = 0
    var ringBend: Float = 0
    var ringSplit: Float = 0
    var ringGlow: Float = 0
    var ringStretch: Float = 0
    var ringPress: Float = 0
    var ringReach: Float = 0
    var time: Float = 0
    var ringEnergy: Float = 0
    var lampLife = SIMD4<Float>(repeating: 0)
}

// What the field draws, decided from the settings in one place. The styles are numbers in the file,
// so they are rounded and kept in range here.
extension UITweaks {
    /// 0 Glass, 1 Lens, 2 Squircle, 3 Droplet, 4 Lamp, 5 Caustic.
    fileprivate var ringStyle: Int { min(max(Int(liveInkFieldStyle.rounded()), 0), 5) }

    /// The lamp moves on its own, so it draws every refresh.
    fileprivate var lampLives: Bool { ringStyle == 4 && ringShows && (liveInkLampBreath > 0 || liveInkLampDrift > 0) }

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
        // The lamp's pool grows with its breath and its energy, as the shader's `S` does.
        case 4: reach = (3 * CGFloat(liveInkFieldSpread) * size + 8) * (1 + 0.5 * stretch)
            * (1 + 0.5 * CGFloat(liveInkLampBreath) + 0.35 * CGFloat(liveInkLampEnergy))
        default: reach = glass
        }
        return min(reach, 600)
    }
}
