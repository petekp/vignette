import XCTest

final class AgentConnectionTests: XCTestCase {
    private let session = "e011fff1-c791-4934-9e61-9307d840a5eb"

    /// The same panes as `herdr pane list` reports them, which is what the listing reads: every
    /// pane, agent or not, so it says where the focus is even when that pane runs no agent. Here a
    /// browser pane beside the session has the focus, as observed 2026-09-24.
    private func paneList(session: String, focused: String = "w9:p6") -> String {
        """
        {"id":"cli:pane:list","result":{"type":"pane_list","panes":[
          {"agent":"claude","agent_status":"idle","cwd":"/Users/p/Code/vignette","focused":\(focused == "w9:p6"),
           "agent_session":{"agent":"claude","kind":"id","value":"\(session)"},
           "pane_id":"w9:p6","tab_id":"w9:t1","terminal_title_stripped":"Closed agent loop","workspace_id":"w9"},
          {"agent":null,"agent_status":"unknown","cwd":"/Users/p/Code/vignette","focused":\(focused == "w9:pC"),
           "pane_id":"w9:pC","tab_id":"w9:t1","terminal_title_stripped":"browser","workspace_id":"w9"},
          {"agent":"claude","agent_status":"idle","cwd":"/Users/p/Code/other","focused":false,
           "pane_id":"w9:pA","tab_id":"w9:t2","terminal_title_stripped":"No session id","workspace_id":"w9"},
          {"agent":"codex","agent_status":"idle","cwd":"/Users/p/Code/two","focused":\(focused == "w9:pB"),
           "pane_id":"w9:pB","tab_id":"w9:t3","workspace_id":"w9"}]}}
        """
    }

    /// A connection over inboxes in a temporary folder. Every process id in `running` is taken to
    /// be alive.
    private func claude(inboxes root: URL, running: Set<Int32> = [101, 102], now: Date = Date()) -> ClaudeCodeConnection {
        var connection = ClaudeCodeConnection()
        connection.inboxes = root
        connection.transcripts = URL(fileURLWithPath: "/nonexistent/projects")
        connection.isRunning = { running.contains($0) }
        connection.now = { now }
        return connection
    }

    /// An inbox as the plugin's scripts leave it.
    @discardableResult
    private func inbox(_ root: URL, pid: Int32, session: String?, cwd: String = "/Users/p/Code/vignette",
                       alive: Date? = Date(), past: [String] = [], transcript: URL? = nil) throws -> URL {
        let folder = root.appendingPathComponent("\(pid)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let session { try Data("\(session)\n".utf8).write(to: folder.appendingPathComponent("session")) }
        try Data("\(cwd)\n".utf8).write(to: folder.appendingPathComponent("cwd"))
        if !past.isEmpty { try Data(past.map { $0 + "\n" }.joined().utf8).write(to: folder.appendingPathComponent("past")) }
        if let transcript { try Data("\(transcript.path)\n".utf8).write(to: folder.appendingPathComponent("transcript")) }
        if let alive {
            let file = folder.appendingPathComponent("alive")
            try Data().write(to: file)
            try FileManager.default.setAttributes([.modificationDate: alive], ofItemAtPath: file.path)
        }
        return folder
    }

    private func temporaryFolder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("inboxes-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // MARK: Claude Code, by session rather than by pane

    func testAnswerThatIsNotAPaneListIsNoAgents() {
        XCTAssertEqual(HerdrFocus.agents(in: Data("not json".utf8)), [])
        XCTAssertEqual(HerdrFocus.agents(in: Data(#"{"error":{"code":"no_server"}}"#.utf8)), [])
        XCTAssertNil(HerdrFocus(paneList: Data("not json".utf8)))
    }

    /// herdr's focus comes from `herdr pane list` when it succeeds. A failed herdr's output, or no
    /// herdr at all, is no focus.
    func testHerdrsFocusIsReadFromItsPaneList() {
        let panes = paneList(session: session)
        func read(binary: String? = "/bin/herdr", status: Int32 = 0) -> HerdrFocus? {
            HerdrFocus.read(binary: { binary }, run: { _, arguments, _ in
                (status, arguments == ["pane", "list"] ? panes : "", false)
            })
        }
        XCTAssertEqual(read(), HerdrFocus(paneList: Data(panes.utf8)))
        XCTAssertEqual(read()?.pane, "w9:p6")
        XCTAssertNil(read(status: 1), "a failed herdr says nothing about the focus")
        XCTAssertNil(read(binary: nil))
    }

    /// A test launch reaches sessions only through a tool the environment names: any other codex or
    /// herdr on the Mac is the person's, and would list and send to their own sessions.
    func testATestLaunchUsesOnlyTheSessionToolItIsGiven() {
        let found = { "/Users/p/.vite-plus/bin/codex" }
        XCTAssertEqual(AgentTools.forSessions("VIGNETTE_CODEX", environment: [:], otherwise: found), found())
        XCTAssertNil(AgentTools.forSessions("VIGNETTE_CODEX", environment: ["VIGNETTE_SETTINGS": "/tmp/s.json"], otherwise: found))
        XCTAssertEqual(AgentTools.forSessions("VIGNETTE_CODEX", environment: ["VIGNETTE_SETTINGS": "/tmp/s.json", "VIGNETTE_CODEX": "/tmp/fake-codex"],
                                              exists: { $0 == "/tmp/fake-codex" }, otherwise: found), "/tmp/fake-codex")
        XCTAssertNil(AgentTools.forSessions("VIGNETTE_CODEX", environment: ["VIGNETTE_SETTINGS": "/tmp/s.json", "VIGNETTE_CODEX": "/tmp/gone"],
                                            exists: { _ in false }, otherwise: found))
    }

    /// A session is offered while its process runs and its monitor does. An inbox whose process has
    /// gone is removed, since nothing else would; one whose monitor stopped stays, unlisted.
    func testOnlySessionsWithARunningMonitorAreOffered() throws {
        let root = temporaryFolder()
        let now = Date()
        try inbox(root, pid: 101, session: session)
        try inbox(root, pid: 102, session: "0f0f0f0f-0000-4000-8000-000000000000", alive: now.addingTimeInterval(-60))
        let gone = try inbox(root, pid: 103, session: "1f0f0f0f-0000-4000-8000-000000000000")
        try inbox(root, pid: 1010, session: nil)
        let connection = claude(inboxes: root, running: [101, 102, 1010], now: now)
        let found = connection.destinations()
        XCTAssertEqual(found.map(\.id), [session])
        XCTAssertEqual(found.first?.name, "New session in vignette", "no transcript yet")
        XCTAssertEqual(found.first?.detail, "vignette")
        XCTAssertEqual(found.first?.address.guardTier, .preflight)
        XCTAssertFalse(FileManager.default.fileExists(atPath: gone.path))
    }

    /// A transcript's tail as Claude Code writes it: titles that change, messages, and entries with
    /// no message in them that it writes to sessions nobody is using.
    private let transcriptTail = """
    {"type":"ai-title","aiTitle":"Loop","sessionId":"s"}
    {"type":"user","timestamp":"2026-09-19T03:42:30.000Z","cwd":"/Users/p/Code/one","message":{"role":"user","content":"hi"}}
    {"type":"ai-title","aiTitle":"Closed agent loop, whole","sessionId":"s"}
    {"type":"assistant","timestamp":"2026-09-19T03:42:45.341Z","cwd":"/Users/p/Code/two","message":{"content":[{"type":"text","text":"done"}]}}
    {"type":"system","subtype":"away_summary","timestamp":"2026-09-24T19:30:00.000Z"}
    {"type":"bridge-session"}
    """

    /// The session was last used when its last message was written, not when Claude Code last
    /// touched the file, and its title is the latest one.
    func testATranscriptSaysWhenItsSessionWasLastUsedAndWhatItIsCalled() throws {
        let found = ClaudeCodeConnection.transcript(tail: Data(transcriptTail.utf8))
        XCTAssertEqual(found.title, "Closed agent loop, whole")
        XCTAssertEqual(found.cwd, "/Users/p/Code/two")
        let expected = try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse("2026-09-19T03:42:45.341Z")
        XCTAssertEqual(found.lastUsed, expected, "an away_summary is not the session being used")
    }

    /// A tail that starts part way through a line leaves that line out rather than misreading it.
    func testATailStartsAtALine() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("tail-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("{\"a\":1}\n{\"b\":2}\n".utf8).write(to: file)
        XCTAssertEqual(ClaudeCodeConnection.tail(of: file, bytes: 10).map { String(decoding: $0, as: UTF8.self) }, "{\"b\":2}\n")
        XCTAssertEqual(ClaudeCodeConnection.tail(of: file, bytes: 100).map { String(decoding: $0, as: UTF8.self) }, "{\"a\":1}\n{\"b\":2}\n")
    }

    /// The transcript the hooks named, or else the one found in whichever project folder it is in,
    /// names the session. The project is the folder Claude Code runs in, not the one the session's
    /// shell was last in.
    func testASessionIsNamedByItsTranscript() throws {
        let root = temporaryFolder()
        let projects = root.appendingPathComponent("projects")
        let folder = projects.appendingPathComponent("-Users-p-Code-elsewhere")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(transcriptTail.utf8).write(to: folder.appendingPathComponent("\(session).jsonl"))
        let inboxes = root.appendingPathComponent("inboxes")
        try inbox(inboxes, pid: 101, session: session)

        var connection = claude(inboxes: inboxes)
        connection.transcripts = projects
        let found = connection.destinations()
        XCTAssertEqual(found.map(\.name), ["Closed agent loop, whole"])
        XCTAssertEqual(found.first?.detail, "vignette")
        XCTAssertNotNil(found.first?.lastUsed)

        let named = root.appendingPathComponent("named.jsonl")
        try Data("{\"type\":\"ai-title\",\"aiTitle\":\"From the hook\"}\n".utf8).write(to: named)
        try inbox(inboxes, pid: 101, session: session, transcript: named)
        XCTAssertEqual(connection.destinations().map(\.name), ["From the hook"])
    }

    /// Send starts on the session you came from: herdr's focused pane, or the one session in the
    /// focused pane's tab when that pane runs no agent. A tab with two sessions says nothing.
    func testSendStartsOnTheSessionInHerdrsFocus() {
        let mew = ClaudeCodeConnection.destination(session: session, cwd: "/Users/p/Code/vignette", transcript: .init())
        func choose(_ sessions: [AgentDestination], complete: Bool = false, herdr: HerdrFocus?) -> DestinationChoice.Answer {
            DestinationChoice.choose(.init(destinations: sessions, complete: complete, fresh: true, herdr: herdr), for: .send(cameFrom: nil))
        }
        func focus(_ pane: String) -> AgentDestination.Focus? {
            choose([mew], herdr: HerdrFocus(paneList: Data(paneList(session: session, focused: pane).utf8))).list.first?.focus
        }
        XCTAssertEqual(focus("w9:p6"), .pane)
        XCTAssertEqual(focus("w9:pC"), .tab, "the browser beside the session")
        XCTAssertNil(focus("w9:pA"), "another session's pane, even one herdr cannot name")
        XCTAssertNil(focus("w9:pB"), "a Codex pane")

        let listed = HerdrFocus.agents(in: Data(paneList(session: session).utf8))
        func marked(_ extra: HerdrFocus.AgentPane, focus: String) -> [AgentDestination.Focus?] {
            choose([mew], herdr: HerdrFocus(pane: focus, tab: "w9:t1", agents: listed + [extra])).list.map(\.focus)
        }
        let second = HerdrFocus.AgentPane(pane: "w9:pD", session: "second", tab: "w9:t1")
        XCTAssertEqual(marked(second, focus: "w9:pC"), [nil], "two sessions beside the browser")
        let codex = HerdrFocus.AgentPane(pane: "w9:pE", tab: "w9:t1")
        XCTAssertEqual(marked(codex, focus: "w9:pE"), [nil], "you are talking to the Codex beside it")

        let old = AgentDestination(id: "1", name: "a", address: .claudeSession("1"), lastUsed: Date(timeIntervalSince1970: 100))
        let new = AgentDestination(id: "2", name: "b", address: .codexThread(uuid: "2"), lastUsed: Date(timeIntervalSince1970: 200))
        let besideOld = HerdrFocus(pane: "w9:pC", tab: "w9:t1", agents: [.init(pane: "w9:p6", session: "1", tab: "w9:t1")])
        func pick(_ list: [AgentDestination], herdr: HerdrFocus? = nil) -> String? {
            choose(list, complete: true, herdr: herdr).pick?.id
        }
        XCTAssertEqual(pick([new, old], herdr: besideOld), "1", "focus comes before the session used last")
        XCTAssertEqual(pick([new, old]), "2")
        XCTAssertNil(pick([]))
        XCTAssertEqual(choose([new, old], herdr: besideOld).pick?.id, "1", "a focus decides before every client has answered")
        XCTAssertFalse(choose([new, old], herdr: nil).decided, "without a focus, the session used last waits for every client")

        let thread = AgentDestination(id: "t1", name: "x", address: .codexThread(uuid: "t1"), lastUsed: Date(timeIntervalSince1970: 50))
        let onCodex = HerdrFocus(pane: "w9:pB", tab: "w9:t3", agents: [.init(pane: "w9:pB", session: "t1", tab: "w9:t3")])
        let whole = choose([old, thread], complete: true, herdr: onCodex)
        XCTAssertEqual(whole.list.map(\.focus), [nil, nil],
                       "herdr's focus on a Codex pane marks nothing, even when herdr names its thread")
        XCTAssertEqual(whole.pick?.id, "1", "so the whole list picks the session used last")
        XCTAssertFalse(choose([old, thread], herdr: onCodex).decided, "and a partial list waits")

        var claimed = old
        claimed.focus = .pane
        let ignored = choose([claimed], herdr: nil)
        XCTAssertNil(ignored.list.first?.focus, "only choose marks: a focus on what it is given is ignored")
        XCTAssertFalse(ignored.decided)
    }

    /// Coming from the Codex app, Send starts on the thread it shows, whatever herdr's focus says,
    /// since herdr keeps a focused pane while its terminal is behind (observed 2026-09-25).
    func testSendStartsOnTheThreadTheCodexAppShows() {
        let focused = AgentDestination(id: "c", name: "vignette", address: .claudeSession("c"))
        let herdr = HerdrFocus(pane: "p", tab: "t", agents: [.init(pane: "p", session: "c", tab: "t")])
        let recent = AgentDestination(id: "t1", name: "Review codebase", address: .codexThread(uuid: "t1"))
        let shown = AgentDestination(id: "t2", name: "Build showroom MCP App PoC", address: .codexThread(uuid: "t2"))
        let list = [focused, recent, shown]
        func choose(_ id: String?, in list: [AgentDestination] = list, fresh: Bool = true) -> DestinationChoice.Answer {
            DestinationChoice.choose(.init(destinations: list, complete: true, fresh: fresh, herdr: herdr), for: .send(cameFrom: (.codex, id)))
        }
        XCTAssertEqual(choose("t2").pick?.id, "t2")
        XCTAssertEqual(choose(nil).pick?.id, "t1", "an app showing no thread gives the Codex thread used last")
        XCTAssertEqual(choose("t9").pick?.id, "t1", "a thread the fresh list lacks")
        XCTAssertEqual(choose(nil, in: [focused]).list.map(\.focus), [nil],
                       "no Codex thread listed: herdr's focus still says nothing")
        let kept = choose("t9", fresh: false)
        XCTAssertEqual(kept.list.map(\.focus), [nil, nil, nil], "a kept list may predate the shown thread")
        XCTAssertFalse(kept.complete, "so the fresh list decides, not the thread used last")
        XCTAssertFalse(kept.decided)
        XCTAssertNil(kept.pick)
        XCTAssertEqual(choose("t2", fresh: false).pick?.id, "t2", "a thread the kept list has settles at once")
    }

    /// The Codex app logs the page its window moves to. The thread it shows is the last such line
    /// in the newest log of its own process, and a page that is not a thread on this Mac is none.
    /// The lines are the app's own (26.928, 2026-10-01), cut to the fields read.
    func testTheThreadTheCodexAppShowsIsTheLastPageItsLogNames() throws {
        let logs = temporaryFolder()
        func write(_ day: String, _ name: String, _ lines: [String], modified: Date) throws {
            let folder = logs.appendingPathComponent(day)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent(name)
            try Data(lines.map { $0 + "\n" }.joined().utf8).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
        }
        func page(_ route: String) -> String {
            "2026-10-02T02:30:20.336Z info [electron-message-handler] IAB_LIFECYCLE received browser sidebar owner sync browserTabId=null conversationId=client-new-thread:b78b originWebContentsId=1 ownerRoutePath=\(route) windowId=1"
        }
        let older = "01a0d213-5b49-7352-9da1-46cdacf0be18", shown = "01a0fa21-6386-7b50-8d42-3d21ae412c09"
        let now = Date()
        try write("2026/10/01", "codex-desktop-a7ea-52946-t0-i1-033930-0.log", [page("/local/\(older)")], modified: now - 7200)
        try write("2026/10/02", "codex-desktop-a7ea-52946-t0-i1-000304-0.log",
                  [page("/local/\(older)"), "info [thread-stream] other", page("/local/\(shown)"), "info later"], modified: now - 60)
        try write("2026/10/02", "codex-desktop-a7ea-52946-t1-i1-003632-0.log", ["info no pages here"], modified: now)
        try write("2026/10/02", "codex-desktop-b8fb-61111-t0-i1-010000-0.log", [page("/local/\(older)")], modified: now)
        let launched = ISO8601DateFormatter().date(from: "2026-10-01T03:39:30Z")
        XCTAssertEqual(AgentApp.shownThread(pid: 52946, launched: launched, logs: logs), shown)
        XCTAssertEqual(AgentApp.shownThread(pid: 52946, launched: ISO8601DateFormatter().date(from: "2026-10-03T00:00:00Z"), logs: logs),
                       nil, "a file from before the process started is another process's")
        try write("2026/10/02", "codex-desktop-a7ea-52946-t0-i1-000304-0.log", [page("/local/\(shown)"), page("/c/6a1b")], modified: now - 60)
        XCTAssertNil(AgentApp.shownThread(pid: 52946, launched: launched, logs: logs), "a ChatGPT chat is no Codex thread")
        XCTAssertNil(AgentApp.thread(inRoute: "/local/client-new-thread:10df"), "a new thread not sent yet")
        XCTAssertNil(AgentApp.thread(inRoute: "/"))
        XCTAssertNil(AgentApp.thread(inRoute: "/dots/\(shown)"), "not a thread on this Mac")
    }

    /// Send's menu holds the active sessions used last, five at most, and always the target. A
    /// Codex thread is active when used in the last day; a Claude Code session is listed only
    /// while it runs in a herdr pane.
    func testTheMenuListsTheActiveSessionsAndTheTarget() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func codex(_ id: String, hoursAgo: Double) -> AgentDestination {
            AgentDestination(id: id, name: id, address: .codexThread(uuid: id), lastUsed: now.addingTimeInterval(-hoursAgo * 3600))
        }
        func claude(_ id: String, hoursAgo: Double) -> AgentDestination {
            AgentDestination(id: id, name: id, address: .claudeSession(id), lastUsed: now.addingTimeInterval(-hoursAgo * 3600))
        }
        let list = [codex("a", hoursAgo: 1), claude("b", hoursAgo: 2), codex("c", hoursAgo: 30),
                    claude("d", hoursAgo: 40), claude("e", hoursAgo: 50), claude("f", hoursAgo: 60), claude("g", hoursAgo: 70)]
        XCTAssertEqual(SessionMenu.menu(list, destination: list[0], now: now).topRows.map(\.id), ["a", "b", "d", "e", "f"],
                       "a Codex thread from yesterday is left out")
        XCTAssertEqual(SessionMenu.menu(list, destination: list[6], now: now).topRows.map(\.id), ["a", "b", "d", "e", "g"])
        XCTAssertEqual(SessionMenu.menu(list, destination: list[2], now: now).topRows.map(\.id), ["a", "b", "d", "e", "c"],
                       "the target is shown even when it is not active")
        let menu = SessionMenu.menu(list, destination: list[0], now: now)
        XCTAssertEqual(menu.projects.flatMap(\.rows).map(\.id), ["a", "b", "d", "e", "f", "g"],
                       "the project submenus hold every active session, the top rows too, in order")
        XCTAssertTrue(SessionMenu.menu(Array(list.prefix(2)), destination: list[0], now: now).projects.isEmpty,
                      "five active sessions or fewer need no submenus")
    }

    /// Send lists the session used last first, and one with no known time after all the others.
    func testSessionsAreListedNewestFirst() {
        let old = AgentDestination(id: "1", name: "a", address: .claudeSession("1"), lastUsed: Date(timeIntervalSince1970: 100))
        let new = AgentDestination(id: "2", name: "b", address: .codexThread(uuid: "2"), lastUsed: Date(timeIntervalSince1970: 200))
        let unknown = AgentDestination(id: "3", name: "0", address: .claudeSession("3"))
        XCTAssertEqual([unknown, old, new].sorted(by: DestinationChoice.newestFirst).map(\.id), ["2", "1", "3"])
    }

    /// The request lands in the inbox holding the session, and in no other.
    func testTheRequestGoesToTheInboxHoldingTheSession() throws {
        let root = temporaryFolder()
        let folder = try inbox(root, pid: 102, session: session)
        try inbox(root, pid: 101, session: "0f0f0f0f-0000-4000-8000-000000000000")
        let connection = claude(inboxes: root)
        let destination = AgentDestination(id: session, name: "x", address: .claudeSession(session))
        guard case .accepted(let detail) = connection.submit("look here [From Vignette]", to: destination) else {
            return XCTFail("a session with a live inbox is submittable")
        }
        XCTAssertTrue(detail.contains("inbox=102"))
        let lines = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".line") }
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent(lines[0]), encoding: .utf8),
                       "look here [From Vignette]\n")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("101").path).filter { $0.hasSuffix(".line") }, [])
    }

    func testASessionRunningInTwoProcessesIsListedOnceAndItsMenuIsBuilt() throws {
        let root = temporaryFolder()
        try inbox(root, pid: 101, session: session)
        try inbox(root, pid: 102, session: session)
        let connection = claude(inboxes: root)
        let found = connection.destinations()
        XCTAssertEqual(found.map(\.id), [session])
        _ = SessionMenu.menu(found, destination: found.first)
        XCTAssertEqual(SessionMenu.row(of: found[0], among: found).destination.id, session)
    }

    /// A session in no inbox is an error, never another session's inbox. When the process that ran
    /// it has since run `/clear` or `/resume`, the card says so.
    func testASessionInNoInboxIsAnErrorAndNeverAnother() throws {
        let root = temporaryFolder()
        let folder = try inbox(root, pid: 101, session: "0f0f0f0f-0000-4000-8000-000000000000")
        let connection = claude(inboxes: root)
        let destination = AgentDestination(id: session, name: "x", address: .claudeSession(session))
        guard case .destinationChanged(_, let reason) = connection.submit("hello", to: destination) else {
            return XCTFail("a missing session must not fall back to another")
        }
        XCTAssertEqual(reason, ClaudeCodeConnection.closed)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".line") }, [])

        try inbox(root, pid: 101, session: "0f0f0f0f-0000-4000-8000-000000000000", past: [session])
        guard case .destinationChanged(_, let clearedReason) = connection.submit("hello", to: destination) else {
            return XCTFail("a cleared session is gone from its inbox")
        }
        XCTAssertEqual(clearedReason, ClaudeCodeConnection.cleared)
    }

    func testASessionsTurnIsReadFromTheInboxItWasListedFromAndNeverAnother() throws {
        let root = temporaryFolder()
        let folder = try inbox(root, pid: 102, session: session)
        try Data("busy\n".utf8).write(to: folder.appendingPathComponent("turn"))
        let other = try inbox(root, pid: 101, session: "0f0f0f0f-0000-4000-8000-000000000000")
        try Data("idle\n".utf8).write(to: other.appendingPathComponent("turn"))
        let connection = claude(inboxes: root)
        let listed = try XCTUnwrap(connection.destinations().first { $0.id == session })
        XCTAssertEqual(listed.inbox, 102)
        XCTAssertEqual(connection.turn(of: listed), .busy)

        try inbox(root, pid: 102, session: "0f0f0f0f-0000-4000-8000-000000000000")
        XCTAssertNil(connection.turn(of: listed))
        try FileManager.default.removeItem(at: folder)
        XCTAssertNil(connection.turn(of: listed))
        XCTAssertNil(connection.turn(of: AgentDestination(id: session, name: "x", address: .claudeSession(session))))
    }

    // MARK: Where a session works

    private func makeFolder(_ path: String, in root: URL) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func canonical(_ url: URL) -> String {
        (try? url.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath) ?? url.path
    }

    /// A custom title is the person's and beats the one Claude Code writes, whichever came last.
    func testACustomTitleBeatsTheAITitle() {
        let tail = """
        {"type":"custom-title","customTitle":"Mine","sessionId":"x"}
        {"type":"ai-title","aiTitle":"Theirs","sessionId":"x"}
        {"type":"user","timestamp":"2026-09-19T03:42:45.341Z","message":{}}
        """
        let found = ClaudeCodeConnection.transcript(tail: Data(tail.utf8))
        XCTAssertEqual(found.title, "Mine")
        XCTAssertEqual(found.aiTitle, "Theirs")
    }

    /// The repository comes from `.git` files alone: a main checkout, a worktree through its
    /// `commondir`, and the branch only when it is not the default.
    func testARepositoryWorktreeSubfolderAndBranchAreReadFromGitFiles() throws {
        let base = temporaryFolder()
        let home = try makeFolder("home", in: base)
        let main = try makeFolder("home/Code/evercars", in: base)
        try write("ref: refs/heads/main\n", to: main.appendingPathComponent(".git/HEAD"))
        try write("ref: refs/remotes/origin/main\n", to: main.appendingPathComponent(".git/refs/remotes/origin/HEAD"))
        _ = try makeFolder("home/Code/evercars/apps/pdk-ui/.hidden", in: base)

        let inMain = SessionPlaces.resolve(folder: main.appendingPathComponent("apps/pdk-ui").path, home: home.path)
        XCTAssertEqual(inMain.place, .repository(name: "evercars", root: canonical(main), worktree: nil, subfolder: "apps/pdk-ui"))
        XCTAssertNil(inMain.branch, "the default branch is not shown")

        let inHidden = SessionPlaces.resolve(folder: main.appendingPathComponent("apps/pdk-ui/.hidden").path, home: home.path)
        XCTAssertEqual(inHidden.place, .repository(name: "evercars", root: canonical(main), worktree: nil, subfolder: "apps/pdk-ui"))

        // A worktree: its `.git` file names its gitdir, whose `commondir` names the main repository's.
        let worktree = try makeFolder("home/Code/worktrees/evercars/live-ink", in: base)
        let gitdir = main.appendingPathComponent(".git/worktrees/live-ink")
        try write("gitdir: \(gitdir.path)\n", to: worktree.appendingPathComponent(".git"))
        try write("../..\n", to: gitdir.appendingPathComponent("commondir"))
        try write("ref: refs/heads/live-ink\n", to: gitdir.appendingPathComponent("HEAD"))
        let inWorktree = SessionPlaces.resolve(folder: worktree.path, home: home.path)
        XCTAssertEqual(inWorktree.place, .repository(name: "evercars", root: canonical(main), worktree: "live-ink", subfolder: nil))
        XCTAssertEqual(inWorktree.branch, "live-ink")

        // A worktree Codex made is "Codex worktree", whatever its folder is called, and a detached HEAD has no branch.
        // A worktree that is gone inside its repository is that worktree, not a subfolder of the checkout.
        let goneInside = SessionPlaces.resolve(folder: main.appendingPathComponent(".claude/worktrees/agent-1").path, home: home.path)
        XCTAssertEqual(goneInside.place, .repository(name: "evercars", root: canonical(main), worktree: "agent-1", subfolder: nil))

        let codex = try makeFolder("home/.codex/worktrees/6684/evercars", in: base)
        let codexGitdir = main.appendingPathComponent(".git/worktrees/evercars1")
        try write("gitdir: \(codexGitdir.path)\n", to: codex.appendingPathComponent(".git"))
        try write("../..\n", to: codexGitdir.appendingPathComponent("commondir"))
        try write("0123456789abcdef\n", to: codexGitdir.appendingPathComponent("HEAD"))
        let inCodex = SessionPlaces.resolve(folder: codex.path, home: home.path)
        XCTAssertEqual(inCodex.place, .repository(name: "evercars", root: canonical(main), worktree: SessionPlaces.codexWorktree, subfolder: nil))
        XCTAssertNil(inCodex.branch)
    }

    /// With no origin/HEAD the default is main, else master, and a session on another branch shows it.
    func testTheDefaultBranchFallsBackToMainThenMaster() throws {
        let base = temporaryFolder()
        let home = try makeFolder("home", in: base)
        let repo = try makeFolder("home/old", in: base)
        try write("ref: refs/heads/feature\n", to: repo.appendingPathComponent(".git/HEAD"))
        try write("0123\n", to: repo.appendingPathComponent(".git/refs/heads/master"))
        XCTAssertEqual(SessionPlaces.resolve(folder: repo.path, home: home.path).branch, "feature")
        try write("ref: refs/heads/master\n", to: repo.appendingPathComponent(".git/HEAD"))
        XCTAssertNil(SessionPlaces.resolve(folder: repo.path, home: home.path).branch)
    }

    /// A folder with no repository is Other folders as a path from home, and home's own `.git` is never taken.
    func testAFolderWithNoRepositoryIsAPathFromHome() throws {
        let base = temporaryFolder()
        let home = try makeFolder("home", in: base)
        try write("ref: refs/heads/main\n", to: home.appendingPathComponent(".git/HEAD"))
        let code = try makeFolder("home/Code", in: base)
        XCTAssertEqual(SessionPlaces.resolve(folder: code.path, home: home.path).place, .folder(fromHome: "~/Code"))
        XCTAssertEqual(SessionPlaces.resolve(folder: home.path, home: home.path).place, .folder(fromHome: "~"))
        XCTAssertEqual(SessionPlaces.resolve(folder: nil, home: home.path).place, .none)
    }

    /// A folder that is gone is read from its shape, then from the remote, else it is a plain folder.
    func testAFolderThatIsGoneIsReadFromItsShapeThenItsRemote() throws {
        let base = temporaryFolder()
        let home = try makeFolder("home", in: base)
        func place(_ path: String, origin: String? = nil) -> Place {
            SessionPlaces.resolve(folder: home.appendingPathComponent(path).path, originURL: origin, home: home.path).place
        }
        XCTAssertEqual(place(".codex/worktrees/6684/evercars/apps/ui"),
                       .repository(name: "evercars", root: nil, worktree: SessionPlaces.codexWorktree, subfolder: "apps/ui"))
        XCTAssertEqual(place("Code/worktrees/vignette/menu"), .repository(name: "vignette", root: nil, worktree: "menu", subfolder: nil))
        XCTAssertEqual(place("Code/vignette/.worktrees/menu/Sources"), .repository(name: "vignette", root: nil, worktree: "menu", subfolder: "Sources"))
        XCTAssertEqual(place("Code/vignette/.claude/worktrees/menu"), .repository(name: "vignette", root: nil, worktree: "menu", subfolder: nil))
        XCTAssertEqual(place("Code/gone", origin: "git@github.com:Ever-Cars/evercars-backend.git"),
                       .repository(name: "evercars-backend", root: nil, worktree: nil, subfolder: nil))
        XCTAssertEqual(place("Code/gone"), .folder(fromHome: "~/Code/gone"))
        XCTAssertEqual(SessionPlaces.remoteName("https://github.com/Ever-Cars/evercars-backend.git"), "evercars-backend")
    }

    func testHerdrTabLabelsAreReadByTabAndFoundBySession() {
        let labels = HerdrFocus.tabLabels(in: Data(#"{"result":{"tabs":[{"tab_id":"w1:t1","label":"Fix ink"},{"tab_id":"w1:t2","label":" "}]}}"#.utf8))
        XCTAssertEqual(labels, ["w1:t1": "Fix ink"])
        let focus = HerdrFocus(pane: "p", tab: "w1:t1", agents: [.init(pane: "p", session: "s1", tab: "w1:t1")], tabLabels: labels)
        XCTAssertEqual(focus.label(ofSession: "s1"), "Fix ink")
        XCTAssertNil(focus.label(ofSession: "s2"))
    }

    // MARK: The session menu's order and groups

    private func session(_ id: String, used hours: Double, place: Place = .none, now: Date) -> AgentDestination {
        AgentDestination(id: id, name: id, address: .claudeSession(id), lastUsed: now.addingTimeInterval(-hours * 3600), place: place)
    }

    private func repo(_ name: String, at root: String? = nil) -> Place {
        .repository(name: name, root: root ?? "/Users/p/Code/\(name)", worktree: nil, subfolder: nil)
    }

    /// Sessions sent to in the last 4 hours come first, newest send first; a send older than that, or one
    /// that never happened, leaves the order to when the agent last worked.
    func testTheMenuRanksRecentSendsFirstThenTheAgentsLastWork() {
        let now = Date()
        var list = [session("a", used: 1, now: now), session("b", used: 2, now: now), session("c", used: 3, now: now),
                    session("d", used: 4, now: now)]
        list[2].lastSent = now.addingTimeInterval(-600)
        list[3].lastSent = now.addingTimeInterval(-60)
        list[1].lastSent = now.addingTimeInterval(-5 * 3600)
        XCTAssertEqual(SessionMenu.ranked(list, now: now).map(\.id), ["d", "c", "a", "b"])
    }

    /// Five are kept before grouping, the destination takes the last when it is missing, and the rest
    /// are in the project submenus, with the top rows.
    func testTheMenuKeepsFiveThenGroupsThemWithOtherFoldersLast() {
        let now = Date()
        let list = [session("a", used: 1, place: .folder(fromHome: "~/Code"), now: now),
                    session("b", used: 2, place: repo("vignette"), now: now),
                    session("c", used: 3, place: repo("inbox"), now: now),
                    session("d", used: 4, place: repo("vignette"), now: now),
                    session("e", used: 5, place: repo("inbox"), now: now),
                    session("f", used: 6, place: repo("vignette"), now: now),
                    session("g", used: 7, place: repo("inbox"), now: now)]
        let menu = SessionMenu.menu(list, destination: list[6], now: now)
        XCTAssertEqual(menu.top.map(\.header), ["vignette", "inbox", "Other folders"])
        XCTAssertEqual(menu.top.map { $0.rows.map(\.id) }, [["b", "d"], ["c", "g"], ["a"]],
                       "the destination took the fifth row, and the groups follow their first rows")
        XCTAssertEqual(menu.projects.map(\.header), ["vignette", "inbox", "Other folders"],
                       "the submenus follow the headers, Other folders last")
        XCTAssertEqual(menu.projects.map { $0.rows.map(\.id) }, [["b", "d", "f"], ["c", "e", "g"], ["a"]],
                       "each holds every active session of its project, the top rows too, so a project of one has its submenu")
        XCTAssertNil(SessionMenu.menu(list, destination: nil, now: now).top.flatMap(\.rows).first { $0.id == "g" },
                     "a note on the responder forces no row in")
    }

    func testSearchFindsEveryWordInTheTitleTheSecondLineOrTheHeader() {
        let now = Date()
        var tabbed = session("a", used: 1, place: repo("vignette"), now: now)
        tabbed.hostLabel = "Café menu"
        tabbed.goal = "Search the sessions"
        let list = [tabbed,
                    session("b", used: 2, place: repo("inbox"), now: now),
                    session("c", used: 3, place: repo("vignette"), now: now)]
        let groups = SessionMenu.menu(list, destination: nil, now: now).everyone
        func ids(_ query: String) -> [[String]] { SessionMenu.matching(query, in: groups).map { $0.rows.map(\.id) } }
        XCTAssertEqual(ids("CAFE"), [["a"]], "case and accents are ignored")
        XCTAssertEqual(ids("search sessions"), [["a"]], "every word must be found, in any order")
        XCTAssertEqual(ids("inbox"), [["b"]], "the header counts")
        XCTAssertEqual(ids("vignette"), [["a", "c"]], "a header matches all of its rows")
        XCTAssertEqual(ids("  "), [["a", "c"], ["b"]], "no words, no filtering")
        XCTAssertEqual(ids("zzz"), [])
    }

    /// A repository known only by name joins the one checkout of that name; two checkouts with one name
    /// get their parent folder in the header.
    func testRepositoriesJoinByNameAndSameNamesAddTheirParentFolder() {
        let now = Date()
        let list = [session("a", used: 1, place: repo("foo", at: "/Users/p/ever/foo"), now: now),
                    session("b", used: 2, place: .repository(name: "bar", root: nil, worktree: nil, subfolder: nil), now: now),
                    session("c", used: 3, place: repo("bar"), now: now),
                    session("d", used: 4, place: repo("foo", at: "/Users/p/Code/foo"), now: now)]
        let menu = SessionMenu.menu(list, destination: nil, now: now)
        XCTAssertEqual(menu.top.map(\.header), ["ever/foo", "bar", "Code/foo"])
        XCTAssertEqual(menu.top[1].rows.map(\.id), ["b", "c"], "the name-only session joined the one checkout called bar")
    }

    // MARK: What a row says

    private func row(_ session: AgentDestination, among others: [AgentDestination] = [], now: Date = Date()) -> SessionMenu.Row {
        SessionMenu.row(of: session, among: [session] + others, now: now)
    }

    /// The title is the herdr tab's label without its repository prefix, else the session's name. The second
    /// line is the worktree, the branch and the goal, each once, with the session's name when it adds to the
    /// title, and no age.
    func testARowLeadsWithTheTabLabelAndThenSaysWhereAndWhy() {
        let now = Date()
        var s = session("a", used: 1, place: .repository(name: "inbox", root: "/c/inbox", worktree: "map-port", subfolder: "Sources"), now: now)
        s = AgentDestination(id: s.id, name: "Port the map", address: s.address, lastUsed: s.lastUsed, place: s.place, branch: "progress-tab",
                             hostLabel: "Inbox: map port", goal: "Move the map to the plugin")
        let withGoal = row(s, now: now)
        XCTAssertEqual(withGoal.title, "map port", "the repository's prefix goes, whatever its case")
        XCTAssertEqual(withGoal.subtitle, "map-port · progress-tab · Move the map to the plugin")
        XCTAssertEqual(withGoal.tooltip, "map port\nmap-port · progress-tab · Move the map to the plugin\ninbox")

        s.goal = nil
        XCTAssertEqual(row(s, now: now).subtitle, "map-port · progress-tab · Port the map", "with no goal, its name")
        s.hostLabel = "Port the map"
        XCTAssertEqual(row(s, now: now).subtitle, "map-port · progress-tab", "a part that repeats the title is left out")

        var folder = s
        folder.place = .folder(fromHome: "~/Code")
        folder.branch = nil
        folder.goal = "Plan the week"
        XCTAssertEqual(row(folder, now: now).subtitle, "~/Code · Plan the week")
    }

    /// With no tab and no goal, a row is the session's name over its worktree, subfolder, branch and age.
    func testARowWithNoTabOrGoalFallsBackToTheNameAndPlace() {
        let now = Date()
        let s = AgentDestination(id: "t", name: "Codex thread", address: .codexThread(uuid: "t"), lastUsed: now.addingTimeInterval(-7200),
                                 place: .repository(name: "evercars", root: nil, worktree: "Codex worktree", subfolder: "apps/ui"),
                                 branch: "codex/selector")
        let fallback = row(s, now: now)
        XCTAssertEqual(fallback.title, "Codex thread")
        XCTAssertEqual(fallback.subtitle, "Codex worktree · apps/ui · codex/selector · 2 hr ago")
        XCTAssertNil(fallback.badge)
    }

    /// An open question for the person wins over a running turn.
    func testTheBadgeSaysNeedsYouBeforeWorking() {
        let now = Date()
        var s = session("a", used: 1, now: now)
        XCTAssertNil(row(s, now: now).badge)
        s.turn = .waiting
        XCTAssertNil(row(s, now: now).badge, "a drawing unread in the inbox is not the agent waiting for the person")
        s.turn = .busy
        XCTAssertEqual(row(s, now: now).badge, "Working")
        s.needsYou = true
        XCTAssertEqual(row(s, now: now).badge, "Needs you")
    }

    /// Equal titles in one group take the first of tab, worktree and branch that tells all of them apart, else
    /// a number by start; the same title in another group takes none.
    func testEqualTitlesInOneGroupAreToldApart() {
        let now = Date()
        func make(_ id: String, worktree: String?, branch: String?, started: Double, root: String = "/c/inbox") -> AgentDestination {
            AgentDestination(id: id, name: "Fix", address: .claudeSession(id), lastUsed: now, place: .repository(name: "inbox", root: root, worktree: worktree, subfolder: nil),
                             branch: branch, started: now.addingTimeInterval(started))
        }
        let byWorktree = [make("a", worktree: "one", branch: "x", started: 0), make("b", worktree: "two", branch: "x", started: 1)]
        XCTAssertEqual(SessionMenu.menu(byWorktree, destination: nil, now: now).topRows.map(\.title), ["Fix (one)", "Fix (two)"])
        let numbered = [make("a", worktree: nil, branch: nil, started: 5), make("b", worktree: "w", branch: nil, started: 1)]
        XCTAssertEqual(SessionMenu.menu(numbered, destination: nil, now: now).topRows.map(\.title), ["Fix (#2)", "Fix (#1)"])
        let apart = [make("a", worktree: nil, branch: nil, started: 0), make("b", worktree: nil, branch: nil, started: 1, root: "/c/other")]
        XCTAssertEqual(SessionMenu.menu(apart, destination: nil, now: now).topRows.map(\.title), ["Fix", "Fix"])
    }

    // MARK: The inbox mod's store

    func testTheInboxModsGoalAndOpenQuestionsAreReadBySession() throws {
        let store: [String: Any] = [
            "s:one": ["ledger": ["card": ["goal": " Ship it "], "items": []]],
            "s:two": ["ledger": ["items": [["ask": "Which branch?"]]]],
            "s:three": ["ledger": ["card": ["goal": ""], "items": [["ask": ""]]]],
            "other": ["ledger": ["card": ["goal": "x"]]],
        ]
        let found = InboxModStore.entries(in: store)
        XCTAssertEqual(found, ["one": .init(goal: "Ship it", needsYou: false), "two": .init(goal: nil, needsYou: true)])
    }

    /// The store is found by its name's start, the newest file wins, and a missing or unreadable one is no entries.
    func testTheStoreIsFoundByPatternAndAMissingOneIsNoEntries() throws {
        let folder = temporaryFolder()
        XCTAssertTrue(InboxModStore.entries(in: folder).isEmpty)
        try write(#"{"s:old":{"ledger":{"card":{"goal":"Old"}}}}"#, to: folder.appendingPathComponent("inbox_inline-aaa.json"))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -100)],
                                              ofItemAtPath: folder.appendingPathComponent("inbox_inline-aaa.json").path)
        try write(#"{"s:new":{"ledger":{"card":{"goal":"New"}}}}"#, to: folder.appendingPathComponent("inbox_inline-bbb.json"))
        try write(#"{"s:x":{"ledger":{"card":{"goal":"Other mod"}}}}"#, to: folder.appendingPathComponent("session-card_inline-ccc.json"))
        XCTAssertEqual(InboxModStore.entries(in: folder).keys.sorted(), ["new"])
        try write("not json", to: folder.appendingPathComponent("inbox_inline-ddd.json"))
        XCTAssertTrue(InboxModStore.entries(in: folder).isEmpty)
    }

    /// A test launch reads the scratch home's store only.
    func testATestLaunchNeverReadsThePersonsStore() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let person = base.appendingPathComponent("person").path
        let scratch = base.appendingPathComponent("scratch").path
        for home in [person, scratch] {
            try FileManager.default.createDirectory(atPath: home + "/.claude", withIntermediateDirectories: true)
        }
        let test = ["VIGNETTE_SETTINGS": "/tmp/s.json"]
        XCTAssertNil(InboxModStore.folder(home: person, environment: test, personHome: person))
        XCTAssertNil(InboxModStore.folder(home: scratch, environment: test.merging(["CLAUDE_CONFIG_DIR": person + "/.claude"]) { $1 }, personHome: person))
        XCTAssertEqual(InboxModStore.folder(home: scratch, environment: test, personHome: person)?.path, scratch + "/.claude/plugins/store")
        XCTAssertEqual(InboxModStore.folder(home: person, environment: [:], personHome: person)?.path, person + "/.claude/plugins/store")
    }

    // MARK: Listing

    private func thread(_ id: String, used: TimeInterval) -> AgentDestination {
        AgentDestination(id: id, name: id, address: .codexThread(uuid: id), lastUsed: Date(timeIntervalSince1970: used))
    }

    private func claudeSession(_ id: String, used: TimeInterval) -> AgentDestination {
        AgentDestination(id: id, name: id, address: .claudeSession(id), lastUsed: Date(timeIntervalSince1970: used))
    }

    /// Starts one listing, collecting what it delivers, and an expectation met by the first delivery
    /// `done` accepts.
    @MainActor
    private func collect(_ listing: SessionListing, shown: (client: AgentClient, id: String)? = nil,
                         until done: @escaping (DestinationChoice.Candidates) -> Bool) -> (Delivered, XCTestExpectation) {
        let delivered = Delivered()
        let finished = expectation(description: "the listing delivers")
        finished.assertForOverFulfill = false
        listing.list(shown: shown) { candidates in
            delivered.all.append(candidates)
            if done(candidates) { finished.fulfill() }
        }
        return (delivered, finished)
    }

    /// The editor opens on Codex's kept threads at once, and every client is still asked afresh, so
    /// a thread started since the list was kept still arrives.
    @MainActor
    func testAKeptListAnswersAtOnceAndEveryClientIsAskedAfresh() async throws {
        let codex = ListedSessions(.codex, keepsList: true, sessions: [thread("t1", used: 200)])
        let claude = ListedSessions(.claude, keepsList: false, sessions: [claudeSession("mew", used: 100)])
        let listing = SessionListing(connections: [.codex: codex, .claude: claude], readHerdr: { nil })
        let (_, primed) = collect(listing) { $0.complete && $0.fresh }
        await fulfillment(of: [primed], timeout: 5)
        let asked = codex.plain

        let (delivered, fresh) = collect(listing) { $0.complete && $0.fresh }
        XCTAssertEqual(delivered.all.count, 1, "the kept list answers inside the call")
        XCTAssertEqual(delivered.all.first?.destinations.map(\.id), ["t1"])
        XCTAssertEqual(delivered.all.first?.complete, false, "Claude Code's list is never kept")
        XCTAssertEqual(delivered.all.first?.fresh, false)
        await fulfillment(of: [fresh], timeout: 5)
        XCTAssertEqual(delivered.all.last?.destinations.map(\.id), ["t1", "mew"])
        XCTAssertEqual(codex.plain, asked + 1, "a kept list is still asked afresh")
        withExtendedLifetime(listing) {}
    }

    @MainActor
    func testTheSessionsVignetteCanStartNeverHoldTheListBackAndLeaveOutARunningProject() async throws {
        var busy = claudeSession("mew", used: 100)
        busy.folder = "/busy"
        let claude = ListedSessions(.claude, keepsList: false, sessions: [busy])
        let found = Date()
        let rows = StartableSessions.rows(folder: "/busy", last: nil, lastUsed: found, found: .init(place: .none, branch: nil))
            + StartableSessions.rows(folder: "/site", last: nil, lastUsed: found, found: .init(place: .none, branch: nil))
        let gate = DispatchSemaphore(value: 0)
        let listing = SessionListing(connections: [.claude: claude], readHerdr: { nil }, startable: { gate.wait(); return rows })
        let fresh = expectation(description: "fresh without the sessions to start")
        let offered = expectation(description: "the sessions to start arrive")
        fresh.assertForOverFulfill = false
        offered.assertForOverFulfill = false
        listing.list { candidates in
            if candidates.complete && candidates.fresh && candidates.startable.isEmpty { fresh.fulfill() }
            if !candidates.startable.isEmpty {
                XCTAssertEqual(candidates.startable.map(\.id), [SessionStart.newRowID(folder: "/site")])
                offered.fulfill()
            }
        }
        await fulfillment(of: [fresh], timeout: 5)
        gate.signal()
        await fulfillment(of: [offered], timeout: 5)
        withExtendedLifetime(listing) {}
    }

    /// An editor opening while a refresh is on its way waits for that answer rather than starting a
    /// second `codex app-server`, and the answer is kept before the waiters hear it.
    @MainActor
    func testASecondAskJoinsTheOneOnItsWay() async throws {
        let codex = ListedSessions(.codex, keepsList: true, sessions: [thread("t1", used: 200)])
        let gate = DispatchSemaphore(value: 0)
        codex.gate = gate
        let listing = SessionListing(connections: [.codex: codex], readHerdr: { nil })
        listing.refreshKeptLists()
        let delivered = Delivered(), again = Delivered()
        let answered = expectation(description: "the joined ask answers")
        listing.list { candidates in
            delivered.all.append(candidates)
            guard candidates.fresh else { return }
            XCTAssertEqual(codex.plain, 1, "the listing joined the refresh's ask")
            codex.gate = nil
            listing.list { again.all.append($0) }
            XCTAssertEqual(again.all.first?.destinations.map(\.id), ["t1"], "kept before the waiters heard it")
            XCTAssertEqual(again.all.first?.fresh, false)
            answered.fulfill()
        }
        XCTAssertTrue(delivered.all.isEmpty, "nothing is kept yet")
        gate.signal()
        await fulfillment(of: [answered], timeout: 5)
        XCTAssertEqual(delivered.all.last?.destinations.map(\.id), ["t1"])

        let settled = expectation(description: "the second listing answers afresh")
        settled.assertForOverFulfill = false
        listing.list { if $0.fresh { settled.fulfill() } }
        await fulfillment(of: [settled], timeout: 5)
        withExtendedLifetime(listing) {}
    }

    /// The thread the Codex app shows is found for that one editor. Its ask does not wait on a plain
    /// one, and an old thread it finds never joins the kept list the next editor opens on.
    @MainActor
    func testAnAskIncludingAShownThreadRunsAloneAndIsNotKept() async throws {
        let codex = ListedSessions(.codex, keepsList: true, sessions: [thread("t1", used: 200)], extra: thread("old", used: 1))
        let gate = DispatchSemaphore(value: 0)
        codex.gate = gate
        let listing = SessionListing(connections: [.codex: codex], readHerdr: { nil })
        listing.refreshKeptLists()
        let (shown, shownAnswered) = collect(listing, shown: (.codex, "old")) { $0.fresh }
        await fulfillment(of: [shownAnswered], timeout: 5)
        XCTAssertEqual(codex.including, 1, "it did not join the plain ask on its way")
        XCTAssertEqual(shown.all.last?.destinations.map(\.id), ["t1", "old"])

        let (next, nextAnswered) = collect(listing) { $0.fresh }
        XCTAssertFalse(next.all.contains { $0.destinations.contains { $0.id == "old" } }, "the shown thread was not kept")
        gate.signal()
        codex.gate = nil
        await fulfillment(of: [nextAnswered], timeout: 5)
        XCTAssertEqual(next.all.last?.destinations.map(\.id), ["t1"])
        let (later, laterAnswered) = collect(listing) { $0.fresh }
        XCTAssertEqual(later.all.first?.destinations.map(\.id), ["t1"])
        await fulfillment(of: [laterAnswered], timeout: 5)
        withExtendedLifetime(listing) {}
    }

    /// herdr's focus comes with Claude Code's answer, so the target settles on the focused session
    /// then, before a complete list could settle it on the Codex thread used last, and the focus
    /// stays on every later answer of that listing. herdr runs only beside a Claude Code list that
    /// has sessions, never on a refresh.
    @MainActor
    func testHerdrsFocusDecidesThePickWithClaudeCodesFirstAnswer() async throws {
        let codex = ListedSessions(.codex, keepsList: true, sessions: [thread("t1", used: 200)])
        let claude = ListedSessions(.claude, keepsList: false, sessions: [claudeSession("mew", used: 100)])
        let focus = HerdrFocus(pane: "p", tab: "t", agents: [.init(pane: "p", session: "mew", tab: "t")])
        let reads = HerdrReads(focus)
        let listing = SessionListing(connections: [.codex: codex, .claude: claude], readHerdr: { reads.read() })
        let (_, primed) = collect(listing) { $0.complete && $0.fresh }
        await fulfillment(of: [primed], timeout: 5)
        let readsBefore = reads.count

        let gate = DispatchSemaphore(value: 0)
        codex.gate = gate
        let delivered = Delivered()
        let claudeAnswered = expectation(description: "Claude Code answers")
        let allFresh = expectation(description: "Codex answers afresh")
        listing.list { candidates in
            delivered.all.append(candidates)
            if candidates.complete && !candidates.fresh { claudeAnswered.fulfill() }
            if candidates.fresh { allFresh.fulfill() }
        }
        XCTAssertEqual(delivered.all.count, 1)
        XCTAssertFalse(delivered.all.first.map { DestinationChoice.choose($0, for: .send(cameFrom: nil)).decided } ?? true,
                       "the kept threads alone decide nothing: Claude Code has not answered")
        await fulfillment(of: [claudeAnswered], timeout: 5)
        // Every delivery from the first that holds Claude Code's sessions carries the focus and
        // picks the focused session, not the Codex thread used last.
        func checkFromClaudesAnswer(_ when: String) {
            guard let first = delivered.all.firstIndex(where: { $0.destinations.contains { $0.id == "mew" } }) else {
                return XCTFail("Claude Code answered")
            }
            for candidates in delivered.all[first...] {
                XCTAssertEqual(candidates.herdr, focus, "the focus comes with Claude Code's answer, \(when)")
                let answer = DestinationChoice.choose(candidates, for: .send(cameFrom: nil))
                XCTAssertTrue(answer.decided)
                XCTAssertEqual(answer.pick?.id, "mew", when)
                XCTAssertEqual(answer.list.first { $0.id == "mew" }?.focus, .pane, when)
            }
        }
        checkFromClaudesAnswer("before Codex answers afresh")

        gate.signal()
        await fulfillment(of: [allFresh], timeout: 5)
        checkFromClaudesAnswer("after Codex answers afresh")
        XCTAssertEqual(reads.count, readsBefore + 1, "herdr is read once, in Claude Code's job")

        codex.gate = nil
        let claudeAsked = claude.plain
        let codexRefreshed = expectation(description: "the refresh asks Codex")
        let claudeRefreshed = expectation(description: "the refresh asks Claude Code")
        claudeRefreshed.isInverted = true
        codex.onAsk = { codexRefreshed.fulfill() }
        claude.onAsk = { claudeRefreshed.fulfill() }
        listing.refreshKeptLists()
        await fulfillment(of: [codexRefreshed, claudeRefreshed], timeout: 0.5)
        codex.onAsk = nil
        claude.onAsk = nil
        XCTAssertEqual(claude.plain, claudeAsked, "a refresh does not ask Claude Code")
        XCTAssertEqual(reads.count, readsBefore + 1, "a refresh never reads herdr")

        let (_, listed) = collect(listing) { $0.complete && $0.fresh }
        await fulfillment(of: [listed], timeout: 5)
        XCTAssertEqual(reads.count, readsBefore + 2, "a listing's Claude Code job reads herdr")

        claude.sessions = []
        let (_, empty) = collect(listing) { $0.complete && $0.fresh }
        await fulfillment(of: [empty], timeout: 5)
        XCTAssertEqual(reads.count, readsBefore + 2, "no Claude Code session, no herdr")
        withExtendedLifetime(listing) {}
    }
}

@MainActor
private final class Delivered {
    var all: [DestinationChoice.Candidates] = []
}

/// An agent client whose listing a test controls: what it lists, whether a plain listing is held,
/// and how often each kind of listing was asked for.
private final class ListedSessions: AgentConnection, @unchecked Sendable {
    let client: AgentClient
    let keepsList: Bool
    private let lock = NSLock()
    private var listed: [AgentDestination]
    private let extra: AgentDestination?
    private var held: DispatchSemaphore?
    private var asked: (@Sendable () -> Void)?
    private var plainCount = 0, includingCount = 0

    init(_ client: AgentClient, keepsList: Bool, sessions: [AgentDestination], extra: AgentDestination? = nil) {
        self.client = client
        self.keepsList = keepsList
        self.listed = sessions
        self.extra = extra
    }

    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    var sessions: [AgentDestination] {
        get { locked { listed } }
        set { locked { listed = newValue } }
    }
    /// Holds every plain listing until signalled.
    var gate: DispatchSemaphore? {
        get { locked { held } }
        set { locked { held = newValue } }
    }
    /// Runs when a plain listing starts, off the main thread.
    var onAsk: (@Sendable () -> Void)? {
        get { locked { asked } }
        set { locked { asked = newValue } }
    }
    var plain: Int { locked { plainCount } }
    var including: Int { locked { includingCount } }

    func destinations() -> [AgentDestination] {
        let (gate, onAsk) = locked { () -> (DispatchSemaphore?, (@Sendable () -> Void)?) in plainCount += 1; return (held, asked) }
        onAsk?()
        _ = gate?.wait(timeout: .now() + 5)
        return sessions
    }

    func destinations(including id: String) -> [AgentDestination] {
        locked {
            includingCount += 1
            return listed + (extra.map { $0.id == id ? [$0] : [] } ?? [])
        }
    }

    func submit(_ line: String, to destination: AgentDestination) -> SubmissionOutcome { .accepted(detail: "") }
}

/// A herdr reading that answers `focus` and counts how often it ran.
private final class HerdrReads: @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    let focus: HerdrFocus?

    init(_ focus: HerdrFocus?) { self.focus = focus }

    func read() -> HerdrFocus? {
        lock.lock(); reads += 1; lock.unlock()
        return focus
    }

    var count: Int { lock.lock(); defer { lock.unlock() }; return reads }
}
