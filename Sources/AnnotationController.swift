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

    /// Nil when the bundle has no page or the server did not start; every call then no-ops.
    private var webView: WKWebView?
    private let toolbar = AnnotatorToolbar()
    private var server: LocalServer?
    private var window: AnnotationWindow?
    /// The window spans the screen's visible frame and stays put. The visible frame is `frameView`
    /// inside it (shadow) with `container` (clip, corner, ring, web view), so a zoom step moves the
    /// frame and scales the page in one layer commit: a window resize and a layer change do not
    /// land on the same display frame, and the image would drift from the frame between them.
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
    /// The hide waiting on the page's park, so a process restart still hides the window.
    private var pendingHide: (() -> Void)?
    /// How long Copy Annotated waits for the page before giving up.
    static let exportTimeout: TimeInterval = 15

    /// Room the annotator needs below its window: the toolbar and its gap.
    var spaceBelow: CGFloat { AnnotatorToolbar.height + Settings.shared.data.ui.annotationToolbarGap }

    /// The frame `prepare` fitted the image into; zoom scales the window from here.
    private var fittedFrame: NSRect = .zero
    private lazy var zoom = Tween(initial: 1) { [weak self] v in self?.applyZoom(v) }
    /// The window's scale on screen. Reset to 1 for each image.
    private(set) var zoomScale: CGFloat = 1
    /// Where zooming has pushed the window scale; below 1 only while a gesture pulls against the fitted size.
    private var windowTarget: CGFloat = 1
    /// Magnification inside a window that can grow no further; 1 fits the image.
    private(set) var canvasZoom: CGFloat = 1
    private var settleTimer: Timer?
    /// How much of a pull below the fitted size the window shows before springing back.
    private let overpull: CGFloat = 0.3
    private let maxCanvasZoom: CGFloat = 8
    /// The window scale the page was last laid out at. Between rest positions the web view keeps
    /// that layout and a layer transform scales it with the window, so image and frame move in
    /// the same commit; a real relayout (and the page's refit) happens once, at rest.
    private var committedScale: CGFloat = 1
    /// A snapshot of the scaled page shown over the web view while it relays out at rest: the web
    /// process paints the new size a frame or two later, and the old size would flash meanwhile.
    private var cover: NSImageView?
    private var uncoverTimer: Timer?

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
        webView.onMagnify = { [weak self] magnification, phase in self?.pinch(magnification, phase: phase) }
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
        windowTarget = 1
        canvasZoom = 1
        settleTimer?.invalidate()
        zoom.set(1)
        place(win, frame: frame)
        committedScale = 1
        removeCover()
        layoutWebView()
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

    /// Zoom in grows the window around its center until it fills the screen, then magnifies the
    /// image inside it. Zoom out reverses that and stops at the fitted size: pulling further
    /// shrinks the window a little and it springs back once the gesture ends. The toolbar stays
    /// where it is. A gesture tracks directly, a keyboard step springs.
    func zoom(by factor: Double?, animated: Bool) {
        guard window != nil, fittedFrame.width > 0 else { return }
        settleTimer?.invalidate()
        removeCover()
        guard let factor else {
            setCanvasZoom(1)
            windowTarget = 1
            zoom.animate(to: 1, duration: 0.3, curve: "spring")
            return
        }
        var f = CGFloat(factor)
        if f > 1 {
            let grown = min(maxZoom, max(1, windowTarget) * f)
            f *= max(1, windowTarget) / grown   // the part the window could not take
            windowTarget = grown
            if f > 1 { setCanvasZoom(min(maxCanvasZoom, canvasZoom * f)) }
        } else {
            let shrunk = max(1, canvasZoom * f)
            f *= canvasZoom / shrunk
            setCanvasZoom(shrunk)
            windowTarget = max(0.5, windowTarget * f)
        }
        let shown = windowTarget < 1 ? 1 - (1 - windowTarget) * overpull : windowTarget
        if animated {
            zoom.animate(to: shown, duration: 0.3, curve: "spring") { [weak self] in
                guard let self, self.windowTarget >= 1 else { return }   // a pull settles on its own
                self.commitZoom()
            }
        } else {
            zoom.set(shown)
        }
        if !animated || windowTarget < 1 { scheduleSettle() }
    }

    /// Lays the page out at the window's current size and drops the live transform. A snapshot of
    /// the scaled page covers the change until the page has painted at the new size.
    private func commitZoom() {
        guard let webView, let container else { return }
        let scale = zoomScale
        guard scale != committedScale else { layoutWebView(); return }
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = false
        webView.takeSnapshot(with: config) { [weak self] image, _ in
            guard let self, self.zoomScale == scale, self.committedScale != scale else { return }   // a new gesture settles again
            if let image {
                let cover = NSImageView(frame: container.bounds)
                cover.image = image
                cover.imageScaling = .scaleAxesIndependently
                cover.autoresizingMask = [.width, .height]
                container.addSubview(cover, positioned: .above, relativeTo: webView)
                self.cover = cover
            }
            self.committedScale = scale
            self.layoutWebView()
            self.uncoverAfterPaint()
        }
    }

    /// Three frames: the resize reaches the page in one, its refit and paint land in the next,
    /// and the third is a margin. A timer backs it up in case the page is busy.
    private func uncoverAfterPaint() {
        uncoverTimer?.invalidate()
        uncoverTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.removeCover() }
        }
        let frames = "await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(r))));"
        webView?.callAsyncJavaScript(frames, arguments: [:], in: nil, in: .page) { [weak self] _ in self?.removeCover() }
    }

    private func removeCover() {
        uncoverTimer?.invalidate()
        uncoverTimer = nil
        cover?.removeFromSuperview()
        cover = nil
    }

    private func layoutWebView() {
        guard let webView, let container else { return }
        webView.layer?.transform = CATransform3DIdentity
        webView.frame = container.bounds
    }

    private func scaleWebView(_ scale: CGFloat) {
        guard let webView, let container, let layer = webView.layer else { return }
        let s = scale / committedScale
        let size = NSSize(width: fittedFrame.width * committedScale, height: fittedFrame.height * committedScale)
        let bounds = container.bounds
        webView.frame = NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        // Scale about the container's center whatever the layer's anchor point is: scaling about
        // the anchor A moves the center C to A + s(C - A), and the translation puts it back.
        let a = layer.anchorPoint
        let anchor = NSPoint(x: webView.frame.minX + a.x * size.width, y: webView.frame.minY + a.y * size.height)
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let shift = NSPoint(x: (center.x - anchor.x) * (1 - s), y: (center.y - anchor.y) * (1 - s))
        layer.transform = CATransform3DConcat(CATransform3DMakeScale(s, s, 1), CATransform3DMakeTranslation(shift.x, shift.y, 0))
    }

    /// A trackpad pinch, straight from AppKit: WebKit would otherwise turn it into gesture events
    /// the page zooms on. The pull springs back the moment the fingers lift.
    private func pinch(_ magnification: CGFloat, phase: NSEvent.Phase) {
        switch phase {
        case .ended, .cancelled: settleNow()
        default: zoom(by: Double(1 + magnification), animated: false)
        }
    }

    /// A pull below the fitted size lets go shortly after the last zoom message, for cmd+wheel
    /// and keyboard steps that have no end event.
    private func scheduleSettle() {
        settleTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.settleNow() }
        }
    }

    private func settleNow() {
        settleTimer?.invalidate()
        guard windowTarget < 1 else { commitZoom(); return }
        windowTarget = 1
        zoom.animate(to: 1, duration: 0.35, curve: "spring") { [weak self] in self?.commitZoom() }
    }

    private func setCanvasZoom(_ ratio: CGFloat) {
        guard ratio != canvasZoom else { return }
        canvasZoom = ratio
        call(.setCanvasZoom(Double(ratio)))
    }
    /// The window may grow to the whole visible screen, past the fitted inset and the toolbar's room.
    private var maxZoom: CGFloat {
        guard let screen = zoomScreen else { return 1 }
        let v = screen.visibleFrame
        return max(1, min(v.width / fittedFrame.width, v.height / fittedFrame.height))
    }

    private func applyZoom(_ scale: CGFloat) {
        guard window != nil, fittedFrame.width > 0 else { return }
        zoomScale = scale
        var f = NSRect(x: 0, y: 0, width: fittedFrame.width * scale, height: fittedFrame.height * scale)
        f.origin = NSPoint(x: fittedFrame.midX - f.width / 2, y: fittedFrame.midY - f.height / 2)
        if let v = zoomScreen?.visibleFrame {
            // Kept on screen: a frame grown to the screen's height slides rather than clips.
            f.origin.x = min(max(f.origin.x, v.minX), max(v.minX, v.maxX - f.width))
            f.origin.y = min(max(f.origin.y, v.minY), max(v.minY, v.maxY - f.height))
        }
        moveFrame(to: f.integral)
        scaleWebView(scale)
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
        guard let shot = current, let webView, pageReady else { hideWindows(); completion?(); return }
        current = nil
        let epoch = pageEpoch
        let done: () -> Void = { [weak self] in
            self?.pendingHide = nil
            self?.hideWindows()
            completion?()
        }
        pendingHide = done
        webView.callAsyncJavaScript(PageAPI.park.script, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self, self.pageEpoch == epoch, self.pendingHide != nil else { return }
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

    private func hideWindows() {
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
        frameView.layer?.shadowColor = NSColor.black.cgColor
        frameView.layer?.shadowOpacity = 0.45
        frameView.layer?.shadowRadius = 24
        frameView.layer?.shadowOffset = CGSize(width: 0, height: -10)
        let container = NSView()
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        container.autoresizesSubviews = true
        webView.frame = container.bounds
        // Sized by hand: see `committedScale`.
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
            completion(pngs, error)
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
        layoutWebView()
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
        case .ready(let version, let tools, let colors):
            guard version == bridgeProtocolVersion else {
                pageFailed = true
                Log.write("[web] error protocol-mismatch page=\(version) app=\(bridgeProtocolVersion); rebuild with scripts/build.sh")
                onProblem?("The editor page is out of date; rebuild the app")
                return
            }
            Log.write("[web] ready protocol=\(version) tools=\(tools.count) colors=\(colors.count)")
            pageReady = true
            toolbar.model.tools = tools
            toolbar.model.colors = colors
            if let call = pendingCall { self.call(call); pendingCall = nil }
            // After a web process restart the window is still up: put its image and stored draft back.
            else if let shot = current, let container { sendImage(shot, windowSize: container.bounds.size) }
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
        case .zoom(let factor):
            zoom(by: factor, animated: factor == nil || abs(log(factor!)) >= log(1.2))
        }
    }

    var stateJSON: [String: Any] {
        [
            "current": current?.url.path as Any,
            "windowVisible": window?.isVisible ?? false,
            "zoom": zoomScale,
            "canvasZoom": canvasZoom,
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
        let script = "return {title: document.title, root: document.getElementById('root')?.children.length, api: typeof window.shotnote, canvas: document.querySelector('.tl-canvas') != null, images: document.querySelectorAll('.tl-image').length, shapes: window.editor ? window.editor.getCurrentPageShapeIds().size : null, canUndo: window.editor ? window.editor.getCanUndo() : null, zoom: window.editor ? window.editor.getZoomLevel() / window.editor.getBaseZoom() : null, inner: [innerWidth, innerHeight], hidden: document.hidden, page: location.pathname.split('/').pop()};"
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
        pendingHide?()
        onProblem?("The editor restarted")
        webView.reload()
    }
}

/// Borderless windows refuse key status by default; the editor needs it for typing and shortcuts.
@MainActor
/// Takes the trackpad pinch before WebKit does, so zoom stays the app's (see `AnnotationController.zoom`).
final class AnnotationWebView: WKWebView {
    var onMagnify: ((CGFloat, NSEvent.Phase) -> Void)?
    override func magnify(with event: NSEvent) {
        onMagnify?(event.magnification, event.phase)
    }
}

final class AnnotationWindow: NSWindow {
    var onCloseRequest: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func performClose(_ sender: Any?) { onCloseRequest?() }
}
