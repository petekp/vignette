import XCTest

final class EditorCorePinsTests: XCTestCase {
    typealias Core = EditorCore
    private static let image = PixelSize(width: 1000, height: 600)

    private func core(_ marks: [Mark] = [], pins: [Pin] = [], nextPin: Int = 1, zoom: CGFloat = 1) -> Core {
        var core = Core()
        _ = core.reduce(.open(Drawing(key: "/tmp/shot.png", pixels: Self.image, pointScale: 1, marks: marks, pins: pins, nextPin: nextPin),
                              style: .standard, metrics: .standard, markStyle: .standard))
        _ = core.reduce(.viewChanged(visible: Self.image.bounds))
        _ = core.reduce(.zoomChanged(zoom))
        _ = core.reduce(.setTool(.comment))
        return core
    }

    private func pin(_ number: Int, _ x: CGFloat, _ y: CGFloat, _ text: String = "Too tight") -> Pin {
        Pin(id: UUID(), number: number, place: .point(CGPoint(x: x, y: y)), comments: [Pin.Comment(text: text)])
    }

    private func write(_ core: inout Core, _ words: String) {
        _ = core.reduce(.composer(.changed(words)))
    }

    func testTheCommentToolsPointerOverThePictureIsItsOwnAndOverAPinIsTheArrow() {
        var core = core(pins: [pin(1, 500, 300)])
        core.move(200, 200)
        XCTAssertEqual(core.cursor, .comment(MarkStyle.standard.personColor))
        core.move(512, 288)
        XCTAssertEqual(core.cursor, .arrow)
        _ = core.reduce(.setTool(.rectangle))
        core.move(200, 200)
        XCTAssertEqual(core.cursor, .crosshair)
    }

    func testAClickPlacesAPinWhoseFirstCommentGivesItTheNextNumber() throws {
        var core = core(nextPin: 4)
        let placed = core.click(500, 300)
        let id = try XCTUnwrap(core.drawing.pins.first?.id)
        XCTAssertTrue(placed.contains(.composer(Core.Composer(pin: id, editing: nil, draft: ""))))
        XCTAssertEqual(core.drawing.pins.first?.number, 0)
        XCTAssertEqual(core.drawingForHost.pins, [])
        write(&core, "Too tight")
        let posted = core.reduce(.composer(.post))
        XCTAssertEqual(core.drawing.pins.map(\.number), [4])
        XCTAssertEqual(core.drawing.nextPin, 5)
        XCTAssertEqual(core.drawing.pins.first?.comments.map(\.text), ["Too tight"])
        XCTAssertTrue(posted.contains(.announce("Pin 4 added")))
        XCTAssertEqual(core.composer, Core.Composer(pin: id, editing: nil, draft: ""))
        XCTAssertEqual(core.undoTitle, "Undo Comment")
    }

    func testAClickOnAPinOpensItsPopoverWithAnyToolAndAShiftClickOnlySelects() {
        let first = pin(1, 500, 300)
        var core = core(pins: [first], nextPin: 2)
        core.click(512, 288)
        XCTAssertEqual(core.composer, Core.Composer(pin: first.id, editing: nil, draft: ""))
        XCTAssertEqual(core.selection, [first.id])
        write(&core, "Draft")
        _ = core.press(512, 288, count: 2)
        _ = core.release(512, 288)
        XCTAssertEqual(core.composer?.draft, "Draft", "a double-click's second press leaves the popover open")
        core.click(512, 288)
        XCTAssertNil(core.composer, "a click on the open pin closes its popover")
        core.click(512, 288, .shift)
        XCTAssertNil(core.composer)
        _ = core.reduce(.setTool(.select))
        core.click(512, 288)
        XCTAssertEqual(core.composer, Core.Composer(pin: first.id, editing: nil, draft: ""))
        XCTAssertEqual(core.selection, [first.id])
        core.click(512, 288)
        XCTAssertNil(core.composer)
        core.click(100, 100)
        core.click(512, 288, .shift)
        XCTAssertNil(core.composer)
        XCTAssertEqual(core.selection, [first.id])
    }

    func testACommentToolPressOnOneOfSeveralSelectedPinsKeepsThemSelectedForADrag() {
        let first = pin(1, 500, 300), second = pin(2, 200, 300)
        var core = core(pins: [first, second], nextPin: 3)
        core.click(512, 288, .shift)
        core.click(212, 288, .shift)
        XCTAssertEqual(core.selection, [first.id, second.id])
        _ = core.press(512, 288)
        XCTAssertEqual(core.selection, [first.id, second.id])
    }

    func testReturnInAnEmptyComposerClosesItAndKeepsThePinSelected() throws {
        var core = core()
        core.click(500, 300)
        write(&core, "One")
        _ = core.reduce(.composer(.post))
        write(&core, "Two")
        _ = core.reduce(.composer(.post))
        let closed = core.reduce(.composer(.post))
        let pin = try XCTUnwrap(core.drawing.pins.first)
        XCTAssertEqual(pin.comments.map(\.text), ["One", "Two"])
        XCTAssertNil(core.composer)
        XCTAssertTrue(closed.contains(.composer(nil)))
        XCTAssertEqual(core.selection, [pin.id])
    }

    func testANewPinClosedWithNothingPostedGoesAndTakesNoNumber() {
        var core = core()
        core.click(500, 300)
        write(&core, "   ")
        _ = core.reduce(.composer(.close))
        XCTAssertEqual(core.drawing.pins, [])
        XCTAssertEqual(core.drawing.nextPin, 1)
        XCTAssertEqual(core.selection, [])
        XCTAssertEqual(core.undoTitle, "Undo")
        core.click(500, 300)
        core.click(100, 100)
        XCTAssertEqual(core.drawing.pins.count, 1, "a press elsewhere closes the first new pin and places another")
    }

    func testEscPostsWhatWasTyped() {
        var core = core()
        core.click(500, 300)
        write(&core, "Kept")
        _ = core.reduce(.composer(.close))
        XCTAssertEqual(core.drawing.pins.map { $0.comments.map(\.text) }, [["Kept"]])
        XCTAssertNil(core.composer)
    }

    func testParkingPostsTheDraftAndClosesThePopover() throws {
        var core = core()
        core.click(500, 300)
        write(&core, "Too tight")
        let parked = core.reduce(.park)
        XCTAssertTrue(parked.contains(.composer(nil)))
        XCTAssertNil(core.composer)
        let handed = parked.compactMap { effect -> Drawing? in
            if case .handOver(let drawing) = effect { return drawing } else { return nil }
        }
        XCTAssertEqual(try XCTUnwrap(handed.first).pins.first?.comments.map(\.text), ["Too tight"])
    }

    func testCmdReturnPostsThenFinishesWithThePin() {
        var core = core()
        core.click(500, 300)
        write(&core, "Ship it")
        let finished = core.reduce(.composer(.finish))
        let done = finished.compactMap { effect -> Drawing? in
            if case .done(let drawing) = effect { return drawing }
            return nil
        }
        XCTAssertEqual(done.first?.pins.map(\.number), [1])
        XCTAssertEqual(done.first?.pins.first?.comments.map(\.text), ["Ship it"])
    }

    func testEditingACommentReplacesItAndEmptyingTheLastOneDeletesThePin() throws {
        var core = core(pins: [pin(1, 500, 300, "First")], nextPin: 2)
        let id = try XCTUnwrap(core.drawing.pins.first?.id)
        core.click(510, 290, count: 2)
        XCTAssertEqual(core.composer?.pin, id)
        _ = core.reduce(.composer(.edit(0)))
        XCTAssertEqual(core.composer, Core.Composer(pin: id, editing: 0, draft: "First"))
        write(&core, "Changed")
        _ = core.reduce(.composer(.post))
        XCTAssertEqual(core.drawing.pins.first?.comments.map(\.text), ["Changed"])
        XCTAssertEqual(core.undoTitle, "Undo Typing")
        _ = core.reduce(.composer(.edit(0)))
        write(&core, "")
        _ = core.reduce(.composer(.post))
        XCTAssertEqual(core.drawing.pins, [])
        XCTAssertNil(core.composer)
        XCTAssertEqual(core.drawing.nextPin, 2)
        core.key(.character("z"), .command)
        XCTAssertEqual(core.drawing.pins.first?.comments.map(\.text), ["Changed"])
    }

    func testDeleteTakesAnAgentsCommentAsOneStepAndTheOnlyCommentLeftTakesThePinWithIt() throws {
        let answered = Pin(id: UUID(), number: 1, place: .point(CGPoint(x: 500, y: 300)),
                           comments: [Pin.Comment(text: "Too tight"), Pin.Comment(text: "Fixed", agent: true, agentName: "claude")])
        var core = core(pins: [answered], nextPin: 2)
        _ = core.reduce(.composer(.open(answered.id)))
        _ = core.reduce(.composer(.delete(1)))
        XCTAssertEqual(core.drawing.pins.first?.comments.map(\.text), ["Too tight"])
        XCTAssertEqual(core.composer, Core.Composer(pin: answered.id, editing: nil, draft: ""))
        XCTAssertEqual(core.undoTitle, "Undo Delete")
        _ = core.reduce(.composer(.delete(0)))
        XCTAssertEqual(core.drawing.pins, [])
        XCTAssertNil(core.composer)
        XCTAssertEqual(core.drawing.nextPin, 2)
        core.key(.character("z"), .command)
        XCTAssertEqual(core.drawing.pins.first?.comments.map(\.text), ["Too tight"])
        core.key(.character("z"), .command)
        XCTAssertEqual(core.drawing.pins, [answered])
    }

    func testTheFirstPinsPopoverOpensWithoutTheKeysOrTheSelectionAndEscClosesItBeforeTheEditor() {
        let mark = Mark(geometry: .rectangle(CGRect(x: 100, y: 100, width: 200, height: 100)))
        let second = pin(2, 700, 400), first = pin(1, 500, 300)
        var core = core([mark], pins: [second, first], nextPin: 3)
        _ = core.reduce(.setTool(.select))
        core.selection = [mark.id]
        _ = core.reduce(.composer(.openFirst))
        XCTAssertEqual(core.composer, Core.Composer(pin: first.id, draft: "", takesKeys: false))
        XCTAssertEqual(core.selection, [mark.id])
        XCTAssertFalse(core.key(.escape).contains(.close))
        XCTAssertNil(core.composer)
        XCTAssertEqual(core.drawing.pins, [second, first])
        XCTAssertEqual(core.undoTitle, "Undo")
        XCTAssertTrue(core.key(.escape).contains(.close))
    }

    func testAfterEmptyingOneCommentAClickOnALaterOneEditsThatOneAndAnUnchangedOneReturnsToANewComment() throws {
        let three = Pin(id: UUID(), number: 1, place: .point(CGPoint(x: 500, y: 300)),
                        comments: ["A", "B", "C"].map { Pin.Comment(text: $0) })
        var core = core(pins: [three], nextPin: 2)
        _ = core.reduce(.composer(.open(three.id)))
        _ = core.reduce(.composer(.edit(0)))
        write(&core, "")
        _ = core.reduce(.composer(.edit(2)))
        XCTAssertEqual(core.drawing.pins.first?.comments.map(\.text), ["B", "C"])
        XCTAssertEqual(core.composer, Core.Composer(pin: three.id, editing: 1, draft: "C"))
        _ = core.reduce(.composer(.post))
        XCTAssertEqual(core.composer, Core.Composer(pin: three.id, editing: nil, draft: ""))
    }

    private func copied(_ effects: [Core.Effect]) throws -> (items: CopiedItems, text: String?) {
        let found = effects.lazy.compactMap { effect -> (items: CopiedItems, text: String?)? in
            guard case .copyItems(let items, let text) = effect else { return nil }
            return (items, text)
        }.first
        return try XCTUnwrap(found, "Copy emitted no copied items")
    }

    func testCutTakesTheSelectedMarksAndPinsAndPasteBringsThePinsBackWithNewNumbers() throws {
        let box = Mark(geometry: .rectangle(CGRect(x: 100, y: 100, width: 100, height: 100)))
        let original = pin(1, 500, 300)
        var core = core([box], pins: [original], nextPin: 2)
        core.key(.character("a"), .command)
        let cut = try copied(core.key(.character("x"), .command))
        XCTAssertEqual(core.drawing.marks, [])
        XCTAssertEqual(core.drawing.pins, [])
        XCTAssertEqual(cut.items.pins, [original])
        XCTAssertEqual(cut.text, "Pin 1: Too tight.")
        _ = core.reduce(.paste(.items(cut.items)))
        let pasted = try XCTUnwrap(core.drawing.pins.first)
        XCTAssertEqual(core.drawing.marks.map(\.geometry), [box.geometry])
        XCTAssertEqual(pasted.place, original.place)
        XCTAssertEqual(pasted.comments, original.comments)
        XCTAssertEqual(pasted.number, 2)
        XCTAssertNotEqual(pasted.id, original.id)
        XCTAssertEqual(core.drawing.nextPin, 3)
        XCTAssertEqual(core.selection, Set(core.drawing.marks.map(\.id) + [pasted.id]))
        core.key(.character("z"), .command)
        XCTAssertEqual(core.drawing.pins, [])
        XCTAssertEqual(core.drawing.nextPin, 3, "an undone paste leaves its numbers unused")
    }

    func testDuplicateAndPasteOfPinsLandTenPointsOffInNumberOrderWithTheNextNumbers() throws {
        var core = core(pins: [pin(4, 500, 300, "Second"), pin(2, 100, 100, "First")], nextPin: 5)
        core.key(.character("a"), .command)
        let copy = try copied(core.key(.character("c"), .command))
        XCTAssertEqual(copy.text, "Pin 2: First. Pin 4: Second.")
        core.key(.character("d"), .command)
        XCTAssertEqual(core.undoTitle, "Undo Duplicate")
        let duplicated = core.drawing.pins.dropFirst(2)
        XCTAssertEqual(duplicated.map(\.number), [5, 6])
        XCTAssertEqual(duplicated.map(\.tip), [CGPoint(x: 110, y: 110), CGPoint(x: 510, y: 310)])
        _ = core.reduce(.paste(.items(copy.items)))
        XCTAssertEqual(core.drawing.pins.dropFirst(4).map(\.tip), [CGPoint(x: 120, y: 120), CGPoint(x: 520, y: 320)])
        XCTAssertEqual(core.drawing.pins.dropFirst(4).map(\.number), [7, 8])
        XCTAssertEqual(Set(core.drawing.pins.map(\.id)).count, 6)
    }

    func testAPressOnATeardropBesideAMarkSelectsThePinAndOneOnTheMarkSelectsTheMark() throws {
        let box = Mark(geometry: .rectangle(CGRect(x: 520, y: 260, width: 200, height: 200)))
        var core = core([box], pins: [pin(1, 500, 300)], nextPin: 2)
        let id = try XCTUnwrap(core.drawing.pins.first?.id)
        core.click(510, 286)
        XCTAssertEqual(core.selection, [id])
        XCTAssertEqual(core.composer?.pin, id)
        core.click(620, 260)
        XCTAssertEqual(core.selection, [box.id])
        XCTAssertNil(core.composer)
        XCTAssertEqual(core.drawing.pins.count, 1)
        core.click(800, 500)
        XCTAssertEqual(core.drawing.pins.count, 2, "the Comment tool places a pin away from marks and pins")
    }

    func testPinsClusterWhenTheirBodiesOverlapAndZoomingInPullsThemApart() {
        let near = [pin(1, 500, 300), pin(2, 506, 300), pin(3, 300, 300), pin(4, 300, 300)]
        var core = core(pins: near, nextPin: 5)
        XCTAssertEqual(core.pinPlacement.clusters.map(\.label).sorted(), ["1 · 2", "3 · 4"])
        _ = core.reduce(.zoomChanged(2))
        XCTAssertEqual(core.pinPlacement.clusters.map(\.label).sorted(), ["1 · 2", "3 · 4"])
        _ = core.reduce(.zoomChanged(3))
        XCTAssertEqual(core.pinPlacement.clusters.map(\.label), ["3 · 4"])
        _ = core.reduce(.zoomChanged(50))
        XCTAssertEqual(core.pinPlacement.clusters.map(\.label), ["3 · 4"], "pins on one point stay a cluster")
        XCTAssertEqual(core.pinPlacement.drops.map(\.number), [1, 2])
    }

    func testAClusterPastThreeCountsTheRestAndAClickListsItsPins() throws {
        var core = core(pins: (1...5).map { pin($0, 400, 300) }, nextPin: 6)
        let cluster = try XCTUnwrap(core.pinPlacement.clusters.first)
        XCTAssertEqual(cluster.label, "1 · 2 · 3 +2")
        let shown = core.click(cluster.frame.midX, cluster.frame.midY)
        XCTAssertTrue(shown.contains(.showCluster(cluster.pins, at: cluster.frame)))
        XCTAssertEqual(core.drawing.pins.count, 5)
        _ = core.reduce(.composer(.open(cluster.pins[3])))
        XCTAssertEqual(core.composer?.pin, cluster.pins[3])
        XCTAssertEqual(core.pinPlacement.clusters.map(\.label), ["1 · 2 · 3 +1"], "the open pin leaves its cluster")
    }

    func testShiftReturnPlacesAPinInTheMiddleOfTheViewAndOpensASelectedOne() throws {
        var core = core()
        _ = core.reduce(.viewChanged(visible: CGRect(x: 200, y: 100, width: 400, height: 200)))
        core.key(.returnKey, .shift)
        XCTAssertEqual(core.drawing.pins.first?.tip, CGPoint(x: 400, y: 200))
        write(&core, "Middle")
        _ = core.reduce(.composer(.close))
        core.key(.returnKey, .option)
        XCTAssertEqual(core.composer?.pin, try XCTUnwrap(core.drawing.pins.first?.id))
    }

    func testAHandleResizesTheOpenPinsAreaWithItsPopoverOpenAndANewPinStillGoesWhenClosedEmpty() throws {
        var core = core()
        core.drag(from: (300, 200), to: (100, 100))
        let id = try XCTUnwrap(core.composer?.pin)
        XCTAssertEqual(core.drawing.pins.first?.place, .area(CGRect(x: 100, y: 100, width: 200, height: 100), tip: .topLeft))
        XCTAssertEqual(core.activePins, [id])
        core.drag(from: (300, 200), to: (340, 230))
        XCTAssertEqual(core.composer?.pin, id)
        XCTAssertEqual(core.drawing.pins.first?.place, .area(CGRect(x: 100, y: 100, width: 240, height: 130), tip: .topLeft))
        _ = core.reduce(.composer(.close))
        XCTAssertEqual(core.drawing.pins, [])
        XCTAssertEqual(core.undoTitle, "Undo")

        core.drag(from: (300, 200), to: (100, 100))
        core.drag(from: (300, 200), to: (340, 230))
        write(&core, "Wider")
        _ = core.reduce(.composer(.close))
        XCTAssertEqual(core.drawing.pins.first?.place, .area(CGRect(x: 100, y: 100, width: 240, height: 130), tip: .topLeft))
        XCTAssertEqual(core.undoTitle, "Undo Comment")

        core.drag(from: (340, 230), to: (60, 60))
        XCTAssertEqual(core.drawing.pins.first?.place, .area(CGRect(x: 60, y: 60, width: 40, height: 40), tip: .bottomRight))
    }

    func testAnAgentsPinsJoiningWhileThePersonPlacesOrMovesAPinStayAndUndoApart() throws {
        let area = Pin.Place.area(CGRect(x: 100, y: 100, width: 200, height: 100), tip: .bottomRight)
        let mine = Pin(id: UUID(), number: 1, place: area, comments: [Pin.Comment(text: "This box")])
        var core = core(pins: [mine], nextPin: 2)
        core.click(700, 400)
        _ = core.reduce(.agentMarks([], pins: try AgentPin.parse(#"[{"x":0.8,"y":0.2,"text":"Here"},{"pin":1,"text":"Fixed"}]"#), from: "claude"))
        _ = core.reduce(.composer(.close))
        XCTAssertEqual(core.drawing.pins.map(\.number), [1, 2], "closing the person's empty new pin leaves the agent's")
        XCTAssertEqual(core.drawing.pins.first?.comments.map(\.text), ["This box", "Fixed"])

        core.press(310, 190)
        core.dragTo(360, 240)
        _ = core.reduce(.agentMarks([], pins: try AgentPin.parse(#"[{"pin":1,"text":"And here"}]"#), from: "claude"))
        XCTAssertEqual(core.drawingForHost.pins.first?.place, area, "the host gets the answer on the pin as it was before the drag")
        XCTAssertEqual(core.drawingForHost.pins.first?.comments.count, 3)
        core.release(360, 240)
        XCTAssertEqual(core.drawing.pins.first?.place, .area(CGRect(x: 150, y: 150, width: 200, height: 100), tip: .bottomRight))
        XCTAssertEqual(core.undoTitle, "Undo Move")
        core.key(.character("z"), .command)
        XCTAssertEqual(core.drawing.pins.first?.place, area)
        XCTAssertEqual(core.drawing.pins.first?.comments.count, 3, "undoing the move leaves the answer")
        XCTAssertEqual(core.undoTitle, "Undo claude's Marks")
        core.key(.character("z"), .command)
        XCTAssertEqual(core.drawing.pins.first?.comments.map(\.text), ["This box", "Fixed"])
        XCTAssertEqual(core.drawing.pins.first?.place, area)
    }

    func testADragWithTheCommentToolPlacesAnAreaPinThatMovesAndResizes() throws {
        var core = core()
        core.drag(from: (100, 100), to: (300, 200))
        let id = try XCTUnwrap(core.drawing.pins.first?.id)
        XCTAssertEqual(core.drawing.pins.first?.place, .area(CGRect(x: 100, y: 100, width: 200, height: 100), tip: .bottomRight))
        write(&core, "This box")
        _ = core.reduce(.composer(.close))
        core.drag(from: (310, 190), to: (360, 240))
        XCTAssertEqual(core.drawing.pins.first?.place, .area(CGRect(x: 150, y: 150, width: 200, height: 100), tip: .bottomRight))
        XCTAssertEqual(core.selection, [id])
        core.key(.right)
        XCTAssertEqual(core.drawing.pins.first?.tip, CGPoint(x: 351, y: 250))
        core.key(.delete)
        XCTAssertEqual(core.drawing.pins, [])
    }
}
