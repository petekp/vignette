import XCTest

final class LogTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-log-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    func testOneLineFlattensEveryLineBreak() {
        XCTAssertEqual(Log.oneLine("a\nb\r\nc\rd"), "a b c d")
        XCTAssertEqual(Log.oneLine("plain"), "plain")
    }

    func testAppendRotatesAtTheLimitAndKeepsOnePrevious() throws {
        let file = dir.appendingPathComponent("t.log")
        let previous = dir.appendingPathComponent("t.log.1")
        Log.append("first\n", to: file, rotateAt: 20)
        Log.append("second line here\n", to: file, rotateAt: 20)   // 6 + 17 = 23 bytes: over the limit after this
        XCTAssertFalse(FileManager.default.fileExists(atPath: previous.path), "rotation happens before the next write, not after this one")
        Log.append("third\n", to: file, rotateAt: 20)
        XCTAssertEqual(try String(contentsOf: previous, encoding: .utf8), "first\nsecond line here\n")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "third\n")
        for _ in 0..<5 { Log.append("filler line long enough\n", to: file, rotateAt: 20) }
        XCTAssertFalse(try String(contentsOf: previous, encoding: .utf8).contains("first"), "only the latest previous log is kept")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted(), ["t.log", "t.log.1"])
    }
}
