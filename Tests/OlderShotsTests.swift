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
        let first = ScreenshotWatcher.older(from: folder, after: nil, top: "Screenshot 1002.png", shown: shown, limit: 4)
        XCTAssertEqual(names(first.places), ["Screenshot 1003.png", "Screenshot 1004.png", "Screenshot 1005.png", "Screenshot 1006.png"])
        XCTAssertTrue(first.more)
        let second = ScreenshotWatcher.older(from: folder, after: first.places.last, top: "Screenshot 1002.png", shown: shown, limit: 4)
        XCTAssertEqual(names(second.places), ["Screenshot 1007.png", "Screenshot 1008.png", "Screenshot 1009.png"])
        XCTAssertFalse(second.more)
        XCTAssertEqual(ScreenshotWatcher.older(from: folder, after: second.places.last, top: "Screenshot 1002.png", shown: shown, limit: 4).places, [])
    }

    func testAChunkSkipsWhatTheColumnShowsAndStartsBelowItsTopCard() {
        var folder = files(6)
        folder["Screenshot 0999.png"] = now.addingTimeInterval(-3)
        let shown: Set<String> = ["Screenshot 1000.png", "Screenshot 1002.png", "Screenshot 1004.png"]
        let chunk = ScreenshotWatcher.older(from: folder, after: nil, top: "Screenshot 1004.png", shown: shown, limit: 10)
        XCTAssertEqual(names(chunk.places), ["Screenshot 1005.png"])
    }

    func testACardWithAnOldDateBelowTheTopCardDoesNotMoveTheStart() {
        let shown: Set<String> = ["Screenshot 1000.png", "Screenshot 1001.png", "Screenshot 1008.png"]
        let chunk = ScreenshotWatcher.older(from: files(10), after: nil, top: "Screenshot 1001.png", shown: shown, limit: 10)
        XCTAssertEqual(names(chunk.places), ["Screenshot 1002.png", "Screenshot 1003.png", "Screenshot 1004.png",
                                             "Screenshot 1005.png", "Screenshot 1006.png", "Screenshot 1007.png", "Screenshot 1009.png"])
    }

    func testAChunkStartsAfterThePlaceTheLastOneTookEvenOnceThatFileIsGone() {
        var folder = files(6)
        let first = ScreenshotWatcher.older(from: folder, after: nil, top: "Screenshot 1000.png", shown: ["Screenshot 1000.png"], limit: 2)
        folder.removeValue(forKey: "Screenshot 1002.png")
        let next = ScreenshotWatcher.older(from: folder, after: first.places.last, top: "Screenshot 1000.png", shown: ["Screenshot 1000.png"], limit: 2)
        XCTAssertEqual(names(next.places), ["Screenshot 1003.png", "Screenshot 1004.png"])
    }

    func testAColumnTheIndexDoesNotHoldStartsAtTheNewestFile() {
        let chunk = ScreenshotWatcher.older(from: files(3), after: nil, top: "elsewhere.png", shown: ["elsewhere.png"], limit: 5)
        XCTAssertEqual(names(chunk.places), ["Screenshot 1000.png", "Screenshot 1001.png", "Screenshot 1002.png"])
        XCTAssertFalse(chunk.more)
    }

    func testEqualDatesFallToTheNameAsTheRecentStackOrdersThem() {
        let folder = ["a.png": now, "c.png": now, "b.png": now, "d.png": now.addingTimeInterval(-1)]
        let chunk = ScreenshotWatcher.older(from: folder, after: nil, top: "c.png", shown: ["c.png"], limit: 5)
        XCTAssertEqual(names(chunk.places), ["b.png", "a.png", "d.png"])
    }
}

@MainActor
final class CardPicturesTests: XCTestCase {
    private func plan(cards: Int, scroll: CGFloat, holding: (Int) -> Bool, keeps: (Int) -> Bool = { _ in false }) -> (drop: [Int], want: [Int]) {
        CardPictures.plan(heights: Array(repeating: 90, count: cards), spacing: 10, view: scroll...(scroll + 1000),
                          holding: (0..<cards).map(holding), keepsAll: 30, keeps: keeps)
    }

    func testAColumnNoLongerThanKeptAlwaysKeepsEveryPicture() {
        let result = plan(cards: CardPictures.keptAlways, scroll: 9000, holding: { _ in true })
        XCTAssertEqual(result.drop, [])
        XCTAssertEqual(result.want, [])
    }

    private func png(_ shade: CGFloat) -> Data {
        let ctx = CGContext(data: nil, width: 300, height: 195, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: shade, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 195))
        return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    }

    func testACardInViewGetsItsPictureBackAfterTheColumnShrinks() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shrunk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let controller = ThumbnailController()
        let layout = StackLayout.current
        let point = NSSize(width: 1512, height: 982)
        let short = max(CardPictures.keptAlways, Settings.shared.data.recentCount)
        var cards: [Card] = []
        for i in 0..<(short + 31) {
            let name = "Screenshot \(i).png"
            let url = folder.appendingPathComponent(name)
            try png(CGFloat(i % 10) / 10).write(to: url)
            cards.append(Card(id: UUID(), shot: Screenshot(key: ScreenshotKey(folder: folder, name: name)),
                              image: NSImage(contentsOf: url), pointSize: point, size: layout.cardSize(for: point), agent: nil))
        }
        controller.model.viewport = 900
        controller.model.cards = cards
        controller.visible = true
        controller.keepPictures()
        let dropped = Set(controller.model.cards.filter { $0.image == nil }.map(\.id))
        XCTAssertGreaterThanOrEqual(dropped.count, 30)
        let newest = Set(controller.model.cards.prefix(32).map(\.id))
        XCTAssertTrue(newest.isDisjoint(with: dropped))
        let staying = controller.model.cards.filter { !newest.contains($0.id) }
        guard let index = staying.firstIndex(where: { dropped.contains($0.id) }) else { return XCTFail("no dropped card") }
        let id = staying[index].id
        controller.model.scroll = layout.cardSpan(index: index, cards: staying.map { layout.drawn($0.size) }).bottom
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertNil(controller.model.cards.first(where: { $0.id == id })?.image)
        controller.removeCards { newest.contains($0.id) }
        XCTAssertEqual(controller.model.cards.count, short - 1)
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, controller.model.cards.first(where: { $0.id == id })?.image == nil {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertNotNil(controller.model.cards.first(where: { $0.id == id })?.image, "the card in view has no picture")
    }

    func testAColumnThatShrankTakesBackThePicturesItLetGo() {
        let result = plan(cards: 90, scroll: 5000, holding: { !(48...62).contains($0) })
        XCTAssertEqual(result.drop, [])
        XCTAssertEqual(result.want, Array(48...62))
    }

    func testAColumnNoLongerThanALargerRecentCountKeepsEveryPicture() {
        let result = CardPictures.plan(heights: Array(repeating: 90, count: 300), spacing: 10, view: 20000...21000,
                                       holding: Array(repeating: true, count: 300), keepsAll: 300, keeps: { _ in false })
        XCTAssertEqual(result.drop, [])
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

final class ColumnSlotsTests: XCTestCase {
    private let layout = StackLayout(ui: UITweaks())
    private var sizes: [NSSize] { Array(repeating: NSSize(width: 188, height: 100), count: 10) }

    private func slotBottom(_ index: Int) -> CGFloat { CGFloat(index) * (100 + layout.spacing) }

    func testTheCardsMeetingABandAreEveryCardWithAnyPartInIt() {
        let band = (slotBottom(3) + 99)...(slotBottom(6) + 1)
        XCTAssertEqual(layout.cards(meeting: band, sizes: sizes), IndexSet(3..<7))
    }

    func testABandInTheGapBetweenTwoCardsMeetsNeither() {
        let band = (slotBottom(4) + 100.5)...(slotBottom(5) - 0.5)
        XCTAssertTrue(layout.cards(meeting: band, sizes: sizes).isEmpty)
    }

    func testABandPastEitherEndMeetsOnlyTheCardsThere() {
        XCTAssertEqual(layout.cards(meeting: -500...50, sizes: sizes), IndexSet(0..<1))
        XCTAssertEqual(layout.cards(meeting: (slotBottom(9) + 50)...5000, sizes: sizes), IndexSet(9..<10))
        XCTAssertTrue(layout.cards(meeting: 5000...6000, sizes: sizes).isEmpty)
    }

    func testALiftedCardMeetsTheBandWhereItIsDrawn() {
        var lifts = Array(repeating: CGFloat(0), count: 10)
        lifts[5] = slotBottom(5) - slotBottom(2)
        let band = (slotBottom(2) + 10)...(slotBottom(2) + 50)
        XCTAssertEqual(layout.cards(meeting: band, sizes: sizes, lifts: lifts), IndexSet([2, 5]))
    }
}
