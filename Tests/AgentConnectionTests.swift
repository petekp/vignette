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

    private static let project = "/Users/p/Code/vignette"
    private static func claude(_ id: String, name: String = "x", detail: String = project) -> AgentDestination {
        AgentDestination(id: id, name: name, detail: detail, address: .claudeSession(id))
    }

    private func note(_ list: [AgentDestination], _ pick: DestinationChoice.LiveNotePick, complete: Bool = true,
                      fresh: Bool = true, herdr: HerdrFocus? = nil) -> DestinationChoice.Answer {
        DestinationChoice.choose(.init(destinations: list, complete: complete, fresh: fresh, herdr: herdr), for: .liveNote(pick))
    }

    /// A live ink note starts on the session it was sent to last, found again by its id or, after
    /// `/clear` gave it a new id, as the one session of its agent in its project; else the responder.
    func testALiveNoteStartsOnTheSessionItWasSentToLast() {
        let a = Self.claude("a"), b = Self.claude("b"), c = Self.claude("c")
        let thread = AgentDestination(id: "t", name: "x", detail: Self.project, address: .codexThread(uuid: "t"))
        let renamed = Self.claude("a", name: "Renamed since")
        XCTAssertEqual(note([b, renamed], .remembered(a)).pick, renamed, "found by id, as the list has it now")
        XCTAssertEqual(note([b, a], .remembered(a)).pick?.id, "a", "the id comes before the project")
        XCTAssertEqual(note([b], .remembered(a)).pick?.id, "b", "after /clear, the one session in its project")
        XCTAssertNil(note([Self.claude("e", detail: "/Users/p/Code/other")], .remembered(a)).pick,
                     "the one session of its agent in another project is not it")
        XCTAssertEqual(note([Self.claude("e", detail: "/Users/p/Code/other"), b], .remembered(a)).pick?.id, "b",
                       "after /clear, a session in another project does not count against the one in its own")
        XCTAssertNil(note([b, c], .remembered(a)).pick, "two sessions in its project: neither is it")
        XCTAssertNil(note([thread], .remembered(a)).pick, "another agent in the same project is not it")
        XCTAssertNil(note([Self.claude("e", detail: "")], .remembered(Self.claude("d", detail: ""))).pick,
                     "no project: never matched by the agent's name")
        XCTAssertNil(note([a, b], .remembered(nil)).pick, "the responder stays, not the session used last")
        XCTAssertNil(note([], .remembered(a)).pick, "an empty list starts on the responder")

        XCTAssertEqual(note([a], .remembered(a), complete: false, fresh: false).pick?.id, "a",
                       "a kept partial list that has the session starts on it at once, without waiting for the rest")
        XCTAssertNil(note([thread], .remembered(a), complete: false, fresh: false).pick,
                     "a kept partial list without the session starts on the responder for now")
        XCTAssertEqual(note([thread, a], .remembered(a)).pick?.id, "a", "and a later answer brings the session back")
    }

    /// A session the person picked on the note stays while it is listed, and drops to the responder
    /// when it is not. It is matched by id alone.
    func testALiveNoteKeepsAHandPickWhileItIsListed() {
        let a = Self.claude("a"), b = Self.claude("b"), c = Self.claude("c")
        let stale = Self.claude("a", name: "Named before")
        XCTAssertEqual(note([Self.claude("a", name: "Named since"), b], .byHand(stale)).pick, stale,
                       "a listed hand pick is not replaced by the list's copy, so the chip does not change under the person")
        XCTAssertEqual(note([a], .byHand(a), complete: false, fresh: false).pick?.id, "a",
                       "a kept partial list keeps a listed hand pick at once")
        XCTAssertNil(note([b, c], .byHand(a)).pick, "a hand pick gone from the list drops to the responder")
        XCTAssertNil(note([], .byHand(a)).pick, "an empty list drops a hand pick too")
        XCTAssertNil(note([b], .byHand(a)).pick, "a hand pick is not found again after /clear")
        XCTAssertNil(note([a, b], .byHand(nil)).pick, "a hand-picked responder stays")
    }

    /// A live ink note reads neither herdr's focus nor marks its list, although Send, given the same
    /// candidates, starts on the focused session.
    func testALiveNoteIgnoresHerdrsFocus() {
        let a = Self.claude("a"), b = Self.claude("b")
        let herdr = HerdrFocus(pane: "p", tab: "t", agents: [.init(pane: "p", session: "b", tab: "t")])
        let send = DestinationChoice.choose(.init(destinations: [a, b], complete: true, fresh: true, herdr: herdr),
                                            for: .send(cameFrom: nil))
        XCTAssertEqual(send.pick?.id, "b", "Send starts on herdr's focus")
        XCTAssertNil(note([a, b], .remembered(nil), herdr: herdr).pick, "the note keeps the responder")
        XCTAssertEqual(note([a, b], .remembered(a), herdr: herdr).pick?.id, "a", "and the session it was sent to")
        XCTAssertEqual(note([a, b], .remembered(nil), herdr: herdr).list.map(\.focus), [nil, nil],
                       "the note's list carries no focus")
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
        XCTAssertEqual(DestinationChoice.menu(list, target: list[0], now: now).map(\.id), ["a", "b", "d", "e", "f"],
                       "a Codex thread from yesterday is left out")
        XCTAssertEqual(DestinationChoice.menu(list, target: list[6], now: now).map(\.id), ["a", "b", "d", "e", "g"])
        XCTAssertEqual(DestinationChoice.menu(list, target: list[2], now: now).map(\.id), ["a", "b", "d", "e", "c"],
                       "the target is shown even when it is not active")
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
