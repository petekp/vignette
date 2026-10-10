import XCTest

final class SendContextTests: XCTestCase {
    private func temporaryFolder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("send-context-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // MARK: The text in a picture

    func testPhrasesFollowTheSpikesRule() {
        XCTAssertEqual(SendContext.phrases(ofLine: "Live Ink: Session-Picker"),
                       ["live ink session picker", "ink session", "session picker", "live ink session", "ink session picker"])
        XCTAssertEqual(SendContext.phrases(ofLine: "go to"), [])

        // A line cut off at the edge loses its last word, whichever ellipsis it ends with.
        for line in ["Session picker for live…", "Session picker for live...", "Session picker for live…  "] {
            XCTAssertEqual(SendContext.phrases(ofLine: line), ["session picker for", "session picker", "picker for"], line)
        }
        XCTAssertTrue(SendContext.phrases(ofLine: "Session… picker for live").contains("session picker for live"))

        // The whole line from 6 characters.
        XCTAssertEqual(SendContext.phrases(ofLine: "abc de"), ["abc de"])
        XCTAssertEqual(SendContext.phrases(ofLine: "ab cd"), [])
        // Two words from 10.
        XCTAssertEqual(SendContext.phrases(ofLine: "abcd efghi x"), ["abcd efghi x", "abcd efghi"])
        XCTAssertEqual(SendContext.phrases(ofLine: "abcd efgh x"), ["abcd efgh x"])
        // Three words from 12.
        XCTAssertEqual(SendContext.phrases(ofLine: "ab cdef ghij k"), ["ab cdef ghij k", "ab cdef ghij"])
        XCTAssertEqual(SendContext.phrases(ofLine: "ab cde ghij k"), ["ab cde ghij k"])
    }

    func testHeldPhrasesCrossPunctuationButNotLinesOrWords() {
        func holds(_ text: String) -> Bool { SendContext.PhraseIndex(["live ink"]).held(in: Data(text.utf8)) == ["live ink"] }
        XCTAssertTrue(holds("the live-ink note"))
        XCTAssertTrue(holds("Live Ink: Session"))
        XCTAssertTrue(holds(#"{"title":"live\"ink"}"#))
        XCTAssertTrue(holds("live\u{2014}ink"))
        XCTAssertTrue(holds("LIVE INK"))
        XCTAssertTrue(holds("live_ink"))
        XCTAssertTrue(holds("live--------ink"))
        // The gap is counted in characters, not bytes: an em dash is three bytes.
        XCTAssertTrue(holds("live" + String(repeating: "\u{2014}", count: 8) + "ink"))

        XCTAssertFalse(holds("live\nink"))
        XCTAssertFalse(holds("live---------ink"))
        XCTAssertFalse(holds("live" + String(repeating: "\u{2014}", count: 9) + "ink"))
        XCTAssertFalse(holds("xlive ink"))
        XCTAssertFalse(holds("live inks"))
        XCTAssertFalse(holds("_live ink"))
        XCTAssertFalse(holds("live ink_"))

        // A phrase is found wherever it is, beside the ones that are not.
        XCTAssertEqual(SendContext.PhraseIndex(["live ink", "session picker", "nowhere here"])
                           .held(in: Data("x live ink, session picker.".utf8)),
                       ["live ink", "session picker"])
    }

    func testRankWeighsALineByHowFewSessionsHoldIt() {
        let ranked = SendContext.rank(lines: [["alpha one"], ["beta two"], []],
                                      held: ["a": ["alpha one", "beta two"], "b": ["beta two"], "c": []])
        XCTAssertEqual(ranked.map(\.id), ["a", "b"])
        XCTAssertEqual(ranked.map(\.score), [1.5, 0.5])

        let ids = ["f", "e", "d", "c", "b", "a"]
        let six = SendContext.rank(lines: ids.map { ["line \($0)"] }, held: Dictionary(uniqueKeysWithValues: ids.map { ($0, ["line \($0)"]) }))
        XCTAssertEqual(six.map(\.id), ["a", "b", "c", "d", "e"])
        XCTAssertEqual(Set(six.map(\.score)), [1])
    }

    func testReadPlanSharesTheBudgetFairly() {
        let now = Date()
        func file(_ name: String, _ size: Int, hoursAgo: Double) -> (url: URL, size: Int, modified: Date) {
            (URL(fileURLWithPath: "/files/\(name)"), size, now.addingTimeInterval(-hoursAgo * 3600))
        }
        let under = SendContext.readPlan([(id: "a", files: [file("a1", 10, hoursAgo: 1), file("a2", 20, hoursAgo: 2)]),
                                          (id: "b", files: [file("b1", 30, hoursAgo: 1)])], maxFile: 100, maxTotal: 100)
        XCTAssertFalse(under.capped)
        XCTAssertEqual(under.reads["a"].map(Set.init), [URL(fileURLWithPath: "/files/a1"), URL(fileURLWithPath: "/files/a2")])
        XCTAssertEqual(under.reads["b"], [URL(fileURLWithPath: "/files/b1")])

        let big = SendContext.readPlan([(id: "a", files: [file("a1", 10, hoursAgo: 1), file("huge", 200, hoursAgo: 0)])],
                                       maxFile: 100, maxTotal: 1000)
        XCTAssertTrue(big.capped)
        XCTAssertEqual(big.reads["a"], [URL(fileURLWithPath: "/files/a1")])

        // Two large candidates and a small one last: the small one reads everything, and the large
        // ones split what it leaves, each its newest files first.
        let over = SendContext.readPlan([
            (id: "large1", files: [file("l1-old", 40, hoursAgo: 5), file("l1-new", 40, hoursAgo: 1), file("l1-mid", 40, hoursAgo: 3)]),
            (id: "large2", files: [file("l2-mid", 40, hoursAgo: 3), file("l2-old", 40, hoursAgo: 5), file("l2-new", 40, hoursAgo: 1)]),
            (id: "small", files: [file("s1", 10, hoursAgo: 9)]),
        ], maxFile: 100, maxTotal: 100)
        XCTAssertTrue(over.capped)
        XCTAssertEqual(over.reads["small"], [URL(fileURLWithPath: "/files/s1")])
        XCTAssertEqual(over.reads["large1"], [URL(fileURLWithPath: "/files/l1-new")])
        XCTAssertEqual(over.reads["large2"], [URL(fileURLWithPath: "/files/l2-new")])
    }

    func testAuthorSearchReadsRecentClaudeSessionsOnly() throws {
        let manager = FileManager.default
        let claude = temporaryFolder().appendingPathComponent(".claude")
        let history = claude.appendingPathComponent("file-history")
        let live = UUID().uuidString, author = UUID().uuidString, other = UUID().uuidString, old = UUID().uuidString
        let first = "Quokka lantern drifts sideways", second = "Marmalade turbine hums softly"
        func folder(_ name: String, files: [String: String]) throws -> URL {
            let url = history.appendingPathComponent(name)
            try manager.createDirectory(at: url, withIntermediateDirectories: true)
            for (file, text) in files { try Data(text.utf8).write(to: url.appendingPathComponent(file)) }
            return url
        }
        let liveFolder = try folder(live, files: ["notes.md@v1": "the turbine: \(second.lowercased())"])
        let outside = claude.deletingLastPathComponent().appendingPathComponent("outside.txt")
        try Data("\(first)\n".utf8).write(to: outside)
        try manager.createSymbolicLink(at: liveFolder.appendingPathComponent("linked@v1"), withDestinationURL: outside)
        let authorFolder = try folder(author, files: ["panel.swift@v2": "let a = \"\(first)\"\nlet b = \"\(second)\""])
        let otherFolder = try folder(other, files: ["readme.md@v3": second])
        let oldFolder = try folder(old, files: ["x@v1": "\(first)\n\(second)"])
        let notSession = try folder("notes", files: ["x": "\(first)\n\(second)"])
        // Dated last: writing a file inside a folder moves the folder's date.
        let now = Date()
        for (url, hours) in [(liveFolder, 30.0), (authorFolder, 2), (otherFolder, 1), (oldFolder, 20), (notSession, 1)] {
            try manager.setAttributes([.modificationDate: now.addingTimeInterval(-hours * 3600)], ofItemAtPath: url.path)
        }

        // The first line is the author's alone; three sessions share the second, a third each.
        let fields = SendContext.authorFields(lines: [first, second, "ok"], listed: [live], claudeRoot: claude, now: now,
                                              limits: SendContext.AuthorLimits())
        let line = try XCTUnwrap(SendContext.line(fields, at: now, seq: 7))
        let text = String(decoding: line, as: UTF8.self)
        XCTAssertTrue(text.hasSuffix("\n"))
        XCTAssertEqual(text.filter { $0 == "\n" }.count, 1)
        XCTAssertTrue(text.contains(#""score":1.33}"#), text)
        XCTAssertTrue(text.contains(#""score":0.33}"#), text)
        for word in (first + " " + second).split(separator: " ") {
            XCTAssertFalse(text.lowercased().contains(word.lowercased()), "the log holds a word from the picture")
        }

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: line) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["authors", "authorLines", "seq", "t"])
        XCTAssertEqual(object["seq"] as? Int, 7)
        XCTAssertEqual(object["authorLines"] as? Int, 2)
        let authors = try XCTUnwrap(object["authors"] as? [[String: Any]])
        XCTAssertEqual(authors.compactMap { $0["id"] as? String }, [author] + [live, other].sorted())

        var tight = SendContext.AuthorLimits()
        tight.maxFile = 10
        let capped = SendContext.authorFields(lines: [first], listed: [live], claudeRoot: claude, now: now, limits: tight)
        XCTAssertEqual(capped["authorCapped"] as? Bool, true)
    }

    func testClaudeRootIsClaudeCodesFolderAndNeverThePersonsInATestLaunch() throws {
        let person = temporaryFolder(), scratch = temporaryFolder()
        func make(_ folder: String, in home: URL) throws {
            try FileManager.default.createDirectory(at: home.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        // A home with Codex's folder alone has no Claude Code folder to search.
        try make(".codex", in: scratch)
        XCTAssertNil(SendContext.claudeRoot(home: scratch, environment: [:], personHome: person))
        try make(".claude", in: scratch)
        XCTAssertEqual(SendContext.claudeRoot(home: scratch, environment: [:], personHome: person)?.standardizedFileURL,
                       scratch.appendingPathComponent(".claude").standardizedFileURL)

        try make(".claude", in: person)
        XCTAssertNil(SendContext.claudeRoot(home: person, environment: ["VIGNETTE_SETTINGS": "/x/settings.json"], personHome: person))
    }

    // MARK: The session a window shows

    private struct Pane {
        var id: String
        var tab: String
        var focused = false
        var agent: String? = nil
        var session: String? = nil
    }

    /// A `herdr pane list` answer in the shape herdr writes it.
    private func paneList(_ panes: [Pane]) -> Data {
        let listed: [[String: Any]] = panes.map { pane in
            var out: [String: Any] = ["pane_id": pane.id, "tab_id": pane.tab, "focused": pane.focused, "workspace_id": "w1",
                                      "agent": pane.agent.map { $0 as Any } ?? NSNull(), "agent_status": "idle", "cwd": "/Users/p/Code/x"]
            if let session = pane.session { out["agent_session"] = ["agent": pane.agent ?? "", "kind": "id", "value": session] }
            return out
        }
        let root: [String: Any] = ["id": "cli:pane:list", "result": ["type": "pane_list", "panes": listed]]
        return try! JSONSerialization.data(withJSONObject: root)
    }

    func testHerdrPanesKeepEveryPane() {
        let session = UUID().uuidString
        let data = paneList([Pane(id: "w1:p1", tab: "w1:t1", focused: true, agent: "claude", session: session),
                             Pane(id: "w1:p2", tab: "w1:t1"),
                             Pane(id: "w1:p3", tab: "w1:t2", agent: "claude", session: "")])
        XCTAssertEqual(SendContext.herdrPanes(in: data), [
            SendContext.HerdrPane(tab: "w1:t1", focused: true, agent: "claude", session: session),
            SendContext.HerdrPane(tab: "w1:t1", focused: false, agent: nil, session: nil),
            SendContext.HerdrPane(tab: "w1:t2", focused: false, agent: "claude", session: nil),
        ])
        XCTAssertNil(SendContext.herdrPanes(in: Data("not json".utf8)))
    }

    func testReadHerdrSaysWhetherHerdrRanAndAnswered() {
        let id = UUID().uuidString
        let answer = paneList([Pane(id: "p1", tab: "t1", focused: true, agent: "claude", session: id)])
        XCTAssertEqual(SendContext.readHerdr(binary: { nil }, run: { _, _, _ in XCTFail("ran without herdr"); return nil }).answer.read,
                       .noBinary)
        XCTAssertEqual(SendContext.readHerdr(binary: { "/x/herdr" }, run: { _, _, _ in nil }).answer.read, .failed)
        XCTAssertEqual(SendContext.readHerdr(binary: { "/x/herdr" }, run: { _, _, _ in (1, "", false) }).answer.read, .failed)
        let read = SendContext.readHerdr(binary: { "/x/herdr" }, run: { _, _, _ in (0, String(decoding: answer, as: UTF8.self), false) })
        XCTAssertEqual(read.answer.read, .answered(answer))
        XCTAssertEqual(read.focus?.pane, "p1")
    }

    func testHerdrClientsCountOnlyAttachedClients() {
        typealias Entry = SendContext.ProcessEntry
        let own: pid_t = 300, ghostty: pid_t = 100
        func counted(of app: pid_t, in table: [Entry]) -> [Int] {
            let clients = SendContext.herdrClients(of: app, own: own, names: ["herdr"], in: table)
            return [clients.under, clients.all, clients.surfaces]
        }
        var table = [
            Entry(pid: ghostty, parent: 1, name: "ghostty", hasTerminal: false),
            Entry(pid: 101, parent: ghostty, name: "login", hasTerminal: true),
            Entry(pid: 102, parent: 101, name: "zsh", hasTerminal: true),
            Entry(pid: 103, parent: 102, name: "herdr", hasTerminal: true),
            // herdr's server, and a hook's `herdr` under a session in one of its panes.
            Entry(pid: 200, parent: 1, name: "herdr", hasTerminal: false),
            Entry(pid: 201, parent: 200, name: "zsh", hasTerminal: true),
            Entry(pid: 202, parent: 201, name: "2.1.0", hasTerminal: true),
            Entry(pid: 203, parent: 202, name: "herdr", hasTerminal: true),
            // Vignette's own herdr read.
            Entry(pid: own, parent: 1, name: "Vignette", hasTerminal: false),
            Entry(pid: 301, parent: own, name: "herdr", hasTerminal: true),
        ]
        XCTAssertEqual(counted(of: ghostty, in: table), [1, 1, 1])

        table += [Entry(pid: 400, parent: 1, name: "Terminal", hasTerminal: false),
                  Entry(pid: 401, parent: 400, name: "login", hasTerminal: true),
                  Entry(pid: 402, parent: 401, name: "zsh", hasTerminal: true),
                  Entry(pid: 403, parent: 402, name: "herdr", hasTerminal: true)]
        XCTAssertEqual(counted(of: ghostty, in: table), [1, 2, 1])

        table.append(Entry(pid: 104, parent: ghostty, name: "login", hasTerminal: true))
        XCTAssertEqual(counted(of: ghostty, in: table), [1, 2, 2])

        // A terminal that runs its shells under a process of its own with no terminal counts none.
        let broker = [Entry(pid: 500, parent: 1, name: "iTerm2", hasTerminal: false),
                      Entry(pid: 501, parent: 500, name: "iTermServer", hasTerminal: false),
                      Entry(pid: 502, parent: 501, name: "login", hasTerminal: true),
                      Entry(pid: 503, parent: 502, name: "zsh", hasTerminal: true),
                      Entry(pid: 504, parent: 503, name: "herdr", hasTerminal: true)]
        XCTAssertEqual(counted(of: 500, in: broker), [1, 1, 0])
    }

    func testShownIsKnownOnlyWhenEveryLinkHolds() {
        let id = UUID().uuidString, thread = UUID().uuidString
        let alone = [Pane(id: "p1", tab: "t1", focused: true, agent: "claude", session: id), Pane(id: "p2", tab: "t2")]
        func shown(capture: String? = "window", bundle: String = "com.mitchellh.ghostty", kind: String = "terminal",
                   clients: SendContext.HerdrClients? = (1, 1, 1), panes: [Pane]? = nil,
                   herdr: SendContext.HerdrRead? = nil, thread: String? = nil, live: Set<String> = [],
                   hasWindow: Bool = true) -> SendContext.Shown {
            SendContext.shown(hasWindow: hasWindow, capture: capture, bundle: bundle, kind: kind, clients: clients,
                              herdr: herdr ?? .answered(paneList(panes ?? alone)), codexThread: thread, live: live)
        }
        XCTAssertEqual(shown(live: [id]), .session(client: "claude", id: id, how: "herdr", live: true))
        XCTAssertEqual(shown(), .session(client: "claude", id: id, how: "herdr", live: false))
        // `live` is about Claude Code's inboxes, so a Codex thread has none to say.
        XCTAssertEqual(shown(panes: [Pane(id: "p1", tab: "t1", focused: true, agent: "codex", session: thread)], live: [thread]),
                       .session(client: "codex", id: thread, how: "herdr", live: nil))

        XCTAssertEqual(shown(panes: alone + [Pane(id: "p3", tab: "t1")]), .unknown(.splitTab))
        XCTAssertEqual(shown(panes: alone + [Pane(id: "p3", tab: "t3", focused: true)]), .unknown(.severalFocused))
        XCTAssertEqual(shown(panes: [Pane(id: "p1", tab: "t1", agent: "claude", session: id)]), .unknown(.noFocus))
        XCTAssertEqual(shown(panes: [Pane(id: "p1", tab: "t1", focused: true, agent: "claude", session: "not-a-uuid")]), .unknown(.noSession))
        XCTAssertEqual(shown(panes: [Pane(id: "p1", tab: "t1", focused: true)]), .unknown(.noSession))
        XCTAssertEqual(shown(panes: [Pane(id: "p1", tab: "t1", focused: true, agent: "gemini", session: id)]), .unknown(.otherAgent))
        XCTAssertEqual(shown(clients: nil), .unknown(.processesUnread))
        XCTAssertEqual(shown(clients: (0, 1, 1)), .unknown(.noHerdrClient))
        XCTAssertEqual(shown(clients: (1, 1, 0)), .unknown(.unknownSurfaces))
        XCTAssertEqual(shown(clients: (1, 1, 2)), .unknown(.severalSurfaces))
        XCTAssertEqual(shown(clients: (1, 2, 1)), .unknown(.severalClients))
        XCTAssertEqual(shown(herdr: .noBinary), .unknown(.noHerdr))
        XCTAssertEqual(shown(herdr: .failed), .unknown(.herdrUnread))
        XCTAssertEqual(shown(herdr: .answered(Data("not json".utf8))), .unknown(.herdrUnread))
        XCTAssertEqual(SendContext.shown(hasWindow: true, capture: "window", bundle: "com.mitchellh.ghostty", kind: "terminal",
                                         clients: (1, 1, 1), herdr: nil, codexThread: nil, live: []), .unknown(.herdrUnread))

        XCTAssertEqual(shown(bundle: AgentApp.codexBundleID, kind: "agent-app", clients: nil, thread: thread),
                       .session(client: "codex", id: thread, how: "codex-app", live: nil))
        XCTAssertEqual(shown(bundle: AgentApp.codexBundleID, kind: "agent-app", clients: nil), .unknown(.codexNoThread))
        XCTAssertEqual(shown(bundle: AgentApp.codexBundleID, kind: "agent-app", clients: nil, thread: "home"), .unknown(.codexNoThread))
        XCTAssertEqual(shown(bundle: "com.anthropic.claudefordesktop", kind: "agent-app", clients: nil), .unknown(.agentAppUnread))
        XCTAssertEqual(shown(bundle: "com.apple.Safari", kind: "browser", clients: nil), .unknown(.notAgentWindow))
        XCTAssertEqual(shown(capture: "display"), .unknown(.display))
        XCTAssertEqual(shown(capture: "display", hasWindow: false), .unknown(.display))
        XCTAssertEqual(shown(hasWindow: false), .unknown(.noWindow))
    }

    /// `hostFields` runs herdr only when `terminalWhyNot` passes, so `shown` must need herdr's answer
    /// exactly then. Otherwise a record reads `herdr-unread` where another link failed.
    func testHerdrIsAskedExactlyWhenItsAnswerDecides() {
        var counts: [SendContext.HerdrClients?] = [nil]
        for under in 0...2 { for all in 0...2 { for surfaces in 0...2 { counts.append((under, all, surfaces)) } } }
        for clients in counts {
            let unasked = SendContext.shown(hasWindow: true, capture: "window", bundle: "com.mitchellh.ghostty", kind: "terminal",
                                            clients: clients, herdr: nil, codexThread: nil, live: [])
            XCTAssertEqual(unasked == .unknown(.herdrUnread), SendContext.terminalWhyNot(clients) == nil, "\(String(describing: clients))")
        }
    }

    func testHostRecordWritesTheDocumentedFields() throws {
        let at = Date(), id = UUID().uuidString
        func written(_ shown: SendContext.Shown, readAt: Date?) throws -> [String: Any] {
            let line = try XCTUnwrap(SendContext.line(SendContext.hostRecord(shown, hostMs: 4, readAt: readAt, at: at), at: at, seq: 0))
            return try XCTUnwrap(JSONSerialization.jsonObject(with: line) as? [String: Any])
        }

        let herdr = try written(.session(client: "claude", id: id, how: "herdr", live: true), readAt: at.addingTimeInterval(0.2504))
        XCTAssertEqual(Set(herdr.keys), ["host", "hostMs", "hostLagMs", "seq", "t"])
        let host = try XCTUnwrap(herdr["host"] as? [String: Any])
        XCTAssertEqual(Set(host.keys), ["client", "id", "how", "live"])
        XCTAssertEqual([host["client"], host["id"], host["how"]].map { $0 as? String }, ["claude", id, "herdr"])
        XCTAssertEqual(host["live"] as? Bool, true)
        XCTAssertEqual(herdr["hostMs"] as? Int, 4)
        XCTAssertEqual(herdr["hostLagMs"] as? Int, 250)

        let codex = try written(.session(client: "codex", id: id, how: "codex-app", live: nil), readAt: at)
        XCTAssertEqual(codex["host"] as? [String: String], ["client": "codex", "id": id, "how": "codex-app"])

        let unknown = try written(.unknown(.splitTab), readAt: nil)
        XCTAssertEqual(Set(unknown.keys), ["hostWhyNot", "hostMs", "seq", "t"])
        XCTAssertEqual(unknown["hostWhyNot"] as? String, "split-tab")
    }
}
