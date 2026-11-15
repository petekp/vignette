import XCTest

extension StackLayoutTests {
    func testAnnotationFrameKeepsAspectAndCentersInTheRectItIsGiven() {
        let frame = layout.annotationFrame(for: NSSize(width: 1600, height: 800), visibleFrame: screen, below: 60)
        XCTAssertEqual(frame.width / frame.height, 2, accuracy: 0.01)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 1, "centered in the rect it is given")
        XCTAssertLessThanOrEqual(frame.maxX, 1512 - 60)
        XCTAssertGreaterThanOrEqual(frame.minY, 60 + 60)
        let small = layout.annotationFrame(for: NSSize(width: 100, height: 100), visibleFrame: screen)
        XCTAssertEqual(small.width, 480, "a small crop scales up to the minimum width")
    }

    func testAnAgentsTitleTakesRoomAboveTheFrame() {
        let wide = NSSize(width: 1600, height: 800), tall = NSSize(width: 800, height: 1600)
        for image in [wide, tall] {
            XCTAssertEqual(layout.annotationFrame(for: image, visibleFrame: screen, below: 60) { _ in 0 },
                           layout.annotationFrame(for: image, visibleFrame: screen, below: 60))
        }
        let untitled = layout.annotationFrame(for: tall, visibleFrame: screen, below: 60)
        let lines = { (width: CGFloat) -> CGFloat in width < 380 ? 90 : 60 }
        let titled = layout.annotationFrame(for: tall, visibleFrame: screen, below: 60, above: lines)
        XCTAssertLessThan(titled.height, untitled.height)
        XCTAssertLessThan(titled.width, 380)
        XCTAssertLessThanOrEqual(titled.maxY + lines(titled.width), screen.maxY - 60)
        XCTAssertGreaterThanOrEqual(titled.minY, 60 + 60)

        var minimum = ui
        minimum.agentTitleMinWidth = 400
        let floored = StackLayout(ui: minimum).annotationFrame(for: tall, visibleFrame: screen, below: 60, above: lines)
        XCTAssertGreaterThan(floored.height, titled.height)

        let roomy = layout.annotationFrame(for: wide, visibleFrame: screen, below: 60) { _ in 40 }
        let plain = layout.annotationFrame(for: wide, visibleFrame: screen, below: 60)
        XCTAssertEqual(roomy.size, plain.size)
        XCTAssertEqual(roomy.midY, plain.midY - 20, accuracy: 1)
    }

    func testATitleWrapsAtTheFramesRightEdgeNoNarrowerThanItsMinimumAndNoFurtherThanTheRoom() {
        let room = NSRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertEqual(StackLayout.titleWrapWidth(frame: NSRect(x: 100, y: 0, width: 600, height: 400), room: room, minimum: 300, indent: 16), 584)
        XCTAssertEqual(StackLayout.titleWrapWidth(frame: NSRect(x: 400, y: 0, width: 200, height: 400), room: room, minimum: 300, indent: 16), 300)
        XCTAssertEqual(StackLayout.titleWrapWidth(frame: NSRect(x: 800, y: 0, width: 150, height: 400), room: room, minimum: 300, indent: 16), 184)
    }

    func testTheAnnotatorsRoomLeavesTheStackItsNarrowestWidth() {
        let room = layout.annotatorRoom(visibleFrame: screen)
        XCTAssertEqual(room.maxX, screen.maxX - 16 - 100 - 20, "the margin, the stack at half width, and the gap")
        XCTAssertEqual(room.minX, screen.minX)
        XCTAssertEqual(room.height, screen.height, "only the right edge moves")
        // A frame filling the room leaves the narrowest stack exactly a gap of clear screen.
        let narrowest = StackLayout(ui: ui, widthScale: layout.minWidthScale)
        let panel = narrowest.panelFrame(viewport: 100, area: area, showsStrip: false)
        let card = narrowest.cardFrame(index: 0, cards: [narrowest.drawn(NSSize(width: 200, height: 100))],
                                       panelFrame: panel, scroll: 0, safeBottom: 0)
        XCTAssertEqual(card.minX, room.maxX + 20, accuracy: 0.001)
        XCTAssertEqual(card.size, NSSize(width: 100, height: 50), "a card at half width")
        XCTAssertEqual(card.maxX, screen.maxX - 16, "the cards keep their right edge, whatever the width")
    }

    func testWhileACardIsInTheAnnotatorTheStackCatchesNoPressInsideTheFramesRoom() {
        var u = ui
        u.annotationToolbarGap = 9
        let narrowest = StackLayout(ui: u, widthScale: 0.5)
        let room = StackLayout(ui: u).annotatorRoom(visibleFrame: screen)
        let columnLeft = screen.maxX - narrowest.margin - narrowest.columnWidth
        XCTAssertEqual(columnLeft - narrowest.catchReach(annotating: true), room.maxX)
        XCTAssertEqual(columnLeft - narrowest.catchReach(annotating: false), columnLeft - 20,
                       "with no image open, a press just beside a card still reaches the stack")
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
        let panel = narrowed.panelFrame(viewport: 100, area: area, showsStrip: false)
        let card = narrowed.cardFrame(index: 0, cards: [narrowed.drawn(NSSize(width: 200, height: 100))],
                                      panelFrame: panel, scroll: 0, safeBottom: 0)
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
