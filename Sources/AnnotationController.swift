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
    /// The window server gives this window the presses on its frame now. Once per `show`, with the key.
    var onTakesEvents: ((String) -> Void)?
    /// A drawing to store: the editor handed it over after a change, or it was parked. `reason`
    /// names which in the log.
    var onDrawing: ((Drawing, _ reason: String) -> Void)?
    /// The stored drawing for a screenshot whose size as displayed is the given one, if any.
    var storedDrawing: ((URL, PixelSize) -> Drawing?)?
    /// The frame moved: it was placed, a zoom stepped it, or it came home on the way out. The
    /// stack follows it, so it narrows as the frame grows towards it.
    var onFrame: ((NSRect) -> Void)?
    /// Send or Reply handed the drawing to this agent session, with the message typed in the bar, if any.
    var onSend: ((Screenshot, Drawing, AgentDestination, String?) -> Void)?
    /// Cmd+C with nothing selected: this drawing's rendering goes on the clipboard.
    var onCopyDrawing: ((Screenshot, Drawing) -> Void)?

    /// The editor, the whole content of the frame. The state report reads its core.
    let editor = EditorView()
    private let toolbar = AnnotatorToolbar()
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
    /// Asks the window server, from `show` until it answers, whether a press on the frame reaches this window.
    private var eventProbe: Timer?
    /// Takes the frame and then the window down behind the flight home (`hideWindows`).
    private let removal = Removal()
    /// Counts `open`s, so a decode or a send's rendering only lands on the open that asked
    /// for it: the same file can be closed and opened again while the first is still on its way.
    private var openGeneration = 0
    /// Where the toolbar's Send or Reply goes once the editor hands over the drawing. A key that
    /// sends goes where the bar's filled button would.
    private var sendingTo: AgentDestination?
    /// The text style of the tweaks.
    private var textStyle = TextStyle.standard

    /// Room the annotator needs below its window: the toolbar and its gap.
    var spaceBelow: CGFloat { AnnotatorToolbar.height + Settings.shared.data.ui.annotationToolbarGap }

    /// The zoom's rules and where they put the frame and the picture. The spring is `zoomTween`.
    private var zoom = AnnotatorZoom()
    private lazy var zoomTween = Tween(initial: 1) { [weak self] level in self?.run(.tick(level)) }

    init() {
        toolbar.onTool = { [weak self] tool in self?.editor.setTool(tool) }
        toolbar.onDone = { [weak self] in self?.editor.done() }
        toolbar.onMessageEnd = { [weak self] in self?.window?.makeKey() }
        toolbar.onSend = { [weak self] destination in
            guard let self else { return }
            sendingTo = destination
            editor.send()
        }
        editor.onTool = { [weak self] tool in self?.toolbar.model.tool = tool }
        editor.onHandOver = { [weak self] drawing in self?.onDrawing?(drawing, "saved") }
        editor.onClose = { [weak self] in self?.cancel() }
        // One Tab order: the marks, then the toolbar's controls, then the marks again.
        editor.onLeaveCanvas = { [weak self] backward in self?.toolbar.enter(backward: backward) }
        toolbar.onLeave = { [weak self] backward in self?.editor.enterCanvas(backward: backward) ?? false }
        editor.onFocusMessage = { [weak self] in self?.toolbar.focusMessage() }
        editor.onPress = { [weak self] in self?.toolbar.clearFocus() }
        editor.takesKey = { [weak self] key, modifiers in
            guard let toolbar = self?.toolbar, toolbar.model.focus != nil, modifiers.isSubset(of: .shift) else { return false }
            switch key {
            case .tab: toolbar.move(backward: modifiers.contains(.shift))
            case .character(" ") where modifiers.isEmpty: toolbar.activate()
            default: return false
            }
            return true
        }
        editor.onDone = { [weak self] drawing in
            guard let self, let shot = current else { return }
            onFinished?(shot, drawing)
        }
        editor.onSend = { [weak self] drawing in
            guard let self, let shot = current, let destination = sendingTo ?? toolbar.model.offer.destination else { return }
            sendingTo = nil
            onSend?(shot, drawing, destination, toolbar.model.sentMessage)
        }
        editor.onCopyDrawing = { [weak self] drawing in
            guard let self, let shot = current else { return }
            onCopyDrawing?(shot, drawing)
        }
        editor.onZoom = { [weak self] request in self?.zoomRequested(request) }
        editor.onZoomGesture = { [weak self] event in self?.zoomGesture(event) }
        editor.onReveal = { [weak self] rect in
            guard let self else { return }
            let pixels = editor.core.drawing.pixels
            run(.reveal(rect, image: CGSize(width: pixels.width, height: pixels.height)))
        }
    }

    /// Sizes the window to `frame`, opens the image in the editor, and takes the keys, so a key
    /// pressed during the flight already reaches the editor and Esc turns the card around. The
    /// window is ordered in invisible until `show`, and the window server passes every press through
    /// a window it draws nothing of. `room` is the rect the frame may grow within: the visible
    /// screen, less any strip its owner keeps for itself.
    func prepare(_ shot: Screenshot, in frame: NSRect, room: NSRect) {
        let started = CACurrentMediaTime()
        current = shot
        // A send still rendering belongs to the session before this one, which its answer will find gone.
        toolbar.model.resetSend()
        // The window and the editor are this image's now, so the last image's removal must not take them.
        removal.cancel()
        let win = window ?? makeWindow()
        frameView?.isHidden = false
        zoom.edge = Self.edgePull(Settings.shared.data.ui)
        run(.prepare(fitted: frame, room: room))
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
        // A new drawing takes the point scale of the screen the annotator opens on: Decision 8 in
        // docs/editor.md.
        let pointScale = min(max(screen.backingScaleFactor, Drawing.pointScales.lowerBound), Drawing.pointScales.upperBound)
        let drawing = storedDrawing?(shot.url, pixels) ?? Drawing(key: key, pixels: pixels, pointScale: pointScale, marks: [])
        let maxPixel = Thumbnailer.screenPixels(on: screen), space = screen.colorSpace?.cgColorSpace
        let decoded = Thumbnailer.cached(at: shot.url, maxPixel: maxPixel, space: space).flatMap(Self.cgImage)
        let ui = Settings.shared.data.ui
        textStyle = ui.textStyle
        editor.open(drawing, image: decoded, picture: container?.bounds ?? .zero, style: textStyle, metrics: ui.editorMetrics,
                    markStyle: ui.markStyle)
        editor.noteSettleDuration = Settings.shared.motionUI.noteSettleDuration
        if decoded != nil { loaded(key, started: started) }
        else {
            Thumbnailer.load(at: shot.url, maxPixel: maxPixel, space: space) { [weak self] image in
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
        moveFrame(to: frame, picture: zoom.picture)
    }

    /// The one place the frame's rect is set: the frame view, the clip, the shadow's path and the
    /// editor inside it all take it from here, in the same tick, so nothing can be a frame behind.
    /// `frameOnScreen` reads the result back for anyone who needs the rect. `picture` is where the
    /// whole picture sits in the editor, in its coordinates, which run down from the top.
    private func moveFrame(to frame: NSRect, picture: CGRect) {
        guard let win = window, let frameView, let container else { return }
        frameView.frame = NSRect(x: frame.minX - win.frame.minX, y: frame.minY - win.frame.minY, width: frame.width, height: frame.height)
        container.frame = frameView.bounds
        let r = Settings.shared.data.ui.annotationCornerRadius
        frameView.layer?.shadowPath = CGPath(roundedRect: frameView.bounds, cornerWidth: r, cornerHeight: r, transform: nil)
        editor.setSize(container.bounds.size, picture: picture)
        onFrame?(frame)
    }

    /// The visible frame in screen coordinates.
    var frameOnScreen: NSRect? {
        guard let win = window, let frameView else { return nil }
        return win.convertToScreen(frameView.frame)
    }

    // MARK: Zoom

    /// Hands `input` to the zoom and does what it answers. A spring that lands at once, at motion 0,
    /// ticks and arrives inside `animate`, after the zoom has answered.
    private func run(_ input: AnnotatorZoom.Input) {
        switch zoom.reduce(input) {
        case .spring(let level, let seconds)?:
            zoomTween.animate(to: level, duration: motionScaled(seconds)) { [weak self] in self?.run(.arrived) }
        case .place(let frame, let picture)?:
            guard window != nil else { return }
            moveFrame(to: frame, picture: picture)
        case .movePicture(let picture)?:
            editor.pictureRect = picture
        case nil:
            break
        }
    }

    /// The editor's zoom keys and its double-click on empty space.
    private func zoomRequested(_ request: EditorCore.ZoomRequest) {
        switch request {
        case .zoomIn: run(.zoomIn)
        case .zoomOut: run(.zoomOut)
        case .fit: run(.fit)
        case .smart(let point):
            run(.smart(at: cursorFraction(editor.convert(editor.viewPoint(forImagePoint: point), to: nil))))
        }
    }

    /// A pinch, a scroll or a two-finger double tap over the editor. Cmd or ctrl on a scroll zooms,
    /// as the pinch does; a plain scroll moves the part of a magnified picture in view. A trackpad's
    /// scroll is a gesture, and lifting the fingers lets go of a pull below the fit; momentum after
    /// the lift is ignored, as a pinch's end is, so the zoom stops where the hand did. A mouse wheel
    /// has no phases, and each notch is a step.
    private func zoomGesture(_ event: NSEvent) {
        switch event.type {
        case .magnify:
            if event.phase == .ended || event.phase == .cancelled { run(.lift); return }
            run(.pinch(by: event.magnification, at: cursorFraction(event.locationInWindow)))
        case .smartMagnify:
            run(.smart(at: cursorFraction(event.locationInWindow)))
        case .scrollWheel:
            let line: CGFloat = event.hasPreciseScrollingDeltas ? 1 : Self.wheelLinePoints
            if event.modifierFlags.intersection([.command, .control]).isEmpty {
                run(.pan(by: CGVector(dx: event.scrollingDeltaX * line, dy: event.scrollingDeltaY * line)))
                return
            }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) { run(.lift); return }
            guard event.momentumPhase.isEmpty else { return }
            run(.wheel(points: event.scrollingDeltaY * line, at: cursorFraction(event.locationInWindow),
                       fingers: !event.phase.isEmpty))
        default:
            break
        }
    }

    /// Zoom's springs are in code rather than in the tweaks, but the motion scale still shortens
    /// them, so `ui.motion: 0` and Reduce Motion land a zoom step at once.
    private func motionScaled(_ seconds: Double) -> Double { seconds * Settings.shared.motionScale }

    private static func edgePull(_ ui: UITweaks) -> AnnotatorZoom.EdgePull {
        AnnotatorZoom.EdgePull(band: ui.zoomEdgeBandPoints, pull: ui.zoomEdgePull)
    }

    /// A line of a mouse wheel's notch in points, for wheels that report lines rather than points.
    private static let wheelLinePoints: CGFloat = 10

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
        toolbar.show()
        NSApp.activate(ignoringOtherApps: true)
        // A click outside this app's windows ends the session. The window was ordered in a line ago
        // and the window server does not report it under the cursor yet, so a press inside this
        // frame in the first few milliseconds would be read as outside and throw the session away
        // (measured: 3 of 4 presses landing 14 to 19 ms after this call). Nothing is ignored for
        // long enough to swallow a press that answers the window: it is not on screen until the
        // flight lands on it, and a hand cannot react inside `outsideClickSettling`.
        outsideClick.start(settling: Self.outsideClickSettling) { [weak self] in self?.cancel() }
        probeEvents()
    }

    /// Finds the moment the window server starts giving this window the presses on its frame. The
    /// window is ordered in at alpha 0 in `prepare`, which passes every press through, and alpha 1
    /// reaches the window server 6 to 25 ms after `show` sets it (measured 2026-09-23). Nothing
    /// announces it: no occlusion change arrives with the alpha. So this asks, every millisecond,
    /// which window a press at the frame's centre would reach.
    private func probeEvents() {
        eventProbe?.invalidate()
        guard let win = window, let key = current?.url.path else { return }
        let started = CACurrentMediaTime()
        let timer = Timer(timeInterval: 0.001, repeats: true) { [weak self] timer in
            let answered = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.current?.url.path == key else { return true }
                let elapsed = CACurrentMediaTime() - started
                let reached = self.pressReaches(win)
                guard reached || elapsed > Self.eventProbeDeadline else { return false }
                self.eventProbe = nil
                Log.write("[annotate] takes events after=\(Int((elapsed * 1000).rounded()))ms reached=\(reached)")
                self.onTakesEvents?(key)
                return true
            }
            if answered { timer.invalidate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        eventProbe = timer
    }

    /// How long `probeEvents` asks before it hands over anyway: presses handed over reach the editor
    /// whatever the window server says, and a flight kept over the frame for want of an answer
    /// would hide what the editor draws.
    private static let eventProbeDeadline: TimeInterval = 0.5

    /// Whether a press at the frame's centre reaches `win`. This app's windows above it are looked
    /// through: the flight layer covers the frame until the flight has settled.
    private func pressReaches(_ win: NSWindow) -> Bool {
        guard let frameView else { return false }
        let point = win.convertPoint(toScreen: NSPoint(x: frameView.frame.midX, y: frameView.frame.midY))
        var below = 0
        for _ in 0..<8 {
            let number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: below)
            if number == win.windowNumber { return true }
            guard let above = NSApp.window(withWindowNumber: number), above.level > win.level else { return false }
            below = number
        }
        return false
    }

    /// A press begun on the card flying into this editor, which the flight layer took. Only for the
    /// image open now: a press held for another has nowhere to go.
    func take(_ event: FlightPress.Event, for key: String) {
        guard current?.url.path == key else { return }
        editor.take(event)
    }

    /// How long the annotator ignores clicks after its window is ordered in. A race with the window
    /// server, not an animation: fixed, in code, and the motion scale does not touch it.
    private static let outsideClickSettling: TimeInterval = 0.15

    /// The flight is exactly on this frame and is going. The window draws the shadow from here on,
    /// in the same run loop turn the flight drops its own, so it is never drawn twice or missing.
    func landed() {
        run(.landed)
        frameView?.layer?.shadowOpacity = Float(TransitionLayer.Look.annotator(Settings.shared.data.ui).shadowOpacity)
    }

    /// Lets the prepared image go without a fit: the session ends before the window came up, so
    /// there is no zoom to undo. Its drawing is parked and stored like any other, since a key
    /// pressed during the flight may have changed it.
    func abandon() {
        guard current != nil else { return }
        // Nothing zooms before the landing, so there is no fit to wait for.
        _ = zoom.reduce(.close)
        outsideClick.stop()
        stopProbe()
        current = nil
        park()
        hideWindows()
    }

    /// Parks the drawing at once and stores it, then removes the window. While zoomed, the window
    /// springs back to the fitted frame first, so the card flies home from where it left. `then`
    /// runs at the fitted frame, in the turn that starts the removal, so the flight home it starts
    /// covers the frame before it goes (`hideWindows`). Called once per `prepare`, by the reducer.
    func hide(then completion: (() -> Void)? = nil) {
        outsideClick.stop()
        stopProbe()
        current = nil
        park()
        fitBeforeHide { [weak self] in
            self?.hideWindows()
            completion?()
        }
    }

    private func stopProbe() {
        eventProbe?.invalidate()
        eventProbe = nil
    }

    private func park() {
        sendingTo = nil
        if let drawing = editor.park() { onDrawing?(drawing, "parked") }
    }

    /// Springs the level back to the fitted size and answers once it is there, so the window the
    /// flight takes over from is the frame the flight starts at. The deadline brings the window down
    /// even if the spring never reports arriving.
    private func fitBeforeHide(_ done: @escaping () -> Void) {
        guard case .spring(let level, let seconds)? = zoom.reduce(.close), window != nil else { done(); return }
        var answered = false
        let once = { if !answered { answered = true; done() } }
        zoomTween.animate(to: level, duration: motionScaled(seconds), completion: once)
        DispatchQueue.main.asyncAfter(deadline: .now() + motionScaled(seconds) + 0.3) { once() }
    }

    private func hideWindows() {
        // Nothing here is on screen any more: a spring still ticking would move a hidden frame.
        zoomTween.stop()
        // `hideSoon` takes the bar down only if no other image has asked for it by the next turn
        // of the run loop.
        toolbar.hideSoon()
        // The flight home is added at this frame in this turn, above this window, and starts moving
        // on the next. The window server takes a window down at once, and ordered out here the
        // window left the frame empty for 4 to 9 frames before the flight showed (measured). So the
        // frame is hidden in the commit that starts the flight moving, and the window goes once the
        // display has shown it. The flight casts the shadow from this turn, so it is never doubled.
        frameView?.layer?.shadowOpacity = 0
        removal.start(on: window?.screen, hide: { [weak self] in self?.frameView?.isHidden = true }) { [weak self] in
            guard let self else { return }
            window?.orderOut(nil)
            // The window is out of sight, so the screenshot and the marks' layers are let go.
            editor.clear()
        }
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

    /// The image in the editor, by path, or nil between sessions.
    var currentKey: String? { current?.url.path }

    /// The open the editor is in, or nil between sessions. A send compares its rendering's answer
    /// with this rather than the path: after Esc and a reopen of the same image, the path matches
    /// and the session does not.
    var session: Int? { current == nil ? nil : openGeneration }

    /// The tweaks changed: the open editor takes their text style, sizes and arrowhead at once.
    func applyTweaks() {
        let ui = Settings.shared.data.ui
        zoom.edge = Self.edgePull(ui)
        textStyle = ui.textStyle
        editor.applyTweaks(style: textStyle, metrics: ui.editorMetrics, markStyle: ui.markStyle)
        editor.noteSettleDuration = Settings.shared.motionUI.noteSettleDuration
    }

    /// A new image opened: `replyTo` is the session it came from, when it names one, and the list
    /// of sessions is on its way. Read once per image: the list comes from subprocesses, and a menu
    /// that re-read it on every click would stall the bar.
    func beginDestinations(replyTo: AgentDestination?) {
        toolbar.model.begin(replyTo: replyTo, carryingTarget: toolbar.model.shown)
        offerChanged()
    }

    /// Another client answered with its sessions; `complete` on the last.
    func destinationsAnswered(_ list: [AgentDestination], complete: Bool) {
        let before = toolbar.model.target?.id
        toolbar.model.answered(list, complete: complete)
        if let target = toolbar.model.target, target.id != before {
            Log.write("[send] target \(target.address.description) project=\(target.detail) focus=\(target.focus?.rawValue ?? "none")")
        }
        offerChanged()
    }

    /// Return and Cmd+Return do what the bar offers.
    private func offerChanged() {
        editor.finishes = toolbar.model.offer.finishes
    }

    /// True from Send's press until the bar leaves; the button shows the send and takes no second
    /// click. `prepare` resets it.
    var sending: Bool {
        get { toolbar.model.sending }
        set { toolbar.model.sending = newValue }
    }

    /// The send failed before its request was stored, so the drawing is still here: the button says
    /// so, with `reason` beside it, until the person moves on.
    func sendFailed(_ reason: String) { toolbar.model.sendFailed(reason) }

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
            "zoom": [zoom.window.width, zoom.window.height],
            "zoomLevel": zoom.level,
            "zoomPhase": zoom.phase.description,
            "canvasZoom": [zoom.camera.width, zoom.camera.height],
            "zoomAnchor": [zoom.anchor.x, zoom.anchor.y],
            "zoomCenter": [zoom.center.x, zoom.center.y],
            "room": StateReport.topLeft(zoom.room, primaryHeight: StateReport.primaryHeight),
            "frame": frameOnScreen.map { StateReport.topLeft($0, primaryHeight: StateReport.primaryHeight) } as Any,
            "toolbar": (toolbar.panel.isVisible ? StateReport.topLeft(toolbar.barFrame, primaryHeight: StateReport.primaryHeight) : nil) as Any,
            "toolbarFocus": toolbar.model.focus?.name as Any,
            "tool": toolbar.model.tool?.rawValue as Any,
            "offer": (current == nil ? nil : offerJSON) as Any,
        ]
    }

    /// What the bar offers, and where its filled button sends: the session's id, client, project
    /// and why it is the session you came from, never its title.
    private var offerJSON: [String: Any] {
        let offer = toolbar.model.offer
        var json: [String: Any] = ["listed": toolbar.model.listed]
        switch offer {
        case .copy: json["kind"] = "copy"
        case .send: json["kind"] = "send"
        case .reply: json["kind"] = "reply"
        }
        if let destination = offer.destination {
            json["session"] = destination.id
            json["client"] = destination.client.rawValue
            json["project"] = destination.detail
            json["focus"] = destination.focus?.rawValue as Any
        }
        return json
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
    /// Esc reaches the window only when no view took it, which means the editor was not the first
    /// responder. It still closes, as Esc does from the editor, and says what held the keys.
    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 53 else { return super.keyDown(with: event) }
        Log.write("[annotate] esc reached the window firstResponder=\(firstResponder.map { String(describing: type(of: $0)) } ?? "none")")
        onCloseRequest?()
    }
}

/// Takes the annotator's frame off screen behind the flight home. `hide` runs on the next turn of
/// the main queue, the one `TransitionLayer.fly` starts the flight moving in, so the two land in
/// one commit. `remove` runs a few display refreshes later, once the display has shown that commit.
@MainActor
private final class Removal: NSObject {
    /// The first refresh can come before the commit, and the render server draws a commit on the
    /// refresh after it arrives.
    private static let refreshes = 3
    private var generation = 0
    private var link: CADisplayLink?
    private var left = 0
    private var remove: (() -> Void)?

    func start(on screen: NSScreen?, hide: @escaping () -> Void, remove: @escaping () -> Void) {
        cancel()
        let started = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == started else { return }
            hide()
            guard let screen = screen ?? NSScreen.main else { remove(); return }
            self.remove = remove
            left = Self.refreshes
            let link = screen.displayLink(target: self, selector: #selector(refreshed))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    func cancel() {
        generation += 1
        link?.invalidate()
        link = nil
        remove = nil
    }

    @objc private func refreshed(_ link: CADisplayLink) {
        left -= 1
        guard left <= 0 else { return }
        let remove = remove
        cancel()
        remove?()
    }
}
