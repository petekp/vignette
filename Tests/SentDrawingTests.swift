import AppKit
import XCTest

@MainActor
final class SentDrawingTests: XCTestCase {
    private var base: URL!
    private var folder: URL!
    private var root: URL!

    override func setUp() async throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-sent-drawing-\(UUID().uuidString)")
        folder = base.appendingPathComponent("shots")
        root = base.appendingPathComponent("requests")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func png(_ side: Int = 4) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    private func card(_ name: String = "Checkout.png") throws -> URL {
        let url = folder.appendingPathComponent(name)
        try png().write(to: url)
        return url
    }

    private func agentDrawing(at url: URL) -> Drawing {
        Drawing(key: url.path, pixels: PixelSize(width: 4, height: 4), pointScale: 2, marks: [
            Mark(geometry: .rectangle(CGRect(x: 0, y: 0, width: 2, height: 2)), agent: true, agentName: "claude"),
            Mark(geometry: .arrow(.init(start: CGPoint(x: 1, y: 1), end: CGPoint(x: 3, y: 3))), agent: true, agentName: "claude"),
        ])
    }

    private let destination = AgentDestination(id: "s", name: "A session", address: .claudeSession("session-1"))

    func testOnlyTheDrawingTheAgentSentCountsAsUnchanged() throws {
        let url = try card()
        let sent = agentDrawing(at: url)
        XCTAssertFalse(Agent.hasSentDrawing(sent, at: url))

        Agent.record(sentDrawing: sent, on: url)
        XCTAssertTrue(Agent.hasSentDrawing(sent, at: url))

        var undone = sent
        undone.marks = sent.marks.map { Mark(geometry: $0.geometry, agent: $0.agent, agentName: $0.agentName) }
        XCTAssertTrue(Agent.hasSentDrawing(undone, at: url))

        var renamed = sent
        renamed.key = folder.appendingPathComponent("Renamed.png").path
        XCTAssertTrue(Agent.hasSentDrawing(renamed, at: url))

        var moved = sent
        moved.marks[0].geometry = .rectangle(CGRect(x: 1, y: 0, width: 2, height: 2))
        XCTAssertFalse(Agent.hasSentDrawing(moved, at: url))

        var removed = sent
        removed.marks.removeLast()
        XCTAssertFalse(Agent.hasSentDrawing(removed, at: url))

        var added = sent
        added.marks.append(Mark(geometry: .ellipse(CGRect(x: 0, y: 2, width: 1, height: 1))))
        XCTAssertFalse(Agent.hasSentDrawing(added, at: url))

        var rescaled = sent
        rescaled.pointScale = 1
        XCTAssertFalse(Agent.hasSentDrawing(rescaled, at: url))

        Agent.forgetSentDrawing(on: url)
        XCTAssertFalse(Agent.hasSentDrawing(sent, at: url))
    }

    func testAPictureEditedInAnotherAppIsAChange() throws {
        let url = try card()
        let sent = agentDrawing(at: url)
        Agent.record(sentDrawing: sent, on: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0]))
        try handle.close()
        XCTAssertFalse(Agent.hasSentDrawing(sent, at: url))
    }

    func testAnImageSentWithoutMarksIsUnchangedUntilAMarkIsDrawn() throws {
        let url = try card()
        Agent.record(sentDrawing: nil, on: url)
        let empty = Drawing(key: url.path, pixels: PixelSize(width: 4, height: 4), pointScale: 2, marks: [])
        XCTAssertTrue(Agent.hasSentDrawing(empty, at: url))
        var drawn = empty
        drawn.marks = [Mark(geometry: .ellipse(CGRect(x: 0, y: 0, width: 2, height: 2)))]
        XCTAssertFalse(Agent.hasSentDrawing(drawn, at: url))
    }

    func testTheFingerprintSurvivesTheDrawingsFile() throws {
        let url = try card()
        let sent = agentDrawing(at: url)
        let store = DrawingStore(directory: base.appendingPathComponent("drawings"), log: { _ in })
        try store.write(sent)
        let read = try XCTUnwrap(store.read(key: url.path, pixels: sent.pixels, style: .standard))
        XCTAssertNotEqual(read.marks.map(\.id), sent.marks.map(\.id))
        Agent.record(sentDrawing: read, on: url)
        XCTAssertTrue(Agent.hasSentDrawing(sent, at: url))
    }

    func testAPushRecordsItsDrawingOnlyWhenItNamesASessionAndTheFileHadNoMarks() throws {
        let sources = base.appendingPathComponent("sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        var stored: [ScreenshotKey: Drawing] = [:]
        let writes = FolderWrites(trash: { $0 }, now: { 10 })
        writes.callbacks = FolderWrites.Callbacks(
            folder: { [unowned self] in self.folder },
            joinMarks: { [unowned self] _, key, done in
                stored[key] = agentDrawing(at: key.url)
                done(.success(Drawings.Joined(marks: 2)))
            },
            storedDrawing: { stored[$0] })
        func push(_ name: String, session: String?, marks: String?) throws -> URL {
            let source = sources.appendingPathComponent(name)
            try png().write(to: source)
            writes.add(CommandRequest(name: "add", files: [source], tag: nil, annotate: false, agent: "claude", session: session,
                                      marks: marks, title: nil, description: nil, root: nil, clear: nil))
            return folder.appendingPathComponent(name)
        }
        let session = UUID().uuidString
        let marks = #"[{"type":"ellipse","x":0.1,"y":0.1,"w":0.2,"h":0.2}]"#

        let withMarks = try push("marks.png", session: session, marks: marks)
        XCTAssertTrue(Agent.hasSentDrawing(agentDrawing(at: withMarks), at: withMarks))

        let bare = try push("bare.png", session: session, marks: nil)
        XCTAssertTrue(Agent.hasSentDrawing(Drawing(key: bare.path, pixels: PixelSize(width: 4, height: 4), pointScale: 2, marks: []), at: bare))

        let noSession = try push("anonymous.png", session: nil, marks: marks)
        XCTAssertFalse(Agent.hasSentDrawing(agentDrawing(at: noSession), at: noSession))

        let personDrew = try card("drawn.png")
        var theirs = agentDrawing(at: personDrew)
        theirs.marks[0].geometry = .rectangle(CGRect(x: 1, y: 1, width: 2, height: 2))
        stored[personDrew.screenshotKey] = theirs
        writes.add(CommandRequest(name: "add", files: [personDrew], tag: nil, annotate: false, agent: "claude", session: session,
                                  marks: nil, title: nil, description: nil, root: nil, clear: nil))
        XCTAssertFalse(Agent.hasSentDrawing(theirs, at: personDrew))
    }

    func testWordsAloneGoOnlyToTheCardsOwnSessionAndOnlyWithTheDrawingAsTheAgentSentIt() throws {
        let url = try card()
        let mine = destination.address, other = AgentAddress.claudeSession("session-2")
        typealias Carried = ScreenshotRequests.Carried
        XCTAssertEqual(Carried.of(card: url, origin: mine, destination: mine, asTheAgentSent: true, message: "Bigger"), .wordsAlone)
        XCTAssertEqual(Carried.of(card: url, origin: mine, destination: mine, asTheAgentSent: true, message: nil), .nothingNew)
        XCTAssertEqual(Carried.of(card: url, origin: mine, destination: mine, asTheAgentSent: false, message: "Bigger"), .drawing)
        XCTAssertEqual(Carried.of(card: url, origin: mine, destination: mine, asTheAgentSent: false, message: nil), .drawing)
        XCTAssertEqual(Carried.of(card: url, origin: mine, destination: other, asTheAgentSent: true, message: "Bigger"), .drawing)
        XCTAssertEqual(Carried.of(card: url, origin: nil, destination: mine, asTheAgentSent: true, message: nil), .drawing)
        let broken = folder.appendingPathComponent("two\nlines.png")
        XCTAssertEqual(Carried.of(card: broken, origin: mine, destination: mine, asTheAgentSent: true, message: "Bigger"), .drawing)

        let sent = agentDrawing(at: url)
        XCTAssertTrue(Carried.wordsAlone.rendering(sent).marks.isEmpty)
        XCTAssertEqual(Carried.drawing.rendering(sent), sent)
    }

    func testWordsOnTheAgentsImageNameItsCardAndTicketAndKeepItsPictureForADrawnAnswer() throws {
        let url = try card()
        let requests = ScreenshotRequests(root: root)
        let record = try requests.send(.unchanged(card: url, title: "Checkout at 390 px", png: nil), source: url.screenshotKey,
                                       to: destination, message: "Make the total bigger")
        XCTAssertEqual(record.unchanged, true)
        let directory = ReplyProtocol.requestDirectory(root: root, requestID: record.id)
        let line = ScreenshotRequests.requestLine(record: record, root: root, message: "Make the total bigger", title: "Checkout at 390 px")
        XCTAssertEqual(line, "Make the total bigger [From Vignette: about your image \"\(url.path)\" (\"Checkout at 390 px\"), unchanged since you sent it. The reply ticket is \"\(directory.path)/ticket.json\". If a drawing would answer better than words, you can send one back.]")
        XCTAssertEqual(ScreenshotRequests.requestLine(record: record, root: root, message: "Bigger", instructions: ""),
                       "Bigger [From Vignette: about your image \"\(url.path)\", unchanged since you sent it. The reply ticket is \"\(directory.path)/ticket.json\".]")
        let secret = try JSONDecoder().decode(ReplyProtocol.Ticket.self, from: Data(contentsOf: directory.appendingPathComponent("ticket.json"))).secret
        XCTAssertFalse(line.contains(secret))
        XCTAssertFalse(line.contains("image.png"))
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)), ["image.png", "ticket.json", "request.json"])
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("image.png")), try Data(contentsOf: url))
    }

    func testWordsOnACardThatIsNotAPNGKeepTheGivenPNG() throws {
        let url = folder.appendingPathComponent("Checkout.jpg")
        try NSBitmapImageRep(data: png())!.representation(using: .jpeg, properties: [:])!.write(to: url)
        XCTAssertFalse(ScreenshotRequests.isPNG(url))
        XCTAssertTrue(ScreenshotRequests.isPNG(try card()))
        let converted = png(8)
        let record = try ScreenshotRequests(root: root).send(.unchanged(card: url, title: nil, png: converted), source: url.screenshotKey,
                                                             to: destination, message: "Bigger")
        let image = ReplyProtocol.requestDirectory(root: root, requestID: record.id).appendingPathComponent("image.png")
        XCTAssertEqual(try Data(contentsOf: image), converted)
    }

    func testADrawingSentAsBeforeIsNotMarkedUnchanged() throws {
        let url = try card()
        let record = try ScreenshotRequests(root: root).send(png: png(), source: url.screenshotKey, to: destination)
        XCTAssertNil(record.unchanged)
        let image = ReplyProtocol.requestDirectory(root: root, requestID: record.id).appendingPathComponent("image.png").path
        XCTAssertTrue(ScreenshotRequests.requestLine(record: record, root: root).hasPrefix("From Vignette: \"\(image)\". "))
    }

    func testAPublishedReplyRecordsTheDrawingItsCardOpensWith() throws {
        let url = try card()
        let requests = ScreenshotRequests(root: root)
        let reply = try publishedReply(to: url, through: requests)
        XCTAssertTrue(Agent.hasSentDrawing(agentDrawing(at: reply), at: reply))
        XCTAssertEqual(requests.origin(of: reply)?.address, destination.address)
    }

    func testASendIsRecordedOnItsScreenshotOnlyOnceItsClientTookIt() async throws {
        let connection = AnsweringConnection()
        let requests = ScreenshotRequests(root: root, connections: [.claude: connection])
        let outcomes: [(SubmissionOutcome, recorded: Bool)] = [
            (.accepted(detail: ""), true), (.queued(detail: "", reason: "queued"), true),
            (.uncertain(detail: "", reason: "uncertain"), false),
            (.notSubmitted(code: .sendFailed, detail: "", reason: "refused"), false),
            (.destinationChanged(detail: "", reason: "changed"), false),
        ]
        for (index, (outcome, recorded)) in outcomes.enumerated() {
            let url = try card("Shot \(index).png")
            connection.outcome = outcome
            try await send(url, through: requests, to: destination, titled: "vignette")
            let sent = Agent.sent(of: url)
            XCTAssertEqual(sent.map { [$0.client.rawValue, $0.id, $0.title] }, recorded ? ["claude", "session-1", "vignette"] : nil, "\(outcome)")
        }

        let url = try card()
        connection.outcome = .accepted(detail: "")
        try await send(url, through: requests, to: destination, titled: "vignette")
        let other = AgentDestination(id: "t", name: "Other", address: .claudeSession("session-2"))
        try await send(url, through: requests, to: other, titled: "release notes")
        XCTAssertEqual(Agent.sent(of: url)?.title, "release notes")
        connection.outcome = .notSubmitted(code: .sendFailed, detail: "", reason: "refused")
        try await send(url, through: requests, to: destination, titled: "vignette")
        XCTAssertEqual(Agent.sent(of: url)?.title, "release notes")

        let unsent = try card("Unsent.png")
        connection.outcome = .accepted(detail: "")
        _ = try requests.send(png: png(), source: unsent.screenshotKey, to: destination, grace: 60, cardTitle: "vignette")
        XCTAssertEqual(requests.unsend(file: unsent.screenshotKey).count, 1)
        XCTAssertNil(Agent.sent(of: unsent))
    }

    func testASendBackToTheSessionAReplyCameFromIsAReplyAndASendElsewhereIsNot() async throws {
        let connection = AnsweringConnection()
        let requests = ScreenshotRequests(root: root, connections: [.claude: connection])
        let url = try card()
        let reply = try publishedReply(to: url, through: requests)
        XCTAssertNil(Agent.origin(of: reply), "a published reply's origin is its request, not its file")

        try await send(url, through: requests, to: destination, titled: "vignette")
        let screenshot = try XCTUnwrap(Agent.sent(of: url))
        XCTAssertEqual(Card.Sent.of(screenshot, agent: Agent.of(url), origin: requests.origin(of: url)), .to(.claude, title: "vignette"))

        try await send(reply, through: requests, to: destination, titled: "vignette")
        let back = try XCTUnwrap(Agent.sent(of: reply))
        XCTAssertEqual(Card.Sent.of(back, agent: Agent.of(reply), origin: requests.origin(of: reply)), .replied)

        let other = AgentDestination(id: "t", name: "Other", address: .claudeSession("session-2"))
        try await send(reply, through: requests, to: other, titled: "release notes")
        let elsewhere = try XCTUnwrap(Agent.sent(of: reply))
        XCTAssertNil(Card.Sent.of(elsewhere, agent: Agent.of(reply), origin: requests.origin(of: reply)))
    }

    func testTheSendFollowsItsFileThroughARenameAndAPushOverItForgetsIt() throws {
        let url = try card()
        let sent = Agent.Sent(client: .codex, id: "thread-1", title: "release notes", at: Date(timeIntervalSinceReferenceDate: 1000))
        Agent.record(sent: sent, on: url)
        let renamed = folder.appendingPathComponent("Renamed.png")
        try FileManager.default.moveItem(at: url, to: renamed)
        XCTAssertEqual(Agent.sent(of: renamed), sent)

        Agent.record(agent: "claude", origin: nil, on: renamed)
        XCTAssertNil(Agent.sent(of: renamed))
    }

    private func send(_ url: URL, through requests: ScreenshotRequests, to destination: AgentDestination, titled title: String) async throws {
        let answered = expectation(description: "the client answered")
        var id = ""
        requests.callbacks.delivered = { record, _ in if record.id == id { answered.fulfill() } }
        id = try requests.send(png: png(), source: url.screenshotKey, to: destination, cardTitle: title).id
        await fulfillment(of: [answered], timeout: 3)
    }

    private func publishedReply(to url: URL, through requests: ScreenshotRequests) throws -> URL {
        var presented: [URL] = []
        var installed: Drawing?
        requests.callbacks = ScreenshotRequests.Callbacks(
            installDrawing: { shot, _, _, _, done in
                installed = self.agentDrawing(at: shot.url)
                done(nil)
            },
            present: { presented.append($0.url) },
            watchFolder: { [unowned self] in self.folder },
            storedDrawing: { _ in installed })
        requests.reconcile(ScreenshotWatcher.Inventory(folder: folder, names: [url.lastPathComponent], dates: [:],
                                                      observedAt: ProcessInfo.processInfo.systemUptime))
        let record = try requests.send(png: png(), source: url.screenshotKey, to: destination)
        let replyID = UUID().uuidString.lowercased(), attemptID = UUID().uuidString.lowercased()
        let submission = ReplyProtocol.submissionDirectory(root: root, requestID: record.id, replyID: replyID)
        try FileManager.default.createDirectory(at: submission, withIntermediateDirectories: true)
        let bundle = Data(#"{"protocolVersion":\#(ReplyProtocol.version),"hasImage":false,"marks":[{"type":"ellipse","x":0.1,"y":0.1,"w":0.2,"h":0.2}],"replyId":"\#(replyID)","requestId":"\#(record.id)"}"#.utf8)
        try bundle.write(to: submission.appendingPathComponent("bundle.json"))
        let secret = try JSONDecoder().decode(ReplyProtocol.Ticket.self, from: Data(contentsOf:
            ReplyProtocol.requestDirectory(root: root, requestID: record.id).appendingPathComponent("ticket.json"))).secret
        let envelope = ReplyProtocol.attemptURL(root: root, requestID: record.id, replyID: replyID, attemptID: attemptID)
        try Data(#"{"protocolVersion":\#(ReplyProtocol.version),"requestId":"\#(record.id)","replyId":"\#(replyID)","attemptId":"\#(attemptID)","payloadDigest":"\#(ReplyProtocol.payloadDigest(bundle: bundle, image: nil))","secret":"\#(secret)"}"#.utf8).write(to: envelope)
        requests.receiveReply(envelope: envelope)
        let reply = try XCTUnwrap(presented.first)
        XCTAssertEqual(reply.lastPathComponent, ReplyProtocol.replyFileName(replyID))
        return reply
    }
}

private final class AnsweringConnection: AgentConnection, @unchecked Sendable {
    let client = AgentClient.claude
    private let lock = NSLock()
    private var answer: SubmissionOutcome = .accepted(detail: "")

    var outcome: SubmissionOutcome {
        get { lock.lock(); defer { lock.unlock() }; return answer }
        set { lock.lock(); answer = newValue; lock.unlock() }
    }

    func destinations() -> [AgentDestination] { [] }
    func submit(_ line: String, to destination: AgentDestination) -> SubmissionOutcome { outcome }
}
