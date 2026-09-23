import AppKit
import XCTest

final class AgentMarksTests: XCTestCase {
    private let sentence = "The strip sits 16 pt from the card now, which reads as one group. Is that enough room, or should it breathe more?"

    private func texts(_ marks: [Mark]) -> [Mark.Text] {
        marks.compactMap { if case .text(let text) = $0.geometry { return text } else { return nil } }
    }

    private func layout(_ text: Mark.Text, _ pixels: PixelSize, _ pointScale: CGFloat) -> TextLayout {
        TextLayout(text, imageWidth: CGFloat(pixels.width), pointScale: pointScale, style: .standard)
    }

    func testALongSentenceGetsTextOf2Point2PercentOfTheWidthWrappedInsideTheImage() throws {
        let pixels = PixelSize(width: 1800, height: 1200)
        // Near the bottom right, so it has to wrap and then move up and in.
        let result = AgentMark.marks([AgentMark(type: .text, x: 0.6, y: 0.95, text: sentence)], in: pixels, pointScale: 2, style: .standard)
        XCTAssertEqual(result.tooLong, [])
        let text = try XCTUnwrap(texts(result.marks).first)
        XCTAssertEqual(text.size * 2, 0.022 * 1800, accuracy: 1e-9, "2.2% of the width, in px")
        let fitted = layout(text, pixels, 2)
        XCTAssertGreaterThan(fitted.lines.count, 1)
        let margin = 0.02 * 1800 - 0.001
        XCTAssertTrue(pixels.bounds.insetBy(dx: margin, dy: margin).contains(fitted.box), "\(fitted.box) keeps the margin from every edge")
    }

    func testATextWithAWidthWrapsThere() throws {
        let pixels = PixelSize(width: 1800, height: 1200)
        let result = AgentMark.marks([AgentMark(type: .text, x: 0.1, y: 0.1, w: 0.25, text: sentence)], in: pixels, pointScale: 2, style: .standard)
        let text = try XCTUnwrap(texts(result.marks).first)
        XCTAssertEqual(text.wrap, 450)
        let lines = layout(text, pixels, 2).lines
        XCTAssertGreaterThan(lines.count, 2)
        XCTAssertTrue(lines.allSatisfy { $0.rect.width <= 450.001 })
        XCTAssertEqual(text.origin, CGPoint(x: 180, y: 120), "it fitted where it was put")
    }

    func testATextTooTallForTheImageIsWidenedFirst() throws {
        // At x 0.88 the room to the edge is a narrow column, which would run far past the bottom.
        let pixels = PixelSize(width: 2800, height: 600)
        let result = AgentMark.marks([AgentMark(type: .text, x: 0.88, y: 0.1, text: sentence + " " + sentence)], in: pixels, pointScale: 2, style: .standard)
        XCTAssertEqual(result.tooLong, [])
        let fitted = layout(try XCTUnwrap(texts(result.marks).first), pixels, 2)
        XCTAssertTrue(pixels.bounds.contains(fitted.box), "\(fitted.box)")
        XCTAssertGreaterThan(fitted.box.width, 0.15 * 2800, "wider than the column it started as")
    }

    func testASentenceTooLongForASmallImageIsReported() throws {
        let pixels = PixelSize(width: 800, height: 200)
        let long = String(repeating: sentence + " ", count: 10)
        let result = AgentMark.marks([
            AgentMark(type: .rectangle, x: 0.1, y: 0.1, w: 0.2, h: 0.2),
            AgentMark(type: .text, x: 0.3, y: 0.3, text: long),
        ], in: pixels, pointScale: 1, style: .standard)
        XCTAssertEqual(result.tooLong, [2], "counted from 1")
        let text = try XCTUnwrap(texts(result.marks).first)
        XCTAssertEqual(text.origin.y, 0, "its start shows")
        XCTAssertLessThanOrEqual(layout(text, pixels, 1).box.maxX, 800, "as wide as the image allows")
    }

    func testEveryMarkIsAnAgentsAndANamedColourIsKept() throws {
        let pixels = PixelSize(width: 1000, height: 500)
        let result = AgentMark.marks([
            AgentMark(type: .rectangle, x: 0.1, y: 0.2, w: 0.3, h: 0.4, color: "violet"),
            AgentMark(type: .ellipse, x: 0.8, y: 0.5, w: 0.4, h: 0.2),
            AgentMark(type: .arrow, x: 0.9, y: 0.1, x2: 0.5, y2: 0.3),
            // Not something `parse` passes, but a stored record read back could hold it.
            AgentMark(type: .rectangle, x: 0.1, y: 0.1),
        ], in: pixels, pointScale: 2, style: .standard)
        XCTAssertEqual(result.marks.map(\.geometry), [
            .rectangle(CGRect(x: 100, y: 100, width: 300, height: 200)),
            .ellipse(CGRect(x: 600, y: 250, width: 400, height: 100)),
            .arrow(Mark.Arrow(start: CGPoint(x: 900, y: 50), end: CGPoint(x: 500, y: 150))),
        ], "in px, and the ellipse that reached past the right edge moved inside; the mark without a size is dropped")
        XCTAssertTrue(result.marks.allSatisfy(\.agent))
        XCTAssertEqual(result.marks.map(\.color), [.violet, .red, .red])
        XCTAssertEqual(result.marks.map(\.colorChosen), [true, false, false])
    }

    /// The marks are ones a drawing file's validator takes, so a drawing built from them reads back
    /// as it was written, with nothing moved or dropped.
    func testADrawingOfAgentsMarksSurvivesAWriteAndARead() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("agent-marks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let lines = LogLines()
        let store = DrawingStore(directory: dir, log: { lines.append($0) })
        // So wide that 2.2% of it at this point scale is past the largest size a file may hold.
        let pixels = PixelSize(width: 24000, height: 2000)
        let result = AgentMark.marks([
            AgentMark(type: .rectangle, x: 0.9, y: 0.5, w: 0.3, h: 0.6, color: "white"),
            AgentMark(type: .arrow, x: 0.1, y: 0.9, x2: 0.3, y2: 0.2),
            AgentMark(type: .text, x: 0.95, y: 0.95, text: sentence),
            AgentMark(type: .text, x: 0.2, y: 0.1, w: 0.1, text: "Here"),
        ], in: pixels, pointScale: 0.5, style: .standard)
        XCTAssertEqual(texts(result.marks).map(\.size), [Mark.Text.maxSize, Mark.Text.maxSize])
        let drawing = Drawing(key: "/shots/Screenshot.png", pixels: pixels, pointScale: 0.5, marks: result.marks)
        try store.write(drawing)
        let read = try XCTUnwrap(store.read(key: drawing.key, pixels: pixels, style: .standard))
        XCTAssertEqual(read.marks.map(\.geometry), result.marks.map(\.geometry))
        XCTAssertEqual(read.marks.map(\.color), result.marks.map(\.color))
        XCTAssertEqual(lines.all, [])
    }
}
