import XCTest

/// A capture opens in the editor from the rect it was taken from, found from the poll's drag, the
/// window under the pointer, or the display, and from nothing that does not match the file's size.
final class CaptureRectTests: XCTestCase {
    private let laptop = CaptureRect.Display(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), scale: 2)
    private let monitor = CaptureRect.Display(frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), scale: 1)
    private let now = Date(timeIntervalSinceReferenceDate: 1000)

    private func locate(_ pixels: CGSize, drag: CaptureRect.Drag? = nil, cursor: CGPoint, window: CGRect? = nil,
                        at: Date? = nil) -> (rect: CGRect, kind: CaptureRect.Kind)? {
        CaptureRect.locate(pixels: pixels, arrivedAt: at ?? now, drag: drag, cursor: cursor, window: window,
                           displays: [laptop, monitor])
    }

    private func drag(_ press: CGPoint, _ release: CGPoint) -> CaptureRect.Drag {
        CaptureRect.Drag(press: press, release: release, at: now.addingTimeInterval(-0.15))
    }

    /// Measured with integer points: a drag from (180, 160) to (700, 480), top-left down, took 180
    /// to 701 by 160 to 481, so the point under the release is inside the capture.
    func testASelectionIsTheSameRectWhicheverWayItWasDragged() {
        let pixels = CGSize(width: 1042, height: 642)   // 521 by 321 points at scale 2
        let expected = CGRect(x: 180, y: 501, width: 521, height: 321)   // Cocoa: y up from the bottom
        let topLeft = CGPoint(x: 180, y: 822), bottomRight = CGPoint(x: 700, y: 502)
        let topRight = CGPoint(x: 700, y: 822), bottomLeft = CGPoint(x: 180, y: 502)
        for (press, release) in [(topLeft, bottomRight), (bottomRight, topLeft), (topRight, bottomLeft), (bottomLeft, topRight)] {
            let found = locate(pixels, drag: drag(press, release), cursor: release)
            XCTAssertEqual(found?.kind, .selection, "\(press) to \(release)")
            XCTAssertEqual(found?.rect, expected, "\(press) to \(release)")
        }
    }

    func testAPressThePollSawLateStillMatchesSinceTheRectComesFromTheRelease() {
        let found = locate(CGSize(width: 1042, height: 642), drag: drag(CGPoint(x: 190, y: 815), CGPoint(x: 700, y: 502)),
                           cursor: CGPoint(x: 700, y: 502))
        XCTAssertEqual(found?.rect, CGRect(x: 180, y: 501, width: 521, height: 321))
    }

    func testADragOfAnotherSizeOrFromLongAgoIsNotTheCapture() {
        let pixels = CGSize(width: 1042, height: 642)
        let release = CGPoint(x: 700, y: 502)
        XCTAssertNil(locate(pixels, drag: drag(CGPoint(x: 400, y: 700), release), cursor: release),
                     "a drag far smaller than the file")
        let old = CaptureRect.Drag(press: CGPoint(x: 180, y: 822), release: release, at: now.addingTimeInterval(-10))
        XCTAssertNil(locate(pixels, drag: old, cursor: release), "a drag from before this capture")
        let later = CaptureRect.Drag(press: CGPoint(x: 180, y: 822), release: release, at: now.addingTimeInterval(1))
        XCTAssertNil(locate(pixels, drag: later, cursor: release), "a drag released after the file arrived")
    }

    func testAWindowCaptureIsTheWindowOrTheWindowAndItsShadow() {
        let window = CGRect(x: 90, y: 91, width: 1351, height: 770)
        let cursor = CGPoint(x: 600, y: 400)
        // A click to choose the window is a drag of no size, which matches nothing.
        let click = drag(cursor, cursor)
        let bare = locate(CGSize(width: 2702, height: 1540), drag: click, cursor: cursor, window: window)
        XCTAssertEqual(bare?.kind, .window)
        XCTAssertEqual(bare?.rect, window)
        // Measured with ⌘⇧4's window mode: 34 to each side, 26 above and 42 below for an inactive
        // window, and 56, 38 and 74 for the active one.
        let inactive = locate(CGSize(width: 2838, height: 1676), drag: click, cursor: cursor, window: window)
        XCTAssertEqual(inactive?.kind, .window)
        XCTAssertEqual(inactive?.rect, CGRect(x: 56, y: 49, width: 1419, height: 838))
        let active = locate(CGSize(width: 2926, height: 1764), drag: click, cursor: cursor, window: window)
        XCTAssertEqual(active?.rect, CGRect(x: 34, y: 17, width: 1463, height: 882))
        XCTAssertNil(locate(CGSize(width: 1000, height: 600), cursor: cursor, window: window), "another size")
    }

    func testAFullScreenCaptureIsTheDisplayUnderThePointerAtThatDisplaysScale() {
        let onLaptop = locate(CGSize(width: 3024, height: 1964), cursor: CGPoint(x: 700, y: 500))
        XCTAssertEqual(onLaptop?.kind, .display)
        XCTAssertEqual(onLaptop?.rect, laptop.frame)
        let onMonitor = locate(CGSize(width: 1920, height: 1080), cursor: CGPoint(x: 2000, y: 500))
        XCTAssertEqual(onMonitor?.rect, monitor.frame)
        XCTAssertNil(locate(CGSize(width: 1920, height: 1080), cursor: CGPoint(x: 700, y: 500)),
                     "the monitor's size, taken while the pointer is on the laptop")
    }

    func testASelectionOnTheMonitorIsInItsPoints() {
        let press = CGPoint(x: 1600, y: 900), release = CGPoint(x: 1900, y: 700)
        let found = locate(CGSize(width: 301, height: 201), drag: drag(press, release), cursor: release)
        XCTAssertEqual(found?.rect, CGRect(x: 1600, y: 699, width: 301, height: 201))
    }
}
