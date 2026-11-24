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
        try put(#"{"version": 2, "key": "/c.png"}"#, for: "/c.png")
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
