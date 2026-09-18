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
    /// The hide waiting on the page's park, so a process restart still hides the window.
    private var pendingHide: (() -> Void)?
    /// How long Copy Drawing waits for the page before giving up.
    static let exportTimeout: TimeInterval = 15

    /// Room the annotator needs below its window: the toolbar and its gap.
    var spaceBelow: CGFloat { AnnotatorToolbar.height + Settings.shared.data.ui.annotationToolbarGap }

    /// The frame `prepare` fitted the image into; zoom grows the window from here.
    private var fittedFrame: NSRect = .zero
    /// How far the image is magnified past the fitted frame. One number: `Zoom.split` divides it
    /// between the window's scale and the page's camera, so those two can never disagree about it.
    private(set) var zoomLevel: CGFloat = 1
    /// Where the level is heading. Every input moves this; one spring carries the level to it, so
    /// a gesture, a key and a fit bend into each other instead of stepping.
    private var zoomTarget: CGFloat = 1
    private lazy var zoomTween = Tween(initial: 1) { [weak self] v in self?.applyZoom(v) }
    /// The window's scale on screen. 1 is the fitted frame.
    var zoomScale: CGFloat { split(zoomLevel).window }
    /// Magnification inside a window that can grow no further, as the page was last told it; 1 fits.
    private(set) var canvasZoom: CGFloat = 1
    /// The point the window grows away from, as a fraction of the window: the cursor's own point,
    /// so what is under it stays under it, or the middle for a key. See `Zoom`.
    private var zoomAim = ZoomAim.fitted
    /// The same for the magnification inside a window that can grow no further: where the visible
    /// middle was when the input arrived, and the point it named.
    private var zoomPan = ZoomPan.centered
    /// The middle of the visible part of the image, as a fraction of it. The stand-in draws from
    /// this and the page is given it at rest, so the two show the same part of the image.
    private(set) var zoomCenter = Zoom.center
    /// The anchor in effect at the scale on screen.
    var zoomAnchor: CGPoint { zoomAim.anchor(at: zoomScale) }
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
    /// Set when the spring has arrived, so the page is laid out at its new size once, on the next
    /// turn of the run loop, rather than inside a display link tick.
    private var pageLayoutPending = false
    /// What is on screen in place of the page while a zoom moves, and the hand-over that gives the
    /// picture back at rest. It owns its own outstanding page calls; see `StandInController`.
    private let standIn = StandInController()

    func preload() {
        _ = FocusReturn.shared
        toolbar.onTool = { [weak self] id in self?.call(.setTool(id)) }
        toolbar.onDone = { [weak self] in self?.call(.finish) }
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
        config.userContentController.add(self, name: "shotnote")
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let webView = AnnotationWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        webView.navigationDelegate = self
        webView.onMagnify = { [weak self] magnification, phase, location in self?.pinch(magnification, phase: phase, at: location) }
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

    /// Sizes the hidden window to `frame` and loads the image, so the page has rendered by `show`.
    /// `room` is the rect the frame may grow within: the visible screen, less any strip its owner
    /// keeps for itself.
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
        canvasZoom = 1
        zoomTween.set(1)
        place(win, frame: frame)
        standIn.prepare(for: shot.url, maxPixel: standInPixels)
        resizeWebView()
        applyCornerRadius()
        toolbar.place(below: frame, gap: Settings.shared.data.ui.annotationToolbarGap)
        webView.layoutSubtreeIfNeeded()
        sendImage(shot, windowSize: frame.size)
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

    /// Zoom in grows the window until it fills the screen, then magnifies the image inside it.
    /// Zoom out reverses that and stops at the fitted size: pulling further shrinks the window a
    /// little and it springs back once the gesture ends. The toolbar stays where it is.
    ///
    /// `factor` multiplies the zoom level; nil asks for the fitted size. `cursor` is the point to
    /// keep in place, a fraction of the window with y from the top; nil means its middle, which is
    /// where a key zooms. Both phases honor it: the window grows away from it, and past that the
    /// page moves its camera about it.
    func zoom(by factor: Double?, at cursor: CGPoint?, as input: ZoomInput) {
        guard window != nil, fittedFrame.width > 0 else { return }
        let cursor = cursor.map(Zoom.clamped) ?? Zoom.center
        // The picture becomes the app's own before the frame moves: the page is drawn in another
        // process and cannot keep step with a frame that moves every refresh.
        raiseStandIn()
        if let factor, factor.isFinite, factor > 0 {
            zoomTarget = min(maxLevel, max(minLevel, zoomTarget * CGFloat(factor)))
        } else {
            zoomTarget = 1
        }
        aim(at: cursor, to: split(zoomTarget).window)
        aimPan(at: cursor)
        zoomTween.animate(to: zoomTarget, duration: motionScaled(input == .gesture ? trackingSeconds : stepSeconds),
                          curve: "spring") { [weak self] in self?.arrived() }
    }

    /// Points the window's growth at `cursor`. The anchor it starts from is read off the frame on
    /// screen, so the step carries on from where the window is: a frame the screen edge has nudged
    /// does not carry that error forward, and a step aimed elsewhere mid-spring bends rather than
    /// stepping sideways. The anchor it ends at is the one the room allows at the target scale, so
    /// the room gives way once, here, rather than the frame sliding part way through the spring.
    /// The window standing still has nothing to aim.
    private func aim(at cursor: CGPoint, to target: CGFloat) {
        guard let onScreen = frameOnScreen, target != zoomScale else { return }
        zoomAim = Zoom.aim(at: cursor, of: onScreen, fitted: fittedFrame, scale: zoomScale,
                           to: target, within: growthLimit)
    }

    /// Points the magnification at `cursor`, from the part of the image that is visible now. Like
    /// `aim`, it starts from what is on screen, so a step aimed elsewhere mid-spring bends.
    ///
    /// A cursor near an edge of the picture is pulled onto it first (`ui.zoomEdgeBandPoints`,
    /// `ui.zoomEdgePull`): only the window's own edge holds the image's edge with it, so without
    /// the pull the corner the cursor is beside is cropped by the first bit of magnification. The
    /// band is measured in points of the frame the cursor is over, so its reach is the same on all
    /// four edges however wide the screenshot is. The window's growth needs none of this — the
    /// whole image is inside the window until the window can grow no further, so nothing can be
    /// cropped before the magnification starts.
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

    /// How a level divides between the window and the page's camera on this screen.
    private func split(_ level: CGFloat) -> (window: CGFloat, camera: CGFloat) {
        Zoom.split(level: level, maxWindow: maxZoom, maxCamera: maxCanvasZoom, pull: overpull)
    }

    /// The room `prepare` was given, if any. `presentEmpty` has none.
    private var room: NSRect?

    /// The rect the frame may grow within. The one place that says it, so the strip the recent
    /// stack keeps for itself reaches both how far the window may grow and where the frame ends up.
    private var growthLimit: CGRect? { room ?? zoomScreen?.visibleFrame }

    /// The window may grow to the whole of that rect, past the fitted inset and the toolbar's room.
    private var maxZoom: CGFloat { Zoom.reach(fitted: fittedFrame, within: growthLimit) }
    private var maxLevel: CGFloat { maxZoom * maxCanvasZoom }
    /// How far a gesture may pull below the fitted size before the level stops following it.
    private let minLevel: CGFloat = 0.5

    /// One tick. The frame's rect and the picture inside it both come from this level: the window
    /// grows until it can grow no further and the magnification takes the rest. Both are set here,
    /// in one run loop turn, so they reach the window server in one Core Animation commit.
    private func applyZoom(_ level: CGFloat) {
        guard window != nil, fittedFrame.width > 0 else { return }
        zoomLevel = level
        let step = split(level)
        canvasZoom = step.camera
        zoomCenter = zoomPan.center(at: step.camera)
        // Kept on screen: a frame grown to the screen's height slides rather than clips.
        moveFrame(to: Zoom.frame(fitted: fittedFrame, scale: step.window,
                                 anchor: zoomAim.anchor(at: step.window), within: growthLimit))
        if let container { standIn.layout(in: container.bounds, camera: step.camera, center: zoomCenter) }
    }

    /// The picture becomes the app's own before the frame moves. Called before every zoom step,
    /// and on the fit the window makes on its way out.
    private func raiseStandIn() {
        guard let container, let webView else { return }
        standIn.raise(over: webView, in: container, camera: canvasZoom, center: zoomCenter)
    }

    /// Hands the picture back to the page at the view it is showing; see `StandInController`.
    private func handOverToPage() {
        guard let webView else { return }
        standIn.handOver(to: webView, size: pageSize, camera: canvasZoom, center: zoomCenter,
                         pageReady: pageReady)
    }

    /// The size the page is laid out at: the frame's own size rounded up to whole points. A page's
    /// layout viewport is a whole number of CSS pixels, so a frame 1318.8 points wide would leave
    /// its last fifth of a point uncovered and the picture would end short of the frame; rounded
    /// up, the page covers the frame and the container's mask clips the fraction over.
    private var pageSize: CGSize {
        guard let container else { return .zero }
        return CGSize(width: ceil(container.bounds.width), height: ceil(container.bounds.height))
    }

    /// Lays the page out at the size it is drawn at, so it renders at the screen's own resolution.
    /// `prepare` calls it directly: there is nothing on screen yet.
    private func resizeWebView() {
        guard let webView else { return }
        webView.frame = CGRect(origin: .zero, size: pageSize)
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

    func show() {
        guard let win = window, current != nil else { return }
        win.alphaValue = 1
        win.makeKeyAndOrderFront(nil)
        if toolbar.panel.parent == nil { win.addChildWindow(toolbar.panel, ordered: .above) }
        toolbar.show()
        NSApp.activate(ignoringOtherApps: true)
        // A click outside this app's windows ends the session.
        outsideClick.start { [weak self] in self?.cancel() }
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
        }
        fitBeforeHide { fitted = true; finish() }
        guard let shot = current, let webView, pageReady else { standIn.sessionEnded(); answered = true; finish(); return }
        current = nil
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
        aim(at: Zoom.center, to: split(1).window)
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
        if let win = window, toolbar.panel.parent === win { win.removeChildWindow(toolbar.panel) }
        toolbar.hide()
        window?.orderOut(nil)
    }

    private func makeWindow(_ webView: WKWebView) -> AnnotationWindow {
        let win = AnnotationWindow(contentRect: .zero, styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false   // the frame view carries the shadow; the window itself is invisible
        win.level = .floating
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
        // Sized by hand: a moving zoom leaves the page at the size it was laid out at, under the
        // stand-in, and lays it out again once, at rest.
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

    private func sendImage(_ shot: Screenshot, windowSize: NSSize) {
        guard let size = Thumbnailer.pixelSize(of: shot.url) else {
            Log.write("[annotate] could not read image \(shot.url.path)")
            return
        }
        loadStarted[shot.url.path] = CACurrentMediaTime()
        let payload = LoadPayload(
            key: shot.url.path,
            mimeType: LocalServer.mimeType(for: shot.url.pathExtension),
            pixelWidth: size.width, pixelHeight: size.height)
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

    /// Debug: runs JavaScript in the page and logs the result. `open 'shotnote://eval?<code>'`.
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
        resizeWebView()
        applyCornerRadius()
        toolbar.place(below: frame, gap: Settings.shared.data.ui.annotationToolbarGap)
        win.makeKeyAndOrderFront(nil)
        if toolbar.panel.parent == nil { win.addChildWindow(toolbar.panel, ordered: .above) }
        toolbar.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Ends the session as Esc would, or closes the empty editor from `show-editor`.
    /// `open shotnote://cancel`. False when nothing was open.
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
            toolbar.model.tools = tools
            colorIDs = markColors.map(\.id)
            if let call = pendingCall { self.call(call); pendingCall = nil }
            // After a web process restart the window is still up: put its image and stored draft back.
            else if let shot = current, let container { sendImage(shot, windowSize: container.bounds.size) }
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
            // A cursor names a gesture: the wheel and the pinch send the point they are over, a
            // key sends none. The two differ only in how long their spring is.
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
            "zoom": zoomScale,
            "zoomLevel": zoomLevel,
            "canvasZoom": canvasZoom,
            "zoomAnchor": [zoomAnchor.x, zoomAnchor.y],
            "zoomCenter": [zoomCenter.x, zoomCenter.y],
            "standIn": standIn.isUp,
            "overlay": standIn.overlayPixels as Any,
            "room": growthLimit.map { StateReport.topLeft($0, primaryHeight: StateReport.primaryHeight) } as Any,
            "frame": frameOnScreen.map { StateReport.topLeft($0, primaryHeight: StateReport.primaryHeight) } as Any,
            "pageState": "\(pageState)",
            "tool": toolbar.model.tool as Any, "color": toolbar.model.color,
            "port": Int(port),
            "webPid": webProcessID.map { Int($0) } as Any,
        ]
    }

    /// What the page has rendered, or nil when it does not answer in time (no page, a page that is
    /// loading, or a dead web process). Driven by shotnote://state.
    func queryPage(timeout: TimeInterval, completion: @escaping (Any?) -> Void) {
        guard let webView, pageReady else { completion(nil); return }
        var answered = false
        let finish: (Any?) -> Void = { value in
            guard !answered else { return }
            answered = true
            completion(value)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { finish(nil) }
        let script = "const vb = window.editor ? window.editor.getViewportPageBounds() : null; return {title: document.title, root: document.getElementById('root')?.children.length, api: typeof window.shotnote, canvas: document.querySelector('.tl-canvas') != null, images: document.querySelectorAll('.tl-image').length, shapes: window.editor ? window.editor.getCurrentPageShapeIds().size : null, canUndo: window.editor ? window.editor.getCanUndo() : null, zoom: window.editor ? window.editor.getZoomLevel() / window.editor.getBaseZoom() : null, visible: vb ? [Math.round(vb.x), Math.round(vb.y), Math.round(vb.w), Math.round(vb.h)] : null, inner: [innerWidth, innerHeight], hidden: document.hidden, page: location.pathname.split('/').pop()};"
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
        pendingHide?()
        standIn.pageRestarted()
        onProblem?("The editor restarted")
        webView.reload()
    }
}

/// Borderless windows refuse key status by default; the editor needs it for typing and shortcuts.
@MainActor
/// Takes the trackpad's zoom gestures before WebKit does, so zoom stays the app's (see
/// `AnnotationController.zoom`). Both carry where the fingers are, which is the point zoom holds.
final class AnnotationWebView: WKWebView {
    var onMagnify: ((CGFloat, NSEvent.Phase, NSPoint) -> Void)?
    var onSmartMagnify: ((NSPoint) -> Void)?
    override func magnify(with event: NSEvent) {
        onMagnify?(event.magnification, event.phase, event.locationInWindow)
    }
    override func smartMagnify(with event: NSEvent) {
        onSmartMagnify?(event.locationInWindow)
    }
}

final class AnnotationWindow: NSWindow {
    var onCloseRequest: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func performClose(_ sender: Any?) { onCloseRequest?() }
}
