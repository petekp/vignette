import AppKit
import XCTest

@MainActor
final class ScreenshotRequestsTests: XCTestCase {
    private var root: URL!
    private var folder: URL!
    private var requests: ScreenshotRequests!
    /// The marks the fake page "built" into a draft, and whether storing one is allowed to succeed.
    private var built: [[Mark]] = []
    private var canvasBusy: String?
    private var draftStoreFails = false
    private var presented: [URL] = []
    /// Set to hold the page's answer: the build's completion lands here instead of being called,
    /// which is what a real `buildDraft` does for as long as the page takes.
    private var heldBuild: ((ParkResult?, String?) -> Void)?
    /// The attempt id `stageReply` last wrote, for a test that needs to read back its receipt.
    private var firstAttemptID = ""

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-requests-\(UUID().uuidString)")
        root = base.appendingPathComponent("requests")
        folder = base.appendingPathComponent("shots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        requests = ScreenshotRequests(root: root)
        requests.callbacks = ScreenshotRequests.Callbacks(
            canvasRefusal: { [unowned self] in self.canvasBusy },
            buildDraft: { [unowned self] _, marks, done in
                self.built.append(marks)
                guard self.heldBuild == nil else { self.heldBuild = done; return }
                done(ParkResult(body: ["snapshot": ["store": [:]], "preview": NSNull()]), nil)
            },
            saveDraft: { [unowned self] _, _, _ in
                if self.draftStoreFails { throw ReplyProtocol.Problem(.storeFailed, "disk full") }
            },
            present: { [unowned self] shot in self.presented.append(shot.url) },
            watchFolder: { [unowned self] in self.folder },
            feedback: { _ in })
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    // MARK: Helpers

    private func png(_ side: Int = 4) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    /// A stored request with no connection behind it, so nothing is submitted anywhere.
    private func makeRequest() throws -> ScreenshotRequests.Record {
        let record = requests.send(png: png(), source: folder.appendingPathComponent("Screenshot.png"),
                                   to: AgentDestination(id: "s", name: "A session", address: .claudeSession("session-1")))
        return try XCTUnwrap(record)
    }

    private func ticket(for record: ScreenshotRequests.Record) throws -> ReplyProtocol.Ticket {
        let url = ReplyProtocol.requestDirectory(root: root, requestID: record.id).appendingPathComponent("ticket.json")
        return try JSONDecoder().decode(ReplyProtocol.Ticket.self, from: Data(contentsOf: url))
    }

    /// Writes a bundle and an attempt the way the helper does, and returns the envelope.
    @discardableResult
    private func stageReply(_ record: ScreenshotRequests.Record, replyID: String = UUID().uuidString.lowercased(),
                            attemptID: String = UUID().uuidString.lowercased(), secret: String? = nil,
                            marks: String = #"[{"type":"ellipse","x":0.1,"y":0.1,"w":0.2,"h":0.2}]"#,
                            image: Data? = nil) throws -> URL {
        let directory = ReplyProtocol.submissionDirectory(root: root, requestID: record.id, replyID: replyID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bundle = Data(#"{"protocolVersion":1,"hasImage":\#(image != nil),"marks":\#(marks),"replyId":"\#(replyID)","requestId":"\#(record.id)"}"#.utf8)
        try bundle.write(to: directory.appendingPathComponent("bundle.json"))
        if let image { try image.write(to: directory.appendingPathComponent("image.png")) }
        let digest = ReplyProtocol.payloadDigest(bundle: bundle, image: image)
        let url = ReplyProtocol.attemptURL(root: root, requestID: record.id, replyID: replyID, attemptID: attemptID)
        firstAttemptID = attemptID
        let secret = try secret ?? ticket(for: record).secret
        try Data(#"{"protocolVersion":1,"requestId":"\#(record.id)","replyId":"\#(replyID)","attemptId":"\#(attemptID)","payloadDigest":"\#(digest)","secret":"\#(secret)"}"#.utf8).write(to: url)
        return url
    }

    private func receipt(_ record: ScreenshotRequests.Record, _ attemptID: String) -> ReplyProtocol.Receipt? {
        let url = ReplyProtocol.receiptURL(root: root, requestID: record.id, attemptID: attemptID)
        return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(ReplyProtocol.Receipt.self, from: $0) }
    }

    private func replyID(in record: ScreenshotRequests.Record) throws -> String {
        let replies = (requests.stateJSON["replies"] as? [[String: Any]]) ?? []
        return try XCTUnwrap(replies.first { $0["request"] as? String == record.id }?["id"] as? String)
    }

    // MARK: Sending stores before anything else happens

    func testASentDrawingIsStoredWithItsTicketBeforeAnythingIsSubmitted() throws {
        let record = try makeRequest()
        let directory = ReplyProtocol.requestDirectory(root: root, requestID: record.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("image.png").path))
        XCTAssertEqual(try ticket(for: record).requestID, record.id)
        XCTAssertFalse(try ticket(for: record).secret.isEmpty)
    }

    func testTheRequestLineNamesTheFixedImageAndTheTicketAndNotTheSecret() throws {
        let record = try makeRequest()
        let line = ScreenshotRequests.requestLine(record: record, ticket: try ticket(for: record), root: root)
        XCTAssertTrue(line.contains(record.id))
        XCTAssertTrue(line.contains("ticket.json"))
        XCTAssertFalse(line.contains(try ticket(for: record).secret), "a secret in the line would be logged with the URL")
        XCTAssertFalse(line.contains("\n"), "herdr submits the line with Return")
    }

    // MARK: Acceptance

    func testAValidReplyIsAcceptedAndAcknowledged() throws {
        let record = try makeRequest()
        let attemptID = UUID().uuidString.lowercased()
        try requests.receiveReply(envelope: stageReply(record, attemptID: attemptID))
        let receipt = try XCTUnwrap(self.receipt(record, attemptID))
        XCTAssertEqual(receipt.acceptance, .accepted)
        XCTAssertEqual(receipt.attemptID, attemptID)
    }

    func testAReplyWithoutTheTicketIsRefusedAndNothingIsStored() throws {
        let record = try makeRequest()
        let attemptID = UUID().uuidString.lowercased()
        try requests.receiveReply(envelope: stageReply(record, attemptID: attemptID, secret: "guessed"))
        XCTAssertEqual(self.receipt(record, attemptID)?.acceptance, .rejected)
        XCTAssertEqual(self.receipt(record, attemptID)?.errorCode, "bad-authorization")
        XCTAssertEqual((requests.stateJSON["replies"] as? [[String: Any]])?.count, 0)
    }

    func testTheSameReplyDispatchedAgainIsAcknowledgedAndMakesNoSecondCard() throws {
        let record = try makeRequest()
        let replyID = UUID().uuidString.lowercased()
        try requests.receiveReply(envelope: stageReply(record, replyID: replyID, attemptID: "aaaaaaaa-0000-4000-8000-000000000001"))
        let cards = presented.count
        try requests.receiveReply(envelope: stageReply(record, replyID: replyID, attemptID: "aaaaaaaa-0000-4000-8000-000000000002"))
        XCTAssertEqual(self.receipt(record, "aaaaaaaa-0000-4000-8000-000000000002")?.acceptance, .accepted)
        XCTAssertEqual(presented.count, cards, "a lost acknowledgement must not cost a second card")
        XCTAssertEqual((requests.stateJSON["replies"] as? [[String: Any]])?.count, 1)
    }

    func testTheSameReplyIdWithOtherBytesIsRefusedAndLeavesTheFirstAlone() throws {
        let record = try makeRequest()
        let replyID = UUID().uuidString.lowercased()
        try requests.receiveReply(envelope: stageReply(record, replyID: replyID, attemptID: "bbbbbbbb-0000-4000-8000-000000000001"))
        let envelope = try stageReply(record, replyID: replyID, attemptID: "bbbbbbbb-0000-4000-8000-000000000002",
                                      marks: #"[{"type":"rectangle","x":0.5,"y":0.5,"w":0.2,"h":0.2}]"#)
        requests.receiveReply(envelope: envelope)
        XCTAssertEqual(self.receipt(record, "bbbbbbbb-0000-4000-8000-000000000002")?.errorCode, "conflicting-reply")
        XCTAssertEqual((requests.stateJSON["replies"] as? [[String: Any]])?.first?["stage"] as? String, "published")
    }

    func testAnEnvelopeForAnUnknownRequestWritesNothingAnywhere() throws {
        let record = try makeRequest()
        let envelope = try stageReply(record)
        requests.run(clear: record.id)
        // Clearing removed the submissions, so stage another under a request id that does not exist.
        let missing = "cccccccc-0000-4000-8000-000000000001"
        let directory = ReplyProtocol.submissionDirectory(root: root, requestID: missing, replyID: "dddddddd-0000-4000-8000-000000000001")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = ReplyProtocol.attemptURL(root: root, requestID: missing, replyID: "dddddddd-0000-4000-8000-000000000001", attemptID: "eeeeeeee-0000-4000-8000-000000000001")
        try Data(#"{"protocolVersion":1,"requestId":"\#(missing)","replyId":"dddddddd-0000-4000-8000-000000000001","attemptId":"eeeeeeee-0000-4000-8000-000000000001","payloadDigest":"sha256:\#(String(repeating: "0", count: 64))","secret":"x"}"#.utf8).write(to: url)
        requests.receiveReply(envelope: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ReplyProtocol.receiptURL(root: root, requestID: missing, attemptID: "eeeeeeee-0000-4000-8000-000000000001").path))
    }

    // MARK: Publication and visibility

    func testAPublishedReplyIsOneOrdinaryFileWithOneCard() throws {
        let record = try makeRequest()
        try requests.receiveReply(envelope: stageReply(record))
        let id = try replyID(in: record)
        let file = folder.appendingPathComponent(ReplyProtocol.replyFileName(id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(requests.isVisible(file))
        XCTAssertEqual(presented, [file])
        XCTAssertEqual(built.count, 1)
        XCTAssertEqual(built.first?.first?.type, .ellipse)
    }

    func testAReplyIsNeverACaptureEvenAfterItIsPublished() throws {
        let record = try makeRequest()
        try requests.receiveReply(envelope: stageReply(record))
        let file = folder.appendingPathComponent(ReplyProtocol.replyFileName(try replyID(in: record)))
        XCTAssertFalse(requests.isCapture(file), "a late watcher event must not copy it or open the editor")
        XCTAssertTrue(requests.isCapture(folder.appendingPathComponent("Screenshot 2026-09-20.png")))
    }

    func testAnImportStoppedBeforePublicationLeavesNoVisibleFile() throws {
        draftStoreFails = true
        let record = try makeRequest()
        try requests.receiveReply(envelope: stageReply(record))
        let file = folder.appendingPathComponent(ReplyProtocol.replyFileName(try replyID(in: record)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "the PNG is copied under the reserved name")
        XCTAssertFalse(requests.isVisible(file), "but nothing may list it until publication commits")
        XCTAssertEqual(presented, [])
    }

    func testAnUnknownManagedNameIsHiddenRatherThanTreatedAsACapture() {
        let stray = folder.appendingPathComponent(ReplyProtocol.replyFileName("ffffffff-0000-4000-8000-000000000001"))
        XCTAssertFalse(requests.isVisible(stray), "a corrupt or missing record fails closed")
    }

    func testAReplyWaitsForTheCanvasAndPublishesWhenItIsFree() throws {
        canvasBusy = "an image is in the annotator"
        let record = try makeRequest()
        try requests.receiveReply(envelope: stageReply(record))
        XCTAssertEqual(presented, [], "nothing is shown while the person is drawing")
        XCTAssertEqual(requests.stateJSON["pendingImports"] as? [String], [try replyID(in: record)])
        canvasBusy = nil
        requests.canvasBecameAvailable()
        XCTAssertEqual(presented.count, 1)
        XCTAssertEqual((requests.stateJSON["pendingImports"] as? [String])?.count, 0)
    }

    func testReloadingFromDiskFindsTheSameStateAndResumesWhatWasPending() throws {
        canvasBusy = "an image is in the annotator"
        let record = try makeRequest()
        try requests.receiveReply(envelope: stageReply(record))
        let id = try replyID(in: record)

        let reopened = ScreenshotRequests(root: root)
        reopened.callbacks = requests.callbacks
        reopened.load()
        XCTAssertEqual(reopened.stateJSON["pendingImports"] as? [String], [id])
        XCTAssertFalse(reopened.isVisible(folder.appendingPathComponent(ReplyProtocol.replyFileName(id))))
    }

    // MARK: Clearing

    func testClearingStopsNewRepliesAndCancelsUnpublishedImports() throws {
        canvasBusy = "an image is in the annotator"
        let record = try makeRequest()
        try requests.receiveReply(envelope: stageReply(record))
        requests.run(clear: record.id)
        let replies = try XCTUnwrap(requests.stateJSON["replies"] as? [[String: Any]])
        XCTAssertEqual(replies.first?["stage"] as? String, "cancelled")
        XCTAssertFalse(FileManager.default.fileExists(atPath: ReplyProtocol.requestDirectory(root: root, requestID: record.id).appendingPathComponent("image.png").path))

        let attemptID = "99999999-0000-4000-8000-000000000001"
        try requests.receiveReply(envelope: stageReply(record, attemptID: attemptID))
        XCTAssertEqual(self.receipt(record, attemptID)?.errorCode, "request-closed")
    }

    func testDeletingAPublishedReplyIsARemovalAndNotARebuild() throws {
        let record = try makeRequest()
        try requests.receiveReply(envelope: stageReply(record))
        let file = folder.appendingPathComponent(ReplyProtocol.replyFileName(try replyID(in: record)))
        try FileManager.default.removeItem(at: file)
        requests.fileRemoved(file)
        XCTAssertEqual((requests.stateJSON["replies"] as? [[String: Any]])?.first?["deleted"] as? Bool, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "the recovery copy never puts it back")
    }

    // MARK: What the review found

    /// A reply that carries its own picture is the first thing written under `payloads/`, and
    /// `Data.write` creates no directory. Every such reply was refused `store-failed` until the
    /// request had already taken a marks-only one.
    func testTheFirstReplyToARequestMayCarryItsOwnImage() throws {
        let record = try makeRequest()
        let attemptID = UUID().uuidString.lowercased()
        let envelope = try stageReply(record, attemptID: attemptID, image: png(6))
        requests.receiveReply(envelope: envelope)

        XCTAssertEqual(receipt(record, attemptID)?.acceptance, .accepted)
        let id = try replyID(in: record)
        let published = folder.appendingPathComponent(ReplyProtocol.replyFileName(id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: published.path))
        // The reply's own picture, not the one that was sent out.
        XCTAssertEqual(try Data(contentsOf: published), png(6))
    }

    /// `buildDraft` can be outstanding for seconds. A clear in that window cancels the import, and
    /// the answer arriving afterwards must not publish it anyway.
    func testAClearDuringABuildCancelsTheImportInsteadOfPublishingIt() throws {
        let record = try makeRequest()
        heldBuild = { _, _ in }          // hold the next build's answer
        requests.receiveReply(envelope: try stageReply(record))
        let id = try replyID(in: record)
        let published = folder.appendingPathComponent(ReplyProtocol.replyFileName(id))
        let answer = try XCTUnwrap(heldBuild)
        XCTAssertTrue(FileManager.default.fileExists(atPath: published.path), "the name is reserved while the build runs")

        requests.run(clear: record.id)
        answer(ParkResult(body: ["snapshot": ["store": [:]], "preview": NSNull()]), nil)

        XCTAssertEqual(presented, [], "a cleared reply makes no card")
        XCTAssertFalse(FileManager.default.fileExists(atPath: published.path), "and leaves no hidden file behind")
        let replies = (requests.stateJSON["replies"] as? [[String: Any]]) ?? []
        XCTAssertEqual(replies.first { $0["id"] as? String == id }?["stage"] as? String, "cancelled")
    }

    /// A reply id is answered from its record. The record has to belong to the request the attempt
    /// names, or a ticket for one request answers for a reply accepted under another.
    func testAReplyIdFromAnotherRequestIsRefused() throws {
        let first = try makeRequest()
        let shared = UUID().uuidString.lowercased()
        requests.receiveReply(envelope: try stageReply(first, replyID: shared))
        let accepted = try XCTUnwrap(receipt(first, firstAttemptID))

        // A ticket holder for another request, naming the first reply's id and its digest. Both are
        // readable from the store; the bundle is never reached, so copying it is not required.
        let second = try makeRequest()
        let attemptID = UUID().uuidString.lowercased()
        let directory = ReplyProtocol.submissionDirectory(root: root, requestID: second.id, replyID: shared)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let secret = try ticket(for: second).secret
        let envelope = ReplyProtocol.attemptURL(root: root, requestID: second.id, replyID: shared, attemptID: attemptID)
        try Data(#"{"protocolVersion":1,"requestId":"\#(second.id)","replyId":"\#(shared)","attemptId":"\#(attemptID)","payloadDigest":"\#(accepted.payloadDigest)","secret":"\#(secret)"}"#.utf8).write(to: envelope)
        requests.receiveReply(envelope: envelope)

        XCTAssertEqual(receipt(second, attemptID)?.acceptance, .rejected, "it is not this request's reply to acknowledge")
        XCTAssertEqual(receipt(second, attemptID)?.errorCode, "conflicting-reply")
    }

    /// The attempt id names the receipt and an unauthorized caller chooses it. It may leave a
    /// refusal where there is none; it may not replace the answer a genuine attempt is waiting for.
    func testAnUnauthorizedReplyCannotOverwriteAnExistingReceipt() throws {
        let record = try makeRequest()
        let replyID = UUID().uuidString.lowercased(), attemptID = UUID().uuidString.lowercased()
        requests.receiveReply(envelope: try stageReply(record, replyID: replyID, attemptID: attemptID))
        XCTAssertEqual(receipt(record, attemptID)?.acceptance, .accepted)

        // The same attempt id again, with the wrong secret.
        requests.receiveReply(envelope: try stageReply(record, replyID: UUID().uuidString.lowercased(),
                                                       attemptID: attemptID, secret: "not-the-secret"))
        XCTAssertEqual(receipt(record, attemptID)?.acceptance, .accepted, "the genuine answer stands")
    }

    /// An envelope reached through a symbolic link in place of `submissions/<replyId>` resolves to
    /// the same real file on both sides of a fully resolved comparison. The root is resolved; what
    /// is below it must be real.
    func testAnEnvelopeUnderALinkedSubmissionDirectoryIsRefused() throws {
        let record = try makeRequest()
        let replyID = UUID().uuidString.lowercased(), attemptID = UUID().uuidString.lowercased()
        let envelope = try stageReply(record, replyID: replyID, attemptID: attemptID)
        let real = envelope.deletingLastPathComponent()
        let elsewhere = root.appendingPathComponent("elsewhere")
        try FileManager.default.moveItem(at: real, to: elsewhere)
        try FileManager.default.createSymbolicLink(at: real, withDestinationURL: elsewhere)

        requests.receiveReply(envelope: envelope)
        XCTAssertNil(receipt(record, attemptID), "nothing is accepted and no receipt is written")
        XCTAssertEqual(presented, [])
    }
}
