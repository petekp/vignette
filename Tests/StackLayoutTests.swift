import XCTest

final class StackLayoutTests: XCTestCase {
    private var ui: UITweaks {
        var u = UITweaks()
        u.cardMaxWidth = 200; u.cardMaxHeight = 100; u.cardMinSide = 50; u.cardSpacing = 10
        u.panelInset = 20; u.screenMargin = 16; u.selectionBarHeight = 40
        // The inset is at least the card's shadow plus a fade, so these decide it too: 4 + 4*2 + 7
        // is 19, under the 20 below, which is what the frames in these tests are written against.
        u.cardShadowY = 4; u.cardShadowRadius = 4
        u.annotationScreenInset = 60; u.annotationMinWidth = 480; u.annotationMinHeight = 140
        u.stackMinScale = 0.5; u.stackGap = 20
        return u
    }
    private var layout: StackLayout { StackLayout(ui: ui) }
    private let screen = NSRect(x: 0, y: 0, width: 1512, height: 944)

    func testCardSizeFitsTheBoxAndKeepsAMinimumSide() {
        XCTAssertEqual(layout.cardSize(for: NSSize(width: 2000, height: 1000)), NSSize(width: 200, height: 100))
        XCTAssertEqual(layout.cardSize(for: NSSize(width: 1000, height: 100)), NSSize(width: 200, height: 50), "a wide strip keeps the minimum side")
        XCTAssertEqual(layout.cardSize(for: .zero), NSSize(width: 200, height: 100))
    }

    func testAShadowBiggerThanTheInsetWidensThePanelInsteadOfBeingCutOff() {
        var big = ui
        big.cardShadowY = 10; big.cardShadowRadius = 8   // room 26, past the 20 pt inset
        let layout = StackLayout(ui: big)
        XCTAssertEqual(layout.cardShadowRoom, 26)
        XCTAssertEqual(layout.inset, 26 + StackLayout.shadowFade, "the panel makes room rather than clipping the shadow")
        XCTAssertGreaterThanOrEqual(layout.inset - layout.cardShadowRoom, StackLayout.shadowFade,
                                    "the column always keeps a soft edge below the shadow")
        // The cards stay where they are: the panel grows around them.
        let cards = [NSSize(width: 200, height: 100)]
        let panel = layout.panelFrame(viewport: 100, visibleFrame: screen, showsStrip: false)
        let card = layout.cardFrame(index: 0, cards: cards, panelFrame: panel, showsBar: false, scroll: 0)
        XCTAssertEqual(card.maxX, screen.maxX - big.screenMargin)
        XCTAssertEqual(card.minY, screen.minY + big.screenMargin)
    }

    func testColumnHeightAndCardFramesStackUpwardFromTheBottom() {
        let cards = [NSSize(width: 200, height: 100), NSSize(width: 100, height: 50)]
        XCTAssertEqual(layout.contentHeight(cards: cards, showsBar: false), 160)
        XCTAssertEqual(layout.contentHeight(cards: cards, showsBar: true), 210)
        let panel = layout.panelFrame(viewport: 160, visibleFrame: screen, showsStrip: false)
        XCTAssertEqual(panel, NSRect(x: 1512 - 240 - 16 + 20, y: 16 - 20, width: 240, height: 200))
        let wide = layout.panelFrame(viewport: 160, visibleFrame: screen, showsStrip: true)
        XCTAssertEqual(wide.width, 240 + layout.stripWidth + layout.stripGap, "the strip widens the panel")
        XCTAssertEqual(wide.maxX, panel.maxX, "the right edge stays put, so the cards do not move")
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

    func testDragSelectScrollsOnlyInTheBandsAtTheEndsOfTheColumn() {
        var u = ui
        u.autoScrollZone = 40; u.autoScrollSpeed = 600
        let layout = StackLayout(ui: u)
        func speed(_ y: CGFloat, viewport: CGFloat = 400) -> CGFloat { layout.autoScrollSpeed(fromTop: y, viewport: viewport) }
        XCTAssertEqual(speed(200), 0, "the middle of the column does not scroll")
        XCTAssertEqual(speed(40), 0, "just inside the band's edge")
        XCTAssertEqual(speed(360), 0)
        XCTAssertEqual(speed(20), 300, "halfway into the top band, half speed; older cards come down")
        XCTAssertEqual(speed(0), 600, "at the top edge, full speed")
        XCTAssertEqual(speed(-100), 600, "past the edge is still full speed, not more")
        XCTAssertEqual(speed(380), -300, "the bottom band goes the other way")
        XCTAssertEqual(speed(500), -600)
        XCTAssertEqual(speed(100, viewport: 100), -600, "a column shorter than two bands still has both")
        XCTAssertEqual(speed(50, viewport: 100), 0, "and they meet in the middle instead of overlapping")
        var off = u
        off.autoScrollZone = 0
        XCTAssertEqual(StackLayout(ui: off).autoScrollSpeed(fromTop: 0, viewport: 400), 0, "no band, no scrolling")
    }

    /// buttonSize 30 and buttonSpacing 5 make a 40-wide strip; two rows are 75 tall.
    private var stripLayout: StackLayout {
        var u = ui
        u.buttonSize = 30; u.buttonSpacing = 5; u.selectionStripGap = 10
        return StackLayout(ui: u)
    }
    private let stripCards = [NSSize(width: 200, height: 100), NSSize(width: 100, height: 50)]   // index 1 on top

    func testSelectionStripCentersOnTheSelectedCardsAndHugsTheWidestOfThem() {
        let layout = stripLayout
        func strip(_ selection: [Int], showsBar: Bool = false) -> StackLayout.StripPlacement? {
            layout.stripPlacement(rows: 2, selection: selection, cards: stripCards, showsBar: showsBar, scroll: 0, viewport: 160)
        }
        XCTAssertNil(strip([]), "nothing selected, no strip")
        XCTAssertNil(strip([7]), "an index that is not a card is ignored")
        XCTAssertEqual(strip([0])?.size, NSSize(width: 40, height: 75))
        XCTAssertEqual(strip([0])?.bottom, 12.5, "centered on the newest card, which spans 0 to 100")
        XCTAssertEqual(strip([0])?.right, 210, "clear of the 200-wide card by the gap")
        XCTAssertEqual(strip([0, 1])?.bottom, 42.5, "centered on the span from 0 to 160")
        XCTAssertEqual(strip([1])?.right, 110, "a narrower card brings the strip closer")
        XCTAssertEqual(strip([0], showsBar: true)?.bottom, 62.5, "the toast row lifts the column and the strip with it")
    }

    func testSelectionStripStaysInsideTheVisibleColumn() {
        let layout = stripLayout
        func bottom(scroll: CGFloat, viewport: CGFloat) -> CGFloat? {
            layout.stripPlacement(rows: 2, selection: [1], cards: stripCards, showsBar: false, scroll: scroll, viewport: viewport)?.bottom
        }
        XCTAssertEqual(bottom(scroll: 0, viewport: 160), 85, "the top card's center would push the strip past the column top")
        XCTAssertEqual(bottom(scroll: 0, viewport: 100), 25, "clamped to what is on screen")
        XCTAssertEqual(bottom(scroll: 60, viewport: 100), 85, "scrolled, the visible band moves with it")
        XCTAssertEqual(bottom(scroll: 0, viewport: 50), -12.5, "a strip taller than the column centers on it")
    }

    func testSelectionStripFrameSitsLeftOfTheSelectedCard() {
        let layout = stripLayout
        let panel = layout.panelFrame(viewport: 160, visibleFrame: screen, showsStrip: true)
        let strip = layout.stripPlacement(rows: 2, selection: [0], cards: stripCards, showsBar: false, scroll: 0, viewport: 160)!
        let frame = layout.stripFrame(strip, panelFrame: panel, scroll: 0)
        let card = layout.cardFrame(index: 0, cards: stripCards, panelFrame: panel, showsBar: false, scroll: 0)
        XCTAssertEqual(frame.maxX, card.minX - layout.stripGap, "the gap separates the strip from the card")
        XCTAssertEqual(frame.midY, card.midY, "and it is centered on the card")
        XCTAssertGreaterThanOrEqual(frame.minX, panel.minX, "inside the panel")
    }

    func testTheStripGrowsToTheLeftWhenItsLabelsComeOut() {
        let layout = stripLayout
        let labels = ["Copy", "Copy Annotated"]
        let reveal = layout.stripReveal(labels: labels)
        XCTAssertGreaterThan(reveal, ButtonLabel.width("Copy Annotated", size: StackLayout.stripLabelSize),
                             "the widest label, and room beside it")
        XCTAssertEqual(layout.stripReveal(labels: []), 0, "no labels, no growth")
        let panel = layout.panelFrame(viewport: 160, visibleFrame: screen, showsStrip: true, reveal: reveal)
        let strip = layout.stripPlacement(rows: 2, selection: [0], cards: stripCards, showsBar: false, scroll: 0, viewport: 160)!
        let rest = layout.stripFrame(strip, panelFrame: panel, scroll: 0)
        let grown = layout.stripFrame(strip, panelFrame: panel, scroll: 0, reveal: reveal)
        XCTAssertEqual(grown.maxX, rest.maxX, "the right edge does not move")
        XCTAssertEqual(grown.minX, rest.minX - reveal, "the icons travel left with the labels")
        XCTAssertEqual(grown.width, rest.width + reveal)
        let card = layout.cardFrame(index: 0, cards: stripCards, panelFrame: panel, showsBar: false, scroll: 0)
        XCTAssertLessThanOrEqual(grown.maxX, card.minX - layout.stripGap, "the labels never reach a card")
        XCTAssertGreaterThanOrEqual(grown.minX, panel.minX, "and the grown strip stays inside the panel")
    }

    func testThePanelHoldsTheRevealSoTheLabelsNeverResizeIt() {
        let layout = stripLayout
        let reveal = layout.stripReveal(labels: ["Copy", "Copy Annotated"])
        let panel = layout.panelFrame(viewport: 160, visibleFrame: screen, showsStrip: true, reveal: reveal)
        let plain = layout.panelFrame(viewport: 160, visibleFrame: screen, showsStrip: true)
        XCTAssertEqual(panel.width, plain.width + reveal, "the room is there before the labels come out")
        XCTAssertEqual(panel.maxX, plain.maxX, "and it is added on the left, so the cards do not move")
        // The widest selected card pushes the strip furthest left; it still has the room.
        let strip = layout.stripPlacement(rows: 2, selection: [0], cards: stripCards, showsBar: false, scroll: 0, viewport: 160)!
        let grown = layout.stripFrame(strip, panelFrame: panel, scroll: 0, reveal: reveal)
        XCTAssertGreaterThanOrEqual(grown.minX, panel.minX)
    }

    func testAnnotationFrameKeepsAspectAndCentersInTheRectItIsGiven() {
        let frame = layout.annotationFrame(for: NSSize(width: 1600, height: 800), visibleFrame: screen, below: 60)
        XCTAssertEqual(frame.width / frame.height, 2, accuracy: 0.01)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 1, "centered in the rect it is given")
        XCTAssertLessThanOrEqual(frame.maxX, 1512 - 60)
        XCTAssertGreaterThanOrEqual(frame.minY, 60 + 60)
        let small = layout.annotationFrame(for: NSSize(width: 100, height: 100), visibleFrame: screen)
        XCTAssertEqual(small.width, 480, "a small crop scales up to the minimum width")
    }

    func testTheAnnotatorsRoomLeavesTheStackItsNarrowestWidth() {
        let room = layout.annotatorRoom(visibleFrame: screen)
        XCTAssertEqual(room.maxX, screen.maxX - 16 - 100 - 20, "the margin, the stack at half width, and the gap")
        XCTAssertEqual(room.minX, screen.minX)
        XCTAssertEqual(room.height, screen.height, "only the right edge moves")
        // A frame filling the room leaves the narrowest stack exactly a gap of clear screen.
        let narrowest = StackLayout(ui: ui, widthScale: layout.minWidthScale)
        let panel = narrowest.panelFrame(viewport: 100, visibleFrame: screen, showsStrip: false)
        let card = narrowest.cardFrame(index: 0, cards: [narrowest.drawn(NSSize(width: 200, height: 100))],
                                       panelFrame: panel, showsBar: false, scroll: 0)
        XCTAssertEqual(card.minX, room.maxX + 20, accuracy: 0.001)
        XCTAssertEqual(card.size, NSSize(width: 100, height: 50), "a card at half width")
        XCTAssertEqual(card.maxX, screen.maxX - 16, "the cards keep their right edge, whatever the width")
    }

    func testTheStackIsAsWideAsTheAnnotatorsFrameLeavesIt() {
        func scale(frameMaxX: CGFloat) -> CGFloat {
            layout.widthScale(clearing: NSRect(x: 0, y: 100, width: frameMaxX, height: 400), visibleFrame: screen)
        }
        XCTAssertEqual(scale(frameMaxX: 1000), 1, "a frame that is nowhere near leaves the stack at its full width")
        XCTAssertEqual(scale(frameMaxX: layout.annotatorRoom(visibleFrame: screen).maxX), 0.5, "at the edge of the room, the narrowest")
        XCTAssertEqual(scale(frameMaxX: 2000), 0.5, "and never narrower, whatever is beside it")
        XCTAssertEqual(scale(frameMaxX: 1300), 0.88, accuracy: 0.0001)
        // In between, the column's left edge sits exactly a gap from the frame.
        let narrowed = StackLayout(ui: ui, widthScale: scale(frameMaxX: 1300))
        let panel = narrowed.panelFrame(viewport: 100, visibleFrame: screen, showsStrip: false)
        let card = narrowed.cardFrame(index: 0, cards: [narrowed.drawn(NSSize(width: 200, height: 100))],
                                      panelFrame: panel, showsBar: false, scroll: 0)
        XCTAssertEqual(card.minX, 1300 + 20, accuracy: 0.001)
    }

    func testThePanelIsSizedForTheStackAtItsFullWidth() {
        let narrowed = StackLayout(ui: ui, widthScale: 0.5)
        XCTAssertEqual(narrowed.panelSize(viewport: 100, showsStrip: false),
                       layout.panelSize(viewport: 100, showsStrip: false),
                       "so a stack that narrows for the annotator does not resize its panel")
        XCTAssertEqual(narrowed.columnWidth, 100, "only the column inside it narrows")
        XCTAssertEqual(narrowed.cardSize(for: NSSize(width: 2000, height: 1000)), NSSize(width: 200, height: 100),
                       "a card is measured at rest, so narrowing and coming back does not re-measure it")
    }
}
