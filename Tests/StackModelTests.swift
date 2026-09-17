import AppKit
import XCTest

@MainActor
final class StackModelTests: XCTestCase {
    private func model(cards count: Int) -> StackModel {
        let model = StackModel()
        // Index 0 is the newest card, at the bottom of the column.
        model.cards = (0..<count).map { i in
            Card(id: UUID(), shot: Screenshot(url: URL(fileURLWithPath: "/tmp/shot \(i).png")), image: nil,
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

    func testPickingACardAgainPutsItLast() {
        let model = model(cards: 3)
        for card in model.cards { model.toggleSelection(of: card.id) }
        model.toggleSelection(of: model.cards[0].id)
        XCTAssertNil(model.selectionNumber(of: model.cards[0].id), "toggled off")
        XCTAssertEqual(model.selectionNumber(of: model.cards[1].id), 1, "the rest close the gap it left")
        model.toggleSelection(of: model.cards[0].id)
        XCTAssertEqual(model.selectionNumber(of: model.cards[0].id), 3, "back on, at the end")
    }
}
