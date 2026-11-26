import CoreGraphics
import XCTest

final class PinTeardropFacingTests: XCTestCase {
    func testATeardropTurnsAwayFromAPiecesNumber() {
        let pixels = PixelSize(width: 300, height: 200), tip = CGPoint(x: 150, y: 100)
        XCTAssertEqual(PinTeardrop.facing(tip: tip, side: 24, edge: 1.5, in: pixels), .upRight)
        XCTAssertEqual(PinTeardrop.facing(tip: tip, side: 24, edge: 1.5, in: pixels, avoiding: [CGRect(x: 160, y: 80, width: 10, height: 10)]), .downRight)
        XCTAssertEqual(PinTeardrop.facing(tip: tip, side: 24, edge: 1.5, in: pixels,
                                          avoiding: [CGRect(x: 153, y: 70, width: 40, height: 60)]), .upLeft)
    }

    func testAnAreaPinsTeardropStaysOutOfItsAreaAtThePicturesEdge() {
        let pixels = PixelSize(width: 300, height: 300)
        XCTAssertEqual(PinTeardrop.facing(tip: CGPoint(x: 300, y: 200), side: 24, edge: 1.5, in: pixels,
                                          area: CGRect(x: 200, y: 100, width: 100, height: 100)), .downLeft)
        XCTAssertEqual(PinTeardrop.facing(tip: CGPoint(x: 100, y: 0), side: 24, edge: 1.5, in: pixels,
                                          area: CGRect(x: 100, y: 0, width: 100, height: 100)), .downLeft)
        XCTAssertEqual(PinTeardrop.facing(tip: CGPoint(x: 100, y: 100), side: 24, edge: 1.5, in: pixels,
                                          area: CGRect(x: 100, y: 100, width: 100, height: 100)), .upRight)
    }
}
