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
        XCTAssertEqual(try drawings.add(pushed, from: "Claude", to: shot.screenshotKey, style: .standard, newScreen: retinaScreen, rule: UITweaks().markScaleRule), 1)
        let stored = try XCTUnwrap(drawings.read(shot.screenshotKey, pixels: pixels, style: .standard))
        var reopened = EditorCore()
        _ = reopened.reduce(.open(stored, style: .standard, metrics: .standard, markStyle: .standard,
                                  history: drawings.history(of: shot.screenshotKey, pixels: pixels, drawing: stored)))
        XCTAssertEqual(reopened.undoTitle, "Undo Claude's Marks")
        reopened.key(.character("z"), .command)
        XCTAssertEqual(reopened.drawing.marks.map(\.geometry), [theirs.geometry], "one undo takes the agent's marks back off")
        XCTAssertEqual(reopened.undoTitle, "Undo Rectangle")
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
}
