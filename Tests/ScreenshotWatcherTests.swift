import AppKit
import XCTest

final class ScreenshotWatcherTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("shotnote-watcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    private func png(_ name: String, side: Int = 2, mtime: Date? = nil) throws -> URL {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let url = dir.appendingPathComponent(name)
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        if let mtime { try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path) }
        return url
    }

    func testRecentCountsEveryCandidate() throws {
        _ = try png("Screenshot a.png"); _ = try png("Screenshot b.png"); _ = try png("Screenshot c.png")
        try Data("x".utf8).write(to: dir.appendingPathComponent("notes.txt"))
        let recent = ScreenshotWatcher.recent(in: dir, limit: 2)
        XCTAssertEqual(recent.recent.count, 2)
        XCTAssertEqual(recent.files, 3)
    }

    func testCandidatesAreScreenshotFormatsAndNotOutputs() {
        for name in ["Screenshot 1.png", "x.PNG", "x.jpg", "x.jpeg", "x.heic"] { XCTAssertTrue(ScreenshotWatcher.isCandidate(name), name) }
        for name in [".hidden.png", "x-annotated.png", "x.pdf", "x.tiff", "x.gif", "png", "x.png.part"] { XCTAssertFalse(ScreenshotWatcher.isCandidate(name), name) }
    }

    func testRecentAreNewestFirstAndLimited() throws {
        let now = Date()
        let old = try png("old.png", mtime: now.addingTimeInterval(-30))
        let mid = try png("mid.png", mtime: now.addingTimeInterval(-20))
        let new = try png("new.png", mtime: now.addingTimeInterval(-10))
        try "no".write(to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(ScreenshotWatcher.recent(in: dir, limit: 10).recent, [new, mid, old])
        XCTAssertEqual(ScreenshotWatcher.recent(in: dir, limit: 2).recent, [new, mid])
        XCTAssertEqual(ScreenshotWatcher.recent(in: dir, limit: -1).recent, [], "a negative limit yields nothing instead of trapping")
        let same = try png("same.png", mtime: now.addingTimeInterval(-10))
        XCTAssertEqual(ScreenshotWatcher.recent(in: dir, limit: 1).recent, [same], "an equal date falls to the name, which carries the capture time")
    }

    func testDiffReportsAddedAndRemovedSorted() {
        let change = ScreenshotWatcher.diff(known: ["b.png", "a.png", "gone.png"], current: ["a.png", "b.png", "new2.png", "new1.png"])
        XCTAssertEqual(change.added, ["new1.png", "new2.png"])
        XCTAssertEqual(change.removed, ["gone.png"])
    }

    func testCompleteImageRejectsATruncatedFile() throws {
        let whole = try png("whole.png", side: 64)
        XCTAssertTrue(ScreenshotWatcher.isCompleteImage(whole))
        let data = try Data(contentsOf: whole)
        let half = dir.appendingPathComponent("half.png")
        try data.prefix(data.count / 2).write(to: half)
        XCTAssertFalse(ScreenshotWatcher.isCompleteImage(half))
        XCTAssertFalse(ScreenshotWatcher.isCompleteImage(dir.appendingPathComponent("missing.png")))
    }

    func testReportsNewAndRemovedFiles() throws {
        let existing = try png("existing.png")
        let newSeen = expectation(description: "new file reported")
        let removedSeen = expectation(description: "removed file reported")
        var reportedNew: URL?
        var reportedRemoved: [URL] = []
        let watcher = ScreenshotWatcher(folder: dir, onNew: { url in reportedNew = url; newSeen.fulfill() },
                                        onRemoved: { urls in reportedRemoved = urls; removedSeen.fulfill() })
        XCTAssertEqual(watcher.newest(), existing, "the index is ready as soon as the watcher exists")
        let added = try png("added.png")
        wait(for: [newSeen], timeout: 5)
        XCTAssertEqual(reportedNew, added)
        XCTAssertEqual(watcher.recent(limit: 10).recent, [added, existing], "the index follows the folder")
        try FileManager.default.removeItem(at: existing)
        wait(for: [removedSeen], timeout: 5)
        XCTAssertEqual(reportedRemoved, [existing])
        XCTAssertEqual(watcher.recent(limit: 10).files, 1)
        withExtendedLifetime(watcher) {}
    }

    func testAFolderThatAppearsLaterIsListedAndThenWatched() throws {
        let later = dir.appendingPathComponent("later")
        let newSeen = expectation(description: "both files reported once the folder is watched")
        newSeen.expectedFulfillmentCount = 2
        var reported: Set<URL> = []
        let watcher = ScreenshotWatcher(folder: later, onNew: { reported.insert($0); newSeen.fulfill() }, onRemoved: { _ in })
        XCTAssertNil(watcher.newest())
        try FileManager.default.createDirectory(at: later, withIntermediateDirectories: true)
        let first = try png("later/first.png")
        XCTAssertEqual(watcher.newest(), first, "an unwatched folder is listed on every read")
        watcher.rescan(reason: "test")   // retries the watch; the file that arrived meanwhile is reported too
        let second = try png("later/second.png")
        wait(for: [newSeen], timeout: 5)
        XCTAssertEqual(reported, [first, second])
        withExtendedLifetime(watcher) {}
    }
}
