import AppKit
import XCTest

final class ScreenshotWatcherTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-watcher-\(UUID().uuidString)")
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

    private func waitFor(_ availability: ScreenshotWatcher.Availability, in watcher: ScreenshotWatcher) {
        let reached = expectation(description: "folder becomes \(availability)")
        let deadline = Date().addingTimeInterval(3)
        func check() {
            if watcher.availability == availability { reached.fulfill(); return }
            if Date() < deadline { DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: check) }
        }
        check()
        wait(for: [reached], timeout: 4)
    }

    func testProtectedAreaIsTheDesktopDocumentsOrDownloadsAndWhatIsInside() {
        let home = URL(fileURLWithPath: "/Users/someone")
        func area(_ path: String) -> String? { ScreenshotWatcher.protectedArea(of: URL(fileURLWithPath: path), home: home) }
        XCTAssertEqual(area("/Users/someone/Desktop"), "your Desktop")
        XCTAssertEqual(area("/Users/someone/Desktop/Screenshots/"), "your Desktop")
        XCTAssertEqual(area("/Users/someone/Documents/Shots"), "your Documents folder")
        XCTAssertEqual(area("/Users/someone/Downloads"), "your Downloads folder")
        XCTAssertNil(area("/Users/someone/DesktopArchive"))
        XCTAssertNil(area("/Users/someone/Dropbox/Screenshots"))
        XCTAssertEqual(area("/Users/someone/Library/Mobile Documents/com~apple~CloudDocs/Shots"), "your iCloud Drive")
        XCTAssertEqual(area("/Users/someone/Library/CloudStorage/Dropbox/Screenshots"), "your Dropbox folder")
        XCTAssertEqual(area("/Users/someone/Library/CloudStorage/GoogleDrive-a@b.com/My Drive"), "your GoogleDrive folder")
        XCTAssertEqual(area("/Volumes/Shots/2026"), "that disk")
    }

    func testCandidatesAreScreenshotFormatsAndNotOutputs() {
        for name in ["Screenshot 1.png", "x.PNG", "x.jpg", "x.jpeg", "x.heic", "Screenshot 1.mov", "x.MOV"] { XCTAssertTrue(ScreenshotWatcher.isCandidate(name), name) }
        for name in [".hidden.png", "x-annotated.png", "x.pdf", "x.tiff", "x.gif", "png", "x.png.part"] { XCTAssertFalse(ScreenshotWatcher.isCandidate(name), name) }
    }

    func testRecentAreNewestFirstAndLimited() throws {
        let now = Date()
        let old = try png("old.png", mtime: now.addingTimeInterval(-30))
        let mid = try png("mid.png", mtime: now.addingTimeInterval(-20))
        let new = try png("new.png", mtime: now.addingTimeInterval(-10))
        let same = try png("same.png", mtime: now.addingTimeInterval(-10))
        try "no".write(to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        let watcher = ScreenshotWatcher(folder: dir, onNew: { _ in }, onRemoved: { _, _ in })
        XCTAssertEqual(watcher.recent(limit: 10).recent, [same, new, mid, old], "an equal date falls to the name, which carries the capture time")
        XCTAssertEqual(watcher.recent(limit: 2).recent, [same, new])
        XCTAssertEqual(watcher.recent(limit: 2).files, 4, "the count is every candidate, past the limit")
        XCTAssertEqual(watcher.recent(limit: -1).recent, [], "a negative limit yields nothing instead of trapping")
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
                                        onRemoved: { urls, _ in reportedRemoved = urls; removedSeen.fulfill() })
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
        let watcher = ScreenshotWatcher(folder: later, onNew: { reported.insert($0); newSeen.fulfill() }, onRemoved: { _, _ in })
        XCTAssertNil(watcher.newest())
        try FileManager.default.createDirectory(at: later, withIntermediateDirectories: true)
        // A volume mounting brings files older than the watcher, which are not new captures.
        _ = try png("later/old.png", mtime: Date().addingTimeInterval(-3600))
        let first = try png("later/first.png")
        XCTAssertEqual(watcher.newest(), first, "an unwatched folder is listed on every read")
        XCTAssertEqual(watcher.recent(limit: 10).files, 2)
        watcher.rescan(reason: "test")   // retries the watch; the file that arrived meanwhile is reported too
        let second = try png("later/second.png")
        wait(for: [newSeen], timeout: 5)
        XCTAssertEqual(reported, [first, second])
        withExtendedLifetime(watcher) {}
    }

    func testAnIndexedFolderThatDisappearsKeepsItsFiles() throws {
        let existing = try png("existing.png")
        let removed = expectation(description: "unavailable input is not a removal")
        removed.isInverted = true
        let watcher = ScreenshotWatcher(folder: dir, onNew: { _ in }, onRemoved: { _, _ in removed.fulfill() })
        let away = dir.appendingPathExtension("unavailable")
        try FileManager.default.moveItem(at: dir, to: away)
        defer { try? FileManager.default.moveItem(at: away, to: dir) }
        watcher.rescan(reason: "test missing folder")
        waitFor(.missing, in: watcher)
        wait(for: [removed], timeout: 0.5)
        XCTAssertEqual(watcher.newest(), existing)
        XCTAssertEqual(watcher.recent(limit: 10).files, 1)
        withExtendedLifetime(watcher) {}
    }

    func testAReplacementDirectoryReceivesLaterArrivals() throws {
        _ = try png("existing.png")
        let replacementSeen = expectation(description: "replacement directory listed")
        let laterSeen = expectation(description: "later arrival on replacement directory")
        var listed = false
        let watcher = ScreenshotWatcher(folder: dir, onNew: { url in
            if url.lastPathComponent == "later.png" { laterSeen.fulfill() }
        }, onRemoved: { _, _ in }, onInventory: { inventory in
            if inventory.names.contains("replacement.png"), !listed {
                listed = true
                replacementSeen.fulfill()
            }
        })
        let away = dir.appendingPathExtension("replaced")
        try FileManager.default.moveItem(at: dir, to: away)
        defer { try? FileManager.default.removeItem(at: away) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = try png("replacement.png")
        watcher.rescan(reason: "test replacement")
        wait(for: [replacementSeen], timeout: 5)
        let later = try png("later.png")
        wait(for: [laterSeen], timeout: 5)
        XCTAssertEqual(watcher.newest(), later)
        withExtendedLifetime(watcher) {}
    }

    func testAQueuedInventoryIsNotDeliveredAfterItsDirectoryDisappears() throws {
        let delivered = expectation(description: "obsolete directory inventory is not delivered")
        delivered.isInverted = true
        let watcher = ScreenshotWatcher(folder: dir, onNew: { _ in }, onRemoved: { _, _ in },
                                        onInventory: { _ in delivered.fulfill() })
        let away = dir.appendingPathExtension("queued-away")
        try FileManager.default.moveItem(at: dir, to: away)
        defer { try? FileManager.default.moveItem(at: away, to: dir) }
        waitFor(.missing, in: watcher)
        wait(for: [delivered], timeout: 0.3)
        withExtendedLifetime(watcher) {}
    }

    func testAnUndeliveredArrivalSurvivesFolderUnavailability() throws {
        for missing in [false, true] {
            let name = missing ? "missing" : "refused"
            let folder = dir.appendingPathComponent(name)
            let away = folder.appendingPathExtension("away")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            _ = try png("\(name)/existing.png")
            let arrivalSeen = expectation(description: "the undelivered capture survives \(name)")
            arrivalSeen.assertForOverFulfill = true
            var interrupted = false
            var arrivals: [URL] = []
            let watcher = ScreenshotWatcher(folder: folder, onNew: { url in
                arrivals.append(url)
                arrivalSeen.fulfill()
            }, onRemoved: { _, _ in }, onInventory: { inventory in
                guard inventory.names.contains("added.png"), !interrupted else { return }
                interrupted = true
                // Hold main delivery while stable-file admission queues its result.
                Thread.sleep(forTimeInterval: 0.3)
                do {
                    if missing { try FileManager.default.moveItem(at: folder, to: away) }
                    else { try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path) }
                } catch { XCTFail("could not interrupt scratch-folder access: \(error)") }
            })
            defer {
                if missing { try? FileManager.default.moveItem(at: away, to: folder) }
                else { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }
            }
            let added = try png("\(name)/added.png")
            waitFor(missing ? .missing : .refused, in: watcher)
            XCTAssertTrue(arrivals.isEmpty)
            if missing { try FileManager.default.moveItem(at: away, to: folder) }
            else { try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }
            watcher.rescan(reason: "test arrival recovery")
            wait(for: [arrivalSeen], timeout: 5)
            XCTAssertEqual(arrivals, [added])
            withExtendedLifetime(watcher) {}
        }
    }

    func testUnknownDatesKeepPresenceAndDoNotClaimMountedCaptures() {
        let date = Date()
        let inventory = ScreenshotWatcher.Inventory(folder: dir, names: ["known.png", "unknown.png", "notes.txt"],
                                                     dates: [:], observedAt: 0)
        let candidates = inventory.candidates(retaining: ["known.png": date])
        XCTAssertEqual(Set(candidates.keys), ["known.png", "unknown.png"])
        XCTAssertEqual(candidates["known.png"], date)
        XCTAssertEqual(ScreenshotWatcher.recent(from: candidates, in: dir, limit: 10).files, 2)
        XCTAssertFalse(inventory.confirmsAbsence(of: dir.appendingPathComponent("unknown.png")))
        XCTAssertTrue(inventory.captures(since: date.addingTimeInterval(-1)).isEmpty)
    }

    func testTheFirstSuccessfulListingAfterRefusalIsSilent() throws {
        _ = try png("existing.png")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path) }
        let newSeen = expectation(description: "existing files are not new captures")
        newSeen.isInverted = true
        let watcher = ScreenshotWatcher(folder: dir, onNew: { _ in newSeen.fulfill() }, onRemoved: { _, _ in })
        waitFor(.refused, in: watcher)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        watcher.rescan(reason: "test permission grant")
        waitFor(.available, in: watcher)
        wait(for: [newSeen], timeout: 0.3)
        XCTAssertEqual(watcher.recent(limit: 10).files, 1)
        withExtendedLifetime(watcher) {}
    }
}
