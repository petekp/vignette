import XCTest

final class LeftoversTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-leftovers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testALaunchRemovesWhatEarlierBuildsLeft() throws {
        let left = ["Application Support/app/drafts", "Caches/app/drafts", "Caches/app/WebKit/NetworkCache", "WebKit/app/WebsiteData"]
        for path in left {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent(path), withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: dir.appendingPathComponent(path).appendingPathComponent("a.json"))
        }
        let log = dir.appendingPathComponent("Application Support/app/send-context.jsonl")
        try Data("{}\n".utf8).write(to: log)
        let folders = ["Application Support/app/drafts", "Caches/app/drafts", "Caches/app/WebKit", "WebKit/app"].map(dir.appendingPathComponent)
        Leftovers.remove(folders + [dir.appendingPathComponent("never-made")], what: "web editor data")
        Leftovers.remove([log], what: "shadow log")
        for item in folders + [log] { XCTAssertFalse(FileManager.default.fileExists(atPath: item.path), item.path) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Caches/app").path), "only those items go")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Application Support/app").path), "only those items go")
    }
}
