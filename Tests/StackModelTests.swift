import AppKit
import XCTest

@MainActor
final class StackModelTests: XCTestCase {
    private func model(cards count: Int) -> StackModel {
        let model = StackModel()
        // Index 0 is the newest card, at the bottom of the column.
        model.cards = (0..<count).map { i in
            Card(id: UUID(), shot: Screenshot(key: URL(fileURLWithPath: "/tmp/shot \(i).png").screenshotKey), image: nil,
                 pointSize: NSSize(width: 100, height: 100), size: NSSize(width: 100, height: 100), agent: nil)
        }
        return model
    }

    /// The number in a card's circle is the order it was picked in, and that is the order the
    /// actions receive the cards and the badge Stitch draws on each one.
    func testSelectionNumbersCountInTheOrderTheCardsWereSelected() {
        let model = model(cards: 4)
        for card in [model.cards[2], model.cards[0], model.cards[3]] { model.toggleSelection(of: card.id) }
        XCTAssertEqual(model.selectionNumber(of: model.cards[2].id), 1)
        XCTAssertEqual(model.selectionNumber(of: model.cards[0].id), 2, "picked second, though it is the newest")
        XCTAssertEqual(model.selectionNumber(of: model.cards[3].id), 3)
        XCTAssertNil(model.selectionNumber(of: model.cards[1].id), "not selected, no number")
        XCTAssertEqual(model.selectedCards().map { model.selectionNumber(of: $0.id) }, [1, 2, 3],
                       "the numbers are the positions in the list actions are given")
        XCTAssertEqual(model.selectedIndices(), [0, 2, 3], "where they sit in the column, whatever the order")
    }

    func testWhenTheFocusedCardLeavesTheNewestTakesTheFocus() {
        let model = model(cards: 3)
        let oldest = model.cards[2].id
        model.focused = oldest
        model.removeCards { $0.id == oldest }
        XCTAssertEqual(model.focused, model.cards.first?.id)
        model.removeCards { _ in true }
        XCTAssertNil(model.focused)
    }

    func testASweepWhoseFirstCardLeavesStartsAgainFromTheCardUnderThePointer() {
        let model = model(cards: 3)
        let sweep = StackSweep(model: model, screen: { NSScreen.screens[0] },
                               column: { .init(layout: StackLayout(ui: UITweaks()), cards: model.cards.map(\.size), contentHeight: 0, maxScroll: 0) },
                               isVisible: { false }, selected: {}, relayout: {})
        let oldest = model.cards[2].id
        sweep.move(toYFromTop: 10)
        XCTAssertEqual(model.selection, [oldest])
        model.removeCards { $0.id == oldest }
        model.deselect([oldest])
        sweep.move(toYFromTop: 10)
        XCTAssertEqual(model.selection, [model.cards[1].id])
        XCTAssertEqual(model.focused, model.cards[1].id)
    }

    func testTheOverflowKeepsTheCardsInTheEditorAndInAStitch() {
        let model = model(cards: 4)
        let (inEditor, forming, oldestFree) = (model.cards[3].id, model.cards[2].id, model.cards[1].id)
        model.outCards = [inEditor]
        model.forming = [forming]
        XCTAssertTrue(model.removeOverflow(over: 3))
        XCTAssertFalse(model.cards.contains { $0.id == oldestFree })
        XCTAssertEqual(model.cards.count, 3)
        XCTAssertTrue(model.cards.contains { $0.id == inEditor })
        XCTAssertTrue(model.cards.contains { $0.id == forming })
    }

    func testPickingACardAgainPutsItLast() {
        let model = model(cards: 3)
        for card in model.cards { model.toggleSelection(of: card.id) }
        model.toggleSelection(of: model.cards[0].id)
        XCTAssertNil(model.selectionNumber(of: model.cards[0].id), "toggled off")
        XCTAssertEqual(model.selectionNumber(of: model.cards[1].id), 1, "the rest close the gap it left")
        model.toggleSelection(of: model.cards[0].id)
        XCTAssertEqual(model.selectionNumber(of: model.cards[0].id), 3, "back on, at the end")
    }

    /// The controller queues cards for the annotator from what joins the selection, in the order
    /// picked, and drops what leaves it; a change that changes nothing is not reported.
    func testSelectionChangesReportWhatJoinedInOrderAndWhatLeft() {
        let model = model(cards: 4)
        var reports: [(added: [UUID], removed: [UUID])] = []
        model.onSelectionChanged = { reports.append((added: $0, removed: $1)) }
        model.select([model.cards[2].id, model.cards[0].id])
        model.select([model.cards[0].id])
        model.setSelection([model.cards[0].id, model.cards[3].id])
        XCTAssertEqual(reports.map(\.added), [[model.cards[2].id, model.cards[0].id], [model.cards[3].id]])
        XCTAssertEqual(reports.map(\.removed), [[], [model.cards[2].id]])
    }

    func testThePagesBesideAScreenshotAreTheNextImagesInTheColumnPassingOverRecordings() {
        let model = model(cards: 4)
        let recording = URL(fileURLWithPath: "/tmp/recording.mov").screenshotKey
        model.cards[1] = Card(id: UUID(), shot: Screenshot(key: recording), image: nil, pointSize: NSSize(width: 100, height: 100),
                              size: NSSize(width: 100, height: 100), agent: nil)
        let keys = model.cards.map(\.shot.key)
        XCTAssertEqual(model.neighbor(of: keys[0], .older)?.shot.key, keys[2])
        XCTAssertEqual(model.neighbor(of: keys[2], .newer)?.shot.key, keys[0])
        XCTAssertEqual(model.neighbor(of: keys[2], .older)?.shot.key, keys[3])
        XCTAssertNil(model.neighbor(of: keys[0], .newer), "the newest")
        XCTAssertNil(model.neighbor(of: keys[3], .older), "the oldest")
        XCTAssertNil(model.neighbor(of: URL(fileURLWithPath: "/tmp/elsewhere.png").screenshotKey, .older), "not in the column")
    }

    func testEveryCardOnScreenThatTheStackShowsStaysAndOnlyTheOthersEnter() {
        let model = model(cards: 3)
        let onScreen = model.cards.map { ($0.shot.key, $0.id) }
        let older = (3..<6).map { URL(fileURLWithPath: "/tmp/shot \($0).png").screenshotKey }
        let recent = model.cards.map(\.shot.key) + older
        let entrance = StackEntrance(onScreen: onScreen, recent: recent)
        XCTAssertEqual(entrance.kept, model.cards.map(\.id) + [nil, nil, nil])
    }

    func testTheFirstCardToEnterGoesAtOnce() {
        let model = model(cards: 2)
        let newer = URL(fileURLWithPath: "/tmp/newer.png").screenshotKey
        let older = URL(fileURLWithPath: "/tmp/older.png").screenshotKey
        let entrance = StackEntrance(onScreen: model.cards.map { ($0.shot.key, $0.id) },
                                     recent: [newer] + model.cards.map(\.shot.key) + [older])
        XCTAssertEqual(entrance.ranks, [0, nil, nil, 1])
    }
}
