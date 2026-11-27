import AppKit
import XCTest

@MainActor
final class SentRecordTests: XCTestCase {
    private var base: URL!
    private var folder: URL!
    private var root: URL!

    override func setUp() async throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-sent-record-\(UUID().uuidString)")
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
            installDrawing: { shot, _, _, _, _, done in
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
