import XCTest

@MainActor
final class PinNumberingTests: XCTestCase {
    private var dir: URL!
    private var store: DrawingStore!
    private let pixels = PixelSize(width: 800, height: 600)

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-pin-numbering-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = DrawingStore(directory: dir.appendingPathComponent("drawings"))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func shot(_ name: String) throws -> String {
        let url = dir.appendingPathComponent(name)
        try Data("png".utf8).write(to: url)
        return url.path
    }

    private func pin(_ number: Int) -> Pin {
        Pin(id: UUID(), number: number, place: .point(CGPoint(x: 100, y: 100)), comments: [Pin.Comment(text: "Pin \(number)")])
    }

    func testAPinPostedAfterEveryPinWasDeletedTakesTheNumberAfterTheLastOne() throws {
        let key = try shot("Message.png")
        let drawings = Drawings(store: store)
        drawings.handOver(Drawing(key: key, pixels: pixels, pointScale: 1, marks: [], pins: [pin(1), pin(2), pin(3)], nextPin: 4),
                          message: "Look here", reason: "saved")
        drawings.handOver(Drawing(key: key, pixels: pixels, pointScale: 1, marks: [], nextPin: 4), message: "Look here", reason: "saved")
        let screenshot = ScreenshotKey(asGiven: key)
        XCTAssertNil(drawings.read(screenshot, pixels: pixels, style: .standard))
        let numbering = try XCTUnwrap(drawings.numbering(of: screenshot, pixels: pixels))
        var core = EditorCore()
        _ = core.reduce(.open(Drawing(key: key, pixels: pixels, pointScale: 1, marks: []).numbered(numbering), style: .standard,
                              metrics: .standard, markStyle: .standard))
        _ = core.reduce(.setTool(.comment))
        core.click(400, 300)
        _ = core.reduce(.composer(.changed("Again")))
        _ = core.reduce(.composer(.close))
        XCTAssertEqual(core.drawing.pins.map(\.number), [4])
    }

    func testAStitchWithoutPinsKeepsItsPieceNumbersForTheNextDrawing() throws {
        let key = try shot("Stitch.png")
        let badges = [CGRect(x: 10, y: 10, width: 30, height: 30), CGRect(x: 410, y: 10, width: 30, height: 30)]
        let drawings = Drawings(store: store)
        XCTAssertTrue(drawings.write(Drawing(key: key, pixels: pixels, pointScale: 1, marks: [], pieceNumbers: badges), reason: "stitched"))
        let screenshot = ScreenshotKey(asGiven: key)
        XCTAssertEqual(store.scan().drawings, [key])
        XCTAssertNil(drawings.read(screenshot, pixels: pixels, style: .standard))
        XCTAssertEqual(drawings.numbering(of: screenshot, pixels: pixels), Drawing.Numbering(nextPin: 1, pieceNumbers: badges))
        let renamed = ScreenshotKey(asGiven: try shot("Stitch renamed.png"))
        drawings.rename(from: screenshot, to: renamed, style: .standard)
        XCTAssertEqual(drawings.numbering(of: renamed, pixels: pixels)?.pieceNumbers, badges)
    }
}
