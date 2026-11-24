import AppKit
import XCTest

@MainActor
final class FolderWritesPutBackTests: XCTestCase {
    private var base: URL!
    private var folder: URL!
    private var writes: FolderWrites!
    private var removedCards: [URL] = []

    override func setUp() async throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-put-back-\(UUID().uuidString)")
        folder = base.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        writes = FolderWrites(trash: { $0 }, now: { 10 })
        writes.callbacks = FolderWrites.Callbacks(
            folder: { [unowned self] in folder },
            removeCards: { [unowned self] in removedCards += $0.map(\.url) })
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func file(_ name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data([0]).write(to: url)
        return url
    }

    private func inTrash(_ url: URL) throws -> FolderWrites.Trashed {
        FolderWrites.Trashed(shot: Screenshot(key: url.screenshotKey), inTrash: try file(url.lastPathComponent, in: base))
    }

    func testAFilePutBackFromTheTrashIsNoCaptureAndHoldsBackOlderRemovals() throws {
        let a = folder.appendingPathComponent("a.png")
        let b = try file("b.png", in: folder)

        let (back, failed) = writes.putBack([try inTrash(a), try inTrash(b)])
        XCTAssertEqual(back.map(\.url), [a])
        XCTAssertEqual(failed.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(writes.arrived(a.screenshotKey))
        XCTAssertFalse(writes.arrived(a.screenshotKey))
        writes.removed([a.screenshotKey], in: ScreenshotWatcher.Inventory(folder: folder, names: [], dates: [:], observedAt: 5))
        XCTAssertEqual(removedCards, [])
    }
}
