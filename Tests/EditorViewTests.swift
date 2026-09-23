import AppKit
import XCTest

/// The editor view driven with real events in an offscreen window: what reaches the core, what the
/// host hears, and what lands on a private pasteboard. Keys go through the window, so they reach
/// whichever view has them; presses go to the view, since a window that is not on screen drops them.
@MainActor
final class EditorViewTests: XCTestCase {
    private static let pixels = PixelSize(width: 1000, height: 600)
    private var window: NSWindow!
    private var view: EditorView!
    private var pasteboard: NSPasteboard!
    /// What the host heard, in order.
    private var heard: [String] = []
    private var handedOver: [Drawing] = []
    private var time: TimeInterval = 0

    override func setUp() async throws {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("com.petepetrash.vignette.tests.\(UUID().uuidString)"))
        view = EditorView(pasteboard: pasteboard)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        heard = []
        handedOver = []
        view.onTool = { [unowned self] tool in heard.append("tool \(tool.rawValue)") }
        view.onClose = { [unowned self] in heard.append("close") }
        view.onToast = { [unowned self] words in heard.append("toast \(words)") }
        view.onHandOver = { [unowned self] drawing in handedOver.append(drawing) }
    }

    override func tearDown() async throws {
        // Parking stops the view's timers, so nothing fires into a later test.
        _ = view.park()
        pasteboard.releaseGlobally()
        window.close()
    }

    private func open(_ marks: [Mark] = []) {
        let ctx = CGContext(data: nil, width: 100, height: 60, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 60))
        view.open(Drawing(key: "/tmp/Screenshot test.png", pixels: Self.pixels, pointScale: 1, marks: marks), image: ctx.makeImage()!,
                  picture: CGRect(x: 0, y: 0, width: 1000, height: 600), style: .standard, metrics: .standard, arrowhead: .standard,
                  pickColor: { _ in nil })
    }

    // MARK: Events

    /// A press, drag or release at a point in the view, sent to the view as the window would.
    private func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat, _ flags: NSEvent.ModifierFlags = [], clicks: Int = 1) {
        time += 0.05
        let event = NSEvent.mouseEvent(with: type, location: view.convert(CGPoint(x: x, y: y), to: nil), modifierFlags: flags, timestamp: time,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        switch type {
        case .leftMouseDown: view.mouseDown(with: event)
        case .leftMouseDragged: view.mouseDragged(with: event)
        case .leftMouseUp: view.mouseUp(with: event)
        default: XCTFail("not a press, drag or release")
        }
    }

    private func drag(from: (CGFloat, CGFloat), to: (CGFloat, CGFloat)) {
        mouse(.leftMouseDown, from.0, from.1)
        mouse(.leftMouseDragged, (from.0 + to.0) / 2, (from.1 + to.1) / 2)
        mouse(.leftMouseDragged, to.0, to.1)
        mouse(.leftMouseUp, to.0, to.1)
    }

    private func keyEvent(_ characters: String, _ keyCode: UInt16, _ flags: NSEvent.ModifierFlags = [], type: NSEvent.EventType = .keyDown) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: time, windowNumber: window.windowNumber, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }

    /// A key through the window, to whichever view has the keys.
    private func key(_ characters: String, _ keyCode: UInt16, _ flags: NSEvent.ModifierFlags = []) {
        window.sendEvent(keyEvent(characters, keyCode, flags))
        window.sendEvent(keyEvent(characters, keyCode, flags, type: .keyUp))
    }

    private func type(_ words: String) {
        for character in words { key(String(character), 0) }
    }

    private var textView: EditorTextView? { view.subviews.compactMap { $0 as? EditorTextView }.first }

    private func frame(_ mark: Mark?) -> CGRect? {
        if case .rectangle(let frame)? = mark?.geometry { return frame }
        return nil
    }

    private func text(_ mark: Mark?) -> Mark.Text? {
        if case .text(let text)? = mark?.geometry { return text }
        return nil
    }

    // MARK: Drawing

    func testADragMakesARectangleFromThePressToTheReleaseInImagePxAtZoomOneAndTwo() {
        open()
        XCTAssertEqual(view.pictureRect, CGRect(x: 0, y: 0, width: 1000, height: 600), "the picture opens fitted to the view")
        drag(from: (100, 100), to: (300, 250))
        XCTAssertEqual(frame(view.core.drawing.marks.last), CGRect(x: 100, y: 100, width: 200, height: 150))

        // Twice as close, with the image's px (500, 300) at the view's top-left corner.
        view.pictureRect = CGRect(x: -1000, y: -600, width: 2000, height: 1200)
        XCTAssertEqual(view.core.zoom, 2)
        drag(from: (100, 100), to: (300, 260))
        XCTAssertEqual(view.core.drawing.marks.count, 2)
        XCTAssertEqual(frame(view.core.drawing.marks.last), CGRect(x: 550, y: 350, width: 100, height: 80))
        XCTAssertEqual(view.viewPoint(forImagePoint: CGPoint(x: 550, y: 350)), CGPoint(x: 100, y: 100))
    }

    func testAModifierPressedMidDragWithNoMoveChangesTheRectangleAtOnce() {
        open()
        mouse(.leftMouseDown, 100, 100)
        mouse(.leftMouseDragged, 200, 150)
        XCTAssertEqual(frame(view.core.drawing.marks.last), CGRect(x: 100, y: 100, width: 100, height: 50))
        window.sendEvent(keyEvent("", 56, .shift, type: .flagsChanged))
        XCTAssertEqual(frame(view.core.drawing.marks.last), CGRect(x: 100, y: 100, width: 100, height: 100), "Shift makes a square at once")
        window.sendEvent(keyEvent("", 56, [], type: .flagsChanged))
        XCTAssertEqual(frame(view.core.drawing.marks.last), CGRect(x: 100, y: 100, width: 100, height: 50))
        mouse(.leftMouseUp, 200, 150)
        XCTAssertEqual(view.core.drawing.marks.count, 1)
    }

    func testAToolKeySelectsTheToolAndTellsTheHost() {
        open()
        XCTAssertEqual(heard, ["tool rectangle"])
        key("a", 0)
        XCTAssertEqual(view.core.tool, .arrow)
        key("V", 9, .shift)
        XCTAssertEqual(view.core.tool, .select)
        XCTAssertEqual(heard, ["tool rectangle", "tool arrow", "tool select"])
    }

    func testEscWithNothingGoingOnAsksTheHostToClose() {
        open()
        mouse(.leftMouseDown, 100, 100)
        mouse(.leftMouseDragged, 300, 300)
        key("\u{1b}", 53)
        XCTAssertTrue(view.core.drawing.marks.isEmpty, "Esc during a drag cancels it")
        XCTAssertEqual(heard.filter { $0 == "close" }.count, 0)
        mouse(.leftMouseUp, 300, 300)
        key("\u{1b}", 53)
        XCTAssertEqual(heard.last, "close")
    }

    func testParkAnswersAtOnceWithTheDrawingAndIgnoresInputAfterwards() {
        open()
        drag(from: (100, 100), to: (300, 250))
        mouse(.leftMouseDown, 500, 300)
        mouse(.leftMouseDragged, 600, 400)
        let parked = view.park()
        XCTAssertEqual(parked?.marks.compactMap(frame), [CGRect(x: 100, y: 100, width: 200, height: 150), CGRect(x: 500, y: 300, width: 100, height: 100)],
                       "a drag in progress is kept as drawn")
        XCTAssertEqual(parked?.key, "/tmp/Screenshot test.png")
        XCTAssertTrue(handedOver.isEmpty, "park answers with the drawing, not through the hand-over")
        drag(from: (700, 100), to: (800, 200))
        XCTAssertEqual(view.core.drawing.marks.count, 2)
        XCTAssertNil(view.park())
    }

    // MARK: Typing

    func testATextClickTypesInATextViewAtTheBoxAndReturnKeepsTheText() throws {
        open()
        key("t", 17)
        mouse(.leftMouseDown, 200, 300)
        mouse(.leftMouseUp, 200, 300)
        let field = try XCTUnwrap(textView)
        XCTAssertTrue(window.firstResponder === field, "the text view has the keys")
        let box = try XCTUnwrap(view.core.typingBox)
        let origin = field.convert(field.textContainerOrigin, to: view)
        XCTAssertEqual(origin.x, view.viewPoint(forImagePoint: box.origin).x, accuracy: 1e-9)
        XCTAssertEqual(origin.y, view.viewPoint(forImagePoint: box.origin).y, accuracy: 1e-9)

        type("vrat \"quoted\" -- x")
        XCTAssertEqual(field.string, "vrat \"quoted\" -- x", "tool keys type, and nothing is replaced")
        XCTAssertEqual(text(view.core.drawing.marks.last)?.text, "vrat \"quoted\" -- x")
        XCTAssertEqual(view.core.tool, .text)

        key("\r", 36, .shift)
        type("two")
        XCTAssertEqual(text(view.core.drawing.marks.last)?.text, "vrat \"quoted\" -- x\ntwo", "Shift+Return is a new line")

        key("\r", 36)
        XCTAssertNil(view.core.typing)
        XCTAssertTrue(window.firstResponder === view)
        settleTexts()
        XCTAssertNil(textView, "the text view is gone once the text's bitmap is on screen")
        XCTAssertEqual(text(view.core.drawing.marks.last)?.text, "vrat \"quoted\" -- x\ntwo")
        XCTAssertEqual(view.core.selection, [view.core.drawing.marks[0].id])
    }

    func testTheTypedWordsSitOnTheBaselineTheDrawingUsesAtZoomOneAndTwo() throws {
        open()
        for zoom in [CGFloat(1), 2] {
            view.pictureRect = CGRect(x: 0, y: 0, width: 1000 * zoom, height: 600 * zoom)
            key("t", 17)
            mouse(.leftMouseDown, 150, 120 + 60 * zoom)
            mouse(.leftMouseUp, 150, 120 + 60 * zoom)
            type("Baseline 基线 🎉")
            let field = try XCTUnwrap(textView)
            let layoutManager = try XCTUnwrap(field.layoutManager)
            layoutManager.ensureLayout(for: try XCTUnwrap(field.textContainer))
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
            let glyph = layoutManager.location(forGlyphAt: 0)
            let typed = field.convert(CGPoint(x: field.textContainerOrigin.x + fragment.minX + glyph.x,
                                              y: field.textContainerOrigin.y + fragment.minY + glyph.y), to: view)
            let mark = try XCTUnwrap(text(view.core.mark(try XCTUnwrap(view.core.typing?.id))))
            let layout = TextLayout(mark, imageWidth: 1000, pointScale: 1, style: .standard)
            let drawn = view.viewPoint(forImagePoint: CGPoint(x: layout.lines[0].rect.minX, y: layout.lines[0].baseline))
            XCTAssertEqual(typed.y, drawn.y, accuracy: 0.5, "zoom \(zoom)")
            XCTAssertEqual(typed.x, drawn.x, accuracy: 0.5, "zoom \(zoom)")
            key("\r", 36)
        }
    }

    // MARK: What is drawn

    /// The window server's picture of the test window; see `NSWindow.capture`.
    private func capture(nominal: Bool = true, until ready: (NSBitmapImageRep) -> Bool) throws -> NSBitmapImageRep {
        try window.capture(nominal: nominal, until: ready)
    }

    /// The pixel at a point of the view, in sRGB components from 0 to 1.
    private func pixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh, let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return (0, 0, 0) }
        return (color.redComponent, color.greenComponent, color.blueComponent)
    }

    /// The marks' red (`#e03131`), whatever the display's profile did to it.
    private func isRed(_ c: (r: CGFloat, g: CGFloat, b: CGFloat)) -> Bool { c.r > 0.7 && c.g < 0.4 && c.b < 0.4 }
    /// The test screenshot's light grey, whatever the display's profile did to it.
    private func isBackground(_ c: (r: CGFloat, g: CGFloat, b: CGFloat)) -> Bool {
        min(c.r, c.g, c.b) > 0.8 && max(c.r, c.g, c.b) - min(c.r, c.g, c.b) < 0.03
    }

    func testMarksAreDrawnWhereTheDrawingPutsThemRightWayUp() throws {
        open([Mark(geometry: .rectangle(CGRect(x: 100, y: 60, width: 300, height: 150))),
              Mark(geometry: .arrow(Mark.Arrow(start: CGPoint(x: 600, y: 100), end: CGPoint(x: 900, y: 100)))),
              Mark(geometry: .text(Mark.Text(origin: CGPoint(x: 600, y: 400), text: "Top", wrap: nil, size: 24)))])
        settleTexts()
        let rep = try capture { self.isBackground(self.pixel($0, 500, 300)) }
        XCTAssertEqual(view.pictureRect, CGRect(x: 0, y: 0, width: 1000, height: 600), "one point a px, so the capture's pixels are the drawing's")

        // The rectangle's top edge is 60 px down; upside down it would be 540 px down.
        XCTAssertTrue(isRed(pixel(rep, 250, 60)), "top edge: \(pixel(rep, 250, 60))")
        XCTAssertTrue(isRed(pixel(rep, 100, 135)), "left edge: \(pixel(rep, 100, 135))")
        XCTAssertTrue(isBackground(pixel(rep, 250, 540)), "nothing where a mirrored top edge would be")
        XCTAssertTrue(isBackground(pixel(rep, 250, 135)), "the inside is not filled")
        // The arrowhead is at the right end, the end the arrow was drawn to.
        XCTAssertTrue(isRed(pixel(rep, 894, 100)), "arrowhead: \(pixel(rep, 894, 100))")
        XCTAssertTrue(isBackground(pixel(rep, 894, 500)))
        // The text's letters are in its first line, 400 to about 430 px down, and not mirrored.
        XCTAssertGreaterThan(red(rep, x: 600...660, y: 400...432), 20)
        XCTAssertEqual(red(rep, x: 600...660, y: 168...200), 0)
    }

    /// How many pixels in a rect of the view are the marks' red.
    private func red(_ rep: NSBitmapImageRep, x: ClosedRange<Int>, y: ClosedRange<Int>) -> Int {
        y.reduce(0) { sum, row in sum + x.filter { isRed(pixel(rep, $0, row)) }.count }
    }

    /// Waits until every text bitmap the view has asked for is drawn and on its layer, or dropped: the
    /// text queue runs dry, then the main queue runs what it sent back, which may ask for more.
    private func settleTexts() {
        func contents(_ layer: CALayer?) -> [ObjectIdentifier?] {
            (layer?.sublayers ?? []).flatMap { [$0.contents.map { ObjectIdentifier($0 as AnyObject) }] + contents($0) }
        }
        func contents() -> [ObjectIdentifier?] { contents(view.subviews.first?.layer) }
        var last = contents(), quiet = 0
        while quiet < 2 {
            MarkLayers.textQueue.sync {}
            var ran = false
            DispatchQueue.main.async { ran = true }
            while !ran { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01)) }
            let now = contents()
            quiet = now == last ? quiet + 1 : 0
            last = now
        }
    }

    /// A flight to or from the annotator draws its texts as the fitted editor does, the frame's width
    /// over the image's, over the whole image: the two take each other's bitmaps as they are, so
    /// nothing steps when one takes the other's place and nothing is drawn twice.
    func testAFlightAndTheFittedEditorShowTheSameTextBitmaps() {
        open([Mark(geometry: .text(Mark.Text(origin: CGPoint(x: 100, y: 100), text: "Handed over", wrap: nil, size: 24)))])
        settleTexts()
        XCTAssertGreaterThan(view.marks.bitmapPixels, 0)
        let drawing = view.core.drawing
        let flight = MarkLayers(pixels: drawing.pixels, queue: MarkLayers.textQueue)
        let scale = view.bounds.width / CGFloat(drawing.pixels.width) * window.backingScaleFactor
        flight.show(drawing, scale: scale, bound: drawing.pixels.bounds, style: .standard, arrowhead: .standard, adopting: [view.marks])
        XCTAssertTrue(flight.isDrawn(drawing.marks[0].id), "the editor's bitmap is the one the flight wants")
        XCTAssertEqual(flight.bitmapPixels, view.marks.bitmapPixels)

        let editor = view.marks
        _ = view.park()
        let home = MarkLayers(pixels: drawing.pixels, queue: MarkLayers.textQueue)
        home.show(drawing, scale: scale, bound: drawing.pixels.bounds, style: .standard, arrowhead: .standard, adopting: [editor])
        XCTAssertTrue(home.isDrawn(drawing.marks[0].id), "the parked editor's bitmap goes home as it is")
    }

    func testABitmapThatArrivesAfterItsTextMovedIsNotShown() throws {
        open([Mark(geometry: .text(Mark.Text(origin: CGPoint(x: 100, y: 100), text: "Moved", wrap: nil, size: 24)))])
        // The first bitmap is drawn and waits on the main queue; the next draw waits on the text queue.
        MarkLayers.textQueue.sync {}
        MarkLayers.textQueue.suspend()
        var suspended = true
        defer { if suspended { MarkLayers.textQueue.resume() } }
        drag(from: (130, 115), to: (130, 415))
        XCTAssertEqual(text(view.core.drawing.marks.first)?.origin, CGPoint(x: 100, y: 400))

        let moving = try capture { _ in true }
        XCTAssertEqual(red(moving, x: 100...200, y: 100...130), 0, "the bitmap drawn for where the text was is dropped")
        XCTAssertEqual(red(moving, x: 100...200, y: 400...430), 0, "the one for where it is has not been drawn")

        MarkLayers.textQueue.resume()
        suspended = false
        settleTexts()
        let moved = try capture { _ in true }
        XCTAssertGreaterThan(red(moved, x: 100...200, y: 400...430), 20)
        XCTAssertEqual(red(moved, x: 100...200, y: 100...130), 0)
    }

    func testNoBitmapIsShownAfterParkOrOnAnotherImage() throws {
        MarkLayers.textQueue.suspend()
        var suspended = true
        defer { if suspended { MarkLayers.textQueue.resume() } }
        open([Mark(geometry: .text(Mark.Text(origin: CGPoint(x: 100, y: 100), text: "Parked", wrap: nil, size: 24)))])
        XCTAssertNotNil(view.park())
        MarkLayers.textQueue.resume()
        suspended = false
        settleTexts()
        let parked = try capture { _ in true }
        XCTAssertEqual(red(parked, x: 100...200, y: 100...130), 0, "a bitmap asked for before park is not shown")

        MarkLayers.textQueue.suspend()
        suspended = true
        open([Mark(geometry: .text(Mark.Text(origin: CGPoint(x: 100, y: 300), text: "First", wrap: nil, size: 24)))])
        open([Mark(geometry: .rectangle(CGRect(x: 600, y: 100, width: 200, height: 100)))])
        MarkLayers.textQueue.resume()
        suspended = false
        settleTexts()
        let other = try capture { self.isRed(self.pixel($0, 700, 100)) }
        XCTAssertEqual(red(other, x: 100...200, y: 300...330), 0, "the first image's text is not drawn on the second")
    }

    func testWhenTypingEndsTheWordsAreOnScreenInEveryFrame() throws {
        open()
        key("t", 17)
        mouse(.leftMouseDown, 100, 100)
        mouse(.leftMouseUp, 100, 100)
        type("Words")
        MarkLayers.textQueue.suspend()
        var suspended = true
        defer { if suspended { MarkLayers.textQueue.resume() } }
        key("\r", 36)
        XCTAssertNil(view.core.typing)
        let box = try XCTUnwrap(text(view.core.drawing.marks.first).map { TextLayout($0, imageWidth: 1000, pointScale: 1, style: .standard).box })
        let columns = Int(box.minX)...Int(box.maxX), rows = Int(box.minY)...Int(box.maxY)

        // Its bitmap cannot be drawn yet, so the text view still shows the words.
        let ended = try capture { _ in true }
        XCTAssertGreaterThan(red(ended, x: columns, y: rows), 20)

        // Once the bitmap can be drawn, it takes over from the text view in one frame.
        MarkLayers.textQueue.resume()
        suspended = false
        var frames = 0
        while textView != nil, frames < 100 {
            let frame = try capture { _ in true }
            XCTAssertGreaterThan(red(frame, x: columns, y: rows), 20, "frame \(frames)")
            frames += 1
        }
        XCTAssertNil(textView)
        let drawn = try capture { _ in true }
        XCTAssertGreaterThan(red(drawn, x: columns, y: rows), 20)
    }

    /// New tweaks reach the open editor: the strokes take the arrowhead at once, a text is drawn again
    /// in the new style even when a bitmap in the old one was already on its way, and a text being
    /// typed is laid out again on the new style's baselines.
    func testNewTweaksReachTheOpenEditor() throws {
        MarkLayers.textQueue.suspend()
        var suspended = true
        defer { if suspended { MarkLayers.textQueue.resume() } }
        open([Mark(geometry: .arrow(Mark.Arrow(start: CGPoint(x: 600, y: 100), end: CGPoint(x: 900, y: 100)))),
              Mark(geometry: .text(Mark.Text(origin: CGPoint(x: 100, y: 100), text: "A\nB", wrap: nil, size: 24)))])
        let tall = TextStyle(weight: .medium, lineHeight: 4)
        view.applyTweaks(style: tall, metrics: .standard, arrowhead: ArrowheadStyle(length: 4.5, width: 12))
        MarkLayers.textQueue.resume()
        suspended = false
        settleTexts()
        let rep = try capture { _ in true }
        // 12 stroke widths across, the head reaches 16 px from the arrow's line 12 px behind its tip;
        // 4 would reach 5.
        XCTAssertTrue(isRed(pixel(rep, 888, 110)), "\(pixel(rep, 888, 110))")
        XCTAssertTrue(isRed(pixel(rep, 888, 90)), "\(pixel(rep, 888, 90))")
        // At 4 times the size, the second line sits below where any of the text was at 1.35.
        XCTAssertGreaterThan(red(rep, x: 100...130, y: 230...258), 20)

        key("t", 17)
        mouse(.leftMouseDown, 150, 450)
        mouse(.leftMouseUp, 150, 450)
        type("Typed")
        let bold = TextStyle(weight: .bold, lineHeight: 2)
        view.applyTweaks(style: bold, metrics: .standard, arrowhead: .standard)
        let field = try XCTUnwrap(textView)
        XCTAssertTrue(window.firstResponder === field, "typing goes on")
        XCTAssertEqual(field.string, "Typed")
        let layoutManager = try XCTUnwrap(field.layoutManager)
        layoutManager.ensureLayout(for: try XCTUnwrap(field.textContainer))
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        let glyph = layoutManager.location(forGlyphAt: 0)
        let typed = field.convert(CGPoint(x: field.textContainerOrigin.x + fragment.minX + glyph.x,
                                          y: field.textContainerOrigin.y + fragment.minY + glyph.y), to: view)
        let mark = try XCTUnwrap(text(view.core.mark(try XCTUnwrap(view.core.typing?.id))))
        let line = try XCTUnwrap(TextLayout(mark, imageWidth: 1000, pointScale: 1, style: bold).lines.first)
        let drawn = view.viewPoint(forImagePoint: CGPoint(x: line.rect.minX, y: line.baseline))
        XCTAssertEqual(fragment.height, line.rect.height, accuracy: 1e-9)
        XCTAssertEqual(typed.y, drawn.y, accuracy: 0.5)
        XCTAssertEqual(typed.x, drawn.x, accuracy: 0.5)
    }

    /// The selection's blue (`#3182ed`), whatever the display's profile did to it.
    private func isBlue(_ c: (r: CGFloat, g: CGFloat, b: CGFloat)) -> Bool { c.b > 0.8 && c.r < 0.4 && c.g < 0.7 }

    func testSelectedMarksKeepTheirColourAlongTheWholeStrokeWithTheOutlineOutsideIt() throws {
        open([Mark(geometry: .rectangle(CGRect(x: 100, y: 60, width: 300, height: 150))),
              Mark(geometry: .ellipse(CGRect(x: 500, y: 60, width: 300, height: 150))),
              Mark(geometry: .arrow(Mark.Arrow(start: CGPoint(x: 100, y: 400), end: CGPoint(x: 400, y: 400))))])
        key("a", 0, .command)
        XCTAssertEqual(view.core.selection.count, 3)
        let rep = try capture { self.isBlue(self.pixel($0, 250, 56)) }

        // Each stroke is 3.5 px about its line, so its colour covers the two rows either side of the
        // line whole, and the outline's 3.5 pt run outside it, the blue in their middle.
        for (x, y, outside) in [(250, 60, -1), (250, 210, 1), (650, 60, -1), (650, 210, 1), (180, 400, -1), (180, 400, 1)] {
            for row in y - 1...y { XCTAssertTrue(isRed(pixel(rep, x, row)), "stroke at \(x),\(row): \(pixel(rep, x, row))") }
            let blue = y + outside * 4 - (outside < 0 ? 0 : 1)
            XCTAssertTrue(isBlue(pixel(rep, x, blue)), "outline at \(x),\(blue): \(pixel(rep, x, blue))")
        }
    }

    /// Along a line of pixels, how many are soft, in between the colours `kinds` name, and how many
    /// edges from one colour to another the line crosses. A shape drawn at the screen's resolution
    /// has about one soft pixel an edge; a magnified bitmap has several.
    private func edges(_ rep: NSBitmapImageRep, _ points: [(Int, Int)],
                       _ kinds: [((r: CGFloat, g: CGFloat, b: CGFloat)) -> Bool]) -> (soft: Int, edges: Int) {
        var soft = 0, edges = 0, last: Int?
        for point in points {
            guard let kind = kinds.firstIndex(where: { $0(pixel(rep, point.0, point.1)) }) else {
                soft += 1
                continue
            }
            if let last, last != kind { edges += 1 }
            last = kind
        }
        return (soft, edges)
    }

    func testStrokesAreSharpAtZoomThreeAtOnceAndTextsOnceTheZoomRests() throws {
        open([Mark(geometry: .rectangle(CGRect(x: 100, y: 60, width: 300, height: 150))),
              Mark(geometry: .text(Mark.Text(origin: CGPoint(x: 600, y: 400), text: "HH", wrap: nil, size: 24)))])
        let zoom: CGFloat = 3
        func centre(_ point: CGPoint) { view.pictureRect = CGRect(x: 500 - point.x * zoom, y: 300 - point.y * zoom, width: 3000, height: 1800) }
        let background = { (c: (r: CGFloat, g: CGFloat, b: CGFloat)) in self.isBackground(c) }
        let red = { (c: (r: CGFloat, g: CGFloat, b: CGFloat)) in self.isRed(c) }
        let dark = { (c: (r: CGFloat, g: CGFloat, b: CGFloat)) in max(c.r, c.g, c.b) < 0.2 }

        // The rectangle's top edge, captured before the zoom rests: a stroke needs nothing drawn again.
        centre(CGPoint(x: 250, y: 60))
        var rep = try capture(nominal: false) { red(self.pixel($0, $0.pixelsWide / 2, $0.pixelsHigh / 2)) }
        let scale = rep.pixelsWide / 1000
        let column = (rep.pixelsHigh / 2 - 20 * scale...rep.pixelsHigh / 2 + 20 * scale).map { (rep.pixelsWide / 2, $0) }
        XCTAssertGreaterThan(column.filter { red(self.pixel(rep, $0.0, $0.1)) }.count, 9 * scale, "the stroke is 3.5 px, 10.5 pt at zoom 3")
        let stroke = edges(rep, column, [background, red])
        XCTAssertEqual(stroke.edges, 2)
        XCTAssertLessThanOrEqual(stroke.soft, stroke.edges + 1, "about one soft pixel at each edge of the stroke")

        // Across the first H, near the top of its stems, captured once the zoom has rested and the
        // text is drawn for it.
        centre(CGPoint(x: 606, y: 412))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: EditorView.restDelay * 3))
        settleTexts()
        rep = try capture(nominal: false) { _ in true }
        let row = (rep.pixelsWide / 2 - 45 * scale...rep.pixelsWide / 2 + 45 * scale).map { ($0, rep.pixelsHigh / 2) }
        XCTAssertGreaterThan(row.filter { red(self.pixel(rep, $0.0, $0.1)) }.count, 4 * scale, "the stems' fill")
        let letters = edges(rep, row, [background, red, dark])
        XCTAssertGreaterThanOrEqual(letters.edges, 4, "into and out of the outline and the fill")
        XCTAssertLessThanOrEqual(letters.soft, letters.edges + 2, "about one soft pixel at each edge of the letters")
    }

    // MARK: The clipboard

    func testCmdCWritesTheMarksAndTheirWordsAndCmdVPastesThemBackThroughEitherPath() throws {
        open([Mark(geometry: .text(Mark.Text(origin: CGPoint(x: 100, y: 100), text: "a note", wrap: nil, size: 24)))])
        XCTAssertEqual(view.core.selection.count, 1, "reopening selects the newest mark")

        // Through keyDown.
        key("c", 8, .command)
        XCTAssertEqual(heard.last, "toast Copied 1 mark")
        let data = try XCTUnwrap(pasteboard.data(forType: CopiedMarks.pasteboardType))
        XCTAssertEqual(CopiedMarks(data: data)?.marks.map(\.geometry), view.core.drawing.marks.map(\.geometry))
        XCTAssertEqual(pasteboard.string(forType: .string), "a note")
        key("v", 9, .command)
        XCTAssertEqual(view.core.drawing.marks.count, 2)
        XCTAssertEqual(text(view.core.drawing.marks.last)?.origin, CGPoint(x: 110, y: 110), "a paste lands 10 pt right and down")
        XCTAssertEqual(view.core.selection, [view.core.drawing.marks[1].id])

        // Through the window's key equivalents, as a Command key reaches it in the app. Each command
        // runs once.
        pasteboard.clearContents()
        XCTAssertTrue(window.performKeyEquivalent(with: keyEvent("c", 8, .command)))
        XCTAssertEqual(heard.filter { $0.hasPrefix("toast") }.count, 2)
        XCTAssertNotNil(pasteboard.data(forType: CopiedMarks.pasteboardType))
        XCTAssertTrue(window.performKeyEquivalent(with: keyEvent("v", 9, .command)))
        XCTAssertEqual(view.core.drawing.marks.count, 3)
        XCTAssertEqual(text(view.core.drawing.marks.last)?.origin, CGPoint(x: 120, y: 120))

        // Cmd+Z undoes one paste, whichever way it arrives.
        XCTAssertTrue(window.performKeyEquivalent(with: keyEvent("z", 6, .command)))
        XCTAssertEqual(view.core.drawing.marks.count, 2)
        key("z", 6, .command)
        XCTAssertEqual(view.core.drawing.marks.count, 1)

        // A Command key the editor has no command for is left for the app's menu.
        XCTAssertFalse(window.performKeyEquivalent(with: keyEvent("w", 13, .command)))
    }

    func testCmdVOfAFileOrAnImageAddsNothingAndSaysSo() {
        open()
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: "/tmp/Screenshot other.png") as NSURL])
        pasteboard.addTypes([.string], owner: nil)
        pasteboard.setString("Screenshot other.png", forType: .string)
        key("v", 9, .command)
        XCTAssertTrue(view.core.drawing.marks.isEmpty, "a file's name on the clipboard does not make it text")
        XCTAssertEqual(heard.last, "toast Images can't be pasted here")

        pasteboard.clearContents()
        pasteboard.setString("https://example.com/a", forType: .string)
        key("v", 9, .command)
        XCTAssertEqual(text(view.core.drawing.marks.last)?.text, "https://example.com/a", "a URL is text")
    }
}
