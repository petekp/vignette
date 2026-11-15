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

    private func writeTranscript(_ root: URL, folder: String, session: String, title: String, used: Date) throws {
        let dir = root.appendingPathComponent(StartableSessions.transcriptFolder(of: folder))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(used)
        let text = """
        {"type":"ai-title","aiTitle":"\(title)","sessionId":"\(session)"}
        {"type":"user","timestamp":"\(stamp)","cwd":"\(folder)","message":{"role":"user","content":"hi"}}

        """
        try Data(text.utf8).write(to: dir.appendingPathComponent("\(session).jsonl"))
    }

    private func sessions(home: URL, now: Date, canStart: Bool = true) -> StartableSessions {
        var sessions = StartableSessions()
        sessions.history = home.appendingPathComponent("history.jsonl")
        sessions.transcripts = home.appendingPathComponent("projects")
        sessions.canStart = { canStart }
        sessions.now = { now }
        sessions.home = home.path
        return sessions
    }

    func testAProjectUsedLatelyOffersItsLastSessionAndANewOne() throws {
        let home = temporaryFolder()
        let site = temporaryFolder("pete-2025").path, other = temporaryFolder("vignette").path
        let gone = home.appendingPathComponent("deleted-worktree").path
        let now = Date()
        let lines = [
            historyLine(site, older, now.addingTimeInterval(-3 * 86400)),
            historyLine(site, past, now.addingTimeInterval(-2 * 86400)),
            historyLine(other, older, now.addingTimeInterval(-3600)),
            historyLine(gone, older, now.addingTimeInterval(-60)),
        ]
        try Data(lines.joined(separator: "\n").utf8).write(to: home.appendingPathComponent("history.jsonl"))
        let projects = home.appendingPathComponent("projects")
        try writeTranscript(projects, folder: site, session: past, title: "Nav spacing", used: now.addingTimeInterval(-2 * 86400))
        try writeTranscript(projects, folder: site, session: older, title: "Carousel", used: now.addingTimeInterval(-1 * 86400))

        let found = sessions(home: home, now: now).destinations()

        XCTAssertEqual(found.map(\.id), [SessionStart.newRowID(folder: other), older, SessionStart.newRowID(folder: site)])
        XCTAssertEqual(found[1].start, .resume(folder: site))
        XCTAssertEqual(found[1].name, "Carousel")
        XCTAssertEqual(found[1].address, .claudeSession(older))
        XCTAssertEqual(found[1].folder, site)
        XCTAssertEqual(found[2].start, .new(folder: site))
        XCTAssertEqual(found[2].lastUsed, found[1].lastUsed)
    }

    func testNothingIsOfferedWithoutALauncherOrPastTheWindow() throws {
        let home = temporaryFolder()
        let site = temporaryFolder("site").path
        let now = Date()
        try Data(historyLine(site, past, now.addingTimeInterval(-15 * 86400)).utf8).write(to: home.appendingPathComponent("history.jsonl"))
        XCTAssertEqual(sessions(home: home, now: now).destinations(), [])
        try Data((historyLine(site, past, now) + "\n").utf8).write(to: home.appendingPathComponent("history.jsonl"))
        XCTAssertEqual(sessions(home: home, now: now, canStart: false).destinations(), [])
        XCTAssertEqual(sessions(home: home, now: now).destinations().map(\.start), [.new(folder: site)])
    }

    private func claude(_ id: String, used: TimeInterval = 0, start: SessionStart? = nil) -> AgentDestination {
        AgentDestination(id: id, name: id, detail: "site", address: .claudeSession(id), lastUsed: Date(timeIntervalSince1970: used), start: start)
    }

    func testOnlyAPersonsPickStartsASession() {
        let resume = claude(past, used: 200, start: .resume(folder: "/site"))
        let new = claude("new:/site", used: 200, start: .new(folder: "/site"))
        let running = claude("r", used: 100)
        func choose(_ list: [AgentDestination], for asker: DestinationChoice.Asker) -> DestinationChoice.Answer {
            DestinationChoice.choose(.init(destinations: list, complete: true, fresh: true, startable: [resume, new]), for: asker)
        }
        XCTAssertNil(choose([], for: .send(cameFrom: nil)).pick)
        XCTAssertEqual(choose([running], for: .send(cameFrom: nil)).pick?.id, "r")
        XCTAssertEqual(choose([], for: .send(cameFrom: nil)).startable, [resume, new])
        XCTAssertNil(choose([], for: .liveNote(.remembered(claude(past)))).pick)
        XCTAssertEqual(choose([], for: .liveNote(.byHand(resume))).pick, resume)
        XCTAssertEqual(ToolbarOffer(replyTo: nil, destinations: [], listed: true, target: nil, startable: [resume, new]), .choose)
        XCTAssertEqual(ToolbarOffer(replyTo: nil, destinations: [], listed: false, target: nil, startable: [resume, new]), .copy)
        XCTAssertEqual(ToolbarOffer.choose.finishes, ToolbarOffer.copy.finishes)
        XCTAssertEqual(ToolbarOffer(replyTo: claude(past), destinations: [], listed: true, target: nil, startable: [resume, new]), .choose)
    }

    func testRowsThatStartASessionAreSearchedAfterTheRunningOnesAndShownOnlyWhenNoneRuns() {
        let now = Date()
        let resume = claude(past, used: now.timeIntervalSince1970, start: .resume(folder: "/site"))
        let new = claude("new:/site", used: now.timeIntervalSince1970, start: .new(folder: "/site"))
        let running = claude("r", used: now.timeIntervalSince1970 - 86000)
        let other = claude("o", used: now.timeIntervalSince1970 - 86100)
        XCTAssertEqual(SessionMenu.ranked([new, running, resume], now: now).map(\.id), ["r", past, "new:/site"])
        let menu = SessionMenu.menu([new, running, resume, other], destination: nil, count: 1, now: now)
        XCTAssertEqual(menu.topRows.map(\.id), ["r"])
        XCTAssertEqual(menu.projects.flatMap(\.rows).map(\.id), ["r", "o"], "a project's count is its running sessions")
        XCTAssertEqual(SessionMenu.matching("", in: menu.everyone).flatMap(\.rows).map(\.id), ["r", "o", past, "new:/site"])
        var (inRepository, newInRepository) = (resume, new)
        inRepository.place = .repository(name: "site", root: "/site", worktree: nil, subfolder: nil)
        newInRepository.place = inRepository.place
        let apart = SessionMenu.menu([running, inRepository, newInRepository], destination: nil, now: now).everyone
        XCTAssertEqual(SessionMenu.matching("", in: apart).first?.rows.first?.id, "r",
                       "a running session in Other folders still comes before a project's rows that start one")
        XCTAssertEqual(SessionMenu.menu([new, running, resume], destination: resume, now: now).topRows.map(\.id), ["r", past],
                       "a picked row that starts a session stays in view as the target")
        let rows = SessionMenu.menu([new, resume], destination: nil, now: now).topRows
        XCTAssertEqual(rows.map(\.title), [SessionMenu.continueLast, SessionMenu.newSession], "with none running they are what the menu offers")
        XCTAssertTrue(rows[0].subtitle.contains(past), rows[0].subtitle)
        XCTAssertEqual(SessionMenu.row(of: resume, among: [running], now: now).title, SessionMenu.lastSession(in: "site"))
        XCTAssertEqual(SessionMenu.row(of: new, among: [running], now: now).title, SessionMenu.newSession(in: "site"))
        XCTAssertTrue(SessionMenu.row(of: resume, among: [running], now: now).tooltip.hasPrefix(SessionMenu.continueLast))
        XCTAssertEqual(SessionMenu.cardTitle(of: SessionMenu.row(of: resume, among: [running], now: now)), "site")
        XCTAssertEqual(SessionMenu.cardTitle(of: SessionMenu.row(of: new, among: [running], now: now)), "site")
        XCTAssertEqual(SessionMenu.cardTitle(of: menu.topRows[0]), "r")
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
        private(set) var launches: [(SessionStart, String)] = []
        var now: Date { lock.withLock { time } }
        func advance(_ seconds: TimeInterval) { lock.withLock { time = time.addingTimeInterval(seconds) } }
        func launched(_ start: SessionStart, _ session: String) { lock.withLock { launches.append((start, session)) } }
    }

    private func connection(_ root: URL, clock: Clock, launch: @escaping @Sendable (SessionStart, String) -> HerdrLauncher.Started) -> ClaudeCodeConnection {
        var connection = ClaudeCodeConnection()
        connection.inboxes = root
        connection.transcripts = URL(fileURLWithPath: "/nonexistent/projects")
        connection.isRunning = { _ in true }
        connection.now = { clock.now }
        connection.later = { delay, look in clock.advance(delay); look() }
        connection.launch = { clock.launched($0, $1); return launch($0, $1) }
        return connection
    }

    private func submit(_ line: String, to destination: AgentDestination, through connection: ClaudeCodeConnection) async -> SubmissionOutcome {
        await withCheckedContinuation { done in connection.submit(line, to: destination, watchingTurn: false) { done.resume(returning: $0) } }
    }

    private func lines(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".line") }
    }

    func testASendToASessionThatIsNotRunningStartsItThenWritesTheLineIntoItsInbox() async throws {
        let root = temporaryFolder()
        try Self.inbox(root, pid: 300, session: older)
        let clock = Clock()
        let up = connection(root, clock: clock) { _, session in
            try? Self.inbox(root, pid: 301, session: session)
            return .started(tab: "tb9", terminal: "t9")
        }
        let destination = AgentDestination(id: past, name: "x", address: .claudeSession(past), start: .resume(folder: "/site"))
        guard case .accepted(let detail) = await submit("From Vignette: look", to: destination, through: up) else { return XCTFail("started and delivered") }
        XCTAssertTrue(detail.contains("inbox=301"), detail)
        XCTAssertEqual(clock.launches.map(\.1), [past])
        XCTAssertEqual(lines(in: root.appendingPathComponent("301")).count, 1)

        let again = await submit("again", to: destination, through: up)
        XCTAssertTrue(again.isAccepted)
        XCTAssertEqual(clock.launches.count, 1)
        XCTAssertFalse(up.submit("x", to: destination).isAccepted)
    }

    func testAStartThatFailsOrNeverComesUpSendsNothing() async throws {
        let root = temporaryFolder()
        let clock = Clock()
        let destination = AgentDestination(id: past, name: "x", address: .claudeSession(past), start: .new(folder: "/site"))
        let refused = connection(root, clock: clock) { _, _ in .failed(detail: "no tab") }
        guard case .notSubmitted(_, _, let reason) = await submit("x", to: destination, through: refused) else { return XCTFail("a failed start sends nothing") }
        XCTAssertEqual(reason, ClaudeCodeConnection.notStarted)

        let silent = connection(root, clock: clock) { _, _ in .started(tab: "tb", terminal: "t") }
        let began = clock.now
        guard case .notSubmitted(_, _, let late) = await submit("x", to: destination, through: silent) else { return XCTFail("a session that never came up got nothing") }
        XCTAssertEqual(late, ClaudeCodeConnection.notUpInTime)
        XCTAssertGreaterThanOrEqual(clock.now.timeIntervalSince(began), ClaudeCodeConnection.startTimeout)

        let notASession = AgentDestination(id: "new:/site", name: "x", address: .claudeSession("new:/site"), start: .new(folder: "/site"))
        let unstarted = await submit("x", to: notASession, through: silent)
        XCTAssertFalse(unstarted.isAccepted)
        XCTAssertEqual(clock.launches.count, 2)
    }

    func testASecondSendWhileItsSessionIsStillStartingJoinsThatStart() async throws {
        let root = temporaryFolder()
        let clock = Clock()
        var starting = connection(root, clock: clock) { _, _ in .started(tab: "tb", terminal: "t") }
        starting.later = { delay, look in
            clock.advance(delay)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.02, execute: look)
        }
        let destination = AgentDestination(id: past, name: "x", address: .claudeSession(past), start: .resume(folder: "/site"))
        async let first = submit("one", to: destination, through: starting)
        async let second = submit("two", to: destination, through: starting)
        let deadline = Date().addingTimeInterval(0.3)
        while clock.launches.count < 2, Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        try Self.inbox(root, pid: 301, session: past)
        let outcomes = await [first, second]
        XCTAssertEqual(clock.launches.count, 1)
        XCTAssertTrue(outcomes.allSatisfy(\.isAccepted), "\(outcomes)")
        XCTAssertEqual(lines(in: root.appendingPathComponent("301")).count, 2)
    }

    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var made: [[String]] = []
        var all: [[String]] { lock.withLock { made } }
        func add(_ call: [String]) { lock.withLock { made.append(call) } }
    }

    private func launcher(_ calls: Calls, shell: String? = "/bin/zsh",
                          answer: @escaping @Sendable ([String]) -> HerdrFocus.Answer?) -> HerdrLauncher {
        var launcher = HerdrLauncher()
        launcher.app = { "/fake/herdr-app" }
        launcher.core = { "/fake/hc" }
        launcher.loginShell = { shell }
        launcher.newTab = { "tb00112233445566778899aabbccddeeff" }
        let clock = Clock()
        launcher.now = { clock.now }
        launcher.later = { delay, next in clock.advance(delay); next() }
        launcher.run = { binary, arguments, _ in
            let call = [binary] + arguments
            calls.add(call)
            return answer(call)
        }
        return launcher
    }

    private static let status: HerdrFocus.Answer = (0, """
        {
          "zoom": 0.9,
          "space": "sp4fe76ace6023eaa0977d3a274c249faf",
          "tab": "tbA",
          "focused_pane": "pA"
        }
        """, false)
    private static let ran: HerdrFocus.Answer = (0, #"{"address":"t42","argv":["/bin/zsh"],"labels":{}}"#, false)

    func testTheSessionRunsInANewTabOfTheSpaceTheWindowShowsWithEveryWordItsOwnArgument() {
        let calls = Calls()
        let renames = Calls()
        let start = launcher(calls) { call in
            if call[1] == "status" { return Self.status }
            if call[1] == "run" { return Self.ran }
            renames.add(call)
            return renames.all.count < 3 ? (1, "no tab tb00112233445566778899aabbccddeeff", false) : (0, "", false)
        }
        XCTAssertEqual(start.start(.resume(folder: "/Users/p/it's here"), session: past),
                       .started(tab: "tb00112233445566778899aabbccddeeff", terminal: "t42"))
        let rename = ["/fake/herdr-app", "do", "tab.rename", #"{"id":"tb00112233445566778899aabbccddeeff","name":"it's here"}"#]
        XCTAssertEqual(calls.all, [
            ["/fake/herdr-app", "status"],
            ["/fake/hc", "run", "--bg", "--json", "--cwd", "/Users/p/it's here", "--no-parent",
             "--label", "herdr.space=sp4fe76ace6023eaa0977d3a274c249faf", "--label", "herdr.tab=tb00112233445566778899aabbccddeeff", "--",
             "/bin/zsh", "-lic", #""$@"; exec "$0" -li"#, "/bin/zsh", "claude", "--resume", past],
            rename, rename, rename,
        ], "a terminal without herdr.space is hidden, a folder joined into a shell line is parsed, and the rename waits for the tab")
    }

    func testClaudeRunsInTheLoginShellWhenItIsZshOrBashAndInZshOtherwise() {
        let program = ["claude", "--session-id", past]
        XCTAssertEqual(HerdrLauncher.wrapped(program, loginShell: "/opt/homebrew/bin/bash"),
                       ["/opt/homebrew/bin/bash", "-lic", #""$@"; exec "$0" -li"#, "/opt/homebrew/bin/bash"] + program)
        XCTAssertEqual(HerdrLauncher.wrapped(program, loginShell: "/opt/homebrew/bin/fish").first, "/bin/zsh", "fish cannot run the line")
        XCTAssertEqual(HerdrLauncher.wrapped(program, loginShell: nil).first, "/bin/zsh")
    }

    func testWithoutASpaceOrWhenHcRefusesNothingStartsAndAFailedRenameIsNoFailedStart() {
        let calls = Calls()
        let closed = launcher(calls) { call in call[1] == "status" ? (1, "no Herdr window", false) : Self.ran }
        XCTAssertEqual(closed.start(.new(folder: "/f"), session: past), .failed(detail: "herdr-app status: no Herdr window"))
        let spaceless = launcher(calls) { call in call[1] == "status" ? (0, #"{"space":"","tab":"tbA"}"#, false) : Self.ran }
        XCTAssertEqual(spaceless.start(.new(folder: "/f"), session: past), .failed(detail: "herdr-app status names no space"))
        XCTAssertFalse(calls.all.contains { $0[1] == "run" }, "a terminal without its space would be hidden")

        let refused = launcher(calls) { call in call[1] == "status" ? Self.status : (1, "core not running", false) }
        XCTAssertEqual(refused.start(.new(folder: "/f"), session: past), .failed(detail: "hc run: core not running"))

        let unnamed = Calls()
        let never = launcher(unnamed) { call in call[1] == "status" ? Self.status : call[1] == "run" ? Self.ran : (1, "no such tab", false) }
        XCTAssertEqual(never.start(.new(folder: "/f"), session: past), .started(tab: "tb00112233445566778899aabbccddeeff", terminal: "t42"))
        XCTAssertEqual(unnamed.all.filter { $0[1] == "do" }.count, Int(HerdrLauncher.renameWait / HerdrLauncher.renameStep),
                       "the rename gives up after renameWait")
    }
}
