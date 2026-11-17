import XCTest

protocol NoteCardGroupsTesting: XCTestCase {
    var t0: Date { get }
}

extension NoteCardGroupsTesting {
    func onWindow(_ window: CGWindowID, session: String = "s1") -> NoteCardGroups.SessionWindow {
        NoteCardGroups.SessionWindow(session: session, window: window)
    }

    /// `ids` sent to `window` at t0, in that order, and delivered unless `delivered` is false.
    func sendAll(_ waits: inout NoteCardGroups, _ ids: [String], to window: NoteCardGroups.SessionWindow, delivered: Bool = true) {
        for id in ids {
            _ = waits.handle(.sent(id, window, reportsTurns: true, canLookAgain: true), at: t0)
            if delivered { _ = waits.handle(.delivered(id, failed: false), at: t0) }
        }
    }

    func each(_ ids: [String], _ effect: NoteCardWait.Effect) -> [NoteCardGroups.Action] {
        ids.map { .note($0, effect) }
    }

    /// One reading of the session's turn, the same for every id.
    func turns(_ ids: [String], _ turn: SessionTurn) -> NoteCardGroups.Input {
        .turns(ids.map { NoteCardGroups.Reading(request: $0, turn: turn, replied: false) })
    }

    /// One reading of busy, then two of idle long enough to end the turn, for every id. Answers the
    /// reading that ends it.
    func endAll(_ waits: inout NoteCardGroups, _ ids: [String]) -> [NoteCardGroups.Action] {
        XCTAssertEqual(waits.handle(turns(ids, .busy), at: t0 + 0.5), [])
        XCTAssertEqual(waits.handle(turns(ids, .idle), at: t0 + 1), [])
        return waits.handle(turns(ids, .idle), at: t0 + 3)
    }
}
