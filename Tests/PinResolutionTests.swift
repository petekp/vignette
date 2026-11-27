import AppKit
import XCTest

@MainActor
final class PinResolutionTests: XCTestCase {
    private var dir: URL!
    private var lines: LogLines!
    private var store: DrawingStore!
    private let key = "/Users/pete/Dropbox/Screenshots/Pinned.png"
    private let pixels = PixelSize(width: 800, height: 600)

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-resolved-pins-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        lines = LogLines()
        store = DrawingStore(directory: dir.appendingPathComponent("drawings"), log: { [lines] in lines?.append($0) })
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func pin(_ number: Int, _ place: Pin.Place = .point(CGPoint(x: 100, y: 100)), _ text: String = "Too tight") -> Pin {
        Pin(id: UUID(), number: number, place: place, comments: [Pin.Comment(text: text)])
    }

    private func file() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.url(for: key))) as? [String: Any])
    }

    private func item(_ number: Int) -> [String: Any] {
        ["id": UUID().uuidString, "number": number, "x": 100, "y": 100, "comments": [["text": "Too tight"]]]
    }

    func testAResolvedPinRoundTripsAndAnyResolvedPinInTheFileOrItsHistoryMakesItVersion3() throws {
        let at = Date(timeIntervalSince1970: 1_795_000_000.6)
        var mine = pin(1), theirs = pin(2)
        mine.resolved = .byPerson(at: at)
        theirs.resolved = Pin.Resolution(agent: true, agentName: "Claude", at: at)
        let open = pin(3)
        try store.write(Drawing(key: key, pixels: pixels, pointScale: 2, marks: [], pins: [mine, theirs, open], nextPin: 4))
        XCTAssertEqual(try XCTUnwrap(store.read(key: key, pixels: pixels, style: .standard)).pins, [mine, theirs, open])
        XCTAssertEqual(try file()["version"] as? Int, 3)
        let resolved = try XCTUnwrap(try file()["pins"] as? [[String: Any]]).map { $0["resolved"] as? [String: Any] }
        XCTAssertEqual(resolved.map { $0?["at"] as? String }, ["2026-11-18T11:06:40Z", "2026-11-18T11:06:40Z", nil])
        XCTAssertEqual(resolved.map { $0?["agent"] as? Bool }, [nil, true, nil])
        XCTAssertEqual(resolved.map { $0?["agentName"] as? String }, [nil, "Claude", nil])
        XCTAssertNil(resolved[2])

        var reopened = mine
        reopened.resolved = nil
        try store.write(Drawing(key: key, pixels: pixels, pointScale: 2, marks: [], pins: [reopened], nextPin: 4))
        XCTAssertEqual(try file()["version"] as? Int, 2)
        let step = EditorHistory(undo: [.drawing(EditStep(name: .reopen, changes: [], selectionBefore: [], selectionAfter: [],
                                                          pins: [EditStep.PinChange(id: mine.id, before: mine, after: reopened)]))])
        try store.write(Drawing(key: key, pixels: pixels, pointScale: 2, marks: [], pins: [reopened], nextPin: 4), history: step)
        XCTAssertEqual(try file()["version"] as? Int, 3, "undo would bring the resolved pin back")
        try store.writeMessage("words", for: Drawing(key: key, pixels: pixels, pointScale: 2, marks: [], pins: [reopened], nextPin: 4), history: step)
        XCTAssertEqual(try file()["version"] as? Int, 3)
    }

    func testAnyResolvedValueReadsAsResolvedAndAFieldThatDoesNotReadIsLeftOut() throws {
        var flagged = item(1), named = item(2), null = item(3)
        flagged["resolved"] = true
        named["resolved"] = ["agent": true, "agentName": "Codex", "at": "yesterday"]
        null["resolved"] = NSNull()
        try FileManager.default.createDirectory(at: store.url(for: key).deletingLastPathComponent(), withIntermediateDirectories: true)
        let object: [String: Any] = ["version": 3, "key": key, "pixels": [800, 600], "pointScale": 2, "marks": [], "pins": [flagged, named, null]]
        try JSONSerialization.data(withJSONObject: object).write(to: store.url(for: key))
        let drawing = try XCTUnwrap(store.read(key: key, pixels: pixels, style: .standard))
        XCTAssertEqual(drawing.pins.map(\.resolved), [Pin.Resolution(), Pin.Resolution(agent: true, agentName: "Codex"), nil])
        XCTAssertEqual(lines.all, [])
    }

    func testAResolvedPinIsLeftOutOfWhatIsHandedOverAndAStitchKeepsItResolved() throws {
        var done = pin(1, .point(CGPoint(x: 100, y: 150)), "Done")
        done.resolved = .byPerson()
        let open = pin(2, .point(CGPoint(x: 200, y: 50)), "Open")
        let made = try writeTestImage(width: 300, height: 200, space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), in: dir) { _, _ in (0, 0, 255) }
        let drawing = Drawing(key: made.path, pixels: PixelSize(width: 300, height: 200), pointScale: 1, marks: [], pins: [done, open], nextPin: 3)
        XCTAssertEqual(drawing.handedOver.pins, [open])
        XCTAssertEqual(ScreenshotRequests.Carried.drawing.rendering(drawing).pins, [open])
        var allDone = drawing
        allDone.pins = [done]
        XCTAssertTrue(allDone.handedOver.isEmpty, "a drawing whose pins are all resolved hands over the picture alone")

        let composed = try XCTUnwrap(Stitch.compose([Stitch.Piece(url: made, drawing: drawing)], style: .standard, markStyle: .standard, longSideLimit: 10_000))
        XCTAssertEqual(composed.pins.map(\.resolved), [done.resolved, nil])
    }
}
