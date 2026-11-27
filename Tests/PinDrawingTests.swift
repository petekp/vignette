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

    private func pinned(_ name: String = "Pinned", width: Int = 300, height: Int = 200,
                        pins: [Pin] = [Pin(id: UUID(), number: 1, place: .point(CGPoint(x: 100, y: 150)), comments: [Pin.Comment(text: "Too tight")])])
        throws -> (shot: URL, drawing: Drawing) {
        let made = try writeTestImage(width: width, height: height, space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), in: dir) { _, _ in (0, 0, 255) }
        let shot = dir.appendingPathComponent("\(name).png")
        try FileManager.default.moveItem(at: made, to: shot)
        return (shot, Drawing(key: shot.path, pixels: PixelSize(width: width, height: height), pointScale: 1, marks: [], pins: pins,
                              nextPin: (pins.map(\.number).max() ?? 0) + 1))
    }

    private func pin(_ number: Int, _ place: Pin.Place, _ text: String = "Too tight") -> Pin {
        Pin(id: UUID(), number: number, place: place, comments: [Pin.Comment(text: text)])
    }

    private func isBlue(_ image: NSBitmapImageRep, at point: CGPoint) -> Bool {
        guard let color = image.colorAt(x: Int(point.x), y: Int(point.y))?.usingColorSpace(.sRGB) else { return false }
        return color.blueComponent > 0.8 && color.redComponent < 0.2
    }

    private func isWhite(_ image: NSBitmapImageRep, at point: CGPoint) -> Bool {
        guard let color = image.colorAt(x: Int(point.x), y: Int(point.y))?.usingColorSpace(.sRGB) else { return false }
        return min(color.redComponent, color.greenComponent, color.blueComponent) > 0.97
    }

    private func hasInk(_ image: NSBitmapImageRep, in rect: CGRect) -> Bool {
        stride(from: Int(rect.minX), to: Int(rect.maxX), by: 1).contains { x in
            stride(from: Int(rect.minY), to: Int(rect.maxY), by: 1).contains { y in
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
                return max(color.redComponent, color.greenComponent, color.blueComponent) < 0.3
            }
        }
    }

    private func isRed(_ image: NSBitmapImageRep, at point: CGPoint) -> Bool {
        guard let color = image.colorAt(x: Int(point.x), y: Int(point.y))?.usingColorSpace(.sRGB) else { return false }
        return color.redComponent > 0.6 && color.blueComponent < 0.4
    }

    private func bodyPoint(of drawing: Drawing, at scale: CGFloat = 1) throws -> CGPoint {
        let pin = try XCTUnwrap(drawing.pins.first)
        let square = PinTeardrop(pin, in: drawing.pixels, pointScale: drawing.pointScale, markStyle: MarkStyle.standard).square
        return CGPoint(x: (square.minX + square.width * 0.2) * scale, y: square.midY * scale)
    }

    func testARenderingDrawsThePinsTeardropOverThePicture() throws {
        let (shot, drawing) = try pinned()
        let image = try XCTUnwrap(NSBitmapImageRep(data: Rendering.png(of: drawing, imageAt: shot, style: .standard, markStyle: .standard)))
        XCTAssertTrue(isRed(image, at: try bodyPoint(of: drawing)))
        XCTAssertFalse(isRed(image, at: CGPoint(x: 250, y: 50)))
    }

    func testAtZoomOneOnADrawingOfPointScaleOneTheEditorDrawsATeardropOnThePixelsTheRenderingDraws() throws {
        let (shot, drawing) = try pinned()
        let rendering = try XCTUnwrap(NSBitmapImageRep(data: Rendering.png(of: drawing, imageAt: shot, style: .standard, markStyle: .standard)))
        var core = EditorCore()
        _ = core.reduce(.open(drawing, style: .standard, metrics: .standard, markStyle: .standard))
        _ = core.reduce(.viewChanged(visible: CGRect(x: 0, y: 0, width: 300, height: 200)))
        _ = core.reduce(.zoomChanged(1))
        let pins = EditorPins()
        pins.setScale(1)
        pins.show(EditorPins.Shown(placement: core.pinPlacement, outlined: [], marching: [], selected: [], markStyle: .standard,
                                   outlineWidth: 1, marchSpeed: 0, transform: .identity))
        let context = try XCTUnwrap(CGContext(data: nil, width: 300, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
        context.translateBy(x: 0, y: 200)
        context.scaleBy(x: 1, y: -1)
        pins.layer.render(in: context)
        let editor = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
        let square = PinTeardrop(try XCTUnwrap(drawing.pins.first), in: drawing.pixels, pointScale: 1, markStyle: MarkStyle.standard).square
        let points = stride(from: square.minX - 4, through: square.maxX + 4, by: 2).flatMap { x in
            stride(from: square.minY - 4, through: square.maxY + 4, by: 2).map { CGPoint(x: x, y: $0) }
        }
        let redInRendering = points.filter { isRed(rendering, at: $0) }
        XCTAssertGreaterThan(redInRendering.count, 20)
        let redInEither = points.filter { isRed(rendering, at: $0) || isRed(editor, at: $0) }
        let redInBoth = redInEither.filter { isRed(rendering, at: $0) && isRed(editor, at: $0) }
        XCTAssertGreaterThan(Double(redInBoth.count) / Double(redInEither.count), 0.9)
        XCTAssertFalse(isRed(editor, at: CGPoint(x: 250, y: 50)))
    }

    func testAFlightsPinsGrowFromTheCardsSizeToTheEditorsAndMeetEachEndExactly() {
        let growth = MarkLayers.PinGrowth(from: .init(zoom: 0.1, editor: false), to: .init(zoom: 0.4, editor: true))
        XCTAssertEqual(growth.growth(atZoom: 0.1, pointScale: 2), 1, accuracy: 0.0001)
        XCTAssertEqual(growth.growth(atZoom: 0.4, pointScale: 2) * 2 * 0.4, 1, accuracy: 0.0001)
        let halfway = growth.growth(atZoom: 0.25, pointScale: 2) * 2 * 0.25
        XCTAssertEqual(halfway, (0.2 + 1) / 2, accuracy: 0.0001)
        let home = MarkLayers.PinGrowth(from: growth.to, to: growth.from)
        XCTAssertEqual(home.growth(atZoom: 0.25, pointScale: 2), growth.growth(atZoom: 0.25, pointScale: 2), accuracy: 0.0001)
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

    func testAStitchMakesItsPiecesPinsItsOwnInPieceOrderWithoutDrawingThem() throws {
        let area = CGRect(x: 20, y: 20, width: 60, height: 40)
        let (shot, drawing) = try pinned(pins: [pin(5, .area(area, tip: .topLeft), "Second"), pin(2, .point(CGPoint(x: 100, y: 150)), "First")])
        let (other, otherDrawing) = try pinned("Other", pins: [pin(1, .point(CGPoint(x: 200, y: 50)), "Third")])
        let composed = try XCTUnwrap(Stitch.compose([Stitch.Piece(url: shot, drawing: drawing), Stitch.Piece(url: other, drawing: otherDrawing)],
                                                    style: .standard, markStyle: .standard, longSideLimit: 10_000))
        XCTAssertEqual(composed.pins.map(\.number), [1, 2, 3])
        XCTAssertEqual(composed.pins.map { $0.comments.map(\.text) }, [["First"], ["Second"], ["Third"]])
        XCTAssertTrue(Set(composed.pins.map(\.id)).isDisjoint(with: (drawing.pins + otherDrawing.pins).map(\.id)))
        let plan = Stitch.layout([CGSize(width: 300, height: 200), CGSize(width: 300, height: 200)])
        let scale = composed.size.width / plan.size.width
        XCTAssertEqual(composed.pins[0].tip.x, (plan.frames[0].minX + 100) * scale, accuracy: 0.01)
        XCTAssertEqual(composed.pins[2].tip.y, (plan.frames[1].minY + 50) * scale, accuracy: 0.01)
        guard case .area(let moved, _) = composed.pins[1].place else { return XCTFail("the area pin lost its area") }
        XCTAssertEqual(moved.width, 60 * scale, accuracy: 0.01)
        XCTAssertEqual(composed.badges.count, 2)
        XCTAssertEqual(composed.badges[1].minY, plan.frames[1].minY * scale + composed.badges[1].height / 4, accuracy: 0.01)
        let image = try XCTUnwrap(NSBitmapImageRep(data: composed.png))
        let body = try bodyPoint(of: Drawing(key: "", pixels: drawing.pixels, pointScale: 1, marks: [], pins: [drawing.pins[1]]))
        XCTAssertFalse(isRed(image, at: CGPoint(x: (plan.frames[0].minX + body.x) * scale, y: (plan.frames[0].minY + body.y) * scale)))
    }

    func testAStitchIsRefusedWhenAPieceHoldingPinsCannotBeRead() throws {
        let (shot, drawing) = try pinned()
        let (other, _) = try pinned("Other", pins: [])
        let unreadable = dir.appendingPathComponent("Gone.png")
        try Data("not an image".utf8).write(to: unreadable)
        let pieces = [Stitch.Piece(url: shot, drawing: drawing), Stitch.Piece(url: unreadable, drawing: nil), Stitch.Piece(url: other, drawing: nil)]
        let composed = try XCTUnwrap(Stitch.compose(pieces, style: .standard, markStyle: .standard, longSideLimit: 10_000))
        XCTAssertEqual(composed.unread, [unreadable])
        XCTAssertEqual(Stitch.refusal(pieces, composed)?.piece, unreadable)
        let unpinned = [Stitch.Piece(url: shot, drawing: nil)] + pieces.dropFirst()
        XCTAssertNil(Stitch.refusal(unpinned, try XCTUnwrap(Stitch.compose(unpinned, style: .standard, markStyle: .standard, longSideLimit: 10_000))))

        let crowded = try [pinned("Fifty", pins: (1...50).map { pin($0, .point(CGPoint(x: 100, y: 100))) }),
                           pinned("Fifty more", pins: (1...50).map { pin($0, .point(CGPoint(x: 100, y: 100))) })]
            .map { Stitch.Piece(url: $0.shot, drawing: $0.drawing) }
        let tooMany = try XCTUnwrap(Stitch.compose(crowded, style: .standard, markStyle: .standard, longSideLimit: 10_000))
        XCTAssertEqual(Stitch.refusal(crowded, tooMany)?.reason, "A stitch holds up to 99 pins. These hold 100.")
    }

    func testACopiedRenderingListsTheCommentsBelowAWideScreenshotAndBesideATallOne() throws {
        let (shot, drawing) = try pinned()
        let image = try XCTUnwrap(NSBitmapImageRep(data: Rendering.png(of: drawing, imageAt: shot, style: .standard, markStyle: .standard,
                                                                       layout: .withComments(textSize: 17))))
        XCTAssertEqual(image.pixelsWide, 300)
        XCTAssertGreaterThan(image.pixelsHigh, 200)
        XCTAssertTrue(isBlue(image, at: CGPoint(x: 250, y: 50)))
        XCTAssertTrue(isRed(image, at: try bodyPoint(of: drawing)))
        XCTAssertTrue(isRed(image, at: CGPoint(x: 17 + 24 * 0.2, y: 200 + 17 + 17 * 0.6 + 12)), "the row starts with the pin's teardrop")
        XCTAssertTrue(hasInk(image, in: CGRect(x: 60, y: 200, width: 240, height: image.pixelsHigh - 200)), "the comment is written")
        XCTAssertTrue(isWhite(image, at: CGPoint(x: 290, y: image.pixelsHigh - 3)))

        let (tallShot, tall) = try pinned("Tall", width: 200, height: 300)
        let beside = try XCTUnwrap(NSBitmapImageRep(data: Rendering.png(of: tall, imageAt: tallShot, style: .standard, markStyle: .standard,
                                                                        layout: .withComments(textSize: 17))))
        XCTAssertEqual(beside.pixelsHigh, 300)
        XCTAssertGreaterThan(beside.pixelsWide, 200)
        XCTAssertTrue(isBlue(beside, at: CGPoint(x: 150, y: 250)))
        XCTAssertTrue(hasInk(beside, in: CGRect(x: 240, y: 0, width: beside.pixelsWide - 240, height: 80)))
    }

    func testADrawingWithoutPinsCopiesAtTheScreenshotsSize() throws {
        let (shot, pinnedDrawing) = try pinned()
        var drawing = pinnedDrawing
        drawing.pins = []
        drawing.marks = [Mark(geometry: .rectangle(CGRect(x: 30, y: 20, width: 40, height: 30)))]
        let copied = try XCTUnwrap(NSBitmapImageRep(data: Rendering.png(of: drawing, imageAt: shot, style: .standard, markStyle: .standard,
                                                                        layout: .withComments(textSize: 17))))
        XCTAssertEqual([copied.pixelsWide, copied.pixelsHigh], [300, 200])
        XCTAssertTrue(isRed(copied, at: CGPoint(x: 30, y: 35)))
    }

    func testAMarkOnTheEdgeStaysOutOfTheCommentList() throws {
        let (shot, pinnedDrawing) = try pinned()
        var drawing = pinnedDrawing
        drawing.marks = [Mark(geometry: .rectangle(CGRect(x: 0, y: 150, width: 300, height: 50)))]
        let image = try XCTUnwrap(NSBitmapImageRep(data: Rendering.png(of: drawing, imageAt: shot, style: .standard, markStyle: .standard,
                                                                       layout: .withComments(textSize: 17))))
        XCTAssertTrue(isWhite(image, at: CGPoint(x: 250, y: 201)))
        XCTAssertTrue(isWhite(image, at: CGPoint(x: 250, y: 204)))
    }

    func testTheCommentListStopsAtItsCapAndSaysHowManyAreLeft() throws {
        let long = String(repeating: "A comment that goes on. ", count: 80)
        let (shot, drawing) = try pinned(pins: (1...99).map { pin($0, .point(CGPoint(x: 100, y: 100)), long) })
        let image = try XCTUnwrap(NSBitmapImageRep(data: Rendering.png(of: drawing, imageAt: shot, style: .standard, markStyle: .standard,
                                                                       layout: .withComments(textSize: 17))))
        XCTAssertLessThanOrEqual(image.pixelsHigh, 200 + Int(CommentList.smallestCap / 300) + 1)
        XCTAssertTrue(hasInk(image, in: CGRect(x: 17, y: image.pixelsHigh - 60, width: 100, height: 50)), "the last line says how many did not fit")

        let (tallShot, tall) = try pinned("Tall", width: 900, height: 5000, pins: (1...99).map { pin($0, .point(CGPoint(x: 100, y: 100)), long) })
        let beside = try XCTUnwrap(NSBitmapImageRep(data: Rendering.png(of: tall, imageAt: tallShot, style: .standard, markStyle: .standard,
                                                                        layout: .withComments(textSize: 17))))
        XCTAssertGreaterThan(beside.pixelsWide, 900)
        XCTAssertLessThanOrEqual(beside.pixelsHigh, Int(CommentList.smallestCap / (17 + 24 + 17 * 0.75 + 24 * 17 + 17)) + 1)
    }

    func testAMovedTeardropsLineRunsToItsPlaceButNotOverAPiecesNumber() throws {
        let (shot, pinnedDrawing) = try pinned(pins: [pin(1, .point(CGPoint(x: 150, y: 100)))])
        var drawing = pinnedDrawing
        drawing.pieceNumbers = [CGRect(x: 130, y: 80, width: 40, height: 40)]
        let drop = try XCTUnwrap(drawing.renderedTeardrops(markStyle: .standard).first)
        XCTAssertEqual(drop.drop.tip, CGPoint(x: 150, y: 76))
        let image = try XCTUnwrap(NSBitmapImageRep(data: Rendering.png(of: drawing, imageAt: shot, style: .standard, markStyle: .standard)))
        XCTAssertTrue(isRed(image, at: CGPoint(x: 150, y: 78)))
        XCTAssertTrue(isBlue(image, at: CGPoint(x: 150, y: 95)))
    }

    func testARenderingOutlinesEachAreaAndSendsNoWords() throws {
        let (shot, drawing) = try pinned(pins: [pin(1, .area(CGRect(x: 50, y: 50, width: 150, height: 100), tip: .topLeft))])
        let image = try XCTUnwrap(NSBitmapImageRep(data: Rendering.png(of: drawing, imageAt: shot, style: .standard, markStyle: .standard)))
        XCTAssertEqual(image.pixelsHigh, 200, "Send's picture is the screenshot's size")
        XCTAssertTrue(isRed(image, at: CGPoint(x: 125, y: 150)))
        XCTAssertTrue(isRed(image, at: CGPoint(x: 200, y: 100)))
        XCTAssertTrue(isBlue(image, at: CGPoint(x: 125, y: 100)))
    }

    func testTeardropsOnOnePlaceTurnUntilTheyOverlapThenMoveAway() throws {
        let place = Pin.Place.point(CGPoint(x: 150, y: 100))
        let (_, drawing) = try pinned(pins: (1...5).map { pin($0, place) })
        let drops = drawing.renderedTeardrops(markStyle: .standard)
        XCTAssertEqual(drops.prefix(4).map(\.drop.orientation), [.upRight, .downRight, .upLeft, .downLeft])
        XCTAssertEqual(drops.map(\.moved), [false, false, false, false, true])
        for (index, drop) in drops.enumerated() {
            for earlier in drops[..<index] {
                let shared = drop.drop.square.intersection(earlier.drop.square)
                XCTAssertFalse(shared.width > 0.5 && shared.height > 0.5, "pin \(drop.pin.number) covers pin \(earlier.pin.number)")
            }
        }
    }

    func testACopiedRenderingsTextIsItsPathThenItsPinsWords() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.petepetrash.vignette.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let (_, drawing) = try pinned()
        let file = dir.appendingPathComponent("Shot one-annotated.png")
        Clipboard.copyRendering(PendingRendering(file: file), words: Pin.clipboardWords(of: drawing), to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "'\(file.path)' Pin 1: Too tight.")
        var bare = drawing
        bare.pins = []
        XCTAssertNil(Pin.clipboardWords(of: bare))
        var shelly = drawing
        shelly.pins = [pin(1, .point(.zero), "Too tight"), pin(2, .point(.zero), "runs $(rm -rf ~)"),
                       pin(3, .point(.zero), "see `ls`"), pin(4, .point(.zero), "it's wide")]
        XCTAssertEqual(Pin.clipboardWords(of: shelly),
                       #"Pin 1: Too tight. Pin 2: 'runs $(rm -rf ~)' Pin 3: 'see `ls`' Pin 4: 'it'\''s wide.'"#)
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
