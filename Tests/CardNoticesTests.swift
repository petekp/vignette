import XCTest

final class CardNoticesTests: XCTestCase {
    private let file: ScreenshotKey = "/tmp/shot.png"
    private let hold: TimeInterval = 2

    @discardableResult
    private func post(_ notices: inout CardNotices, _ event: CardNotices.Event, seen: Bool = true) -> CardNotices.Posted? {
        notices.post(event, on: file, seen: seen, noticeHold: hold)
    }

    private func sending(_ request: String) -> CardNotices.Event {
        .sending(request: request, client: .claude, sessionTitle: "vignette")
    }

    private func sendState(_ notices: CardNotices) -> SendNotice.State? {
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
        notices.expire(first.id)
        XCTAssertEqual(notices.notice(on: file), .copied(label: "Copied"), "two copies a second apart")

        let failure = try XCTUnwrap(post(&notices, .notCopied(reason: "The disk is full.")))
        let again = try XCTUnwrap(post(&notices, .notCopied(reason: "The disk is full.")))
        notices.expire(failure.id)
        XCTAssertNotNil(notices.notice(on: file), "the same failure twice")
        notices.expire(again.id)
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

        for state: SendNotice.State in [.queued, .uncertain, .failed] {
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
        let expected: [SendNotice.State: TimeInterval] = [.sent: hold, .queued: hold * 3, .uncertain: hold * 3, .failed: hold * 3]
        for (state, time) in expected {
            let start = post(&notices, sending("s"))
            XCTAssertNil(start?.hold, "sending")
            XCTAssertEqual(post(&notices, .answered(request: "s", state: state, reason: nil))?.hold, time, "\(state)")
        }
    }

    func testNoticesAreKeptPerFile() {
        var notices = CardNotices()
        post(&notices, .copied(label: "Copied"))
        XCTAssertNotNil(notices.post(.notCopied(reason: "Why."), on: "/tmp/other.png", seen: true, noticeHold: hold))
        XCTAssertEqual(notices.notice(on: file), .copied(label: "Copied"))
        XCTAssertFalse(notices.awaitsAnswer(on: ["/tmp/other.png"]))
    }

    // MARK: A send in its grace

    private let grace = SendNotice.Grace(deadline: 13, length: 3)

    private func waiting(_ request: String) -> CardNotices.Event {
        .sending(request: request, client: .claude, sessionTitle: "vignette", grace: grace)
    }

    /// A card stuck on the countdown would offer Don't send for a line that has gone.
    func testASendInItsGraceWaitsAndReleaseMovesItOnToSending() {
        var notices = CardNotices()
        post(&notices, waiting("a"))
        XCTAssertEqual(sendState(notices), .inGrace)
        XCTAssertTrue(notices.awaitsAnswer(on: [file]))
        XCTAssertNil(post(&notices, .released(request: "b")), "another request's release")
        XCTAssertEqual(sendState(notices), .inGrace)
        XCTAssertNil(post(&notices, .released(request: "a")))
        XCTAssertEqual(sendState(notices), .sending)
        guard case .send(let send)? = notices.notice(on: file) else { return XCTFail("the send's notice is gone") }
        XCTAssertNil(send.grace)
        XCTAssertNotNil(post(&notices, .answered(request: "a", state: .sent, reason: nil)))
        XCTAssertEqual(sendState(notices), .sent)
    }

    /// A card that kept saying Sending after Don't send would claim a line that never went.
    func testACancelledSendLosesItsNoticeAndTheWaitForAnAnswer() {
        var notices = CardNotices()
        post(&notices, waiting("a"))
        XCTAssertNil(post(&notices, .cancelled(request: "a")))
        XCTAssertNil(notices.notice(on: file))
        XCTAssertFalse(notices.awaitsAnswer(on: [file]))
        XCTAssertNil(post(&notices, .answered(request: "a", state: .sent, reason: nil)))
        XCTAssertNil(notices.notice(on: file))
    }

    /// Cancelling an earlier send must not clear the ring of a later one on the same file.
    func testCancellingAnEarlierSendLeavesALaterOneInItsGrace() {
        var notices = CardNotices()
        post(&notices, waiting("a"))
        post(&notices, waiting("b"))
        post(&notices, .cancelled(request: "a"))
        XCTAssertEqual(sendState(notices), .inGrace)
        XCTAssertTrue(notices.awaitsAnswer(on: [file]))
    }

    /// A Copied notice that covered the countdown must not hide Don't send for the rest of the grace.
    func testACopiedNoticeGivesTheCountdownBackWhenItExpires() throws {
        var notices = CardNotices()
        post(&notices, waiting("a"))
        let copied = try XCTUnwrap(post(&notices, .copied(label: "Copied")))
        XCTAssertEqual(notices.notice(on: file), .copied(label: "Copied"))
        notices.expire(copied.id)
        XCTAssertEqual(sendState(notices), .inGrace)
    }

    func testANoticeOnAFileRenamedDuringItsHoldStillExpires() throws {
        var notices = CardNotices()
        let renamed: ScreenshotKey = "/tmp/renamed.png"
        post(&notices, waiting("a"))
        let copied = try XCTUnwrap(post(&notices, .copied(label: "Copied")))
        notices.rename(from: file, to: renamed)
        notices.expire(copied.id)
        guard case .send(let send)? = notices.notice(on: renamed) else { return XCTFail("the Copied notice outlived its hold") }
        XCTAssertEqual(send.state, .inGrace)
    }

    /// Only the countdown comes back: a line already released gives its card the answer, as a send with no
    /// grace does, so a Copied that expires after the release must not bring back a Sending nobody ends.
    func testAReleaseUnderACopiedLeavesNothingToShowWhenTheCopiedExpires() throws {
        var notices = CardNotices()
        post(&notices, waiting("a"))
        let copied = try XCTUnwrap(post(&notices, .copied(label: "Copied")))
        post(&notices, .released(request: "a"))
        notices.expire(copied.id)
        XCTAssertNil(notices.notice(on: file))
        post(&notices, .answered(request: "a", state: .sent, reason: nil))
        XCTAssertEqual(sendState(notices), .sent)
    }

    /// A ring that restarted when its card landed late would show more time than the send has.
    func testTheGraceRemainingIsClampedToTheSendsOwnLength() {
        XCTAssertEqual(grace.remaining(at: 20), 0, "after the deadline")
        XCTAssertEqual(grace.remaining(at: 5), 1, "before the start")
    }

    /// A line released and answered in one turn must still show Sending, or the card jumps from the
    /// countdown to the answer.
    func testALineReleasedAndAnsweredTogetherStillShowsSending() {
        XCTAssertEqual(SendNotice.steps(from: .inGrace, to: .sent), [.sending, .sent])
        XCTAssertEqual(SendNotice.steps(from: .inGrace, to: .sending), [.sending])
        XCTAssertEqual(SendNotice.steps(from: .sending, to: .failed), [.failed])
    }

    func testAQueuedAnswerCarriesDontSendAndWithdrawingTakesItsNoticeDown() {
        var notices = CardNotices()
        post(&notices, sending("q"))
        post(&notices, .answered(request: "q", state: .queued, reason: "Why.", withdrawable: true))
        guard case .send(let shown)? = notices.notice(on: file) else { return XCTFail("the queued notice is up") }
        XCTAssertTrue(shown.withdrawable)

        post(&notices, .withdrawing(request: "other"))
        XCTAssertNotNil(notices.notice(on: file), "another request's Don't send leaves this notice")
        XCTAssertNil(post(&notices, .withdrawing(request: "q")))
        XCTAssertNil(notices.notice(on: file))
    }

    func testALaterAnswerShowsWithItsReasonUnlessANewerSendWaits() {
        var notices = CardNotices()
        let started = post(&notices, .later(request: "q", client: .codex, sessionTitle: "work", state: .sent, reason: "Codex had already started on it."))
        XCTAssertEqual(started?.hold, hold * 3, "a Sent that says why holds as long as a failure")
        XCTAssertEqual(sendState(notices), .sent)

        post(&notices, sending("newer"))
        XCTAssertNil(post(&notices, .later(request: "q", client: .codex, sessionTitle: "work", state: .failed, reason: "Gone.")))
        XCTAssertEqual(sendState(notices), .sending)
        XCTAssertNotNil(post(&notices, .later(request: "newer", client: .codex, sessionTitle: "work", state: .queued, reason: "Why.")))
    }
}
