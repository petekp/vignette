import AppKit
import XCTest

final class DrawingFileTests: XCTestCase {
    private var dir: URL!
    private var lines: LogLines!
    private var store: DrawingStore!
    private let key = "/Users/pete/Dropbox/Screenshots/Screenshot 2026-09-22 at 10.08.24 PM.png"
    private let pixels = PixelSize(width: 3024, height: 1964)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-drawings-\(UUID().uuidString)")
        lines = LogLines()
        store = DrawingStore(directory: dir, log: { [lines] in lines!.append($0) })
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func put(_ json: String, for key: String? = nil) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: store.url(for: key ?? self.key))
    }

    private func read() -> Drawing? {
        store.read(key: key, pixels: pixels, style: .standard)
    }

    func testKeysListTheDrawingsThisBuildCanRead() throws {
        let rectangle = [Mark(geometry: .rectangle(CGRect(x: 1, y: 1, width: 5, height: 5)))]
        try store.write(Drawing(key: "/a.png", pixels: pixels, pointScale: 1, marks: rectangle))
        try store.write(Drawing(key: "/b.png", pixels: pixels, pointScale: 1, marks: rectangle))
        try put(#"{"version": 3, "key": "/c.png"}"#, for: "/c.png")
        try put("not json", for: "/d.png")
        try Data("x".utf8).write(to: dir.appendingPathComponent("notes.txt"))
        XCTAssertEqual(store.scan().drawings, ["/a.png", "/b.png"])
        try store.remove(key: "/a.png")
        XCTAssertEqual(store.scan().drawings, ["/b.png"])
        XCTAssertEqual(DrawingStore(directory: dir.appendingPathComponent("never-made")).scan(), DrawingStore.Scan())
    }

    func testAMessageIsKeptBesideTheMarksAndWithoutThem() throws {
        let box = [Mark(geometry: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 50)))]
        try store.write(Drawing(key: key, pixels: pixels, pointScale: 2, marks: box), message: "the header\nscrolls")
        XCTAssertEqual(store.readMessage(key: key, pixels: pixels), "the header\nscrolls")
        try store.write(Drawing(key: key, pixels: pixels, pointScale: 2, marks: box + box))
        XCTAssertEqual(store.readMessage(key: key, pixels: pixels), "the header\nscrolls")
        XCTAssertEqual(read()?.marks.count, 2)

        try store.write(Drawing(key: key, pixels: pixels, pointScale: 2, marks: []))
        XCTAssertNil(read())
        XCTAssertEqual(store.readMessage(key: key, pixels: pixels), "the header\nscrolls")
        XCTAssertEqual(store.scan(), DrawingStore.Scan(drawings: [], messages: [key]))
        XCTAssertEqual(store.readMessage(key: key, pixels: PixelSize(width: 1512, height: 982)), "")

        let drawing = Drawing(key: key, pixels: pixels, pointScale: 2, marks: box)
        try store.write(drawing)
        try store.writeMessage("", for: drawing)
        XCTAssertEqual(store.readMessage(key: key, pixels: pixels), "")
        XCTAssertEqual(read()?.marks.count, 1)
        try store.writeMessage("only words", for: Drawing(key: key, pixels: pixels, pointScale: 2, marks: []))
        XCTAssertEqual(read()?.marks.count, 1)
        XCTAssertEqual(store.readMessage(key: key, pixels: pixels), "only words")

        try store.write(Drawing(key: key, pixels: pixels, pointScale: 2, marks: []), message: "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: key).path))
        try store.writeMessage("typed first", for: Drawing(key: key, pixels: pixels, pointScale: 2, marks: []))
        XCTAssertEqual(store.readMessage(key: key, pixels: pixels), "typed first")
        try store.writeMessage("", for: Drawing(key: key, pixels: pixels, pointScale: 2, marks: []))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: key).path))
        XCTAssertEqual(lines.all, [])
    }

    func testAFileWithoutAMessageOpensWithNoneAndIsWrittenWithoutOne() throws {
        try put(#"{"version": 1, "key": "\#(key)", "pixels": [3024, 1964], "pointScale": 2, "marks": [{"type": "rectangle", "x": 1, "y": 1, "w": 5, "h": 5}]}"#)
        XCTAssertEqual(store.readMessage(key: key, pixels: pixels), "")
        try store.write(XCTUnwrap(read()))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.url(for: key))) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["version", "key", "pixels", "pointScale", "marks"])
    }

    private func open(_ drawing: Drawing, message: String = "", history: EditorHistory = EditorHistory()) -> EditorCore {
        var core = EditorCore()
        _ = core.reduce(.open(drawing, style: .standard, metrics: .standard, markStyle: .standard, message: message, history: history))
        return core
    }

    private func storedHistory(_ key: String? = nil, of drawing: Drawing? = nil) -> EditorHistory {
        let key = key ?? self.key
        let marks = (drawing ?? store.read(key: key, pixels: pixels, style: .standard))?.marks ?? []
        return store.readHistory(key: key, pixels: pixels, marks: marks)
    }

    func testTheHistoryIsKeptWithTheDrawingAndTheScreenshotOpensAgainWithItsUndoAndRedo() throws {
        var core = open(Drawing(key: key, pixels: pixels, pointScale: 2, marks: []))
        core.drag(from: (100, 100), to: (400, 300))
        let drawn = core.drawing.marks.map(\.geometry)
        _ = core.reduce(.setTool(.select))
        core.drag(from: (250, 200), to: (450, 300))
        _ = core.reduce(.setTool(.arrow))
        core.drag(from: (1000, 500), to: (1500, 900))
        core.key(.delete)
        _ = core.reduce(.messageChanged("the header", .typing))
        core.key(.character("z"), .command)
        try store.write(core.drawingForHost, message: core.message, history: core.history)

        let drawing = try XCTUnwrap(read())
        let message = store.readMessage(key: key, pixels: pixels)
        var reopened = open(drawing, message: message, history: storedHistory(of: drawing))
        XCTAssertEqual(reopened.undoTitle, "Undo Delete")
        XCTAssertEqual(reopened.redoTitle, "Redo Typing")
        XCTAssertTrue(reopened.key(.character("z"), [.command, .shift]).contains(.message("the header")))
        reopened.key(.character("z"), .command)
        reopened.key(.character("z"), .command)
        XCTAssertEqual(reopened.drawing.marks.map(\.kind), [.rectangle, .arrow])
        reopened.key(.character("z"), .command)
        reopened.key(.character("z"), .command)
        XCTAssertEqual(reopened.drawing.marks.map(\.geometry), drawn)
        reopened.key(.character("z"), .command)
        XCTAssertTrue(reopened.drawing.marks.isEmpty)
        XCTAssertFalse(reopened.canUndo)

        let note = Mark(geometry: .text(Mark.Text(origin: CGPoint(x: CGFloat(pixels.width) - 40, y: 100), text: "Hello there", size: 24)))
        let typed = EditorHistory(undo: [.drawing(EditStep(name: .typing, changes: [EditStep.Change(id: note.id, before: nil, after: PlacedMark(mark: note, index: 0))],
                                                          selectionBefore: [], selectionAfter: [note.id]))])
        try store.write(Drawing(key: key, pixels: pixels, pointScale: 2, marks: [note]), message: "", history: typed)
        let moved = try XCTUnwrap(read())
        XCTAssertNotEqual(moved.marks.map(\.geometry), [note.geometry], "the read moves the note in from the edge")
        XCTAssertEqual(storedHistory(of: moved).undo.count, 1)
        XCTAssertFalse(lines.all.contains { $0.contains("history dropped") })
    }

    func testAHistoryFollowsARenameAndIsDroppedWhenTheMarksOrTheMessageChangedWithoutTheEditor() throws {
        let box = Mark(geometry: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 50)))
        let typed = EditorHistory(undo: [.message(MessageStep(name: .typing, before: "", after: "words"))])
        try store.write(Drawing(key: key, pixels: pixels, pointScale: 2, marks: [box]), message: "words", history: typed)
        XCTAssertEqual(storedHistory().undo.count, 1)
        XCTAssertTrue(store.readHistory(key: key, pixels: PixelSize(width: 1512, height: 982), marks: [box]).isEmpty)

        let renamed = "/Users/pete/Dropbox/Screenshots/Renamed.png"
        XCTAssertEqual(try store.rename(from: key, to: renamed), pixels)
        XCTAssertEqual(storedHistory(renamed).undo.count, 1)

        var edited = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.url(for: renamed))) as? [String: Any])
        edited["message"] = "other words"
        try JSONSerialization.data(withJSONObject: edited).write(to: store.url(for: renamed))
        XCTAssertTrue(storedHistory(renamed).isEmpty)

        try store.write(Drawing(key: renamed, pixels: pixels, pointScale: 2, marks: [box]), message: "words", history: typed)
        try store.write(Drawing(key: renamed, pixels: pixels, pointScale: 2, marks: [box, box]))
        XCTAssertTrue(storedHistory(renamed).isEmpty, "a write without a history, as a reply's install makes")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.url(for: renamed))) as? [String: Any])
        XCTAssertNil(object["history"])
        XCTAssertEqual(lines.all.filter { $0.contains("history dropped") }.count, 1)
    }

    func testAFileKeepsTheNewestStepsWithinItsCapDroppingTheOldestUndoFirst() throws {
        let steps = (0..<150).map { HistoryStep.message(MessageStep(name: .typing, before: "\($0)", after: "\($0 + 1)")) }
        let blank = Drawing(key: key, pixels: PixelSize(width: 10, height: 10), pointScale: 1, marks: [])
        let kept = try EditorHistory(fileObject: XCTUnwrap(EditorHistory(undo: steps).fileObject(endingAt: blank, message: "150")), marks: [],
                                     basis: EditorHistory.basis(marks: [], message: "150"))
        XCTAssertEqual(kept.undo.count, EditorHistory.maxSteps)
        guard case .message(let oldest)? = kept.undo.first, case .message(let newest)? = kept.undo.last else { return XCTFail("no message steps") }
        XCTAssertEqual(oldest.before, "50")
        XCTAssertEqual(newest.after, "150")

        let long = String(repeating: "a", count: 100_000)
        let pasted = HistoryStep.message(MessageStep(name: .paste, before: "", after: long))
        let big = EditorHistory(undo: Array(repeating: pasted, count: 4), redo: [pasted])
        let fitted = try EditorHistory(fileObject: XCTUnwrap(big.fileObject(endingAt: blank, message: "")), marks: [],
                                       basis: EditorHistory.basis(marks: [], message: ""))
        XCTAssertEqual(fitted.undo.count, 1)
        XCTAssertEqual(fitted.redo.count, 1)
    }
}

@MainActor
final class DrawingMessageTests: XCTestCase {
    private var dir: URL!
    private var drawings: Drawings!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-drawings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        drawings = Drawings(store: DrawingStore(directory: dir.appendingPathComponent("drawings")))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testAMessageFollowsARenameAndGoesWithItsScreenshot() throws {
        let shot = try writeTestImage(width: 300, height: 200, space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), in: dir) { _, _ in (0xe0, 0x31, 0x31) }
        let renamed = shot.deletingLastPathComponent().appendingPathComponent("Renamed.png")
        let pixels = try XCTUnwrap(PixelSize(imageAt: shot))
        drawings.keepMessage("make it blue", for: Drawing(key: shot.path, pixels: pixels, pointScale: 2, marks: []))
        XCTAssertEqual(drawings.message(of: shot.screenshotKey, pixels: pixels), "make it blue")
        XCTAssertEqual(drawings.keys, [])
        try FileManager.default.moveItem(at: shot, to: renamed)

        drawings.rename(from: shot.screenshotKey, to: renamed.screenshotKey, style: .standard)

        XCTAssertEqual(drawings.message(of: shot.screenshotKey, pixels: pixels), "")
        XCTAssertEqual(drawings.message(of: renamed.screenshotKey, pixels: pixels), "make it blue")
        XCTAssertEqual(Drawings(store: drawings.store).message(of: renamed.screenshotKey, pixels: pixels), "make it blue")
        drawings.remove([renamed.screenshotKey])
        XCTAssertEqual(drawings.messages, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: drawings.store.url(for: renamed.path).path))
    }
}
