import AppKit
import XCTest

@MainActor
extension FolderWritesTests {
    // MARK: Removals

    /// Catches a stale listing removing a file the app just wrote, a held-back removal never
    /// confirmed, confirmed twice or leaving only its card, a listing of one folder dropping the
    /// removals held back for another, or a later write not holding back removals from a listing
    /// that was current until then.
    func testARemovalFromAnOlderListingWaitsForANewerOne() throws {
        let other = base.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        _ = try source("same.png", in: folder)
        writes.published(Screenshot(key: folder.appendingPathComponent("r.png").screenshotKey))
        events = []
        let gone = folder.appendingPathComponent("gone.png")
        // Held back for the folder watched before; the current folder holds a file of the same name.
        let elsewhere = other.appendingPathComponent("same.png")
        writes.removed([gone].map(\.screenshotKey), in: try inventory(observedAt: 5))
        writes.removed([elsewhere].map(\.screenshotKey), in: ScreenshotWatcher.Inventory(folder: other, names: [], dates: [:], observedAt: 5))
        XCTAssertEqual(events, [])
        writes.listed(try inventory(observedAt: 5))
        XCTAssertEqual(events, [.rescan("after an app write")])
        events = []
        writes.listed(try inventory(observedAt: 10))
        XCTAssertEqual(events, settled(10) + leaves(gone, 10))
        events = []
        writes.listed(try inventory(observedAt: 12))
        XCTAssertEqual(events, settled(12))
        events = []
        writes.listed(ScreenshotWatcher.Inventory(folder: other, names: [], dates: [:], observedAt: 13))
        XCTAssertEqual(events, settled(13) + leaves(elsewhere, 13))

        clock = 20
        writes.published(Screenshot(key: folder.appendingPathComponent("r2.png").screenshotKey))
        events = []
        writes.removed([gone].map(\.screenshotKey), in: try inventory(observedAt: 15))
        XCTAssertEqual(events, [])
    }

    /// Catches a file replaced in place being removed as gone, a held-back entry that never clears,
    /// or a confirmed removal waiting on an unconfirmed one reported with it.
    func testAnUnconfirmedRemovalWaitsForALaterListing() throws {
        let file = try source("x.png", in: folder)
        let gone = folder.appendingPathComponent("gone.png")
        writes.removed([gone, file].map(\.screenshotKey), in: try inventory(observedAt: 5))
        XCTAssertEqual(events, [.rescan("after an unconfirmed removal")] + leaves(gone, 5))
        events = []
        writes.listed(try inventory(observedAt: 6))
        XCTAssertEqual(events, settled(6))
        events = []
        try FileManager.default.removeItem(at: file)
        writes.listed(try inventory(observedAt: 7))
        XCTAssertEqual(events, settled(7))
    }

    /// Catches a party to the fan-out dropped or doubled, or the listing's time not reaching the drawings.
    func testAWatcherRemovalTellsEachOnceInOrder() throws {
        let gone = folder.appendingPathComponent("a.png")
        writes.removed([gone].map(\.screenshotKey), in: try inventory(observedAt: 20))
        XCTAssertEqual(events, leaves(gone, 20))
    }

    /// Catches a renamed file being told to the drawings before its card, or as a removal.
    func testAWatcherRenameTellsTheCardsThenTheDrawingsAndNoRemoval() throws {
        let from = folder.appendingPathComponent("a.png"), to = folder.appendingPathComponent("b.png")
        writes.renamed([(from: from.screenshotKey, to: to.screenshotKey)], in: try inventory(observedAt: 20))
        XCTAssertEqual(events, [.renameCards([from.screenshotKey], [to.screenshotKey]),
                                .renameDrawings([from.screenshotKey], [to.screenshotKey])])
    }

    /// Catches a rename from a listing older than an app write landing early, or after the sweep
    /// that would take the old name's drawing as the drawing of a file that is gone.
    func testARenameFromAnOlderListingWaitsForANewerOneAndComesBeforeTheSweep() throws {
        let from = folder.appendingPathComponent("a.png"), to = folder.appendingPathComponent("b.png")
        writes.add(request(file: try source()))
        XCTAssertTrue(writes.arrived(folder.appendingPathComponent("src.png").screenshotKey))
        events = []
        writes.renamed([(from: from.screenshotKey, to: to.screenshotKey)], in: try inventory(observedAt: 5))
        XCTAssertEqual(events, [])
        writes.listed(try inventory(observedAt: 12))
        XCTAssertEqual(events, [.renameCards([from.screenshotKey], [to.screenshotKey]),
                                .renameDrawings([from.screenshotKey], [to.screenshotKey])] + settled(12))
    }

    /// Catches a file whose trash failed losing its card, drawing or reply record, or the trash and
    /// the watcher fanning out through copies that differ.
    func testTrashTellsTheStackTheDrawingsAndTheRequestsOnce() throws {
        let a = try source("a.png", in: folder)
        let b = try source("b.png", in: folder)
        trashFailsFor = "b.png"
        writes.trash([Screenshot(key: a.screenshotKey), Screenshot(key: b.screenshotKey)])
        XCTAssertEqual(events, leaves(a, .infinity))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
    }
}
