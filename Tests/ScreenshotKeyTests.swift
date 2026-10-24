import XCTest

final class ScreenshotKeyTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: "/tmp/vignette-key-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Screenshots"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAFileNamedByTheOtherSpellingOfTheFolderTakesTheFoldersSpelling() throws {
        let folder = root.appendingPathComponent("Screenshots")
        let real = URL(fileURLWithPath: "/private" + folder.path)
        let key = try XCTUnwrap(ScreenshotKey(resolving: real.appendingPathComponent("a.png"), in: folder))
        XCTAssertEqual(key.path, folder.appendingPathComponent("a.png").path)
    }

    func testAFileReachedThroughALinkedFolderTakesTheLinksSpelling() throws {
        let folder = root.appendingPathComponent("Screenshots")
        let link = root.appendingPathComponent("Link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        let key = try XCTUnwrap(ScreenshotKey(resolving: folder.appendingPathComponent("a.png"), in: link))
        XCTAssertEqual(key.path, link.appendingPathComponent("a.png").path)
    }

    func testAFileThatDoesNotExistYetIsPlacedByItsFolder() throws {
        let folder = root.appendingPathComponent("Screenshots")
        let real = URL(fileURLWithPath: "/private" + folder.path)
        let key = try XCTUnwrap(ScreenshotKey(resolving: real.appendingPathComponent("new.png"), in: folder))
        XCTAssertEqual(key, ScreenshotKey(folder: folder, name: "new.png"))
    }

    func testAFileOutsideTheFolderHasNoKey() throws {
        let folder = root.appendingPathComponent("Screenshots")
        try Data().write(to: root.appendingPathComponent("a.png"))
        XCTAssertNil(ScreenshotKey(resolving: root.appendingPathComponent("a.png"), in: folder))
        XCTAssertNil(ScreenshotKey(resolving: root.appendingPathComponent("Screenshots-other/a.png"), in: folder))
    }
}
