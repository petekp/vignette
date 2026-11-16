import XCTest

final class LiveWindowsLiftTests: XCTestCase {
    func testAnOverlayLiftedAsTheKeysGoBackStaysUpWhileNothingCoversItsWindow() {
        let lift = LiveWindows.Lift(cause: .keysBack, since: 10)
        XCTAssertFalse(lift.ends(coveredByAnotherApp: false, at: 10.02), "the app brings its window forward about 20 ms later")
        XCTAssertFalse(lift.ends(coveredByAnotherApp: false, at: 10 + LiveWindows.Lift.limit))
        XCTAssertTrue(lift.ends(coveredByAnotherApp: false, at: 10 + LiveWindows.Lift.limit + 0.01))
        XCTAssertTrue(lift.ends(coveredByAnotherApp: true, at: 10.02), "another app's window over it covers its marks at once")
    }

    func testAnOverlayLiftedAsItsAppComesForwardGoesDownOnceTheAppHasRaisedItsWindow() {
        let lift = LiveWindows.Lift(cause: .activating, since: 10)
        XCTAssertFalse(lift.ends(coveredByAnotherApp: true, at: 10.1))
        XCTAssertTrue(lift.ends(coveredByAnotherApp: false, at: 10.1))
        XCTAssertTrue(lift.ends(coveredByAnotherApp: true, at: 10 + LiveWindows.Lift.limit + 0.01))
    }
}
