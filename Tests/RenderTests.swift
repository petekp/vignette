import AppKit
import WebKit
import XCTest

/// The page's `render` is a workaround for tldraw's export, which rasterizes blank in WebKit when
/// the SVG embeds the screenshot. This loads the built page into a real WKWebView over the
/// loopback server, exactly as the app does, and checks the exported pixels: the screenshot
/// where there is no annotation, and the annotation's color where there is one.
@MainActor
final class RenderTests: XCTestCase {
    private var dir: URL!
    private var server: LocalServer!
    private var webView: WKWebView!
    private var messages: [String: [String: Any]] = [:]
    private var expectations: [String: XCTestExpectation] = [:]

    /// Solid dark blue, 400x300, so any pixel that is not this color came from somewhere else.
    private let background = (r: 20, g: 40, b: 120)
    private let pixelWidth = 400, pixelHeight = 300

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("shotnote-render-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelWidth, pixelsHigh: pixelHeight, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let color = NSColor(deviceRed: CGFloat(background.r) / 255, green: CGFloat(background.g) / 255, blue: CGFloat(background.b) / 255, alpha: 1)
        for y in 0..<pixelHeight { for x in 0..<pixelWidth { rep.setColor(color, atX: x, y: y) } }
        try rep.representation(using: .png, properties: [:])!.write(to: fixture)
        let dist = try XCTUnwrap(Bundle(for: RenderTests.self).url(forResource: "dist", withExtension: nil), "web/dist is a test resource (project.yml)")
        let access = LocalServer.FileAccess()
        access.update(folder: dir, unrestricted: false)
        server = LocalServer(root: dist, access: access)
        try server.start()
        XCTAssertNotEqual(server.port, 0)
        let config = WKWebViewConfiguration()
        config.userContentController.add(Handler(owner: self), name: "shotnote")
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        webView.load(URLRequest(url: server.indexURL))
    }

    override func tearDownWithError() throws {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "shotnote")
        try FileManager.default.removeItem(at: dir)
    }

    private var fixture: URL { dir.appendingPathComponent("Screenshot fixture.png") }

    private final class Handler: NSObject, WKScriptMessageHandler {
        weak var owner: RenderTests?
        init(owner: RenderTests) { self.owner = owner }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            MainActor.assumeIsolated { owner?.received(message.body) }
        }
    }

    private func received(_ body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return }
        messages[type] = dict
        expectations[type]?.fulfill()
    }

    private func waitFor(_ type: String, timeout: TimeInterval = 15) {
        if messages[type] != nil { return }
        let e = expectation(description: type)
        expectations[type] = e
        wait(for: [e], timeout: timeout)
        expectations[type] = nil
    }

    /// Runs `script` as an async function body and returns its value.
    private func eval(_ script: String, timeout: TimeInterval = 15) throws -> Any? {
        var out: Result<Any?, Error>?
        let e = expectation(description: "eval")
        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { out = $0.map { $0 as Any? }; e.fulfill() }
        wait(for: [e], timeout: timeout)
        return try XCTUnwrap(out).get()
    }

    private func pixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
        return (Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255), Int(c.alphaComponent * 255))
    }

    func testExportKeepsTheScreenshotAndDrawsTheAnnotation() throws {
        waitFor("ready")
        XCTAssertEqual(messages["ready"]?["protocol"] as? Int, bridgeProtocolVersion, "the built page must match the app's protocol")
        let payload = LoadPayload(key: fixture.path, mimeType: "image/png", pixelWidth: pixelWidth, pixelHeight: pixelHeight, viewWidth: 800, viewHeight: 600)
        _ = try eval(PageAPI.load(payload, snapshot: nil).script)
        // The page confirms `loaded` from a requestAnimationFrame, which never fires in a view that
        // is not on screen, so poll for the image shape instead.
        for _ in 0..<50 where try eval("return window.editor ? window.editor.getShape('shape:screenshot') != null : false") as? Bool != true {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(try eval("return window.editor.getCurrentPageShapeIds().size") as? Int, 1)
        // A solid red rectangle over the middle half of the image, in canvas points.
        _ = try eval("""
            const img = window.editor.getShape('shape:screenshot');
            window.editor.createShape({ type: 'geo', x: img.props.w / 4, y: img.props.h / 4,
              props: { w: img.props.w / 2, h: img.props.h / 2, geo: 'rectangle', color: 'red', fill: 'solid' } });
            return window.editor.getCurrentPageShapeIds().size;
            """)
        let result = try XCTUnwrap(ExportResult(body: try eval(PageAPI.export([(key: fixture.path, snapshot: Data("{}".utf8))]).script)))
        XCTAssertNil(result.error, result.error ?? "")
        let png = try XCTUnwrap(result.pngs[fixture.path], "one rendering for the key")
        let rep = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(rep.pixelsWide, pixelWidth, "exports are at the screenshot's pixel size")
        XCTAssertEqual(rep.pixelsHigh, pixelHeight)
        // Canvas drawing is color managed, so the fixture's blue comes back shifted by a few
        // dozen units; a blank export would be transparent or white, and red would be red.
        let corner = pixel(rep, 8, 8)
        XCTAssertEqual(corner.a, 255, "the screenshot is under the annotation: \(corner)")
        XCTAssertLessThan(abs(corner.r - background.r) + abs(corner.g - background.g) + abs(corner.b - background.b), 60, "the screenshot is under the annotation: \(corner)")
        XCTAssertGreaterThan(corner.b, corner.r + 60, "the screenshot is under the annotation: \(corner)")
        // The page runs tldraw in its dark scheme, where a solid red fill is a dark red tint.
        let center = pixel(rep, pixelWidth / 2, pixelHeight / 2)
        XCTAssertGreaterThan(center.r, center.b, "the red fill covers the middle: \(center)")
        XCTAssertGreaterThan(abs(center.r - background.r) + abs(center.g - background.g) + abs(center.b - background.b), 100, "the annotation changed the middle: \(center)")
        XCTAssertEqual(try eval("return window.editor.getCanUndo()") as? Bool, true, "export leaves the drawing's undo entry in place")
    }
}
