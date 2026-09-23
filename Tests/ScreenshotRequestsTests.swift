import AppKit
import XCTest

@MainActor
final class ScreenshotRequestsTests: XCTestCase {
    private var root: URL!
    private var folder: URL!
    private var requests: ScreenshotRequests!
    /// The marks added to a drawing, and whether writing it fails.
    private var added: [[AgentMark]] = []
    private var addFails = false
    private var presented: [URL] = []
    private var toasts: [String] = []
    /// Set to hold the answer: the completion lands here instead of being called, which is what a
    /// real `addMarks` does while it makes its colour sample off the main thread.
    private var heldAdd: ((Drawings.Failure?) -> Void)?
    /// The attempt id `stageReply` last wrote, for a test that needs to read back its receipt.
    private var firstAttemptID = ""

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-requests-\(UUID().uuidString)")
        root = base.appendingPathComponent("requests")
        folder = base.appendingPathComponent("shots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        requests = ScreenshotRequests(root: root)
        requests.callbacks = ScreenshotRequests.Callbacks(
            addMarks: { [unowned self] _, marks, done in
                self.added.append(marks)
                guard self.heldAdd == nil else { self.heldAdd = done; return }
                done(self.addFails ? Drawings.Failure(code: .writeFailed, description: "disk full") : nil)
            },
            present: { [unowned self] shot in self.presented.append(shot.url) },
            watchFolder: { [unowned self] in self.folder },
            feedback: { [unowned self] words in self.toasts.append(words) })
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
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(added.first?.first?.type, .ellipse)
    }

    func testAReplyIsNeverACaptureEvenAfterItIsPublished() throws {
        let record = try makeRequest()
        try requests.receiveReply(envelope: stageReply(record))
        let file = folder.appendingPathComponent(ReplyProtocol.replyFileName(try replyID(in: record)))
        XCTAssertFalse(requests.isCapture(file), "a late watcher event must not copy it or open the editor")
        XCTAssertTrue(requests.isCapture(folder.appendingPathComponent("Screenshot 2026-09-20.png")))
    }

    func testAnImportStoppedBeforePublicationLeavesNoVisibleFile() throws {
        addFails = true
        let record = try makeRequest()
        try requests.receiveReply(envelope: stageReply(record))
        let file = folder.appendingPathComponent(ReplyProtocol.replyFileName(try replyID(in: record)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "the PNG is copied under the reserved name")
        XCTAssertFalse(requests.isVisible(file), "but nothing may list it until publication commits")
        XCTAssertEqual(presented, [])
        XCTAssertEqual((requests.stateJSON["replies"] as? [[String: Any]])?.first?["error"] as? String, "draft-store-failed",
                       "the code receipts have always carried for a drawing that could not be stored")
    }

    func testAnUnknownManagedNameIsHiddenRatherThanTreatedAsACapture() {
        let stray = folder.appendingPathComponent(ReplyProtocol.replyFileName("ffffffff-0000-4000-8000-000000000001"))
        XCTAssertFalse(requests.isVisible(stray), "a corrupt or missing record fails closed")
    }

    func testALaunchPublishesTheRepliesStillWaitingOnce() throws {
        heldAdd = { _ in }             // the import stops before publication, as a quit would leave it
        let record = try makeRequest()
        try requests.receiveReply(envelope: stageReply(record))
        let id = try replyID(in: record)
        let file = folder.appendingPathComponent(ReplyProtocol.replyFileName(id))
        XCTAssertEqual(requests.stateJSON["pendingImports"] as? [String], [id])

        heldAdd = nil
        let reopened = ScreenshotRequests(root: root)
        reopened.callbacks = requests.callbacks
        reopened.load()
        XCTAssertEqual(presented, [file], "the records' load is what starts the import")
        XCTAssertEqual((reopened.stateJSON["pendingImports"] as? [String])?.count, 0)
        XCTAssertTrue(reopened.isVisible(file))
    }

    // MARK: Clearing

    func testClearingStopsNewRepliesAndCancelsUnpublishedImports() throws {
        heldAdd = { _ in }             // the import stays unpublished
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

    /// `addMarks` answers later, once its colour sample is made. A clear in that window cancels the
    /// import, and the answer arriving afterwards must not publish it anyway. The clear takes the
    /// file back, so the real answer is a failure, and that must not turn the cancellation into one.
    func testAClearWhileMarksAreAddedCancelsTheImportInsteadOfPublishingIt() throws {
        let gone = Drawings.Failure(code: .unreadableImage, description: "the file is gone")
        for outcome in [nil, gone] {
            let record = try makeRequest()
            toasts = []                      // the send's own, from a request with no connection
            heldAdd = { _ in }             // hold the next add's answer
            requests.receiveReply(envelope: try stageReply(record))
            let id = try replyID(in: record)
            let published = folder.appendingPathComponent(ReplyProtocol.replyFileName(id))
            let answer = try XCTUnwrap(heldAdd)
            XCTAssertTrue(FileManager.default.fileExists(atPath: published.path), "the name is reserved while the marks are added")

            requests.run(clear: record.id)
            answer(outcome)

            XCTAssertEqual(presented, [], "a cleared reply makes no card")
            XCTAssertEqual(toasts, [], "and no toast: the person cleared it")
            XCTAssertFalse(FileManager.default.fileExists(atPath: published.path), "and leaves no hidden file behind")
            let reply = (requests.stateJSON["replies"] as? [[String: Any]])?.first { $0["id"] as? String == id }
            XCTAssertEqual(reply?["stage"] as? String, "cancelled")
            XCTAssertEqual(reply?["error"] as? String, "request-cleared")
        }
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
