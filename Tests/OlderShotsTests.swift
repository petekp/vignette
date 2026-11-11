import AppKit
import XCTest

final class OlderShotsTests: XCTestCase {
    private let now = Date()

    private func files(_ count: Int) -> [String: Date] {
        Dictionary(uniqueKeysWithValues: (0..<count).map { ("Screenshot \(1000 + $0).png", now.addingTimeInterval(Double(-$0))) })
    }

    private func names(_ places: [ScreenshotWatcher.Place]) -> [String] { places.map(\.name) }

    func testChunksWalkTheFolderNewestFirstFromBelowTheColumnToTheOldestFile() {
        let folder = files(10)
        let shown: Set<String> = ["Screenshot 1000.png", "Screenshot 1001.png", "Screenshot 1002.png"]
        let first = ScreenshotWatcher.older(from: folder, after: nil, shown: shown, limit: 4)
        XCTAssertEqual(names(first.places), ["Screenshot 1003.png", "Screenshot 1004.png", "Screenshot 1005.png", "Screenshot 1006.png"])
        XCTAssertTrue(first.more)
        let second = ScreenshotWatcher.older(from: folder, after: first.places.last, shown: shown, limit: 4)
        XCTAssertEqual(names(second.places), ["Screenshot 1007.png", "Screenshot 1008.png", "Screenshot 1009.png"])
        XCTAssertFalse(second.more)
        XCTAssertEqual(ScreenshotWatcher.older(from: folder, after: second.places.last, shown: shown, limit: 4).places, [])
    }

    func testAChunkSkipsWhatTheColumnShowsAndStartsBelowItsOldestCard() {
        var folder = files(6)
        folder["Screenshot 0999.png"] = now.addingTimeInterval(-3)
        let shown: Set<String> = ["Screenshot 1000.png", "Screenshot 1002.png", "Screenshot 1004.png"]
        let chunk = ScreenshotWatcher.older(from: folder, after: nil, shown: shown, limit: 10)
        XCTAssertEqual(names(chunk.places), ["Screenshot 1005.png"])
    }

    func testAChunkStartsAfterThePlaceTheLastOneTookEvenOnceThatFileIsGone() {
        var folder = files(6)
        let first = ScreenshotWatcher.older(from: folder, after: nil, shown: ["Screenshot 1000.png"], limit: 2)
        folder.removeValue(forKey: "Screenshot 1002.png")
        let next = ScreenshotWatcher.older(from: folder, after: first.places.last, shown: ["Screenshot 1000.png"], limit: 2)
        XCTAssertEqual(names(next.places), ["Screenshot 1003.png", "Screenshot 1004.png"])
    }

    func testAColumnTheIndexDoesNotHoldStartsAtTheNewestFile() {
        let chunk = ScreenshotWatcher.older(from: files(3), after: nil, shown: ["elsewhere.png"], limit: 5)
        XCTAssertEqual(names(chunk.places), ["Screenshot 1000.png", "Screenshot 1001.png", "Screenshot 1002.png"])
        XCTAssertFalse(chunk.more)
    }

    func testEqualDatesFallToTheNameAsTheRecentStackOrdersThem() {
        let folder = ["a.png": now, "c.png": now, "b.png": now, "d.png": now.addingTimeInterval(-1)]
        let chunk = ScreenshotWatcher.older(from: folder, after: nil, shown: ["c.png"], limit: 5)
        XCTAssertEqual(names(chunk.places), ["b.png", "a.png", "d.png"])
    }
}

@MainActor
final class CardPicturesTests: XCTestCase {
    private func plan(cards: Int, scroll: CGFloat, holding: (Int) -> Bool, keeps: (Int) -> Bool = { _ in false }) -> (drop: [Int], want: [Int]) {
        CardPictures.plan(heights: Array(repeating: 90, count: cards), spacing: 10, view: scroll...(scroll + 1000),
                          holding: (0..<cards).map(holding), keeps: keeps)
    }

    func testAColumnNoLongerThanTheLargestRecentCountKeepsEveryPicture() {
        let result = plan(cards: CardPictures.keptAlways, scroll: 9000, holding: { _ in true })
        XCTAssertEqual(result.drop, [])
        XCTAssertEqual(result.want, [])
    }

    func testPicturesFarFromTheViewGoInABatchAndThoseInViewStay() {
        let result = plan(cards: 300, scroll: 20000, holding: { _ in true })
        XCTAssertEqual(result.drop.count, 209)
        XCTAssertFalse(result.drop.contains { (160...250).contains($0) }, "cards within four viewports either side keep theirs")
        XCTAssertTrue(result.drop.contains(0))
        XCTAssertTrue(result.drop.contains(299))
    }

    func testAFewFarPicturesWaitForAWholeBatch() {
        let result = plan(cards: 300, scroll: 20000, holding: { (140..<260).contains($0) })
        XCTAssertEqual(result.drop, [], "29 held pictures are far, one short of a batch")
    }

    func testCardsComingNearTheViewAskForTheirPicturesBack() {
        let result = plan(cards: 300, scroll: 20000, holding: { _ in false })
        XCTAssertEqual(result.want, Array(180..<230), "two viewports either side of the cards in view")
    }

    func testACardTheControllerHoldsKeepsItsPictureAnywhere() {
        let result = plan(cards: 300, scroll: 20000, holding: { _ in true }, keeps: { $0 == 0 })
        XCTAssertFalse(result.drop.contains(0))
    }
}
