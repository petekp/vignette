import XCTest

final class EditorCoreResolvedPinsTests: XCTestCase {
    typealias Core = EditorCore
    private static let image = PixelSize(width: 1000, height: 600)

    private func core(pins: [Pin], nextPin: Int) -> Core {
        var core = Core()
        _ = core.reduce(.open(Drawing(key: "/tmp/shot.png", pixels: Self.image, pointScale: 1, marks: [], pins: pins, nextPin: nextPin),
                              style: .standard, metrics: .standard, markStyle: .standard))
        _ = core.reduce(.viewChanged(visible: Self.image.bounds))
        _ = core.reduce(.zoomChanged(1))
        _ = core.reduce(.setTool(.comment))
        return core
    }

    private func pin(_ number: Int, _ x: CGFloat, _ y: CGFloat) -> Pin {
        Pin(id: UUID(), number: number, place: .point(CGPoint(x: x, y: y)), comments: [Pin.Comment(text: "Too tight")])
    }

    private func write(_ core: inout Core, _ words: String) {
        _ = core.reduce(.composer(.changed(words)))
    }

    func testResolveAndReplyAndResolveAreEachOneStepAndANewCommentReopensThePin() throws {
        let first = pin(1, 500, 300)
        var core = core(pins: [first], nextPin: 2)
        _ = core.reduce(.composer(.open(first.id)))
        let resolved = core.reduce(.composer(.resolve))
        XCTAssertEqual(core.drawing.pins.first?.resolved?.resolver, .person)
        XCTAssertNotNil(core.drawing.pins.first?.resolved?.at)
        XCTAssertTrue(resolved.contains(.announce("Pin 1 resolved")))
        XCTAssertEqual(core.undoTitle, "Undo Resolve")
        XCTAssertEqual(core.composer, Core.Composer(pin: first.id, editing: nil, draft: ""))

        write(&core, "Still too tight")
        _ = core.reduce(.composer(.post))
        XCTAssertNil(core.drawing.pins.first?.resolved)
        XCTAssertEqual(core.undoTitle, "Undo Comment")

        write(&core, "Loosened it")
        _ = core.reduce(.composer(.resolve))
        let pin = try XCTUnwrap(core.drawing.pins.first)
        XCTAssertEqual(pin.comments.map(\.text), ["Too tight", "Still too tight", "Loosened it"])
        XCTAssertTrue(pin.isResolved)
        XCTAssertEqual(core.undoSteps.map(\.name), [.resolve, .comment, .resolve])
        core.key(.character("z"), .command)
        XCTAssertEqual(core.drawing.pins.first?.comments.map(\.text), ["Too tight", "Still too tight"])
        XCTAssertNil(core.drawing.pins.first?.resolved)
    }

    func testReopenIsOneStepAndPostsADraftFirst() throws {
        var done = pin(1, 500, 300)
        done.resolved = .byPerson()
        var core = core(pins: [done], nextPin: 2)
        _ = core.reduce(.composer(.open(done.id)))
        let reopened = core.reduce(.composer(.reopen))
        XCTAssertNil(core.drawing.pins.first?.resolved)
        XCTAssertTrue(reopened.contains(.announce("Pin 1 reopened")))
        XCTAssertTrue(reopened.contains(.composer(core.composer)), "the open popover hears of the pin it shows")
        XCTAssertEqual(core.undoTitle, "Undo Reopen")
        XCTAssertTrue(core.reduce(.composer(.reopen)).isEmpty, "an open pin has nothing to reopen")
        XCTAssertEqual(core.undoSteps.map(\.name), [.reopen])

        var again = self.core(pins: [done], nextPin: 2)
        _ = again.reduce(.composer(.open(done.id)))
        write(&again, "One more thing")
        _ = again.reduce(.composer(.reopen))
        XCTAssertEqual(again.drawing.pins.first?.comments.map(\.text), ["Too tight", "One more thing"])
        XCTAssertNil(again.drawing.pins.first?.resolved)
        XCTAssertEqual(again.undoSteps.map(\.name), [.comment], "the new comment reopened it")
    }

    func testTheFirstPinsPopoverSkipsResolvedPinsAndOpensNoneWhenEveryPinIsResolved() {
        var done = pin(1, 500, 300)
        done.resolved = .byPerson()
        let open = pin(2, 700, 400)
        var core = core(pins: [done, open], nextPin: 3)
        _ = core.reduce(.composer(.openFirst))
        XCTAssertEqual(core.composer?.pin, open.id)
        var allDone = self.core(pins: [done], nextPin: 2)
        _ = allDone.reduce(.composer(.openFirst))
        XCTAssertNil(allDone.composer)
    }

    func testAResolvedPinClustersOnlyWithResolvedPins() {
        var first = pin(1, 300, 300), second = pin(2, 300, 300)
        first.resolved = .byPerson()
        second.resolved = .byPerson()
        let core = core(pins: [first, second, pin(3, 300, 300)], nextPin: 4)
        XCTAssertEqual(core.pinPlacement.clusters.map(\.label), ["1 · 2"])
        XCTAssertEqual(core.pinPlacement.clusters.map(\.resolved), [true])
        XCTAssertEqual(core.pinPlacement.drops.map(\.number), [3])
    }

    func testCopiedResolvedPinsPasteBackResolvedAndLeaveTheirWordsOffTheClipboardText() throws {
        var done = pin(1, 500, 300)
        done.resolved = .byPerson()
        let open = Pin(id: UUID(), number: 2, place: .point(CGPoint(x: 200, y: 300)), comments: [Pin.Comment(text: "Wrong date")])
        var core = core(pins: [done, open], nextPin: 3)
        _ = core.reduce(.setTool(.select))
        core.selection = [done.id, open.id]
        let copied = core.key(.character("c"), .command).compactMap { effect -> (CopiedItems, String?)? in
            guard case .copyItems(let items, let text) = effect else { return nil }
            return (items, text)
        }.first
        let (items, text) = try XCTUnwrap(copied)
        XCTAssertEqual(items.pins.map(\.resolved), [done.resolved, nil])
        XCTAssertEqual(text, "Pin 2: Wrong date.")
        core.paste(.items(items))
        XCTAssertEqual(core.drawing.pins.suffix(2).map(\.isResolved), [true, false])
    }
}
