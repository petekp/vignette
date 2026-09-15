import XCTest

final class StackLayoutTests: XCTestCase {
    private var ui: UITweaks {
        var u = UITweaks()
        u.cardMaxWidth = 200; u.cardMaxHeight = 100; u.cardMinSide = 50; u.cardSpacing = 10
        u.panelInset = 20; u.screenMargin = 16; u.selectionBarHeight = 40
        u.annotationScreenInset = 60; u.annotationMinWidth = 480; u.annotationMinHeight = 140
        return u
    }
    private var layout: StackLayout { StackLayout(ui: ui) }
    private let screen = NSRect(x: 0, y: 0, width: 1512, height: 944)

    func testCardSizeFitsTheBoxAndKeepsAMinimumSide() {
        XCTAssertEqual(layout.cardSize(for: NSSize(width: 2000, height: 1000)), NSSize(width: 200, height: 100))
        XCTAssertEqual(layout.cardSize(for: NSSize(width: 1000, height: 100)), NSSize(width: 200, height: 50), "a wide strip keeps the minimum side")
        XCTAssertEqual(layout.cardSize(for: .zero), NSSize(width: 200, height: 100))
    }

    func testColumnHeightAndCardFramesStackUpwardFromTheBottom() {
        let cards = [NSSize(width: 200, height: 100), NSSize(width: 100, height: 50)]
        XCTAssertEqual(layout.contentHeight(cards: cards, showsBar: false), 160)
        XCTAssertEqual(layout.contentHeight(cards: cards, showsBar: true), 210)
        let panel = layout.panelFrame(viewport: 160, visibleFrame: screen)
        XCTAssertEqual(panel, NSRect(x: 1512 - 240 - 16 + 20, y: 16 - 20, width: 240, height: 200))
        let newest = layout.cardFrame(index: 0, cards: cards, panelFrame: panel, showsBar: false, scroll: 0)
        let older = layout.cardFrame(index: 1, cards: cards, panelFrame: panel, showsBar: false, scroll: 0)
        XCTAssertEqual(newest, NSRect(x: panel.maxX - 20 - 200, y: panel.minY + 20, width: 200, height: 100))
        XCTAssertEqual(older.minY, newest.maxY + 10, "the older card sits above the newest")
        XCTAssertEqual(older.maxX, newest.maxX, "cards are right-aligned")
        XCTAssertEqual(layout.cardFrame(index: 0, cards: cards, panelFrame: panel, showsBar: true, scroll: 5).minY, panel.minY + 20 + 50 - 5)
    }

    func testViewportIsCappedByTheScreen() {
        XCTAssertEqual(layout.viewportHeight(content: 100, visibleFrame: screen), 100)
        XCTAssertEqual(layout.viewportHeight(content: 5000, visibleFrame: screen), 944 - 32)
    }

    func testCardIndexFromTheTopOfTheColumn() {
        let cards = [NSSize(width: 200, height: 100), NSSize(width: 100, height: 50)]   // index 1 is on top
        XCTAssertEqual(layout.cardIndex(atYFromTop: 0, cards: cards), 1)
        XCTAssertEqual(layout.cardIndex(atYFromTop: 49, cards: cards), 1)
        XCTAssertNil(layout.cardIndex(atYFromTop: 55, cards: cards), "between cards")
        XCTAssertEqual(layout.cardIndex(atYFromTop: 60, cards: cards), 0)
        XCTAssertNil(layout.cardIndex(atYFromTop: 500, cards: cards))
        XCTAssertEqual(layout.cardSpan(index: 1, cards: cards, showsBar: false).bottom, 110)
    }

    func testAnnotationFrameKeepsAspectAndAvoidsTheStack() {
        let frame = layout.annotationFrame(for: NSSize(width: 1600, height: 800), visibleFrame: screen, avoidRight: 232, below: 60)
        XCTAssertEqual(frame.width / frame.height, 2, accuracy: 0.01)
        XCTAssertLessThanOrEqual(frame.maxX, 1512 - 60 - 232)
        XCTAssertGreaterThanOrEqual(frame.minY, 60 + 60)
        let small = layout.annotationFrame(for: NSSize(width: 100, height: 100), visibleFrame: screen)
        XCTAssertEqual(small.width, 480, "a small crop scales up to the minimum width")
    }
}
