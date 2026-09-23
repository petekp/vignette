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
