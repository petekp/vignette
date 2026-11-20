import XCTest

@MainActor
final class DrawingsWriteFailureTests: XCTestCase {
    private var dir: URL!
    private var folder: URL!
    private var shot: URL!
    private var drawings: Drawings!
    private var failed: [ScreenshotKey] = []

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-drawing-writes-\(UUID().uuidString)")
        folder = dir.appendingPathComponent("drawings")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        shot = dir.appendingPathComponent("Shot.png")
        try Data("png".utf8).write(to: shot)
        drawings = Drawings(store: DrawingStore(directory: folder))
        failed = []
        drawings.onWriteFailed = { [unowned self] in failed.append($0) }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        try? FileManager.default.removeItem(at: dir)
    }

    private func drawing(marks: [Mark]) -> Drawing {
        Drawing(key: shot.path, pixels: PixelSize(width: 10, height: 10), pointScale: 1, marks: marks)
    }

    private func lockFolder(_ locked: Bool) throws {
        try FileManager.default.setAttributes([.posixPermissions: locked ? 0o500 : 0o700], ofItemAtPath: folder.path)
    }

    func testAHandOverThatFailsSaysSoOnceTheEditorHasLetGoOfTheDrawing() throws {
        let drawing = drawing(marks: [Mark(geometry: .rectangle(CGRect(x: 1, y: 1, width: 4, height: 4)))])
        let editor = FakeEditor(drawing)
        drawings.open = editor
        try lockFolder(true)

        drawings.handOver(drawing, reason: "saved")
        XCTAssertEqual(failed, [])

        editor.isOpen = false
        drawings.handOver(drawing, reason: "parked")
        XCTAssertEqual(failed, [shot.screenshotKey])

        try lockFolder(false)
        drawings.handOver(drawing, reason: "parked")
        XCTAssertEqual(failed, [shot.screenshotKey])
        XCTAssertEqual(drawings.keys, [shot.screenshotKey])
    }

    func testAWriteFromAnywhereElseAnswersItsCallerAlone() throws {
        try lockFolder(true)
        XCTAssertFalse(drawings.write(drawing(marks: [Mark(geometry: .rectangle(CGRect(x: 1, y: 1, width: 4, height: 4)))]), reason: "built"))
        XCTAssertEqual(failed, [])
    }

    func testAnEmptyHandOverThatANewerBuildsFileRefusesIsNotAFailure() throws {
        let store = DrawingStore(directory: folder)
        let newer = #"{"version": \#(Drawing.version + 1), "key": "\#(shot.path)", "pixels": [10, 10], "pointScale": 1, "marks": []}"#
        try Data(newer.utf8).write(to: store.url(for: shot.path))

        drawings.handOver(drawing(marks: []), reason: "parked")
        XCTAssertEqual(failed, [])

        drawings.handOver(drawing(marks: [Mark(geometry: .rectangle(CGRect(x: 1, y: 1, width: 4, height: 4)))]), reason: "parked")
        XCTAssertEqual(failed, [shot.screenshotKey])
    }
}
