import XCTest

/// Sequences of what happens between Send and the line reaching the client. No timers: the times
/// come in with the events.
final class SendGraceTests: XCTestCase {
    private var grace = SendGrace()

    private func send(_ request: String, file: String = "/shots/a.png", line: String = "line", length: TimeInterval = 3,
                      at time: TimeInterval = 100) -> [SendGrace.Effect] {
        grace.handle(.sent(request: request, file: file, line: line, grace: length, at: time))
    }

    /// A timer that runs twice, or after the deadline was handled, must not hand the line over twice.
    func testTheLineGoesOnceWhenTheDeadlineComes() {
        XCTAssertEqual(send("r", line: "the line"), [.arm(request: "r", after: 3)])
        XCTAssertEqual(grace.handle(.due(request: "r", at: 103)), [.submit(request: "r", line: "the line", waited: 3)])
        XCTAssertEqual(grace.handle(.due(request: "r", at: 103.5)), [])
        XCTAssertNil(grace.wait(of: "r"))
    }

    /// A cancelled send must never go out, even when its timer still runs.
    func testACancelledSendIsDiscardedAndItsTimerDoesNothing() {
        _ = send("r")
        XCTAssertEqual(grace.handle(.cancelled(file: "/shots/a.png")), [.discard(request: "r")])
        XCTAssertEqual(grace.handle(.due(request: "r", at: 103)), [])
    }

    /// A cancel after the line was handed over must be refused, not clear a request the agent has.
    func testACancelAfterTheLineWentIsRefused() {
        _ = send("r")
        _ = grace.handle(.due(request: "r", at: 103))
        XCTAssertEqual(grace.handle(.cancelled(file: "/shots/a.png")), [])
    }

    /// Sends of different screenshots share nothing: cancelling one leaves the other to its own deadline.
    func testSendsOfDifferentFilesAreIndependent() {
        _ = send("a", file: "/shots/a.png", length: 3, at: 100)
        _ = send("b", file: "/shots/b.png", length: 5, at: 101)
        XCTAssertEqual(grace.handle(.cancelled(file: "/shots/a.png")), [.discard(request: "a")])
        XCTAssertEqual(grace.handle(.due(request: "b", at: 103)), [.arm(request: "b", after: 3)], "b waits until 106")
        XCTAssertEqual(grace.handle(.due(request: "b", at: 106)), [.submit(request: "b", line: "line", waited: 5)])
    }

    /// A cancel that left an earlier send of the same file waiting would let a line go out unseen.
    func testCancellingAFileDiscardsEverySendOfItInSendOrder() {
        _ = send("first", at: 100)
        _ = send("second", at: 101)
        _ = send("other", file: "/shots/b.png")
        XCTAssertEqual(grace.handle(.cancelled(file: "/shots/a.png")), [.discard(request: "first"), .discard(request: "second")])
        XCTAssertNotNil(grace.wait(of: "other"))
    }

    /// A setting of 0 means off: nothing may wait.
    func testNoGraceSubmitsAtOnceAndKeepsNothing() {
        XCTAssertEqual(send("r", length: 0), [.submit(request: "r", line: "line", waited: nil)])
        XCTAssertEqual(send("s", length: -1), [.submit(request: "s", line: "line", waited: nil)])
        XCTAssertTrue(grace.waiting.isEmpty)
    }

    /// A timer that runs early must not shorten the grace.
    func testATimerThatRunsEarlyArmsAgainForWhatIsLeft() {
        _ = send("r")
        XCTAssertEqual(grace.handle(.due(request: "r", at: 102.25)), [.arm(request: "r", after: 0.75)])
        XCTAssertNotNil(grace.wait(of: "r"))
    }

    /// A cleared request must not be submitted when its timer runs.
    func testAClearTakesAWaitingSendAndItsTimerDoesNothing() {
        _ = send("r")
        XCTAssertEqual(grace.handle(.cleared(request: "r")), [.dropped(request: "r")])
        XCTAssertEqual(grace.handle(.due(request: "r", at: 103)), [])
        XCTAssertEqual(grace.handle(.cleared(request: "r")), [])
    }

    /// Quitting must hand over every waiting line, in the order they were sent, once.
    func testQuitSubmitsEveryWaitInSendOrderOnce() {
        _ = send("a", file: "/shots/a.png", line: "one")
        _ = send("b", file: "/shots/b.png", line: "two")
        XCTAssertEqual(grace.handle(.quit), [.submit(request: "a", line: "one", waited: 3), .submit(request: "b", line: "two", waited: 3)])
        XCTAssertTrue(grace.waiting.isEmpty)
        XCTAssertEqual(grace.handle(.quit), [])
    }
}
