import XCTest

@MainActor
final class FolderWritesStitchTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-stitch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testAStitchWhoseNameIsTakenGetsACounterAndLeavesTheFirstAlone() throws {
        let writes = FolderWrites(trash: { try FileManager.default.removeItem(at: $0) }, now: { 0 })
        let first = try writes.writeStitch(Data("first".utf8), in: folder, as: "Stitch x.png")
        let second = try writes.writeStitch(Data("second".utf8), in: folder, as: "Stitch x.png")
        XCTAssertEqual(first.name, "Stitch x.png")
        XCTAssertEqual(second.name, "Stitch x 2.png")
        XCTAssertEqual(try Data(contentsOf: first.url), Data("first".utf8))
        XCTAssertEqual(try Data(contentsOf: second.url), Data("second".utf8))
    }
}
