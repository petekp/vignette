import AppKit
import XCTest

final class LiveInkTests: XCTestCase {
    private let chordFlags: NSEvent.ModifierFlags = [.control, .option]

    // MARK: The chord

    func testBeginsOnExactlyControlAndOptionInEitherOrder() {
        var chord = HeldChord(chordFlags)
        XCTAssertNil(chord.flagsChanged(.option))
        XCTAssertEqual(chord.flagsChanged([.option, .control]), .began)
        XCTAssertNil(chord.flagsChanged([.option, .control]), "the local and global monitors can both report one event")
        XCTAssertEqual(chord.flagsChanged(.control), .ended)
        XCTAssertNil(chord.flagsChanged([]))

        XCTAssertNil(chord.flagsChanged(.control))
        XCTAssertEqual(chord.flagsChanged([.control, .option]), .began)
    }

    func testIgnoresFlagsThatAreNotModifiers() {
        var chord = HeldChord(chordFlags)
        XCTAssertEqual(chord.flagsChanged([.control, .option, .capsLock, .function]), .began)
    }

    func testDoesNotBeginWithAnotherModifierHeld() {
        var chord = HeldChord(chordFlags)
        XCTAssertNil(chord.flagsChanged(.shift))
        XCTAssertNil(chord.flagsChanged([.shift, .control, .option]))
    }

    func testAKeyEndsItUntilTheModifiersAreLetGo() {
        var chord = HeldChord(chordFlags)
        XCTAssertEqual(chord.flagsChanged([.control, .option]), .began)
        XCTAssertEqual(chord.keyDown(), .ended, "Control-Option-arrow is a window manager's shortcut")
        XCTAssertNil(chord.keyDown())
        XCTAssertNil(chord.flagsChanged([.control, .option]))
        XCTAssertNil(chord.flagsChanged(.option), "one of its modifiers is still down")
        XCTAssertNil(chord.flagsChanged([.control, .option]))
        XCTAssertNil(chord.flagsChanged([]))
        XCTAssertEqual(chord.flagsChanged([.control, .option]), .began)
    }

    func testLettingGoOfTheRestOfALargerChordDoesNotBeginIt() {
        var chord = HeldChord(chordFlags)
        XCTAssertNil(chord.flagsChanged(.command))
        XCTAssertNil(chord.flagsChanged([.command, .control]))
        XCTAssertNil(chord.flagsChanged([.command, .control, .option]))
        XCTAssertNil(chord.flagsChanged([.control, .option]), "⌘ let go after a ⌘⌃⌥ shortcut")
        XCTAssertNil(chord.flagsChanged(.option))
        XCTAssertNil(chord.flagsChanged([]))
        XCTAssertEqual(chord.flagsChanged([.control, .option]), .began)
    }

    func testAnotherModifierJoiningEndsItUntilTheModifiersAreLetGo() {
        var chord = HeldChord(chordFlags)
        XCTAssertEqual(chord.flagsChanged([.control, .option]), .began)
        XCTAssertEqual(chord.flagsChanged([.control, .option, .command]), .ended)
        XCTAssertNil(chord.flagsChanged([.control, .option]))
        XCTAssertNil(chord.flagsChanged([]))
        XCTAssertEqual(chord.flagsChanged([.control, .option]), .began)
    }

    // MARK: Strokes

    func testAPressThatBarelyMovesIsATap() {
        XCTAssertEqual(InkStroke([CGPoint(x: 100, y: 100), CGPoint(x: 103, y: 102)], shortestArrow: 8), .tap(CGPoint(x: 100, y: 100)))
        XCTAssertEqual(InkStroke([CGPoint(x: 100, y: 100)], shortestArrow: 8), .tap(CGPoint(x: 100, y: 100)))
        XCTAssertEqual(InkStroke([], shortestArrow: 8), .nothing)
    }

    func testAStrokeThatComesBackToItsStartIsTheEllipseRoundIt() {
        let circle = (0...60).map { i -> CGPoint in
            let angle = CGFloat(i) / 60 * 2 * .pi
            return CGPoint(x: 300 + 80 * cos(angle), y: 200 + 50 * sin(angle))
        }
        guard case .ellipse(let frame) = InkStroke(circle, shortestArrow: 8) else { return XCTFail("not an ellipse") }
        XCTAssertEqual(frame.minX, 220, accuracy: 0.5)
        XCTAssertEqual(frame.maxX, 380, accuracy: 0.5)
        XCTAssertEqual(frame.minY, 150, accuracy: 0.5)
        XCTAssertEqual(frame.maxY, 250, accuracy: 0.5)
    }

    func testALoopMayStopShortOfItsStart() {
        // Most of a circle of radius 120: about 680 pt of path, its ends about 74 pt apart, more than
        // `loopGap` and within 18% of the path.
        let loop = (0...50).map { i -> CGPoint in
            let angle = CGFloat(i) / 50 * 1.8 * .pi
            return CGPoint(x: 300 + 120 * cos(angle), y: 300 + 120 * sin(angle))
        }
        guard case .ellipse = InkStroke(loop, shortestArrow: 8) else { return XCTFail("not an ellipse") }
    }

    func testAStraightStrokeIsAStraightArrow() {
        let line = (0...20).map { CGPoint(x: 100 + CGFloat($0) * 10, y: 100 + CGFloat($0) * 0.5) }
        XCTAssertEqual(InkStroke(line, shortestArrow: 8), .arrow(Mark.Arrow(start: line[0], end: line[20])))
    }

    func testAnOpenCurveIsAFreehandArrow() {
        // A half circle: long, with its ends far apart.
        let arc = (0...40).map { i -> CGPoint in
            let angle = CGFloat(i) / 40 * .pi
            return CGPoint(x: 300 + 100 * cos(angle), y: 300 - 100 * sin(angle))
        }
        guard case .arrow(let arrow) = InkStroke(arc, shortestArrow: 8) else { return XCTFail("not an arrow") }
        XCTAssertEqual(arrow.start, arc[0])
        XCTAssertEqual(arrow.end, arc[40])
        XCTAssertFalse(arrow.via.isEmpty)
    }

    // MARK: Erasing

    func testATapErasesTheTopmostMarkItIsNearOrElseTheSmallestEllipseRoundIt() {
        let style = UITweaks().markStyle
        let big = Mark(geometry: .ellipse(CGRect(x: 0, y: 0, width: 600, height: 400)))
        let low = Mark(geometry: .ellipse(CGRect(x: 100, y: 100, width: 200, height: 100)))
        let high = Mark(geometry: .arrow(Mark.Arrow(start: CGPoint(x: 100, y: 150), end: CGPoint(x: 400, y: 150))))
        let marks = [big, low, high]
        XCTAssertEqual(LiveInk.markToErase(at: CGPoint(x: 100, y: 150), in: marks, markStyle: style), 2)
        XCTAssertEqual(LiveInk.markToErase(at: CGPoint(x: 350, y: 160), in: marks, markStyle: style), 2, "a little off the arrow")
        XCTAssertEqual(LiveInk.markToErase(at: CGPoint(x: 200, y: 105), in: marks, markStyle: style), 1)
        XCTAssertEqual(LiveInk.markToErase(at: CGPoint(x: 200, y: 125), in: marks, markStyle: style), 1, "inside two ellipses: the smaller")
        XCTAssertEqual(LiveInk.markToErase(at: CGPoint(x: 500, y: 300), in: marks, markStyle: style), 0)
        XCTAssertNil(LiveInk.markToErase(at: CGPoint(x: 900, y: 900), in: marks, markStyle: style))
    }

    // MARK: The answer

    func testAnAnswerKeepsItsReplyAndDropsMarksThatPointAtNothing() throws {
        let answer = try LiveAnswer(json: [
            "say": "  The total is wrong.  ",
            "marks": [
                ["kind": "circle", "line": "t3", "words": "$197.85", "label": "Should be $194.24"],
                ["kind": "arrow", "box": [0.5, 0.75, 0.8, 0.5]],
                ["kind": "arrow"],
                ["kind": "underline", "line": "t1"],
            ],
        ])
        XCTAssertEqual(answer.say, "The total is wrong.")
        XCTAssertEqual(answer.marks, [
            AnswerMark(kind: .circle, line: "t3", words: "$197.85", label: "Should be $194.24"),
            AnswerMark(kind: .arrow, box: CGRect(x: 0.5, y: 0.75, width: 0.5, height: 0.25)),
        ], "a box is cut to the picture; a mark with no target or an unknown kind is dropped")
        XCTAssertThrowsError(try LiveAnswer(json: ["say": " ", "marks": []]))
        XCTAssertThrowsError(try LiveAnswer(json: ["marks": []]))
    }

    func testTheReplyStreamsInAsTheAnswersJSONArrives() {
        let pieces = ["{\"say\": \"The", " total", " is \\\"$197", ".85\\\"\\nnot", " $194\\u00b7", "\", \"marks\": []}"]
        var json = "", seen: [String] = []
        XCTAssertNil(LiveAnswer.partialSay(in: "{\"say\": \""))
        for piece in pieces {
            json += piece
            if let say = LiveAnswer.partialSay(in: json), say != seen.last { seen.append(say) }
        }
        XCTAssertEqual(seen, ["The", "The total", "The total is \"$197", "The total is \"$197.85\"\nnot", "The total is \"$197.85\"\nnot $194·"])
    }

    // MARK: Placing an answer

    private let room = CGRect(x: 8, y: 8, width: 1496, height: 966)
    private var sizes: LiveAnswerLayout.Sizes { LiveAnswerLayout.Sizes(textSize: 15, textWidth: 320, style: UITweaks().textStyle) }

    func testANoteGoesBesideWhatItIsAboutWhenThatIsClear() {
        let ink = CGRect(x: 510, y: 435, width: 156, height: 64)
        let scene = LiveAnswerLayout.Scene(room: room, ink: [Mark(geometry: .ellipse(ink))], text: [])
        let note = LiveAnswerLayout.note("Live ink needs Screen Recording permission to see the screen.", near: ink, scene: scene,
                                         obstacles: [ink], sizes: sizes)
        let box = try? XCTUnwrap(LiveAnswerLayout.noteBox(note, sizes: sizes))
        XCTAssertEqual(box?.minX ?? 0, ink.maxX + 10, accuracy: 0.5, "right of the ink")
        XCTAssertEqual(box?.midY ?? 0, ink.midY, accuracy: 1)
    }

    func testANoteMovesOffTextAndStaysInTheRoom() {
        let ink = CGRect(x: 1300, y: 435, width: 156, height: 64)
        let text = [CGRect(x: 900, y: 430, width: 380, height: 80)]
        let scene = LiveAnswerLayout.Scene(room: room, ink: [Mark(geometry: .ellipse(ink))], text: text)
        let note = LiveAnswerLayout.note("Should be $194.24", near: ink, scene: scene, obstacles: [ink] + text, sizes: sizes)
        let box = LiveAnswerLayout.noteBox(note, sizes: sizes)!
        XCTAssertTrue(room.contains(box), "no room right of the ink, which is at the edge")
        XCTAssertFalse(box.intersects(text[0]) || box.intersects(ink), "left of it is text")
    }

    func testACircleRoundAPersonsLoopBecomesAnArrowAndALongLineABox() {
        let total = CGRect(x: 536, y: 452, width: 104, height: 30)
        let loop = Mark(geometry: .ellipse(total.insetBy(dx: -20, dy: -6)))
        let empty = LiveAnswerLayout.Scene(room: room, ink: [], text: [])
        guard case .ellipse(let frame) = LiveAnswerLayout.pointer(.circle, at: total, scene: empty, obstacles: []).geometry else {
            return XCTFail("a circle round a short target is an ellipse")
        }
        XCTAssertTrue(frame.contains(total))

        let circled = LiveAnswerLayout.Scene(room: room, ink: [loop], text: [])
        guard case .arrow(let arrow) = LiveAnswerLayout.pointer(.circle, at: total, scene: circled, obstacles: []).geometry else {
            return XCTFail("the person circled it already")
        }
        XCTAssertFalse(total.contains(arrow.start))
        XCTAssertLessThan(hypot(arrow.end.x - total.maxX, arrow.end.y - total.midY), LiveAnswerLayout.arrowGap + 1, "from the right, which is clear")

        let line = CGRect(x: 100, y: 200, width: 900, height: 20)
        guard case .rectangle = LiveAnswerLayout.pointer(.circle, at: line, scene: empty, obstacles: []).geometry else {
            return XCTFail("a long line is boxed")
        }
    }

    func testAnArrowComesFromTheSideThatCoversLeast() {
        let target = CGRect(x: 600, y: 400, width: 80, height: 24)
        let right = CGRect(x: 680, y: 380, width: 200, height: 200)
        let arrow = LiveAnswerLayout.arrow(to: target, room: room, obstacles: [right])
        XCTAssertLessThan(arrow.end.x, target.midX + 1, "not from the right, which is covered")
    }

    func testAnAnswersReplyComesFirstAndAMarkWithNoTargetIsDropped() {
        let answer = LiveAnswer(say: "Subtotal plus tax is $194.24.", marks: [
            AnswerMark(kind: .circle, line: "t9", label: "Wrong"),
            AnswerMark(kind: .arrow, line: "t4"),
        ])
        let total = CGRect(x: 536, y: 452, width: 104, height: 30)
        let scene = LiveAnswerLayout.Scene(room: room, ink: [], text: [total])
        let marks = LiveAnswerLayout.marks(for: answer, targets: [nil, total], asked: total, scene: scene, sizes: sizes)
        XCTAssertEqual(marks.map(\.kind), [.text, .arrow])
        XCTAssertTrue(marks.allSatisfy(\.agent))
        XCTAssertEqual(marks.first.flatMap { LiveAnswerLayout.noteBox($0, sizes: sizes) }?.intersects(total), false)

        let streamed = marks[0]
        let again = LiveAnswerLayout.marks(for: answer, targets: [nil, total], asked: total, scene: scene, sizes: sizes, streamed: streamed)
        XCTAssertEqual(again.first?.id, streamed.id, "the reply that streamed in keeps its note")
    }
}
