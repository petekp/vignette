import XCTest
import os

final class CodexQueueTests: XCTestCase {
    func testTheLineIdIsReadFromWhatCodexQueuePrints() {
        let thread = "01a1e7b5-5855-7441-80ab-7a49ae2b5b8b"
        XCTAssertEqual(QueuedLine.of(output: "Queued message 01a1e7c0-0000-7000-8000-00000000000a for thread \(thread).\n", thread: thread),
                       QueuedLine(id: "01a1e7c0-0000-7000-8000-00000000000a", thread: thread))
        XCTAssertEqual(QueuedLine.of(output: "warning: x\nQueued message 7 for thread \(thread.uppercased())", thread: thread)?.id, "7")
        XCTAssertNil(QueuedLine.of(output: "Queued message 7 for thread 01a1e7b5-0000-7441-80ab-7a49ae2b5b8b.", thread: thread))
        XCTAssertNil(QueuedLine.of(output: "", thread: thread))
        XCTAssertNil(QueuedLine.of(output: "Message queued.", thread: thread))
    }

    func testTheRolloutsEndSaysHowTheLastTurnStands() {
        func end(_ lines: [String]) -> RolloutEnd { RolloutEnd.of(tail: Data(lines.joined(separator: "\n").utf8)) }
        let nested = #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"n","root_turn_id":"a"}}"#
        XCTAssertEqual(end([]), .unknown)
        XCTAssertEqual(end([RolloutLines.started]), .running)
        XCTAssertEqual(end([RolloutLines.started, RolloutLines.asked]), .asking)
        XCTAssertEqual(end([RolloutLines.started, RolloutLines.asked, RolloutLines.answered]), .running)
        XCTAssertEqual(end([RolloutLines.started, RolloutLines.completed]), .ended)
        XCTAssertEqual(end([RolloutLines.started, RolloutLines.asked, RolloutLines.aborted]), .stopped)
        XCTAssertEqual(end([RolloutLines.started, RolloutLines.aborted, RolloutLines.started]), .running)
        XCTAssertEqual(end([RolloutLines.started, nested]), .running)
        XCTAssertEqual(end(["ype\":\"task_complete\"}}", RolloutLines.started]), .running)
    }

    func testWhyTheQueueHoldsTheLineFollowsTheTurnAndWhetherTheThreadIsOpen() {
        XCTAssertEqual(QueuedLine.Hold.of(.running, loaded: true), .turnRunning)
        XCTAssertEqual(QueuedLine.Hold.of(.asking, loaded: true), .question)
        XCTAssertEqual(QueuedLine.Hold.of(.stopped, loaded: true), .stopped)
        XCTAssertEqual(QueuedLine.Hold.of(.stopped, loaded: false), .stopped)
        XCTAssertEqual(QueuedLine.Hold.of(.running, loaded: false), .notOpen)
        XCTAssertEqual(QueuedLine.Hold.of(.ended, loaded: false), .notOpen)
        XCTAssertEqual(QueuedLine.Hold.of(.ended, loaded: true), .nothing)
        XCTAssertEqual(QueuedLine.Hold.of(.unknown, loaded: true), .nothing)
    }

    func testTheWatchSaysEachNewReasonOnceAndWaitsForTheEnginesLookBeforeSayingNothingHoldsIt() {
        let line = QueuedLine(id: "q", thread: "t")
        var watch = QueueWatch(line: line, queued: 100, shown: QueuedLine.Hold.turnRunning.reason)
        XCTAssertEqual(watch.look(.held(.turnRunning), at: 103), .wait)
        XCTAssertEqual(watch.look(.held(.question), at: 106), .show(.question))
        XCTAssertEqual(watch.look(.held(.question), at: 109), .wait)
        XCTAssertEqual(watch.look(.held(.nothing), at: 112), .wait)
        XCTAssertEqual(watch.look(.held(.nothing), at: 126), .wait)
        XCTAssertEqual(watch.look(.held(.nothing), at: 127), .show(.nothing))
        XCTAssertEqual(watch.look(.unread(detail: "locked"), at: 130), .logUnread("locked"))
        XCTAssertEqual(watch.look(.unread(detail: "locked"), at: 133), .wait)
        XCTAssertEqual(watch.look(.removed, at: 136), .removed)
        XCTAssertEqual(watch.look(.taken, at: 136), .taken(wasShown: true))

        var idle = QueueWatch(line: line, queued: 100, shown: nil)
        XCTAssertEqual(idle.look(.held(.nothing), at: 103), .wait)
        XCTAssertEqual(idle.look(.taken, at: 106), .taken(wasShown: false), "a card that said Sent says nothing more")
        XCTAssertEqual(idle.look(.threadGone(detail: "gone"), at: 109), .threadGone(detail: "gone"))

        XCTAssertEqual(watch.nextLook(at: 159), 3)
        XCTAssertEqual(watch.nextLook(at: 160), 10)
        XCTAssertEqual(watch.nextLook(at: 400), 30)
        XCTAssertEqual(watch.nextLook(at: 100 + 30 * 60), 60)
    }

    func testALookFindsTheThreadGoneAndDontSendTakesTheLineOut() {
        let line = QueuedLine(id: "01a1e7c0-000a", thread: "01a1e7b5-5855-7441-80ab-7a49ae2b5b8b")
        let asked = OSAllocatedUnfairLock(initialState: [String]())
        let answer = OSAllocatedUnfairLock(initialState: "")
        var connection = CodexConnection()
        connection.binary = { "/bin/codex" }
        connection.isLoaded = { _ in true }
        connection.converse = { _, _, requests in
            asked.withLock { $0 = requests }
            return [answer.withLock { $0 }]
        }

        answer.withLock { $0 = #"{"id":2,"error":{"code":-32600,"message":"thread not found: 01a1e7b5"}}"# }
        XCTAssertEqual(connection.look(at: line, carrying: "x"), .threadGone(detail: "thread not found: 01a1e7b5"))
        answer.withLock { $0 = #"{"id":2,"error":{"code":-32603,"message":"failed to read thread: invalid thread-store request: no rollout found for thread id 01a1e7b5"}}"# }
        XCTAssertEqual(connection.look(at: line, carrying: "x"), .threadGone(detail: "failed to read thread: invalid thread-store request: no rollout found for thread id 01a1e7b5"))
        answer.withLock { $0 = #"{"id":2,"error":{"code":-32600,"message":"session 01a1e7b5 is archived. Run `codex unarchive 01a1e7b5` to unarchive it first."}}"# }
        XCTAssertEqual(connection.look(at: line, carrying: "x"), .held(.archived))
        answer.withLock { $0 = #"{"id":2,"error":{"code":-32603,"message":"database is locked"}}"# }
        XCTAssertEqual(connection.look(at: line, carrying: "x"), .unread(detail: "database is locked"))

        answer.withLock { $0 = #"{"id":2,"result":{"deleted":true}}"# }
        XCTAssertEqual(connection.withdraw(line), .removed)
        XCTAssertEqual(asked.withLock { $0.last },
                       #"{"id":2,"method":"thread\/queue\/delete","params":{"queuedSubmissionId":"01a1e7c0-000a","threadId":"\#(line.thread)"}}"#)
        answer.withLock { $0 = #"{"id":2,"result":{"deleted":false}}"# }
        XCTAssertEqual(connection.withdraw(line), .alreadyTaken)
        answer.withLock { $0 = #"{"id":2,"error":{"code":-32600,"message":"session 01a1e7b5 is archived."}}"# }
        XCTAssertEqual(connection.withdraw(line), .failed(detail: "session 01a1e7b5 is archived."))
        answer.withLock { $0 = "" }
        XCTAssertEqual(connection.withdraw(line), .failed(detail: "no answer"))
    }
}

enum RolloutLines {
    static let started = #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"a","root_turn_id":"a"}}"#
    static let completed = #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"a"}}"#
    static let aborted = #"{"type":"event_msg","payload":{"type":"turn_aborted","turn_id":"a","root_turn_id":"a","reason":"interrupted"}}"#
    static let asked = #"{"type":"response_item","payload":{"type":"function_call","name":"request_user_input","call_id":"q1","arguments":"{}"}}"#
    static let answered = #"{"type":"response_item","payload":{"type":"function_call_output","call_id":"q1","output":"yes"}}"#
}
