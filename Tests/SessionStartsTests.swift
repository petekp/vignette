import XCTest

@MainActor
final class SessionStartsTests: XCTestCase {
    private let past = "a1b2c3d4-0000-4000-8000-000000000001"
    private let older = "a1b2c3d4-0000-4000-8000-000000000002"

    private func temporaryFolder(_ name: String = "starts") -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func historyLine(_ folder: String, _ session: String, _ time: Date) -> String {
        #"{"display":"hi","pastedContents":{},"timestamp":\#(Int(time.timeIntervalSince1970 * 1000)),"project":"\#(folder)","sessionId":"\#(session)"}"#
    }

    private func transcriptName(_ folder: String) -> String {
        String(folder.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? Character($0) : "-" })
    }

    private func writeTranscript(_ root: URL, folder: String, session: String, title: String, used: Date) throws {
        let dir = root.appendingPathComponent(transcriptName(folder))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(used)
        let text = """
        {"type":"ai-title","aiTitle":"\(title)","sessionId":"\(session)"}
        {"type":"user","timestamp":"\(stamp)","cwd":"\(folder)","message":{"role":"user","content":"hi"}}

        """
        try Data(text.utf8).write(to: dir.appendingPathComponent("\(session).jsonl"))
    }

    private func sessions(home: URL, running: [String] = [], now: Date, canStart: Bool = true) -> StartableSessions {
        var sessions = StartableSessions()
        sessions.history = home.appendingPathComponent("history.jsonl")
        sessions.transcripts = home.appendingPathComponent("projects")
        sessions.running = { running }
        sessions.canStart = { canStart }
        sessions.now = { now }
        sessions.home = home.path
        return sessions
    }

    func testAProjectWithNoRunningSessionOffersItsLastSessionAndANewOne() throws {
        let home = temporaryFolder()
        let site = temporaryFolder("pete-2025").path, busy = temporaryFolder("vignette").path
        let gone = home.appendingPathComponent("deleted-worktree").path
        let now = Date()
        let lines = [
            historyLine(site, older, now.addingTimeInterval(-3 * 86400)),
            historyLine(site, past, now.addingTimeInterval(-2 * 86400)),
            historyLine(busy, older, now.addingTimeInterval(-3600)),
            historyLine(gone, older, now.addingTimeInterval(-60)),
        ]
        try Data(lines.joined(separator: "\n").utf8).write(to: home.appendingPathComponent("history.jsonl"))
        let projects = home.appendingPathComponent("projects")
        try writeTranscript(projects, folder: site, session: past, title: "Nav spacing", used: now.addingTimeInterval(-2 * 86400))
        try writeTranscript(projects, folder: site, session: older, title: "Carousel", used: now.addingTimeInterval(-1 * 86400))

        let found = sessions(home: home, running: [StartableSessions.canonical(busy)], now: now).destinations()

        XCTAssertEqual(found.map(\.id), [older, SessionStart.newRowID(folder: site)])
        XCTAssertEqual(found[0].start, .resume(folder: site))
        XCTAssertEqual(found[0].name, "Carousel")
        XCTAssertEqual(found[0].address, .claudeSession(older))
        XCTAssertEqual(found[1].start, .new(folder: site))
        XCTAssertEqual(found[1].lastUsed, found[0].lastUsed)
        XCTAssertTrue(found.allSatisfy { $0.isActive() && $0.startsProcess })
    }

    func testNothingIsOfferedWithoutALauncherOrPastTheWindow() throws {
        let home = temporaryFolder()
        let site = temporaryFolder("site").path
        let now = Date()
        try Data(historyLine(site, past, now.addingTimeInterval(-15 * 86400)).utf8).write(to: home.appendingPathComponent("history.jsonl"))
        XCTAssertEqual(sessions(home: home, now: now).destinations(), [])
        try Data(historyLine(site, past, now).utf8).write(to: home.appendingPathComponent("history.jsonl"))
        XCTAssertEqual(sessions(home: home, now: now, canStart: false).destinations(), [])
        XCTAssertEqual(sessions(home: home, now: now).destinations().map(\.start), [.new(folder: site)])
    }

    func testANewSessionIsAddressedByAnIdChosenAtSend() {
        let row = StartableSessions.rows(folder: "/Users/p/Code/site", last: nil, lastUsed: Date(), found: .init(place: .none, branch: nil))[0]
        let sent = row.addressed(id: past)
        XCTAssertEqual(sent.id, past)
        XCTAssertEqual(sent.address, .claudeSession(past))
        XCTAssertEqual(sent.start, .new(folder: "/Users/p/Code/site"))
        XCTAssertEqual(sent.start?.arguments(session: past), ["--session-id", past])
        let resume = AgentDestination(id: older, name: "x", address: .claudeSession(older), start: .resume(folder: "/f"))
        XCTAssertEqual(resume.addressed(id: past), resume)
        XCTAssertEqual(resume.start?.arguments(session: older), ["--resume", older])
    }

    private func claude(_ id: String, used: TimeInterval = 0, start: SessionStart? = nil) -> AgentDestination {
        AgentDestination(id: id, name: id, detail: "site", address: .claudeSession(id), lastUsed: Date(timeIntervalSince1970: used), start: start)
    }

    func testNothingStartsASessionOnItsOwn() {
        let resume = claude(past, used: 200, start: .resume(folder: "/site"))
        let new = claude("new:/site", used: 200, start: .new(folder: "/site"))
        let running = claude("r", used: 100)
        func send(_ list: [AgentDestination]) -> DestinationChoice.Answer {
            DestinationChoice.choose(.init(destinations: list, complete: true, fresh: true), for: .send(cameFrom: nil))
        }
        XCTAssertNil(send([resume, new]).pick)
        XCTAssertEqual(send([resume, new, running]).pick?.id, "r")
        func note(_ list: [AgentDestination], _ pick: DestinationChoice.LiveNotePick) -> AgentDestination? {
            DestinationChoice.choose(.init(destinations: list, complete: true, fresh: true), for: .liveNote(pick)).pick
        }
        XCTAssertNil(note([resume, new], .remembered(claude(past))))
        XCTAssertNil(note([resume, new], .remembered(claude("cleared"))))
        XCTAssertEqual(note([resume, new], .byHand(resume)), resume)
        XCTAssertEqual(ToolbarOffer(replyTo: nil, destinations: [resume, new], listed: true, target: nil), .choose)
        XCTAssertEqual(ToolbarOffer.choose.finishes, ToolbarOffer.copy.finishes)
        XCTAssertEqual(ToolbarOffer(replyTo: claude(past), destinations: [resume, new], listed: true, target: nil), .choose)
    }

    func testRowsThatStartASessionComeAfterEveryRunningOne() {
        let now = Date()
        let resume = claude(past, used: now.timeIntervalSince1970, start: .resume(folder: "/site"))
        let new = claude("new:/site", used: now.timeIntervalSince1970, start: .new(folder: "/site"))
        var running = claude("r", used: now.timeIntervalSince1970 - 86000)
        running.lastSent = nil
        let ranked = SessionMenu.ranked([new, running, resume], now: now)
        XCTAssertEqual(ranked.map(\.id), ["r", past, "new:/site"])
        let rows = SessionMenu.menu([new, running, resume], destination: nil, now: now).topRows
        XCTAssertEqual(rows.map(\.title), ["r", SessionMenu.continueLast, SessionMenu.newSession])
        XCTAssertTrue(rows[1].subtitle.contains(past), rows[1].subtitle)
    }

    private nonisolated static func inbox(_ root: URL, pid: Int32, session: String) throws {
        let folder = root.appendingPathComponent("\(pid)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("\(session)\n".utf8).write(to: folder.appendingPathComponent("session"))
        try Data().write(to: folder.appendingPathComponent("alive"))
    }

    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var time = Date()
        private(set) var launches: [(SessionStart, String, String)] = []
        var now: Date { lock.withLock { time } }
        func advance(_ seconds: TimeInterval) { lock.withLock { time = time.addingTimeInterval(seconds) } }
        func launched(_ start: SessionStart, _ session: String, _ label: String) { lock.withLock { launches.append((start, session, label)) } }
    }

    private func connection(_ root: URL, clock: Clock, launch: @escaping @Sendable (SessionStart, String, String) -> HerdrLauncher.Started) -> ClaudeCodeConnection {
        var connection = ClaudeCodeConnection()
        connection.inboxes = root
        connection.transcripts = URL(fileURLWithPath: "/nonexistent/projects")
        connection.isRunning = { _ in true }
        connection.now = { clock.now }
        connection.pause = { clock.advance($0) }
        connection.launch = { clock.launched($0, $1, $2); return launch($0, $1, $2) }
        return connection
    }

    private func lines(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".line") }
    }

    func testASendToASessionThatIsNotRunningStartsItThenWritesTheLineIntoItsInbox() throws {
        let root = temporaryFolder()
        let clock = Clock()
        let up = connection(root, clock: clock) { _, session, _ in
            try? Self.inbox(root, pid: 301, session: session)
            return .started(tab: "w1:t9", pane: "w1:p9")
        }
        let destination = AgentDestination(id: past, name: "x", detail: "site", address: .claudeSession(past), start: .resume(folder: "/site"))
        guard case .accepted(let detail) = up.submit("From Vignette: look", to: destination) else { return XCTFail("started and delivered") }
        XCTAssertTrue(detail.contains("inbox=301"), detail)
        XCTAssertEqual(clock.launches.map { $0.1 }, [past])
        XCTAssertEqual(clock.launches.map { $0.2 }, ["site"])
        XCTAssertEqual(lines(in: root.appendingPathComponent("301")).count, 1)

        XCTAssertTrue(up.submit("again", to: destination).isAccepted)
        XCTAssertEqual(clock.launches.count, 1)
    }

    func testAStartThatFailsOrNeverComesUpSendsNothing() throws {
        let root = temporaryFolder()
        let clock = Clock()
        let destination = AgentDestination(id: past, name: "x", address: .claudeSession(past), start: .new(folder: "/site"))
        let refused = connection(root, clock: clock) { _, _, _ in .failed(detail: "no tab") }
        guard case .notSubmitted(_, _, let reason) = refused.submit("x", to: destination) else { return XCTFail("a failed start sends nothing") }
        XCTAssertEqual(reason, ClaudeCodeConnection.notStarted)

        let silent = connection(root, clock: clock) { _, _, _ in .started(tab: "t", pane: "p") }
        let began = clock.now
        guard case .notSubmitted(_, _, let late) = silent.submit("x", to: destination) else { return XCTFail("a session that never came up got nothing") }
        XCTAssertEqual(late, ClaudeCodeConnection.notUpInTime)
        XCTAssertGreaterThanOrEqual(clock.now.timeIntervalSince(began), ClaudeCodeConnection.startTimeout)

        let notASession = AgentDestination(id: "new:/site", name: "x", address: .claudeSession("new:/site"), start: .new(folder: "/site"))
        XCTAssertFalse(silent.submit("x", to: notASession).isAccepted)
        XCTAssertEqual(clock.launches.count, 2)
    }

    func testHerdrOpensATabInTheFolderAndTypesTheCommandIntoItsShell() {
        final class Calls: @unchecked Sendable { var all: [[String]] = []; let lock = NSLock() }
        let calls = Calls()
        var launcher = HerdrLauncher()
        launcher.binary = { "/fake/herdr" }
        launcher.run = { _, arguments, _ in
            calls.lock.withLock { calls.all.append(arguments) }
            if arguments.first == "tab" {
                return (0, #"{"id":"cli:tab:create","result":{"tab":{"tab_id":"w1:t4","label":"site"},"root_pane":{"pane_id":"w1:p7"}}}"#, false)
            }
            return (0, "", false)
        }
        XCTAssertEqual(launcher.start(.resume(folder: "/Users/p/it's here"), session: past, label: "site"), .started(tab: "w1:t4", pane: "w1:p7"))
        XCTAssertEqual(calls.all, [
            ["tab", "create", "--cwd", "/Users/p/it's here", "--no-focus", "--label", "site"],
            ["pane", "run", "w1:p7", "'claude' '--resume' '\(past)'"],
        ])
        XCTAssertEqual(HerdrLauncher.shellCommand(["it's"]), #"'it'\''s'"#)
        launcher.run = { _, _, _ in (1, #"{"error":"no server"}"#, false) }
        guard case .failed(let detail) = launcher.start(.new(folder: "/f"), session: past, label: "") else { return XCTFail("herdr refused") }
        XCTAssertTrue(detail.contains("no server"), detail)
    }
}
