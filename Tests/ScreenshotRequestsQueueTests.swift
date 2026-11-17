import AppKit
import XCTest

@MainActor
final class ScreenshotRequestsQueueTests: XCTestCase {
    private var root: URL!
    private var folder: URL!
    private var requests: ScreenshotRequests!
    private let line = QueuedLine(id: "q1", thread: "t")

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-queue-\(UUID().uuidString)")
        root = base.appendingPathComponent("requests")
        folder = base.appendingPathComponent("shots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private func stored(_ record: ScreenshotRequests.Record) throws -> ScreenshotRequests.Record {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = ReplyProtocol.requestDirectory(root: root, requestID: record.id).appendingPathComponent(ScreenshotRequests.recordFileName)
        return try decoder.decode(ScreenshotRequests.Record.self, from: Data(contentsOf: file))
    }

    private func queue(_ outcome: SubmissionOutcome, events: GraceEvents) async throws
        -> (record: ScreenshotRequests.Record, source: URL, connection: QueueConnection, clock: GraceClock, answers: Answers) {
        let connection = QueueConnection(events: events)
        connection.outcome = outcome
        let clock = GraceClock()
        requests = ScreenshotRequests(root: root, connections: [.claude: connection], now: { clock.time },
                                      schedule: { _, work in clock.timers.append(work) })
        let answers = Answers()
        requests.callbacks.watchFolder = { [unowned self] in self.folder }
        requests.callbacks.delivered = { _, outcome in answers.add(outcome) }
        requests.callbacks.withdrawing = { _ in events.add("withdrawing") }
        requests.callbacks.queueChanged = { _ in events.add("queue changed") }
        requests.callbacks.laterAnswer = { _, state, reason in events.add("later \(state) \(reason)") }
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        requests.reconcile(ScreenshotWatcher.Inventory(folder: folder, names: Set(files.map(\.lastPathComponent)), dates: [:],
                                                       observedAt: ProcessInfo.processInfo.systemUptime))
        let source = folder.appendingPathComponent("Shot-\(UUID().uuidString).png")
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = rep.representation(using: .png, properties: [:])!
        try png.write(to: source)
        let record = try requests.send(png: png, source: source.screenshotKey,
                                       to: AgentDestination(id: "s", name: "A session", address: .claudeSession("session-1")), grace: 0)
        try await answers.wait(for: 1)
        return (record, source, connection, clock, answers)
    }

    private func look(_ clock: GraceClock, after seconds: TimeInterval, events: GraceEvents) async {
        let before = events.all.count
        clock.time += seconds
        clock.fire()
        for _ in 0..<300 where events.all.count == before { try? await Task.sleep(nanoseconds: 10_000_000) }
        await Task.yield()
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    func testAQueuedLineSaysEachNewReasonThenSentWhenTheSessionTakesIt() async throws {
        let events = GraceEvents()
        let queued = SubmissionOutcome.queued(detail: "", reason: QueuedLine.Hold.turnRunning.reason, line: line)
        let (record, _, connection, clock, answers) = try await queue(queued, events: events)
        XCTAssertEqual(requests.queued(record.id), QueuedLine.Hold.turnRunning.reason)
        XCTAssertEqual(try stored(record).status, .submitted)
        XCTAssertEqual(clock.timers.count, 1)

        await look(clock, after: 3, events: events)
        XCTAssertFalse(events.all.contains("queue changed"), "the same reason is not said again")
        connection.state = .held(.question)
        await look(clock, after: 3, events: events)
        try await events.wait(for: "queue changed")
        XCTAssertEqual(requests.queued(record.id), QueuedLine.Hold.question.reason)

        connection.state = .taken
        await look(clock, after: 3, events: events)
        XCTAssertEqual(events.all.filter { $0 == "queue changed" }.count, 2)
        XCTAssertNil(requests.queued(record.id))
        XCTAssertEqual(answers.count, 1, "the tab changes; no notice is posted")
        XCTAssertTrue(clock.timers.isEmpty, "a taken line is not looked at again")
        XCTAssertEqual(events.all.filter { $0 == "look q1" }.count, 3)
    }

    func testAnIdleSessionsLineStaysSentUnlessItWaitsPastTheEnginesLook() async throws {
        let events = GraceEvents()
        let (record, _, connection, clock, answers) = try await queue(.accepted(detail: "", line: line), events: events)
        XCTAssertNil(requests.queued(record.id))
        connection.state = .held(.nothing)
        for _ in 0..<4 { await look(clock, after: 3, events: events) }
        XCTAssertNil(requests.queued(record.id))
        await look(clock, after: 3, events: events)
        try await events.wait(for: "queue changed")
        XCTAssertEqual(requests.queued(record.id), QueuedLine.Hold.nothing.reason)
        XCTAssertEqual(answers.count, 1)

        let quietEvents = GraceEvents()
        let quiet = try await queue(.accepted(detail: "", line: QueuedLine(id: "q2", thread: "t")), events: quietEvents)
        quiet.connection.state = .taken
        await look(quiet.clock, after: 3, events: quietEvents)
        XCTAssertFalse(quietEvents.all.contains("queue changed"), "a tab that said Sent stays as it is when the line is taken")
    }

    func testAThreadThatIsGoneFailsTheSend() async throws {
        let events = GraceEvents()
        let (record, _, connection, clock, answers) = try await queue(.queued(detail: "", reason: "r", line: line), events: events)
        connection.state = .threadGone(detail: "thread not found")
        await look(clock, after: 3, events: events)
        try await events.wait(for: "later failed Codex can't find this thread. You can send it to another one.")
        XCTAssertEqual(answers.count, 1)
        XCTAssertEqual(try stored(record).status, .failed)
        XCTAssertNil(requests.queued(record.id))
    }

    func testDontSendTakesAQueuedLineOutAndClearsItsRequest() async throws {
        let events = GraceEvents()
        let (record, source, _, _, _) = try await queue(.queued(detail: "", reason: "r", line: line), events: events)
        XCTAssertEqual(Agent.sent(of: source)?.address, record.address)
        XCTAssertEqual(requests.unsend(file: source.screenshotKey).map(\.id), [record.id])
        XCTAssertTrue(requests.unsend(file: source.screenshotKey).isEmpty, "a line already going is not taken twice")
        try await events.wait(for: "queue changed")
        XCTAssertEqual(events.all.suffix(3), ["withdrawing", "withdraw q1", "queue changed"])
        XCTAssertEqual(try stored(record).status, .cleared)
        XCTAssertNil(requests.queued(record.id))
        XCTAssertNil(Agent.sent(of: source), "the card's tab no longer says it was sent")
    }

    func testDontSendOnALineTheSessionAlreadyTookOrCouldNotRemoveKeepsTheRequest() async throws {
        let events = GraceEvents()
        let first = try await queue(.queued(detail: "", reason: "r", line: line), events: events)
        first.connection.withdrawn = .alreadyTaken
        requests.unsend(file: first.source.screenshotKey)
        try await events.wait(for: "later sent Codex had already started on it.")
        XCTAssertEqual(try stored(first.record).status, .submitted)
        XCTAssertNil(requests.queued(first.record.id))

        let second = try await queue(.queued(detail: "", reason: "r", line: QueuedLine(id: "q2", thread: "t")), events: events)
        second.connection.withdrawn = .failed(detail: "locked")
        requests.unsend(file: second.source.screenshotKey)
        try await events.wait(for: "later queued Vignette couldn't remove it. You can delete it in Codex.")
        XCTAssertEqual(try stored(second.record).status, .submitted)
        XCTAssertEqual(requests.queued(second.record.id), "r", "the line is still watched")
        XCTAssertFalse(second.clock.timers.isEmpty)
    }

    func testALineRemovedInTheSessionsAppClearsTheRequest() async throws {
        let events = GraceEvents()
        let (record, source, connection, clock, answers) = try await queue(.queued(detail: "", reason: "r", line: line), events: events)
        connection.state = .removed
        await look(clock, after: 3, events: events)
        try await events.wait(for: "queue changed")
        XCTAssertEqual(try stored(record).status, .cleared)
        XCTAssertNil(requests.queued(record.id))
        XCTAssertNil(Agent.sent(of: source))
        XCTAssertEqual(answers.count, 1)
    }

    func testAClearEndsTheWatch() async throws {
        let events = GraceEvents()
        let (record, _, _, clock, answers) = try await queue(.queued(detail: "", reason: "r", line: line), events: events)
        requests.run(clear: record.id)
        XCTAssertNil(requests.queued(record.id))
        await look(clock, after: 3, events: events)
        XCTAssertFalse(events.all.contains("look q1"))
        XCTAssertEqual(answers.count, 1)
    }
}

final class Answers: @unchecked Sendable {
    private let lock = NSLock()
    private var outcomes: [SubmissionOutcome] = []
    func add(_ outcome: SubmissionOutcome) { lock.lock(); outcomes.append(outcome); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return outcomes.count }
    var last: SubmissionOutcome? { lock.lock(); defer { lock.unlock() }; return outcomes.last }

    func wait(for count: Int) async throws {
        for _ in 0..<300 where self.count < count { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertGreaterThanOrEqual(self.count, count, "no answer arrived")
    }
}

extension GraceEvents {
    func wait(for event: String) async throws {
        for _ in 0..<300 where !all.contains(event) { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(all.contains(event), "\(event) never happened: \(all)")
    }
}

final class QueueConnection: AgentConnection, @unchecked Sendable {
    let client = AgentClient.claude
    private let events: GraceEvents
    private let lock = NSLock()
    private var answer: SubmissionOutcome = .accepted(detail: "")
    private var queueState: QueuedLine.State = .held(.turnRunning)
    private var withdrawal: QueuedLine.Withdrawal = .removed

    init(events: GraceEvents) { self.events = events }

    var outcome: SubmissionOutcome {
        get { lock.lock(); defer { lock.unlock() }; return answer }
        set { lock.lock(); answer = newValue; lock.unlock() }
    }

    var state: QueuedLine.State {
        get { lock.lock(); defer { lock.unlock() }; return queueState }
        set { lock.lock(); queueState = newValue; lock.unlock() }
    }

    var withdrawn: QueuedLine.Withdrawal {
        get { lock.lock(); defer { lock.unlock() }; return withdrawal }
        set { lock.lock(); withdrawal = newValue; lock.unlock() }
    }

    func destinations() -> [AgentDestination] { [] }

    func submit(_ line: String, to destination: AgentDestination) -> SubmissionOutcome {
        events.add("submit")
        return outcome
    }

    func look(at line: QueuedLine, carrying text: String?) -> QueuedLine.State? {
        events.add("look \(line.id)")
        return state
    }

    func withdraw(_ line: QueuedLine) -> QueuedLine.Withdrawal {
        events.add("withdraw \(line.id)")
        return withdrawn
    }
}
