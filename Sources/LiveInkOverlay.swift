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
    /// The pointer moved while inking with no press down, in global top-left points.
    var onHover: ((CGPoint) -> Void)? {
        get { canvas.onHover }
        set { canvas.onHover = newValue }
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
    func show(_ marks: [Mark], markStyle: MarkStyle, textStyle: TextStyle, drawingOn: Set<Mark.ID> = [], pulsing: Set<Mark.ID> = [],
              finishing: [Mark.ID: LiveMarksLayer.Finish] = [:]) {
        canvas.show(marks, markStyle: markStyle, textStyle: textStyle, drawingOn: drawingOn, pulsing: pulsing, finishing: finishing)
    }

    /// The stroke being drawn on any screen, in global top-left points, so one that crosses onto
    /// this screen shows here too.
    func showPen(_ points: [CGPoint], markStyle: MarkStyle) {
        canvas.showPen(points, markStyle: markStyle)
    }

    func showGlow(_ on: Bool, ui: UITweaks, color: CGColor) {
        canvas.glow.show(on, ui: ui, color: color)
    }

    func preview(_ preview: LiveMarksLayer.Preview?) { canvas.marksLayer.preview(preview) }

    /// The canvas: the marks, the stroke being drawn, and the glow. Flipped, so its layers run from
    /// the screen's top-left corner, y down, as the marks' coordinates do.
    private final class Canvas: NSView {
        var onStroke: (([CGPoint]) -> Void)?
        var onStrokeMoved: (([CGPoint]) -> Void)?
        var onHover: ((CGPoint) -> Void)?
        let glow: EdgeGlow
        /// The screen's top-left corner in global top-left points, the coordinates marks are in.
        private(set) var origin: CGPoint = .zero
        private let host = CALayer()
        /// The marks, in global points: moved by the screen's origin so each lands on this screen.
        let marksLayer: LiveMarksLayer
        /// The stroke being drawn, above the marks, moved as they are.
        private let pen: ShapeMarkLayer
        private var stroke: [CGPoint] = []
        private let scale: CGFloat

        var isTracking: Bool { !stroke.isEmpty }

        init(frame: CGRect, scale: CGFloat) {
            self.scale = scale
            glow = EdgeGlow(scale: scale)
            pen = ShapeMarkLayer(scale: scale)
            marksLayer = LiveMarksLayer(scale: scale)
            super.init(frame: frame)
            layer = host
            wantsLayer = true
            host.contentsScale = scale
            for layer in [marksLayer, pen.root] {
                layer.anchorPoint = .zero
                host.addSublayer(layer)
            }
            host.addSublayer(glow)
            // The panel never becomes key, so only an always-active area hears the pointer move.
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
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

        func show(_ marks: [Mark], markStyle: MarkStyle, textStyle: TextStyle, drawingOn: Set<Mark.ID>, pulsing: Set<Mark.ID>,
                  finishing: [Mark.ID: LiveMarksLayer.Finish]) {
            marksLayer.show(marks, markStyle: markStyle, textStyle: textStyle, drawingOn: drawingOn, pulsing: pulsing, finishing: finishing)
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

        override func mouseMoved(with event: NSEvent) {
            guard !isTracking else { return }
            onHover?(location(of: event))
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

/// The marks of one live ink surface, a screen's or a window's. Not `MarkLayers`, which shows a
/// drawing on an image; these marks are on no image. Each mark sits in a holder of its own, which
/// moves it with its content and fades it while the content moves (`LiveWindows`).
@MainActor
final class LiveMarksLayer: CALayer {
    @MainActor
    private struct Drawn {
        /// Moved, faded and clipped with the content (`LiveWindows`).
        let holder = CALayer()
        /// Inside the holder: dimmed for a tap's preview.
        let previewed = CALayer()
        var shape: ShapeMarkLayer?
        var note: NoteLayer?
        var mark: Mark?
        /// The done animation has started on it; the mark is removed once it ends.
        var finished = false
        var layer: CALayer { shape?.root ?? note ?? holder }
    }

    /// What a tap where the pointer is would do, shown while the chord is held: a mark it would erase
    /// fades back, and an answer's loop or arrow it would pick takes the person's colour.
    enum Preview: Equatable {
        case erase(Mark.ID)
        case pick(Mark.ID)

        var id: Mark.ID {
            switch self {
            case .erase(let id), .pick(let id): id
            }
        }
    }

    /// How marks leave: done, when the session's turn ended, which turns them green with a check,
    /// or dismissed by the person, which takes them away at once.
    enum Finish {
        case done, dismissed
    }

    private var drawn: [Mark.ID: Drawn] = [:]
    private var previewing: Preview?
    private var markStyle: MarkStyle?
    private let scale: CGFloat

    init(scale: CGFloat) {
        self.scale = scale
        super.init()
        anchorPoint = .zero
        contentsScale = scale
    }

    override init(layer: Any) {
        scale = (layer as? LiveMarksLayer)?.scale ?? 2
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// `drawingOn` names the marks that draw themselves on as they appear, in the order of `marks`,
    /// `pulsing` the ones that shimmer, and `finishing` the ones that leave, and how.
    func show(_ marks: [Mark], markStyle: MarkStyle, textStyle: TextStyle, drawingOn: Set<Mark.ID>, pulsing: Set<Mark.ID>,
              finishing: [Mark.ID: Finish] = [:]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let ids = Set(marks.map(\.id))
        for id in drawn.keys where !ids.contains(id) { remove(id) }
        var delay: CFTimeInterval = 0
        let motion = Settings.shared.motionUI
        self.markStyle = markStyle
        // One check for what finishes together: on its note, or its last shape when it has none.
        let done = marks.filter { finishing[$0.id] == .done }
        let checked = (done.first { if case .text = $0.geometry { true } else { false } } ?? done.last)?.id
        for mark in marks {
            var record = drawn[mark.id] ?? Drawn()
            let new = drawn[mark.id] == nil
            if new {
                record.holder.anchorPoint = .zero
                record.previewed.anchorPoint = .zero
                record.holder.addSublayer(record.previewed)
                addSublayer(record.holder)
            }
            record.mark = mark
            if case .text = mark.geometry {
                let note = record.note ?? NoteLayer(scale: scale)
                note.show(mark, textStyle: textStyle, markStyle: markStyle)
                if record.note == nil { record.previewed.addSublayer(note); record.note = note }
                if drawingOn.contains(mark.id) { note.springIn(after: delay, duration: motion.liveInkDrawOn); delay += motion.liveInkDrawOn * 0.3 }
            } else {
                let shape = record.shape ?? ShapeMarkLayer(scale: scale)
                shape.show(previewing == .pick(mark.id) ? Self.persons(mark) : mark, pointScale: 1, markStyle: markStyle)
                if record.shape == nil { record.previewed.addSublayer(shape.root); record.shape = shape }
                if drawingOn.contains(mark.id) { shape.drawOn(after: delay, duration: motion.liveInkDrawOn); delay += motion.liveInkDrawOn * 0.6 }
            }
            if let how = finishing[mark.id], !record.finished {
                record.finished = true
                finish(record, how, check: mark.id == checked, markStyle: markStyle, textStyle: textStyle)
            }
            drawn[mark.id] = record
        }
        let shimmering = marks.filter { pulsing.contains($0.id) && finishing[$0.id] == nil }
        let area = shimmering.compactMap { drawn[$0.id].flatMap(Self.extent(of:)) }.reduce(CGRect.null) { $0.union($1) }
        for mark in marks {
            guard let record = drawn[mark.id] else { continue }
            shimmer(record, over: shimmering.contains { $0.id == mark.id } && !area.isNull ? area : nil)
        }
        CATransaction.commit()
    }

    /// Shows what a tap would do to one mark, and puts the last one back, over a short fade.
    func preview(_ preview: Preview?) {
        guard preview != previewing else { return }
        let old = previewing
        previewing = preview
        CATransaction.begin()
        CATransaction.setAnimationDuration(Settings.shared.motionUI.liveInkHideFade)
        if let old { apply(old, on: false) }
        if let preview { apply(preview, on: true) }
        CATransaction.commit()
    }

    private func apply(_ preview: Preview, on: Bool) {
        guard let record = drawn[preview.id] else { return }
        switch preview {
        case .erase:
            record.previewed.opacity = on ? 0.35 : 1
        case .pick:
            guard let mark = record.mark, let markStyle else { return }
            record.shape?.show(on ? Self.persons(mark) : mark, pointScale: 1, markStyle: markStyle)
        }
    }

    /// An answer's mark drawn as the person's.
    private static func persons(_ mark: Mark) -> Mark {
        var own = mark
        own.agent = false
        return own
    }

    /// How long an erased or cleared mark takes to fade out.
    static var removalFade: CFTimeInterval { Settings.shared.motionUI.liveInkHideFade * 1.5 }

    /// Fades every mark out and lets it go.
    func removeAll() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for id in drawn.keys { remove(id) }
        CATransaction.commit()
    }

    /// Fades a mark out and lets it go, rather than taking it off in a frame.
    private func remove(_ id: Mark.ID) {
        if previewing?.id == id { previewing = nil }
        guard let holder = drawn.removeValue(forKey: id)?.holder else { return }
        let fade = Self.removalFade
        guard fade > 0, holder.opacity > 0 else { holder.removeFromSuperlayer(); return }
        CATransaction.begin()
        CATransaction.setCompletionBlock { holder.removeFromSuperlayer() }
        let out = CABasicAnimation(keyPath: "opacity")
        out.fromValue = holder.presentation()?.opacity ?? holder.opacity
        out.toValue = 0
        out.duration = fade
        out.timingFunction = CAMediaTimingFunction(name: .easeIn)
        holder.opacity = 0
        holder.add(out, forKey: "fade")
        CATransaction.commit()
    }

    /// Moves a mark by `offset` from where it was drawn, at once.
    /// Moves a mark by `offset` from where it was drawn, at once, or over `duration` from wherever
    /// it is on screen now, so a glide that a newer one interrupts carries on from there.
    func move(_ id: Mark.ID, by offset: CGVector, duration: CFTimeInterval = 0) {
        guard let holder = drawn[id]?.holder else { return }
        let position = CGPoint(x: offset.dx, y: offset.dy)
        guard holder.position != position else { return }
        let from = holder.presentation()?.position ?? holder.position
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        holder.position = position
        CATransaction.commit()
        guard duration > 0 else { return }
        let glide = CABasicAnimation(keyPath: "position")
        glide.fromValue = NSValue(point: from)
        glide.toValue = NSValue(point: position)
        glide.duration = duration
        glide.timingFunction = CAMediaTimingFunction(name: .easeOut)
        holder.add(glide, forKey: "glide")
    }

    /// Cuts a mark off outside `rect`, in the marks' coordinates, as its scroll area cuts off the
    /// content it points at; nil shows all of it.
    func clip(_ id: Mark.ID, to rect: CGRect?) {
        guard let holder = drawn[id]?.holder else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let rect {
            let mask = holder.mask ?? CALayer()
            mask.backgroundColor = CGColor(gray: 0, alpha: 1)
            mask.frame = rect.offsetBy(dx: -holder.position.x, dy: -holder.position.y)
            holder.mask = mask
        } else {
            holder.mask = nil
        }
        CATransaction.commit()
    }

    /// Whether a mark is meant to show, whatever a fade under way has got to.
    func isShown(_ id: Mark.ID) -> Bool { (drawn[id]?.holder.opacity ?? 0) > 0 }

    /// Fades a mark in or out over `duration`, from wherever a fade under way has got to.
    func fade(_ id: Mark.ID, shown: Bool, duration: CFTimeInterval) {
        guard let holder = drawn[id]?.holder else { return }
        let target: Float = shown ? 1 : 0
        let from = holder.presentation()?.opacity ?? holder.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        holder.opacity = target
        CATransaction.commit()
        guard duration > 0, from != target else { holder.removeAnimation(forKey: "fade"); return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.toValue = target
        fade.duration = duration * Double(abs(target - from))
        fade.timingFunction = CAMediaTimingFunction(name: shown ? .easeOut : .easeIn)
        holder.add(fade, forKey: "fade")
    }

    /// What is waiting for its answer shimmers: a lighter band sweeps across it, the rest at full
    /// strength, so it reads as being worked on. One band crosses every mark of the ask, as if they
    /// were one picture: each mark's mask spans `area`, the marks' extent in their own coordinates,
    /// and every sweep keeps time with `shimmerEpoch`. A mask is in its layer's coordinates, which
    /// are the marks' for a shape and start at the note's corner for a note.
    private func shimmer(_ record: Drawn, over area: CGRect?) {
        let layer = record.layer
        let frame = area.map { area in record.note.map { area.offsetBy(dx: -$0.frame.minX, dy: -$0.frame.minY) } ?? area }
        guard let frame, !frame.isEmpty else {
            if layer.mask is ShimmerMask { layer.mask = nil }
            return
        }
        if let band = layer.mask as? ShimmerMask { band.frame = frame; return }
        let band = ShimmerMask()
        band.frame = frame
        let light = CGColor(gray: 1, alpha: 0.4), full = CGColor(gray: 1, alpha: 1)
        band.startPoint = CGPoint(x: 0, y: 0.3)
        band.endPoint = CGPoint(x: 1, y: 0.7)
        layer.mask = band
        guard Settings.shared.motionScale > 0 else {
            band.colors = [CGColor(gray: 1, alpha: 0.7), CGColor(gray: 1, alpha: 0.7)]
            return
        }
        band.colors = [full, light, full]
        band.locations = [0, 0.15, 0.3]
        let sweep = CABasicAnimation(keyPath: "locations")
        sweep.fromValue = [-0.3, -0.15, 0]
        sweep.toValue = [1, 1.15, 1.3]
        sweep.duration = 1.4
        sweep.repeatCount = .infinity
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        sweep.beginTime = band.convertTime(Self.shimmerEpoch, from: nil)
        band.add(sweep, forKey: "sweep")
    }

    /// When the first shimmer began, which every sweep counts from, so marks that start shimmering
    /// at different moments sweep together.
    private static let shimmerEpoch = CACurrentMediaTime()

    /// Done: the mark turns green, the note of the ask, or its last shape when it has none, raises a
    /// small green check, and then the mark leaves. Dismissed: it leaves at once. The layers stay at
    /// the end state, invisible, until the mark is removed (`LiveInk.finishDuration`).
    private func finish(_ record: Drawn, _ how: Finish, check: Bool, markStyle: MarkStyle, textStyle: TextStyle) {
        let motion = Settings.shared.motionScale
        let now = record.previewed.convertTime(CACurrentMediaTime(), from: nil)
        guard motion > 0, let mark = record.mark else {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = Self.doneFade
            record.previewed.opacity = 0
            record.previewed.add(fade, forKey: "done")
            return
        }
        let hold = how == .done ? Self.doneHold * motion : 0, away = Self.doneAway * motion
        if how == .done { celebrate(record, mark: mark, check: check, markStyle: markStyle, textStyle: textStyle, now: now, hold: hold) }
        leave(record, now: now, hold: hold, away: away)
    }

    /// Turns the mark green, as a copy drawn over it and faded in, and with `check`, raises the check.
    private func celebrate(_ record: Drawn, mark: Mark, check: Bool, markStyle: MarkStyle, textStyle: TextStyle,
                           now: CFTimeInterval, hold: CFTimeInterval) {
        let motion = Settings.shared.motionScale
        var green = markStyle
        green.personColor = Self.doneColor
        green.agentColor = Self.doneColor
        let twin: CALayer
        if record.note != nil {
            let copy = NoteLayer(scale: scale)
            copy.show(mark, textStyle: textStyle, markStyle: green)
            twin = copy
        } else {
            let copy = ShapeMarkLayer(scale: scale)
            copy.show(mark, pointScale: 1, markStyle: green)
            twin = copy.root
        }
        record.previewed.addSublayer(twin)
        let tint = CABasicAnimation(keyPath: "opacity")
        tint.fromValue = 0
        tint.toValue = 1
        tint.beginTime = now
        tint.duration = 0.14 * motion
        tint.fillMode = .backwards
        tint.timingFunction = CAMediaTimingFunction(name: .easeOut)
        twin.add(tint, forKey: "tint")
        if check, let top = Self.topCentre(of: mark, textStyle: textStyle) {
            let size = Self.checkSize
            let badge = Self.check(rising: CGPoint(x: top.x, y: top.y + size * 0.8), to: CGPoint(x: top.x, y: top.y - 6 - size / 2),
                                   size: size, markStyle: markStyle, now: now + 0.12 * motion, leaving: now + hold - 0.08 * motion, motion: motion)
            // Under the mark, so it rises from behind it.
            record.previewed.insertSublayer(badge, at: 0)
        }
    }

    /// A note shrinks and fades, and a shape un-draws along its path and fades, after `hold`.
    private func leave(_ record: Drawn, now: CFTimeInterval, hold: CFTimeInterval, away: CFTimeInterval) {
        if record.note != nil {
            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.fromValue = 1
            shrink.toValue = 0.85
            shrink.beginTime = now + hold
            shrink.duration = away
            shrink.fillMode = .forwards
            shrink.isRemovedOnCompletion = false
            shrink.timingFunction = CAMediaTimingFunction(name: .easeIn)
            for layer in (record.previewed.sublayers ?? []) where layer is NoteLayer { layer.add(shrink, forKey: "done") }
        } else {
            for shape in Self.shapeLayers(in: record.previewed) {
                let undraw = CABasicAnimation(keyPath: "strokeStart")
                undraw.fromValue = 0
                undraw.toValue = 1
                undraw.beginTime = now + hold * 0.8
                undraw.duration = away
                undraw.fillMode = .forwards
                undraw.isRemovedOnCompletion = false
                undraw.timingFunction = CAMediaTimingFunction(name: .easeIn)
                shape.add(undraw, forKey: "done")
            }
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.beginTime = now + hold + (record.note == nil ? away * 0.5 : 0)
        fade.duration = record.note == nil ? away * 0.5 : away
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        record.previewed.add(fade, forKey: "done")
    }

    /// The middle of the top edge of a note's tag, or of a shape's extent, where the check rises to.
    private static func topCentre(of mark: Mark, textStyle: TextStyle) -> CGPoint? {
        if case .text(let text) = mark.geometry {
            let box = TextLayout(text, imageWidth: .greatestFiniteMagnitude, pointScale: 1, style: textStyle.forMark(mark)).box
            return CGPoint(x: box.midX, y: box.minY)
        }
        return mark.shapeExtent.map { CGPoint(x: $0.midX, y: $0.minY) }
    }

    /// A green disc with a white edge and a white check that draws itself on. It springs up from
    /// `start` to `end` as it grows, overshooting a little, and at `leaving` swells and shrinks away.
    private static func check(rising start: CGPoint, to end: CGPoint, size: CGFloat, markStyle: MarkStyle,
                              now: CFTimeInterval, leaving: CFTimeInterval, motion: CGFloat) -> CALayer {
        let badge = CAShapeLayer()
        badge.frame = CGRect(x: end.x - size / 2, y: end.y - size / 2, width: size, height: size)
        badge.path = CGPath(ellipseIn: badge.bounds, transform: nil)
        badge.fillColor = doneColor.cgColor
        badge.strokeColor = markStyle.edgeColor.cgColor
        badge.lineWidth = markStyle.edgeWidth
        badge.shadowOpacity = Float(0.25 * markStyle.shadowOpacity)
        badge.shadowRadius = 2
        badge.shadowOffset = CGSize(width: 0, height: 1)
        let tick = CAShapeLayer()
        tick.frame = badge.bounds
        let path = CGMutablePath()
        path.move(to: CGPoint(x: size * 0.29, y: size * 0.52))
        path.addLine(to: CGPoint(x: size * 0.44, y: size * 0.67))
        path.addLine(to: CGPoint(x: size * 0.72, y: size * 0.36))
        tick.path = path
        tick.fillColor = nil
        tick.strokeColor = CGColor(gray: 1, alpha: 1)
        tick.lineWidth = max(1.75, size * 0.12)
        tick.lineCap = .round
        tick.lineJoin = .round
        badge.addSublayer(tick)
        let rise = CASpringAnimation(keyPath: "position")
        rise.fromValue = NSValue(point: start)
        rise.toValue = NSValue(point: end)
        rise.stiffness = 320
        rise.damping = 15
        rise.beginTime = now
        rise.duration = rise.settlingDuration
        rise.fillMode = .backwards
        badge.add(rise, forKey: "rise")
        let grow = CASpringAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.4
        grow.toValue = 1
        grow.stiffness = 320
        grow.damping = 12
        grow.beginTime = now
        grow.duration = grow.settlingDuration
        grow.fillMode = .backwards
        badge.add(grow, forKey: "grow")
        let away = CAKeyframeAnimation(keyPath: "transform.scale")
        away.values = [1, 1.18, 0]
        away.keyTimes = [0, 0.35, 1]
        away.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
        away.beginTime = leaving
        away.duration = 0.26 * motion
        away.fillMode = .forwards
        away.isRemovedOnCompletion = false
        badge.add(away, forKey: "away")
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.beginTime = now + 0.06
        draw.duration = 0.24 * motion
        draw.fillMode = .backwards
        draw.timingFunction = CAMediaTimingFunction(name: .easeOut)
        tick.add(draw, forKey: "draw")
        return badge
    }

    /// What a mark draws, in the marks' coordinates: a note's bitmap, or a shape's extent with room
    /// for its edge and shadow.
    private static func extent(of record: Drawn) -> CGRect? {
        record.note?.frame ?? record.mark?.shapeExtent?.insetBy(dx: -shimmerMargin, dy: -shimmerMargin)
    }

    private static func shapeLayers(in layer: CALayer) -> [CAShapeLayer] {
        ([layer as? CAShapeLayer].compactMap { $0 }) + (layer.sublayers ?? []).flatMap(shapeLayers(in:))
    }

    /// The done animation's times at full motion: how long the check shows, and how long the marks
    /// take to leave after it. `LiveInk.doneDuration` is their sum, plus a margin.
    static let doneHold: CFTimeInterval = 0.9
    static let doneAway: CFTimeInterval = 0.45
    static let doneFade: CFTimeInterval = 0.3
    /// The done state's green, macOS's system green in light mode, and the check's diameter in pt.
    static let doneColor = SRGB(hex: "#34C759")!
    private static let checkSize: CGFloat = 16

    /// Room round a shape for its edge and shadow, which the mask would otherwise cut off.
    private static let shimmerMargin: CGFloat = 16
}

/// The mask that makes a mark shimmer, told apart from any other mask its layer might have.
private final class ShimmerMask: CAGradientLayer {}

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
