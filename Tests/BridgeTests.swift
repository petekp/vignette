import XCTest

final class BridgeTests: XCTestCase {
    private let png = "data:image/png;base64," + Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString()

    // MARK: WebMessage decoding

    func testReadyCarriesProtocolToolsAndColors() throws {
        let msg = WebMessage(body: [
            "type": "ready", "protocol": 3,
            "tools": [["id": "draw", "label": "Draw", "key": "d", "symbol": "pencil"], ["id": "bad"]],
            "colors": [["id": "red", "hex": "#f00"]],
        ] as [String: Any])
        guard case .ready(let version, let tools, let colors)? = msg else { return XCTFail("\(String(describing: msg))") }
        XCTAssertEqual(version, 3)
        XCTAssertEqual(tools.map(\.id), ["draw"], "an incomplete tool is dropped, not fatal")
        XCTAssertEqual(colors.map(\.hex), ["#f00"])
    }

    func testReadyWithoutProtocolIsVersionZero() {
        guard case .ready(let version, _, _)? = WebMessage(body: ["type": "ready"]) else { return XCTFail() }
        XCTAssertEqual(version, 0, "a page built before versioning must never pass the version check")
    }

    func testEveryMessageTypeDecodes() throws {
        guard case .tool(let tool, let color)? = WebMessage(body: ["type": "tool", "tool": "arrow", "color": "red"]) else { return XCTFail() }
        XCTAssertEqual(tool, "arrow"); XCTAssertEqual(color, "red")
        guard case .tool(nil, _)? = WebMessage(body: ["type": "tool", "color": "red"]) else { return XCTFail("tool may be null") }
        guard case .loaded(let key)? = WebMessage(body: ["type": "loaded", "key": "/a.png"]) else { return XCTFail() }
        XCTAssertEqual(key, "/a.png")
        guard case .cancel? = WebMessage(body: ["type": "cancel"]) else { return XCTFail() }
        guard case .log(let text)? = WebMessage(body: ["type": "log", "message": "hi"]) else { return XCTFail() }
        XCTAssertEqual(text, "hi")
        guard case .done(let data?)? = WebMessage(body: ["type": "done", "png": png]) else { return XCTFail() }
        XCTAssertEqual(data.count, 4)
        guard case .done(nil)? = WebMessage(body: ["type": "done", "png": NSNull()]) else { return XCTFail("a null png means nothing was drawn") }
        XCTAssertNil(WebMessage(body: ["type": "done"]))
        guard case .draft(let dkey, let snapshot)? = WebMessage(body: ["type": "draft", "key": "/a.png", "snapshot": ["document": ["x": 1]]]) else { return XCTFail() }
        XCTAssertEqual(dkey, "/a.png")
        XCTAssertEqual((snapshot as? [String: Any])?.keys.sorted(), ["document"])
        guard case .draft(_, nil)? = WebMessage(body: ["type": "draft", "key": "/a.png", "snapshot": NSNull()]) else { return XCTFail("null snapshot means no annotations") }
        guard case .zoom(let factor, let at)? = WebMessage(body: ["type": "zoom", "factor": 1.25, "at": ["x": 0.25, "y": 0.75]] as [String: Any]) else { return XCTFail() }
        XCTAssertEqual(factor, 1.25)
        XCTAssertEqual(at, CGPoint(x: 0.25, y: 0.75))
        guard case .zoom(nil, nil)? = WebMessage(body: ["type": "zoom", "factor": NSNull(), "at": NSNull()]) else { return XCTFail("null factor means the fitted size, no anchor its middle") }
        guard case .zoom(_, nil)? = WebMessage(body: ["type": "zoom", "factor": 1.25, "at": ["x": 0.5]] as [String: Any]) else { return XCTFail("half an anchor is no anchor") }
        XCTAssertNil(WebMessage(body: ["type": "zoom", "factor": 0, "at": NSNull()]), "a zero or negative factor would collapse the window")
        XCTAssertNil(WebMessage(body: ["type": "zoom"]))
    }

    func testParkAndExportResultsDecode() {
        let parked = ParkResult(body: ["snapshot": ["document": [:]], "preview": png] as [String: Any])
        XCTAssertNotNil(parked?.snapshot); XCTAssertEqual(parked?.preview?.count, 4)
        let empty = ParkResult(body: ["snapshot": NSNull(), "preview": NSNull()])
        XCTAssertNil(empty?.snapshot); XCTAssertNil(empty?.preview)
        XCTAssertNil(ParkResult(body: nil), "the page did not answer")
        let exported = ExportResult(body: ["items": [["key": "/a.png", "png": png], ["key": "/b.png"]], "error": NSNull()] as [String: Any])
        XCTAssertEqual(exported?.pngs.keys.sorted(), ["/a.png"], "an item without a png is dropped")
        XCTAssertNil(exported?.error)
        XCTAssertEqual(ExportResult(body: ["items": [], "error": "render threw"])?.error, "render threw")
        XCTAssertNil(ExportResult(body: "nope"))
    }

    func testMalformedBodiesAreRefused() {
        XCTAssertNil(WebMessage(body: "ready"))
        XCTAssertNil(WebMessage(body: ["protocol": 2]))
        XCTAssertNil(WebMessage(body: ["type": "teleport"]))
        XCTAssertNil(WebMessage(body: ["type": "loaded"]))
        XCTAssertNil(WebMessage(body: ["type": "done", "png": "not base64 !!"]))
        XCTAssertNil(WebMessage(body: ["type": "draft", "key": "/a.png"]), "a draft without a snapshot field")
        XCTAssertNil(WebMessage(body: ["type": "draft", "snapshot": NSNull()]))
    }

    func testDescribeNamesTypeAndKeysOnly() {
        XCTAssertEqual(WebMessage.describe(["type": "done", "png": String(repeating: "x", count: 10_000)]), "type=done keys=png,type")
        XCTAssertEqual(WebMessage.describe(["png": "x"]), "type=? keys=png")
        XCTAssertEqual(WebMessage.describe(42), "non-object Int")
    }

    // MARK: PageAPI scripts

    func testLoadScriptEmbedsPayloadAndSnapshotAsJSON() throws {
        let payload = LoadPayload(key: "/Users/p/Shot \"one\".png", mimeType: "image/png",
                                  pixelWidth: 10, pixelHeight: 20, viewWidth: 5.5, viewHeight: 6)
        let fresh = PageAPI.load(payload, snapshot: nil).script
        XCTAssertTrue(fresh.hasPrefix("window.shotnote && window.shotnote.load({\"snapshot\":null,\"key\":"), fresh)
        XCTAssertTrue(fresh.contains(#""key":"/Users/p/Shot \"one\".png""#), fresh)
        XCTAssertTrue(fresh.contains(#""pixelWidth":10"#) && fresh.contains(#""viewWidth":5.5"#), fresh)
        let stored = PageAPI.load(payload, snapshot: Data(#"{"document":{"a":1}}"#.utf8)).script
        XCTAssertTrue(stored.hasPrefix(#"window.shotnote && window.shotnote.load({"snapshot":{"document":{"a":1}},"key":"#), stored)
        // The argument must be one JSON object: parse what the script passes to load().
        let start = stored.range(of: "load(")!.upperBound
        let object = try JSONSerialization.jsonObject(with: Data(stored[start...].dropLast(2).utf8)) as? [String: Any]
        XCTAssertEqual(object?.keys.sorted(), ["key", "mimeType", "pixelHeight", "pixelWidth", "snapshot", "viewHeight", "viewWidth"])
    }

    func testBuildScriptCarriesTheImageItsDraftAndTheMarks() throws {
        let payload = LoadPayload(key: "/a b.png", mimeType: "image/png", pixelWidth: 10, pixelHeight: 20, viewWidth: 5, viewHeight: 6)
        let marks = [Mark(type: .ellipse, x: 0.1, y: 0.2, w: 0.3, h: 0.4, color: "red"),
                     Mark(type: .text, x: 0, y: 0, text: "say \"hi\"")]
        let script = PageAPI.build(payload, snapshot: Data(#"{"document":1}"#.utf8), marks: marks).script
        XCTAssertTrue(script.hasPrefix(#"return window.shotnote ? await window.shotnote.build({"snapshot":{"document":1},"key":"/a b.png""#), script)
        // Both arguments must be JSON the page can take as they are: read them back as a pair.
        let start = script.range(of: "build(")!.upperBound
        let end = script.range(of: ") : null;")!.lowerBound
        let args = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(("[" + script[start..<end] + "]").utf8)) as? [Any])
        XCTAssertEqual((args.first as? [String: Any])?["key"] as? String, "/a b.png")
        let sent = try XCTUnwrap(args.last as? [[String: Any]])
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent[0]["type"] as? String, "ellipse")
        XCTAssertEqual(sent[0]["w"] as? Double, 0.3)
        XCTAssertEqual(sent[1]["text"] as? String, "say \"hi\"")
        XCTAssertNil(sent[1]["w"], "a mark carries only the numbers its type uses")
    }

    func testExportScriptCarriesEachSnapshot() throws {
        let script = PageAPI.export([(key: "/a b.png", snapshot: Data(#"{"d":1}"#.utf8)), (key: "/c.png", snapshot: Data(#"{"d":2}"#.utf8))]).script
        XCTAssertEqual(script, #"return window.shotnote ? await window.shotnote.export([{"key":"/a b.png","snapshot":{"d":1}},{"key":"/c.png","snapshot":{"d":2}}]) : null;"#)
        XCTAssertEqual(PageAPI.export([]).script, "return window.shotnote ? await window.shotnote.export([]) : null;")
    }

    func testStringArgumentsAreEscapedForJavaScript() {
        XCTAssertEqual(PageAPI.setTool("dr\"aw').x</script>").script, #"window.shotnote && window.shotnote.setTool("dr\"aw').x</script>");"#)
        XCTAssertEqual(PageAPI.setColor("line\nbreak").script, #"window.shotnote && window.shotnote.setColor("line\nbreak");"#)
    }

    func testParkAwaitsAndOthersGuard() {
        XCTAssertEqual(PageAPI.park.script, "return window.shotnote ? await window.shotnote.park() : null;")
        for api in [PageAPI.reset, .finish, .setColor("red")] {
            XCTAssertTrue(api.script.hasPrefix("window.shotnote && window.shotnote."), api.script)
        }
    }
}
