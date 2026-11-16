import XCTest

extension AnnotatorZoomTests {
    private var dockFitted: CGRect { CGRect(x: 310, y: 290, width: 380, height: 285) }
    private var dockRoom: CGRect { CGRect(x: 0, y: 210, width: 1000, height: 370) }
    private var dockFrameRoom: CGRect { CGRect(x: 0, y: 272, width: 1000, height: 308) }

    private func carry(_ zoom: inout AnnotatorZoom, _ effect: Effect?, line: UInt = #line) -> [CGRect] {
        guard case .refit(let seconds)? = effect else {
            XCTFail("no re-fit: \(String(describing: effect))", line: line)
            return []
        }
        XCTAssertEqual(seconds, AnnotatorZoom.stepSeconds, line: line)
        var frames: [CGRect] = []
        for progress: CGFloat in [0, 0.25, 0.5, 0.75, 1] {
            guard case .place(let frame, let picture, let barTop)? = zoom.reduce(.refitTick(progress)) else {
                XCTFail("tick \(progress) placed nothing", line: line)
                continue
            }
            XCTAssertTrue(picture.minX <= 1e-6 && picture.minY <= 1e-6 && picture.maxX >= frame.width - 1e-6
                          && picture.maxY >= frame.height - 1e-6, "\(picture) does not cover \(frame.size)", line: line)
            XCTAssertLessThanOrEqual(barTop, frame.minY - bar.margin + 1e-6, "the bar at \(barTop) is over \(frame)", line: line)
            if let scale = zoom.pixelScale {
                let edges = [frame.minX, frame.maxX, frame.minY, frame.maxY].map { $0 * scale }
                XCTAssertFalse(edges.contains { abs($0 - $0.rounded()) > 1e-6 }, "\(frame) is off the pixel grid", line: line)
            }
            frames.append(frame)
        }
        return frames
    }

    func testARoomThatShrinksAndGrowsMidZoomKeepsTheMagnificationAndTheFrameInside() {
        var zoom = landed()
        zoom.pixelScale = 2
        settle(&zoom, zoom.reduce(.smart(at: CGPoint(x: 0.2, y: 0.3))))
        XCTAssertEqual(target(zoom.reduce(.zoomIn)), 2.5)
        _ = zoom.reduce(.tick(2.2))
        let shown = zoom.placed, center = zoom.center

        let shrink = zoom.reduce(.refit(fitted: dockFitted, room: dockRoom, bar: bar))
        XCTAssertEqual(zoom.level * dockFitted.width, 2.5 * fitted.width, accuracy: 1e-9, "the picture is drawn at another size")
        let frames = carry(&zoom, shrink)
        XCTAssertEqual(frames.first, shown.frame, "the re-fit did not start from the frame on screen")
        XCTAssertTrue(dockFrameRoom.contains(zoom.frame), "\(zoom.frame) left \(dockFrameRoom)")
        XCTAssertEqual(zoom.room, dockFrameRoom)
        XCTAssertGreaterThanOrEqual(zoom.barTop - bar.height, dockRoom.minY + bar.margin - 1e-6, "the bar is under the Dock")
        XCTAssertEqual(zoom.picture.width, 2.5 * fitted.width, accuracy: 1e-9)
        let kept = Zoom.clamped(center: center, camera: zoom.camera)
        XCTAssertEqual(zoom.center.x, kept.x, accuracy: 1e-9)
        XCTAssertEqual(zoom.center.y, kept.y, accuracy: 1e-9)

        let grow = zoom.reduce(.refit(fitted: fitted, room: room, bar: bar))
        XCTAssertEqual(zoom.level, 2.5, accuracy: 1e-9)
        _ = carry(&zoom, grow)
        assertEqual(zoom.frame, frameRoom)

        _ = zoom.reduce(.refit(fitted: dockFitted, room: dockRoom, bar: bar))
        _ = zoom.reduce(.refitTick(1))
        settle(&zoom, zoom.reduce(.fit))
        assertEqual(zoom.frame, dockFitted)
    }

    func testARoomThatShrinksUnderAZoomAtTheCapTakesTheNewCap() {
        var zoom = landed()
        for _ in 0..<40 { settle(&zoom, zoom.reduce(.zoomIn)) }
        _ = carry(&zoom, zoom.reduce(.refit(fitted: dockFitted, room: dockRoom, bar: bar)))
        XCTAssertEqual(zoom.level, dockFrameRoom.height / dockFitted.height * AnnotatorZoom.maxCanvasZoom, accuracy: 1e-9)
        assertEqual(zoom.frame, dockFrameRoom)
        XCTAssertNil(zoom.reduce(.zoomIn))
    }

    func testAnImageAtTheFitStaysAtTheFit() {
        var zoom = landed()
        _ = carry(&zoom, zoom.reduce(.refit(fitted: dockFitted, room: dockRoom, bar: bar)))
        XCTAssertEqual(zoom.level, 1)
        assertEqual(zoom.frame, dockFitted)
        XCTAssertEqual(zoom.barCenter, dockFitted.midX)
        XCTAssertEqual(zoom.barTop, dockFitted.minY - bar.margin)
    }

    func testARoomThatChangesBeforeTheFlightsImageHasGoneWaitsForIt() {
        var zoom = AnnotatorZoom()
        _ = zoom.reduce(.prepare(fitted: fitted, room: room, bar: bar))
        _ = zoom.reduce(.tick(1))
        XCTAssertNil(zoom.reduce(.refit(fitted: dockFitted, room: dockRoom, bar: bar)))
        XCTAssertNil(zoom.reduce(.landed))
        XCTAssertEqual(zoom.fitted, fitted)
        _ = carry(&zoom, zoom.reduce(.lifted))
        assertEqual(zoom.frame, dockFitted)

        _ = zoom.reduce(.prepare(fitted: fitted, room: room, bar: bar))
        XCTAssertNil(zoom.reduce(.refit(fitted: dockFitted, room: dockRoom, bar: bar)))
        XCTAssertNil(zoom.reduce(.lifted))
        _ = carry(&zoom, zoom.reduce(.landed))
        assertEqual(zoom.frame, dockFitted)

        _ = zoom.reduce(.prepare(fitted: fitted, room: room, bar: bar))
        XCTAssertNil(zoom.reduce(.refit(fitted: dockFitted, room: dockRoom, bar: bar)))
        XCTAssertNil(zoom.reduce(.close))
        XCTAssertNil(zoom.reduce(.landed))
        XCTAssertNil(zoom.reduce(.lifted))
        XCTAssertNil(zoom.reduce(.refit(fitted: dockFitted, room: dockRoom, bar: bar)))
        XCTAssertEqual(zoom.fitted, fitted)
    }

    func testACloseDuringARefitLetsItLandOnTheNewFittedFrameWithoutAJump() {
        var zoom = landed()
        _ = zoom.reduce(.refit(fitted: dockFitted, room: dockRoom, bar: bar))
        guard case .place(let before, _, _)? = zoom.reduce(.refitTick(0.4)) else { return XCTFail("no place") }
        XCTAssertNil(zoom.reduce(.close))
        XCTAssertTrue(zoom.refitting)
        guard case .place(let onTheWay, _, _)? = zoom.reduce(.refitTick(0.7)) else { return XCTFail("the close stopped the re-fit") }
        XCTAssertGreaterThan(abs(onTheWay.minY - dockFitted.minY), 1)
        XCTAssertLessThan(abs(onTheWay.minY - dockFitted.minY), abs(before.minY - dockFitted.minY))
        _ = zoom.reduce(.refitTick(1))
        XCTAssertFalse(zoom.refitting)
        assertEqual(zoom.placed.frame, dockFitted)

        var zoomed = landed()
        settle(&zoomed, zoomed.reduce(.smart(at: nil)))
        _ = zoomed.reduce(.refit(fitted: dockFitted, room: dockRoom, bar: bar))
        guard case .place(let drawn, _, _)? = zoomed.reduce(.refitTick(0.4)) else { return XCTFail("no place") }
        XCTAssertEqual(zoomed.reduce(.close), .spring(to: 1, seconds: AnnotatorZoom.fitToCloseSeconds))
        guard case .place(let first, _, _)? = zoomed.reduce(.tick(zoomed.level)) else { return XCTFail("no place") }
        assertEqual(first, drawn)
        _ = zoomed.reduce(.refitTick(0.8))
        _ = zoomed.reduce(.tick(1))
        _ = zoomed.reduce(.refitTick(1))
        assertEqual(zoomed.placed.frame, dockFitted)
    }

    func testAnUnchangedRoomAsksForNoRefit() {
        var zoom = landed()
        XCTAssertNil(zoom.reduce(.refit(fitted: fitted, room: room, bar: bar)))
    }
}
