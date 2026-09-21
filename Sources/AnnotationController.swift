import AppKit
import WebKit

/// Hosts the tldraw editor in a WKWebView. Preloaded at launch so opening feels instant.
/// Lifecycle: `prepare` sizes the hidden window and loads the image, `show` reveals it once the
/// card transition has landed, `hide` removes it at once for a swap, and the page's cancel/done
/// messages end a session through `close`.
@MainActor
final class AnnotationController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    /// Done: the rendering, or nil when nothing was drawn.
    var onFinished: ((Screenshot, Data?) -> Void)?
    /// The page asks to end the session: Esc, click outside, Cmd+W, or Done. The owner decides what
    /// happens next and calls `hide` when it is time; nothing here hides on its own.
    var onClosed: (() -> Void)?
    /// The page has the image for this key on its canvas.
    var onLoaded: ((String) -> Void)?
    /// Something the user should see: a stale page, a page that never came up.
    var onProblem: ((String) -> Void)?
    /// Which files the server may serve; the app keeps it in step with the watch folder and `debug`.
    let fileAccess = LocalServer.FileAccess()
    /// The stored draft for a key, as JSON, to load with its image. The owner keeps the drafts.
    var draftSnapshot: ((String) -> Data?)?
    /// The page reported the current image's annotations; a nil snapshot means there are none.
    var onDraft: ((String, Any?) -> Void)?
    /// The page parked an image on hide: what to store, and a rendering when it changed.
    var onParked: ((String, ParkResult) -> Void)?
    /// A rendering of a screenshot with its draft, for the stack to show in place of the original.
    var onDraftPreview: ((String, Data) -> Void)?
    /// The editor page is up and can take calls. Also after a web content process restart.
    var onPageReady: (() -> Void)?
    /// The frame moved: it was placed, a zoom stepped it, or it came home on the way out. The
    /// stack follows it, so it narrows as the frame grows towards it.
    var onFrame: ((NSRect) -> Void)?
    /// The Send menu asked to hand the drawing on the canvas to this agent session.
    var onSend: ((AgentDestination) -> Void)?

    /// Nil when the bundle has no page or the server did not start; every call then no-ops.
    private var webView: WKWebView?
    private let toolbar = AnnotatorToolbar()
    private var server: LocalServer?
    private var window: AnnotationWindow?
    /// The window spans the screen's visible frame and stays put. The visible frame is `frameView`
    /// inside it (shadow) with `container` (clip, corner, ring, web view), so a zoom step moves the
    /// frame and the picture inside it in one layer commit: a window resize and a layer change do
    /// not land on the same display frame, and the image would drift from the frame between them.
    /// While a zoom moves, the picture is the native stand-in over the web view; see `StandIn`.
    private var frameView: NSView?
    private var container: NSView?
    private var zoomScreen: NSScreen?
    /// The shot the page holds, from `prepare` until `hide` parks it. Not the session: see AnnotatorTransition.
    private var current: Screenshot?
    private var pageReady = false
    private var pageFailed = false
    private var pendingCall: PageAPI?

    enum PageState { case unavailable, loading, ready }
    /// Whether the editor page can take a call: `loading` calls are queued one deep, `unavailable`
    /// means there is no page to wait for (bundle or server missing, or the load failed).
    var pageState: PageState {
        if pageReady { return .ready }
        if webView == nil || pageFailed { return .unavailable }
        return .loading
    }
    var port: UInt16 { server?.port ?? 0 }
    private let outsideClick = OutsideClick()
    /// Bumped when the web process restarts, so an answer from the old page is ignored.
    private var pageEpoch = 0
    /// The export waiting on the page, if any. Called exactly once: by the page's answer, the
    /// timeout, or a process restart, whichever comes first.
    private var pendingExport: (([String: Data], String?) -> Void)?
    /// The marks build waiting on the page, if any. One at a time, and called exactly once.
    private var pendingBuild: ((ParkResult?, String?) -> Void)?
    /// Set while Send is rendering the current drawing, so two clicks cannot send twice.
    private var pendingSnapshot: ((Data?, String?) -> Void)?
    /// The hide waiting on the page's park, so a process restart still hides the window.
    private var pendingHide: (() -> Void)?
    /// How long Copy Drawing waits for the page before giving up.
    static let exportTimeout: TimeInterval = 15

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
    /// The middle of the visible part of the image, as a fraction of it. The stand-in draws from
    /// this and the page is given it at rest, so the two show the same part of the image.
    private(set) var zoomCenter = Zoom.center
    /// The anchor in effect at the level on screen.
    var zoomAnchor: CGPoint { zoomAim.anchor(at: zoomLevel) }
    /// How much of a pull below the fitted size the window shows before springing back.
    private let overpull: CGFloat = 0.3
    private let maxCanvasZoom: CGFloat = 8
    /// How far a two-finger double tap zooms in. Preview picks a level from the content; one step
    /// of twice the fitted size is the same gesture without guessing at what is under the cursor.
    private let smartZoomFactor = 2.0
    /// A gesture's spring. Short enough to follow the fingers; long enough that the window still
    /// moves once per display refresh when the page's messages arrive unevenly, which they do:
    /// they cross a process boundary, so two can land in one refresh and none in the next.
    private let trackingSeconds = 0.1
    /// A step's spring: a key, a two-finger double tap, or a fit is a movement the eye follows.
    private let stepSeconds = 0.3
    /// The fit the window makes on its way out, before the card flies back. Shorter than a step:
    /// it is the start of the card leaving rather than a zoom the user asked for.
    private let fitToCloseSeconds = 0.2
    /// Set when the spring has arrived, so the page is handed the view once, on the next turn of
    /// the run loop, rather than inside a display link tick.
    private var pageLayoutPending = false
    /// What is on screen in place of the page while a zoom moves, and the hand-over that gives the
    /// picture back at rest. It owns its own outstanding page calls; see `StandInController`.
    private let standIn = StandInController()

    func preload() {
        _ = FocusReturn.shared
        toolbar.onTool = { [weak self] id in self?.call(.setTool(id)) }
        toolbar.onDone = { [weak self] in self?.call(.finish) }
        toolbar.onSend = { [weak self] destination in self?.onSend?(destination) }
        standIn.atRest = { [weak self] in self.map { $0.zoomTween.value == $0.zoomTarget } ?? false }
        standIn.windowVisible = { [weak self] in self?.window?.isVisible == true }
        guard let dist = Bundle.main.url(forResource: "dist", withExtension: nil) else {
            Log.write("[web] web/dist missing from bundle")
            return
        }
        let server = LocalServer(root: dist, access: fileAccess)
        do { try server.start() } catch { Log.write("LocalServer start failed: \(error)"); return }
        self.server = server
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "vignette")
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let webView = AnnotationWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        webView.navigationDelegate = self
        webView.onMagnify = { [weak self] magnification, phase, location in self?.pinch(magnification, phase: phase, at: location) }
        webView.onZoomWheel = { [weak self] event in self?.wheel(event) }
        webView.onSmartMagnify = { [weak self] location in
            guard let self else { return }
            smartZoom(at: cursorFraction(location))
        }
        webView.setValue(false, forKey: "drawsBackground")
        webView.load(URLRequest(url: server.indexURL))
        self.webView = webView
    }

    /// The web content process, for `kill` tests and memory checks. WKWebView only exposes it
    /// through a private accessor, so this is nil if that accessor disappears.
    var webProcessID: pid_t? {
        guard let webView, webView.responds(to: Selector(("_webProcessIdentifier"))) else { return nil }
        return (webView.value(forKey: "_webProcessIdentifier") as? NSNumber)?.int32Value
    }

    /// Sizes the window to `frame`, loads the image, and takes the keys, so the page has rendered
    /// by `show` and a key pressed during the flight already reaches it. The window is ordered in
    /// invisible and ignoring the mouse until `show`: a press still lands on the flight image, whose
    /// picture is not where the page is yet. `room` is the rect the frame may grow within: the
    /// visible screen, less any strip its owner keeps for itself.
    func prepare(_ shot: Screenshot, in frame: NSRect, room: NSRect) {
        guard let webView else { return }
        current = shot
        let win = window ?? makeWindow(webView)
        fittedFrame = frame
        self.room = room
        zoomTarget = 1
        zoomAim = .fitted
        zoomPan = .centered
        zoomCenter = Zoom.center
        canvasZoom = Zoom.none
        zoomTween.set(1)
        place(win, frame: frame)
        standIn.prepare(for: shot.url, maxPixel: standInPixels)
        placeWebView()
        applyCornerRadius()
        toolbar.place(below: frame, gap: Settings.shared.data.ui.annotationToolbarGap)
        webView.layoutSubtreeIfNeeded()
        win.alphaValue = 0
        win.ignoresMouseEvents = true
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        sendImage(shot)
    }

    /// Asks the page for the annotations alone, for the stand-in to lay over the screenshot.
    private func refreshOverlay(for key: String) {
        guard let webView, pageReady else { return }
        standIn.refreshOverlay(on: webView, for: key)
    }

    private var standInPixels: Int {
        Thumbnailer.screenPixels(on: zoomScreen ?? NSScreen.main ?? NSScreen.screens[0])
    }

    private func place(_ win: NSWindow, frame: NSRect) {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main ?? NSScreen.screens[0]
        zoomScreen = screen
        if win.frame != screen.visibleFrame { win.setFrame(screen.visibleFrame, display: false) }
        moveFrame(to: frame)
    }

    /// The one place the frame's rect is set: the frame view, the clip and the shadow's path all
    /// take it from here, in the same tick, so nothing can be a frame behind. `frameOnScreen`
    /// reads the result back for anyone who needs the rect.
    private func moveFrame(to frame: NSRect) {
        guard let win = window, let frameView, let container else { return }
        frameView.frame = NSRect(x: frame.minX - win.frame.minX, y: frame.minY - win.frame.minY, width: frame.width, height: frame.height)
        container.frame = frameView.bounds
        let r = Settings.shared.data.ui.annotationCornerRadius
        frameView.layer?.shadowPath = CGPath(roundedRect: frameView.bounds, cornerWidth: r, cornerHeight: r, transform: nil)
        onFrame?(frame)
    }

    /// The visible frame in screen coordinates.
    var frameOnScreen: NSRect? {
        guard let win = window, let frameView else { return nil }
        return win.convertToScreen(frameView.frame)
    }

    /// What asked for a zoom: the fingers on a trackpad, or a key, a two-finger double tap, or a fit.
    enum ZoomInput { case gesture, step }

    /// Zoom in grows each side of the window until that side fills the room, then magnifies the
    /// image past it. Zoom out reverses that and stops at the fitted size: pulling further shrinks
    /// the window a little and it springs back once the gesture ends. The toolbar stays where it is.
    ///
    /// `factor` multiplies the zoom level; nil asks for the fitted size. `cursor` is the point to
    /// keep in place, a fraction of the window with y from the top; nil means its middle, which is
    /// where a key zooms. Both phases honor it: the window grows away from it, and past that the
    /// page moves its camera about it.
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
        // An input that moves nothing (a notch out at the fit, cmd+0 at rest) is over here: raising
        // the stand-in for it would only hand the picture straight back.
        guard target != zoomTarget || zoomTween.value != zoomTarget else { return }
        zoomTarget = target
        // The picture becomes the app's own before the frame moves: the page is drawn in another
        // process and cannot keep step with a frame that moves every refresh.
        raiseStandIn()
        aim(at: cursor, to: zoomTarget)
        aimPan(at: cursor)
        zoomTween.animate(to: zoomTarget, duration: motionScaled(input == .gesture ? trackingSeconds : stepSeconds),
                          curve: "spring") { [weak self] in self?.arrived() }
    }

    /// Points the window's growth at `cursor`. The anchor it starts from is read off the frame on
    /// screen, so the step carries on from where the window is: a frame the screen edge has nudged
    /// does not carry that error forward, and a step aimed elsewhere mid-spring bends rather than
    /// stepping sideways. The anchor it ends at is the one the room allows, so the room gives way
    /// once, here, rather than the frame sliding part way through the spring. The window standing
    /// still has nothing to aim.
    private func aim(at cursor: CGPoint, to target: CGFloat) {
        guard let onScreen = frameOnScreen, target != zoomLevel else { return }
        zoomAim = Zoom.aim(at: cursor, of: onScreen, fitted: fittedFrame, window: split(target).window,
                           from: zoomLevel, to: target, within: growthLimit)
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

    /// The room `prepare` was given, if any. `presentEmpty` has none.
    private var room: NSRect?

    /// The rect the frame may grow within. The one place that says it, so the strip the recent
    /// stack keeps for itself reaches both how far the window may grow and where the frame ends up.
    private var growthLimit: CGRect? { room ?? zoomScreen?.visibleFrame }

    /// How far each side of the window may grow: to the whole of that rect, past the fitted inset
    /// and the toolbar's room.
    private var reach: CGSize { Zoom.reach(fitted: fittedFrame, within: growthLimit) }
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
        moveFrame(to: Zoom.frame(fitted: fittedFrame, scale: step.window,
                                 anchor: zoomAim.anchor(at: level), within: growthLimit))
        if let container { standIn.layout(in: container.bounds, camera: step.camera, center: zoomCenter) }
    }

    /// The picture becomes the app's own before the frame moves. Called before every zoom step,
    /// and on the fit the window makes on its way out.
    private func raiseStandIn() {
        guard let container, let webView else { return }
        standIn.raise(over: webView, in: container, camera: canvasZoom, center: zoomCenter)
    }

    /// Hands the picture back to the page at the view it is showing; see `StandInController`.
    /// The image rect is the stand-in's own, so the two pictures are one rect by construction.
    private func handOverToPage() {
        guard let webView, let container, let place = pagePlace else { return }
        let picture = Zoom.picture(in: container.bounds, camera: canvasZoom, center: zoomCenter)
        standIn.handOver(to: webView, at: place,
                         view: ViewRequest(frame: pageRect(container.bounds, in: place), image: pageRect(picture, in: place)),
                         pageReady: pageReady)
    }

    /// Where the page sits inside the frame's container: the whole room the frame may grow within,
    /// so the page is laid out once per image and never resized by a zoom, which is a relayout in
    /// another process each time. The frame moves over it; at each rest the page is moved back so
    /// it stays put on screen, and the editor inside it is placed at the frame (`pageRect`).
    private var pagePlace: CGRect? {
        guard let onScreen = frameOnScreen, let room = growthLimit else { return nil }
        return CGRect(x: room.minX - onScreen.minX, y: room.minY - onScreen.minY,
                      width: ceil(room.width), height: ceil(room.height))
    }

    /// A rect in the container's coordinates as the page sees it: CSS points of the web view at
    /// `place`, x from its left and y from its top.
    private func pageRect(_ rect: CGRect, in place: CGRect) -> PageRect {
        PageRect(x: rect.minX - place.minX, y: place.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Lays the page out at the room. `prepare` calls it directly: there is nothing on screen yet.
    private func placeWebView() {
        guard let webView, let place = pagePlace else { return }
        webView.frame = place
    }

    /// The spring has arrived. A pull below the fitted size lets go here; otherwise the page takes
    /// the picture back, on the next turn of the run loop rather than inside the tick that just
    /// ran, and only if nothing has aimed the zoom somewhere else meanwhile.
    private func arrived() {
        if zoomTarget < 1 { zoom(by: nil, at: nil, as: .step); return }
        guard !pageLayoutPending else { return }
        pageLayoutPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pageLayoutPending = false
            guard self.zoomTween.value == self.zoomTarget else { return }
            self.handOverToPage()
        }
    }

    /// A trackpad pinch, straight from AppKit: WebKit would otherwise turn it into gesture events
    /// the page zooms on. It follows the fingers about the point they are over. The pull springs
    /// back the moment the fingers lift.
    private func pinch(_ magnification: CGFloat, phase: NSEvent.Phase, at locationInWindow: NSPoint) {
        switch phase {
        case .ended, .cancelled: release()
        default: zoom(by: Double(1 + magnification), at: cursorFraction(locationInWindow), as: .gesture)
        }
    }

    /// Cmd+wheel or ctrl+wheel, straight from AppKit like the pinch: the event never crosses into
    /// the web process, so it arrives with the trackpad's phases and without a frame of latency.
    /// A trackpad's wheel is a gesture, and lifting the fingers releases the pull below the fit;
    /// momentum after the lift is ignored, as a pinch's end is, so the zoom stops where the hand
    /// did. A mouse wheel has no phases: each notch is a step, and it stops at the fit.
    private func wheel(_ event: NSEvent) {
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) { release(); return }
        guard event.momentumPhase.isEmpty else { return }
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * Self.wheelLinePoints
        guard dy != 0, dy.isFinite else { return }
        let cursor = cursorFraction(event.locationInWindow)
        zoom(by: exp(dy * Self.wheelZoomRate), at: cursor, as: event.phase.isEmpty ? .step : .gesture)
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

    /// A two-finger double tap on the trackpad, or a double-click with the select tool, as Preview
    /// and Safari use it: in on the point named, or back to the fitted size from anywhere above it.
    /// `cursor` is a fraction of the window; nil zooms about its middle.
    private func smartZoom(at cursor: CGPoint?) {
        guard window?.isVisible == true else { return }
        let zoomedIn = zoomTarget > 1.001
        zoom(by: zoomedIn ? nil : smartZoomFactor, at: zoomedIn ? nil : cursor, as: .step)
    }

    /// A point in the window's coordinates as a fraction of the visible frame, x from the left and
    /// y from the top, which is how the page reports the cursor. Read against the frame view: the
    /// web view carries a layer transform between rest positions, so its own bounds are not where
    /// its pixels are.
    private func cursorFraction(_ locationInWindow: NSPoint) -> CGPoint? {
        guard let frameView, frameView.bounds.width > 0, frameView.bounds.height > 0 else { return nil }
        let p = frameView.convert(locationInWindow, from: nil)
        return Zoom.clamped(CGPoint(x: p.x / frameView.bounds.width, y: 1 - p.y / frameView.bounds.height))
    }

    /// Puts the window up behind the flight image, which is past this frame on every side and so
    /// covers it — except for a shadow, which falls outside the frame it is cast from. The flight
    /// carries the shadow until it lands; `landed` hands it over. The keys came with `prepare`; the
    /// pointer comes here, so a drag lands on the page as soon as the card looks still.
    func show() {
        guard let win = window, current != nil else { return }
        win.alphaValue = 1
        win.ignoresMouseEvents = false
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

    /// Lets the prepared image go without asking the page for anything. Called instead of `hide`
    /// when the session ends before the window came up: nobody saw that image and nobody could
    /// draw on it, so there is nothing to store, and the stored draft the page was told to load
    /// stays as it is. A park here would be a round trip that can sit behind an export, with the
    /// card hanging in the air until it answers.
    func abandon() {
        guard current != nil else { return }
        outsideClick.stop()
        current = nil
        pendingHide = nil
        standIn.sessionEnded()
        call(.reset)
        hideWindows()
        canvasMaybeFreed()
    }

    /// Parks the draft, then removes the window. `then` runs once the page has answered, so a
    /// transition that starts there shows the annotations. Called once per `prepare`, by the reducer.
    func hide(then completion: (() -> Void)? = nil) {
        outsideClick.stop()
        // The window comes home to the fitted frame before it goes. The card flies back from that
        // frame, and a zoomed window is not only somewhere else: it shows a crop of the image where
        // the flight image is the whole picture, so handing over from it would swap the content too.
        var fitted = false, answered = false, finished = false
        let finish: () -> Void = { [weak self] in
            guard fitted, answered, !finished else { return }
            finished = true
            self?.pendingHide = nil
            self?.hideWindows()
            completion?()
            self?.canvasMaybeFreed()
        }
        fitBeforeHide { fitted = true; finish() }
        // The image is let go on both paths: a `current` left behind says the annotator still holds
        // it, and `canvasRefusal` would refuse a build until the next session.
        let shot = current
        current = nil
        guard let shot, let webView, pageReady else { standIn.sessionEnded(); answered = true; finish(); return }
        standIn.sessionEnded()
        let epoch = pageEpoch
        let done: () -> Void = {
            guard !answered else { return }
            answered = true
            finish()
        }
        pendingHide = done
        // The page runs park, export, and build one at a time, so an Esc during a long
        // Copy Drawing waits behind it. The window comes down on this deadline whatever the page
        // does; a park that answers after it is dropped, because by then the canvas may hold
        // another image.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.exportTimeout) {
            guard !answered else { return }
            Log.write("[web] error park timeout after \(Int(Self.exportTimeout)) s \(shot.url.lastPathComponent)")
            done()
        }
        webView.callAsyncJavaScript(PageAPI.park.script, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self, self.pageEpoch == epoch, !answered else { return }
            switch result {
            case .failure(let error): Log.write("[web] error park failed: \(error)")
            case .success(let value):
                if let parked = ParkResult(body: value) { self.onParked?(shot.url.path, parked) }
                else { Log.write("[web] error park returned \(WebMessage.describe(value as Any))") }
            }
            self.call(.reset)
            done()
        }
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
        raiseStandIn()
        zoomTarget = 1
        aim(at: Zoom.center, to: 1)
        aimPan(at: Zoom.center)
        zoomTween.animate(to: 1, duration: motionScaled(fitToCloseSeconds), curve: "spring", completion: once)
        DispatchQueue.main.asyncAfter(deadline: .now() + motionScaled(fitToCloseSeconds) + 0.3) { once() }
    }

    private func hideWindows() {
        // Nothing here is on screen any more: a spring still ticking would move a hidden frame,
        // hand a view to a page that has been reset, and lay out a hidden web view.
        zoomTween.stop()
        pageLayoutPending = false
        standIn.forget()
        // The panel stops being this window's child before the window goes, or AppKit would order
        // it out with its parent; `hideSoon` then takes it down only if no other image has asked
        // for it by the next turn of the run loop, and `show` makes it a child of the new window.
        if let win = window, toolbar.panel.parent === win { win.removeChildWindow(toolbar.panel) }
        toolbar.hideSoon()
        window?.orderOut(nil)
    }

    private func makeWindow(_ webView: WKWebView) -> AnnotationWindow {
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
        container.autoresizesSubviews = true
        webView.frame = container.bounds
        // Placed by hand: the page is laid out at the room, not the frame, and only moved at rest.
        webView.autoresizingMask = []
        container.addSubview(webView)
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

    /// Sends the image with the editor's place inside the page, which is the frame as laid out now.
    private func sendImage(_ shot: Screenshot) {
        guard let size = Thumbnailer.pixelSize(of: shot.url) else {
            Log.write("[annotate] could not read image \(shot.url.path)")
            return
        }
        loadStarted[shot.url.path] = CACurrentMediaTime()
        let frame = container.flatMap { c in pagePlace.map { pageRect(c.bounds, in: $0) } }
        let payload = LoadPayload(
            key: shot.url.path,
            mimeType: LocalServer.mimeType(for: shot.url.pathExtension),
            pixelWidth: size.width, pixelHeight: size.height, frame: frame)
        let load = PageAPI.load(payload, snapshot: draftSnapshot?(shot.url.path))
        if pageReady { call(load) } else { pendingCall = load }
    }

    private func call(_ api: PageAPI) {
        webView?.evaluateJavaScript(api.script) { _, error in
            if let error { Log.write("[web] error call failed: \(String(describing: error).replacingOccurrences(of: "\n", with: " "))") }
        }
    }

    /// Renders each item's stored draft at original pixel size. Always answers: with the page's
    /// renderings, or with `error` after a failure, a timeout, or when the page cannot take the
    /// call. One export at a time; a second one answers `error` at once.
    func exportDrafts(_ items: [(key: String, snapshot: Data)], completion: @escaping ([String: Data], String?) -> Void) {
        guard let webView, pageReady else { completion([:], "page not ready"); return }
        guard pendingExport == nil else { completion([:], "an export is already running"); return }
        let epoch = pageEpoch
        var answered = false
        let finish: ([String: Data], String?) -> Void = { [weak self] pngs, error in
            guard !answered else { return }
            answered = true
            self?.pendingExport = nil
            self?.canvasMaybeFreed()
            // The page's own text can name the URL it failed on, and the log is readable by any
            // local process, so the token comes out of it before anyone writes it down.
            completion(pngs, error.map { self?.server?.redacted($0) ?? $0 })
        }
        pendingExport = finish
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.exportTimeout) { finish([:], "timeout after \(Int(Self.exportTimeout)) s") }
        webView.callAsyncJavaScript(PageAPI.export(items).script, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self, self.pageEpoch == epoch else { return }
            switch result {
            case .failure(let error): finish([:], String(describing: error).replacingOccurrences(of: "\n", with: " "))
            case .success(let value):
                guard let exported = ExportResult(body: value) else { finish([:], "page returned \(WebMessage.describe(value as Any))"); return }
                finish(exported.pngs, exported.error)
            }
        }
    }

    /// The image the page is holding, by path, or nil between sessions. A send compares its own
    /// answer with this, so a rendering that lands after a swap closes nothing.
    var currentKey: String? { current?.url.path }

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

    /// The drawing exactly as it stands, rendered at full size, with nothing closed and nothing
    /// stored: what Send hands to an agent. Done is unsuitable for this — its rendering failure
    /// path sends `cancel` and ends the session — and its contract is left alone.
    ///
    /// Answers with the key the rendering belongs to, so a caller can drop an answer that arrived
    /// after the person moved to another image. A nil PNG with no error means nothing is drawn,
    /// which is a send of the plain screenshot. Always answers.
    func snapshotCurrent(completion: @escaping (_ key: String, _ png: Data?, _ error: String?) -> Void) {
        guard let shot = current, let webView, pageReady else {
            completion("", nil, "the editor page is not ready"); return
        }
        let key = shot.url.path
        guard pendingSnapshot == nil else { completion(key, nil, "a send is already preparing"); return }
        let epoch = pageEpoch
        var answered = false
        let finish: (Data?, String?) -> Void = { [weak self] png, error in
            guard !answered else { return }
            answered = true
            self?.pendingSnapshot = nil
            // The page's own text can name a served URL, and every served URL starts with the
            // per-launch token, which must never reach the log.
            completion(key, png, error.map { self?.server?.redacted($0) ?? $0 })
        }
        pendingSnapshot = finish
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.exportTimeout) { finish(nil, "timeout after \(Int(Self.exportTimeout)) s") }
        webView.callAsyncJavaScript(PageAPI.snapshot.script, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self, self.pageEpoch == epoch else { return }
            switch result {
            case .failure(let error): finish(nil, String(describing: error).replacingOccurrences(of: "\n", with: " "))
            case .success(let value):
                guard let snapshot = SnapshotResult(body: value) else {
                    finish(nil, "page returned \(WebMessage.describe(value as Any))"); return
                }
                finish(snapshot.png, snapshot.error)
            }
        }
    }

    /// The page's canvas belongs to the annotator, so nothing else may draw on it. It takes it in
    /// `prepare`, about half a second before the window appears, and gives it back when `park`
    /// answers, after the window is gone.
    private var holdsCanvas: Bool { current != nil || pendingHide != nil }

    /// Every color the page can draw a mark in, by id: what an agent's `marks=` may name.
    private(set) var colorIDs: [String] = []

    /// Why nothing may borrow the page's canvas right now, or nil when it is free. A marks build
    /// and a preview rendering both put their own image there for the length of one rendering, so
    /// they wait for the annotator; `add` asks before it copies anything, so a refusal is one error
    /// line and no file left behind.
    /// Called a turn after the canvas stops being owned, so whatever was refused can ask again.
    /// It fires from every place one of the four owners lets go rather than from the callers of
    /// those places: an export or a build that answered somewhere new would otherwise strand a
    /// waiting import until the next unrelated session.
    var onCanvasFree: (() -> Void)?

    /// Signals `onCanvasFree` on the next turn of the run loop, if the canvas is still free then.
    /// The next turn rather than now: an owner clears its flag inside its own completion, and an
    /// import starting there would run inside the call that released it.
    private func canvasMaybeFreed() {
        guard canvasRefusal == nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.canvasRefusal == nil else { return }
            self.onCanvasFree?()
        }
    }

    var canvasRefusal: String? {
        if webView == nil || !pageReady { return "the editor page is not ready" }
        if holdsCanvas { return "an image is in the annotator" }
        // Copy Drawing and a launch-time preview both run through `exportDrafts`, so this says
        // what is true of either rather than naming one of them.
        if pendingExport != nil { return "the page is rendering" }
        if pendingBuild != nil { return "another push is still building its marks" }
        return nil
    }

    /// Turns an agent's marks into a draft without showing anything: the page puts the image and the
    /// marks on its canvas, hands back the snapshot and a rendering, and restores its own canvas.
    /// `snapshot` is the image's existing draft, so marks add to it instead of replacing it.
    /// Always answers, like `exportDrafts`: with the result, or with an error after a failure, a
    /// timeout, or when the page cannot take the call.
    func buildDraft(_ shot: Screenshot, marks: [Mark], completion: @escaping (ParkResult?, String?) -> Void) {
        if let refusal = canvasRefusal { completion(nil, refusal); return }
        guard let webView else { completion(nil, "the editor page is not ready"); return }
        guard let pixels = Thumbnailer.pixelSize(of: shot.url) else {
            completion(nil, "could not read \(shot.url.lastPathComponent)"); return
        }
        let payload = LoadPayload(
            key: shot.url.path, mimeType: LocalServer.mimeType(for: shot.url.pathExtension),
            pixelWidth: pixels.width, pixelHeight: pixels.height)
        let epoch = pageEpoch
        var answered = false
        let finish: (ParkResult?, String?) -> Void = { [weak self] parked, error in
            guard !answered else { return }
            answered = true
            self?.pendingBuild = nil
            self?.canvasMaybeFreed()
            completion(parked, error)
        }
        pendingBuild = finish
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.exportTimeout) { finish(nil, "timeout after \(Int(Self.exportTimeout)) s") }
        let script = PageAPI.build(payload, snapshot: draftSnapshot?(shot.url.path), marks: marks).script
        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self, self.pageEpoch == epoch else { return }
            switch result {
            case .failure(let error): finish(nil, String(describing: error).replacingOccurrences(of: "\n", with: " "))
            case .success(let value):
                guard let parked = ParkResult(body: value) else { finish(nil, "page returned \(WebMessage.describe(value as Any))"); return }
                finish(parked, nil)
            }
        }
    }

    /// When each image's `load` was sent, by key, for the `[annotate] loaded` line. A swap can have two in flight.
    private var loadStarted: [String: CFTimeInterval] = [:]

    /// Debug: runs JavaScript in the page and logs the result. `open 'vignette://eval?<code>'`.
    func evalForDebug(_ code: String) {
        guard let webView else { Commands.error("eval", .pageNotReady, "no page"); return }
        webView.callAsyncJavaScript(code, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .success(let value): Commands.ok("eval", String(describing: value).replacingOccurrences(of: "\n", with: " "))
            case .failure(let error): Commands.error("eval", .evalFailed, String(describing: error).replacingOccurrences(of: "\n", with: " "))
            }
        }
    }

    /// Debug: shows the editor window without loading an image.
    func presentEmpty() {
        guard let webView else { return }
        let frame = StackLayout.current.annotationFrame(for: NSSize(width: 1200, height: 800), visibleFrame: (NSScreen.main ?? NSScreen.screens[0]).visibleFrame)
        room = nil
        let win = window ?? makeWindow(webView)
        place(win, frame: frame)
        placeWebView()
        applyCornerRadius()
        toolbar.place(below: frame, gap: Settings.shared.data.ui.annotationToolbarGap)
        win.makeKeyAndOrderFront(nil)
        landed()   // no flight to hand over from: this window is the whole of it
        if toolbar.panel.parent == nil { win.addChildWindow(toolbar.panel, ordered: .above) }
        toolbar.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Ends the session as Esc would, or closes the empty editor from `show-editor`.
    /// `open vignette://cancel`. False when nothing was open.
    @discardableResult
    func cancelForDebug() -> Bool {
        if current == nil {
            guard let window, window.isVisible else { return false }
            hideWindows()
            return true
        }
        cancel()
        return true
    }

    private func cancel() {
        guard current != nil else { return }
        Log.write("[annotate] cancelled")
        onClosed?()
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let msg = WebMessage(body: message.body) else {
            Log.write("[web] unrecognized message \(WebMessage.describe(message.body))")
            return
        }
        switch msg {
        case .ready(let version, let tools, let markColors):
            guard version == bridgeProtocolVersion else {
                pageFailed = true
                Log.write("[web] error protocol-mismatch page=\(version) app=\(bridgeProtocolVersion); rebuild with scripts/build.sh")
                onProblem?("The editor page is out of date; rebuild the app")
                return
            }
            Log.write("[web] ready protocol=\(version) tools=\(tools.count) markColors=\(markColors.count)")
            pageReady = true
            canvasMaybeFreed()
            toolbar.model.tools = tools
            colorIDs = markColors.map(\.id)
            if let call = pendingCall { self.call(call); pendingCall = nil }
            // After a web process restart the window is still up: put its image and stored draft back.
            else if let shot = current { sendImage(shot) }
            onPageReady?()
        case .tool(let tool, let color):
            toolbar.model.tool = tool
            toolbar.model.color = color
        case .loaded(let key):
            let ms = loadStarted.removeValue(forKey: key).map { Int((CACurrentMediaTime() - $0) * 1000) } ?? -1
            Log.write("[annotate] loaded \(ms)ms \((key as NSString).lastPathComponent)")
            onLoaded?(key)
            // A stored draft comes with the image, so the stand-in has its annotations before the
            // first zoom rather than after the first change.
            refreshOverlay(for: key)
        case .done(let png):
            // The host answers through the transition (finish or dismiss), which parks and hides.
            guard let shot = current else { return }
            if let png { onDraftPreview?(shot.url.path, png) }
            onFinished?(shot, png)
        case .cancel:
            cancel()
        case .log(let text):
            Log.write("[web] \(text)")
        case .draft(let key, let snapshot):
            onDraft?(key, snapshot)
            // The annotations changed, so the picture the stand-in draws them with has to change
            // too. The draft is already debounced behind the last change, so this is as well.
            refreshOverlay(for: key)
        case .zoom(let factor, let at):
            // The zoom keys. The wheel and the pinch never reach the page: `AnnotationWebView`
            // takes them, so a cursor here is a leftover and treated as a gesture's.
            zoom(by: factor, at: at, as: at == nil ? .step : .gesture)
        case .smartZoom(let at):
            // The page has decided this double-click is not tldraw's: the tool is select and the
            // pointer is over the picture rather than over a mark.
            smartZoom(at: at)
        }
    }

    var stateJSON: [String: Any] {
        [
            "current": current?.url.path as Any,
            "windowVisible": window?.isVisible ?? false,
            "zoom": [zoomWindow.width, zoomWindow.height],
            "zoomLevel": zoomLevel,
            "canvasZoom": [canvasZoom.width, canvasZoom.height],
            "zoomAnchor": [zoomAnchor.x, zoomAnchor.y],
            "zoomCenter": [zoomCenter.x, zoomCenter.y],
            "standIn": standIn.isUp,
            "overlay": standIn.overlayPixels as Any,
            "room": growthLimit.map { StateReport.topLeft($0, primaryHeight: StateReport.primaryHeight) } as Any,
            "frame": frameOnScreen.map { StateReport.topLeft($0, primaryHeight: StateReport.primaryHeight) } as Any,
            "toolbar": (toolbar.panel.isVisible ? StateReport.topLeft(toolbar.panel.frame, primaryHeight: StateReport.primaryHeight) : nil) as Any,
            "pageState": "\(pageState)",
            "tool": toolbar.model.tool as Any, "color": toolbar.model.color,
            "port": Int(port),
            "webPid": webProcessID.map { Int($0) } as Any,
        ]
    }

    /// What the page has rendered, or nil when it does not answer in time (no page, a page that is
    /// loading, or a dead web process). Driven by vignette://state.
    func queryPage(timeout: TimeInterval, completion: @escaping (Any?) -> Void) {
        guard let webView, pageReady else { completion(nil); return }
        var answered = false
        let finish: (Any?) -> Void = { value in
            guard !answered else { return }
            answered = true
            completion(value)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { finish(nil) }
        let script = "const vb = window.editor ? window.editor.getViewportPageBounds() : null; return {title: document.title, root: document.getElementById('root')?.children.length, api: typeof window.vignette, canvas: document.querySelector('.tl-canvas') != null, images: document.querySelectorAll('.tl-image').length, shapes: window.editor ? window.editor.getCurrentPageShapeIds().size : null, canUndo: window.editor ? window.editor.getCanUndo() : null, zoom: window.editor ? window.editor.getZoomLevel() / window.editor.getBaseZoom() : null, visible: vb ? [Math.round(vb.x), Math.round(vb.y), Math.round(vb.w), Math.round(vb.h)] : null, inner: [innerWidth, innerHeight], hidden: document.hidden, page: location.pathname.split('/').pop()};"
        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
            if case .success(let value) = result { finish(value) } else { finish(nil) }
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Log.write("[web] loaded \(webView.url.map { LocalServer.redacted($0) } ?? "?")")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        pageFailed = true
        Log.write("[web] failed to load: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        pageFailed = true
        Log.write("[web] navigation failed: \(error.localizedDescription)")
    }

    /// WebKit killed or lost the content process. Everything on the page is gone; reload it. The
    /// `ready` that follows re-sends the current image with its stored draft.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        pageReady = false
        pendingCall = nil
        pageEpoch += 1
        Log.write("[web] error process-terminated; reloading")
        pendingExport?([:], "web process terminated")
        pendingBuild?(nil, "web process terminated")
        pendingSnapshot?(nil, "web process terminated")
        pendingHide?()
        standIn.pageRestarted()
        // The reloaded page fits the image to the frame it finds, and a zoomed frame is not the
        // image's shape any more, so it would fit the whole image inside it with a gap down one
        // side. The window comes home instead, which is the view that page will draw.
        if abs(zoomTarget - 1) > 0.001 { zoom(by: nil, at: nil, as: .step) }
        onProblem?("The editor restarted")
        webView.reload()
    }
}

/// Takes the trackpad's zoom gestures before WebKit does, so zoom stays the app's (see
/// `AnnotationController.zoom`). Both carry where the fingers are, which is the point zoom holds.
@MainActor
final class AnnotationWebView: WKWebView {
    var onMagnify: ((CGFloat, NSEvent.Phase, NSPoint) -> Void)?
    var onSmartMagnify: ((NSPoint) -> Void)?
    /// A wheel with cmd or ctrl held. Taken here so tldraw never sees it: it would zoom its own
    /// camera, and the page would see it a frame late and without the trackpad's phases.
    var onZoomWheel: ((NSEvent) -> Void)?
    override func magnify(with event: NSEvent) {
        onMagnify?(event.magnification, event.phase, event.locationInWindow)
    }
    override func scrollWheel(with event: NSEvent) {
        if !event.modifierFlags.intersection([.command, .control]).isEmpty { onZoomWheel?(event); return }
        super.scrollWheel(with: event)
    }
    override func smartMagnify(with event: NSEvent) {
        onSmartMagnify?(event.locationInWindow)
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
