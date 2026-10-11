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

    // MARK: How long a note card's turn is waited on

    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    private func readings(_ watch: inout TurnWatch, _ turns: [(SessionTurn?, TimeInterval)]) -> [TurnWatch.Verdict] {
        turns.map { watch.read($0.0, at: t0 + $0.1) }
    }

    func testATurnSeenToStartEndsOnceItHasBeenIdleTwoSeconds() {
        var watch = TurnWatch(asked: t0)
        XCTAssertEqual(readings(&watch, [(.busy, 0), (.idle, 10), (.idle, 11.5)]), [.stillWaiting, .stillWaiting, .stillWaiting])
        XCTAssertEqual(watch.read(.idle, at: t0 + 12), .ended, "idle for two seconds from the first idle reading")
    }

    func testABusyMomentBetweenTurnsStartsTheIdleSpellOver() {
        var watch = TurnWatch(asked: t0)
        XCTAssertEqual(readings(&watch, [(.busy, 0), (.idle, 10), (.busy, 11), (.idle, 12), (.idle, 13.5)]),
                       Array(repeating: .stillWaiting, count: 5))
        XCTAssertEqual(watch.read(.idle, at: t0 + 14), .ended)
    }

    func testATurnEndingWhileTheRequestStillWaitsIsAnotherRequests() {
        var watch = TurnWatch(asked: t0)
        let verdicts = readings(&watch, [(.busy, 0), (.waiting, 1)] + (2...20).map { (.idle, TimeInterval($0)) })
        XCTAssertFalse(verdicts.contains(.ended), "the busy turn before the request left the inbox was another one's")
    }

    func testWithNoTurnSeenToStartVignetteStopsWaitingThreeMinutesAfterTheSessionTookTheRequest() {
        var watch = TurnWatch(asked: t0)
        XCTAssertEqual(watch.read(nil, at: t0 + 180), .stillWaiting)
        XCTAssertEqual(watch.read(nil, at: t0 + 180.5), .stoppedWaiting)

        var taken = TurnWatch(asked: t0)
        XCTAssertEqual(taken.read(.waiting, at: t0 + 100), .stillWaiting)
        XCTAssertEqual(taken.read(nil, at: t0 + 280), .stillWaiting, "counted from when the session took it, not the ask")
        XCTAssertEqual(taken.read(nil, at: t0 + 280.5), .stoppedWaiting)
    }

    func testATurnUnderWayIsWaitedOnForThirtyMinutes() {
        var watch = TurnWatch(asked: t0)
        let busy = readings(&watch, [(.waiting, 50)] + stride(from: 60, through: 1850, by: 60).map { (.busy, TimeInterval($0)) } + [(.busy, 1850)])
        XCTAssertFalse(busy.contains(.stoppedWaiting))
        XCTAssertEqual(watch.read(.busy, at: t0 + 1850.5), .stoppedWaiting, "thirty minutes from when the session took the request")

        var unknown = TurnWatch(asked: t0)
        XCTAssertEqual(unknown.read(.busy, at: t0), .stillWaiting)
        XCTAssertEqual(unknown.read(nil, at: t0 + 180), .stillWaiting)
        XCTAssertEqual(unknown.read(nil, at: t0 + 180.5), .stoppedWaiting, "a reading that cannot tell gets the shorter limit")
    }

    func testARequestStillQueuedCountsFromTheAsk() {
        var watch = TurnWatch(asked: t0)
        let queued = readings(&watch, stride(from: 60, through: 1800, by: 60).map { (.waiting, TimeInterval($0)) })
        XCTAssertFalse(queued.contains(.stoppedWaiting))
        XCTAssertEqual(watch.read(.waiting, at: t0 + 1800.5), .stoppedWaiting)
    }

    func testAnIdleSpellSettlingIsNotCutShortByTheLimit() {
        var watch = TurnWatch(asked: t0)
        XCTAssertEqual(readings(&watch, [(.busy, 0), (.idle, 1799), (.idle, 1800.5)]), [.stillWaiting, .stillWaiting, .stillWaiting])
        XCTAssertEqual(watch.read(.idle, at: t0 + 1801), .ended)
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

    // MARK: The pointer field

    func testTheRingGrowsInAndSettlesRoundThePointer() {
        let ui = UITweaks()
        var motion = PointerFieldMotion()
        motion.reset(at: .zero, now: 0)
        XCTAssertEqual(motion.radius, 0, "it grows in from nothing")
        let pointer = CGPoint(x: 200, y: 100)
        var now = 0.0
        for _ in 0..<120 {
            now += 1.0 / 60
            _ = motion.step(to: now, pointer: pointer, pressed: false, ui: ui)
        }
        XCTAssertEqual(motion.centre.x, pointer.x + PointerFieldMotion.ringOffset.dx, accuracy: 0.01)
        XCTAssertEqual(motion.centre.y, pointer.y + PointerFieldMotion.ringOffset.dy, accuracy: 0.01)
        XCTAssertEqual(motion.radius, CGFloat(ui.liveInkFieldSize), accuracy: 0.01)
        XCTAssertEqual(motion.step(to: now + 1.0 / 60, pointer: pointer, pressed: false, ui: ui), .init(), "settled, so nothing is drawn again")
    }

    func testAFollowAndAFadeOfZeroPutTheRingInPlaceAtOnce() {
        var ui = UITweaks()
        ui.liveInkFieldFollow = 0
        ui.liveInkFieldFade = 0
        var motion = PointerFieldMotion()
        motion.reset(at: .zero, now: 0)
        _ = motion.step(to: 1.0 / 60, pointer: CGPoint(x: 50, y: 40), pressed: true, ui: ui)
        XCTAssertEqual(motion.centre, CGPoint(x: 50 + PointerFieldMotion.ringOffset.dx, y: 40 + PointerFieldMotion.ringOffset.dy))
        XCTAssertEqual(motion.velocity, .zero)
        XCTAssertEqual(motion.radius, CGFloat(ui.liveInkFieldSize) * 0.8, "smaller while pressed")
    }

    func testTheWakeSpacesItsPointsKeepsTheNewestAndLetsThemGo() {
        var ui = UITweaks()
        ui.liveInkFieldSize = 0
        var motion = PointerFieldMotion()
        motion.reset(at: .zero, now: 0)
        _ = motion.step(to: 0.01, pointer: .zero, pressed: false, ui: ui)
        XCTAssertTrue(motion.trail.isEmpty, "no wake without a press")
        _ = motion.step(to: 0.02, pointer: .zero, pressed: true, ui: ui)
        _ = motion.step(to: 0.03, pointer: CGPoint(x: 3, y: 0), pressed: true, ui: ui)
        XCTAssertEqual(motion.trail.map(\.point), [.zero], "a point under 6 pt from the last adds no ring")
        _ = motion.step(to: 0.04, pointer: CGPoint(x: 9, y: 0), pressed: true, ui: ui)
        XCTAssertEqual(motion.trail.count, 2)

        var now = 0.04
        for i in 2..<200 {
            now += 0.001
            _ = motion.step(to: now, pointer: CGPoint(x: Double(i) * 10, y: 0), pressed: true, ui: ui)
        }
        XCTAssertEqual(motion.trail.count, PointerFieldMotion.trailLimit)
        XCTAssertEqual(motion.trail.last?.point, CGPoint(x: 1990, y: 0), "the oldest go first")

        now += ui.liveInkWakeDuration + 0.001
        XCTAssertEqual(motion.step(to: now, pointer: .zero, pressed: false, ui: ui), .init(wake: true), "drawn once more as the last ring goes")
        XCTAssertTrue(motion.trail.isEmpty)
        XCTAssertEqual(motion.step(to: now + 0.01, pointer: .zero, pressed: false, ui: ui), .init())
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

    func testTheReplyHelperRefusesAMarkItWouldDropAndNamesIt() throws {
        let good: [String: Any] = ["kind": "circle", "words": "$72k", "box": [0.25, 0.5, 0.125, 0.0625]]
        let kept = try LiveAnswer(json: ["say": "Here.", "marks": [good]], strict: true)
        XCTAssertEqual(kept.marks, [AnswerMark(kind: .circle, words: "$72k", box: CGRect(x: 0.25, y: 0.5, width: 0.125, height: 0.0625))],
                       "words and a box together are kept, so the box can stand in when the words are not found")
        let refused: [(Any, String)] = [
            ([good, ["kind": "underline", "words": "Total"]], "mark 2"),
            ([good, good, ["kind": "arrow", "box": [1.2, 0.5, 0.1, 0.1]]], "mark 3"),
            ([["kind": "arrow"]], "mark 1"),
            (Array(repeating: good, count: LiveAnswer.maxMarks + 1), "at most"),
        ]
        for (marks, named) in refused {
            XCTAssertThrowsError(try LiveAnswer(json: ["say": "Here.", "marks": marks], strict: true)) { error in
                XCTAssertTrue("\(error)".contains(named), "\(error)")
            }
            XCTAssertNoThrow(try LiveAnswer(json: ["say": "Here.", "marks": marks]), "the responder's answer still drops them and is shown")
        }
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

    /// A note is placed and hit by the box it draws, so an agent's note keeps the mark above it clear
    /// of its badge, which rises more than an em above the tag.
    func testABadgedAgentNotesBoxHoldsItsBadge() throws {
        let ink = CGRect(x: 510, y: 435, width: 156, height: 64)
        let scene = LiveAnswerLayout.Scene(room: room, ink: [Mark(geometry: .ellipse(ink))], text: [])
        let note = LiveAnswerLayout.note("Should be $194.24", near: ink, scene: scene, obstacles: [], sizes: sizes)
        guard case .text(let text) = note.geometry else { return XCTFail("not a note") }
        let layout = TextLayout(text, imageWidth: .greatestFiniteMagnitude, pointScale: 1, style: sizes.style.forMark(note))
        let badge = try XCTUnwrap(layout.badge, "an agent's note carries its badge")
        let box = try XCTUnwrap(LiveAnswerLayout.noteBox(note, sizes: sizes))
        XCTAssertTrue(box.contains(badge.frame(on: layout.box)), "\(box) holds \(badge.frame(on: layout.box))")
    }

    /// A result card's words go beside the first mark rather than over the window's title bar, and
    /// no text on the card covers a mark or another text. How many marks there are is the same with
    /// or without a picture to measure on, since a reply's stored drawing is checked against it.
    func testAnAnswersWordsOnACardGoBesideItsFirstMarkAndCoverNothing() throws {
        let answer = try LiveAnswer(json: ["say": "Made the button green and moved the email field under it.", "marks": [
            ["kind": "circle", "box": [0.42, 0.40, 0.14, 0.06], "label": "Now green"],
            ["kind": "arrow", "box": [0.10, 0.70, 0.22, 0.05], "label": "Field moved"]]])
        let pixels = PixelSize(width: 2400, height: 1600), scale: CGFloat = 2, style = UITweaks().textStyle
        // A browser's page, below its toolbar.
        let page = CGRect(x: 0, y: 0.08, width: 1, height: 0.92)
        let canvas = LiveAnswer.Canvas(pixels: pixels, pointScale: scale, style: style, agent: "claude", page: page)
        // A field's placeholder left of the button, where the words would otherwise go, and the word
        // after the arrow's, which an arrow from the right would cross.
        let line = CGRect(x: 0.16, y: 0.41, width: 0.22, height: 0.04)
        let next = CGRect(x: 0.33, y: 0.70, width: 0.2, height: 0.05)
        let laidOut = answer.cardMarks(targets: answer.marks.map(\.box), text: [line, next], on: canvas)
        XCTAssertEqual(laidOut.map(\.type), answer.cardMarks(targets: answer.marks.map(\.box), on: nil).map(\.type))
        XCTAssertEqual(laidOut.first?.text, answer.say)

        let marks = AgentMark.marks(laidOut, from: "claude", in: pixels, pointScale: scale, style: style).marks
        XCTAssertEqual(marks.count, laidOut.count)
        func extent(_ mark: Mark) -> CGRect {
            guard case .text(let text) = mark.geometry else { return mark.shapeExtent ?? .null }
            return TextLayout(text, imageWidth: CGFloat(pixels.width), pointScale: scale, style: style.forMark(mark)).drawnBox()
        }
        let extents = marks.map(extent)
        XCTAssertTrue(zip(marks, extents).allSatisfy { mark, extent in
            if case .text = mark.geometry { extent.minY >= page.minY * CGFloat(pixels.height) } else { true }
        }, "the texts keep off the toolbar")
        for (i, a) in extents.enumerated() {
            guard case .text = marks[i].geometry else { continue }
            for (j, b) in extents.enumerated() where j != i {
                XCTAssertFalse(a.intersects(b), "text \(i) covers mark \(j)")
            }
        }
        let words = extents[0], ring = extents[1]
        XCTAssertGreaterThan(words.minY, CGFloat(pixels.height) * 0.1, "off the title bar")
        func px(_ fraction: CGRect) -> CGRect {
            CGRect(x: fraction.minX * CGFloat(pixels.width), y: fraction.minY * CGFloat(pixels.height),
                   width: fraction.width * CGFloat(pixels.width), height: fraction.height * CGFloat(pixels.height))
        }
        XCTAssertFalse(words.intersects(px(line)), "off the page's own text")

        let index = try XCTUnwrap(marks.firstIndex { if case .arrow = $0.geometry { true } else { false } })
        guard case .arrow(let arrow) = marks[index].geometry else { return XCTFail("no arrow") }
        let target = px(try XCTUnwrap(answer.marks[1].box))
        let reach = max(target.minX - arrow.end.x, arrow.end.x - target.maxX, target.minY - arrow.end.y, arrow.end.y - target.maxY)
        XCTAssertLessThanOrEqual(reach, 8 * scale, "the head stops at the words it names")
        XCTAssertFalse(extents[index].intersects(px(next)), "the arrow keeps off the next word")
        let gap = max(ring.minX - words.maxX, words.minX - ring.maxX, ring.minY - words.maxY, words.minY - ring.maxY)
        XCTAssertLessThanOrEqual(gap, 12 * scale, "beside the first mark")
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

    // MARK: A result card

    /// A line of a window's text at `box`, in fractions of the picture, whose characters each take an
    /// equal part of its width, as a monospaced reading would.
    private func line(_ id: String, _ read: String, _ box: CGRect) -> LivePacket.Line {
        LivePacket.Line(id: id, read: read, box: box) { range in
            let total = CGFloat(read.count)
            let offset = CGFloat(read.distance(from: read.startIndex, to: range.lowerBound))
            let count = CGFloat(read.distance(from: range.lowerBound, to: range.upperBound))
            return CGRect(x: box.minX + box.width * offset / total, y: box.minY, width: box.width * count / total, height: box.height)
        }
    }

    /// A line whose reading gives no box for any part of it.
    private func unboxedLine(_ id: String, _ read: String, _ box: CGRect) -> LivePacket.Line {
        LivePacket.Line(id: id, read: read, box: box) { _ in nil }
    }

    /// The box `line` gives for the first `words` in it, as it reads them.
    @MainActor private func box(of words: String, in line: LivePacket.Line) throws -> CGRect {
        try XCTUnwrap(line.box(of: try XCTUnwrap(line.read.range(of: words))))
    }

    /// The screen and a result card find what an answer's mark names by this one rule.
    @MainActor func testAMarkFindsItsWordsAsTheWindowReadThem() throws {
        let title = line("t1", "Subscribe to Field Notes newsletter", CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.04))
        let field = line("t2", "Email address", CGRect(x: 0.1, y: 0.3, width: 0.3, height: 0.04))
        let again = line("t3", "Field Notes, every Friday", CGRect(x: 0.1, y: 0.5, width: 0.4, height: 0.04))
        let lines = [title, field, again]
        let all = Set(lines.map(\.id))
        func target(_ mark: AnswerMark, in lines: [LivePacket.Line] = lines, sent: Set<String> = all) -> CGRect? {
            mark.target(in: lines, sent: sent)
        }

        XCTAssertEqual(target(AnswerMark(kind: .arrow, words: "field notes")), try box(of: "Field Notes", in: title),
                       "words in another case are the first line's that has them, of the two that do")
        XCTAssertEqual(target(AnswerMark(kind: .circle, words: "Email-Address")), field.box,
                       "with other punctuation, the line whose letters hold them, all of it")
        let twice = line("t1", "Total: $12, then Total again", CGRect(x: 0.2, y: 0.6, width: 0.6, height: 0.05))
        XCTAssertEqual(target(AnswerMark(kind: .circle, words: "total"), in: [twice], sent: ["t1"]), try box(of: "Total", in: twice),
                       "the first time a line says them")
        let loosely = line("t1", "Field-Notes archive", CGRect(x: 0.1, y: 0.05, width: 0.3, height: 0.03))
        XCTAssertEqual(target(AnswerMark(kind: .arrow, words: "Field Notes"), in: [loosely, title], sent: ["t1", "t2"]),
                       try box(of: "Field Notes", in: title), "a line that has the words as they are wins over an earlier loose one")

        XCTAssertEqual(target(AnswerMark(kind: .circle, line: "t2", words: "Field Notes"), sent: ["t1"]), try box(of: "Field Notes", in: title),
                       "a line the answer was not sent is not taken, and the words are looked for")
        XCTAssertEqual(target(AnswerMark(kind: .circle, line: "t2", words: "Field Notes")), field.box,
                       "a line sent that lacks the words is the place, whole, and no other line is searched")
        XCTAssertEqual(target(AnswerMark(kind: .circle, line: "t3", words: "field notes")), try box(of: "Field Notes", in: again),
                       "a sent line that has the words gives their box there, though an earlier line has them too")

        let long = String(repeating: "lorem ipsum ", count: 18) + "Unsubscribe here " + String(repeating: "dolor sit ", count: 5)
        let wide = line("t1", long, CGRect(x: 0, y: 0.9, width: 1, height: 0.02))
        XCTAssertEqual(wide.text.count, LivePacket.maxLineLength, "an ask sends the line cut short")
        XCTAssertEqual(target(AnswerMark(kind: .circle, words: "unsubscribe"), in: [wide], sent: ["t1"]), try box(of: "Unsubscribe", in: wide),
                       "words past the part an ask sends are still found")

        let blank = unboxedLine("t1", "Save changes", CGRect(x: 0.7, y: 0.8, width: 0.2, height: 0.04))
        XCTAssertEqual(target(AnswerMark(kind: .circle, words: "changes"), in: [blank], sent: ["t1"]), blank.box,
                       "words the reading gives no box for are the whole line")
        let place = CGRect(x: 0.6, y: 0.6, width: 0.1, height: 0.1)
        XCTAssertEqual(target(AnswerMark(kind: .circle, box: place)), place)
        XCTAssertEqual(target(AnswerMark(kind: .circle, words: "Unsubscribe", box: place)), place, "words found nowhere fall back to the box")
        XCTAssertNil(target(AnswerMark(kind: .arrow, words: "Unsubscribe")), "words found nowhere with no box point at nothing")
    }

    /// A card's note is placed by the box it draws, then set again by `AgentMark.marks` on the card, so
    /// the two must agree on its wrap, its fit, the margin and its badge.
    func testACardNoteStaysWhereAgentMarksPlacedIt() throws {
        let pixels = PixelSize(width: 2400, height: 1600), scale: CGFloat = 2, style = UITweaks().textStyle
        // A browser's page below its toolbar, in the picture's points.
        let page = CGRect(x: 0, y: 60, width: 1200, height: 740)
        let room = AgentMark.textRoom(CGSize(width: 1200, height: 800)).intersection(page)
        // At the room's right edge with text on its left, so the note goes under it, flush with that edge,
        // where a fit that kept another margin would move it.
        let near = CGRect(x: room.maxX - 100, y: 300, width: 100, height: 30)
        let obstacle = CGRect(x: 700, y: 280, width: near.minX - 10 - 700, height: 55)
        // Given the page alone, the note keeps the margin itself.
        let placed = try XCTUnwrap(AgentMark.note("Made the button green and moved the email field under it.", from: "claude", near: near,
                                                  room: page, obstacles: [obstacle], in: pixels, pointScale: scale, style: style))
        XCTAssertEqual(placed.covers.maxX, room.maxX, accuracy: 0.5)

        let set = try XCTUnwrap(AgentMark.marks([placed.mark], from: "claude", in: pixels, pointScale: scale, style: style).marks.first)
        guard case .text(let text) = set.geometry else { return XCTFail("not a note") }
        let drawn = TextLayout(text, imageWidth: CGFloat(pixels.width), pointScale: scale, style: style.forMark(set)).drawnBox()
        XCTAssertNotNil(style.forMark(set).badge, "an agent's note, with its badge")
        XCTAssertEqual(drawn.minX / scale, placed.covers.minX, accuracy: 0.5)
        XCTAssertEqual(drawn.minY / scale, placed.covers.minY, accuracy: 0.5)
        XCTAssertEqual(drawn.maxX / scale, placed.covers.maxX, accuracy: 0.5)
        XCTAssertEqual(drawn.maxY / scale, placed.covers.maxY, accuracy: 0.5)
        XCTAssertTrue(room.insetBy(dx: -0.5, dy: -0.5).contains(placed.covers), "off the toolbar and inside the margin")
        XCTAssertFalse(placed.covers.intersects(obstacle))

        // Beside something at the page's own edge, where the page alone would let the note reach
        // into the margin and the fit then move it.
        let atEdge = CGRect(x: page.maxX - 100, y: 300, width: 100, height: 30)
        let left = CGRect(x: 700, y: 280, width: atEdge.minX - 10 - 700, height: 55)
        let edged = try XCTUnwrap(AgentMark.note("Made the button green and moved the email field under it.", from: "claude", near: atEdge,
                                                 room: page, obstacles: [left], in: pixels, pointScale: scale, style: style))
        let setAtEdge = try XCTUnwrap(AgentMark.marks([edged.mark], from: "claude", in: pixels, pointScale: scale, style: style).marks.first)
        guard case .text(let edgeText) = setAtEdge.geometry else { return XCTFail("not a note") }
        let drawnAtEdge = TextLayout(edgeText, imageWidth: CGFloat(pixels.width), pointScale: scale, style: style.forMark(setAtEdge)).drawnBox()
        XCTAssertEqual(drawnAtEdge.minX / scale, edged.covers.minX, accuracy: 0.5, "the fit leaves it where it was placed")
        XCTAssertEqual(drawnAtEdge.minY / scale, edged.covers.minY, accuracy: 0.5)
        XCTAssertTrue(room.insetBy(dx: -0.5, dy: -0.5).contains(edged.covers), "inside the margin")
    }

    /// The window a result card is made from, in global top-left points, captured at 2 px a point.
    private let cardFrame = CGRect(x: 200, y: 100, width: 1200, height: 800)
    private let cardPixels = PixelSize(width: 2400, height: 1600)

    /// `answer` on a result card of the window at `cardFrame` with `lines`, and the card's marks set
    /// as the card sets them.
    @MainActor private func resultCard(_ answer: LiveAnswer, lines: [LivePacket.Line], page: CGRect? = nil,
                            about ink: CGRect = CGRect(x: 600, y: 400, width: 80, height: 40))
    -> (marks: [AgentMark], notDrawn: [Int], set: [Mark]) {
        let style = UITweaks().textStyle
        let card = ResultCard(frame: cardFrame, pixels: cardPixels, pointScale: 2, page: page, lines: lines)
        let made = card.marks(for: answer, about: ink, style: style, agent: "claude")
        let set = AgentMark.marks(made.marks, from: "claude", in: cardPixels, pointScale: 2, style: style).marks
        XCTAssertEqual(set.count, made.marks.count, "the card draws every mark")
        return (made.marks, made.notDrawn, set)
    }

    /// A rect in global top-left points in the card's px.
    private func cardPx(_ rect: CGRect) -> CGRect {
        CGRect(x: (rect.minX - cardFrame.minX) * 2, y: (rect.minY - cardFrame.minY) * 2, width: rect.width * 2, height: rect.height * 2)
    }

    /// What a text on the card draws, in its px.
    private func drawnBox(_ mark: Mark) -> CGRect? {
        guard case .text(let text) = mark.geometry else { return nil }
        let style = UITweaks().textStyle
        return TextLayout(text, imageWidth: CGFloat(cardPixels.width), pointScale: 2, style: style.forMark(mark)).drawnBox()
    }

    /// A ring round words has room round them; an arrow ends at them, since a ring's room would put
    /// its head in the next word.
    @MainActor func testAResultCardsArrowEndsAtTheWordsItNamesAndARingHasRoomRoundThem() throws {
        let title = line("t1", "Subscribe to Field Notes newsletter", CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.04))
        let field = line("t2", "Email address", CGRect(x: 0.3, y: 0.5, width: 0.2, height: 0.04))
        let alone = CGRect(x: 0.7, y: 0.75, width: 0.1, height: 0.08)
        let answer = LiveAnswer(say: "Renamed the list.", marks: [AnswerMark(kind: .arrow, words: "field notes"),
                                                                  AnswerMark(kind: .circle, words: "Email address"),
                                                                  AnswerMark(kind: .circle, box: alone),
                                                                  AnswerMark(kind: .circle, line: "t2")])
        let card = resultCard(answer, lines: [title, field])
        XCTAssertEqual(card.notDrawn, [])
        XCTAssertEqual(card.marks.map(\.type), [.text, .arrow, .ellipse, .ellipse, .ellipse])

        guard case .arrow(let arrow) = card.set[1].geometry else { return XCTFail("no arrow") }
        let words = cardPx(LivePacket.global(try box(of: "Field Notes", in: title), in: cardFrame))
        let reach = max(words.minX - arrow.end.x, arrow.end.x - words.maxX, words.minY - arrow.end.y, arrow.end.y - words.maxY)
        XCTAssertLessThanOrEqual(reach, 8 * 2, "the head stops at the words it names")

        func assertRoom(_ ring: Mark, round place: CGRect, _ what: String) {
            guard case .ellipse(let ring) = ring.geometry else { return XCTFail("no ring") }
            let clear = place.insetBy(dx: -4 * 2, dy: -3 * 2)
            for corner in [CGPoint(x: clear.minX, y: clear.minY), CGPoint(x: clear.maxX, y: clear.minY),
                           CGPoint(x: clear.minX, y: clear.maxY), CGPoint(x: clear.maxX, y: clear.maxY)] {
                XCTAssertTrue(EditorGeometry.ellipse(ring, contains: corner), "the ring goes round \(what) with room: \(corner) in \(ring)")
            }
        }
        assertRoom(card.set[2], round: cardPx(LivePacket.global(try box(of: "Email address", in: field), in: cardFrame)), "the words")
        assertRoom(card.set[4], round: cardPx(LivePacket.global(field.box, in: cardFrame)), "a line named by its id")

        let boxed = card.marks[3]
        XCTAssertEqual(boxed.x, alone.minX, accuracy: 1e-9, "a box the answer gave is already what it means")
        XCTAssertEqual(boxed.y, alone.minY, accuracy: 1e-9)
        XCTAssertEqual(boxed.w ?? 0, alone.width, accuracy: 1e-9)
        XCTAssertEqual(boxed.h ?? 0, alone.height, accuracy: 1e-9)
    }

    /// In a browser the card's words keep to the page, off its toolbar, but an arrow at a word in the
    /// page's first line may come down across the toolbar, the one way to it that crosses no text.
    @MainActor func testAResultCardsTextsKeepToThePageWhileItsArrowMayCrossTheToolbar() throws {
        // The page starts 100 pt down. Its title is one line Vision reads across the page, with a
        // line of text right under it.
        let page = CGRect(x: cardFrame.minX, y: cardFrame.minY + 100, width: cardFrame.width, height: cardFrame.height - 100)
        let title = line("t1", "The weekly Field Notes for people who build small useful things", CGRect(x: 0.02, y: 0.13, width: 0.96, height: 0.035))
        let under = line("t2", String(repeating: "Every Friday, a short letter about tools and craft. ", count: 2),
                         CGRect(x: 0.02, y: 0.17, width: 0.96, height: 0.03))
        let answer = LiveAnswer(say: "Renamed it Field Notes.", marks: [AnswerMark(kind: .arrow, words: "Field Notes", label: "New name")])
        let card = resultCard(answer, lines: [title, under], page: page)
        let pageTop = cardPx(page).minY

        guard case .arrow(let arrow) = try XCTUnwrap(card.set.first { $0.kind == .arrow }).geometry else { return XCTFail("no arrow") }
        XCTAssertLessThan(arrow.start.y, pageTop, "the arrow comes down across the toolbar")
        let texts = card.set.compactMap(drawnBox)
        XCTAssertEqual(texts.count, 2, "the words and the label")
        for text in texts { XCTAssertGreaterThanOrEqual(text.minY, pageTop - 0.01, "a text keeps off the toolbar") }
    }

    /// Words the window no longer shows are reported, not drawn somewhere else.
    @MainActor func testAResultCardReportsTheMarksItCouldNotFind() throws {
        let field = line("t1", "Email address", CGRect(x: 0.3, y: 0.5, width: 0.2, height: 0.04))
        let edge = line("t2", "Sign in", CGRect(x: 0.92, y: 0.2, width: 0.08, height: 0.04))
        // Right of the field, where the words would go first beside its ring.
        let hint = line("t3", "Required field", CGRect(x: 0.56, y: 0.5, width: 0.24, height: 0.04))
        let fallback = CGRect(x: 0.6, y: 0.6, width: 0.1, height: 0.05)
        let answer = LiveAnswer(say: "Two of these are gone.", marks: [AnswerMark(kind: .circle, words: "email address"),
                                                                       AnswerMark(kind: .arrow, words: "Unsubscribe"),
                                                                       AnswerMark(kind: .circle, line: "t9"),
                                                                       AnswerMark(kind: .circle, words: "Plans", box: fallback),
                                                                       AnswerMark(kind: .circle, words: "Sign in")])
        let card = resultCard(answer, lines: [field, edge, hint])
        XCTAssertEqual(card.notDrawn, [1, 2])
        XCTAssertEqual(card.marks.map(\.type), [.text, .ellipse, .ellipse, .ellipse], "the words, then a ring for each mark found")

        guard case .ellipse(let standIn) = card.set[2].geometry else { return XCTFail("no ring") }
        XCTAssertTrue(standIn.insetBy(dx: -0.5, dy: -0.5).contains(cardPx(LivePacket.global(fallback, in: cardFrame))),
                      "words not found are ringed at the box the answer gave")
        let atEdge = card.marks[3]
        XCTAssertEqual(atEdge.x + (atEdge.w ?? 0), 1, accuracy: 1e-9, "a ring at the window's edge is cut at the card's")

        guard case .ellipse(let first) = card.set[1].geometry else { return XCTFail("no ring") }
        let said = try XCTUnwrap(drawnBox(card.set[0]))
        let gap = max(first.minX - said.maxX, said.minX - first.maxX, first.minY - said.maxY, said.minY - first.maxY)
        XCTAssertLessThanOrEqual(gap, 12 * 2, "the words go beside the first mark drawn")
        for line in [field, edge, hint] {
            XCTAssertFalse(said.intersects(cardPx(LivePacket.global(line.box, in: cardFrame))), "the words keep off the window's \(line.read)")
        }

        // With no mark found, the words go beside the ink the note was about.
        let ink = CGRect(x: 1000, y: 300, width: 80, height: 40)
        let lost = LiveAnswer(say: "Both are gone.", marks: [AnswerMark(kind: .arrow, words: "Unsubscribe"),
                                                             AnswerMark(kind: .circle, line: "t9", label: "Was here")])
        let alone = resultCard(lost, lines: [field, edge], about: ink)
        XCTAssertEqual(alone.notDrawn, [0, 1])
        XCTAssertEqual(alone.marks.map(\.type), [.text], "no mark, and no label for one")
        let words = try XCTUnwrap(drawnBox(alone.set[0]))
        let about = cardPx(ink)
        XCTAssertLessThanOrEqual(max(about.minX - words.maxX, words.minX - about.maxX, about.minY - words.maxY, words.minY - about.maxY),
                                 12 * 2, "the words go beside the ink")
    }

    // MARK: Whether a change landed

    func testTheRegionComparedIsTheInkWithAMarginInsideTheWindow() {
        let room = CGRect(x: 0, y: 0, width: 500, height: 400)
        XCTAssertEqual(LiveChange.region(around: CGRect(x: 100, y: 100, width: 50, height: 20), in: room),
                       CGRect(x: 88, y: 88, width: 74, height: 44))
        XCTAssertEqual(LiveChange.region(around: CGRect(x: 490, y: 5, width: 40, height: 20), in: room),
                       CGRect(x: 478, y: 0, width: 22, height: 37))
        XCTAssertNil(LiveChange.region(around: CGRect(x: 600, y: 100, width: 50, height: 20), in: room))
    }

    func testTheSamePictureHasNotChanged() throws {
        let page = try Self.region(blocks: [CGRect(x: 20, y: 20, width: 60, height: 14)])
        guard case .unchanged = LiveChange.compare(before: page, after: page, again: page, size: CGSize(width: 200, height: 80)) else {
            return XCTFail("the same picture read as changed")
        }
    }

    func testSomethingNewUnderTheInkIsAChange() throws {
        let before = try Self.region(blocks: [CGRect(x: 20, y: 20, width: 60, height: 14)])
        let after = try Self.region(blocks: [CGRect(x: 20, y: 20, width: 60, height: 14), CGRect(x: 120, y: 30, width: 40, height: 30)])
        guard case .changed(let share, let around) = LiveChange.compare(before: before, after: after, again: after, size: CGSize(width: 200, height: 80)) else {
            return XCTFail("a new block read as no change")
        }
        XCTAssertEqual(share, 0.075, accuracy: 0.02)
        XCTAssertEqual(around.minX, 120, accuracy: 3)
        XCTAssertEqual(around.maxY, 60, accuracy: 3)
    }

    func testOnlyTheInkDecidesButTheChangeRoundItIsKept() throws {
        let ink = CGRect(x: 20, y: 20, width: 50, height: 40)
        let before = try Self.region(blocks: [CGRect(x: 30, y: 30, width: 50, height: 20)])
        // The block under the ink grew past it to the right.
        let grew = try Self.region(blocks: [CGRect(x: 30, y: 30, width: 130, height: 20)])
        guard case .unchanged = LiveChange.compare(before: before, after: grew, again: grew, size: CGSize(width: 200, height: 80), ink: ink) else {
            return XCTFail("a change outside the ink decided")
        }
        // Grown and moved down, so the ink's part changed too.
        let moved = try Self.region(blocks: [CGRect(x: 30, y: 44, width: 130, height: 20)])
        guard case .changed(_, let around) = LiveChange.compare(before: before, after: moved, again: moved, size: CGSize(width: 200, height: 80), ink: ink) else {
            return XCTFail("the change under the ink read as none")
        }
        XCTAssertEqual(around.maxX, 160, accuracy: 3)
    }

    func testAFewPixelsAreNotAChange() throws {
        let before = try Self.region(blocks: [])
        let after = try Self.region(blocks: [CGRect(x: 100, y: 40, width: 3, height: 3)])
        guard case .unchanged = LiveChange.compare(before: before, after: after, again: after, size: CGSize(width: 200, height: 80)) else {
            return XCTFail("a dot read as a change")
        }
    }

    func testWhatMovesOnItsOwnAfterTheTurnIsNotAChange() throws {
        // A spinner: there in one picture after the turn, gone in the next.
        let before = try Self.region(blocks: [])
        let after = try Self.region(blocks: [CGRect(x: 100, y: 10, width: 12, height: 60)])
        guard case .changed = LiveChange.compare(before: before, after: after, again: nil, size: CGSize(width: 200, height: 80)) else {
            return XCTFail("the caret alone did not read as a change")
        }
        guard case .unchanged = LiveChange.compare(before: before, after: after, again: before, size: CGSize(width: 200, height: 80)) else {
            return XCTFail("a caret that blinked read as a change")
        }
    }

    func testARecolourAtTheSameBrightnessIsAChange() throws {
        // A green and a red that read only 18 apart in grey, under the threshold.
        let button = CGRect(x: 120, y: 30, width: 60, height: 30)
        let green = try Self.region(blocks: [button], colour: CGColor(srgbRed: 0x1f / 255, green: 0x9d / 255, blue: 0x55 / 255, alpha: 1))
        let red = try Self.region(blocks: [button], colour: CGColor(srgbRed: 0xd9 / 255, green: 0x36 / 255, blue: 0x36 / 255, alpha: 1))
        guard case .changed = LiveChange.compare(before: green, after: red, again: red, size: CGSize(width: 200, height: 80)) else {
            return XCTFail("a green button turned red read as no change")
        }
    }

    func testACropKeepsThePixelsUnderItsRect() throws {
        let page = try Self.region(blocks: [CGRect(x: 100, y: 40, width: 20, height: 20)])
        // The window at (1000, 500), at 1 px per pt.
        let crop = try XCTUnwrap(LiveChange.crop(page, frame: CGRect(x: 1000, y: 500, width: 200, height: 80),
                                                 to: CGRect(x: 1090, y: 530, width: 40, height: 40)))
        XCTAssertEqual(crop.width, 40)
        XCTAssertEqual(crop.height, 40)
        guard case .changed = LiveChange.compare(before: try Self.region(blocks: [], size: CGSize(width: 40, height: 40)), after: crop,
                                                 again: crop, size: CGSize(width: 40, height: 40)) else {
            return XCTFail("the crop lost the block")
        }
    }

    /// Catches the notes of one window being judged by one another's part of it: a change under one
    /// note's ink making every note on the window read as changed, or a note whose window has
    /// changed size being compared against a picture of another shape.
    @MainActor func testEachNoteOfAWindowIsComparedOnItsOwnPart() throws {
        let frame = CGRect(x: 100, y: 50, width: 400, height: 300)
        func before(region: CGRect, ink: CGRect, windowSize: CGSize = CGSize(width: 400, height: 300)) throws -> LiveNoteCards.Before {
            LiveNoteCards.Before(picture: try Self.region(blocks: [], size: region.size), region: region, ink: ink, windowSize: windowSize, windowID: 7)
        }
        // A block has appeared under the first note's ink, and nowhere near the second's.
        let now = try Self.region(blocks: [CGRect(x: 50, y: 40, width: 40, height: 20)], size: frame.size)
        let first = try before(region: CGRect(x: 20, y: 20, width: 200, height: 80), ink: CGRect(x: 40, y: 30, width: 60, height: 30))
        let second = try before(region: CGRect(x: 220, y: 150, width: 150, height: 100), ink: CGRect(x: 240, y: 170, width: 50, height: 40))
        let resized = try before(region: CGRect(x: 20, y: 20, width: 200, height: 80), ink: CGRect(x: 40, y: 30, width: 60, height: 30),
                                 windowSize: CGSize(width: 300, height: 300))
        let outside = try before(region: CGRect(x: 500, y: 400, width: 50, height: 50), ink: CGRect(x: 510, y: 410, width: 20, height: 20))
        let result = LiveNoteCards.compare([("a", first), ("b", second), ("c", resized), ("d", outside)],
                                           after: (now, frame), again: (now, frame))
        XCTAssertEqual(result.changed, ["a"])
        XCTAssertEqual(result.uncompared, ["c", "d"])
    }

    /// A white picture of `size` points at 1 px per pt with `blocks` in `colour`, from its top-left corner.
    private static func region(blocks: [CGRect], size: CGSize = CGSize(width: 200, height: 80),
                               colour: CGColor = CGColor(gray: 0, alpha: 1)) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(colour)
        for block in blocks { context.fill(CGRect(x: block.minX, y: size.height - block.maxY, width: block.width, height: block.height)) }
        return try XCTUnwrap(context.makeImage())
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
