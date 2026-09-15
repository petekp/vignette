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
                     \.expandDuration, \.hoverRevealDuration, \.backdropFadeIn, \.backdropFadeOut, \.dimFade] {
            XCTAssertEqual(off[keyPath: path], 0)
        }
        XCTAssertEqual(off.thumbnailSeconds, base.thumbnailSeconds, "a dwell time is not motion")
        XCTAssertEqual(off.toastSeconds, base.toastSeconds)
        XCTAssertEqual(off.cardMaxWidth, base.cardMaxWidth)
        XCTAssertEqual(base.scaledForMotion(1), base)
        XCTAssertEqual(base.scaledForMotion(0.5).slideInDuration, base.slideInDuration / 2)
    }
}
