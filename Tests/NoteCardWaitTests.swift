import XCTest

/// How a note card's wait ends, in any order of its reply, its turn's end and its delivery
/// (`NoteCardWait`), and how the waits of the notes one turn end answers end together (`NoteCardGroups`).
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

    /// Catches a note answered by a result card, its own or another note's, saying Done as well, or
    /// losing the late answers that go on that card.
    func testACardMadeAnswersTheNoteAndNoCardSaysDone() {
        var answered = claude()
        _ = endTurn(&answered)
        XCTAssertEqual(answered.handle(.lookedAgain(.cardMade), at: t0 + 5), [])
        XCTAssertEqual(answered.handle(.answer, at: t0 + 10), [.drawReplyOnResultCard])
        _ = answered.handle(.delivered(failed: false), at: t0 + 11)
        XCTAssertFalse(answered.isFinished(at: t0 + 5 + TurnWatch.turnLimit))
        XCTAssertTrue(answered.isFinished(at: t0 + 5 + TurnWatch.turnLimit + 1))

        var unanswered = claude()
        _ = endTurn(&unanswered)
        XCTAssertEqual(unanswered.handle(.lookedAgain(.noCard), at: t0 + 5), [.sayDone])
    }

    /// Catches a note left with no end state when the card that answered it could not be written.
    func testACardThatCannotBeWrittenLeavesTheNoteSayingDone() {
        var wait = claude()
        _ = endTurn(&wait)
        XCTAssertEqual(wait.handle(.lookedAgain(.cardMade), at: t0 + 5), [])
        XCTAssertEqual(wait.handle(.cardFailed, at: t0 + 6), [.sayDone])
        XCTAssertEqual(wait.handle(.answer, at: t0 + 7), [.drawReplyOnSentPicture], "there is no card to draw on")
        XCTAssertEqual(wait.handle(.cardFailed, at: t0 + 8), [], "a note says Done once")
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
        XCTAssertEqual(wait.handle(.lookedAgain(.replied), at: t0 + 5), [.replyIsTheResult])
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
        XCTAssertEqual(looking.handle(.lookedAgain(.cardMade), at: t0 + 5), [])
        XCTAssertEqual(looking.handle(.answer, at: t0 + 6), [.drawReplyOnSentPicture], "a send that failed has no card to answer")

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
        XCTAssertEqual(wait.handle(.lookedAgain(.replied), at: t0 + 5), [.replyIsTheResult])
    }

    /// Catches an answer that comes after the turn's result card becoming a second card: it goes on
    /// the result card for as long as a turn may run, and on the sent picture after that.
    func testAnAnswerAfterAChangedResultCardGoesOnTheResultCard() {
        var wait = claude()
        XCTAssertEqual(endTurn(&wait), [.turnEnded, .lookAgain])
        XCTAssertEqual(wait.handle(.lookedAgain(.cardMade), at: t0 + 5), [])
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
        XCTAssertEqual(done.handle(.lookedAgain(.noCard), at: t0 + 5), [.sayDone])
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
        let endings: Set<NoteCardWait.Effect> = [.sayDone, .replyIsTheResult]
        for seed in 0..<1000 {
            var rng = SeededGenerator(seed: UInt64(seed))
            let window = Bool.random(using: &rng)
            var wait = NoteCardWait(reportsTurns: Bool.random(using: &rng), hasWindow: window, canLookAgain: Bool.random(using: &rng))
            var now = t0
            var trace: [String] = ["reportsTurns=\(wait.reportsTurns) hasWindow=\(window) canLookAgain=\(wait.canLookAgain)"]
            func fail(_ message: String) -> String { "\(message) (seed \(seed))\n" + trace.joined(separator: "\n") }
            var ended = 0, looks = 0, wasOver = false, madeCard = false
            let looksAt: [NoteCardWait.LookOutcome] = [.replied, .cardMade, .noCard]
            for step in 0..<Int.random(in: 1...60, using: &rng) {
                now += [0.5, 0.5, 1, 2, 30, 200, 1000].randomElement(using: &rng)!
                let event: NoteCardWait.Event
                switch step == 0 ? 0 : Int.random(in: 0...5, using: &rng) {
                case 0: event = .sent
                case 1: event = .delivered(failed: Bool.random(using: &rng))
                case 2: event = .turn(turns.randomElement(using: &rng)!, replied: Bool.random(using: &rng))
                case 3: event = .lookedAgain(looksAt.randomElement(using: &rng)!)
                case 4: event = .cardFailed
                default: event = .answer
                }
                let effects = wait.handle(event, at: now)
                trace.append("\(now.timeIntervalSince(t0)) \(event) -> \(effects) [\(wait.phase)]")
                ended += effects.filter(endings.contains).count
                looks += effects.filter { $0 == .lookAgain }.count
                if effects.contains(.drawReplyOnResultCard) { XCTAssertTrue(madeCard, fail("no result card to draw on")) }
                if event == .cardFailed, effects == [.sayDone] {
                    // The card never stood, so the note ends once, with Done.
                    ended -= 1
                    madeCard = false
                }
                if case .resultCard = wait.phase {
                    if !madeCard { ended += 1 }
                    madeCard = true
                }
                XCTAssertLessThanOrEqual(ended, 1, fail("a note ends with one result card, Done or reply"))
                XCTAssertLessThanOrEqual(looks, 1, fail("the window is looked at again once"))
                if effects.contains(.watchTurn) { XCTAssertEqual(event, .sent, fail("only a send starts the watch")) }
                if !window { XCTAssertFalse(effects.contains(.drawReplyOnFreshCapture), fail("no window to capture afresh")) }
                if wasOver { XCTAssertTrue(effects.allSatisfy { $0 == .drawReplyOnSentPicture }, fail("nothing more once over")) }
                wasOver = wait.phase == .over
            }
        }
    }

    // MARK: A turn end that answers several notes

    private func onWindow(_ window: CGWindowID, session: String = "s1") -> NoteCardGroups.SessionWindow {
        NoteCardGroups.SessionWindow(session: session, window: window)
    }

    /// `ids` sent to `window` at t0, in that order, and delivered unless `delivered` is false.
    private func sendAll(_ waits: inout NoteCardGroups, _ ids: [String], to window: NoteCardGroups.SessionWindow, delivered: Bool = true) {
        for id in ids {
            _ = waits.handle(.sent(id, window, reportsTurns: true, canLookAgain: true), at: t0)
            if delivered { _ = waits.handle(.delivered(id, failed: false), at: t0) }
        }
    }

    private func each(_ ids: [String], _ effect: NoteCardWait.Effect) -> [NoteCardGroups.Action] {
        ids.map { .note($0, effect) }
    }

    /// One reading of the session's turn, the same for every id.
    private func turns(_ ids: [String], _ turn: SessionTurn) -> NoteCardGroups.Input {
        .turns(ids.map { NoteCardGroups.Reading(request: $0, turn: turn, replied: false) })
    }

    /// One reading of busy, then two of idle long enough to end the turn, for every id. Answers the
    /// reading that ends it.
    private func endAll(_ waits: inout NoteCardGroups, _ ids: [String]) -> [NoteCardGroups.Action] {
        XCTAssertEqual(waits.handle(turns(ids, .busy), at: t0 + 0.5), [])
        XCTAssertEqual(waits.handle(turns(ids, .idle), at: t0 + 1), [])
        return waits.handle(turns(ids, .idle), at: t0 + 3)
    }

    /// Catches Pete's bug of 2026-10-09: seven notes answered by one turn end made seven result cards.
    func testSevenNotesEndedByOneReadingShareOneLookAndOneResultCard() {
        let ids = (1...7).map { "r\($0)" }
        var waits = NoteCardGroups()
        sendAll(&waits, ids, to: onWindow(1))
        let ended = endAll(&waits, ids)
        XCTAssertEqual(ended, each(ids, .turnEnded) + [.look(ids)])
        XCTAssertFalse(waits.isWatchingAny)

        XCTAssertEqual(waits.handle(.looked(ids, changed: Set(ids), replied: []), at: t0 + 5), [.makeResultCard(for: ids)])
    }

    /// Catches the notes the card answers saying Done as well, which brings a lone thumbnail for
    /// each one whose card is off screen, or a card for each note that changed.
    func testOneChangedNoteMakesTheCardAndAnswersTheOthersWithoutDone() {
        let ids = ["r1", "r2", "r3"]
        var waits = NoteCardGroups()
        sendAll(&waits, ids, to: onWindow(1))
        _ = endAll(&waits, ids)
        XCTAssertEqual(waits.handle(.looked(ids, changed: ["r2"], replied: []), at: t0 + 5),
                       [.makeResultCard(for: ["r2", "r1", "r3"])])
    }

    /// Catches the lists following the order an input names requests in. The send order is c, a, b,
    /// which the ids' own order does not match, so the first note to change is c, not a.
    func testRequestsListedInAnyOrderAreAnsweredInSendOrder() {
        var waits = NoteCardGroups()
        sendAll(&waits, ["c", "a", "b"], to: onWindow(1))
        XCTAssertEqual(endAll(&waits, ["b", "c", "a"]), each(["c", "a", "b"], .turnEnded) + [.look(["c", "a", "b"])])
        XCTAssertEqual(waits.handle(.looked(["b", "a", "c"], changed: ["a", "c"], replied: []), at: t0 + 5),
                       [.makeResultCard(for: ["c", "a", "b"])])
    }

    /// Catches a grouped note's late answer going on the sent picture, or making a second card.
    func testALateAnswerForTheThirdNoteLandsOnTheSharedCard() {
        let ids = ["r1", "r2", "r3"]
        var waits = NoteCardGroups()
        sendAll(&waits, ids, to: onWindow(1), delivered: false)
        _ = endAll(&waits, ids)
        _ = waits.handle(.looked(ids, changed: ["r2"], replied: []), at: t0 + 5)
        for (n, id) in ["r3", "r1", "r2"].enumerated() {
            XCTAssertEqual(waits.handle(.answer(id), at: t0 + 10 + Double(n)), [.note(id, .drawReplyOnResultCard)])
        }

        for id in ids { _ = waits.handle(.delivered(id, failed: false), at: t0 + 20) }
        XCTAssertEqual(waits.handle(.answer("r1"), at: t0 + 5 + TurnWatch.turnLimit + 1), [.note("r1", .drawReplyOnSentPicture)])
        for id in ids { XCTAssertNil(waits[id], "\(id) is let go once no answer can still come") }
    }

    /// Catches a result card made when nothing changed, which Pete's rule forbids.
    func testNothingChangedSaysDoneOnEveryNoteAndMakesNoCard() {
        let ids = ["r1", "r2", "r3"]
        var waits = NoteCardGroups()
        sendAll(&waits, ids, to: onWindow(1), delivered: false)
        _ = endAll(&waits, ids)
        XCTAssertEqual(waits.handle(.looked(ids, changed: [], replied: []), at: t0 + 5), each(ids, .sayDone))
        XCTAssertEqual(waits.handle(.answer("r2"), at: t0 + 10), [.note("r2", .drawReplyOnSentPicture)])
    }

    /// Catches grouping by the session alone, or by the window alone.
    func testNotesOnTwoWindowsOrTwoSessionsGetTheirOwnLookAndCard() {
        func ended(_ waits: inout NoteCardGroups) -> [NoteCardGroups.Action] {
            sendAll(&waits, ["a1", "a2"], to: onWindow(1))
            sendAll(&waits, ["b1"], to: onWindow(2))
            return endAll(&waits, ["a1", "a2", "b1"]).filter { if case .look = $0 { return true } else { return false } }
        }

        var oneChanged = NoteCardGroups()
        XCTAssertEqual(ended(&oneChanged), [.look(["a1", "a2"]), .look(["b1"])])
        XCTAssertEqual(oneChanged.handle(.looked(["a1", "a2"], changed: ["a1", "a2"], replied: []), at: t0 + 5), [.makeResultCard(for: ["a1", "a2"])])
        XCTAssertEqual(oneChanged.handle(.looked(["b1"], changed: [], replied: []), at: t0 + 5), [.note("b1", .sayDone)])

        var twoCards = NoteCardGroups()
        _ = ended(&twoCards)
        XCTAssertEqual(twoCards.handle(.looked(["a1", "a2"], changed: ["a2"], replied: []), at: t0 + 5), [.makeResultCard(for: ["a2", "a1"])])
        XCTAssertEqual(twoCards.handle(.looked(["b1"], changed: ["b1"], replied: []), at: t0 + 5), [.makeResultCard(for: ["b1"])])

        var sessions = NoteCardGroups()
        sendAll(&sessions, ["x1"], to: onWindow(1, session: "s1"))
        sendAll(&sessions, ["y1"], to: onWindow(1, session: "s2"))
        let looks = endAll(&sessions, ["x1", "y1"])
        XCTAssertTrue(looks.contains(.look(["x1"])) && looks.contains(.look(["y1"])))
    }

    /// Catches a reply making a duplicate card: the reply is that note's own result.
    func testAReplyIsItsOwnResultAndNeverPartOfTheCard() {
        let ids = ["r1", "r2", "r3"]
        var waits = NoteCardGroups()
        sendAll(&waits, ids, to: onWindow(1), delivered: false)
        _ = endAll(&waits, ids)
        XCTAssertEqual(waits.handle(.looked(ids, changed: Set(ids), replied: ["r1"]), at: t0 + 5),
                       [.makeResultCard(for: ["r2", "r3"]), .note("r1", .replyIsTheResult)])
        XCTAssertEqual(waits.handle(.answer("r1"), at: t0 + 10), [.note("r1", .drawReplyOnSentPicture)])

        var allReplied = NoteCardGroups()
        sendAll(&allReplied, ids, to: onWindow(1))
        _ = endAll(&allReplied, ids)
        XCTAssertEqual(allReplied.handle(.looked(ids, changed: Set(ids), replied: Set(ids)), at: t0 + 5),
                       each(ids, .replyIsTheResult))
    }

    /// Catches a note whose send failed during the look still being counted in the card, or making it.
    func testANoteWhoseSendFailedDuringTheLookIsLeftOut() {
        let ids = ["r1", "r2", "r3"]
        var waits = NoteCardGroups()
        sendAll(&waits, ids, to: onWindow(1), delivered: false)
        _ = endAll(&waits, ids)
        XCTAssertEqual(waits.handle(.delivered("r1", failed: true), at: t0 + 4), [])
        XCTAssertEqual(waits.handle(.looked(ids, changed: ["r1", "r2"], replied: []), at: t0 + 5),
                       [.makeResultCard(for: ["r2", "r3"])])
    }

    /// Catches notes sent minutes apart, before the session took any of them, ending in separate
    /// groups, which is how seven notes made seven cards.
    func testNotesSentMinutesApartEndInOneGroupWhenTheSessionEndsOneTurn() {
        let ids = ["r1", "r2", "r3"]
        var waits = NoteCardGroups()
        for (n, id) in ids.enumerated() {
            let sent = t0 + Double(n) * 60
            _ = waits.handle(.sent(id, onWindow(1), reportsTurns: true, canLookAgain: true), at: sent)
            _ = waits.handle(.delivered(id, failed: false), at: sent + 1)
        }
        // The session is busy with another turn, so all three requests wait in its inbox.
        XCTAssertEqual(waits.handle(turns(ids, .waiting), at: t0 + 130), [])
        XCTAssertEqual(waits.handle(turns(ids, .busy), at: t0 + 140), [])
        XCTAssertEqual(waits.handle(turns(ids, .idle), at: t0 + 141), [])
        XCTAssertEqual(waits.handle(turns(ids, .idle), at: t0 + 143), each(ids, .turnEnded) + [.look(ids)])
        XCTAssertEqual(waits.handle(.looked(ids, changed: Set(ids), replied: []), at: t0 + 145), [.makeResultCard(for: ids)])
    }

    /// Catches a note sent while the session runs a turn ending apart from the notes sent before
    /// it: the session reads waiting until it takes the new request, for every note.
    func testANoteSentWhileTheSessionIsBusyEndsWithTheOthers() {
        let ids = ["r1", "r2", "r3"]
        var waits = NoteCardGroups()
        sendAll(&waits, ["r1", "r2"], to: onWindow(1))
        XCTAssertEqual(waits.handle(turns(["r1", "r2"], .busy), at: t0 + 5), [])
        _ = waits.handle(.sent("r3", onWindow(1), reportsTurns: true, canLookAgain: true), at: t0 + 20)
        _ = waits.handle(.delivered("r3", failed: false), at: t0 + 20)
        XCTAssertEqual(waits.handle(turns(ids, .waiting), at: t0 + 21), [])
        XCTAssertEqual(waits.handle(turns(ids, .busy), at: t0 + 30), [])
        XCTAssertEqual(waits.handle(turns(ids, .idle), at: t0 + 31), [])
        XCTAssertEqual(waits.handle(turns(ids, .idle), at: t0 + 33), each(ids, .turnEnded) + [.look(ids)])
    }

    /// Catches a note of a later turn on the same window being counted into the card of an earlier
    /// one, or left without a card of its own.
    func testANoteOfALaterTurnOnTheSameWindowGetsItsOwnLookAndCard() {
        var waits = NoteCardGroups()
        sendAll(&waits, ["r1"], to: onWindow(1))
        XCTAssertEqual(endAll(&waits, ["r1"]), [.note("r1", .turnEnded), .look(["r1"])])
        XCTAssertEqual(waits.handle(.looked(["r1"], changed: ["r1"], replied: []), at: t0 + 5), [.makeResultCard(for: ["r1"])])

        _ = waits.handle(.sent("r2", onWindow(1), reportsTurns: true, canLookAgain: true), at: t0 + 10)
        _ = waits.handle(.delivered("r2", failed: false), at: t0 + 10)
        XCTAssertEqual(waits.handle(turns(["r2"], .waiting), at: t0 + 11), [])
        XCTAssertEqual(waits.handle(turns(["r2"], .busy), at: t0 + 12), [])
        XCTAssertEqual(waits.handle(turns(["r2"], .idle), at: t0 + 13), [])
        XCTAssertEqual(waits.handle(turns(["r2"], .idle), at: t0 + 15), [.note("r2", .turnEnded), .look(["r2"])])
        XCTAssertEqual(waits.handle(.looked(["r2"], changed: ["r2"], replied: []), at: t0 + 17), [.makeResultCard(for: ["r2"])])
    }

    /// Catches a Codex note, which no turn reading reaches, being pulled into a Claude note's look,
    /// or losing its fresh capture.
    func testANoteToASessionThatReportsNoTurnsIsNotInTheLookOfItsWindow() {
        var waits = NoteCardGroups()
        XCTAssertEqual(waits.handle(.sent("x", onWindow(1), reportsTurns: false, canLookAgain: true), at: t0), [.note("x", .stopWaiting)])
        sendAll(&waits, ["y"], to: onWindow(1))
        _ = waits.handle(.delivered("x", failed: false), at: t0)
        XCTAssertEqual(endAll(&waits, ["x", "y"]), [.note("y", .turnEnded), .look(["y"])])
        XCTAssertEqual(waits.handle(.looked(["y"], changed: ["y"], replied: []), at: t0 + 5), [.makeResultCard(for: ["y"])])
        XCTAssertEqual(waits.handle(.answer("x"), at: t0 + 10), [.note("x", .drawReplyOnFreshCapture)])
    }

    /// Catches a reply to the only note that changed leaving a card behind, which would show the
    /// window twice: the reply is that note's result.
    func testAReplyToTheOnlyNoteThatChangedMakesNoCard() {
        let ids = ["r1", "r2", "r3"]
        var waits = NoteCardGroups()
        sendAll(&waits, ids, to: onWindow(1))
        _ = endAll(&waits, ids)
        XCTAssertEqual(waits.handle(.looked(ids, changed: ["r1"], replied: ["r1"]), at: t0 + 5),
                       [.note("r1", .replyIsTheResult), .note("r2", .sayDone), .note("r3", .sayDone)])
    }

    /// Catches a note whose part of the window could not be compared being answered by a card that
    /// another note made, or making it: its picture is of a window it was not drawn on.
    func testANoteWhoseRegionCouldNotBeComparedSaysDoneAndIsNotPartOfTheCard() {
        let ids = ["r1", "r2", "r3"]
        var waits = NoteCardGroups()
        sendAll(&waits, ids, to: onWindow(1), delivered: false)
        _ = endAll(&waits, ids)
        XCTAssertEqual(waits.handle(.looked(ids, changed: ["r1", "r3"], replied: [], uncompared: ["r1"]), at: t0 + 5),
                       [.makeResultCard(for: ["r3", "r2"]), .note("r1", .sayDone)])
        XCTAssertEqual(waits.handle(.answer("r1"), at: t0 + 10), [.note("r1", .drawReplyOnSentPicture)])
        XCTAssertEqual(waits.handle(.answer("r2"), at: t0 + 10), [.note("r2", .drawReplyOnResultCard)])
    }

    /// Catches a card that cannot be written leaving every note it was to answer with no end: none
    /// says Done and none has a card.
    func testWhenTheSharedCardCannotBeWrittenEveryNoteItAnsweredSaysDone() {
        let ids = ["r1", "r2", "r3"]
        var waits = NoteCardGroups()
        sendAll(&waits, ids, to: onWindow(1), delivered: false)
        _ = endAll(&waits, ids)
        XCTAssertEqual(waits.handle(.looked(ids, changed: ["r2"], replied: ["r1"]), at: t0 + 5),
                       [.makeResultCard(for: ["r2", "r3"]), .note("r1", .replyIsTheResult)])
        XCTAssertEqual(waits.handle(.cardFailed(["r3", "r2"]), at: t0 + 6), [.note("r2", .sayDone), .note("r3", .sayDone)])
        XCTAssertEqual(waits.handle(.answer("r3"), at: t0 + 7), [.note("r3", .drawReplyOnSentPicture)])
        XCTAssertEqual(waits.handle(.cardFailed(["r2"]), at: t0 + 8), [], "a note says Done once")
    }

    /// Catches the group path changing what one note does.
    func testASingleNoteBehavesAsBefore() {
        var changed = NoteCardGroups()
        sendAll(&changed, ["r"], to: onWindow(1))
        XCTAssertEqual(endAll(&changed, ["r"]), [.note("r", .turnEnded), .look(["r"])])
        XCTAssertEqual(changed.handle(.looked(["r"], changed: ["r"], replied: []), at: t0 + 5), [.makeResultCard(for: ["r"])])

        var unchanged = NoteCardGroups()
        sendAll(&unchanged, ["r"], to: onWindow(1))
        _ = endAll(&unchanged, ["r"])
        XCTAssertEqual(unchanged.handle(.looked(["r"], changed: [], replied: []), at: t0 + 5), [.note("r", .sayDone)])
    }

    /// Catches a group that makes two cards from one look, a card when no note that may be answered
    /// changed or none when one did, the first note to change not making it, a card with no note
    /// behind a late answer, a note that a card answers saying Done while the card stands, or a note
    /// ending twice, whatever order the events come in.
    func testAnyOrderOfGroupEventsMakesAtMostOneCardPerLook() {
        let turns: [SessionTurn?] = [.busy, .busy, .idle, .idle, .idle, .idle, .idle, .waiting, nil]
        // A session mostly runs a turn through: its request waits, the turn runs, then it is idle.
        let script: [SessionTurn] = [.waiting, .busy, .busy, .idle, .idle, .idle]
        var seedsWithGroupedCard = 0
        for seed in 0..<1000 {
            var rng = SeededGenerator(seed: UInt64(seed))
            var waits = NoteCardGroups()
            let ids = (1...Int.random(in: 1...6, using: &rng)).map { "r\($0)" }
            var windows: [String: NoteCardGroups.SessionWindow] = [:]
            var trace: [String] = []
            func fail(_ message: String) -> String { "\(message) (seed \(seed))\n" + trace.joined(separator: "\n") }
            func sendOrder(_ group: [String]) -> [String] { group.sorted { ids.firstIndex(of: $0)! < ids.firstIndex(of: $1)! } }
            var now = t0
            var looks: [[String]] = []
            var answered = Set<Int>()
            var lookedRequests = Set<String>()
            var cardOf: [String: Int] = [:]
            var cursor: [String: Int] = [:]
            var cardsMade: [[String]] = []
            var failedCards = Set<Int>()
            var cards = 0, groupedHere = false
            var replies: [String: Int] = [:], dones: [String: Int] = [:]

            func run(_ input: NoteCardGroups.Input, changed: Set<String> = [], look: Int? = nil) {
                // What a look must answer: the notes still looking that the session has not replied to.
                var expected: (members: Set<String>, maker: String?)?
                var skipped = Set<String>()
                if case .looked(let group, let changed, let replied, let uncompared) = input {
                    let members = sendOrder(group).filter { waits[$0]?.isLookingAgain == true && !replied.contains($0) && !uncompared.contains($0) }
                    expected = (Set(members), members.first { changed.contains($0) })
                    skipped = uncompared
                }
                let actions = waits.handle(input, at: now)
                trace.append("\(now.timeIntervalSince(t0)) \(input) -> \(actions)")
                if let look, !answered.insert(look).inserted { XCTAssertEqual(actions, [], fail("a look is answered once")) }
                var made: [[String]] = []
                var doneNow = 0
                for action in actions {
                    switch action {
                    case .watchTurn:
                        break
                    case .note(let id, let effect):
                        XCTAssertFalse([.watchTurn, .lookAgain].contains(effect), fail("a wish is merged"))
                        if effect == .replyIsTheResult { replies[id, default: 0] += 1 }
                        if effect == .sayDone {
                            dones[id, default: 0] += 1
                            if !skipped.contains(id) { doneNow += 1 }
                            XCTAssertFalse(changed.contains(id), fail("a note whose region changed says nothing more"))
                        }
                        if effect == .drawReplyOnResultCard { XCTAssertNotNil(cardOf[id], fail("no card to draw on")) }
                    case .look(let group):
                        XCTAssertEqual(group, sendOrder(group), fail("a look is in send order"))
                        XCTAssertEqual(Set(group.compactMap { windows[$0] }).count, 1, fail("a look is of one window"))
                        for id in group { XCTAssertTrue(lookedRequests.insert(id).inserted, fail("\(id) is looked at once")) }
                        looks.append(group)
                    case .makeResultCard(let group):
                        made.append(group)
                        XCTAssertEqual(Set(group.compactMap { windows[$0] }).count, 1, fail("a card is of one window"))
                        XCTAssertEqual(Array(group.dropFirst()), sendOrder(Array(group.dropFirst())), fail("a card lists its notes in send order"))
                        for id in group {
                            XCTAssertNil(cardOf[id], fail("\(id) is in one card"))
                            cardOf[id] = cards
                        }
                        cardsMade.append(group)
                        cards += 1
                        if group.count > 1 { groupedHere = true }
                    }
                }
                XCTAssertLessThanOrEqual(made.count, 1, fail("a look makes at most one card"))
                if let expected {
                    XCTAssertEqual(made.first?.first, expected.maker, fail("the first note to change makes the card, and none changed otherwise"))
                    XCTAssertEqual(Set(made.first ?? []), expected.maker == nil ? [] : expected.members, fail("the card answers every note not replied to"))
                }
                if !made.isEmpty { XCTAssertEqual(doneNow, 0, fail("a note a card answers says no Done")) }
                for id in ids {
                    XCTAssertLessThanOrEqual(replies[id, default: 0] + dones[id, default: 0], 1, fail("\(id) ends once"))
                    if replies[id] != nil { XCTAssertNil(cardOf[id], fail("a reply is not part of a card")) }
                    if dones[id] != nil, let card = cardOf[id] { XCTAssertTrue(failedCards.contains(card), fail("\(id) says Done while its card stands")) }
                }
            }

            for id in ids {
                // Most notes share a place, since only they can be answered by one card.
                let window = onWindow(Int.random(in: 0..<4, using: &rng) == 0 ? 2 : 1, session: Int.random(in: 0..<4, using: &rng) == 0 ? "s2" : "s1")
                windows[id] = window
                run(.sent(id, window, reportsTurns: Int.random(in: 0..<5, using: &rng) > 0, canLookAgain: Int.random(in: 0..<7, using: &rng) > 0))
            }
            for _ in 0..<Int.random(in: 1...60, using: &rng) {
                // Mostly short steps, as the tick's, so waits last long enough to end together; now and then a long one.
                now += [0.5, 0.5, 0.5, 0.5, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 5, 5, 5, 30, 1000].randomElement(using: &rng)!
                switch Int.random(in: 0...9, using: &rng) {
                case 0:
                    run(.delivered(ids.randomElement(using: &rng)!, failed: Int.random(in: 0..<8, using: &rng) == 0))
                case 1, 2, 3, 4:
                    // A session's turn is read once, so its notes on every window get the same reading.
                    var turnAt: [String: SessionTurn?] = [:]
                    var readings: [NoteCardGroups.Reading] = []
                    for id in ids where Int.random(in: 0..<12, using: &rng) > 0 {
                        let session = windows[id]!.session
                        if turnAt[session] == nil {
                            if Int.random(in: 0..<8, using: &rng) == 0 {
                                turnAt[session] = .some(turns.randomElement(using: &rng)!)
                            } else {
                                turnAt[session] = .some(script[cursor[session, default: 0] % script.count])
                                cursor[session, default: 0] += 1
                            }
                        }
                        readings.append(NoteCardGroups.Reading(request: id, turn: turnAt[session]!, replied: Int.random(in: 0..<15, using: &rng) == 0))
                    }
                    run(.turns(readings.shuffled(using: &rng)))
                case 5, 6:
                    guard let index = looks.indices.randomElement(using: &rng) else { continue }
                    let group = looks[index]
                    let changed = Set(group.filter { _ in Bool.random(using: &rng) })
                    let replied = Set(group.filter { _ in Int.random(in: 0..<5, using: &rng) == 0 })
                    let uncompared = Set(group.filter { !changed.contains($0) && Int.random(in: 0..<6, using: &rng) == 0 })
                    run(.looked(group.shuffled(using: &rng), changed: changed, replied: replied, uncompared: uncompared),
                        changed: changed, look: index)
                case 7:
                    guard let index = cardsMade.indices.randomElement(using: &rng) else { continue }
                    failedCards.insert(index)
                    run(.cardFailed(cardsMade[index].shuffled(using: &rng)))
                default:
                    run(.answer(ids.randomElement(using: &rng)!))
                }
            }
            if groupedHere { seedsWithGroupedCard += 1 }
        }
        XCTAssertGreaterThan(seedsWithGroupedCard, 80, "the mix no longer reaches cards that answer several notes: retune the generator, not the reducer")
    }
}
