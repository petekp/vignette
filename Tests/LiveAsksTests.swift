import CoreGraphics
import XCTest

final class LiveAsksTests: XCTestCase {
    typealias A = LiveAsks

    private func reduce(_ a: inout A, _ event: A.Event) -> [A.Effect] { a.reduce(event) }

    private func ink(_ x: CGFloat = 0) -> Mark { Mark(geometry: .ellipse(CGRect(x: x, y: 0, width: 40, height: 30))) }
    private func arrow() -> Mark { Mark(geometry: .arrow(Mark.Arrow(start: .zero, end: CGPoint(x: 60, y: 40)))) }
    private func shape() -> Mark { Mark(geometry: .ellipse(CGRect(x: 200, y: 0, width: 40, height: 30)), agent: true) }
    private func text(_ words: String, agent: Bool = false) -> Mark {
        Mark(geometry: .text(Mark.Text(origin: .zero, text: words, wrap: nil, size: 14)), agent: agent)
    }

    private func following(_ reply: Mark?, picked: LiveAnswerActions.Pick?, words: String) -> A.Following? {
        reply.map { A.Following(reply: $0, pick: picked ?? .reply, words: words) }
    }

    /// Begins an ask as `LiveInk.ask` does, and answers its id.
    @discardableResult
    private func begin(_ a: inout A, on shown: [Mark], following reply: Mark? = nil, picked: LiveAnswerActions.Pick? = nil,
                       words: String = "and this?", toSession: Bool = false, file: StaticString = #filePath,
                       line: UInt = #line) -> A.Ask.ID {
        switch a.begin(among: shown, following: following(reply, picked: picked, words: words), toSession: toSession) {
        case .began(let id, _, _, _):
            return id
        case .refused(let refusal, _):
            XCTFail("the ask was refused: \(refusal.rawValue)", file: file, line: line)
            return 0
        }
    }

    /// Takes off the marks the effects take off, as `LiveInk.run` does.
    private func takeOff(_ a: inout A, _ effects: [A.Effect]) {
        for case .removeAnswer(_, let gone) in effects where !gone.isEmpty { _ = reduce(&a, .removed(gone)) }
    }

    /// What `LiveInk.showSay` sends when the reply streams in for `id`. Answers whether the ask took it.
    @discardableResult
    private func streamed(_ a: inout A, _ reply: Mark, for id: A.Ask.ID) -> Bool {
        let effects = reduce(&a, .arrived(.replyCame, for: id))
        guard effects.contains(.showReply) else { return false }
        takeOff(&a, effects)
        _ = reduce(&a, .streamed(reply, for: id))
        return true
    }

    /// What `LiveInk.answered` sends when the answer comes for `id`. Answers whether the ask took it.
    @discardableResult
    private func answered(_ a: inout A, _ reply: Mark?, actions: [LiveAnswer.Action] = [], findings: [[Mark.ID]] = [],
                          shown: Set<Mark.ID>, for id: A.Ask.ID) -> Bool {
        let effects = reduce(&a, .arrived(.answerCame, for: id))
        guard effects.contains(.drawAnswer) else { return false }
        takeOff(&a, effects)
        _ = reduce(&a, .answered(reply: reply, actions: actions, findings: findings, shown: shown, for: id))
        return true
    }

    /// Asks about `shown` and draws `reply` with `shapes` as its answer, with no other ask under way.
    @discardableResult
    private func answer(_ a: inout A, on shown: [Mark], reply: Mark, shapes: [Mark] = []) -> A.Ask.ID {
        let id = begin(&a, on: shown)
        XCTAssertEqual(reduce(&a, .arrived(.packetCame, for: id)), [.send(id)])
        answered(&a, reply, actions: [LiveAnswer.Action("Fix it")], findings: shapes.map { [$0.id] }, shown: Set(([reply] + shapes).map(\.id)),
                 for: id)
        return id
    }

    // MARK: Rules

    func testANewAskIsAboutTheInkDrawnSinceTheLastAndAFollowUpAboutTheInkAskedLast() {
        var a = A()
        let first = ink(), second = arrow()
        XCTAssertEqual(a.newInk(among: [first, second]).map(\.id), [first.id, second.id])
        let reply = text("It's a button.", agent: true), loop = shape()
        let id = answer(&a, on: [first, second], reply: reply, shapes: [loop])
        let failure = text("Not sent.")
        _ = reduce(&a, .answerShown([failure.id], for: id))
        let shown = [first, second, reply, loop, failure]
        XCTAssertEqual(a.ink(among: shown).map(\.id), [first.id, second.id],
                       "an agent's marks are not ink, nor is a failure's note in the person's colour")
        XCTAssertEqual(a.newInk(among: shown), [])
        XCTAssertEqual(a.about(among: shown).map(\.id), [first.id, second.id], "with no new ink, a follow-up is about the ink asked last")

        let third = ink(100)
        XCTAssertEqual(a.about(among: shown + [third]).map(\.id), [third.id])
        XCTAssertEqual(A.leader(of: [first, text("this"), second]), second.id, "the newest ink leads, not the person's note")
        let alone = text("this")
        XCTAssertEqual(A.leader(of: [alone]), alone.id, "a note alone leads")
    }

    func testCirclesDrawnAcrossSeveralHoldsAreAllInTheNextAsk() {
        var a = A()
        let first = ink(), second = ink(50), third = ink(100)
        _ = reduce(&a, .drew(first.id))
        _ = reduce(&a, .drew(second.id))
        _ = reduce(&a, .drew(third.id))
        guard case .began(_, let about, _, _) = a.begin(among: [first, second, third], following: nil)
        else { return XCTFail("the ask begins") }
        XCTAssertEqual(about.map(\.id), [first.id, second.id, third.id], "every hold's ink no ask has been about")
        XCTAssertEqual(a.noteInk, [], "ink asked about is the note's no more")
    }

    func testAnAskSentWhileAnotherIsUnderWayWaitsItsTurn() {
        var a = A()
        let first = ink(), second = ink(50), third = ink(100)
        let one = begin(&a, on: [first])
        XCTAssertTrue(a.isUnderWay)
        let two = begin(&a, on: [first, second])
        XCTAssertEqual(a.ask(two)?.about, [second.id], "the next ask is about the ink drawn since")
        XCTAssertEqual(reduce(&a, .arrived(.packetCame, for: two)), [], "its picture is taken at once, but it waits for the ask before it")
        XCTAssertEqual(a.ask(two)?.phase, .waiting)
        XCTAssertEqual(a.queued, [two])
        XCTAssertEqual(a.pulsing, [first.id, second.id], "the ink of both carries the light")
        XCTAssertEqual(reduce(&a, .arrived(.packetCame, for: one)), [.send(one)], "the first goes, since nothing is before it")
        let three = begin(&a, on: [first, second, third])
        XCTAssertEqual(reduce(&a, .arrived(.packetCame, for: three)), [])
        XCTAssertEqual(a.queued, [two, three], "in the order sent")

        let reply = text("It's a button.", agent: true)
        XCTAssertEqual(reduce(&a, .arrived(.answerCame, for: one)), [.drawAnswer])
        XCTAssertEqual(reduce(&a, .answered(reply: reply, actions: [], findings: [], shown: [reply.id], for: one)), [.send(two)],
                       "the answer, once drawn, lets the next go")
        XCTAssertEqual(a.ask(two)?.phase, .asking)
        XCTAssertEqual(reduce(&a, .arrived(.failed(reason: "No.", shown: [first.id, second.id, third.id, reply.id]), for: two)),
                       [.removeAnswer(two, []), .say(two, "No."), .send(three)], "and so does a failure, which says why beside its own ink")
        XCTAssertEqual(a.answerMarks(of: one), [reply.id], "the first answer stays")
        XCTAssertEqual(a.pulsing, [third.id])
    }

    func testAnswersStayBesideTheirInkUntilTheirOwnX() {
        var a = A()
        let first = ink(), second = ink(50), third = ink(100)
        let replies = [text("One", agent: true), text("Two", agent: true), text("Three", agent: true)]
        let loop = shape()
        var ids: [A.Ask.ID] = []
        for n in 1...3 {
            let id = begin(&a, on: Array([first, second, third].prefix(n)))
            _ = reduce(&a, .arrived(.packetCame, for: id))
            ids.append(id)
        }
        answered(&a, replies[0], shown: [replies[0].id], for: ids[0])
        answered(&a, replies[1], shown: [replies[1].id, loop.id], for: ids[1])
        answered(&a, replies[2], shown: [replies[2].id], for: ids[2])
        XCTAssertEqual(a.asks.map(\.phase), [.answered, .answered, .answered])
        XCTAssertEqual(a.answerMarks, [replies[0].id, replies[1].id, replies[2].id, loop.id], "every answer is on the screen")
        XCTAssertEqual(a.answer(of: loop.id), ids[1])
        XCTAssertTrue(ids.allSatisfy(a.offersDismiss))

        XCTAssertEqual(reduce(&a, .dismissed(ids[1])), [.ended(ids[1]), .finish([replies[1].id, loop.id, second.id], .dismissed)],
                       "the middle × takes its own answer and ink")
        XCTAssertEqual(a.asks.map(\.id), [ids[0], ids[2]])
        XCTAssertEqual(reduce(&a, .finished([replies[1].id, loop.id, second.id])), [.remove([replies[1].id, loop.id, second.id])])
        XCTAssertEqual(a.answerMarks, [replies[0].id, replies[2].id], "the others stay")
    }

    func testTheXKeepsInkAnotherAnswerIsAbout() {
        var a = A()
        let mark = ink()
        let first = text("It's a button.", agent: true), second = text("It's blue.", agent: true)
        let one = answer(&a, on: [mark], reply: first)
        let two = answer(&a, on: [mark, first], reply: second)
        XCTAssertEqual(a.ask(two)?.about, [mark.id], "with no new ink, the next ask is about the ink asked about")
        XCTAssertEqual(reduce(&a, .dismissed(one)), [.ended(one), .finish([first.id], .dismissed)], "the second answer still points at the ink")
        XCTAssertEqual(reduce(&a, .dismissed(two)), [.ended(two), .finish([second.id, mark.id], .dismissed)], "the last answer about it takes it")
    }

    func testAnAskWithNoInkIsRefused() {
        var a = A()
        let mark = ink(), note = text("What is this?")
        XCTAssertEqual(a.begin(among: [note], following: nil), .refused(.noInk, effects: []),
                       "a person's note alone is no ink to ask about")
        begin(&a, on: [mark])
        XCTAssertEqual(A.Refusal.noInk.rawValue, "There's no ink to ask about.")
        XCTAssertEqual(A.Refusal.noInk.detail, "no ink")
    }

    func testAnAskBeginsAtItsNewestShapeLedByItsInk() {
        var a = A()
        let first = ink(), second = ink(100), note = text("this")
        guard case .began(let id, let about, let point, _) = a.begin(
            among: [first, note, second], following: nil) else { return XCTFail("the ask begins") }
        XCTAssertEqual(about.map(\.id), [first.id, note.id, second.id], "oldest first")
        XCTAssertEqual(point, CGPoint(x: 120, y: 15), "at the centre of the newest shape")
        XCTAssertEqual(a.newest?.id, id)
        XCTAssertEqual(a.ask(id)?.leader, second.id, "the newest ink leads, not the person's note")
    }

    func testAPacketIsTakenOnlyWhileItsAskIsLookingAndMovesItToAsking() {
        var a = A()
        let id = begin(&a, on: [ink()])
        XCTAssertEqual(reduce(&a, .arrived(.packetCame, for: id)), [.send(id)])
        XCTAssertEqual(a.ask(id)?.phase, .asking)
        let asking = a
        XCTAssertEqual(reduce(&a, .arrived(.packetCame, for: id)), [], "a second packet is not sent")
        XCTAssertEqual(a, asking)

        _ = reduce(&a, .cleared)
        let cleared = a
        XCTAssertEqual(reduce(&a, .arrived(.packetCame, for: id)), [], "nothing is sent after a clear")
        XCTAssertEqual(a, cleared)
    }

    func testAPacketFromAClearedAskIsDroppedAndTheNextAskTakesItsOwn() {
        var a = A()
        let mark = ink()
        let old = begin(&a, on: [mark])
        _ = reduce(&a, .cleared)
        let next = begin(&a, on: [mark])
        let before = a
        XCTAssertEqual(reduce(&a, .arrived(.packetCame, for: old)), [],
                       "the cleared ask's words and picture are not sent as the next question")
        XCTAssertEqual(a, before)
        XCTAssertEqual(a.ask(next)?.phase, .looking)
        XCTAssertEqual(reduce(&a, .arrived(.packetCame, for: next)), [.send(next)], "the next ask sends its own")
    }

    func testTheConversationIsTheReplyFromTheAskAndCarriesTheLightUntilAnswered() {
        var a = A()
        let mark = ink()
        var conversation = text("", agent: true)
        conversation.quote = "What is this?"
        let id = begin(&a, on: [mark])
        _ = reduce(&a, .conversed(conversation, for: id))
        XCTAssertEqual(a.ask(id)?.say, conversation, "the reply's words come into the conversation")
        XCTAssertEqual(a.answer(of: conversation.id), id, "it is the ask's")
        XCTAssertEqual(a.pulsing, [mark.id, conversation.id], "it carries the light with the ink while the packet is made")
        XCTAssertEqual(a.newInk(among: [mark, conversation]), [], "and is not ink")
        _ = reduce(&a, .arrived(.packetCame, for: id))
        XCTAssertEqual(a.pulsing, [mark.id, conversation.id], "and while the responder works")
        XCTAssertEqual(reduce(&a, .arrived(.replyCame, for: id)), [.showReply], "the reply keeps it")
        answered(&a, conversation, shown: [conversation.id], for: id)
        XCTAssertEqual(a.pulsing, [], "the light goes once answered")
    }

    func testAFailureSaysWhyInTheConversationAndKeepsIt() {
        var a = A()
        let mark = ink()
        let conversation = text("", agent: true)
        let id = begin(&a, on: [mark])
        _ = reduce(&a, .conversed(conversation, for: id))
        _ = reduce(&a, .arrived(.packetCame, for: id))
        XCTAssertEqual(reduce(&a, .arrived(.failed(reason: "Claude stopped.", shown: [mark.id, conversation.id]), for: id)),
                       [.removeAnswer(id, []), .notice(reply: conversation.id, reason: "Claude stopped.")])
        XCTAssertEqual(a.ask(id)?.phase, .failed)
        XCTAssertEqual(a.answerMarks, [conversation.id], "it stays as the answer, saying why")
        XCTAssertTrue(a.isSettledAnswer(conversation.id), "which Esc can close")
        XCTAssertEqual(a.pulsing, [], "with its light off")
        XCTAssertEqual(reduce(&a, .dismissed(id)), [.ended(id), .finish([mark.id, conversation.id], .dismissed)], "the × takes it with the ink")
    }

    func testANoteSentToASessionLeavesWithItsConversation() {
        var a = A()
        let mark = ink()
        let conversation = text("", agent: true)
        let id = begin(&a, on: [mark], toSession: true)
        _ = reduce(&a, .conversed(conversation, for: id))
        XCTAssertEqual(reduce(&a, .arrived(.packetCame, for: id)), [.share(about: [mark.id])])
        XCTAssertEqual(reduce(&a, .arrived(.sentToSession(ink: [mark.id]), for: id)), [.ended(id), .finish([mark.id, conversation.id], .dismissed)])
        XCTAssertNil(a.ask(id), "the ask ends once the session has the note")
    }

    func testANoteToASessionNeitherWaitsForNorHoldsUpTheResponder() {
        var a = A()
        let first = ink(), second = ink(50), third = ink(100)
        let one = begin(&a, on: [first])
        _ = reduce(&a, .arrived(.packetCame, for: one))
        let note = begin(&a, on: [first, second], toSession: true)
        XCTAssertEqual(reduce(&a, .arrived(.packetCame, for: note)), [.share(about: [second.id])], "it goes while the responder answers")
        let two = begin(&a, on: [first, second, third])
        _ = reduce(&a, .arrived(.packetCame, for: two))
        XCTAssertEqual(a.queued, [two], "the next ask to the responder waits only for the one the responder has")
        XCTAssertEqual(reduce(&a, .arrived(.answerCame, for: one)), [.drawAnswer])
        XCTAssertEqual(reduce(&a, .answered(reply: nil, actions: [], findings: [], shown: [], for: one)), [.send(two)],
                       "and goes while the note is still being stored")
    }

    func testTheReplyStreamsOnlyWhileAskingAndAnAnswerIsTakenOnlyWhileUnderWay() {
        var a = A()
        let mark = ink()
        let id = begin(&a, on: [mark])
        var before = a
        XCTAssertEqual(reduce(&a, .arrived(.replyCame, for: id)), [], "no reply before the packet went")
        XCTAssertEqual(a, before)

        _ = reduce(&a, .arrived(.packetCame, for: id))
        let reply = text("It's", agent: true)
        XCTAssertTrue(streamed(&a, reply, for: id))
        XCTAssertEqual(a.ask(id)?.say, reply)
        XCTAssertTrue(a.isAnswer(reply.id))
        answered(&a, reply, shown: [reply.id], for: id)
        before = a
        XCTAssertEqual(reduce(&a, .arrived(.replyCame, for: id)), [], "no reply after the answer")
        XCTAssertEqual(reduce(&a, .arrived(.answerCame, for: id)), [], "nor a second answer")
        XCTAssertEqual(reduce(&a, .arrived(.failed(reason: "No.", shown: [reply.id]), for: id)), [], "nor a failure")
        XCTAssertEqual(a, before)

        let failing = begin(&a, on: [mark])
        _ = reduce(&a, .arrived(.packetCame, for: failing))
        _ = reduce(&a, .arrived(.failed(reason: "No.", shown: [mark.id]), for: failing))
        before = a
        XCTAssertEqual(reduce(&a, .arrived(.replyCame, for: failing)), [], "no reply after a failure")
        XCTAssertEqual(a, before)

        _ = reduce(&a, .cleared)
        before = a
        XCTAssertEqual(reduce(&a, .arrived(.answerCame, for: failing)), [], "no answer after a clear")
        XCTAssertEqual(a, before)
    }

    func testAReplyAndAnAnswerFromADismissedAskAreDropped() {
        var a = A()
        let first = ink(), second = ink(50)
        let old = begin(&a, on: [first])
        _ = reduce(&a, .arrived(.packetCame, for: old))
        let next = begin(&a, on: [first, second])
        XCTAssertEqual(reduce(&a, .arrived(.packetCame, for: next)), [])
        XCTAssertEqual(reduce(&a, .dismissed(old)), [.ended(old), .interrupt, .finish([first.id], .dismissed), .send(next)],
                       "the × ends the ask at once, stops the responder's turn on it, and the next goes")
        XCTAssertNil(a.ask(old))
        let late = text("About the first", agent: true)
        XCTAssertFalse(streamed(&a, late, for: old), "the next ask does not show the dismissed one's reply")
        XCTAssertFalse(answered(&a, late, shown: [late.id], for: old), "nor its answer")
        XCTAssertFalse(a.isAnswer(late.id))
        XCTAssertEqual(a.ask(next)?.phase, .asking)
        XCTAssertNil(a.ask(next)?.say)

        let own = text("About the second", agent: true)
        XCTAssertTrue(streamed(&a, own, for: next))
        XCTAssertTrue(answered(&a, own, shown: [own.id], for: next))
        XCTAssertEqual(a.ask(next)?.phase, .answered)
    }

    func testALateFailureFromADismissedAskLeavesTheOtherAnswersAlone() {
        var a = A()
        let first = ink(), second = ink(50)
        let old = begin(&a, on: [first])
        _ = reduce(&a, .arrived(.packetCame, for: old))
        guard case .finish(let ids, _)? = reduce(&a, .dismissed(old)).last else { return XCTFail("the × finishes the ink") }
        _ = reduce(&a, .finished(ids))
        let next = answer(&a, on: [second], reply: text("About the second", agent: true))
        let shown = a

        XCTAssertEqual(reduce(&a, .arrived(.failed(reason: "Claude stopped.", shown: [second.id]), for: old)), [],
                       "a dismissed ask's failure does not turn into a note")
        XCTAssertEqual(a, shown)
        guard case .text(let words)? = a.ask(next)?.say?.geometry else { return XCTFail("the answer has its reply") }
        XCTAssertEqual(words.text, "About the second")
    }

    func testACaptureFailureFromAClearedAskLeavesTheNextAskLooking() {
        var a = A()
        let mark = ink()
        let old = begin(&a, on: [mark])
        _ = reduce(&a, .cleared)
        let next = begin(&a, on: [mark])
        let before = a
        XCTAssertEqual(reduce(&a, .arrived(.failed(reason: "Vignette couldn't see the screen.", shown: [mark.id]), for: old)), [],
                       "the next ask is not failed, and nothing says so beside its ink")
        XCTAssertEqual(a, before)
        XCTAssertEqual(reduce(&a, .arrived(.packetCame, for: next)), [.send(next)])
    }

    func testAnAskWhosePictureFailsLetsTheAsksBehindItGo() {
        var a = A()
        let first = ink(), second = ink(50)
        let one = begin(&a, on: [first])
        let two = begin(&a, on: [first, second])
        XCTAssertEqual(reduce(&a, .arrived(.packetCame, for: two)), [], "the first is still looking")
        XCTAssertEqual(reduce(&a, .arrived(.failed(reason: "Vignette couldn't see the screen.", shown: [first.id, second.id]), for: one)),
                       [.removeAnswer(one, []), .say(one, "Vignette couldn't see the screen."), .send(two)])
    }

    func testAnAnswerTakesTheReplysPlaceAndOffersItsActions() {
        var a = A()
        let mark = ink(), reply = text("It's a button.", agent: true), earlier = shape()
        let first = answer(&a, on: [mark], reply: reply, shapes: [earlier])
        let follow = begin(&a, on: [mark, reply, earlier], following: reply, picked: .action("Fix it"), words: "Fix it")
        XCTAssertNil(a.ask(first), "the ask from the picked button takes the answer's place")
        XCTAssertEqual(a.answer(of: reply.id), follow, "with its marks")
        XCTAssertEqual(a.ask(follow)?.picked, .action("Fix it"))
        XCTAssertFalse(a.offersDismiss(follow), "no × while the ask from a picked button is under way")
        XCTAssertEqual(a.pulsing, [mark.id, reply.id, earlier.id], "the earlier answer pulses with the ink while that ask is under way")
        var queued = A()
        answer(&queued, on: [mark], reply: reply)
        var noticed = reply
        noticed.notice = "Queued."
        let pending = begin(&queued, on: [mark, noticed], following: noticed, picked: .action("Fix it"), words: "Fix it")
        XCTAssertTrue(queued.offersDismiss(pending), "an ask whose reply carries a notice still offers the ×")
        XCTAssertEqual(reduce(&a, .arrived(.packetCame, for: follow)), [.send(follow)])
        XCTAssertEqual(reduce(&a, .arrived(.answerCame, for: follow)), [.removeAnswer(follow, [earlier.id]), .drawAnswer],
                       "the earlier answer goes, all but the reply the next one takes the place of")
        XCTAssertEqual(a.answerMarks, [reply.id])
        let next = text("Fixed.", agent: true), loop = shape()
        _ = reduce(&a, .answered(reply: next, actions: [LiveAnswer.Action("Undo")], findings: [[loop.id]], shown: [next.id, loop.id], for: follow))
        XCTAssertEqual(a.ask(follow)?.phase, .answered)
        XCTAssertEqual(a.ask(follow)?.say, next)
        XCTAssertNil(a.ask(follow)?.picked, "the next answer's buttons are enabled")
        XCTAssertEqual(a.ask(follow)?.actions, [LiveAnswer.Action("Undo")])
        XCTAssertEqual(a.ask(follow)?.findings, [[loop.id]])
        XCTAssertTrue(a.isAnswer(next.id) && a.isAnswer(loop.id))
        XCTAssertTrue(a.offersDismiss(follow))
    }

    func testAFollowUpWaitsItsTurnBehindAFreshAskAndStaysOnItsAnswer() {
        var a = A()
        let mark = ink(), other = ink(50), reply = text("It's a button.", agent: true), elsewhere = text("It's a link.", agent: true)
        let first = answer(&a, on: [mark], reply: reply)
        let fresh = begin(&a, on: [mark, reply, other])
        _ = reduce(&a, .arrived(.packetCame, for: fresh))
        let follow = begin(&a, on: [mark, reply, other], following: reply, picked: .reply)
        XCTAssertEqual(reduce(&a, .arrived(.packetCame, for: follow)), [], "the reply waits for the fresh ask sent before it")
        XCTAssertEqual(a.queued, [follow])
        XCTAssertNil(a.ask(first))
        XCTAssertEqual(reduce(&a, .arrived(.answerCame, for: fresh)), [.drawAnswer])
        XCTAssertEqual(reduce(&a, .answered(reply: elsewhere, actions: [], findings: [], shown: [elsewhere.id], for: fresh)), [.send(follow)])
        XCTAssertEqual(a.answer(of: reply.id), follow, "the follow-up still hangs from its own answer's reply")
        XCTAssertEqual(a.answer(of: elsewhere.id), fresh)
    }

    func testAFailureAfterAPickedButtonPutsItsAnswerBackWithTheTypedWords() {
        var a = A()
        let mark = ink(), reply = text("It's a button.", agent: true)
        let first = answer(&a, on: [mark], reply: reply)
        let earlier = a.ask(first)!
        var quoting = reply
        quoting.quote = "and this?"
        let follow = begin(&a, on: [mark, quoting], following: quoting, picked: .reply, words: "and this?")
        _ = reduce(&a, .arrived(.packetCame, for: follow))

        XCTAssertEqual(reduce(&a, .arrived(.failed(reason: "Claude stopped.", shown: [mark.id, reply.id]), for: follow)),
                       [.ended(follow), .restore(reply: reply.id, reason: "Claude stopped.", aside: [])])
        var noticed = reply
        noticed.notice = "Claude stopped."
        _ = reduce(&a, .replyRedrawn(noticed))
        var expected = earlier
        expected.say = noticed
        expected.reason = "Claude stopped."
        expected.draft = "and this?"
        XCTAssertEqual(a.asks, [expected], "the earlier answer is back in its place, its id included, with the typed words in Reply")
        XCTAssertEqual(a.answer(of: reply.id), first)
        XCTAssertEqual(reduce(&a, .arrived(.failed(reason: "Again.", shown: [mark.id, reply.id]), for: follow)), [],
                       "the restored answer has its own id, so the ask from the picked button takes nothing more")

        let noInk = A.Refusal.noInk.rawValue
        var action = A()
        let answeredID = answer(&action, on: [mark], reply: reply)
        XCTAssertEqual(action.begin(among: [reply], following: A.Following(reply: reply, pick: .action("Fix it"), words: "Fix it")),
                       .refused(.noInk, effects: [.restore(reply: reply.id, reason: noInk, aside: [])]), "an ask refused before it began puts it back too")
        XCTAssertEqual(action.newest?.id, answeredID)
        XCTAssertEqual(action.newest?.reason, noInk)
        XCTAssertEqual(action.newest?.draft, "", "an action's words are not typed words")

        var typed = A()
        answer(&typed, on: [mark], reply: reply)
        XCTAssertEqual(typed.begin(among: [reply], following: A.Following(reply: reply, pick: .reply, words: "and this?")),
                       .refused(.noInk, effects: [.restore(reply: reply.id, reason: noInk, aside: [])]))
        XCTAssertEqual(typed.newest?.draft, "and this?", "typed words wait in Reply again")

        var gone = A()
        answer(&gone, on: [mark], reply: reply)
        let failing = begin(&gone, on: [mark, reply], following: reply, picked: .reply)
        _ = reduce(&gone, .arrived(.packetCame, for: failing))
        XCTAssertEqual(reduce(&gone, .arrived(.failed(reason: "Claude stopped.", shown: [mark.id]), for: failing)),
                       [.removeAnswer(failing, [reply.id]), .say(failing, "Claude stopped.")],
                       "with its reply off the screen, there is nothing to put back, and the failure is a note")
        XCTAssertEqual(gone.ask(failing)?.phase, .failed)
    }

    func testOnceTheReplyOfAnAskFromAPickedButtonStartsTheEarlierAnswerIsSetAsideUntilTheNewAnswerComes() {
        var a = A()
        let mark = ink(), reply = text("It's a button.", agent: true), loop = shape()
        answer(&a, on: [mark], reply: reply, shapes: [loop])
        let follow = begin(&a, on: [mark, reply], following: reply, picked: .reply)
        _ = reduce(&a, .arrived(.packetCame, for: follow))
        XCTAssertEqual(reduce(&a, .arrived(.replyCame, for: follow)), [.setAside(follow, [loop.id]), .showReply])
        XCTAssertEqual(a.answerMarks, [reply.id], "the loop is no longer the answer's once the reply starts")
        _ = reduce(&a, .streamed(reply, for: follow))
        var failing = a
        XCTAssertEqual(reduce(&failing, .arrived(.failed(reason: "Claude stopped.", shown: [mark.id, reply.id]), for: follow)),
                       [.ended(follow), .restore(reply: reply.id, reason: "Claude stopped.", aside: [loop.id])],
                       "a failure while the reply streams puts the earlier answer back")
        XCTAssertEqual(failing.answerMarks, [reply.id, loop.id])
        XCTAssertEqual(reduce(&a, .arrived(.answerCame, for: follow)), [.removeAnswer(follow, [loop.id]), .drawAnswer],
                       "once the new answer comes, the earlier one goes for good")
        XCTAssertEqual(reduce(&a, .arrived(.failed(reason: "Claude stopped.", shown: [mark.id, reply.id]), for: follow)),
                       [.removeAnswer(follow, []), .notice(reply: reply.id, reason: "Claude stopped.")],
                       "after that nothing is put back, and the reply says why")
    }

    func testDismissingWhileAFollowUpStreamsFinishesTheSetAsideAnswerToo() {
        var a = A()
        let mark = ink(), reply = text("It's a button.", agent: true), loop = shape(), focus = shape()
        answer(&a, on: [mark], reply: reply, shapes: [loop])
        let follow = begin(&a, on: [mark, reply, loop], following: reply, picked: .reply)
        _ = reduce(&a, .answerShown([focus.id], for: follow))
        _ = reduce(&a, .arrived(.packetCame, for: follow))
        XCTAssertTrue(streamed(&a, reply, for: follow))
        XCTAssertEqual(reduce(&a, .dismissed(follow)), [.ended(follow), .interrupt, .finish([mark.id, reply.id, loop.id, focus.id], .dismissed)])
    }

    func testANewAskLeavesEarlierAnswersAndAnAskFromAPickedButtonKeepsItsReply() {
        var a = A()
        let mark = ink(), other = ink(50), reply = text("It's a button.", agent: true), loop = shape(), more = shape()
        let first = answer(&a, on: [mark], reply: reply, shapes: [loop, more])
        let shown = [mark, reply, loop, more, other]

        var fresh = a
        let next = begin(&fresh, on: shown)
        XCTAssertEqual(fresh.answerMarks(of: first), [reply.id, loop.id, more.id], "a fresh ask takes nothing off")
        XCTAssertEqual(fresh.asks.map(\.id), [first, next])

        let follow = begin(&a, on: shown, following: reply)
        _ = reduce(&a, .arrived(.packetCame, for: follow))
        XCTAssertEqual(reduce(&a, .arrived(.replyCame, for: follow)), [.setAside(follow, [loop.id, more.id]), .showReply])
        XCTAssertEqual(a.answerMarks, [reply.id])
    }

    func testDismissingFinishesTheAnswerAndTheInkItWasAbout() {
        var a = A()
        let first = ink(), second = ink(50), reply = text("It's a button.", agent: true), loop = shape()
        let id = answer(&a, on: [first, second], reply: reply, shapes: [loop])
        let all: Set = [first.id, second.id, reply.id, loop.id]
        XCTAssertEqual(reduce(&a, .dismissed(id)), [.ended(id), .finish(all, .dismissed)])
        XCTAssertEqual(a.finishing, Dictionary(uniqueKeysWithValues: all.map { ($0, .dismissed) }), "they are leaving as the × asked")
        XCTAssertNil(a.ask(id))

        var empty = A()
        XCTAssertEqual(reduce(&empty, .dismissed(id)), [])
    }

    func testDismissingAnAskUnderWayEndsItAndItsInkIsNoLongerAskedOnceGone() {
        var a = A()
        let first = ink(), second = ink(50)
        let id = begin(&a, on: [first, second])
        XCTAssertEqual(reduce(&a, .dismissed(id)), [.ended(id), .finish([first.id, second.id], .dismissed)], "an ask still looking has no turn to stop")
        XCTAssertFalse(a.isUnderWay, "a dismissed note leaves nothing under way")
        XCTAssertEqual(reduce(&a, .finished([first.id])), [.remove([first.id])])
        XCTAssertEqual(a.newInk(among: [second]), [], "ink still leaving stays asked")
        XCTAssertEqual(reduce(&a, .finished([second.id])), [.remove([second.id])])
    }

    func testAnAnswerWithNoMarksLeftEnds() {
        var a = A()
        let mark = ink(), reply = text("It's a button.", agent: true), loop = shape()
        let id = answer(&a, on: [mark], reply: reply, shapes: [loop])
        _ = reduce(&a, .removed([loop.id]))
        XCTAssertNotNil(a.ask(id))
        _ = reduce(&a, .removed([reply.id]))
        XCTAssertNil(a.ask(id), "nothing of it is left to close")
        XCTAssertEqual(a.about(among: [mark]).map(\.id), [mark.id], "its ink stays asked about")

        let under = begin(&a, on: [mark])
        _ = reduce(&a, .removed([mark.id]))
        XCTAssertNotNil(a.ask(under), "an ask under way stays, whatever is erased")
    }

    func testAFinishAfterAClearDoesNothing() {
        var a = A()
        let mark = ink()
        let id = begin(&a, on: [mark])
        _ = reduce(&a, .dismissed(id))
        _ = reduce(&a, .cleared)
        _ = reduce(&a, .drew(mark.id))
        let before = a
        XCTAssertEqual(reduce(&a, .finished([mark.id])), [])
        XCTAssertEqual(a, before)
    }

    func testAnOverlappingFinishIsEndedByTheFirstTimer() {
        var a = A()
        let first = ink(), second = ink(50), reply = text("It's a button.", agent: true)
        let id = answer(&a, on: [first, second], reply: reply)
        _ = reduce(&a, .answerClosed)
        _ = reduce(&a, .dismissed(id))
        XCTAssertEqual(a.finishing, [reply.id: .dismissed], "the × of an answer Esc closed does nothing more")
        let other = begin(&a, on: [first, second])
        _ = reduce(&a, .dismissed(other))
        XCTAssertEqual(reduce(&a, .finished([reply.id, first.id])), [.remove([reply.id, first.id])],
                       "the first timer takes the marks a later finish had started on")
        XCTAssertEqual(a.finishing, [second.id: .dismissed])
        XCTAssertEqual(reduce(&a, .finished([first.id])), [], "and the later timer finds nothing to do")
    }

    func testClearingForgetsEveryAskAndRoleButTheNotesInk() {
        var a = A()
        let drawn = ink(), other = ink(50), reply = text("It's a button.", agent: true), loop = shape()
        _ = reduce(&a, .drew(drawn.id))
        let id = answer(&a, on: [drawn], reply: reply, shapes: [loop])
        let queued = begin(&a, on: [drawn, other])
        _ = reduce(&a, .arrived(.packetCame, for: queued))
        _ = reduce(&a, .dismissed(id))
        _ = reduce(&a, .cleared)
        XCTAssertEqual(a.asks, [], "every ask ends, those waiting their turn too")
        XCTAssertFalse(a.isUnderWay)
        XCTAssertEqual(a.begin(among: [], following: A.Following(reply: reply, pick: .reply, words: "and this?")),
                       .refused(.noInk, effects: []), "nothing is put back after a clear")
        XCTAssertEqual(a.newInk(among: [drawn, other]), [drawn, other], "the ink is new again")
        XCTAssertEqual(a.answerMarks, [])
        XCTAssertEqual(a.finishing, [:])
        XCTAssertEqual(a.noteInk, [], "a clear takes every mark, so the note has no ink left")
    }

    func testAWindowGoingForgetsOnlyItsMarksAskedAndAnswerRoles() {
        var a = A()
        let gone = ink(), stays = ink(50), reply = text("It's a button.", agent: true)
        _ = reduce(&a, .drew(gone.id))
        let id = answer(&a, on: [gone, stays], reply: reply)
        _ = reduce(&a, .dismissed(id))
        _ = reduce(&a, .windowGone([gone.id, reply.id]))
        XCTAssertEqual(a.newInk(among: [gone, stays]), [gone], "only the marks that went are new again")
        XCTAssertFalse(a.isAnswer(reply.id))
        XCTAssertEqual(a.noteInk, [], "ink gone with its window is the note's no more")
        XCTAssertEqual(a.finishing[gone.id], .dismissed, "and so is its finish")

        var other = A()
        let answered = answer(&other, on: [gone], reply: reply)
        _ = reduce(&other, .windowGone([reply.id]))
        XCTAssertNil(other.ask(answered), "an answer whose marks went with their window ends")
    }

    func testAnErasedMarkLosesItsRolesAndItsFinish() {
        var a = A()
        let mark = ink(), reply = text("It's a button.", agent: true), loop = shape()
        let id = answer(&a, on: [mark], reply: reply, shapes: [loop])
        let asked = a.ask(id)
        XCTAssertEqual(reduce(&a, .removed([loop.id])), [])
        XCTAssertEqual(a.ask(id), asked, "the ask is untouched")
        XCTAssertFalse(a.isAnswer(loop.id))
        var dismissed = a
        XCTAssertEqual(reduce(&dismissed, .dismissed(id)), [.ended(id), .finish([mark.id, reply.id], .dismissed)], "the × no longer finishes the erased loop")

        var inkErased = a
        _ = reduce(&inkErased, .removed([mark.id]))
        XCTAssertEqual(inkErased.ask(id), asked, "erased ink stays in what the ask is about")
        XCTAssertEqual(reduce(&inkErased, .dismissed(id)), [.ended(id), .finish([mark.id, reply.id], .dismissed)], "so the × still finishes it")

        let follow = begin(&a, on: [mark, reply], following: reply, picked: .reply)
        XCTAssertEqual(a.ask(follow)?.about, [mark.id, reply.id], "the ask from a picked button is not about the erased loop")
        XCTAssertFalse(a.pulsing.contains(loop.id))

        var note = A()
        let first = ink(), second = ink(50)
        _ = reduce(&note, .drew(first.id))
        _ = reduce(&note, .drew(second.id))
        _ = reduce(&note, .removed([first.id]))
        XCTAssertEqual(reduce(&note, .noteDiscarded), [.remove([second.id])], "Esc takes back only the note's ink still there")

        var leaving = A()
        let left = answer(&leaving, on: [mark], reply: reply, shapes: [loop])
        _ = reduce(&leaving, .dismissed(left))
        _ = reduce(&leaving, .removed([reply.id]))
        XCTAssertFalse(leaving.isFinishing(reply.id), "a mark erased while leaving is no longer leaving")
        XCTAssertTrue(leaving.isFinishing(mark.id))
    }

    func testTheNotesInkIsAllTheInkNoAskHasBeenAbout() {
        var a = A()
        let asked = ink(), first = ink(50), second = ink(100)
        _ = reduce(&a, .drew(asked.id))
        begin(&a, on: [asked])
        _ = reduce(&a, .drew(first.id))
        _ = reduce(&a, .drew(second.id))
        XCTAssertEqual(a.noteInk, [first.id, second.id], "one note for all the new ink, however many holds drew it")
        XCTAssertEqual(reduce(&a, .noteDiscarded), [.remove([first.id, second.id])], "ink an earlier ask was about stays")
        XCTAssertEqual(a.noteInk, [])
    }

    func testStoppingAnAskGivesItsNewInkBackToTheNote() {
        var a = A()
        let asked = ink(), fresh = ink(50), erased = ink(100)
        _ = reduce(&a, .drew(asked.id))
        begin(&a, on: [asked])
        _ = reduce(&a, .drew(fresh.id))
        _ = reduce(&a, .drew(erased.id))
        let id = begin(&a, on: [asked, fresh, erased])
        XCTAssertEqual(a.noteInk, [])
        _ = reduce(&a, .removed([erased.id]))
        _ = reduce(&a, .cancelled(id, shown: [asked.id, fresh.id]))
        XCTAssertEqual(a.noteInk, [fresh.id], "the ink that was new is the note's again, but not ink erased meanwhile")

        var two = A()
        _ = reduce(&two, .drew(fresh.id))
        let first = begin(&two, on: [fresh])
        begin(&two, on: [fresh], toSession: true)
        _ = reduce(&two, .cancelled(first, shown: [fresh.id]))
        XCTAssertEqual(two.noteInk, [], "ink another ask is about stays out of the note")
        XCTAssertEqual(two.newInk(among: [fresh]), [], "and stays asked")
    }

    func testADraftIsKeptOnlyForTheReplyThePanelWasMadeFor() {
        var a = A()
        let mark = ink(), other = ink(50), reply = text("It's a button.", agent: true), elsewhere = text("Elsewhere", agent: true)
        let first = answer(&a, on: [mark], reply: reply)
        _ = reduce(&a, .drafted("half typed", reply: reply.id))
        XCTAssertEqual(a.ask(first)?.draft, "half typed")

        let next = answer(&a, on: [mark, reply, other], reply: elsewhere)
        _ = reduce(&a, .drafted("more", reply: reply.id))
        XCTAssertEqual(a.ask(first)?.draft, "more", "each answer on the screen keeps its own")
        XCTAssertEqual(a.ask(next)?.draft, "", "and none goes to another")
        let before = a
        _ = reduce(&a, .drafted("no reply", reply: nil))
        XCTAssertEqual(a, before, "a panel made with no reply keeps nothing")
    }

    func testASessionsAnswerIsTakenOnlyByItsAsk() {
        var a = A()
        let first = ink(), second = ink(50), beside = ink(100)
        let id = begin(&a, on: [first], toSession: true)
        XCTAssertEqual(reduce(&a, .arrived(.packetCame, for: id)), [.share(about: [first.id])])
        let shared = a

        XCTAssertEqual(reduce(&a, .arrived(.sentToSession(ink: [beside.id]), for: id)),
                       [.ended(id), .finish([first.id, beside.id], .dismissed)], "the ink in the card's picture leaves with the ink asked about")
        XCTAssertEqual(a.finishing, [first.id: .dismissed, beside.id: .dismissed])
        a = shared
        XCTAssertEqual(reduce(&a, .arrived(.failed(reason: "Not sent.", shown: [first.id]), for: id)), [.removeAnswer(id, []), .say(id, "Not sent.")])
        XCTAssertEqual(a.ask(id)?.phase, .failed)

        a = shared
        _ = reduce(&a, .cleared)
        XCTAssertEqual(reduce(&a, .arrived(.sentToSession(ink: []), for: id)), [], "not after a clear")
        let next = begin(&a, on: [second], toSession: true)
        XCTAssertEqual(reduce(&a, .arrived(.failed(reason: "Not sent.", shown: []), for: id)), [], "not by another ask")
        XCTAssertEqual(reduce(&a, .arrived(.sentToSession(ink: []), for: next)), [.ended(next), .finish([second.id], .dismissed)])
    }

    func testASessionsCardKeepsInkAnotherAnswerIsAbout() {
        var a = A()
        let mark = ink(), other = ink(50), reply = text("It's a button.", agent: true)
        answer(&a, on: [mark], reply: reply)
        let note = begin(&a, on: [mark, reply, other], toSession: true)
        _ = reduce(&a, .arrived(.packetCame, for: note))
        XCTAssertEqual(reduce(&a, .arrived(.sentToSession(ink: [mark.id, other.id]), for: note)), [.ended(note), .finish([other.id], .dismissed)],
                       "the answer up still points at its ink")
    }

    func testAPickedAnswerMarkIsNoLongerTheAnswers() {
        var a = A()
        let mark = ink(), reply = text("Which one?", agent: true), loop = shape()
        answer(&a, on: [mark], reply: reply, shapes: [loop])
        _ = reduce(&a, .removed([loop.id]))
        XCTAssertFalse(a.isAnswer(loop.id))
        XCTAssertEqual(a.answerMarks, [reply.id])
    }

    func testAFailureIsTakenBeforeAClearButNotAfter() {
        var a = A()
        let mark = ink()
        let id = begin(&a, on: [mark])
        _ = reduce(&a, .arrived(.packetCame, for: id))
        var stopped = a
        XCTAssertEqual(reduce(&stopped, .arrived(.failed(reason: "Claude stopped.", shown: [mark.id]), for: id)),
                       [.removeAnswer(id, []), .say(id, "Claude stopped.")], "an ask takes a failure until it is cleared")
        _ = reduce(&a, .cleared)
        let cleared = a
        XCTAssertEqual(reduce(&a, .arrived(.failed(reason: "Claude stopped.", shown: [mark.id]), for: id)), [])
        XCTAssertEqual(a, cleared)
    }

    func testAPictureIsRecordedOnItsOwnAsk() {
        var a = A()
        let mark = ink()
        let old = begin(&a, on: [mark])
        _ = reduce(&a, .cleared)
        let next = begin(&a, on: [mark])
        _ = reduce(&a, .pictureSent(fresh: true, for: old))
        XCTAssertEqual(a.ask(next)?.picture, false, "a cleared ask's picture is not the next one's")
        _ = reduce(&a, .pictureSent(fresh: true, for: next))
        XCTAssertEqual(a.ask(next)?.picture, true)
    }

    // MARK: Esc

    func testStoppingAFirstAskTakesItsReplyAndLeavesTheInkNewAgain() {
        var a = A()
        let mark = ink(), conversation = text("Is this a button?")
        let id = begin(&a, on: [mark])
        _ = reduce(&a, .conversed(conversation, for: id))
        XCTAssertTrue(a.newInk(among: [mark]).isEmpty)
        XCTAssertEqual(a.cancellable(sendsWait: false), id)
        XCTAssertEqual(reduce(&a, .cancelled(id, shown: [mark.id, conversation.id])), [.ended(id), .removeAnswer(id, [conversation.id])],
                       "an ask still looking has nothing at the responder to stop")
        XCTAssertNil(a.ask(id))
        XCTAssertFalse(a.isUnderWay)
        XCTAssertEqual(a.newInk(among: [mark]).map(\.id), [mark.id], "the ink is askable as new again")
        XCTAssertFalse(a.isAnswer(conversation.id))
        XCTAssertEqual(reduce(&a, .arrived(.answerCame, for: id)), [], "the answer that comes late is dropped")
        XCTAssertEqual(reduce(&a, .arrived(.failed(reason: "Claude stopped.", shown: [mark.id]), for: id)), [], "and so is a failure")
        _ = begin(&a, on: [mark])
        XCTAssertTrue(a.isUnderWay, "a new ask can begin at once")
    }

    func testEscStopsTheNewestAskFirstAndTheResponderOnlyForTheOneItHas() {
        var a = A()
        let first = ink(), second = ink(50), third = ink(100)
        let one = begin(&a, on: [first])
        _ = reduce(&a, .arrived(.packetCame, for: one))
        let two = begin(&a, on: [first, second])
        _ = reduce(&a, .arrived(.packetCame, for: two))
        let three = begin(&a, on: [first, second, third])
        XCTAssertEqual(a.cancellable(sendsWait: false), three, "the newest goes first")
        XCTAssertEqual(reduce(&a, .cancelled(three, shown: [])), [.ended(three), .removeAnswer(three, [])], "a waiting ask was never sent")
        XCTAssertEqual(a.cancellable(sendsWait: false), two)
        XCTAssertEqual(reduce(&a, .cancelled(two, shown: [])), [.ended(two), .removeAnswer(two, [])])
        XCTAssertEqual(a.newInk(among: [first, second, third]).map(\.id), [second.id, third.id])
        XCTAssertEqual(reduce(&a, .cancelled(one, shown: [])), [.ended(one), .interrupt, .removeAnswer(one, [])], "the one the responder has is interrupted")

        var b = A()
        let asking = begin(&b, on: [first])
        _ = reduce(&b, .arrived(.packetCame, for: asking))
        let waiting = begin(&b, on: [first, second])
        _ = reduce(&b, .arrived(.packetCame, for: waiting))
        XCTAssertEqual(reduce(&b, .cancelled(asking, shown: [])), [.ended(asking), .interrupt, .removeAnswer(asking, []), .send(waiting)],
                       "stopping the one the responder has lets the next go")
    }

    func testStoppingASessionAskWithdrawsItsNoteIfItIsStoredAfterAll() {
        var a = A()
        let mark = ink()
        let id = begin(&a, on: [mark], toSession: true)
        XCTAssertEqual(a.cancellable(sendsWait: true), id)
        XCTAssertNil(a.cancellable(sendsWait: false), "with no grace, nothing can take the send back")
        XCTAssertEqual(reduce(&a, .arrived(.packetCame, for: id)), [.share(about: [mark.id])])
        let shared = a

        _ = reduce(&a, .cancelled(id, shown: [mark.id]))
        XCTAssertEqual(reduce(&a, .arrived(.sentToSession(ink: [mark.id]), for: id)), [.withdraw])
        XCTAssertEqual(reduce(&a, .arrived(.sentToSession(ink: [mark.id]), for: id)), [], "once")

        a = shared
        _ = reduce(&a, .cancelled(id, shown: [mark.id]))
        XCTAssertEqual(reduce(&a, .arrived(.failed(reason: "Not sent.", shown: [mark.id]), for: id)), [])
        XCTAssertEqual(reduce(&a, .arrived(.sentToSession(ink: [mark.id]), for: id)), [], "a refused send has nothing to withdraw")

        a = shared
        _ = reduce(&a, .arrived(.sentToSession(ink: [mark.id]), for: id))
        XCTAssertNil(a.cancellable(sendsWait: true), "a stored send is taken back with Don't send")
    }

    func testStoppingASessionAskBeforeItsPacketSendsNothing() {
        var a = A()
        let mark = ink()
        let id = begin(&a, on: [mark], toSession: true)
        _ = reduce(&a, .cancelled(id, shown: [mark.id]))
        XCTAssertEqual(reduce(&a, .arrived(.packetCame, for: id)), [])
        XCTAssertEqual(reduce(&a, .arrived(.sentToSession(ink: [mark.id]), for: id)), [])
    }

    func testStoppingAnAskAboutInkAskedBeforeLeavesThatInkAsked() {
        var a = A()
        let mark = ink(), reply = text("It's a button.", agent: true)
        answer(&a, on: [mark], reply: reply)
        _ = reduce(&a, .answerClosed)
        _ = reduce(&a, .finished([reply.id]))
        let id = begin(&a, on: [mark])
        XCTAssertEqual(reduce(&a, .arrived(.packetCame, for: id)), [.send(id)])
        _ = reduce(&a, .cancelled(id, shown: [mark.id]))
        XCTAssertTrue(a.newInk(among: [mark]).isEmpty, "ink that was asked about before stays asked about")
        XCTAssertEqual(a.about(among: [mark]).map(\.id), [mark.id])
    }

    func testStoppingAFollowUpPutsTheAnswerBackWithNoSentence() {
        var a = A()
        let mark = ink(), reply = text("It's a button.", agent: true), loop = shape()
        let first = answer(&a, on: [mark], reply: reply, shapes: [loop])
        let earlier = a.ask(first)!
        var quoting = reply
        quoting.quote = "and this?"
        let follow = begin(&a, on: [mark, quoting, loop], following: quoting, picked: .reply, words: "and this?")
        _ = reduce(&a, .arrived(.packetCame, for: follow))
        XCTAssertEqual(reduce(&a, .cancelled(follow, shown: [mark.id, reply.id, loop.id])),
                       [.ended(follow), .interrupt, .restore(reply: reply.id, reason: nil, aside: [])])
        var expected = earlier
        expected.draft = "and this?"
        XCTAssertEqual(a.asks, [expected], "the earlier answer is back as it was, with the typed words waiting in Reply")
        XCTAssertTrue(a.isAnswer(reply.id) && a.isAnswer(loop.id))
        XCTAssertEqual(a.answer(of: loop.id), first)
        XCTAssertEqual(reduce(&a, .arrived(.answerCame, for: follow)), [], "the stopped ask takes nothing more")
    }

    func testStoppingAFollowUpThatStartedToReplyBringsTheAnswerBack() {
        var a = A()
        let mark = ink(), reply = text("It's a button.", agent: true), loop = shape()
        let first = answer(&a, on: [mark], reply: reply, shapes: [loop])
        let earlier = a.ask(first)!
        let follow = begin(&a, on: [mark, reply, loop], following: reply, picked: .reply, words: "and this?")
        _ = reduce(&a, .arrived(.packetCame, for: follow))
        var streaming = reply
        streaming.geometry = .text(Mark.Text(origin: .zero, text: "It's a", wrap: nil, size: 14))
        XCTAssertTrue(streamed(&a, streaming, for: follow))
        XCTAssertEqual(reduce(&a, .cancelled(follow, shown: [mark.id, reply.id])),
                       [.ended(follow), .interrupt, .restore(reply: reply.id, reason: nil, aside: [loop.id])])
        var expected = earlier
        expected.draft = "and this?"
        XCTAssertEqual(a.asks, [expected], "the earlier answer is back with its first words, not the ones that streamed")
        XCTAssertEqual(a.answerMarks, [reply.id, loop.id])

        var gone = A()
        answer(&gone, on: [mark], reply: reply, shapes: [loop])
        let stopped = begin(&gone, on: [mark, reply, loop], following: reply, picked: .reply)
        _ = reduce(&gone, .arrived(.packetCame, for: stopped))
        XCTAssertTrue(streamed(&gone, reply, for: stopped))
        XCTAssertEqual(reduce(&gone, .cancelled(stopped, shown: [mark.id])), [.ended(stopped), .interrupt, .removeAnswer(stopped, [reply.id, loop.id])],
                       "with its reply off the screen, the set-aside answer goes with the reply")
        XCTAssertEqual(gone.asks, [])
        XCTAssertTrue(gone.answerMarks.isEmpty)
    }

    func testStoppingAnAskDoesNothingWhenItIsNotUnderWay() {
        var a = A()
        XCTAssertEqual(reduce(&a, .cancelled(1, shown: [])), [])
        let mark = ink(), reply = text("It's a button.", agent: true)
        let id = answer(&a, on: [mark], reply: reply)
        XCTAssertNil(a.cancellable(sendsWait: true))
        let before = a
        XCTAssertEqual(reduce(&a, .cancelled(id, shown: [mark.id, reply.id])), [])
        XCTAssertEqual(a, before, "an answered ask is not stopped")
    }

    func testEscClosesTheNewestAnswerFirstAndKeepsTheInk() {
        var a = A()
        let first = ink(), second = ink(50), reply = text("It's a button.", agent: true), loop = shape(), later = text("Later", agent: true)
        let one = answer(&a, on: [first], reply: reply, shapes: [loop])
        let two = answer(&a, on: [first, second], reply: later)
        XCTAssertEqual(reduce(&a, .answerClosed), [.ended(two), .finish([later.id], .dismissed)], "the newest first")
        XCTAssertNil(a.ask(two))
        XCTAssertEqual(reduce(&a, .answerClosed), [.ended(one), .finish([reply.id, loop.id], .dismissed)], "then the one before")
        XCTAssertNil(a.ask(one))
        XCTAssertEqual(Set(a.finishing.keys), [later.id, reply.id, loop.id], "only the answers are leaving")
        XCTAssertEqual(reduce(&a, .finished([reply.id, loop.id])), [.remove([reply.id, loop.id])])
        XCTAssertEqual(a.ink(among: [first]).map(\.id), [first.id])
        XCTAssertEqual(reduce(&a, .answerClosed), [], "with no answer left there is nothing to close")
    }

    func testClosingAnAnswerPassesOverAsksUnderWay() {
        var a = A()
        let mark = ink(), other = ink(50), reply = text("It's a button.", agent: true), conversation = text("", agent: true)
        let first = answer(&a, on: [mark], reply: reply)
        let next = begin(&a, on: [mark, reply, other])
        _ = reduce(&a, .conversed(conversation, for: next))
        XCTAssertFalse(a.isSettledAnswer(conversation.id), "a conversation waiting for its answer is not one Esc closes")
        XCTAssertEqual(reduce(&a, .answerClosed), [.ended(first), .finish([reply.id], .dismissed)])
        XCTAssertNil(a.ask(first))
        XCTAssertNotNil(a.ask(next))
    }

    // MARK: Random sequences

    /// Plays random sequences through `LiveAsksEnvironment` and checks the asks' invariants after
    /// every event.
    func testEveryWayAnAskEndsSaysSoFirst() {
        let mark = ink(), reply = text("It's a button.", agent: true)

        var dismissed = A()
        let x = answer(&dismissed, on: [mark], reply: reply)
        XCTAssertEqual(reduce(&dismissed, .dismissed(x)), [.ended(x), .finish([reply.id, mark.id], .dismissed)], "the ×")

        var closed = A()
        let esc = answer(&closed, on: [mark], reply: reply)
        XCTAssertEqual(reduce(&closed, .answerClosed), [.ended(esc), .finish([reply.id], .dismissed)], "Esc on an answer")

        var stopped = A()
        let stop = begin(&stopped, on: [mark])
        XCTAssertEqual(reduce(&stopped, .cancelled(stop, shown: [mark.id])), [.ended(stop), .removeAnswer(stop, [])], "Esc on an ask under way")

        var shared = A()
        let note = begin(&shared, on: [mark], toSession: true)
        _ = reduce(&shared, .arrived(.packetCame, for: note))
        XCTAssertEqual(reduce(&shared, .arrived(.sentToSession(ink: [mark.id]), for: note)), [.ended(note), .finish([mark.id], .dismissed)],
                       "a note a session took")

        var erased = A()
        let gone = answer(&erased, on: [mark], reply: reply)
        XCTAssertEqual(reduce(&erased, .removed([reply.id])), [.ended(gone)], "an answer with no marks left")

        var windowGone = A()
        let away = answer(&windowGone, on: [mark], reply: reply)
        XCTAssertEqual(reduce(&windowGone, .windowGone([reply.id])), [.ended(away)], "an answer whose window went")

        var cleared = A()
        let one = answer(&cleared, on: [mark], reply: reply), two = begin(&cleared, on: [mark])
        XCTAssertEqual(reduce(&cleared, .cleared), [.ended(one), .ended(two)], "a clear, oldest first")

        var followed = A()
        let earlier = answer(&followed, on: [mark], reply: reply)
        guard case .began(let follow, _, _, let effects) = followed.begin(
            among: [mark, reply], following: A.Following(reply: reply, pick: .reply, words: "and this?")) else { return XCTFail("the follow-up begins") }
        XCTAssertEqual(effects, [.ended(earlier)], "an answer a follow-up takes the place of")
        XCTAssertEqual(reduce(&followed, .cancelled(follow, shown: [mark.id, reply.id])),
                       [.ended(follow), .restore(reply: reply.id, reason: nil, aside: [])], "a follow-up whose answer comes back")
    }

    func testRandomSequencesKeepTheInvariants() {
        var dropped = 0, restores = 0, otherAsk = 0, overlapping = 0, refused = 0, setAside = 0, broughtBack = 0
        var stopped = 0, withdrawals = 0, queued = 0, coexisting = 0, interrupted = 0, closed = 0, sharedInk = 0
        for seed in 0..<2000 {
            var lastID = 0
            var answeredAsks: Set<A.Ask.ID> = []
            var withdrawn: Set<A.Ask.ID> = []
            let env = LiveAsksEnvironment(seed: seed) { env, sent in
                func fail(_ message: String) -> String { "\(message) (seed \(seed))\n" + env.trace.joined(separator: "\n") }
                let (before, after) = (sent.before, sent.after)
                let ended = sent.effects.prefix { if case .ended = $0 { true } else { false } }
                let effects = Array(sent.effects.dropFirst(ended.count))
                XCTAssertEqual(Array(ended), before.asks.map(\.id).filter { after.ask($0) == nil }.map(A.Effect.ended),
                               fail("every ask that leaves says so first, oldest first"))
                XCTAssertFalse(effects.contains { if case .ended = $0 { true } else { false } }, fail("and only first"))
                let all = Set(env.made.map(\.id))
                func answers(_ asks: A, but id: A.Ask.ID?) -> [A.Ask.ID: Set<Mark.ID>] {
                    Dictionary(uniqueKeysWithValues: asks.asks.filter { $0.id != id }.map { ($0.id, asks.answerMarks(of: $0.id)) })
                }
                /// Every other ask's answer is untouched, those that ended aside.
                func othersKept(but id: A.Ask.ID?) {
                    let then = answers(before, but: id), now = answers(after, but: id)
                    for (other, marks) in now where then[other] != nil { XCTAssertEqual(marks, then[other], fail("another ask's answer is left as it was")) }
                }
                func nothingToPutBack(_ id: A.Ask.ID?) -> Bool {
                    guard let id, after.ask(id)?.isUnderWay == true else { return true }
                    var probe = after
                    return !probe.reduce(.arrived(.failed(reason: "probe", shown: all), for: id)).contains {
                        if case .restore = $0 { true } else { false }
                    }
                }
                func keepsNoRole(_ ids: Set<Mark.ID>) -> Bool {
                    let marks = env.made.filter { ids.contains($0.id) }
                    return ids.allSatisfy { after.finishing[$0] == nil && !after.isAnswer($0) }
                        && after.newInk(among: marks) == after.ink(among: marks)
                }
                func checkFinishes() {
                    for case .finish(let ids, let how) in effects {
                        if !Set(before.finishing.keys).isDisjoint(with: ids) { overlapping += 1 }
                        XCTAssertTrue(ids.allSatisfy { after.finishing[$0] == how }, fail("finishing marks are set leaving, as the effect says"))
                    }
                }
                func checkRestore(_ reply: Mark.ID, saying said: String?, _ reason: String) {
                    restores += 1
                    XCTAssertEqual(said, reason, fail("the answer put back says why"))
                    guard let back = after.ask(withReply: reply) else { return XCTFail(fail("the answer put back hangs from its reply")) }
                    XCTAssertEqual(back.phase, .answered, fail("the answer put back is an answer"))
                    XCTAssertNil(back.picked, fail("with its buttons enabled"))
                    XCTAssertEqual(back.reason, reason, fail("with the reason"))
                    XCTAssertTrue(answeredAsks.contains(back.id), fail("an answer that was drawn is what comes back"))
                    XCTAssertEqual(after.answer(of: reply), back.id, fail("and its reply is its own again"))
                }
                func checkBroughtBack(_ brought: Set<Mark.ID>, owner: A.Ask.ID?) {
                    if !brought.isEmpty { broughtBack += 1 }
                    XCTAssertTrue(brought.allSatisfy { after.answer(of: $0) == owner }, fail("what was set aside is the answer's again"))
                }
                func checkFailure(_ id: A.Ask.ID, _ reason: String) {
                    guard !effects.isEmpty else { return }
                    let ending = effects.filter { if case .send = $0 { false } else { true } }
                    switch ending.last {
                    case .restore(let reply, let said, let brought):
                        XCTAssertEqual(ending.count, 1, fail("an answer put back is all that is answered"))
                        checkRestore(reply, saying: said, reason)
                        checkBroughtBack(brought, owner: after.ask(withReply: reply)?.id)
                    case .notice(let reply, let said):
                        XCTAssertEqual(reply, before.ask(id)?.say?.id, fail("a failure says why in the conversation"))
                        XCTAssertEqual(ending.first, .removeAnswer(id, before.answerMarks(of: id).subtracting([reply]).union(env.aside(of: id))),
                                       fail("which alone stays of its answer"))
                        XCTAssertEqual(ending.count, 2, fail("and says why"))
                        XCTAssertEqual(after.answerMarks(of: id), [reply], fail("it is the answer"))
                        XCTAssertEqual(said, reason, fail("saying why"))
                        XCTAssertEqual(after.ask(id)?.phase, .failed, fail("a taken failure fails the ask"))
                        XCTAssertEqual(after.ask(id)?.reason, reason, fail("and keeps why"))
                    case .say(let failed, let said):
                        XCTAssertEqual(failed, id, fail("the note is the failed ask's"))
                        XCTAssertEqual(ending.first, .removeAnswer(id, before.answerMarks(of: id).union(env.aside(of: id))),
                                       fail("a failure's note takes its own answer's place"))
                        XCTAssertEqual(ending.count, 2, fail("and says why"))
                        XCTAssertEqual(after.answerMarks(of: id), [], fail("nothing is its answer once it went"))
                        XCTAssertEqual(said, reason, fail("the note says why"))
                        XCTAssertEqual(after.ask(id)?.phase, .failed, fail("a taken failure fails the ask"))
                        XCTAssertEqual(after.ask(id)?.reason, reason, fail("and keeps why"))
                    default: XCTFail(fail("a failure puts the answer back or says why"))
                    }
                }

                let event: A.Event
                switch sent.step {
                case .begun(let begun, let shown, let following):
                    let about = before.about(among: shown)
                    switch begun {
                    case .refused(let refusal, let effects):
                        refused += 1
                        XCTAssertNil(about.last?.shapeExtent, fail("only an ask with no ink is refused"))
                        XCTAssertEqual(refusal, .noInk)
                        if case .restore(let reply, let said, _)? = effects.first {
                            XCTAssertEqual(effects.count, 1, fail("a refusal puts back the answer and does nothing else"))
                            XCTAssertEqual(said, refusal.rawValue, fail("saying why"))
                            XCTAssertNotNil(after.ask(withReply: reply), fail("and the answer stays"))
                        } else {
                            XCTAssertEqual(effects, [], fail("a refusal answers nothing but an answer put back"))
                            XCTAssertEqual(after, before, fail("and changes nothing"))
                        }
                    case .began(let id, let asked, _, _):
                        XCTAssertNotNil(about.last?.shapeExtent, fail("an ask begins only about ink"))
                        if before.isUnderWay { queued += 1 }
                        XCTAssertEqual(asked.map(\.id), about.map(\.id), fail("it is about the ink it says"))
                        XCTAssertEqual(after.newest?.id, id, fail("the ask begun is the newest"))
                        XCTAssertEqual(after.ask(id)?.phase, .looking, fail("an ask begins looking"))
                        XCTAssertGreaterThan(id, lastID, fail("each ask's id is above every earlier one"))
                        lastID = id
                        if following {
                            let reply = after.ask(id)?.say?.id
                            XCTAssertNil(reply.flatMap { before.ask(withReply: $0) }.flatMap { after.ask($0.id) },
                                         fail("an ask from a picked button takes its answer's place"))
                        } else {
                            othersKept(but: id)
                            XCTAssertEqual(after.answerMarks, before.answerMarks, fail("a fresh ask takes no answer off"))
                        }
                    }
                    return
                case .event(let sentEvent):
                    event = sentEvent
                }
                if case .arrived(let arrival, let id) = event, withdrawn.remove(id) != nil {
                    withdrawals += 1
                    if case .sentToSession = arrival {
                        XCTAssertEqual(effects, [.withdraw], fail("a stopped session ask's stored note is taken back"))
                    } else {
                        XCTAssertEqual(effects, [], fail("what comes back for a stopped session ask answers nothing else"))
                    }
                    var forgot = after
                    _ = forgot.reduce(.arrived(arrival, for: id))
                    XCTAssertEqual(forgot, after, fail("and only its first arrival is taken"))
                    return
                }
                if case .arrived(_, let id) = event {
                    if effects.isEmpty {
                        dropped += 1
                        XCTAssertEqual(after.asks.filter { $0.id != id }, before.asks.filter { $0.id != id },
                                       fail("what an ask does not take leaves every other ask as it was"))
                    }
                    if before.ask(id)?.isUnderWay != true {
                        otherAsk += 1
                        XCTAssertEqual(effects, [], fail("what comes back for an ask no longer under way answers nothing"))
                        XCTAssertEqual(after, before, fail("and changes nothing"))
                    }
                }
                // Each ask the responder is sent was waiting, and is the oldest to it under way.
                for case .send(let id) in effects {
                    XCTAssertEqual(after.ask(id)?.phase, .asking, fail("an ask sent is asking"))
                    XCTAssertEqual(after.asks.first { $0.isUnderWay && !$0.toSession }?.id, id, fail("in the order sent"))
                    XCTAssertTrue(before.ask(id)?.phase == .waiting || before.ask(id)?.phase == .looking, fail("having waited for its turn"))
                }
                switch event {
                case .arrived(.packetCame, let id) where !effects.isEmpty:
                    if before.ask(id)?.toSession == true {
                        XCTAssertEqual(effects, [.share(about: before.ask(id)?.about ?? [])], fail("a session is sent the ink asked about"))
                        XCTAssertEqual(after, before, fail("and the ask waits for its answer as it was"))
                    } else {
                        XCTAssertEqual(effects, [.send(id)], fail("the packet goes when no ask before it is with the responder"))
                    }
                case .arrived(.packetCame, let id):
                    if before.ask(id)?.phase == .looking, before.ask(id)?.toSession == false {
                        XCTAssertEqual(after.ask(id)?.phase, .waiting, fail("an ask behind another waits with its packet"))
                    }
                case .arrived(.replyCame, let id) where !effects.isEmpty, .arrived(.answerCame, let id) where !effects.isEmpty:
                    let drawn = effects.filter { if case .send = $0 { false } else { true } }
                    XCTAssertTrue(drawn.last == .showReply || drawn.last == .drawAnswer, fail("a taken reply or answer is drawn"))
                    othersKept(but: id)
                    let earlier = before.answerMarks(of: id).filter { $0 != before.ask(id)?.say?.id }
                    for case .setAside(let owner, let ids) in effects {
                        if !ids.isEmpty { setAside += 1 }
                        XCTAssertEqual(owner, id)
                        XCTAssertEqual(ids, earlier, fail("as the reply starts, the earlier answer is set aside, all but its reply"))
                        XCTAssertTrue(after.answerMarks.isDisjoint(with: ids), fail("and is not the answer's while aside"))
                    }
                    for case .removeAnswer(let owner, let gone) in effects {
                        XCTAssertEqual(owner, id)
                        XCTAssertEqual(gone, earlier.union(env.aside(of: id)), fail("the earlier answer goes, all but its reply, with what was set aside"))
                        XCTAssertTrue(after.answerMarks.isDisjoint(with: gone), fail("and is no longer the answer's"))
                    }
                    if case .arrived(.answerCame, _) = event {
                        XCTAssertTrue(nothingToPutBack(id), fail("once an answer comes, nothing is put back"))
                    }
                case .arrived(.failed(let reason, _), let id):
                    if before.ask(id)?.isUnderWay == true {
                        checkFailure(id, reason)
                        othersKept(but: id)
                    }
                case .arrived(.sentToSession(let ink), let id) where !effects.isEmpty:
                    let others = before.asks.filter { $0.id != id }.reduce(into: Set<Mark.ID>()) { $0.formUnion($1.about) }
                    let ids = (before.ask(id)?.about ?? []).union(ink).subtracting(others).union(before.answerMarks(of: id))
                    if !ink.subtracting(before.ask(id)?.about ?? []).isDisjoint(with: others) { sharedInk += 1 }
                    XCTAssertEqual(effects, [.finish(ids, .dismissed)], fail("a session's card takes the ink and the conversation"))
                    XCTAssertNil(after.ask(id), fail("and ends the ask"))
                    checkFinishes()
                case .streamed(_, let id):
                    XCTAssertEqual(after.ask(id)?.phase, before.ask(id)?.phase, fail("streaming never changes the phase"))
                case .conversed(let reply, let id):
                    guard after.ask(id) != nil else { break }
                    XCTAssertEqual(after.ask(id)?.say, reply, fail("the conversation is the reply"))
                    XCTAssertEqual(after.answer(of: reply.id), id, fail("and the ask's"))
                    if after.ask(id)?.isUnderWay == true { XCTAssertTrue(after.pulsing.contains(reply.id), fail("and carries the light")) }
                case .answered(_, _, _, _, let id):
                    XCTAssertEqual(after.ask(id)?.phase, .answered, fail("a drawn answer answers the ask"))
                    answeredAsks.insert(id)
                    if after.asks.filter({ $0.phase == .answered }).count > 1 { coexisting += 1 }
                case .dismissed(let id):
                    checkFinishes()
                    XCTAssertNil(after.ask(id), fail("the × ends its ask"))
                    guard let ask = before.ask(id) else {
                        XCTAssertEqual(effects, [], fail("the × of an ask that ended does nothing"))
                        break
                    }
                    let others = before.asks.filter { $0.id != id }.reduce(into: Set<Mark.ID>()) { $0.formUnion($1.about) }
                    if !ask.about.isDisjoint(with: others) { sharedInk += 1 }
                    let ids = before.answerMarks(of: id).union(ask.about.subtracting(others)).union(env.aside(of: id))
                    XCTAssertEqual(effects.first == .interrupt, ask.phase == .asking, fail("the × stops the responder only for the ask it has"))
                    if ask.phase == .asking { interrupted += 1 }
                    XCTAssertEqual(effects.filter { if case .send = $0 { false } else { $0 != .interrupt } }, ids.isEmpty ? [] : [.finish(ids, .dismissed)],
                                   fail("the × finishes its answer, what was set aside, and the ink only it was about"))
                    othersKept(but: id)
                case .cancelled(let id, _):
                    guard let ask = before.ask(id), ask.isUnderWay else {
                        XCTAssertEqual(effects, [], fail("Esc stops nothing that is not under way"))
                        XCTAssertEqual(after, before, fail("and changes nothing"))
                        break
                    }
                    if ask.toSession { withdrawn.insert(id) }
                    XCTAssertEqual(effects.first == .interrupt, ask.phase == .asking, fail("the responder is stopped only for the ask it has"))
                    if ask.phase == .asking { interrupted += 1 }
                    let ending = effects.filter { $0 != .interrupt && { if case .send = $0 { false } else { true } }($0) }
                    if case .restore(let reply, let said, let brought)? = ending.last {
                        stopped += 1
                        XCTAssertNil(said, fail("an answer Esc puts back says nothing"))
                        checkBroughtBack(brought, owner: after.ask(withReply: reply)?.id)
                        XCTAssertEqual(after.ask(withReply: reply)?.phase, .answered, fail("the answer put back is an answer"))
                    } else {
                        XCTAssertEqual(ending, [.removeAnswer(id, before.answerMarks(of: id).union(env.aside(of: id)))],
                                       fail("Esc takes its reply off, with what was set aside"))
                        XCTAssertNil(after.ask(id), fail("and ends the ask"))
                    }
                    othersKept(but: id)
                case .answerClosed:
                    checkFinishes()
                    let newest = before.asks.last { !$0.isUnderWay && before.answerMarks(of: $0.id).contains { !before.isFinishing($0) } }
                    if let newest {
                        closed += 1
                        XCTAssertEqual(effects, [.finish(before.answerMarks(of: newest.id), .dismissed)], fail("Esc closes the newest answer"))
                        XCTAssertNil(after.ask(newest.id))
                    } else {
                        XCTAssertEqual(effects, [], fail("with no answer up, Esc closes nothing"))
                    }
                case .noteDiscarded:
                    XCTAssertEqual(effects, before.noteInk.isEmpty ? [] : [.remove(before.noteInk)], fail("Esc takes back the note's ink"))
                    XCTAssertEqual(after.noteInk, [], fail("and the note has no ink left"))
                case .removed(let ids):
                    XCTAssertEqual(effects, [], fail("a mark taken off answers nothing"))
                    XCTAssertEqual(after.asks.filter(\.isUnderWay), before.asks.filter(\.isUnderWay), fail("and leaves the asks under way as they were"))
                    XCTAssertTrue(keepsNoRole(ids), fail("it keeps no role and no finish"))
                    XCTAssertTrue(after.noteInk.isDisjoint(with: ids), fail("and is not the note's ink"))
                case .windowGone(let ids):
                    XCTAssertEqual(after.noteInk, before.noteInk.subtracting(ids), fail("a window going takes its marks from the note's ink"))
                    XCTAssertEqual(after.finishing, before.finishing, fail("and every finish"))
                    XCTAssertTrue(after.answerMarks.isDisjoint(with: ids), fail("its marks are not the answer's"))
                case .drafted(let words, let reply):
                    if let reply, let owner = before.ask(withReply: reply) {
                        XCTAssertEqual(after.ask(owner.id)?.draft, words, fail("the answer the panel was made for keeps its words"))
                        var back = after
                        _ = back.reduce(.drafted(owner.draft, reply: reply))
                        XCTAssertEqual(back, before, fail("and nothing else changes"))
                    } else {
                        XCTAssertEqual(after, before, fail("another answer keeps none"))
                    }
                case .finished(let ids):
                    let leaving = !Set(before.finishing.keys).isDisjoint(with: ids)
                    XCTAssertEqual(!effects.isEmpty, leaving, fail("a timer acts exactly when one of its marks is leaving"))
                    if effects.isEmpty {
                        XCTAssertEqual(after, before, fail("a timer with nothing to do changes nothing"))
                    } else {
                        XCTAssertEqual(effects, [.remove(ids)], fail("a timer removes its own marks"))
                        XCTAssertTrue(keepsNoRole(ids), fail("a finished mark keeps no role"))
                    }
                case .cleared:
                    XCTAssertEqual(after.asks, [], fail("a clear ends every ask"))
                    XCTAssertTrue(keepsNoRole(all), fail("a clear forgets every role and finish"))
                    XCTAssertEqual(after.noteInk, [], fail("a clear leaves the note no ink"))
                default:
                    break
                }
                // What holds after every event.
                let toResponder = after.asks.filter { $0.isUnderWay && !$0.toSession }
                XCTAssertLessThanOrEqual(after.asks.filter { $0.phase == .asking }.count, 1, fail("the responder has one ask at a time"))
                XCTAssertNotEqual(toResponder.first?.phase, .waiting, fail("an ask whose turn has come is sent"))
                XCTAssertTrue(toResponder.dropFirst().allSatisfy { $0.phase != .asking }, fail("only the oldest is with the responder"))
                XCTAssertEqual(Set(after.asks.map(\.id)).count, after.asks.count, fail("each ask once"))
                for ask in after.asks { XCTAssertTrue(after.noteInk.isDisjoint(with: ask.about), fail("no ask's ink is the note's")) }
                for ask in after.asks where ask.phase == .answered { XCTAssertNil(ask.picked, fail("an answer's buttons are enabled")) }
                let underWay = after.asks.filter(\.isUnderWay)
                XCTAssertEqual(after.pulsing, underWay.reduce(into: Set<Mark.ID>()) { $0.formUnion($1.about); if let say = $1.say { $0.insert(say.id) } },
                               fail("what pulses is what the asks under way are about, and their replies"))
                for id in all where after.isAnswer(id) && !after.isFinishing(id) {
                    XCTAssertNotNil(after.answer(of: id).flatMap(after.ask), fail("a mark of an answer on the screen belongs to an ask"))
                }
            }
            env.play()
            XCTAssertEqual(env.asks.asks, [], "a clear and every answer owed leave no ask (seed \(seed))")
        }
        XCTAssertGreaterThan(dropped, 300, "late callbacks are part of the mix")
        XCTAssertGreaterThan(restores, 30, "answers put back are part of the mix")
        XCTAssertGreaterThan(otherAsk, 50, "callbacks for an ask no longer under way are part of the mix")
        XCTAssertGreaterThan(overlapping, 5, "overlapping finishes are part of the mix")
        XCTAssertGreaterThan(refused, 100, "refused asks are part of the mix")
        XCTAssertGreaterThan(setAside, 20, "answers set aside are part of the mix")
        XCTAssertGreaterThan(broughtBack, 5, "set-aside answers brought back are part of the mix")
        XCTAssertGreaterThan(stopped, 10, "answers Esc puts back are part of the mix")
        XCTAssertGreaterThan(queued, 300, "asks sent while others are under way are part of the mix")
        XCTAssertGreaterThan(coexisting, 100, "answers on the screen together are part of the mix")
        XCTAssertGreaterThan(interrupted, 50, "asks stopped at the responder are part of the mix")
        XCTAssertGreaterThan(closed, 100, "answers Esc closes are part of the mix")
        XCTAssertGreaterThan(sharedInk, 50, "ink two asks are about is part of the mix")
        XCTAssertGreaterThan(withdrawals, 0, "withdrawn notes are part of the mix")
    }
}

/// Plays what `LiveInk` sends `LiveAsks`, in a random order, against a fake screen, and runs the
/// effects each event answers as `LiveInk` runs them. Each event goes to `observe` with the state
/// before and after it. What comes back for an ask is sent whether the ask takes it or not, so the
/// reducer's own check is what drops it.
private final class LiveAsksEnvironment {
    enum Step {
        /// `begin`, with the marks on the screen it was given, and whether it followed a reply.
        case begun(LiveAsks.Begun, shown: [Mark], following: Bool)
        case event(LiveAsks.Event)
    }

    struct Sent {
        let step: Step
        let before: LiveAsks
        let after: LiveAsks
        let effects: [LiveAsks.Effect]
    }

    private enum Owed {
        case packet(LiveAsks.Ask.ID)
        case captureFailed(LiveAsks.Ask.ID)
        case picture(LiveAsks.Ask.ID)
        case say(LiveAsks.Ask.ID)
        case answer(LiveAsks.Ask.ID)
        case failure(LiveAsks.Ask.ID)
        case sent(LiveAsks.Ask.ID, ink: Set<Mark.ID>, refused: Bool)
        case timer(Set<Mark.ID>)
        case focus([Mark], LiveAsks.Ask.ID)

        /// Held by the responder, which fails it when it stops.
        var heldBy: LiveAsks.Ask.ID? {
            switch self {
            case .say(let id), .answer(let id), .failure(let id): id
            default: nil
            }
        }

        var isFocus: Bool { if case .focus = self { true } else { false } }
    }

    /// What `LiveInk.ask` says when the packet could not be captured.
    static let couldNotSee = "Vignette couldn't see the screen."

    private(set) var asks = LiveAsks()
    private(set) var trace: [String] = []
    /// Every mark made.
    private(set) var made: [Mark] = []
    private var screen: [Mark] = []
    /// The marks set aside, by the ask from a picked button whose reply set them aside.
    private var aside: [LiveAsks.Ask.ID: [Mark]] = [:]
    func aside(of id: LiveAsks.Ask.ID) -> Set<Mark.ID> { Set((aside[id] ?? []).map(\.id)) }
    private var rng: SeededGenerator
    private var owed: [(due: Int, owed: Owed)] = []
    private var step = 0
    private var names: [Mark.ID: String] = [:]
    private var focusShown: (stop: [Mark], ask: LiveAsks.Ask.ID)?
    private let observe: (LiveAsksEnvironment, Sent) -> Void

    init(seed: Int, observe: @escaping (LiveAsksEnvironment, Sent) -> Void) {
        rng = SeededGenerator(seed: UInt64(seed))
        self.observe = observe
    }

    func play(steps: Int = 40) {
        for step in 0..<steps {
            self.step = step
            deliverDue()
            act()
            for (id, marks) in aside where !marks.isEmpty && asks.ask(id)?.isUnderWay != true {
                XCTFail("marks stay set aside only while their ask is under way #\(id)\n" + trace.suffix(30).joined(separator: "\n"))
            }
        }
        // Drain: a clear, then every answer and timer still owed.
        step = steps
        clear()
        for step in steps..<(steps + 20) {
            self.step = step
            deliverDue()
        }
    }

    private func act() {
        switch Int.random(in: 0..<22, using: &rng) {
        case 0...3: draw()
        case 4...7: ask()
        case 8...9: respond()
        case 10...11: dismissAnswer()
        case 12: erase()
        case 13: windowGone()
        case 14: pick()
        case 15: draw()
        case 16: discardNote()
        case 17: letGoOfFocus()
        case 18: clear()
        case 19: cancel()
        case 20: closeAnswer()
        default: break
        }
    }

    private func deliverDue() {
        let due = owed.filter { $0.due <= step }
        owed.removeAll { $0.due <= step }
        for item in due {
            switch item.owed {
            case .packet(let id): packet(for: id)
            case .captureFailed(let id): failed(Self.couldNotSee, for: id)
            case .picture(let id): _ = send(.pictureSent(fresh: chance(2), for: id))
            case .say(let id): showSay(for: id)
            case .answer(let id): answered(for: id)
            case .failure(let id): failed("Claude stopped.", for: id)
            case .sent(let id, let ink, let refused): sessionAnswered(for: id, ink: ink, refused: refused)
            case .timer(let ids): finished(ids)
            case .focus(let stop, let id): nextFocus(stop, for: id)
            }
        }
    }

    // MARK: Plumbing

    private func send(_ event: LiveAsks.Event) -> [LiveAsks.Effect] {
        let before = asks
        let effects = asks.reduce(event)
        trace.append("\(step): \(describe(event)) -> \(effects.map { describe($0) }) asks=\(asks.asks.map(describe).joined(separator: ", "))")
        observe(self, Sent(step: .event(event), before: before, after: asks, effects: effects))
        return effects
    }

    private func chance(_ n: Int) -> Bool { Int.random(in: 0..<n, using: &rng) == 0 }

    private func owe(_ item: Owed, in steps: ClosedRange<Int> = 1...3) {
        owed.append((step + Int.random(in: steps, using: &rng), item))
    }

    private func make(_ geometry: Mark.Geometry, agent: Bool, _ prefix: String) -> Mark {
        let mark = Mark(geometry: geometry, agent: agent)
        names[mark.id] = "\(prefix)\(names.count)"
        made.append(mark)
        return mark
    }

    private func shape(agent: Bool) -> Mark {
        let origin = CGPoint(x: CGFloat(Int.random(in: 0..<800, using: &rng)), y: CGFloat(Int.random(in: 0..<600, using: &rng)))
        return make(.ellipse(CGRect(origin: origin, size: CGSize(width: 40, height: 30))), agent: agent, agent ? "s" : "i")
    }

    private func note(_ words: String, agent: Bool) -> Mark {
        make(.text(Mark.Text(origin: .zero, text: words, wrap: nil, size: 14)), agent: agent, agent ? "r" : "n")
    }

    private var shown: Set<Mark.ID> { Set(screen.map(\.id)) }

    /// `put`: on the screen, in place of a mark of the same id, which keeps its part in the asks.
    private func put(_ marks: [Mark]) {
        for mark in marks {
            takeOff([mark.id])
            screen.append(mark)
        }
    }

    /// `remove`: off the screen, and out of the asks.
    private func remove(_ ids: Set<Mark.ID>) {
        takeOff(ids)
        run(send(.removed(ids)))
    }

    /// `takeOff`: off the screen, with no word to the asks.
    private func takeOff(_ ids: Set<Mark.ID>) {
        screen.removeAll { ids.contains($0.id) }
        for id in aside.keys { aside[id]?.removeAll { ids.contains($0.id) } }
    }

    // MARK: Ink

    private func draw() {
        let mark = shape(agent: false)
        _ = send(.drew(mark.id))
        put([mark])
    }

    private func erase() {
        guard let mark = screen.randomElement(using: &rng) else { return }
        remove([mark.id])
    }

    /// The window's marks go with it, which `LiveWindows` does without `remove`.
    private func windowGone() {
        let ids = Set((screen + aside.values.joined()).filter { _ in chance(3) }.map(\.id))
        guard !ids.isEmpty else { return }
        takeOff(ids)
        run(send(.windowGone(ids)))
    }

    private func pick() {
        guard let hit = screen.filter({ $0.agent && $0.kind != .text && asks.isAnswer($0.id) }).randomElement(using: &rng) else { return }
        let own = make(hit.geometry, agent: false, "p")
        _ = send(.drew(own.id))
        put([own])
        remove([hit.id])
    }

    private func discardNote() {
        run(send(.noteDiscarded))
    }

    // MARK: Asking

    @discardableResult
    private func ask(following reply: Mark? = nil, picked: LiveAnswerActions.Pick = .reply) -> Bool {
        let before = asks
        let given = screen
        let toSession = reply == nil && chance(5)
        let begun = asks.begin(among: given, following: reply.map { LiveAsks.Following(reply: $0, pick: picked, words: "and this?") },
                               toSession: toSession)
        let effects: [LiveAsks.Effect]
        switch begun {
        case .began(let id, let about, _, let ended):
            effects = ended
            trace.append("\(step): began #\(id) about=\(list(Set(about.map(\.id)))) following=\(name(reply?.id)) session=\(toSession) -> \(effects.map { describe($0) })")
        case .refused(let refusal, let refused):
            effects = refused
            trace.append("\(step): refused \(refusal) following=\(name(reply?.id)) -> \(effects.map { describe($0) })")
        }
        observe(self, Sent(step: .begun(begun, shown: given, following: reply != nil), before: before, after: asks, effects: effects))
        run(effects)
        guard case .began(let id, _, _, _) = begun else { return false }
        if let reply {
            put([reply])
        } else if chance(2) {
            var conversation = note("", agent: true)
            conversation.quote = "What is this?"
            _ = send(.conversed(conversation, for: id))
            put([conversation])
        }
        // A capture that fails can take a while, and `ask`'s task then fails the ask it began, whatever
        // has happened since.
        if chance(10) { owe(.captureFailed(id), in: 2...12) } else { owe(.packet(id)) }
        return true
    }

    private func packet(for id: LiveAsks.Ask.ID) {
        let effects = send(.arrived(.packetCame, for: id))
        if effects.contains(where: { if case .share = $0 { true } else { false } }) {
            let ink = Set(asks.ink(among: screen).filter { _ in chance(2) }.map(\.id))
            owe(.sent(id, ink: ink, refused: chance(4)))
        }
        run(effects)
    }

    /// `LiveResponder` takes the ask: the picture goes, the reply streams, and the answer or a failure comes.
    private func responderTakes(_ id: LiveAsks.Ask.ID) {
        if chance(2) { _ = send(.pictureSent(fresh: chance(2), for: id)) } else { owe(.picture(id), in: 1...2) }
        // The responder can shut down as it is asked, which fails the ask in the same turn.
        if chance(8) { return failed("The responder ended.", for: id) }
        let says = Int.random(in: 0...3, using: &rng)
        for n in 0..<says { owe(.say(id), in: (n + 1)...(n + 1)) }
        owe(chance(4) ? .failure(id) : .answer(id), in: (says + 1)...(says + 3))
    }

    private func sessionAnswered(for id: LiveAsks.Ask.ID, ink: Set<Mark.ID>, refused: Bool) {
        if refused { return failed("Not sent.", for: id) }
        run(send(.arrived(.sentToSession(ink: ink), for: id)))
    }

    /// A press on an answer's panel. Its buttons are enabled only on an answer, and the panel shows
    /// only while the reply does (`shownReply`).
    private func respond() {
        let answers = asks.asks.filter { ask in
            guard ask.phase == .answered, let said = ask.say else { return false }
            return screen.contains { $0.id == said.id } && asks.answer(of: said.id) == ask.id && !asks.isFinishing(said.id)
        }
        guard let answer = answers.randomElement(using: &rng), let said = answer.say else { return }
        let pick: LiveAnswerActions.Pick = chance(2) ? .reply : .action("Fix it")
        guard var reply = screen.first(where: { $0.id == said.id }) else { return }
        reply.quote = "and this?"
        reply.notice = nil
        ask(following: reply, picked: pick)
    }

    // MARK: Answering

    private func showSay(for id: LiveAsks.Ask.ID) {
        let effects = send(.arrived(.replyCame, for: id))
        guard effects.contains(.showReply) else { return }
        run(effects)
        let reply: Mark
        if var shown = asks.ask(id)?.say, case .text(var words) = shown.geometry {
            words.text += " more"
            shown.geometry = .text(words)
            reply = shown
        } else {
            reply = note("It's", agent: true)
        }
        _ = send(.streamed(reply, for: id))
        put([reply])
    }

    private func answered(for id: LiveAsks.Ask.ID) {
        let effects = send(.arrived(.answerCame, for: id))
        guard effects.contains(.drawAnswer) else { return }
        run(effects)
        let reply = asks.ask(id)?.say ?? note("It's a button.", agent: true)
        let shapes = (0..<Int.random(in: 0...3, using: &rng)).map { _ in shape(agent: true) }
        let held = shapes.filter { _ in chance(3) }
        let shown = [reply] + shapes.filter { shape in !held.contains { $0.id == shape.id } }
        _ = send(.answered(reply: reply, actions: chance(2) ? [] : [LiveAnswer.Action("Fix it")], findings: shapes.map { [$0.id] },
                           shown: Set(shown.map(\.id)), for: id))
        put(shown)
        // `pullFocus`
        if !held.isEmpty {
            letGoOfFocus()
            if chance(4) {
                _ = send(.answerShown(Set(held.map(\.id)), for: id))
                put(held)
            } else {
                for (n, stop) in held.enumerated() { owe(.focus([stop], id), in: (n + 1)...(n + 1)) }
            }
        }
    }

    private func nextFocus(_ stop: [Mark], for id: LiveAsks.Ask.ID) {
        if let previous = focusShown { dropFocus(previous.stop) }
        focusShown = (stop, id)
        _ = send(.answerShown(Set(stop.map(\.id)), for: id))
        if chance(2), var reply = asks.ask(id)?.say, case .text(var words) = reply.geometry, asks.answer(of: reply.id) == id {
            words.origin.y += 40
            reply.geometry = .text(words)
            _ = send(.replyRedrawn(reply))
            put(stop + [reply])
        } else {
            put(stop)
        }
    }

    private func letGoOfFocus() {
        owed.removeAll { $0.owed.isFocus }
        guard let shown = focusShown else { return }
        focusShown = nil
        dropFocus(shown.stop)
    }

    /// `letGoOfTour(of:)`: the focus goes only when it is that ask's.
    private func letGoOfFocus(of id: LiveAsks.Ask.ID) {
        let ours = owed.contains { if case .focus(_, let owner) = $0.owed { owner == id } else { false } } || focusShown?.ask == id
        if ours { letGoOfFocus() }
    }

    private func dropFocus(_ stop: [Mark]) {
        let ids = Set(stop.map(\.id)).intersection(asks.answerMarks)
        guard !ids.isEmpty else { return }
        remove(ids)
    }

    private func failed(_ reason: String, for id: LiveAsks.Ask.ID) {
        run(send(.arrived(.failed(reason: reason, shown: shown), for: id)))
    }

    private func run(_ effects: [LiveAsks.Effect]) {
        for effect in effects {
            switch effect {
            case .ended(let id): release(id)
            case .send(let id): responderTakes(id)
            case .interrupt: break
            case .removeAnswer(let id, let gone): removeAnswer(gone, of: id)
            case .setAside(let id, let ids): setAside(ids, of: id)
            case .restore(let reply, let reason, let brought):
                if !brought.isEmpty { bringBack(brought) }
                restoreAnswer(reply, saying: reason)
            case .say(let id, let reason): say(reason, for: id)
            case .notice(let reply, let reason): notice(reason, in: reply)
            case .remove(let ids): remove(ids)
            case .finish(let ids, _): owe(.timer(ids), in: 1...3)
            case .showReply, .drawAnswer, .share, .withdraw: break
            }
        }
    }

    /// `release`: the focus and the buttons go when they are that ask's.
    private func release(_ id: LiveAsks.Ask.ID) {
        letGoOfFocus(of: id)
        hideActions(of: id)
    }

    private func notice(_ reason: String, in replyID: Mark.ID) {
        guard var reply = asks.ask(withReply: replyID)?.say else { return }
        reply.notice = reason
        _ = send(.replyRedrawn(reply))
        put([reply])
    }

    private func restoreAnswer(_ replyID: Mark.ID, saying reason: String?) {
        guard let ask = asks.ask(withReply: replyID), var reply = ask.say else { return }
        reply.notice = reason
        _ = send(.replyRedrawn(reply))
        hideActions(of: ask.id)
        put([reply])
    }

    /// Reply's field, when it is open, reports its words as it hides, for the reply it was made for.
    private func hideActions(of id: LiveAsks.Ask.ID) {
        guard chance(3) else { return }
        let reply = chance(4) ? made.filter { $0.agent && $0.kind == .text }.randomElement(using: &rng)?.id : asks.ask(id)?.say?.id
        _ = send(.drafted("half typed", reply: reply))
    }

    private func say(_ words: String, for id: LiveAsks.Ask.ID) {
        guard let about = asks.ask(id)?.about else { return }
        guard screen.contains(where: { about.contains($0.id) && $0.shapeExtent != nil }) else { return }
        let note = note(words, agent: false)
        _ = send(.conversed(note, for: id))
        put([note])
    }

    private func removeAnswer(_ gone: Set<Mark.ID>, of id: LiveAsks.Ask.ID) {
        letGoOfFocus(of: id)
        hideActions(of: id)
        if !gone.isEmpty { remove(gone) }
    }

    private func setAside(_ ids: Set<Mark.ID>, of id: LiveAsks.Ask.ID) {
        letGoOfFocus(of: id)
        hideActions(of: id)
        aside[id, default: []] += screen.filter { ids.contains($0.id) }
        screen.removeAll { ids.contains($0.id) }
    }

    private func bringBack(_ ids: Set<Mark.ID>) {
        for id in aside.keys {
            screen += (aside[id] ?? []).filter { ids.contains($0.id) }
            aside[id]?.removeAll { ids.contains($0.id) }
        }
    }

    // MARK: Exits

    /// Esc on the newest ask Esc can stop.
    private func cancel() {
        guard let id = asks.cancellable(sendsWait: chance(2)) else { return }
        owed.removeAll { $0.owed.heldBy == id && asks.ask(id)?.phase == .asking }
        run(send(.cancelled(id, shown: shown)))
    }

    /// The × over an answer's reply, which shows on any ask with its reply up, while it offers one.
    private func dismissAnswer() {
        let replies = asks.asks.filter { ask in
            guard asks.offersDismiss(ask.id), let said = ask.say else { return false }
            return screen.contains { $0.id == said.id } && asks.answer(of: said.id) == ask.id && !asks.isFinishing(said.id)
        }
        guard let ask = replies.randomElement(using: &rng) else { return }
        if ask.phase == .asking { owed.removeAll { $0.owed.heldBy == ask.id } }
        run(send(.dismissed(ask.id)))
    }

    /// Esc with no ask to stop.
    private func closeAnswer() {
        guard asks.cancellable(sendsWait: false) == nil else { return }
        run(send(.answerClosed))
    }

    private func finished(_ ids: Set<Mark.ID>) {
        run(send(.finished(ids)))
    }

    /// `clear()`, which takes the marks off first, or `setOn(false)`, which takes them off after.
    private func clear() {
        let marksFirst = chance(2)
        if marksFirst { screen = [] }
        letGoOfFocus()
        run(send(.cleared))
        // `responder.stop()` drops the ask it holds, with no answer and no failure.
        owed.removeAll { $0.owed.heldBy != nil }
        screen = []
        aside = [:]
    }

    // MARK: Trace

    private func name(_ id: Mark.ID?) -> String { id.map { names[$0] ?? "?" } ?? "nil" }

    private func list(_ ids: Set<Mark.ID>) -> String { "[" + ids.map { name($0) }.sorted().joined(separator: " ") + "]" }

    private func describe(_ ask: LiveAsks.Ask) -> String {
        "#\(ask.id) \(ask.phase)\(ask.toSession ? " session" : "") about=\(list(ask.about)) say=\(name(ask.say?.id))\(ask.picked == nil ? "" : " picked")"
    }

    private func describe(_ event: LiveAsks.Event) -> String {
        switch event {
        case .drew(let id): "drew \(name(id))"
        case .noteDiscarded: "noteDiscarded"
        case .removed(let ids): "removed \(list(ids))"
        case .windowGone(let ids): "windowGone \(list(ids))"
        case .arrived(let arrival, let id): "\(describe(arrival)) #\(id)"
        case .conversed(let mark, let id): "conversed \(name(mark.id)) #\(id)"
        case .pictureSent(let fresh, let id): "pictureSent \(fresh) #\(id)"
        case .streamed(let mark, let id): "streamed \(name(mark.id)) #\(id)"
        case .answered(let reply, _, _, let shown, let id): "answered \(name(reply?.id)) shown=\(list(shown)) #\(id)"
        case .drafted(_, let reply): "drafted \(name(reply))"
        case .replyRedrawn(let reply): "replyRedrawn \(name(reply.id))"
        case .answerShown(let ids, let id): "answerShown \(list(ids)) #\(id)"
        case .dismissed(let id): "dismissed #\(id)"
        case .cancelled(let id, _): "cancelled #\(id)"
        case .answerClosed: "answerClosed"
        case .finished(let ids): "finished \(list(ids))"
        case .cleared: "cleared"
        }
    }

    private func describe(_ arrival: LiveAsks.Arrival) -> String {
        switch arrival {
        case .packetCame: "packetCame"
        case .replyCame: "replyCame"
        case .answerCame: "answerCame"
        case .failed(let reason, _): "failed \"\(reason)\""
        case .sentToSession(let ink): "sentToSession ink=\(list(ink))"
        }
    }

    private func describe(_ effect: LiveAsks.Effect) -> String {
        switch effect {
        case .ended(let id): "ended #\(id)"
        case .send(let id): "send #\(id)"
        case .interrupt: "interrupt"
        case .share(let about): "share \(list(about))"
        case .showReply: "showReply"
        case .drawAnswer: "drawAnswer"
        case .restore(let reply, _, let aside): "restore \(name(reply)) aside=\(list(aside))"
        case .say(let id, _): "say #\(id)"
        case .notice(let reply, _): "notice \(name(reply))"
        case .remove(let ids): "remove \(list(ids))"
        case .withdraw: "withdraw"
        case .removeAnswer(let id, let gone): "removeAnswer #\(id) \(list(gone))"
        case .setAside(let id, let ids): "setAside #\(id) \(list(ids))"
        case .finish(let ids, let how): "finish \(list(ids)) \(how)"
        }
    }
}
