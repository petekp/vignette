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

    /// A connection over inboxes in a temporary folder, with herdr answering `panes` when given.
    /// Every process id in `running` is taken to be alive.
    private func claude(inboxes root: URL, running: Set<Int32> = [101, 102], panes: String? = nil,
                        now: Date = Date()) -> (ClaudeCodeConnection, () -> [[String]]) {
        let calls = Recorder()
        var connection = ClaudeCodeConnection()
        connection.inboxes = root
        connection.transcripts = URL(fileURLWithPath: "/nonexistent/projects")
        connection.isRunning = { running.contains($0) }
        connection.now = { now }
        connection.herdr = { panes == nil ? nil : "/bin/herdr" }
        connection.run = { _, arguments, _ in
            calls.record(arguments)
            return panes.map { (0, $0, false) }
        }
        return (connection, { calls.all() })
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

    /// Collects argv across threads; the connection's runner is `@Sendable`.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [[String]] = []
        func record(_ arguments: [String]) { lock.lock(); calls.append(arguments); lock.unlock() }
        func all() -> [[String]] { lock.lock(); defer { lock.unlock() }; return calls }
    }

    // MARK: Claude Code, by session rather than by pane

    func testAnswerThatIsNotAPaneListIsNoAgents() {
        XCTAssertEqual(ClaudeCodeConnection.agents(in: Data("not json".utf8)), [])
        XCTAssertEqual(ClaudeCodeConnection.agents(in: Data(#"{"error":{"code":"no_server"}}"#.utf8)), [])
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
        let (connection, _) = claude(inboxes: root, running: [101, 102, 1010], now: now)
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

        var (connection, _) = claude(inboxes: inboxes)
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
        let root = temporaryFolder()
        XCTAssertNoThrow(try inbox(root, pid: 101, session: session))
        func focus(_ pane: String) -> AgentDestination.Focus? {
            let (connection, _) = claude(inboxes: root, panes: paneList(session: session, focused: pane))
            return connection.destinations().first?.focus
        }
        XCTAssertEqual(focus("w9:p6"), .pane)
        XCTAssertEqual(focus("w9:pC"), .tab, "the browser beside the session")
        XCTAssertNil(focus("w9:pA"), "another session's pane, even one herdr cannot name")
        XCTAssertNil(focus("w9:pB"), "a Codex pane")

        let listed = ClaudeCodeConnection.agents(in: Data(paneList(session: session).utf8))
        let destinations = listed.compactMap { agent in
            agent.session.map { ClaudeCodeConnection.destination(session: $0, cwd: "", transcript: .init()) }
        }
        func marked(_ extra: ClaudeCodeConnection.HerdrAgent, focus: String) -> [AgentDestination.Focus?] {
            ClaudeCodeConnection.markFocus(destinations, agents: listed + [extra], focus: (focus, "w9:t1")).map(\.focus)
        }
        let second = ClaudeCodeConnection.HerdrAgent(pane: "w9:pD", session: "second", tab: "w9:t1")
        XCTAssertEqual(marked(second, focus: "w9:pC"), [nil], "two sessions beside the browser")
        let codex = ClaudeCodeConnection.HerdrAgent(pane: "w9:pE", tab: "w9:t1")
        XCTAssertEqual(marked(codex, focus: "w9:pE"), [nil], "you are talking to the Codex beside it")

        let old = AgentDestination(id: "1", name: "a", address: .claudeSession("1"), lastUsed: Date(timeIntervalSince1970: 100))
        let new = AgentDestination(id: "2", name: "b", address: .codexThread(uuid: "2"), lastUsed: Date(timeIntervalSince1970: 200))
        var beside = old
        beside.focus = .tab
        XCTAssertEqual(AgentDestination.defaultTarget(in: [new, beside])?.id, "1", "focus comes before the session used last")
        XCTAssertEqual(AgentDestination.defaultTarget(in: [new, old])?.id, "2")
        XCTAssertNil(AgentDestination.defaultTarget(in: []))
    }

    /// Coming from the Codex app, Send starts on the thread it shows, whatever herdr's focus says,
    /// since herdr keeps a focused pane while its terminal is behind (observed 2026-09-25).
    func testSendStartsOnTheThreadTheCodexAppShows() {
        var focused = AgentDestination(id: "c", name: "vignette", address: .claudeSession("c"))
        focused.focus = .pane
        let recent = AgentDestination(id: "t1", name: "Review codebase", address: .codexThread(uuid: "t1"))
        let shown = AgentDestination(id: "t2", name: "Build showroom MCP App PoC", address: .codexThread(uuid: "t2"))
        let list = [focused, recent, shown]
        func target(_ id: String?) -> String? {
            AgentDestination.defaultTarget(in: AgentDestination.cameFrom(.codex, shown: id, in: list))?.id
        }
        XCTAssertEqual(target("t2"), "t2")
        XCTAssertEqual(target(nil), "t1", "an app showing no thread gives the Codex thread used last")
        XCTAssertEqual(target("t9"), "t1", "a thread the fresh list lacks")
        XCTAssertEqual(AgentDestination.cameFrom(.codex, shown: nil, in: [focused]).map(\.focus), [nil],
                       "no Codex thread listed: herdr's focus still says nothing")
        XCTAssertEqual(AgentDestination.cameFrom(.codex, shown: "t9", in: list, fresh: false).map(\.focus),
                       [nil, nil, nil], "a kept list may predate the shown thread, so the fresh list decides")
        XCTAssertEqual(AgentDestination.cameFrom(.codex, shown: "t2", in: list, fresh: false)
            .first { $0.focus == .app }?.id, "t2", "a thread the kept list has settles at once")
    }

    /// A thread is named as the Codex app names it: the app's rule, read from its bundle and checked
    /// against its own titles for 144 threads on 2026-09-25. A first message is plain text with its lines joined, and an IDE's is its request.
    func testAThreadIsNamedAsTheCodexAppNamesIt() {
        func name(_ name: String?, _ preview: String) -> String {
            CodexConnection.name(of: AppServer.Thread(id: "01a0ab02-0000", name: name, cwd: "/x", preview: preview))
        }
        XCTAssertEqual(name("Implement Plan: <task>Add a toolbar</task>", ""), "Implement Plan: Add a toolbar",
                       "a tag is taken out of a name")
        XCTAssertEqual(name(nil, "Review [notes.md](docs/notes.md).\n\n---\n\n### Then\n\n- fix **the** `outline`"),
                       "Review notes.md. Then fix the outline")
        XCTAssertEqual(name(nil, "# Context from my IDE setup:\n\n## Active file: a.swift\n\n## My request for Codex:\nMake it faster"),
                       "Make it faster")
        XCTAssertEqual(name(nil, "<environment_context>\n  <cwd>/Users/p/x</cwd>\n</environment_context>"),
                       "<environment_context> /Users/p/x </environment_context>",
                       "a tag's name has no underscore, so this one is text")
        let long = String(repeating: "word ", count: 30)
        XCTAssertEqual(name(nil, long), String(String(repeating: "word ", count: 16).dropLast()) + "…",
                       "cut to 79 characters and an ellipsis, without the space before it")
        XCTAssertEqual(name("", " \n "), "Codex 01a0ab02")
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

    /// The thread the Codex app shows joins the threads used last when it is older than them, and
    /// only when the store has it.
    func testTheShownThreadJoinsTheListingWhateverItsAge() {
        let listing = #"{"id":2,"result":{"data":[{"id":"a","name":"Recent","cwd":"/x","recencyAt":300}]}}"#
        let read = #"{"id":3,"result":{"thread":{"id":"old","name":"Investigate appointments","cwd":"/y","recencyAt":1}}}"#
        var connection = CodexConnection()
        connection.binary = { "/bin/codex" }
        connection.converse = { _, _, _ in [listing, read] }
        XCTAssertEqual(connection.destinations(including: "old").map(\.id), ["a", "old"])
        XCTAssertEqual(connection.destinations().map(\.id), ["a"], "without an id, no read is used")
        let refused = #"{"id":3,"error":{"code":-32600,"message":"thread not loaded: old"}}"#
        connection.converse = { _, _, _ in [listing, refused] }
        XCTAssertEqual(connection.destinations(including: "old").map(\.id), ["a"])
        connection.converse = { _, _, _ in [listing, #"{"id":3,"result":{"thread":{"id":"a","cwd":"/x"}}}"#] }
        XCTAssertEqual(connection.destinations(including: "a").map(\.id), ["a"], "a listed thread is listed once")
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
        XCTAssertEqual(AgentDestination.menu(list, target: list[0], now: now).map(\.id), ["a", "b", "d", "e", "f"],
                       "a Codex thread from yesterday is left out")
        XCTAssertEqual(AgentDestination.menu(list, target: list[6], now: now).map(\.id), ["a", "b", "d", "e", "g"])
        XCTAssertEqual(AgentDestination.menu(list, target: list[2], now: now).map(\.id), ["a", "b", "d", "e", "c"],
                       "the target is shown even when it is not active")
    }

    /// Send lists the session used last first, and one with no known time after all the others.
    func testSessionsAreListedNewestFirst() {
        let old = AgentDestination(id: "1", name: "a", address: .claudeSession("1"), lastUsed: Date(timeIntervalSince1970: 100))
        let new = AgentDestination(id: "2", name: "b", address: .codexThread(uuid: "2"), lastUsed: Date(timeIntervalSince1970: 200))
        let unknown = AgentDestination(id: "3", name: "0", address: .claudeSession("3"))
        XCTAssertEqual([unknown, old, new].sorted(by: AgentDestination.newestFirst).map(\.id), ["2", "1", "3"])
    }

    /// The request lands in the inbox holding the session, and in no other.
    func testTheRequestGoesToTheInboxHoldingTheSession() throws {
        let root = temporaryFolder()
        let folder = try inbox(root, pid: 102, session: session)
        try inbox(root, pid: 101, session: "0f0f0f0f-0000-4000-8000-000000000000")
        let (connection, calls) = claude(inboxes: root)
        let destination = AgentDestination(id: session, name: "x", address: .claudeSession(session))
        guard case .accepted(let detail) = connection.submit("look here [From Vignette]", to: destination) else {
            return XCTFail("a session with a live inbox is submittable")
        }
        XCTAssertTrue(detail.contains("inbox=102"))
        let lines = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".line") }
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent(lines[0]), encoding: .utf8),
                       "look here [From Vignette]\n")
        XCTAssertEqual(calls(), [], "herdr sends nothing")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("101").path).filter { $0.hasSuffix(".line") }, [])
    }

    /// A session in no inbox is an error, never another session's inbox. When the process that ran
    /// it has since run `/clear` or `/resume`, the card says so.
    func testASessionInNoInboxIsAnErrorAndNeverAnother() throws {
        let root = temporaryFolder()
        let folder = try inbox(root, pid: 101, session: "0f0f0f0f-0000-4000-8000-000000000000")
        let (connection, _) = claude(inboxes: root)
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

    // MARK: Codex, by thread UUID

    func testTheQueueCallIsOneArgvElementPerPart() {
        let thread = "01a0c176-bfab-7662-9ffb-a30cc3490835"
        XCTAssertEqual(CodexConnection.arguments(thread: thread, message: "look at \"a b.png\""),
                       ["queue", "--thread", thread, "--message", "look at \"a b.png\""])
    }

    func testAThreadTheServerDoesNotHaveIsTheDestinationHavingChanged() {
        // What codex queue 0.159.2 prints for a thread id no thread has (2026-10-01).
        let deleted = "Error: failed to queue session message: thread/queue/add failed: failed to read thread: invalid thread-store request: no rollout found for thread id 01a0fa10-0000-7000-8000-00000000dead (code -32603)"
        guard case .destinationChanged(_, let reason) = CodexConnection.failure(output: deleted, thread: "t") else {
            return XCTFail("a missing thread is not a retryable failure")
        }
        XCTAssertEqual(reason, "Codex can't find this thread. You can send it to another one.")
        guard case .destinationChanged = CodexConnection.failure(output: "failed to connect to ws://127.0.0.1:9", thread: "t") else {
            return XCTFail("an engine that cannot be reached is not a retryable failure")
        }
        guard case .notSubmitted = CodexConnection.failure(output: "Error: invalid message", thread: "t") else {
            return XCTFail("anything else definitely did not arrive")
        }
    }

    /// `codex queue` answers the same whether or not an engine has the thread, so a send to a thread
    /// nobody has open says it waits, and the lock an engine holds on a loaded thread is what tells.
    func testASendToAThreadNoEngineHasLoadedIsQueued() throws {
        let thread = "01a0c176-bfab-7662-9ffb-a30cc3490835"
        var connection = CodexConnection()
        connection.binary = { "/bin/codex" }
        connection.run = { _, _, _ in (0, "Queued message 7 for thread \(thread).", false) }
        let destination = AgentDestination(id: thread, name: "t", address: .codexThread(uuid: thread))
        connection.isLoaded = { _ in false }
        guard case .queued(_, let reason) = connection.submit("look", to: destination) else {
            return XCTFail("a thread no engine has loaded only stores the message")
        }
        XCTAssertEqual(reason, "Codex reads it when you open this thread.")
        connection.isLoaded = { _ in true }
        guard case .accepted = connection.submit("look", to: destination) else { return XCTFail("a loaded thread takes it") }

        let home = temporaryFolder()
        XCTAssertFalse(CodexConnection.isLoaded(thread, codexHome: home))
        let locks = home.appendingPathComponent("thread-writer-locks")
        try FileManager.default.createDirectory(at: locks, withIntermediateDirectories: true)
        try Data().write(to: locks.appendingPathComponent("\(thread).lock"))
        XCTAssertTrue(CodexConnection.isLoaded(thread, codexHome: home))
    }

    // MARK: Codex discovery

    /// Every thread the listing reports becomes a destination, named, with its own project and
    /// the time it was last used, and addressed by its UUID alone.
    func testEveryListedThreadBecomesADestinationWithItsProject() {
        let answer = """
        {"id":2,"result":{"data":[\
        {"id":"01a0c14e-e536-7580-866c-c50622cecd9b","name":"Explore agent screenshot loop","cwd":"/Users/p/Code/vignette","status":{"type":"idle"}},\
        {"id":"01a0c28f-7c24-7a93-82e4-a7906de82cf4","name":"Open drawing","cwd":"/tmp/loop-test","recencyAt":1789970783,"status":{"type":"idle"}},\
        {"id":"01a0ab02-91c0-7000-8000-000000000000","name":null,"cwd":"/tmp/x","preview":"## Look at this\\nthe rest","status":{"type":"idle"}}]}}
        """
        var connection = CodexConnection()
        connection.binary = { "/bin/codex" }
        connection.converse = { _, _, _ in [answer] }

        let found = connection.destinations()
        XCTAssertEqual(found.map(\.name), ["Explore agent screenshot loop", "Open drawing", "Look at this the rest"],
                       "a thread with no name reads as its first message, its lines joined")
        XCTAssertEqual(found[1].detail, "loop-test", "the project is the session's own folder")
        XCTAssertEqual(found[1].address, .codexThread(uuid: "01a0c28f-7c24-7a93-82e4-a7906de82cf4"))
        XCTAssertEqual(found[1].lastUsed, Date(timeIntervalSince1970: 1789970783))
    }

    /// Discovery starts an app-server of its own. `thread/list` reads the store on disk, so that
    /// server sees the same sessions the desktop app's does.
    func testDiscoveryAsksAnAppServerItStarts() {
        var argv: [String] = []
        var connection = CodexConnection()
        connection.binary = { "/bin/codex" }
        connection.converse = { _, arguments, _ in argv = arguments; return [] }
        _ = connection.destinations()
        XCTAssertEqual(argv, ["app-server"])
    }

    /// No Codex on the machine is not an error: there is nothing to discover and nothing is spawned.
    func testWithNoCodexThereAreNoDestinationsAndNothingIsSpawned() {
        var asked = false
        var connection = CodexConnection()
        connection.binary = { nil }
        connection.converse = { _, _, _ in asked = true; return [] }

        XCTAssertTrue(connection.destinations().isEmpty)
        XCTAssertFalse(asked, "nothing is spawned when there is no binary to spawn")
    }
}
