import XCTest

final class AnnotatorZoomBarTests: XCTestCase {
    private let room = CGRect(x: 0, y: 77, width: 1377, height: 872)
    private let bar = ZoomBar(height: 44, margin: 9)
    private let wide = CGRect(x: 60, y: 373, width: 1257, height: 333)
    private let tall = CGRect(x: 558, y: 190, width: 262, height: 699)
    private var lowestFrameBottom: CGFloat { room.minY + bar.height + 2 * bar.margin }

    private func opened(_ fitted: CGRect) -> AnnotatorZoom {
        var zoom = AnnotatorZoom()
        _ = zoom.reduce(.prepare(fitted: fitted, room: room, bar: bar))
        _ = zoom.reduce(.tick(1))
        _ = zoom.reduce(.landed)
        return zoom
    }

    private func step(_ zoom: inout AnnotatorZoom, _ input: AnnotatorZoom.Input) -> [(frame: CGRect, barTop: CGFloat)] {
        guard case .spring(let to, _)? = zoom.reduce(input) else { return [] }
        let from = zoom.level
        var placed: [(frame: CGRect, barTop: CGFloat)] = []
        for part: CGFloat in [0.3, 0.6, 0.9, 1] {
            if case .place(let frame, _, let barTop)? = zoom.reduce(.tick(from + (to - from) * part)) {
                placed.append((frame, barTop))
            }
        }
        _ = zoom.reduce(.arrived)
        return placed
    }

    func testAFrameGrowingDownCarriesTheBarAndStopsItOneMarginAboveTheRoom() {
        for fitted in [wide, tall] {
            var zoom = opened(fitted)
            var lastTop = zoom.barTop
            var widthWhenTheBottomStopped: CGFloat?
            var barStillMovingOnceTheWidthFilled = false
            for _ in 0..<20 {
                for (frame, barTop) in step(&zoom, .zoomIn) {
                    XCTAssertEqual(barTop, frame.minY - bar.margin, accuracy: 1e-6, "\(fitted): the bar left the frame at \(frame)")
                    XCTAssertLessThanOrEqual(barTop, lastTop + 1e-6, "\(fitted): the bar rose while zooming in")
                    XCTAssertGreaterThanOrEqual(frame.minY, lowestFrameBottom - 1e-6, "\(fitted): \(frame) grew past the bar's floor")
                    if abs(frame.minY - lowestFrameBottom) < 1e-6, widthWhenTheBottomStopped == nil { widthWhenTheBottomStopped = frame.width }
                    if abs(frame.width - room.width) < 1e-6, frame.minY > lowestFrameBottom + 1 { barStillMovingOnceTheWidthFilled = true }
                    lastTop = barTop
                }
            }
            XCTAssertEqual(zoom.frame.minY, lowestFrameBottom, accuracy: 1e-6, "\(fitted)")
            XCTAssertEqual(zoom.barTop - bar.height, room.minY + bar.margin, accuracy: 1e-6, "\(fitted)")
            if fitted == tall {
                XCTAssertLessThan(widthWhenTheBottomStopped ?? .infinity, zoom.frame.width, "the sides stopped with the bottom edge")
            } else {
                XCTAssertTrue(barStillMovingOnceTheWidthFilled, "the bottom edge stopped with the sides")
            }
        }
    }

    func testZoomingOutCarriesTheBarBackAlongTheSamePath() {
        for fitted in [wide, tall] {
            var zoom = opened(fitted)
            var tops: [(level: CGFloat, barTop: CGFloat)] = []
            for _ in 0..<6 {
                _ = step(&zoom, .zoomIn)
                tops.append((zoom.level, zoom.barTop))
            }
            for (level, barTop) in tops.reversed().dropFirst() {
                _ = step(&zoom, .zoomOut)
                XCTAssertEqual(zoom.level, level, accuracy: 1e-9)
                XCTAssertEqual(zoom.barTop, barTop, accuracy: 1e-6, "\(fitted) at level \(level)")
            }
            _ = step(&zoom, .zoomOut)
            XCTAssertEqual(zoom.level, 1)
            XCTAssertEqual(zoom.frame, fitted)
            XCTAssertEqual(zoom.barTop, fitted.minY - bar.margin)
        }
    }

    func testAPullBelowTheFitLeavesTheBarInItsPlace() {
        var zoom = opened(tall)
        let placed = step(&zoom, .pinch(by: -0.4, at: CGPoint(x: 0.5, y: 0.9)))
        XCTAssertFalse(placed.isEmpty)
        XCTAssertGreaterThan(zoom.frame.minY, tall.minY)
        for (_, barTop) in placed { XCTAssertEqual(barTop, tall.minY - bar.margin) }
    }

    func testAFrameFittedBelowTheBarsFloorKeepsItsPlaceAndItsBottomEdge() {
        let low = CGRect(x: 400, y: room.minY + bar.height + bar.margin + 5, width: 500, height: 300)
        var zoom = opened(low)
        XCTAssertEqual(zoom.frame, low)
        XCTAssertEqual(zoom.room.minY, low.minY)
        for _ in 0..<10 {
            for (frame, barTop) in step(&zoom, .zoomIn) {
                XCTAssertEqual(frame.minY, low.minY, accuracy: 1e-6)
                XCTAssertEqual(barTop, low.minY - bar.margin, accuracy: 1e-6)
            }
        }
        XCTAssertGreaterThan(zoom.frame.height, low.height)
    }
}
