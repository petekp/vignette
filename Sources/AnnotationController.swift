import AppKit
import WebKit

/// Hosts the tldraw editor in a WKWebView. Preloaded at launch so opening feels instant.
/// Lifecycle: `prepare` sizes the hidden window and loads the image, `show` reveals it once the
/// card transition has landed, `hide` removes it at once for a swap, and the page's cancel/done
/// messages end a session through `close`.
@MainActor
final class AnnotationController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var onFinished: ((Screenshot, Data) -> Void)?
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
    private var container: NSView?
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
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        webView.navigationDelegate = self
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
        win.setFrame(frame, display: false)
        applyCornerRadius()
        toolbar.place(below: frame, gap: Settings.shared.data.ui.annotationToolbarGap)
        webView.layoutSubtreeIfNeeded()
        sendImage(shot, windowSize: frame.size)
    }

    func show() {
        guard let win = window, current != nil else { return }
        win.alphaValue = 1
        win.makeKeyAndOrderFront(nil)
        if toolbar.panel.parent == nil { win.addChildWindow(toolbar.panel, ordered: .above) }
        toolbar.panel.orderFront(nil)
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
        if let win = window, toolbar.panel.parent === win { win.removeChildWindow(toolbar.panel) }
        toolbar.panel.orderOut(nil)
        window?.orderOut(nil)
    }

    private func makeWindow(_ webView: WKWebView) -> AnnotationWindow {
        let win = AnnotationWindow(contentRect: .zero, styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = .floating
        win.isMovableByWindowBackground = false
        win.isReleasedWhenClosed = false
        win.animationBehavior = .none
        win.onCloseRequest = { [weak self] in self?.cancel() }
        let container = NSView()
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        container.autoresizesSubviews = true
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
        win.contentView = container
        self.container = container
        window = win
        return win
    }

    private func applyCornerRadius() {
        container?.layer?.cornerRadius = Settings.shared.data.ui.annotationCornerRadius
        container?.layer?.cornerCurve = .continuous
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
        win.setFrame(frame, display: false)
        applyCornerRadius()
        toolbar.place(below: frame, gap: Settings.shared.data.ui.annotationToolbarGap)
        win.makeKeyAndOrderFront(nil)
        if toolbar.panel.parent == nil { win.addChildWindow(toolbar.panel, ordered: .above) }
        toolbar.panel.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Ends the session as Esc would. `open shotnote://cancel`. False when nothing was open.
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
            else if let shot = current, let win = window { sendImage(shot, windowSize: win.frame.size) }
        case .tool(let tool, let color):
            toolbar.model.tool = tool
            toolbar.model.color = color
        case .loaded(let key):
            let ms = loadStarted.removeValue(forKey: key).map { Int((CACurrentMediaTime() - $0) * 1000) } ?? -1
            Log.write("[annotate] loaded \(ms)ms \((key as NSString).lastPathComponent)")
            onLoaded?(key)
        case .done(let png):
            guard let shot = current else { return }
            onDraftPreview?(shot.url.path, png)
            onFinished?(shot, png)
            onClosed?()
        case .cancel:
            cancel()
        case .log(let text):
            Log.write("[web] \(text)")
        case .draft(let key, let snapshot):
            onDraft?(key, snapshot)
        }
    }

    var stateDescription: String {
        "current=\(current?.url.lastPathComponent ?? "nil") windowVisible=\(window?.isVisible ?? false) frame=\(window?.frame ?? .zero) pageReady=\(pageReady) webPid=\(webProcessID.map(String.init) ?? "unknown")"
    }

    /// Logs what the page has rendered. Driven by shotnote://state.
    func dumpPageState() {
        guard let webView else { Log.write("[web] no page"); return }
        webView.evaluateJavaScript("JSON.stringify({title: document.title, root: document.getElementById('root')?.children.length, api: typeof window.shotnote, canvas: document.querySelector('.tl-canvas') != null, images: document.querySelectorAll('.tl-image').length, toolbar: document.querySelector('.toolbar') != null, inner: [innerWidth, innerHeight], page: location.pathname.split('/').pop()})") { result, error in
            Log.write("[web] page state: \(result ?? "nil") error: \(error?.localizedDescription ?? "none")")
        }
        Log.write("[web] view frame=\(webView.frame) inWindow=\(webView.window != nil) windowVisible=\(window?.isVisible ?? false) windowFrame=\(window?.frame ?? .zero)")
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
final class AnnotationWindow: NSWindow {
    var onCloseRequest: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func performClose(_ sender: Any?) { onCloseRequest?() }
}
