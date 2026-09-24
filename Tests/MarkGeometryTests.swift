import AppKit
import XCTest

final class MarkGeometryTests: XCTestCase {
    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    // MARK: Arrows

    func testABendUnder8PtIsDrawnStraight() {
        let arrow = Mark.Arrow(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 200, y: 0), bend: 15)
        XCTAssertNil(arrow.body(pointScale: 2).arc, "15 px is 7.5 pt on a Retina drawing")
        XCTAssertNotNil(arrow.body(pointScale: 1).arc, "and 15 pt on a standard one")
        var negative = arrow
        negative.bend = -15
        XCTAssertNil(negative.body(pointScale: 2).arc, "either side")
        XCTAssertEqual(arrow.body(pointScale: 2).point(at: 0.5), CGPoint(x: 100, y: 0))
    }

    func testAPositiveBendBowsToTheRightOfTheDirectionOfTravel() {
        // Travelling right, with y down, the right-hand side is below the line.
        let arrow = Mark.Arrow(start: CGPoint(x: 0, y: 50), end: CGPoint(x: 200, y: 50), bend: 30)
        XCTAssertEqual(arrow.bendPoint, CGPoint(x: 100, y: 80))
        var back = arrow
        (back.start, back.end) = (arrow.end, arrow.start)
        XCTAssertEqual(back.bendPoint, CGPoint(x: 100, y: 20))
    }

    func testTheArcPassesThroughBothEndsAndTheBendPoint() {
        let shapes = [
            Mark.Arrow(start: CGPoint(x: 10, y: 20), end: CGPoint(x: 300, y: 140), bend: 60),
            Mark.Arrow(start: CGPoint(x: 10, y: 20), end: CGPoint(x: 300, y: 140), bend: -60),
            // Bent further than half its length: more than a semicircle.
            Mark.Arrow(start: CGPoint(x: 100, y: 100), end: CGPoint(x: 140, y: 100), bend: 90),
        ]
        for arrow in shapes {
            let body = arrow.body(pointScale: 2)
            XCTAssertNotNil(body.arc)
            XCTAssertLessThan(distance(body.point(at: 0), arrow.start), 1e-9)
            XCTAssertLessThan(distance(body.point(at: 1), arrow.end), 1e-9)
            XCTAssertLessThan(distance(body.point(at: 0.5), arrow.bendPoint), 1e-9, "the bend point is the arc's middle")
            XCTAssertLessThan(body.distance(to: arrow.bendPoint), 1e-9)
            XCTAssertLessThan(body.distance(to: arrow.start), 1e-9)
            // The drawn path goes through the bend point, and not through its mirror across the line.
            let stroke = body.path(upTo: 1).copy(strokingWithWidth: 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
            XCTAssertTrue(stroke.contains(arrow.bendPoint), "\(arrow)")
            let mirror = CGPoint(x: arrow.start.x + arrow.end.x - arrow.bendPoint.x, y: arrow.start.y + arrow.end.y - arrow.bendPoint.y)
            XCTAssertFalse(stroke.contains(mirror), "\(arrow)")
            // The bounds hold the whole arc, and are no bigger than it.
            let bounds = body.bounds
            let points = (0...2000).map { body.point(at: CGFloat($0) / 2000) }
            XCTAssertTrue(points.allSatisfy { bounds.insetBy(dx: -1e-9, dy: -1e-9).contains($0) }, "\(arrow)")
            let xs = points.map(\.x), ys = points.map(\.y)
            assertEqual(bounds, CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!), accuracy: 0.01)
        }
    }

    func testTheDistanceToAStraightBody() {
        let body = Mark.Arrow(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0)).body(pointScale: 1)
        XCTAssertEqual(body.distance(to: CGPoint(x: 50, y: 7)), 7)
        XCTAssertEqual(body.distance(to: CGPoint(x: 103, y: 4)), 5, "past the tip, from the tip")
    }

    func testTheLargestSafeBendKeepsTheArcInsideTheImage() {
        let image = CGRect(x: 0, y: 0, width: 400, height: 300)
        let arrows = [
            Mark.Arrow(start: CGPoint(x: 50, y: 250), end: CGPoint(x: 350, y: 250)),
            Mark.Arrow(start: CGPoint(x: 20, y: 20), end: CGPoint(x: 60, y: 30)),
            Mark.Arrow(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 400, y: 300)),
        ]
        for arrow in arrows {
            for wanted in [-10_000, -120, 40, 10_000] as [CGFloat] {
                let bend = arrow.largestBend(wanted, inside: image)
                XCTAssertTrue(image.contains(ArrowBody(start: arrow.start, end: arrow.end, bend: bend).bounds), "\(arrow) \(wanted)")
                XCTAssertTrue(bend == 0 || (bend > 0) == (wanted > 0), "it keeps the side it was asked for")
                if bend != wanted {
                    let further = bend + copysign(0.5, wanted)
                    XCTAssertFalse(image.contains(ArrowBody(start: arrow.start, end: arrow.end, bend: further).bounds),
                                   "half a px more would cross an edge: \(arrow) \(wanted) gave \(bend)")
                }
            }
        }
        let fits = arrows[0]
        XCTAssertEqual(fits.largestBend(40, inside: image), 40, "a bend whose arc fits is kept")
        XCTAssertEqual(fits.largestBend(80, inside: image), 50, accuracy: 0.001, "the arc bows down to the bottom edge and no further")
        let outside = Mark.Arrow(start: CGPoint(x: -5, y: 0), end: CGPoint(x: 60, y: 30))
        XCTAssertEqual(outside.largestBend(40, inside: image), 0, "no bend fits when an end is outside")
    }

    // MARK: Text

    private let words = "The header should not scroll with the rest of the page, it should stay pinned at the top."

    func testALongTextWrapsAtTheImagesEdgeLessTheMargin() {
        let text = Mark.Text(origin: CGPoint(x: 100, y: 20), text: words, size: 24)
        let layout = TextLayout(text, imageWidth: 800, pointScale: 2, style: .standard)
        XCTAssertGreaterThan(layout.lines.count, 1)
        for line in layout.lines {
            XCTAssertLessThanOrEqual(line.rect.maxX, 800 * 0.98 + 0.001, "no line passes the image's edge less 2%")
        }
        XCTAssertGreaterThan(layout.lines[0].rect.maxX, 800 * 0.98 - 200, "the first line runs up to the edge before it wraps")
        XCTAssertEqual(layout.box.width, layout.lines.map(\.rect.width).max()!)

        let wider = TextLayout(text, imageWidth: 3000, pointScale: 2, style: .standard)
        XCTAssertEqual(wider.lines.count, 1, "on a wider image the same words fit one line")

        var wrapped = text
        wrapped.wrap = 300
        let narrow = TextLayout(wrapped, imageWidth: 3000, pointScale: 2, style: .standard)
        XCTAssertGreaterThan(narrow.lines.count, 3)
        XCTAssertTrue(narrow.lines.allSatisfy { $0.rect.width <= 300.001 }, "a wrap width wraps it, wherever the image's edge is")
        XCTAssertEqual(narrow.box.width, 300, accuracy: 0.001)
    }

    func testHardLineBreaksMakeLines() {
        func lines(_ string: String) -> Int {
            TextLayout(Mark.Text(origin: .zero, text: string, size: 24), imageWidth: 2000, pointScale: 1, style: .standard).lines.count
        }
        XCTAssertEqual(lines("one\ntwo\nthree"), 3)
        XCTAssertEqual(lines("one\n\nthree"), 3, "an empty line is a line")
        XCTAssertEqual(lines("one\n"), 2, "a line break at the end starts an empty line, where the caret goes")
        XCTAssertEqual(lines(""), 1)
    }

    func testLinesAreTheLineHeightApart() {
        let text = Mark.Text(origin: CGPoint(x: 10, y: 30), text: "one\ntwo", size: 24)
        let layout = TextLayout(text, imageWidth: 2000, pointScale: 2, style: TextStyle(weight: .medium, lineHeight: 1.5))
        XCTAssertEqual(CTFontGetSize(layout.font), 48, "the size in pt times the point scale")
        XCTAssertEqual(layout.lineHeight, 72)
        XCTAssertEqual(layout.lines.map(\.rect.minY), [30, 102])
        XCTAssertEqual(layout.box, CGRect(x: 10, y: 30, width: layout.box.width, height: 144))
        for line in layout.lines {
            XCTAssertGreaterThan(line.baseline, line.rect.minY + line.rect.height / 2, "the glyphs stand inside their line")
            XCTAssertLessThan(line.baseline, line.rect.maxY)
        }
    }

    func testChineseAndAnEmojiLayOutWithASize() {
        for string in ["这个按钮的颜色不对", "🎉", "Ship it 🚀 今天"] {
            let layout = TextLayout(Mark.Text(origin: .zero, text: string, size: 24), imageWidth: 2000, pointScale: 2, style: .standard)
            XCTAssertEqual(layout.lines.count, 1, string)
            XCTAssertGreaterThan(layout.box.width, 24, string)
            XCTAssertGreaterThan(layout.box.height, 0, string)
            XCTAssertGreaterThan(CTLineGetGlyphCount(layout.lines[0].ctLine), 0, string)
        }
    }
}

private func assertEqual(_ a: CGRect, _ b: CGRect, accuracy: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
    for (x, y) in [(a.minX, b.minX), (a.minY, b.minY), (a.width, b.width), (a.height, b.height)] {
        XCTAssertEqual(x, y, accuracy: accuracy, "\(a) is not \(b)", file: file, line: line)
    }
}
