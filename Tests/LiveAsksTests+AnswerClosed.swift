import CoreGraphics
import XCTest

extension LiveAsksTests {
    func testEscClosesTheNewestAnswerFirstAndKeepsTheInk() {
        var a = A()
        let first = ink(), second = ink(50), reply = text("It's a button.", agent: true), loop = shape(), later = text("Later", agent: true)
        let one = answer(&a, on: [first], reply: reply, shapes: [loop])
        let two = answer(&a, on: [first, second], reply: later)
        let all: Set<Mark.ID> = [first.id, second.id, reply.id, loop.id, later.id]
        XCTAssertEqual(reduce(&a, .answerClosed(inSight: all)), [.ended(two), .finish([later.id], .dismissed)], "the newest first")
        XCTAssertNil(a.ask(two))
        XCTAssertEqual(reduce(&a, .answerClosed(inSight: all)), [.ended(one), .finish([reply.id, loop.id], .dismissed)], "then the one before")
        XCTAssertNil(a.ask(one))
        XCTAssertEqual(Set(a.finishing.keys), [later.id, reply.id, loop.id], "only the answers are leaving")
        XCTAssertEqual(reduce(&a, .finished([reply.id, loop.id])), [.remove([reply.id, loop.id])])
        XCTAssertEqual(a.ink(among: [first]).map(\.id), [first.id])
        XCTAssertEqual(reduce(&a, .answerClosed(inSight: all)), [], "with no answer left there is nothing to close")
    }

    func testEscClosesTheNewestAnswerInSightAndLeavesOneOnAnotherSpace() {
        var a = A()
        let first = ink(), second = ink(50), reply = text("It's a button.", agent: true), loop = shape(), later = text("Later", agent: true)
        let one = answer(&a, on: [first], reply: reply, shapes: [loop])
        let two = answer(&a, on: [second], reply: later)
        XCTAssertEqual(reduce(&a, .answerClosed(inSight: [first.id, reply.id, loop.id])), [.ended(one), .finish([reply.id, loop.id], .dismissed)],
                       "the newer answer is out of sight, so the older one in sight closes")
        XCTAssertNotNil(a.ask(two))
        XCTAssertEqual(reduce(&a, .answerClosed(inSight: [first.id, second.id])), [], "an answer out of sight is never closed")
        XCTAssertNotNil(a.ask(two))
    }

    func testClosingAnAnswerPassesOverAsksUnderWay() {
        var a = A()
        let mark = ink(), other = ink(50), reply = text("It's a button.", agent: true), conversation = text("", agent: true)
        let first = answer(&a, on: [mark], reply: reply)
        let next = begin(&a, on: [mark, reply, other])
        _ = reduce(&a, .conversed(conversation, for: next))
        XCTAssertFalse(a.isSettledAnswer(conversation.id), "a conversation waiting for its answer is not one Esc closes")
        XCTAssertEqual(reduce(&a, .answerClosed(inSight: [mark.id, other.id, reply.id, conversation.id])), [.ended(first), .finish([reply.id], .dismissed)])
        XCTAssertNil(a.ask(first))
        XCTAssertNotNil(a.ask(next))
    }
}
