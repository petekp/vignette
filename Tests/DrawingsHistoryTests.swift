import XCTest

private let retinaScreen = DrawingScreen(scale: 2, size: CGSize(width: 1512, height: 982))

extension FakeEditor {
    func history(of key: ScreenshotKey) -> EditorHistory? { nil }
}

@MainActor
final class DrawingsHistoryTests: XCTestCase {
    private var dir: URL!
    private var drawings: Drawings!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-drawings-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        drawings = Drawings(store: DrawingStore(directory: dir.appendingPathComponent("drawings")))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testAgentsMarksAddedWhileTheScreenshotIsClosedAreOneStepOfItsHistory() throws {
        let shot = try writeTestImage(width: 300, height: 200, space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), in: dir) { _, _ in (0xe0, 0x31, 0x31) }
        let pixels = try XCTUnwrap(PixelSize(imageAt: shot))
        let theirs = Mark(geometry: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 40)))
        let drawn = EditorHistory(undo: [.drawing(EditStep(name: .rectangle, changes: [EditStep.Change(id: theirs.id, before: nil, after: PlacedMark(mark: theirs, index: 0))],
                                                          selectionBefore: [], selectionAfter: [theirs.id]))])
        drawings.write(Drawing(key: shot.path, pixels: pixels, pointScale: 1, marks: [theirs]), history: drawn, reason: "saved")

        let pushed = [AgentMark(type: .rectangle, x: 0.1, y: 0.1, w: 0.5, h: 0.5)]
        XCTAssertEqual(try drawings.add(AgentAdditions(marks: pushed, agent: "Claude"), to: shot.screenshotKey, style: .standard, newScreen: retinaScreen, rule: UITweaks().markScaleRule).marks, 1)
        let stored = try XCTUnwrap(drawings.read(shot.screenshotKey, pixels: pixels, style: .standard))
        var reopened = EditorCore()
        _ = reopened.reduce(.open(stored, style: .standard, metrics: .standard, markStyle: .standard,
                                  history: drawings.history(of: shot.screenshotKey, pixels: pixels, drawing: stored)))
        XCTAssertEqual(reopened.undoTitle, "Undo Claude's Marks")
        reopened.key(.character("z"), .command)
        XCTAssertEqual(reopened.drawing.marks.map(\.geometry), [theirs.geometry], "one undo takes the agent's marks back off")
        XCTAssertEqual(reopened.undoTitle, "Undo Rectangle")
    }

    func testAnAgentsNewPinAndAnswerJoinAStoredDrawingAsOneStepThatUndoes() throws {
        let shot = try writeTestImage(width: 300, height: 200, space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), in: dir) { _, _ in (0xe0, 0x31, 0x31) }
        let pixels = try XCTUnwrap(PixelSize(imageAt: shot))
        let mine = Pin(id: UUID(), number: 1, place: .point(CGPoint(x: 20, y: 20)), comments: [Pin.Comment(text: "Too tight")])
        drawings.write(Drawing(key: shot.path, pixels: pixels, pointScale: 1, marks: [], pins: [mine], nextPin: 2), history: EditorHistory(), reason: "saved")
        let at = Date(timeIntervalSince1970: 1_795_000_000)
        let pins = try AgentPin.parse(#"[{"x":0.5,"y":0.5,"text":"Here"},{"pin":1,"text":"Fixed"}]"#)

        let joined = try drawings.add(AgentAdditions(marks: [], pins: pins, agent: "claude", at: at), to: shot.screenshotKey, style: .standard,
                                      newScreen: retinaScreen, rule: UITweaks().markScaleRule)
        XCTAssertEqual(joined, Drawings.Joined(marks: 0, pins: 2))
        let stored = try XCTUnwrap(drawings.read(shot.screenshotKey, pixels: pixels, style: .standard))
        XCTAssertEqual(stored.pins.map(\.number), [1, 2])
        XCTAssertEqual(stored.pins[0].comments.last, Pin.Comment(text: "Fixed", agent: true, agentName: "claude", at: at))
        XCTAssertEqual(stored.pins[1].place, .point(CGPoint(x: 150, y: 100)))
        XCTAssertEqual(stored.nextPin, 3)

        var reopened = EditorCore()
        _ = reopened.reduce(.open(stored, style: .standard, metrics: .standard, markStyle: .standard,
                                  history: drawings.history(of: shot.screenshotKey, pixels: pixels, drawing: stored)))
        reopened.key(.character("z"), .command)
        XCTAssertEqual(reopened.drawing.pins, [mine], "the new pin goes and the answer leaves the person's pin")
        XCTAssertEqual(reopened.drawing.nextPin, 3, "a number once given is not given again")
    }

    func testADrawingWrittenBackFromWhatWasSavedKeepsItsMessageAndItsHistory() throws {
        let shot = try writeTestImage(width: 300, height: 200, space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), in: dir) { _, _ in (0xe0, 0x31, 0x31) }
        let pixels = try XCTUnwrap(PixelSize(imageAt: shot))
        let mark = Mark(geometry: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 40)))
        let drawn = EditorHistory(undo: [.drawing(EditStep(name: .rectangle, changes: [EditStep.Change(id: mark.id, before: nil, after: PlacedMark(mark: mark, index: 0))],
                                                          selectionBefore: [], selectionAfter: [mark.id]))])
        let drawing = Drawing(key: shot.path, pixels: pixels, pointScale: 1, marks: [mark])
        drawings.write(drawing, message: "the button", history: drawn, reason: "saved")
        let saved = try XCTUnwrap(drawings.saved(of: shot.screenshotKey, style: .standard))

        drawings.write(drawing, reason: "replaced")
        XCTAssertTrue(drawings.history(of: shot.screenshotKey, pixels: pixels, drawing: saved.drawing).isEmpty)
        drawings.write(saved.drawing, message: saved.message, history: saved.history, reason: "put back")

        XCTAssertEqual(drawings.message(of: shot.screenshotKey, pixels: pixels), "the button")
        XCTAssertEqual(drawings.history(of: shot.screenshotKey, pixels: pixels, drawing: saved.drawing).undo.count, 1)
    }

    func testAFileWithNoMarksOrPinsIsWrittenBackAfterItsScreenshotWentWithItsMessageHistoryAndNumbering() throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let typedShot = try writeTestImage(width: 300, height: 200, space: space, in: dir) { _, _ in (0xe0, 0x31, 0x31) }
        let typedPixels = try XCTUnwrap(PixelSize(imageAt: typedShot))
        let typed = EditorHistory(undo: [.message(MessageStep(name: .typing, before: "", after: "the button"))])
        drawings.write(Drawing(key: typedShot.path, pixels: typedPixels, pointScale: 2, marks: [], nextPin: 3), message: "the button",
                       history: typed, reason: "saved")
        let stitchShot = dir.appendingPathComponent("stitch.png")
        try FileManager.default.copyItem(at: typedShot, to: stitchShot)
        let pieces = [CGRect(x: 0, y: 0, width: 300, height: 100), CGRect(x: 0, y: 100, width: 300, height: 100)]
        drawings.write(Drawing(key: stitchShot.path, pixels: typedPixels, pointScale: 2, marks: [], pieceNumbers: pieces), reason: "stitched")

        let keys = [typedShot.screenshotKey, stitchShot.screenshotKey]
        let saved = try keys.map { try XCTUnwrap(drawings.saved(of: $0, style: .standard)) }
        drawings.remove(keys)
        XCTAssertNil(drawings.numbering(of: typedShot.screenshotKey, pixels: typedPixels))
        for item in saved { drawings.write(item.drawing, message: item.message, history: item.history, reason: "put back") }

        XCTAssertEqual(drawings.message(of: typedShot.screenshotKey, pixels: typedPixels), "the button")
        XCTAssertEqual(drawings.numbering(of: typedShot.screenshotKey, pixels: typedPixels)?.nextPin, 3)
        let blank = try XCTUnwrap(saved.first?.drawing)
        XCTAssertEqual(drawings.history(of: typedShot.screenshotKey, pixels: typedPixels, drawing: blank).undo.count, 1)
        XCTAssertEqual(drawings.numbering(of: stitchShot.screenshotKey, pixels: typedPixels)?.pieceNumbers, pieces)
    }
}
