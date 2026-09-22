import XCTest

final class LocalServerTests: XCTestCase {
    private var root: URL!
    private var shots: URL!
    private var routes: LocalServer.Routes!
    private let access = LocalServer.FileAccess()

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-server-\(UUID().uuidString)")
        root = base.appendingPathComponent("dist"); shots = base.appendingPathComponent("shots")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        try "<html>".write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try "js".write(to: root.appendingPathComponent("assets/app.js"), atomically: true, encoding: .utf8)
        try "secret".write(to: base.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
        try Data([1, 2, 3]).write(to: shots.appendingPathComponent("Shot 1.png"))
        access.update(folder: shots, unrestricted: false)
        routes = LocalServer.Routes(root: root, token: "tok", port: 4242, access: access)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private func get(_ target: String, host: String? = "127.0.0.1:4242", method: String = "GET") -> (status: Int, type: String?, body: Data) {
        var head = "\(method) \(target) HTTP/1.1\r\n"
        if let host { head += "Host: \(host)\r\n" }
        let response = routes.response(for: HTTPRequest.parse(Data((head + "\r\n").utf8))!)
        let split = response.range(of: Data("\r\n\r\n".utf8))!
        let headLines = String(data: response[..<split.lowerBound], encoding: .utf8)!.components(separatedBy: "\r\n")
        let status = Int(headLines[0].split(separator: " ")[1])!
        let type = headLines.first { $0.hasPrefix("Content-Type: ") }?.dropFirst("Content-Type: ".count)
        return (status, type.map(String.init), response[split.upperBound...])
    }

    // MARK: request parsing

    func testParseWaitsForTheHeaderTerminator() {
        XCTAssertNil(HTTPRequest.parse(Data("GET /x HTTP/1.1\r\nHost: a\r\n".utf8)))
        let r = HTTPRequest.parse(Data("GET /tok/file?p=%2FUsers%2Fp%2FShot%201.png&x=1 HTTP/1.1\r\nHost: 127.0.0.1:4242\r\nAccept:  */*\r\n\r\nbody".utf8))
        XCTAssertEqual(r?.method, "GET")
        XCTAssertEqual(r?.path, "/tok/file")
        XCTAssertEqual(r?.query, ["p": "/Users/p/Shot 1.png", "x": "1"])
        XCTAssertEqual(r?.host, "127.0.0.1:4242")
        XCTAssertEqual(r?.headers["accept"], "*/*")
        XCTAssertNil(HTTPRequest.parse(Data("\r\n\r\n".utf8)))
        XCTAssertNil(HTTPRequest.parse(Data("GET\r\n\r\n".utf8)))
    }

    func testAbsoluteFormTargetDoesNotStandInForTheHostHeader() {
        let r = HTTPRequest.parse(Data("GET http://127.0.0.1:4242/tok/index.html HTTP/1.1\r\nHost: evil.example\r\n\r\n".utf8))!
        XCTAssertEqual(r.path, "/tok/index.html")
        XCTAssertEqual(r.host, "evil.example")
        XCTAssertTrue(String(data: routes.response(for: r), encoding: .utf8)!.hasPrefix("HTTP/1.1 400 "))
    }

    // MARK: routing

    func testServesTheBundleUnderTheToken() {
        let index = get("/tok/index.html")
        XCTAssertEqual(index.status, 200)
        XCTAssertEqual(index.type, "text/html; charset=utf-8")
        XCTAssertEqual(String(data: index.body, encoding: .utf8), "<html>")
        let js = get("/tok/assets/app.js?v=1")
        XCTAssertEqual(js.status, 200)
        XCTAssertEqual(js.type, "text/javascript; charset=utf-8")
    }

    func testRefusesWithoutTheToken() {
        XCTAssertEqual(get("/index.html").status, 404)
        XCTAssertEqual(get("/wrong/index.html").status, 404)
        XCTAssertEqual(get("/tok").status, 404)
        XCTAssertEqual(get("/tok/missing.html").status, 404)
    }

    func testRefusesOtherHostsAndMethods() {
        XCTAssertEqual(get("/tok/index.html", host: "evil.example:4242").status, 400)
        XCTAssertEqual(get("/tok/index.html", host: "localhost:4242").status, 400)
        XCTAssertEqual(get("/tok/index.html", host: nil).status, 400)
        XCTAssertEqual(get("/tok/index.html", method: "POST").status, 405)
        XCTAssertEqual(get("/tok/index.html", method: "HEAD").status, 405)
    }

    func testBundleRequestsCannotLeaveTheRoot() {
        XCTAssertEqual(get("/tok/../secret.txt").status, 404)
        XCTAssertEqual(get("/tok/assets/../../secret.txt").status, 404)
        XCTAssertEqual(get("/tok/%2e%2e/secret.txt").status, 404)
    }

    /// The page builds this target itself, from its own location; the parser must give the path back whole.
    func testFileTargetAsThePageBuildsItParses() {
        let path = shots.path + "/Screenshot 2026-09-15 at 2.50.12 PM.png"
        let target = "/tok/file?p=" + path.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowedStrict)!
        XCTAssertEqual(HTTPRequest.parse(Data("GET \(target) HTTP/1.1\r\n\r\n".utf8))?.query["p"], path)
    }

    func testServesScreenshotsInsideTheWatchFolderOnly() {
        let shot = get("/tok/file?p=" + (shots.path + "/Shot 1.png").addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)
        XCTAssertEqual(shot.status, 200)
        XCTAssertEqual(shot.type, "image/png")
        XCTAssertEqual(shot.body, Data([1, 2, 3]))
        let secret = shots.deletingLastPathComponent().appendingPathComponent("secret.txt").path
        XCTAssertEqual(get("/tok/file?p=" + secret.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!).status, 404)
        XCTAssertEqual(get("/tok/file?p=" + (shots.path + "/../secret.txt").addingPercentEncoding(withAllowedCharacters: .alphanumerics)!).status, 404)
        XCTAssertEqual(get("/tok/file").status, 404)
        XCTAssertEqual(get("/tok/file/extra?p=x").status, 404)
    }

    func testDebugLiftsTheFolderRule() {
        let secret = shots.deletingLastPathComponent().appendingPathComponent("secret.txt").path
        access.update(folder: shots, unrestricted: true)
        let r = get("/tok/file?p=" + secret.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(r.type, "text/plain; charset=utf-8")
        access.update(folder: shots, unrestricted: false)
        XCTAssertEqual(get("/tok/file?p=" + secret.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!).status, 404)
    }

    func testRedactedURLHidesTheToken() {
        let server = LocalServer(root: root, access: access, token: "s3cret")
        XCTAssertEqual(LocalServer.redacted(server.indexURL), "http://127.0.0.1:0/token/index.html")
        XCTAssertEqual(LocalServer.redacted(URL(string: "http://127.0.0.1:0/s3cret/file?p=%2Fa.png")!), "http://127.0.0.1:0/token/file?p=%2Fa.png")
    }

    func testMimeTypesCoverEveryWatchedImageFormat() {
        // Recordings are watched too but never reach the page, so the server has no type for them.
        for ext in ScreenshotWatcher.candidateExtensions.subtracting(Screenshot.recordingExtensions) {
            XCTAssertTrue(LocalServer.mimeType(for: ext).hasPrefix("image/"), ext)
        }
        XCTAssertEqual(LocalServer.mimeType(for: "JPG"), "image/jpeg")
        XCTAssertEqual(LocalServer.mimeType(for: "bin"), "application/octet-stream")
    }
}

private extension CharacterSet {
    /// What `encodeURIComponent` leaves alone.
    static let urlQueryValueAllowedStrict = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.!~*'()")
}
