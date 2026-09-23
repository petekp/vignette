import AppKit

/// Hosts the drawing editor in a borderless window. Lifecycle: `prepare` opens the image in the
/// window, ordered in invisible, and gives it the keys; `show` reveals it once the card's flight
/// covers its frame; `hide` parks the drawing at once and removes the window. The editor never
/// hides itself: Esc, a click outside, Cmd+W and Done ask through `onClosed` and `onFinished`, and
/// the transition reducer decides.
@MainActor
final class AnnotationController {
    /// Done: the drawing to render, copy and finish with.
    var onFinished: ((Screenshot, Drawing) -> Void)?
    /// Esc, a click outside, or Cmd+W. The owner decides what happens next and calls `hide` when
    /// it is time; nothing here hides on its own.
    var onClosed: (() -> Void)?
    /// The editor has this key's screenshot, decoded at the screen's size.
    var onLoaded: ((String) -> Void)?
    /// A drawing to store: the editor handed it over after a change, or it was parked. `reason`
    /// names which in the log.
    var onDrawing: ((Drawing, _ reason: String) -> Void)?
    /// The stored drawing for a screenshot whose size as displayed is the given one, if any.
    var storedDrawing: ((URL, PixelSize) -> Drawing?)?
    /// The frame moved: it was placed, a zoom stepped it, or it came home on the way out. The
    /// stack follows it, so it narrows as the frame grows towards it.
    var onFrame: ((NSRect) -> Void)?
    /// The Send menu handed the drawing to this agent session.
    var onSend: ((Screenshot, Drawing, AgentDestination) -> Void)?
    /// Cmd+C with nothing selected: this drawing's rendering goes on the clipboard.
    var onCopyDrawing: ((Screenshot, Drawing) -> Void)?

    /// The editor, the whole content of the frame. The state report reads its core.
    let editor = EditorView()
    private let toolbar = AnnotatorToolbar()
    private let toast = AnnotatorToast()
    private var window: AnnotationWindow?
    /// The window spans the screen's visible frame and stays put. The visible frame is `frameView`
    /// inside it (shadow) with `container` (clip, corner, ring, editor), so a zoom step moves the
    /// frame and the picture inside it in one layer commit: a window resize and a layer change do
    /// not land on the same display frame, and the picture would drift from the frame between them.
    private var frameView: NSView?
    private var container: NSView?
    private var zoomScreen: NSScreen?
    /// The shot in the editor, from `prepare` until `hide` parks it. Not the session: see AnnotatorTransition.
    private var current: Screenshot?
    private let outsideClick = OutsideClick()
    /// The colour pass's sample of the screenshot in the editor, once it is made.
    private var colorSample: (key: String, sample: ColorSample)?
    /// Counts `open`s, so a decode or a sample only lands on the open that asked for it: the same
    /// file can be closed and opened again while the first decode is still on its way.
    private var openGeneration = 0
    /// Where the Send menu's pick goes once the editor hands over the drawing.
    private var sendingTo: AgentDestination?
    /// The text style of the tweaks, which the colour pass lays a text out in to sample under it.
    private var textStyle = TextStyle.standard

    /// Room the annotator needs below its window: the toolbar and its gap.
    var spaceBelow: CGFloat { AnnotatorToolbar.height + Settings.shared.data.ui.annotationToolbarGap }

    /// The frame `prepare` fitted the image into; zoom grows the window from here.
    private var fittedFrame: NSRect = .zero
    /// How far the image is magnified past the fitted frame. One number: `Zoom.split` divides it
    /// between the frame's growth and the magnification inside it, one division per side, so those
    /// two can never disagree about it. The picture itself is magnified uniformly by this level.
    private(set) var zoomLevel: CGFloat = 1
    /// Where the level is heading. Every input moves this; one spring carries the level to it, so
    /// a gesture, a key and a fit bend into each other instead of stepping.
    private var zoomTarget: CGFloat = 1
    private lazy var zoomTween = Tween(initial: 1) { [weak self] v in self?.applyZoom(v) }
    /// How far each side of the frame has grown past the fitted frame. 1 by 1 is the fitted frame.
    var zoomWindow: CGSize { split(zoomLevel).window }
    /// Magnification inside a frame that can grow no further on that side, per side; 1 by 1 shows
    /// the whole image.
    private(set) var canvasZoom = Zoom.none
    /// The point the window grows away from, as a fraction of the window: the cursor's own point,
    /// so what is under it stays under it, or the middle for a key. See `Zoom`.
    private var zoomAim = ZoomAim.fitted
    /// The same for the magnification inside a window that can grow no further: where the visible
    /// middle was when the input arrived, and the point it named.
    private var zoomPan = ZoomPan.centered
    /// The middle of the visible part of the image, as a fraction of it.
    private(set) var zoomCenter = Zoom.center
    /// The anchor in effect at the level on screen.
    var zoomAnchor: CGPoint { zoomAim.anchor(at: zoomLevel) }
    /// How much of a pull below the fitted size the window shows before springing back.
    private let overpull: CGFloat = 0.3
    private let maxCanvasZoom: CGFloat = 8
    /// How far a two-finger double tap zooms in. Preview picks a level from the content; one step
    /// of twice the fitted size is the same gesture without guessing at what is under the cursor.
    private let smartZoomFactor = 2.0
    /// How far Cmd+Plus and Cmd+Minus magnify, as a multiple of the level.
    private let keyZoomStep = 1.25
    /// A gesture's spring. Short enough to follow the fingers; long enough that the window still
    /// moves once per display refresh when events arrive unevenly.
    private let trackingSeconds = 0.1
    /// A step's spring: a key, a two-finger double tap, or a fit is a movement the eye follows.
    private let stepSeconds = 0.3
    /// The fit the window makes on its way out, before the card flies back. Shorter than a step:
    /// it is the start of the card leaving rather than a zoom the user asked for.
    private let fitToCloseSeconds = 0.2

    init() {
        toolbar.onTool = { [weak self] tool in self?.editor.setTool(tool) }
        toolbar.onDone = { [weak self] in self?.editor.done() }
        toolbar.onSend = { [weak self] destination in
            guard let self else { return }
            sendingTo = destination
            editor.send()
        }
        editor.onTool = { [weak self] tool in self?.toolbar.model.tool = tool }
        editor.onHandOver = { [weak self] drawing in self?.onDrawing?(drawing, "saved") }
        editor.onClose = { [weak self] in self?.cancel() }
        editor.onDone = { [weak self] drawing in
            guard let self, let shot = current else { return }
            onFinished?(shot, drawing)
        }
        editor.onSend = { [weak self] drawing in
            guard let self, let shot = current, let destination = sendingTo else { return }
            sendingTo = nil
            onSend?(shot, drawing, destination)
        }
        editor.onCopyDrawing = { [weak self] drawing in
            guard let self, let shot = current else { return }
            onCopyDrawing?(shot, drawing)
        }
        editor.onToast = { [weak self] words in self?.toast.show(words) }
        editor.onZoom = { [weak self] request in self?.zoom(request) }
        editor.onZoomGesture = { [weak self] event in self?.zoomGesture(event) }
    }

    /// Sizes the window to `frame`, opens the image in the editor, and takes the keys, so a key
    /// pressed during the flight already reaches the editor and Esc turns the card around. The
    /// window is ordered in invisible until `show`, and the window server passes every press through
    /// a window it draws nothing of. `room` is the rect the frame may grow within: the visible
    /// screen, less any strip its owner keeps for itself.
    func prepare(_ shot: Screenshot, in frame: NSRect, room: NSRect) {
        let started = CACurrentMediaTime()
        current = shot
        let win = window ?? makeWindow()
        fittedFrame = frame
        self.room = room
        zoomTarget = 1
        zoomAim = .fitted
        zoomPan = .centered
        zoomCenter = Zoom.center
        canvasZoom = Zoom.none
        zoomTween.set(1)
        place(win, frame: frame)
        applyCornerRadius()
        toolbar.place(below: frame, gap: Settings.shared.data.ui.annotationToolbarGap)
        win.alphaValue = 0
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        open(shot, started: started)
    }

    /// Opens the drawing with the screenshot's decode at the screen's size: the one a hovered card's
    /// flight already asked for when there is one, else decoded off the main thread and handed to
    /// the editor when it is ready. The drawing opens at once either way, so the keys work from here.
    private func open(_ shot: Screenshot, started: CFTimeInterval) {
        let key = shot.url.path, name = shot.url.lastPathComponent
        openGeneration += 1
        let generation = openGeneration
        guard let pixels = PixelSize(imageAt: shot.url) else {
            Log.write("[annotate] error \(CommandError.unreadableImage.rawValue) \(name)")
            cancel()
            return
        }
        let screen = zoomScreen ?? NSScreen.main ?? NSScreen.screens[0]
        // A new drawing takes the point scale of the screen the annotator opens on (spec, Decision 8).
        let pointScale = min(max(screen.backingScaleFactor, Drawing.pointScales.lowerBound), Drawing.pointScales.upperBound)
        let drawing = storedDrawing?(shot.url, pixels) ?? Drawing(key: key, pixels: pixels, pointScale: pointScale, marks: [])
        let maxPixel = Thumbnailer.screenPixels(on: screen)
        let decoded = Thumbnailer.cached(at: shot.url, maxPixel: maxPixel).flatMap(Self.cgImage)
        colorSample = nil
        let ui = Settings.shared.data.ui
        textStyle = ui.textStyle
        // Read here and captured: the pick runs inside the core's own reduce, where the editor's core
        // cannot be read.
        let scale = drawing.pointScale
        editor.open(drawing, image: decoded, picture: container?.bounds ?? .zero, style: textStyle, metrics: ui.editorMetrics,
                    arrowhead: ui.arrowhead, pickColor: { [weak self] mark in
                        guard let self, let sample = colorSample, sample.key == key else { return nil }
                        return sample.sample.pick(for: mark, pointScale: scale, style: textStyle)
                    })
        if decoded != nil { loaded(key, started: started) }
        else {
            Thumbnailer.load(at: shot.url, maxPixel: maxPixel) { [weak self] image in
                guard let self, openGeneration == generation, current?.url.path == key else { return }
                guard let cg = image.flatMap(Self.cgImage) else {
                    Log.write("[annotate] error \(CommandError.unreadableImage.rawValue) \(name)")
                    cancel()
                    return
                }
                editor.setImage(cg)
                loaded(key, started: started)
            }
        }
        let url = shot.url
        DispatchQueue.global(qos: .userInitiated).async {
            let sample = ColorSample(imageAt: url)
            DispatchQueue.main.async { MainActor.assumeIsolated { [weak self] in
                guard let self, let sample, openGeneration == generation, current?.url.path == key else { return }
                colorSample = (key, sample)
                editor.colorSampleArrived()
            } }
        }
    }

    private func loaded(_ key: String, started: CFTimeInterval) {
        Log.write("[annotate] loaded \(Int((CACurrentMediaTime() - started) * 1000))ms \((key as NSString).lastPathComponent)")
        onLoaded?(key)
    }

    private static func cgImage(_ image: NSImage) -> CGImage? {
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private func place(_ win: NSWindow, frame: NSRect) {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main ?? NSScreen.screens[0]
        zoomScreen = screen
        if win.frame != screen.visibleFrame { win.setFrame(screen.visibleFrame, display: false) }
        moveFrame(to: frame)
    }

    /// The one place the frame's rect is set: the frame view, the clip, the shadow's path and the
    /// editor inside it all take it from here, in the same tick, so nothing can be a frame behind.
    /// `frameOnScreen` reads the result back for anyone who needs the rect.
    private func moveFrame(to frame: NSRect) {
        guard let win = window, let frameView, let container else { return }
        frameView.frame = NSRect(x: frame.minX - win.frame.minX, y: frame.minY - win.frame.minY, width: frame.width, height: frame.height)
        container.frame = frameView.bounds
        let r = Settings.shared.data.ui.annotationCornerRadius
        frameView.layer?.shadowPath = CGPath(roundedRect: frameView.bounds, cornerWidth: r, cornerHeight: r, transform: nil)
        editor.setSize(container.bounds.size, picture: pictureRect)
        onFrame?(frame)
    }

    /// Where the whole picture sits in the editor: the frame magnified by `canvasZoom` and slid so
    /// that the part of the image `zoomCenter` names fills it. In the editor's own coordinates,
    /// which run down from the top.
    private var pictureRect: CGRect {
        guard let bounds = container?.bounds else { return .zero }
        let up = Zoom.picture(in: bounds, camera: canvasZoom, center: zoomCenter)
        return CGRect(x: up.minX, y: bounds.height - up.maxY, width: up.width, height: up.height)
    }

    /// The visible frame in screen coordinates.
    var frameOnScreen: NSRect? {
        guard let win = window, let frameView else { return nil }
        return win.convertToScreen(frameView.frame)
    }

    // MARK: Zoom

    /// What asked for a zoom: the fingers on a trackpad, or a key, a two-finger double tap, or a fit.
    enum ZoomInput { case gesture, step }

    /// The editor's zoom keys and its double-click on empty space. Only once the window is up: a
    /// zoom during the flight would move a frame the flight is still landing on.
    private func zoom(_ request: EditorCore.ZoomRequest) {
        guard window?.isVisible == true, window?.alphaValue == 1 else { return }
        switch request {
        case .zoomIn: zoom(by: keyZoomStep, at: nil, as: .step)
        case .zoomOut: zoom(by: 1 / keyZoomStep, at: nil, as: .step)
        case .fit: zoom(by: nil, at: nil, as: .step)
        case .smart(let point):
            smartZoom(at: cursorFraction(editor.convert(editor.viewPoint(forImagePoint: point), to: nil)))
        }
    }

    /// A pinch, a scroll or a two-finger double tap over the editor. Cmd or ctrl on a scroll zooms,
    /// as the pinch does; a plain scroll moves the part of a magnified picture in view.
    private func zoomGesture(_ event: NSEvent) {
        switch event.type {
        case .magnify: pinch(event.magnification, phase: event.phase, at: event.locationInWindow)
        case .smartMagnify: smartZoom(at: cursorFraction(event.locationInWindow))
        case .scrollWheel:
            if event.modifierFlags.intersection([.command, .control]).isEmpty { pan(event) } else { wheel(event) }
        default: break
        }
    }

    /// Zoom in grows each side of the window until that side fills the room, then magnifies the
    /// image past it. Zoom out reverses that and stops at the fitted size: pulling further shrinks
    /// the window a little and it springs back once the gesture ends. The toolbar stays where it is.
    ///
    /// `factor` multiplies the zoom level; nil asks for the fitted size. `cursor` is the point to
    /// keep in place, a fraction of the window with y from the top; nil means its middle, which is
    /// where a key zooms. Both phases honor it: the window grows away from it, and past that the
    /// picture is magnified about it.
    func zoom(by factor: Double?, at cursor: CGPoint?, as input: ZoomInput) {
        guard window != nil, fittedFrame.width > 0 else { return }
        let cursor = cursor.map(Zoom.clamped) ?? Zoom.center
        let target: CGFloat
        if let factor, factor.isFinite, factor > 0 {
            // Only a hand pulls below the fit: a key or a mouse wheel's notch stops at it, as it
            // does in Preview, since there is no gesture to let go of.
            let floor = input == .gesture ? minLevel : 1
            target = min(maxLevel, max(floor, zoomTarget * CGFloat(factor)))
        } else {
            target = 1
        }
        // An input that moves nothing (a notch out at the fit, cmd+0 at rest) is over here.
        guard target != zoomTarget || zoomTween.value != zoomTarget else { return }
        zoomTarget = target
        aim(at: cursor, to: zoomTarget)
        aimPan(at: cursor)
        zoomTween.animate(to: zoomTarget, duration: motionScaled(input == .gesture ? trackingSeconds : stepSeconds),
                          curve: "spring") { [weak self] in self?.arrived() }
    }

    /// Points the window's growth at `cursor`. The anchor it starts from is read off the frame on
    /// screen, so the step carries on from where the window is: a frame the screen edge has nudged
    /// does not carry that error forward, and a step aimed elsewhere mid-spring bends rather than
    /// stepping sideways. The anchor it ends at is the one the room allows, so the room gives way
    /// once, here, rather than the frame sliding part way through the spring. A window at rest
    /// has nothing to aim.
    private func aim(at cursor: CGPoint, to target: CGFloat) {
        guard let onScreen = frameOnScreen, target != zoomLevel else { return }
        zoomAim = Zoom.aim(at: cursor, of: onScreen, fitted: fittedFrame, window: split(target).window,
                           from: zoomLevel, to: target, within: room)
    }

    /// Points the magnification at `cursor`, from the part of the image that is visible now. Like
    /// `aim`, it starts from what is on screen, so a step aimed elsewhere mid-spring bends.
    ///
    /// A cursor near an edge of the picture is pulled onto it first (`ui.zoomEdgeBandPoints`,
    /// `ui.zoomEdgePull`): only the window's own edge holds the image's edge with it, so without
    /// the pull the corner the cursor is beside is cropped by the first bit of magnification. The
    /// band is measured in points of the frame the cursor is over, so its reach is the same on all
    /// four edges however wide the screenshot is.
    ///
    /// The frame's growth is not aimed and needs none of this, but "still growing" and "nothing
    /// cropped yet" are no longer the same state: each side reaches the room at its own level, so
    /// the picture is already cropped in the side that got there first while the other is still
    /// growing. The pull is applied in both directions on every input for that reason. A side that
    /// is still growing shows the whole image in that direction, so the pull has nothing to hold
    /// there and `Zoom.clamped(center:camera:)` pins it.
    private func aimPan(at cursor: CGPoint) {
        let ui = Settings.shared.data.ui
        let picture = frameOnScreen?.size ?? fittedFrame.size
        let aimed = Zoom.pulledToEdges(cursor, in: picture, band: ui.zoomEdgeBandPoints, pull: ui.zoomEdgePull)
        let camera = split(zoomLevel).camera
        zoomPan = ZoomPan(center: zoomPan.center(at: camera), camera: camera, cursor: aimed)
    }

    /// Zoom's springs are in code rather than in the tweaks, but the motion scale still shortens
    /// them, so `ui.motion: 0` and Reduce Motion land a zoom step at once.
    private func motionScaled(_ seconds: Double) -> Double { seconds * Settings.shared.motionScale }

    /// How a level divides between the frame's growth and the magnification inside it, per side.
    private func split(_ level: CGFloat) -> (window: CGSize, camera: CGSize) {
        Zoom.split(level: level, reach: reach, pull: overpull)
    }

    /// The rect the frame may grow within, as `prepare` was given it, so the strip the recent stack
    /// keeps for itself reaches both how far the window may grow and where the frame ends up.
    private var room = NSRect.zero

    /// How far each side of the window may grow: to the whole of that rect, past the fitted inset
    /// and the toolbar's room.
    private var reach: CGSize { Zoom.reach(fitted: fittedFrame, within: room) }
    /// The level stops where the side that fills the room first has been magnified `maxCanvasZoom`
    /// past it. That side is the one magnified most, so this is the cap on the whole picture.
    private var maxLevel: CGFloat { min(reach.width, reach.height) * maxCanvasZoom }
    /// How far a gesture may pull below the fitted size before the level stops following it.
    private let minLevel: CGFloat = 0.5

    /// One tick. The frame's rect and the picture inside it both come from this level: each side of
    /// the frame grows until it can grow no further and the magnification takes the rest. Both are
    /// set here, in one run loop turn, so they reach the window server in one Core Animation commit.
    private func applyZoom(_ level: CGFloat) {
        guard window != nil, fittedFrame.width > 0 else { return }
        zoomLevel = level
        let step = split(level)
        canvasZoom = step.camera
        zoomCenter = zoomPan.center(at: step.camera)
        // Kept on screen: a frame grown to the screen's height slides rather than clips.
        moveFrame(to: Zoom.frame(fitted: fittedFrame, scale: step.window, anchor: zoomAim.anchor(at: level), within: room))
    }

    /// The spring has arrived. A pull below the fitted size lets go here.
    private func arrived() {
        if zoomTarget < 1 { zoom(by: nil, at: nil, as: .step) }
    }

    /// A trackpad pinch. It follows the fingers about the point they are over. The pull springs
    /// back the moment the fingers lift.
    private func pinch(_ magnification: CGFloat, phase: NSEvent.Phase, at locationInWindow: NSPoint) {
        switch phase {
        case .ended, .cancelled: release()
        default: zoom(by: Double(1 + magnification), at: cursorFraction(locationInWindow), as: .gesture)
        }
    }

    /// Cmd+wheel or ctrl+wheel. A trackpad's wheel is a gesture, and lifting the fingers releases
    /// the pull below the fit; momentum after the lift is ignored, as a pinch's end is, so the zoom
    /// stops where the hand did. A mouse wheel has no phases: each notch is a step, and it stops at
    /// the fit.
    private func wheel(_ event: NSEvent) {
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) { release(); return }
        guard event.momentumPhase.isEmpty else { return }
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * Self.wheelLinePoints
        guard dy != 0, dy.isFinite else { return }
        let cursor = cursorFraction(event.locationInWindow)
        zoom(by: exp(dy * Self.wheelZoomRate), at: cursor, as: event.phase.isEmpty ? .step : .gesture)
    }

    /// A plain scroll over a picture magnified past its frame moves the part in view, with the
    /// fingers, as Preview does. At the fitted size, or on a side that is still growing, there is
    /// nothing hidden to bring into view.
    private func pan(_ event: NSEvent) {
        guard canvasZoom.width > 1 || canvasZoom.height > 1 else { return }
        let picture = pictureRect
        guard picture.width > 0, picture.height > 0 else { return }
        let line: CGFloat = event.hasPreciseScrollingDeltas ? 1 : Self.wheelLinePoints
        let dx = event.scrollingDeltaX * line, dy = event.scrollingDeltaY * line
        guard dx.isFinite, dy.isFinite, dx != 0 || dy != 0 else { return }
        // The content follows the fingers, so the middle of what is in view moves the other way.
        let center = Zoom.clamped(center: CGPoint(x: zoomCenter.x - dx / picture.width, y: zoomCenter.y - dy / picture.height),
                                  camera: canvasZoom)
        zoomPan = ZoomPan(center: center, camera: canvasZoom, cursor: Zoom.center)
        zoomCenter = center
        editor.pictureRect = pictureRect
    }

    /// How much one point of wheel travel zooms: a factor of e to this per point, so 100 points
    /// of scroll is a zoom of e (2.7 times) in either direction.
    private static let wheelZoomRate = 0.01
    /// A line of a mouse wheel's notch in points, for wheels that report lines rather than points.
    private static let wheelLinePoints: CGFloat = 10

    /// The fingers lifted. A pull below the fitted size lets go now, rather than when the spring
    /// catches up with it.
    private func release() {
        guard zoomTarget < 1 else { return }
        zoom(by: nil, at: nil, as: .step)
    }

    /// A two-finger double tap on the trackpad, or a double-click with the select tool on empty
    /// space, as Preview and Safari use it: in on the point named, or back to the fitted size from
    /// anywhere above it. `cursor` is a fraction of the window; nil zooms about its middle.
    private func smartZoom(at cursor: CGPoint?) {
        guard window?.isVisible == true else { return }
        let zoomedIn = zoomTarget > 1.001
        zoom(by: zoomedIn ? nil : smartZoomFactor, at: zoomedIn ? nil : cursor, as: .step)
    }

    /// A point in the window's coordinates as a fraction of the visible frame, x from the left and
    /// y from the top.
    private func cursorFraction(_ locationInWindow: NSPoint) -> CGPoint? {
        guard let frameView, frameView.bounds.width > 0, frameView.bounds.height > 0 else { return nil }
        let p = frameView.convert(locationInWindow, from: nil)
        return Zoom.clamped(CGPoint(x: p.x / frameView.bounds.width, y: 1 - p.y / frameView.bounds.height))
    }

    // MARK: Showing and hiding

    /// Puts the window up behind the flight image, which is past this frame on every side and so
    /// covers it — except for a shadow, which falls outside the frame it is cast from. The flight
    /// carries the shadow until it lands; `landed` hands it over. The keys came with `prepare`; the
    /// pointer comes here, so a drag lands on the editor as soon as the card looks still.
    func show() {
        guard let win = window, current != nil else { return }
        win.alphaValue = 1
        frameView?.layer?.shadowOpacity = 0
        win.makeKeyAndOrderFront(nil)
        if toolbar.panel.parent == nil { win.addChildWindow(toolbar.panel, ordered: .above) }
        toolbar.show()
        NSApp.activate(ignoringOtherApps: true)
        // A click outside this app's windows ends the session. The window was ordered in a line ago
        // and the window server does not report it under the cursor yet, so a press inside this
        // frame in the first few milliseconds would be read as outside and throw the session away
        // (measured: 3 of 4 presses landing 14 to 19 ms after this call). Nothing is ignored for
        // long enough to swallow a press that answers the window: it is not on screen until the
        // flight lands on it, and a hand cannot react inside `outsideClickSettling`.
        outsideClick.start(settling: Self.outsideClickSettling) { [weak self] in self?.cancel() }
    }

    /// How long the annotator ignores clicks after its window is ordered in. A race with the window
    /// server, not an animation: fixed, in code, and the motion scale does not touch it.
    private static let outsideClickSettling: TimeInterval = 0.15

    /// The flight is exactly on this frame and is going. The window draws the shadow from here on,
    /// in the same run loop turn the flight drops its own, so it is never drawn twice or missing.
    func landed() {
        frameView?.layer?.shadowOpacity = Float(TransitionLayer.Look.annotator(Settings.shared.data.ui).shadowOpacity)
    }

    /// Lets the prepared image go without a fit: the session ends before the window came up, so
    /// there is no zoom to undo. Its drawing is parked and stored like any other, since a key
    /// pressed during the flight may have changed it.
    func abandon() {
        guard current != nil else { return }
        outsideClick.stop()
        current = nil
        park()
        hideWindows()
    }

    /// Parks the drawing at once and stores it, then removes the window. While zoomed, the window
    /// springs back to the fitted frame first, so the card flies home from where it left. `then`
    /// runs once the window is gone. Called once per `prepare`, by the reducer.
    func hide(then completion: (() -> Void)? = nil) {
        outsideClick.stop()
        current = nil
        park()
        fitBeforeHide { [weak self] in
            self?.hideWindows()
            completion?()
        }
    }

    private func park() {
        sendingTo = nil
        if let drawing = editor.park() { onDrawing?(drawing, "parked") }
    }

    /// Springs the level back to the fitted size and answers once it is there, so the window the
    /// flight takes over from is the frame the flight starts at. Shorter than a fit the user asked
    /// for: this one is the start of the card leaving, not a zoom of its own. The deadline is there
    /// because a zoom arriving mid-fit takes the tween's completion with it, and the window still
    /// has to come down.
    private func fitBeforeHide(_ done: @escaping () -> Void) {
        guard window != nil, fittedFrame.width > 0, abs(zoomLevel - 1) > 0.001 || abs(zoomTarget - 1) > 0.001 else {
            done(); return
        }
        var answered = false
        let once = { if !answered { answered = true; done() } }
        zoomTarget = 1
        aim(at: Zoom.center, to: 1)
        aimPan(at: Zoom.center)
        zoomTween.animate(to: 1, duration: motionScaled(fitToCloseSeconds), curve: "spring", completion: once)
        DispatchQueue.main.asyncAfter(deadline: .now() + motionScaled(fitToCloseSeconds) + 0.3) { once() }
    }

    private func hideWindows() {
        // Nothing here is on screen any more: a spring still ticking would move a hidden frame.
        zoomTween.stop()
        toast.hide()
        // The panel stops being this window's child before the window goes, or AppKit would order
        // it out with its parent; `hideSoon` then takes it down only if no other image has asked
        // for it by the next turn of the run loop, and `show` makes it a child of the new window.
        if let win = window, toolbar.panel.parent === win { win.removeChildWindow(toolbar.panel) }
        toolbar.hideSoon()
        window?.orderOut(nil)
        // The window is out of sight, so the screenshot and the marks' layers are let go.
        editor.clear()
        colorSample = nil
    }

    private func makeWindow() -> AnnotationWindow {
        let win = AnnotationWindow(contentRect: .zero, styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false   // the frame view carries the shadow; the window itself is invisible
        win.level = AnnotationWindow.level
        win.isMovableByWindowBackground = false
        win.isReleasedWhenClosed = false
        win.animationBehavior = .none
        win.onCloseRequest = { [weak self] in self?.cancel() }
        let root = NSView()
        root.wantsLayer = true
        let frameView = NSView()
        frameView.wantsLayer = true
        // The same shadow the flight carries into this frame, so the handover shows nothing.
        // AppKit's y points up, so a shadow below the frame is a negative offset.
        let look = TransitionLayer.Look.annotator(Settings.shared.data.ui)
        frameView.layer?.shadowColor = NSColor.black.cgColor
        frameView.layer?.shadowOpacity = Float(look.shadowOpacity)
        frameView.layer?.shadowRadius = look.shadowRadius
        frameView.layer?.shadowOffset = CGSize(width: 0, height: -look.shadowY)
        let container = NSView()
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        // The window server gives a press to the window whose pixel under it is not clear, so this
        // opaque frame takes every press on it, over a screenshot's transparent pixels too, and the
        // clear rest of the window passes presses to the app behind, where `OutsideClick` sees them.
        // That holds only while `ignoresMouseEvents` is never set: once set either way, the window
        // takes or passes every press, whatever its pixels.
        container.layer?.backgroundColor = Config.matte.cgColor
        // Sized by hand, with its picture, in `moveFrame`: a size set without the picture would lay
        // the editor out at a size its picture does not fill.
        editor.autoresizingMask = []
        container.addSubview(editor)
        toast.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]
        container.addSubview(toast)
        frameView.addSubview(container)
        root.addSubview(frameView)
        win.contentView = root
        self.frameView = frameView
        self.container = container
        window = win
        return win
    }

    /// The window's corner and ring match a card's, so the flight from the stack ends on a shape that looks the same.
    private func applyCornerRadius() {
        let ui = Settings.shared.data.ui
        container?.layer?.cornerRadius = ui.annotationCornerRadius
        container?.layer?.cornerCurve = .continuous
        container?.layer?.borderWidth = ui.cardBorderWidth
        container?.layer?.borderColor = NSColor.white.withAlphaComponent(ui.cardBorderOpacity).cgColor
    }

    /// The image in the editor, by path, or nil between sessions. A send compares its own answer
    /// with this, so a rendering that lands after a swap closes nothing.
    var currentKey: String? { current?.url.path }

    /// The drawing open for `url` as the editor would hand it over now, or nil when that screenshot
    /// is not open.
    func openDrawing(of url: URL) -> Drawing? {
        guard editor.core.isOpen, editor.core.drawing.key == url.path else { return nil }
        return editor.core.drawingForHost
    }

    /// A short message over the picture, where the editor's own confirmations appear.
    func showToast(_ words: String) { toast.show(words) }

    /// The tweaks changed: the open editor takes their text style, sizes and arrowhead at once.
    func applyTweaks() {
        let ui = Settings.shared.data.ui
        textStyle = ui.textStyle
        editor.applyTweaks(style: textStyle, metrics: ui.editorMetrics, arrowhead: ui.arrowhead)
    }

    /// What the Send menu offers for the image that is opening, and the session a reply belongs
    /// back to. Read once per image: the list comes from subprocesses, and a menu that re-read it
    /// on every click would stall the bar.
    func setDestinations(_ list: [AgentDestination], replyTo: AgentDestination?) {
        toolbar.model.destinations = list
        toolbar.model.replyTo = replyTo
    }

    /// True while a send is rendering or submitting; the button says so and takes no second click.
    var sending: Bool {
        get { toolbar.model.sending }
        set { toolbar.model.sending = newValue }
    }

    /// Ends the session as Esc would. `open vignette://cancel`. False when nothing was open.
    @discardableResult
    func cancelForDebug() -> Bool {
        guard current != nil else { return false }
        cancel()
        return true
    }

    private func cancel() {
        guard current != nil else { return }
        Log.write("[annotate] cancelled")
        onClosed?()
    }

    /// The drawing in the editor, stored before the app quits. The editor parks for it.
    func storeForQuit() {
        guard current != nil else { return }
        park()
    }

    var stateJSON: [String: Any] {
        [
            "current": current?.url.path as Any,
            "windowVisible": window?.isVisible ?? false,
            "key": window?.isKeyWindow ?? false,
            "zoom": [zoomWindow.width, zoomWindow.height],
            "zoomLevel": zoomLevel,
            "canvasZoom": [canvasZoom.width, canvasZoom.height],
            "zoomAnchor": [zoomAnchor.x, zoomAnchor.y],
            "zoomCenter": [zoomCenter.x, zoomCenter.y],
            "room": StateReport.topLeft(room, primaryHeight: StateReport.primaryHeight),
            "frame": frameOnScreen.map { StateReport.topLeft($0, primaryHeight: StateReport.primaryHeight) } as Any,
            "toolbar": (toolbar.panel.isVisible ? StateReport.topLeft(toolbar.panel.frame, primaryHeight: StateReport.primaryHeight) : nil) as Any,
            "tool": toolbar.model.tool?.rawValue as Any,
        ]
    }
}

/// A short confirmation from the editor, such as "Copied drawing": a small dark capsule at the
/// bottom of the frame, over the picture, where the eye already is and nothing in the toolbar moves
/// for it. It takes no clicks.
@MainActor
private final class AnnotatorToast: NSVisualEffectView {
    private let label = NSTextField(labelWithString: "")
    private var generation = 0
    /// Its distance from the bottom of the frame, and its padding around the words.
    private static let inset: CGFloat = 14
    private static let padding = CGSize(width: 12, height: 5)

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        alphaValue = 0
        isHidden = true
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ words: String) {
        guard let container = superview else { return }
        generation += 1
        let gen = generation
        label.stringValue = words
        label.sizeToFit()
        let size = CGSize(width: ceil(label.frame.width) + Self.padding.width * 2, height: ceil(label.frame.height) + Self.padding.height * 2)
        frame = CGRect(x: ((container.bounds.width - size.width) / 2).rounded(), y: Self.inset, width: size.width, height: size.height)
        label.frame.origin = CGPoint(x: Self.padding.width, y: Self.padding.height)
        layer?.cornerRadius = size.height / 2
        isHidden = false
        let ui = Settings.shared.motionUI
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15 * Settings.shared.motionScale
            animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + ui.toastSeconds) { [weak self] in
            guard let self, generation == gen else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2 * Settings.shared.motionScale
                self.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.generation == gen else { return }
                    self.isHidden = true
                }
            })
        }
    }

    /// Gone at once, with the window.
    func hide() {
        generation += 1
        alphaValue = 0
        isHidden = true
    }
}

/// Borderless windows refuse key status by default; the editor needs it for typing and shortcuts.
final class AnnotationWindow: NSWindow {
    /// Above the stack's backdrop blur (19) and the Dock (20), so the blur never paints over the
    /// image, and under the stack and the flight layer (`.statusBar`, 25), so a flight image still
    /// covers this window and the stack draws over its shadow. The toolbar shares it.
    static let level = NSWindow.Level(rawValue: 21)
    var onCloseRequest: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func performClose(_ sender: Any?) { onCloseRequest?() }
}
