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

    /// Nil when the bundle has no page or the server did not start; every call then no-ops.
    private var webView: WKWebView?
    private let toolbar = AnnotatorToolbar()
    private var server: LocalServer?
    private var window: AnnotationWindow?
    /// The window spans the screen's visible frame and stays put. The visible frame is `frameView`
    /// inside it (shadow) with `container` (clip, corner, ring, web view), so a zoom step moves the
    /// frame and scales the page in one layer commit: a window resize and a layer change do not
    /// land on the same display frame, and the image would drift from the frame between them.
    /// The web view's scale is read off `container.bounds`, so the image's edges are the frame's.
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
    private var outsideClickMonitor: Any?
    /// Bumped when the web process restarts, so an answer from the old page is ignored.
    private var pageEpoch = 0
    /// The export waiting on the page, if any. Called exactly once: by the page's answer, the
    /// timeout, or a process restart, whichever comes first.
    private var pendingExport: (([String: Data], String?) -> Void)?
    /// The marks build waiting on the page, if any. One at a time, and called exactly once.
    private var pendingBuild: ((ParkResult?, String?) -> Void)?
    /// The hide waiting on the page's park, so a process restart still hides the window.
    private var pendingHide: (() -> Void)?
    /// How long Copy Annotated waits for the page before giving up.
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
    /// The point the last input named. The page holds the same one while it magnifies.
    private var zoomCursor = Zoom.center
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
    /// One camera call at a time, with the newest value waiting; see `setCanvasZoom`.
    private var cameraInFlight = false
    private var cameraPending: (ratio: CGFloat, cursor: CGPoint)?
    /// A picture of the page laid over the web view while the page re-renders at a new size.
    /// Measured: a web view grown before its process has painted draws its old, smaller content in
    /// the corner of the new size, so the image stops filling the frame until the paint lands. The
    /// cover is those same pixels stretched to the frame, which is what the live page under a
    /// transform was showing anyway, and it follows the frame, so a gesture may start while it is
    /// up. It comes down when the page says it has painted, not on a timer.
    private var cover: NSImageView?
    /// Which relayout the cover belongs to, so a late answer never takes down a newer cover.
    private var coverEpoch = 0

    func preload() {
        _ = FocusReturn.shared
        toolbar.onTool = { [weak self] id in self?.call(.setTool(id)) }
        toolbar.onColor = { [weak self] id in self?.call(.setColor(id)) }
        toolbar.onDone = { [weak self] in self?.call(.finish) }
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
        webView.onSmartMagnify = { [weak self] location in self?.smartZoom(at: location) }
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
    func prepare(_ shot: Screenshot, in frame: NSRect) {
        guard let webView else { return }
        current = shot
        let win = window ?? makeWindow(webView)
        fittedFrame = frame
        zoomTarget = 1
        zoomAim = .fitted
        zoomCursor = Zoom.center
        canvasZoom = 1
        zoomTween.set(1)
        place(win, frame: frame)
        removeCover()
        resizeWebView()
        applyCornerRadius()
        toolbar.place(below: frame, gap: Settings.shared.data.ui.annotationToolbarGap)
        webView.layoutSubtreeIfNeeded()
        sendImage(shot, windowSize: frame.size)
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
        zoomCursor = cursor
        if let factor, factor.isFinite, factor > 0 {
            zoomTarget = min(maxLevel, max(minLevel, zoomTarget * CGFloat(factor)))
        } else {
            zoomTarget = 1
        }
        aim(at: cursor, to: split(zoomTarget).window)
        zoomTween.animate(to: zoomTarget, duration: motionScaled(input == .gesture ? trackingSeconds : stepSeconds),
                          curve: "spring") { [weak self] in self?.arrived() }
    }

    /// Points the window's growth at `cursor`. The anchor it starts from is read off the frame on
    /// screen, so the step carries on from where the window is: a frame the screen edge has nudged
    /// does not carry that error forward, and a step aimed elsewhere mid-spring bends rather than
    /// stepping sideways. The window standing still has nothing to aim.
    private func aim(at cursor: CGPoint, to target: CGFloat) {
        guard let onScreen = frameOnScreen, target != zoomScale else { return }
        zoomAim = Zoom.aim(at: cursor, of: onScreen, fitted: fittedFrame, scale: zoomScale, to: target)
    }

    /// Zoom's springs are in code rather than in the tweaks, but the motion scale still shortens
    /// them, so `ui.motion: 0` and Reduce Motion land a zoom step at once.
    private func motionScaled(_ seconds: Double) -> Double { seconds * Settings.shared.motionScale }

    /// How a level divides between the window and the page's camera on this screen.
    private func split(_ level: CGFloat) -> (window: CGFloat, camera: CGFloat) {
        Zoom.split(level: level, maxWindow: maxZoom, maxCamera: maxCanvasZoom, pull: overpull)
    }

    /// The window may grow to the whole visible screen, past the fitted inset and the toolbar's room.
    private var maxZoom: CGFloat {
        guard let screen = zoomScreen, fittedFrame.width > 0, fittedFrame.height > 0 else { return 1 }
        let v = screen.visibleFrame
        return max(1, min(v.width / fittedFrame.width, v.height / fittedFrame.height))
    }
    private var maxLevel: CGFloat { maxZoom * maxCanvasZoom }
    /// How far a gesture may pull below the fitted size before the level stops following it.
    private let minLevel: CGFloat = 0.5

    /// One tick. The frame's rect and the image's scale both come from this level, and the web
    /// view's scale is read off the frame's own bounds, so the image's edges are the frame's edges
    /// in every commit. The camera only moves once the window cannot grow any further.
    private func applyZoom(_ level: CGFloat) {
        guard window != nil, fittedFrame.width > 0 else { return }
        zoomLevel = level
        let step = split(level)
        // Kept on screen: a frame grown to the screen's height slides rather than clips.
        moveFrame(to: Zoom.frame(fitted: fittedFrame, scale: step.window,
                                 anchor: zoomAim.anchor(at: step.window), within: zoomScreen?.visibleFrame))
        fitWebView()
        setCanvasZoom(step.camera, at: zoomCursor)
    }

    /// Scales the web view to the frame around it, about the frame's centre. The scale is the
    /// frame's own size over the size the page was laid out at, so the image lands on the frame's
    /// edges exactly whatever rect the frame came out as, and both change in one layer commit.
    private func fitWebView() {
        guard let webView, let container, let layer = webView.layer else { return }
        let laid = webView.bounds.size
        let b = container.bounds
        guard laid.width > 0, laid.height > 0, b.width > 0, b.height > 0 else { return }
        webView.frame = NSRect(x: (b.width - laid.width) / 2, y: (b.height - laid.height) / 2,
                               width: laid.width, height: laid.height)
        // Scaling happens about the layer's anchor point, wherever that is; the shift puts the
        // result back on the frame. With the usual centre anchor the shift is zero.
        let a = layer.anchorPoint
        let shift = NSPoint(x: (b.width - laid.width) * (a.x - 0.5), y: (b.height - laid.height) * (a.y - 0.5))
        layer.transform = CATransform3DConcat(CATransform3DMakeScale(b.width / laid.width, b.height / laid.height, 1),
                                              CATransform3DMakeTranslation(shift.x, shift.y, 0))
    }

    /// Lays the page out at the size it is drawn at, so it renders at the screen's own resolution
    /// again. Only at rest: between rest positions the web view keeps its layout and `fitWebView`
    /// scales it, because a resize costs a round trip to the web process and the page paints the
    /// new size a frame or more later. A picture of the page covers that gap.
    private func layoutPageAtFrame() {
        guard let webView, let container, webView.bounds.size != container.bounds.size else { return }
        guard cover == nil else { resizeWebView(); return }
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = false
        webView.takeSnapshot(with: config) { [weak self] image, _ in
            guard let self, let webView = self.webView, let container = self.container,
                  webView.bounds.size != container.bounds.size else { return }
            // A snapshot is a round trip to the web process: a momentum tail can resume while it is
            // out. Laying the page out then would resize it under a moving frame.
            guard self.zoomTween.value == self.zoomTarget else { return }
            if let image { self.showCover(image) }
            self.resizeWebView()
        }
    }

    /// The resize itself. `prepare` calls it directly: nothing is on screen to cover.
    private func resizeWebView() {
        guard let webView, let container else { return }
        webView.frame = container.bounds
        webView.layer?.transform = CATransform3DIdentity
        uncoverWhenPainted()
    }

    private func showCover(_ image: NSImage) {
        guard let container, let webView else { return }
        removeCover()
        let view = NSImageView(frame: container.bounds)
        view.image = image
        view.imageScaling = .scaleAxesIndependently
        view.autoresizingMask = [.width, .height]
        container.addSubview(view, positioned: .above, relativeTo: webView)
        cover = view
    }

    /// Takes the cover down once the page has painted at its new size: two of its frames, the
    /// second after its resize observer has refitted. A deadline backs that up in case the page
    /// never answers; it is a main-queue hop, which still runs while a gesture is tracking.
    private func uncoverWhenPainted() {
        guard cover != nil else { return }
        coverEpoch += 1
        let epoch = coverEpoch
        let frames = "await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));"
        webView?.callAsyncJavaScript(frames, arguments: [:], in: nil, in: .page) { [weak self] _ in
            guard let self, self.coverEpoch == epoch else { return }
            self.removeCover()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.coverEpoch == epoch else { return }
            self.removeCover()
        }
    }

    private func removeCover() {
        guard cover != nil else { return }
        cover?.removeFromSuperview()
        cover = nil
    }

    /// The spring has arrived. A pull below the fitted size lets go here; otherwise the page is
    /// laid out at its new size, on the next turn of the run loop rather than inside the tick that
    /// just ran, and only if nothing has aimed the zoom somewhere else meanwhile.
    private func arrived() {
        if zoomTarget < 1 { zoom(by: nil, at: nil, as: .step); return }
        guard !pageLayoutPending else { return }
        pageLayoutPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pageLayoutPending = false
            guard self.zoomTween.value == self.zoomTarget else { return }
            self.layoutPageAtFrame()
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

    /// The trackpad's two-finger double tap, as Preview and Safari use it: in on the point tapped,
    /// or back to the fitted size from anywhere above it.
    private func smartZoom(at locationInWindow: NSPoint) {
        guard window?.isVisible == true else { return }
        let zoomedIn = zoomTarget > 1.001
        zoom(by: zoomedIn ? nil : smartZoomFactor, at: zoomedIn ? nil : cursorFraction(locationInWindow), as: .step)
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

    /// `cursor` is the point the page keeps in place, a fraction of the window.
    ///
    /// Sent at the page's pace, not the display link's. The window fills the screen at a modest
    /// level on a large image, so almost all of a zoom is the camera phase, and a call per tick at
    /// 120 Hz would queue work in the web process faster than it can run it. One call is in flight
    /// at a time; the latest value goes when it returns, and the ones in between are dropped,
    /// because only the last one is where the camera should be.
    private func setCanvasZoom(_ ratio: CGFloat, at cursor: CGPoint) {
        guard abs(ratio - canvasZoom) > 1e-6 else { return }
        canvasZoom = ratio
        if cameraInFlight { cameraPending = (ratio, cursor); return }
        sendCanvasZoom(ratio, at: cursor)
    }

    private func sendCanvasZoom(_ ratio: CGFloat, at cursor: CGPoint) {
        guard let webView else { return }
        cameraInFlight = true
        webView.evaluateJavaScript(PageAPI.setCanvasZoom(Double(ratio), at: cursor).script) { [weak self] _, error in
            guard let self else { return }
            self.cameraInFlight = false
            if let error { Log.write("[web] error call failed: \(String(describing: error).replacingOccurrences(of: "\n", with: " "))") }
            guard let next = self.cameraPending else { return }
            self.cameraPending = nil
            self.sendCanvasZoom(next.ratio, at: next.cursor)
        }
    }

    func show() {
        guard let win = window, current != nil else { return }
        win.alphaValue = 1
        win.makeKeyAndOrderFront(nil)
        if toolbar.panel.parent == nil { win.addChildWindow(toolbar.panel, ordered: .above) }
        toolbar.show()
        NSApp.activate(ignoringOtherApps: true)
        installOutsideClickMonitor()
    }

    /// Parks the draft, then removes the window. `then` runs once the page has answered, so a
    /// transition that starts there shows the annotations. Called once per `prepare`, by the reducer.
    func hide(then completion: (() -> Void)? = nil) {
        removeOutsideClickMonitor()
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
        guard let shot = current, let webView, pageReady else { answered = true; finish(); return }
        current = nil
        let epoch = pageEpoch
        let done: () -> Void = {
            guard !answered else { return }
            answered = true
            finish()
        }
        pendingHide = done
        // The page runs park, export, and build one at a time, so an Esc during a long Copy
        // Annotated waits behind it. The window comes down on this deadline whatever the page does;
        // a park that answers after it is dropped, because by then the canvas may hold another image.
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
        zoomCursor = Zoom.center
        zoomTarget = 1
        aim(at: Zoom.center, to: split(1).window)
        zoomTween.animate(to: 1, duration: motionScaled(fitToCloseSeconds), curve: "spring", completion: once)
        DispatchQueue.main.asyncAfter(deadline: .now() + motionScaled(fitToCloseSeconds) + 0.3) { once() }
    }

    private func hideWindows() {
        // Nothing here is on screen any more: a spring still ticking would move a hidden frame,
        // call the page's camera after `reset` has emptied it, and relayout a hidden web view.
        zoomTween.stop()
        pageLayoutPending = false
        cameraPending = nil
        coverEpoch += 1
        removeCover()
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
        // Sized by hand: a zoom keeps the layout and scales the layer; see `fitWebView`.
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
            pixelWidth: size.width, pixelHeight: size.height,
            viewWidth: windowSize.width, viewHeight: windowSize.height)
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

    /// Every color the page can draw a mark in, by id: what a mark's `color` may name. Not the
    /// toolbar's swatches, which are empty while the palette is hidden.
    private(set) var colorIDs: [String] = []

    /// Why nothing may borrow the page's canvas right now, or nil when it is free. A marks build
    /// and a preview rendering both put their own image there for the length of one rendering, so
    /// they wait for the annotator; `add` asks before it copies anything, so a refusal is one error
    /// line and no file left behind.
    var canvasRefusal: String? {
        if webView == nil || !pageReady { return "the editor page is not ready" }
        if holdsCanvas { return "an image is in the annotator" }
        // Copy Annotated and a launch-time preview both run through `exportDrafts`, so this says
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
        guard let pixels = Thumbnailer.pixelSize(of: shot.url), let points = Thumbnailer.pointSize(of: shot.url) else {
            completion(nil, "could not read \(shot.url.lastPathComponent)"); return
        }
        // The frame the image would open in: the page does not lay anything out for a build, but the
        // payload says what a view of it looks like.
        let frame = StackLayout.current.annotationFrame(
            for: points, visibleFrame: (NSScreen.main ?? NSScreen.screens[0]).visibleFrame, below: spaceBelow)
        let payload = LoadPayload(
            key: shot.url.path, mimeType: LocalServer.mimeType(for: shot.url.pathExtension),
            pixelWidth: pixels.width, pixelHeight: pixels.height,
            viewWidth: frame.width, viewHeight: frame.height)
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

    /// A click outside this app's windows ends the session.
    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = OutsideClick.monitor { [weak self] in self?.cancel() }
    }

    private func removeOutsideClickMonitor() {
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m) }
        outsideClickMonitor = nil
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let msg = WebMessage(body: message.body) else {
            Log.write("[web] unrecognized message \(WebMessage.describe(message.body))")
            return
        }
        switch msg {
        case .ready(let version, let tools, let colors, let markColors):
            guard version == bridgeProtocolVersion else {
                pageFailed = true
                Log.write("[web] error protocol-mismatch page=\(version) app=\(bridgeProtocolVersion); rebuild with scripts/build.sh")
                onProblem?("The editor page is out of date; rebuild the app")
                return
            }
            Log.write("[web] ready protocol=\(version) tools=\(tools.count) colors=\(colors.count) markColors=\(markColors.count)")
            pageReady = true
            toolbar.model.tools = tools
            toolbar.model.colors = colors
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
        case .zoom(let factor, let at):
            // A cursor names a gesture: the wheel and the pinch send the point they are over, a
            // key sends none. The two differ only in how long their spring is.
            zoom(by: factor, at: at, as: at == nil ? .step : .gesture)
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
