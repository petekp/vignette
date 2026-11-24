import XCTest

final class HerdrFocusTests: XCTestCase {
    private let session = "e011fff1-c791-4934-9e61-9307d840a5eb"
    private let other = "0f0f0f0f-0000-4000-8000-000000000000"

    private func status(pane: String, tab: String = "tbA", agent: String = "t9") -> HerdrFocus.Answer {
        (0, #"{"zoom":0.9,"space":"spA","tab":"\#(tab)","focused_pane":"\#(pane)","layout":"main","agent":"\#(agent)","floats":{},"overlays":[],"errors":[]}"#, false)
    }

    private let ls: HerdrFocus.Answer = (0, """
        {"spaces":[{"id":"spA","name":"vignette","folder":"/Users/p/Code/vignette","machine":null,"active":true,"tabs":[
          {"id":"tbA","name":"vignette [fix ink]","active":true,"settled":false,"terminals":[
            {"terminal":"t1","pane":"pA1","status":"idle","app":"claude-code","name":"fix-ink","sub_agents":[]},
            {"terminal":"t2","pane":"pA2","status":null,"app":null,"name":null,"sub_agents":[]}]},
          {"id":"tbB","name":"7","active":false,"settled":false,"terminals":[
            {"terminal":"t3","pane":"pB1","status":"done","app":"claude-code","name":null,"sub_agents":[]}]},
          {"id":"tbC","name":"two agents","active":false,"settled":false,"terminals":[
            {"terminal":"t4","pane":"pC1","status":"idle","app":"codex","name":null,"sub_agents":[]},
            {"terminal":"t5","pane":"pC2","status":"idle","app":"claude-code","name":null,"sub_agents":[]}]}]}],
         "recent":[]}
        """, false)

    private var terminals: [String] {
        [#"""
        {"id":1,"jsonrpc":"2.0","result":{"hidden_finished":0,"machines":[],"terminals":[
          {"address":"t1","pid":500,"foreground":{"pid":501,"name":"2.1.322","argv":["claude"],"cwd":"/x"},
           "labels":{"inbox.session":"\#(session)","inbox.panel":"pPanel1","herdr.tab":"tbA","fleet.role":"coordinator"}},
          {"address":"t2","pid":600,"foreground":{"pid":600,"name":"zsh","argv":["zsh"],"cwd":"/x"},"labels":{}},
          {"address":"t3","pid":700,"foreground":{"pid":700,"name":"2.1.322","argv":["claude"],"cwd":"/x"},
           "labels":{"inbox.session":"\#(other)"},"parent":"t1"},
          {"address":"t4","pid":800,"foreground":{"pid":800,"name":"codex","argv":["codex"],"cwd":"/x"},"labels":{}},
          {"address":"t5","pid":900,"foreground":{"pid":900,"name":"2.1.322","argv":["claude"],"cwd":"/x"},
           "labels":{"fleet.role":"fix the ink, then ship"}}]}}
        """#]
    }

    private func focus(_ pane: String, tab: String = "tbA") -> HerdrFocus? {
        try? HerdrFocus.reading(status: status(pane: pane, tab: tab), ls: ls, terminals: terminals).get()
    }

    private func marked(_ focus: HerdrFocus?, listing: [AgentDestination]) -> [AgentDestination.Focus?] {
        DestinationChoice.choose(.init(destinations: listing, complete: false, fresh: true, herdr: focus?.sessions(from: listing)),
                                 for: .send(cameFrom: nil)).list.map(\.focus)
    }

    private func claude(_ id: String, pid: Int32?) -> AgentDestination {
        var destination = AgentDestination(id: id, name: id, address: .claudeSession(id))
        destination.inbox = pid
        return destination
    }

    func testTheFocusedTerminalAndEveryAgentAreJoinedAcrossStatusLsAndHc() throws {
        let read = try XCTUnwrap(focus("pA1"))
        XCTAssertEqual(read.pane, "pA1")
        XCTAssertEqual(read.tab, "tbA")
        XCTAssertEqual(read.agents, [.init(pane: "pA1", session: session, tab: "tbA", pid: 501, role: "coordinator"),
                                     .init(pane: "pB1", session: other, tab: "tbB", pid: 700, role: "delegate"),
                                     .init(pane: "pC1", tab: "tbC", pid: 800),
                                     .init(pane: "pC2", tab: "tbC", pid: 900, role: "other")],
                       "a shell is no agent, and the foreground process is Claude Code's, not the shell it was started from")
        XCTAssertEqual(read.tabLabels, ["tbA": "vignette [fix ink]", "tbC": "two agents"], "a tab Herdr numbered has no label")
        XCTAssertEqual(read.label(ofSession: session), "vignette [fix ink]")
    }

    func testTheInboxModsPanelGivesTheFocusToItsTerminal() {
        XCTAssertEqual(focus("pPanel1")?.pane, "pA1")
        XCTAssertEqual(marked(focus("pPanel1"), listing: [claude(session, pid: 501)]), [.pane])
    }

    func testAShellBesideOneAgentMarksThatAgentByItsTabAndATabWithTwoMarksNothing() {
        XCTAssertEqual(marked(focus("pA2"), listing: [claude(session, pid: 501)]), [.tab])
        XCTAssertEqual(marked(focus("pElsewhere", tab: "tbC"), listing: [claude("c5", pid: 900)]), [nil])
        XCTAssertEqual(marked(focus("pC1", tab: "tbC"), listing: [claude("c5", pid: 900)]), [nil], "the focused Codex terminal marks nothing")
    }

    func testTheSessionIsFoundByItsProcessBeforeTheInboxModsLabel() {
        let cleared = "1f0f0f0f-0000-4000-8000-000000000000"
        XCTAssertEqual(marked(focus("pA1"), listing: [claude(cleared, pid: 501), claude(session, pid: nil)]), [.pane, nil],
                       "after /clear the inbox names the new session while the label may still name the old one")
        XCTAssertEqual(marked(focus("pA1"), listing: [claude(session, pid: 42)]), [.pane],
                       "a terminal whose process runs no listed session keeps its label's session")
        XCTAssertEqual(marked(focus("pC2", tab: "tbC"), listing: [claude("c5", pid: 900)]), [.pane], "no label, found by process")
        XCTAssertEqual(marked(focus("pB1", tab: "tbB"), listing: [claude(other, pid: 501)]), [nil],
                       "a label naming a session another terminal runs is not that session")
    }

    func testAClaudeCodeHerdrShowsNoAgentForIsFoundByItsProcess() {
        let unreported = "2f0f0f0f-0000-4000-8000-000000000000"
        XCTAssertEqual(marked(focus("pA2"), listing: [claude(session, pid: 501), claude(unreported, pid: 600)]), [nil, .pane],
                       "the terminal Herdr shows as running nothing runs a listed Claude Code, which has the focus")
        XCTAssertEqual(marked(focus("pA2"), listing: [claude(session, pid: 501)]), [.tab], "a shell is still no agent")
    }

    func testASessionsRoleFollowsItsProcessAndTheLogGetsARuleNameOrOther() {
        let read = focus("pA2")?.sessions(from: [claude("cleared", pid: 501), claude("c5", pid: 900)])
        XCTAssertEqual(read?.role(ofSession: "cleared"), "coordinator", "after /clear the role stays with the terminal")
        XCTAssertEqual(read?.role(ofSession: "c5"), "other", "a sentence in the label never reaches the log")
        XCTAssertEqual(read?.role(ofSession: other), "delegate", "no fleet.role label, but a parent terminal")
        XCTAssertEqual(HerdrFocus.role(labels: ["fleet.role": "coordinator"], parent: "t1"), "coordinator", "a label wins over a parent")
        XCTAssertNil(HerdrFocus.role(labels: [:], parent: ""))
        XCTAssertEqual(HerdrFocus.loggedRole("delegate-2"), "delegate-2")
        XCTAssertEqual(HerdrFocus.loggedRole(String(repeating: "a", count: 25)), "other")
        XCTAssertEqual(HerdrFocus.loggedRole("délégué"), "other")
        XCTAssertEqual(HerdrFocus.loggedRole(""), "other")
    }

    func testEveryFailureMarksNothingAndSaysWhy() {
        func reason(status: HerdrFocus.Answer? = nil, ls: HerdrFocus.Answer?? = nil, terminals: [String]? = nil) -> String? {
            let result = HerdrFocus.reading(status: status ?? self.status(pane: "pA1"), ls: ls ?? self.ls, terminals: terminals ?? self.terminals)
            if case .failure(let unread) = result { return unread.reason }
            return nil
        }
        XCTAssertNil(reason())
        XCTAssertEqual(reason(status: (1, "no window", false)), "status exit 1: no window", "the Herdr window is closed")
        XCTAssertEqual(reason(status: (0, "", true)), "status timed out")
        XCTAssertEqual(reason(ls: .some(nil)), "ls did not run")
        XCTAssertEqual(reason(status: (0, "{}", false)), "status unreadable")
        XCTAssertEqual(reason(ls: (0, "not json", false)), "ls unreadable")
        XCTAssertEqual(reason(terminals: []), "hc did not answer")
        XCTAssertEqual(reason(terminals: [#"{"id":1,"jsonrpc":"2.0","error":{"code":-32601,"message":"no such method"}}"#]), "hc did not answer")
        XCTAssertEqual(reason(status: status(pane: "pA1", tab: "tbGone")), "status's tab tbGone is not in ls")
        XCTAssertEqual(reason(status: status(pane: "pB1", tab: "tbA")), "status's tab tbA is not the focused terminal's tbB")
    }

    func testWithoutTheHerdrAppOrHcNothingRuns() {
        let ran = RunCount()
        let run: @Sendable (String, [String], TimeInterval) -> HerdrFocus.Answer? = { _, _, _ in ran.mark(); return nil }
        let converse: @Sendable (String, [String], [String], TimeInterval) -> [String] = { _, _, _, _ in ran.mark(); return [] }
        XCTAssertNil(HerdrFocus.read(app: { nil }, core: { "/bin/hc" }, run: run, converse: converse))
        XCTAssertNil(HerdrFocus.read(app: { "/bin/herdr-app" }, core: { nil }, run: run, converse: converse))
        XCTAssertFalse(ran.marked)
    }

    func testACaptureLogsTheFocusedPaneItsSessionAndItsRepository() {
        var listed = claude(session, pid: 501)
        listed.place = .repository(name: "vignette", root: "/Users/p/Code/vignette", worktree: nil, subfolder: nil)
        func line(pane: String, tab: String = "tbA", listing: [AgentDestination]) -> String {
            HerdrFocus.logged(HerdrFocus.clue(read: { .success(self.focus(pane, tab: tab) ?? HerdrFocus(pane: pane, tab: tab, agents: [])) },
                                              listing: { listing }))
        }
        XCTAssertEqual(line(pane: "pA1", listing: [listed]), "herdr=pA1/\(session) focus=pane project=vignette")
        XCTAssertEqual(line(pane: "pA2", listing: [listed]), "herdr=pA2/\(session) focus=tab project=vignette", "a shell beside the one agent")
        XCTAssertEqual(line(pane: "pC1", tab: "tbC", listing: [listed]), "herdr=pC1/none focus=none project=none", "a Codex pane has no Claude Code session")
        XCTAssertEqual(line(pane: "pA1", listing: []), "herdr=pA1/none focus=none project=none")
    }

    func testACaptureWithNoFocusLogsOneWordWhy() {
        let listing = RunCount()
        let unread = HerdrFocus.clue(read: { .failure(HerdrFocus.Unread(reason: "status exit 1: no window")) }, listing: { listing.mark(); return [] })
        XCTAssertEqual(HerdrFocus.logged(unread), "herdr=unread:status-exit-1:-no-window focus=none project=none")
        XCTAssertEqual(HerdrFocus.logged(HerdrFocus.clue(read: { HerdrFocus.readReporting(app: { nil }, core: { nil }) }, listing: { [] })),
                       "herdr=unread:no-herdr-app-or-hc focus=none project=none")
        XCTAssertFalse(listing.marked, "sessions are listed only after the focus is read")
    }

    func testTheThreeReadsAreAskedOfTheirTools() throws {
        let status = status(pane: "pA1"), ls = ls, terminals = terminals
        let read = HerdrFocus.read(app: { "/bin/herdr-app" }, core: { "/bin/hc" }, run: { binary, arguments, _ in
            binary == "/bin/herdr-app" ? (arguments == ["status"] ? status : arguments == ["ls"] ? ls : nil) : nil
        }, converse: { binary, arguments, requests, _ in
            binary == "/bin/hc" && arguments == ["connect"] && requests == [HerdrFocus.terminalListRequest] ? terminals : []
        })
        XCTAssertEqual(read?.pane, "pA1")
    }
}

private final class RunCount: @unchecked Sendable {
    private let lock = NSLock()
    private var ran = false
    func mark() { lock.lock(); ran = true; lock.unlock() }
    var marked: Bool { lock.lock(); defer { lock.unlock() }; return ran }
}
