import AppKit
import XCTest

@MainActor
final class StackUndoTests: XCTestCase {
    private var folder: Set<String> = []
    private var trash: [String: URL] = [:]
    private var column: [String] = []
    private var beeps = 0
    private var announced: [String] = []
    private var history: StackUndo!

    private func shot(_ name: String) -> Screenshot { Screenshot(key: key(name)) }
    private func key(_ name: String) -> ScreenshotKey { ScreenshotKey(folder: URL(fileURLWithPath: "/shots"), name: name) }
    private func names(_ shots: [Screenshot]) -> [String] { shots.map(\.key.name) }

    override func setUp() async throws {
        history = StackUndo(beep: { [unowned self] in beeps += 1 })
        history.announce = { [unowned self] in announced.append($0) }
        history.files = StackUndo.Files(
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
            exists: { [unowned self] in folder.contains($0.key.name) })
        history.cards = StackUndo.Cards(
            column: { [unowned self] in column.map(key) },
            putBack: { [unowned self] shots, was in
                for shot in shots {
                    column.insert(shot.key.name, at: StackUndo.place(of: shot.key, in: was, among: column.map(key)))
                }
            },
            takeOut: { [unowned self] shots in column.removeAll { names(shots).contains($0) } })
    }

    func testUndoingADeletePutsTheFilesAndTheirCardsBackWhereTheyWere() {
        folder = ["a.png", "b.png", "c.png", "d.png"]
        column = ["a.png", "b.png", "c.png", "d.png"]
        history.trash([shot("b.png"), shot("d.png")])
        XCTAssertEqual(column, ["a.png", "c.png"])
        XCTAssertEqual(history.menuTitle(for: StackUndo.undoAction), "Undo Move to Trash")

        history.undo()
        XCTAssertEqual(column, ["a.png", "b.png", "c.png", "d.png"])
        XCTAssertEqual(folder, ["a.png", "b.png", "c.png", "d.png"])
        XCTAssertEqual(history.menuTitle(for: StackUndo.redoAction), "Redo Move to Trash")
        XCTAssertFalse(history.canRun(StackUndo.undoAction))

        history.redo()
        XCTAssertEqual(column, ["a.png", "c.png"])
        XCTAssertEqual(history.menuTitle(for: StackUndo.undoAction), "Undo Move to Trash")
        XCTAssertEqual(announced, ["Undo Move to Trash", "Redo Move to Trash"])
        XCTAssertEqual(beeps, 0)
    }

    func testAStepWhoseFileLeftTheTrashBeepsAndTheNextUndoGoesToTheOneBefore() {
        folder = ["a.png", "b.png"]
        column = ["a.png", "b.png"]
        history.trash([shot("a.png")])
        history.trash([shot("b.png")])
        trash["b.png"] = nil

        history.undo()
        XCTAssertEqual(beeps, 1)
        XCTAssertEqual(announced, [])
        XCTAssertEqual(column, [])
        XCTAssertFalse(history.canRun(StackUndo.redoAction))

        history.undo()
        XCTAssertEqual(column, ["a.png"])
        XCTAssertEqual(beeps, 1)
    }

    func testUndoWithNothingToUndoBeeps() {
        history.undo()
        history.redo()
        XCTAssertEqual(beeps, 2)
        XCTAssertEqual(history.menuTitle(for: StackUndo.undoAction), "Undo")
        XCTAssertEqual(history.menuTitle(for: StackUndo.redoAction), "Redo")
    }

    func testUndoingAStitchTrashesItAndBringsBackThePiecesItTookOut() {
        folder = ["a.png", "b.png", "c.png", "stitch.png"]
        column = ["a.png", "b.png", "c.png"]
        let before = column.map(key)
        column = ["stitch.png", "a.png"]
        history.stitched(shot("stitch.png"), takenOut: [shot("b.png"), shot("c.png")], column: before)
        XCTAssertEqual(history.menuTitle(for: StackUndo.undoAction), "Undo Stitch")

        history.undo()
        XCTAssertEqual(column, ["a.png", "b.png", "c.png"])
        XCTAssertFalse(folder.contains("stitch.png"))
        XCTAssertEqual(history.menuTitle(for: StackUndo.redoAction), "Redo Stitch")

        history.redo()
        XCTAssertEqual(column, ["stitch.png", "a.png"])
        XCTAssertTrue(folder.contains("stitch.png"))
    }

    func testAStitchRenamedSinceIsTrashedUnderItsNewName() {
        folder = ["a.png", "b.png", "renamed.png"]
        column = ["stitch.png", "a.png", "b.png"]
        history.stitched(shot("stitch.png"), takenOut: [], column: ["a.png", "b.png"].map(key))
        history.rename([(from: key("stitch.png"), to: key("renamed.png"))])
        column[0] = "renamed.png"

        history.undo()
        XCTAssertEqual(folder, ["a.png", "b.png"])
        XCTAssertEqual(column, ["a.png", "b.png"])
        XCTAssertEqual(beeps, 0)
    }

    func testACardGoesBackBeforeTheOlderCardThatIsStillThereElseAfterTheNewerOne() {
        let was = ["a", "b", "c", "d"].map(key)
        XCTAssertEqual(StackUndo.place(of: key("b"), in: was, among: ["a", "d"].map(key)), 1)
        XCTAssertEqual(StackUndo.place(of: key("d"), in: was, among: ["x", "a", "b"].map(key)), 3)
        XCTAssertEqual(StackUndo.place(of: key("b"), in: was, among: ["x"].map(key)), 1)
        XCTAssertEqual(StackUndo.place(of: key("z"), in: was, among: ["a"].map(key)), 0)
    }
}
