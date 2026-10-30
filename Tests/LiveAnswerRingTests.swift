import XCTest
@testable import Vignette

final class LiveAnswerRingTests: XCTestCase {
    func testAPointersRingKeepsOffTheWordsBesideItsButtonAndItsLabelOffTheLinesBelow() throws {
        let words = CGRect(x: 30, y: 262, width: 278, height: 34)
        let button = CGRect(x: 324.5, y: 264.5, width: 124.5, height: 19)
        let rows = [CGRect(x: 20, y: 140, width: 440, height: 52), CGRect(x: 20, y: 192, width: 440, height: 52)]
        let footer = CGRect(x: 20, y: 350, width: 440, height: 30)
        let header = CGRect(x: 100, y: 50, width: 280, height: 60)
        let scene = LiveAnswerLayout.Scene(room: CGRect(x: 12, y: 12, width: 456, height: 474), ink: [], text: [footer, header],
                                           notes: rows + [words])
        let sizes = LiveAnswerLayout.Sizes(ui: UITweaks())
        let marks = LiveAnswerLayout.pointer(.circle, label: "Then this", at: button, scene: scene, sizes: sizes)
        guard marks.count == 2, case .ellipse(let ring) = marks[0].geometry else { return XCTFail("a ring and its label") }
        XCTAssertGreaterThanOrEqual(ring.minX, words.maxX + LiveAnswerLayout.ringGap - 0.5)
        for corner in [CGPoint(x: button.minX, y: button.minY), CGPoint(x: button.maxX, y: button.maxY)] {
            let x = (corner.x - ring.midX) / (ring.width / 2), y = (corner.y - ring.midY) / (ring.height / 2)
            XCTAssertLessThan(x * x + y * y, 1, "the button stays inside the ring")
        }
        let label = try XCTUnwrap(LiveAnswerLayout.noteBox(marks[1], sizes: sizes))
        XCTAssertFalse(label.intersects(footer))
        XCTAssertFalse(label.intersects(words))
    }

    func testARingWithNoRoomBesideItsButtonIsABox() {
        let button = CGRect(x: 324.5, y: 264.5, width: 124.5, height: 19)
        let words = CGRect(x: 30, y: 262, width: 290, height: 34)
        guard case .rectangle(let box) = LiveAnswerLayout.circle(around: button, keepingOff: [words]) else { return XCTFail("a box") }
        XCTAssertTrue(box.contains(button))
    }
}
