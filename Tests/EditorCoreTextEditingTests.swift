import XCTest

final class EditorCoreTextEditingTests: XCTestCase {
    typealias Core = EditorCore
    private static let everyToolButText: [Core.Tool] = [.select, .rectangle, .arrow]

    private func core(_ tool: Core.Tool, notes: [CGPoint] = [CGPoint(x: 200, y: 200)]) -> Core {
        let marks = notes.map { Mark(geometry: .text(Mark.Text(origin: $0, text: "note", wrap: nil, size: EditorMetrics.standard.newTextSize))) }
        var core = Core()
        _ = core.reduce(.open(Drawing(key: "/tmp/shot.png", pixels: PixelSize(width: 1000, height: 600), pointScale: 1, marks: marks),
                              style: .standard, metrics: .standard, markStyle: .standard))
        _ = core.reduce(.zoomChanged(1))
        _ = core.reduce(.setTool(tool))
        return core
    }

    private func box(_ core: Core, _ index: Int = 0) -> CGRect {
        let mark = core.drawing.marks[index]
        guard case .text(let text) = mark.geometry else {
            XCTFail("not a note")
            return .null
        }
        return core.geometry.layout(text, of: mark).box
    }

    private func origin(_ core: Core) -> CGPoint? {
        if case .text(let text)? = core.drawing.marks.first?.geometry { return text.origin }
        return nil
    }

    private func beginsTyping(_ effects: [Core.Effect]) -> Bool {
        effects.contains { if case .beginTyping = $0 { true } else { false } }
    }

    private func rim(_ core: Core) -> CGPoint {
        let box = box(core)
        let left = core.overlay.handles.first { $0.position == .left }
        return CGPoint(x: (left?.hitArea.maxX ?? box.minX) - 0.5, y: box.midY)
    }

    func testATextClickOnAnExistingTextEditsIt() {
        var core = core(.text)
        let id = core.drawing.marks[0].id
        let effects = core.click(210, 210)
        XCTAssertTrue(effects.contains(.beginTyping(id, .at(CGPoint(x: 210, y: 210)))))
        XCTAssertEqual(core.typing?.id, id)
        XCTAssertEqual(core.drawing.marks.count, 1)
        XCTAssertEqual(core.cursor, .iBeam)
    }

    func testADoubleClickOnATextTypesInItWithAllItsWordsSelectedWhateverTheTool() {
        for tool in Self.everyToolButText {
            var core = core(tool)
            let id = core.drawing.marks[0].id, middle = CGPoint(x: box(core).midX, y: box(core).midY)
            core.click(900, 500)
            XCTAssertTrue(core.selection.isEmpty, "\(tool)")
            core.click(middle.x, middle.y)
            XCTAssertNil(core.typing, "\(tool): the first click selects")
            XCTAssertTrue(core.click(middle.x, middle.y, count: 2).contains(.beginTyping(id, .selectAll)), "\(tool)")
            XCTAssertEqual(core.typing?.id, id, "\(tool)")
            XCTAssertEqual(core.tool, tool)
        }
        var text = core(.text)
        let middle = CGPoint(x: box(text).midX, y: box(text).midY)
        XCTAssertTrue(text.click(middle.x, middle.y).contains(.beginTyping(text.drawing.marks[0].id, .at(middle))))
        XCTAssertTrue(text.click(middle.x, middle.y, count: 2).contains(.beginTyping(text.drawing.marks[0].id, .selectAll)),
                      "with the Text tool too, the second click selects all the words")

        var twoNotes = core(.rectangle, notes: [CGPoint(x: 200, y: 200), CGPoint(x: 500, y: 300)])
        let first = box(twoNotes, 0), second = box(twoNotes, 1), other = twoNotes.drawing.marks[1].id
        twoNotes.click(first.midX, first.midY, count: 2)
        twoNotes.click(second.midX, second.midY)
        XCTAssertTrue(twoNotes.click(second.midX, second.midY, count: 2).contains(.beginTyping(other, .selectAll)),
                      "a double-click on another text while typing selects all its words")
    }

    func testADoubleClickOnASelectedTextsHandleTypesInItAndADragFromThereStillResizes() {
        for tool in Self.everyToolButText + [.text] {
            var core = core(tool)
            let id = core.drawing.marks[0].id, rim = rim(core)
            XCTAssertTrue(box(core).contains(rim), "\(tool): the handle reaches inside the tag")
            XCTAssertEqual(core.target(at: rim), .handle(id, .left), "\(tool)")
            core.click(rim.x, rim.y)
            XCTAssertNil(core.typing, "\(tool): one click on a handle does nothing")
            XCTAssertTrue(core.click(rim.x, rim.y, count: 2).contains(.beginTyping(id, .selectAll)), "\(tool)")
            XCTAssertEqual(core.typing?.id, id, "\(tool)")

            var resized = self.core(tool)
            let original = resized.drawing.marks[0]
            resized.press(rim.x, rim.y, count: 2)
            resized.dragTo(rim.x - 20, rim.y)
            resized.dragTo(rim.x - 40, rim.y)
            resized.release(rim.x - 40, rim.y)
            XCTAssertNil(resized.typing, "\(tool)")
            XCTAssertNotEqual(resized.drawing.marks[0], original, "\(tool): the drag resized the text")
        }
    }

    func testAClickOnTheLoneSelectedTextTypesAtTheClickWhateverTheToolAndADragMovesIt() {
        for tool in Self.everyToolButText {
            var core = core(tool)
            let id = core.drawing.marks[0].id, start = origin(core), middle = CGPoint(x: box(core).midX, y: box(core).midY)
            XCTAssertEqual(core.selection, [id])
            XCTAssertTrue(core.click(middle.x, middle.y).contains(.beginTyping(id, .at(middle))), "\(tool)")
            XCTAssertEqual(core.typing?.id, id, "\(tool)")

            var moved = self.core(tool)
            moved.drag(from: (middle.x, middle.y), to: (middle.x + 50, middle.y + 30))
            XCTAssertNil(moved.typing, "\(tool)")
            XCTAssertEqual(origin(moved)?.x ?? 0, (start?.x ?? 0) + 50, accuracy: 0.001, "\(tool)")
            XCTAssertEqual(origin(moved)?.y ?? 0, (start?.y ?? 0) + 30, accuracy: 0.001, "\(tool)")
        }
    }

    func testTheIBeamShowsWhereAClickTypesAndTheResizeCursorOnTheHandles() {
        for tool in Self.everyToolButText {
            var core = core(tool)
            let middle = CGPoint(x: box(core).midX, y: box(core).midY), rim = rim(core)
            core.move(middle.x, middle.y)
            XCTAssertEqual(core.cursor, .iBeam, "\(tool)")
            _ = core.reduce(.modifiersChanged(.shift))
            XCTAssertEqual(core.cursor, .arrow, "\(tool): Shift makes the click take the text out of the selection")
            _ = core.reduce(.modifiersChanged(.control))
            XCTAssertEqual(core.cursor, .arrow, "\(tool): a Control-click is a right-click")
            _ = core.reduce(.modifiersChanged([]))
            core.press(middle.x, middle.y)
            _ = core.reduce(.modifiersChanged(.shift))
            XCTAssertEqual(core.cursor, .iBeam, "\(tool): the release types whatever is held by then")
            core.key(.escape)
            _ = core.reduce(.modifiersChanged([]))
            core.move(rim.x, rim.y)
            XCTAssertEqual(core.cursor, .resize(.left), "\(tool)")
            core.click(900, 500)
            core.move(middle.x, middle.y)
            XCTAssertEqual(core.cursor, .arrow, "\(tool): a click on a text that is not selected selects it")
            core.press(middle.x, middle.y)
            XCTAssertEqual(core.cursor, .arrow, "\(tool): held, the press that selects the text does not type on release")
            core.release(middle.x, middle.y)
            XCTAssertNil(core.typing)
        }
        var typing = core(.rectangle, notes: [CGPoint(x: 200, y: 200), CGPoint(x: 500, y: 300)])
        let first = box(typing, 0), second = box(typing, 1)
        typing.click(first.midX, first.midY, count: 2)
        typing.move(second.midX, second.midY)
        XCTAssertEqual(typing.cursor, .iBeam, "a click on another text while typing types in it")
        typing.click(second.midX, second.midY)
        XCTAssertEqual(typing.typing?.id, typing.drawing.marks[1].id)
    }

    func testAPressTheCursorSaysWillDrawNeverTypesAndDrawsWhenDragged() {
        for tool in [Core.Tool.rectangle, .arrow] {
            let around = box(core(tool)).insetBy(dx: -24, dy: -24)
            var drawn = 0, typed = 0
            for x in stride(from: around.minX, through: around.maxX, by: 3) {
                for y in stride(from: around.minY, through: around.maxY, by: 3) {
                    var core = core(tool)
                    core.move(x, y)
                    let cursor = core.cursor
                    let types = beginsTyping(core.click(x, y) + core.click(x, y, count: 2))
                    if types { typed += 1 }
                    guard cursor == .crosshair else { continue }
                    XCTAssertFalse(types, "\(tool) at \(x), \(y)")
                    var drag = self.core(tool)
                    drag.drag(from: (x, y), to: (x + 60, y + 60))
                    XCTAssertEqual(drag.drawing.marks.count, 2, "\(tool) at \(x), \(y)")
                    XCTAssertNil(drag.typing)
                    drawn += 1
                }
            }
            XCTAssertGreaterThan(drawn, 0)
            XCTAssertGreaterThan(typed, 0)
        }
    }
}
