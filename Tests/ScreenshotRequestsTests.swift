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
    /// The requests whose reply could not be made a card.
    private var replyFailures: [String] = []
    /// Set to hold the answer: the completion lands here instead of being called, which is what a
    /// real installation does before its completion reaches the request owner.
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
            installDrawing: { [unowned self] _, marks, _, done in
                self.added.append(marks)
                guard self.heldAdd == nil else { self.heldAdd = done; return }
                done(self.addFails ? Drawings.Failure(code: .writeFailed, description: "disk full") : nil)
            },
            present: { [unowned self] shot in self.presented.append(shot.url) },
            watchFolder: { [unowned self] in self.folder },
            replyFailed: { [unowned self] record, _ in self.replyFailures.append(record.id) })
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    // MARK: Helpers

    private func inventory(in folder: URL) throws -> ScreenshotWatcher.Inventory {
        let observedAt = ProcessInfo.processInfo.systemUptime
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        return ScreenshotWatcher.Inventory(folder: folder, names: Set(files.map(\.lastPathComponent)), dates: [:], observedAt: observedAt)
    }

    private func png(_ side: Int = 4) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    private func jpeg(_ side: Int) -> Data {
        NSBitmapImageRep(data: png(side))!.representation(using: .jpeg, properties: [:])!
    }

    /// A stored request with no connection behind it, so nothing is submitted anywhere.
    private func makeRequest() throws -> ScreenshotRequests.Record {
        requests.reconcile(try inventory(in: folder))
        return try requests.send(png: png(), source: folder.appendingPathComponent("Screenshot.png"),
                                 to: AgentDestination(id: "s", name: "A session", address: .claudeSession("session-1")))
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
                            image: Data? = nil, answer: String? = nil) throws -> URL {
        let directory = ReplyProtocol.submissionDirectory(root: root, requestID: record.id, replyID: replyID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bundle = Data(#"{"protocolVersion":\#(ReplyProtocol.version),"hasImage":\#(image != nil),"marks":\#(answer == nil ? marks : "[]"),\#(answer.map { #""answer":\#($0),"# } ?? "")"replyId":"\#(replyID)","requestId":"\#(record.id)"}"#.utf8)
        try bundle.write(to: directory.appendingPathComponent("bundle.json"))
        if let image { try image.write(to: directory.appendingPathComponent("image.png")) }
        let digest = ReplyProtocol.payloadDigest(bundle: bundle, image: image)
        let url = ReplyProtocol.attemptURL(root: root, requestID: record.id, replyID: replyID, attemptID: attemptID)
        firstAttemptID = attemptID
        let secret = try secret ?? ticket(for: record).secret
        try Data(#"{"protocolVersion":\#(ReplyProtocol.version),"requestId":"\#(record.id)","replyId":"\#(replyID)","attemptId":"\#(attemptID)","payloadDigest":"\#(digest)","secret":"\#(secret)"}"#.utf8).write(to: url)
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

    private func stored(_ record: ScreenshotRequests.Record) throws -> ScreenshotRequests.Record {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = ReplyProtocol.requestDirectory(root: root, requestID: record.id).appendingPathComponent(ScreenshotRequests.recordFileName)
        return try decoder.decode(ScreenshotRequests.Record.self, from: Data(contentsOf: file))
    }

    private func commitClearedRecord(_ record: ScreenshotRequests.Record) throws {
        var cleared = try stored(record)
        cleared.status = .cleared
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let file = ReplyProtocol.requestDirectory(root: root, requestID: record.id).appendingPathComponent(ScreenshotRequests.recordFileName)
        try encoder.encode(cleared).write(to: file, options: .atomic)
    }

    // MARK: Sending stores before anything else happens

    func testRecoveryPublishesOneCompleteDrawingAfterInstallationWasInterrupted() throws {
        let store = DrawingStore(directory: root.deletingLastPathComponent().appendingPathComponent("drawings"))
        let drawings = Drawings(store: store)
        requests.callbacks.installDrawing = { [unowned self] shot, marks, agent, done in
            do {
                try drawings.installReply(marks, from: agent, at: shot.url, style: .standard, newPointScale: 2)
                self.heldAdd = done
            } catch {
                done(Drawings.Failure(code: .writeFailed, description: "\(error)"))
            }
        }
        let record = try makeRequest()
        requests.receiveReply(envelope: try stageReply(record,
            marks: #"[{"type":"rectangle","x":0.1,"y":0.1,"w":0.2,"h":0.2},{"type":"text","x":0.2,"y":0.3,"text":"The reply"}]"#,
            image: png(256)))
        XCTAssertTrue(presented.isEmpty)
        let id = try replyID(in: record)
        let output = folder.appendingPathComponent(ReplyProtocol.replyFileName(id))
        let pixels = try XCTUnwrap(PixelSize(imageAt: output))
        let before = try XCTUnwrap(store.readComplete(key: output.path, pixels: pixels, style: .standard))
        let bytes = try Data(contentsOf: store.url(for: output.path))
        requests = ScreenshotRequests(root: root)
        let reopened = Drawings(store: store)
        var changedUI = UITweaks()
        changedUI.agentTextSize *= 2
        let changedStyle = changedUI.textStyle
        requests.callbacks = ScreenshotRequests.Callbacks(
            installDrawing: { shot, marks, agent, done in
                do {
                    try reopened.installReply(marks, from: agent, at: shot.url, style: changedStyle, newPointScale: 1)
                    done(nil)
                } catch { done(Drawings.Failure(code: .writeFailed, description: "\(error)")) }
            },
            present: { [unowned self] shot in self.presented.append(shot.url) },
            watchFolder: { [unowned self] in self.folder })
        requests.load()
        requests.reconcile(try inventory(in: folder))
        XCTAssertEqual(presented, [output])
        XCTAssertTrue(requests.isVisible(output))
        let after = try XCTUnwrap(store.readComplete(key: output.path, pixels: pixels, style: .standard))
        XCTAssertEqual(after.pointScale, before.pointScale)
        XCTAssertEqual(after.marks.map(\.geometry), before.marks.map(\.geometry))
        XCTAssertEqual(after.marks.count, 2)
        XCTAssertEqual(try Data(contentsOf: store.url(for: output.path)), bytes)
    }

    /// The line names only the image. The skill finds the ticket beside it, so that is where it must be.
    func testTheRequestLineNamesTheImageBesideItsTicketAndNotTheSecret() throws {
        let record = try makeRequest()
        let line = ScreenshotRequests.requestLine(record: record, root: root)
        let directory = ReplyProtocol.requestDirectory(root: root, requestID: record.id)
        XCTAssertTrue(line.hasPrefix("From Vignette: \"\(directory.appendingPathComponent("image.png").path)\""))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ticket.json").path))
        let secret = try ticket(for: record).secret
        XCTAssertFalse(secret.isEmpty)
        XCTAssertFalse(line.contains(secret), "a secret in the line would be logged with the URL")
        XCTAssertFalse(line.contains("\n"), "herdr submits the line with Return")

        let asked = ScreenshotRequests.requestLine(record: record, root: root, message: "Make this bigger")
        XCTAssertEqual(asked, "Make this bigger [\(line)]", "the person's message leads, and the Vignette part is a note after it")

        // settings.json's `sendInstructions` replaces the sentence after the image, and an empty one drops it.
        let image = directory.appendingPathComponent("image.png").path
        XCTAssertEqual(ScreenshotRequests.requestLine(record: record, root: root, instructions: "Reply with marks."),
                       "From Vignette: \"\(image)\". Reply with marks.")
        XCTAssertEqual(ScreenshotRequests.requestLine(record: record, root: root, instructions: ""), "From Vignette: \"\(image)\".")
    }

    /// The field takes line breaks from a paste or Option+Return; the line cannot hold them.
    func testAMessageJoinsTheLineAsOneLineAndABlankOneIsNone() {
        let model = AnnotatorToolbar.Model()
        model.message = "  Make this bigger\nand bluer\r\n\tplease  "
        XCTAssertEqual(model.sentMessage, "Make this bigger and bluer please")
        model.message = " \n\t "
        XCTAssertNil(model.sentMessage)
    }

    // MARK: Acceptance

    /// An answer to live ink becomes live ink's own result card, and the reply makes no file; one
    /// whose window cannot be captured, or that comes after a relaunch, still reaches the person as a
    /// card on the request's picture. Either way the receipt is written again once it is drawn,
    /// naming the marks that were not.
    func testAnAnswerBecomesLiveInksResultOrElseACard() throws {
        var shown: [LiveAnswer] = []
        var drawsLive = true
        requests.callbacks.presentLive = { _, answer, done in
            shown.append(answer)
            // The words of the first mark are not on the window.
            done(drawsLive ? [0] : nil)
        }
        let answer = #"{"say":"Moved the dates under the title.","marks":[{"kind":"circle","words":"October 12","label":"moved"},{"kind":"arrow","box":[0.1,0.2,0.3,0.1]}]}"#

        let live = try makeRequest()
        let attemptID = UUID().uuidString.lowercased()
        try requests.receiveReply(envelope: stageReply(live, attemptID: attemptID, answer: answer))
        XCTAssertEqual(shown.first?.say, "Moved the dates under the title.")
        XCTAssertEqual(shown.first?.marks.first?.words, "October 12")
        XCTAssertEqual(receipt(live, attemptID)?.acceptance, .accepted)
        XCTAssertEqual(receipt(live, attemptID)?.publication, .ready)
        XCTAssertEqual(receipt(live, attemptID)?.notDrawn, [0])
        let replies = (requests.stateJSON["replies"] as? [[String: Any]]) ?? []
        XCTAssertEqual(replies.first { $0["request"] as? String == live.id }?["stage"] as? String, "shown")
        XCTAssertTrue(presented.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)

        drawsLive = false
        let card = try makeRequest()
        let cardAttempt = UUID().uuidString.lowercased()
        try requests.receiveReply(envelope: stageReply(card, attemptID: cardAttempt, answer: answer))
        XCTAssertEqual(presented.count, 1)
        let marks = try XCTUnwrap(added.last)
        XCTAssertEqual(marks.first?.text, "Moved the dates under the title.")
        // The words-only mark has nothing to find on the request's picture; the boxed arrow points at its box.
        XCTAssertEqual(marks.map(\.type), [.text, .arrow])
        XCTAssertEqual(receipt(card, cardAttempt)?.notDrawn, [0])
    }

    /// The skill's helper is `ReplyCommand`. What it writes has to be what this side accepts, and a
    /// retry of the same bundle has to be acknowledged without a second card.
    func testAReplyTheCommandPreparesIsAcceptedAndItsRetryMakesNoSecondCard() throws {
        let record = try makeRequest()
        let ticketFile = ReplyProtocol.requestDirectory(root: root, requestID: record.id).appendingPathComponent("ticket.json")
        let ticket = try ReplyCommand.loadTicket(ticketFile.path)
        let marksFile = root.deletingLastPathComponent().appendingPathComponent("marks.json")
        try Data(#"[{"type":"arrow","x":0.5,"y":0.9,"x2":0.4,"y2":0.6},{"type":"text","x":0.2,"y":0.1,"text":"a \"quoted\" word"}]"#.utf8)
            .write(to: marksFile)
        let prepared = try ReplyCommand.prepare(ticket: ticket, marks: ReplyCommand.loadMarks(marksFile.path), image: nil)

        let first = try ReplyCommand.writeAttempt(ticket: ticket, prepared: prepared)
        requests.receiveReply(envelope: first.envelope)
        let receipt = try XCTUnwrap(self.receipt(record, first.id))
        XCTAssertEqual(receipt.acceptance, .accepted, receipt.errorCode ?? "")
        XCTAssertTrue(ReplyCommand.answers(receipt, ticket: ticket, prepared: prepared, attemptID: first.id))
        let cards = presented.count

        let again = try ReplyCommand.reread(prepared.directory)
        XCTAssertEqual(again, prepared, "a retry carries the same reply id and digest")
        let second = try ReplyCommand.writeAttempt(ticket: ticket, prepared: again)
        requests.receiveReply(envelope: second.envelope)
        XCTAssertEqual(self.receipt(record, second.id)?.acceptance, .accepted)
        XCTAssertEqual(presented.count, cards, "a retry makes no second card")
        XCTAssertEqual((requests.stateJSON["replies"] as? [[String: Any]])?.count, 1)
    }

    /// The command sends the agent's picture as a PNG whatever it was, and with it an empty marks
    /// list, which is what the app accepts.
    func testAPictureTheCommandSendsIsAPNGTheAppAccepts() throws {
        let record = try makeRequest()
        let ticketFile = ReplyProtocol.requestDirectory(root: root, requestID: record.id).appendingPathComponent("ticket.json")
        let ticket = try ReplyCommand.loadTicket(ticketFile.path)
        let picture = root.deletingLastPathComponent().appendingPathComponent("picture.jpg")
        try jpeg(6).write(to: picture)
        let marksFile = root.deletingLastPathComponent().appendingPathComponent("marks.json")
        try Data("[]".utf8).write(to: marksFile)
        let prepared = try ReplyCommand.prepare(ticket: ticket, marks: ReplyCommand.loadMarks(marksFile.path, allowingEmpty: true),
                                                image: ReplyCommand.loadImage(picture))

        let attempt = try ReplyCommand.writeAttempt(ticket: ticket, prepared: prepared)
        requests.receiveReply(envelope: attempt.envelope)
        XCTAssertEqual(receipt(record, attempt.id)?.acceptance, .accepted)
        let published = folder.appendingPathComponent(ReplyProtocol.replyFileName(prepared.replyID))
        XCTAssertTrue(ReplyProtocol.isPNG(try Data(contentsOf: published)))
    }

    /// A reply is published as `Agent reply <id>.png`, so a picture in any other format is refused
    /// rather than published under a name that says it is a PNG.
    func testAReplyPictureThatIsNotAPNGIsRefused() throws {
        let record = try makeRequest()
        let attemptID = UUID().uuidString.lowercased()
        requests.receiveReply(envelope: try stageReply(record, attemptID: attemptID, image: jpeg(6)))
        XCTAssertEqual(receipt(record, attemptID)?.errorCode, ReplyProtocol.Refusal.badPayload.rawValue)
        XCTAssertTrue(presented.isEmpty)
    }

    /// The attempt names its bundle's digest, so bytes changed after the helper checked them are
    /// refused rather than shown as what the agent sent.
    func testABundleChangedAfterItsAttemptWasWrittenIsRefused() throws {
        let record = try makeRequest()
        let replyID = UUID().uuidString.lowercased(), attemptID = UUID().uuidString.lowercased()
        let envelope = try stageReply(record, replyID: replyID, attemptID: attemptID)
        let bundle = ReplyProtocol.submissionDirectory(root: root, requestID: record.id, replyID: replyID).appendingPathComponent("bundle.json")
        let changed = try String(contentsOf: bundle, encoding: .utf8).replacingOccurrences(of: #""x":0.1"#, with: #""x":0.5"#)
        try Data(changed.utf8).write(to: bundle)
        requests.receiveReply(envelope: envelope)
        XCTAssertEqual(receipt(record, attemptID)?.errorCode, ReplyProtocol.Refusal.digestMismatch.rawValue)
        XCTAssertTrue(presented.isEmpty)
        XCTAssertEqual((requests.stateJSON["replies"] as? [[String: Any]])?.count, 0)
    }

    func testAReplyWithoutTheTicketIsRefusedAndNothingIsStored() throws {
        let record = try makeRequest()
        let attemptID = UUID().uuidString.lowercased()
        try requests.receiveReply(envelope: stageReply(record, attemptID: attemptID, secret: "guessed"))
        XCTAssertEqual(self.receipt(record, attemptID)?.acceptance, .rejected)
        XCTAssertEqual(self.receipt(record, attemptID)?.errorCode, "bad-authorization")
        XCTAssertEqual((requests.stateJSON["replies"] as? [[String: Any]])?.count, 0)
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
        try Data(#"{"protocolVersion":\#(ReplyProtocol.version),"requestId":"\#(missing)","replyId":"dddddddd-0000-4000-8000-000000000001","attemptId":"eeeeeeee-0000-4000-8000-000000000001","payloadDigest":"sha256:\#(String(repeating: "0", count: 64))","secret":"x"}"#.utf8).write(to: url)
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
        XCTAssertEqual(replyFailures, [record.id], "the card that was sent says so instead")
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
        folder = root.deletingLastPathComponent().appendingPathComponent("new-folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let reopened = ScreenshotRequests(root: root)
        reopened.callbacks = requests.callbacks
        reopened.load()
        XCTAssertTrue(presented.isEmpty, "record loading does not access a screenshots folder before readiness")
        reopened.reconcile(try inventory(in: folder))
        XCTAssertEqual(presented, [file])
        XCTAssertEqual((reopened.stateJSON["pendingImports"] as? [String])?.count, 0)
        XCTAssertTrue(reopened.isVisible(file))
    }

    // MARK: Clearing

    func testEveryLateSubmissionOutcomeLeavesClearTerminal() async throws {
        let outcomes: [SubmissionOutcome] = [
            .accepted(detail: "accepted"), .queued(detail: "queued", reason: "queued"),
            .uncertain(detail: "uncertain", reason: "uncertain"),
            .notSubmitted(code: .sendFailed, detail: "refused", reason: "refused"),
            .destinationChanged(detail: "changed", reason: "changed"),
        ]
        let connection = HeldSubmission()
        let callbacks = requests.callbacks
        requests = ScreenshotRequests(root: root, connections: [.claude: connection])
        requests.callbacks = callbacks
        for outcome in outcomes {
            connection.outcome = outcome
            let answered = expectation(description: "delayed submission answers")
            requests.callbacks.delivered = { _, delivered in
                XCTAssertEqual(delivered.detail, outcome.detail)
                answered.fulfill()
            }
            let record = try makeRequest()
            XCTAssertEqual(connection.entered.wait(timeout: .now() + 3), .success)
            requests.run(clear: record.id)
            let cleared = try stored(record)
            XCTAssertEqual(cleared.status, .cleared)
            connection.resume.signal()
            await fulfillment(of: [answered], timeout: 3)
            XCTAssertEqual(try stored(record).status, .cleared)
            XCTAssertEqual(try stored(record).detail, cleared.detail)
            let reopened = ScreenshotRequests(root: root)
            reopened.callbacks = requests.callbacks
            reopened.load()
            let attempt = UUID().uuidString.lowercased()
            reopened.receiveReply(envelope: try stageReply(record, attemptID: attempt))
            XCTAssertEqual(receipt(record, attempt)?.errorCode, "request-closed")
        }
    }

    // MARK: Waiting before the line goes

    private func send(_ file: String, grace: TimeInterval = 3, message: String? = nil) throws -> (record: ScreenshotRequests.Record, source: URL) {
        requests.reconcile(try inventory(in: folder))
        let source = folder.appendingPathComponent(file)
        try png().write(to: source)
        let record = try requests.send(png: png(), source: source,
                                       to: AgentDestination(id: "s", name: "A session", address: .claudeSession("session-1")),
                                       message: message, grace: grace)
        return (record, source)
    }

    /// Gives `requests` a recording connection and a clock and timers the test runs by hand.
    private func holdSends(events: GraceEvents) -> (connection: RecordingConnection, clock: GraceClock) {
        let connection = RecordingConnection(events: events)
        let clock = GraceClock()
        let callbacks = requests.callbacks
        requests = ScreenshotRequests(root: root, connections: [.claude: connection], now: { clock.time },
                                      schedule: { _, work in clock.timers.append(work) })
        requests.callbacks = callbacks
        requests.callbacks.released = { _ in events.add("released") }
        requests.callbacks.cancelled = { _ in events.add("cancelled") }
        return (connection, clock)
    }

    /// Waits long enough for a submission the last step started on another queue to reach the client,
    /// and fails if one did: reading `lines` straight away would pass whenever the submit is still on its way.
    private func assertNothingSent(to connection: RecordingConnection, file: StaticString = #filePath, line: UInt = #line) async {
        let arrived = expectation(description: "a line reached the client")
        arrived.isInverted = true
        connection.onSubmit = { arrived.fulfill() }
        await fulfillment(of: [arrived], timeout: 0.3)
        connection.onSubmit = nil
        XCTAssertEqual(connection.lines, [], "a line reached the client", file: file, line: line)
    }

    /// A changed or lost line, or the client asked before the card was told, is a send that went wrong.
    func testTheLineWaitsForTheGraceThenGoesUnchanged() async throws {
        let events = GraceEvents()
        let (connection, clock) = holdSends(events: events)
        let answered = expectation(description: "delivered")
        requests.callbacks.delivered = { _, _ in events.add("delivered"); answered.fulfill() }
        let (record, _) = try send("Shot.png", message: "look at this")
        await assertNothingSent(to: connection)
        XCTAssertEqual(try stored(record).status, .prepared)
        let waiting = try XCTUnwrap((requests.stateJSON["requests"] as? [[String: Any]])?.first?["graceMs"] as? Int)
        XCTAssertEqual(waiting, 3000)

        clock.time += 3
        clock.fire()
        await fulfillment(of: [answered], timeout: 3)
        XCTAssertEqual(events.all, ["released", "submit", "delivered"])
        let expected = ScreenshotRequests.requestLine(record: record, root: root, message: "look at this",
                                                      instructions: SettingsData.defaultSendInstructions)
        XCTAssertEqual(connection.lines, [expected], "the line is what a send with no grace would have written")
        XCTAssertEqual(try stored(record).status, .submitted)
    }

    /// A send cancelled in its grace that still reached the agent, or deleted the screenshot, is the failure to catch.
    func testDontSendClearsTheRequestAndNothingIsEverSent() async throws {
        let events = GraceEvents()
        let (connection, clock) = holdSends(events: events)
        let (record, source) = try send("Shot.png")
        XCTAssertEqual(requests.unsend(file: source).map(\.id), [record.id])
        XCTAssertEqual(events.all, ["cancelled"])
        clock.time += 3
        clock.fire()
        await assertNothingSent(to: connection)
        XCTAssertEqual(try stored(record).status, .cleared)
        let directory = ReplyProtocol.requestDirectory(root: root, requestID: record.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("image.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "the person's screenshot stays")
        let attempt = UUID().uuidString.lowercased()
        requests.receiveReply(envelope: try stageReply(record, attemptID: attempt))
        XCTAssertEqual(receipt(record, attempt)?.errorCode, "request-closed")
    }

    /// Cancelling after the line went must not clear a request the agent already has.
    func testDontSendAfterTheLineWentChangesNothing() async throws {
        let events = GraceEvents()
        let (_, clock) = holdSends(events: events)
        let answered = expectation(description: "delivered")
        requests.callbacks.delivered = { _, _ in answered.fulfill() }
        let (record, source) = try send("Shot.png")
        clock.time += 3
        clock.fire()
        await fulfillment(of: [answered], timeout: 3)
        XCTAssertTrue(requests.unsend(file: source).isEmpty)
        XCTAssertFalse(events.all.contains("cancelled"))
        XCTAssertEqual(try stored(record).status, .submitted)
    }

    /// Cancelling one screenshot's send must leave another screenshot's to go at its deadline.
    func testSendsOfTwoScreenshotsAreCancelledApart() async throws {
        let events = GraceEvents()
        let (connection, clock) = holdSends(events: events)
        let answered = expectation(description: "delivered")
        requests.callbacks.delivered = { _, _ in answered.fulfill() }
        let (_, first) = try send("First.png")
        let (second, _) = try send("Second.png")
        XCTAssertEqual(requests.unsend(file: first).count, 1)
        clock.time += 3
        clock.fire()
        await fulfillment(of: [answered], timeout: 3)
        XCTAssertEqual(connection.lines.count, 1)
        XCTAssertTrue(connection.lines[0].contains(second.id))
    }

    /// A request cleared by id or by the admission limit must not be sent when its timer runs.
    func testClearingAWaitingRequestStopsItsSend() async throws {
        let events = GraceEvents()
        let (connection, clock) = holdSends(events: events)
        let (record, _) = try send("Shot.png")
        requests.run(clear: record.id)
        XCTAssertEqual(events.all, ["cancelled"])
        clock.time += 3
        clock.fire()
        await assertNothingSent(to: connection)
    }

    /// A timer that runs early must not shorten the grace, and one that runs late must still send once.
    func testATimerThatRunsEarlyArmsAgainForWhatIsLeft() async throws {
        let events = GraceEvents()
        let (connection, clock) = holdSends(events: events)
        let answered = expectation(description: "delivered")
        requests.callbacks.delivered = { _, _ in answered.fulfill() }
        _ = try send("Shot.png")
        clock.time += 1
        clock.fire()
        await assertNothingSent(to: connection)
        XCTAssertEqual(clock.timers.count, 1, "armed again for the two seconds left")
        clock.time += 2
        clock.fire()
        await fulfillment(of: [answered], timeout: 3)
        XCTAssertEqual(connection.lines.count, 1)
    }

    /// A session that ended during the grace is the existing failure, told after the grace and not before.
    func testAnAnswerThatFailsAfterTheGraceReachesTheCard() async throws {
        let events = GraceEvents()
        let (connection, clock) = holdSends(events: events)
        connection.outcome = .notSubmitted(code: .noAgent, detail: "ended", reason: "This session has ended.")
        let answered = expectation(description: "delivered")
        var delivered: SubmissionOutcome?
        requests.callbacks.delivered = { _, outcome in delivered = outcome; answered.fulfill() }
        let (record, _) = try send("Shot.png")
        XCTAssertEqual(try stored(record).status, .prepared)
        clock.time += 3
        clock.fire()
        await fulfillment(of: [answered], timeout: 3)
        guard case .notSubmitted(_, _, let reason)? = delivered else { return XCTFail("expected a failure") }
        XCTAssertEqual(reason, "This session has ended.")
        XCTAssertNotEqual(try stored(record).status, .prepared)
    }

    /// Deleting the card is a way of not sending it: a file that left the folder cancels its waiting send.
    func testAFileThatLeavesTheFolderCancelsItsWaitingSend() async throws {
        let events = GraceEvents()
        let (connection, clock) = holdSends(events: events)
        let (record, source) = try send("Shot.png")
        requests.fileRemoved(source)
        XCTAssertEqual(events.all, ["cancelled"])
        clock.time += 3
        clock.fire()
        await assertNothingSent(to: connection)
        XCTAssertEqual(try stored(record).status, .cleared)
    }

    /// A quit or crash during the grace takes the line from memory: the request must not stay prepared for good.
    func testARequestStillPreparedAtLaunchIsClearedBecauseItsLineIsGone() throws {
        let events = GraceEvents()
        _ = holdSends(events: events)
        let (record, _) = try send("Shot.png")
        XCTAssertEqual(try stored(record).status, .prepared)
        let reopened = ScreenshotRequests(root: root)
        reopened.callbacks = requests.callbacks
        reopened.load()
        XCTAssertEqual(try stored(record).status, .cleared)
        let image = ReplyProtocol.requestDirectory(root: root, requestID: record.id).appendingPathComponent("image.png")
        XCTAssertFalse(FileManager.default.fileExists(atPath: image.path))
    }

    /// A client that answers after quit's wait must not hold the quit up, and its late answer must not crash.
    func testQuitDoesNotWaitLongerThanItsLimitForASlowClient() throws {
        let slow = HeldSubmission()
        let clock = GraceClock()
        requests = ScreenshotRequests(root: root, connections: [.claude: slow], now: { clock.time },
                                      schedule: { _, work in clock.timers.append(work) })
        let (record, _) = try send("Shot.png")
        let started = Date()
        requests.releaseHeld(waitingUpTo: 0.05)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        // The line may have arrived, so the next launch must not clear it as one that never went.
        XCTAssertEqual(try stored(record).status, .uncertain)
        slow.resume.signal()
        let reopened = ScreenshotRequests(root: root)
        reopened.load()
        XCTAssertEqual(try stored(record).status, .uncertain)
        let image = ReplyProtocol.requestDirectory(root: root, requestID: record.id).appendingPathComponent("image.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: image.path), "the image the line names stays")
    }

    /// Quitting is not a retraction: the waiting line goes once, and the cards the callbacks tell are going too.
    func testQuitHandsAWaitingSendOverOnceWithoutTouchingCards() async throws {
        let events = GraceEvents()
        let (connection, clock) = holdSends(events: events)
        requests.callbacks.delivered = { _, _ in events.add("delivered") }
        let (record, _) = try send("Shot.png")
        requests.releaseHeld()
        XCTAssertEqual(connection.lines.count, 1)
        XCTAssertEqual(try stored(record).status, .submitted)
        clock.time += 3
        clock.fire()
        // A callback queued for the main thread runs before this one does.
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 3)
        XCTAssertEqual(connection.lines.count, 1, "the timer that was armed finds nothing")
        XCTAssertEqual(events.all, ["submit"])
    }

    /// A newer launch loads while the older copy is still handing its waiting lines over as it quits.
    /// Clearing the request then deletes the image the line names.
    func testALaunchReplacingACopyLeavesItsWaitingSendsAlone() throws {
        let events = GraceEvents()
        let (connection, _) = holdSends(events: events)
        let (record, _) = try send("Shot.png")
        let newer = ScreenshotRequests(root: root)
        newer.load(clearingUnsent: false)
        let image = ReplyProtocol.requestDirectory(root: root, requestID: record.id).appendingPathComponent("image.png")
        XCTAssertEqual(try stored(record).status, .prepared)
        XCTAssertTrue(FileManager.default.fileExists(atPath: image.path))
        requests.releaseHeld()
        XCTAssertEqual(connection.lines.count, 1)
        XCTAssertEqual(try stored(record).status, .submitted, "the older copy's answer is not written over a cleared record")
        XCTAssertTrue(FileManager.default.fileExists(atPath: image.path))
    }

    func testClearWriteFailureKeepsStateAndOwnedFiles() throws {
        heldAdd = { _ in }
        let record = try makeRequest()
        try requests.receiveReply(envelope: stageReply(record))
        let output = folder.appendingPathComponent(ReplyProtocol.replyFileName(try replyID(in: record)))
        let directory = ReplyProtocol.requestDirectory(root: root, requestID: record.id)
        let before = try stored(record)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        requests.run(clear: record.id)
        XCTAssertEqual(try stored(record).status, before.status)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("image.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("submissions").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        let attempt = UUID().uuidString.lowercased()
        requests.receiveReply(envelope: try stageReply(record, attemptID: attempt))
        XCTAssertEqual(receipt(record, attempt)?.acceptance, .accepted)
    }

    func testClearRemovesAFailedImportsOwnedOutputAtItsRecordedLocation() throws {
        addFails = true
        let record = try makeRequest()
        try requests.receiveReply(envelope: stageReply(record))
        let id = try replyID(in: record)
        let output = folder.appendingPathComponent(ReplyProtocol.replyFileName(id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        let outputFolder = try XCTUnwrap(folder)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: outputFolder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: outputFolder.path) }
        folder = root.deletingLastPathComponent().appendingPathComponent("new-current-folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        requests.run(clear: record.id)
        XCTAssertEqual(try stored(record).status, .cleared)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path), "a refused deletion remains pending")
        XCTAssertEqual((requests.stateJSON["replies"] as? [[String: Any]])?.first?["stage"] as? String, "cancelled")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: outputFolder.path)
        requests.reconcile(try inventory(in: folder))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))

        let file = ReplyProtocol.requestDirectory(root: root, requestID: record.id)
            .appendingPathComponent("replies").appendingPathComponent(id + ".json")
        let bytes = try Data(contentsOf: file)
        let inode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? NSNumber)
        for _ in 0..<3 {
            requests.reconcile(try inventory(in: folder))
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? NSNumber, inode,
                           "a screenshot scan must not replace an unchanged completed cancellation")
        }
        let reopened = ScreenshotRequests(root: root)
        reopened.callbacks = requests.callbacks
        reopened.load()
        reopened.reconcile(try inventory(in: folder))
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? NSNumber, inode)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testLoadReplaysClearCleanupAndCannotPublishAnUncancelledReply() throws {
        heldAdd = { _ in }
        let record = try makeRequest()
        try requests.receiveReply(envelope: stageReply(record))
        let id = try replyID(in: record)
        let output = folder.appendingPathComponent(ReplyProtocol.replyFileName(id))
        let directory = ReplyProtocol.requestDirectory(root: root, requestID: record.id)
        let repliesDirectory = directory.appendingPathComponent("replies")
        let file = repliesDirectory.appendingPathComponent(id + ".json")
        let before = try Data(contentsOf: file)
        try commitClearedRecord(record)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: repliesDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: repliesDirectory.path) }
        let reopened = ScreenshotRequests(root: root)
        reopened.callbacks = requests.callbacks
        reopened.load()
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path), "screenshot cleanup waits for startup readiness")
        XCTAssertEqual(reopened.stateJSON["pendingImports"] as? [String], [])
        reopened.reconcile(try inventory(in: folder))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(presented.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), before, "the blocked write left the reserved record on disk")
        XCTAssertEqual((reopened.stateJSON["replies"] as? [[String: Any]])?.first?["stage"] as? String, "cancelled")
        let interrupted = ScreenshotRequests(root: root)
        interrupted.callbacks = requests.callbacks
        interrupted.load()
        interrupted.reconcile(try inventory(in: folder))
        XCTAssertEqual(try Data(contentsOf: file), before)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: repliesDirectory.path)
        interrupted.reconcile(try inventory(in: folder))
        let cancelled = try JSONDecoder().decode(ScreenshotRequests.Reply.self, from: Data(contentsOf: file))
        XCTAssertEqual(cancelled.stage, .cancelled)
        XCTAssertEqual(cancelled.needsOutputCleanup, false)
        XCTAssertEqual(cancelled.errorCode, "request-cleared")
        let inode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? NSNumber)
        let again = ScreenshotRequests(root: root)
        again.callbacks = requests.callbacks
        again.load()
        again.reconcile(try inventory(in: folder))
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? NSNumber, inode)
        again.reconcile(try inventory(in: folder), now: Date().addingTimeInterval(ScreenshotRequests.clearedKept + 60))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertTrue(presented.isEmpty)
    }

    func testAdmissionFailureDoesNotAccumulatePreparedRequestsOrClearOldPayloads() throws {
        var records: [ScreenshotRequests.Record] = []
        for _ in 0..<ScreenshotRequests.maxLiveRequests { records.append(try makeRequest()) }
        let oldest = try XCTUnwrap(records.first)
        let directory = ReplyProtocol.requestDirectory(root: root, requestID: oldest.id)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        for _ in 0..<3 { XCTAssertThrowsError(try makeRequest()) }
        XCTAssertEqual((requests.stateJSON["requests"] as? [[String: Any]])?.count, ScreenshotRequests.maxLiveRequests)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).count,
                       ScreenshotRequests.maxLiveRequests)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("image.png").path))
        XCTAssertNotEqual(try stored(oldest).status, .cleared)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        _ = try makeRequest()
        XCTAssertEqual(try stored(oldest).status, .cleared)
    }

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

    /// Pruning deletes a request's folder, and with it the record of every reply to it. A reply still
    /// in the watch folder is shown only by its record, so that request outlasts the week.
    func testPruningKeepsARequestWhoseReplyIsStillACard() throws {
        let answered = try makeRequest()
        try requests.receiveReply(envelope: stageReply(answered))
        let reply = folder.appendingPathComponent(ReplyProtocol.replyFileName(try replyID(in: answered)))
        let unanswered = try makeRequest()
        requests.run(clear: "all")
        requests.prune(now: Date().addingTimeInterval(ScreenshotRequests.clearedKept + 60))

        XCTAssertTrue(requests.isVisible(reply), "the reply's card stays")
        XCTAssertTrue(FileManager.default.fileExists(atPath: ReplyProtocol.requestDirectory(root: root, requestID: answered.id).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ReplyProtocol.requestDirectory(root: root, requestID: unanswered.id).path),
                       "a request with nothing on screen goes")
    }

    func testDeletingAPublishedReplyIsARemovalAndNotARebuild() throws {
        let record = try makeRequest()
        try requests.receiveReply(envelope: stageReply(record))
        let file = folder.appendingPathComponent(ReplyProtocol.replyFileName(try replyID(in: record)))
        let other = root.deletingLastPathComponent().appendingPathComponent("other-folder")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let copy = other.appendingPathComponent(file.lastPathComponent)
        try FileManager.default.copyItem(at: file, to: copy)
        XCTAssertFalse(requests.isVisible(copy))
        XCTAssertNil(requests.origin(of: copy))
        requests.fileRemoved(copy)
        XCTAssertEqual((requests.stateJSON["replies"] as? [[String: Any]])?.first?["deleted"] as? Bool, false)
        try FileManager.default.removeItem(at: file)
        requests.fileRemoved(file)
        XCTAssertEqual((requests.stateJSON["replies"] as? [[String: Any]])?.first?["deleted"] as? Bool, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "the recovery copy never puts it back")
    }

    func testAnUnavailableReplyFolderDoesNotLosePublicationOnLoadOrPrune() throws {
        let record = try makeRequest()
        try requests.receiveReply(envelope: stageReply(record))
        let reply = folder.appendingPathComponent(ReplyProtocol.replyFileName(try replyID(in: record)))
        requests.run(clear: record.id)
        let away = folder.appendingPathExtension("unavailable")
        try FileManager.default.moveItem(at: folder, to: away)
        defer { try? FileManager.default.moveItem(at: away, to: folder) }

        let reopened = ScreenshotRequests(root: root)
        reopened.callbacks = requests.callbacks
        reopened.load()
        reopened.prune(now: Date().addingTimeInterval(ScreenshotRequests.clearedKept + 60))
        XCTAssertTrue(reopened.isVisible(reply))
        XCTAssertEqual(reopened.origin(of: reply)?.id, record.destinationID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ReplyProtocol.requestDirectory(root: root, requestID: record.id).path))
    }

    func testChangingFoldersDoesNotPruneAPublishedReplyInTheOriginalFolder() throws {
        let record = try makeRequest()
        try requests.receiveReply(envelope: stageReply(record))
        let reply = folder.appendingPathComponent(ReplyProtocol.replyFileName(try replyID(in: record)))
        requests.run(clear: record.id)
        folder = root.deletingLastPathComponent().appendingPathComponent("other-shots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        requests.reconcile(ScreenshotWatcher.Inventory(folder: folder, names: [], dates: [:],
                                                         observedAt: ProcessInfo.processInfo.systemUptime),
                           now: Date().addingTimeInterval(ScreenshotRequests.clearedKept + 60))
        requests.prune(now: Date().addingTimeInterval(ScreenshotRequests.clearedKept + 60))
        XCTAssertTrue(requests.isVisible(reply))
        XCTAssertEqual(requests.origin(of: reply)?.id, record.destinationID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: reply.path))
    }

    func testAQueuedInventoryCannotRemoveANewerPublishedReply() throws {
        let inventory = ScreenshotWatcher.Inventory(folder: folder, names: [], dates: [:],
                                                     observedAt: ProcessInfo.processInfo.systemUptime)
        let record = try makeRequest()
        try requests.receiveReply(envelope: stageReply(record))
        let reply = folder.appendingPathComponent(ReplyProtocol.replyFileName(try replyID(in: record)))
        requests.run(clear: record.id)
        requests.reconcile(inventory, now: Date().addingTimeInterval(ScreenshotRequests.clearedKept + 60))
        XCTAssertTrue(requests.isVisible(reply))
        XCTAssertEqual((requests.stateJSON["replies"] as? [[String: Any]])?.first?["deleted"] as? Bool, false)
    }

    func testAnAcceptedReplyWaitsForStartupInventory() throws {
        let waiting = ScreenshotRequests(root: root)
        waiting.callbacks = requests.callbacks
        let record = try waiting.send(png: png(), source: folder.appendingPathComponent("Screenshot.png"),
                                      to: AgentDestination(id: "s", name: "A session", address: .claudeSession("session-1")))
        try waiting.receiveReply(envelope: stageReply(record))
        let rows = try XCTUnwrap(waiting.stateJSON["replies"] as? [[String: Any]])
        let id = try XCTUnwrap(rows.first?["id"] as? String)
        let file = folder.appendingPathComponent(ReplyProtocol.replyFileName(id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(presented.isEmpty)
        XCTAssertEqual(rows.first?["stage"] as? String, "accepted")
        waiting.reconcile(try inventory(in: folder))
        XCTAssertEqual(presented, [file])
        XCTAssertTrue(waiting.isVisible(file))
    }

    func testAReservedReplyWithoutLocationFailsAfterStartupReadiness() throws {
        heldAdd = { _ in }
        let record = try makeRequest()
        try requests.receiveReply(envelope: stageReply(record, image: png()))
        let id = try replyID(in: record)
        let directory = ReplyProtocol.requestDirectory(root: root, requestID: record.id)
        let recordFile = directory.appendingPathComponent("replies").appendingPathComponent(id + ".json")
        var stored = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: recordFile)) as? [String: Any])
        stored["destination"] = nil
        try JSONSerialization.data(withJSONObject: stored).write(to: recordFile, options: .atomic)
        let output = folder.appendingPathComponent(ReplyProtocol.replyFileName(id))
        try FileManager.default.removeItem(at: output)
        heldAdd = nil
        let reopened = ScreenshotRequests(root: root)
        reopened.callbacks = requests.callbacks
        reopened.load()
        reopened.reconcile(try inventory(in: folder))
        let rows = try XCTUnwrap(reopened.stateJSON["replies"] as? [[String: Any]])
        XCTAssertEqual(rows.first?["stage"] as? String, "failed")
        XCTAssertEqual(rows.first?["error"] as? String, "destination-unknown")
        XCTAssertEqual(reopened.stateJSON["pendingImports"] as? [String], [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("payloads/\(id).png").path))
    }

    func testConfirmedAbsenceAtThePublishedLocationAllowsRetentionCleanup() throws {
        let record = try makeRequest()
        try requests.receiveReply(envelope: stageReply(record))
        let reply = folder.appendingPathComponent(ReplyProtocol.replyFileName(try replyID(in: record)))
        requests.run(clear: record.id)
        try FileManager.default.removeItem(at: reply)
        requests.reconcile(ScreenshotWatcher.Inventory(folder: folder, names: [], dates: [:],
                                                         observedAt: ProcessInfo.processInfo.systemUptime),
                           now: Date().addingTimeInterval(ScreenshotRequests.clearedKept + 60))
        XCTAssertFalse(requests.isVisible(reply))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ReplyProtocol.requestDirectory(root: root, requestID: record.id).path))
    }

    func testLocationlessPublishedRecordsAreRetainedWithoutGuessing() throws {
        let record = try makeRequest()
        try requests.receiveReply(envelope: stageReply(record))
        let id = try replyID(in: record)
        let reply = folder.appendingPathComponent(ReplyProtocol.replyFileName(id))
        requests.run(clear: record.id)
        let file = ReplyProtocol.requestDirectory(root: root, requestID: record.id)
            .appendingPathComponent("replies").appendingPathComponent(id + ".json")
        var stored = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        stored["destination"] = nil
        try JSONSerialization.data(withJSONObject: stored).write(to: file, options: .atomic)
        try FileManager.default.removeItem(at: reply)
        let reopened = ScreenshotRequests(root: root)
        reopened.callbacks = requests.callbacks
        reopened.load()
        reopened.reconcile(ScreenshotWatcher.Inventory(folder: folder, names: [], dates: [:],
                                                         observedAt: ProcessInfo.processInfo.systemUptime),
                           now: Date().addingTimeInterval(ScreenshotRequests.clearedKept + 60))
        XCTAssertTrue(reopened.isVisible(reply))
        XCTAssertEqual(reopened.origin(of: reply)?.id, record.destinationID)
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
            heldAdd = { _ in }             // hold the next add's answer
            requests.receiveReply(envelope: try stageReply(record))
            let id = try replyID(in: record)
            let published = folder.appendingPathComponent(ReplyProtocol.replyFileName(id))
            let answer = try XCTUnwrap(heldAdd)
            XCTAssertTrue(FileManager.default.fileExists(atPath: published.path), "the name is reserved while the marks are added")

            requests.run(clear: record.id)
            answer(outcome)

            XCTAssertEqual(presented, [], "a cleared reply makes no card")
            XCTAssertEqual(replyFailures, [], "and no failure: the person cleared it")
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
        try Data(#"{"protocolVersion":\#(ReplyProtocol.version),"requestId":"\#(second.id)","replyId":"\#(shared)","attemptId":"\#(attemptID)","payloadDigest":"\#(accepted.payloadDigest)","secret":"\#(secret)"}"#.utf8).write(to: envelope)
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

private final class HeldSubmission: AgentConnection, @unchecked Sendable {
    let client = AgentClient.claude
    let entered = DispatchSemaphore(value: 0)
    let resume = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var answer: SubmissionOutcome = .accepted(detail: "")

    /// What the next submission answers once resumed.
    var outcome: SubmissionOutcome {
        get { lock.lock(); defer { lock.unlock() }; return answer }
        set { lock.lock(); answer = newValue; lock.unlock() }
    }

    func destinations() -> [AgentDestination] { [] }
    func submit(_ line: String, to destination: AgentDestination) -> SubmissionOutcome {
        entered.signal()
        _ = resume.wait(timeout: .now() + 5)
        return outcome
    }
}

/// What happened, in order, from callbacks on the main thread and connections on another.
private final class GraceEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    func add(_ event: String) { lock.lock(); events.append(event); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return events }
}

/// The clock and the timers a grace period runs on, moved by hand.
private final class GraceClock {
    var time: TimeInterval = 1000
    var timers: [@MainActor @Sendable () -> Void] = []

    @MainActor func fire() {
        let due = timers
        timers = []
        for timer in due { timer() }
    }
}

private final class RecordingConnection: AgentConnection, @unchecked Sendable {
    let client = AgentClient.claude
    private let events: GraceEvents
    private let lock = NSLock()
    private var sent: [String] = []
    private var answer: SubmissionOutcome = .accepted(detail: "")

    /// What the next submission answers.
    var outcome: SubmissionOutcome {
        get { lock.lock(); defer { lock.unlock() }; return answer }
        set { lock.lock(); answer = newValue; lock.unlock() }
    }

    init(events: GraceEvents) { self.events = events }

    private var arrived: (@Sendable () -> Void)?
    /// Called on the submitting queue for each line, so a test can wait for one that may be on its way.
    var onSubmit: (@Sendable () -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return arrived }
        set { lock.lock(); arrived = newValue; lock.unlock() }
    }

    var lines: [String] { lock.lock(); defer { lock.unlock() }; return sent }
    func destinations() -> [AgentDestination] { [] }
    func submit(_ line: String, to destination: AgentDestination) -> SubmissionOutcome {
        lock.lock(); sent.append(line); lock.unlock()
        events.add("submit")
        onSubmit?()
        return outcome
    }
}
