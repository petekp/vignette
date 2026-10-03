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
        XCTAssertEqual(drawing.marks.first?.agent, false)
        XCTAssertEqual(lines.all, [])
    }

    func testADrawingSurvivesAWriteAndARead() throws {
        let marks = [
            Mark(geometry: .rectangle(CGRect(x: 410.25, y: 220, width: 640, height: 180.5))),
            Mark(geometry: .ellipse(CGRect(x: 10, y: 20, width: 30, height: 40)), agent: true),
            Mark(geometry: .arrow(.init(start: CGPoint(x: 100, y: 900), end: CGPoint(x: 700, y: 600), bend: -83.125))),
            Mark(geometry: .arrow(.init(start: CGPoint(x: 1, y: 2), end: CGPoint(x: 3, y: 4))), agent: true),
            Mark(geometry: .text(.init(origin: CGPoint(x: 50, y: 60), text: "Header should not scroll\nsecond line 你好 🎉", wrap: 900.5, size: 24))),
            Mark(geometry: .text(.init(origin: CGPoint(x: 0.1, y: 1.0 / 3.0), text: "no wrap", size: 31.7))),
        ]
        try store.write(Drawing(key: key, pixels: pixels, pointScale: 2, marks: marks))
        let back = try XCTUnwrap(read())
        XCTAssertEqual(back.pointScale, 2)
        XCTAssertEqual(back.marks.map(\.geometry), marks.map(\.geometry))
        XCTAssertEqual(back.marks.map(\.agent), marks.map(\.agent))
        XCTAssertEqual(lines.all, [])

        // The defaults are left out: a straight arrow has no bend, a text without one no wrap, and
        // `agent` is not written while it is false. No mark stores a colour.
        let file = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.url(for: key))) as? [String: Any])
        XCTAssertEqual(file["version"] as? Int, 1)
        XCTAssertEqual(file["pixels"] as? [Int], [3024, 1964])
        let written = try XCTUnwrap(file["marks"] as? [[String: Any]])
        XCTAssertEqual(Set(written[0].keys), ["type", "x", "y", "w", "h"])
        XCTAssertEqual(Set(written[1].keys), ["type", "x", "y", "w", "h", "agent"])
        XCTAssertEqual(Set(written[3].keys), ["type", "x", "y", "x2", "y2", "agent"])
        XCTAssertEqual(Set(written[5].keys), ["type", "x", "y", "text", "size"])
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
        XCTAssertEqual(store.scan(), [], "a newer build's drawing is not this build's to sweep")
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

    /// Only the launch's scan sets a bad file aside. A read runs off the main thread beside the
    /// main thread's writes, and a set-aside there could move the good file a write had just put
    /// in the bad one's place, losing its marks.
    func testAFileThatDoesNotParseIsSetAsideByTheLaunchScanOnly() throws {
        try put(#"{"version": 1, "key": "#)
        XCTAssertNil(read())
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: key).path), "a read leaves the file where it is")
        XCTAssertEqual(lines.all.count, 1)
        XCTAssertTrue(lines.all[0].hasPrefix("[drawing] error invalid"), lines.all[0])

        XCTAssertEqual(store.scan(), [])
        let aside = store.url(for: key).appendingPathExtension("invalid")
        XCTAssertEqual(aside.lastPathComponent, DrawingStore.id(for: key) + ".json.invalid")
        XCTAssertTrue(FileManager.default.fileExists(atPath: aside.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: key).path))
        XCTAssertEqual(lines.all.count, 2)
        XCTAssertTrue(lines.all[1].hasPrefix("[drawing] error invalid"), lines.all[1])

        // A top level that parses as JSON but is not a drawing is set aside the same way.
        try put(#"{"version": 1, "key": "\#(key)", "pixels": [3024], "pointScale": 2, "marks": []}"#)
        XCTAssertNil(read())
        XCTAssertEqual(store.scan(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: key).path))
        XCTAssertEqual(lines.all.count, 4)
    }

    func testAPointScaleOutsideHalfToEightMakesTheFileInvalid() throws {
        for scale in ["0.1", "9", "1e300", "1e-300"] {
            try put(#"{"version": 1, "key": "\#(key)", "pixels": [3024, 1964], "pointScale": \#(scale), "marks": [{"type": "rectangle", "x": 1, "y": 1, "w": 5, "h": 5, "color": "red"}]}"#)
            XCTAssertNil(read(), scale)
            XCTAssertTrue(lines.all.last?.hasPrefix("[drawing] error invalid") == true, "\(lines.all)")
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
        XCTAssertEqual(store.scan(), [], "it is not listed under a key whose name it does not have")
    }

    func testKeysListTheDrawingsThisBuildCanRead() throws {
        let rectangle = [Mark(geometry: .rectangle(CGRect(x: 1, y: 1, width: 5, height: 5)))]
        try store.write(Drawing(key: "/a.png", pixels: pixels, pointScale: 1, marks: rectangle))
        try store.write(Drawing(key: "/b.png", pixels: pixels, pointScale: 1, marks: rectangle))
        try put(#"{"version": 2, "key": "/c.png"}"#, for: "/c.png")
        try put("not json", for: "/d.png")
        try Data("x".utf8).write(to: dir.appendingPathComponent("notes.txt"))
        XCTAssertEqual(store.scan(), ["/a.png", "/b.png"])
        try store.remove(key: "/a.png")
        XCTAssertEqual(store.scan(), ["/b.png"])
        XCTAssertEqual(DrawingStore(directory: dir.appendingPathComponent("never-made")).scan(), [])
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

    /// A 300 by 200 screenshot in a person's red.
    private func redShot() throws -> URL {
        try writeTestImage(width: 300, height: 200, space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), in: dir) { _, _ in (0xe0, 0x31, 0x31) }
    }

    private let pushed = [AgentMark(type: .rectangle, x: 0.1, y: 0.1, w: 0.5, h: 0.5),
                          AgentMark(type: .ellipse, x: 0.5, y: 0.5, w: 0.2, h: 0.2, color: "red")]

    func testAgentsMarksJoinTheStoredDrawing() throws {
        let shot = try redShot()
        let pixels = try XCTUnwrap(PixelSize(imageAt: shot))
        let theirs = Mark(geometry: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 40)))
        drawings.write(Drawing(key: shot.path, pixels: pixels, pointScale: 1, marks: [theirs]), reason: "saved")

        let added = try drawings.add(pushed, from: nil, to: shot, style: .standard, newPointScale: 2)
        XCTAssertEqual(added, 2)
        let stored = try XCTUnwrap(drawings.read(shot, pixels: pixels, style: .standard))
        XCTAssertEqual(stored.pointScale, 1, "a stored drawing keeps its own scale")
        XCTAssertEqual(stored.marks.map(\.geometry).first, theirs.geometry, "the person's mark stays first")
        XCTAssertEqual(stored.marks.count, 3)
        XCTAssertEqual(stored.marks.dropFirst().map(\.agent), [true, true])
        XCTAssertEqual(stored.marks.dropFirst().map(\.color), [.agent, .agent], "a colour the agent names is ignored")

        // A screenshot with no drawing gets a new one at the scale it is given.
        let fresh = try redShot()
        XCTAssertEqual(try drawings.add(pushed, from: nil, to: fresh, style: .standard, newPointScale: 2), 2)
        let made = try XCTUnwrap(drawings.read(fresh, pixels: pixels, style: .standard))
        XCTAssertEqual(made.pointScale, 2)
        XCTAssertEqual(made.marks.count, 2)
        XCTAssertEqual(drawings.keys, [shot.path, fresh.path])
    }

    func testReplyRecoveryReusesTheCompleteStoredGeometryAndScale() throws {
        let shot = try redShot()
        let pixels = try XCTUnwrap(PixelSize(imageAt: shot))
        let reply = pushed + [AgentMark(type: .text, x: 0.2, y: 0.2, text: "A complete reply")]
        try drawings.installReply(reply, from: "claude", at: shot, style: .standard, newPointScale: 2)
        let checkpoint = try XCTUnwrap(drawings.store.readComplete(key: shot.path, pixels: pixels, style: .standard))
        let bytes = try Data(contentsOf: drawings.store.url(for: shot.path))
        let restarted = Drawings(store: drawings.store)
        var changedUI = UITweaks()
        changedUI.agentTextSize *= 2
        try restarted.installReply(reply, from: "claude", at: shot, style: changedUI.textStyle, newPointScale: 1)
        let recovered = try XCTUnwrap(restarted.store.readComplete(key: shot.path, pixels: pixels, style: .standard))
        XCTAssertEqual(recovered.pointScale, checkpoint.pointScale)
        XCTAssertEqual(recovered.marks.map(\.geometry), checkpoint.marks.map(\.geometry))
        XCTAssertEqual(recovered.marks.count, reply.count)
        XCTAssertEqual(try Data(contentsOf: drawings.store.url(for: shot.path)), bytes)
    }

    func testReplyRecoveryRefusesPartialOrCorruptCheckpoints() throws {
        let shot = try redShot()
        try drawings.installReply(pushed, from: "claude", at: shot, style: .standard, newPointScale: 2)
        let file = drawings.store.url(for: shot.path)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var marks = try XCTUnwrap(json["marks"] as? [[String: Any]])
        json["marks"] = [marks[0]]
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        XCTAssertThrowsError(try drawings.installReply(pushed, from: "claude", at: shot, style: .standard, newPointScale: 1))
        var outside = marks
        outside[1]["x"] = 1000
        json["marks"] = outside
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        XCTAssertThrowsError(try drawings.installReply(pushed, from: "claude", at: shot, style: .standard, newPointScale: 1))
        marks[1]["x"] = "invalid"
        json["marks"] = marks
        let partial = try JSONSerialization.data(withJSONObject: json)
        try partial.write(to: file)
        let restarted = Drawings(store: drawings.store)
        XCTAssertThrowsError(try restarted.installReply(pushed, from: "claude", at: shot, style: .standard, newPointScale: 1))
        XCTAssertEqual(try Data(contentsOf: file), partial)
        try Data("not JSON".utf8).write(to: file)
        let afterScan = Drawings(store: drawings.store)
        XCTAssertThrowsError(try afterScan.installReply(pushed, from: "claude", at: shot, style: .standard, newPointScale: 1))
        XCTAssertEqual(try Data(contentsOf: file.appendingPathExtension("invalid")), Data("not JSON".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testAPushToTheOpenDrawingWritesWhatTheJoinAnswersOnce() throws {
        let shot = try redShot()
        let pixels = try XCTUnwrap(PixelSize(imageAt: shot))
        let theirs = Mark(geometry: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 40)))
        let editor = FakeEditor(Drawing(key: shot.path, pixels: pixels, pointScale: 1, marks: [theirs]))
        drawings.open = editor
        var written: [Drawing?] = []
        drawings.onChange = { _, drawing in written.append(drawing) }

        XCTAssertEqual(try drawings.add(pushed, from: nil, to: shot, style: .standard, newPointScale: 2), 2)
        XCTAssertEqual(editor.drawing.marks.dropFirst().map(\.agent), [true, true], "the marks join the open drawing")
        XCTAssertEqual(written.map { $0?.marks.count }, [3], "one write, of the joined drawing")
        XCTAssertEqual(drawings.read(shot, pixels: pixels, style: .standard)?.marks.count, 3)

        // The push answers from the write, not from the marks having joined.
        try FileManager.default.removeItem(at: shot)
        XCTAssertThrowsError(try drawings.add(pushed, from: nil, to: shot, style: .standard, newPointScale: 2)) { error in
            XCTAssertEqual((error as? Drawings.Failure)?.code, .writeFailed)
        }
    }

    /// The editor hands its drawing over 0.3 s after a change, so until then the open drawing is the
    /// one now, for a copy, a stitch or a drag.
    func testTheDrawingNowIsTheOpenOneOverTheStoredOne() throws {
        let shot = try redShot(), other = try redShot()
        let pixels = try XCTUnwrap(PixelSize(imageAt: shot))
        let stored = Mark(geometry: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 40)))
        let drawn = Mark(geometry: .rectangle(CGRect(x: 90, y: 90, width: 50, height: 40)))
        drawings.write(Drawing(key: shot.path, pixels: pixels, pointScale: 1, marks: [stored]), reason: "saved")
        XCTAssertEqual(drawings.current(of: shot, style: .standard)?.marks.map(\.geometry), [stored.geometry])
        XCTAssertNil(drawings.current(of: other, style: .standard), "a screenshot with no drawing has none")

        let editor = FakeEditor(Drawing(key: shot.path, pixels: pixels, pointScale: 1, marks: [stored, drawn]))
        drawings.open = editor
        XCTAssertEqual(drawings.current(of: shot, style: .standard)?.marks.map(\.geometry), [stored.geometry, drawn.geometry])
        XCTAssertEqual(drawings.current(of: shot, stored: { XCTFail("the open drawing needs no stored one"); return nil })?.marks.count, 2)
        XCTAssertNil(drawings.current(of: other, style: .standard), "another screenshot is not the open one")

        editor.isOpen = false
        XCTAssertEqual(drawings.current(of: shot, style: .standard)?.marks.map(\.geometry), [stored.geometry])
        XCTAssertNil(drawings.current(of: shot, stored: { nil }), "the caller's copy, once nothing is open")
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

        drawings.load([shot], style: .standard) { loaded.append(contentsOf: $0.values) }
        drawings.write(new, reason: "saved")
        Drawings.loads.sync(flags: .barrier) {}
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(changed.map { $0?.marks }, [new.marks])
        XCTAssertTrue(loaded.isEmpty, "the load read the old drawing, or the new one, and either way the write already said")

        drawings.load([shot], style: .standard) { loaded.append(contentsOf: $0.values) }
        Drawings.loads.sync(flags: .barrier) {}
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(loaded.map { $0?.marks.map(\.geometry) }, [new.marks.map(\.geometry)], "read from disk, so the ids are new")

        drawings.remove([shot])
        XCTAssertEqual(changed.count, 2)
        XCTAssertNil(changed[1], "a removal says there is no drawing")
    }

    func testSweepUsesPresenceOnlyInTheSuccessfullyListedFolder() throws {
        let folder = dir.appendingPathComponent("Screenshots")
        let kept = folder.appendingPathComponent("kept.png").path, gone = folder.appendingPathComponent("gone.png").path
        let elsewhere = dir.appendingPathComponent("Unavailable/other.png").path
        let marks = [Mark(geometry: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 40)))]
        for key in [kept, gone, elsewhere] {
            try drawings.store.write(Drawing(key: key, pixels: PixelSize(width: 300, height: 200), pointScale: 1, marks: marks))
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: kept, contents: Data()))
        let launch = Drawings(store: drawings.store)
        launch.sweep(ScreenshotWatcher.Inventory(folder: folder, names: ["kept.png"], dates: [:],
                                                 observedAt: ProcessInfo.processInfo.systemUptime))
        XCTAssertEqual(launch.keys, [kept, elsewhere])
        XCTAssertEqual(Drawings(store: drawings.store).keys, [kept, elsewhere])
    }

    func testAQueuedInventoryCannotSweepANewerDrawingWrite() throws {
        let shot = try redShot()
        let inventory = ScreenshotWatcher.Inventory(folder: shot.deletingLastPathComponent(), names: [], dates: [:],
                                                     observedAt: ProcessInfo.processInfo.systemUptime)
        let drawing = Drawing(key: shot.path, pixels: PixelSize(width: 300, height: 200), pointScale: 1,
                              marks: [Mark(geometry: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 40)))])
        XCTAssertTrue(drawings.write(drawing, reason: "saved"))
        drawings.sweep(inventory)
        XCTAssertEqual(drawings.current(of: shot, style: .standard)?.marks.map(\.geometry), drawing.marks.map(\.geometry))
        XCTAssertEqual(Drawings(store: drawings.store).keys, [shot.path])
    }

    func testSweepKeepsAnExistingFileReachedThroughACaseAlias() throws {
        let actual = dir.appendingPathComponent("Mixed-Case.PNG")
        try FileManager.default.moveItem(at: redShot(), to: actual)
        let alias = dir.appendingPathComponent("mixed-case.png")
        guard FileManager.default.fileExists(atPath: alias.path) else {
            throw XCTSkip("This filesystem treats filename case as distinct.")
        }
        let mark = Mark(geometry: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 40)))
        let drawing = Drawing(key: alias.path, pixels: PixelSize(width: 300, height: 200), pointScale: 1, marks: [mark])
        XCTAssertTrue(drawings.write(drawing, reason: "saved"))
        let inventory = ScreenshotWatcher.Inventory(folder: dir, names: [actual.lastPathComponent], dates: [:],
                                                     observedAt: ProcessInfo.processInfo.systemUptime)
        drawings.sweep(inventory)
        XCTAssertEqual(Drawings(store: drawings.store).keys, [alias.path])
        XCTAssertEqual(drawings.current(of: alias, style: .standard)?.marks.map(\.geometry), [mark.geometry])
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

/// The editor's open drawing, without a window: a join adds the marks and answers the drawing.
@MainActor
private final class FakeEditor: OpenDrawing {
    var drawing: Drawing
    var isOpen = true

    init(_ drawing: Drawing) { self.drawing = drawing }

    func drawing(of key: String) -> Drawing? { isOpen && drawing.key == key ? drawing : nil }

    func join(_ marks: [Mark]) -> Drawing? {
        guard !marks.isEmpty else { return nil }
        drawing.marks += marks
        return drawing
    }
}
