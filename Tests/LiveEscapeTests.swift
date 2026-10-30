import XCTest

final class LiveEscapeTests: XCTestCase {
    private func everything() -> LiveEscape.Snapshot {
        LiveEscape.Snapshot(isOn: true, note: .hasKeys, replyFieldOpen: true, askCanBeCancelled: true, tourRunning: true,
                            answerShown: true, marksShown: true)
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
        XCTAssertEqual(LiveEscape.next(LiveEscape.Snapshot(isOn: true, marksShown: true)), .clearInk)
        XCTAssertNil(LiveEscape.next(LiveEscape.Snapshot(isOn: true)))
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
}
