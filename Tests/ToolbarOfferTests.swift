import XCTest

/// What the annotator's bar offers, and where Send goes. The two rules at risk: Return never sends
/// to a session Vignette picked, and a target on screen is never swapped for another under the
/// pointer when a slower client answers.
@MainActor
final class ToolbarOfferTests: XCTestCase {
    private func session(_ id: String, _ client: AgentClient = .claude, used: TimeInterval = 0,
                         focus: AgentDestination.Focus? = nil) -> AgentDestination {
        AgentDestination(id: id, name: id, address: client == .claude ? .claudeSession(id) : .codexThread(uuid: id),
                         lastUsed: Date(timeIntervalSince1970: used), focus: focus)
    }

    func testEachOfferSaysWhatReturnAndCmdReturnDo() {
        let mew = session("mew")
        XCTAssertEqual(ToolbarOffer(replyTo: nil, destinations: [], listed: true, target: nil), .copy)
        XCTAssertEqual(ToolbarOffer.copy.finishes, .init(returnKey: .done, commandReturn: .done))
        XCTAssertEqual(ToolbarOffer(replyTo: nil, destinations: [mew], listed: true, target: mew), .send(mew))
        XCTAssertEqual(ToolbarOffer.send(mew).finishes, .init(returnKey: .done, commandReturn: .send),
                       "Return copies: the target is Vignette's pick")
        XCTAssertEqual(ToolbarOffer(replyTo: mew, destinations: [], listed: false, target: nil), .reply(mew))
        XCTAssertEqual(ToolbarOffer.reply(mew).finishes, .init(returnKey: .send, commandReturn: .send),
                       "Return replies: the image names where it came from")
    }

    /// A Claude Code session missing from the whole list has closed, since herdr lists every pane.
    /// Codex lists only the threads used last, so a Codex thread missing from it may still be there.
    func testAReplyGivesWayOnlyWhenItsClaudeSessionHasClosed() {
        let gone = session("gone"), other = session("other"), thread = session("thread", .codex)
        XCTAssertEqual(ToolbarOffer(replyTo: gone, destinations: [other], listed: false, target: other), .reply(gone),
                       "a missing session may only be late")
        XCTAssertEqual(ToolbarOffer(replyTo: gone, destinations: [other], listed: true, target: other), .send(other))
        XCTAssertEqual(ToolbarOffer(replyTo: gone, destinations: [], listed: true, target: nil), .copy)
        XCTAssertEqual(ToolbarOffer(replyTo: thread, destinations: [other], listed: true, target: other), .reply(thread))
    }

    func testTheTargetSettlesOnHerdrsFocusAndStaysWhenCodexAnswersLater() {
        let model = AnnotatorToolbar.Model()
        model.begin(replyTo: nil)
        let codex = session("codex", .codex, used: 200), unfocused = session("other", used: 150)
        model.answered([codex], complete: false)
        XCTAssertNil(model.target, "no focus yet, and the session used last needs every client's answer")
        let beside = session("mew", used: 100, focus: .tab)
        model.answered([codex, unfocused, beside], complete: false)
        XCTAssertEqual(model.target?.id, "mew")
        model.answered([session("new codex", .codex, used: 300), codex, unfocused, beside], complete: true)
        XCTAssertEqual(model.target?.id, "mew", "a later answer does not move a target that is still there")
        model.pick(codex)
        model.answered([beside], complete: true)
        XCTAssertEqual(model.target?.id, "codex", "a pick stays, even when the list no longer has it")
    }

    func testWithNoFocusTheTargetIsTheSessionUsedLastAndIsReplacedOnlyWhenItIsGone() {
        let model = AnnotatorToolbar.Model()
        model.begin(replyTo: nil)
        let old = session("old", used: 100), new = session("new", .codex, used: 200)
        model.answered([new, old], complete: true)
        XCTAssertEqual(model.target?.id, "new")
        model.answered([old], complete: true)
        XCTAssertEqual(model.target?.id, "old")
        model.begin(replyTo: nil)
        XCTAssertNil(model.target, "each image starts over")
    }
}
