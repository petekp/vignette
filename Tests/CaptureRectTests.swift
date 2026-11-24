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

    private func recorded(_ rect: CGRect, _ kind: String, pixels: CGSize, age: TimeInterval = 0.2)
        -> (rect: CGRect, kind: CaptureRect.Kind)? {
        CaptureRect.recorded(CaptureRect.Recorded(rect: rect, kind: kind), pixels: pixels, age: age,
                             displays: [laptop, monitor], primaryHeight: laptop.frame.height)
    }

    func testTheRectMacOSRecordedIsTurnedIntoCocoaPoints() {
        let found = recorded(CGRect(x: 219, y: 91, width: 533, height: 813), "selection", pixels: CGSize(width: 1066, height: 1626))
        XCTAssertEqual(found?.kind, .selection)
        XCTAssertEqual(found?.rect, CGRect(x: 219, y: 78, width: 533, height: 813))
        let onMonitor = recorded(CGRect(x: 1600, y: 100, width: 301, height: 201), "window", pixels: CGSize(width: 301, height: 201))
        XCTAssertEqual(onMonitor?.kind, .window)
        XCTAssertEqual(onMonitor?.rect, CGRect(x: 1600, y: 681, width: 301, height: 201))
    }

    func testARecordedRectIsNotThisCapturesWhenTheFileIsOldOrAnotherSize() {
        let rect = CGRect(x: 219, y: 91, width: 533, height: 813)
        let pixels = CGSize(width: 1066, height: 1626)
        XCTAssertNil(recorded(rect, "selection", pixels: pixels, age: 60), "an old capture copied into the folder")
        XCTAssertNil(recorded(rect, "selection", pixels: CGSize(width: 533, height: 813)), "pixels at another scale")
        XCTAssertNil(recorded(rect, "touchbar", pixels: pixels), "a kind the flight does not know")
    }

    func testASelectionOnTheMonitorIsInItsPoints() {
        let press = CGPoint(x: 1600, y: 900), release = CGPoint(x: 1900, y: 700)
        let found = locate(CGSize(width: 301, height: 201), drag: drag(press, release), cursor: release)
        XCTAssertEqual(found?.rect, CGRect(x: 1600, y: 699, width: 301, height: 201))
    }

    private let herdr = CaptureRect.Window(app: "dev.herdr.app", frame: CGRect(x: 0, y: 0, width: 400, height: 400))
    private let codex = CaptureRect.Window(app: "com.openai.codex", frame: CGRect(x: 0, y: 0, width: 1000, height: 800))

    func testEachPointOfACaptureIsTheFrontmostWindowsThere() {
        let owners = CaptureRect.owners(of: CGRect(x: 100, y: 0, width: 400, height: 400), kind: .selection, windows: [herdr, codex])
        XCTAssertEqual(owners, [CaptureRect.Owner(app: "dev.herdr.app", share: 0.75), CaptureRect.Owner(app: "com.openai.codex", share: 0.25)])
        XCTAssertEqual(CaptureRect.owners(of: CGRect(x: 100, y: 0, width: 400, height: 400), kind: .selection, windows: [codex, herdr]),
                       [CaptureRect.Owner(app: "com.openai.codex", share: 1)], "a window behind shows nowhere")
    }

    func testTheLogNamesAtMostThreeAppsByShareOrSaysWhyThereAreNone() {
        let owners = [("a", 0.5), ("b", 0.25), ("c", 0.125), ("d", 0.125)].map { CaptureRect.Owner(app: $0.0, share: $0.1) }
        XCTAssertEqual(CaptureRect.logged(owners), "a:50%,b:25%,c:13%")
        XCTAssertEqual(CaptureRect.logged([]), "none")
        XCTAssertEqual(CaptureRect.logged(nil), "unlocated")
    }

    func testTheDesktopCountsForNobody() {
        XCTAssertEqual(CaptureRect.owners(of: CGRect(x: 800, y: 0, width: 400, height: 400), kind: .display, windows: [codex]),
                       [CaptureRect.Owner(app: "com.openai.codex", share: 1)])
        XCTAssertEqual(CaptureRect.owners(of: CGRect(x: 2000, y: 0, width: 400, height: 400), kind: .selection, windows: [codex]), [])
    }

    func testAWindowCaptureIsItsOneWindowEvenUnderAnother() {
        XCTAssertEqual(CaptureRect.owners(of: herdr.frame, kind: .window, windows: [codex, herdr]),
                       [CaptureRect.Owner(app: "dev.herdr.app", share: 1)])
        let shadow = CaptureRect.shadows[0]
        let shadowed = CGRect(x: -shadow.left, y: -shadow.bottom, width: 400 + shadow.left + shadow.right,
                              height: 400 + shadow.top + shadow.bottom)
        XCTAssertEqual(CaptureRect.owners(of: shadowed, kind: .window, windows: [codex, herdr]),
                       [CaptureRect.Owner(app: "dev.herdr.app", share: 1)], "with Apple's shadow")
    }
}
