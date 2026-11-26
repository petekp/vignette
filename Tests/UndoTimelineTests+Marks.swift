import AppKit
import XCTest

@MainActor
extension UndoTimelineTests {
    private func entry(_ agent: String = "claude") -> PendingMarks.Entry {
        PendingMarks.Entry(agent: agent, marks: [AgentMark(type: .rectangle, x: 0.1, y: 0.1, w: 0.2, h: 0.2)],
                           drawing: Drawing(key: "/shots/b.png", pixels: PixelSize(width: 300, height: 200), pointScale: 1, marks: []))
    }

    private func keep(_ marks: PendingMarks.Entry, on name: String) {
        onTop[name] = nil
        if editorOpen == name { mark() } else { joined[name, default: 0] += 1 }
        timeline.kept(marks, on: key(name))
    }

    private func clear(_ marks: PendingMarks.Entry, on name: String) {
        onTop[name] = nil
        timeline.cleared(marks, on: key(name))
    }

    func testUndoingClearPutsTheAgentsMarksBackOnTopAndRedoTakesThemOffAgain() {
        let marks = entry()
        clear(marks, on: "b.png")
        XCTAssertEqual(timeline.menuTitle(for: UndoTimeline.undoAction), "Undo Clear Marks")

        timeline.undo()
        XCTAssertEqual(onTop["b.png"]?.id, marks.id)
        XCTAssertEqual(timeline.menuTitle(for: UndoTimeline.redoAction), "Redo Clear Marks")

        timeline.redo()
        XCTAssertNil(onTop["b.png"])
        timeline.undo()
        XCTAssertEqual(onTop["b.png"]?.id, marks.id)
        XCTAssertEqual(announced, ["Undo Clear Marks", "Redo Clear Marks", "Undo Clear Marks"])
        XCTAssertEqual(beeps, 0)
    }

    func testUndoingKeepOnACardTakesTheMarksOutOfTheDrawingAndPutsThemBackOnTop() {
        let marks = entry()
        keep(marks, on: "b.png")
        XCTAssertEqual(timeline.menuTitle(for: UndoTimeline.undoAction), "Undo Keep Marks")

        timeline.undo()
        XCTAssertEqual(joined["b.png"], 0)
        XCTAssertEqual(onTop["b.png"]?.id, marks.id)
        XCTAssertEqual(timeline.menuTitle(for: UndoTimeline.redoAction), "Redo Keep Marks")

        timeline.redo()
        XCTAssertEqual(joined["b.png"], 1)
        XCTAssertNil(onTop["b.png"])
        timeline.undo()
        XCTAssertEqual(joined["b.png"], 0)
        XCTAssertEqual(beeps, 0)
    }

    func testKeepInTheEditorSitsAboveItsJoinSoTheStepsDrawnAfterItAreUndoneFirst() {
        folder = ["b.png"]
        let marks = entry()
        open("b.png")
        mark()
        keep(marks, on: "b.png")
        mark()

        var seen: [String] = []
        while timeline.canRun(UndoTimeline.undoAction) {
            seen.append(timeline.menuTitle(for: UndoTimeline.undoAction) ?? "")
            timeline.undo()
        }
        XCTAssertEqual(seen, ["Undo Arrow", "Undo Keep Marks", "Undo Arrow", "Undo Open Drawing"])
        XCTAssertEqual(steps["b.png"]?.undo, 0)
        XCTAssertEqual(onTop["b.png"]?.id, marks.id)

        seen = []
        while timeline.canRun(UndoTimeline.redoAction) {
            seen.append(timeline.menuTitle(for: UndoTimeline.redoAction) ?? "")
            timeline.redo()
        }
        XCTAssertEqual(seen, ["Redo Open Drawing", "Redo Arrow", "Redo Keep Marks", "Redo Arrow"])
        XCTAssertNil(onTop["b.png"])
        XCTAssertEqual(beeps, 0)
    }

    func testClearInTheEditorIsUndoneAfterTheStepsDrawnSince() {
        folder = ["b.png"]
        let marks = entry()
        open("b.png")
        clear(marks, on: "b.png")
        mark()

        timeline.undo()
        XCTAssertNil(onTop["b.png"])
        XCTAssertEqual(timeline.menuTitle(for: UndoTimeline.undoAction), "Undo Clear Marks")
        timeline.undo()
        XCTAssertEqual(onTop["b.png"]?.id, marks.id)
        XCTAssertEqual(editorOpen, "b.png")
    }

    func testAKeepWhoseDrawingChangedSinceIsUsedUpWithABeepAndTheMarksStayKept() {
        let marks = entry()
        keep(marks, on: "b.png")
        redrawn = ["b.png"]

        timeline.undo()
        XCTAssertEqual(beeps, 1)
        XCTAssertEqual(joined["b.png"], 1)
        XCTAssertNil(onTop["b.png"])
        XCTAssertFalse(timeline.canRun(UndoTimeline.undoAction))
    }

    func testNewerMarksOnTopUseUpTheStepAndStayWhereTheyAre() {
        let cleared = entry(), newer = entry("codex")
        clear(cleared, on: "b.png")
        onTop["b.png"] = newer

        timeline.undo()
        XCTAssertEqual(beeps, 1)
        XCTAssertEqual(onTop["b.png"]?.id, newer.id)

        keep(newer, on: "b.png")
        timeline.undo()
        onTop["b.png"] = cleared
        timeline.redo()
        XCTAssertEqual(beeps, 2)
        XCTAssertEqual(joined["b.png"], 0)
        XCTAssertEqual(onTop["b.png"]?.id, cleared.id)
    }
}
