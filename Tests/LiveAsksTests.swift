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

    /// Begins an ask as `LiveInk.ask` does, taking the marks it answers off, and answers its id.
    @discardableResult
    private func begin(_ a: inout A, on shown: [Mark], following reply: Mark? = nil, picked: LiveAnswerActions.Pick? = nil,
                       words: String = "and this?", file: StaticString = #filePath, line: UInt = #line) -> A.Ask.ID {
        switch a.begin(among: shown, following: following(reply, picked: picked, words: words), shift: { _ in nil }) {
        case .began(let id, _, _, let effects):
            for case .removeAnswer(let gone) in effects where !gone.isEmpty { _ = reduce(&a, .removed(gone)) }
            return id
        case .refused(let refusal, _):
            XCTFail("the ask was refused: \(refusal.rawValue)", file: file, line: line)
            return 0
        }
    }

    /// What `LiveInk.showSay` sends when the reply streams in for `id`. Answers whether the ask took it.
    @discardableResult
    private func streamed(_ a: inout A, _ reply: Mark, for id: A.Ask.ID) -> Bool {
        let effects = reduce(&a, .arrived(.replyCame, for: id))
        guard effects.contains(.showReply) else { return false }
        for case .removeAnswer(let gone) in effects where !gone.isEmpty { _ = reduce(&a, .removed(gone)) }
        _ = reduce(&a, .streamed(reply))
        return true
    }

    /// What `LiveInk.answered` sends when the answer comes for `id`. Answers whether the ask took it.
    @discardableResult
    private func answered(_ a: inout A, _ reply: Mark?, actions: [LiveAnswer.Action] = [], findings: [[Mark.ID]] = [],
                          shown: Set<Mark.ID>, for id: A.Ask.ID) -> Bool {
        let effects = reduce(&a, .arrived(.answerCame, for: id))
        guard effects.contains(.drawAnswer) else { return false }
        for case .removeAnswer(let gone) in effects where !gone.isEmpty { _ = reduce(&a, .removed(gone)) }
        _ = reduce(&a, .answered(reply: reply, actions: actions, findings: findings, shown: shown))
        return true
    }

    /// Asks about `shown` and draws `reply` with `shapes` as its answer.
    @discardableResult
    private func answer(_ a: inout A, on shown: [Mark], reply: Mark, shapes: [Mark] = []) -> A.Ask.ID {
        let id = begin(&a, on: shown)
        XCTAssertEqual(reduce(&a, .arrived(.packetCame(toSession: false), for: id)), [.send])
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
        answer(&a, on: [first, second], reply: reply, shapes: [loop])
        let failure = text("Not sent.")
        _ = reduce(&a, .answerShown([failure.id]))
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

    func testAnotherAskIsRefusedWhileOneIsUnderWay() {
        var a = A()
        let mark = ink()
        XCTAssertFalse(a.isUnderWay)
        let id = begin(&a, on: [mark])
        XCTAssertTrue(a.isUnderWay)
        var before = a
        XCTAssertEqual(a.begin(among: [mark], following: nil, shift: { _ in nil }), .refused(.busy, effects: []), "not while it looks")
        XCTAssertEqual(a, before)
        _ = reduce(&a, .arrived(.packetCame(toSession: false), for: id))
        XCTAssertTrue(a.isUnderWay)
        before = a
        XCTAssertEqual(a.begin(among: [mark], following: nil, shift: { _ in nil }), .refused(.busy, effects: []), "nor while it asks")
        XCTAssertEqual(a, before)
        answered(&a, text("Yes.", agent: true), shown: [], for: id)
        XCTAssertFalse(a.isUnderWay)

        let next = begin(&a, on: [mark])
        XCTAssertTrue(a.isUnderWay)
        XCTAssertEqual(reduce(&a, .arrived(.failed(reason: "No.", shown: [mark.id]), for: next)), [.removeAnswer([]), .say("No.")])
        XCTAssertFalse(a.isUnderWay)

        begin(&a, on: [mark])
        _ = reduce(&a, .cleared)
        XCTAssertFalse(a.isUnderWay)
        begin(&a, on: [mark])
    }

    func testAnAskWithNoInkIsRefusedBeforeItIsBusy() {
        var a = A()
        let mark = ink(), note = text("What is this?")
        XCTAssertEqual(a.begin(among: [note], following: nil, shift: { _ in nil }), .refused(.noInk, effects: []),
                       "a person's note alone is no ink to ask about")
        begin(&a, on: [mark])
        let before = a
        XCTAssertEqual(a.begin(among: [note], following: nil, shift: { _ in nil }), .refused(.noInk, effects: []),
                       "no ink is said before an ask under way")
        XCTAssertEqual(a, before)
        XCTAssertEqual(A.Refusal.noInk.rawValue, "There's no ink to ask about.")
        XCTAssertEqual(A.Refusal.noInk.detail, "no ink")
        XCTAssertEqual(A.Refusal.busy.rawValue, "An ask is under way.")
        XCTAssertEqual(A.Refusal.busy.detail, "busy")
    }

    func testAnAskBeginsAtItsNewestShapeLedByItsInk() {
        var a = A()
        let first = ink(), second = ink(100), note = text("this")
        let shift = CGVector(dx: 0, dy: 12)
        guard case .began(let id, let about, let point, let effects) = a.begin(
            among: [first, note, second], following: nil, shift: { $0 == second.id ? shift : nil }) else { return XCTFail("the ask begins") }
        XCTAssertEqual(about.map(\.id), [first.id, note.id, second.id], "oldest first")
        XCTAssertEqual(point, CGPoint(x: 120, y: 15), "at the centre of the newest shape")
        XCTAssertEqual(effects, [.removeAnswer([])], "a fresh ask always lets go of the last answer")
        XCTAssertEqual(a.ask?.id, id)
        XCTAssertEqual(a.ask?.leader, second.id, "the newest ink leads, not the person's note")
        XCTAssertEqual(a.ask?.leaderShift, shift, "with how far its content had moved")
    }

    func testAPacketIsTakenOnlyWhileItsAskIsLookingAndMovesItToAsking() {
        var a = A()
        let id = begin(&a, on: [ink()])
        XCTAssertEqual(reduce(&a, .arrived(.packetCame(toSession: false), for: id)), [.send])
        XCTAssertEqual(a.ask?.phase, .asking)
        let asking = a
        XCTAssertEqual(reduce(&a, .arrived(.packetCame(toSession: false), for: id)), [], "a second packet is not sent")
        XCTAssertEqual(a, asking)

        _ = reduce(&a, .cleared)
        let cleared = a
        XCTAssertEqual(reduce(&a, .arrived(.packetCame(toSession: false), for: id)), [], "nothing is sent after a clear")
        XCTAssertEqual(a, cleared)
    }

    func testAPacketFromAClearedAskIsDroppedAndTheNextAskTakesItsOwn() {
        var a = A()
        let mark = ink()
        let old = begin(&a, on: [mark])
        _ = reduce(&a, .cleared)
        let next = begin(&a, on: [mark])
        let before = a
        XCTAssertEqual(reduce(&a, .arrived(.packetCame(toSession: false), for: old)), [],
                       "the cleared ask's words and picture are not sent as the next question")
        XCTAssertEqual(a, before)
        XCTAssertEqual(a.ask?.phase, .looking)
        XCTAssertEqual(reduce(&a, .arrived(.packetCame(toSession: false), for: next)), [.send], "the next ask sends its own")
    }

    func testThePersonsQuestionIsPartOfTheAskAndIsNotNewInk() {
        var a = A()
        let mark = ink(), question = text("What is this?")
        let id = begin(&a, on: [mark])
        _ = reduce(&a, .arrived(.packetCame(toSession: false), for: id))
        _ = reduce(&a, .noted(question.id))
        XCTAssertEqual(a.ask?.about, [mark.id, question.id])
        XCTAssertEqual(a.pulsing, [mark.id, question.id], "the question pulses with the ink while the ask is under way")
        XCTAssertEqual(a.newInk(among: [mark, question]), [], "the next ask is not about the person's own question")
    }

    func testTheReplyStreamsOnlyWhileAskingAndAnAnswerIsTakenWhileThereIsAnAsk() {
        var a = A()
        let mark = ink()
        let id = begin(&a, on: [mark])
        var before = a
        XCTAssertEqual(reduce(&a, .arrived(.replyCame, for: id)), [], "no reply before the packet went")
        XCTAssertEqual(a, before)

        _ = reduce(&a, .arrived(.packetCame(toSession: false), for: id))
        let reply = text("It's", agent: true)
        XCTAssertTrue(streamed(&a, reply, for: id))
        XCTAssertEqual(a.ask?.say, reply)
        XCTAssertTrue(a.isAnswer(reply.id))
        answered(&a, reply, shown: [reply.id], for: id)
        before = a
        XCTAssertEqual(reduce(&a, .arrived(.replyCame, for: id)), [], "no reply after the answer")
        XCTAssertEqual(a, before)

        let failing = begin(&a, on: [mark])
        _ = reduce(&a, .arrived(.packetCame(toSession: false), for: failing))
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
        _ = reduce(&a, .arrived(.packetCame(toSession: false), for: old))
        guard case .finish(let ids, _)? = reduce(&a, .dismissed).first else { return XCTFail("the × finishes the ink") }
        _ = reduce(&a, .finished(ids))
        XCTAssertNil(a.ask)
        let next = begin(&a, on: [second])
        _ = reduce(&a, .arrived(.packetCame(toSession: false), for: next))
        let late = text("About the first", agent: true)
        XCTAssertFalse(streamed(&a, late, for: old), "the next ask does not show the dismissed one's reply")
        XCTAssertFalse(answered(&a, late, shown: [late.id], for: old), "nor its answer")
        XCTAssertEqual(a.ask?.id, next)
        XCTAssertEqual(a.ask?.phase, .asking)
        XCTAssertNil(a.ask?.say)

        let own = text("About the second", agent: true)
        XCTAssertTrue(streamed(&a, own, for: next))
        XCTAssertTrue(answered(&a, own, shown: [own.id], for: next))
        XCTAssertEqual(a.ask?.phase, .answered)
    }

    func testALateAnswerAndFailureFromADismissedAskLeaveTheNextAnswerAlone() {
        var a = A()
        let first = ink(), second = ink(50)
        let old = begin(&a, on: [first])
        _ = reduce(&a, .arrived(.packetCame(toSession: false), for: old))
        guard case .finish(let ids, _)? = reduce(&a, .dismissed).first else { return XCTFail("the × finishes the ink") }
        _ = reduce(&a, .finished(ids))
        answer(&a, on: [second], reply: text("About the second", agent: true))
        let shown = a

        let late = text("About the first", agent: true)
        XCTAssertFalse(answered(&a, late, shown: [late.id], for: old), "a dismissed ask's answer does not replace the one up")
        XCTAssertEqual(reduce(&a, .arrived(.failed(reason: "Claude stopped.", shown: [second.id]), for: old)), [],
                       "nor does its failure turn it into a note")
        XCTAssertEqual(a, shown)
        guard case .text(let words)? = a.ask?.say?.geometry else { return XCTFail("the answer has its reply") }
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
        XCTAssertEqual(reduce(&a, .arrived(.packetCame(toSession: false), for: next)), [.send])
    }

    func testAnAnswerTakesTheReplysPlaceAndOffersItsActions() {
        var a = A()
        let mark = ink(), reply = text("It's a button.", agent: true), earlier = shape()
        answer(&a, on: [mark], reply: reply, shapes: [earlier])
        let follow = begin(&a, on: [mark, reply, earlier], following: reply, picked: .action("Fix it"), words: "Fix it")
        XCTAssertEqual(a.ask?.picked, .action("Fix it"))
        XCTAssertFalse(a.offersDismiss, "no × while the ask from a picked button is under way")
        XCTAssertEqual(a.pulsing, [mark.id, reply.id, earlier.id], "the earlier answer pulses with the ink while that ask is under way")
        var queued = A()
        answer(&queued, on: [mark], reply: reply)
        var noticed = reply
        noticed.notice = "Queued."
        begin(&queued, on: [mark, noticed], following: noticed, picked: .action("Fix it"), words: "Fix it")
        XCTAssertTrue(queued.offersDismiss, "an ask whose reply carries a notice still offers the ×")
        _ = reduce(&a, .arrived(.packetCame(toSession: false), for: follow))
        XCTAssertEqual(reduce(&a, .arrived(.answerCame, for: follow)), [.removeAnswer([earlier.id]), .drawAnswer],
                       "the earlier answer goes, all but the reply the next one takes the place of")
        XCTAssertEqual(a.answerMarks, [reply.id])
        let next = text("Fixed.", agent: true), loop = shape()
        _ = reduce(&a, .answered(reply: next, actions: [LiveAnswer.Action("Undo")], findings: [[loop.id]], shown: [next.id, loop.id]))
        XCTAssertEqual(a.ask?.phase, .answered)
        XCTAssertEqual(a.ask?.say, next)
        XCTAssertNil(a.ask?.picked, "the next answer's buttons are enabled")
        XCTAssertEqual(a.ask?.actions, [LiveAnswer.Action("Undo")])
        XCTAssertEqual(a.ask?.findings, [[loop.id]])
        XCTAssertTrue(a.isAnswer(next.id) && a.isAnswer(loop.id))
        XCTAssertTrue(a.offersDismiss)
    }

    func testAFailureAfterAPickedButtonPutsItsAnswerBackWithTheTypedWords() {
        var a = A()
        let mark = ink(), reply = text("It's a button.", agent: true)
        answer(&a, on: [mark], reply: reply)
        let earlier = a.ask!
        var quoting = reply
        quoting.quote = "and this?"
        let follow = begin(&a, on: [mark, quoting], following: quoting, picked: .reply, words: "and this?")
        _ = reduce(&a, .arrived(.packetCame(toSession: false), for: follow))

        XCTAssertEqual(reduce(&a, .arrived(.failed(reason: "Claude stopped.", shown: [mark.id, reply.id]), for: follow)),
                       [.restore(reply: reply.id, reason: "Claude stopped.")])
        var noticed = reply
        noticed.notice = "Claude stopped."
        _ = reduce(&a, .replyRedrawn(noticed))
        var expected = earlier
        expected.say = noticed
        expected.reason = "Claude stopped."
        expected.draft = "and this?"
        XCTAssertEqual(a.ask, expected, "the earlier answer is back, its id included, with the typed words in Reply")
        XCTAssertEqual(reduce(&a, .arrived(.failed(reason: "Again.", shown: [mark.id, reply.id]), for: follow)), [],
                       "the restored answer has its own id, so the ask from the picked button takes nothing more")

        let noInk = A.Refusal.noInk.rawValue
        var action = A()
        answer(&action, on: [mark], reply: reply)
        let answered = action.ask
        XCTAssertEqual(action.begin(among: [reply], following: A.Following(reply: reply, pick: .action("Fix it"), words: "Fix it"),
                                    shift: { _ in nil }),
                       .refused(.noInk, effects: [.restore(reply: reply.id, reason: noInk)]), "an ask refused before it began puts it back too")
        XCTAssertEqual(action.ask?.id, answered?.id)
        XCTAssertEqual(action.ask?.reason, noInk)
        XCTAssertEqual(action.ask?.draft, "", "an action's words are not typed words")

        var typed = A()
        answer(&typed, on: [mark], reply: reply)
        XCTAssertEqual(typed.begin(among: [reply], following: A.Following(reply: reply, pick: .reply, words: "and this?"),
                                   shift: { _ in nil }),
                       .refused(.noInk, effects: [.restore(reply: reply.id, reason: noInk)]))
        XCTAssertEqual(typed.ask?.draft, "and this?", "typed words wait in Reply again")

        var gone = A()
        answer(&gone, on: [mark], reply: reply)
        let failing = begin(&gone, on: [mark, reply], following: reply, picked: .reply)
        XCTAssertEqual(reduce(&gone, .arrived(.failed(reason: "Claude stopped.", shown: [mark.id]), for: failing)),
                       [.removeAnswer([reply.id]), .say("Claude stopped.")],
                       "with its reply off the screen, there is nothing to put back, and the failure is a note")
        XCTAssertEqual(gone.ask?.phase, .failed)
    }

    func testOnceTheReplyOfAnAskFromAPickedButtonStartsTheEarlierAnswerGoesAndAFailureIsANote() {
        var a = A()
        let mark = ink(), reply = text("It's a button.", agent: true), loop = shape()
        answer(&a, on: [mark], reply: reply, shapes: [loop])
        let follow = begin(&a, on: [mark, reply], following: reply, picked: .reply)
        _ = reduce(&a, .arrived(.packetCame(toSession: false), for: follow))
        XCTAssertEqual(reduce(&a, .arrived(.replyCame, for: follow)), [.removeAnswer([loop.id]), .showReply])
        XCTAssertEqual(a.answerMarks, [reply.id], "the loop is no longer the answer's once the reply starts")
        _ = reduce(&a, .streamed(reply))
        XCTAssertEqual(reduce(&a, .arrived(.failed(reason: "Claude stopped.", shown: [mark.id, reply.id]), for: follow)),
                       [.removeAnswer([reply.id]), .say("Claude stopped.")], "nothing is put back once the earlier answer was replaced")
    }

    func testANewAskTakesTheWholeAnswerOffAndAnAskFromAPickedButtonKeepsItsReply() {
        var a = A()
        let mark = ink(), reply = text("It's a button.", agent: true), loop = shape(), other = shape()
        answer(&a, on: [mark], reply: reply, shapes: [loop, other])
        let shown = [mark, reply, loop, other]

        var fresh = a
        guard case .began(_, _, _, let effects) = fresh.begin(among: shown, following: nil, shift: { _ in nil })
        else { return XCTFail("the ask begins") }
        XCTAssertEqual(effects, [.removeAnswer([reply.id, loop.id, other.id])])
        XCTAssertEqual(fresh.answerMarks, [])

        guard case .began(let follow, _, _, let none) = a.begin(among: shown, following: A.Following(reply: reply, pick: .reply, words: "and this?"),
                                                              shift: { _ in nil })
        else { return XCTFail("the ask from a picked button begins") }
        XCTAssertEqual(none, [], "an ask from a picked button keeps the answer until its reply comes")
        _ = reduce(&a, .arrived(.packetCame(toSession: false), for: follow))
        XCTAssertEqual(reduce(&a, .arrived(.replyCame, for: follow)), [.removeAnswer([loop.id, other.id]), .showReply])
        XCTAssertEqual(a.answerMarks, [reply.id])
    }

    func testDismissingFinishesTheAnswerAndTheInkItWasAbout() {
        var a = A()
        let first = ink(), second = ink(50), reply = text("It's a button.", agent: true), loop = shape()
        answer(&a, on: [first, second], reply: reply, shapes: [loop])
        let all: Set = [first.id, second.id, reply.id, loop.id]
        XCTAssertEqual(reduce(&a, .dismissed), [.finish(all, .dismissed)])
        XCTAssertEqual(a.finishing, Dictionary(uniqueKeysWithValues: all.map { ($0, .dismissed) }), "they are leaving as the × asked")

        var empty = A()
        XCTAssertEqual(reduce(&empty, .dismissed), [])
    }

    func testAFinishEndsTheAskOnlyWhenItTookEverythingItWasAbout() {
        var a = A()
        let first = ink(), second = ink(50)
        begin(&a, on: [first, second])
        XCTAssertEqual(reduce(&a, .carrying([first.id])), [.finish([first.id], .carried)])
        XCTAssertEqual(reduce(&a, .finished([first.id])), [.remove([first.id])])
        XCTAssertNotNil(a.ask, "the ask keeps the ink it was about that is still there")
        XCTAssertTrue(a.isUnderWay)

        _ = reduce(&a, .carrying([first.id, second.id]))
        XCTAssertEqual(reduce(&a, .finished([first.id, second.id])), [.remove([first.id, second.id])])
        XCTAssertNil(a.ask)
        XCTAssertFalse(a.isUnderWay, "a note carried off to a session leaves nothing under way")
        XCTAssertEqual(a.newInk(among: [second]), [second], "the ink it took is no longer asked about")
    }

    func testATimerStillEndsAnAskWhoseLeavingMarksWereAllErased() {
        var a = A()
        let first = ink()
        begin(&a, on: [first])
        _ = reduce(&a, .carrying([first.id]))
        _ = reduce(&a, .removed([first.id]))
        XCTAssertEqual(a.finishing, [:])
        XCTAssertEqual(reduce(&a, .finished([first.id])), [.remove([first.id])])
        XCTAssertNil(a.ask, "an ask left under way would refuse every ask after it")
        begin(&a, on: [ink(50)])
    }

    func testAFinishAfterAClearDoesNothing() {
        var a = A()
        let mark = ink()
        begin(&a, on: [mark])
        _ = reduce(&a, .dismissed)
        _ = reduce(&a, .cleared)
        _ = reduce(&a, .drew(mark.id))
        let before = a
        XCTAssertEqual(reduce(&a, .finished([mark.id])), [])
        XCTAssertEqual(a, before)
    }

    func testAnOverlappingFinishIsEndedByTheFirstTimer() {
        var a = A()
        let first = ink(), second = ink(50)
        begin(&a, on: [first, second])
        _ = reduce(&a, .dismissed)
        _ = reduce(&a, .carrying([second.id]))
        XCTAssertEqual(a.finishing, [first.id: .dismissed, second.id: .carried])
        XCTAssertEqual(reduce(&a, .finished([first.id, second.id])), [.remove([first.id, second.id])],
                       "the first timer takes the mark a later finish had started on")
        XCTAssertEqual(a.finishing, [:])
        XCTAssertEqual(reduce(&a, .finished([second.id])), [], "and the later timer finds nothing to do")
    }

    func testClearingForgetsEveryAskAndRoleButTheNotesInk() {
        var a = A()
        let drawn = ink(), reply = text("It's a button.", agent: true), loop = shape()
        _ = reduce(&a, .drew(drawn.id))
        answer(&a, on: [drawn], reply: reply, shapes: [loop])
        _ = reduce(&a, .dismissed)
        _ = reduce(&a, .cleared)
        XCTAssertNil(a.ask)
        XCTAssertEqual(a.begin(among: [], following: A.Following(reply: reply, pick: .reply, words: "and this?"), shift: { _ in nil }),
                       .refused(.noInk, effects: []), "nothing is put back after a clear")
        XCTAssertEqual(a.newInk(among: [drawn]), [drawn], "the ink is new again")
        XCTAssertEqual(a.answerMarks, [])
        XCTAssertEqual(a.finishing, [:])
        XCTAssertEqual(a.noteInk, [drawn.id])
        XCTAssertEqual(reduce(&a, .noteDiscarded), [.remove([drawn.id])], "⌘⌫ still takes back the open note's ink")
    }

    func testAWindowGoingForgetsOnlyItsMarksAskedAndAnswerRoles() {
        var a = A()
        let gone = ink(), stays = ink(50), reply = text("It's a button.", agent: true)
        _ = reduce(&a, .drew(gone.id))
        answer(&a, on: [gone, stays], reply: reply)
        _ = reduce(&a, .carrying([gone.id]))
        _ = reduce(&a, .windowGone([gone.id, reply.id]))
        XCTAssertEqual(a.newInk(among: [gone, stays]), [gone], "only the marks that went are new again")
        XCTAssertFalse(a.isAnswer(reply.id))
        XCTAssertEqual(a.noteInk, [gone.id], "the note's ink is kept")
        XCTAssertEqual(a.finishing, [gone.id: .carried], "and so is its finish")

        var only = A()
        begin(&only, on: [gone])
        _ = reduce(&only, .carrying([gone.id]))
        _ = reduce(&only, .windowGone([gone.id]))
        XCTAssertEqual(reduce(&only, .finished([gone.id])), [.remove([gone.id])])
        XCTAssertNil(only.ask, "the timer of marks that left with their window still ends the ask")
    }

    func testAnErasedMarkLosesItsRolesAndItsFinish() {
        var a = A()
        let mark = ink(), reply = text("It's a button.", agent: true), loop = shape()
        answer(&a, on: [mark], reply: reply, shapes: [loop])
        let asked = a.ask
        XCTAssertEqual(reduce(&a, .removed([loop.id])), [])
        XCTAssertEqual(a.ask, asked, "the ask is untouched")
        XCTAssertFalse(a.isAnswer(loop.id))
        var dismissed = a
        XCTAssertEqual(reduce(&dismissed, .dismissed), [.finish([mark.id, reply.id], .dismissed)], "the × no longer finishes the erased loop")

        var inkErased = a
        _ = reduce(&inkErased, .removed([mark.id]))
        XCTAssertEqual(inkErased.ask, asked, "erased ink stays in what the ask is about")
        XCTAssertEqual(reduce(&inkErased, .dismissed), [.finish([mark.id, reply.id], .dismissed)], "so the × still finishes it")
        XCTAssertEqual(reduce(&inkErased, .finished([mark.id, reply.id])), [.remove([mark.id, reply.id])])
        XCTAssertNil(inkErased.ask, "and its timer ends the ask, which was about only what left")

        begin(&a, on: [mark, reply], following: reply, picked: .reply)
        XCTAssertEqual(a.ask?.about, [mark.id, reply.id], "the ask from a picked button is not about the erased loop")
        XCTAssertFalse(a.pulsing.contains(loop.id))

        var note = A()
        let first = ink(), second = ink(50)
        _ = reduce(&note, .drew(first.id))
        _ = reduce(&note, .drew(second.id))
        _ = reduce(&note, .removed([first.id]))
        XCTAssertEqual(reduce(&note, .noteDiscarded), [.remove([second.id])], "⌘⌫ takes back only the note's ink still there")

        var leaving = A()
        answer(&leaving, on: [mark], reply: reply)
        _ = reduce(&leaving, .dismissed)
        _ = reduce(&leaving, .removed([reply.id]))
        XCTAssertFalse(leaving.isFinishing(reply.id), "a mark erased while leaving is no longer leaving")
        XCTAssertTrue(leaving.isFinishing(mark.id))
    }

    func testTheNotesInkStartsOverWhenTheChordGoesDownWithNoNoteOpen() {
        var a = A()
        let kept = ink(), first = ink(50), second = ink(100)
        _ = reduce(&a, .drew(kept.id))
        _ = reduce(&a, .inkingBegan(noteOpen: false))
        _ = reduce(&a, .drew(first.id))
        _ = reduce(&a, .inkingBegan(noteOpen: true))
        _ = reduce(&a, .drew(second.id))
        XCTAssertEqual(a.noteInk, [first.id, second.id], "a press with the note open adds to its ink")
        XCTAssertEqual(reduce(&a, .noteDiscarded), [.remove([first.id, second.id])], "ink an earlier note kept stays")
        XCTAssertEqual(a.noteInk, [])
    }

    func testADraftIsKeptOnlyForTheReplyThePanelWasMadeFor() {
        var a = A()
        let mark = ink(), reply = text("It's a button.", agent: true)
        answer(&a, on: [mark], reply: reply)
        _ = reduce(&a, .drafted("half typed", reply: reply.id))
        XCTAssertEqual(a.ask?.draft, "half typed")

        begin(&a, on: [mark])
        _ = reduce(&a, .drafted("half typed", reply: reply.id))
        XCTAssertEqual(a.ask?.draft, "", "a hidden panel's words stay out of the next answer")
        _ = reduce(&a, .drafted("no reply", reply: nil))
        XCTAssertEqual(a.ask?.draft, "no reply", "a panel made with no reply matches an ask with none")
    }

    func testASessionsAnswerIsTakenOnlyByItsAsk() {
        var a = A()
        let first = ink(), second = ink(50), beside = ink(100)
        let id = begin(&a, on: [first])
        XCTAssertEqual(reduce(&a, .arrived(.packetCame(toSession: true), for: id)), [.share(about: [first.id])])
        let shared = a

        XCTAssertEqual(reduce(&a, .arrived(.sentToSession(ink: [beside.id], carried: false), for: id)),
                       [.finish([first.id, beside.id], .dismissed)], "the ink in the card's picture leaves with the ink asked about")
        XCTAssertEqual(a.finishing, [first.id: .dismissed, beside.id: .dismissed])
        a = shared
        XCTAssertEqual(reduce(&a, .arrived(.sentToSession(ink: [beside.id], carried: true), for: id)), [.carry([first.id, beside.id])])
        XCTAssertEqual(a.finishing, [:], "carried ink starts to leave on the next turn, with the card")
        a = shared
        XCTAssertEqual(reduce(&a, .arrived(.failed(reason: "Not sent.", shown: [first.id]), for: id)), [.removeAnswer([]), .say("Not sent.")])
        XCTAssertEqual(a.ask?.phase, .failed)

        a = shared
        _ = reduce(&a, .cleared)
        XCTAssertEqual(reduce(&a, .arrived(.sentToSession(ink: [], carried: false), for: id)), [], "not after a clear")
        let next = begin(&a, on: [second])
        XCTAssertEqual(reduce(&a, .arrived(.failed(reason: "Not sent.", shown: []), for: id)), [], "not by another ask")
        XCTAssertEqual(reduce(&a, .arrived(.sentToSession(ink: [], carried: false), for: next)), [.finish([second.id], .dismissed)])
    }

    func testAPickedAnswerMarkIsNoLongerTheAnswers() {
        var a = A()
        let mark = ink(), reply = text("Which one?", agent: true), loop = shape()
        answer(&a, on: [mark], reply: reply, shapes: [loop])
        _ = reduce(&a, .removed([loop.id]))
        XCTAssertFalse(a.isAnswer(loop.id))
        guard case .began(_, _, _, let effects) = a.begin(among: [mark, reply], following: nil, shift: { _ in nil })
        else { return XCTFail("the ask begins") }
        XCTAssertEqual(effects, [.removeAnswer([reply.id])], "the next ask does not take the picked loop")
    }

    func testAFailureIsTakenBeforeAClearButNotAfter() {
        var a = A()
        let mark = ink()
        let id = begin(&a, on: [mark])
        _ = reduce(&a, .arrived(.packetCame(toSession: false), for: id))
        var stopped = a
        XCTAssertEqual(reduce(&stopped, .arrived(.failed(reason: "Claude stopped.", shown: [mark.id]), for: id)),
                       [.removeAnswer([]), .say("Claude stopped.")], "an ask takes a failure until it is cleared")
        _ = reduce(&a, .cleared)
        let cleared = a
        XCTAssertEqual(reduce(&a, .arrived(.failed(reason: "Claude stopped.", shown: [mark.id]), for: id)), [])
        XCTAssertEqual(a, cleared)
    }

    // MARK: Today's behaviour, kept on purpose for now

    func testAPacketForASessionLeavesTheAskLookingUntilTheSessionAnswers() {
        var a = A()
        let mark = ink()
        let id = begin(&a, on: [mark])
        _ = reduce(&a, .arrived(.packetCame(toSession: true), for: id))
        XCTAssertEqual(a.ask?.phase, .looking, "today, a note sent to a session keeps its ask looking")
        XCTAssertTrue(a.isUnderWay, "so another ask is refused until the session answers")
        XCTAssertEqual(a.pulsing, [mark.id], "and the ink pulses")
    }

    func testAnAnswerDuringTheDismissFadeOutlivesItsAsk() {
        var a = A()
        let mark = ink()
        let id = begin(&a, on: [mark])
        _ = reduce(&a, .arrived(.packetCame(toSession: false), for: id))
        guard case .finish(let ids, _)? = reduce(&a, .dismissed).first else { return XCTFail("the × finishes the ink") }
        let reply = text("Late", agent: true)
        answered(&a, reply, shown: [reply.id], for: id)
        _ = reduce(&a, .finished(ids))
        XCTAssertNil(a.ask)
        XCTAssertEqual(a.answerMarks, [reply.id], "today, the answer stays with no ask, so with no × and no actions, until a clear or the next ask")
    }

    func testAPictureIsRecordedOnWhicheverAskIsCurrent() {
        var a = A()
        let mark = ink()
        let old = begin(&a, on: [mark])
        _ = reduce(&a, .cleared)
        begin(&a, on: [mark])
        _ = reduce(&a, .pictureSent(fresh: true, for: old))
        XCTAssertEqual(a.ask?.picture, true, "today, the picture of a cleared ask is recorded on the next")
    }

    // MARK: Random sequences

    /// Plays random sequences through `LiveAsksEnvironment` and checks the ask's invariants after
    /// every event.
    func testRandomSequencesKeepTheInvariants() {
        var dropped = 0, restores = 0, otherAsk = 0, overlapping = 0, nested = 0, staleCapture = 0, refused = 0
        for seed in 0..<2000 {
            var lastID = 0
            var answeredAsks: Set<A.Ask.ID> = []
            let env = LiveAsksEnvironment(seed: seed) { env, sent in
                func fail(_ message: String) -> String { "\(message) (seed \(seed))\n" + env.trace.joined(separator: "\n") }
                let (before, after, effects) = (sent.before, sent.after, sent.effects)
                func nothingToPutBack() -> Bool {
                    guard let id = after.ask?.id else { return true }
                    var probe = after
                    return !probe.reduce(.arrived(.failed(reason: "probe", shown: Set(env.made.map(\.id))), for: id)).contains {
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
                func checkRestore(_ reply: Mark.ID, saying said: String, _ reason: String) {
                    restores += 1
                    XCTAssertEqual(said, reason, fail("the answer put back says why"))
                    XCTAssertEqual(after.ask?.say?.id, reply, fail("the answer put back hangs from its reply"))
                    XCTAssertEqual(after.ask?.phase, .answered, fail("the answer put back is an answer"))
                    XCTAssertNil(after.ask?.picked, fail("with its buttons enabled"))
                    XCTAssertEqual(after.ask?.reason, reason, fail("with the reason"))
                    XCTAssertTrue(answeredAsks.contains(after.ask?.id ?? 0), fail("an answer that was drawn is what comes back"))
                    XCTAssertTrue(nothingToPutBack(), fail("an answer is put back once"))
                }
                func checkFailure(_ reason: String) {
                    guard !effects.isEmpty else { return }
                    switch effects.last {
                    case .restore(let reply, let said):
                        XCTAssertEqual(effects.count, 1, fail("an answer put back is all a failure answers"))
                        checkRestore(reply, saying: said, reason)
                    case .say(let said):
                        XCTAssertEqual(effects.first, .removeAnswer(before.answerMarks), fail("a failure's note takes the answer's place"))
                        XCTAssertEqual(effects.count, 2, fail("and says why"))
                        XCTAssertEqual(after.answerMarks, [], fail("nothing is the answer's once it went"))
                        XCTAssertEqual(said, reason, fail("the note says why"))
                        XCTAssertEqual(after.ask?.phase, .failed, fail("a taken failure fails the ask"))
                        XCTAssertEqual(after.ask?.reason, reason, fail("and keeps why"))
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
                        if about.last?.shapeExtent == nil {
                            XCTAssertEqual(refusal, .noInk, fail("an ask with no ink is refused as no ink"))
                        } else {
                            XCTAssertEqual(refusal, .busy, fail("an ask with ink is refused only as busy"))
                            XCTAssertTrue(before.isUnderWay, fail("and only while one is under way"))
                        }
                        if case .restore(let reply, let said)? = effects.first {
                            XCTAssertEqual(effects.count, 1, fail("a refusal puts back the answer and does nothing else"))
                            checkRestore(reply, saying: said, refusal.rawValue)
                        } else {
                            XCTAssertEqual(effects, [], fail("a refusal answers nothing but an answer put back"))
                            XCTAssertEqual(after, before, fail("and changes nothing"))
                        }
                    case .began(let id, let asked, _, let effects):
                        XCTAssertNotNil(about.last?.shapeExtent, fail("an ask begins only about ink"))
                        XCTAssertFalse(before.isUnderWay, fail("and only with none under way"))
                        XCTAssertEqual(asked.map(\.id), about.map(\.id), fail("it is about the ink it says"))
                        XCTAssertEqual(after.ask?.id, id, fail("the ask begun is the ask"))
                        XCTAssertEqual(after.ask?.phase, .looking, fail("an ask begins looking"))
                        XCTAssertGreaterThan(id, lastID, fail("each ask's id is above every earlier one"))
                        lastID = id
                        if following {
                            XCTAssertEqual(effects, [], fail("an ask from a picked button keeps the answer until its reply comes"))
                        } else {
                            XCTAssertEqual(effects, [.removeAnswer(before.answerMarks)], fail("a fresh ask takes the whole answer off"))
                            XCTAssertEqual(after.answerMarks, [], fail("and none of it is the answer's"))
                        }
                    }
                    return
                case .event(let sentEvent):
                    event = sentEvent
                }
                if case .arrived(_, let id) = event {
                    if effects.isEmpty {
                        dropped += 1
                        XCTAssertEqual(after, before, fail("what an ask no longer takes changes nothing"))
                    }
                    if id != before.ask?.id {
                        otherAsk += 1
                        XCTAssertEqual(effects, [], fail("what comes back for another ask answers nothing"))
                        XCTAssertEqual(after, before, fail("and changes nothing"))
                    }
                }
                switch event {
                case .arrived(.packetCame(let toSession), _) where !effects.isEmpty:
                    if toSession {
                        XCTAssertEqual(effects, [.share(about: before.ask?.about ?? [])], fail("a session is sent the ink asked about"))
                        XCTAssertEqual(after, before, fail("and the ask waits for its answer as it was"))
                    } else {
                        XCTAssertEqual(effects, [.send], fail("the responder is sent the packet"))
                        XCTAssertEqual(before.ask?.phase, .looking, fail("a packet comes to an ask that is looking"))
                        XCTAssertEqual(after.ask?.phase, .asking, fail("and moves it to asking"))
                    }
                case .arrived(.replyCame, _) where !effects.isEmpty, .arrived(.answerCame, _) where !effects.isEmpty:
                    XCTAssertTrue(effects.last == .showReply || effects.last == .drawAnswer, fail("a taken reply or answer is drawn"))
                    XCTAssertEqual(after.ask?.phase, before.ask?.phase, fail("before it is drawn, the phase stays"))
                    XCTAssertTrue(nothingToPutBack(), fail("once a reply or answer comes, nothing is put back"))
                    XCTAssertEqual(effects.count == 2, before.ask?.say != nil, fail("an answer is taken off around a reply already up"))
                    for case .removeAnswer(let gone) in effects {
                        nested += 1
                        let kept = before.ask?.say?.id
                        XCTAssertEqual(gone, before.answerMarks.filter { $0 != kept }, fail("the earlier answer goes, all but its reply"))
                        XCTAssertTrue(after.answerMarks.isDisjoint(with: gone), fail("and is no longer the answer's"))
                    }
                case .arrived(.failed(let reason, _), let id):
                    checkFailure(reason)
                    if reason == LiveAsksEnvironment.couldNotSee, id != before.ask?.id { staleCapture += 1 }
                case .arrived(.sentToSession(let ink, let carried), _) where !effects.isEmpty:
                    let ids = (before.ask?.about ?? []).union(ink)
                    XCTAssertEqual(effects, carried ? [.carry(ids)] : [.finish(ids, .dismissed)], fail("a session's card takes the ink"))
                    checkFinishes()
                case .streamed:
                    XCTAssertEqual(after.ask?.phase, before.ask?.phase, fail("streaming never changes the phase"))
                case .answered:
                    XCTAssertEqual(after.ask?.phase, .answered, fail("a drawn answer answers the ask"))
                    if let id = after.ask?.id { answeredAsks.insert(id) }
                case .carrying, .dismissed:
                    checkFinishes()
                    if case .dismissed = event {
                        let ids = before.answerMarks.union(before.ask?.about ?? [])
                        XCTAssertEqual(effects, ids.isEmpty ? [] : [.finish(ids, .dismissed)], fail("the × finishes the answer and the ink it was about"))
                    }
                case .noteDiscarded:
                    XCTAssertEqual(effects, before.noteInk.isEmpty ? [] : [.remove(before.noteInk)], fail("⌘⌫ takes back the note's ink"))
                    XCTAssertEqual(after.noteInk, [], fail("and the note has no ink left"))
                case .removed(let ids):
                    XCTAssertEqual(effects, [], fail("a mark taken off answers nothing"))
                    XCTAssertEqual(after.ask, before.ask, fail("and leaves the ask as it was"))
                    XCTAssertTrue(keepsNoRole(ids), fail("it keeps no role and no finish"))
                    XCTAssertTrue(after.noteInk.isDisjoint(with: ids), fail("and is not the note's ink"))
                case .windowGone(let ids):
                    XCTAssertEqual(after.noteInk, before.noteInk, fail("a window going keeps the note's ink"))
                    XCTAssertEqual(after.finishing, before.finishing, fail("and every finish"))
                    XCTAssertTrue(after.answerMarks.isDisjoint(with: ids), fail("its marks are not the answer's"))
                case .drafted(let words, let reply):
                    if before.ask != nil, before.ask?.say?.id == reply {
                        XCTAssertEqual(after.ask?.draft, words, fail("the answer the panel was made for keeps its words"))
                        var back = after
                        _ = back.reduce(.drafted(before.ask?.draft ?? "", reply: reply))
                        XCTAssertEqual(back, before, fail("and nothing else changes"))
                    } else {
                        XCTAssertEqual(after, before, fail("another answer keeps none"))
                    }
                case .finished(let ids):
                    let ends = !ids.isEmpty && before.ask.map { $0.about.isSubset(of: ids) } == true
                    let leaving = !Set(before.finishing.keys).isDisjoint(with: ids)
                    XCTAssertEqual(!effects.isEmpty, ends || leaving,
                                   fail("a timer acts exactly when one of its marks is leaving or the ask was about only them"))
                    if effects.isEmpty {
                        XCTAssertEqual(after, before, fail("a timer with nothing to do changes nothing"))
                    } else {
                        XCTAssertEqual(effects, [.remove(ids)], fail("a timer removes its own marks"))
                        XCTAssertTrue(keepsNoRole(ids), fail("a finished mark keeps no role"))
                        XCTAssertEqual(after.ask == nil, before.ask == nil || before.ask?.about.isSubset(of: ids) == true,
                                       fail("a timer ends the ask exactly when it took everything the ask was about"))
                    }
                case .cleared:
                    XCTAssertNil(after.ask, fail("a clear ends the ask"))
                    XCTAssertTrue(nothingToPutBack(), fail("a clear leaves no answer to put back"))
                    XCTAssertTrue(keepsNoRole(Set(env.made.map(\.id))), fail("a clear forgets every role and finish"))
                    XCTAssertEqual(after.noteInk, before.noteInk, fail("a clear keeps the note's ink"))
                default:
                    break
                }
                if after.ask?.phase == .answered { XCTAssertNil(after.ask?.picked, fail("an answer's buttons are enabled")) }
                if !after.isUnderWay { XCTAssertEqual(after.pulsing, [], fail("nothing pulses with no ask under way")) }
            }
            env.play()
            XCTAssertNil(env.asks.ask, "a clear and every answer owed leave no ask (seed \(seed))")
        }
        XCTAssertGreaterThan(dropped, 300, "late callbacks are part of the mix")
        XCTAssertGreaterThan(restores, 50, "answers put back are part of the mix")
        XCTAssertGreaterThan(otherAsk, 50, "callbacks for another ask are part of the mix")
        XCTAssertGreaterThan(overlapping, 50, "overlapping finishes are part of the mix")
        XCTAssertGreaterThan(nested, 100, "an answer removed inside another event is part of the mix")
        XCTAssertGreaterThan(staleCapture, 10, "capture failures for an ask no longer current are part of the mix")
        XCTAssertGreaterThan(refused, 100, "refused asks are part of the mix")
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
        case packet(LiveAsks.Ask.ID, toSession: Bool)
        case captureFailed(LiveAsks.Ask.ID)
        case picture(LiveAsks.Ask.ID)
        case say(LiveAsks.Ask.ID)
        case answer(LiveAsks.Ask.ID)
        case failure(LiveAsks.Ask.ID)
        case sent(LiveAsks.Ask.ID, ink: Set<Mark.ID>, refused: Bool, carried: Bool)
        case carry(Set<Mark.ID>)
        case timer(Set<Mark.ID>)
        case focus([Mark])

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
    private var rng: SeededGenerator
    private var owed: [(due: Int, owed: Owed)] = []
    private var step = 0
    private var names: [Mark.ID: String] = [:]
    private var questions: [LiveAsks.Ask.ID: Mark.ID] = [:]
    private var focusShown: [Mark]?
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
        switch Int.random(in: 0..<20, using: &rng) {
        case 0...3: draw()
        case 4...6: ask()
        case 7...8: respond()
        case 9...10: dismissAnswer()
        case 11: erase()
        case 12: windowGone()
        case 13: pick()
        case 14: chordBegan()
        case 15: discardNote()
        case 16: letGoOfFocus()
        case 17: clear()
        default: break
        }
    }

    private func deliverDue() {
        let due = owed.filter { $0.due <= step }
        owed.removeAll { $0.due <= step }
        for item in due {
            switch item.owed {
            case .packet(let id, let toSession): packet(for: id, toSession: toSession)
            case .captureFailed(let id): failed(Self.couldNotSee, for: id)
            case .picture(let id): _ = send(.pictureSent(fresh: chance(2), for: id))
            case .say(let id): showSay(for: id)
            case .answer(let id): answered(for: id)
            case .failure(let id): failed("Claude stopped.", for: id)
            case .sent(let id, let ink, let refused, let carried): sessionAnswered(for: id, ink: ink, refused: refused, carried: carried)
            case .carry(let ids):
                for case .finish(let ids, let how) in send(.carrying(ids)) { finish(ids, how) }
            case .timer(let ids): finished(ids)
            case .focus(let stop): nextFocus(stop)
            }
        }
    }

    // MARK: Plumbing

    private func send(_ event: LiveAsks.Event) -> [LiveAsks.Effect] {
        let before = asks
        let effects = asks.reduce(event)
        trace.append("\(step): \(describe(event)) -> \(effects.map { describe($0) }) ask=\(describe(asks.ask))")
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
        _ = send(.removed(ids))
    }

    /// `takeOff`: off the screen, with no word to the asks.
    private func takeOff(_ ids: Set<Mark.ID>) { screen.removeAll { ids.contains($0.id) } }

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
        let ids = Set(screen.filter { _ in chance(3) }.map(\.id))
        guard !ids.isEmpty else { return }
        takeOff(ids)
        _ = send(.windowGone(ids))
    }

    private func pick() {
        guard let hit = screen.filter({ $0.agent && $0.kind != .text && asks.isAnswer($0.id) }).randomElement(using: &rng) else { return }
        let own = make(hit.geometry, agent: false, "p")
        _ = send(.drew(own.id))
        put([own])
        remove([hit.id])
    }

    private func chordBegan() {
        _ = send(.inkingBegan(noteOpen: chance(2)))
        letGoOfFocus()
    }

    private func discardNote() {
        for case .remove(let ids) in send(.noteDiscarded) { remove(ids) }
    }

    // MARK: Asking

    @discardableResult
    private func ask(following reply: Mark? = nil, picked: LiveAnswerActions.Pick = .reply) -> Bool {
        let before = asks
        let given = screen
        let shifted = chance(2)
        let begun = asks.begin(among: given, following: reply.map { LiveAsks.Following(reply: $0, pick: picked, words: "and this?") },
                               shift: { _ in shifted ? CGVector(dx: 0, dy: 12) : nil })
        let effects: [LiveAsks.Effect]
        switch begun {
        case .began(let id, let about, _, let began):
            effects = began
            trace.append("\(step): began #\(id) about=\(list(Set(about.map(\.id)))) following=\(name(reply?.id)) -> \(effects.map { describe($0) })")
        case .refused(let refusal, let refused):
            effects = refused
            trace.append("\(step): refused \(refusal) following=\(name(reply?.id)) -> \(effects.map { describe($0) })")
        }
        observe(self, Sent(step: .begun(begun, shown: given, following: reply != nil), before: before, after: asks, effects: effects))
        guard case .began(let id, _, _, _) = begun else {
            for case .restore(let id, let reason) in effects { restoreAnswer(id, saying: reason) }
            return false
        }
        for case .removeAnswer(let gone) in effects { removeAnswer(gone) }
        if let reply { put([reply]) }
        // A capture that fails can take a while, and `ask`'s task then fails the ask it began, whatever
        // has happened since.
        if chance(10) { owe(.captureFailed(id), in: 2...12) } else { owe(.packet(id, toSession: reply == nil && chance(5))) }
        return true
    }

    private func packet(for id: LiveAsks.Ask.ID, toSession: Bool) {
        let effects = send(.arrived(.packetCame(toSession: toSession), for: id))
        if effects.contains(where: { if case .share = $0 { true } else { false } }) {
            let ink = Set(asks.ink(among: screen).filter { _ in chance(2) }.map(\.id))
            owe(.sent(id, ink: ink, refused: chance(4), carried: chance(2)))
        }
        guard effects.contains(.send) else { return }
        if asks.ask?.say == nil, chance(2) {
            let question = note("What is this?", agent: false)
            put([question])
            questions[id] = question.id
            _ = send(.noted(question.id))
        }
        if chance(2) { _ = send(.pictureSent(fresh: chance(2), for: id)) } else { owe(.picture(id), in: 1...2) }
        // The responder can shut down as it is asked, which fails the ask in the same turn.
        if chance(8) { return failed("The responder ended.", for: id) }
        let says = Int.random(in: 0...3, using: &rng)
        for n in 0..<says { owe(.say(id), in: (n + 1)...(n + 1)) }
        owe(chance(4) ? .failure(id) : .answer(id), in: (says + 1)...(says + 3))
    }

    private func sessionAnswered(for id: LiveAsks.Ask.ID, ink: Set<Mark.ID>, refused: Bool, carried: Bool) {
        if refused { return failed("Not sent.", for: id) }
        for effect in send(.arrived(.sentToSession(ink: ink, carried: carried), for: id)) {
            switch effect {
            case .finish(let ids, let how): finish(ids, how)
            case .carry(let ids): owe(.carry(ids), in: 1...1)
            default: break
            }
        }
    }

    /// A press on the answer's panel. Its buttons are enabled only on an answer, and the panel shows
    /// only while the reply does (`shownReply`).
    private func respond() {
        guard let answer = asks.ask, answer.phase == .answered, let said = answer.say,
              screen.contains(where: { $0.id == said.id }), asks.isAnswer(said.id), !asks.isFinishing(said.id) else { return }
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
        for case .removeAnswer(let gone) in effects { removeAnswer(gone) }
        let reply: Mark
        if var shown = asks.ask?.say, case .text(var words) = shown.geometry {
            words.text += " more"
            shown.geometry = .text(words)
            reply = shown
        } else {
            reply = note("It's", agent: true)
        }
        _ = send(.streamed(reply))
        put([reply])
        replace(question: questions[id])
    }

    private func answered(for id: LiveAsks.Ask.ID) {
        let effects = send(.arrived(.answerCame, for: id))
        guard effects.contains(.drawAnswer) else { return }
        for case .removeAnswer(let gone) in effects { removeAnswer(gone) }
        let reply = asks.ask?.say ?? note("It's a button.", agent: true)
        let shapes = (0..<Int.random(in: 0...3, using: &rng)).map { _ in shape(agent: true) }
        let held = shapes.filter { _ in chance(3) }
        let shown = [reply] + shapes.filter { shape in !held.contains { $0.id == shape.id } }
        _ = send(.answered(reply: reply, actions: chance(2) ? [] : [LiveAnswer.Action("Fix it")], findings: shapes.map { [$0.id] },
                           shown: Set(shown.map(\.id))))
        put(shown)
        // `pullFocus`
        letGoOfFocus()
        if !held.isEmpty {
            if chance(4) {
                _ = send(.answerShown(Set(held.map(\.id))))
                put(held)
            } else {
                for (n, stop) in held.enumerated() { owe(.focus([stop]), in: (n + 1)...(n + 1)) }
            }
        }
        replace(question: questions[id])
    }

    private func replace(question: Mark.ID?) {
        guard let question, screen.contains(where: { $0.id == question }) else { return }
        remove([question])
    }

    private func nextFocus(_ stop: [Mark]) {
        if let previous = focusShown { dropFocus(previous) }
        focusShown = stop
        _ = send(.answerShown(Set(stop.map(\.id))))
        if chance(2), var reply = asks.ask?.say, case .text(var words) = reply.geometry, asks.isAnswer(reply.id) {
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
        guard let stop = focusShown else { return }
        focusShown = nil
        dropFocus(stop)
    }

    private func dropFocus(_ stop: [Mark]) {
        let ids = Set(stop.map(\.id)).intersection(asks.answerMarks)
        guard !ids.isEmpty else { return }
        remove(ids)
    }

    private func failed(_ reason: String, for id: LiveAsks.Ask.ID) {
        failed(send(.arrived(.failed(reason: reason, shown: shown), for: id)))
    }

    private func failed(_ effects: [LiveAsks.Effect]) {
        for effect in effects {
            switch effect {
            case .removeAnswer(let gone): removeAnswer(gone)
            case .restore(let reply, let reason): restoreAnswer(reply, saying: reason)
            case .say(let reason): say(reason)
            default: break
            }
        }
    }

    private func restoreAnswer(_ replyID: Mark.ID, saying reason: String) {
        guard var reply = screen.first(where: { $0.id == replyID }) else { return }
        reply.quote = nil
        reply.notice = reason
        _ = send(.replyRedrawn(reply))
        hideActions()
        put([reply])
    }

    /// Reply's field, when it is open, reports its words as it hides, for the reply it was made for.
    private func hideActions() {
        guard chance(3) else { return }
        let reply = chance(4) ? made.filter { $0.agent && $0.kind == .text }.randomElement(using: &rng)?.id : asks.ask?.say?.id
        _ = send(.drafted("half typed", reply: reply))
    }

    private func say(_ words: String) {
        guard let about = asks.ask?.about else { return }
        guard screen.contains(where: { about.contains($0.id) && $0.shapeExtent != nil }) else { return }
        let note = note(words, agent: false)
        _ = send(.answerShown([note.id]))
        put([note])
    }

    private func removeAnswer(_ gone: Set<Mark.ID>) {
        letGoOfFocus()
        hideActions()
        if !gone.isEmpty { remove(gone) }
    }

    // MARK: Exits

    private func dismissAnswer() {
        letGoOfFocus()
        for case .finish(let ids, let how) in send(.dismissed) { finish(ids, how) }
    }

    private func finish(_ ids: Set<Mark.ID>, _ how: LiveMarksLayer.Finish) {
        owe(.timer(ids), in: how == .carried ? 1...1 : 1...3)
    }

    private func finished(_ ids: Set<Mark.ID>) {
        for case .remove(let gone) in send(.finished(ids)) { remove(gone) }
    }

    /// `clear()`, which takes the marks off first, or `setOn(false)`, which takes them off after.
    private func clear() {
        let marksFirst = chance(2)
        if marksFirst { screen = [] }
        // `responder.stop()` fails every ask it holds, in order.
        var held: [LiveAsks.Ask.ID] = []
        for item in owed { if let id = item.owed.heldBy, !held.contains(id) { held.append(id) } }
        owed.removeAll { $0.owed.heldBy != nil }
        for id in held { failed("Claude stopped before it answered.", for: id) }
        letGoOfFocus()
        _ = send(.cleared)
        screen = []
    }

    // MARK: Trace

    private func name(_ id: Mark.ID?) -> String { id.map { names[$0] ?? "?" } ?? "nil" }

    private func list(_ ids: Set<Mark.ID>) -> String { "[" + ids.map { name($0) }.sorted().joined(separator: " ") + "]" }

    private func describe(_ ask: LiveAsks.Ask?) -> String {
        guard let ask else { return "nil" }
        return "#\(ask.id) \(ask.phase) about=\(list(ask.about)) say=\(name(ask.say?.id))\(ask.picked == nil ? "" : " picked")"
    }

    private func describe(_ event: LiveAsks.Event) -> String {
        switch event {
        case .drew(let id): "drew \(name(id))"
        case .inkingBegan(let open): "inkingBegan open=\(open)"
        case .noteDiscarded: "noteDiscarded"
        case .removed(let ids): "removed \(list(ids))"
        case .windowGone(let ids): "windowGone \(list(ids))"
        case .arrived(let arrival, let id): "\(describe(arrival)) #\(id)"
        case .noted(let mark): "noted \(name(mark))"
        case .pictureSent(let fresh, let id): "pictureSent \(fresh) #\(id)"
        case .streamed(let mark): "streamed \(name(mark.id))"
        case .answered(let reply, _, _, let shown): "answered \(name(reply?.id)) shown=\(list(shown))"
        case .drafted(_, let reply): "drafted \(name(reply))"
        case .replyRedrawn(let reply): "replyRedrawn \(name(reply.id))"
        case .answerShown(let ids): "answerShown \(list(ids))"
        case .dismissed: "dismissed"
        case .carrying(let ids): "carrying \(list(ids))"
        case .finished(let ids): "finished \(list(ids))"
        case .cleared: "cleared"
        }
    }

    private func describe(_ arrival: LiveAsks.Arrival) -> String {
        switch arrival {
        case .packetCame(let toSession): "packetCame\(toSession ? " session" : "")"
        case .replyCame: "replyCame"
        case .answerCame: "answerCame"
        case .failed(let reason, _): "failed \"\(reason)\""
        case .sentToSession(let ink, let carried): "sentToSession ink=\(list(ink))\(carried ? " carried" : "")"
        }
    }

    private func describe(_ effect: LiveAsks.Effect) -> String {
        switch effect {
        case .send: "send"
        case .share(let about): "share \(list(about))"
        case .showReply: "showReply"
        case .drawAnswer: "drawAnswer"
        case .restore(let reply, _): "restore \(name(reply))"
        case .say: "say"
        case .remove(let ids): "remove \(list(ids))"
        case .removeAnswer(let gone): "removeAnswer \(list(gone))"
        case .finish(let ids, let how): "finish \(list(ids)) \(how)"
        case .carry(let ids): "carry \(list(ids))"
        }
    }
}
