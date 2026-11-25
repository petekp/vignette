import AppKit
import XCTest

@MainActor
final class PinDrawingTests: XCTestCase {
    private var dir: URL!
    private var drawings: Drawings!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-pin-drawings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        drawings = Drawings(store: DrawingStore(directory: dir.appendingPathComponent("drawings")))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func pinned(_ name: String = "Pinned") throws -> (shot: URL, drawing: Drawing) {
        let made = try writeTestImage(width: 300, height: 200, space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), in: dir) { _, _ in (0, 0, 255) }
        let shot = dir.appendingPathComponent("\(name).png")
        try FileManager.default.moveItem(at: made, to: shot)
        let pin = Pin(id: UUID(), number: 1, place: .point(CGPoint(x: 100, y: 150)), comments: [Pin.Comment(text: "Too tight")])
        return (shot, Drawing(key: shot.path, pixels: PixelSize(width: 300, height: 200), pointScale: 1, marks: [], pins: [pin], nextPin: 2))
    }

    private func isRed(_ image: NSBitmapImageRep, at point: CGPoint) -> Bool {
        guard let color = image.colorAt(x: Int(point.x), y: Int(point.y))?.usingColorSpace(.sRGB) else { return false }
        return color.redComponent > 0.6 && color.blueComponent < 0.4
    }

    private func bodyPoint(of drawing: Drawing, at scale: CGFloat = 1) throws -> CGPoint {
        let pin = try XCTUnwrap(drawing.pins.first)
        let square = PinTeardrop(pin, in: drawing.pixels, pointScale: drawing.pointScale, edgeWidth: MarkStyle.standard.edgeWidth).square
        return CGPoint(x: (square.minX + square.width * 0.2) * scale, y: square.midY * scale)
    }

    func testARenderingDrawsThePinsTeardropOverThePicture() throws {
        let (shot, drawing) = try pinned()
        let image = try XCTUnwrap(NSBitmapImageRep(data: Rendering.png(of: drawing, imageAt: shot, style: .standard, markStyle: .standard)))
        XCTAssertTrue(isRed(image, at: try bodyPoint(of: drawing)))
        XCTAssertFalse(isRed(image, at: CGPoint(x: 250, y: 50)))
    }

    func testADrawingHoldingOnlyPinsFollowsARename() throws {
        let (shot, drawing) = try pinned()
        drawings.write(drawing, reason: "saved")
        let renamed = dir.appendingPathComponent("Renamed.png")
        try FileManager.default.moveItem(at: shot, to: renamed)
        drawings.rename(from: shot.screenshotKey, to: renamed.screenshotKey, style: .standard)
        XCTAssertEqual(drawings.current(of: renamed.screenshotKey, style: .standard)?.pins, drawing.pins)
        XCTAssertNil(drawings.current(of: shot.screenshotKey, style: .standard))
    }

    func testADrawingHoldingOnlyPinsComesBackWithTrashUndo() throws {
        let (shot, drawing) = try pinned()
        drawings.write(drawing, reason: "saved")
        let saved = try XCTUnwrap(drawings.saved(of: shot.screenshotKey, style: .standard))
        drawings.remove([shot.screenshotKey])
        XCTAssertNil(drawings.current(of: shot.screenshotKey, style: .standard))
        drawings.write(saved.drawing, message: saved.message, history: saved.history, reason: "put back")
        let back = try XCTUnwrap(drawings.current(of: shot.screenshotKey, style: .standard))
        XCTAssertEqual(back.pins, drawing.pins)
        XCTAssertEqual(back.nextPin, 2)
    }

    func testADrawingHoldingOnlyPinsGoesIntoItsStitchPiece() throws {
        let (shot, drawing) = try pinned()
        let (other, _) = try pinned("Other")
        drawings.write(drawing, reason: "saved")
        let pieces = [shot, other].map { Stitch.Piece(url: $0, drawing: drawings.current(of: $0.screenshotKey, style: .standard)) }
        XCTAssertEqual(pieces[0].drawing?.pins, drawing.pins)
        let composed = try XCTUnwrap(Stitch.compose(pieces, style: .standard, markStyle: .standard, longSideLimit: 10_000))
        let image = try XCTUnwrap(NSBitmapImageRep(data: composed.png))
        let plan = Stitch.layout([CGSize(width: 300, height: 200), CGSize(width: 300, height: 200)])
        let scale = composed.size.width / plan.size.width
        let body = try bodyPoint(of: drawing)
        let at = { (frame: CGRect) in CGPoint(x: (frame.minX + body.x) * scale, y: (frame.minY + body.y) * scale) }
        XCTAssertTrue(isRed(image, at: at(plan.frames[0])))
        XCTAssertFalse(isRed(image, at: at(plan.frames[1])))
    }

    func testAPinChangesTheFingerprintOfWhatTheAgentSent() throws {
        let (shot, drawing) = try pinned()
        Agent.record(sentDrawing: nil, on: shot)
        defer { Agent.forgetSentDrawing(on: shot) }
        var empty = drawing
        empty.pins = []
        XCTAssertTrue(Agent.hasSentDrawing(empty, at: shot))
        XCTAssertFalse(Agent.hasSentDrawing(drawing, at: shot))
        Agent.record(sentDrawing: drawing, on: shot)
        var moved = drawing
        moved.pins[0].place = .point(CGPoint(x: 120, y: 150))
        XCTAssertTrue(Agent.hasSentDrawing(drawing, at: shot))
        XCTAssertFalse(Agent.hasSentDrawing(moved, at: shot))
    }
}
