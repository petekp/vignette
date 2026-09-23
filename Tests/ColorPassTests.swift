import AppKit
import XCTest

final class ColorPassTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("color-pass-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    private let white: (UInt8, UInt8, UInt8) = (255, 255, 255)
    private let grey: (UInt8, UInt8, UInt8) = (128, 128, 128)
    private let red: (UInt8, UInt8, UInt8) = (0xe0, 0x31, 0x31)
    private let darkRed: (UInt8, UInt8, UInt8) = (0x7a, 0x12, 0x12)

    /// A 300 by 200 screenshot, under the sample's long side, so it is sampled pixel for pixel.
    private func sample(_ color: (Int, Int) -> (UInt8, UInt8, UInt8)) throws -> ColorSample {
        let sRGB = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        return try XCTUnwrap(ColorSample(imageAt: writeTestImage(width: 300, height: 200, space: sRGB, in: dir, color: color)))
    }

    private func pick(_ geometry: Mark.Geometry, on sample: ColorSample) -> MarkColor {
        sample.pick(for: Mark(geometry: geometry), pointScale: 1, style: .standard)
    }

    func testRedStaysRedOverWhiteAndOverGrey() throws {
        let halves = try sample { x, _ in x < 150 ? self.white : self.grey }
        for left in [10, 160] as [CGFloat] {
            XCTAssertEqual(pick(.rectangle(CGRect(x: left, y: 20, width: 120, height: 150)), on: halves), .red)
            XCTAssertEqual(pick(.ellipse(CGRect(x: left, y: 20, width: 120, height: 150)), on: halves), .red)
            XCTAssertEqual(pick(.arrow(Mark.Arrow(start: CGPoint(x: left, y: 30), end: CGPoint(x: left + 120, y: 170))), on: halves), .red)
            XCTAssertEqual(pick(.text(Mark.Text(origin: CGPoint(x: left, y: 80), text: "Here", size: 24)), on: halves), .red)
        }
    }

    func testAMarkOverARedRegionMovesOffRed() throws {
        let halves = try sample { x, _ in x < 150 ? self.red : self.darkRed }
        XCTAssertEqual(pick(.rectangle(CGRect(x: 10, y: 20, width: 120, height: 150)), on: halves), .yellow)
        XCTAssertEqual(pick(.rectangle(CGRect(x: 160, y: 20, width: 120, height: 150)), on: halves), .yellow, "dark red is too near red as well")
    }

    func testAnArrowIsSampledAlongItsArc() throws {
        // White, with a red block on the middle of the line between the arrow's ends.
        let block = CGRect(x: 100, y: 80, width: 100, height: 40)
        let blocked = try sample { x, y in block.contains(CGPoint(x: x, y: y)) ? self.red : self.white }
        let straight = Mark.Arrow(start: CGPoint(x: 20, y: 100), end: CGPoint(x: 280, y: 100))
        XCTAssertEqual(pick(.arrow(straight), on: blocked), .yellow)
        var bent = straight
        bent.bend = 80
        XCTAssertEqual(pick(.arrow(bent), on: blocked), .red, "the arc runs over white, around the block")
    }

    func testATextIsSampledOverEachOfItsLinesRatherThanItsBox() throws {
        let text = Mark.Text(origin: CGPoint(x: 20, y: 20), text: "A first line of words\nhi", size: 20)
        let layout = TextLayout(text, imageWidth: 300, pointScale: 1, style: .standard)
        XCTAssertEqual(layout.lines.count, 2)
        // Red fills the box beside the short second line, where no letter is.
        let short = layout.lines[1].rect
        let besideLetters = CGRect(x: short.maxX + 2, y: short.minY, width: layout.box.maxX - short.maxX - 2, height: short.height)
        let beside = try sample { x, y in besideLetters.contains(CGPoint(x: x, y: y)) ? self.red : self.white }
        XCTAssertEqual(pick(.text(text), on: beside), .red)
        let under = try sample { x, y in short.contains(CGPoint(x: x, y: y)) ? self.red : self.white }
        XCTAssertEqual(pick(.text(text), on: under), .yellow, "red under the letters of one line moves it")
    }

    /// Stripes of four of the colours: each of them is as near as can be, and light blue, 54 from
    /// the white, is the furthest of the five, though under the threshold.
    func testWhenNoColourIsFarEnoughThePickIsTheFurthest() throws {
        let stripes: [(UInt8, UInt8, UInt8)] = [red, (0xff, 0xc0, 0x34), (0xf3, 0xf3, 0xf3), (0xae, 0x3e, 0xc9)]
        let striped = try sample { x, _ in stripes[x / 75] }
        XCTAssertEqual(pick(.rectangle(CGRect(x: 0, y: 0, width: 300, height: 200)), on: striped), .lightBlue)
    }

    func testTheSampleIs320PxOnItsLongSideAsDisplayed() throws {
        let sRGB = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let url = try writeTestImage(width: 1600, height: 800, space: sRGB, orientation: 6, in: dir) { _, _ in self.white }
        let sample = try XCTUnwrap(ColorSample(imageAt: url))
        XCTAssertEqual(sample.pixels, PixelSize(width: 800, height: 1600), "turned for display")
        XCTAssertEqual([sample.width, sample.height], [160, 320])
        let small = try XCTUnwrap(ColorSample(imageAt: writeTestImage(width: 200, height: 100, space: sRGB, in: dir) { _, _ in self.white }))
        XCTAssertEqual([small.width, small.height], [200, 100], "never enlarged")
    }
}
