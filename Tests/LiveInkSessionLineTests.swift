import XCTest

final class LiveInkSessionLineTests: XCTestCase {
    private func packet() throws -> LivePacket {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let capture = try XCTUnwrap(context.makeImage())
        return LivePacket(frame: CGRect(x: 100, y: 200, width: 400, height: 300), windowID: 7, app: "Google Chrome",
                          title: "Postcard", location: nil, page: nil, lines: [], picture: Data(), numbers: [:], detail: nil,
                          luminance: nil, capture: capture, windows: [], alone: [], subject: .window(7), shownRegions: nil)
    }

    func testAnAskWithoutInkGivesThePointerInPercentagesOfThePicture() throws {
        XCTAssertEqual(try packet().sessionLine(note: "What is this", numbered: false, pointer: CGPoint(x: 396, y: 296)),
                       "What is this. Asked with Vignette's live ink, without drawing, about Google Chrome, \"Postcard\". "
                       + "The pointer was at 74% across and 32% down the picture.")
    }

    func testAPointerOffThePictureIsLeftOut() throws {
        XCTAssertEqual(try packet().sessionLine(note: "What is this", numbered: false, pointer: CGPoint(x: 50, y: 296)),
                       "What is this. Asked with Vignette's live ink, without drawing, about Google Chrome, \"Postcard\".")
    }

    func testAnAskWithInkSaysNothingOfThePointer() throws {
        XCTAssertEqual(try packet().sessionLine(note: "Move these up", numbered: false, pointer: nil),
                       "Move these up. Drawn with Vignette's live ink on Google Chrome, \"Postcard\".")
    }
}
