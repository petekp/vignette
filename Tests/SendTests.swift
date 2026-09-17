import XCTest

final class SendTests: XCTestCase {
    /// Trimmed from a real `herdr agent list` answer: two agents, one named and focused.
    private let agentList = Data("""
    {"id":"cli:agent:list","result":{"type":"agent_list","agents":[
      {"agent":"claude","agent_status":"idle","cwd":"/Users/p/Code/one","focused":false,
       "name":"reviewer","pane_id":"w9:p3","tab_id":"w9:t2","workspace_id":"w9"},
      {"agent":"codex","agent_status":"working","cwd":"/Users/p/Code/two","focused":true,
       "pane_id":"w9:p6","tab_id":"w9:t5","workspace_id":"w9"}]}}
    """.utf8)

    func testReadsEachAgentHerdrLists() {
        let targets = Send.targets(fromAgentList: agentList)
        XCTAssertEqual(targets.map(\.id), ["reviewer", "w9:p6"])
        XCTAssertEqual(targets.map(\.kind), ["claude", "codex"])
        XCTAssertEqual(targets.map(\.status), ["idle", "working"])
        XCTAssertEqual(targets[1].cwd, "/Users/p/Code/two")
    }

    func testAnswerThatIsNotAnAgentListIsNoAgents() {
        XCTAssertEqual(Send.targets(fromAgentList: Data("not json".utf8)), [])
        XCTAssertEqual(Send.targets(fromAgentList: Data(#"{"error":{"code":"no_server"}}"#.utf8)), [])
    }

    func testWithoutATargetTheFocusedAgentGetsIt() {
        XCTAssertEqual(Send.choose(Send.targets(fromAgentList: agentList), to: nil)?.id, "w9:p6")
    }

    func testATargetNamesAnAgentOrItsPane() {
        let targets = Send.targets(fromAgentList: agentList)
        XCTAssertEqual(Send.choose(targets, to: "reviewer")?.pane, "w9:p3")
        XCTAssertEqual(Send.choose(targets, to: "w9:p3")?.id, "reviewer")
        XCTAssertNil(Send.choose(targets, to: "nobody"))
    }

    func testNoFocusedAgentAndNoTargetIsNothingToSendTo() {
        let list = Data(#"{"result":{"agents":[{"agent":"claude","pane_id":"w1:p1","focused":false}]}}"#.utf8)
        XCTAssertNil(Send.choose(Send.targets(fromAgentList: list), to: nil))
    }

    func testTheMessageIsOneLineWithTheQuotedPath() {
        let file = URL(fileURLWithPath: "/Users/p/Dropbox/Screenshots/Screenshot 1 PM-annotated.png")
        XCTAssertEqual(Send.message(text: "the header scrolls", file: file),
                       "the header scrolls \"/Users/p/Dropbox/Screenshots/Screenshot 1 PM-annotated.png\"")
        XCTAssertEqual(Send.message(text: "two\nlines", file: file).components(separatedBy: .newlines).count, 1)
        XCTAssertEqual(Send.message(text: nil, file: URL(fileURLWithPath: "/a/b.png")), "Screenshot: \"/a/b.png\"")
        XCTAssertEqual(Send.message(text: "  ", file: URL(fileURLWithPath: "/a/b.png")), "Screenshot: \"/a/b.png\"")
    }

    func testTheHerdrBinaryIsTheFirstOneThatExists() {
        XCTAssertEqual(Send.binary { $0 == Send.binaryPaths[1] }, Send.binaryPaths[1])
        XCTAssertNil(Send.binary { _ in false })
    }
}
