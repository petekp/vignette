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
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-render-\(UUID().uuidString)")
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
        config.userContentController.add(Handler(owner: self), name: "vignette")
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        webView.load(URLRequest(url: server.indexURL))
    }

    override func tearDownWithError() throws {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "vignette")
        try FileManager.default.removeItem(at: dir)
    }

    private var fixture: URL { dir.appendingPathComponent("Screenshot fixture.png") }

    @MainActor
    private final class Handler: NSObject, WKScriptMessageHandler {
        weak var owner: RenderTests?
        init(owner: RenderTests) { self.owner = owner }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            owner?.received(message.body)
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

    /// Pixels no part of the blue fixture can produce, so they came from a red annotation.
    private func redPixels(_ rep: NSBitmapImageRep) -> Int {
        var count = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) where pixel(rep, x, y).r > pixel(rep, x, y).b + 60 { count += 1 }
        }
        return count
    }

    /// Loads the fixture and waits for the image shape. `loaded` is posted from a
    /// requestAnimationFrame, which never fires in a view that is not on screen, so this polls.
    private func loadFixture(snapshot: Data? = nil) throws {
        _ = try eval(PageAPI.load(payload, snapshot: snapshot).script)
        for _ in 0..<50 where try eval("return window.editor ? window.editor.getShape('shape:screenshot') != null : false") as? Bool != true {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
    }

    private var payload: LoadPayload {
        LoadPayload(key: fixture.path, mimeType: "image/png", pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }

    func testExportKeepsTheScreenshotAndDrawsTheAnnotation() throws {
        waitFor("ready")
        XCTAssertEqual(messages["ready"]?["protocol"] as? Int, bridgeProtocolVersion, "the built page must match the app's protocol")
        try loadFixture()
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

    /// The overlay is what the host lays over the screenshot while a zoom is moving: the same
    /// annotations the export draws, alone, clear everywhere else, and no larger than the cap the
    /// host asked for. The page sends one after every change, behind the draft's debounce.
    func testTheOverlayIsTheAnnotationsAloneAndHonoursTheCap() throws {
        waitFor("ready")
        try loadFixture()
        XCTAssertNil(try eval(PageAPI.overlay(maxPixel: 2048).script) as? String, "nothing drawn, no overlay")
        // A solid red rectangle over the middle half of the image, in canvas points.
        _ = try eval("""
            const img = window.editor.getShape('shape:screenshot');
            window.editor.createShape({ id: 'shape:mark', type: 'geo', x: img.props.w / 4, y: img.props.h / 4,
              props: { w: img.props.w / 2, h: img.props.h / 2, geo: 'rectangle', color: 'red', fill: 'solid' } });
            window.editor.setSelectedShapes(['shape:mark']);
            return window.editor.getCurrentPageShapeIds().size;
            """)
        let full = try XCTUnwrap(NSBitmapImageRep(data: try overlay(maxPixel: 2048)))
        // The screenshot is 400 x 300 pixels at 2x, so 200 x 150 canvas points; under the cap the
        // overlay is rendered at the device's own scale, which is the screenshot's pixel size.
        XCTAssertEqual(full.pixelsWide, pixelWidth, "under the cap the overlay is the image's own size")
        XCTAssertEqual(full.pixelsHigh, pixelHeight)
        XCTAssertEqual(pixel(full, 8, 8).a, 0, "the screenshot is not in it: the corner is clear")
        let middle = pixel(full, pixelWidth / 2, pixelHeight / 2)
        XCTAssertEqual(middle.a, 255, "the annotation is opaque where it is drawn: \(middle)")
        XCTAssertGreaterThan(middle.r, middle.b, "and it is the red it was drawn in: \(middle)")
        XCTAssertGreaterThan(redPixels(full), 50)
        XCTAssertEqual(try eval("return window.editor.getSelectedShapeIds().length") as? Int, 1,
                       "the user's selection is put back: they are still editing this canvas")

        let capped = try XCTUnwrap(NSBitmapImageRep(data: try overlay(maxPixel: 100)))
        XCTAssertEqual(capped.pixelsWide, 100, "the cap is the longest side")
        XCTAssertEqual(capped.pixelsHigh, 75)
    }

    private func overlay(maxPixel: Int) throws -> Data {
        try XCTUnwrap(WebMessage.pngData(try XCTUnwrap(try eval(PageAPI.overlay(maxPixel: maxPixel).script) as? String, "a rendering")))
    }

    /// An agent's marks become a draft while the editor is busy with another image and never shown:
    /// the rendering carries the marks, the page's own canvas comes back untouched, and the stored
    /// snapshot reopens as the image with the marks on it, for the user to edit.
    func testBuildMakesADraftFromMarksWithoutDisturbingTheCanvas() throws {
        waitFor("ready")
        try loadFixture()
        _ = try eval("""
            const img = window.editor.getShape('shape:screenshot');
            window.editor.createShape({ type: 'geo', x: 0, y: 0, props: { w: 10, h: 10, geo: 'rectangle', color: 'light-blue' } });
            return window.editor.getCurrentPageShapeIds().size;
            """)
        let marks = [
            Mark(type: .ellipse, x: 0.2, y: 0.2, w: 0.5, h: 0.5, color: "red"),
            Mark(type: .arrow, x: 0.1, y: 0.9, x2: 0.4, y2: 0.6, color: "red"),
            Mark(type: .text, x: 0.05, y: 0.05, text: "Header should not scroll", color: "red"),
        ]
        let built = try XCTUnwrap(ParkResult(body: try eval(PageAPI.build(payload, snapshot: nil, marks: marks).script)))
        let preview = try XCTUnwrap(built.preview, "a build always renders a preview for the card")
        let rep = try XCTUnwrap(NSBitmapImageRep(data: preview))
        XCTAssertGreaterThan(redPixels(rep), 50, "the marks are drawn on the screenshot")
        let corner = pixel(rep, rep.pixelsWide - 4, 4)
        XCTAssertGreaterThan(corner.b, corner.r + 60, "the screenshot is under the marks: \(corner)")

        XCTAssertEqual(try eval("return window.editor.getCurrentPageShapeIds().size") as? Int, 2, "the page's own canvas is back")
        XCTAssertEqual(try eval("return window.editor.getCanUndo()") as? Bool, true, "a build leaves the drawing's undo entry in place")

        let snapshot = try JSONSerialization.data(withJSONObject: try XCTUnwrap(built.snapshot))
        try loadFixture(snapshot: snapshot)
        XCTAssertEqual(try eval("return window.editor.getCurrentPageShapeIds().size") as? Int, 1 + marks.count,
                       "the stored draft reopens as the image with every mark on it")
        XCTAssertEqual(try eval("return window.editor.getShape('shape:screenshot').props.w > 0") as? Bool, true)
        // A reopen picks up the annotation the user drew last; these are the agent's, so none is picked.
        XCTAssertEqual(try eval("return window.editor.getSelectedShapeIds().length") as? Int, 0)
        XCTAssertEqual(try eval("return window.editor.getCurrentPageShapes().filter(s => s.meta.agent).length") as? Int, marks.count)
    }

    /// A marked push and an image opening at the same moment. The build borrows the canvas and puts
    /// back what it found when its rendering is done, so a `load` that landed in the middle would be
    /// wiped. Both take their turn in the page's queue instead: the push keeps its draft, and the
    /// image the host asked for is what stays on the canvas.
    func testAnImageLoadedDuringABuildStaysOnTheCanvas() throws {
        waitFor("ready")
        try loadFixture()
        _ = try eval("""
            window.editor.createShape({ type: 'geo', x: 0, y: 0, props: { w: 10, h: 10, geo: 'rectangle', color: 'light-blue' } });
            return window.editor.getCurrentPageShapeIds().size;
            """)
        let marks = [Mark(type: .ellipse, x: 0.2, y: 0.2, w: 0.5, h: 0.5, color: "red")]
        // The build is not awaited. The load goes in once its mark is on the canvas, which is the
        // build waiting on its rendering: the moment a load used to be thrown away.
        _ = try eval("""
            window.buildInFlight = window.vignette.build(\(PageAPI.payload(payload, nil)),\(PageAPI.json(marks)));
            for (let i = 0; i < 200; i++) {
              const shapes = [...window.editor.getCurrentPageShapeIds()].map((id) => window.editor.getShape(id));
              if (shapes.some((s) => s.type === 'geo' && s.props.geo === 'ellipse')) break;
              await new Promise((r) => setTimeout(r, 5));
            }
            \(PageAPI.load(payload, snapshot: nil).script)
            """)
        let built = try XCTUnwrap(ParkResult(body: try eval("return await window.buildInFlight;")))
        XCTAssertNotNil(built.snapshot, "the push still gets its draft")
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(built.preview, "and its rendering")))
        XCTAssertGreaterThan(redPixels(rep), 50, "with the marks on it")
        for _ in 0..<50 where try eval("return window.editor.getCurrentPageShapeIds().size") as? Int != 1 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(try eval("return window.editor.getCurrentPageShapeIds().size") as? Int, 1,
                       "the canvas holds the image the host loaded, not the one the build put back")
    }

    /// A pushed text is wrapped inside the image and sized for it. Three sentences an agent could
    /// send: one with no width from a third of the way across, one that names its own box, and one
    /// from the far corner, where the box has to move to fit. None of them may leave the image, or
    /// the export and the card's preview cut it off. The same sentence on an image twice the size
    /// must cover the same part of it, which is what makes a crop and a full capture read alike.
    /// The one text shape on the page, as fractions of the image it is drawn on.
    private let oneTextBox = """
        const image = window.editor.getShapePageBounds('shape:screenshot');
        const s = window.editor.getCurrentPageShapesSorted().find((s) => s.type === 'text');
        const b = window.editor.getShapePageBounds(s.id);
        return { x: (b.x - image.x) / image.w, y: (b.y - image.y) / image.h, w: b.w / image.w, h: b.h / image.h };
        """

    func testAPushedTextWrapsInsideTheImageAndIsSizedForIt() throws {
        waitFor("ready")
        let words = "16 pt between strip and card now. Enough? Circle what to change."
        let marks = [
            Mark(type: .text, x: 0.3, y: 0.55, text: words, color: "red"),
            Mark(type: .text, x: 0.1, y: 0.1, w: 0.4, text: words, color: "red"),
            Mark(type: .text, x: 0.92, y: 0.9, text: words, color: "red"),
        ]
        let built = try XCTUnwrap(ParkResult(body: try eval(PageAPI.build(payload, snapshot: nil, marks: marks).script)))
        try loadFixture(snapshot: try JSONSerialization.data(withJSONObject: try XCTUnwrap(built.snapshot)))
        let boxes = try XCTUnwrap(eval("""
            const image = window.editor.getShapePageBounds('shape:screenshot');
            return window.editor.getCurrentPageShapesSorted().filter((s) => s.type === 'text').map((s) => {
              const b = window.editor.getShapePageBounds(s.id);
              return { x: (b.x - image.x) / image.w, y: (b.y - image.y) / image.h, w: b.w / image.w, h: b.h / image.h };
            });
            """) as? [[String: Double]])
        XCTAssertEqual(boxes.count, marks.count)
        for box in boxes {
            XCTAssertGreaterThanOrEqual(box["x"]!, 0, "a pushed text starts inside the image: \(box)")
            XCTAssertGreaterThanOrEqual(box["y"]!, 0, "\(box)")
            XCTAssertLessThanOrEqual(box["x"]! + box["w"]!, 1, "and ends inside it: \(box)")
            XCTAssertLessThanOrEqual(box["y"]! + box["h"]!, 1, "\(box)")
        }
        XCTAssertEqual(boxes[1]["w"]!, 0.4, accuracy: 0.01, "a text mark that names its box gets it")

        // A caption asked for at the image's full width already fits it exactly, so the pull-back
        // has no room to give it and must leave it where it is rather than move it in by the margin.
        let full = try XCTUnwrap(ParkResult(body: try eval(PageAPI.build(payload, snapshot: nil,
            marks: [Mark(type: .text, x: 0, y: 0.1, w: 1, text: words, color: "red")]).script)))
        try loadFixture(snapshot: try JSONSerialization.data(withJSONObject: try XCTUnwrap(full.snapshot)))
        let spanning = try XCTUnwrap(eval(oneTextBox) as? [String: Double])
        XCTAssertGreaterThanOrEqual(spanning["x"]!, 0, "a full-width caption stays inside: \(spanning)")
        XCTAssertLessThanOrEqual(spanning["x"]! + spanning["w"]!, 1, "\(spanning)")

        // A long sentence in a narrow default box wraps into a column taller than the image. The
        // box is widened until the words fit the height, so the whole of it is still on the picture
        // rather than cut off below it — which is what this mark is for.
        let wide = LoadPayload(key: fixture.path, mimeType: "image/png", pixelWidth: pixelWidth * 7, pixelHeight: pixelHeight * 2)
        let long = String(repeating: "the header should not scroll with the rest of the page, ", count: 4)
        let tall = try XCTUnwrap(ParkResult(body: try eval(PageAPI.build(wide, snapshot: nil,
            marks: [Mark(type: .text, x: 0.88, y: 0.2, text: long, color: "red")]).script)))
        try loadFixture(snapshot: try JSONSerialization.data(withJSONObject: try XCTUnwrap(tall.snapshot)))
        let column = try XCTUnwrap(eval(oneTextBox) as? [String: Double])
        XCTAssertLessThanOrEqual(column["h"]!, 1, "a long sentence is widened until it fits the image's height: \(column)")
        XCTAssertLessThanOrEqual(column["y"]! + column["h"]!, 1, "so its bottom is on the image: \(column)")
        XCTAssertLessThanOrEqual(column["x"]! + column["w"]!, 1, "\(column)")

        // The same sentence on an image twice as wide: the font follows the image, so the wrapped
        // box covers the same fraction of it. The payload is what tells the page the image's size.
        let bigger = LoadPayload(key: fixture.path, mimeType: "image/png", pixelWidth: pixelWidth * 2, pixelHeight: pixelHeight * 2)
        let onBigger = try XCTUnwrap(ParkResult(body: try eval(PageAPI.build(bigger, snapshot: nil, marks: [marks[0]]).script)))
        try loadFixture(snapshot: try JSONSerialization.data(withJSONObject: try XCTUnwrap(onBigger.snapshot)))
        let box = try XCTUnwrap(eval(oneTextBox) as? [String: Double])
        XCTAssertEqual(box["w"]!, boxes[0]["w"]!, accuracy: 0.02, "the box covers the same part of either image")
        XCTAssertEqual(box["h"]!, boxes[0]["h"]!, accuracy: 0.02, "so the sentence wraps into the same number of lines")
    }

    /// The first thing this page ever draws is a text mark, on a canvas nobody has seen: the font
    /// it needs has not been used yet, and the rendering must wait for it rather than come back
    /// blank. The second text mark must be drawn too: `render` waits once per font and then trusts
    /// WebKit to keep it, and every rendering makes a new `Image` for the SVG.
    func testEveryTextMarkIsDrawn() throws {
        waitFor("ready")
        for words in ["Header should not scroll", "The second one draws too"] {
            let marks = [Mark(type: .text, x: 0.1, y: 0.4, text: words, color: "red")]
            let built = try XCTUnwrap(ParkResult(body: try eval(PageAPI.build(payload, snapshot: nil, marks: marks).script)))
            let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(built.preview)))
            XCTAssertGreaterThan(redPixels(rep), 50, "\"\(words)\" is drawn, not left blank")
        }
    }
}
