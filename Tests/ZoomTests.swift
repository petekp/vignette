import XCTest

final class ZoomTests: XCTestCase {
    /// A 400x300 window sitting in the middle of a 1000x800 screen.
    private let fitted = CGRect(x: 300, y: 250, width: 400, height: 300)
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    /// The screen point the frame shows at `cursor`, a fraction of it with y from the top.
    private func point(_ cursor: CGPoint, of frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + cursor.x * frame.width, y: frame.maxY - cursor.y * frame.height)
    }

    func testTheWindowComesHomeAtTheFittedSize() {
        for anchor in [Zoom.center, CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: -0.4, y: 2.5)] {
            XCTAssertEqual(Zoom.frame(fitted: fitted, scale: 1, anchor: anchor, within: screen), fitted)
        }
    }

    func testTheAnchorIsTheCornerOrTheMiddleItNames() {
        let middle = Zoom.frame(fitted: fitted, scale: 2, anchor: Zoom.center, within: nil)
        XCTAssertEqual(middle, CGRect(x: 100, y: 100, width: 800, height: 600))
        let topLeft = Zoom.frame(fitted: fitted, scale: 2, anchor: CGPoint(x: 0, y: 0), within: nil)
        XCTAssertEqual(topLeft.minX, fitted.minX, "the left edge stays where it is")
        XCTAssertEqual(topLeft.maxY, fitted.maxY, "and so does the top")
        let bottomRight = Zoom.frame(fitted: fitted, scale: 2, anchor: CGPoint(x: 1, y: 1), within: nil)
        XCTAssertEqual(bottomRight.maxX, fitted.maxX)
        XCTAssertEqual(bottomRight.minY, fitted.minY)
    }

    func testThePointUnderTheCursorStaysUnderIt() {
        let cursors = [CGPoint(x: 0.1, y: 0.2), Zoom.center, CGPoint(x: 0.95, y: 0.9), CGPoint(x: 0, y: 1)]
        for cursor in cursors {
            // A run of steps from the fitted size, each one holding the same cursor.
            var shown = fitted
            var scale: CGFloat = 1
            for step in [1.2, 1.2, 1.2, 0.8, 0.9] as [CGFloat] {
                let was = point(cursor, of: shown)
                let target = scale * step
                let aim = Zoom.aim(at: cursor, of: shown, fitted: fitted, scale: scale, to: target)
                scale = target
                shown = Zoom.frame(fitted: fitted, scale: scale, anchor: aim.anchor(at: scale), within: nil)
                let now = point(cursor, of: shown)
                XCTAssertEqual(now.x, was.x, accuracy: 0.001, "cursor \(cursor) at scale \(scale)")
                XCTAssertEqual(now.y, was.y, accuracy: 0.001, "cursor \(cursor) at scale \(scale)")
            }
        }
    }

    func testAimingSomewhereElseMidStepDoesNotMoveTheWindow() {
        // Grown away from the top left, then aimed at the bottom right part way through a spring.
        let first = Zoom.aim(at: CGPoint(x: 0.08, y: 0.08), of: fitted, fitted: fitted, scale: 1, to: 1.6)
        let inFlight: CGFloat = 1.3
        let shown = Zoom.frame(fitted: fitted, scale: inFlight, anchor: first.anchor(at: inFlight), within: nil)
        let second = Zoom.aim(at: CGPoint(x: 0.9, y: 0.9), of: shown, fitted: fitted, scale: inFlight, to: 2)
        let redrawn = Zoom.frame(fitted: fitted, scale: inFlight, anchor: second.anchor(at: inFlight), within: nil)
        XCTAssertEqual(redrawn.minX, shown.minX, accuracy: 0.001, "the frame must not step sideways")
        XCTAssertEqual(redrawn.minY, shown.minY, accuracy: 0.001)
        // And it still lands holding the point the new aim named.
        let held = point(CGPoint(x: 0.9, y: 0.9), of: shown)
        let landed = Zoom.frame(fitted: fitted, scale: 2, anchor: second.anchor(at: 2), within: nil)
        XCTAssertEqual(point(CGPoint(x: 0.9, y: 0.9), of: landed).x, held.x, accuracy: 0.001)
        XCTAssertEqual(point(CGPoint(x: 0.9, y: 0.9), of: landed).y, held.y, accuracy: 0.001)
    }

    func testAnAimHoldsItsEndsPastThem() {
        let aim = ZoomAim(was: CGPoint(x: 0, y: 0), now: CGPoint(x: 1, y: 1), from: 1.2, to: 1.8)
        XCTAssertEqual(aim.anchor(at: 1.2), CGPoint(x: 0, y: 0))
        XCTAssertEqual(aim.anchor(at: 1.5), Zoom.center, "half way through the step, half way between")
        XCTAssertEqual(aim.anchor(at: 1.8), CGPoint(x: 1, y: 1))
        XCTAssertEqual(aim.anchor(at: 0.5), CGPoint(x: 0, y: 0), "turned back past the start")
        XCTAssertEqual(aim.anchor(at: 4), CGPoint(x: 1, y: 1), "carried past the target")
        XCTAssertEqual(ZoomAim.fitted.anchor(at: 3), Zoom.center)
    }

    func testReadingTheAnchorAtTheScaleOnScreenLeavesTheFrameAlone() {
        // The frame the screen edge has nudged: reading the anchor off it again reproduces it, so
        // the next step carries on from what is on screen instead of from where it should have been.
        let nudged = Zoom.frame(fitted: fitted, scale: 2.4, anchor: CGPoint(x: 0, y: 0), within: screen)
        XCTAssertLessThan(nudged.maxX, fitted.minX + 400 * 2.4, "the screen edge moved it")
        let cursor = CGPoint(x: 0.3, y: 0.7)
        let anchor = Zoom.anchor(holding: cursor, of: nudged, fitted: fitted, at: 2.4)
        XCTAssertEqual(Zoom.frame(fitted: fitted, scale: 2.4, anchor: anchor, within: screen), nudged)
    }

    func testTheFrameStaysOnTheScreenItIsGiven() {
        for anchor in [Zoom.center, CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)] {
            for scale in [1.5, 2, 2.5] as [CGFloat] {
                let f = Zoom.frame(fitted: fitted, scale: scale, anchor: anchor, within: screen)
                XCTAssertTrue(screen.contains(f), "anchor \(anchor) at \(scale) left the screen: \(f)")
            }
        }
        // Wider than the screen: it covers the screen rather than being pushed inside it.
        let huge = Zoom.frame(fitted: fitted, scale: 4, anchor: Zoom.center, within: screen)
        XCTAssertEqual(huge.minX, screen.minX)
        XCTAssertEqual(huge.minY, screen.minY)
    }

    func testAnAnchorAtTheFittedSizeIsTheCursorItself() {
        // Nothing has grown yet, so there is no growth to divide: the cursor's own point is where
        // the next step in either direction wants the anchor.
        let cursor = CGPoint(x: 0.2, y: 0.8)
        XCTAssertEqual(Zoom.anchor(holding: cursor, of: fitted, fitted: fitted, at: 1), cursor)
        XCTAssertEqual(Zoom.anchor(holding: cursor, of: fitted, fitted: fitted, at: 1.5).x, cursor.x, accuracy: 0.001)
        XCTAssertEqual(Zoom.anchor(holding: cursor, of: fitted, fitted: fitted, at: 1.5).y, cursor.y, accuracy: 0.001)
    }

    func testABadNumberLeavesTheAnchorWhereTheCursorIs() {
        let cursor = CGPoint(x: 0.25, y: 0.25)
        XCTAssertEqual(Zoom.anchor(holding: cursor, of: fitted, fitted: .zero, at: 2), cursor)
        XCTAssertEqual(Zoom.anchor(holding: cursor, of: .zero, fitted: fitted, at: 2), cursor)
        XCTAssertEqual(Zoom.anchor(holding: cursor, of: fitted, fitted: fitted, at: .nan), cursor)
        XCTAssertEqual(Zoom.clamped(CGPoint(x: -3, y: 9)), CGPoint(x: 0, y: 1))
    }
}
