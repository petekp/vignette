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
        XCTAssertEqual(CodexConnection.arguments(thread: thread, endpoint: nil, message: "look at \"a b.png\""),
                       ["queue", "--thread", thread, "--message", "look at \"a b.png\""])
        XCTAssertEqual(CodexConnection.arguments(thread: thread, endpoint: "ws://127.0.0.1:1", message: "x"),
                       ["queue", "--thread", thread, "--remote", "ws://127.0.0.1:1", "--message", "x"])
        XCTAssertEqual(CodexConnection.arguments(thread: thread, endpoint: "", message: "x").count, 5,
                       "an empty endpoint is no endpoint, not an empty one")
    }

    func testAThreadTheServerDoesNotHaveIsTheDestinationHavingChanged() {
        guard case .destinationChanged = CodexConnection.failure(output: "Error: thread not found", thread: "t") else {
            return XCTFail("a missing thread is not a retryable failure")
        }
        guard case .destinationChanged = CodexConnection.failure(output: "failed to connect to ws://127.0.0.1:9", thread: "t") else {
            return XCTFail("an endpoint that is gone is not a retryable failure")
        }
        guard case .notSubmitted = CodexConnection.failure(output: "Error: invalid message", thread: "t") else {
            return XCTFail("anything else definitely did not arrive")
        }
    }

    func testACodexDestinationIsPinnedByTheRuntimeAndAClaudeOneByAPreflightCheck() {
        XCTAssertEqual(AgentAddress.codexThread(uuid: "u", endpoint: nil).guardTier, .runtimeEnforced)
        XCTAssertEqual(AgentAddress.claudeSession("s").guardTier, .preflight)
    }

    func testSettingsWithoutAThreadUuidOfferNoCodexDestination() {
        var data = SettingsData()
        data.codexSessions = [CodexSession(id: "a", name: "A", thread: "not-a-uuid"),
                              CodexSession(id: "b", name: "B", thread: "01A0C176-BFAB-7662-9FFB-A30CC3490835")]
        let found = data.codexDestinations
        XCTAssertEqual(found.map(\.id), ["b"])
        XCTAssertEqual(found.first?.address, .codexThread(uuid: "01a0c176-bfab-7662-9ffb-a30cc3490835", endpoint: nil))
    }

    // MARK: Codex discovery

    /// A running app-server's sessions and the configured ones are one list. A configured entry
    /// that names the same thread wins, because its name is the one the person chose.
    func testDiscoveredSessionsJoinTheConfiguredOnesWithoutDuplicatingAThread() {
        let shared = "01a0c14e-e536-7580-866c-c50622cecd9b"
        let answer = """
        {"id":2,"result":{"data":[\
        {"id":"\(shared)","name":"Server's name","cwd":"/Users/p/Code/vignette","status":{"type":"idle"}},\
        {"id":"01a0c28f-7c24-7a93-82e4-a7906de82cf4","name":"Open drawing","cwd":"/tmp/loop-test","status":{"type":"idle"}}]}}
        """
        var connection = CodexConnection(configured: [
            AgentDestination(id: "mine", name: "My name for it", detail: "vignette",
                             address: .codexThread(uuid: shared, endpoint: nil)),
        ])
        connection.binary = { "/bin/codex" }
        connection.serverIsRunning = { true }
        connection.converse = { _, _, _ in [answer] }

        let found = connection.destinations()
        XCTAssertEqual(found.map(\.name), ["My name for it", "Open drawing"])
        XCTAssertEqual(found[1].detail, "loop-test", "the project is the session's own folder")
        XCTAssertEqual(found[1].address, .codexThread(uuid: "01a0c28f-7c24-7a93-82e4-a7906de82cf4",
                                                      endpoint: "unix://" + AppServer.controlSocket.path))
    }

    /// No server to ask is the ordinary case, and not an error: the configured entries answer and
    /// nothing is started to change that.
    func testWithNoRunningServerOnlyTheConfiguredSessionsAreOffered() {
        var asked = false
        var connection = CodexConnection(configured: [
            AgentDestination(id: "mine", name: "Mine", address: .codexThread(uuid: "u", endpoint: nil)),
        ])
        connection.binary = { "/bin/codex" }
        connection.serverIsRunning = { false }
        connection.converse = { _, _, _ in asked = true; return [] }

        XCTAssertEqual(connection.destinations().map(\.name), ["Mine"])
        XCTAssertFalse(asked, "nothing is spawned when there is no socket")
    }

    /// The conversation is aimed at the control socket through the proxy, which is what reaches
    /// the server that owns the threads.
    func testDiscoveryAsksThroughTheProxyAtTheControlSocket() {
        var argv: [String] = []
        var connection = CodexConnection()
        connection.binary = { "/bin/codex" }
        connection.serverIsRunning = { true }
        connection.converse = { _, arguments, _ in argv = arguments; return [] }
        _ = connection.destinations()
        XCTAssertEqual(argv, ["app-server", "proxy", "--sock", AppServer.controlSocket.path])
    }
}
