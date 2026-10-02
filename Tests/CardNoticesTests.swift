import XCTest

final class CardNoticesTests: XCTestCase {
    private let file = "/tmp/shot.png"
    private let hold: TimeInterval = 2

    @discardableResult
    private func post(_ notices: inout CardNotices, _ event: CardNotices.Event, seen: Bool = true) -> CardNotices.Posted? {
        notices.post(event, on: file, seen: seen, markHold: hold)
    }

    private func sending(_ request: String) -> CardNotices.Event {
        .sending(request: request, client: .claude, project: "vignette")
    }

    private func sendState(_ notices: CardNotices) -> SendMark.State? {
        if case .send(let mark)? = notices.notice(on: file) { return mark.state }
        return nil
    }

    /// One notice at a time: whatever happened last is what the card says.
    func testEachNoticeReplacesTheOneBefore() {
        var notices = CardNotices()
        post(&notices, .copied(label: "Copied"))
        post(&notices, sending("a"))
        XCTAssertEqual(sendState(notices), .sending)
        post(&notices, .answered(request: "a", state: .sent, reason: nil))
        post(&notices, .notCopied(reason: "The disk is full."))
        XCTAssertEqual(notices.notice(on: file), .notCopied(reason: "The disk is full."))
        post(&notices, .copied(label: "Copied Path"))
        XCTAssertEqual(notices.notice(on: file), .copied(label: "Copied Path"))
    }

    /// A copy made while a send is out takes the card, and the send's failure still reaches it.
    func testAFailedSendIsShownAfterACopyMadeWhileItWaited() {
        var notices = CardNotices()
        post(&notices, sending("a"))
        post(&notices, .copied(label: "Copied"))
        XCTAssertTrue(notices.awaitsAnswer(on: [file]), "the corner waits for the answer")
        let posted = post(&notices, .answered(request: "a", state: .failed, reason: "The session closed."))
        XCTAssertNotNil(posted)
        XCTAssertEqual(sendState(notices), .failed)
        XCTAssertFalse(notices.awaitsAnswer(on: [file]))
    }

    /// Only the newest posting's timer takes a notice down.
    func testAnEarlierTimerLeavesALaterNoticeUp() throws {
        var notices = CardNotices()
        let first = try XCTUnwrap(post(&notices, .copied(label: "Copied")))
        post(&notices, .copied(label: "Copied"))
        notices.expire(first.id, on: file)
        XCTAssertEqual(notices.notice(on: file), .copied(label: "Copied"), "two copies a second apart")

        let failure = try XCTUnwrap(post(&notices, .notCopied(reason: "The disk is full.")))
        let again = try XCTUnwrap(post(&notices, .notCopied(reason: "The disk is full.")))
        notices.expire(failure.id, on: file)
        XCTAssertNotNil(notices.notice(on: file), "the same failure twice")
        notices.expire(again.id, on: file)
        XCTAssertNil(notices.notice(on: file))
    }

    func testAnAnswerToAnEarlierSendIsDropped() {
        var notices = CardNotices()
        post(&notices, sending("a"))
        post(&notices, sending("b"))
        XCTAssertNil(post(&notices, .answered(request: "a", state: .failed, reason: "Old.")))
        XCTAssertEqual(sendState(notices), .sending)
        XCTAssertTrue(notices.awaitsAnswer(on: [file]))
    }

    func testAFailedReplyWaitsBehindALaterSendButNotAFinishedOne() {
        var notices = CardNotices()
        post(&notices, sending("b"))
        XCTAssertNil(post(&notices, .replyFailed(request: "a", client: .codex, reason: "Unreadable.")))
        XCTAssertEqual(sendState(notices), .sending)
        post(&notices, .answered(request: "b", state: .sent, reason: nil))
        XCTAssertNotNil(post(&notices, .replyFailed(request: "a", client: .codex, reason: "Unreadable.")))
        XCTAssertEqual(sendState(notices), .replyFailed)
    }

    /// A card nobody will see says nothing more about a send that worked, and comes back for
    /// anything else.
    func testWhatACardNobodySeesComesBackFor() {
        var notices = CardNotices()
        post(&notices, sending("a"))
        XCTAssertNil(post(&notices, .answered(request: "a", state: .sent, reason: nil), seen: false))
        XCTAssertNil(notices.notice(on: file), "the sending mark goes with it")

        for state: SendMark.State in [.queued, .uncertain, .failed] {
            post(&notices, sending("q"))
            XCTAssertNotNil(post(&notices, .answered(request: "q", state: state, reason: "Why."), seen: false), "\(state)")
            XCTAssertEqual(sendState(notices), state)
        }
        XCTAssertNotNil(post(&notices, .notCopied(reason: "Why."), seen: false))
        XCTAssertNotNil(post(&notices, .replyFailed(request: "r", client: .claude, reason: "Why."), seen: false))
    }

    /// A notice with a sentence to read holds three times as long; a send waiting for its answer holds
    /// until it comes.
    func testHolds() {
        var notices = CardNotices()
        XCTAssertEqual(post(&notices, .copied(label: "Copied"))?.hold, hold)
        XCTAssertEqual(post(&notices, .notCopied(reason: "Why."))?.hold, hold * 3)
        XCTAssertEqual(post(&notices, .replyFailed(request: "r", client: .claude, reason: "Why."))?.hold, hold * 3)
        let expected: [SendMark.State: TimeInterval] = [.sent: hold, .queued: hold * 3, .uncertain: hold * 3, .failed: hold * 3]
        for (state, time) in expected {
            let start = post(&notices, sending("s"))
            XCTAssertNil(start?.hold, "sending")
            XCTAssertEqual(post(&notices, .answered(request: "s", state: state, reason: nil))?.hold, time, "\(state)")
        }
    }

    func testNoticesAreKeptPerFile() {
        var notices = CardNotices()
        post(&notices, .copied(label: "Copied"))
        XCTAssertNotNil(notices.post(.notCopied(reason: "Why."), on: "/tmp/other.png", seen: true, markHold: hold))
        XCTAssertEqual(notices.notice(on: file), .copied(label: "Copied"))
        XCTAssertFalse(notices.awaitsAnswer(on: ["/tmp/other.png"]))
    }
}
