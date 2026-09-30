import AppKit
import ImageIO
import XCTest

final class MarkRenderingTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("rendering-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    // MARK: A full rendering

    func testADisplayP3RenderingKeepsItsSizeItsProfileAndEveryPixelTheMarksLeaveAlone() throws {
        let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        // Every pixel differs from its neighbours, so a pixel moved or converted anywhere shows.
        let url = try writeTestImage(width: 240, height: 160, space: p3, dpi: 144, in: dir) { x, y in
            (UInt8((x * 37 + y * 11) % 256), UInt8((x * 13 + y * 57) % 256), UInt8((x * y) % 256))
        }
        let frame = CGRect(x: 30, y: 20, width: 40, height: 30)
        let drawing = Drawing(key: url.path, pixels: PixelSize(width: 240, height: 160), pointScale: 2, marks: [Mark(geometry: .rectangle(frame))])
        let png = try Rendering.png(of: drawing, imageAt: url, style: .standard, markStyle: .standard)

        let source = try decode(Data(contentsOf: url)), rendered = try decode(png)
        XCTAssertEqual([rendered.width, rendered.height], [240, 160])
        XCTAssertEqual(rendered.colorSpace?.name, CGColorSpace.displayP3)
        XCTAssertEqual(rendered.colorSpace?.copyICCData() as Data?, source.colorSpace?.copyICCData() as Data?)
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil)), 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyDPIWidth] as? Double, 144, "it pastes at the size the screenshot does")

        // The stroke reaches half its 7 px width either side of the frame, its white edge 3 px past
        // that, and the edge's shadow, 6 px down and blurred over 20 px, past that.
        let reach: CGFloat = 36
        let before = try pixels(of: source), after = try pixels(of: rendered)
        var changedOutside = 0, inked = 0
        for y in 0..<160 {
            for x in 0..<240 {
                let i = (y * 240 + x) * 4
                let pixel = CGRect(x: x, y: y, width: 1, height: 1)
                let underStroke = frame.insetBy(dx: -reach, dy: -reach).intersects(pixel) && !frame.insetBy(dx: reach, dy: reach).contains(pixel)
                guard before[i..<i + 4] != after[i..<i + 4] else { continue }
                if underStroke { inked += 1 } else { changedOutside += 1 }
            }
        }
        XCTAssertEqual(changedOutside, 0, "every pixel outside the mark is the screenshot's own")
        XCTAssertGreaterThan(inked, 700)
        // Red is defined in sRGB and converted into the image's space.
        let red = try XCTUnwrap(MarkStyle.standard.personColor.cgColor.converted(to: p3, intent: .defaultIntent, options: nil)?.components)
        let i = (35 * 240 + 30) * 4
        XCTAssertEqual(Array(after[i..<i + 3]), red.prefix(3).map { UInt8(($0 * 255).rounded()) }, "the middle of the left stroke")
    }

    func testAnImageWithAnOrientationFlagRendersAsDisplayedWithTheMarksWhereTheDrawingPutThem() throws {
        let sRGB = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        // Stored 60 by 40 in four colours, turned a quarter clockwise for display: 40 by 60.
        let url = try writeTestImage(width: 60, height: 40, space: sRGB, orientation: 6, in: dir) { x, y in
            x < 30 ? (y < 20 ? (255, 0, 0) : (0, 0, 255)) : (y < 20 ? (0, 255, 0) : (255, 255, 255))
        }
        let frame = CGRect(x: 6, y: 6, width: 12, height: 12)
        let drawing = Drawing(key: url.path, pixels: PixelSize(width: 40, height: 60), pointScale: 1,
                              marks: [Mark(geometry: .rectangle(frame))])
        let rendered = try decode(Rendering.png(of: drawing, imageAt: url, style: .standard, markStyle: .standard))
        XCTAssertEqual([rendered.width, rendered.height], [40, 60])

        // ImageIO's own turned copy says where each colour is displayed.
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 60]
        let displayed = try pixels(of: XCTUnwrap(CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)))
        let after = try pixels(of: rendered)
        // Near enough rather than equal: the mark's shadow reaches a little way over some of them.
        for (x, y) in [(30, 10), (30, 50), (10, 50), (3, 25)] {
            let i = (y * 40 + x) * 4
            XCTAssertTrue(zip(after[i..<i + 3], displayed[i..<i + 3]).allSatisfy { abs(Int($0) - Int($1)) <= 8 }, "(\(x), \(y))")
        }
        let onStroke = (12 * 40 + 6) * 4
        XCTAssertEqual(Array(after[onStroke..<onStroke + 3]), [0xe0, 0x31, 0x31], "the rectangle's left side, in the displayed top-left corner")

        let madeOnTheFilesOwnSize = Drawing(key: url.path, pixels: PixelSize(width: 60, height: 40), pointScale: 1, marks: drawing.marks)
        XCTAssertThrowsError(try Rendering.png(of: madeOnTheFilesOwnSize, imageAt: url, style: .standard, markStyle: .standard)) {
            XCTAssertEqual(($0 as? Rendering.Failure)?.code, .unreadableImage)
        }
    }

    func testAFileThatIsNotAnImageFailsAsUnreadable() throws {
        let url = dir.appendingPathComponent("Screenshot.png")
        try Data("not a png".utf8).write(to: url)
        let drawing = Drawing(key: url.path, pixels: PixelSize(width: 10, height: 10), pointScale: 1, marks: [])
        XCTAssertThrowsError(try Rendering.png(of: drawing, imageAt: url, style: .standard, markStyle: .standard)) {
            XCTAssertEqual(($0 as? Rendering.Failure)?.code, .unreadableImage)
        }
    }

    /// The largest capture on this Mac. The rendering draws straight at this size, off the main thread.
    func testA3102By6780RenderingCompletesOffTheMainThread() throws {
        let sRGB = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let url = try writeTestImage(width: 3102, height: 6780, space: sRGB, in: dir) { _, y in (UInt8(y % 256), 40, 90) }
        let pixels = PixelSize(width: 3102, height: 6780)
        let drawing = Drawing(key: url.path, pixels: pixels, pointScale: 2, marks: [
            Mark(geometry: .rectangle(CGRect(x: 300, y: 600, width: 1500, height: 1200))),
            Mark(geometry: .arrow(Mark.Arrow(start: CGPoint(x: 2800, y: 6000), end: CGPoint(x: 600, y: 2400), bend: 400))),
            Mark(geometry: .text(Mark.Text(origin: CGPoint(x: 300, y: 4000), text: "The header should stay pinned", size: 24))),
        ])
        var rendered: Result<Data, Error>?
        DispatchQueue.global(qos: .userInitiated).sync {
            rendered = Result { try Rendering.png(of: drawing, imageAt: url, style: .standard, markStyle: .standard) }
        }
        let image = try decode(XCTUnwrap(rendered).get())
        XCTAssertEqual([image.width, image.height], [3102, 6780])
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

        let later = PendingRendering()
        Clipboard.copyRendering(later, file: file, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), file.path, "the path is there at once")
        let png = try Rendering.png(of: drawing, imageAt: url, style: .standard, markStyle: .standard)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { later.finish(png: png, file: file, failure: nil) }
        let asked = Date()
        XCTAssertEqual(pasteboard.data(forType: .png), png)
        XCTAssertGreaterThan(Date().timeIntervalSince(asked), 0.2, "the paste waited for the rendering")
        XCTAssertNotNil(pasteboard.data(forType: .tiff).flatMap(NSImage.init(data:)))
        XCTAssertEqual(pasteboard.string(forType: .fileURL), file.absoluteString)

        // The queue writes the file it was given, with the bytes the clipboard holds.
        let rendered = RenderingQueue.shared.render(drawing, imageAt: url, writingTo: file, style: .standard, markStyle: .standard)
        let output = try XCTUnwrap(rendered.wait(timeout: 10))
        XCTAssertNil(output.failure)
        XCTAssertEqual(output.file, file)
        XCTAssertEqual(try Data(contentsOf: file), output.png)

        // A rendering that fails takes its promise back, and never a copy made after it.
        func answered(_ rendering: PendingRendering) {
            rendering.finish(png: nil, file: nil, failure: .unreadableImage("the file is gone"))
            let drained = expectation(description: "the main queue ran the rendering's answer")
            DispatchQueue.main.async { drained.fulfill() }
            wait(for: [drained], timeout: 1)
        }
        let failed = PendingRendering()
        Clipboard.copyRendering(failed, file: file, to: pasteboard)
        answered(failed)
        XCTAssertNil(pasteboard.string(forType: .string), "no path to a file that never appears")
        let overtaken = PendingRendering()
        Clipboard.copyRendering(overtaken, file: file, to: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("copied since", forType: .string)
        answered(overtaken)
        XCTAssertEqual(pasteboard.string(forType: .string), "copied since")

        // A drop has no clipboard to take back, so the item itself gives nothing for a rendering
        // that failed, even one that made its PNG and could not write the file.
        let unwritten = PendingRendering()
        pasteboard.clearContents()
        pasteboard.writeObjects([Clipboard.renderingItem(unwritten, file: file)])
        unwritten.finish(png: png, file: nil, failure: .writeFailed("could not write the file"))
        XCTAssertNil(pasteboard.data(forType: .png))
        XCTAssertNil(pasteboard.data(forType: .tiff))
        XCTAssertNil(pasteboard.string(forType: .fileURL))
    }

    // MARK: Marks

    func testATextWithChineseCharactersAndAnEmojiDrawsInkForBoth() throws {
        let text = Mark.Text(origin: CGPoint(x: 10, y: 10), text: "这个😀", size: 24)
        let drawn = try marksAlone(Drawing(key: "", pixels: PixelSize(width: 300, height: 100), pointScale: 2,
                                           marks: [Mark(geometry: .text(text))]))

        let line = try XCTUnwrap(TextLayout(text, imageWidth: 300, pointScale: 2, style: .standard).lines.first)
        let chineseEnd = line.rect.minX + CTLineGetOffsetForStringIndex(line.ctLine, 2, nil)
        let emojiEnd = line.rect.minX + CTLineGetOffsetForStringIndex(line.ctLine, 4, nil)
        func count(from left: CGFloat, to right: CGFloat, where matches: (ArraySlice<UInt8>) -> Bool) -> Int {
            var found = 0
            for y in Int(line.rect.minY)..<Int(line.rect.maxY) {
                for x in Int(left)..<Int(right) where matches(drawn[(y * 300 + x) * 4..<(y * 300 + x) * 4 + 4]) { found += 1 }
            }
            return found
        }
        XCTAssertGreaterThan(count(from: line.rect.minX, to: chineseEnd) { Array($0) == [0xe0, 0x31, 0x31, 255] }, 50,
                             "the tag behind the Chinese characters is the mark's colour")
        XCTAssertGreaterThan(count(from: line.rect.minX, to: chineseEnd) { $0[$0.startIndex + 3] == 255 && $0.prefix(3).allSatisfy { $0 > 240 } }, 20,
                             "and the characters are white on it")
        XCTAssertGreaterThan(count(from: chineseEnd, to: emojiEnd) { $0[$0.startIndex] > 200 && $0[$0.startIndex + 1] > 150 && $0[$0.startIndex + 2] < 100 }, 50,
                             "the emoji draws in its own yellow")
    }

    /// A note is a tag filled with its mark's colour and rounded at its corners, inside a white edge,
    /// its words white, and an agent's note carries a white badge on its top edge.
    func testANoteIsARoundedTagInItsColourWithItsWordsAndAnAgentsBadge() throws {
        let pixels = PixelSize(width: 400, height: 200)
        let person = Mark.Text(origin: CGPoint(x: 20, y: 20), text: "IIII", size: 24)
        let agents = Mark.Text(origin: CGPoint(x: 20, y: 110), text: "IIII", size: 24)
        let drawn = try marksAlone(Drawing(key: "", pixels: pixels, pointScale: 1, marks: [
            Mark(geometry: .text(person)),
            Mark(geometry: .text(agents), agent: true, agentName: "claude"),
        ]))
        func pixel(_ x: CGFloat, _ y: CGFloat) -> [UInt8] {
            let i = (Int(y) * pixels.width + Int(x)) * 4
            return Array(drawn[i..<i + 4])
        }
        let layout = TextLayout(person, imageWidth: 400, pointScale: 1, style: .standard)
        let box = layout.box, line = try XCTUnwrap(layout.lines.first)
        XCTAssertEqual(pixel(box.minX + 4, box.midY), [0xe0, 0x31, 0x31, 255], "the padding is the mark's red")
        XCTAssertNotEqual(pixel(box.minX + 1, box.minY + 1), [0xe0, 0x31, 0x31, 255], "the corner is rounded off")
        XCTAssertTrue(pixel(box.maxX + 1, box.midY).allSatisfy { $0 > 240 }, "a white edge runs round it")
        XCTAssertLessThan(pixel(box.maxX + 3, box.midY)[3], 255, "and past the edge only its shadow is drawn")
        let stem = line.rect.minX + CTLineGetOffsetForStringIndex(line.ctLine, 1, nil) / 2
        XCTAssertEqual(pixel(stem, line.baseline - 4), [255, 255, 255, 255], "white words on red")

        let agent = TextLayout(agents, imageWidth: 400, pointScale: 1, style: TextStyle.standard.forAgent(named: "claude"))
        let badge = try XCTUnwrap(agent.badge).frame(on: agent.box)
        XCTAssertLessThan(badge.minY, agent.box.minY, "the badge crosses the tag's top edge")
        XCTAssertGreaterThan(agent.lines[0].rect.minY, badge.maxY, "and the words start below it")
        XCTAssertEqual(pixel(badge.maxX - badge.height / 2, badge.minY + 2), [255, 255, 255, 255], "the badge is white above the tag")

        let long = TextLayout(agents, imageWidth: 400, pointScale: 1,
                              style: TextStyle.standard.forAgent(named: "an-agent-with-a-very-long-name"))
        let longBadge = try XCTUnwrap(long.badge)
        XCTAssertLessThanOrEqual(CTLineGetTypographicBounds(longBadge.line, nil, nil, nil), NoteBadge.longestLabel * longBadge.fontSize + 0.5,
                                 "a long name is cut short")
        XCTAssertGreaterThanOrEqual(long.box.width, longBadge.leastTagWidth(padSide: long.padding.side) - 1e-9, "and the tag is as wide as its badge")
    }

    /// The head is aimed from the point on the body one head-length back from the tip, and the body
    /// stops there, so its round cap never shows past the tip or through a side, however tight the arc.
    func testTheArrowheadIsAimedAlongTheBodyAndCoversItsEnd() {
        let stroke = MarkStyle.standard.strokeWidth * 2
        let full = MarkStyle.standard.arrowheadLength * stroke
        let arrows: [(Mark.Arrow, headLength: CGFloat)] = [
            (Mark.Arrow(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 400, y: 10)), full),
            (Mark.Arrow(start: CGPoint(x: 400, y: 300), end: CGPoint(x: 20, y: 40)), full),
            (Mark.Arrow(start: CGPoint(x: 10, y: 200), end: CGPoint(x: 410, y: 200), bend: 60), full),
            // Half circles whose radius is 8 strokes, and 4, tighter than 6.
            (Mark.Arrow(start: CGPoint(x: 100, y: 100), end: CGPoint(x: 100 + 16 * stroke, y: 100), bend: -8 * stroke), full),
            (Mark.Arrow(start: CGPoint(x: 100, y: 100), end: CGPoint(x: 100 + 8 * stroke, y: 100), bend: 4 * stroke), full),
            // Bent past a half circle, with a radius of about 3.6 strokes.
            (Mark.Arrow(start: CGPoint(x: 100, y: 100), end: CGPoint(x: 140, y: 100), bend: 40), full),
            // A radius of 10.625 px, 1.5 strokes: the head is as long as the circle is wide.
            (Mark.Arrow(start: CGPoint(x: 100, y: 100), end: CGPoint(x: 110, y: 100), bend: 20), 21.25),
            // Freehand, arriving on a curve and on a hook tighter than the head.
            (Mark.Arrow(start: CGPoint(x: 50, y: 300), end: CGPoint(x: 400, y: 300), via: [CGPoint(x: 150, y: 150), CGPoint(x: 300, y: 250)]), full),
            (Mark.Arrow(start: CGPoint(x: 50, y: 300), end: CGPoint(x: 200, y: 290), via: [CGPoint(x: 200, y: 300), CGPoint(x: 210, y: 295)]), full),
        ]
        for (arrow, headLength) in arrows {
            let body = arrow.body(pointScale: 2)
            XCTAssertEqual(body.arc != nil, arrow.bend != 0, "the bent ones are drawn as arcs")
            let head = Arrowhead(body: body, strokeWidth: stroke, style: .standard)
            XCTAssertEqual(head.tip, arrow.end)
            // The middle of the base is on the body, a head's length from the tip.
            let base = CGPoint(x: (head.corners.0.x + head.corners.1.x) / 2, y: (head.corners.0.y + head.corners.1.y) / 2)
            XCTAssertEqual(hypot(arrow.end.x - base.x, arrow.end.y - base.y), headLength, accuracy: 1e-9, "\(arrow)")
            XCTAssertLessThan(body.distance(to: base), 1e-9, "\(arrow)")
            // The stroke stops there, and everything of its round cap ahead of the base is inside the head.
            let end = body.point(at: head.bodyEnd)
            XCTAssertLessThan(hypot(end.x - base.x, end.y - base.y), 1e-9, "\(arrow)")
            for step in 0..<72 {
                let angle = CGFloat(step) * .pi / 36
                let edge = CGPoint(x: end.x + cos(angle) * stroke / 2, y: end.y + sin(angle) * stroke / 2)
                let ahead = (edge.x - base.x) * (arrow.end.x - base.x) + (edge.y - base.y) * (arrow.end.y - base.y) > 1e-9
                XCTAssertTrue(!ahead || head.path.contains(edge), "\(arrow): the cap's edge at \(step * 5)°")
            }
        }
    }

    func testAFreehandArrowsBodyIsTheCurveThroughItsPoints() {
        let arrow = Mark.Arrow(start: CGPoint(x: 50, y: 300), end: CGPoint(x: 400, y: 300), via: [CGPoint(x: 150, y: 150), CGPoint(x: 300, y: 250)])
        let body = arrow.body(pointScale: 2)
        for point in [arrow.start, arrow.end] + arrow.via { XCTAssertLessThan(body.distance(to: point), 1e-9, "it passes through \(point)") }
        XCTAssertEqual(body.point(at: 0), arrow.start)
        XCTAssertEqual(body.point(at: 1), arrow.end)
        XCTAssertLessThan(body.bounds.minY, 150, "it bows past the highest point, as a smooth curve through it does")
        // The stroked path is the same curve, cut where the fraction says.
        for fraction: CGFloat in [0.25, 0.5, 0.9, 1] {
            let end = body.path(upTo: fraction).currentPoint, expected = body.point(at: fraction)
            XCTAssertEqual(hypot(end.x - expected.x, end.y - expected.y), 0, accuracy: 0.05, "at \(fraction)")
        }
    }

    func testAShortArrowGetsASmallerHeadOfTheSameShape() {
        let stroke = MarkStyle.standard.strokeWidth * 2
        let arrow = Mark.Arrow(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 30, y: 10))
        let head = Arrowhead(body: arrow.body(pointScale: 2), strokeWidth: stroke, style: .standard)
        let baseX = (head.corners.0.x + head.corners.1.x) / 2
        XCTAssertEqual(arrow.end.x - baseX, 10, accuracy: 1e-9, "half the body")
        XCTAssertEqual(abs(head.corners.0.y - head.corners.1.y) / (arrow.end.x - baseX),
                       MarkStyle.standard.arrowheadWidth / MarkStyle.standard.arrowheadLength, accuracy: 1e-9)
        XCTAssertGreaterThan(head.bodyEnd, 0, "some body still shows")
    }

    /// The drawing's marks over transparent pixels, as RGBA bytes in sRGB.
    private func marksAlone(_ drawing: Drawing) throws -> [UInt8] {
        let sRGB = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let ctx = try XCTUnwrap(CGContext(data: nil, width: drawing.pixels.width, height: drawing.pixels.height, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.translateBy(x: 0, y: CGFloat(drawing.pixels.height))
        ctx.scaleBy(x: 1, y: -1)
        drawing.draw(in: ctx, style: .standard, markStyle: .standard)
        return try pixels(of: XCTUnwrap(ctx.makeImage()))
    }

    private func decode(_ data: Data) throws -> CGImage {
        try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
    }
}

/// A PNG in `directory` whose pixel at (x, y), from the top-left, is `color(x, y)`: opaque, 8 bits a
/// channel, in `space`, with an orientation flag and a DPI when given.
func writeTestImage(width: Int, height: Int, space: CGColorSpace, orientation: Int? = nil, dpi: Double? = nil, in directory: URL,
                    color: (Int, Int) -> (UInt8, UInt8, UInt8)) throws -> URL {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let (red, green, blue) = color(x, y)
            let i = (y * width + x) * 4
            (bytes[i], bytes[i + 1], bytes[i + 2]) = (red, green, blue)
        }
    }
    let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
    let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
                                      decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let url = directory.appendingPathComponent("Screenshot \(UUID().uuidString).png")
    let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
    var properties: [CFString: Any] = [:]
    if let orientation { properties[kCGImagePropertyOrientation] = orientation }
    if let dpi { (properties[kCGImagePropertyDPIWidth], properties[kCGImagePropertyDPIHeight]) = (dpi, dpi) }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return url
}

/// An image's pixels as RGBA bytes, drawn in its own colour space so nothing is converted.
func pixels(of image: CGImage) throws -> [UInt8] {
    let space = try XCTUnwrap(image.colorSpace)
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try bytes.withUnsafeMutableBytes { buffer in
        let ctx = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                          bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setBlendMode(.copy)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return bytes
}

extension TextStyle {
    /// The default style with another weight for a person's notes and another line height.
    static func tweaked(weight: Double, lineHeight: Double) -> TextStyle {
        var ui = UITweaks()
        ui.textWeight = weight
        ui.textLineHeight = lineHeight
        return ui.textStyle
    }
}

extension MarkStyle {
    /// The default style with another arrowhead.
    static func tweaked(arrowheadLength: Double, arrowheadWidth: Double) -> MarkStyle {
        var ui = UITweaks()
        ui.arrowheadLength = arrowheadLength
        ui.arrowheadWidth = arrowheadWidth
        return ui.markStyle
    }
}
