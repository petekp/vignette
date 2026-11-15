import CoreGraphics
import XCTest

extension LiveAsksTests {
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
                       [.interrupt, .restore(reply: reply.id, reason: nil, aside: [], followUp: follow)])
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
                       [.interrupt, .restore(reply: reply.id, reason: nil, aside: [loop.id], followUp: follow)])
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
}
