import XCTest

final class SetupInkDemoTests: XCTestCase {
    func testTheSessionsTurnEndsOnlyAfterTheKeysHaveGrown() throws {
        let start = Date()
        var wait = NoteCardWait(reportsTurns: true, hasWindow: true, canLookAgain: false)
        var sent: TimeInterval?
        var ended: TimeInterval?
        var grew: TimeInterval?
        for step in SetupInkDemo.steps {
            let at = start.addingTimeInterval(step.at)
            switch step.beat {
            case .send:
                sent = step.at
                XCTAssertEqual(wait.handle(.sent, at: at), [.watchTurn])
            case .reading(let turn):
                if wait.handle(.turn(turn, replied: false), at: at).contains(.sayDone), ended == nil { ended = step.at }
            case .growKeys:
                grew = step.at
            default:
                break
            }
        }
        let sentAt = try XCTUnwrap(sent), grewAt = try XCTUnwrap(grew), endedAt = try XCTUnwrap(ended)
        XCTAssertGreaterThan(grewAt, sentAt)
        XCTAssertGreaterThanOrEqual(endedAt - grewAt, SetupInkDemo.growing)
        XCTAssertEqual(endedAt - sentAt, 2.6, accuracy: 0.5)
    }

    func testTheHandFinishesEachStrokeBeforeTheNextBegins() {
        var handFreeAt: TimeInterval = 0
        var chordDown = false
        for step in SetupInkDemo.steps {
            switch step.beat {
            case .chord(let down):
                XCTAssertGreaterThanOrEqual(step.at, handFreeAt)
                chordDown = down
            case .write(let index):
                XCTAssertTrue(chordDown)
                XCTAssertGreaterThanOrEqual(step.at, handFreeAt)
                handFreeAt = step.at + SetupInkDemo.writing[index]
            case .circleKeys:
                XCTAssertTrue(chordDown)
                XCTAssertGreaterThanOrEqual(step.at, handFreeAt)
                handFreeAt = step.at + SetupInkDemo.circling
            case .openNote:
                XCTAssertFalse(chordDown)
            default:
                break
            }
        }
    }

    func testTheNoteIsSentWithAllItsWords() {
        let typed = SetupInkDemo.steps.compactMap { step -> String? in
            if case .type(let words) = step.beat { return words }
            return nil
        }
        let sent = SetupInkDemo.steps.firstIndex { $0.beat == .send }
        let lastTyped = SetupInkDemo.steps.lastIndex { if case .type = $0.beat { true } else { false } }
        XCTAssertEqual(typed.last, SetupInkDemo.words)
        XCTAssertLessThan(lastTyped ?? .max, sent ?? .min)
    }

    func testAHandSlowsWhereTheLineTurns() {
        let hand = HandStroke(through: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)], duration: 1)
        let gaps = zip(hand.points, hand.points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        let corner = hand.points.indices.dropLast().min { hypot(hand.points[$0].x - 100, hand.points[$0].y) < hypot(hand.points[$1].x - 100, hand.points[$1].y) }!
        XCTAssertLessThan(gaps[corner], gaps[gaps.count / 4])
        XCTAssertEqual(hand.duration, 1, accuracy: 0.001)
        XCTAssertEqual(hand.points.last!.x, 100, accuracy: 0.5)
        XCTAssertEqual(hand.points.last!.y, 100, accuracy: 0.5)
    }
}
