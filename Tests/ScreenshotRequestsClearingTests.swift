import AppKit
import XCTest

@MainActor
final class ScreenshotRequestsClearingTests: XCTestCase {
    private var root: URL!
    private var folder: URL!
    private var requests: ScreenshotRequests!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-clearing-\(UUID().uuidString)")
        root = base.appendingPathComponent("requests")
        folder = base.appendingPathComponent("shots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        requests = ScreenshotRequests(root: root)
        requests.callbacks = ScreenshotRequests.Callbacks(
            installDrawing: { _, _, _, _, done in done(nil) },
            present: { _ in },
            watchFolder: { [unowned self] in self.folder },
            replyFailed: { _, _ in })
        requests.callbacks.presentLive = { _, _, done in done([]) }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private func makeRequest() throws -> ScreenshotRequests.Record {
        requests.reconcile(ScreenshotWatcher.Inventory(folder: folder, names: [], dates: [:], observedAt: ProcessInfo.processInfo.systemUptime))
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return try requests.send(png: rep.representation(using: .png, properties: [:])!,
                                 source: folder.appendingPathComponent("Screenshot.png").screenshotKey,
                                 to: AgentDestination(id: "s", name: "A session", address: .claudeSession("session-1")))
    }

    private func stageAnswer(to record: ScreenshotRequests.Record) throws -> URL {
        let replyID = UUID().uuidString.lowercased(), attemptID = UUID().uuidString.lowercased()
        let directory = ReplyProtocol.submissionDirectory(root: root, requestID: record.id, replyID: replyID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let answer = #"{"say":"The dates moved.","marks":[{"kind":"arrow","box":[0.1,0.2,0.3,0.1]}]}"#
        let bundle = Data(#"{"protocolVersion":\#(ReplyProtocol.version),"hasImage":false,"marks":[],"answer":\#(answer),"replyId":"\#(replyID)","requestId":"\#(record.id)"}"#.utf8)
        try bundle.write(to: directory.appendingPathComponent("bundle.json"))
        let ticketFile = ReplyProtocol.requestDirectory(root: root, requestID: record.id).appendingPathComponent("ticket.json")
        let secret = try JSONDecoder().decode(ReplyProtocol.Ticket.self, from: Data(contentsOf: ticketFile)).secret
        let digest = ReplyProtocol.payloadDigest(bundle: bundle, image: nil)
        let url = ReplyProtocol.attemptURL(root: root, requestID: record.id, replyID: replyID, attemptID: attemptID)
        try Data(#"{"protocolVersion":\#(ReplyProtocol.version),"requestId":"\#(record.id)","replyId":"\#(replyID)","attemptId":"\#(attemptID)","payloadDigest":"\#(digest)","secret":"\#(secret)"}"#.utf8).write(to: url)
        return url
    }

    private func stage(of record: ScreenshotRequests.Record) -> String? {
        let replies = (requests.stateJSON["replies"] as? [[String: Any]]) ?? []
        return replies.first { $0["request"] as? String == record.id }?["stage"] as? String
    }

    func testAClearedRequestWhoseAnswerLiveInkDrewStaysDrawnAndIsPrunedAfterAWeek() throws {
        let record = try makeRequest()
        try requests.receiveReply(envelope: stageAnswer(to: record))
        XCTAssertEqual(stage(of: record), "shown")
        requests.run(clear: record.id)
        XCTAssertEqual(stage(of: record), "shown")
        requests.prune(now: Date().addingTimeInterval(ScreenshotRequests.clearedKept + 60))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ReplyProtocol.requestDirectory(root: root, requestID: record.id).path))
    }
}
