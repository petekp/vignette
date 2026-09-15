import XCTest

final class BridgeTests: XCTestCase {
    private let png = "data:image/png;base64," + Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString()

    // MARK: WebMessage decoding

    func testReadyCarriesProtocolToolsAndColors() throws {
        let msg = WebMessage(body: [
            "type": "ready", "protocol": 2,
            "tools": [["id": "draw", "label": "Draw", "key": "d", "symbol": "pencil"], ["id": "bad"]],
            "colors": [["id": "red", "hex": "#f00"]],
        ] as [String: Any])
        guard case .ready(let version, let tools, let colors)? = msg else { return XCTFail("\(String(describing: msg))") }
        XCTAssertEqual(version, 2)
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
        guard case .done(let data)? = WebMessage(body: ["type": "done", "png": png]) else { return XCTFail() }
        XCTAssertEqual(data.count, 4)
        guard case .drafts(let keys)? = WebMessage(body: ["type": "drafts", "keys": ["/a.png", "/b.png"]]) else { return XCTFail() }
        XCTAssertEqual(keys, ["/a.png", "/b.png"])
        guard case .draft(let dkey, let preview)? = WebMessage(body: ["type": "draft", "key": "/a.png", "preview": png]) else { return XCTFail() }
        XCTAssertEqual(dkey, "/a.png"); XCTAssertEqual(preview.count, 4)
        guard case .exported(let items)? = WebMessage(body: ["type": "exported", "items": [["key": "/a.png", "png": png], ["key": "/b.png"]]]) else { return XCTFail() }
        XCTAssertEqual(items.map(\.key), ["/a.png"], "an item without a png is dropped")
    }

    func testMalformedBodiesAreRefused() {
        XCTAssertNil(WebMessage(body: "ready"))
        XCTAssertNil(WebMessage(body: ["protocol": 2]))
        XCTAssertNil(WebMessage(body: ["type": "teleport"]))
        XCTAssertNil(WebMessage(body: ["type": "loaded"]))
        XCTAssertNil(WebMessage(body: ["type": "done", "png": "not base64 !!"]))
        XCTAssertNil(WebMessage(body: ["type": "draft", "key": "/a.png"]))
    }

    func testDescribeNamesTypeAndKeysOnly() {
        XCTAssertEqual(WebMessage.describe(["type": "done", "png": String(repeating: "x", count: 10_000)]), "type=done keys=png,type")
        XCTAssertEqual(WebMessage.describe(["png": "x"]), "type=? keys=png")
        XCTAssertEqual(WebMessage.describe(42), "non-object Int")
    }

    // MARK: PageAPI scripts

    func testLoadScriptEmbedsPayloadAsJSON() {
        let payload = LoadPayload(key: "/Users/p/Shot \"one\".png", imageUrl: "http://127.0.0.1:1/t/file?p=%2Fa.png", mimeType: "image/png",
                                  pixelWidth: 10, pixelHeight: 20, viewWidth: 5.5, viewHeight: 6)
        let script = PageAPI.load(payload).script
        XCTAssertTrue(script.hasPrefix("window.shotnote && window.shotnote.load({"), script)
        XCTAssertTrue(script.contains(#""key":"/Users/p/Shot \"one\".png""#), script)
        XCTAssertTrue(script.contains(#""imageUrl":"http://127.0.0.1:1/t/file?p=%2Fa.png""#), script)
        XCTAssertTrue(script.contains(#""pixelWidth":10"#) && script.contains(#""viewWidth":5.5"#), script)
    }

    func testStringArgumentsAreEscapedForJavaScript() {
        XCTAssertEqual(PageAPI.setTool("dr\"aw').x</script>").script, #"window.shotnote && window.shotnote.setTool("dr\"aw').x</script>");"#)
        XCTAssertEqual(PageAPI.forget(["/a b.png", "line\nbreak"]).script, #"window.shotnote && window.shotnote.forget(["/a b.png","line\nbreak"]);"#)
        XCTAssertEqual(PageAPI.export([]).script, "window.shotnote && window.shotnote.export([]);")
    }

    func testParkAwaitsAndOthersGuard() {
        XCTAssertEqual(PageAPI.park.script, "if (window.shotnote) await window.shotnote.park();")
        for api in [PageAPI.reset, .finish, .setColor("red")] {
            XCTAssertTrue(api.script.hasPrefix("window.shotnote && window.shotnote."), api.script)
        }
    }
}
