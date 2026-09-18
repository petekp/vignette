import XCTest

final class StitchTests: XCTestCase {
    private var dir: URL!
    /// A screenshot the size of a browser window on a Retina display, the usual piece.
    private let screenshot = CGSize(width: 1760, height: 1080)

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("stitch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    func testAStackOfTwoStaysAStackAndSixGoSideBySide() {
        XCTAssertEqual(Stitch.layout(Array(repeating: screenshot, count: 2)).columns, 1)
        XCTAssertEqual(Stitch.layout(Array(repeating: screenshot, count: 3)).columns, 1)
        XCTAssertEqual(Stitch.layout(Array(repeating: screenshot, count: 6)).columns, 2,
                       "a six-piece stack is so tall the long edge is capped before the pixels are used up")
    }

    /// The rule the layout exists for: whatever it picks, no other column count would leave more of
    /// the composition once a vision model has resized it.
    func testNoOtherColumnCountSurvivesTheResizeBetter() {
        let mixed = [screenshot, CGSize(width: 900, height: 1400), CGSize(width: 600, height: 400),
                     CGSize(width: 2400, height: 1000), CGSize(width: 1200, height: 1200), CGSize(width: 800, height: 600)]
        for sizes in [Array(repeating: screenshot, count: 4), mixed] {
            let chosen = Stitch.layout(sizes)
            for columns in 1...sizes.count {
                let other = Stitch.layout(sizes, columns: columns, gap: chosen.gap)
                XCTAssertLessThanOrEqual(other.readerScale, chosen.readerScale + 0.001,
                                         "\(columns) columns would keep more than the \(chosen.columns) chosen")
            }
        }
    }

    func testTheGapAndTheBadgeFollowThePieceTheyAreOn() {
        XCTAssertEqual(Stitch.gap(for: [screenshot]), 22, "2% of the 1080 pt side")
        XCTAssertEqual(Stitch.gap(for: [screenshot, CGSize(width: 300, height: 200)]), 12,
                       "the smallest piece decides, and a 4 pt gap is bounded up to 12")
        XCTAssertEqual(Stitch.badgeDiameter(for: screenshot), 65)
        XCTAssertEqual(Stitch.badgeDiameter(for: CGSize(width: 300, height: 200)), 32, "bounded up from 12")
    }

    func testPiecesAreDrawnInOrderEachWithItsOwnBadge() throws {
        let first = try piece(600, 400, .blue)
        let second = try piece(600, 400, .green)
        let composed = try XCTUnwrap(Stitch.compose([first, second], longSideLimit: 8192))
        let image = try XCTUnwrap(NSBitmapImageRep(data: composed.png))
        XCTAssertEqual(composed.size, CGSize(width: image.pixelsWide, height: image.pixelsHigh))

        let plan = Stitch.layout([CGSize(width: 600, height: 400), CGSize(width: 600, height: 400)])
        XCTAssertEqual(composed.size, plan.size, "nothing to scale: the composition is under the limit")
        XCTAssertEqual(strongest(image, at: CGPoint(x: plan.frames[0].midX, y: plan.frames[0].midY)), .blue)
        XCTAssertEqual(strongest(image, at: CGPoint(x: plan.frames[1].midX, y: plan.frames[1].midY)), .green,
                       "the second piece is below the first, not over it")

        // Each badge, red, sits inside its own piece's top-left corner.
        for frame in plan.frames {
            let diameter = Stitch.badgeDiameter(for: frame.size)
            // Left of the middle, so the number itself is not what gets sampled.
            XCTAssertEqual(strongest(image, at: CGPoint(x: frame.minX + diameter * 0.4, y: frame.minY + diameter * 0.75)), .red)
        }
    }

    func testACompositionLongerThanTheLimitIsScaledDownToIt() throws {
        let pieces = [try piece(600, 400, .blue), try piece(600, 400, .green)]
        let composed = try XCTUnwrap(Stitch.compose(pieces, longSideLimit: 400))
        XCTAssertEqual(max(composed.size.width, composed.size.height), 400)
        let full = Stitch.layout([CGSize(width: 600, height: 400), CGSize(width: 600, height: 400)]).size
        XCTAssertEqual(composed.size.width / composed.size.height, full.width / full.height, accuracy: 0.01,
                       "scaled down, not cropped or stretched")
    }

    /// A solid PNG on disk, one of the pieces a stitch is made of.
    private func piece(_ width: Int, _ height: Int, _ color: NSColor) throws -> URL {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        let url = dir.appendingPathComponent("\(UUID().uuidString).png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    private enum Channel { case red, green, blue, none }

    /// Which channel the pixel at `point` is made of. Channels rather than colour values: the
    /// composition is drawn in device RGB and read back through a colour space, which moves every
    /// component a little, but a blue piece stays blue. `point` is in the composition's own space:
    /// top-left origin, y down, as `Layout.frames` are.
    private func strongest(_ image: NSBitmapImageRep, at point: CGPoint) -> Channel {
        guard let pixel = image.colorAt(x: Int(point.x), y: Int(point.y)) else { return .none }
        let (r, g, b) = (pixel.redComponent, pixel.greenComponent, pixel.blueComponent)
        if r > g + 0.2 && r > b + 0.2 { return .red }
        if g > r + 0.2 && g > b + 0.2 { return .green }
        if b > r + 0.2 && b > g + 0.2 { return .blue }
        return .none
    }
}
