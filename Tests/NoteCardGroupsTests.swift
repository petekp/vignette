import XCTest

/// Which notes one turn end answers together (`NoteCardGroups`): one look and one card for the notes
/// of one session on one window whose waits end in the same reading.
final class NoteCardGroupsTests: XCTestCase, NoteCardGroupsTesting {
    let t0 = Date(timeIntervalSinceReferenceDate: 0)

    /// Catches a turn that ends during a note's grace period being taken for the answer to the note:
    /// the wait on the session's turn must start when the line goes, not when the note is sent.
    func testAHeldNoteWatchesNoTurnUntilItsLineIsReleased() {
        var waits = NoteCardGroups()
        XCTAssertEqual(waits.handle(.held("r1", onWindow(1), reportsTurns: true, canLookAgain: true), at: t0), [])
        XCTAssertNil(waits["r1"])
        XCTAssertFalse(waits.isWatchingAny)
        XCTAssertEqual(waits.handle(turns(["r1"], .idle), at: t0 + 1), [], "a turn read during the grace is no one's")

        let sent = NoteCardGroups.Input.sent("r1", onWindow(1), reportsTurns: true, canLookAgain: true)
        var immediate = NoteCardGroups()
        let expected = immediate.handle(sent, at: t0 + 2)
        XCTAssertEqual(waits.handle(.released("r1"), at: t0 + 2), expected, "released is a send, from that moment")
        XCTAssertTrue(waits.isWatchingAny)
        XCTAssertEqual(waits.handle(.released("r1"), at: t0 + 3), [], "a line goes once")
    }

    /// Catches a cancelled note still waiting on its session, or a release that follows a cancel
    /// bringing a wait back for a note whose card is gone.
    func testACancelledHeldNoteIsNeverWaitedFor() {
        var waits = NoteCardGroups()
        _ = waits.handle(.held("r1", onWindow(1), reportsTurns: true, canLookAgain: true), at: t0)
        _ = waits.handle(.held("r2", onWindow(1), reportsTurns: true, canLookAgain: true), at: t0)
        XCTAssertEqual(waits.handle(.cancelled("r1"), at: t0 + 1), [])
        XCTAssertEqual(waits.handle(.released("r1"), at: t0 + 3), [])
        XCTAssertNil(waits["r1"])
        XCTAssertFalse(waits.handle(.released("r2"), at: t0 + 3).isEmpty, "the other note's send is its own")
        XCTAssertNotNil(waits["r2"])
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

        var failed = NoteCardGroups()
        sendAll(&failed, ["r"], to: onWindow(1))
        _ = endAll(&failed, ["r"])
        _ = failed.handle(.looked(["r"], changed: ["r"], replied: []), at: t0 + 5)
        XCTAssertEqual(failed.handle(.cardFailed(["r"]), at: t0 + 6), [.note("r", .sayDone)])
    }
}
