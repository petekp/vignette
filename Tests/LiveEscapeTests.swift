import XCTest

final class LiveEscapeTests: XCTestCase {
    private func everything() -> LiveEscape.Snapshot {
        LiveEscape.Snapshot(isOn: true, note: .hasKeys, replyFieldOpen: true, askCanBeCancelled: true, tourRunning: true,
                            answerShown: true, marksShown: true, pointerOnInk: true)
    }

    func testEscBacksOutOneStepAtATimeInOrder() {
        var state = everything()
        XCTAssertEqual(LiveEscape.next(state), .discardNote)
        state.note = .none
        let steps: [(LiveEscape.Step, WritableKeyPath<LiveEscape.Snapshot, Bool>)] = [
            (.closeReplyField, \.replyFieldOpen), (.cancelAsk, \.askCanBeCancelled),
            (.endTour, \.tourRunning), (.closeAnswer, \.answerShown), (.clearInk, \.marksShown),
        ]
        for (step, field) in steps {
            XCTAssertEqual(LiveEscape.next(state), step)
            state[keyPath: field] = false
        }
        XCTAssertNil(LiveEscape.next(state), "with nothing left, Esc is the app's again")
    }

    func testEscIsTheAppsWhileTheNoteIsUpWithoutTheKeys() {
        var state = everything()
        state.note = .withoutKeys
        XCTAssertNil(LiveEscape.next(state))
    }

    func testEscClearsInkAloneAndNothingElse() {
        XCTAssertEqual(LiveEscape.next(LiveEscape.Snapshot(isOn: true, marksShown: true, pointerOnInk: true)), .clearInk)
        XCTAssertNil(LiveEscape.next(LiveEscape.Snapshot(isOn: true, pointerOnInk: true)))
    }

    func testEscPastTheNoteAndReplysFieldIsTheAppsUnlessThePointerIsOnInk() {
        var state = everything()
        state.note = .none
        state.replyFieldOpen = false
        state.pointerOnInk = false
        XCTAssertNil(LiveEscape.next(state), "typing in a terminal with ink up, Esc reaches the terminal")
        XCTAssertTrue(LiveEscape.needsPointer(state))
        state.replyFieldOpen = true
        XCTAssertEqual(LiveEscape.next(state), .closeReplyField)
        XCTAssertFalse(LiveEscape.needsPointer(state))
        state.replyFieldOpen = false
        state.note = .hasKeys
        XCTAssertEqual(LiveEscape.next(state), .discardNote)
        XCTAssertFalse(LiveEscape.needsPointer(state))
    }

    func testEscIsNeverTakenWhileTheStackHoldsTheScreenAMenuIsUpOrLiveInkIsOff() {
        var state = everything()
        state.screenIsFree = false
        XCTAssertNil(LiveEscape.next(state))
        state.screenIsFree = true
        state.menuOpen = true
        XCTAssertNil(LiveEscape.next(state), "the note's menu closes on Esc")
        state.menuOpen = false
        state.isOn = false
        XCTAssertNil(LiveEscape.next(state))
    }

    func testEscDuringTheHoldCancelsItWhateverElseIsUp() {
        var state = everything()
        state.inking = true
        state.pointerOnInk = false
        XCTAssertEqual(LiveEscape.next(state), .cancelHold)
        state.note = .withoutKeys
        XCTAssertEqual(LiveEscape.next(state), .cancelHold, "the early note opened while the chord is held goes with the hold")
        XCTAssertFalse(LiveEscape.needsPointer(state))
        state.menuOpen = true
        XCTAssertNil(LiveEscape.next(state))
    }

    func testRightAfterTheReleaseEscStopsTheNoteOrTheAskWhereverThePointerIs() {
        var state = LiveEscape.Snapshot(isOn: true, justLetGo: true, note: .withoutKeys, askCanBeCancelled: true, tourRunning: true,
                                        answerShown: true, marksShown: true)
        XCTAssertEqual(LiveEscape.next(state), .discardNote, "a note a menu kept the keys from")
        state.note = .none
        XCTAssertEqual(LiveEscape.next(state), .cancelAsk)
        XCTAssertFalse(LiveEscape.needsPointer(state))
        state.askSentOnRelease = true
        XCTAssertEqual(LiveEscape.next(state), .discardAsk)
        state.askCanBeCancelled = false
        XCTAssertNil(LiveEscape.next(state), "the tour, an answer and the ink keep the pointer rule")
        XCTAssertTrue(LiveEscape.needsPointer(state))
        state.pointerOnInk = true
        XCTAssertEqual(LiveEscape.next(state), .endTour)
    }

    func testAnAskSentOnReleaseIsDiscardedOnlyFromTheInk() {
        var state = LiveEscape.Snapshot(isOn: true, askCanBeCancelled: true, askSentOnRelease: true)
        XCTAssertNil(LiveEscape.next(state), "once the person has gone elsewhere, Esc is that app's")
        state.pointerOnInk = true
        XCTAssertEqual(LiveEscape.next(state), .discardAsk)
    }
}
