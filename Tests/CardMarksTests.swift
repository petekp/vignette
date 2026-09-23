import AppKit
import SwiftUI
import XCTest

/// A card's marks, drawn the way the stack draws them: over the thumbnail's aspect fill, clipped to
/// its corners, with texts drawn on the card queue and let go with the card.
@MainActor
final class CardMarksTests: XCTestCase {
    /// The card's box in the test window, in points from its top left.
    private static let card = CGRect(x: 100, y: 50, width: 200, height: 200)
    private static let corner: CGFloat = 12
    private var window: NSWindow!

    override func setUp() async throws {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
    }

    override func tearDown() async throws {
        window.close()
    }

    /// A thumbnail of an image of `pixels`, a quarter of its size as a card's is smaller than the
    /// screenshot: light grey, with a black square over `square`, in the image's px.
    private func thumbnail(_ pixels: PixelSize, square: CGRect) throws -> NSImage {
        let width = pixels.width / 4, height = pixels.height / 4
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(gray: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        // The context's y runs up.
        ctx.fill(CGRect(x: square.minX / 4, y: CGFloat(height) - square.maxY / 4, width: square.width / 4, height: square.height / 4))
        return NSImage(cgImage: try XCTUnwrap(ctx.makeImage()), size: NSSize(width: width, height: height))
    }

    /// The card as `CardView` draws it, on blue, one point a pixel in a nominal capture.
    private func show(_ marks: MarkLayers?, over thumbnail: NSImage) {
        let card = Self.card, corner = Self.corner
        let root = ZStack(alignment: .topLeading) {
            Color.blue
            Image(nsImage: thumbnail).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                .frame(width: card.width, height: card.height)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .overlay(DragSource(urls: { [] }, image: thumbnail, onPress: { _ in }, onClick: {}, marks: marks, picture: thumbnail.size, corner: corner))
                .padding(.leading, card.minX)
                .padding(.top, card.minY)
        }
        .frame(width: 400, height: 300, alignment: .topLeading)
        window.contentView = NSHostingView(rootView: root)
    }

    /// The pixel at a point of the card, in sRGB components from 0 to 1.
    private func pixel(_ rep: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let x = Int(Self.card.minX + x), y = Int(Self.card.minY + y)
        guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh, let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return (0, 0, 0) }
        return (color.redComponent, color.greenComponent, color.blueComponent)
    }

    /// The marks' red (`#e03131`), whatever the display's profile did to it.
    private func isRed(_ c: (r: CGFloat, g: CGFloat, b: CGFloat)) -> Bool { c.r > 0.7 && c.g < 0.4 && c.b < 0.4 }
    private func isBlack(_ c: (r: CGFloat, g: CGFloat, b: CGFloat)) -> Bool { max(c.r, c.g, c.b) < 0.1 }
    private func isGrey(_ c: (r: CGFloat, g: CGFloat, b: CGFloat)) -> Bool { min(c.r, c.g, c.b) > 0.8 && max(c.r, c.g, c.b) - min(c.r, c.g, c.b) < 0.03 }

    /// How many pixels in a rect of the card are the marks' red.
    private func red(_ rep: NSBitmapImageRep, x: ClosedRange<Int>, y: ClosedRange<Int>) -> Int {
        y.reduce(0) { sum, row in sum + x.filter { isRed(pixel(rep, CGFloat($0), CGFloat(row))) }.count }
    }

    /// Waits until every text bitmap the marks asked for is drawn and on its layer, or dropped.
    private func settle(_ marks: [MarkLayers]) {
        func contents(_ layer: CALayer?) -> [ObjectIdentifier?] {
            (layer?.sublayers ?? []).flatMap { [$0.contents.map { ObjectIdentifier($0 as AnyObject) }] + contents($0) }
        }
        var last = marks.flatMap { contents($0.layer) }, quiet = 0
        while quiet < 2 {
            MarkLayers.cardQueue.sync {}
            var ran = false
            DispatchQueue.main.async { ran = true }
            while !ran { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01)) }
            let now = marks.flatMap { contents($0.layer) }
            quiet = now == last ? quiet + 1 : 0
            last = now
        }
    }

    /// Marks on an image of `pixels`, placed by `px`, which takes a rect of the card to the image's px
    /// under it, checked against the thumbnail's own black square. `cut` is a rectangle half in the part
    /// the card crops: its edge shows at `inside`, not at `outside`.
    private func checkPlacement(_ pixels: PixelSize, px: (CGRect) -> CGRect, cut: CGRect, inside: CGPoint, outside: CGPoint) throws {
        let square = CGRect(x: 50, y: 50, width: 100, height: 100)
        let drawing = Drawing(key: "/tmp/Screenshot card.png", pixels: pixels, pointScale: 2, marks: [
            Mark(geometry: .rectangle(px(square))),
            // Its top left is the card's, where the rounded corner cuts it.
            Mark(geometry: .rectangle(px(CGRect(x: 0, y: 0, width: 60, height: 60)))),
            // Half of it is in the part of the image the card crops.
            Mark(geometry: .rectangle(px(cut))),
        ])
        let marks = MarkLayers(pixels: pixels, queue: MarkLayers.cardQueue)
        marks.show(drawing, filling: Self.card.size, backingScale: 2, style: .standard, arrowhead: .standard)
        show(marks, over: try thumbnail(pixels, square: px(square)))
        let rep = try window.capture { self.isRed(self.pixel($0, 100, 50)) && self.isBlack(self.pixel($0, 100, 100)) }

        // The thumbnail's square is where the test puts it, so the marks are checked against the picture.
        XCTAssertTrue(isBlack(pixel(rep, 100, 54)), "inside the thumbnail's square: \(pixel(rep, 100, 54))")
        XCTAssertTrue(isGrey(pixel(rep, 100, 45)), "above it: \(pixel(rep, 100, 45))")
        // The square's mark runs along its edges, 3.5 points wide.
        for (x, y) in [(100, 50), (50, 100), (150, 100), (100, 150)] as [(CGFloat, CGFloat)] {
            XCTAssertTrue(isRed(pixel(rep, x, y)), "edge at \(x), \(y): \(pixel(rep, x, y))")
        }
        // The corner mark is cut by the card's rounded corner, and shows along the top edge.
        XCTAssertTrue(isRed(pixel(rep, 30, 0)), "top edge by the corner: \(pixel(rep, 30, 0))")
        XCTAssertFalse(isRed(pixel(rep, 1, 1)), "outside the rounded corner: \(pixel(rep, 1, 1))")
        // The cropped half is not drawn past the card's edge.
        XCTAssertTrue(isRed(pixel(rep, inside.x, inside.y)), "the half in the card: \(pixel(rep, inside.x, inside.y))")
        XCTAssertFalse(isRed(pixel(rep, outside.x, outside.y)), "the half the card crops: \(pixel(rep, outside.x, outside.y))")
    }

    /// The card crops the image's sides: 800 by 400 px in a 200 point square shows px 200 to 600.
    func testMarksLandOnTheirPixelsOfAnImageWiderThanTheCard() throws {
        try checkPlacement(PixelSize(width: 800, height: 400), px: { r in
            CGRect(x: (r.minX + 100) * 2, y: r.minY * 2, width: r.width * 2, height: r.height * 2)
        }, cut: CGRect(x: -50, y: 10, width: 100, height: 30), inside: CGPoint(x: 20, y: 10), outside: CGPoint(x: -20, y: 10))
    }

    /// The card crops the image's top and bottom: 400 by 800 px shows px 200 to 600 down.
    func testMarksLandOnTheirPixelsOfAnImageTallerThanTheCard() throws {
        try checkPlacement(PixelSize(width: 400, height: 800), px: { r in
            CGRect(x: r.minX * 2, y: (r.minY + 100) * 2, width: r.width * 2, height: r.height * 2)
        }, cut: CGRect(x: 10, y: -50, width: 30, height: 100), inside: CGPoint(x: 10, y: 20), outside: CGPoint(x: 10, y: -20))
    }

    /// A text's bitmap drawn for a drawing that has since been written again reaches the main thread
    /// after the new drawing is shown, and is dropped.
    func testACardNeverShowsTheTextOfADrawingThatWasWrittenOver() throws {
        let pixels = PixelSize(width: 800, height: 400)
        func drawing(_ words: String, cardY: CGFloat) -> Drawing {
            Drawing(key: "/tmp/Screenshot card.png", pixels: pixels, pointScale: 2, marks: [
                Mark(id: Self.textID, geometry: .text(Mark.Text(origin: CGPoint(x: 240, y: cardY * 2), text: words, wrap: nil, size: 24))),
            ])
        }
        let marks = MarkLayers(pixels: pixels, queue: MarkLayers.cardQueue)
        show(marks, over: try thumbnail(pixels, square: .zero))
        // The old text's bitmap is drawn and waits on the main queue. The new one is queued only once
        // the old one arrives, and then waits on the suspended card queue.
        marks.show(drawing("Old words", cardY: 20), filling: Self.card.size, backingScale: 2, style: .standard, arrowhead: .standard)
        MarkLayers.cardQueue.sync {}
        MarkLayers.cardQueue.suspend()
        var suspended = true
        defer { if suspended { MarkLayers.cardQueue.resume() } }
        marks.show(drawing("New", cardY: 120), filling: Self.card.size, backingScale: 2, style: .standard, arrowhead: .standard)

        let between = try window.capture { _ in true }
        XCTAssertEqual(red(between, x: 20...100, y: 20...44), 0, "the old drawing's text is dropped")
        XCTAssertEqual(red(between, x: 20...100, y: 120...144), 0, "the new one's is still being drawn")

        MarkLayers.cardQueue.resume()
        suspended = false
        settle([marks])
        let after = try window.capture { self.red($0, x: 20...100, y: 120...144) > 10 }
        XCTAssertGreaterThan(red(after, x: 20...100, y: 120...144), 10)
        XCTAssertEqual(red(after, x: 20...100, y: 20...44), 0)
    }

    private static let textID = UUID()

    /// A drawing read from its file again, as a push or a park writes it, names every mark anew; a card
    /// keeps showing the texts that did not change instead of dropping them until they are drawn again.
    func testATextThatOnlyChangedItsIdKeepsItsBitmap() {
        let pixels = PixelSize(width: 800, height: 400)
        let words = Mark.Geometry.text(Mark.Text(origin: CGPoint(x: 240, y: 40), text: "Kept", wrap: nil, size: 24))
        let marks = MarkLayers(pixels: pixels, queue: MarkLayers.cardQueue)
        marks.show(Drawing(key: "/tmp/Screenshot card.png", pixels: pixels, pointScale: 2, marks: [Mark(geometry: words)]),
                   filling: Self.card.size, backingScale: 2, style: .standard, arrowhead: .standard)
        settle([marks])
        let drawn = marks.bitmapPixels
        XCTAssertGreaterThan(drawn, 0)

        MarkLayers.cardQueue.suspend()
        defer { MarkLayers.cardQueue.resume() }
        let again = Drawing(key: "/tmp/Screenshot card.png", pixels: pixels, pointScale: 2,
                            marks: [Mark(geometry: words), Mark(geometry: .text(Mark.Text(origin: CGPoint(x: 240, y: 240), text: "New", wrap: nil, size: 24)))])
        marks.show(again, filling: Self.card.size, backingScale: 2, style: .standard, arrowhead: .standard)
        XCTAssertEqual(marks.bitmapPixels, drawn, "the unchanged text is on screen while the new one is drawn")
        XCTAssertTrue(marks.isDrawn(again.marks[0].id))
        XCTAssertFalse(marks.isDrawn(again.marks[1].id))
    }

    /// Words over the whole of a Retina screenshot and past its bottom, wrapped at its edge.
    private func longText(_ pixels: PixelSize) -> Drawing {
        let words = Array(repeating: "A long sentence an agent wrote across the picture.", count: 90).joined(separator: " ")
        return Drawing(key: "/tmp/Screenshot card.png", pixels: pixels, pointScale: 2, marks: [
            Mark(geometry: .text(Mark.Text(origin: CGPoint(x: 20, y: 20), text: words, wrap: nil, size: 24))),
        ])
    }

    func testACardsTextBitmapHasNoMorePixelsThanTheCard() {
        let pixels = PixelSize(width: 3024, height: 1964)
        let marks = MarkLayers(pixels: pixels, queue: MarkLayers.cardQueue)
        let card = CGSize(width: 200, height: 130)
        marks.show(longText(pixels), filling: card, backingScale: 2, style: .standard, arrowhead: .standard)
        settle([marks])
        XCTAssertGreaterThan(marks.bitmapPixels, 0)
        // The card's own device pixels, and the one at each side a bitmap grows by to meet whole pixels.
        XCTAssertLessThanOrEqual(marks.bitmapPixels, Int((card.width * 2 + 2) * (card.height * 2 + 2)))
    }

    /// Hiding the stack takes every card out of the column this way.
    func testCardsTakenOutOfTheColumnLetTheirBitmapsGoAndTheDrawsOnTheirWay() {
        let pixels = PixelSize(width: 3024, height: 1964)
        let model = StackModel()
        let marks = [MarkLayers(pixels: pixels, queue: MarkLayers.cardQueue), MarkLayers(pixels: pixels, queue: MarkLayers.cardQueue)]
        model.cards = marks.enumerated().map { i, marks in
            Card(id: UUID(), shot: Screenshot(url: URL(fileURLWithPath: "/tmp/shot \(i).png")), image: nil,
                 pointSize: NSSize(width: 200, height: 130), size: NSSize(width: 200, height: 130), agent: nil, marks: marks)
        }
        marks[0].show(longText(pixels), filling: CGSize(width: 200, height: 130), backingScale: 2, style: .standard, arrowhead: .standard)
        settle(marks)
        XCTAssertGreaterThan(marks[0].bitmapPixels, 0)

        MarkLayers.cardQueue.suspend()
        var suspended = true
        defer { if suspended { MarkLayers.cardQueue.resume() } }
        marks[1].show(longText(pixels), filling: CGSize(width: 200, height: 130), backingScale: 2, style: .standard, arrowhead: .standard)
        model.removeCards { _ in true }
        MarkLayers.cardQueue.resume()
        suspended = false
        settle(marks)

        XCTAssertTrue(model.cards.isEmpty)
        XCTAssertEqual(marks.map(\.bitmapPixels), [0, 0], "neither card keeps a bitmap, the one drawn or the one that was on its way")
        XCTAssertEqual(marks.map { $0.layer.sublayers?.count ?? 0 }, [0, 0])
    }
}
