import AppKit
import XCTest

final class VoiceCaretTests: XCTestCase {
    private func edge(x: CGFloat, line: Int) -> VoiceCaret.Edge {
        VoiceCaret.Edge(x: x, lineTop: CGFloat(line) * 16, middle: CGFloat(line) * 16 + 9, lineHeight: 16)
    }

    func testTheWaveformStaysCentredOnItsLineAndNeverTallerThanTheLetters() {
        var wave = VoiceCaret(lineWidth: 276, edge: edge(x: 0, line: 0))
        var x: CGFloat = 0
        for frame in 0..<600 {
            x = min(x + CGFloat(frame % 3), 270)
            wave.tick(1.0 / 60, edge: edge(x: x, line: 0), level: Float(frame % 7) / 6, motion: 1)
            for bar in wave.bars {
                XCTAssertEqual(bar.top + bar.height / 2, 9, accuracy: 0.001)
                XCTAssertLessThanOrEqual(bar.height, VoiceCaret.tallest)
                XCTAssertGreaterThanOrEqual(bar.x, x, "letters take the bars from the left")
                XCTAssertLessThanOrEqual(bar.x + VoiceCaret.barWidth, 276, "the bars stop at the line's end")
            }
        }
    }

    func testTheWaveformKeepsItsWidthAndRollsRatherThanSlides() {
        var wave = VoiceCaret(lineWidth: 276, edge: edge(x: 0, line: 0))
        for _ in 0..<60 { wave.tick(1.0 / 60, edge: edge(x: 0, line: 0), level: 1, motion: 1) }
        let slots = Set(wave.bars.map(\.x))
        for _ in 0..<60 { wave.tick(1.0 / 60, edge: edge(x: 40, line: 0), level: 1, motion: 1) }
        let span = { (bars: [VoiceCaret.Bar]) in (bars.map(\.x).max() ?? 0) - (bars.map(\.x).min() ?? 0) }
        XCTAssertLessThanOrEqual(span(wave.bars), VoiceCaret.width)
        XCTAssertGreaterThanOrEqual(span(wave.bars), VoiceCaret.width - 2 * VoiceCaret.pitch)
        XCTAssertTrue(wave.bars.allSatisfy { $0.x.truncatingRemainder(dividingBy: VoiceCaret.pitch) == 0 }, "the bars sit on a fixed grid")
        XCTAssertFalse(Set(wave.bars.map(\.x)).isSubset(of: slots), "new bars came in on the right")
    }

    func testTheWaveformMovesToTheNextLineOnlyWithALetterAndAtOnce() {
        var wave = VoiceCaret(lineWidth: 276, edge: edge(x: 0, line: 0))
        for _ in 0..<30 { wave.tick(1.0 / 60, edge: edge(x: 270, line: 0), level: 1, motion: 1) }
        XCTAssertFalse(wave.bars.isEmpty)
        XCTAssertTrue(wave.bars.allSatisfy { abs($0.top + $0.height / 2 - 9) < 0.001 })
        wave.tick(1.0 / 60, edge: edge(x: 6, line: 1), level: 1, motion: 1)
        XCTAssertTrue(wave.bars.allSatisfy { abs($0.top + $0.height / 2 - 25) < 0.001 })
        XCTAssertEqual(wave.left, 6)
    }

    func testTheWaveformFoldsIntoTheCaretAtTheWordsEnd() {
        var wave = VoiceCaret(lineWidth: 276, edge: edge(x: 50, line: 0))
        XCTAssertNil(wave.caret)
        wave.fold()
        for _ in 0..<30 { wave.tick(1.0 / 60, edge: edge(x: 50, line: 0), level: 1, motion: 1) }
        XCTAssertTrue(wave.isFolded)
        XCTAssertTrue(wave.bars.allSatisfy { $0.height == 0 && $0.opacity == 0 })
        XCTAssertEqual(wave.caret?.x, 51)
        XCTAssertEqual(wave.caret?.height, 14)
    }

    func testWithNoMotionTheWaveformIsStillAndFoldsAtOnce() {
        var wave = VoiceCaret(lineWidth: 276, edge: edge(x: 0, line: 0))
        wave.tick(1.0 / 60, edge: edge(x: 0, line: 0), level: 1, motion: 0)
        let still = wave.bars
        wave.tick(1.0 / 60, edge: edge(x: 0, line: 0), level: 0, motion: 0)
        XCTAssertEqual(wave.bars, still)
        wave.fold()
        wave.tick(1.0 / 60, edge: edge(x: 0, line: 0), level: 0, motion: 0)
        XCTAssertTrue(wave.isFolded)
    }

    func testLettersShowOneAtATimeAndFadeIn() {
        var letters = HeardLetters()
        letters.hear("Make this")
        letters.tick(at: 0, motion: 1)
        XCTAssertEqual(letters.shown, 1)
        let later = HeardLetters.interval * 3 + 0.001
        letters.tick(at: later, motion: 1)
        XCTAssertEqual(letters.shown, 4)
        XCTAssertLessThan(letters.strength(of: 3, at: later, motion: 1), 1)
        XCTAssertEqual(letters.strength(of: 0, at: HeardLetters.fade, motion: 1), 1)
        XCTAssertEqual(letters.strength(of: 8, at: later, motion: 1), 0)
    }

    func testLettersNeverFallFurtherBehindThanTheirLimit() {
        var letters = HeardLetters()
        letters.hear(String(repeating: "word ", count: 40))
        var now: TimeInterval = 0
        while !letters.allShown, now < 2 {
            letters.tick(at: now, motion: 1)
            now += 1.0 / 60
        }
        XCTAssertTrue(letters.allShown)
        XCTAssertLessThanOrEqual(now, HeardLetters.mostBehind + 0.05)
    }

    func testACorrectedWordChangesInPlaceAndAShorterOneHidesNothingElse() {
        var letters = HeardLetters()
        letters.hear("the same blew")
        letters.showAll(at: 0)
        letters.hear("the same blue")
        XCTAssertTrue(letters.allShown)
        letters.hear("the same")
        XCTAssertEqual(letters.shown, 8)
        XCTAssertEqual(letters.newestWord, 4)
    }

    func testWithNoMotionLettersShowAtOnce() {
        var letters = HeardLetters()
        letters.hear("Make this")
        letters.tick(at: 0, motion: 0)
        XCTAssertTrue(letters.allShown)
        XCTAssertEqual(letters.strength(of: 8, at: 0, motion: 0), 1)
    }

    func testTheVoicesLevelRunsFromAQuietRoomToCloseSpeech() {
        XCTAssertEqual(VoiceLevels.level(rms: 0), 0)
        XCTAssertEqual(VoiceLevels.level(rms: pow(10, -50.0 / 20)), 0, accuracy: 0.001)
        XCTAssertEqual(VoiceLevels.level(rms: pow(10, -15.0 / 20)), 1, accuracy: 0.001)
        XCTAssertEqual(VoiceLevels.level(rms: 1), 1)
    }

    func testLevelsPlayBackAtTheRateTheyWereHeardAndNeverFallFarBehind() {
        var levels = VoiceLevels()
        levels.add((0..<10).map { Float($0) / 10 })
        levels.advance(0.035)
        XCTAssertEqual(levels.current, 0.2, accuracy: 0.001)
        levels.add(Array(repeating: 1, count: 40))
        levels.advance(VoiceLevels.step * Double(VoiceLevels.mostWaiting))
        XCTAssertEqual(levels.current, 1)
    }
}
