import AppKit
import XCTest

final class DrawingStoreTests: XCTestCase {
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

    private func read(_ pixels: PixelSize? = nil) -> Drawing? {
        store.read(key: key, pixels: pixels ?? self.pixels, style: .standard)
    }

    func testTheSpecsExampleDecodes() throws {
        try put("""
            {
              "version": 1,
              "key": "/Users/pete/Dropbox/Screenshots/Screenshot 2026-09-22 at 10.08.24 PM.png",
              "pixels": [3024, 1964],
              "pointScale": 2,
              "marks": [
                { "type": "rectangle", "x": 410, "y": 220, "w": 640, "h": 180, "color": "red" }
              ]
            }
            """)
        let drawing = try XCTUnwrap(read())
        XCTAssertEqual(drawing.key, key)
        XCTAssertEqual(drawing.pixels, pixels)
        XCTAssertEqual(drawing.pointScale, 2)
        XCTAssertEqual(drawing.marks.map(\.geometry), [.rectangle(CGRect(x: 410, y: 220, width: 640, height: 180))])
        XCTAssertEqual(drawing.marks.first?.color, .red)
        XCTAssertEqual(drawing.marks.first?.agent, false)
        XCTAssertEqual(drawing.marks.first?.colorChosen, false)
        XCTAssertEqual(lines.all, [])
    }

    func testADrawingSurvivesAWriteAndARead() throws {
        let marks = [
            Mark(geometry: .rectangle(CGRect(x: 410.25, y: 220, width: 640, height: 180.5)), color: .red),
            Mark(geometry: .ellipse(CGRect(x: 10, y: 20, width: 30, height: 40)), color: .yellow, agent: true, colorChosen: true),
            Mark(geometry: .arrow(.init(start: CGPoint(x: 100, y: 900), end: CGPoint(x: 700, y: 600), bend: -83.125)), color: .lightBlue),
            Mark(geometry: .arrow(.init(start: CGPoint(x: 1, y: 2), end: CGPoint(x: 3, y: 4))), color: .white, agent: true),
            Mark(geometry: .text(.init(origin: CGPoint(x: 50, y: 60), text: "Header should not scroll\nsecond line 你好 🎉", wrap: 900.5, size: 24)), color: .violet),
            Mark(geometry: .text(.init(origin: CGPoint(x: 0.1, y: 1.0 / 3.0), text: "no wrap", size: 31.7)), color: .red, colorChosen: true),
        ]
        try store.write(Drawing(key: key, pixels: pixels, pointScale: 2, marks: marks))
        let back = try XCTUnwrap(read())
        XCTAssertEqual(back.pointScale, 2)
        XCTAssertEqual(back.marks.map(\.geometry), marks.map(\.geometry))
        XCTAssertEqual(back.marks.map(\.color), marks.map(\.color))
        XCTAssertEqual(back.marks.map(\.agent), marks.map(\.agent))
        XCTAssertEqual(back.marks.map(\.colorChosen), marks.map(\.colorChosen))
        XCTAssertEqual(lines.all, [])

        // The defaults are left out: a straight arrow has no bend, a text without one no wrap, and
        // neither flag is written while it is false.
        let file = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.url(for: key))) as? [String: Any])
        XCTAssertEqual(file["version"] as? Int, 1)
        XCTAssertEqual(file["pixels"] as? [Int], [3024, 1964])
        let written = try XCTUnwrap(file["marks"] as? [[String: Any]])
        XCTAssertEqual(Set(written[0].keys), ["type", "x", "y", "w", "h", "color"])
        XCTAssertEqual(Set(written[1].keys), ["type", "x", "y", "w", "h", "color", "agent", "colorChosen"])
        XCTAssertEqual(Set(written[3].keys), ["type", "x", "y", "x2", "y2", "color", "agent"])
        XCTAssertEqual(Set(written[5].keys), ["type", "x", "y", "text", "size", "color", "colorChosen"])
    }

    func testANewerVersionIsReadAsNoDrawingAndNeverOverwritten() throws {
        let newer = #"{"version": 2, "key": "\#(key)", "pixels": [3024, 1964], "pointScale": 2, "marks": [], "future": true}"#
        try put(newer)
        XCTAssertNil(read())
        XCTAssertEqual(lines.all.count, 1)
        XCTAssertTrue(lines.all[0].hasPrefix("[drawing] warning newer"), lines.all[0])

        let drawing = Drawing(key: key, pixels: pixels, pointScale: 2,
                              marks: [Mark(geometry: .rectangle(CGRect(x: 1, y: 1, width: 5, height: 5)))])
        XCTAssertThrowsError(try store.write(drawing))
        XCTAssertThrowsError(try store.write(Drawing(key: key, pixels: pixels, pointScale: 2, marks: [])), "an empty drawing would remove it")
        XCTAssertThrowsError(try store.remove(key: key))
        XCTAssertEqual(try String(contentsOf: store.url(for: key), encoding: .utf8), newer)
        XCTAssertEqual(lines.all.count, 4, "one line for the read and one for each refusal: \(lines.all)")
        XCTAssertEqual(store.keys(), [], "a newer build's drawing is not this build's to sweep")
    }

    func testANonFiniteCoordinateDropsThatMarkWithOneLogLine() throws {
        try put("""
            {"version": 1, "key": "\(key)", "pixels": [3024, 1964], "pointScale": 2, "marks": [
              {"type": "rectangle", "x": 10, "y": 10, "w": 100, "h": 100, "color": "red"},
              {"type": "rectangle", "x": 1e999, "y": 10, "w": 100, "h": 100, "color": "red"},
              {"type": "text", "x": 10, "y": 300, "text": "1e999 in a string is words", "size": 24, "color": "white"}
            ]}
            """)
        let drawing = try XCTUnwrap(read())
        XCTAssertEqual(drawing.marks.map(\.kind), [.rectangle, .text])
        guard case .text(let text) = drawing.marks[1].geometry else { return XCTFail() }
        XCTAssertEqual(text.text, "1e999 in a string is words")
        XCTAssertEqual(lines.all.count, 1, "\(lines.all)")
        XCTAssertTrue(lines.all[0].contains("mark=2"), lines.all[0])
        XCTAssertTrue(lines.all[0].contains("x must be a finite number"), lines.all[0])
    }

    func testAFileThatDoesNotParseIsSetAside() throws {
        try put(#"{"version": 1, "key": "#)
        XCTAssertNil(read())
        let aside = store.url(for: key).appendingPathExtension("invalid")
        XCTAssertEqual(aside.lastPathComponent, DrawingStore.id(for: key) + ".json.invalid")
        XCTAssertTrue(FileManager.default.fileExists(atPath: aside.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: key).path))
        XCTAssertEqual(lines.all.count, 1)
        XCTAssertTrue(lines.all[0].hasPrefix("[drawing] error invalid"), lines.all[0])

        // A top level that parses as JSON but is not a drawing is set aside the same way.
        try put(#"{"version": 1, "key": "\#(key)", "pixels": [3024], "pointScale": 2, "marks": []}"#)
        XCTAssertNil(read())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: key).path))
        XCTAssertEqual(lines.all.count, 2)
    }

    func testAPointScaleOutsideHalfToEightMakesTheFileInvalid() throws {
        for scale in ["0.1", "9", "1e300", "1e-300"] {
            try put(#"{"version": 1, "key": "\#(key)", "pixels": [3024, 1964], "pointScale": \#(scale), "marks": [{"type": "rectangle", "x": 1, "y": 1, "w": 5, "h": 5, "color": "red"}]}"#)
            XCTAssertNil(read(), scale)
            XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: key).appendingPathExtension("invalid").path), scale)
            XCTAssertTrue(lines.all.last?.contains("pointScale must be a number from 0.5 to 8") == true, "\(lines.all)")
        }
        for scale in ["0.5", "8"] {
            try put(#"{"version": 1, "key": "\#(key)", "pixels": [3024, 1964], "pointScale": \#(scale), "marks": [{"type": "rectangle", "x": 1, "y": 1, "w": 5, "h": 5, "color": "red"}]}"#)
            XCTAssertNotNil(read(), scale)
        }
    }

    func testADrawingWhosePixelsDifferIsDropped() throws {
        let drawing = Drawing(key: key, pixels: pixels, pointScale: 2,
                              marks: [Mark(geometry: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 50)))])
        try store.write(drawing)
        XCTAssertNil(read(PixelSize(width: 1512, height: 982)))
        XCTAssertEqual(lines.all.count, 1)
        XCTAssertTrue(lines.all[0].hasPrefix("[drawing] dropped"), lines.all[0])
        XCTAssertNotNil(read(), "the file is left for the image it was made on")
    }

    func testADrawingWithNoMarksHasNoFile() throws {
        try store.write(Drawing(key: key, pixels: pixels, pointScale: 2, marks: []))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: key).path))
        try store.write(Drawing(key: key, pixels: pixels, pointScale: 2,
                                marks: [Mark(geometry: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 50)))]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: key).path))
        try store.write(Drawing(key: key, pixels: pixels, pointScale: 2, marks: []))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: key).path))
        XCTAssertNil(read())
        XCTAssertEqual(lines.all, [])
    }

    func testAMarkPartlyOutsideTheImageIsMovedInsideWithOneLogLine() throws {
        try put("""
            {"version": 1, "key": "\(key)", "pixels": [3024, 1964], "pointScale": 2, "marks": [
              {"type": "rectangle", "x": 3000, "y": 10, "w": 100, "h": 100, "color": "red"}
            ]}
            """)
        let drawing = try XCTUnwrap(read())
        XCTAssertEqual(drawing.marks.map(\.geometry), [.rectangle(CGRect(x: 2924, y: 10, width: 100, height: 100))])
        XCTAssertEqual(lines.all.count, 1)
        XCTAssertTrue(lines.all[0].hasPrefix("[drawing] moved mark=1"), lines.all[0])
    }

    func testAFileHoldingAnotherKeysDrawingIsNotOpened() throws {
        try put(#"{"version": 1, "key": "/elsewhere.png", "pixels": [3024, 1964], "pointScale": 2, "marks": [{"type": "rectangle", "x": 1, "y": 1, "w": 5, "h": 5, "color": "red"}]}"#)
        XCTAssertNil(read())
        XCTAssertEqual(lines.all.count, 1)
        XCTAssertEqual(store.keys(), [], "it is not listed under a key whose name it does not have")
    }

    func testKeysListTheDrawingsThisBuildCanRead() throws {
        let rectangle = [Mark(geometry: .rectangle(CGRect(x: 1, y: 1, width: 5, height: 5)))]
        try store.write(Drawing(key: "/a.png", pixels: pixels, pointScale: 1, marks: rectangle))
        try store.write(Drawing(key: "/b.png", pixels: pixels, pointScale: 1, marks: rectangle))
        try put(#"{"version": 2, "key": "/c.png"}"#, for: "/c.png")
        try put("not json", for: "/d.png")
        try Data("x".utf8).write(to: dir.appendingPathComponent("notes.txt"))
        XCTAssertEqual(store.keys(), ["/a.png", "/b.png"])
        try store.remove(key: "/a.png")
        XCTAssertEqual(store.keys(), ["/b.png"])
        XCTAssertEqual(DrawingStore(directory: dir.appendingPathComponent("never-made")).keys(), [])
    }

    func testIdIsStableAndFilenameSafe() {
        let id = DrawingStore.id(for: "/Users/p/Screenshots/Screenshot 2026-09-15 at 2.50.12 PM.png")
        XCTAssertEqual(id, DrawingStore.id(for: "/Users/p/Screenshots/Screenshot 2026-09-15 at 2.50.12 PM.png"))
        XCTAssertEqual(id.count, 32)
        XCTAssertTrue(id.allSatisfy { $0.isHexDigit })
        XCTAssertNotEqual(id, DrawingStore.id(for: "/Users/p/Screenshots/Screenshot 2026-09-15 at 2.50.13 PM.png"))
    }
}

/// The lines a store logged, collected from whichever thread logs them.
final class LogLines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) { lock.withLock { lines.append(line) } }
    var all: [String] { lock.withLock { lines } }
}

/// Agents' marks reaching a drawing, and the launch clearing out the previous editor's drafts.
@MainActor
final class DrawingsTests: XCTestCase {
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

    /// A 300 by 200 screenshot in the red a mark starts in, so the colour pass has to move a mark off it.
    private func redShot() throws -> URL {
        try writeTestImage(width: 300, height: 200, space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), in: dir) { _, _ in (0xe0, 0x31, 0x31) }
    }

    private let pushed = [AgentMark(type: .rectangle, x: 0.1, y: 0.1, w: 0.5, h: 0.5),
                          AgentMark(type: .ellipse, x: 0.5, y: 0.5, w: 0.2, h: 0.2, color: "red")]

    func testAgentsMarksJoinTheStoredDrawingThroughTheColourPass() throws {
        let shot = try redShot()
        let pixels = try XCTUnwrap(PixelSize(imageAt: shot))
        let theirs = Mark(geometry: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 40)), color: .yellow)
        drawings.write(Drawing(key: shot.path, pixels: pixels, pointScale: 1, marks: [theirs]), reason: "saved")

        let added = try drawings.add(pushed, to: shot, editor: nil, sample: ColorSample(imageAt: shot), style: .standard, newPointScale: 2)
        XCTAssertEqual(added, 2)
        let stored = try XCTUnwrap(drawings.read(shot, pixels: pixels, style: .standard))
        XCTAssertEqual(stored.pointScale, 1, "a stored drawing keeps its own scale")
        XCTAssertEqual(stored.marks.map(\.geometry).first, theirs.geometry, "the person's mark stays first")
        XCTAssertEqual(stored.marks.count, 3)
        XCTAssertEqual(stored.marks.dropFirst().map(\.agent), [true, true])
        XCTAssertNotEqual(stored.marks[1].color, .red, "the colour pass moves an unnamed mark off the red under it")
        XCTAssertEqual(stored.marks[2].color, .red, "a colour the agent named is kept")

        // A screenshot with no drawing gets a new one at the scale it is given.
        let fresh = try redShot()
        XCTAssertEqual(try drawings.add(pushed, to: fresh, editor: nil, sample: nil, style: .standard, newPointScale: 2), 2)
        let made = try XCTUnwrap(drawings.read(fresh, pixels: pixels, style: .standard))
        XCTAssertEqual(made.pointScale, 2)
        XCTAssertEqual(made.marks.count, 2)
        XCTAssertEqual(drawings.keys, [shot.path, fresh.path])
    }

    func testAgentsMarksJoinTheOpenDrawingAsOneUndoStep() throws {
        let shot = try redShot()
        let pixels = try XCTUnwrap(PixelSize(imageAt: shot))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.petepetrash.vignette.tests.\(UUID().uuidString)"))
        let view = EditorView(pasteboard: pasteboard)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { _ = view.park(); pasteboard.releaseGlobally(); window.close() }
        let theirs = Mark(geometry: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 40)), color: .yellow)
        view.open(Drawing(key: shot.path, pixels: pixels, pointScale: 1, marks: [theirs]), image: nil,
                  picture: CGRect(x: 0, y: 0, width: 300, height: 200), style: .standard, metrics: .standard, arrowhead: .standard,
                  pickColor: { _ in nil })

        view.onHandOver = { [drawings] drawing in drawings!.write(drawing, reason: "saved") }

        XCTAssertEqual(try drawings.add(pushed, to: shot, editor: view, sample: nil, style: .standard, newPointScale: 2), 2)
        XCTAssertEqual(view.core.drawing.marks.count, 3)
        XCTAssertEqual(view.core.drawing.marks.dropFirst().map(\.agent), [true, true])
        XCTAssertEqual(drawings.read(shot, pixels: pixels, style: .standard)?.marks.count, 3,
                       "the editor hands the join over at once, so the push answers with the drawing written")

        view.undo(nil)
        XCTAssertEqual(view.core.drawing.marks.map(\.geometry), [theirs.geometry], "one undo takes the whole push back")

        // The push answers from the hand-over's write, not from the marks having joined.
        try FileManager.default.removeItem(at: shot)
        XCTAssertThrowsError(try drawings.add(pushed, to: shot, editor: view, sample: nil, style: .standard, newPointScale: 2)) { error in
            XCTAssertEqual((error as? Drawings.Failure)?.code, .writeFailed)
        }
    }

    /// A card reads its drawing off the main thread; a write while it reads says what the drawing is
    /// now, and the read's older answer is dropped.
    func testALoadThatBeganBeforeAWriteDoesNotAnswer() throws {
        let shot = try redShot()
        let pixels = try XCTUnwrap(PixelSize(imageAt: shot))
        let old = Drawing(key: shot.path, pixels: pixels, pointScale: 1, marks: [Mark(geometry: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 40)))])
        let new = Drawing(key: shot.path, pixels: pixels, pointScale: 1, marks: [Mark(geometry: .rectangle(CGRect(x: 90, y: 90, width: 50, height: 40)))])
        drawings.write(old, reason: "saved")
        var changed: [Drawing?] = [], loaded: [Drawing?] = []
        drawings.onChange = { _, drawing in changed.append(drawing) }

        drawings.load(shot, style: .standard) { loaded.append($0) }
        drawings.write(new, reason: "saved")
        Drawings.loads.sync(flags: .barrier) {}
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(changed.map { $0?.marks }, [new.marks])
        XCTAssertTrue(loaded.isEmpty, "the load read the old drawing, or the new one, and either way the write already said")

        drawings.load(shot, style: .standard) { loaded.append($0) }
        Drawings.loads.sync(flags: .barrier) {}
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(loaded.map { $0?.marks.map(\.geometry) }, [new.marks.map(\.geometry)], "read from disk, so the ids are new")

        drawings.remove([shot])
        XCTAssertEqual(changed.count, 2)
        XCTAssertNil(changed[1], "a removal says there is no drawing")
    }

    func testALaunchRemovesWhatTheWebEditorLeft() throws {
        // The drafts folders and WebKit's two, as a launch names them, inside a scratch home.
        let left = ["Application Support/app/drafts", "Caches/app/drafts", "Caches/app/WebKit/NetworkCache", "WebKit/app/WebsiteData"]
        for path in left {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent(path), withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: dir.appendingPathComponent(path).appendingPathComponent("a.json"))
        }
        let folders = ["Application Support/app/drafts", "Caches/app/drafts", "Caches/app/WebKit", "WebKit/app"].map(dir.appendingPathComponent)
        Drawings.removeWebEditorData(folders + [dir.appendingPathComponent("never-made")])
        for folder in folders { XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), folder.path) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Caches/app").path), "only those folders go")
    }
}
