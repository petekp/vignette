import XCTest

final class DraftStoreTests: XCTestCase {
    private var base: URL!
    private var store: DraftStore!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-drafts-\(UUID().uuidString)")
        store = DraftStore(directory: base.appendingPathComponent("drafts"), previewDirectory: base.appendingPathComponent("cache"))
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: base)
    }

    private func json(_ data: Data?) -> [String: Any]? {
        data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    func testSaveThenSnapshotRoundTripsTheJSON() throws {
        let key = "/Users/p/Screenshots/Shot 1.png"
        XCTAssertNil(store.snapshot(for: key))
        try store.save(key: key, snapshot: ["document": ["shapes": [1, 2]], "session": ["camera": 1.5]])
        XCTAssertEqual(store.keys, [key])
        let back = json(store.snapshot(for: key))
        XCTAssertEqual((back?["document"] as? [String: Any])?["shapes"] as? [Int], [1, 2])
        XCTAssertEqual((back?["session"] as? [String: Any])?["camera"] as? Double, 1.5)
    }

    func testKeysComeBackFromDiskOnTheNextLaunch() throws {
        try store.save(key: "/a.png", snapshot: ["v": 1])
        try store.save(key: "/b.png", snapshot: ["v": 2])
        try store.savePreview(key: "/a.png", png: Data([1, 2, 3]))
        let again = DraftStore(directory: store.directory, previewDirectory: store.previewDirectory)
        XCTAssertEqual(again.keys, ["/a.png", "/b.png"])
        XCTAssertEqual(json(again.snapshot(for: "/b.png"))?["v"] as? Int, 2)
        XCTAssertEqual(again.preview(for: "/a.png"), Data([1, 2, 3]))
        XCTAssertNil(again.preview(for: "/b.png"))
    }

    func testCorruptAndForeignFilesAreIgnored() throws {
        try store.save(key: "/ok.png", snapshot: ["v": 1])
        try Data("{not json".utf8).write(to: store.directory.appendingPathComponent("bad.json"))
        try Data(#"{"snapshot":{}}"#.utf8).write(to: store.directory.appendingPathComponent("nokey.json"))
        try Data("x".utf8).write(to: store.directory.appendingPathComponent("notes.txt"))
        XCTAssertEqual(DraftStore(directory: store.directory, previewDirectory: store.previewDirectory).keys, ["/ok.png"])
    }

    func testDraftsWithoutAPreviewAreListed() throws {
        try store.save(key: "/a.png", snapshot: ["v": 1])
        try store.save(key: "/b.png", snapshot: ["v": 2])
        try store.savePreview(key: "/a.png", png: Data([1, 2, 3]))
        XCTAssertEqual(store.keysWithoutPreview(), ["/b.png"])
        try FileManager.default.removeItem(at: store.previewURL(for: "/a.png"))
        XCTAssertEqual(store.keysWithoutPreview(), ["/a.png", "/b.png"])
        store.forget(["/a.png"])
        XCTAssertEqual(store.keysWithoutPreview(), ["/b.png"], "a draft that is gone is not missing a preview")
    }

    func testForgetRemovesSnapshotAndPreview() throws {
        try store.save(key: "/a.png", snapshot: ["v": 1])
        try store.savePreview(key: "/a.png", png: Data([9]))
        store.forget(["/a.png", "/never-saved.png"])
        XCTAssertEqual(store.keys, [])
        XCTAssertNil(store.snapshot(for: "/a.png"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.snapshotURL(for: "/a.png").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.previewURL(for: "/a.png").path))
    }

    func testSweepDropsDraftsWhoseImageIsGone() throws {
        try store.save(key: "/kept.png", snapshot: ["v": 1])
        try store.save(key: "/gone.png", snapshot: ["v": 2])
        XCTAssertEqual(store.sweep { $0 == "/kept.png" }, ["/gone.png"])
        XCTAssertEqual(store.keys, ["/kept.png"])
    }
}
