import AppKit
import XCTest

final class DrawingTests: XCTestCase {
    private let image = PixelSize(width: 400, height: 100)

    func testTheFiveColoursInTheOrderTheColourPassTriesThem() {
        XCTAssertEqual(MarkColor.allCases.map(\.rawValue), ["red", "yellow", "light-blue", "white", "violet"])
        XCTAssertEqual(MarkColor.allCases.map(\.hex), ["#e03131", "#ffc034", "#4dabf7", "#f3f3f3", "#ae3ec9"])
        XCTAssertEqual(MarkColor.start, .red)
    }

    // MARK: The validator

    /// Every refusal a mark from a drawing file or a paste can meet, one case each, named by the field.
    func testAFileMarkThatFailsNamesTheOneThingWrong() {
        let long = String(repeating: "x", count: MarkFields.maxTextLength + 1)
        let cases: [(String, String)] = [
            (#"["rectangle"]"#, "not an object"),
            (#"{"x": 1, "y": 1, "w": 5, "h": 5, "color": "red"}"#, "no type"),
            (#"{"type": "circle", "x": 1, "y": 1, "color": "red"}"#, "unknown type"),
            (#"{"type": "rectangle", "x": "1", "y": 1, "w": 5, "h": 5, "color": "red"}"#, "x must be a finite number"),
            (#"{"type": "rectangle", "x": true, "y": 1, "w": 5, "h": 5, "color": "red"}"#, "x must be a finite number"),
            (#"{"type": "rectangle", "x": 1, "w": 5, "h": 5, "color": "red"}"#, "y must be a finite number"),
            (#"{"type": "rectangle", "x": 1, "y": 1, "w": 0, "h": 5, "color": "red"}"#, "w must be more than 0"),
            (#"{"type": "ellipse", "x": 1, "y": 1, "w": 5, "h": -5, "color": "red"}"#, "h must be more than 0"),
            (#"{"type": "rectangle", "x": 1, "y": 1, "w": 5, "h": 5}"#, "color is missing"),
            (#"{"type": "rectangle", "x": 1, "y": 1, "w": 5, "h": 5, "color": "blue"}"#, "color must be one of red, yellow, light-blue, white, violet"),
            (#"{"type": "rectangle", "x": 1, "y": 1, "w": 5, "h": 5, "color": "red", "agent": 1}"#, "agent must be true or false"),
            (#"{"type": "rectangle", "x": 1, "y": 1, "w": 5, "h": 5, "color": "red", "colorChosen": "yes"}"#, "colorChosen must be true or false"),
            (#"{"type": "arrow", "x": 1, "y": 1, "x2": 1, "y2": 1, "color": "red"}"#, "the arrow ends where it starts"),
            (#"{"type": "arrow", "x": 1, "y": 1, "x2": 5, "y2": 1, "bend": null, "color": "red"}"#, "bend must be a finite number"),
            (#"{"type": "arrow", "x": 1, "y": 1, "x2": 5, "y2": 1, "via": [1, 2], "color": "red"}"#, "via must be a list of [x, y] points"),
            (#"{"type": "arrow", "x": 1, "y": 1, "x2": 5, "y2": 1, "via": [[1, "2"]], "color": "red"}"#, "via must be a list of [x, y] points"),
            (#"{"type": "arrow", "x": 1, "y": 1, "x2": 5, "y2": 1, "via": [[1, 2, 3]], "color": "red"}"#, "via must be a list of [x, y] points"),
            (#"{"type": "arrow", "x": 1, "y": 1, "x2": 5, "y2": 1, "via": \#(Array(repeating: [2, 2], count: Mark.Arrow.maxVia + 1)), "color": "red"}"#,
             "via has more than 500 points"),
            (#"{"type": "text", "x": 1, "y": 1, "size": 24, "color": "red"}"#, "text is missing"),
            (#"{"type": "text", "x": 1, "y": 1, "text": " \n ", "size": 24, "color": "red"}"#, "text is missing"),
            (#"{"type": "text", "x": 1, "y": 1, "text": "\#(long)", "size": 24, "color": "red"}"#, "text is longer than 2000 characters"),
            (#"{"type": "text", "x": 1, "y": 1, "text": "a", "color": "red"}"#, "size must be a finite number"),
            (#"{"type": "text", "x": 1, "y": 1, "text": "a", "size": 0, "color": "red"}"#, "size must be more than 0"),
            (#"{"type": "text", "x": 1, "y": 1, "text": "a", "size": 1000.5, "color": "red"}"#, "size must be at most 1000"),
            (#"{"type": "text", "x": 1, "y": 1, "text": "a", "size": 1e300, "color": "red"}"#, "size must be at most 1000"),
            (#"{"type": "text", "x": 1, "y": 1, "text": "a", "size": 24, "wrap": 0, "color": "red"}"#, "wrap must be more than 0"),
        ]
        for (json, expected) in cases {
            let item = try! JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)
            XCTAssertThrowsError(try Mark(validating: item), json) { error in
                XCTAssertTrue("\(error)".contains(expected), "\(json) gave \"\(error)\", wanted \"\(expected)\"")
            }
        }
        let longest = String(repeating: "字", count: MarkFields.maxTextLength)
        XCTAssertNoThrow(try Mark(validating: ["type": "text", "x": 1, "y": 1, "text": longest, "size": 1000, "color": "red"]))
    }

    /// One character can carry any number of combining marks, so the character count alone would
    /// let a single "a" hold megabytes.
    func testATextOverTheByteLimitIsRefusedWhateverItsCharacterCount() {
        let heavy = "a" + String(repeating: "\u{0301}", count: 2_000_000)
        XCTAssertEqual(heavy.count, 1)
        XCTAssertThrowsError(try Mark(validating: ["type": "text", "x": 1, "y": 1, "text": heavy, "size": 24, "color": "red"])) { error in
            XCTAssertTrue("\(error)".contains("text is longer than 100000 bytes"), "\(error)")
        }
    }

    func testAnOverflowingNumberBecomesNullOutsideStringsOnly() throws {
        let json = #"{"a": 1e999, "b": [-1E+400, 2.5e3, 0], "c": "1e999 \" 1e999", "d": -0.5}"#
        let object = try XCTUnwrap(DrawingJSON.object(from: Data(json.utf8)) as? [String: Any])
        XCTAssertTrue(object["a"] is NSNull)
        XCTAssertTrue((object["b"] as? [Any])?.first is NSNull)
        XCTAssertEqual((object["b"] as? [Any])?.dropFirst().compactMap { DrawingJSON.number($0) }, [2500, 0])
        XCTAssertEqual(object["c"] as? String, #"1e999 " 1e999"#)
        XCTAssertEqual(DrawingJSON.number(object["d"]), -0.5)
    }

    // MARK: Placing inside the image

    private func placed(_ geometry: Mark.Geometry, in image: PixelSize? = nil) -> Mark.Geometry? {
        Mark(geometry: geometry).placed(in: image ?? self.image, pointScale: 1, style: .standard)?.geometry
    }

    func testAFrameIsMovedInsideAndCutWhenItIsLargerThanTheImage() {
        XCTAssertEqual(placed(.rectangle(CGRect(x: 10, y: 10, width: 30, height: 20))), .rectangle(CGRect(x: 10, y: 10, width: 30, height: 20)))
        XCTAssertEqual(placed(.rectangle(CGRect(x: -10, y: 90, width: 30, height: 20))), .rectangle(CGRect(x: 0, y: 80, width: 30, height: 20)))
        XCTAssertEqual(placed(.ellipse(CGRect(x: -20, y: 10, width: 450, height: 20))), .ellipse(CGRect(x: 0, y: 10, width: 400, height: 20)))
    }

    func testAnArrowIsMovedWhenItsEndsFitAndStoppedAtTheEdgeWhenNot() {
        XCTAssertEqual(placed(.arrow(.init(start: CGPoint(x: -10, y: 10), end: CGPoint(x: 40, y: 20)))),
                       .arrow(.init(start: CGPoint(x: 0, y: 10), end: CGPoint(x: 50, y: 20))), "moved: it still points the same way")
        XCTAssertEqual(placed(.arrow(.init(start: CGPoint(x: -50, y: 10), end: CGPoint(x: 450, y: 20)))),
                       .arrow(.init(start: CGPoint(x: 0, y: 10), end: CGPoint(x: 400, y: 20))))
        XCTAssertNil(placed(.arrow(.init(start: CGPoint(x: -900, y: 10), end: CGPoint(x: -420, y: 10)))),
                     "both ends stop at the same point on the edge, so nothing is left of it")
    }

    func testAFreehandArrowMovesInWholeWhenItsCurveFitsAndIsCutToTheImageWhenNot() throws {
        let arrow = Mark.Arrow(start: CGPoint(x: -30, y: 50), end: CGPoint(x: 100, y: 50), via: [CGPoint(x: 30, y: 20)])
        guard case .arrow(let moved)? = placed(.arrow(arrow)) else { return XCTFail() }
        XCTAssertEqual(moved.end.x - moved.start.x, 130, "moved, not squeezed")
        XCTAssertEqual(moved.via.count, 1)
        XCTAssertTrue(image.bounds.contains(moved.exactBody.bounds))

        let wide = Mark.Arrow(start: CGPoint(x: -30, y: 50), end: CGPoint(x: 500, y: 50), via: [CGPoint(x: 200, y: -200)])
        guard case .arrow(let cut)? = placed(.arrow(wide)) else { return XCTFail() }
        XCTAssertEqual(cut.start, CGPoint(x: 0, y: 50))
        XCTAssertEqual(cut.end, CGPoint(x: 400, y: 50))
        XCTAssertEqual(cut.via, [CGPoint(x: 200, y: 0)])
    }

    func testAFreehandArrowRoundTripsThroughAFileAndAnOlderReaderSeesItsEnds() throws {
        let arrow = Mark(geometry: .arrow(.init(start: CGPoint(x: 10, y: 20), end: CGPoint(x: 300, y: 80),
                                                via: [CGPoint(x: 100, y: 5.5), CGPoint(x: 200, y: 90)])))
        let data = try CopiedMarks(pointScale: 2, marks: [arrow]).encoded()
        let object = try XCTUnwrap(DrawingJSON.object(from: data) as? [String: Any])
        let item = try XCTUnwrap((object["marks"] as? [Any])?.first as? [String: Any])
        XCTAssertEqual(item["via"] as? [[Double]], [[100, 5.5], [200, 90]])
        XCTAssertNil(item["bend"])
        XCTAssertEqual(try Mark(validating: item).geometry, arrow.geometry)
        // x, y, x2 and y2 are its ends, which is all a build from before `via` reads.
        XCTAssertEqual([item["x"], item["y"], item["x2"], item["y2"]].map { $0 as? Double }, [10, 20, 300, 80])
    }

    func testACurvedArrowsBendStopsWhereItsArcWouldLeaveTheImage() throws {
        let arrow = Mark.Arrow(start: CGPoint(x: 100, y: 50), end: CGPoint(x: 300, y: 50), bend: 500)
        guard case .arrow(let inside)? = placed(.arrow(arrow)) else { return XCTFail() }
        XCTAssertGreaterThan(inside.bend, 0, "the arrow still bows the way it did")
        XCTAssertLessThan(inside.bend, 50)
        XCTAssertTrue(image.bounds.contains(ArrowBody(start: inside.start, end: inside.end, bend: inside.bend).bounds))
    }

    func testATextIsMovedInsideAndOneTallerThanTheImageKeepsItsStart() throws {
        guard case .text(let moved)? = placed(.text(.init(origin: CGPoint(x: -20, y: 90), text: "Hello", size: 24))) else { return XCTFail() }
        let box = TextLayout(moved, imageWidth: 400, pointScale: 1, style: .standard).box
        XCTAssertEqual(moved.origin.x, 0)
        XCTAssertEqual(box.maxY, 100, accuracy: 0.001, "its bottom rests on the image's bottom edge")

        let tall = Mark.Text(origin: CGPoint(x: 50, y: 40), text: "one\ntwo\nthree\nfour", size: 24)
        guard case .text(let start)? = placed(.text(tall)) else { return XCTFail() }
        XCTAssertEqual(start.origin, CGPoint(x: 50, y: 0), "taller than the image: its first line shows")

        let atTheEdge = Mark.Text(origin: CGPoint(x: 395, y: 0), text: "Hello there", wrap: 800, size: 24)
        guard case .text(let cut)? = placed(.text(atTheEdge)) else { return XCTFail() }
        XCTAssertEqual(cut.wrap, 400, "a wrap width wider than the image is cut to it")
        XCTAssertEqual(cut.origin.x, 0)
    }

    /// A text with less than 15% of the image's width to its right moves left instead of wrapping
    /// into a column of single characters.
    func testATextNearTheRightEdgeMovesLeftInsteadOfWrappingIntoAColumn() throws {
        let wide = PixelSize(width: 1600, height: 1000)
        func place(_ text: Mark.Text, in image: PixelSize, pointScale: CGFloat) throws -> (text: Mark.Text, layout: TextLayout) {
            let mark = try XCTUnwrap(Mark(geometry: .text(text)).placed(in: image, pointScale: pointScale, style: .standard))
            guard case .text(let placed) = mark.geometry else { throw MarkProblem("placing a text gave another kind of mark") }
            return (placed, TextLayout(placed, imageWidth: CGFloat(image.width), pointScale: pointScale, style: .standard))
        }

        let header = try place(Mark.Text(origin: CGPoint(x: 1560, y: 100), text: "The header should not scroll", size: 24), in: wide, pointScale: 2)
        XCTAssertEqual(header.layout.lines.count, 1)
        XCTAssertLessThan(header.text.origin.x, 1560)
        XCTAssertGreaterThanOrEqual(header.layout.box.minX, 0)
        XCTAssertLessThanOrEqual(header.layout.box.maxX, 1600 * 0.98 + 0.001, "its right edge is on the margin")
        XCTAssertEqual(header.text.origin.y, 100)

        let hello = try place(Mark.Text(origin: CGPoint(x: 380, y: 10), text: "Hello there", size: 24), in: image, pointScale: 1)
        XCTAssertEqual(hello.layout.lines.count, 1)
        XCTAssertLessThan(hello.text.origin.x, 380)

        // With 20% of the width to its right a text keeps its place and wraps there.
        let roomy = try place(Mark.Text(origin: CGPoint(x: 1248, y: 100), text: "The header should not scroll", size: 24), in: wide, pointScale: 2)
        XCTAssertEqual(roomy.text.origin.x, 1248)
        XCTAssertGreaterThan(roomy.layout.lines.count, 1)

        // A text with a wrap width keeps its x; one wider than the image starts at its left edge.
        let wrapped = Mark.Text(origin: CGPoint(x: 1560, y: 100), text: "The header", wrap: 30, size: 24)
        XCTAssertEqual(TextLayout.leftEdge(of: wrapped, imageWidth: 1600, pointScale: 2, style: .standard), 1560)
        let long = Mark.Text(origin: CGPoint(x: 1560, y: 100), text: String(repeating: "the header should not scroll ", count: 6), size: 24)
        XCTAssertEqual(TextLayout.leftEdge(of: long, imageWidth: 1600, pointScale: 2, style: .standard), 0)
    }

    // MARK: Copied marks

    func testCopiedMarksComeBackThroughTheValidator() throws {
        let marks = [
            Mark(geometry: .rectangle(CGRect(x: 1, y: 2, width: 3, height: 4)), color: .yellow),
            Mark(geometry: .arrow(.init(start: CGPoint(x: 5, y: 6), end: CGPoint(x: 7, y: 8), bend: 12)), agent: true),
            Mark(geometry: .text(.init(origin: CGPoint(x: 9, y: 10), text: "copied", wrap: 120, size: 30)), color: .white, colorChosen: true),
        ]
        let copied = try XCTUnwrap(CopiedMarks(data: try CopiedMarks(pointScale: 2, marks: marks).encoded()))
        XCTAssertEqual(copied.pointScale, 2)
        XCTAssertEqual(copied.marks.map(\.geometry), marks.map(\.geometry))
        XCTAssertEqual(copied.marks.map(\.color), marks.map(\.color))
        XCTAssertEqual(copied.marks.map(\.agent), marks.map(\.agent))
        XCTAssertEqual(copied.marks.map(\.colorChosen), marks.map(\.colorChosen))

        // Another app can write the type: a mark that fails is dropped and the rest are pasted.
        let written = #"{"version": 1, "pointScale": 1, "marks": [{"type": "rectangle", "x": 1e999, "y": 0, "w": 1, "h": 1, "color": "red"}, {"type": "rectangle", "x": 0, "y": 0, "w": 1, "h": 1, "color": "red"}]}"#
        XCTAssertEqual(CopiedMarks(data: Data(written.utf8))?.marks.map(\.geometry), [.rectangle(CGRect(x: 0, y: 0, width: 1, height: 1))])
        XCTAssertNil(CopiedMarks(data: Data(#"{"version": 2, "pointScale": 1, "marks": []}"#.utf8)), "a newer build's marks")
        XCTAssertNil(CopiedMarks(data: Data(#"{"version": 1, "pointScale": 9, "marks": [{"type": "rectangle", "x": 0, "y": 0, "w": 1, "h": 1, "color": "red"}]}"#.utf8)))
        XCTAssertNil(CopiedMarks(data: Data(#"{"version": 1, "pointScale": 1, "marks": []}"#.utf8)))
        XCTAssertNil(CopiedMarks(data: Data("plain words".utf8)))
        XCTAssertEqual(CopiedMarks.pasteboardType.rawValue, Identity.bundleID + ".marks")
    }
}
