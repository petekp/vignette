import XCTest

final class ZoomTests: XCTestCase {
    /// A 400x300 window sitting in the middle of a 1000x800 screen.
    private let fitted = CGRect(x: 300, y: 250, width: 400, height: 300)
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    /// A room with 30 points above the fitted frame and 110 below, so the height fills first.
    private let room = CGRect(x: 0, y: 140, width: 1000, height: 440)

    /// The screen point the frame shows at `cursor`, a fraction of it with y from the top.
    private func point(_ cursor: CGPoint, of frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + cursor.x * frame.width, y: frame.maxY - cursor.y * frame.height)
    }

    /// The frame at `level` inside `limit`, aimed at `cursor` from the fitted size.
    private func frame(at level: CGFloat, aimedAt cursor: CGPoint = Zoom.center, within limit: CGRect?) -> CGRect {
        let reach = Zoom.reach(fitted: fitted, within: limit)
        let split = Zoom.split(level: level, reach: reach, pull: 0.3)
        let aim = Zoom.aim(at: cursor, of: fitted, fitted: fitted, window: split.window,
                           from: 1, to: level, within: limit)
        return Zoom.frame(fitted: fitted, scale: split.window, anchor: aim.anchor(at: level), within: limit)
    }

    func testTheWindowComesHomeAtTheFittedSize() {
        for anchor in [Zoom.center, CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: -0.4, y: 2.5)] {
            XCTAssertEqual(Zoom.frame(fitted: fitted, scale: Zoom.none, anchor: anchor, within: screen), fitted)
        }
    }

    func testTheAnchorIsTheCornerOrTheMiddleItNames() {
        let twice = CGSize(width: 2, height: 2)
        let middle = Zoom.frame(fitted: fitted, scale: twice, anchor: Zoom.center, within: nil)
        XCTAssertEqual(middle, CGRect(x: 100, y: 100, width: 800, height: 600))
        let topLeft = Zoom.frame(fitted: fitted, scale: twice, anchor: CGPoint(x: 0, y: 0), within: nil)
        XCTAssertEqual(topLeft.minX, fitted.minX, "the left edge stays where it is")
        XCTAssertEqual(topLeft.maxY, fitted.maxY, "and so does the top")
        let bottomRight = Zoom.frame(fitted: fitted, scale: twice, anchor: CGPoint(x: 1, y: 1), within: nil)
        XCTAssertEqual(bottomRight.maxX, fitted.maxX)
        XCTAssertEqual(bottomRight.minY, fitted.minY)
    }

    // MARK: Each side of the frame grows until it fills the room

    func testEachSideOfTheFrameReachesTheRoomOnItsOwn() {
        let reach = Zoom.reach(fitted: fitted, within: room)
        XCTAssertEqual(reach.height, 440.0 / 300, accuracy: 1e-9, "the height fills the room first")
        XCTAssertEqual(reach.width, 1000.0 / 400, accuracy: 1e-9)
        // At the level the height fills the room the frame is still the image's shape.
        let filled = frame(at: reach.height, within: room)
        XCTAssertEqual(filled.height, room.height, accuracy: 1e-9)
        XCTAssertEqual(filled.width, fitted.width * reach.height, accuracy: 1e-9)
        // Past it the height stays and the width keeps growing, so the frame changes shape.
        let wider = frame(at: 1.8, within: room)
        XCTAssertEqual(wider.height, room.height, accuracy: 1e-9, "the height cannot grow further")
        XCTAssertEqual(wider.width, fitted.width * 1.8, accuracy: 1e-9, "and the width still does")
        // And at the width's own reach the frame is the whole room.
        let whole = frame(at: reach.width, within: room)
        XCTAssertEqual(whole.width, room.width, accuracy: 1e-9)
        XCTAssertEqual(whole.height, room.height, accuracy: 1e-9)
        XCTAssertEqual(whole.minX, room.minX, accuracy: 1e-9)
        XCTAssertEqual(whole.minY, room.minY, accuracy: 1e-9)
    }

    func testThePictureIsMagnifiedEvenlyWhateverShapeTheFrameIs() {
        let reach = Zoom.reach(fitted: fitted, within: room)
        for level in stride(from: 1.0, through: 6.0, by: 0.05) {
            let level = CGFloat(level)
            let split = Zoom.split(level: level, reach: reach, pull: 0.3)
            let f = frame(at: level, within: room)
            let picture = Zoom.picture(in: CGRect(origin: .zero, size: f.size), camera: split.camera,
                                       center: Zoom.center)
            // The whole picture, wherever it is cropped, is the fitted frame times the level.
            XCTAssertEqual(picture.width, fitted.width * level, accuracy: 1e-6, "level \(level)")
            XCTAssertEqual(picture.height, fitted.height * level, accuracy: 1e-6, "level \(level)")
        }
    }

    func testTheWholeImageStaysVisibleInASideThatIsStillGrowing() {
        let reach = Zoom.reach(fitted: fitted, within: room)
        // Between the two reaches: the height is cropped, the width shows all of the image.
        let split = Zoom.split(level: 1.8, reach: reach, pull: 0.3)
        let visible = Zoom.visible(center: CGPoint(x: 0.2, y: 0.2), camera: split.camera)
        XCTAssertEqual(visible.width, 1, accuracy: 1e-9, "the whole width is in the frame")
        XCTAssertEqual(visible.minX, 0, accuracy: 1e-9)
        XCTAssertEqual(visible.height, reach.height / 1.8, accuracy: 1e-9, "the height is a band of it")
        XCTAssertLessThan(visible.height, 1)
    }

    func testTheRoomTakesTheAnchorInBothDirections() {
        // 30 points above the frame and 110 below, and 300 on either side: each side of the frame
        // grows into the room beside it, so there is one anchor per direction and no cursor in it.
        let allowed = Zoom.anchor(fitted: fitted, within: room)
        XCTAssertEqual(allowed.y, 30.0 / 140, accuracy: 1e-9, "the room says where the growth goes")
        XCTAssertEqual(allowed.x, 0.5, accuracy: 1e-9, "the frame is centred, so its growth is even")
        // A frame off to one side grows mostly the other way.
        let offset = CGRect(x: 60, y: 250, width: 400, height: 300)
        XCTAssertEqual(Zoom.anchor(fitted: offset, within: room).x, 60.0 / 600, accuracy: 1e-9)
        // A room the frame already fills has no growth to divide, and neither has no room at all.
        XCTAssertEqual(Zoom.anchor(fitted: fitted, within: fitted), Zoom.center)
        XCTAssertEqual(Zoom.anchor(fitted: fitted, within: nil), Zoom.center)
        XCTAssertEqual(Zoom.reach(fitted: fitted, within: fitted), Zoom.none)
    }

    func testTheAnchorThatHoldsTheCursorsPointHoldsIt() {
        // What the room's anchor replaces, and what a pull below the fitted size still uses: given
        // a frame on screen and a growth, the anchor that leaves the cursor's point where it is.
        // Each direction is answered on its own, so a frame growing in one alone still holds it.
        let cursors = [CGPoint(x: 0.1, y: 0.2), Zoom.center, CGPoint(x: 0.95, y: 0.9), CGPoint(x: 0, y: 1)]
        let growths = [CGSize(width: 1.4, height: 1.4), CGSize(width: 2.2, height: 1.3),
                       CGSize(width: 1, height: 1.8), CGSize(width: 0.8, height: 0.8)]
        for cursor in cursors {
            var shown = fitted
            for window in growths {
                let was = point(cursor, of: shown)
                let anchor = Zoom.anchor(holding: cursor, of: shown, fitted: fitted, grownTo: window)
                shown = Zoom.frame(fitted: fitted, scale: window, anchor: anchor, within: nil)
                let now = point(cursor, of: shown)
                XCTAssertEqual(now.x, was.x, accuracy: 0.001, "cursor \(cursor) grown to \(window)")
                XCTAssertEqual(now.y, was.y, accuracy: 0.001, "cursor \(cursor) grown to \(window)")
            }
        }
    }

    func testAimingSomewhereElseMidStepDoesNotMoveTheWindow() {
        // Grown away from the top left, then aimed at the bottom right part way through a spring.
        // The room decides the anchor a step ends at, so a mid-spring aim is where a clamp could
        // step the frame sideways.
        let reach = Zoom.reach(fitted: fitted, within: room)
        let end = max(reach.width, reach.height)
        let inFlight = 1 + (end - 1) * 0.3
        let first = Zoom.aim(at: CGPoint(x: 0.08, y: 0.08), of: fitted, fitted: fitted,
                             window: Zoom.split(level: 1 + (end - 1) * 0.6, reach: reach, pull: 0.3).window,
                             from: 1, to: 1 + (end - 1) * 0.6, within: room)
        let midWindow = Zoom.split(level: inFlight, reach: reach, pull: 0.3).window
        let shown = Zoom.frame(fitted: fitted, scale: midWindow, anchor: first.anchor(at: inFlight), within: room)
        let second = Zoom.aim(at: CGPoint(x: 0.9, y: 0.9), of: shown, fitted: fitted,
                              window: Zoom.split(level: end, reach: reach, pull: 0.3).window,
                              from: inFlight, to: end, within: room)
        let redrawn = Zoom.frame(fitted: fitted, scale: midWindow, anchor: second.anchor(at: inFlight), within: room)
        XCTAssertEqual(redrawn.minX, shown.minX, accuracy: 0.001, "the frame must not step sideways")
        XCTAssertEqual(redrawn.minY, shown.minY, accuracy: 0.001)
        // And it still lands on the room, whatever the second aim named.
        let landed = Zoom.frame(fitted: fitted, scale: Zoom.split(level: end, reach: reach, pull: 0.3).window,
                                anchor: second.anchor(at: end), within: room)
        XCTAssertEqual(landed.minX, room.minX, accuracy: 1e-6)
        XCTAssertEqual(landed.minY, room.minY, accuracy: 1e-6)
        XCTAssertEqual(landed.maxX, room.maxX, accuracy: 1e-6)
        XCTAssertEqual(landed.maxY, room.maxY, accuracy: 1e-6)
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

    func testReadingTheAnchorOffTheFrameOnScreenLeavesItAlone() {
        // The frame the screen edge has nudged: reading the anchor off it again reproduces it, so
        // the next step carries on from what is on screen instead of from where it should have been.
        let scale = CGSize(width: 2.4, height: 2.4)
        let nudged = Zoom.frame(fitted: fitted, scale: scale, anchor: CGPoint(x: 0, y: 0), within: screen)
        XCTAssertLessThan(nudged.maxX, fitted.minX + 400 * 2.4, "the screen edge moved it")
        let anchor = Zoom.anchor(reproducing: nudged, fitting: fitted, or: Zoom.center)
        XCTAssertEqual(Zoom.frame(fitted: fitted, scale: scale, anchor: anchor, within: screen), nudged)
        // A side that has not grown has no anchor to read, and takes the one it is given.
        let onlyWider = Zoom.frame(fitted: fitted, scale: CGSize(width: 1.5, height: 1), anchor: CGPoint(x: 0.2, y: 0.7), within: nil)
        let read = Zoom.anchor(reproducing: onlyWider, fitting: fitted, or: CGPoint(x: 0.9, y: 0.4))
        XCTAssertEqual(read.x, 0.2, accuracy: 1e-9)
        XCTAssertEqual(read.y, 0.4, accuracy: 1e-9)
    }

    func testTheRoomGivesWayWhenTheZoomIsAimedAndNotPartWayThroughIt() {
        let reach = Zoom.reach(fitted: fitted, within: room)
        let end = max(reach.width, reach.height)
        let aim = Zoom.aim(at: Zoom.center, of: fitted, fitted: fitted,
                           window: Zoom.split(level: end, reach: reach, pull: 0.3).window,
                           from: 1, to: end, within: room)
        var walked: [CGRect] = []
        for i in 0...200 {
            let level = 1 + (end - 1) * CGFloat(i) / 200
            let scale = Zoom.split(level: level, reach: reach, pull: 0.3).window
            let anchor = aim.anchor(at: level)
            let free = Zoom.frame(fitted: fitted, scale: scale, anchor: anchor, within: nil)
            let kept = Zoom.frame(fitted: fitted, scale: scale, anchor: anchor, within: room)
            XCTAssertEqual(kept.minX, free.minX, accuracy: 1e-6, "the room moved the frame at level \(level)")
            XCTAssertEqual(kept.minY, free.minY, accuracy: 1e-6, "the room moved the frame at level \(level)")
            walked.append(kept)
        }
        XCTAssertEqual(walked.last!.maxY, room.maxY, accuracy: 1e-6, "and it still grows into the whole room")
        XCTAssertEqual(walked.last!.minY, room.minY, accuracy: 1e-6)
        XCTAssertEqual(walked.last!.maxX, room.maxX, accuracy: 1e-6)
        XCTAssertEqual(walked.last!.minX, room.minX, accuracy: 1e-6)
        // Every edge of the frame moves one way for the whole growth: nothing turns around.
        for edge in [\CGRect.minX, \CGRect.maxX, \CGRect.minY, \CGRect.maxY] {
            let line = walked.map { $0[keyPath: edge] }
            let falling = line.last! < line.first!
            for (a, b) in zip(line, line.dropFirst()) {
                XCTAssertTrue(falling ? b <= a + 1e-9 : b >= a - 1e-9, "an edge turned around")
            }
        }
    }

    func testAPullBelowTheFittedSizeShrinksAboutTheCursorsOwnAnchor() {
        // A target under 1: the pull a zoom-out makes before it springs back. A shrunk frame is
        // inside the fitted one, which is inside the room, so the room has no growth to divide and
        // must leave the anchor alone. Clamping there slid the picture down while it shrank and
        // back up on the way home.
        let reach = Zoom.reach(fitted: fitted, within: room)
        for target in [0.95, 0.85, 0.5] as [CGFloat] {
            let window = Zoom.split(level: target, reach: reach, pull: 0.3).window
            let aim = Zoom.aim(at: Zoom.center, of: fitted, fitted: fitted, window: window,
                               from: 1, to: target, within: room)
            XCTAssertEqual(aim.now.x, 0.5, accuracy: 1e-9, "a key names the middle and the room takes nothing")
            XCTAssertEqual(aim.now.y, 0.5, accuracy: 1e-9, "a key names the middle and the room takes nothing")
            let pulled = Zoom.frame(fitted: fitted, scale: window, anchor: aim.anchor(at: target), within: room)
            XCTAssertEqual(fitted.maxY - pulled.maxY, pulled.minY - fitted.minY, accuracy: 1e-9,
                           "the top and the bottom come in by the same amount")
            XCTAssertEqual(fitted.midX, pulled.midX, accuracy: 1e-9)
            XCTAssertEqual(fitted.midY, pulled.midY, accuracy: 1e-9)
        }
        // A cursor off the middle is still its own anchor: a pinch out shrinks about the fingers.
        let window = Zoom.split(level: 0.8, reach: reach, pull: 0.3).window
        let corner = Zoom.aim(at: CGPoint(x: 0.9, y: 0.9), of: fitted, fitted: fitted, window: window,
                              from: 1, to: 0.8, within: room)
        XCTAssertEqual(corner.now.x, 0.9, accuracy: 1e-9)
        XCTAssertEqual(corner.now.y, 0.9, accuracy: 1e-9)
    }

    func testTheFrameStaysOnTheScreenItIsGiven() {
        for anchor in [Zoom.center, CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)] {
            for scale in [1.5, 2, 2.5] as [CGFloat] {
                let f = Zoom.frame(fitted: fitted, scale: CGSize(width: scale, height: scale), anchor: anchor, within: screen)
                XCTAssertTrue(screen.contains(f), "anchor \(anchor) at \(scale) left the screen: \(f)")
            }
        }
        // Wider than the screen: it covers the screen rather than being pushed inside it.
        let huge = Zoom.frame(fitted: fitted, scale: CGSize(width: 4, height: 4), anchor: Zoom.center, within: screen)
        XCTAssertEqual(huge.minX, screen.minX)
        XCTAssertEqual(huge.minY, screen.minY)
    }

    func testTheWindowAndTheCameraMultiplyToTheLevelInEachDirection() {
        // Whatever the level, what the user sees in each direction is that side's growth times the
        // magnification in it. That is the invariant the two sides cannot drift apart from, so it
        // is checked across the levels where each side stops growing.
        let reach = CGSize(width: 2.5, height: 1.2656)
        for level in stride(from: 1.0, through: 8.0, by: 0.05) {
            let s = Zoom.split(level: CGFloat(level), reach: reach, pull: 0.3)
            XCTAssertEqual(s.window.width * s.camera.width, CGFloat(level), accuracy: 1e-9, "level \(level)")
            XCTAssertEqual(s.window.height * s.camera.height, CGFloat(level), accuracy: 1e-9, "level \(level)")
            XCTAssertLessThanOrEqual(s.window.width, reach.width)
            XCTAssertLessThanOrEqual(s.window.height, reach.height)
            XCTAssertGreaterThanOrEqual(s.camera.width, 1)
            XCTAssertGreaterThanOrEqual(s.camera.height, 1)
        }
    }

    func testEachSideGrowsFirstAndIsMagnifiedOnlyAfterIt() {
        let reach = CGSize(width: 4, height: 2)
        // Under both limits nothing is magnified: the page is not asked for anything at all.
        let low = Zoom.split(level: 1.9, reach: reach, pull: 0.3)
        XCTAssertEqual(low.window, CGSize(width: 1.9, height: 1.9))
        XCTAssertEqual(low.camera, Zoom.none)
        // Past the height's limit the height is magnified and the width still grows.
        let middle = Zoom.split(level: 3, reach: reach, pull: 0.3)
        XCTAssertEqual(middle.window, CGSize(width: 3, height: 2))
        XCTAssertEqual(middle.camera.width, 1, accuracy: 1e-9)
        XCTAssertEqual(middle.camera.height, 1.5, accuracy: 1e-9)
        // Past both, the frame is the room and the rest is magnification.
        let high = Zoom.split(level: 8, reach: reach, pull: 0.3)
        XCTAssertEqual(high.window, CGSize(width: 4, height: 2))
        XCTAssertEqual(high.camera.width, 2, accuracy: 1e-9)
        XCTAssertEqual(high.camera.height, 4, accuracy: 1e-9)
        // A room that cannot hold a bigger window leaves every level to the magnification.
        let stuck = Zoom.split(level: 3, reach: Zoom.none, pull: 0.3)
        XCTAssertEqual(stuck.window, Zoom.none)
        XCTAssertEqual(stuck.camera, CGSize(width: 3, height: 3))
    }

    func testThePageIsToldTheMagnificationPastTheWholeImageFitting() {
        let reach = CGSize(width: 4, height: 2)
        // While any side is still growing the whole image is in the window: nothing to magnify.
        for level in [1.0, 1.5, 2.0] as [CGFloat] {
            let window = Zoom.split(level: level, reach: reach, pull: 0.3).window
            XCTAssertEqual(Zoom.pageRatio(level: level, window: window), 1, accuracy: 1e-9, "level \(level)")
        }
        // Past the first side's limit the ratio is the level over that side's growth.
        XCTAssertEqual(Zoom.pageRatio(level: 3, window: Zoom.split(level: 3, reach: reach, pull: 0.3).window),
                       1.5, accuracy: 1e-9)
        XCTAssertEqual(Zoom.pageRatio(level: 8, window: Zoom.split(level: 8, reach: reach, pull: 0.3).window),
                       4, accuracy: 1e-9)
        XCTAssertEqual(Zoom.pageRatio(level: .nan, window: Zoom.none), 1, "the page refuses anything but a number")
    }

    func testAPullBelowTheFittedSizeShowsAFractionOfItself() {
        // The window gives a little and the page is not involved, which is what springs back.
        let pulled = Zoom.split(level: 0.5, reach: CGSize(width: 2, height: 2), pull: 0.3)
        XCTAssertEqual(pulled.window.width, 0.85, accuracy: 1e-9)
        XCTAssertEqual(pulled.window.height, 0.85, accuracy: 1e-9, "and evenly, so nothing is cropped")
        XCTAssertEqual(pulled.camera, Zoom.none)
        XCTAssertEqual(Zoom.split(level: 0, reach: CGSize(width: 2, height: 2), pull: 0.3).window, Zoom.none,
                       "a level of zero is not a size")
        XCTAssertEqual(Zoom.split(level: .nan, reach: CGSize(width: 2, height: 2), pull: 0.3).window, Zoom.none)
    }

    // MARK: The magnification's side: which part of the image is visible

    func testTheWholeImageIsVisibleUntilTheMagnificationStarts() {
        XCTAssertEqual(Zoom.visible(center: Zoom.center, camera: Zoom.none), CGRect(x: 0, y: 0, width: 1, height: 1))
        // Wherever the middle is asked to be, at the fitted size it is the image's own middle.
        XCTAssertEqual(Zoom.clamped(center: CGPoint(x: 0.1, y: 0.9), camera: Zoom.none), Zoom.center)
        XCTAssertEqual(Zoom.visible(center: CGPoint(x: 0.1, y: 0.9), camera: Zoom.none), CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testTheVisiblePartNeverLeavesTheImage() {
        for camera in [CGSize(width: 1.5, height: 1.5), CGSize(width: 1, height: 3), CGSize(width: 4, height: 1.2), CGSize(width: 8, height: 8)] {
            for center in [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0.5, y: 0.5), CGPoint(x: -2, y: 3)] {
                let v = Zoom.visible(center: center, camera: camera)
                XCTAssertEqual(v.width, 1 / camera.width, accuracy: 1e-9)
                XCTAssertEqual(v.height, 1 / camera.height, accuracy: 1e-9)
                XCTAssertGreaterThanOrEqual(v.minX, -1e-9, "camera \(camera) center \(center)")
                XCTAssertGreaterThanOrEqual(v.minY, -1e-9)
                XCTAssertLessThanOrEqual(v.maxX, 1 + 1e-9)
                XCTAssertLessThanOrEqual(v.maxY, 1 + 1e-9)
            }
        }
    }

    func testThePointUnderTheCursorStaysUnderItWhileMagnifying() {
        // The same run of steps as the window's test, in the magnification's half of the zoom:
        // the image's point under the cursor has to keep its place on screen there too. The two
        // directions are magnified by different amounts, which is what a grown frame does.
        for cursor in [CGPoint(x: 0.1, y: 0.2), Zoom.center, CGPoint(x: 0.8, y: 0.85)] {
            var pan = ZoomPan.centered
            var camera = Zoom.none
            for step in [1.4, 1.4, 1.2, 0.9] as [CGFloat] {
                let next = CGSize(width: max(1, camera.width * step), height: max(1, camera.height * step * 1.3))
                pan = ZoomPan(center: pan.center(at: camera), camera: camera, cursor: cursor)
                let before = Zoom.visible(center: pan.center(at: camera), camera: camera)
                let after = Zoom.visible(center: pan.center(at: next), camera: next)
                // The image's point at the cursor, in both views.
                let was = CGPoint(x: before.minX + cursor.x * before.width, y: before.minY + cursor.y * before.height)
                let now = CGPoint(x: after.minX + cursor.x * after.width, y: after.minY + cursor.y * after.height)
                // Away from the image's edges the point is held exactly; at them the view slides
                // and the cursor gives way, as the window does against the screen's edge.
                if after.minX > 1e-9 && after.maxX < 1 - 1e-9 {
                    XCTAssertEqual(now.x, was.x, accuracy: 0.001, "cursor \(cursor) at camera \(next)")
                }
                if after.minY > 1e-9 && after.maxY < 1 - 1e-9 {
                    XCTAssertEqual(now.y, was.y, accuracy: 0.001, "cursor \(cursor) at camera \(next)")
                }
                camera = next
            }
        }
    }

    func testACursorNearAnEdgeKeepsThatEdgeInView() {
        // A square picture, so a band of 150 points is 0.15 of either side.
        let square = CGSize(width: 1000, height: 1000), band: CGFloat = 150, pull: CGFloat = 0.5
        // Without the pull the corner beside the cursor goes as soon as the picture magnifies.
        let plain = ZoomPan(center: Zoom.center, camera: Zoom.none, cursor: CGPoint(x: 0.95, y: 0.95))
        let twice = CGSize(width: 2, height: 2)
        XCTAssertLessThan(Zoom.visible(center: plain.center(at: twice), camera: twice).maxX, 1 - 1e-6)
        XCTAssertLessThan(Zoom.visible(center: plain.center(at: twice), camera: twice).maxY, 1 - 1e-6)
        // With it, the image's bottom right corner stays in view however far the zoom goes.
        let aimed = Zoom.pulledToEdges(CGPoint(x: 0.95, y: 0.95), in: square, band: band, pull: pull)
        let pan = ZoomPan(center: Zoom.center, camera: Zoom.none, cursor: aimed)
        for camera in [1.5, 2, 4, 8] as [CGFloat] {
            let both = CGSize(width: camera, height: camera)
            let v = Zoom.visible(center: pan.center(at: both), camera: both)
            XCTAssertEqual(v.maxX, 1, accuracy: 1e-9, "camera \(camera)")
            XCTAssertEqual(v.maxY, 1, accuracy: 1e-9, "camera \(camera)")
        }
        // And it holds the edge in a direction that is magnified while the other still grows.
        let oneWay = CGSize(width: 1, height: 3)
        let band3 = Zoom.visible(center: pan.center(at: oneWay), camera: oneWay)
        XCTAssertEqual(band3.maxY, 1, accuracy: 1e-9, "the bottom edge stays")
        XCTAssertEqual(band3.width, 1, accuracy: 1e-9, "and the whole width is still there")
        // And the top left corner the same way.
        let corner = ZoomPan(center: Zoom.center, camera: Zoom.none,
                             cursor: Zoom.pulledToEdges(CGPoint(x: 0.04, y: 0.06), in: square, band: band, pull: pull))
        let v = Zoom.visible(center: corner.center(at: CGSize(width: 4, height: 4)), camera: CGSize(width: 4, height: 4))
        XCTAssertEqual(v.minX, 0, accuracy: 1e-9)
        XCTAssertEqual(v.minY, 0, accuracy: 1e-9)
    }

    func testTheEdgeBandReachesAsFarFromEveryEdgeOfAWideFrame() {
        // Three times as wide as it is tall: the band is 0.08 of the width and 0.24 of the height.
        let wide = CGSize(width: 1500, height: 500), band: CGFloat = 120, pull: CGFloat = 0.5
        // 30 points in from the left edge and 30 points down from the top: both are inside the
        // half of the band that pins, so a zoom there holds both edges.
        let held = Zoom.pulledToEdges(CGPoint(x: 30 / wide.width, y: 30 / wide.height),
                                      in: wide, band: band, pull: pull)
        XCTAssertEqual(held.x, 0)
        XCTAssertEqual(held.y, 0)
        let four = CGSize(width: 4, height: 4)
        let v = Zoom.visible(center: ZoomPan(center: Zoom.center, camera: Zoom.none, cursor: held).center(at: four), camera: four)
        XCTAssertEqual(v.minX, 0, accuracy: 1e-9, "the left edge stays in view")
        XCTAssertEqual(v.minY, 0, accuracy: 1e-9, "and the top edge with it")
        // 90 points in from the right edge and from the bottom: the same way through the band, so
        // the pull leaves the cursor the same number of points from either edge.
        let eased = Zoom.pulledToEdges(CGPoint(x: 1 - 90 / wide.width, y: 1 - 90 / wide.height),
                                       in: wide, band: band, pull: pull)
        XCTAssertEqual((1 - eased.x) * wide.width, 45, accuracy: 1e-9)
        XCTAssertEqual((1 - eased.y) * wide.height, 45, accuracy: 1e-9)
        // And 200 points in from either edge is outside the band on both.
        let inside = Zoom.pulledToEdges(CGPoint(x: 200 / wide.width, y: 200 / wide.height),
                                        in: wide, band: band, pull: pull)
        XCTAssertEqual(inside.x, 200 / wide.width)
        XCTAssertEqual(inside.y, 200 / wide.height)
    }

    func testTheMiddleOfThePictureStillZoomsAboutItself() {
        let square = CGSize(width: 1000, height: 1000)
        XCTAssertEqual(Zoom.pulledToEdges(Zoom.center, in: square, band: 150, pull: 0.5), Zoom.center)
        // Outside the band, and at its inner edge, the cursor is its own anchor.
        XCTAssertEqual(Zoom.pulledToEdges(CGPoint(x: 0.7, y: 0.3), in: square, band: 150, pull: 0.5), CGPoint(x: 0.7, y: 0.3))
        XCTAssertEqual(Zoom.pulledToEdges(CGPoint(x: 0.85, y: 0.15), in: square, band: 150, pull: 0.5), CGPoint(x: 0.85, y: 0.15))
        // Inside the band the pull eases in rather than snapping.
        let eased = Zoom.pulledToEdges(CGPoint(x: 0.88, y: 0.12), in: square, band: 150, pull: 0.5)
        XCTAssertGreaterThan(eased.x, 0.88)
        XCTAssertLessThan(eased.x, 1)
        XCTAssertLessThan(eased.y, 0.12)
        XCTAssertGreaterThan(eased.y, 0)
        // A band of nothing leaves every cursor where it is, and so does a band wider than the
        // picture: it reaches half of each side, and the middle is exactly that far from both.
        XCTAssertEqual(Zoom.pulledToEdges(CGPoint(x: 0.99, y: 0.01), in: square, band: 0, pull: 0.5), CGPoint(x: 0.99, y: 0.01))
        XCTAssertEqual(Zoom.pulledToEdges(Zoom.center, in: square, band: 5000, pull: 0.5), Zoom.center)
    }

    func testAPanComesHomeToTheWholeImage() {
        let pan = ZoomPan(center: CGPoint(x: 0.8, y: 0.2), camera: CGSize(width: 4, height: 2), cursor: CGPoint(x: 0.1, y: 0.1))
        XCTAssertEqual(pan.center(at: Zoom.none), Zoom.center, "zooming back out shows the whole image again")
        XCTAssertEqual(ZoomPan.centered.center(at: CGSize(width: 3, height: 3)), Zoom.center, "a step about the middle stays centred")
    }

    func testThePictureFillsTheFrameAndCropsToTheVisiblePart() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        // At the fitted size the whole image is the frame.
        XCTAssertEqual(Zoom.picture(in: bounds, camera: Zoom.none, center: Zoom.center), bounds)
        // Magnified about the middle: twice the size, centred on the frame.
        let twice = Zoom.picture(in: bounds, camera: CGSize(width: 2, height: 2), center: Zoom.center)
        XCTAssertEqual(twice, CGRect(x: -200, y: -150, width: 800, height: 600))
        // Magnified at the image's top left corner: that corner is the frame's top left.
        let corner = Zoom.picture(in: bounds, camera: CGSize(width: 2, height: 2), center: CGPoint(x: 0, y: 0))
        XCTAssertEqual(corner.minX, 0, accuracy: 1e-9, "the image's left edge is the frame's")
        XCTAssertEqual(corner.maxY, bounds.maxY, accuracy: 1e-9, "and its top edge is the frame's top")
        // One direction magnified and the other not: the picture is wider than the frame and
        // exactly as tall, which is a frame that has grown into the room in height alone.
        let oneWay = Zoom.picture(in: bounds, camera: CGSize(width: 2, height: 1), center: Zoom.center)
        XCTAssertEqual(oneWay.height, bounds.height, accuracy: 1e-9)
        XCTAssertEqual(oneWay.width, bounds.width * 2, accuracy: 1e-9)
        XCTAssertEqual(oneWay.midX, bounds.midX, accuracy: 1e-9)
        // The picture always covers the frame, whatever the middle asks for.
        for camera in [Zoom.none, CGSize(width: 1.5, height: 3), CGSize(width: 3, height: 1), CGSize(width: 8, height: 8)] {
            for center in [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0.3, y: 0.7)] {
                let p = Zoom.picture(in: bounds, camera: camera, center: center)
                XCTAssertLessThanOrEqual(p.minX, bounds.minX + 1e-9, "camera \(camera) center \(center)")
                XCTAssertGreaterThanOrEqual(p.maxX, bounds.maxX - 1e-9)
                XCTAssertLessThanOrEqual(p.minY, bounds.minY + 1e-9)
                XCTAssertGreaterThanOrEqual(p.maxY, bounds.maxY - 1e-9)
            }
        }
    }

    func testABadNumberLeavesTheVisiblePartAlone() {
        let bad = CGSize(width: CGFloat.nan, height: CGFloat.nan)
        XCTAssertEqual(Zoom.visible(center: Zoom.center, camera: bad), CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(Zoom.picture(in: CGRect(x: 0, y: 0, width: 4, height: 3), camera: bad, center: Zoom.center),
                       CGRect(x: 0, y: 0, width: 4, height: 3))
        XCTAssertEqual(ZoomPan(center: Zoom.center, camera: bad, cursor: Zoom.center).center(at: CGSize(width: 2, height: 2)), Zoom.center)
    }

    func testABadNumberLeavesTheAnchorWhereTheCursorIs() {
        let cursor = CGPoint(x: 0.25, y: 0.25)
        let twice = CGSize(width: 2, height: 2)
        XCTAssertEqual(Zoom.anchor(holding: cursor, of: fitted, fitted: .zero, grownTo: twice), cursor)
        XCTAssertEqual(Zoom.anchor(holding: cursor, of: .zero, fitted: fitted, grownTo: twice), cursor)
        XCTAssertEqual(Zoom.anchor(holding: cursor, of: fitted, fitted: fitted, grownTo: CGSize(width: CGFloat.nan, height: CGFloat.nan)), cursor)
        XCTAssertEqual(Zoom.anchor(holding: cursor, of: fitted, fitted: fitted, grownTo: Zoom.none), cursor,
                       "nothing has grown, so there is no growth to divide")
        XCTAssertEqual(Zoom.clamped(CGPoint(x: -3, y: 9)), CGPoint(x: 0, y: 1))
    }
}
