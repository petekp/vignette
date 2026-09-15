import AppKit
import XCTest

final class CommandsTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("shotnote-commands-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    // MARK: parse

    func testParsesNameAndFilesWithOneDecode() {
        let r = Commands.parse(URL(string: "shotnote://annotate?file=/tmp/a%20b.png&file=/tmp/100%25.png")!)
        XCTAssertEqual(r.name, "annotate")
        XCTAssertEqual(r.files.map(\.path), ["/tmp/a b.png", "/tmp/100%.png"])
    }

    func testExpandsTildeAndIgnoresOtherQueryItems() {
        let r = Commands.parse(URL(string: "shotnote://copy?tag=x&file=~/Desktop/s.png")!)
        XCTAssertEqual(r.files, [URL(fileURLWithPath: NSHomeDirectory() + "/Desktop/s.png")])
    }

    func testEvalKeepsTheDecodedQuery() {
        let r = Commands.parse(URL(string: "shotnote://eval?return%201%2B1")!)
        XCTAssertEqual(r.name, "eval")
        XCTAssertEqual(r.query, "return 1+1")
        XCTAssertEqual(r.files, [])
    }

    func testKnowsFixedCommandsAndActions() {
        XCTAssertTrue(Commands.isKnown("help"))
        XCTAssertTrue(Commands.isKnown("copy"))
        XCTAssertFalse(Commands.isKnown("bogus"))
        XCTAssertFalse(Commands.isKnown(""))
        XCTAssertTrue(Commands.needsDebug("eval"))
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

    func testErrorCodesAreKebabCaseAndUnique() {
        let codes = CommandError.allCases.map(\.rawValue)
        XCTAssertEqual(Set(codes).count, codes.count)
        for code in codes { XCTAssertNil(code.rangeOfCharacter(from: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz-").inverted), code) }
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
