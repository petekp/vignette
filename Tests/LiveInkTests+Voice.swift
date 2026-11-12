import AppKit
import XCTest

final class LiveInkVoiceTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
    private let size = CGSize(width: 300, height: 120)

    // MARK: The field and the voice

    func testTheVoiceLightsTheFieldAndSettlesOnceItStops() {
        let ui = UITweaks()
        var motion = PointerFieldMotion()
        motion.reset(at: .zero, now: 0)
        var now = 0.0
        for _ in 0..<6 {
            now += 1.0 / 60
            motion.hear(0.6, at: now)
            _ = motion.step(to: now, pointer: .zero, pressed: false, ui: ui)
        }
        XCTAssertEqual(motion.voice, 0.6, accuracy: 0.05)
        for _ in 0..<60 {
            now += 1.0 / 60
            _ = motion.step(to: now, pointer: .zero, pressed: false, ui: ui)
        }
        XCTAssertEqual(motion.voice, 0)
    }

    // MARK: The note by the pointer

    func testTheNoteHangsRightOfThePointerClearOfIt() {
        let pointer = CGPoint(x: 400, y: 400)
        let place = LiveNotePopover.pointerPlace(size, at: pointer, clearance: 40, screen: screen)
        XCTAssertNil(place.anchor)
        XCTAssertEqual(place.edge, .right)
        XCTAssertGreaterThanOrEqual(place.body.minX, pointer.x + 40)
        XCTAssertFalse(LiveNotePopover.pointer(pointer, crowds: place.body, clearance: 40))
        XCTAssertEqual(LiveNotePopover.pointer(hungFrom: place), pointer)
    }

    func testNearTheRightEdgeTheNoteHangsLeftOfThePointer() {
        let pointer = CGPoint(x: screen.maxX - 60, y: 400)
        let place = LiveNotePopover.pointerPlace(size, at: pointer, clearance: 40, screen: screen)
        XCTAssertEqual(place.edge, .left)
        XCTAssertLessThanOrEqual(place.body.maxX, pointer.x - 40)
    }

    func testAMovedNoteKeepsItsSideWhileItFits() {
        let pointer = CGPoint(x: 700, y: 400)
        let place = LiveNotePopover.pointerPlace(size, at: pointer, clearance: 40, screen: screen, keeping: .left)
        XCTAssertEqual(place.edge, .left)
    }

    func testThePointerCrowdsTheNoteWithinHalfTheClearance() {
        let body = CGRect(x: 500, y: 300, width: 300, height: 120)
        XCTAssertTrue(LiveNotePopover.pointer(CGPoint(x: 485, y: 350), crowds: body, clearance: 40))
        XCTAssertFalse(LiveNotePopover.pointer(CGPoint(x: 470, y: 350), crowds: body, clearance: 40))
    }
}
