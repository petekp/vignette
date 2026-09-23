import XCTest

final class AgentConnectionTests: XCTestCase {
    private let session = "e011fff1-c791-4934-9e61-9307d840a5eb"

    /// Trimmed from a real `herdr agent list`: two Claude Code panes and one Codex pane.
    private func agentList(session: String, status: String = "idle", pane: String = "w9:p6") -> String {
        """
        {"id":"cli:agent:list","result":{"type":"agent_list","agents":[
          {"agent":"claude","agent_status":"\(status)","cwd":"/Users/p/Code/vignette","focused":true,
           "agent_session":{"agent":"claude","kind":"id","value":"\(session)"},
           "pane_id":"\(pane)","terminal_title_stripped":"Closed agent loop","workspace_id":"w9"},
          {"agent":"claude","agent_status":"idle","cwd":"/Users/p/Code/other","focused":false,
           "pane_id":"w9:pA","terminal_title_stripped":"No session id","workspace_id":"w9"},
          {"agent":"codex","agent_status":"idle","cwd":"/Users/p/Code/two","focused":false,
           "pane_id":"w9:pB","workspace_id":"w9"}]}}
        """
    }

    /// A connection whose subprocesses are answers this test wrote, and a record of the argv it used.
    private func claude(_ answers: [String: (Int32, String, Bool)]) -> (ClaudeCodeConnection, () -> [[String]]) {
        let calls = Recorder()
        var connection = ClaudeCodeConnection()
        connection.binary = { "/bin/herdr" }
        connection.run = { _, arguments, _ in
            calls.record(arguments)
            // The whole argv first, so one call can be answered differently from another that
            // starts with the same word.
            let answer = answers[arguments.joined(separator: " ")] ?? answers[arguments.first ?? ""]
            return answer.map { ($0.0, $0.1, $0.2) }
        }
        return (connection, { calls.all() })
    }

    /// Collects argv across threads; the connection's runner is `@Sendable`.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [[String]] = []
        func record(_ arguments: [String]) { lock.lock(); calls.append(arguments); lock.unlock() }
        func all() -> [[String]] { lock.lock(); defer { lock.unlock() }; return calls }
    }

    // MARK: Claude Code, by session rather than by pane

    /// Trimmed from a real `herdr agent list` answer: two agents, one of them named.
    private let namedAgentList = Data("""
    {"id":"cli:agent:list","result":{"type":"agent_list","agents":[
      {"agent":"claude","agent_status":"idle","cwd":"/Users/p/Code/one","focused":false,
       "name":"reviewer","pane_id":"w9:p3","tab_id":"w9:t2","workspace_id":"w9"},
      {"agent":"codex","agent_status":"working","cwd":"/Users/p/Code/two","focused":true,
       "pane_id":"w9:p6","tab_id":"w9:t5","workspace_id":"w9"}]}}
    """.utf8)

    func testReadsEachAgentHerdrLists() {
        let agents = ClaudeCodeConnection.agents(fromAgentList: namedAgentList)
        XCTAssertEqual(agents.map(\.id), ["reviewer", "w9:p6"])
        XCTAssertEqual(agents.map(\.kind), ["claude", "codex"])
        XCTAssertEqual(agents.map(\.status), ["idle", "working"])
        XCTAssertEqual(agents[1].cwd, "/Users/p/Code/two")
    }

    func testAnswerThatIsNotAnAgentListIsNoAgents() {
        XCTAssertEqual(ClaudeCodeConnection.agents(fromAgentList: Data("not json".utf8)), [])
        XCTAssertEqual(ClaudeCodeConnection.agents(fromAgentList: Data(#"{"error":{"code":"no_server"}}"#.utf8)), [])
    }

    func testTheHerdrBinaryIsTheFirstOneThatExists() {
        XCTAssertEqual(ClaudeCodeConnection.binary { $0 == ClaudeCodeConnection.binaryPaths[1] }, ClaudeCodeConnection.binaryPaths[1])
        XCTAssertNil(ClaudeCodeConnection.binary { _ in false })
    }

    func testOnlyClaudePanesWithASessionAreOffered() {
        let (connection, _) = claude(["agent": (0, agentList(session: session), false)])
        let found = connection.destinations()
        XCTAssertEqual(found.map(\.id), [session], "a pane herdr cannot identify is not a conversation")
        XCTAssertEqual(found.first?.name, "Closed agent loop")
        XCTAssertEqual(found.first?.detail, "vignette")
        XCTAssertEqual(found.first?.address.guardTier, .preflight)
    }

    func testTheRequestGoesToThePaneRunningTheBoundSession() {
        let (connection, calls) = claude(["agent": (0, agentList(session: session, pane: "w9:pZ"), false)])
        let destination = AgentDestination(id: session, name: "x", address: .claudeSession(session))
        guard case .accepted(let detail) = connection.submit("hello", to: destination) else {
            return XCTFail("a session in a pane is submittable")
        }
        XCTAssertTrue(detail.contains("w9:pZ"))
        XCTAssertEqual(calls().last?.prefix(3).map { $0 }, ["agent", "prompt", "w9:pZ"])
    }

    func testASessionThatIsInNoPaneIsAnErrorAndNeverAnotherPane() {
        let (connection, calls) = claude(["agent": (0, agentList(session: "0f0f0f0f-0000-4000-8000-000000000000"), false)])
        let destination = AgentDestination(id: session, name: "x", address: .claudeSession(session))
        guard case .destinationChanged = connection.submit("hello", to: destination) else {
            return XCTFail("a missing session must not fall back to the focused pane")
        }
        XCTAssertEqual(calls().count, 1, "nothing is submitted once the guard fails")
    }

    func testAnAgentWaitingOnItsOwnPromptIsNotInterrupted() {
        let (connection, calls) = claude(["agent": (0, agentList(session: session, status: "blocked"), false)])
        let destination = AgentDestination(id: session, name: "x", address: .claudeSession(session))
        guard case .notSubmitted = connection.submit("hello", to: destination) else {
            return XCTFail("a blocked agent is a definite non-submission")
        }
        XCTAssertEqual(calls().count, 1)
    }

    func testAPromptThatNeverAnsweredIsUncertainRatherThanFailed() {
        let (connection, _) = claude(["agent": (0, agentList(session: session), false),
                                      "agent prompt w9:p6 hello": (15, "", true)])
        let destination = AgentDestination(id: session, name: "x", address: .claudeSession(session))
        guard case .uncertain = connection.submit("hello", to: destination) else {
            return XCTFail("a call killed on its deadline may already have been accepted")
        }
    }

    // MARK: Codex, by thread UUID

    func testTheQueueCallIsOneArgvElementPerPart() {
        let thread = "01a0c176-bfab-7662-9ffb-a30cc3490835"
        XCTAssertEqual(CodexConnection.arguments(thread: thread, message: "look at \"a b.png\""),
                       ["queue", "--thread", thread, "--message", "look at \"a b.png\""])
    }

    func testAThreadTheServerDoesNotHaveIsTheDestinationHavingChanged() {
        guard case .destinationChanged = CodexConnection.failure(output: "Error: thread not found", thread: "t") else {
            return XCTFail("a missing thread is not a retryable failure")
        }
        guard case .destinationChanged = CodexConnection.failure(output: "failed to connect to ws://127.0.0.1:9", thread: "t") else {
            return XCTFail("an engine that cannot be reached is not a retryable failure")
        }
        guard case .notSubmitted = CodexConnection.failure(output: "Error: invalid message", thread: "t") else {
            return XCTFail("anything else definitely did not arrive")
        }
    }

    func testACodexDestinationIsPinnedByTheRuntimeAndAClaudeOneByAPreflightCheck() {
        XCTAssertEqual(AgentAddress.codexThread(uuid: "u").guardTier, .runtimeEnforced)
        XCTAssertEqual(AgentAddress.claudeSession("s").guardTier, .preflight)
    }

    // MARK: Codex discovery

    /// Every thread the listing reports becomes a destination, named and grouped by its own
    /// project, and addressed by its UUID alone.
    func testEveryListedThreadBecomesADestinationGroupedByItsProject() {
        let answer = """
        {"id":2,"result":{"data":[\
        {"id":"01a0c14e-e536-7580-866c-c50622cecd9b","name":"Explore agent screenshot loop","cwd":"/Users/p/Code/vignette","status":{"type":"idle"}},\
        {"id":"01a0c28f-7c24-7a93-82e4-a7906de82cf4","name":"Open drawing","cwd":"/tmp/loop-test","status":{"type":"idle"}}]}}
        """
        var connection = CodexConnection()
        connection.binary = { "/bin/codex" }
        connection.converse = { _, _, _ in [answer] }

        let found = connection.destinations()
        XCTAssertEqual(found.map(\.name), ["Explore agent screenshot loop", "Open drawing"])
        XCTAssertEqual(found[1].detail, "loop-test", "the project is the session's own folder")
        XCTAssertEqual(found[1].address, .codexThread(uuid: "01a0c28f-7c24-7a93-82e4-a7906de82cf4"))
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
