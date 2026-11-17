import XCTest

/// How a look at the window ends the notes it answers (`NoteCardGroups`): a result card, Done, a
/// reply, and where a late answer goes.
final class NoteCardGroupsEndingTests: XCTestCase, NoteCardGroupsTesting {
    let t0 = Date(timeIntervalSinceReferenceDate: 0)

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

    /// Catches a result card made when nothing changed, which Pete's rule forbids, and a Done on every
    /// note, which brings a lone thumbnail for each note card that is off screen.
    func testNothingChangedMakesNoCardAndOnlyTheNewestNoteSaysDoneAloud() {
        let ids = ["r1", "r2", "r3"]
        var waits = NoteCardGroups()
        sendAll(&waits, ids, to: onWindow(1), delivered: false)
        _ = endAll(&waits, ids)
        XCTAssertEqual(waits.handle(.looked(ids, changed: [], replied: []), at: t0 + 5),
                       each(["r1", "r2"], .sayDoneQuietly) + [.note("r3", .sayDone)])
        XCTAssertEqual(waits.handle(.answer("r2"), at: t0 + 10), [.note("r2", .drawReplyOnSentPicture)])
    }

    /// Catches Pete's case of 2026-11-17: a result card of the Herdr window he was using. Every note
    /// the card would have answered says Done instead, the newest aloud, and keeps its late answer.
    func testAChangeInTheWindowInFrontMakesNoCard() {
        let ids = ["r1", "r2", "r3"]
        var waits = NoteCardGroups()
        sendAll(&waits, ids, to: onWindow(1), delivered: false)
        _ = endAll(&waits, ids)
        XCTAssertEqual(waits.handle(.looked(ids, changed: ["r2"], replied: ["r3"], inFront: true), at: t0 + 5),
                       [.note("r1", .windowInFront), .note("r1", .sayDoneQuietly), .note("r2", .windowInFront), .note("r2", .sayDone),
                        .note("r3", .replyIsTheResult)])
        XCTAssertEqual(waits.handle(.answer("r1"), at: t0 + 10), [.note("r1", .drawReplyOnFreshCapture)])

        var unchanged = NoteCardGroups()
        sendAll(&unchanged, ["a"], to: onWindow(1))
        _ = endAll(&unchanged, ["a"])
        XCTAssertEqual(unchanged.handle(.looked(["a"], changed: [], replied: [], inFront: true), at: t0 + 5), [.note("a", .sayDone)],
                       "nothing changed, so the window's place says nothing")
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

    /// Catches a reply to the only note that changed leaving a card behind, which would show the
    /// window twice: the reply is that note's result.
    func testAReplyToTheOnlyNoteThatChangedMakesNoCard() {
        let ids = ["r1", "r2", "r3"]
        var waits = NoteCardGroups()
        sendAll(&waits, ids, to: onWindow(1))
        _ = endAll(&waits, ids)
        XCTAssertEqual(waits.handle(.looked(ids, changed: ["r1"], replied: ["r1"]), at: t0 + 5),
                       [.note("r1", .replyIsTheResult), .note("r2", .sayDoneQuietly), .note("r3", .sayDone)])
    }

    /// Catches a note whose part of the window could not be compared being answered by a card that
    /// another note made, or making it: its picture is of a window it was not drawn on. It says Done
    /// in place, since the card that comes up is already the turn's news.
    func testANoteWhoseRegionCouldNotBeComparedSaysDoneQuietlyAndIsNotPartOfTheCard() {
        let ids = ["r1", "r2", "r3"]
        var waits = NoteCardGroups()
        sendAll(&waits, ids, to: onWindow(1), delivered: false)
        _ = endAll(&waits, ids)
        XCTAssertEqual(waits.handle(.looked(ids, changed: ["r1", "r3"], replied: [], uncompared: ["r1"]), at: t0 + 5),
                       [.makeResultCard(for: ["r3", "r2"]), .note("r1", .sayDoneQuietly)])
        XCTAssertEqual(waits.handle(.answer("r1"), at: t0 + 10), [.note("r1", .drawReplyOnSentPicture)])
        XCTAssertEqual(waits.handle(.answer("r2"), at: t0 + 10), [.note("r2", .drawReplyOnResultCard)])
    }

    /// Catches a card that cannot be written leaving every note it was to answer with no end: none
    /// says Done and none has a card. Only the newest says it aloud.
    func testWhenTheSharedCardCannotBeWrittenTheNewestNoteItAnsweredSaysDoneAloudAndTheRestInPlace() {
        let ids = ["r1", "r2", "r3"]
        var waits = NoteCardGroups()
        sendAll(&waits, ids, to: onWindow(1), delivered: false)
        _ = endAll(&waits, ids)
        XCTAssertEqual(waits.handle(.looked(ids, changed: ["r2"], replied: ["r1"]), at: t0 + 5),
                       [.makeResultCard(for: ["r2", "r3"]), .note("r1", .replyIsTheResult)])
        XCTAssertEqual(waits.handle(.cardFailed(["r3", "r2"]), at: t0 + 6), [.note("r2", .sayDoneQuietly), .note("r3", .sayDone)])
        XCTAssertEqual(waits.handle(.answer("r3"), at: t0 + 7), [.note("r3", .drawReplyOnSentPicture)])
        XCTAssertEqual(waits.handle(.cardFailed(["r2"]), at: t0 + 8), [], "a note says Done once")
    }

    /// Catches a card that cannot be written for a group of three bringing up three thumbnails.
    func testACardThatCannotBeWrittenForThreeNotesSaysDoneAloudOnce() {
        let ids = ["r1", "r2", "r3"]
        var waits = NoteCardGroups()
        sendAll(&waits, ids, to: onWindow(1))
        _ = endAll(&waits, ids)
        XCTAssertEqual(waits.handle(.looked(ids, changed: ["r1"], replied: []), at: t0 + 5), [.makeResultCard(for: ids)])
        XCTAssertEqual(waits.handle(.cardFailed(["r1", "r2", "r3"]), at: t0 + 6),
                       each(["r1", "r2"], .sayDoneQuietly) + [.note("r3", .sayDone)])
    }

    /// Catches the newest note being the one that could not be compared: the card that is made is
    /// then the turn's news, and no note says Done aloud.
    func testAResizedWindowNoteSaysDoneQuietlyWhateverItsPlaceInTheGroup() {
        let ids = ["r1", "r2", "r3"]
        var waits = NoteCardGroups()
        sendAll(&waits, ids, to: onWindow(1))
        _ = endAll(&waits, ids)
        XCTAssertEqual(waits.handle(.looked(ids, changed: ["r1"], replied: [], uncompared: ["r3"]), at: t0 + 5),
                       [.makeResultCard(for: ["r1", "r2"]), .note("r3", .sayDoneQuietly)])
    }
}
