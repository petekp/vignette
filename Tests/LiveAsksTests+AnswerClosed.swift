import CoreGraphics
import XCTest

extension LiveAsksTests {
    func testEscClosesTheNewestAnswerAndOnlyTheInkItWasAbout() {
        var a = A()
        let first = ink(), second = ink(50), reply = text("It's a button.", agent: true), loop = shape(), later = text("Later", agent: true)
        let one = answer(&a, on: [first], reply: reply, shapes: [loop])
        let two = answer(&a, on: [first, second], reply: later)
        let all: Set<Mark.ID> = [first.id, second.id, reply.id, loop.id, later.id]
        XCTAssertEqual(a.newestAnswerToClose(inSight: all), two, "the newest first")
        XCTAssertEqual(reduce(&a, .dismissed(two)), [.ended(two), .finish([later.id, second.id], .dismissed)], "ink of the older answer stays")
        XCTAssertEqual(a.newestAnswerToClose(inSight: all), one, "then the one before")
        XCTAssertEqual(reduce(&a, .dismissed(one)), [.ended(one), .finish([reply.id, loop.id, first.id], .dismissed)])
        XCTAssertNil(a.newestAnswerToClose(inSight: all), "with no answer left there is nothing to close")
    }

    func testEscClosesTheNewestAnswerInSightAndLeavesOneOnAnotherSpace() {
        var a = A()
        let first = ink(), second = ink(50), reply = text("It's a button.", agent: true), loop = shape(), later = text("Later", agent: true)
        let one = answer(&a, on: [first], reply: reply, shapes: [loop])
        let two = answer(&a, on: [second], reply: later)
        XCTAssertEqual(a.newestAnswerToClose(inSight: [first.id, reply.id, loop.id]), one,
                       "the newer answer is out of sight, so the older one in sight closes")
        XCTAssertEqual(reduce(&a, .dismissed(one)), [.ended(one), .finish([reply.id, loop.id, first.id], .dismissed)])
        XCTAssertNil(a.newestAnswerToClose(inSight: [first.id, second.id]), "an answer out of sight is never closed")
        XCTAssertNotNil(a.ask(two))
        XCTAssertEqual(a.newestAnswerToClose(inSight: [second.id, later.id]), two, "it closes once its Space is the active one")
    }

    func testEscLeavesInkNoAnswerIsAbout() {
        var a = A()
        let asked = ink(), loose = ink(50), reply = text("It's a button.", agent: true)
        _ = reduce(&a, .drew(loose.id))
        let id = answer(&a, on: [asked], reply: reply)
        XCTAssertEqual(a.newestAnswerToClose(inSight: [asked.id, loose.id, reply.id]), id)
        XCTAssertEqual(reduce(&a, .dismissed(id)), [.ended(id), .finish([reply.id, asked.id], .dismissed)])
        XCTAssertEqual(a.newInk(among: [loose]).map(\.id), [loose.id], "loose ink stays for the next Esc")
    }

    func testClosingAnAnswerPassesOverAsksUnderWay() {
        var a = A()
        let mark = ink(), other = ink(50), reply = text("It's a button.", agent: true), conversation = text("", agent: true)
        let first = answer(&a, on: [mark], reply: reply)
        let next = begin(&a, on: [mark, reply, other])
        _ = reduce(&a, .conversed(conversation, for: next))
        XCTAssertFalse(a.isSettledAnswer(conversation.id), "a conversation waiting for its answer is not one Esc closes")
        XCTAssertEqual(a.newestAnswerToClose(inSight: [mark.id, other.id, reply.id, conversation.id]), first)
        XCTAssertEqual(reduce(&a, .dismissed(first)), [.ended(first), .finish([reply.id, mark.id], .dismissed)])
        XCTAssertNil(a.ask(first))
        XCTAssertNotNil(a.ask(next))
    }
}
