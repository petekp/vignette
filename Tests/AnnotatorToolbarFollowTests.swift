import XCTest

@MainActor
final class AnnotatorToolbarFollowTests: XCTestCase {
    private let gap: CGFloat = 9
    private let wide = NSRect(x: 60, y: 373, width: 1257, height: 333)
    private let tall = NSRect(x: 558, y: 190, width: 262, height: 699)

    func testATickForTheNextImageBeforeItsPlaceLeavesTheBarWhereItWas() {
        let toolbar = AnnotatorToolbar()
        toolbar.place(below: wide, gap: gap)
        let before = toolbar.panel.frame.origin
        toolbar.follow(top: tall.minY - 100, fitted: tall)
        XCTAssertEqual(toolbar.panel.frame.origin, before)
        XCTAssertNil(toolbar.carriedTop)
    }

    func testATickForTheImageTheBarIsPlacedUnderCarriesIt() {
        let toolbar = AnnotatorToolbar()
        toolbar.place(below: tall, gap: gap)
        let before = toolbar.panel.frame.origin
        toolbar.follow(top: tall.minY - gap - 100, fitted: tall)
        XCTAssertEqual(toolbar.carriedTop, tall.minY - gap - 100)
        XCTAssertEqual(toolbar.panel.frame.origin.y, before.y - 100)
    }
}
