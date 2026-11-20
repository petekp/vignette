import AppKit
import XCTest

@MainActor
final class ScreenshotRequestsHandOverTests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-hand-over-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    private final class Client: AgentConnection, @unchecked Sendable {
        let client = AgentClient.claude
        private let lock = NSLock()
        private var sent: [String] = []
        var lines: [String] { lock.withLock { sent } }
        func destinations() -> [AgentDestination] { [] }
        func submit(_ line: String, to destination: AgentDestination) -> SubmissionOutcome {
            lock.withLock { sent.append(line) }
            return .accepted(detail: "")
        }
    }

    func testASendWhoseRecordCannotBeStoredAsItsLineGoesIsRefusedAndSendsNothing() throws {
        let root = base.appendingPathComponent("requests"), folder = base.appendingPathComponent("shots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let client = Client(), clock = GraceClock()
        let requests = ScreenshotRequests(root: root, connections: [.claude: client], now: { clock.time },
                                          schedule: { _, work in clock.timers.append(work) })
        var delivered: [SubmissionOutcome] = []
        requests.callbacks = ScreenshotRequests.Callbacks(installDrawing: { _, _, _, _, done in done(nil) }, present: { _ in },
                                                          watchFolder: { folder }, replyFailed: { _, _ in })
        requests.callbacks.delivered = { _, outcome in delivered.append(outcome) }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let source = folder.appendingPathComponent("Shot.png")
        try png.write(to: source)
        requests.reconcile(ScreenshotWatcher.Inventory(folder: folder, names: ["Shot.png"], dates: [:], observedAt: ProcessInfo.processInfo.systemUptime))
        let record = try requests.send(png: png, source: source.screenshotKey,
                                       to: AgentDestination(id: "s", name: "A session", address: .claudeSession("session-1")), grace: 3)
        let directory = ReplyProtocol.requestDirectory(root: root, requestID: record.id)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }

        clock.time += 3
        clock.fire()
        let deadline = Date().addingTimeInterval(1)
        while delivered.isEmpty, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }

        guard case .notSubmitted(.writeFailed, _, let reason)? = delivered.first else { return XCTFail("\(delivered)") }
        XCTAssertTrue(reason.hasPrefix("Vignette couldn't save the request."), reason)
        XCTAssertEqual(client.lines, [])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let stored = try decoder.decode(ScreenshotRequests.Record.self,
                                        from: Data(contentsOf: directory.appendingPathComponent(ScreenshotRequests.recordFileName)))
        XCTAssertEqual(stored.status, .prepared)
    }
}
