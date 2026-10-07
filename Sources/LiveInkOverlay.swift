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
        canvas.marksLayer.host = canvas
        canvas.marksLayer.sharing = sharingType
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
              finishing: [Mark.ID: LiveMarksLayer.Finish] = [:], overDark: Set<Mark.ID> = [], hands: [Mark.ID: InkHand] = [:]) {
        canvas.marksLayer.show(marks, markStyle: markStyle, textStyle: textStyle, drawingOn: drawingOn, pulsing: pulsing,
                               finishing: finishing, overDark: overDark, hands: hands)
    }

    /// The stroke being drawn on any screen, in global top-left points, so one that crosses onto
    /// this screen shows here too.
    func showPen(_ points: [CGPoint], markStyle: MarkStyle) {
        canvas.showPen(points, markStyle: markStyle)
    }

    /// `pen` is in global top-left points; the glow follows the pointer over this screen after that.
    func showGlow(_ on: Bool, ui: UITweaks, color: CGColor, pen: CGPoint?) {
        canvas.showGlow(on, ui: ui, color: color, pen: pen)
    }

    func preview(_ preview: LiveMarksLayer.Preview?) { canvas.marksLayer.preview(preview) }

    func popover(of id: Mark.ID) -> ReplyPopover? { canvas.marksLayer.popover(of: id) }

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
        private let pen: InkMarkLayer
        private var stroke: [CGPoint] = []
        private let scale: CGFloat

        var isTracking: Bool { !stroke.isEmpty }

        init(frame: CGRect, scale: CGFloat) {
            self.scale = scale
            glow = EdgeGlow(scale: scale)
            pen = InkMarkLayer(scale: scale)
            marksLayer = LiveMarksLayer(scale: scale)
            super.init(frame: frame)
            layer = host
            wantsLayer = true
            host.contentsScale = scale
            for layer in [marksLayer, pen] {
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
            for layer in [marksLayer, pen] {
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

        func showPen(_ points: [CGPoint], markStyle: MarkStyle) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            let stroke = InkHand.stroke(points, tapersEnd: false)
            pen.isHidden = stroke.points.count < 2
            guard stroke.points.count > 1 else { return }
            pen.showPen(stroke, markStyle: markStyle)
        }

        func showGlow(_ on: Bool, ui: UITweaks, color: CGColor, pen: CGPoint?) {
            glow.show(on, ui: ui, color: color, pen: pen.map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) })
        }

        override func mouseMoved(with event: NSEvent) {
            glow.follow(convert(event.locationInWindow, from: nil))
            guard !isTracking else { return }
            onHover?(location(of: event))
        }

        override func mouseDown(with event: NSEvent) {
            glow.follow(convert(event.locationInWindow, from: nil))
            stroke = [location(of: event)]
            onStrokeMoved?(stroke)
        }

        override func mouseDragged(with event: NSEvent) {
            guard isTracking else { return }
            glow.follow(convert(event.locationInWindow, from: nil))
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
        /// A person's shape, or an agent's shown as the person's while a tap would pick it.
        var ink: InkMarkLayer?
        /// An agent's shape.
        var light: LightMarkLayer?
        var note: NoteLayer?
        /// An agent's focus, under every other mark.
        var focus: FocusLayer?
        var mark: Mark?
        /// The done animation has started on it; the mark is removed once it ends.
        var finished = false
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
    /// An answer's reply is a popover from this view, the one whose layer holds the marks, rather
    /// than a note drawn here. Its window shares with captures as `sharing` says, as the overlay does.
    weak var host: NSView?
    var sharing: NSWindow.SharingType = .none
    private var popovers: [Mark.ID: ReplyPopover] = [:]

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
    /// `pulsing` the ones that carry the thinking light, `finishing` the ones that leave, and how, `overDark` the
    /// agent's shapes whose window is dark behind them, and `hands` how the person drew their marks. A
    /// person's mark that draws itself on eases from where the hand drew it, when its hand is known.
    func show(_ marks: [Mark], markStyle: MarkStyle, textStyle: TextStyle, drawingOn: Set<Mark.ID>, pulsing: Set<Mark.ID>,
              finishing: [Mark.ID: Finish] = [:], overDark: Set<Mark.ID> = [], hands: [Mark.ID: InkHand] = [:]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let ids = Set(marks.map(\.id))
        for id in drawn.keys where !ids.contains(id) { remove(id) }
        var delay: CFTimeInterval = 0
        let motion = Settings.shared.motionUI
        self.markStyle = markStyle
        // One check for what finishes together: on its note, or its last shape when it has none. A
        // reply's popover would cover a check on it.
        let done = marks.filter { finishing[$0.id] == .done && $0.popover == nil }
        let checked = (done.first { if case .text = $0.geometry { true } else { false } } ?? done.last)?.id
        var appearing = Set<Mark.ID>()
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
            if mark.popover != nil, let host {
                if popovers[mark.id] == nil { popovers[mark.id] = ReplyPopover(host: host, sharing: sharing) }
                if drawingOn.contains(mark.id) { appearing.insert(mark.id) }
            } else if let place = mark.focus {
                let focus = record.focus ?? FocusLayer()
                focus.show(place, spot: mark.shapeExtent ?? place.target)
                if record.focus == nil {
                    record.previewed.addSublayer(focus.root)
                    record.holder.zPosition = -1
                    record.focus = focus
                }
                if drawingOn.contains(mark.id) { focus.appear(duration: Focus.fade * Settings.shared.motionScale) }
            } else if case .text = mark.geometry {
                let note = record.note ?? NoteLayer(scale: scale)
                note.show(mark, textStyle: textStyle, markStyle: markStyle)
                if record.note == nil { record.previewed.addSublayer(note); record.note = note }
                if drawingOn.contains(mark.id) { note.springIn(after: delay, duration: motion.liveInkDrawOn); delay += motion.liveInkDrawOn * 0.3 }
            } else if mark.agent {
                let light = record.light ?? LightMarkLayer(scale: scale)
                light.show(mark, markStyle: markStyle, dark: overDark.contains(mark.id))
                if record.light == nil { record.previewed.addSublayer(light.root); record.light = light }
                if drawingOn.contains(mark.id) {
                    light.drawOn(after: delay, duration: motion.liveInkDrawOn, settle: Self.lightSettle * Settings.shared.motionScale)
                    delay += motion.liveInkDrawOn * 0.6
                }
            } else {
                let ink = record.ink ?? InkMarkLayer(scale: scale)
                let hand = hands[mark.id]
                ink.show(mark, hand: hand, markStyle: markStyle)
                if record.ink == nil { record.previewed.addSublayer(ink); record.ink = ink }
                if drawingOn.contains(mark.id), let hand {
                    ink.ease(from: hand.drawn(for: mark), duration: Self.inkEase * Settings.shared.motionScale)
                } else if drawingOn.contains(mark.id) {
                    ink.drawOn(after: delay, duration: motion.liveInkDrawOn)
                    delay += motion.liveInkDrawOn * 0.6
                }
            }
            if let how = finishing[mark.id], !record.finished {
                record.finished = true
                finish(record, how, check: mark.id == checked, markStyle: markStyle, textStyle: textStyle)
            }
            drawn[mark.id] = record
        }
        for mark in marks {
            guard let record = drawn[mark.id] else { continue }
            let thinking = pulsing.contains(mark.id) && finishing[mark.id] == nil
            think(record, thinking, markStyle: markStyle)
            popovers[mark.id]?.think(thinking)
        }
        CATransaction.commit()
        for mark in marks where popovers[mark.id] != nil && finishing[mark.id] == nil {
            showPopover(of: mark.id, appearing: appearing.contains(mark.id))
        }
    }

    /// Puts a reply's popover where its mark is now, faded as its mark is, over `fade` seconds.
    private func showPopover(of id: Mark.ID, appearing: Bool = false, fade: CFTimeInterval = 0) {
        guard let popover = popovers[id], let record = drawn[id], let mark = record.mark, let place = mark.popover,
              let hostLayer = host?.layer else { return }
        popover.show(mark, place: place, at: record.holder.convert(place.at, to: hostLayer), appearing: appearing)
        popover.fade(to: CGFloat(record.holder.opacity * record.previewed.opacity), duration: fade)
    }

    func popover(of id: Mark.ID) -> ReplyPopover? { popovers[id] }

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
            showPopover(of: preview.id, fade: CATransaction.animationDuration())
        case .pick:
            guard let mark = record.mark, let markStyle, let light = record.light else { return }
            // The light gives way to the person's ink, which is what a tap would make it.
            let ink: InkMarkLayer
            if let shown = record.ink {
                ink = shown
            } else {
                ink = InkMarkLayer(scale: scale)
                ink.show(Self.persons(mark), hand: nil, markStyle: markStyle)
                record.previewed.addSublayer(ink)
                var record = record
                record.ink = ink
                drawn[preview.id] = record
                // A layer added in this transaction takes its first opacity without animating.
                let appear = CABasicAnimation(keyPath: "opacity")
                appear.fromValue = 0
                appear.duration = CATransaction.animationDuration()
                ink.add(appear, forKey: "pick")
            }
            ink.opacity = on ? 1 : 0
            light.root.opacity = on ? 0 : 1
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
        for id in Array(drawn.keys) { remove(id) }
        CATransaction.commit()
    }

    /// Fades a mark out and lets it go, rather than taking it off in a frame.
    private func remove(_ id: Mark.ID) {
        if previewing?.id == id { previewing = nil }
        popovers.removeValue(forKey: id)?.close(fade: Self.removalFade)
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
        showPopover(of: id)
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
        fade(id, to: shown ? 1 : 0, duration: duration)
    }

    /// Fades a mark to `target`, its opacity, over `duration` from wherever a fade under way has got to.
    func fade(_ id: Mark.ID, to target: Float, duration: CFTimeInterval) {
        guard let holder = drawn[id]?.holder else { return }
        let shown = target > (holder.presentation()?.opacity ?? holder.opacity)
        let from = holder.presentation()?.opacity ?? holder.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        holder.opacity = target
        CATransaction.commit()
        showPopover(of: id, fade: duration * Double(abs(target - from)))
        guard duration > 0, from != target else { holder.removeAnimation(forKey: "fade"); return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.toValue = target
        fade.duration = duration * Double(abs(target - from))
        fade.timingFunction = CAMediaTimingFunction(name: shown ? .easeOut : .easeIn)
        holder.add(fade, forKey: "fade")
    }

    /// What is waiting for its answer carries the thinking light: a short band of light runs along
    /// each of its strokes, and a sheen crosses its note a third of a beat later, so the marks read as
    /// being worked on. Every band and sheen keeps time with `thinkingEpoch`, so marks that start at
    /// different moments move together. With motion off the ink brightens and holds. The light fades
    /// in and out; one fading out has opacity 0 and counts as gone.
    private func think(_ record: Drawn, _ on: Bool, markStyle: MarkStyle) {
        let lit = { (layer: CALayer) in (layer is ThinkingBand || layer is NoteSheen) && layer.opacity > 0 }
        let shown = record.previewed.sublayers?.first(where: lit) ?? record.note?.sublayers?.first(where: lit)
        let fade = Self.thinkingFade * Settings.shared.motionScale
        guard on, let mark = record.mark else {
            guard let shown else { return }
            let from = shown.presentation()?.opacity ?? shown.opacity
            shown.opacity = 0
            guard fade > 0 else { shown.removeFromSuperlayer(); return }
            CATransaction.begin()
            CATransaction.setCompletionBlock { shown.removeFromSuperlayer() }
            let out = CABasicAnimation(keyPath: "opacity")
            out.fromValue = from
            out.toValue = 0
            out.duration = fade
            shown.add(out, forKey: "fade")
            CATransaction.commit()
            return
        }
        guard shown == nil else { return }
        let still = Settings.shared.motionScale == 0
        let light: CALayer
        if let note = record.note {
            light = NoteSheen(over: note, still: still)
            note.addSublayer(light)
        } else if let path = record.ink?.centreLine ?? mark.shape(pointScale: 1, markStyle: markStyle)?.stroked {
            light = ThinkingBand(along: path, width: markStyle.strokeWidth, scale: scale, still: still)
            record.previewed.addSublayer(light)
        } else {
            return
        }
        guard fade > 0 else { return }
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.duration = fade
        light.add(fadeIn, forKey: "fade")
    }

    /// When the first thinking light began, which every band and sheen counts from, how long one
    /// takes to cross its mark, and how long the light takes to come and go at full motion.
    nonisolated static let thinkingEpoch = CACurrentMediaTime()
    nonisolated static let thinkingPeriod: CFTimeInterval = 1.15
    static let thinkingFade: CFTimeInterval = 0.2

    /// Done: the mark turns green, the note of the ask, or its last shape when it has none, raises a
    /// small green check, and then the mark leaves. Dismissed: it leaves at once. The layers stay at
    /// the end state, invisible, until the mark is removed (`LiveInk.finishDuration`).
    private func finish(_ record: Drawn, _ how: Finish, check: Bool, markStyle: MarkStyle, textStyle: TextStyle) {
        let motion = Settings.shared.motionScale
        let now = record.previewed.convertTime(CACurrentMediaTime(), from: nil)
        // A reply's popover stays while the marks it answered turn green, and leaves with them.
        if let popover = record.mark.flatMap({ popovers[$0.id] }) {
            return popover.close(after: how == .done ? Self.doneHold * motion : 0, fade: motion > 0 ? Self.doneAway * motion : Self.doneFade)
        }
        // A focus has nothing to turn green.
        guard motion > 0, let mark = record.mark, record.focus == nil else {
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
        } else if let ink = record.ink {
            twin = ink.twin(in: green)
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
            for ink in (record.previewed.sublayers ?? []).compactMap({ $0 as? InkMarkLayer }) {
                ink.undraw(at: now + hold * 0.8, duration: away)
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

    private static func shapeLayers(in layer: CALayer) -> [CAShapeLayer] {
        ([layer as? CAShapeLayer].compactMap { $0 }) + (layer.sublayers ?? []).flatMap(shapeLayers(in:))
    }

    /// The done animation's times at full motion: how long the check shows, and how long the marks
    /// take to leave after it. `LiveInk.doneDuration` is their sum, plus a margin.
    static let doneHold: CFTimeInterval = 0.9
    static let doneAway: CFTimeInterval = 0.45
    static let doneFade: CFTimeInterval = 0.3
    /// How long an agent's light takes to settle once it has drawn itself on, and how long the
    /// person's ink takes to ease onto its shape, at full motion.
    static let lightSettle: CFTimeInterval = 0.9
    static let inkEase: CFTimeInterval = 0.3
    /// The done state's green, macOS's system green in light mode, and the check's diameter in pt.
    static let doneColor = SRGB(hex: "#34C759")!
    private static let checkSize: CGFloat = 16
}

/// The thinking light on one stroke: a band of light `bandLength` long that runs along it from start
/// to end, starting and finishing `runUp` off the stroke so each pass ends in a short rest.
private final class ThinkingBand: CAShapeLayer {
    init(along path: CGPath, width: CGFloat, scale: CGFloat, still: Bool) {
        super.init()
        anchorPoint = .zero
        contentsScale = scale
        self.path = path
        fillColor = nil
        strokeColor = CGColor(gray: 1, alpha: 0.85)
        lineWidth = width * 0.7
        lineCap = .round
        lineJoin = .round
        shadowColor = CGColor(gray: 1, alpha: 1)
        shadowOffset = .zero
        shadowRadius = 4
        shadowOpacity = 0.9
        guard !still else { opacity = 0.35; return }
        let length = max(path.length, 1)
        let reach = Self.bandLength / length, runUp = Self.runUp / length
        // Core Animation clamps the ends to the stroke, so the band grows in at the start and shrinks
        // away at the end.
        let end = CABasicAnimation(keyPath: "strokeEnd")
        end.fromValue = -runUp
        end.toValue = 1 + reach + runUp
        let start = CABasicAnimation(keyPath: "strokeStart")
        start.fromValue = -runUp - reach
        start.toValue = 1 + runUp
        let run = CAAnimationGroup()
        run.animations = [end, start]
        run.duration = LiveMarksLayer.thinkingPeriod
        run.repeatCount = .infinity
        run.beginTime = convertTime(LiveMarksLayer.thinkingEpoch, from: nil)
        add(run, forKey: "think")
    }

    override init(layer: Any) { super.init(layer: layer) }

    required init?(coder: NSCoder) { fatalError("not used") }

    static let bandLength: CGFloat = 40
    static let runUp: CGFloat = 40
}

/// The thinking light on a note: a sheen that crosses its tag a third of a beat after the band on
/// the ink, masked by the note's own picture so only the tag catches it.
private final class NoteSheen: CAGradientLayer {
    init(over note: NoteLayer, still: Bool) {
        super.init()
        frame = note.bounds
        contentsScale = note.contentsScale
        let tag = CALayer()
        tag.frame = bounds
        tag.contents = note.contents
        tag.contentsScale = note.contentsScale
        mask = tag
        startPoint = CGPoint(x: 0, y: 0.3)
        endPoint = CGPoint(x: 1, y: 0.7)
        guard !still else {
            colors = [CGColor(gray: 1, alpha: 0.15), CGColor(gray: 1, alpha: 0.15)]
            return
        }
        let clear = CGColor(gray: 1, alpha: 0), lit = CGColor(gray: 1, alpha: 0.42)
        colors = [clear, lit, clear]
        locations = [-0.3, -0.15, 0]
        let sweep = CABasicAnimation(keyPath: "locations")
        sweep.fromValue = [-0.3, -0.15, 0]
        sweep.toValue = [1, 1.15, 1.3]
        sweep.duration = LiveMarksLayer.thinkingPeriod
        sweep.repeatCount = .infinity
        sweep.beginTime = convertTime(LiveMarksLayer.thinkingEpoch, from: nil)
        // Two thirds of a beat ahead is a third behind: the sheen follows the band.
        sweep.timeOffset = LiveMarksLayer.thinkingPeriod * 0.65
        add(sweep, forKey: "think")
    }

    override init(layer: Any) { super.init(layer: layer) }

    required init?(coder: NSCoder) { fatalError("not used") }
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

/// A thin bright line along the screen's edges with a soft glow falling off inward, brightest near
/// the pen, which says the screen is taking ink.
@MainActor
final class EdgeGlow: CALayer {
    /// The glow, cut into a strip along each edge as deep as it reaches: the top and bottom span the
    /// width and the sides fit between them. Each strip has its own mask for the brightness round
    /// the pen, so following the pen composites the strips again rather than the whole screen.
    private let strips: [Strip]
    /// Where the pen is, in this layer's points.
    private var pen: CGPoint?
    /// What the strips' pictures were drawn for.
    private var laid: (size: CGSize, reach: CGFloat, color: CGColor)?

    /// Sublayers of a layer-hosting view do not take the screen's scale from it.
    init(scale: CGFloat) {
        strips = (0..<4).map { _ in Strip(scale: scale) }
        super.init()
        contentsScale = scale
        strips.forEach { addSublayer($0.layer) }
        opacity = 0
    }

    override init(layer: Any) {
        strips = []
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Shows or hides the glow, `pen` in this layer's points, drawn in a lighter `color`.
    func show(_ on: Bool, ui: UITweaks, color: CGColor, pen: CGPoint?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if on { lay(out: ui.liveInkGlowWidth, color: color.mixed(with: .white, Self.lighten)) }
        if let pen { self.pen = pen }
        follow()
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

    /// Moves the brightest part of the glow to `pen`, in this layer's points.
    func follow(_ pen: CGPoint) {
        guard opacity > 0 else { return }
        self.pen = pen
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        follow()
        CATransaction.commit()
    }

    /// Draws the line and the glow into each strip, unless they are drawn already for this size, reach
    /// and colour.
    private func lay(out reach: CGFloat, color: CGColor) {
        let size = bounds.size
        if let laid, laid.size == size, laid.reach == reach, laid.color == color { return }
        laid = (size, reach, color)
        let depth = min(reach * Self.tail, size.width / 2, size.height / 2)
        let rects = [CGRect(x: 0, y: 0, width: size.width, height: depth),
                     CGRect(x: 0, y: size.height - depth, width: size.width, height: depth),
                     CGRect(x: 0, y: depth, width: depth, height: size.height - depth * 2),
                     CGRect(x: size.width - depth, y: depth, width: depth, height: size.height - depth * 2)]
        for (strip, rect) in zip(strips, rects) {
            strip.layer.frame = rect
            strip.layer.contents = Self.picture(of: rect, on: size, scale: contentsScale, reach: reach, color: color)
        }
    }

    /// Sets each strip's mask from `pen`: full brightness under it, falling to `floor` far from it.
    private func follow() {
        let size = bounds.size
        guard let pen, size.width > 0, size.height > 0 else { return }
        // A Gaussian of the distance from the pen, as stops of a radial gradient, which reaches
        // twice the screen's diagonal so no strip is outside it.
        let reach = 2 * hypot(size.width, size.height), spread = Self.spread * size.height
        let stops: [CGFloat] = [0, 0.05, 0.1, 0.15, 0.2, 0.3, 0.45, 1]
        let colors = stops.map { stop -> CGColor in
            let near = exp(-pow(stop * reach / spread, 2))
            return CGColor(gray: 1, alpha: Self.floor + (1 - Self.floor) * near)
        }
        for strip in strips {
            strip.brightness(at: pen, reach: reach, stops: stops.map { NSNumber(value: Double($0)) }, colors: colors)
        }
    }

    /// The line and the glow over one strip of the screen, as a bitmap: each pixel's strength comes
    /// from its distance to the nearest edge, so the corners meet on their diagonals.
    private static func picture(of rect: CGRect, on screen: CGSize, scale: CGFloat, reach: CGFloat, color: CGColor) -> CGImage? {
        let width = Int((rect.width * scale).rounded()), height = Int((rect.height * scale).rounded())
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard width > 0, height > 0, reach > 0,
              let rgb = color.converted(to: space, intent: .defaultIntent, options: nil)?.components, rgb.count >= 3,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        // The strength at each whole pixel of distance, as far as a strip reaches.
        let strengths = (0...Int(reach * tail * scale) + 1).map { step -> CGFloat in
            let distance = (CGFloat(step) + 0.5) / scale
            return min(1, lineAlpha * exp(-distance / lineFalloff) + glowAlpha * exp(-distance / reach))
        }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for row in 0..<height {
            let y = rect.minY + (CGFloat(row) + 0.5) / scale
            let fromTopOrBottom = min(y, screen.height - y)
            for column in 0..<width {
                let x = rect.minX + (CGFloat(column) + 0.5) / scale
                let distance = min(fromTopOrBottom, x, screen.width - x)
                let alpha = strengths[min(Int(distance * scale), strengths.count - 1)]
                let pixel = pixels + (row * width + column) * 4
                pixel[0] = UInt8(rgb[0] * alpha * 255)
                pixel[1] = UInt8(rgb[1] * alpha * 255)
                pixel[2] = UInt8(rgb[2] * alpha * 255)
                pixel[3] = UInt8(alpha * 255)
            }
        }
        return context.makeImage()
    }

    /// How far the glow is moved towards white from the person's colour.
    private static let lighten: CGFloat = 0.3
    /// The line's strength at the edge and the distance over which it falls to a third, in points,
    /// and the glow's strength at the edge, which falls to a third over the glow's width.
    private static let lineAlpha: CGFloat = 0.9
    private static let lineFalloff: CGFloat = 1.6
    private static let glowAlpha: CGFloat = 0.55
    /// How many glow widths a strip reaches into the screen, where the glow has all but gone.
    private static let tail: CGFloat = 4
    /// How bright the glow is far from the pen, and how far its brightness spreads round the pen, as
    /// a fraction of the screen's height.
    private static let floor: CGFloat = 0.35
    private static let spread: CGFloat = 0.55

    /// One edge's strip of the glow: its picture, and the mask that brightens it near the pen.
    @MainActor
    private final class Strip {
        let layer = CALayer()
        private let mask = CAGradientLayer()

        init(scale: CGFloat) {
            for layer in [layer, mask] {
                layer.anchorPoint = .zero
                layer.contentsScale = scale
            }
            mask.type = .radial
            layer.mask = mask
        }

        func brightness(at pen: CGPoint, reach: CGFloat, stops: [NSNumber], colors: [CGColor]) {
            let rect = layer.frame
            guard rect.width > 0, rect.height > 0 else { return }
            mask.frame = CGRect(origin: .zero, size: rect.size)
            let centre = CGPoint(x: (pen.x - rect.minX) / rect.width, y: (pen.y - rect.minY) / rect.height)
            mask.startPoint = centre
            mask.endPoint = CGPoint(x: centre.x + reach / rect.width, y: centre.y + reach / rect.height)
            mask.colors = colors
            mask.locations = stops
        }
    }
}
