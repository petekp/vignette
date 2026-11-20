import XCTest

/// What the annotator's bar offers, and where Send goes. The two rules at risk: Return never sends
/// to a session Vignette picked, and a target on screen is never swapped for another under the
/// pointer when a slower client answers.
@MainActor
final class ToolbarOfferTests: XCTestCase {
    private func session(_ id: String, _ client: AgentClient = .claude, used: TimeInterval = 0) -> AgentDestination {
        AgentDestination(id: id, name: id, address: client == .claude ? .claudeSession(id) : .codexThread(uuid: id),
                         lastUsed: Date(timeIntervalSince1970: used))
    }

    private func answer(_ list: [AgentDestination], complete: Bool, herdr: HerdrFocus? = nil) -> DestinationChoice.Answer {
        DestinationChoice.choose(.init(destinations: list, complete: complete, fresh: true, herdr: herdr), for: .send(cameFrom: nil))
    }

    /// herdr's focus on the pane running session `id`.
    private func inPane(_ id: String) -> HerdrFocus {
        HerdrFocus(pane: "p", tab: "t", agents: [.init(pane: "p", session: id, tab: "t")])
    }

    /// herdr's focus on a pane running no agent, in the tab where session `id` runs.
    private func besideFocus(_ id: String) -> HerdrFocus {
        HerdrFocus(pane: "b", tab: "t", agents: [.init(pane: "p", session: id, tab: "t")])
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

    /// The message field takes the keys as the image opens. Until something is typed in it, Return
    /// and Esc there are the image's, so opening and pressing Return copies rather than sending.
    func testAFieldThatTookTheKeysOnItsOwnSendsOnlyOnceSomethingIsTypedOrASessionIsPicked() {
        let model = AnnotatorToolbar.Model()
        let mew = session("mew")
        model.begin(replyTo: nil, carryingTarget: false)
        model.answered(answer([mew], complete: true, herdr: inPane("mew")))
        model.tookKeysOnOpen = true
        XCTAssertEqual(model.fieldReturn, .done, "Return copies: the target is Vignette's pick")
        XCTAssertTrue(model.fieldEscCloses)
        model.message = " \n "
        XCTAssertEqual(model.fieldReturn, .done, "blank is empty")
        model.message = "fix this"
        XCTAssertEqual(model.fieldReturn, .send)
        XCTAssertFalse(model.fieldEscCloses, "Esc keeps the words and hands the keys back")

        model.message = ""
        model.tookKeysOnOpen = true
        model.pick(session("other"))
        XCTAssertEqual(model.fieldReturn, .send, "a pick chooses the session to write to")
        XCTAssertFalse(model.fieldEscCloses, "Esc after a pick hands the keys back to the image")

        model.begin(replyTo: nil, carryingTarget: true)
        XCTAssertFalse(model.tookKeysOnOpen, "each image starts over")
        XCTAssertEqual(model.fieldReturn, .send, "a field the person moved to sends, as before")
        XCTAssertFalse(model.fieldEscCloses)

        model.begin(replyTo: mew, carryingTarget: false)
        model.tookKeysOnOpen = true
        XCTAssertEqual(model.fieldReturn, .send, "Return replies: the image names where it came from")
    }

    func testReplyIsUnavailableOnlyWhileTheAgentsImageHasNothingNew() {
        let model = AnnotatorToolbar.Model()
        let mew = session("mew")
        model.begin(replyTo: mew, carryingTarget: false)
        model.drawingAsSent = true
        XCTAssertTrue(model.nothingToReply)
        XCTAssertFalse(model.controls.contains(.action))
        model.message = " \n "
        XCTAssertTrue(model.nothingToReply)
        model.message = "bigger"
        XCTAssertFalse(model.nothingToReply)
        XCTAssertTrue(model.controls.contains(.action))
        model.message = ""
        model.drawingAsSent = false
        XCTAssertFalse(model.nothingToReply)

        model.begin(replyTo: nil, carryingTarget: false)
        model.answered(answer([mew], complete: true, herdr: inPane("mew")))
        model.drawingAsSent = true
        XCTAssertFalse(model.nothingToReply)
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
        model.begin(replyTo: nil, carryingTarget: false)
        let codex = session("codex", .codex, used: 200), unfocused = session("other", used: 150)
        model.answered(answer([codex], complete: false))
        XCTAssertNil(model.target, "no focus yet, and the session used last needs every client's answer")
        let beside = session("mew", used: 100)
        model.answered(answer([codex, unfocused, beside], complete: false, herdr: besideFocus("mew")))
        XCTAssertEqual(model.target?.id, "mew")
        model.answered(answer([session("new codex", .codex, used: 300), codex, unfocused, beside], complete: true,
                              herdr: besideFocus("mew")))
        XCTAssertEqual(model.target?.id, "mew", "a later answer does not move a target that is still there")
        model.pick(codex)
        model.answered(answer([beside], complete: true))
        XCTAssertEqual(model.target?.id, "codex", "a pick stays, even when the list no longer has it")
    }

    func testWithNoFocusTheTargetIsTheSessionUsedLastAndIsReplacedOnlyWhenItIsGone() {
        let model = AnnotatorToolbar.Model()
        model.begin(replyTo: nil, carryingTarget: false)
        let old = session("old", used: 100), new = session("new", .codex, used: 200)
        model.answered(answer([new, old], complete: true))
        XCTAssertEqual(model.target?.id, "new")
        model.answered(answer([old], complete: true))
        XCTAssertEqual(model.target?.id, "old")
        model.begin(replyTo: nil, carryingTarget: false)
        XCTAssertNil(model.target, "each image starts over")
    }

    /// A swap keeps the bar up. Emptying the target there took Send and the target off the bar for
    /// the length of the listing, and the bar jumped narrower and back on every swap.
    func testASwapKeepsTheTargetOnTheBarUntilTheNextImagesSettles() {
        let model = AnnotatorToolbar.Model()
        model.begin(replyTo: nil, carryingTarget: false)
        let mew = session("mew"), codex = session("codex", .codex, used: 200)
        let inMewsPane = answer([mew], complete: true, herdr: inPane("mew"))
        let focusedMew = inMewsPane.list[0]
        model.answered(inMewsPane)
        model.begin(replyTo: nil, carryingTarget: true)
        XCTAssertEqual(model.offer, .send(focusedMew))
        model.answered(answer([codex], complete: false))
        XCTAssertEqual(model.target?.id, "mew", "an answer that settles nothing leaves it")
        model.answered(answer([codex, session("other")], complete: false, herdr: inPane("other")))
        XCTAssertEqual(model.target?.id, "other", "this image's own focus replaces it")

        // A reply to a Claude Code session the image before's whole list did not have: that session
        // has closed, so the bar stays Send rather than narrowing to Reply until this list answers.
        model.answered(inMewsPane)
        let gone = session("gone")
        model.begin(replyTo: gone, carryingTarget: true)
        XCTAssertEqual(model.offer, .send(focusedMew))
        model.answered(answer([codex], complete: false))
        XCTAssertEqual(model.offer, .send(focusedMew), "a partial answer does not bring Reply back")
        model.begin(replyTo: focusedMew, carryingTarget: true)
        XCTAssertEqual(model.offer, .reply(focusedMew), "a session the list has is still there")
        model.begin(replyTo: gone, carryingTarget: false)
        XCTAssertEqual(model.offer, .reply(gone), "a new bar has no list yet, so the session may only be late")
    }

    private func answer(_ list: [AgentDestination], complete: Bool, kept: AgentDestination,
                        herdr: HerdrFocus? = nil) -> DestinationChoice.Answer {
        DestinationChoice.choose(.init(destinations: list, complete: complete, fresh: true, herdr: herdr),
                                 for: .send(cameFrom: nil, kept: kept))
    }

    func testOnlyTheTargetPickedInTheMenuIsAHandPick() {
        let model = AnnotatorToolbar.Model()
        let a = session("a"), b = session("b")
        model.begin(replyTo: nil, carryingTarget: false)
        model.answered(answer([a, b], complete: true, kept: b, herdr: inPane("a")))
        XCTAssertFalse(model.isHandPick(b), "a start Vignette chose, the kept pick included, is not one")
        model.pick(a)
        XCTAssertTrue(model.isHandPick(a))
        XCTAssertFalse(model.isHandPick(b))
        model.begin(replyTo: nil, carryingTarget: true)
        XCTAssertFalse(model.isHandPick(a), "a pick belongs to its own image")
    }

    func testAKeptPickSettlesASwappedBarWithoutShowingAnotherSessionFirst() {
        let model = AnnotatorToolbar.Model()
        let before = session("before"), focused = session("focused"), kept = session("kept", .codex)
        model.begin(replyTo: nil, carryingTarget: false)
        model.answered(answer([before], complete: true, herdr: inPane("before")))
        model.begin(replyTo: nil, carryingTarget: true)
        model.answered(answer([focused], complete: false, kept: kept, herdr: inPane("focused")))
        XCTAssertEqual(model.target?.id, "before")
        model.answered(answer([focused, kept], complete: true, kept: kept, herdr: inPane("focused")))
        XCTAssertEqual(model.target?.id, "kept")
    }

    func testAToolLetterTypedFirstPicksItsToolUntilAWordShowsItBeganOne() {
        var held = HeldToolLetter()
        XCTAssertEqual(held.key("a", isRepeat: false, canHold: true, tool: .rectangle), .hold(.arrow))
        XCTAssertEqual(held.key("a", isRepeat: true, canHold: true, tool: .arrow), .swallow)
        XCTAssertEqual(held.key("d", isRepeat: false, canHold: true, tool: .arrow), .type(restoring: .rectangle))
        XCTAssertEqual(held.key("d", isRepeat: false, canHold: false, tool: .rectangle), .pass)

        held = HeldToolLetter()
        XCTAssertEqual(held.key("r", isRepeat: false, canHold: true, tool: .select), .hold(.rectangle))
        held.keepTool()
        XCTAssertEqual(held.key("e", isRepeat: false, canHold: true, tool: .rectangle), .pass)

        held = HeldToolLetter()
        XCTAssertEqual(held.key("t", isRepeat: false, canHold: true, tool: .rectangle), .hold(.text))
        XCTAssertEqual(held.key(nil, isRepeat: false, canHold: true, tool: .text), .pass)
        XCTAssertEqual(held.toolBefore, nil)

        held = HeldToolLetter()
        XCTAssertEqual(held.key("h", isRepeat: false, canHold: true, tool: .rectangle), .pass)
        XCTAssertEqual(held.key("a", isRepeat: false, canHold: false, tool: .rectangle), .pass)
    }

    private func command(_ key: EditorCore.Key, _ modifiers: EditorCore.Modifiers, empty: Bool = false) -> FieldCommand? {
        FieldCommand(key, modifiers, fieldEmpty: empty)
    }

    func testInTheMessageFieldCmdWAndTheZoomKeysAreTheAnnotatorsAndTheEditingKeysStayWithTheField() {
        XCTAssertEqual(command(.character("w"), .command), .close)
        XCTAssertEqual(command(.character("="), .command), .zoom(.zoomIn))
        XCTAssertEqual(command(.character("+"), [.command, .shift]), .zoom(.zoomIn))
        XCTAssertEqual(command(.character("-"), .command), .zoom(.zoomOut))
        XCTAssertEqual(command(.character("0"), .command), .zoom(.fit))
        for editing: Character in ["v", "a", "x", "z", "c"] {
            XCTAssertNil(command(.character(editing), .command), "Cmd+\(editing) stays with the field")
            XCTAssertEqual(command(.character(editing), .command, empty: true) == .copyDrawing, editing == "c")
        }
        XCTAssertNil(command(.character("z"), [.command, .shift]))
        XCTAssertNil(command(.character("w"), [.command, .shift]))
        XCTAssertNil(command(.character("w"), []))
        XCTAssertNil(command(.returnKey, .command))
    }

    func testCmdCInAnEmptyMessageFieldCopiesTheDrawingAndInAFieldWithWordsStaysWithTheField() {
        XCTAssertEqual(command(.character("c"), .command, empty: true), .copyDrawing)
        XCTAssertNil(command(.character("c"), .command, empty: false), "a field with words copies its words")
        XCTAssertNil(command(.character("c"), [.command, .shift], empty: true))

        let model = AnnotatorToolbar.Model()
        model.begin(replyTo: nil, carryingTarget: false)
        model.answered(answer([session("mew")], complete: true, herdr: inPane("mew")))
        XCTAssertFalse(model.tookKeysOnOpen)
        XCTAssertTrue(model.fieldEmpty, "a field pressed into later")
        model.pick(session("mew"))
        XCTAssertTrue(model.fieldEmpty, "a field after a pick")
        model.message = "  \n"
        XCTAssertTrue(model.fieldEmpty, "spaces are no words, as for Return and Esc")
        model.message = "fix this"
        XCTAssertFalse(model.fieldEmpty)
    }

    func testAFieldWhosePanelDoesNotTakeTheKeysOnOpenLetsTheFocusGoSoALaterOfferCanTryAgain() {
        let toolbar = AnnotatorToolbar()
        toolbar.model.begin(replyTo: nil, carryingTarget: false)
        XCTAssertFalse(toolbar.typeOnOpen(), "no field yet")
        toolbar.model.answered(answer([session("mew")], complete: true, herdr: inPane("mew")))
        XCTAssertFalse(toolbar.typeOnOpen(), "a panel off screen never becomes key")
        XCTAssertNil(toolbar.model.focus)
        XCTAssertFalse(toolbar.model.tookKeysOnOpen)
    }

    func testAPickInTheTargetsMenuLandsOnlyOnTheImageWhoseMenuItCameFrom() {
        let toolbar = AnnotatorToolbar()
        let model = toolbar.model
        let a = session("a"), b = session("b")
        model.shown = true
        model.begin(replyTo: nil, carryingTarget: false)
        toolbar.targetMenuActions.onPick?(b, nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(model.target?.id, b.id)

        toolbar.targetMenuActions.onPick?(a, nil)
        model.begin(replyTo: nil, carryingTarget: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(model.target?.id, b.id, "the next image keeps the target it carried")
        XCTAssertFalse(model.isHandPick(a))

        toolbar.targetMenuActions.onPick?(a, nil)
        model.shown = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(model.target?.id, b.id, "a closed bar takes no pick")
    }
}
