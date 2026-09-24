import XCTest

/// A press on a card flying into the editor never reaches another app and ends up in the editor;
/// a press on any other flight goes nowhere.
final class FlightPressTests: XCTestCase {
    private func event(_ phase: FlightPress.Phase, _ x: CGFloat, picture: Bool = true) -> FlightPress.Event {
        FlightPress.Event(phase: phase, picture: picture ? CGPoint(x: x, y: 0.5) : nil, screen: CGPoint(x: x * 100, y: 50),
                          modifiers: 0, time: TimeInterval(x))
    }

    func testAPressBeforeTheEditorCanTakeItIsHeldThenHandedOverInOrder() {
        var press = FlightPress()
        XCTAssertEqual(press.press(event(.pressed(clickCount: 1), 0.1), into: "a", ready: false), [])
        XCTAssertEqual(press.move(event(.dragged, 0.2)), [])
        XCTAssertEqual(press.move(event(.dragged, 0.3)), [])
        XCTAssertEqual(press.ready("a"), [event(.pressed(clickCount: 1), 0.1), event(.dragged, 0.2), event(.dragged, 0.3)])
        // From here the editor places the rest by where the pointer is on screen.
        XCTAssertEqual(press.move(event(.dragged, 0.4)), [event(.dragged, 0.4, picture: false)])
        XCTAssertEqual(press.move(event(.released, 0.5)), [event(.released, 0.5, picture: false)])
        XCTAssertNil(press.key)
        XCTAssertEqual(press.ready("a"), [], "an answer that comes again hands nothing over twice")
    }

    func testAPressOnceTheEditorCanTakeItGoesAtOnce() {
        var press = FlightPress()
        XCTAssertEqual(press.press(event(.pressed(clickCount: 2), 0.1), into: "a", ready: true), [event(.pressed(clickCount: 2), 0.1)])
        XCTAssertEqual(press.move(event(.released, 0.2)), [event(.released, 0.2, picture: false)])
        XCTAssertEqual(press.move(event(.dragged, 0.3)), [], "nothing is down any more")
    }

    func testAPressReleasedDuringTheFlightIsHandedOverWhole() {
        var press = FlightPress()
        _ = press.press(event(.pressed(clickCount: 1), 0.1), into: "a", ready: false)
        _ = press.move(event(.released, 0.2))
        XCTAssertEqual(press.ready("a"), [event(.pressed(clickCount: 1), 0.1), event(.released, 0.2)])
        XCTAssertNil(press.key)
        XCTAssertEqual(press.move(event(.dragged, 0.3)), [], "nothing is down any more")
    }

    func testAPressOnAnyOtherFlightIsSwallowedToItsRelease() {
        var press = FlightPress()
        XCTAssertEqual(press.press(event(.pressed(clickCount: 1), 0.1), into: nil, ready: false), [])
        XCTAssertEqual(press.move(event(.dragged, 0.2)), [])
        XCTAssertEqual(press.move(event(.released, 0.3)), [])
        XCTAssertEqual(press.press(event(.pressed(clickCount: 1), 0.4), into: "a", ready: true), [event(.pressed(clickCount: 1), 0.4)],
                       "the next press starts afresh")
    }

    func testAPressBesideThePictureIsSwallowed() {
        var press = FlightPress()
        XCTAssertEqual(press.press(event(.pressed(clickCount: 1), 0.1, picture: false), into: "a", ready: true), [])
        XCTAssertEqual(press.move(event(.released, 0.2)), [])
    }

    func testAPressHeldForAnImageThatTurnsBackGoesNowhere() {
        var press = FlightPress()
        _ = press.press(event(.pressed(clickCount: 1), 0.1), into: "a", ready: false)
        press.ended("b")
        XCTAssertEqual(press.key, "a", "another image ending leaves it alone")
        press.ended("a")
        XCTAssertEqual(press.move(event(.dragged, 0.2)), [])
        XCTAssertEqual(press.ready("a"), [])
        XCTAssertEqual(press.move(event(.released, 0.3)), [])
        XCTAssertNil(press.key)
    }

    func testAPressHandedOverStopsWhenTheImageLeavesTheEditor() {
        var press = FlightPress()
        _ = press.press(event(.pressed(clickCount: 1), 0.1), into: "a", ready: true)
        press.ended("a")
        XCTAssertEqual(press.move(event(.dragged, 0.2)), [])
        XCTAssertEqual(press.move(event(.released, 0.3)), [])
        XCTAssertEqual(press.press(event(.pressed(clickCount: 1), 0.4), into: "a", ready: true), [event(.pressed(clickCount: 1), 0.4)])
    }

    func testAnAnswerForAnotherImageHandsNothingOver() {
        var press = FlightPress()
        _ = press.press(event(.pressed(clickCount: 1), 0.1), into: "a", ready: false)
        XCTAssertEqual(press.ready("b"), [])
        XCTAssertEqual(press.ready("a"), [event(.pressed(clickCount: 1), 0.1)])
    }

    /// The flight fills its frame with the picture and crops any excess, the way the card does.
    func testAPointOnTheFlightIsItsPlaceOnThePicture() throws {
        let wide = CGSize(width: 200, height: 100)
        let centre = try XCTUnwrap(FlightSpotView.fraction(of: CGPoint(x: 50, y: 50), in: CGSize(width: 100, height: 100), picture: wide))
        XCTAssertEqual(centre.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(centre.y, 0.5, accuracy: 1e-9)
        let corner = try XCTUnwrap(FlightSpotView.fraction(of: .zero, in: CGSize(width: 100, height: 100), picture: wide))
        XCTAssertEqual(corner.x, 0.25, accuracy: 1e-9, "a quarter of the picture is cropped on each side")
        XCTAssertEqual(corner.y, 0, accuracy: 1e-9)
        XCTAssertNil(FlightSpotView.fraction(of: .zero, in: .zero, picture: wide))
    }
}
