import AppKit
import XCTest

final class RenderingPromiseTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("rendering-promise-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    // MARK: Done's clipboard

    /// Done puts the path on the clipboard at once and promises the image, so a paste that comes
    /// before the rendering finishes waits for it instead of finding nothing or the old clipboard.
    /// A card with a drawing dragged out of the stack drops the same item.
    @MainActor
    func testThePromisedClipboardAnswersOnceTheRenderingIsDone() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.petepetrash.vignette.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let url = try writeTestImage(width: 120, height: 80, space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), in: dir) { _, _ in (255, 255, 255) }
        let drawing = Drawing(key: url.path, pixels: PixelSize(width: 120, height: 80), pointScale: 1,
                              marks: [Mark(geometry: .rectangle(CGRect(x: 30, y: 20, width: 40, height: 30)))])
        let file = dir.appendingPathComponent("Screenshot-annotated.png")

        let later = PendingRendering(file: file)
        Clipboard.copyRendering(later, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), file.path, "the path is there at once")
        let png = try Rendering.png(of: drawing, imageAt: url, style: .standard, markStyle: .standard)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { later.finish(png: png, failure: nil) }
        let asked = Date()
        XCTAssertEqual(pasteboard.data(forType: .png), png)
        XCTAssertGreaterThan(Date().timeIntervalSince(asked), 0.2, "the paste waited for the rendering")
        XCTAssertNotNil(pasteboard.data(forType: .tiff).flatMap(NSImage.init(data:)))
        XCTAssertEqual(pasteboard.string(forType: .fileURL), file.absoluteString)

        let rendered = RenderingQueue.shared.render(drawing, imageAt: url, output: .file, style: .standard, markStyle: .standard)
        let output = try XCTUnwrap(rendered.wait(timeout: 10))
        XCTAssertNil(output.failure)
        XCTAssertEqual(output.file, rendered.file)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(output.file)), output.png)

        // A rendering that fails takes its promise back, and never a copy made after it.
        func answered(_ rendering: PendingRendering) {
            rendering.finish(png: nil, failure: .unreadableImage("the file is gone"))
            let drained = expectation(description: "the main queue ran the rendering's answer")
            DispatchQueue.main.async { drained.fulfill() }
            wait(for: [drained], timeout: 1)
        }
        let failed = PendingRendering(file: file)
        Clipboard.copyRendering(failed, to: pasteboard)
        answered(failed)
        XCTAssertNil(pasteboard.string(forType: .string), "no path to a file that never appears")
        let overtaken = PendingRendering(file: file)
        Clipboard.copyRendering(overtaken, to: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("copied since", forType: .string)
        answered(overtaken)
        XCTAssertEqual(pasteboard.string(forType: .string), "copied since")

        // A drop has no clipboard to take back, so the item itself gives nothing for a rendering
        // that failed, even one that made its PNG and could not write the file.
        let unwritten = PendingRendering(file: file)
        pasteboard.clearContents()
        pasteboard.writeObjects([Clipboard.renderingItem(unwritten, loggedAs: "clipboard")])
        unwritten.finish(png: png, failure: .writeFailed("could not write the file"))
        XCTAssertNil(pasteboard.data(forType: .png))
        XCTAssertNil(pasteboard.data(forType: .tiff))
        XCTAssertNil(pasteboard.string(forType: .fileURL))
    }

    @MainActor
    func testAFileWriteFailureProvidesNoPromisedImageOrFile() throws {
        guard geteuid() != 0 else { throw XCTSkip("root can write a read-only directory") }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.petepetrash.vignette.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let source = try writeTestImage(width: 120, height: 80, space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), in: dir) { _, _ in (255, 255, 255) }
        let drawing = Drawing(key: source.path, pixels: PixelSize(width: 120, height: 80), pointScale: 1, marks: [])
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path) }
        let rendering = RenderingQueue().render(drawing, imageAt: source, output: .file, style: .standard, markStyle: .standard)
        pasteboard.writeObjects([Clipboard.renderingItem(rendering, loggedAs: "clipboard")])
        let output = try XCTUnwrap(rendering.wait(timeout: 10))
        XCTAssertEqual(output.failure?.code, .writeFailed)
        XCTAssertNotNil(output.png)
        XCTAssertNil(output.file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(rendering.file).path))
        XCTAssertNil(pasteboard.data(forType: .png))
        XCTAssertNil(pasteboard.data(forType: .tiff))
        XCTAssertNil(pasteboard.string(forType: .fileURL))
    }

    // MARK: A drag

    @MainActor
    func testRenderedBytesBecomeAFileBesideTheScreenshotThatTheDropReceives() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.petepetrash.vignette.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let source = try writeTestImage(width: 120, height: 80, space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), in: dir) { _, _ in (255, 255, 255) }
        let drawing = Drawing(key: source.path, pixels: PixelSize(width: 120, height: 80), pointScale: 1,
                              marks: [Mark(geometry: .rectangle(CGRect(x: 10, y: 10, width: 30, height: 25)))])
        let queue = RenderingQueue()
        let bytes = queue.render(drawing, imageAt: source, output: .bytes, style: .standard, markStyle: .standard)
        let png = try XCTUnwrap(XCTUnwrap(bytes.wait(timeout: 10)).png)
        XCTAssertTrue(bytes.isDone)

        let first = queue.file(from: bytes, beside: source), second = queue.file(from: bytes, beside: source)
        pasteboard.writeObjects([Clipboard.renderingItem(first, loggedAs: "drag")])
        let firstFile = try XCTUnwrap(XCTUnwrap(first.wait(timeout: 10)).file)
        let secondFile = try XCTUnwrap(XCTUnwrap(second.wait(timeout: 10)).file)
        XCTAssertNotEqual(firstFile, secondFile)
        XCTAssertEqual(firstFile.deletingLastPathComponent().path, dir.path)
        XCTAssertTrue(firstFile.lastPathComponent.hasSuffix("-annotated.png"))
        XCTAssertEqual(try Data(contentsOf: firstFile), png)
        XCTAssertEqual(try Data(contentsOf: secondFile), png)
        XCTAssertEqual(pasteboard.data(forType: .png), png)
        XCTAssertEqual(pasteboard.string(forType: .fileURL), firstFile.absoluteString)
    }

    @MainActor
    func testBytesThatFailedWriteNoFileAndTheDropReceivesNoImage() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.petepetrash.vignette.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let source = dir.appendingPathComponent("not an image.png")
        try Data("text".utf8).write(to: source)
        let drawing = Drawing(key: source.path, pixels: PixelSize(width: 120, height: 80), pointScale: 1,
                              marks: [Mark(geometry: .rectangle(CGRect(x: 10, y: 10, width: 30, height: 25)))])
        let queue = RenderingQueue()
        let bytes = queue.render(drawing, imageAt: source, output: .bytes, style: .standard, markStyle: .standard)
        let file = queue.file(from: bytes, beside: source)
        pasteboard.writeObjects([Clipboard.renderingItem(file, loggedAs: "drag")])
        let output = try XCTUnwrap(file.wait(timeout: 10))
        XCTAssertEqual(output.failure?.code, .unreadableImage)
        XCTAssertNil(output.file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(file.file).path))
        XCTAssertNil(pasteboard.data(forType: .png))
        XCTAssertNil(pasteboard.string(forType: .fileURL))
    }
}
