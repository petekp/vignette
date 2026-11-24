import AppKit
import XCTest

@MainActor
final class UndoTimelineTests: XCTestCase {
    private var folder: Set<String> = []
    private var trash: [String: URL] = [:]
    private var column: [String] = []
    private var beeps = 0
    private var announced: [String] = []
    private var timeline: UndoTimeline!
    private var editorOpen: String?
    private var parked: String?
    private var corner = true
    private var steps: [String: (undo: Int, redo: Int)] = [:]
    private var changed: Set<String> = []

    private func shot(_ name: String) -> Screenshot { Screenshot(key: key(name)) }
    private func key(_ name: String) -> ScreenshotKey { ScreenshotKey(folder: URL(fileURLWithPath: "/shots"), name: name) }
    private func names(_ shots: [Screenshot]) -> [String] { shots.map(\.key.name) }

    override func setUp() async throws {
        timeline = UndoTimeline(beep: { [unowned self] in beeps += 1 })
        timeline.announce = { [unowned self] in announced.append($0) }
        timeline.files = UndoTimeline.Files(
            trash: { [unowned self] shots in
                shots.filter { folder.remove($0.key.name) != nil }.map { shot in
                    column.removeAll { $0 == shot.key.name }
                    let inTrash = URL(fileURLWithPath: "/trash/\(shot.key.name)")
                    trash[shot.key.name] = inTrash
                    return FolderWrites.Trashed(shot: shot, inTrash: inTrash)
                }
            },
            putBack: { [unowned self] trashed in
                let back = trashed.filter { trash.removeValue(forKey: $0.shot.key.name) != nil && folder.insert($0.shot.key.name).inserted }
                return (back.map(\.shot), [])
            },
            exists: { [unowned self] in folder.contains($0.key.name) },
            identity: { [unowned self] in FileIdentity(size: changed.contains($0.key.name) ? 2 : 1, modified: .distantPast) })
        timeline.cards = UndoTimeline.Cards(
            column: { [unowned self] in column.map(key) },
            putBack: { [unowned self] shots, was in
                for shot in shots {
                    column.insert(shot.key.name, at: UndoTimeline.place(of: shot.key, in: was, among: column.map(key)))
                }
            },
            takeOut: { [unowned self] shots in column.removeAll { names(shots).contains($0) } },
            draw: { [unowned self] key in
                if let key { open(key.name) } else { close() }
                return true
            },
            isStack: { [unowned self] in corner })
        timeline.editor = UndoTimeline.Editor(
            open: { [unowned self] in
                editorOpen.map { UndoTimeline.EditorPlace(key: key($0), undo: steps[$0]?.undo ?? 0, redo: steps[$0]?.redo ?? 0) }
            },
            depth: { [unowned self] in (editorOpen ?? parked).flatMap { steps[$0]?.undo } ?? 0 },
            step: { [unowned self] redo in
                guard let name = editorOpen, var counts = steps[name] else { return }
                if redo { counts.undo += 1; counts.redo -= 1 } else { counts.undo -= 1; counts.redo += 1 }
                steps[name] = counts
            },
            title: { $0 ? "Redo Arrow" : "Undo Arrow" })
    }

    private func open(_ name: String) {
        park()
        editorOpen = name
        timeline.editorOpened(key(name))
    }

    private func close() {
        park()
        timeline.editorEnded()
    }

    private func park() {
        guard let was = editorOpen else { return }
        editorOpen = nil
        parked = was
        timeline.editorLeft(key(was))
    }

    private func mark() {
        guard let name = editorOpen else { return }
        steps[name] = ((steps[name]?.undo ?? 0) + 1, 0)
    }

    private var depth: Int? { editorOpen.flatMap { steps[$0]?.undo } }

    func testUndoingADeletePutsTheFilesAndTheirCardsBackWhereTheyWere() {
        folder = ["a.png", "b.png", "c.png", "d.png"]
        column = ["a.png", "b.png", "c.png", "d.png"]
        timeline.trash([shot("b.png"), shot("d.png")])
        XCTAssertEqual(column, ["a.png", "c.png"])
        XCTAssertEqual(timeline.menuTitle(for: UndoTimeline.undoAction), "Undo Move to Trash")

        timeline.undo()
        XCTAssertEqual(column, ["a.png", "b.png", "c.png", "d.png"])
        XCTAssertEqual(folder, ["a.png", "b.png", "c.png", "d.png"])
        XCTAssertEqual(timeline.menuTitle(for: UndoTimeline.redoAction), "Redo Move to Trash")
        XCTAssertFalse(timeline.canRun(UndoTimeline.undoAction))

        timeline.redo()
        XCTAssertEqual(column, ["a.png", "c.png"])
        XCTAssertEqual(timeline.menuTitle(for: UndoTimeline.undoAction), "Undo Move to Trash")
        XCTAssertEqual(announced, ["Undo Move to Trash", "Redo Move to Trash"])
        XCTAssertEqual(beeps, 0)
    }

    func testAStepWhoseFileLeftTheTrashBeepsAndTheNextUndoGoesToTheOneBefore() {
        folder = ["a.png", "b.png"]
        column = ["a.png", "b.png"]
        timeline.trash([shot("a.png")])
        timeline.trash([shot("b.png")])
        trash["b.png"] = nil

        timeline.undo()
        XCTAssertEqual(beeps, 1)
        XCTAssertEqual(announced, [])
        XCTAssertEqual(column, [])
        XCTAssertFalse(timeline.canRun(UndoTimeline.redoAction))

        timeline.undo()
        XCTAssertEqual(column, ["a.png"])
        XCTAssertEqual(beeps, 1)
    }

    func testUndoWithNothingToUndoBeeps() {
        timeline.undo()
        timeline.redo()
        XCTAssertEqual(beeps, 2)
        XCTAssertEqual(timeline.menuTitle(for: UndoTimeline.undoAction), "Undo")
        XCTAssertEqual(timeline.menuTitle(for: UndoTimeline.redoAction), "Redo")
    }

    func testUndoingAStitchTrashesItAndBringsBackThePiecesItTookOut() {
        folder = ["a.png", "b.png", "c.png", "stitch.png"]
        column = ["a.png", "b.png", "c.png"]
        let before = column.map(key)
        column = ["stitch.png", "a.png"]
        timeline.stitched(shot("stitch.png"), takenOut: [shot("b.png"), shot("c.png")], column: before)
        XCTAssertEqual(timeline.menuTitle(for: UndoTimeline.undoAction), "Undo Stitch")

        timeline.undo()
        XCTAssertEqual(column, ["a.png", "b.png", "c.png"])
        XCTAssertFalse(folder.contains("stitch.png"))
        XCTAssertEqual(timeline.menuTitle(for: UndoTimeline.redoAction), "Redo Stitch")

        timeline.redo()
        XCTAssertEqual(column, ["stitch.png", "a.png"])
        XCTAssertTrue(folder.contains("stitch.png"))
    }

    func testAStitchRenamedSinceIsTrashedUnderItsNewName() {
        folder = ["a.png", "b.png", "renamed.png"]
        column = ["stitch.png", "a.png", "b.png"]
        timeline.stitched(shot("stitch.png"), takenOut: [], column: ["a.png", "b.png"].map(key))
        timeline.rename([(from: key("stitch.png"), to: key("renamed.png"))])
        column[0] = "renamed.png"

        timeline.undo()
        XCTAssertEqual(folder, ["a.png", "b.png"])
        XCTAssertEqual(column, ["a.png", "b.png"])
        XCTAssertEqual(beeps, 0)
    }

    func testACardGoesBackBeforeTheOlderCardThatIsStillThereElseAfterTheNewerOne() {
        let was = ["a", "b", "c", "d"].map(key)
        XCTAssertEqual(UndoTimeline.place(of: key("b"), in: was, among: ["a", "d"].map(key)), 1)
        XCTAssertEqual(UndoTimeline.place(of: key("d"), in: was, among: ["x", "a", "b"].map(key)), 3)
        XCTAssertEqual(UndoTimeline.place(of: key("b"), in: was, among: ["x"].map(key)), 1)
        XCTAssertEqual(UndoTimeline.place(of: key("z"), in: was, among: ["a"].map(key)), 0)
    }

    func testUndoWalksBackThroughDeleteOpenMarksCloseAndStitchInTheOrderTheyWereMade() {
        folder = ["a.png", "b.png", "c.png", "d.png"]
        column = ["a.png", "b.png", "c.png", "d.png"]
        timeline.trash([shot("a.png")])
        open("b.png")
        mark(); mark()
        close()
        folder.insert("cd.png"); column.insert("cd.png", at: 0)
        timeline.stitched(shot("cd.png"), takenOut: [], column: ["b.png", "c.png", "d.png"])

        var seen: [String] = []
        while timeline.canRun(UndoTimeline.undoAction) {
            seen.append(timeline.menuTitle(for: UndoTimeline.undoAction) ?? "")
            timeline.undo()
        }
        XCTAssertEqual(seen, ["Undo Stitch", "Undo Close Drawing", "Undo Arrow", "Undo Arrow", "Undo Open Drawing", "Undo Move to Trash"])
        XCTAssertNil(editorOpen)
        XCTAssertEqual(steps["b.png"]?.undo, 0)
        XCTAssertEqual(folder, ["a.png", "b.png", "c.png", "d.png"])

        seen = []
        while timeline.canRun(UndoTimeline.redoAction) {
            seen.append(timeline.menuTitle(for: UndoTimeline.redoAction) ?? "")
            timeline.redo()
        }
        XCTAssertEqual(seen, ["Redo Move to Trash", "Redo Open Drawing", "Redo Arrow", "Redo Arrow", "Redo Close Drawing", "Redo Stitch"])
        XCTAssertNil(editorOpen)
        XCTAssertEqual(steps["b.png"]?.undo, 2)
        XCTAssertEqual(beeps, 0)
    }

    func testUndoingACloseOpensTheImageAgainWithItsHistory() {
        folder = ["b.png"]
        open("b.png")
        mark(); mark(); mark()
        timeline.undo()
        close()

        timeline.undo()
        XCTAssertEqual(editorOpen, "b.png")
        XCTAssertEqual(depth, 2)
        XCTAssertEqual(steps["b.png"]?.redo, 1)
        XCTAssertEqual(announced, ["Undo Close Drawing"])
        XCTAssertEqual(timeline.menuTitle(for: UndoTimeline.redoAction), "Redo Close Drawing")
    }

    func testUndoingAnOpeningClosesItAndItsUndoneStepsWaitForRedoAfterItOpensAgain() {
        folder = ["b.png"]
        open("b.png")
        mark(); mark()
        timeline.undo(); timeline.undo()
        XCTAssertEqual(timeline.menuTitle(for: UndoTimeline.undoAction), "Undo Open Drawing")

        timeline.undo()
        XCTAssertNil(editorOpen)
        timeline.redo()
        XCTAssertEqual(editorOpen, "b.png")
        XCTAssertEqual(depth, 0)
        timeline.redo(); timeline.redo()
        XCTAssertEqual(depth, 2)
        timeline.redo()
        XCTAssertEqual(beeps, 1)
    }

    func testASecondOpeningOfAnImageStopsAtItsOwnStartAndItsEarlierStepsWaitAtTheirPlace() {
        folder = ["b.png", "c.png"]
        open("b.png")
        mark()
        close()
        open("c.png")
        close()
        open("b.png")
        mark()

        var seen: [String] = []
        while timeline.canRun(UndoTimeline.undoAction) {
            seen.append("\(timeline.menuTitle(for: UndoTimeline.undoAction) ?? "") \(editorOpen ?? "-")")
            timeline.undo()
        }
        XCTAssertEqual(seen, ["Undo Arrow b.png", "Undo Open Drawing b.png", "Undo Close Drawing -", "Undo Open Drawing c.png",
                              "Undo Close Drawing -", "Undo Arrow b.png", "Undo Open Drawing b.png"])
        XCTAssertEqual(steps["b.png"]?.undo, 0)
        XCTAssertNil(editorOpen)
    }

    func testAnImageTheTimelineHoldsNoStepOfWalksBackThroughItsStoredHistoryBeforeItsOpeningIsUndone() {
        folder = ["b.png"]
        steps["b.png"] = (3, 0)
        open("b.png")
        timeline.undo(); timeline.undo(); timeline.undo()
        XCTAssertEqual(depth, 0)
        XCTAssertEqual(editorOpen, "b.png")
        timeline.undo()
        XCTAssertNil(editorOpen)
    }

    func testSwitchingImagesIsOneStepThatGoesBackToTheImageBefore() {
        folder = ["a.png", "b.png"]
        open("a.png")
        mark()
        open("b.png")
        XCTAssertEqual(timeline.menuTitle(for: UndoTimeline.undoAction), "Undo Open Drawing")
        timeline.undo()
        XCTAssertEqual(editorOpen, "a.png")
        XCTAssertEqual(timeline.menuTitle(for: UndoTimeline.undoAction), "Undo Arrow")
        timeline.redo()
        XCTAssertEqual(editorOpen, "b.png")
    }

    func testAFileReplacedSinceItClosedUsesUpTheStepWithABeepAndTheNextUndoGoesOn() {
        folder = ["a.png", "b.png"]
        column = ["a.png", "b.png"]
        timeline.trash([shot("a.png")])
        open("b.png")
        close()
        changed = ["b.png"]

        timeline.undo()
        XCTAssertNil(editorOpen)
        XCTAssertEqual(beeps, 1)
        XCTAssertEqual(announced, [])
        timeline.undo()
        XCTAssertEqual(folder, ["a.png", "b.png"])
        XCTAssertEqual(announced, ["Undo Move to Trash"])
        XCTAssertEqual(beeps, 1)
    }

    func testAFileDeletedByAnotherAppSinceItClosedUsesUpTheStep() {
        folder = ["b.png"]
        open("b.png")
        close()
        folder = []
        timeline.undo()
        XCTAssertNil(editorOpen)
        XCTAssertEqual(beeps, 1)
        XCTAssertFalse(timeline.canRun(UndoTimeline.undoAction))
    }

    func testUndoingTheDeleteOfTheImageInTheEditorBringsItBackThere() {
        folder = ["b.png"]
        column = ["b.png"]
        open("b.png")
        mark()
        timeline.trash([shot("b.png")])
        close()
        XCTAssertEqual(timeline.menuTitle(for: UndoTimeline.undoAction), "Undo Move to Trash")

        timeline.undo()
        XCTAssertEqual(column, ["b.png"])
        XCTAssertEqual(editorOpen, "b.png")
        XCTAssertEqual(depth, 1)
    }

    func testANewStepInTheEditorEndsWhatCouldBeRedone() {
        folder = ["b.png"]
        open("b.png")
        mark()
        close()
        timeline.undo()
        timeline.undo()
        XCTAssertTrue(timeline.canRun(UndoTimeline.redoAction))
        mark()
        XCTAssertFalse(timeline.canRun(UndoTimeline.redoAction))
        timeline.redo()
        XCTAssertEqual(beeps, 1)
    }

    func testAFileThatKeptFewerStepsThanTheEditorHadMovesItsOpeningsDownByAsMany() {
        folder = ["b.png"]
        open("b.png")
        mark(); mark(); mark()
        close()
        open("b.png")
        mark()
        close()
        steps["b.png"] = (2, 0)

        timeline.undo()
        XCTAssertEqual(depth, 2)
        timeline.undo()
        XCTAssertEqual(depth, 1)
        XCTAssertEqual(editorOpen, "b.png")
        timeline.undo()
        XCTAssertNil(editorOpen)
    }

    func testAnImageWhoseFileLeftAsTheQueueMovedOnIsNotWhatUndoingTheNextOpeningGoesBackTo() {
        folder = ["a.png", "b.png"]
        column = ["a.png", "b.png"]
        open("a.png")
        timeline.trash([shot("a.png")])
        open("b.png")

        timeline.undo()
        XCTAssertNil(editorOpen)
        XCTAssertEqual(beeps, 0)
        timeline.undo()
        XCTAssertEqual(editorOpen, "a.png")
        XCTAssertEqual(column, ["a.png", "b.png"])
    }

    func testUndoWaitsWithABeepWhileTheAnnotatorIsStillClosingTheImage() {
        folder = ["b.png"]
        column = ["b.png"]
        timeline.trash([])
        open("b.png")
        mark()
        park()
        timeline.undo()
        XCTAssertEqual(beeps, 1)
        XCTAssertFalse(timeline.canRun(UndoTimeline.undoAction))

        timeline.editorEnded()
        timeline.undo()
        XCTAssertEqual(editorOpen, "b.png")
        XCTAssertEqual(depth, 1)
    }

    func testAHeldCmdZWalksOnlyTheEditorsOwnSteps() {
        folder = ["b.png"]
        open("b.png")
        mark(); mark()
        for _ in 0..<5 { timeline.walk(redo: false, repeated: true) }
        XCTAssertEqual(depth, 0)
        XCTAssertEqual(editorOpen, "b.png")
        XCTAssertEqual(beeps, 0)
        timeline.undo()
        XCTAssertNil(editorOpen)
    }

    func testOverLoneThumbnailsUndoStopsAtTheOpeningsStart() {
        folder = ["b.png"]
        corner = false
        open("b.png")
        mark()
        timeline.undo()
        XCTAssertEqual(depth, 0)
        timeline.undo()
        XCTAssertEqual(editorOpen, "b.png")
        XCTAssertEqual(beeps, 1)
        XCTAssertFalse(timeline.canRun(UndoTimeline.undoAction))
    }

    func testStoredStepsAreOlderThanTheTimelineSoTheyWaitUntilNothingIsLeftBeforeTheirOpening() {
        folder = ["a.png", "c.png"]
        column = ["a.png", "c.png"]
        steps["a.png"] = (5, 0)
        timeline.trash([shot("c.png")])
        open("a.png")
        close()

        timeline.undo()
        XCTAssertEqual(depth, 5)
        XCTAssertEqual(timeline.menuTitle(for: UndoTimeline.undoAction), "Undo Open Drawing")
        timeline.undo()
        XCTAssertNil(editorOpen)
        timeline.undo()
        XCTAssertEqual(folder, ["a.png", "c.png"])
        XCTAssertFalse(timeline.canRun(UndoTimeline.undoAction))

        open("a.png")
        XCTAssertEqual(timeline.menuTitle(for: UndoTimeline.undoAction), "Undo Arrow")
    }

    func testAgentsMarksAddedWhileClosedLeaveTheOpeningsStartWhereItWas() {
        folder = ["b.png"]
        open("b.png")
        mark()
        close()
        open("b.png")
        mark()
        close()
        steps["b.png"] = (3, 0)

        timeline.undo()
        timeline.undo(); timeline.undo()
        XCTAssertEqual(depth, 1)
        XCTAssertEqual(editorOpen, "b.png")
        timeline.undo()
        XCTAssertNil(editorOpen)
    }

    func testReadingTheTitleLeavesWhatCanBeRedone() {
        folder = ["b.png"]
        open("b.png")
        mark()
        close()
        timeline.undo()
        timeline.undo()
        mark()
        XCTAssertFalse(timeline.canRun(UndoTimeline.redoAction))
        steps["b.png"] = (0, 1)
        XCTAssertTrue(timeline.canRun(UndoTimeline.redoAction))
    }
}
