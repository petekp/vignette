import AppKit
import XCTest

@MainActor
final class FolderWritesTests: XCTestCase {
    private enum Event: Equatable {
        case present(URL, Bool)
        case showCard(URL)
        case removeCards([URL])
        case removeDrawings([URL], TimeInterval)
        case removeReply(URL)
        case sweepDrawings(TimeInterval)
        case reconcileRequests(TimeInterval)
        case rescan(String)
    }

    private var base: URL!
    private var folder: URL!
    private var sources: URL!
    private var writes: FolderWrites!
    private var events: [Event] = []
    /// The agent recorded on each presented file at the moment it was presented.
    private var agentsAtPresent: [String?] = []
    private var clock: TimeInterval = 10
    /// Set to hold the join's answer in `heldJoin` until the test gives it; otherwise the join
    /// answers `joinResult` in the same turn it is asked.
    private var holdsJoin = false
    private var heldJoin: ((Result<Int, Drawings.Failure>) -> Void)?
    private var joinResult: Result<Int, Drawings.Failure> = .success(1)
    /// The one file name whose trash fails.
    private var trashFailsFor: String?

    private let marks = #"[{"type":"ellipse","x":0.1,"y":0.1,"w":0.2,"h":0.2}]"#

    override func setUp() async throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-folder-writes-\(UUID().uuidString)")
        folder = base.appendingPathComponent("folder")
        sources = base.appendingPathComponent("sources")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        writes = FolderWrites(
            trash: { [unowned self] url in
                if url.lastPathComponent == self.trashFailsFor { throw CocoaError(.fileWriteNoPermission) }
                try FileManager.default.removeItem(at: url)
            },
            now: { [unowned self] in self.clock })
        writes.callbacks = FolderWrites.Callbacks(
            folder: { [unowned self] in self.folder },
            present: { [unowned self] shot, annotate in
                self.agentsAtPresent.append(Agent.of(shot.url))
                self.events.append(.present(shot.url, annotate))
            },
            showCard: { [unowned self] shot in self.events.append(.showCard(shot.url)) },
            joinMarks: { [unowned self] _, _, _, done in
                if self.holdsJoin { self.heldJoin = done } else { done(self.joinResult) }
            },
            removeCards: { [unowned self] shots in self.events.append(.removeCards(shots.map(\.url))) },
            removeDrawings: { [unowned self] urls, observedAt in self.events.append(.removeDrawings(urls, observedAt)) },
            removeReply: { [unowned self] url in self.events.append(.removeReply(url)) },
            sweepDrawings: { [unowned self] inventory in self.events.append(.sweepDrawings(inventory.observedAt)) },
            reconcileRequests: { [unowned self] inventory in self.events.append(.reconcileRequests(inventory.observedAt)) },
            rescan: { [unowned self] reason in self.events.append(.rescan(reason)) })
    }

    override func tearDown() async throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try? FileManager.default.removeItem(at: base)
    }

    // MARK: Helpers

    private func png(_ side: Int = 4) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    private func source(_ name: String = "src.png", in directory: URL? = nil) throws -> URL {
        let url = (directory ?? sources).appendingPathComponent(name)
        try png().write(to: url)
        return url
    }

    private func request(file: URL, annotate: Bool = false, agent: String? = nil, session: String? = nil,
                         marks: String? = nil) -> CommandRequest {
        CommandRequest(name: "add", files: [file], tag: nil, annotate: annotate, agent: agent, session: session,
                       marks: marks, root: nil, clear: nil)
    }

    private func listing() throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
    }

    private func inventory(observedAt: TimeInterval) throws -> ScreenshotWatcher.Inventory {
        ScreenshotWatcher.Inventory(folder: folder, names: try listing(), dates: [:], observedAt: observedAt)
    }

    /// What a current listing does before anything else.
    private func settled(_ observedAt: TimeInterval) -> [Event] {
        [.sweepDrawings(observedAt), .reconcileRequests(observedAt)]
    }

    private func leaves(_ url: URL, _ observedAt: TimeInterval) -> [Event] {
        [.removeCards([url]), .removeDrawings([url], observedAt), .removeReply(url)]
    }

    // MARK: Adds

    /// Catches the editor opening before the agent's marks are in its drawing, or a card presented
    /// on both the report and the join.
    func testAReportBeforeTheMarksJoinPresentsOnceAfterThem() throws {
        holdsJoin = true
        writes.add(request(file: try source(), annotate: true, marks: marks))
        let destination = folder.appendingPathComponent("src.png")
        XCTAssertTrue(writes.arrived(destination))
        XCTAssertEqual(events, [])
        heldJoin?(.success(1))
        XCTAssertEqual(events, [.present(destination, true)])
        XCTAssertFalse(writes.arrived(destination))
        XCTAssertEqual(events, [.present(destination, true)])
    }

    /// Catches presenting on the join alone, before the watcher has reported a decodable file, with
    /// the join answering in the same turn it was asked.
    func testMarksJoiningBeforeTheReportWaitForIt() throws {
        writes.add(request(file: try source(), marks: marks))
        let destination = folder.appendingPathComponent("src.png")
        XCTAssertEqual(events, [])
        XCTAssertTrue(writes.arrived(destination))
        XCTAssertEqual(events, [.present(destination, false)])
    }

    /// Catches an add of a file already in the folder waiting for a watcher report that never
    /// comes, or its card presented before its agent is recorded, which leaves the card without its badge.
    func testAnAddAlreadyInTheFolderPresentsWithoutAReport() throws {
        let file = try source("inside.png", in: folder)
        let before = try listing()
        writes.add(request(file: file, agent: "claude"))
        XCTAssertEqual(events, [.present(file, false)])
        XCTAssertEqual(agentsAtPresent, ["claude"])
        XCTAssertEqual(try listing(), before)
        XCTAssertFalse(writes.arrived(file))
    }

    /// Catches a stale listing removing the card of a file an agent has just pushed: an add records
    /// the write time, so a listing observed before it waits for a newer one.
    func testAnAddHoldsBackRemovalsFromAnOlderListing() throws {
        writes.add(request(file: try source()))
        XCTAssertTrue(writes.arrived(folder.appendingPathComponent("src.png")))
        events = []
        writes.removed([folder.appendingPathComponent("gone.png")], in: try inventory(observedAt: 5))
        XCTAssertEqual(events, [])
        writes.listed(try inventory(observedAt: 5))
        XCTAssertEqual(events, [.rescan("after an app write")])
    }

    // MARK: Live ink cards

    /// Writes a live ink card and waits for its answer.
    private func card(from destination: AgentDestination? = nil, fails: Bool = false) async -> URL? {
        let data: Data? = fails ? nil : png()
        let answered = expectation(description: "written")
        var written: URL?
        writes.writeCard(named: "Live ink result", png: { data }, from: destination) {
            written = $0
            answered.fulfill()
        }
        await fulfillment(of: [answered], timeout: 5)
        return written
    }

    /// Catches a live ink card shown as a capture, before its marks are in, or without the session
    /// Reply goes back to.
    func testALiveCardWaitsForItsReportAndItsMarks() async throws {
        let thread = UUID().uuidString.lowercased()
        let written = await card(from: AgentDestination(id: thread, name: "Codex", address: .codexThread(uuid: thread)))
        let url = try XCTUnwrap(written)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(Agent.origin(of: url)?.id, thread)
        XCTAssertTrue(writes.arrived(url))
        XCTAssertEqual(events, [])
        writes.ready(url)
        XCTAssertEqual(events, [.present(url, false)])
        XCTAssertFalse(writes.arrived(url))
    }

    /// Catches a card that is ready before the watcher reports it being shown before the file is
    /// decodable, or not at all.
    func testALiveCardReadyBeforeItsReportWaitsForIt() async throws {
        let written = await card()
        let url = try XCTUnwrap(written)
        writes.ready(url)
        XCTAssertEqual(events, [])
        XCTAssertTrue(writes.arrived(url))
        XCTAssertEqual(events, [.present(url, false)])
    }

    /// Catches a stale listing removing a live ink card just written.
    func testALiveCardHoldsBackRemovalsFromAnOlderListing() async throws {
        let written = await card()
        XCTAssertNotNil(written)
        writes.listed(try inventory(observedAt: 5))
        XCTAssertEqual(events, [.rescan("after an app write")])
    }

    /// Catches a refused note leaving its file, its drawing, or a reservation that turns the
    /// watcher's later report of that name into a card.
    func testATakenBackCardLeavesNothing() async throws {
        let written = await card()
        let url = try XCTUnwrap(written)
        writes.takeBack(url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(events, [.removeDrawings([url], .infinity)])
        XCTAssertFalse(writes.arrived(url))
    }

    /// Catches a card that was not written keeping its name reserved or recording a write.
    func testACardThatIsNotWrittenLeavesNothing() async throws {
        let url = await card(fails: true)
        XCTAssertNil(url)
        XCTAssertEqual(try listing(), [])
        writes.listed(try inventory(observedAt: 5))
        XCTAssertEqual(events, settled(5))
    }

    /// Catches two cards asked for within one second taking the same name, which would write one
    /// over the other.
    func testTwoCardsInOneSecondTakeTwoNames() async throws {
        let data = png()
        let answered = expectation(description: "both written")
        answered.expectedFulfillmentCount = 2
        var urls: [URL] = []
        for _ in 0..<2 {
            writes.writeCard(named: "Live ink note", png: { data }, from: nil) {
                if let url = $0 { urls.append(url) }
                answered.fulfill()
            }
        }
        await fulfillment(of: [answered], timeout: 5)
        XCTAssertEqual(Set(urls.map(\.lastPathComponent)).count, 2)
        XCTAssertEqual(try listing().count, 2)
    }

    /// Catches a failed join taking the image back out of the folder, or dropping its card.
    func testMarksThatFailKeepTheImageAndStillPresent() throws {
        joinResult = .failure(Drawings.Failure(code: .writeFailed, description: "x"))
        writes.add(request(file: try source(), marks: marks))
        let destination = folder.appendingPathComponent("src.png")
        XCTAssertTrue(writes.arrived(destination))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(events, [.present(destination, false)])
    }

    /// Catches the copy moving ahead of the mark check: a push with bad marks is one error line and no file.
    func testBadMarksCopyNothing() throws {
        writes.add(request(file: try source(), marks: #"{"type":"ellipse"}"#))
        XCTAssertEqual(try listing(), [])
        XCTAssertFalse(writes.arrived(folder.appendingPathComponent("src.png")))
    }

    /// Catches a copy landing on `Agent reply <uuid>.png`: it would have no reply record, so the
    /// reply's visibility check would hide it for good.
    func testAnAddRefusesAReplyName() throws {
        let file = try source("Agent reply \(UUID().uuidString.lowercased()).png")
        writes.add(request(file: file))
        XCTAssertEqual(try listing(), [])
        XCTAssertFalse(writes.arrived(folder.appendingPathComponent(file.lastPathComponent)))
        XCTAssertEqual(events, [])
    }

    /// Catches a pending entry left behind by a failed copy, which would swallow a later capture of
    /// that name, or a write time recorded for a write that never happened.
    func testACopyThatFailsLeavesNothingWaitingAndRecordsNoWrite() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        writes.add(request(file: try source()))
        XCTAssertEqual(try listing(), [])
        XCTAssertFalse(writes.arrived(folder.appendingPathComponent("src.png")))
        let gone = folder.appendingPathComponent("gone.png")
        writes.removed([gone], in: try inventory(observedAt: 5))
        XCTAssertEqual(events, leaves(gone, 5))
    }

    /// Catches the attribute writes that give a pushed card its badge and its Reply going missing,
    /// or a push from outside the folder presenting before the watcher has reported its copy.
    func testAnAddRecordsItsAgentAndSessionOnTheCopy() throws {
        let session = UUID().uuidString
        writes.add(request(file: try source(), agent: "claude", session: session))
        let first = folder.appendingPathComponent("src.png")
        XCTAssertEqual(events, [])
        XCTAssertEqual(Agent.of(first), "claude")
        XCTAssertEqual(Agent.origin(of: first)?.id, session.lowercased())

        writes.add(request(file: try source(), agent: "claude", session: "not-a-uuid"))
        let second = folder.appendingPathComponent("src 2.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertEqual(Agent.of(second), "claude")
        XCTAssertNil(Agent.origin(of: second))
    }

    // MARK: Stitches and replies

    /// Catches a stitch registered as Vignette's own, which would stop annotateOnCapture opening it.
    /// It also pins that a stitch records no write time, so changing that is a deliberate edit here.
    func testAStitchIsNotReservedAndRecordsNoWriteTime() throws {
        let out = folder.appendingPathComponent("Stitch x.png")
        let bytes = png()
        try writes.writeStitch(bytes, to: out)
        XCTAssertEqual(try Data(contentsOf: out), bytes)
        XCTAssertFalse(writes.arrived(out))
        let gone = folder.appendingPathComponent("gone.png")
        writes.removed([gone], in: try inventory(observedAt: 5))
        XCTAssertEqual(events, leaves(gone, 5))
    }

    /// Catches a reply's card shown without the write time, which would let a stale listing remove
    /// a card, or a reply presented as a capture.
    func testAPublishedReplyRecordsTheWriteTimeAndShowsItsCard() throws {
        let reply = folder.appendingPathComponent("r.png")
        writes.published(Screenshot(url: reply))
        XCTAssertEqual(events, [.showCard(reply)])
        writes.removed([folder.appendingPathComponent("gone.png")], in: try inventory(observedAt: 5))
        XCTAssertEqual(events, [.showCard(reply)])
    }

    // MARK: Removals

    /// Catches a stale listing removing a file the app just wrote, a held-back removal never
    /// confirmed or confirmed twice, the held-back path removing drawings and replies a second time,
    /// a listing of one folder dropping the removals held back for another, or a later write not
    /// holding back removals from a listing that was current until then.
    func testARemovalFromAnOlderListingWaitsForANewerOne() throws {
        let other = base.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        _ = try source("same.png", in: folder)
        writes.published(Screenshot(url: folder.appendingPathComponent("r.png")))
        events = []
        let gone = folder.appendingPathComponent("gone.png")
        // Held back for the folder watched before; the current folder holds a file of the same name.
        let elsewhere = other.appendingPathComponent("same.png")
        writes.removed([gone], in: try inventory(observedAt: 5))
        writes.removed([elsewhere], in: ScreenshotWatcher.Inventory(folder: other, names: [], dates: [:], observedAt: 5))
        XCTAssertEqual(events, [])
        writes.listed(try inventory(observedAt: 5))
        XCTAssertEqual(events, [.rescan("after an app write")])
        events = []
        writes.listed(try inventory(observedAt: 10))
        XCTAssertEqual(events, settled(10) + [.removeCards([gone])])
        events = []
        writes.listed(try inventory(observedAt: 12))
        XCTAssertEqual(events, settled(12))
        events = []
        writes.listed(ScreenshotWatcher.Inventory(folder: other, names: [], dates: [:], observedAt: 13))
        XCTAssertEqual(events, settled(13) + [.removeCards([elsewhere])])

        clock = 20
        writes.published(Screenshot(url: folder.appendingPathComponent("r2.png")))
        events = []
        writes.removed([gone], in: try inventory(observedAt: 15))
        XCTAssertEqual(events, [])
    }

    /// Catches a file replaced in place being removed as gone, a held-back entry that never clears,
    /// or a confirmed removal waiting on an unconfirmed one reported with it.
    func testAnUnconfirmedRemovalWaitsForALaterListing() throws {
        let file = try source("x.png", in: folder)
        let gone = folder.appendingPathComponent("gone.png")
        writes.removed([gone, file], in: try inventory(observedAt: 5))
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
        writes.removed([gone], in: try inventory(observedAt: 20))
        XCTAssertEqual(events, leaves(gone, 20))
    }

    /// Catches a file whose trash failed losing its card, drawing or reply record, or the trash and
    /// the watcher fanning out through copies that differ.
    func testTrashTellsTheStackTheDrawingsAndTheRequestsOnce() throws {
        let a = try source("a.png", in: folder)
        let b = try source("b.png", in: folder)
        trashFailsFor = "b.png"
        writes.trash([Screenshot(url: a), Screenshot(url: b)])
        XCTAssertEqual(events, leaves(a, .infinity))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
    }
}
