import XCTest

final class StackSwipeTests: XCTestCase {
    private let rules = StackSwipe.Rules(distance: 70, speed: 500, stretch: 40, returnDuration: 0.25, exitDuration: 0.15)

    private struct Fingers {
        var swipe = StackSwipe()
        var time: TimeInterval = 100
        let rules: StackSwipe.Rules
        var swipes = true

        @discardableResult
        mutating func send(_ phase: StackSwipe.Scroll.Phase, dx: CGFloat = 0, dy: CGFloat = 0, momentum: Bool = false, after: TimeInterval = 0.01) -> StackSwipe.Answer {
            time += after
            let event = StackSwipe.Scroll(phase: phase, momentum: momentum, dx: dx, dy: dy, time: time)
            return swipe.scroll(event, swipes: swipes, rules: rules, now: time)
        }

        mutating func drag(dx: CGFloat, dy: CGFloat = 0, steps: Int, every interval: TimeInterval = 0.01) {
            send(.began, after: interval)
            for _ in 0..<steps { send(.changed, dx: dx, dy: dy, after: interval) }
        }

        mutating func settle(for seconds: TimeInterval = 2) {
            let end = time + seconds
            while time < end {
                time += 1.0 / 120
                swipe.tick(at: time)
            }
        }
    }

    private func fingers() -> Fingers { Fingers(rules: rules) }

    func testASidewaysGestureFollowsTheFingersOneToOneTowardTheEdge() {
        var f = fingers()
        f.drag(dx: 5, steps: 6)
        XCTAssertEqual(f.swipe.offset, 30, accuracy: 0.001)
        XCTAssertTrue(f.swipe.isSwiping)
    }

    func testAGestureLocksToItsFirstAxis() {
        var f = fingers()
        f.send(.began)
        XCTAssertEqual(f.send(.changed, dx: 0.5, dy: 4), .scrollColumn(4))
        XCTAssertEqual(f.send(.changed, dx: 20, dy: 0), .scrollColumn(0))
        XCTAssertEqual(f.swipe.offset, 0)
        f.send(.ended)

        var g = fingers()
        g.send(.began)
        XCTAssertEqual(g.send(.changed, dx: 4, dy: 1), .moved)
        XCTAssertEqual(g.send(.changed, dx: 1, dy: 30), .moved)
        XCTAssertEqual(g.swipe.offset, 5, accuracy: 0.001)
    }

    func testMovementBelowTheLockDistanceWaitsAndThenScrollsAllOfIt() {
        var f = fingers()
        f.send(.began)
        XCTAssertEqual(f.send(.changed, dy: 1), StackSwipe.Answer.none)
        XCTAssertEqual(f.send(.changed, dy: 1), StackSwipe.Answer.none)
        XCTAssertEqual(f.send(.changed, dy: 1.5), .scrollColumn(3.5))
    }

    func testAShortSlowReleaseSpringsBack() {
        var f = fingers()
        f.drag(dx: 2, steps: 20, every: 0.02)
        XCTAssertEqual(f.send(.ended, after: 0.1), StackSwipe.Answer.none)
        XCTAssertTrue(f.swipe.isSpringing)
        f.settle()
        XCTAssertEqual(f.swipe.offset, 0)
        XCTAssertFalse(f.swipe.isSpringing)
    }

    func testAReleasePastTheDistanceCloses() {
        var f = fingers()
        f.drag(dx: 4, steps: 20, every: 0.02)
        XCTAssertGreaterThan(f.swipe.offset, rules.distance)
        XCTAssertEqual(f.send(.ended, after: 0.1), .close)
    }

    func testAFastReleaseClosesWhereverItIs() {
        var f = fingers()
        f.drag(dx: 10, steps: 3, every: 0.01)
        XCTAssertLessThan(f.swipe.offset, rules.distance)
        XCTAssertEqual(f.send(.ended, after: 0.005), .close)
        XCTAssertGreaterThan(f.swipe.velocity, rules.speed)
    }

    func testAFlingBackFromPastTheDistanceSpringsBack() {
        var f = fingers()
        f.drag(dx: 4, steps: 40, every: 0.02)
        for _ in 0..<6 { f.send(.changed, dx: -12, after: 0.01) }
        XCTAssertGreaterThan(f.swipe.offset, rules.distance)
        XCTAssertEqual(f.send(.ended, after: 0.005), StackSwipe.Answer.none)
        f.settle()
        XCTAssertEqual(f.swipe.offset, 0)
    }

    func testACancelledGestureSpringsBackFromAnywhere() {
        var f = fingers()
        f.drag(dx: 10, steps: 20)
        XCTAssertEqual(f.send(.cancelled), StackSwipe.Answer.none)
        f.settle()
        XCTAssertEqual(f.swipe.offset, 0)
    }

    func testAPullAwayFromTheEdgeIsResistedAndNeverPassesTheStretch() {
        var f = fingers()
        f.drag(dx: -4, steps: 2)
        XCTAssertLessThan(f.swipe.offset, 0)
        XCTAssertGreaterThan(f.swipe.offset, -8)
        f.drag(dx: -50, steps: 40)
        XCTAssertGreaterThan(f.swipe.offset, -rules.stretch)
        XCTAssertLessThan(f.swipe.offset, -rules.stretch * 0.9)
        XCTAssertEqual(f.send(.ended, after: 0.2), StackSwipe.Answer.none)
        f.settle()
        XCTAssertEqual(f.swipe.offset, 0)
    }

    func testTheMomentumAfterASidewaysGestureMovesNothing() {
        var f = fingers()
        f.drag(dx: 2, steps: 5)
        f.send(.ended)
        XCTAssertEqual(f.send(.none, dx: 30, dy: 30, momentum: true), StackSwipe.Answer.none)
        f.settle()
        XCTAssertEqual(f.swipe.offset, 0)

        var g = fingers()
        g.drag(dx: 0, dy: 5, steps: 5)
        g.send(.ended)
        XCTAssertEqual(g.send(.none, dx: 30, dy: 12, momentum: true), .scrollColumn(12))
        XCTAssertEqual(g.swipe.offset, 0)

        var h = fingers()
        h.drag(dx: 10, steps: 3)
        XCTAssertEqual(h.send(.ended, after: 0.005), .close)
        h.swipe.reset()
        XCTAssertEqual(h.send(.none, dy: 12, momentum: true), StackSwipe.Answer.none)
    }

    func testAMouseWheelOnlyScrolls() {
        var f = fingers()
        XCTAssertEqual(f.send(.none, dx: 40, dy: 10), .scrollColumn(10))
        XCTAssertEqual(f.swipe.offset, 0)
    }

    func testAGestureThatBeganBeforeTheCornerWasThereOnlyScrolls() {
        var f = fingers()
        XCTAssertEqual(f.send(.changed, dx: 20, dy: 1), .scrollColumn(1))
        XCTAssertEqual(f.swipe.offset, 0)
    }

    func testNothingSwipesWhileTheCornerMayNotSwipeAway() {
        var f = fingers()
        f.swipes = false
        f.send(.began)
        XCTAssertEqual(f.send(.changed, dx: 20, dy: 1), .scrollColumn(1))
        XCTAssertEqual(f.swipe.offset, 0)

        var g = fingers()
        g.drag(dx: 5, steps: 4)
        g.swipes = false
        XCTAssertEqual(g.send(.changed, dx: 5), StackSwipe.Answer.none)
        g.settle()
        XCTAssertEqual(g.swipe.offset, 0)
    }

    func testFingersRestingOnTheTrackpadCatchTheColumnComingBack() {
        var f = fingers()
        f.drag(dx: 5, steps: 8)
        f.send(.ended, after: 0.2)
        f.time += 0.05
        f.swipe.tick(at: f.time)
        let caught = f.swipe.offset
        XCTAssertGreaterThan(caught, 0)
        f.send(.mayBegin)
        f.settle(for: 0.5)
        XCTAssertEqual(f.swipe.offset, caught)
        f.send(.began)
        f.send(.changed, dx: 4)
        XCTAssertEqual(f.swipe.offset, caught + 4, accuracy: 0.001)
    }

    func testLiftingRestingFingersLetsTheColumnComeBack() {
        var f = fingers()
        f.drag(dx: 5, steps: 8)
        f.send(.ended, after: 0.2)
        f.time += 0.05
        f.swipe.tick(at: f.time)
        f.send(.mayBegin)
        f.send(.cancelled)
        f.settle()
        XCTAssertEqual(f.swipe.offset, 0)
    }

    func testTheColumnLeavesAsOnePieceAndComesBackWhenTheCornerReturns() {
        var f = fingers()
        f.drag(dx: 10, steps: 3)
        XCTAssertEqual(f.send(.ended, after: 0.005), .close)
        let released = f.swipe.offset
        f.swipe.leave(distance: 240, rules: rules, now: f.time)
        XCTAssertTrue(f.swipe.carriesColumn)
        f.time += 1.0 / 120
        f.swipe.tick(at: f.time)
        XCTAssertGreaterThan(f.swipe.offset, released)
        XCTAssertEqual(f.send(.began), StackSwipe.Answer.none)
        f.settle()
        XCTAssertEqual(f.swipe.offset, 240)
        XCTAssertTrue(f.swipe.carriesColumn)

        f.swipe.presented(rules: rules, now: f.time)
        XCTAssertTrue(f.swipe.carriesColumn)
        f.settle()
        XCTAssertEqual(f.swipe.offset, 0)
        XCTAssertFalse(f.swipe.carriesColumn)
    }

    func testACloseThatDidNotHappenComesBack() {
        var f = fingers()
        f.drag(dx: 10, steps: 3)
        XCTAssertEqual(f.send(.ended, after: 0.005), .close)
        f.swipe.cancelClose(rules: rules, now: f.time)
        f.settle()
        XCTAssertEqual(f.swipe.offset, 0)
        XCTAssertEqual(f.swipe.phase, .idle)
    }

    func testWithNoMotionTheSpringsLandAtOnce() {
        let still = StackSwipe.Rules(distance: 70, speed: 500, stretch: 40, returnDuration: 0, exitDuration: 0)
        var f = Fingers(rules: still)
        f.drag(dx: 2, steps: 5, every: 0.05)
        f.send(.ended, after: 0.2)
        XCTAssertEqual(f.swipe.offset, 0)
        XCTAssertFalse(f.swipe.isSpringing)
        f.drag(dx: 10, steps: 10)
        XCTAssertEqual(f.send(.ended, after: 0.005), .close)
        f.swipe.leave(distance: 240, rules: still, now: f.time)
        XCTAssertEqual(f.swipe.offset, 240)
    }

    func testTheStretchAndItsInverseAgree() {
        for raw in stride(from: -400.0, through: 100.0, by: 25.0) {
            let drawn = StackSwipe.drawn(raw, stretch: 40)
            XCTAssertEqual(StackSwipe.raw(drawn, stretch: 40), raw, accuracy: 0.01)
        }
        XCTAssertEqual(StackSwipe.drawn(-100, stretch: 0), 0)
    }
}
