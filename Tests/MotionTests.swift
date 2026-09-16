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

    func testScaledTweaksTouchOnlyAnimationDurations() {
        let base = UITweaks()
        let off = base.scaledForMotion(0)
        for path in [\UITweaks.slideInDuration, \.slideOutDuration, \.staggerDelay, \.staggerTotalMax, \.relayoutDuration,
                     \.expandDuration, \.hoverRevealDuration, \.backdropFadeIn, \.backdropFadeOut, \.backdropSlideIn, \.backdropSlideOut, \.dimFade] {
            XCTAssertEqual(off[keyPath: path], 0)
        }
        XCTAssertEqual(off.thumbnailSeconds, base.thumbnailSeconds, "a dwell time is not motion")
        XCTAssertEqual(off.toastSeconds, base.toastSeconds)
        XCTAssertEqual(off.cardMaxWidth, base.cardMaxWidth)
        XCTAssertEqual(base.scaledForMotion(1), base)
        XCTAssertEqual(base.scaledForMotion(0.5).slideInDuration, base.slideInDuration / 2)
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
