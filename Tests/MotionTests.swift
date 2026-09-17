import SwiftUI
import XCTest

final class MotionTests: XCTestCase {
    func testScaleClampsAndReduceMotionWins() {
        XCTAssertEqual(Motion.scale(reduceMotion: false, multiplier: 1), 1)
        XCTAssertEqual(Motion.scale(reduceMotion: false, multiplier: 0.5), 0.5)
        XCTAssertEqual(Motion.scale(reduceMotion: false, multiplier: 7), 1)
        XCTAssertEqual(Motion.scale(reduceMotion: false, multiplier: -1), 0)
        XCTAssertEqual(Motion.scale(reduceMotion: false, multiplier: .nan), 1)
        XCTAssertEqual(Motion.scale(reduceMotion: true, multiplier: 1), 0)
    }

    func testScaledTweaksTouchOnlyMotion() {
        let base = UITweaks()
        let off = base.scaledForMotion(0)
        for path in [\UITweaks.slideInDuration, \.slideOutDuration, \.staggerDelay, \.staggerTotalMax, \.relayoutDuration,
                     \.expandDuration, \.hoverRevealDuration, \.backdropFadeIn, \.backdropFadeOut, \.backdropSlideIn, \.backdropSlideOut, \.dimFade,
                     \.flightArc, \.flightDepth] {
            XCTAssertEqual(off[keyPath: path], 0)
        }
        XCTAssertEqual(off.thumbnailSeconds, base.thumbnailSeconds, "a dwell time is not motion")
        XCTAssertEqual(off.toastSeconds, base.toastSeconds)
        XCTAssertEqual(off.cardMaxWidth, base.cardMaxWidth)
        XCTAssertEqual(off.flightArcMax, base.flightArcMax, "the cap is a limit on the bow, not an amount of it")
        XCTAssertEqual(base.scaledForMotion(1), base)
        XCTAssertEqual(base.scaledForMotion(0.5).slideInDuration, base.slideInDuration / 2)
    }

    // MARK: Handing a flight over

    @MainActor func testAFlightHandsOverOnlyOnceItIsThere() {
        let duration = 0.4, bounce = 0.15, screenWide: CGFloat = 1138
        let spring = Spring(duration: duration, bounce: bounce)
        func short(at t: Double) -> CGFloat { abs(1 - spring.value(target: 1.0, time: t)) * screenWide }
        XCTAssertGreaterThan(short(at: duration * 1.15), 1,
                             "the nominal end of the motion leaves a screen-wide flight points short")
        let settled = Anim.settle(duration, bounce: bounce, distance: screenWide, within: 0.5)
        XCTAssertGreaterThan(settled, duration * 1.15)
        XCTAssertLessThanOrEqual(short(at: settled), 0.5, "within a pixel by then, so nothing steps")
        XCTAssertLessThan(Anim.settle(duration, bounce: bounce, distance: 20, within: 0.5), settled,
                          "a short hop is there sooner")
        XCTAssertEqual(Anim.settle(0, bounce: bounce, distance: screenWide, within: 0.5), 0,
                       "motion off hands over in the same turn")
    }

    // MARK: The flight curve

    private let leg = FlightCurve(arc: 0.2, arcMax: 1000, depth: 0.5)

    func testFlightEndsExactlyWhereTheLayoutPutIt() {
        let from = CGPoint(x: 100, y: 400), to = CGPoint(x: 500, y: 100)
        for point in [from, to] {
            XCTAssertEqual(leg.placement(at: point, from: from, to: to), FlightCurve.Placement(offset: .zero, scale: 1))
        }
        // A spring overshoots; past the ends the card is on the line, never bowed the wrong way.
        XCTAssertEqual(leg.placement(at: CGPoint(x: 540, y: 70), from: from, to: to).offset, .zero)
    }

    func testFlightBowsAndSwellsMostInTheMiddle() {
        let from = CGPoint(x: 0, y: 0), to = CGPoint(x: 400, y: 0)   // a path running sideways
        let mid = leg.placement(at: CGPoint(x: 200, y: 0), from: from, to: to)
        XCTAssertEqual(mid.offset.width, 0, accuracy: 0.001)
        XCTAssertEqual(mid.offset.height, -80, accuracy: 0.001, "0.2 of 400 points, upward")
        XCTAssertEqual(mid.scale, 1.5, accuracy: 0.001)
        let quarter = leg.placement(at: CGPoint(x: 100, y: 0), from: from, to: to)
        XCTAssertEqual(quarter.offset.height, -60, accuracy: 0.001, "three quarters of the bow")
        XCTAssertLessThan(quarter.scale, mid.scale)
    }

    func testFlightBowIsCappedAndPerpendicular() {
        let capped = FlightCurve(arc: 0.2, arcMax: 30, depth: 0)
        let from = CGPoint(x: 0, y: 0), to = CGPoint(x: 600, y: 800)   // 1000 points long
        let mid = capped.placement(at: CGPoint(x: 300, y: 400), from: from, to: to)
        XCTAssertEqual(hypot(mid.offset.width, mid.offset.height), 30, accuracy: 0.001)
        XCTAssertEqual(mid.offset.width * 600 + mid.offset.height * 800, 0, accuracy: 0.01, "square to the path")
    }

    func testFlightThatTurnsAroundKeepsBowingTheSameWay() {
        // The side belongs to the line: a card that reverses mid-air must not snap across the path.
        for (from, to) in [(CGPoint(x: 1400, y: 900), CGPoint(x: 756, y: 460)),   // stack slot to annotator
                           (CGPoint(x: 1400, y: 900), CGPoint(x: 1390, y: 300))]  // up the column
        {
            let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            XCTAssertEqual(leg.placement(at: mid, from: from, to: to).offset,
                           leg.placement(at: mid, from: to, to: from).offset)
        }
    }

    /// A flight aimed somewhere else in mid-air keeps the old bow and crosses to the new one, so
    /// nothing steps sideways in a frame. What matters most is the end: at the new target the mix
    /// is the new path's placement alone, which is nothing, so the card lands exactly there.
    func testRetargetedFlightBlendsAndStillLandsOnItsTarget() {
        let was = leg.placement(at: CGPoint(x: 300, y: 400), from: .zero, to: CGPoint(x: 600, y: 0))
        let now = leg.placement(at: CGPoint(x: 300, y: 400), from: .zero, to: CGPoint(x: 300, y: 400))
        XCTAssertNotEqual(was.offset, .zero, "the old path still bows where the new one ends")
        XCTAssertEqual(now, FlightCurve.Placement(offset: .zero, scale: 1), "a path's own end is flat")
        XCTAssertEqual(FlightCurve.blend(was, now, 1), now, "settled, only the new path counts")
        XCTAssertEqual(FlightCurve.blend(was, now, 0), was, "the frame it is aimed again, only the old one")
        let half = FlightCurve.blend(was, now, 0.5)
        XCTAssertEqual(half.offset.width, was.offset.width / 2, accuracy: 0.001)
        XCTAssertEqual(half.offset.height, was.offset.height / 2, accuracy: 0.001)
    }

    func testFlightIsStraightWithMotionOff() {
        let curve = FlightCurve(ui: UITweaks().scaledForMotion(0))
        let from = CGPoint(x: 0, y: 0), to = CGPoint(x: 400, y: 300)
        let mid = curve.placement(at: CGPoint(x: 200, y: 150), from: from, to: to)
        XCTAssertEqual(mid, FlightCurve.Placement(offset: .zero, scale: 1))
        XCTAssertNotEqual(FlightCurve(ui: UITweaks()).placement(at: CGPoint(x: 200, y: 150), from: from, to: to).offset, .zero,
                          "the tuned defaults do bow")
    }

    @MainActor
    func testSpringTweenSettlesWithoutOvershootAndReversesFromWhereItIs() {
        var seen: [CGFloat] = []
        let tween = Tween(initial: 0) { seen.append($0) }
        let done = expectation(description: "settled")
        tween.animate(to: 1, duration: 0.3, curve: "spring") { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(tween.value, 1)
        XCTAssertEqual(seen, seen.sorted(), "a critically damped spring never overshoots")
        XCTAssertLessThanOrEqual(seen.max() ?? 0, 1)

        // Reverse mid-flight: the value turns back from where it is, not from the target.
        tween.animate(to: 0, duration: 0.3, curve: "spring")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
        let midway = tween.value
        XCTAssertGreaterThan(midway, 0)
        XCTAssertLessThan(midway, 1)
        let back = expectation(description: "back up")
        tween.animate(to: 1, duration: 0.3, curve: "spring") { back.fulfill() }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertLessThan(abs(tween.value - midway), 0.2, "no jump on retarget")
        wait(for: [back], timeout: 2)
        XCTAssertEqual(tween.value, 1)
    }

    /// The run loop stalls — a launch, a decode, a stitch — and the next tick arrives several
    /// frames late. The step must land where the spring really is by then: one late tick used to
    /// carry the value far past its target, which is what threw the stack's backdrop most of a
    /// screen to the left and swept it back into place.
    @MainActor
    func testSpringStepNeverPassesItsTargetHoweverLateTheTickIs() {
        let omega = 6.6 / 0.3      // the backdrop's slide-in
        for dt in [0.008, 0.016, 0.042, 0.06, 0.1, 0.4] {
            var value: CGFloat = 0, velocity: CGFloat = 0
            for _ in 0..<400 {
                (value, velocity) = Tween.spring(value: value, velocity: velocity, target: 1, omega: omega, dt: dt)
                XCTAssertLessThanOrEqual(value, 1, "a tick \(Int(dt * 1000)) ms late carried the value past its target")
            }
            XCTAssertEqual(value, 1, accuracy: 0.001, "and it still arrives")
        }
    }
}
