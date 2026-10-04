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

    func testATapErasesTheTopmostMarkWhoseStrokeItIsOn() {
        let style = UITweaks().markStyle
        let low = Mark(geometry: .ellipse(CGRect(x: 100, y: 100, width: 200, height: 100)))
        let high = Mark(geometry: .arrow(Mark.Arrow(start: CGPoint(x: 100, y: 150), end: CGPoint(x: 400, y: 150))))
        let marks = [low, high]
        XCTAssertEqual(LiveInk.topmostMark(at: CGPoint(x: 100, y: 150), in: marks, markStyle: style, hitMargin: 4), 1)
        XCTAssertEqual(LiveInk.topmostMark(at: CGPoint(x: 200, y: 101), in: marks, markStyle: style, hitMargin: 4), 0)
        XCTAssertNil(LiveInk.topmostMark(at: CGPoint(x: 200, y: 125), in: marks, markStyle: style, hitMargin: 4), "inside the ellipse, off its line")
        XCTAssertNil(LiveInk.topmostMark(at: CGPoint(x: 500, y: 500), in: marks, markStyle: style, hitMargin: 4))
    }
}
