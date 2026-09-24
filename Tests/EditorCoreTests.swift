import XCTest

/// The behaviour `docs/editor.md` gives tools, selection, keys, typing, undo and the clipboard, run
/// against the editor's core with no view. At point scale 1 and zoom 1, px, pt and screen pt are one.
final class EditorCoreTests: XCTestCase {
    typealias Core = EditorCore
    private static let image = PixelSize(width: 1000, height: 600)

    private func core(_ marks: [Mark] = [], pixels: PixelSize = image, scale: CGFloat = 1, zoom: CGFloat = 1,
                      metrics: EditorMetrics = .standard, pick: @escaping Core.ColorPick = { _ in nil }) -> Core {
        var core = Core()
        _ = core.reduce(.open(Drawing(key: "/tmp/shot.png", pixels: pixels, pointScale: scale, marks: marks), style: .standard,
                              metrics: metrics, arrowhead: .standard, pickColor: pick))
        _ = core.reduce(.zoomChanged(zoom))
        return core
    }

    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, agent: Bool = false) -> Mark {
        Mark(geometry: .rectangle(CGRect(x: x, y: y, width: w, height: h)), agent: agent)
    }

    private func arrow(_ x: CGFloat, _ y: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> Mark {
        Mark(geometry: .arrow(Mark.Arrow(start: CGPoint(x: x, y: y), end: CGPoint(x: x2, y: y2))))
    }

    private func text(_ words: String, _ x: CGFloat, _ y: CGFloat) -> Mark {
        Mark(geometry: .text(Mark.Text(origin: CGPoint(x: x, y: y), text: words, wrap: nil, size: EditorMetrics.standard.newTextSize)))
    }

    private func frame(_ mark: Mark?) -> CGRect? {
        switch mark?.geometry {
        case .rectangle(let frame)?, .ellipse(let frame)?: return frame
        default: return nil
        }
    }

    private func textOf(_ mark: Mark?) -> Mark.Text? {
        if case .text(let text)? = mark?.geometry { return text }
        return nil
    }

    private func arrowOf(_ mark: Mark?) -> Mark.Arrow? {
        if case .arrow(let arrow)? = mark?.geometry { return arrow }
        return nil
    }

    private func copied(_ effects: [Core.Effect]) -> CopiedMarks? {
        for case .copyMarks(let marks, _) in effects { return marks }
        return nil
    }

    // MARK: Tools

    func testAFreshScreenshotOpensOnRectangleAndADragDrawsFromThePressToTheRelease() {
        var core = Core()
        let opened = core.reduce(.open(Drawing(key: "/tmp/shot.png", pixels: Self.image, pointScale: 1, marks: []), style: .standard, metrics: .standard,
                                       arrowhead: .standard, pickColor: { _ in nil }))
        XCTAssertEqual(core.tool, .rectangle)
        XCTAssertTrue(opened.contains(.tool(.rectangle)))
        core.drag(from: (100, 100), to: (300, 250))
        XCTAssertEqual(core.drawing.marks.count, 1)
        XCTAssertEqual(frame(core.drawing.marks.first), CGRect(x: 100, y: 100, width: 200, height: 150))
        XCTAssertEqual(core.selection, [core.drawing.marks[0].id])
        XCTAssertEqual(core.undoSteps.count, 1)
    }

    func testShiftDrawsASquareInTheDragsQuadrantAndOptionCentresItOnThePress() {
        var core = core()
        core.drag(from: (500, 300), to: (400, 260), .shift)
        XCTAssertEqual(frame(core.drawing.marks.last), CGRect(x: 400, y: 200, width: 100, height: 100))
        core.drag(from: (700, 300), to: (760, 340), .option)
        XCTAssertEqual(frame(core.drawing.marks.last), CGRect(x: 640, y: 260, width: 120, height: 80))
        core.drag(from: (200, 450), to: (230, 510), [.shift, .option])
        XCTAssertEqual(frame(core.drawing.marks.last), CGRect(x: 140, y: 390, width: 120, height: 120))
        // A modifier pressed mid-drag reshapes the rectangle at once, with no move.
        core.press(850, 100)
        core.dragTo(900, 120)
        _ = core.reduce(.modifiersChanged(.shift))
        XCTAssertEqual(frame(core.drawing.marks.last), CGRect(x: 850, y: 100, width: 50, height: 50))
    }

    func testAClickOnEmptySpaceWithRectangleOrArrowMakesNothingAndClearsTheSelection() {
        for tool in [Core.Tool.rectangle, .arrow] {
            var core = core([rect(100, 100, 50, 50)])
            XCTAssertEqual(core.selection.count, 1)
            _ = core.reduce(.setTool(tool))
            core.click(500, 400)
            XCTAssertEqual(core.drawing.marks.count, 1, "\(tool)")
            XCTAssertEqual(core.selection, [], "\(tool)")
            XCTAssertEqual(core.undoSteps.count, 0, "\(tool)")
        }
    }

    func testADragOfThreeScreenPointsMakesNothing() {
        var core = core(zoom: 2)
        core.drag(from: (100, 100), to: (101.5, 100))
        XCTAssertTrue(core.drawing.marks.isEmpty)
        // Past the drag distance, but one side is still under 4 screen pt at release.
        core.drag(from: (100, 100), to: (150, 101.5))
        XCTAssertTrue(core.drawing.marks.isEmpty)
        XCTAssertEqual(core.undoSteps.count, 0)
    }

    func testTheDragDistanceTheHostPassesDecidesWhenAPressDraws() {
        var standard = core()
        standard.drag(from: (100, 100), to: (112, 112))
        XCTAssertEqual(standard.drawing.marks.count, 1)
        var metrics = EditorMetrics.standard
        metrics.dragDistance = 20
        var tuned = core(metrics: metrics)
        // 17 pt: past the standard 4, short of 20.
        tuned.drag(from: (100, 100), to: (112, 112))
        XCTAssertTrue(tuned.drawing.marks.isEmpty)
        tuned.drag(from: (100, 100), to: (130, 130))
        XCTAssertEqual(tuned.drawing.marks.count, 1)
    }

    func testARectangleDraggedPastTheImageStopsAtItsEdge() {
        var core = core()
        core.drag(from: (900, 500), to: (1200, 800))
        XCTAssertEqual(frame(core.drawing.marks.first), CGRect(x: 900, y: 500, width: 100, height: 100))
    }

    func testAfterARectangleTheToolIsStillRectangleAndTheNewRectanglesCornersResizeIt() {
        var core = core()
        core.drag(from: (100, 100), to: (300, 250))
        XCTAssertEqual(core.tool, .rectangle)
        let corners = core.overlay.handles.filter { $0.position.isCorner }
        XCTAssertEqual(corners.count, 4)
        XCTAssertTrue(corners.allSatisfy { $0.square != nil })
        XCTAssertEqual(core.target(at: CGPoint(x: 300, y: 250)), .handle(core.drawing.marks[0].id, .bottomRight))
        core.drag(from: (300, 250), to: (350, 300))
        XCTAssertEqual(core.drawing.marks.count, 1)
        XCTAssertEqual(frame(core.drawing.marks.first), CGRect(x: 100, y: 100, width: 250, height: 200))
        XCTAssertEqual(core.tool, .rectangle)
    }

    func testWithRectangleTheCursorAndHoverSayWhetherAPressSelectsOrDraws() {
        var core = core([rect(100, 100, 200, 200), rect(600, 100, 100, 100)])
        _ = core.reduce(.setTool(.rectangle))
        core.click(900, 500)
        let other = core.drawing.marks[0].id
        XCTAssertTrue(core.move(100, 150).contains(.cursor(.arrow)))
        XCTAssertEqual(core.overlay.hovered, other)
        XCTAssertTrue(core.move(200, 200).contains(.cursor(.crosshair)), "the empty inside of a rectangle draws")
        XCTAssertNil(core.overlay.hovered)
        core.move(100, 150)
        XCTAssertTrue(core.move(500, 500).contains(.cursor(.crosshair)))
    }

    func testWithRectangleAPressOnAnotherMarksStrokeSelectsItAndADragMovesIt() {
        var core = core([rect(100, 100, 200, 200), rect(600, 100, 100, 100)])
        _ = core.reduce(.setTool(.rectangle))
        let other = core.drawing.marks[0].id
        core.press(100, 150)
        XCTAssertEqual(core.selection, [other])
        core.dragTo(150, 150)
        core.release(150, 150)
        XCTAssertEqual(core.drawing.marks.count, 2)
        XCTAssertEqual(frame(core.mark(other)), CGRect(x: 150, y: 100, width: 200, height: 200))
        XCTAssertEqual(core.tool, .rectangle)
    }

    func testAnArrowDragPutsTheHeadAtTheReleasePointAndShiftSnapsItTo15DegreeSteps() throws {
        var core = core()
        _ = core.reduce(.setTool(.arrow))
        core.drag(from: (100, 100), to: (300, 180))
        XCTAssertEqual(arrowOf(core.drawing.marks.last)?.start, CGPoint(x: 100, y: 100))
        XCTAssertEqual(arrowOf(core.drawing.marks.last)?.end, CGPoint(x: 300, y: 180))
        core.drag(from: (100, 300), to: (300, 340), .shift)
        let snapped = try XCTUnwrap(arrowOf(core.drawing.marks.last))
        XCTAssertEqual(atan2(snapped.end.y - 300, snapped.end.x - 100) * 180 / .pi, 15, accuracy: 1e-9)
        XCTAssertEqual(hypot(snapped.end.x - 100, snapped.end.y - 300), hypot(200, 40), accuracy: 1e-9)
        XCTAssertEqual(core.tool, .arrow)
    }

    func testAnArrowReleasedFiveScreenPointsFromItsStartIsDiscarded() {
        var core = core(zoom: 2)
        _ = core.reduce(.setTool(.arrow))
        core.drag(from: (100, 100), to: (102.5, 100))
        XCTAssertTrue(core.drawing.marks.isEmpty)
        XCTAssertEqual(core.undoSteps.count, 0)
    }

    func testATextClickPutsTheFirstLinesLeftEndAndVerticalCentreAtTheClickAndTypingStarts() throws {
        var core = core()
        _ = core.reduce(.setTool(.text))
        let effects = core.click(200, 300)
        let mark = try XCTUnwrap(core.drawing.marks.first)
        XCTAssertTrue(effects.contains(.beginTyping(mark.id, .end)))
        XCTAssertEqual(core.typing?.id, mark.id)
        let text = try XCTUnwrap(textOf(mark))
        let lineHeight = EditorMetrics.standard.newTextSize * TextStyle.standard.lineHeight
        XCTAssertEqual(text.origin.x, 200)
        XCTAssertEqual(text.origin.y + lineHeight / 2, 300, accuracy: 1e-9)
    }

    func testTypingPastTheRightEdgeWrapsAndTypingPastTheBottomMovesTheTextUp() throws {
        var core = core()
        _ = core.reduce(.setTool(.text))
        core.click(500, 300)
        _ = core.reduce(.typingChanged(String(repeating: "wrap these words ", count: 20)))
        let wrapped = try XCTUnwrap(textOf(core.drawing.marks.first))
        let layout = core.geometry.layout(wrapped)
        XCTAssertGreaterThan(layout.lines.count, 1)
        XCTAssertLessThanOrEqual(layout.box.maxX, 1000 * (1 - TextLayout.margin))
        XCTAssertEqual(wrapped.origin.x, 500)
        _ = core.reduce(.typingEnded)

        core.click(100, 560)
        let startY = try XCTUnwrap(textOf(core.drawing.marks.last)).origin.y
        _ = core.reduce(.typingChanged(Array(repeating: "line", count: 6).joined(separator: "\n")))
        let grown = try XCTUnwrap(textOf(core.drawing.marks.last))
        XCTAssertLessThan(grown.origin.y, startY)
        XCTAssertEqual(core.geometry.layout(grown).box.maxY, 600, accuracy: 1e-9)
        _ = core.reduce(.typingEnded)

        // Started with under 15% of the width to its right, a text moves left as it grows.
        core.click(900, 100)
        _ = core.reduce(.typingChanged("hello wonderful world"))
        let moved = try XCTUnwrap(textOf(core.drawing.marks.last))
        XCTAssertLessThan(moved.origin.x, 900)
        XCTAssertEqual(core.geometry.layout(moved).lines.count, 1)
    }

    func testATextToolDragSetsAWrapOfAtLeastOneEmAndOneBroughtBackIsAClick() throws {
        var core = core(scale: 2)
        _ = core.reduce(.setTool(.text))
        core.press(300, 300, time: 0)
        core.dragTo(400, 300, time: 0.3)
        let chosen = try XCTUnwrap(core.overlay.wrap)
        XCTAssertEqual(chosen.minX, 300)
        XCTAssertEqual(chosen.width, 100)
        core.dragTo(310, 300, time: 0.4)
        core.release(310, 300, time: 0.5)
        let clicked = try XCTUnwrap(textOf(core.drawing.marks.last))
        XCTAssertNil(clicked.wrap)
        _ = core.reduce(.typingChanged("first"))
        core.key(.escape)

        // 30 px is past the drag distance and under one em of a 24 pt text at point scale 2.
        core.press(500, 450, time: 1)
        core.dragTo(530, 450, time: 1.3)
        core.release(530, 450, time: 1.4)
        let narrow = try XCTUnwrap(textOf(core.drawing.marks.last))
        XCTAssertEqual(narrow.wrap, 48)
        XCTAssertEqual(narrow.origin.x, 500)
    }

    func testATextClickOnAnExistingTextEditsIt() {
        var core = core([text("note", 200, 200)])
        _ = core.reduce(.setTool(.text))
        let id = core.drawing.marks[0].id
        let effects = core.click(210, 210)
        XCTAssertTrue(effects.contains(.beginTyping(id, .at(CGPoint(x: 210, y: 210)))))
        XCTAssertEqual(core.typing?.id, id)
        XCTAssertEqual(core.drawing.marks.count, 1)
        XCTAssertEqual(core.cursor, .iBeam)
    }

    // MARK: Selection

    func testAPressOnARectanglesStrokeSelectsItAndAPressInItsEmptyMiddleBrushes() {
        var core = core([rect(100, 100, 200, 200)])
        core.click(900, 500)
        let id = core.drawing.marks[0].id
        core.click(100, 150)
        XCTAssertEqual(core.selection, [id])
        core.click(900, 500)
        core.press(200, 200)
        XCTAssertEqual(core.selection, [])
        core.dragTo(260, 260)
        XCTAssertEqual(core.gesture?.phase, .brushing)
        XCTAssertEqual(core.overlay.brush, CGRect(x: 200, y: 200, width: 60, height: 60))
        core.release(260, 260)
        XCTAssertEqual(frame(core.mark(id)), CGRect(x: 100, y: 100, width: 200, height: 200))
    }

    func testASelectedRectangleDragsFromAnywhereInsideIt() {
        var core = core([rect(100, 100, 200, 200)])
        core.drag(from: (200, 200), to: (250, 230))
        XCTAssertEqual(frame(core.drawing.marks.first), CGRect(x: 150, y: 130, width: 200, height: 200))
        XCTAssertEqual(core.undoSteps.count, 1)
    }

    func testABrushWhollyInsideAHollowRectangleLeavesTheRectangleUnselected() {
        var core = core([rect(100, 100, 200, 200), text("inside", 150, 250)])
        core.click(900, 500)
        core.drag(from: (130, 130), to: (200, 200))
        XCTAssertEqual(core.selection, [])
        core.drag(from: (130, 130), to: (200, 262))
        XCTAssertEqual(core.selection, [core.drawing.marks[1].id], "a brush inside a text box selects the text")
        core.drag(from: (50, 130), to: (200, 200))
        XCTAssertEqual(core.selection, [core.drawing.marks[0].id], "a brush across the outline selects the rectangle")
    }

    func testShiftPressAddsAMarkAndShiftClickOnASelectedMarkRemovesIt() {
        var core = core([rect(100, 100, 100, 100), rect(400, 100, 100, 100)])
        let (a, b) = (core.drawing.marks[0].id, core.drawing.marks[1].id)
        XCTAssertEqual(core.selection, [b])
        core.press(100, 150, .shift)
        XCTAssertEqual(core.selection, [a, b], "added on the press")
        core.release(100, 150, .shift)
        core.press(400, 150, .shift)
        XCTAssertEqual(core.selection, [a, b], "removed on the release, not the press")
        core.release(400, 150, .shift)
        XCTAssertEqual(core.selection, [a])
        XCTAssertEqual(core.undoSteps.count, 0)
    }

    func testCmdASelectsEveryMark() {
        var core = core([rect(100, 100, 100, 100), arrow(300, 300, 400, 400), text("hi", 600, 100)])
        core.key(.character("a"), .command)
        XCTAssertEqual(core.selection, Set(core.drawing.marks.map(\.id)))
    }

    func testTabGoesThroughTheMarksInReadingOrder() {
        // Drawn out of order; A and B share a row, C is below them, D below C.
        let b = rect(500, 110, 50, 50), a = rect(100, 100, 50, 50), d = arrow(100, 400, 300, 450), c = text("c", 300, 250)
        var core = core([b, a, d, c])
        core.click(900, 550)
        var visited: [Mark.ID] = []
        for _ in 0..<5 {
            core.key(.tab)
            visited.append(contentsOf: core.selection)
        }
        XCTAssertEqual(visited, [a.id, b.id, c.id, d.id, a.id])
        core.key(.tab, .shift)
        XCTAssertEqual(core.selection, [d.id])
        XCTAssertEqual(core.undoSteps.count, 0)
    }

    func testATenByTenScreenPointRectangleShowsFourCornersEachDraggable() {
        let expected: [(Core.HandlePosition, CGPoint, CGRect)] = [
            (.topLeft, CGPoint(x: 95, y: 95), CGRect(x: 80, y: 80, width: 30, height: 30)),
            (.topRight, CGPoint(x: 115, y: 95), CGRect(x: 100, y: 80, width: 30, height: 30)),
            (.bottomLeft, CGPoint(x: 95, y: 115), CGRect(x: 80, y: 100, width: 30, height: 30)),
            (.bottomRight, CGPoint(x: 115, y: 115), CGRect(x: 100, y: 100, width: 30, height: 30)),
        ]
        for (position, grab, result) in expected {
            var core = core([rect(100, 100, 10, 10)])
            let corners = core.overlay.handles.filter { $0.position.isCorner }
            XCTAssertEqual(corners.count, 4)
            XCTAssertTrue(corners.allSatisfy { $0.square?.size == CGSize(width: 8, height: 8) })
            XCTAssertEqual(core.target(at: grab), .handle(core.drawing.marks[0].id, position), "\(position)")
            core.drag(from: (grab.x, grab.y), to: (grab.x + (position.xSide < 0 ? -20 : 20), grab.y + (position.ySide < 0 ? -20 : 20)))
            XCTAssertEqual(frame(core.drawing.marks.first), result, "\(position)")
        }
    }

    func testTheHandlesOfAMarkInTheImagesCornerCanAllBeTakenInsideTheImage() {
        let core = core([rect(0, 0, 10, 10)])
        let id = core.drawing.marks[0].id
        let handles = core.overlay.handles
        XCTAssertEqual(handles.count, 8)
        // The frame runs outside the stroke except where the image ends, where it stays inside by
        // half the outline's width, so all of the outline is seen.
        XCTAssertEqual(core.overlay.frame, CGRect(x: 1.75, y: 1.75, width: 11.75, height: 11.75))
        for handle in handles {
            XCTAssertTrue(CGRect(x: 0, y: 0, width: 1000, height: 600).contains(handle.hitArea), "\(handle.position)")
            let width: CGFloat = handle.position.isCorner ? 13.5 : handle.position.xSide != 0 ? 9 : 11.75
            XCTAssertEqual(handle.hitArea.width, width, "\(handle.position)")
        }
        for corner in handles where corner.position.isCorner {
            // The hit area's outer corner.
            let point = CGPoint(x: corner.position.xSide < 0 ? corner.hitArea.minX : corner.hitArea.maxX,
                                y: corner.position.ySide < 0 ? corner.hitArea.minY : corner.hitArea.maxY)
            XCTAssertEqual(core.target(at: point), .handle(id, corner.position))
        }
        XCTAssertEqual(handles.first { $0.position == .topLeft }?.square?.midX, 1.75)
        XCTAssertEqual(handles.first { $0.position == .topLeft }?.square?.midY, 1.75)
    }

    func testDraggingATextsRightEdgeSetsItsWrapWidthAndDraggingItsCornerScalesItsFont() throws {
        var core = core([text("hello world", 100, 100)])
        let id = core.drawing.marks[0].id
        let before = core.geometry.layout(try XCTUnwrap(textOf(core.mark(id))))
        let right = CGPoint(x: before.box.maxX, y: before.box.midY)
        XCTAssertEqual(core.target(at: right), .handle(id, .right))
        core.drag(from: (right.x, right.y), to: (right.x - before.box.width * 0.4, right.y + 30))
        let wrapped = try XCTUnwrap(textOf(core.mark(id)))
        XCTAssertEqual(try XCTUnwrap(wrapped.wrap), before.box.width * 0.6, accuracy: 1e-9)
        XCTAssertEqual(wrapped.origin, CGPoint(x: 100, y: 100), "the top stays")
        XCTAssertEqual(core.geometry.layout(wrapped).lines.count, 2)
        XCTAssertEqual(wrapped.size, EditorMetrics.standard.newTextSize)

        let box = core.geometry.layout(wrapped).box
        core.drag(from: (box.maxX, box.maxY), to: (box.maxX + box.width, box.maxY + box.height))
        let scaled = try XCTUnwrap(textOf(core.mark(id)))
        XCTAssertEqual(scaled.size, EditorMetrics.standard.newTextSize * 2, accuracy: 1e-9)
        XCTAssertEqual(scaled.origin, CGPoint(x: 100, y: 100))
        XCTAssertEqual(core.undoSteps.count, 2)
    }

    func testOnAThirtyPointArrowAPressOnTheMiddleDotBendsItAndOneOnAnEndDotMovesThatEnd() throws {
        var core = core([arrow(100, 300, 130, 300)])
        let id = core.drawing.marks[0].id
        let middle = try XCTUnwrap(core.overlay.dots.first { $0.kind == .middle })
        core.drag(from: (middle.center.x, middle.center.y), to: (115, 340))
        let bent = try XCTUnwrap(arrowOf(core.mark(id)))
        XCTAssertEqual(bent.bend, 40, accuracy: 1e-9)
        XCTAssertEqual(bent.start, CGPoint(x: 100, y: 300))
        XCTAssertEqual(bent.end, CGPoint(x: 130, y: 300))
        let end = try XCTUnwrap(core.overlay.dots.first { $0.kind == .end })
        core.drag(from: (end.center.x, end.center.y), to: (160, 250))
        let moved = try XCTUnwrap(arrowOf(core.mark(id)))
        XCTAssertEqual(moved.start, CGPoint(x: 100, y: 300))
        XCTAssertEqual(moved.end, CGPoint(x: 160, y: 250))
    }

    func testDotsShowOnlyWhileOneArrowIsSelected() {
        var core = core([arrow(100, 100, 300, 100), arrow(100, 300, 300, 300)])
        XCTAssertEqual(core.overlay.dots.count, 3)
        core.key(.character("a"), .command)
        XCTAssertTrue(core.overlay.dots.isEmpty)
        // A drag from an arrow's end moves the whole selection rather than that end.
        core.drag(from: (300, 300), to: (320, 320))
        XCTAssertEqual(arrowOf(core.drawing.marks[0])?.start, CGPoint(x: 120, y: 120))
        XCTAssertEqual(arrowOf(core.drawing.marks[1])?.start, CGPoint(x: 120, y: 320))
        XCTAssertEqual(arrowOf(core.drawing.marks[1])?.end, CGPoint(x: 320, y: 320))
    }

    func testOptionDragLeavesTheOriginalAndMovesACopy() {
        var core = core([rect(100, 100, 100, 100)])
        let original = core.drawing.marks[0]
        core.drag(from: (150, 150), to: (450, 250), .option)
        XCTAssertEqual(core.drawing.marks.count, 2)
        XCTAssertEqual(core.drawing.marks[0], original)
        XCTAssertEqual(frame(core.drawing.marks[1]), CGRect(x: 400, y: 200, width: 100, height: 100))
        XCTAssertEqual(core.selection, [core.drawing.marks[1].id])
        XCTAssertEqual(core.undoSteps.count, 1)
        // Releasing Option mid-drag takes the copy away and moves the original.
        core.press(100, 150, .option)
        core.dragTo(200, 150, .option)
        XCTAssertEqual(core.drawing.marks.count, 3)
        _ = core.reduce(.modifiersChanged([]))
        XCTAssertEqual(core.drawing.marks.count, 2)
        XCTAssertEqual(frame(core.drawing.marks[0]), CGRect(x: 200, y: 100, width: 100, height: 100))
    }

    func testSeveralMarksMovedAgainstAnEdgeStopTogether() {
        var core = core([rect(50, 50, 100, 100), rect(300, 100, 100, 100)])
        core.key(.character("a"), .command)
        core.drag(from: (50, 100), to: (-150, 100))
        XCTAssertEqual(frame(core.drawing.marks[0]), CGRect(x: 0, y: 50, width: 100, height: 100))
        XCTAssertEqual(frame(core.drawing.marks[1]), CGRect(x: 250, y: 100, width: 100, height: 100))
    }

    func testATextDraggedTowardTheRightEdgeStopsThereWithItsLines() throws {
        var core = core([text("hello wonderful world", 800, 300)])
        let id = core.drawing.marks[0].id
        let start = try XCTUnwrap(textOf(core.mark(id)))
        let lines = core.geometry.layout(start).lines.count
        let box = core.geometry.layout(start).box
        core.press(box.minX + 5, box.midY)
        var x = start.origin.x
        for step in 1...30 {
            core.dragTo(box.minX + 5 + CGFloat(step * 5), box.midY)
            let text = try XCTUnwrap(textOf(core.mark(id)))
            XCTAssertGreaterThanOrEqual(text.origin.x, x)
            XCTAssertEqual(core.geometry.layout(text).lines.count, lines)
            x = text.origin.x
        }
        core.release(box.minX + 155, box.midY)
        let moved = try XCTUnwrap(textOf(core.mark(id)))
        XCTAssertEqual(core.geometry.layout(moved).box.maxX, 1000 * (1 - TextLayout.margin), accuracy: 1e-6)
    }

    func testATextNudgedTowardTheRightEdgeStopsThereWithItsLines() throws {
        var core = core([text("a longer sentence that wraps into several lines near the edge", 800, 200)])
        let id = core.drawing.marks[0].id
        let lines = core.geometry.layout(try XCTUnwrap(textOf(core.mark(id)))).lines.count
        var x = try XCTUnwrap(textOf(core.mark(id))).origin.x
        for press in 0..<20 {
            core.key(.right, .shift, isRepeat: press > 0)
            let text = try XCTUnwrap(textOf(core.mark(id)))
            XCTAssertGreaterThanOrEqual(text.origin.x, x)
            XCTAssertEqual(core.geometry.layout(text).lines.count, lines)
            x = text.origin.x
        }
        let moved = try XCTUnwrap(textOf(core.mark(id)))
        XCTAssertEqual(core.geometry.layout(moved).box.maxX, 1000 * (1 - TextLayout.margin), accuracy: 1e-6)
    }

    // MARK: Keys

    func testEscDuringADragPutsTheMarkBackAndLeavesTheEditorOpenAndEscAtRestClosesIt() {
        var core = core([rect(100, 100, 100, 100)])
        let drawn = core.drawing
        core.press(150, 150)
        core.dragTo(300, 300)
        XCTAssertNotEqual(core.drawing, drawn)
        let cancelled = core.key(.escape)
        XCTAssertEqual(core.drawing, drawn)
        XCTAssertFalse(cancelled.contains(.close))
        XCTAssertTrue(core.isOpen)
        core.release(300, 300)
        XCTAssertEqual(core.drawing, drawn)
        XCTAssertTrue(core.key(.escape).contains(.close))
    }

    func testReturnFinishesAndWhileTypingEndsTheTypingOnlyAndCmdReturnWhileTypingFinishes() throws {
        var core = core()
        XCTAssertTrue(core.key(.returnKey).contains(.done(core.drawing)))
        _ = core.reduce(.setTool(.text))
        core.click(200, 200)
        _ = core.reduce(.typingChanged("note"))
        let ended = core.key(.returnKey)
        XCTAssertTrue(ended.contains(.endTyping))
        XCTAssertFalse(ended.contains { if case .done = $0 { return true } else { return false } })
        XCTAssertNil(core.typing)
        let id = try XCTUnwrap(core.drawing.marks.first?.id)
        XCTAssertEqual(core.selection, [id], "the text stays selected")

        core.key(.returnKey, .shift)
        XCTAssertEqual(core.typing?.id, id)
        let finished = core.key(.returnKey, .command)
        XCTAssertEqual(finished.first, .endTyping)
        XCTAssertTrue(finished.contains(.done(core.drawing)))
    }

    func testOptionReturnAndShiftReturnWhileTypingAreTheTextViewsNewLine() {
        var core = core()
        _ = core.reduce(.setTool(.text))
        core.click(200, 200)
        XCTAssertFalse(core.takesKey(.returnKey, .option))
        XCTAssertFalse(core.takesKey(.returnKey, .shift))
        XCTAssertTrue(core.takesKey(.returnKey, []))
        XCTAssertTrue(core.takesKey(.returnKey, .command))
        XCTAssertFalse(core.takesKey(.character("v"), []), "V is typed, not the Select tool")
        XCTAssertFalse(core.takesKey(.character("b"), .command), "Cmd+B is the text view's, and it does nothing there")
        XCTAssertFalse(core.takesKey(.left, .shift), "arrow keys move the caret")
        XCTAssertTrue(core.takesKey(.character("="), .command), "the host's zoom")
    }

    func testCommandKeysTheEditorHasNoUseForAreLeftForTheApp() {
        var core = core([rect(100, 100, 100, 100)])
        for character in ["z", "a", "c", "x", "v", "d", "=", "+", "-", "0"] as [Character] {
            XCTAssertTrue(core.takesKey(.character(character), .command), "Cmd+\(character)")
        }
        XCTAssertTrue(core.takesKey(.character("z"), [.command, .shift]))
        XCTAssertTrue(core.takesKey(.left, .command))
        XCTAssertTrue(core.takesKey(.returnKey, .command))
        XCTAssertTrue(core.takesKey(.character("w"), []), "a plain key is the editor's, even one it does nothing with")
        XCTAssertFalse(core.takesKey(.character("w"), .command), "Cmd+W is the app's")
        XCTAssertFalse(core.takesKey(.character("q"), .command))
        core.press(100, 150)
        core.dragTo(300, 300)
        XCTAssertTrue(core.takesKey(.character("w"), .command), "any key cancels a gesture")
        core.key(.character("w"), .command)
        XCTAssertNil(core.gesture)
    }

    func testArrowKeysNudgeAMarkSelectedOnReopenWithNoClickFirst() {
        var core = core([rect(100, 100, 100, 100)], scale: 2)
        core.key(.right)
        _ = core.reduce(.keyUp(.right))
        core.key(.down)
        XCTAssertEqual(frame(core.drawing.marks.first), CGRect(x: 102, y: 102, width: 100, height: 100))
    }

    func testRightShiftArrowAndLeftShiftArrowBothNudgeTenPoints() {
        // NSEvent flags: Shift, and the device bit for the right key (0x04) or the left one (0x02).
        for flags: UInt in [0x20004, 0x20002] {
            var core = core([rect(100, 100, 100, 100)], scale: 2)
            core.key(.right, Core.Modifiers(eventFlags: flags))
            XCTAssertEqual(frame(core.drawing.marks.first), CGRect(x: 120, y: 100, width: 100, height: 100), "flags \(flags)")
        }
    }

    func testHoldingAnArrowKeyIsOneUndoStepAndTwoKeysTogetherMoveDiagonally() {
        var core = core([rect(100, 100, 100, 100)])
        core.key(.right)
        for _ in 0..<5 { core.key(.right, isRepeat: true) }
        core.key(.down)
        core.key(.down, isRepeat: true)
        XCTAssertEqual(frame(core.drawing.marks.first), CGRect(x: 108, y: 102, width: 100, height: 100))
        _ = core.reduce(.keyUp(.right))
        _ = core.reduce(.keyUp(.down))
        XCTAssertEqual(core.undoSteps.count, 1)
        core.key(.character("z"), .command)
        XCTAssertEqual(frame(core.drawing.marks.first), CGRect(x: 100, y: 100, width: 100, height: 100))
    }

    // MARK: Typing

    func testATextThatEndsWithNoTextIsRemoved() {
        var core = core()
        _ = core.reduce(.setTool(.text))
        core.click(200, 200)
        _ = core.reduce(.typingChanged(" \n "))
        core.key(.returnKey)
        XCTAssertTrue(core.drawing.marks.isEmpty)
        XCTAssertEqual(core.undoSteps.count, 0, "a text that never held words leaves no step")

        var edited = self.core([text("old", 200, 200)])
        edited.key(.returnKey, .option)
        _ = edited.reduce(.typingChanged(""))
        edited.key(.escape)
        XCTAssertTrue(edited.drawing.marks.isEmpty)
        XCTAssertEqual(edited.undoSteps.count, 1)
        edited.key(.character("z"), .command)
        XCTAssertEqual(textOf(edited.drawing.marks.first)?.text, "old")
    }

    func testATypingSessionThatChangesNothingAddsNoUndoStep() {
        var core = core([text("same", 200, 200)])
        core.key(.returnKey, .shift)
        _ = core.reduce(.typingChanged("sam"))
        _ = core.reduce(.typingChanged("same"))
        core.key(.returnKey)
        XCTAssertNil(core.typing)
        XCTAssertEqual(core.undoSteps.count, 0)
    }

    func testCreatingATextAndItsFirstSessionAreOneUndoStep() {
        var core = core()
        _ = core.reduce(.setTool(.text))
        core.click(200, 200)
        _ = core.reduce(.typingChanged("one"))
        _ = core.reduce(.typingChanged("one two"))
        core.key(.returnKey)
        XCTAssertEqual(core.undoSteps.count, 1)
        core.key(.returnKey, .shift)
        _ = core.reduce(.typingChanged("one two three"))
        core.key(.escape)
        XCTAssertEqual(core.undoSteps.count, 2)
        core.key(.character("z"), .command)
        XCTAssertEqual(textOf(core.drawing.marks.first)?.text, "one two", "a later session puts back the text as it was")
        core.key(.character("z"), .command)
        XCTAssertTrue(core.drawing.marks.isEmpty)
    }

    func testATypedTextIsCappedAtWhatADrawingFileMayHold() {
        var core = core()
        _ = core.reduce(.setTool(.text))
        core.click(100, 100)
        _ = core.reduce(.typingChanged(String(repeating: "x", count: MarkFields.maxTextLength + 50)))
        XCTAssertEqual(textOf(core.drawing.marks.first)?.text.count, MarkFields.maxTextLength)
        _ = core.reduce(.typingChanged("e" + String(repeating: "\u{301}", count: 60_000)))
        XCTAssertLessThanOrEqual(textOf(core.drawing.marks.first)?.text.utf8.count ?? .max, MarkFields.maxTextBytes)
    }

    // MARK: Undo

    func testThreeRectanglesAndOneUndoLeaveTwo() {
        var core = core()
        core.drag(from: (100, 100), to: (200, 200))
        core.drag(from: (300, 100), to: (400, 200))
        core.drag(from: (500, 100), to: (600, 200))
        core.key(.character("z"), .command)
        XCTAssertEqual(core.drawing.marks.count, 2)
        XCTAssertEqual(core.selection, [core.drawing.marks[1].id], "the selection that went with the step")
    }

    func testDrawADrawBDeleteBAndUndoBringsBothBack() {
        var core = core()
        core.drag(from: (100, 100), to: (200, 200))
        core.drag(from: (300, 100), to: (400, 200))
        let drawn = core.drawing
        core.key(.delete)
        XCTAssertEqual(core.drawing.marks.count, 1)
        core.key(.character("z"), .command)
        XCTAssertEqual(core.drawing, drawn)
        XCTAssertEqual(core.selection, [drawn.marks[1].id])
        core.key(.character("z"), .command, shift: true)
        XCTAssertEqual(core.drawing.marks.count, 1, "redo deletes it again")
    }

    func testCmdZDuringADragCancelsTheDragAndNothingElse() {
        var core = core()
        core.drag(from: (100, 100), to: (200, 200))
        let drawn = core.drawing
        core.press(300, 300)
        core.dragTo(400, 400)
        XCTAssertEqual(core.drawing.marks.count, 2)
        core.key(.character("z"), .command)
        XCTAssertEqual(core.drawing, drawn)
        XCTAssertEqual(core.undoSteps.count, 1)
        XCTAssertNil(core.gesture)
    }

    func testUndoNeverStepsThroughAColourChange() {
        var core = core(pick: { _ in .yellow })
        core.drag(from: (100, 100), to: (200, 200))
        _ = core.reduce(.timerFired)
        core.drag(from: (300, 100), to: (400, 200))
        _ = core.reduce(.timerFired)
        XCTAssertEqual(core.drawing.marks.map(\.color), [.yellow, .yellow])
        XCTAssertEqual(core.undoSteps.count, 2)
        core.key(.character("z"), .command)
        XCTAssertEqual(core.drawing.marks.map(\.color), [.yellow], "B is gone and A keeps its colour")
        core.key(.character("z"), .command)
        XCTAssertTrue(core.drawing.marks.isEmpty)
    }

    // MARK: Clipboard

    func testWithNothingSelectedCmdCCopiesTheDrawingAndLeavesTheEditorOpen() {
        var core = core([rect(100, 100, 100, 100)])
        core.click(900, 500)
        let effects = core.key(.character("c"), .command)
        XCTAssertTrue(effects.contains(.copyDrawing(core.drawing)))
        XCTAssertTrue(effects.contains(.toast("Copied drawing")))
        XCTAssertFalse(effects.contains(.close))
        XCTAssertTrue(core.isOpen)
    }

    func testRightAfterDrawingARectangleAClickOnEmptySpaceThenCmdCCopiesTheDrawing() {
        var core = core()
        core.drag(from: (100, 100), to: (200, 200))
        core.click(500, 500)
        XCTAssertEqual(core.drawing.marks.count, 1)
        XCTAssertTrue(core.key(.character("c"), .command).contains(.copyDrawing(core.drawing)))
        XCTAssertEqual(core.tool, .rectangle)
    }

    func testEveryCopyAndCutSaysWhatItCopied() {
        var core = core([rect(100, 100, 100, 100), rect(300, 100, 100, 100)])
        XCTAssertTrue(core.key(.character("c"), .command).contains(.toast("Copied 1 mark")))
        core.key(.character("a"), .command)
        XCTAssertTrue(core.key(.character("c"), .command).contains(.toast("Copied 2 marks")))
        XCTAssertTrue(core.key(.character("x"), .command).contains(.toast("Cut 2 marks")))
        XCTAssertEqual(core.key(.character("x"), .command), [])
        XCTAssertTrue(core.key(.character("c"), .command).contains(.toast("Copied drawing")))
    }

    func testCmdCThenCmdVAddsACopyTenPointsRightAndDownSelectedAndEachPasteStepsFurther() throws {
        var core = core([rect(100, 100, 100, 100)], scale: 2)
        let payload = try XCTUnwrap(copied(core.key(.character("c"), .command)))
        XCTAssertTrue(core.key(.character("v"), .command).contains(.readClipboard))
        _ = core.reduce(.paste(.marks(payload)))
        XCTAssertEqual(frame(core.drawing.marks.last), CGRect(x: 120, y: 120, width: 100, height: 100))
        XCTAssertEqual(core.selection, [core.drawing.marks[1].id])
        _ = core.reduce(.paste(.marks(payload)))
        XCTAssertEqual(frame(core.drawing.marks.last), CGRect(x: 140, y: 140, width: 100, height: 100))
        XCTAssertEqual(core.undoSteps.count, 2)
    }

    func testACopiedTextCarriesItsWordsForOtherApps() {
        var core = core([rect(100, 100, 50, 50), text("second", 100, 300), text("first", 400, 100)])
        core.key(.character("a"), .command)
        let effects = core.key(.character("c"), .command)
        let words = effects.compactMap { effect -> String? in
            if case .copyMarks(_, let text) = effect { return text }
            return nil
        }
        XCTAssertEqual(words, ["first\nsecond"])
    }

    func testMarksCopiedOnOneScreenshotPasteIntoAnotherAtTheSamePositionInsideTheImage() throws {
        var retina = core([rect(1800, 1000, 100, 100)], pixels: PixelSize(width: 2000, height: 1200), scale: 2)
        let payload = try XCTUnwrap(copied(retina.key(.character("c"), .command)))

        var standard = core(pixels: PixelSize(width: 1000, height: 600), scale: 1)
        _ = standard.reduce(.paste(.marks(payload)))
        XCTAssertEqual(frame(standard.drawing.marks.first), CGRect(x: 900, y: 500, width: 50, height: 50), "the same place and size in pt")

        var small = core(pixels: PixelSize(width: 800, height: 400), scale: 1)
        _ = small.reduce(.paste(.marks(payload)))
        XCTAssertEqual(frame(small.drawing.marks.first), CGRect(x: 750, y: 350, width: 50, height: 50), "kept inside the image")
    }

    func testCmdXRemovesTheSelectedMarksAndCmdVPutsThemBackWhereTheyWere() throws {
        var core = core([rect(100, 100, 100, 100), arrow(300, 300, 400, 350)])
        core.key(.character("a"), .command)
        let before = core.drawing.marks
        let payload = try XCTUnwrap(copied(core.key(.character("x"), .command)))
        XCTAssertTrue(core.drawing.marks.isEmpty)
        XCTAssertEqual(core.undoSteps.count, 1)
        _ = core.reduce(.paste(.marks(payload)))
        XCTAssertEqual(core.drawing.marks.map(\.geometry), before.map(\.geometry))
        XCTAssertEqual(core.selection, Set(core.drawing.marks.map(\.id)))
    }

    func testCmdVOfCopiedTextAddsATextMarkAtThePointer() throws {
        var core = core()
        core.move(300, 200)
        _ = core.reduce(.paste(.text("from another app")))
        let text = try XCTUnwrap(textOf(core.drawing.marks.first))
        XCTAssertEqual(text.text, "from another app")
        XCTAssertEqual(text.origin.x, 300)
        XCTAssertEqual(text.origin.y + EditorMetrics.standard.newTextSize * TextStyle.standard.lineHeight / 2, 200, accuracy: 1e-9)
        XCTAssertEqual(core.selection, [core.drawing.marks[0].id])
        XCTAssertEqual(core.undoSteps.count, 1)
    }

    func testPastingMarksSomeOfWhoseOriginalsAreGoneStepsPastTheOnesStillThere() throws {
        var core = core([rect(100, 100, 50, 50), rect(300, 100, 50, 50)])
        core.key(.character("a"), .command)
        let payload = try XCTUnwrap(copied(core.key(.character("c"), .command)))
        core.click(300, 125)
        core.key(.delete)
        _ = core.reduce(.paste(.marks(payload)))
        XCTAssertEqual(core.drawing.marks.suffix(2).map(frame), [CGRect(x: 110, y: 110, width: 50, height: 50), CGRect(x: 310, y: 110, width: 50, height: 50)])
    }

    func testAMarkPastedTooThinToHaveAnAreaIsDropped() {
        // 5e-324 px passes the validator; from point scale 8 to 0.5 it is scaled to nothing.
        var core = core(scale: 0.5)
        _ = core.reduce(.paste(.marks(CopiedMarks(pointScale: 8, marks: [rect(0, 100, 5e-324, 100)]))))
        XCTAssertTrue(core.drawing.marks.isEmpty)
        // Where its left handle would be, a drag now meets empty space.
        core.drag(from: (0, 150), to: (40, 150))
        for mark in core.drawing.marks {
            XCTAssertGreaterThan(frame(mark)?.width ?? 1, 0)
            XCTAssertGreaterThan(frame(mark)?.height ?? 1, 0)
        }
        let flat = CGRect(x: 0, y: 100, width: 0, height: 100)
        XCTAssertEqual(core.geometry.resized(flat, by: .left, delta: CGVector(dx: 40, dy: 0), proportional: false, fromCenter: false), flat)
    }

    func testCmdVOfAnImageAddsNothingAndSaysSo() {
        var core = core()
        let effects = core.reduce(.paste(.image))
        XCTAssertTrue(core.drawing.marks.isEmpty)
        XCTAssertTrue(effects.contains { if case .toast = $0 { return true } else { return false } })
    }

    // MARK: Around the editor

    func testParkingWhileANewTextIsStillEmptyStoresNoText() {
        var core = core()
        _ = core.reduce(.setTool(.text))
        core.click(200, 200)
        XCTAssertEqual(core.drawing.marks.count, 1)
        let effects = core.reduce(.park)
        XCTAssertTrue(effects.contains(.endTyping))
        XCTAssertTrue(effects.contains(.handOver(Drawing(key: "/tmp/shot.png", pixels: Self.image, pointScale: 1, marks: []))))
        XCTAssertFalse(core.isOpen)
    }

    func testParkingDuringADragKeepsTheMarkAsDrawn() {
        var core = core()
        core.press(100, 100)
        core.dragTo(250, 200)
        let effects = core.reduce(.park)
        let handed = effects.compactMap { effect -> Drawing? in
            if case .handOver(let drawing) = effect { return drawing }
            return nil
        }
        XCTAssertEqual(handed.count, 1)
        XCTAssertEqual(handed.first?.marks.map(\.geometry), [.rectangle(CGRect(x: 100, y: 100, width: 150, height: 100))])
    }

    func testTheDrawingGoesToTheHostAfterThePauseAndNotWhileTheButtonIsHeld() {
        var core = core()
        XCTAssertTrue(core.drag(from: (100, 100), to: (200, 200)).contains(.scheduleTimer))
        core.press(300, 300)
        core.dragTo(400, 400)
        XCTAssertEqual(core.reduce(.timerFired), [.scheduleTimer], "the button is held")
        core.release(400, 400)
        let handed = core.reduce(.timerFired).compactMap { effect -> Drawing? in
            if case .handOver(let drawing) = effect { return drawing }
            return nil
        }
        XCTAssertEqual(handed.first?.marks.count, 2)
        XCTAssertEqual(core.reduce(.timerFired), [], "nothing changed since")
    }

    func testNewTweaksKeepTheDrawingTheSelectionTheHistoryAndTheTextBeingTyped() throws {
        var core = core()
        core.drag(from: (100, 100), to: (300, 250))
        _ = core.reduce(.setTool(.text))
        core.click(200, 400)
        _ = core.reduce(.typingChanged("a note"))
        let drawing = core.drawing, selection = core.selection, typing = try XCTUnwrap(core.typing)
        XCTAssertEqual(core.undoSteps.count, 1)

        var metrics = EditorMetrics.standard
        metrics.handleSize = 20
        let style = TextStyle(weight: .bold, lineHeight: 2)
        let arrowhead = ArrowheadStyle(length: 8, width: 6)
        let effects = core.reduce(.tweaksChanged(style: style, metrics: metrics, arrowhead: arrowhead))
        XCTAssertEqual(core.drawing, drawing, "every mark stays as it was, a text's origin included")
        XCTAssertEqual(core.selection, selection)
        XCTAssertEqual(core.typing, typing)
        XCTAssertFalse(effects.contains(.endTyping))
        XCTAssertEqual(core.undoSteps.count, 1)
        XCTAssertEqual(core.geometry.layout(try XCTUnwrap(textOf(core.drawing.marks.last))).lineHeight, 48, "its lines are set in the new style")

        // Typing goes on in the same session, which ends as one step with the text it made.
        _ = core.reduce(.typingChanged("a note, longer"))
        core.key(.escape)
        XCTAssertEqual(textOf(core.drawing.marks.last)?.text, "a note, longer")
        XCTAssertEqual(core.overlay.handles.compactMap(\.square).first?.width, 20)
        XCTAssertEqual(core.undoSteps.count, 2)
        core.key(.character("z"), .command)
        core.key(.character("z"), .command)
        XCTAssertTrue(core.drawing.marks.isEmpty, "the steps from before the tweaks still undo")
    }

    // MARK: Opening, agents and the colour pass

    func testReopeningSelectsTheNewestMarkThePersonDrewNeverAnAgentsAndChangesNoColour() {
        var mine = rect(100, 100, 100, 100)
        mine.color = .violet
        let agents = rect(300, 300, 100, 100, agent: true)
        var core = core([rect(500, 100, 50, 50), mine, agents], pick: { _ in .yellow })
        XCTAssertEqual(core.tool, .select)
        XCTAssertEqual(core.selection, [mine.id])
        _ = core.reduce(.timerFired)
        XCTAssertEqual(core.drawing.marks.map(\.color), [.red, .violet, .red])

        let onlyAgents = self.core([rect(300, 300, 100, 100, agent: true)])
        XCTAssertEqual(onlyAgents.selection, [])
        XCTAssertEqual(onlyAgents.undoSteps.count, 0)
    }

    func testAgentsMarksJoinTheOpenDrawingAsOneUndoStepEvenWhileTextIsTyped() {
        var core = core(pick: { _ in .yellow })
        _ = core.reduce(.setTool(.text))
        core.click(100, 100)
        _ = core.reduce(.typingChanged("mine"))
        var named = rect(400, 100, 100, 100, agent: true)
        named.colorChosen = true
        let effects = core.reduce(.agentMarks([named, rect(600, 100, 100, 100, agent: true)]))
        XCTAssertTrue(effects.contains { if case .handOver = $0 { return true } else { return false } })
        XCTAssertEqual(core.undoSteps.count, 1)
        XCTAssertEqual(core.drawing.marks.map(\.color), [.red, .red, .yellow], "a named colour is kept; the typed text waits")
        core.key(.returnKey)
        XCTAssertEqual(core.drawing.marks.first?.color, .yellow, "a text's colour is picked when typing ends")
        XCTAssertEqual(core.undoSteps.count, 2)
        core.key(.character("z"), .command)
        XCTAssertEqual(core.drawing.marks.count, 2, "undo takes the text and leaves the agent's marks")
        core.key(.character("z"), .command)
        XCTAssertTrue(core.drawing.marks.isEmpty)
    }

    func testAColourTheCopyOfTheDrawingChangesGoesToTheHost() {
        var answer: MarkColor?
        var core = core(pick: { _ in answer })
        core.drag(from: (100, 100), to: (300, 250))
        _ = core.reduce(.timerFired)
        answer = .yellow
        core.click(600, 500)
        let effects = core.key(.character("c"), .command)
        XCTAssertEqual(core.drawing.marks[0].color, .yellow)
        XCTAssertTrue(effects.contains(.scheduleTimer))
    }

    func testAControlClickDoesNothing() {
        var core = core([rect(100, 100, 100, 100)])
        let drawing = core.drawing
        core.click(900, 500, .control)
        XCTAssertEqual(core.selection, [drawing.marks[0].id])
        core.drag(from: (100, 150), to: (300, 300), .control)
        XCTAssertEqual(core.drawing, drawing)
    }
}

extension EditorCore {
    @discardableResult
    mutating func press(_ x: CGFloat, _ y: CGFloat, _ modifiers: Modifiers = [], count: Int = 1, time: TimeInterval = 0) -> [Effect] {
        reduce(.pointerPressed(Pointer(location: CGPoint(x: x, y: y), modifiers: modifiers, time: time), clickCount: count))
    }

    @discardableResult
    mutating func dragTo(_ x: CGFloat, _ y: CGFloat, _ modifiers: Modifiers = [], time: TimeInterval = 1) -> [Effect] {
        reduce(.pointerDragged(Pointer(location: CGPoint(x: x, y: y), modifiers: modifiers, time: time)))
    }

    @discardableResult
    mutating func release(_ x: CGFloat, _ y: CGFloat, _ modifiers: Modifiers = [], time: TimeInterval = 1) -> [Effect] {
        reduce(.pointerReleased(Pointer(location: CGPoint(x: x, y: y), modifiers: modifiers, time: time)))
    }

    @discardableResult
    mutating func move(_ x: CGFloat, _ y: CGFloat) -> [Effect] {
        reduce(.pointerMoved(Pointer(location: CGPoint(x: x, y: y))))
    }

    /// A press, a drag through the middle and on to `to`, and a release there: the effects of all four.
    @discardableResult
    mutating func drag(from: (CGFloat, CGFloat), to: (CGFloat, CGFloat), _ modifiers: Modifiers = []) -> [Effect] {
        press(from.0, from.1, modifiers)
            + dragTo((from.0 + to.0) / 2, (from.1 + to.1) / 2, modifiers)
            + dragTo(to.0, to.1, modifiers)
            + release(to.0, to.1, modifiers)
    }

    @discardableResult
    mutating func click(_ x: CGFloat, _ y: CGFloat, _ modifiers: Modifiers = [], count: Int = 1) -> [Effect] {
        press(x, y, modifiers, count: count) + release(x, y, modifiers, time: 0.05)
    }

    @discardableResult
    mutating func key(_ key: Key, _ modifiers: Modifiers = [], shift: Bool = false, isRepeat: Bool = false) -> [Effect] {
        reduce(.keyDown(key, shift ? modifiers.union(.shift) : modifiers, isRepeat: isRepeat))
    }
}
