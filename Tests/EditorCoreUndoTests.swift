import XCTest

final class EditorCoreUndoTests: XCTestCase {
    private func core() -> EditorCore {
        var core = EditorCore()
        _ = core.reduce(.open(Drawing(key: "/tmp/shot.png", pixels: PixelSize(width: 1000, height: 600), pointScale: 1, marks: []),
                              style: .standard, metrics: .standard, markStyle: .standard))
        return core
    }

    func testEachUndoStepIsNamedAsTheEditMenuNamesItAndUndoSaysWhatItUndid() throws {
        var core = core()
        XCTAssertEqual(core.undoTitle, "Undo")
        XCTAssertEqual(core.redoTitle, "Redo")
        core.drag(from: (100, 100), to: (300, 250))
        XCTAssertEqual(core.undoTitle, "Undo Rectangle")
        _ = core.reduce(.setTool(.select))
        core.drag(from: (200, 175), to: (250, 200))
        XCTAssertEqual(core.undoTitle, "Undo Move")
        core.key(.right)
        _ = core.reduce(.keyUp(.right))
        XCTAssertEqual(core.undoSteps.map(\.name), [.rectangle, .move, .move])
        core.key(.character("d"), .command)
        XCTAssertEqual(core.undoTitle, "Undo Duplicate")
        core.key(.delete)
        XCTAssertEqual(core.undoTitle, "Undo Delete")
        core.key(.character("a"), .command)
        core.key(.character("x"), .command)
        XCTAssertEqual(core.undoTitle, "Undo Cut")
        _ = core.reduce(.setTool(.arrow))
        core.drag(from: (400, 100), to: (600, 300))
        XCTAssertEqual(core.undoTitle, "Undo Arrow")
        _ = core.reduce(.setTool(.text))
        core.click(700, 400)
        _ = core.reduce(.typingChanged("a note"))
        core.key(.escape)
        XCTAssertEqual(core.undoTitle, "Undo Typing")
        _ = core.reduce(.paste(.text("pasted")))
        XCTAssertEqual(core.undoTitle, "Undo Paste")
        _ = core.reduce(.agentMarks([Mark(geometry: .rectangle(CGRect(x: 600, y: 100, width: 100, height: 100)), agent: true, agentName: "Claude")]))
        XCTAssertEqual(core.undoTitle, "Undo Claude's Marks")

        let undone = core.key(.character("z"), .command)
        XCTAssertTrue(undone.contains(.announce("Undo Claude's Marks")))
        XCTAssertEqual(core.undoTitle, "Undo Paste")
        XCTAssertEqual(core.redoTitle, "Redo Claude's Marks")
        XCTAssertTrue(core.key(.character("z"), [.command, .shift]).contains(.announce("Redo Claude's Marks")))
        XCTAssertEqual(core.inspection["undoTitle"] as? String, "Undo Claude's Marks")

        _ = core.reduce(.agentMarks([], pins: try AgentPin.parse(#"[{"x":0.3,"y":0.5,"text":"Here"}]"#), from: "Claude"))
        let pin = try XCTUnwrap(core.drawing.pins.first)
        XCTAssertEqual(pin.place, .point(CGPoint(x: 300, y: 300)))
        XCTAssertEqual(core.newestAgentMarks?.pins.map(\.id), [pin.id], "an agent's pins alone are a join Keep's undo can take back")
        core.key(.character("z"), .command)
        XCTAssertEqual(core.drawing.pins, [])
    }

    func testTheMessageFieldsTypingIsOneStepInOrderWithTheMarksAndUndoPutsItsWordsBack() {
        var core = core()
        core.drag(from: (100, 100), to: (300, 250))
        for words in ["t", "th", "the"] { _ = core.reduce(.messageChanged(words, .typing)) }
        XCTAssertEqual(core.undoSteps.map(\.name), [.rectangle, .typing])
        XCTAssertEqual(core.undoTitle, "Undo Typing")
        _ = core.reduce(.messageTypingEnded)
        _ = core.reduce(.messageChanged("the box", .typing))
        _ = core.reduce(.messageChanged("the box scrolls", .paste))
        _ = core.reduce(.messageChanged("the box scrolls!", .typing))
        _ = core.reduce(.messageChanged("the box scrolls!", .typing))
        XCTAssertEqual(core.undoSteps.map(\.name), [.rectangle, .typing, .typing, .paste, .typing])
        core.drag(from: (500, 100), to: (700, 250))
        _ = core.reduce(.messageChanged("the box scrolls!?", .typing))
        XCTAssertEqual(core.undoSteps.map(\.name), [.rectangle, .typing, .typing, .paste, .typing, .rectangle, .typing],
                       "a mark drawn between ends the typing's step")

        core.key(.character("z"), .command)
        core.key(.character("z"), .command)
        let undone = core.key(.character("z"), .command)
        XCTAssertTrue(undone.contains(.message("the box scrolls")))
        XCTAssertTrue(undone.contains(.announce("Undo Typing")))
        XCTAssertEqual(core.message, "the box scrolls")
        XCTAssertEqual(core.drawing.marks.count, 1)
        for _ in 0..<3 { core.key(.character("z"), .command) }
        XCTAssertEqual(core.message, "")
        XCTAssertEqual(core.drawing.marks.count, 1)
        core.key(.character("z"), .command)
        XCTAssertTrue(core.drawing.marks.isEmpty)

        core.key(.character("z"), [.command, .shift])
        XCTAssertEqual(core.drawing.marks.count, 1)
        XCTAssertTrue(core.key(.character("z"), [.command, .shift]).contains(.message("the")))
        _ = core.reduce(.messageChanged("then", .typing))
        XCTAssertTrue(core.redoSteps.isEmpty, "a new change ends what could be redone")
        XCTAssertEqual(core.undoSteps.map(\.name), [.rectangle, .typing, .typing])
    }

    func testKeptMarksTakenBackTakeTheRedoStepsWithThemAndPuttingThemBackBringsThoseBack() throws {
        var core = core()
        _ = core.reduce(.agentMarks([Mark(geometry: .rectangle(CGRect(x: 600, y: 100, width: 100, height: 100)), agent: true, agentName: "Claude")]))
        core.drag(from: (100, 100), to: (300, 250))
        XCTAssertNil(core.newestAgentMarks, "the newest step is the person's rectangle")
        core.key(.character("z"), .command)
        XCTAssertEqual(core.redoTitle, "Redo Rectangle")

        let kept = TakenBackMarks(step: try XCTUnwrap(core.newestAgentMarks), redo: core.redoSteps)
        XCTAssertTrue(core.reduce(.takeBackAgentMarks).contains { if case .handOver = $0 { return true } else { return false } })
        XCTAssertTrue(core.drawing.marks.isEmpty)
        XCTAssertEqual(core.undoTitle, "Undo")
        XCTAssertEqual(core.redoTitle, "Redo")

        _ = core.reduce(.putBackAgentMarks(kept))
        XCTAssertEqual(core.drawing.marks.map(\.agent), [true])
        XCTAssertEqual(core.undoTitle, "Undo Claude's Marks")
        XCTAssertEqual(core.redoTitle, "Redo Rectangle")
        core.key(.character("z"), [.command, .shift])
        XCTAssertEqual(core.drawing.marks.map(\.agent), [true, false])
    }
}
