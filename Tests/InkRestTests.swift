import XCTest

final class InkRestTests: XCTestCase {
    func testInkLeftOnTheScreenSlowsToStillAfterItsLastStirAndWakesAtTheNext() {
        var rest = InkRest(stirredAt: 100)
        XCTAssertEqual(rest.drift(at: 100 + InkRest.awake), 1)
        let slowing = rest.drift(at: 100 + InkRest.awake + InkRest.fade / 2)
        XCTAssertGreaterThan(slowing, 0)
        XCTAssertLessThan(slowing, 1)
        XCTAssertEqual(rest.drift(at: 100 + InkRest.awake + InkRest.fade), 0)
        XCTAssertEqual(rest.drift(at: 10_000), 0)
        rest.stir(at: 10_000)
        XCTAssertEqual(rest.drift(at: 10_000), 1)
    }
}
