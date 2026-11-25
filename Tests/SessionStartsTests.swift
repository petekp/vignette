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
        XCTAssertEqual(choose([running], for: .send(cameFrom: nil)).sessions.map(\.id), ["r", past, "new:/site"])
        XCTAssertEqual(choose([running], for: .liveNote(.remembered(nil))).sessions.map(\.id), ["r", past, "new:/site"])
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
        XCTAssertEqual(SessionMenu.matching("", in: menu).flatMap(\.rows).map(\.id), ["r", "o", past, "new:/site"])
        var (inRepository, newInRepository) = (resume, new)
        inRepository.place = .repository(name: "site", root: "/site", worktree: nil, subfolder: nil)
        newInRepository.place = inRepository.place
        let apart = SessionMenu.menu([running, inRepository, newInRepository], destination: nil, now: now)
        XCTAssertEqual(SessionMenu.matching("", in: apart).first?.rows.first?.id, "r",
                       "a running session in Other folders still comes before a project's rows that start one")
        XCTAssertEqual(SessionMenu.menu([new, running, resume], destination: resume, now: now).topRows.map(\.id), ["r", past],
                       "a picked row that starts a session stays in view as the target")
        let rows = SessionMenu.menu([new, resume], destination: nil, now: now).topRows
        XCTAssertEqual(rows.map(\.title), [SessionMenu.continueLast, SessionMenu.newSession], "with none running they are what the menu offers")
        XCTAssertTrue(rows[0].details.contains(past), rows[0].details)
        XCTAssertNotNil(rows[0].activity, "Continue says when the session it continues was last active")
        XCTAssertNil(rows[1].activity, "New has no time of its own")
        XCTAssertEqual(SessionMenu.row(of: resume, among: [running], now: now).title, SessionMenu.lastSession(in: "site"))
        XCTAssertEqual(SessionMenu.row(of: new, among: [running], now: now).title, SessionMenu.newSession(in: "site"))
        XCTAssertTrue(SessionMenu.row(of: resume, among: [running], now: now).tooltip.hasPrefix(SessionMenu.continueLast))
        XCTAssertEqual(SessionMenu.cardTitle(of: SessionMenu.row(of: resume, among: [running], now: now)), "site")
        XCTAssertEqual(SessionMenu.cardTitle(of: SessionMenu.row(of: new, among: [running], now: now)), "site")
        XCTAssertEqual(SessionMenu.cardTitle(of: menu.topRows[0]), "r")
    }
}
