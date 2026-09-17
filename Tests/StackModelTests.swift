import AppKit
import XCTest

@MainActor
final class StackModelTests: XCTestCase {
    private func model(cards count: Int) -> StackModel {
        let model = StackModel()
        // Index 0 is the newest card, at the bottom of the column.
        model.cards = (0..<count).map { i in
            Card(id: UUID(), shot: Screenshot(url: URL(fileURLWithPath: "/tmp/shot \(i).png")), image: nil,
                 pointSize: NSSize(width: 100, height: 100), size: NSSize(width: 100, height: 100))
        }
        return model
    }

    /// The number in a card's circle has to predict the badge Stitch draws on it, so it counts
    /// from the oldest selected card, the order every action receives them in.
    func testSelectionNumbersCountFromTheOldestAndMatchTheActionOrder() {
        let model = model(cards: 4)
        model.selected = [model.cards[0].id, model.cards[2].id]
        XCTAssertEqual(model.selectionNumber(of: model.cards[2].id), 1, "the older of the two comes first")
        XCTAssertEqual(model.selectionNumber(of: model.cards[0].id), 2)
        XCTAssertNil(model.selectionNumber(of: model.cards[1].id), "not selected, no number")
        XCTAssertEqual(model.selectedCards().map { model.selectionNumber(of: $0.id) }, [1, 2],
                       "the numbers are the positions in the list actions are given")
        XCTAssertEqual(model.selectedIndices(), [0, 2])
    }
}
