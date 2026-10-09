import XCTest

/// How a note card's wait ends, in any order of its reply, its turn's end and its delivery.
final class NoteCardWaitTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    /// A note to a session that reports its turns, sent at t0.
    private func claude(window: Bool = true, before: Bool = true) -> NoteCardWait {
        var wait = NoteCardWait(reportsTurns: true, hasWindow: window, canLookAgain: before)
        _ = wait.handle(.sent, at: t0)
        return wait
    }

    private func codex() -> NoteCardWait {
        var wait = NoteCardWait(reportsTurns: false, hasWindow: true, canLookAgain: true)
        _ = wait.handle(.sent, at: t0)
        return wait
    }

    /// Busy, then idle long enough to end, with `replied` on the reading that ends it.
    private func endTurn(_ wait: inout NoteCardWait, replied: Bool = false) -> [NoteCardWait.Effect] {
        XCTAssertEqual(wait.handle(.turn(.busy, replied: false), at: t0 + 0.5), [])
        XCTAssertEqual(wait.handle(.turn(.idle, replied: false), at: t0 + 1), [])
        return wait.handle(.turn(.idle, replied: replied), at: t0 + 3)
    }

    func testANoteToASessionThatReportsTurnsIsWatchedUntilItsTurnEnds() {
        var wait = NoteCardWait(reportsTurns: true, hasWindow: true, canLookAgain: true)
        XCTAssertEqual(wait.handle(.sent, at: t0), [.watchTurn])
        XCTAssertTrue(wait.isWatching)
        XCTAssertEqual(endTurn(&wait), [.turnEnded, .lookAgain])
        XCTAssertFalse(wait.isWatching, "a note looked at again no longer has its turn read")
    }

    func testAChangeUnderTheInkMakesAResultCardAndNoChangeSaysDone() {
        var changed = claude()
        _ = endTurn(&changed)
        XCTAssertEqual(changed.handle(.lookedAgain(changed: true, replied: false), at: t0 + 5), [.makeResultCard])

        var unchanged = claude()
        _ = endTurn(&unchanged)
        XCTAssertEqual(unchanged.handle(.lookedAgain(changed: false, replied: false), at: t0 + 5), [.sayDone])
    }

    func testATurnSeenToEndWithNoBeforePictureSaysDoneAtOnce() {
        var wait = claude(before: false)
        XCTAssertEqual(endTurn(&wait), [.turnEnded, .sayDone])

        var replied = claude(before: false)
        XCTAssertEqual(endTurn(&replied, replied: true), [.turnEnded, .replyIsTheResult])
    }

    func testAnAnswerDuringTheTurnIsDrawnFreshAndTheTurnsEndAddsNoCard() {
        var wait = claude()
        XCTAssertEqual(wait.handle(.answer, at: t0 + 0.2), [.drawReplyOnFreshCapture])
        XCTAssertTrue(wait.isWatching)
        XCTAssertEqual(endTurn(&wait, replied: true), [.turnEnded, .lookAgain], "the look still runs after a reply")
        XCTAssertEqual(wait.handle(.lookedAgain(changed: true, replied: true), at: t0 + 5), [.replyIsTheResult])
    }

    func testStoppingWaitingSaysNothingMoreUnlessTheSessionReplied() {
        var silent = claude()
        XCTAssertEqual(silent.handle(.turn(nil, replied: false), at: t0 + 180.5), [.stopWaiting])

        var replied = claude()
        XCTAssertEqual(replied.handle(.turn(nil, replied: true), at: t0 + 180.5), [.stopWaiting, .replyIsTheResult])
        XCTAssertFalse(replied.isWatching)
    }

    func testAFailedDeliveryEndsTheWaitSilently() {
        var watching = claude()
        XCTAssertEqual(watching.handle(.delivered(failed: true), at: t0 + 1), [])
        XCTAssertFalse(watching.isWatching)
        XCTAssertEqual(watching.handle(.answer, at: t0 + 2), [.drawReplyOnSentPicture])

        var looking = claude()
        _ = endTurn(&looking)
        XCTAssertEqual(looking.handle(.delivered(failed: true), at: t0 + 4), [])
        XCTAssertEqual(looking.handle(.lookedAgain(changed: true, replied: false), at: t0 + 5), [],
                       "no result card and no Done after a send that failed")

        var delivered = claude()
        XCTAssertEqual(delivered.handle(.delivered(failed: false), at: t0 + 1), [])
        XCTAssertTrue(delivered.isWatching)
        XCTAssertEqual(endTurn(&delivered), [.turnEnded, .lookAgain])
    }

    /// Pins today's order: the window is known while it is looked at again, but the answer goes on
    /// the sent picture. Widening the fresh capture to this phase has to be a deliberate edit.
    func testAnAnswerWhileTheWindowIsLookedAtAgainGoesOnTheSentPicture() {
        var wait = claude()
        _ = endTurn(&wait)
        XCTAssertEqual(wait.handle(.answer, at: t0 + 4), [.drawReplyOnSentPicture])
        XCTAssertEqual(wait.handle(.lookedAgain(changed: true, replied: true), at: t0 + 5), [.replyIsTheResult])
    }

    /// Catches an answer that comes after the turn's result card becoming a second card: it goes on
    /// the result card for as long as a turn may run, and on the sent picture after that.
    func testAnAnswerAfterAChangedResultCardGoesOnTheResultCard() {
        var wait = claude()
        XCTAssertEqual(endTurn(&wait), [.turnEnded, .lookAgain])
        XCTAssertEqual(wait.handle(.lookedAgain(changed: true, replied: false), at: t0 + 5), [.makeResultCard])
        XCTAssertEqual(wait.handle(.answer, at: t0 + 10), [.drawReplyOnResultCard])
        XCTAssertEqual(wait.handle(.answer, at: t0 + 20), [.drawReplyOnResultCard])
        _ = wait.handle(.delivered(failed: false), at: t0 + 21)
        XCTAssertFalse(wait.isFinished(at: t0 + 5 + TurnWatch.turnLimit))
        XCTAssertTrue(wait.isFinished(at: t0 + 5 + TurnWatch.turnLimit + 1))
        XCTAssertEqual(wait.handle(.answer, at: t0 + 5 + TurnWatch.turnLimit + 1), [.drawReplyOnSentPicture])
    }

    func testAnAnswerAfterDoneOrForANoteOfNoOneWindowGoesOnTheSentPicture() {
        var done = claude()
        _ = endTurn(&done)
        XCTAssertEqual(done.handle(.lookedAgain(changed: false, replied: false), at: t0 + 5), [.sayDone])
        XCTAssertEqual(done.handle(.answer, at: t0 + 10), [.drawReplyOnSentPicture])

        var nowhere = claude(window: false, before: false)
        XCTAssertTrue(nowhere.isWatching)
        XCTAssertEqual(nowhere.handle(.answer, at: t0 + 1), [.drawReplyOnSentPicture])
    }

    func testACodexNoteStopsWaitingAsItIsSentAndItsAnswerIsDrawnFreshForThreeMinutes() {
        var wait = NoteCardWait(reportsTurns: false, hasWindow: true, canLookAgain: true)
        XCTAssertEqual(wait.handle(.sent, at: t0), [.stopWaiting])
        XCTAssertFalse(wait.isWatching, "a route that reports no turns is not read")
        XCTAssertEqual(wait.handle(.answer, at: t0 + 180), [.drawReplyOnFreshCapture])

        var late = codex()
        XCTAssertEqual(late.handle(.answer, at: t0 + 180.5), [.drawReplyOnSentPicture])
    }

    func testANoteIsForgottenOnlyOnceDeliveredAndOver() {
        var wait = claude(before: false)
        _ = endTurn(&wait)
        XCTAssertFalse(wait.isFinished(at: t0 + 3), "its send notice still needs the note card")
        _ = wait.handle(.delivered(failed: false), at: t0 + 4)
        XCTAssertTrue(wait.isFinished(at: t0 + 4))

        var watched = claude()
        _ = watched.handle(.delivered(failed: false), at: t0 + 1)
        XCTAssertFalse(watched.isFinished(at: t0 + 1))

        var codex = codex()
        _ = codex.handle(.delivered(failed: false), at: t0 + 1)
        XCTAssertFalse(codex.isFinished(at: t0 + 180), "its answer may still be drawn fresh")
        XCTAssertTrue(codex.isFinished(at: t0 + 180.5))
    }

    func testAnyOrderOfEventsEndsTheWaitOnce() {
        let turns: [SessionTurn?] = [.waiting, .busy, .idle, nil]
        let endings: Set<NoteCardWait.Effect> = [.makeResultCard, .sayDone, .replyIsTheResult]
        for seed in 0..<1000 {
            var rng = SeededGenerator(seed: UInt64(seed))
            let window = Bool.random(using: &rng)
            var wait = NoteCardWait(reportsTurns: Bool.random(using: &rng), hasWindow: window, canLookAgain: Bool.random(using: &rng))
            var now = t0
            var trace: [String] = ["reportsTurns=\(wait.reportsTurns) hasWindow=\(window) canLookAgain=\(wait.canLookAgain)"]
            func fail(_ message: String) -> String { "\(message) (seed \(seed))\n" + trace.joined(separator: "\n") }
            var ended = 0, looks = 0, wasOver = false, madeCard = false
            for step in 0..<Int.random(in: 1...60, using: &rng) {
                now += [0.5, 0.5, 1, 2, 30, 200, 1000].randomElement(using: &rng)!
                let event: NoteCardWait.Event
                switch step == 0 ? 0 : Int.random(in: 0...4, using: &rng) {
                case 0: event = .sent
                case 1: event = .delivered(failed: Bool.random(using: &rng))
                case 2: event = .turn(turns.randomElement(using: &rng)!, replied: Bool.random(using: &rng))
                case 3: event = .lookedAgain(changed: Bool.random(using: &rng), replied: Bool.random(using: &rng))
                default: event = .answer
                }
                let effects = wait.handle(event, at: now)
                trace.append("\(now.timeIntervalSince(t0)) \(event) -> \(effects) [\(wait.phase)]")
                ended += effects.filter(endings.contains).count
                looks += effects.filter { $0 == .lookAgain }.count
                if effects.contains(.drawReplyOnResultCard) { XCTAssertTrue(madeCard, fail("no result card to draw on")) }
                madeCard = madeCard || effects.contains(.makeResultCard)
                XCTAssertLessThanOrEqual(ended, 1, fail("a note ends with one result card, Done or reply"))
                XCTAssertLessThanOrEqual(looks, 1, fail("the window is looked at again once"))
                if effects.contains(.watchTurn) { XCTAssertEqual(event, .sent, fail("only a send starts the watch")) }
                if !window { XCTAssertFalse(effects.contains(.drawReplyOnFreshCapture), fail("no window to capture afresh")) }
                if wasOver { XCTAssertTrue(effects.allSatisfy { $0 == .drawReplyOnSentPicture }, fail("nothing more once over")) }
                wasOver = wait.phase == .over
            }
        }
    }
}
