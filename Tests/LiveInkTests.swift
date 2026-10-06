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
        XCTAssertFalse(answer.steps)
        XCTAssertTrue(try LiveAnswer(json: ["say": "Two clicks.", "marks": [], "steps": true]).steps)
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

    func testALabelStaysBesideItsMarkWhenTextIsAllRound() {
        let answer = LiveAnswer(say: "No.", marks: [AnswerMark(kind: .circle, line: "t1", label: "Should be $194.40")])
        let total = CGRect(x: 536, y: 452, width: 104, height: 30)
        // Lines of text all round the total, and none further off.
        let text = stride(from: 300, to: 620, by: 34).flatMap { y in
            [CGRect(x: 300, y: CGFloat(y), width: 230, height: 30), CGRect(x: 646, y: CGFloat(y), width: 230, height: 30)]
        } + [CGRect(x: 536, y: 418, width: 104, height: 30), CGRect(x: 536, y: 486, width: 104, height: 30)]
        let scene = LiveAnswerLayout.Scene(room: room, ink: [], text: text + [total])
        let marks = LiveAnswerLayout.marks(for: answer, targets: [total], asked: CGRect(x: 1300, y: 800, width: 40, height: 20),
                                           scene: scene, sizes: sizes)
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
        let marks = LiveAnswerLayout.marks(for: answer, targets: [share, map], asked: CGRect(x: 100, y: 800, width: 40, height: 20),
                                           scene: scene, sizes: sizes)
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

    func testTheReplyKeepsOffThePersonsLoopUnderTheirNote() {
        let loop = CGRect(x: 400, y: 300, width: 300, height: 200)
        let question = CGRect(x: 400, y: 260, width: 180, height: 30)
        let scene = LiveAnswerLayout.Scene(room: room, ink: [Mark(geometry: .ellipse(loop))], text: [], notes: [question])
        let reply = LiveAnswerLayout.reply("Two more things break at this width.", question: question, near: loop, scene: scene,
                                           obstacles: LiveAnswerLayout.obstacles(in: scene), sizes: sizes)
        let box = LiveAnswerLayout.noteBox(reply, sizes: sizes) ?? .null
        XCTAssertFalse(box.intersects(loop), "under the note is the loop")
        XCTAssertEqual(box.maxY, question.minY - LiveAnswerLayout.threadGap, accuracy: 0.5, "so it goes right above the note")
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

    func testInsideALoopRoundTheWholePageTheReplyHangsUnderTheNoteAndLabelsStay() {
        let loop = CGRect(x: 40, y: 40, width: 1400, height: 900)
        let question = CGRect(x: 500, y: 60, width: 260, height: 30)
        let scene = LiveAnswerLayout.Scene(room: room, ink: [Mark(geometry: .ellipse(loop))], text: [], notes: [question])
        let answer = LiveAnswer(say: "Two more things break at this width.",
                                marks: [AnswerMark(kind: .arrow, line: "t1", label: "Map cropped")])
        let marks = LiveAnswerLayout.marks(for: answer, targets: [CGRect(x: 600, y: 500, width: 90, height: 24)], asked: loop,
                                           question: question, scene: scene, sizes: sizes)
        let reply = LiveAnswerLayout.noteBox(marks[0], sizes: sizes) ?? .null
        XCTAssertEqual(reply.minY, question.maxY + LiveAnswerLayout.threadGap, accuracy: 0.5, "under the note, inside the loop")
        XCTAssertEqual(marks.map(\.kind), [.text, .arrow, .text], "the label is kept")
    }

    func testAReplyTakesTheQuestionsPlaceAndQuotesItOnOneMutedLine() throws {
        let question = CGRect(x: 500, y: 300, width: 260, height: 30)
        let scene = LiveAnswerLayout.Scene(room: room, ink: [], text: [], notes: [question])
        let words = "what else should we fix on mobile before we ship this to everyone on the trip?"
        let reply = LiveAnswerLayout.reply("Two more things.", question: question, quote: words, near: question, scene: scene,
                                           obstacles: [], sizes: sizes)
        XCTAssertEqual(reply.quote, words)
        let box = try XCTUnwrap(LiveAnswerLayout.noteBox(reply, sizes: sizes))
        XCTAssertEqual(box.minX, question.minX, accuracy: 0.5, "where the question was")
        guard case .text(let text) = reply.geometry else { return XCTFail("a note") }
        let layout = TextLayout(text, imageWidth: .greatestFiniteMagnitude, pointScale: 1, style: sizes.style.forMark(reply))
        let quote = try XCTUnwrap(layout.quote)
        XCTAssertLessThanOrEqual(quote.rect.width, layout.box.width - 2 * layout.padding.side + 0.5, "cut to the reply's width")
        XCTAssertLessThan(quote.rect.maxY, layout.lines[0].rect.minY + 0.5, "above the reply's words")
        let plain = LiveAnswerLayout.reply("Two more things.", question: question, near: question, scene: scene, obstacles: [], sizes: sizes)
        XCTAssertGreaterThan(box.height, try XCTUnwrap(LiveAnswerLayout.noteBox(plain, sizes: sizes)).height, "taller by the quote")
    }

    func testAnArrowGrowsLongerWhenItsLabelHasNoRoomAtAShortOnesTail() {
        // The reply fills the room round the target at short range, as at the top of a narrow window.
        let target = CGRect(x: 1400, y: 40, width: 30, height: 24)
        let question = CGRect(x: 1180, y: 90, width: 300, height: 60)
        let scene = LiveAnswerLayout.Scene(room: CGRect(x: 1100, y: 20, width: 380, height: 600), ink: [], text: [], notes: [question])
        let answer = LiveAnswer(say: "Beyond the hero, four things break at this width.", marks: [AnswerMark(kind: .arrow, line: "t1", label: "Share cut off")])
        let marks = LiveAnswerLayout.marks(for: answer, targets: [target], asked: question, question: question, quote: "what else?",
                                           scene: scene, sizes: sizes)
        XCTAssertEqual(marks.map(\.kind), [.text, .arrow, .text], "the label is kept")
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
