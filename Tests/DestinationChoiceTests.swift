import XCTest

final class DestinationChoiceTests: XCTestCase {
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

    /// A session the person picked on the note stays while it is listed, as the list's own record of
    /// it, or may still be, and drops to the responder when a whole list leaves it out. It is matched by id alone.
    func testALiveNoteKeepsAHandPickWhileItIsListed() {
        let a = Self.claude("a"), b = Self.claude("b"), c = Self.claude("c")
        let stale = Self.claude("a", name: "Named before")
        let fresh = Self.claude("a", name: "Named since")
        XCTAssertEqual(note([fresh, b], .byHand(stale)).pick, fresh, "a listed hand pick is the list's record, not the stored copy")
        XCTAssertEqual(note([a], .byHand(a), complete: false, fresh: false).pick?.id, "a",
                       "a kept partial list keeps a listed hand pick at once")
        XCTAssertEqual(note([b], .byHand(a), complete: false, fresh: false).pick?.id, "a",
                       "a partial list without the hand pick keeps it, since the rest may list it")
        XCTAssertNil(note([b, c], .byHand(a)).pick, "a hand pick gone from the list drops to the responder")
        XCTAssertNil(note([], .byHand(a)).pick, "an empty list drops a hand pick too")
        XCTAssertNil(note([b], .byHand(a)).pick, "a hand pick is not found again after /clear")
        XCTAssertNil(note([a, b], .byHand(nil)).pick, "a hand-picked responder stays")
    }

    @MainActor
    func testALiveNoteKeepsItsWholeListAndItsTargetOverALaterPartialAnswer() {
        let a = Self.claude("a")
        let thread = AgentDestination(id: "t", name: "x", detail: Self.project, address: .codexThread(uuid: "t"))
        let note = LiveNotePopover(at: PopoverPlace(anchor: nil, at: .zero, edge: .below, body: .zero, foot: .zero), target: .session(a))
        note.setSessions(.init(destinations: [a, thread], complete: true, fresh: true))
        note.setSessions(.init(destinations: [thread], complete: false, fresh: false))
        XCTAssertEqual(note.sessionCount, 2, "the next listing's kept Codex list leaves Claude Code's sessions in the menu")
        XCTAssertEqual(note.target, .session(a), "and the session it was sent to last stays its target")
        note.setSessions(.init(destinations: [thread], complete: true, fresh: true))
        XCTAssertEqual(note.sessionCount, 1, "a complete answer replaces the list")
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

    private static func codex(_ id: String) -> AgentDestination {
        AgentDestination(id: id, name: "x", detail: project, address: .codexThread(uuid: id))
    }

    private func send(_ list: [AgentDestination], kept: AgentDestination?, complete: Bool = true, fresh: Bool = true,
                      herdr: HerdrFocus? = nil, cameFrom: (client: AgentClient, shown: String?)? = nil) -> DestinationChoice.Answer {
        DestinationChoice.choose(.init(destinations: list, complete: complete, fresh: fresh, herdr: herdr),
                                 for: .send(cameFrom: cameFrom, kept: kept))
    }

    private static let focusOnB = HerdrFocus(pane: "p", tab: "t", agents: [.init(pane: "p", session: "b", tab: "t")])

    func testSendStartsOnTheKeptPickBeforeTheAgentsAppAndHerdrsFocus() {
        let a = Self.claude("a"), b = Self.claude("b"), shown = Self.codex("shown"), thread = Self.codex("t")
        let overHerdr = send([b, a], kept: a, herdr: Self.focusOnB)
        XCTAssertEqual(overHerdr.pick?.id, "a")
        XCTAssertEqual(overHerdr.pick?.focus, .kept)
        XCTAssertEqual(send([shown, thread, a], kept: thread, cameFrom: (.codex, "shown")).pick?.id, "t",
                       "the kept pick comes before the thread the Codex app shows")
        XCTAssertEqual(send([b, a], kept: nil, herdr: Self.focusOnB).pick?.id, "b", "with no kept pick, herdr's focus")
    }

    func testSendSettlesOnNothingElseUntilTheKeptPickIsListedOrEveryClientHasAnsweredAfresh() {
        let b = Self.claude("b"), thread = Self.codex("t"), other = Self.codex("u")
        let partial = send([b], kept: thread, complete: false, herdr: Self.focusOnB)
        XCTAssertFalse(partial.decided, "herdr's focus does not put another session on the bar first")
        let keptList = send([b, other], kept: thread, complete: true, fresh: false, herdr: Self.focusOnB)
        XCTAssertFalse(keptList.decided, "a kept Codex list may lack a thread the fresh one has")
        XCTAssertFalse(keptList.keptIsGone)
        XCTAssertTrue(send([thread], kept: thread, complete: false, fresh: false).decided,
                      "a kept list that has it settles at once")
        let gone = send([b, other], kept: thread, herdr: Self.focusOnB)
        XCTAssertTrue(gone.keptIsGone)
        XCTAssertEqual(gone.pick?.id, "b", "a gone kept pick gives way to the usual choice")
    }

    func testAnAgentThatListedNoSessionDoesNotEndTheKeptPick() {
        let b = Self.claude("b")
        let failed = send([b], kept: Self.codex("t"), herdr: Self.focusOnB)
        XCTAssertFalse(failed.keptIsGone, "a Codex listing that failed answers no threads at all")
        XCTAssertEqual(failed.pick?.id, "b", "and this image starts on the usual choice")
    }

    func testOnlyASendToAHandPickOrToTheKeptPickKeepsIt() {
        typealias Kept = DestinationChoice.KeptPick
        let a = Self.claude("a"), b = Self.claude("b")
        let then = Date(timeIntervalSince1970: 0), now = Date(timeIntervalSince1970: 300)
        let kept = Kept(session: a, sentAt: then)
        XCTAssertEqual(Kept.after(sendTo: b, isSend: true, handPicked: true, kept: kept, at: now),
                       Kept(session: b, sentAt: now), "another hand pick replaces it")
        XCTAssertEqual(Kept.after(sendTo: a, isSend: true, handPicked: false, kept: kept, at: now),
                       Kept(session: a, sentAt: now), "a send to it starts the window again")
        XCTAssertEqual(Kept.after(sendTo: a, isSend: false, handPicked: false, kept: kept, at: now), kept,
                       "a Reply to it does not")
        XCTAssertEqual(Kept.after(sendTo: b, isSend: true, handPicked: false, kept: kept, at: now), kept,
                       "a send to a start Vignette chose leaves it")
        XCTAssertNil(Kept.after(sendTo: b, isSend: true, handPicked: false, kept: nil, at: now),
                     "a start Vignette chose is never kept")
        let late = Date(timeIntervalSince1970: 900)
        XCTAssertEqual(Kept.after(sendTo: a, isSend: true, handPicked: false, kept: kept, at: late),
                       Kept(session: a, sentAt: late), "the image opened on it, so a send to it renews it after its 10 minutes")
        XCTAssertNil(Kept.after(sendTo: b, isSend: true, handPicked: false, kept: kept, at: late),
                     "a send elsewhere after its 10 minutes ends it")
        XCTAssertNil(Kept.after(sendTo: a, isSend: false, handPicked: false, kept: kept, at: late), "so does a Reply")
    }

    func testTheCodexAppRuleYieldsToACaptureThatShowsAnotherApp() {
        typealias Owner = CaptureRect.Owner
        let app = AgentApp.codexBundleID, herdr = "dev.herdr.app"
        XCTAssertTrue(DestinationChoice.appRuleApplies(app: app, capture: nil), "no capture")
        XCTAssertTrue(DestinationChoice.appRuleApplies(app: app, capture: []), "a capture no window holds")
        XCTAssertTrue(DestinationChoice.appRuleApplies(app: app, capture: [Owner(app: app, share: 0.7), Owner(app: herdr, share: 0.3)]))
        XCTAssertTrue(DestinationChoice.appRuleApplies(app: app, capture: [Owner(app: herdr, share: 0.5), Owner(app: app, share: 0.5)]),
                      "a tie keeps the app")
        XCTAssertFalse(DestinationChoice.appRuleApplies(app: app, capture: [Owner(app: herdr, share: 1)]))
        XCTAssertFalse(DestinationChoice.appRuleApplies(app: app, capture: [Owner(app: herdr, share: 0.6), Owner(app: app, share: 0.4)]))
    }

    func testAKeptPickClearedToANewIdIsNotFoundAgainByItsProject() {
        let cleared = Self.claude("a"), sameProject = Self.claude("a2")
        let answer = send([sameProject], kept: cleared)
        XCTAssertTrue(answer.keptIsGone)
        XCTAssertNil(answer.pick?.focus)
    }

    func testTheResponderIsTheAgentUsedLastAmongThoseThatCanAnswer() {
        let session = Self.claude("a")
        let thread = AgentDestination(id: "t", name: "x", detail: Self.project, address: .codexThread(uuid: "t"))
        XCTAssertEqual(DestinationChoice.responder(among: [thread, session], answering: [.claude, .codex]), .codex)
        XCTAssertEqual(DestinationChoice.responder(among: [session, thread], answering: [.claude, .codex]), .claude)
        XCTAssertEqual(DestinationChoice.responder(among: [thread, session], answering: [.claude]), .claude,
                       "a Codex thread used last does not pick a Codex that cannot answer")
        XCTAssertEqual(DestinationChoice.responder(among: [session], answering: [.codex]), .codex)
        XCTAssertEqual(DestinationChoice.responder(among: [], answering: [.claude, .codex]), .claude, "no sessions: Claude")
        XCTAssertNil(DestinationChoice.responder(among: [thread], answering: []))
    }
}
