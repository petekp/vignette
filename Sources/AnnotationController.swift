import AppKit
import WebKit

/// Hosts the tldraw editor in a WKWebView. Preloaded at launch so opening feels instant.
final class AnnotationController: NSObject, WKScriptMessageHandler, WKNavigationDelegate, NSWindowDelegate {
    var onFinished: ((Screenshot, Data) -> Void)?

    private var webView: WKWebView!
    private var server: LocalServer?
    private var window: NSWindow?
    private var current: Screenshot?
    private var pageReady = false
    private var pendingScript: String?

    func preload() {
        guard let dist = Bundle.main.url(forResource: "dist", withExtension: nil) else {
            Log.write("Shotnote: web/dist missing from bundle")
            return
        }
        let server = LocalServer(root: dist)
        do { try server.start() } catch { Log.write("LocalServer start failed: \(error)"); return }
        self.server = server
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "shotnote")
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.load(URLRequest(url: server.indexURL))
    }

    func present(_ shot: Screenshot, from frame: NSRect) {
        current = shot
        let win = window ?? makeWindow()
        win.setFrame(frame, display: false)
        win.contentView = webView
        webView.layoutSubtreeIfNeeded()
        // Load after the view has its final size so tldraw's initial camera fit matches the window.
        sendImage(shot, windowSize: frame.size)
        win.alphaValue = 0
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            win.animator().alphaValue = 1
        }
    }

    private func makeWindow() -> NSWindow {
        let win = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView, .resizable], backing: .buffered, defer: false)
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = false
        win.level = .floating
        win.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1)
        win.isReleasedWhenClosed = false
        win.delegate = self
        window = win
        return win
    }

    private func sendImage(_ shot: Screenshot, windowSize: NSSize) {
        guard let data = try? Data(contentsOf: shot.url), let rep = NSBitmapImageRep(data: data) else { return }
        let payload: [String: Any] = [
            "dataUrl": "data:image/png;base64," + data.base64EncodedString(),
            "pixelWidth": rep.pixelsWide,
            "pixelHeight": rep.pixelsHigh,
            "viewWidth": windowSize.width,
            "viewHeight": windowSize.height,
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: json, encoding: .utf8) else { return }
        let script = "window.shotnote && window.shotnote.load(\(text));"
        if pageReady { run(script) } else { pendingScript = script }
    }

    private func run(_ script: String) {
        webView.evaluateJavaScript(script) { _, error in
            if let error { Log.write("evaluateJavaScript failed: \(error)") }
        }
    }

    /// Debug: shows the editor window without loading an image.
    func presentEmpty() {
        let frame = StackLayout.annotationFrame(for: NSSize(width: 1200, height: 800), on: NSScreen.main!)
        let win = window ?? makeWindow()
        win.setFrame(frame, display: false)
        win.contentView = webView
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func close() {
        guard let win = window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            win.animator().alphaValue = 0
        }, completionHandler: {
            win.orderOut(nil)
            self.webView.evaluateJavaScript("window.shotnote && window.shotnote.reset();")
        })
        current = nil
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            Log.write("Shotnote web ready")
            pageReady = true
            if let s = pendingScript { run(s); pendingScript = nil }
        case "done":
            guard let shot = current, let b64 = body["png"] as? String else { return }
            let clean = b64.replacingOccurrences(of: "data:image/png;base64,", with: "")
            if let data = Data(base64Encoded: clean) { onFinished?(shot, data) }
            close()
        case "cancel":
            close()
        case "log":
            Log.write("Shotnote web: \(body["message"] ?? "")")
        default:
            break
        }
    }

    /// Logs what the page has rendered. Driven by shotnote://debug.
    func dumpState() {
        webView.evaluateJavaScript("JSON.stringify({title: document.title, root: document.getElementById('root')?.children.length, api: typeof window.shotnote, canvas: document.querySelector('.tl-canvas') != null, images: document.querySelectorAll('.tl-image').length, toolbar: document.querySelector('.toolbar') != null, inner: [innerWidth, innerHeight], container: document.querySelector('.tl-container') != null, html: document.getElementById('root').innerHTML.slice(0, 500), url: location.href})") { result, error in
            Log.write("Shotnote page state: \(result ?? "nil") error: \(error?.localizedDescription ?? "none")")
        }
        Log.write("webView frame=\(webView.frame) hidden=\(webView.isHidden) inWindow=\(webView.window != nil) windowVisible=\(window?.isVisible ?? false) windowFrame=\(window?.frame ?? .zero) contentView=\(String(describing: window?.contentView === webView))")
        if false {
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Log.write("Shotnote web loaded: \(webView.url?.absoluteString ?? "?")")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Log.write("Shotnote web failed to load: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Log.write("Shotnote web navigation failed: \(error.localizedDescription)")
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        close()
        return false
    }
}
