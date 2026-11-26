import AppKit
import XCTest

@MainActor
final class ScreenshotRequestsPinsTests: XCTestCase {
    private var root: URL!
    private var folder: URL!
    private var requests: ScreenshotRequests!
    private var installed: [[Pin]] = []
    private var presented: [URL] = []

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-reply-pins-\(UUID().uuidString)")
        root = base.appendingPathComponent("requests")
        folder = base.appendingPathComponent("shots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        requests = ScreenshotRequests(root: root)
        requests.callbacks = ScreenshotRequests.Callbacks(
            installDrawing: { [unowned self] _, _, pins, _, _, done in
                self.installed.append(pins)
                done(nil)
            },
            present: { [unowned self] shot in self.presented.append(shot.url) },
            watchFolder: { [unowned self] in self.folder })
        requests.reconcile(ScreenshotWatcher.Inventory(folder: folder, names: [], dates: [:], observedAt: ProcessInfo.processInfo.systemUptime))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private func png(_ white: CGFloat) throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 30, bitsPerSample: 8, samplesPerPixel: 4,
                                                 hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.setColor(NSColor(white: white, alpha: 1), atX: 0, y: 0)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    private let pins = [
        Pin(id: UUID(), number: 1, place: .point(CGPoint(x: 10, y: 10)), comments: [Pin.Comment(text: "Too tight")]),
        Pin(id: UUID(), number: 2, place: .area(CGRect(x: 5, y: 5, width: 20, height: 10), tip: .bottomRight),
            comments: [Pin.Comment(text: "Wrong date")]),
    ]

    private func send(base: Data) throws -> ReplyProtocol.Ticket {
        let record = try requests.send(.drawing(png: try png(0), pins: pins, base: base),
                                       source: folder.appendingPathComponent("Screenshot.png").screenshotKey,
                                       to: AgentDestination(id: "s", name: "A session", address: .claudeSession("session-1")))
        let directory = ReplyProtocol.requestDirectory(root: root, requestID: record.id)
        return try ReplyCommand.loadTicket(directory.appendingPathComponent("ticket.json").path)
    }

    private func reply(_ ticket: ReplyProtocol.Ticket, comments: [ReplyProtocol.Comment], image: Data? = nil) throws -> ReplyProtocol.Receipt {
        let prepared = try ReplyCommand.prepare(ticket: ticket, marks: [], image: image, comments: comments)
        let attempt = try ReplyCommand.writeAttempt(ticket: ticket, prepared: prepared)
        requests.receiveReply(envelope: attempt.envelope)
        let url = ReplyProtocol.receiptURL(root: root, requestID: ticket.requestID, attemptID: attempt.id)
        return try JSONDecoder().decode(ReplyProtocol.Receipt.self, from: Data(contentsOf: url))
    }

    func testAnAnswerByNumberJoinsThePersonsPinsOnTheirPictureWithoutNumbers() throws {
        let base = try png(1)
        let ticket = try send(base: base)
        let comments = try ReplyCommand.loadComments(#"{"2": "Moved the date under the title"}"#, ticket: ticket)
        XCTAssertEqual(comments, [ReplyProtocol.Comment(pin: pins[1].id, text: "Moved the date under the title")])

        XCTAssertEqual(try reply(ticket, comments: comments).acceptance, .accepted)
        let card = try XCTUnwrap(presented.first)
        XCTAssertEqual(try Data(contentsOf: card), base)
        let cardPins = try XCTUnwrap(installed.first)
        XCTAssertEqual(cardPins.map(\.id), pins.map(\.id))
        XCTAssertEqual(cardPins[0].comments, pins[0].comments)
        XCTAssertEqual(cardPins[1].comments.map(\.text), ["Wrong date", "Moved the date under the title"])
        XCTAssertEqual(cardPins[1].comments.last?.agentName, "claude")
        XCTAssertNotNil(cardPins[1].comments.last?.at)
    }

    func testAnswersOnAPinTheRequestDidNotSendOrWithTheAgentsOwnImageAreRefused() throws {
        let ticket = try send(base: try png(1))
        XCTAssertThrowsError(try ReplyCommand.loadComments(#"{"3": "Done"}"#, ticket: ticket))

        let stranger = try reply(ticket, comments: [ReplyProtocol.Comment(pin: UUID(), text: "Done")])
        XCTAssertEqual(stranger.acceptance, .rejected)
        XCTAssertEqual(stranger.errorCode, ReplyProtocol.Refusal.badPayload.rawValue)

        let withImage = try reply(ticket, comments: [ReplyProtocol.Comment(pin: pins[0].id, text: "Done")], image: try png(0.5))
        XCTAssertEqual(withImage.errorCode, ReplyProtocol.Refusal.badPayload.rawValue)
        XCTAssertTrue(presented.isEmpty)
    }
}
