import AppKit
import XCTest

final class CommandsTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-commands-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    // MARK: parse

    func testParsesNameAndFilesWithOneDecode() {
        let r = Commands.parse(URL(string: "vignette://annotate?file=/tmp/a%20b.png&file=/tmp/100%25.png")!)
        XCTAssertEqual(r.name, "annotate")
        XCTAssertEqual(r.files.map(\.path), ["/tmp/a b.png", "/tmp/100%.png"])
    }

    func testExpandsTildeAndIgnoresOtherQueryItems() {
        let r = Commands.parse(URL(string: "vignette://copy?tag=x&file=~/Desktop/s.png")!)
        XCTAssertEqual(r.files, [URL(fileURLWithPath: NSHomeDirectory() + "/Desktop/s.png")])
    }

    func testTagIsReadFromTheQuery() {
        XCTAssertEqual(Commands.parse(URL(string: "vignette://state?tag=t%201")!).tag, "t 1")
        XCTAssertNil(Commands.parse(URL(string: "vignette://state")!).tag)
    }

    func testAddParsesTheAnnotateFlag() {
        XCTAssertTrue(Commands.parse(URL(string: "vignette://add?file=/tmp/x.png&annotate")!).annotate)
        XCTAssertTrue(Commands.parse(URL(string: "vignette://add?file=/tmp/x.png&annotate=1")!).annotate)
        XCTAssertFalse(Commands.parse(URL(string: "vignette://add?file=/tmp/x.png&annotate=0")!).annotate)
        XCTAssertFalse(Commands.parse(URL(string: "vignette://add?file=/tmp/x.png")!).annotate)
    }

    func testAddParsesTheAgentName() {
        XCTAssertEqual(Commands.parse(URL(string: "vignette://add?file=/tmp/x.png&agent=claude")!).agent, "claude")
        XCTAssertEqual(Commands.parse(URL(string: "vignette://add?file=/tmp/x.png&agent")!).agent, "",
                       "the parameter without a name still means an agent added it")
        XCTAssertNil(Commands.parse(URL(string: "vignette://add?file=/tmp/x.png")!).agent)
        XCTAssertEqual(Commands.parse(URL(string: "vignette://add?agent=%20claude%20code%0A")!).agent, "claude code",
                       "a name is one trimmed line: the log and the state report are one line each")
        XCTAssertEqual(Commands.parse(URL(string: "vignette://add?agent=\(String(repeating: "x", count: 200))")!).agent?.count, Agent.maxLength)
    }

    func testInstallSkillParsesItsRoot() {
        XCTAssertEqual(Commands.parse(URL(string: "vignette://install-skill?root=/tmp/agent%20home")!).root,
                       URL(fileURLWithPath: "/tmp/agent home"))
        XCTAssertNil(Commands.parse(URL(string: "vignette://install-skill")!).root)
        XCTAssertTrue(Commands.isKnown("install-skill"))
        XCTAssertFalse(Commands.needsDebug("install-skill"), "a script installs the skill without debug; only root= needs it")
    }

    func testAddDestinationNeverOverwrites() {
        let folder = dir.appendingPathComponent("shots")
        let source = URL(fileURLWithPath: "/tmp/agent/x.png")
        let taken: Set<String> = ["x.png", "x 2.png"]
        XCTAssertEqual(Commands.destination(for: source, in: folder) { taken.contains($0.lastPathComponent) },
                       folder.appendingPathComponent("x 3.png"))
        XCTAssertEqual(Commands.destination(for: source, in: folder) { _ in false }, folder.appendingPathComponent("x.png"))
    }

    // MARK: marks

    func testMarksComeFromAFileOrFromTheURLItself() throws {
        let file = dir.appendingPathComponent("marks.json")
        try Data(#"[{"type":"ellipse","x":0.1,"y":0.2,"w":0.3,"h":0.4,"color":"red"}]"#.utf8).write(to: file)
        XCTAssertEqual(Commands.parse(URL(string: "vignette://add?file=/tmp/x.png&marks=/tmp/m.json")!).marks, "/tmp/m.json")
        XCTAssertEqual(try AgentMark.parse(file.path), [AgentMark(type: .ellipse, x: 0.1, y: 0.2, w: 0.3, h: 0.4, color: "red")])
        XCTAssertEqual(try AgentMark.parse(#"[{"type":"arrow","x":0.5,"y":0.5,"x2":0.7,"y2":0.6}]"#),
                       [AgentMark(type: .arrow, x: 0.5, y: 0.5, x2: 0.7, y2: 0.6)])
        XCTAssertEqual(try AgentMark.parse(#"[{"type":"text","x":0.1,"y":0.8,"text":"Header should not scroll"}]"#),
                       [AgentMark(type: .text, x: 0.1, y: 0.8, text: "Header should not scroll")])
        // A text mark may name the box its words wrap in; without one it takes the room to the edge.
        XCTAssertEqual(try AgentMark.parse(#"[{"type":"text","x":0.1,"y":0.8,"w":0.4,"text":"Header should not scroll"}]"#),
                       [AgentMark(type: .text, x: 0.1, y: 0.8, w: 0.4, text: "Header should not scroll")])
        XCTAssertEqual(try AgentMark.parse(#"[{"type":"rectangle","x":0,"y":1,"w":1,"h":0.5,"color":"light-blue"}]"#),
                       [AgentMark(type: .rectangle, x: 0, y: 1, w: 1, h: 0.5, color: "light-blue")])
    }

    func testMarksNameTheOneThingWrong() throws {
        let cases = [
            ("/tmp/does-not-exist.json", "cannot read"),
            ("[]", "no marks"),
            (#"{"type":"ellipse"}"#, "expected a JSON array"),
            ("[" + String(repeating: #"{"type":"text","x":0,"y":0,"text":"x"},"#, count: AgentMark.maxCount) + #"{"type":"text","x":0,"y":0,"text":"x"}]"#, "at most \(AgentMark.maxCount)"),
            (#"[{"type":"ellipse","x":0,"y":0,"w":0.1,"h":0.1},{"type":"circle","x":0,"y":0}]"#, "mark 2: unknown type"),
            (#"[{"type":"ellipse","x":340,"y":120,"w":0.1,"h":0.1}]"#, "x must be a number from 0 to 1, a fraction of the image"),
            (#"[{"type":"ellipse","x":"0.5","y":0,"w":0.1,"h":0.1}]"#, "x must be a number from 0 to 1"),
            ("[" + String(repeating: " ", count: AgentMark.maxBytes) + "]", "at most \(AgentMark.maxBytes / 1024) KB"),
            (#"[{"type":"ellipse","x":0,"y":0,"w":0,"h":0.1}]"#, "w must be more than 0"),
            (#"[{"type":"arrow","x":0.1,"y":0.1,"x2":0.1,"y2":0.1}]"#, "ends where it starts"),
            (#"[{"type":"text","x":0.1,"y":0.1}]"#, "text is missing"),
            (#"[{"type":"text","x":0.1,"y":0.1,"w":1.4,"text":"x"}]"#, "w must be a number from 0 to 1"),
            (#"[{"type":"text","x":0.1,"y":0.1,"w":0,"text":"x"}]"#, "w must be more than 0"),
            (#"[{"type":"text","x":0.1,"y":0.1,"text":"  \n "}]"#, "text is missing"),
            ("[{\"type\":\"text\",\"x\":0.1,\"y\":0.1,\"text\":\"" + String(repeating: "x", count: 2001) + "\"}]", "text is longer than 2000 characters"),
            (#"[{"type":"ellipse","x":0.1,"y":0.1,"w":0.1,"h":0.1,"color":"blue"}]"#, "mark 1: color must be one of red, yellow, light-blue, white, violet"),
            (#"[{"type":"ellipse","x":true,"y":0.1,"w":0.1,"h":0.1}]"#, "x must be a number from 0 to 1"),
            (#"[{"type":"ellipse","x":0.1,"y":0.1,"w":0.1,"h":0.1},{"type":"ellipse","x":0.1,"y":1e999,"w":0.1,"h":0.1}]"#, "mark 2: y must be a number from 0 to 1"),
        ]
        for (value, expected) in cases {
            XCTAssertThrowsError(try AgentMark.parse(value), value) { error in
                XCTAssertTrue("\(error)".contains(expected), "\(value) gave \"\(error)\", wanted \"\(expected)\"")
            }
        }
    }

    func testKnowsFixedCommandsAndActions() {
        XCTAssertTrue(Commands.isKnown("help"))
        XCTAssertTrue(Commands.isKnown("add"))
        XCTAssertFalse(Commands.needsDebug("add"))
        XCTAssertTrue(Commands.isKnown("copy"))
        XCTAssertFalse(Commands.isKnown("bogus"))
        XCTAssertFalse(Commands.isKnown(""))
        XCTAssertTrue(Commands.needsDebug("tweaks"))
        XCTAssertFalse(Commands.needsDebug("recent"))
        XCTAssertFalse(Commands.needsDebug("copy"))
    }

    // MARK: policy

    func testFilesOutsideTheWatchFolderAreRefusedUnlessDebug() {
        let folder = dir.appendingPathComponent("shots")
        let outside = dir.appendingPathComponent("elsewhere/x.png")
        XCTAssertEqual(Commands.policyError(for: outside, watchFolder: folder, debug: false), .outsideWatchFolder)
        XCTAssertNil(Commands.policyError(for: outside, watchFolder: folder, debug: true))
        XCTAssertNil(Commands.policyError(for: folder.appendingPathComponent("x.png"), watchFolder: folder, debug: false))
    }

    func testPrefixOfTheFolderNameIsNotInside() {
        let folder = dir.appendingPathComponent("shots")
        let sibling = dir.appendingPathComponent("shots-archive/x.png")
        XCTAssertEqual(Commands.policyError(for: sibling, watchFolder: folder, debug: false), .outsideWatchFolder)
    }

    func testDotDotCannotEscape() {
        let folder = dir.appendingPathComponent("shots")
        let escaped = folder.appendingPathComponent("../secret/x.png")
        XCTAssertEqual(Commands.policyError(for: escaped, watchFolder: folder, debug: false), .outsideWatchFolder)
    }

    func testSymlinksResolveOnBothSides() throws {
        let real = dir.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = dir.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        XCTAssertNil(Commands.policyError(for: link.appendingPathComponent("x.png"), watchFolder: real, debug: false))
        XCTAssertNil(Commands.policyError(for: real.appendingPathComponent("x.png"), watchFolder: link, debug: false))
        let elsewhere = dir.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let escapeLink = real.appendingPathComponent("out")
        try FileManager.default.createSymbolicLink(at: escapeLink, withDestinationURL: elsewhere)
        XCTAssertEqual(Commands.policyError(for: escapeLink.appendingPathComponent("x.png"), watchFolder: real, debug: false), .outsideWatchFolder,
                       "a link inside the folder that points out is still outside")
    }

    // MARK: readability

    func testReadableImageNeedsARealImage() throws {
        XCTAssertFalse(Commands.isReadableImage(dir.appendingPathComponent("missing.png")))
        let text = dir.appendingPathComponent("text.png")
        try "not a png".write(to: text, atomically: true, encoding: .utf8)
        XCTAssertFalse(Commands.isReadableImage(text))
        let png = dir.appendingPathComponent("real.png")
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try rep.representation(using: .png, properties: [:])!.write(to: png)
        XCTAssertTrue(Commands.isReadableImage(png))
    }

    // MARK: help and codes

    func testHelpNamesEveryCommandAndAction() {
        let lines = Commands.helpLines()
        for fixed in Commands.fixed { XCTAssertTrue(lines.contains { $0.hasPrefix(fixed.name + ":") }, fixed.name) }
        for action in Config.actions { XCTAssertTrue(lines.contains { $0.hasPrefix(action.id + ":") }, action.id) }
        XCTAssertEqual(lines.count, Commands.fixed.count + Config.actions.count)
    }

    /// A recording in the selection turns off everything that only works on images, rather than
    /// running it on the part it can take, and Return opens a recording where it draws on an image.
    func testActionsRunOnlyOnKindsTheyTake() {
        let image = Screenshot(url: URL(fileURLWithPath: "/tmp/Screenshot 1.png"))
        let recording = Screenshot(url: URL(fileURLWithPath: "/tmp/Screenshot 2.MOV"))
        let returnKey: (ShotAction.Key) -> Bool = { $0.character == "\r" && $0.modifiers.isEmpty }
        func ran(_ shots: [Screenshot]) -> String? {
            if case .run(let action) = Config.action(for: returnKey, on: shots) { return action.id }
            return nil
        }

        XCTAssertEqual(recording.kind, .recording)
        XCTAssertEqual(ran([image]), "annotate")
        XCTAssertEqual(ran([recording]), "open")
        XCTAssertNil(ran([image, recording]))
        guard case .unavailable = Config.action(for: returnKey, on: [image, recording]) else { return XCTFail("Return on a mixed selection") }

        XCTAssertEqual(Config.defaultAction(for: [recording])?.label, "Open")
        XCTAssertEqual(Config.defaultAction(for: [image])?.label, "Draw")
        for id in ["annotate", "copy-annotated", "stitch"] {
            XCTAssertNotNil(Config.action(id: id)?.unavailableReason(for: [image, image, recording]), id)
        }
        for id in ["copy", "paths", "trash"] {
            XCTAssertNil(Config.action(id: id)?.unavailableReason(for: [image, recording]), id)
        }

        // Draw and Open are one row, which shows the one that can run.
        let row = Config.stripRows.first { $0.contains { $0.id == "annotate" } } ?? []
        XCTAssertEqual(row.map(\.id), ["annotate", "open"])
        XCTAssertEqual(Config.stripAction(in: row, for: [recording]).id, "open")
        XCTAssertEqual(Config.stripAction(in: row, for: [image, recording]).id, "annotate")
    }

    func testErrorCodesAreKebabCaseAndUnique() {
        let codes = CommandError.allCases.map(\.rawValue)
        XCTAssertEqual(Set(codes).count, codes.count)
        for code in codes { XCTAssertNil(code.rangeOfCharacter(from: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz-").inverted), code) }
    }
}

final class AgentTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vignette-agent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    func testARecordedAgentReadsBackAndFollowsTheFile() throws {
        let file = dir.appendingPathComponent("Screenshot.png")
        try Data("png".utf8).write(to: file)
        XCTAssertNil(Agent.of(file), "a capture has no agent")
        Agent.record("claude", on: file)
        XCTAssertEqual(Agent.of(file), "claude")
        let renamed = dir.appendingPathComponent("Screenshot 2.png")
        try FileManager.default.moveItem(at: file, to: renamed)
        XCTAssertEqual(Agent.of(renamed), "claude", "the name travels with the file, not with its path")
        XCTAssertNil(Agent.of(dir.appendingPathComponent("gone.png")))
    }

    /// A push that names its Claude Code session is answered with Reply, which goes back to that
    /// session. Anything that is not a session id, or a push from another agent, names nowhere.
    func testAPushThatNamesItsSessionIsAReplyTarget() throws {
        let session = "E011FFF1-C791-4934-9E61-9307D840A5EB"
        XCTAssertEqual(Commands.parse(URL(string: "vignette://add?file=/tmp/x.png&agent=claude&session=\(session)")!).session, session)
        XCTAssertEqual(Agent.cleanSession(session), session.lowercased(), "herdr reports ids in lowercase")
        XCTAssertNil(Agent.cleanSession(""), "an unset variable sends an empty value")
        XCTAssertNil(Agent.cleanSession("../../etc"))

        let file = dir.appendingPathComponent("Checkout.png")
        try Data("png".utf8).write(to: file)
        Agent.record("claude", on: file)
        XCTAssertNil(Agent.origin(of: file), "a push that did not say which session is not a reply")
        Agent.record(session: session.lowercased(), on: file)
        XCTAssertEqual(Agent.origin(of: file)?.address, .claudeSession(session.lowercased()))
        Agent.record("codex", on: file)
        XCTAssertNil(Agent.origin(of: file), "only Claude Code's session id is known")
    }

    func testBadgeLabelNamesTheAgent() {
        XCTAssertEqual(Agent.label(for: "claude"), "From Claude")
        XCTAssertEqual(Agent.label(for: ""), "From an agent")
        XCTAssertNotNil(NSImage(systemSymbolName: Agent.fallbackSymbol, accessibilityDescription: nil), "the badge glyph must exist")
    }
}

final class ClipboardTests: XCTestCase {
    @MainActor
    func testPathsTextQuotesOnlyWhatAShellNeeds() {
        let plain = URL(fileURLWithPath: "/tmp/a.png")
        let spaced = URL(fileURLWithPath: "/tmp/Screenshot 1.png")
        let quoted = URL(fileURLWithPath: "/tmp/it's here.png")
        XCTAssertEqual(Clipboard.pathsText([plain]), "/tmp/a.png")
        XCTAssertEqual(Clipboard.pathsText([plain, spaced]), "/tmp/a.png\n'/tmp/Screenshot 1.png'")
        XCTAssertEqual(Clipboard.pathsText([quoted]), "'/tmp/it'\\''s here.png'")
    }
}
