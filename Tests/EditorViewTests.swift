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
                  style: .standard, metrics: .standard, arrowhead: .standard, pickColor: { _ in nil })
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
        XCTAssertNil(textView, "the text view is gone")
        XCTAssertTrue(window.firstResponder === view)
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

    func testCmdBWhileTypingChangesNothing() throws {
        open()
        key("t", 17)
        mouse(.leftMouseDown, 200, 300)
        mouse(.leftMouseUp, 200, 300)
        type("plain")
        let before = view.core.drawing
        let field = try XCTUnwrap(textView)
        key("b", 11, .command)
        XCTAssertFalse(window.performKeyEquivalent(with: keyEvent("b", 11, .command)))
        XCTAssertEqual(view.core.drawing, before)
        XCTAssertNotNil(view.core.typing)
        XCTAssertEqual(field.string, "plain")
        XCTAssertEqual(field.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
                       field.textStorage?.attribute(.font, at: 4, effectiveRange: nil) as? NSFont)
        XCTAssertFalse(field.isRichText)
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
