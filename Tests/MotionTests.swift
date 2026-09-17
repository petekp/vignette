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
}
