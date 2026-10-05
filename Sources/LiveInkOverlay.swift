import AppKit
import QuartzCore

/// One screen's surface for live ink on one Space: a borderless, non-activating panel over the whole
/// screen that shows the marks, and while the chord is held takes every press there to draw them. It
/// does not join other Spaces, so macOS keeps it, and its marks, on the Space it was put up on. It
/// is shared with no capture, so a screenshot shows the screen without it and ⌘⇧4's window picker
/// passes over it.
///
/// At rest it sits at `restingLevel`, just above ordinary windows and below the dim and Vignette's
/// floating windows, so the stack and the annotator cover the marks; so do menus, the Dock and other
/// apps' floating windows. It passes every press through then. Inking raises it to `.screenSaver`,
/// over all of those.
@MainActor
final class LiveInkOverlay: NSPanel {
    /// Level 1: above normal windows (0), below the dim (2) and Vignette's floating windows.
    static let restingLevel = NSWindow.Level(rawValue: 1)
    /// A test launch with `VIGNETTE_SHARE_LIVE_INK` in its environment lets captures see the marks,
    /// so a test can look at what it drew.
    static let sharedWithCaptures = Settings.isOverridden && ProcessInfo.processInfo.environment["VIGNETTE_SHARE_LIVE_INK"] != nil

    /// The screen it covers.
    let display: CGDirectDisplayID
    /// The stroke so far, in global top-left points, as it grows.
    var onStrokeMoved: (([CGPoint]) -> Void)? {
        get { canvas.onStrokeMoved }
        set { canvas.onStrokeMoved = newValue }
    }
    /// A finished stroke, in global top-left points.
    var onStroke: (([CGPoint]) -> Void)? {
        get { canvas.onStroke }
        set { canvas.onStroke = newValue }
    }

    private let canvas: Canvas

    /// Comes up at once, on the Space that is active now.
    init(screen: NSScreen, display: CGDirectDisplayID) {
        self.display = display
        canvas = Canvas(frame: CGRect(origin: .zero, size: screen.frame.size), scale: screen.backingScaleFactor)
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = Self.restingLevel
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .ignoresCycle]
        sharingType = Self.sharedWithCaptures ? .readOnly : .none
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        contentView = canvas
        fit(to: screen)
        orderFrontRegardless()
    }

    /// Covers `screen` again after the screens changed, keeping its Space and its marks.
    func fit(to screen: NSScreen) {
        setFrame(screen.frame, display: false)
        canvas.fit(origin: CGPoint(x: screen.frame.minX, y: StateReport.primaryHeight - screen.frame.maxY))
    }

    /// The screen it covers, in global top-left points, the marks' coordinates.
    var globalFrame: CGRect { CGRect(origin: canvas.origin, size: frame.size) }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// A press is down here and its stroke is not finished.
    var isTracking: Bool { canvas.isTracking }

    /// Closes the overlay once `fade` has passed, so a glow fading out finishes first. Ordering it
    /// out instead would lose its Space: ordered in again, it comes up on the active one.
    func close(after fade: TimeInterval) {
        guard fade > 0 else { close(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + fade) { [weak self] in self?.close() }
    }

    /// Whether this screen takes presses to draw. Once `ignoresMouseEvents` has been set, the window
    /// takes every press with it off, over clear pixels too. Stopping drops a stroke under way.
    func setInking(_ inking: Bool) {
        if !inking { canvas.cancelStroke() }
        level = inking ? .screenSaver : Self.restingLevel
        ignoresMouseEvents = !inking
    }

    /// Finishes the stroke under way with the points it has, as its release would.
    func endStroke() { canvas.endStroke() }

    /// `drawingOn` names the marks that draw themselves on as they appear, in the order of `marks`.
    func show(_ marks: [Mark], markStyle: MarkStyle, textStyle: TextStyle, drawingOn: Set<Mark.ID> = [], pulsing: Set<Mark.ID> = []) {
        canvas.show(marks, markStyle: markStyle, textStyle: textStyle, drawingOn: drawingOn, pulsing: pulsing)
    }

    /// The stroke being drawn on any screen, in global top-left points, so one that crosses onto
    /// this screen shows here too.
    func showPen(_ points: [CGPoint], markStyle: MarkStyle) {
        canvas.showPen(points, markStyle: markStyle)
    }

    func showGlow(_ on: Bool, ui: UITweaks, color: CGColor) {
        canvas.glow.show(on, ui: ui, color: color)
    }

    /// The canvas: the marks, the stroke being drawn, and the glow. Flipped, so its layers run from
    /// the screen's top-left corner, y down, as the marks' coordinates do.
    private final class Canvas: NSView {
        var onStroke: (([CGPoint]) -> Void)?
        var onStrokeMoved: (([CGPoint]) -> Void)?
        let glow: EdgeGlow
        /// The screen's top-left corner in global top-left points, the coordinates marks are in.
        private(set) var origin: CGPoint = .zero
        private let host = CALayer()
        /// The marks, in global points: moved by the screen's origin so each lands on this screen.
        private let marksLayer = CALayer()
        /// The stroke being drawn, above the marks, moved as they are.
        private let pen: ShapeMarkLayer
        private var shapes: [Mark.ID: ShapeMarkLayer] = [:]
        private var notes: [Mark.ID: NoteLayer] = [:]
        private var stroke: [CGPoint] = []
        private let scale: CGFloat

        var isTracking: Bool { !stroke.isEmpty }

        init(frame: CGRect, scale: CGFloat) {
            self.scale = scale
            glow = EdgeGlow(scale: scale)
            pen = ShapeMarkLayer(scale: scale)
            super.init(frame: frame)
            layer = host
            wantsLayer = true
            host.contentsScale = scale
            for layer in [marksLayer, pen.root] {
                layer.anchorPoint = .zero
                host.addSublayer(layer)
            }
            host.addSublayer(glow)
        }

        func fit(origin: CGPoint) {
            self.origin = origin
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for layer in [marksLayer, pen.root] {
                layer.setAffineTransform(CGAffineTransform(translationX: -origin.x, y: -origin.y))
            }
            glow.frame = bounds
            CATransaction.commit()
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        /// AppKit sets a layer-hosting view's root layer geometry from the view, so the view itself
        /// must be flipped for the marks to run y down.
        override var isFlipped: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        /// Not `MarkLayers`, which shows a drawing on an image; these marks are on no image.
        func show(_ marks: [Mark], markStyle: MarkStyle, textStyle: TextStyle, drawingOn: Set<Mark.ID>, pulsing: Set<Mark.ID>) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let ids = Set(marks.map(\.id))
            for (id, record) in shapes where !ids.contains(id) {
                record.root.removeFromSuperlayer()
                shapes[id] = nil
            }
            for (id, note) in notes where !ids.contains(id) {
                note.removeFromSuperlayer()
                notes[id] = nil
            }
            var delay: CFTimeInterval = 0
            let motion = Settings.shared.motionUI
            for mark in marks {
                let layer: CALayer
                if case .text = mark.geometry {
                    let note = notes[mark.id] ?? NoteLayer(scale: scale)
                    note.show(mark, textStyle: textStyle, markStyle: markStyle)
                    if notes[mark.id] == nil { marksLayer.addSublayer(note); notes[mark.id] = note }
                    if drawingOn.contains(mark.id) { note.springIn(after: delay, duration: motion.liveInkDrawOn); delay += motion.liveInkDrawOn * 0.3 }
                    layer = note
                } else {
                    let record = shapes[mark.id] ?? ShapeMarkLayer(scale: scale)
                    record.show(mark, pointScale: 1, markStyle: markStyle)
                    if shapes[mark.id] == nil { marksLayer.addSublayer(record.root); shapes[mark.id] = record }
                    if drawingOn.contains(mark.id) { record.drawOn(after: delay, duration: motion.liveInkDrawOn); delay += motion.liveInkDrawOn * 0.6 }
                    layer = record.root
                }
                pulse(layer, pulsing.contains(mark.id))
            }
            CATransaction.commit()
        }

        /// Ink waiting for its answer is lighter, and breathes, so it reads as sent.
        private func pulse(_ layer: CALayer, _ on: Bool) {
            let key = "waiting"
            layer.opacity = on ? 0.7 : 1
            guard on else { layer.removeAnimation(forKey: key); return }
            guard layer.animation(forKey: key) == nil, Settings.shared.motionScale > 0 else { return }
            let breathe = CABasicAnimation(keyPath: "opacity")
            breathe.fromValue = 1
            breathe.toValue = 0.45
            breathe.duration = 0.7
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(breathe, forKey: key)
        }

        func showPen(_ points: [CGPoint], markStyle: MarkStyle) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            let smoothed = FreehandStroke.smoothed(points, spacing: EditorCore.strokeSpacing)
            pen.root.isHidden = smoothed.count < 2
            guard smoothed.count > 1 else { return }
            let path = CGMutablePath()
            path.addLines(between: smoothed)
            pen.show(MarkShape(stroked: path, filled: nil, lineWidth: markStyle.strokeWidth), color: .person, pointScale: 1, markStyle: markStyle)
        }

        override func mouseDown(with event: NSEvent) {
            stroke = [location(of: event)]
            onStrokeMoved?(stroke)
        }

        override func mouseDragged(with event: NSEvent) {
            guard isTracking else { return }
            stroke.append(location(of: event))
            onStrokeMoved?(stroke)
        }

        override func mouseUp(with event: NSEvent) {
            guard isTracking else { return }
            stroke.append(location(of: event))
            endStroke()
        }

        func endStroke() {
            guard isTracking else { return }
            let finished = stroke
            cancelStroke()
            onStroke?(finished)
        }

        func cancelStroke() {
            guard isTracking else { return }
            stroke = []
            onStrokeMoved?([])
        }

        /// In global top-left points.
        private func location(of event: NSEvent) -> CGPoint {
            let local = convert(event.locationInWindow, from: nil)
            return CGPoint(x: local.x + origin.x, y: local.y + origin.y)
        }
    }
}

/// A note on the live screen: its tag, badge and words drawn by the renderer into one bitmap at the
/// screen's scale, as `Mark.draw` draws a note on a screenshot. A few short notes, so on the main thread.
@MainActor
final class NoteLayer: CALayer {
    private var shown: (mark: Mark, textStyle: TextStyle, markStyle: MarkStyle)?

    init(scale: CGFloat) {
        super.init()
        contentsScale = scale
    }

    override init(layer: Any) { super.init(layer: layer) }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ mark: Mark, textStyle: TextStyle, markStyle: MarkStyle) {
        guard case .text(let text) = mark.geometry else { return }
        if let shown, shown.mark == mark, shown.textStyle == textStyle, shown.markStyle == markStyle { return }
        shown = (mark, textStyle, markStyle)
        // The notes wrap at their own width, so no image edge bounds them.
        let layout = TextLayout(text, imageWidth: .greatestFiniteMagnitude, pointScale: 1, style: textStyle.forMark(mark))
        let region = MarkLayers.aligned(MarkLayers.padded(text, box: layout.box, pointScale: 1, markStyle: markStyle), scale: contentsScale)
        let width = Int((region.width * contentsScale).rounded()), height = Int((region.height * contentsScale).rounded())
        guard width > 0, height > 0, let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                             bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: contentsScale, y: -contentsScale)
        context.translateBy(x: -region.minX, y: -region.minY)
        mark.draw(in: context, pointScale: 1, imageWidth: .greatestFiniteMagnitude, style: textStyle, markStyle: markStyle)
        frame = region
        contents = context.makeImage()
    }

    /// Springs in from its centre after `delay`.
    func springIn(after delay: CFTimeInterval, duration: CFTimeInterval) {
        guard duration > 0 else { return }
        let begin = CACurrentMediaTime() + delay
        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.6
        pop.toValue = 1
        pop.damping = 14
        pop.stiffness = 240
        pop.beginTime = begin
        pop.duration = pop.settlingDuration
        pop.fillMode = .backwards
        let appear = CABasicAnimation(keyPath: "opacity")
        appear.fromValue = 0
        appear.toValue = opacity
        appear.beginTime = begin
        appear.duration = duration * 0.3
        appear.fillMode = .backwards
        add(pop, forKey: "pop")
        add(appear, forKey: "appear")
    }
}

/// A soft band of colour along the screen's edges, which says the screen is taking ink.
@MainActor
final class EdgeGlow: CALayer {
    private let band = CAShapeLayer()

    /// Sublayers of a layer-hosting view do not take the screen's scale from it.
    init(scale: CGFloat) {
        super.init()
        contentsScale = scale
        band.contentsScale = scale
        band.fillColor = nil
        band.shadowOffset = .zero
        addSublayer(band)
        opacity = 0
    }

    override init(layer: Any) { super.init(layer: layer) }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ on: Bool, ui: UITweaks, color: CGColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let width = ui.liveInkGlowWidth
        band.path = CGPath(rect: bounds, transform: nil)
        // Without a shadow path, Core Animation finds the shadow's shape from the band's pixels, offscreen.
        band.shadowPath = band.path?.copy(strokingWithWidth: width, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
        band.lineWidth = width
        band.strokeColor = color
        band.shadowColor = color
        band.shadowRadius = width
        band.shadowOpacity = 1
        let target: Float = on ? Float(ui.liveInkGlowOpacity) : 0
        let from = presentation()?.opacity ?? opacity
        opacity = target
        CATransaction.commit()
        // Core Animation runs an animation of no duration for its default 0.25 s, so with motion off
        // there is none.
        guard ui.liveInkGlowFade > 0 else { removeAnimation(forKey: "opacity"); return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.toValue = target
        fade.duration = ui.liveInkGlowFade
        add(fade, forKey: "opacity")
    }
}
