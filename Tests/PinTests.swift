import AppKit
import XCTest

final class PinTests: XCTestCase {
    private var dir: URL!
    private var lines: LogLines!
    private var store: DrawingStore!
    private let key = "/Users/pete/Dropbox/Screenshots/Pinned.png"
    private let pixels = PixelSize(width: 800, height: 600)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-pins-\(UUID().uuidString)")
        lines = LogLines()
        store = DrawingStore(directory: dir, log: { [lines] in lines?.append($0) })
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func pin(_ number: Int, _ place: Pin.Place = .point(CGPoint(x: 100, y: 100)), _ text: String = "Too tight") -> Pin {
        Pin(id: UUID(), number: number, place: place, comments: [Pin.Comment(text: text)])
    }

    private func put(_ object: [String: Any]) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object).write(to: store.url(for: key))
    }

    private func file() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.url(for: key))) as? [String: Any])
    }

    private func written(_ pins: [[String: Any]], nextPin: Any? = nil) throws -> Drawing? {
        var object: [String: Any] = ["version": 2, "key": key, "pixels": [800, 600], "pointScale": 2, "marks": [], "pins": pins]
        object["nextPin"] = nextPin
        try put(object)
        return store.read(key: key, pixels: pixels, style: .standard)
    }

    private func item(_ number: Int, id: UUID = UUID(), x: Double = 100, y: Double = 100, comments: [[String: Any]] = [["text": "Too tight"]]) -> [String: Any] {
        ["id": id.uuidString, "number": number, "x": x, "y": y, "comments": comments]
    }

    func testAPinnedFileRoundTripsAsVersion2() throws {
        let point = Pin(id: UUID(), number: 1, place: .point(CGPoint(x: 120.5, y: 80)),
                        comments: [Pin.Comment(text: "Too tight"), Pin.Comment(text: "Agreed", agent: true, agentName: "Claude",
                                                                                at: Date(timeIntervalSince1970: 1_795_000_000.6))])
        let area = Pin(id: UUID(), number: 3, place: .area(CGRect(x: 300, y: 200, width: 150, height: 90), tip: .bottomRight),
                       comments: [Pin.Comment(text: "Whole card", agent: true, agentName: "Codex")])
        let drawing = Drawing(key: key, pixels: pixels, pointScale: 2, marks: [Mark(geometry: .ellipse(CGRect(x: 10, y: 10, width: 40, height: 40)))],
                              pins: [point, area], nextPin: 5)
        try store.write(drawing)
        let back = try XCTUnwrap(store.read(key: key, pixels: pixels, style: .standard))
        XCTAssertEqual(back.pins, [point, area])
        XCTAssertEqual(back.nextPin, 5)
        XCTAssertEqual(back.marks.map(\.geometry), drawing.marks.map(\.geometry))
        XCTAssertEqual(lines.all, [])
        let object = try file()
        XCTAssertEqual(object["version"] as? Int, 2)
        XCTAssertEqual(object["nextPin"] as? Int, 5)
        let pins = try XCTUnwrap(object["pins"] as? [[String: Any]])
        XCTAssertEqual(Set(pins[0].keys), ["id", "number", "x", "y", "comments"])
        XCTAssertEqual(Set(pins[1].keys), ["id", "number", "x", "y", "w", "h", "corner", "comments"])
        XCTAssertEqual(pins[1]["x"] as? Double, 300)
        XCTAssertEqual(pins[1]["corner"] as? String, "bottomRight")
        let comments = try XCTUnwrap(pins[0]["comments"] as? [[String: Any]])
        XCTAssertEqual(comments.map { $0["at"] as? String }, [nil, "2026-11-18T11:06:40Z"])

        let untimed = try XCTUnwrap(written([item(1, comments: [["text": "Too tight", "at": "yesterday"]])]))
        XCTAssertEqual(untimed.pins.first?.comments, [Pin.Comment(text: "Too tight")], "a time that does not read costs the comment nothing but its time")
    }

    func testOnlyAFileHoldingPinsANextPinOrAPinStepIsVersion2() throws {
        let box = Mark(geometry: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 50)))
        try store.write(Drawing(key: key, pixels: pixels, pointScale: 2, marks: [box]))
        XCTAssertEqual(try file()["version"] as? Int, 1)
        XCTAssertNil(try file()["pins"])
        XCTAssertNil(try file()["nextPin"])

        try store.write(Drawing(key: key, pixels: pixels, pointScale: 2, marks: [box], nextPin: 4))
        XCTAssertEqual(try file()["version"] as? Int, 2)

        try store.remove(key: key)
        let gone = pin(1)
        let deleted = EditorHistory(undo: [.drawing(EditStep(name: .delete, changes: [], selectionBefore: [], selectionAfter: [],
                                                             pins: [EditStep.PinChange(id: gone.id, before: gone, after: nil)]))])
        try store.write(Drawing(key: key, pixels: pixels, pointScale: 2, marks: [box]), history: deleted)
        XCTAssertEqual(try file()["version"] as? Int, 2)
        let step = try XCTUnwrap((try file()["history"] as? [String: Any])?["undo"] as? [[String: Any]]).first
        XCTAssertNil(step?["changes"], "a step that changed only pins")
        XCTAssertEqual((step?["pins"] as? [[String: Any]])?.first?["id"] as? String, gone.id.uuidString)
        try store.writeMessage("words", for: Drawing(key: key, pixels: pixels, pointScale: 2, marks: [box]), history: deleted)
        XCTAssertEqual(try file()["version"] as? Int, 2)
        try store.writeMessage("words", for: Drawing(key: key, pixels: pixels, pointScale: 2, marks: [box]))
        XCTAssertEqual(try file()["version"] as? Int, 1)

        try store.write(Drawing(key: key, pixels: pixels, pointScale: 2, marks: [box], nextPin: 6))
        try store.write(Drawing(key: key, pixels: pixels, pointScale: 2, marks: [box]))
        XCTAssertEqual(try file()["version"] as? Int, 2, "the file's nextPin is kept, and with it version 2")
    }

    func testADrawingHoldingOnlyPinsKeepsItsFileAndAnEmptyOneLosesItWhateverItsNextPin() throws {
        try store.write(Drawing(key: key, pixels: pixels, pointScale: 2, marks: [], pins: [pin(1)], nextPin: 2))
        XCTAssertEqual(try XCTUnwrap(store.read(key: key, pixels: pixels, style: .standard)).pins.map(\.number), [1])
        XCTAssertEqual(store.scan().drawings, [key])
        try store.write(Drawing(key: key, pixels: pixels, pointScale: 2, marks: [], nextPin: 2))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: key).path))
    }

    func testAWriteKeepsTheFilesHigherNextPin() throws {
        try store.write(Drawing(key: key, pixels: pixels, pointScale: 2, marks: [], pins: [pin(1)], nextPin: 7))
        try store.write(Drawing(key: key, pixels: pixels, pointScale: 2, marks: [], pins: [pin(1)]))
        XCTAssertEqual(try file()["nextPin"] as? Int, 7)
    }

    func testAPinOutsideTheImageIsMovedInWithOneLogLine() throws {
        let drawing = try XCTUnwrap(written([item(1, x: 900, y: -20),
                                             ["id": UUID().uuidString, "number": 2, "x": 700, "y": 550, "w": 300, "h": 200, "comments": [["text": "a"]]]]))
        XCTAssertEqual(drawing.pins.map(\.tip), [CGPoint(x: 800, y: 0), CGPoint(x: 500, y: 400)])
        guard case .area(let frame, _) = drawing.pins[1].place else { return XCTFail("the area pin became a point") }
        XCTAssertEqual(frame.size, CGSize(width: 300, height: 200))
        XCTAssertEqual(lines.all.filter { $0.hasPrefix("[drawing] moved pin=") }.count, 2, "\(lines.all)")
    }

    func testABadPinIsDroppedWithALogLineAndNextPinPassesTheHighestKept() throws {
        let repeated = UUID()
        let drawing = try XCTUnwrap(written([
            item(1, id: repeated),
            item(2, comments: []),
            item(1),
            item(3, id: repeated),
            item(4, comments: [["text": String(repeating: "a", count: MarkFields.maxTextLength + 1)]]),
            ["number": 5, "x": 1, "y": 1, "comments": [["text": "no id"]]],
            item(6),
        ], nextPin: 3))
        XCTAssertEqual(drawing.pins.map(\.number), [1, 6])
        XCTAssertEqual(drawing.nextPin, 7)
        XCTAssertEqual(try XCTUnwrap(written([item(4), item(2)])).pins.map(\.number), [2, 4], "read in number order")
        XCTAssertEqual(lines.all.filter { $0.hasPrefix("[drawing] dropped pin=") }.count, 5, "\(lines.all)")

        XCTAssertEqual(try XCTUnwrap(written([item(1)], nextPin: 9)).nextPin, 9, "a deleted pin's number is not given again")
    }

    func testPinsPastTheMostAScreenshotHoldsAreDropped() throws {
        let drawing = try XCTUnwrap(written((1...(Pin.maxCount + 1)).map { item($0) }))
        XCTAssertEqual(drawing.pins.count, Pin.maxCount)
    }

    func testAPinStepUndoesAndRedoesAndSurvivesTheFile() throws {
        let kept = pin(1), moved = pin(2)
        var after = moved
        after.place = .point(CGPoint(x: 400, y: 300))
        let step = EditStep(name: .move, changes: [], selectionBefore: [], selectionAfter: [],
                            pins: [EditStep.PinChange(id: kept.id, before: kept, after: nil), EditStep.PinChange(id: moved.id, before: moved, after: after)])
        let now = Drawing(key: key, pixels: pixels, pointScale: 2, marks: [], pins: [after], nextPin: 3)
        let undone = step.applied(to: now, forward: false)
        XCTAssertEqual(undone.pins, [kept, moved], "the deleted pin comes back with its number, in number order")
        XCTAssertEqual(undone.nextPin, 3)
        XCTAssertEqual(step.applied(to: undone, forward: true).pins, [after])

        try store.write(now, history: EditorHistory(undo: [.drawing(step)]))
        let read = try XCTUnwrap(store.read(key: key, pixels: pixels, style: .standard))
        let history = store.readHistory(key: key, pixels: pixels, marks: read.marks, pins: read.pins)
        guard case .drawing(let back)? = history.undo.first else { return XCTFail("the pin step was dropped: \(lines.all)") }
        XCTAssertEqual(back.applied(to: read, forward: false).pins, [kept, moved])

        var further = after
        further.place = .point(CGPoint(x: 500, y: 300))
        let next = EditStep(name: .move, changes: [], selectionBefore: [], selectionAfter: [],
                            pins: [EditStep.PinChange(id: moved.id, before: after, after: further)])
        let merged = try XCTUnwrap(step.merged(with: next))
        XCTAssertEqual(merged.pins.first { $0.id == moved.id }?.after, further)
        XCTAssertEqual(merged.applied(to: now, forward: false).pins, [kept, moved])
        let back2 = EditStep(name: .move, changes: [], selectionBefore: [], selectionAfter: [],
                             pins: [EditStep.PinChange(id: moved.id, before: further, after: after)])
        XCTAssertNil(next.merged(with: back2), "a move and its reverse leave nothing to undo")
    }

    func testAStoredStepThatNamesAPinTwiceDropsTheHistory() throws {
        let one = pin(1)
        let change = EditStep.PinChange(id: one.id, before: nil, after: one)
        let twice = EditorHistory(undo: [.drawing(EditStep(name: .rectangle, changes: [], selectionBefore: [], selectionAfter: [], pins: [change, change]))])
        let drawing = Drawing(key: key, pixels: pixels, pointScale: 2, marks: [], pins: [one], nextPin: 2)
        try store.write(drawing, history: twice)
        XCTAssertTrue(store.readHistory(key: key, pixels: pixels, marks: [], pins: [one]).isEmpty)
        XCTAssertTrue(lines.all.contains { $0.contains("names a pin twice") }, "\(lines.all)")
    }

    func testAHistoryIsDroppedOnceItsPinsChangedOutsideTheEditor() throws {
        let one = pin(1)
        let added = EditorHistory(undo: [.drawing(EditStep(name: .rectangle, changes: [], selectionBefore: [], selectionAfter: [],
                                                           pins: [EditStep.PinChange(id: one.id, before: nil, after: one)]))])
        try store.write(Drawing(key: key, pixels: pixels, pointScale: 2, marks: [], pins: [one], nextPin: 2), history: added)
        var object = try file()
        var pins = try XCTUnwrap(object["pins"] as? [[String: Any]])
        pins[0]["x"] = 101
        object["pins"] = pins
        try put(object)
        let read = try XCTUnwrap(store.read(key: key, pixels: pixels, style: .standard))
        XCTAssertTrue(store.readHistory(key: key, pixels: pixels, marks: read.marks, pins: read.pins).isEmpty)
        XCTAssertEqual(lines.all.filter { $0.contains("history dropped") && $0.contains("the drawing or the message changed") }.count, 1, "\(lines.all)")
    }

    func testATeardropAtThePicturesTopOrRightEdgeFlipsInsideIt() {
        let picture = CGRect(x: 0, y: 0, width: 800, height: 600)
        let cases: [(CGPoint, PinTeardrop.Orientation)] = [
            (CGPoint(x: 400, y: 300), .upRight),
            (CGPoint(x: 400, y: 10), .downRight),
            (CGPoint(x: 790, y: 300), .upLeft),
            (CGPoint(x: 790, y: 10), .downLeft),
            (CGPoint(x: 400, y: MarkStyle.standard.pin.side * 2 + 1), .downRight),
            (CGPoint(x: 800 - MarkStyle.standard.pin.side * 2 - 1, y: 300), .upLeft),
        ]
        for (tip, orientation) in cases {
            let drop = PinTeardrop(Pin(id: UUID(), number: 12, place: .point(tip), comments: [Pin.Comment(text: "a")]),
                                   in: pixels, pointScale: 2, markStyle: .standard)
            XCTAssertEqual(drop.orientation, orientation, "at \(tip)")
            XCTAssertTrue(picture.contains(drop.square), "at \(tip): \(drop.square)")
            XCTAssertTrue(drop.body.contains(tip.moved(toward: drop.square, by: 1)), "the tip is the body's corner at \(tip)")
        }
    }

    @MainActor
    func testSendsLineCarriesEachPinsWordsAfterTheMessageAndPinsJSONKeepsThem() async throws {
        let catcher = LineCatcher()
        let root = dir.appendingPathComponent("requests")
        let requests = ScreenshotRequests(root: root, connections: [.claude: catcher])
        var shimmer = pin(3, .area(CGRect(x: 10, y: 20, width: 30, height: 40), tip: .topLeft), "the shimmer effect is too narrow; needs more width and spread.")
        shimmer.comments.append(Pin.Comment(text: "can we have the dot indicator\npulse gently with a subtle glow?"))
        let pins = [shimmer, pin(1, .point(CGPoint(x: 5, y: 5)), "remove extra margin"), pin(2, .point(CGPoint(x: 6, y: 6)), "why such a big gap between these?")]
        let arrived = expectation(description: "the line reached the client")
        catcher.onSubmit = { arrived.fulfill() }
        let record = try requests.send(.drawing(png: Data([1]), pins: pins), source: URL(fileURLWithPath: key).screenshotKey,
                                       to: AgentDestination(id: "s", name: "A session", address: .claudeSession("session-1")),
                                       message: "Tighten the session menu", instructions: "")
        await fulfillment(of: [arrived], timeout: 3)
        let directory = ReplyProtocol.requestDirectory(root: root, requestID: record.id)
        let image = directory.appendingPathComponent("image.png").path
        XCTAssertEqual(catcher.lines, ["Tighten the session menu. Pin 1: remove extra margin. Pin 2: why such a big gap between these? "
            + "Pin 3: the shimmer effect is too narrow; needs more width and spread. / can we have the dot indicator pulse gently with a subtle glow? "
            + "[From Vignette: \"\(image)\".]"])
        XCTAssertEqual(ScreenshotRequests.requestLine(record: record, root: root, instructions: "", pins: [pins[1]]),
                       "Pin 1: remove extra margin. [From Vignette: \"\(image)\".]")
        XCTAssertEqual(ScreenshotRequests.requestLine(record: record, root: root, message: "check this :)", instructions: "", pins: [pins[2]]),
                       "check this :) Pin 2: why such a big gap between these? [From Vignette: \"\(image)\".]")
        let stored = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("pins.json"))) as? [String: Any])
        let listed = try XCTUnwrap(stored["pins"] as? [[String: Any]])
        XCTAssertEqual(listed.map { $0["number"] as? Int }, [1, 2, 3])
        XCTAssertEqual(listed.first?["id"] as? String, pins[1].id.uuidString)
        XCTAssertEqual(listed.last?["w"] as? Double, 30)
        XCTAssertEqual((listed.last?["comments"] as? [[String: Any]])?.count, 2)

        let plainArrived = expectation(description: "the plain line reached the client")
        catcher.onSubmit = { plainArrived.fulfill() }
        let plain = try requests.send(.drawing(png: Data([1])), source: URL(fileURLWithPath: key).screenshotKey,
                                      to: AgentDestination(id: "s", name: "A session", address: .claudeSession("session-1")))
        await fulfillment(of: [plainArrived], timeout: 3)
        XCTAssertEqual(catcher.lines.count, 2)
        let plainFolder = ReplyProtocol.requestDirectory(root: root, requestID: plain.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: plainFolder.appendingPathComponent("pins.json").path))
    }

    func testWordsAloneSendTheCardsPictureWithoutTheAgentsPins() {
        let drawing = Drawing(key: key, pixels: pixels, pointScale: 1, marks: [Mark(geometry: .rectangle(CGRect(x: 1, y: 1, width: 9, height: 9)))],
                              pins: [pin(1)], nextPin: 2)
        XCTAssertTrue(ScreenshotRequests.Carried.wordsAlone.rendering(drawing).isEmpty)
        XCTAssertEqual(ScreenshotRequests.Carried.drawing.rendering(drawing), drawing)
    }

    func testAStitchsPieceNumbersSurviveItsFileAndAreCutToTheImage() throws {
        let inside = CGRect(x: 10, y: 10, width: 40, height: 40)
        let drawing = Drawing(key: key, pixels: pixels, pointScale: 2, marks: [], pins: [pin(1)], nextPin: 2,
                              pieceNumbers: [inside, CGRect(x: 780, y: 590, width: 40, height: 40), CGRect(x: 900, y: 10, width: 40, height: 40)])
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try drawing.encoded().write(to: store.url(for: key))
        let back = try XCTUnwrap(store.read(key: key, pixels: pixels, style: .standard))
        XCTAssertEqual(back.pieceNumbers, [inside, CGRect(x: 780, y: 590, width: 20, height: 10)])
        XCTAssertNotNil(try file()["pieceNumbers"])
        var plain = drawing
        plain.pieceNumbers = []
        try plain.encoded().write(to: store.url(for: key))
        XCTAssertNil(try file()["pieceNumbers"])
    }
}

private extension CGPoint {
    func moved(toward square: CGRect, by distance: CGFloat) -> CGPoint {
        CGPoint(x: x + (square.midX > x ? distance : -distance), y: y + (square.midY > y ? distance : -distance))
    }
}

private final class LineCatcher: AgentConnection, @unchecked Sendable {
    let client = AgentClient.claude
    private let lock = NSLock()
    private var sent: [String] = []
    private var arrived: (@Sendable () -> Void)?

    var onSubmit: (@Sendable () -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return arrived }
        set { lock.lock(); arrived = newValue; lock.unlock() }
    }

    var lines: [String] { lock.lock(); defer { lock.unlock() }; return sent }
    func destinations() -> [AgentDestination] { [] }
    func submit(_ line: String, to destination: AgentDestination) -> SubmissionOutcome {
        lock.lock(); sent.append(line); lock.unlock()
        onSubmit?()
        return .accepted(detail: "")
    }
}
