import AppKit
import XCTest

final class LiveInkTests: XCTestCase {
    private let chordFlags: NSEvent.ModifierFlags = [.control, .option]

    // MARK: When listening ends

    func testListeningUntilReleaseEndsJustAfterTheChordIsLetGo() {
        var end = ListeningEnd(until: .release, pause: 1.2, quiet: 0.4, began: 0)
        end.heard(level: 0.9, at: 1)
        XCTAssertFalse(end.isOver(at: 5), "while the chord is held, listening goes on")
        end.release(at: 5)
        XCTAssertFalse(end.isOver(at: 5 + ListeningEnd.tail - 0.01))
        XCTAssertTrue(end.isOver(at: 5 + ListeningEnd.tail))
    }

    func testListeningUntilAPauseWaitsForTheLastLoudMomentAfterRelease() {
        var end = ListeningEnd(until: .pause, pause: 1.2, quiet: 0.4, began: 0)
        end.release(at: 2)
        end.heard(level: 0.8, at: 2.5)
        end.heard(level: 0.1, at: 3)
        XCTAssertFalse(end.isOver(at: 3.6), "still within the pause after the last word")
        XCTAssertTrue(end.isOver(at: 3.71))
    }

    func testListeningUntilAPauseEndsAfterThePauseWhenNothingIsSaidAfterRelease() {
        var end = ListeningEnd(until: .pause, pause: 1.2, quiet: 0.4, began: 0)
        end.heard(level: 0.9, at: 1)
        end.release(at: 4)
        XCTAssertFalse(end.isOver(at: 5))
        XCTAssertTrue(end.isOver(at: 5.21))
    }

    func testPressingTheChordAgainKeepsListening() {
        var end = ListeningEnd(until: .release, pause: 1.2, quiet: 0.4, began: 0)
        end.release(at: 1)
        end.pressAgain()
        XCTAssertFalse(end.isOver(at: 10), "drawing more is part of the same note")
        XCTAssertTrue(end.isOver(at: ListeningEnd.longest), "but never past the longest listening")
    }

    // MARK: Tying spoken words to strokes

    private func words(_ spoken: [(String, TimeInterval)]) -> [SpokenWord] {
        spoken.map { SpokenWord(text: $0.0, start: $0.1, duration: 0.2) }
    }

    func testAStrokeIsNumberedAfterThePointingWordSaidAsItWasDrawn() {
        let said = words([("Make", 0), ("this", 0.3), ("one", 0.5), ("the", 0.7), ("same", 0.8), ("size", 1.1), ("as", 1.4), ("that", 1.6), ("one", 1.8)])
        let strokes = [SpokenNote.Stroke(number: 1, start: 0.1, end: 0.9), SpokenNote.Stroke(number: 2, start: 1.5, end: 2.4)]
        XCTAssertEqual(SpokenNote.marked(said, strokes: strokes), "Make this [1] one the same size as that [2] one")
    }

    func testAStrokeWithNoPointingWordNearIsNumberedWhereItBegan() {
        let said = words([("Bigger", 0), ("please", 0.4)])
        XCTAssertEqual(SpokenNote.marked(said, strokes: [SpokenNote.Stroke(number: 1, start: 0.5, end: 0.8)]), "Bigger please [1]")
        XCTAssertEqual(SpokenNote.marked(said, strokes: [SpokenNote.Stroke(number: 1, start: -0.5, end: -0.1)]), "[1] Bigger please",
                       "a stroke drawn before the first word goes before it")
    }

    func testTwoStrokesNearOnePointingWordDoNotShareIt() {
        let said = words([("this", 0.2), ("and", 0.5), ("this", 1.4)])
        let strokes = [SpokenNote.Stroke(number: 1, start: 0, end: 0.6), SpokenNote.Stroke(number: 2, start: 0.7, end: 1.2)]
        XCTAssertEqual(SpokenNote.marked(said, strokes: strokes), "this [1] and this [2]")
    }

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
        XCTAssertEqual(try LiveAnswer(responder: ["say": "Here.", "marks": [["kind": "arrow", "box": [500, 750, 800, 500]]]]).marks,
                       [AnswerMark(kind: .arrow, box: CGRect(x: 0.5, y: 0.75, width: 0.5, height: 0.25))],
                       "the responder's boxes are in thousandths, as its schema asks")
        XCTAssertFalse(answer.steps)
        XCTAssertTrue(try LiveAnswer(json: ["say": "Two clicks.", "marks": [], "steps": true]).steps)
        XCTAssertThrowsError(try LiveAnswer(json: ["say": " ", "marks": []]))
        XCTAssertThrowsError(try LiveAnswer(json: ["marks": []]))
    }

    func testOnlyAFocusZoomsAndItSurvivesTheReplysBundle() throws {
        let answer = try LiveAnswer(json: ["say": "Look here.", "marks": [["kind": "focus", "words": "1 px", "zoom": true],
                                                                          ["kind": "circle", "words": "Share", "zoom": true]]])
        XCTAssertEqual(answer.marks.map(\.zoom), [true, false], "a circle has nothing to magnify")
        let again = try JSONDecoder().decode(LiveAnswer.self, from: JSONEncoder().encode(answer))
        XCTAssertEqual(again.marks, answer.marks)
    }

    func testTheReplyStreamsInAsTheAnswersJSONArrives() throws {
        // `say` streams in ahead of the marks only when the schema lists it first.
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(LiveAnswer.schema.utf8)))
        let fields = LiveAnswer.schema[try XCTUnwrap(LiveAnswer.schema.range(of: #""properties""#)).upperBound...]
        XCTAssertLessThan(try XCTUnwrap(fields.range(of: #""say""#)).lowerBound, try XCTUnwrap(fields.range(of: #""marks""#)).lowerBound)
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

    func testThePersonsNoteTouchesAnArrowsTailOnTheSideAwayFromItsHead() {
        let arrow = Mark(geometry: .arrow(Mark.Arrow(start: CGPoint(x: 900, y: 500), end: CGPoint(x: 1100, y: 600))))
        let scene = LiveAnswerLayout.Scene(room: room, ink: [arrow], text: [])
        let spot = LiveAnswerLayout.noteSpot(CGSize(width: 320, height: 30), under: 25, for: arrow, scene: scene)
        XCTAssertTrue(spot.growsLeft, "it keeps its right edge at the tail")
        XCTAssertEqual(spot.rect.maxX, 894, accuracy: 0.5)
        XCTAssertEqual(spot.rect.maxY, 494, accuracy: 0.5, "up and to the left, the way the arrow came from")
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
        func first(at target: CGRect, in scene: LiveAnswerLayout.Scene) -> Mark.Geometry? {
            LiveAnswerLayout.pointers(.circle, at: target, scene: scene, obstacles: []).first?.geometry
        }
        guard case .ellipse(let frame) = first(at: total, in: empty) else {
            return XCTFail("a circle round a short target is an ellipse")
        }
        XCTAssertTrue(frame.contains(total))

        let circled = LiveAnswerLayout.Scene(room: room, ink: [loop], text: [])
        guard case .arrow(let arrow) = first(at: total, in: circled) else {
            return XCTFail("the person circled it already")
        }
        XCTAssertFalse(total.contains(arrow.start))

        let line = CGRect(x: 100, y: 200, width: 900, height: 20)
        guard case .rectangle = first(at: line, in: empty) else {
            return XCTFail("a long line is boxed")
        }
    }

    func testAnArrowComesFromTheSideThatCoversLeast() {
        let target = CGRect(x: 600, y: 400, width: 80, height: 24)
        let right = CGRect(x: 680, y: 380, width: 200, height: 200)
        let answer = LiveAnswer(say: "No.", marks: [AnswerMark(kind: .arrow, line: "t1")])
        let marks = LiveAnswerLayout.placed(for: answer, targets: [target], asked: CGRect(x: 100, y: 800, width: 40, height: 20),
                                            scene: LiveAnswerLayout.Scene(room: room, ink: [], text: [right]), sizes: sizes).marks
        guard case .arrow(let arrow) = marks.last?.geometry else { return XCTFail("an arrow") }
        XCTAssertLessThan(arrow.end.x, target.midX + 1, "not from the right, which is covered")
    }

    func testAnAnswersReplyComesFirstAndAMarkWithNoTargetIsDropped() {
        let answer = LiveAnswer(say: "Subtotal plus tax is $194.24.", marks: [
            AnswerMark(kind: .circle, line: "t9", label: "Wrong"),
            AnswerMark(kind: .arrow, line: "t4"),
        ])
        let total = CGRect(x: 536, y: 452, width: 104, height: 30)
        let scene = LiveAnswerLayout.Scene(room: room, ink: [], text: [total])
        let marks = LiveAnswerLayout.placed(for: answer, targets: [nil, total], asked: total, scene: scene, sizes: sizes).marks
        XCTAssertEqual(marks.map(\.kind), [.text, .arrow])
        XCTAssertTrue(marks.allSatisfy(\.agent))
        XCTAssertEqual(marks.first.flatMap { LiveAnswerLayout.noteBox($0, sizes: sizes) }?.intersects(total), false)

        let streamed = marks[0]
        let again = LiveAnswerLayout.placed(for: answer, targets: [nil, total], asked: total, scene: scene, sizes: sizes, streamed: streamed).marks
        XCTAssertEqual(again.first?.id, streamed.id, "the reply that streamed in keeps its note")
        XCTAssertEqual(again.first?.popover?.at, streamed.popover?.at, "and where it hangs")
    }

    func testALabelStaysBesideItsMarkWhenTextIsAllRound() {
        let answer = LiveAnswer(say: "No.", marks: [AnswerMark(kind: .circle, line: "t1", label: "Should be $194.40")])
        let total = CGRect(x: 536, y: 452, width: 104, height: 30)
        // Lines of text all round the total, and none further off.
        let text = stride(from: 300, to: 620, by: 34).flatMap { y in
            [CGRect(x: 300, y: CGFloat(y), width: 230, height: 30), CGRect(x: 646, y: CGFloat(y), width: 230, height: 30)]
        } + [CGRect(x: 536, y: 418, width: 104, height: 30), CGRect(x: 536, y: 486, width: 104, height: 30)]
        let scene = LiveAnswerLayout.Scene(room: room, ink: [], text: text + [total])
        let marks = LiveAnswerLayout.placed(for: answer, targets: [total], asked: CGRect(x: 1300, y: 800, width: 40, height: 20),
                                            scene: scene, sizes: sizes).marks
        XCTAssertEqual(marks.map(\.kind), [.text, .ellipse, .text], "the circle keeps its label")
        let circle = marks[1].shapeExtent ?? .null
        let label = marks.last.flatMap { LiveAnswerLayout.noteBox($0, sizes: sizes) } ?? .null
        XCTAssertLessThanOrEqual(hypot(max(0, circle.minX - label.maxX, label.minX - circle.maxX),
                                       max(0, circle.minY - label.maxY, label.minY - circle.maxY)), 6.5,
                                 "the label touches the circle, over the text there, not off where there is room")
    }

    func testArrowsComeFromOneSideWithTheirLabelsInAColumnAtTheirTails() {
        let answer = LiveAnswer(say: "Two more things break at this width.",
                                marks: [AnswerMark(kind: .arrow, line: "t1", label: "Share cut off"),
                                        AnswerMark(kind: .arrow, line: "t2", label: "Map cropped")])
        let share = CGRect(x: 700, y: 200, width: 60, height: 24), map = CGRect(x: 600, y: 500, width: 90, height: 24)
        let scene = LiveAnswerLayout.Scene(room: room, ink: [], text: [])
        let marks = LiveAnswerLayout.placed(for: answer, targets: [share, map], asked: CGRect(x: 100, y: 800, width: 40, height: 20),
                                            scene: scene, sizes: sizes).marks
        XCTAssertEqual(marks.map(\.kind), [.text, .arrow, .text, .arrow, .text])
        let arrows = marks.compactMap { mark -> Mark.Arrow? in if case .arrow(let arrow) = mark.geometry { arrow } else { nil } }
        XCTAssertEqual(arrows[0].start.x > arrows[0].end.x, arrows[1].start.x > arrows[1].end.x, "both from one side")
        XCTAssertEqual(arrows[0].start.x, arrows[1].start.x, accuracy: 0.5, "tails in a column")
        for (arrow, label) in zip(arrows, [marks[2], marks[4]]) {
            let box = LiveAnswerLayout.noteBox(label, sizes: sizes) ?? .null
            let gap = hypot(max(0, box.minX - arrow.start.x, arrow.start.x - box.maxX), max(0, box.minY - arrow.start.y, arrow.start.y - box.maxY))
            XCTAssertLessThanOrEqual(gap, 6 * 2.squareRoot() + 0.5, "the label touches its arrow's tail, or its corner does")
        }
    }

    func testAReplyThatPointsAtNothingHangsUnderTheInkUnlessThePersonsNoteIsThere() {
        let loop = CGRect(x: 400, y: 300, width: 300, height: 200)
        let open = LiveAnswerLayout.Scene(room: room, ink: [Mark(geometry: .ellipse(loop))], text: [])
        let reply = LiveAnswerLayout.reply("Two more things break at this width.", quote: nil, from: loop, scene: open, sizes: sizes)
        XCTAssertEqual(reply.popover?.edge, .below)
        XCTAssertNil(reply.popover?.anchor, "it hangs from the ink")
        XCTAssertEqual(reply.popover?.at.midX ?? 0, loop.midX, accuracy: 0.5)
        XCTAssertGreaterThan(LiveAnswerLayout.noteBox(reply, sizes: sizes)?.minY ?? 0, loop.maxY)

        let note = CGRect(x: 400, y: 510, width: 300, height: 60)
        let noted = LiveAnswerLayout.Scene(room: room, ink: [Mark(geometry: .ellipse(loop))], text: [], notes: [note])
        let above = LiveAnswerLayout.reply("Two more things break at this width.", quote: nil, from: loop, scene: noted, sizes: sizes)
        XCTAssertEqual(above.popover?.edge, .above, "under the loop is the person's note")
        XCTAssertFalse((LiveAnswerLayout.noteBox(above, sizes: sizes) ?? .null).intersects(loop))
    }

    func testAnActionNamesTheMarksItActsOnByIndex() throws {
        let answer = try LiveAnswer(json: ["say": "Two more things.", "marks": [["kind": "circle", "words": "Share"], ["kind": "arrow", "words": "20 km"]],
                                           "actions": ["Fix both", ["title": "Header only", "marks": [0, 0, 9]], ["title": "Map only", "marks": [Int]()]]])
        XCTAssertEqual(answer.actions, [LiveAnswer.Action("Fix both"), LiveAnswer.Action("Header only", marks: [0]), LiveAnswer.Action("Map only")],
                       "no repeats, no index past the marks, and none is every mark")
        let again = try JSONDecoder().decode(LiveAnswer.self, from: JSONEncoder().encode(answer))
        XCTAssertEqual(again.actions, answer.actions)
    }

    func testEachFindingKnowsTheMarksDrawnForIt() {
        let answer = LiveAnswer(say: "Two more things.", marks: [AnswerMark(kind: .arrow, line: "t1", label: "Share cut off"),
                                                                 AnswerMark(kind: .arrow, line: "t2", label: "Map cropped")])
        let placed = LiveAnswerLayout.placed(for: answer, targets: [nil, CGRect(x: 600, y: 500, width: 90, height: 24)],
                                             asked: CGRect(x: 100, y: 800, width: 40, height: 20),
                                             scene: LiveAnswerLayout.Scene(room: room, ink: [], text: []), sizes: sizes)
        XCTAssertEqual(placed.findings.count, 2)
        XCTAssertEqual(placed.findings[0], [], "the one not found drew nothing")
        XCTAssertEqual(placed.findings[1], placed.marks.dropFirst().map(\.id), "the arrow and its label")
    }

    func testAWholeAnswerHangsItsReplyFromItsFirstMarkAndKeepsItsLabel() {
        // A loop round the whole page leaves no room clear of what it encloses.
        let loop = CGRect(x: 40, y: 40, width: 1400, height: 900)
        let scene = LiveAnswerLayout.Scene(room: room, ink: [Mark(geometry: .ellipse(loop))], text: [])
        let target = CGRect(x: 600, y: 500, width: 90, height: 24)
        let answer = LiveAnswer(say: "Two more things break at this width.",
                                marks: [AnswerMark(kind: .arrow, line: "t1", label: "Map cropped")])
        let marks = LiveAnswerLayout.placed(for: answer, targets: [target], asked: loop, scene: scene, sizes: sizes).marks
        XCTAssertEqual(marks.map(\.kind), [.text, .arrow, .text], "the label is kept")
        guard case .arrow(let arrow) = marks[1].geometry, let place = marks[0].popover else { return XCTFail("a reply hung from an arrow") }
        XCTAssertEqual(place.anchor, marks[1].id)
        XCTAssertTrue(place.at.insetBy(dx: -1, dy: -1).contains(arrow.start), "from the arrow's tail")
        let label = LiveAnswerLayout.noteBox(marks[2], sizes: sizes) ?? .null
        XCTAssertFalse(place.body.intersects(label) || place.body.intersects(target), "covering neither its label nor what the arrow points at")

        let steps = LiveAnswer(say: answer.say, marks: answer.marks, steps: true)
        let stepped = LiveAnswerLayout.placed(for: steps, targets: [target], asked: loop, scene: scene, sizes: sizes).marks
        XCTAssertNotNil(stepped[0].popover)
        XCTAssertNil(stepped[0].popover?.anchor, "steps come and go, so the reply hangs from the ink")
    }

    func testAReplysHeaderQuotesTheQuestionOnOneLine() {
        let words = "what else should we fix on mobile before we ship this to everyone on the trip?"
        let reply = LiveAnswerLayout.reply("Two more things.", quote: words, from: CGRect(x: 500, y: 300, width: 260, height: 30),
                                           scene: LiveAnswerLayout.Scene(room: room, ink: [], text: []), sizes: sizes)
        XCTAssertEqual(reply.quote, words)
        let quoted = ReplyContent.size("Two more things.", agent: reply.agentName, quote: words, wrap: sizes.textWidth, foot: .zero)
        let plain = ReplyContent.size("Two more things.", agent: reply.agentName, quote: nil, wrap: sizes.textWidth, foot: .zero)
        XCTAssertEqual(quoted.height, plain.height, "the question is cut to the header's one line")
        XCTAssertLessThanOrEqual(quoted.width, ReplyContent.insets.left + sizes.textWidth + ReplyContent.insets.right + 1, "and to the reply's width")
    }

    func testAReplysNoticeWrapsSoAllOfItShows() {
        let reason = "Not sent. Claude Code closed that session, so Vignette has nowhere to send your reply."
        let plain = ReplyContent.size("Two more things.", agent: LiveAnswerLayout.agentName, quote: nil, wrap: sizes.textWidth, foot: .zero)
        let noticed = ReplyContent.size("Two more things.", agent: LiveAnswerLayout.agentName, quote: "why?", notice: reason,
                                        wrap: sizes.textWidth, foot: .zero)
        XCTAssertGreaterThan(noticed.height, plain.height, "the reason wraps under the name instead of being cut")
        XCTAssertLessThanOrEqual(noticed.width, ReplyContent.insets.left + sizes.textWidth + ReplyContent.insets.right + 1, "within the reply's width")
    }

    func testAReplyIsNeverNarrowerThanItsButtons() {
        let plain = ReplyContent.size("Done.", agent: LiveAnswerLayout.agentName, quote: nil, wrap: sizes.textWidth, foot: .zero)
        let row = CGSize(width: sizes.textWidth + 60, height: 36)
        let footed = ReplyContent.size("Done.", agent: LiveAnswerLayout.agentName, quote: nil, wrap: sizes.textWidth, foot: row)
        XCTAssertEqual(footed.width, ReplyContent.insets.left + row.width + ReplyContent.insets.right, accuracy: 1, "as wide as its row of buttons")
        XCTAssertEqual(footed.height, plain.height + row.height, accuracy: 1, "with the row's room under its words")
    }

    func testAnArrowGrowsLongerWhenItsLabelHasNoRoomAtAShortOnesTail() {
        // The person's note fills the room round the target at short range, as at the top of a narrow
        // window. Steps hang their reply from the person's ink, so only the label needs room here.
        let target = CGRect(x: 1400, y: 40, width: 30, height: 24)
        let note = CGRect(x: 1180, y: 90, width: 300, height: 60)
        let scene = LiveAnswerLayout.Scene(room: CGRect(x: 1100, y: 20, width: 380, height: 600), ink: [], text: [], notes: [note])
        let answer = LiveAnswer(say: "Beyond the hero, four things break at this width.",
                                marks: [AnswerMark(kind: .arrow, line: "t1", label: "Share cut off")], steps: true)
        let marks = LiveAnswerLayout.placed(for: answer, targets: [target], asked: note, scene: scene, sizes: sizes).marks
        XCTAssertEqual(marks.map(\.kind), [.text, .arrow, .text], "the label is kept")
    }

    func testAFocusDrawsNoStrokeAndTheRestOfTheAnswerKeepsClearOfIt() throws {
        let target = CGRect(x: 600, y: 400, width: 80, height: 20)
        let scene = LiveAnswerLayout.Scene(room: room, ink: [], text: [])
        let answer = LiveAnswer(say: "This is the one.", marks: [AnswerMark(kind: .focus, line: "t1", label: "Here")])
        let marks = LiveAnswerLayout.placed(for: answer, targets: [target], asked: CGRect(x: 100, y: 800, width: 40, height: 20),
                                            scene: scene, sizes: sizes).marks
        XCTAssertEqual(marks.map(\.kind), [.text, .rectangle, .text])
        XCTAssertEqual(marks[1].focus?.target, target)
        XCTAssertEqual(marks[1].shapeExtent, Focus.spot(around: target), "the sharp spot")
        XCTAssertEqual(marks[0].popover?.anchor, marks[1].id, "the reply hangs from it")
        for note in [marks[0], marks[2]] {
            XCTAssertFalse((LiveAnswerLayout.noteBox(note, sizes: sizes) ?? .null).intersects(Focus.spot(around: target)))
        }

        let zoomed = LiveAnswerLayout.placed(for: LiveAnswer(say: "Too small.", marks: [AnswerMark(kind: .focus, line: "t1", zoom: true)]),
                                             targets: [CGRect(x: 1490, y: 400, width: 8, height: 8)], asked: .null, scene: scene, sizes: sizes).marks
        let lens = try XCTUnwrap(zoomed[1].shapeExtent)
        XCTAssertTrue(room.contains(lens), "the lens stays in the window at its edge")
        XCTAssertEqual(lens.width, Focus.spot(around: CGRect(x: 0, y: 0, width: 8, height: 8)).width * Focus.zoom, accuracy: 0.5)

        let stepped = LiveAnswerLayout.placed(for: LiveAnswer(say: "Click it.", marks: [AnswerMark(kind: .focus, line: "t1")], steps: true),
                                              targets: [target], asked: .null, scene: scene, sizes: sizes).marks
        XCTAssertNil(stepped[1].focus, "a step is something to click")
        XCTAssertEqual(stepped[1].kind, .ellipse)

        let windowless = LiveAnswerLayout.placed(for: answer, targets: [target], asked: .null, scene: scene, sizes: sizes, focusable: false).marks
        XCTAssertNil(windowless[1].focus, "with no window to blur, a focus would show nothing")
        XCTAssertEqual(windowless.map(\.kind), [.text, .ellipse, .text], "the label is kept")

        let later = CGRect(x: 300, y: 900, width: 80, height: 20)
        let tour = LiveAnswerLayout.placed(for: LiveAnswer(say: "This one, then that one.", marks: [AnswerMark(kind: .focus, line: "t1", label: "Here"),
                                                                                                   AnswerMark(kind: .focus, line: "t2", label: "There")]),
                                           targets: [target, later], asked: .null, scene: scene, sizes: sizes)
        let second = try XCTUnwrap(tour.marks.first { $0.focus?.target == later })
        let place = try XCTUnwrap(tour.tour[second.id], "the reply moves to the second stop")
        XCTAssertEqual(place.anchor, second.id)
        XCTAssertFalse(place.body.intersects(Focus.spot(around: later)))
        let label = try XCTUnwrap(tour.marks.last)
        XCTAssertFalse((LiveAnswerLayout.noteBox(label, sizes: sizes) ?? .null).intersects(place.body), "its label stays beside it")
    }

    func testATourHoldsEachStopForItsSentence() {
        let say = "The total is wrong. It adds the tax twice, once on each line, and again at the end."
        let holds = Focus.holds(for: say, stops: 2)
        XCTAssertEqual(holds[0], Focus.least, "four words read faster than the least it holds")
        XCTAssertEqual(holds[1], 14 * Focus.perWord, accuracy: 0.01)
        XCTAssertEqual(Focus.holds(for: say, stops: 1), [18 * Focus.perWord], "one focus holds for the whole reply")
        XCTAssertEqual(Focus.holds(for: "Here.", stops: 3), [Focus.least, Focus.least, Focus.lastLeast], "more stops than sentences")
    }

    func testAHookAtTheHeadDoesNotTurnTheWayAnArrowLeavesItsTail() {
        // Straight to the right for 200 pt, then a hook back up and left at the head.
        let via = stride(from: 10, through: 200, by: 10).map { CGPoint(x: 100 + CGFloat($0), y: 300) } + [CGPoint(x: 290, y: 260)]
        let away = LiveAnswerLayout.leaving(Mark.Arrow(start: CGPoint(x: 100, y: 300), end: CGPoint(x: 240, y: 240), via: via))
        XCTAssertEqual(away.dx, -1, accuracy: 0.01)
        XCTAssertEqual(away.dy, 0, accuracy: 0.01)
    }

    // MARK: Marks that stay on their window

    func testAPatchFindsItsContentWhereTheScrollTookIt() throws {
        let page = Self.page(seed: 3)
        let patch = try XCTUnwrap(LivePatch(try Self.window(page, top: 200), around: CGPoint(x: 200, y: 150)))
        let shift = try XCTUnwrap(patch.shift(in: try Self.window(page, top: 260), expected: CGVector(dx: 0, dy: -50)))
        XCTAssertEqual(shift, CGVector(dx: 0, dy: -60), "scrolling down 60 pt moves the content up 60 pt")
    }

    func testAPatchScrolledOutOfTheWindowIsNotFound() throws {
        let page = Self.page(seed: 3)
        let patch = try XCTUnwrap(LivePatch(try Self.window(page, top: 200), around: CGPoint(x: 200, y: 150)))
        XCTAssertNil(patch.shift(in: try Self.window(page, top: 600), expected: CGVector(dx: 0, dy: -400)))
    }

    func testAPatchCutOffAtTheWindowsEdgeIsStillFound() throws {
        let page = Self.page(seed: 7)
        let patch = try XCTUnwrap(LivePatch(try Self.window(page, top: 200), around: CGPoint(x: 200, y: 150)))
        // The mark's point comes to rest 10 pt above the window's bottom edge, with the patch's bottom cut off.
        let shift = try XCTUnwrap(patch.shift(in: try Self.window(page, top: 60), expected: CGVector(dx: 0, dy: 130)))
        XCTAssertEqual(shift, CGVector(dx: 0, dy: 140))
    }

    func testOfMatchesThatLookAlikeTheOneTheScrollBroughtThereWins() throws {
        let page = Self.page(seed: 5, repeating: 100)
        let patch = try XCTUnwrap(LivePatch(try Self.window(page, top: 200), around: CGPoint(x: 200, y: 150)))
        let after = try Self.window(page, top: 300)
        XCTAssertEqual(patch.shift(in: after, expected: CGVector(dx: 0, dy: -96)), CGVector(dx: 0, dy: -100))
        XCTAssertEqual(patch.shift(in: after, expected: CGVector(dx: 0, dy: 4)), CGVector(dx: 0, dy: 0))
    }

    func testAPlainStretchOfPageGivesNoPatch() throws {
        let blank = [UInt8](repeating: 30, count: 400 * 900)
        XCTAssertNil(LivePatch(try Self.window(blank, top: 200), around: CGPoint(x: 200, y: 150)))
    }

    func testAnElementCutOffAtTheTopOfItsScrollAreaKeepsItsHeight() {
        let pinned = CGRect(x: 10, y: 120, width: 200, height: 20)
        let clip = CGRect(x: 0, y: 87, width: 500, height: 400)
        let whole = LiveAnchor.Reading(rect: CGRect(x: 10, y: 100, width: 200, height: 20), clip: clip)
        XCTAssertEqual(whole.shift(from: pinned), CGVector(dx: 0, dy: -20))
        // Chromium reports the part still in view: its top held at the edge, its height shrinking.
        let cut = LiveAnchor.Reading(rect: CGRect(x: 10, y: 87, width: 200, height: 8), clip: clip)
        XCTAssertEqual(cut.shift(from: pinned), CGVector(dx: 0, dy: -45))
        XCTAssertNil(LiveAnchor.Reading(rect: CGRect(x: 10, y: 87, width: 200, height: 0), clip: clip).shift(from: pinned))
    }

    /// A page 400 pt wide and 900 tall of blocks of grey, as text gives at a glance, the same every
    /// `repeating` rows when given.
    private static func page(seed: UInt64, repeating: Int? = nil) -> [UInt8] {
        var state = seed
        func next() -> UInt8 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return UInt8(truncatingIfNeeded: state >> 56)
        }
        let blocks = (0..<(50 * 113)).map { _ in next() }
        return (0..<(400 * 900)).map { index in
            let x = index % 400, y = index / 400
            let row = repeating.map { y % $0 } ?? y
            return blocks[(row / 8) * 50 + x / 8]
        }
    }

    /// The window over `page` whose top edge is at `top`: 400 by 300 pt at 1 px per pt.
    private static func window(_ page: [UInt8], top: Int) throws -> WindowImage {
        let rows = Array(page[(top * 400)..<((top + 300) * 400)])
        let provider = try XCTUnwrap(CGDataProvider(data: Data(rows) as CFData))
        let image = try XCTUnwrap(CGImage(width: 400, height: 300, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 400,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                          provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        return try XCTUnwrap(WindowImage(image))
    }
}
