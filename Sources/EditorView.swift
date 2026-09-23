import AppKit
import QuartzCore

/// The drawing editor on screen. It hosts `EditorCore`: it turns mouse, key and modifier events into
/// the core's inputs, runs the effects each input returns in the order they come, and draws what the
/// core's state says. It decides nothing. The host opens an image, sets where the picture sits as its
/// zoom moves, and hears from the editor through the callbacks.
///
/// The view is flipped: its coordinates run down from the top-left corner, as the image's px do.
@MainActor
final class EditorView: NSView {
    // MARK: What the host does

    /// The drawing to store: after the pause that follows a change, and when agents' marks join. With
    /// no marks the host removes its file. Park answers with its drawing instead (`park()`).
    var onHandOver: ((Drawing) -> Void)?
    /// The active tool changed; the toolbar shows it.
    var onTool: ((EditorCore.Tool) -> Void)?
    /// Esc with nothing under way: the host decides whether and how the editor closes.
    var onClose: (() -> Void)?
    /// Return or Done: render this drawing and finish.
    var onDone: ((Drawing) -> Void)?
    /// Send: render this drawing and send it. The editor stays open.
    var onSend: ((Drawing) -> Void)?
    /// Cmd+C with nothing selected: this drawing's rendering goes on the clipboard.
    var onCopyDrawing: ((Drawing) -> Void)?
    /// A zoom key, or a double-click asking for smart zoom. The point of `.smart` is in image px;
    /// `viewPoint(forImagePoint:)` places it in the view.
    var onZoom: ((EditorCore.ZoomRequest) -> Void)?
    /// A pinch, a scroll or a two-finger double tap: the host's zoom and pan act on these.
    var onZoomGesture: ((NSEvent) -> Void)?
    /// A short confirmation to show, such as "Copied 2 marks".
    var onToast: ((String) -> Void)?

    /// Everything the editor decides; the host reads it for `[state]`.
    private(set) var core = EditorCore()

    /// The marks of the image open now, or of the one just parked until `clear`: a flight takes their
    /// text bitmaps.
    var marks: MarkLayers { picture.marks }

    /// Where the picture sits in the view: `open` places it, and the host's zoom sets it on every
    /// step. The zoom, in screen pt per image px, is its width over the image's, and the marks, the
    /// overlay and the text being typed follow it in the same turn.
    var pictureRect: CGRect {
        get { placedPicture }
        set {
            placedPicture = newValue
            pictureMoved()
        }
    }

    /// The view's size and the picture's rect in it, set together as one zoom step, for a host whose
    /// zoom grows the window with the picture. Setting the size alone is a zoom step too.
    func setSize(_ size: CGSize, picture: CGRect) {
        settingSize = true
        setFrameSize(size)
        settingSize = false
        pictureRect = picture
    }

    /// How long the picture stays put before the texts are drawn again for the zoom it is at.
    static let restDelay: TimeInterval = 0.1

    private let pasteboard: NSPasteboard
    private let canvas = CanvasView()
    private let picture = EditorPicture()
    private let overlay = EditorOverlayLayers()
    private var placedPicture = CGRect.zero
    private var screenshotName = ""
    private var typingField: TypingField?
    /// The text view of a typing session that ended, kept over its text until the text's bitmap is
    /// on its layer, so the words are on screen in every frame.
    private var lingering: TypingField?
    private var handOverTimer: Timer?
    private var restTimer: Timer?
    private var zoomMoving = false
    /// Inside `setSize(_:picture:)`, whose picture step follows the size at once.
    private var settingSize = false
    /// Arrow keys down, which get their key up when the window stops being key.
    private var heldArrows: Set<EditorCore.Key> = []
    private var resignKeyObserver: NSObjectProtocol?

    /// `pasteboard` is where Cmd+C and Cmd+V go: the general one, or a private one in tests.
    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        super.init(frame: .zero)
        wantsLayer = true
        canvas.frame = bounds
        canvas.autoresizingMask = [.width, .height]
        addSubview(canvas)
        canvas.host.addSublayer(picture.layer)
        canvas.host.addSublayer(overlay.layer)
        picture.onTextDrawn = { [weak self] id in
            if self?.lingering?.id == id { self?.settleLingering() }
        }
        registerForDraggedTypes([.fileURL] + NSImage.imageTypes.map { NSPasteboard.PasteboardType($0) })
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Opening, parking and the toolbar

    /// Opens a screenshot with its drawing, an empty one when it has none. `image` is the screenshot
    /// decoded at any size, or nil until its decode arrives (`setImage`); it fills the drawing's
    /// `pixels`, shown at `picture` in the view. `pickColor` is the colour pass's pick, which may
    /// answer nil until its sample exists (`colorSampleArrived`). The strokes are on screen when
    /// this returns; each text follows a moment later, once its bitmap is drawn off the main thread.
    func open(_ drawing: Drawing, image: CGImage?, picture: CGRect, style: TextStyle, metrics: EditorMetrics, arrowhead: ArrowheadStyle,
              pickColor: @escaping EditorCore.ColorPick) {
        stopTimers()
        heldArrows = []
        screenshotName = URL(fileURLWithPath: drawing.key).deletingPathExtension().lastPathComponent
        self.picture.open(image, pixels: drawing.pixels)
        placedPicture = picture
        handle(.open(drawing, style: style, metrics: metrics, arrowhead: arrowhead, pickColor: pickColor))
        dropLingering()
        guard core.isOpen else {
            Log.write("[editor] error open-refused \(screenshotName): pixels=\(drawing.pixels.width)x\(drawing.pixels.height) pointScale=\(drawing.pointScale)")
            return
        }
        handle(.zoomChanged(zoom))
        window?.makeFirstResponder(self)
    }

    /// The drawing to store, at once: a gesture ends as if released, typing ends, and the colour pass
    /// runs. Nil when nothing is open. The editor then ignores every input until the next `open`, and
    /// what it shows stays as it is: a text bitmap still being drawn is never put on screen.
    func park() -> Drawing? {
        guard core.isOpen else { return nil }
        var parked: Drawing?
        for effect in core.reduce(.park) {
            if case .handOver(let drawing) = effect { parked = drawing } else { run(effect, event: nil) }
        }
        heldArrows = []
        refresh()
        picture.park()
        return parked
    }

    /// The screenshot's decode, when it arrives after `open`. The drawing and everything else stay.
    func setImage(_ image: CGImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        picture.setImage(image)
        CATransaction.commit()
    }

    /// Frees the screenshot and every mark's layers once the parked view is out of sight. The next
    /// `open` draws again. The picture's session ends first, so a text bitmap still on its way is
    /// never put on the cleared view, and a text view left from typing goes with the marks.
    func clear() {
        guard !core.isOpen else { return }
        stopTimers()
        dropLingering()
        core = EditorCore()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        picture.park()
        picture.open(nil, pixels: core.drawing.pixels)
        CATransaction.commit()
    }

    /// A tool button in the toolbar.
    func setTool(_ tool: EditorCore.Tool) { handle(.setTool(tool)) }

    /// Done in the toolbar; the drawing comes back through `onDone`.
    func done() { handle(.done) }

    /// Send in the toolbar, once a destination is chosen; the drawing comes back through `onSend`.
    func send() { handle(.send) }

    /// Agents' marks joining the open drawing, already in px. They go to the host at once.
    func addAgentMarks(_ marks: [Mark]) { handle(.agentMarks(marks)) }

    /// The colour pass's sample exists now: marks it could not colour before are coloured.
    func colorSampleArrived() {
        if !core.colorOwed.isEmpty { handle(.timerFired) }
    }

    /// The tweaks changed: the text style, the sizes and the arrowhead replace the ones `open` gave,
    /// and the drawing, the selection, the history and a typing session stay. The strokes take a new
    /// arrowhead at once. Each text keeps its bitmap until one in the new style arrives, and a text
    /// being typed is laid out again where it is.
    func applyTweaks(style: TextStyle, metrics: EditorMetrics, arrowhead: ArrowheadStyle) {
        guard core.isOpen, style != core.style || metrics != core.metrics || arrowhead != core.arrowhead else { return }
        let restyled = style != core.style
        for effect in core.reduce(.tweaksChanged(style: style, metrics: metrics, arrowhead: arrowhead)) { run(effect, event: nil) }
        if restyled {
            for field in [typingField, lingering].compactMap({ $0 }) {
                guard case .text(let text)? = core.mark(field.id)?.geometry else { continue }
                field.setStyle(style, size: text.size, pointScale: core.drawing.pointScale, imageWidth: CGFloat(core.drawing.pixels.width))
            }
        }
        refresh()
    }

    // MARK: Coordinates

    /// Screen pt per image px.
    private var zoom: CGFloat {
        let width = CGFloat(core.drawing.pixels.width)
        return width > 0 ? placedPicture.width / width : 0
    }

    private var toView: CGAffineTransform {
        CGAffineTransform(a: zoom, b: 0, c: 0, d: zoom, tx: placedPicture.minX, ty: placedPicture.minY)
    }

    func viewPoint(forImagePoint point: CGPoint) -> CGPoint { point.applying(toView) }

    func imagePoint(forViewPoint point: CGPoint) -> CGPoint {
        guard zoom > 0 else { return point }
        return CGPoint(x: (point.x - placedPicture.minX) / zoom, y: (point.y - placedPicture.minY) / zoom)
    }

    // MARK: Running the core

    @discardableResult
    private func handle(_ input: EditorCore.Input, event: NSEvent? = nil) -> [EditorCore.Effect] {
        let effects = core.reduce(input)
        for effect in effects { run(effect, event: event) }
        refresh()
        return effects
    }

    /// Runs one effect. `event` is the press that produced it, for `passPressToText`.
    private func run(_ effect: EditorCore.Effect, event: NSEvent?) {
        switch effect {
        case .tool(let tool): onTool?(tool)
        case .cursor(let cursor): if pointerIsInside { Self.cursor(cursor).set() }
        case .beginTyping(let id, let caret): beginTyping(id, caret: caret)
        case .endTyping: endTyping()
        case .passPressToText:
            // NSTextView tracks the drag and the release in its own loop before this returns, so
            // they never reach the editor.
            guard let event, let field = typingField else { return }
            field.textView.mouseDown(with: event)
        case .scheduleTimer: scheduleHandOver()
        case .cancelTimer:
            handOverTimer?.invalidate()
            handOverTimer = nil
        case .handOver(let drawing): onHandOver?(drawing)
        case .copyMarks(let marks, let text): write(marks, text: text)
        case .copyDrawing(let drawing): onCopyDrawing?(drawing)
        case .readClipboard: handle(.paste(clipboardContent()))
        case .toast(let words): onToast?(words)
        case .zoom(let request): onZoom?(request)
        case .announce(let words):
            // The words can be a text's own, so they go to VoiceOver and nowhere else.
            NSAccessibility.post(element: self, notification: .announcementRequested,
                                 userInfo: [.announcement: words, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        case .close: onClose?()
        case .done(let drawing): onDone?(drawing)
        case .send(let drawing): onSend?(drawing)
        }
    }

    private func scheduleHandOver() {
        handOverTimer?.invalidate()
        // Common modes, so the pause also runs out while a text view tracks a drag.
        let timer = Timer(timeInterval: EditorCore.handOverDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handOverTimer = nil
                self?.handle(.timerFired)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        handOverTimer = timer
    }

    private func stopTimers() {
        handOverTimer?.invalidate()
        handOverTimer = nil
        restTimer?.invalidate()
        restTimer = nil
        zoomMoving = false
    }

    // MARK: Drawing

    /// Draws what the core's state says, in one Core Animation transaction.
    private func refresh() {
        guard core.drawing.pixels.width > 0, zoom > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let transform = toView
        let geometry = core.geometry
        picture.layer.setAffineTransform(transform)
        picture.show(core.drawing, typing: core.typing?.id, covered: lingering?.id, geometry: geometry, resolution: resolution,
                     gesture: core.gesture != nil)
        overlay.show(core.overlay, drawing: core.drawing, geometry: geometry, transform: transform)
        placeTypingField()
        settleLingering()
        CATransaction.commit()
    }

    private var backingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    /// The zoom's resolution and the part of the image in view, the whole picture while the view has
    /// no size yet.
    private var resolution: EditorPicture.Resolution {
        let shown = bounds.isEmpty ? placedPicture : bounds.intersection(placedPicture)
        var visible = CGRect.null
        if !shown.isNull, zoom > 0 {
            let origin = imagePoint(forViewPoint: shown.origin)
            visible = CGRect(x: origin.x, y: origin.y, width: shown.width / zoom, height: shown.height / zoom).intersection(core.drawing.pixels.bounds)
        }
        let room = shown.isNull || shown.isEmpty ? bounds : shown
        let view = bounds.isEmpty ? placedPicture : bounds, image = core.drawing.pixels.bounds
        let fit = image.isEmpty ? 0 : min(view.width / image.width, view.height / image.height) * backingScale
        return EditorPicture.Resolution(scale: zoom * backingScale, visible: visible, pixels: room.width * room.height * backingScale * backingScale,
                                        fit: fit, moving: zoomMoving)
    }

    /// A zoom step: everything follows at once, and the texts are drawn for the new zoom once it rests.
    /// A parked view still follows, since the host springs it back to fit before it hides.
    private func pictureMoved() {
        guard zoom > 0, zoom.isFinite else { return }
        zoomMoving = true
        restTimer?.invalidate()
        let timer = Timer(timeInterval: Self.restDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.zoomCameToRest() }
        }
        RunLoop.main.add(timer, forMode: .common)
        restTimer = timer
        if core.isOpen { handle(.zoomChanged(zoom)) } else { refresh() }
    }

    /// The zoom is still: the texts are drawn for it, and the hover is found again under a pointer the
    /// picture moved beneath.
    private func zoomCameToRest() {
        restTimer = nil
        zoomMoving = false
        guard core.isOpen else { return }
        if core.gesture == nil, NSEvent.pressedMouseButtons == 0, pointerIsInside, let window {
            let at = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            handle(.pointerMoved(EditorCore.Pointer(location: imagePoint(forViewPoint: at), modifiers: EditorCore.Modifiers(eventFlags: NSEvent.modifierFlags.rawValue))))
        } else {
            refresh()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed, !settingSize { pictureMoved() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        overlay.setScale(backingScale)
        picture.setScale(backingScale)
        canvas.host.contentsScale = backingScale
        refresh()
    }

    // MARK: Typing

    private func beginTyping(_ id: Mark.ID, caret: EditorCore.Caret) {
        guard let mark = core.mark(id), case .text(let text) = mark.geometry else { return }
        if typingField?.id != id {
            endTyping()
            dropLingering()
            let field = TypingField(id: id, text: text, color: mark.color, pointScale: core.drawing.pointScale,
                                    imageWidth: CGFloat(core.drawing.pixels.width), style: core.style)
            field.onChange = { [weak self] words in self?.handle(.typingChanged(words)) }
            field.onResign = { [weak self, weak field] in
                // The text view gave up the keys to something other than the editor.
                guard let self, let field, self.typingField === field else { return }
                self.handle(.typingEnded)
            }
            field.textView.takeKey = { [weak self] event in self?.typingKey(event) ?? false }
            typingField = field
            addSubview(field.textView)
            placeTypingField()
            window?.makeFirstResponder(field.textView)
        }
        guard let field = typingField, case .text(let typed)? = core.mark(id)?.geometry else { return }
        field.setCaret(caret, boxOrigin: typed.origin)
    }

    private func endTyping() {
        guard let field = typingField else { return }
        typingField = nil
        if window?.firstResponder === field.textView { window?.makeFirstResponder(self) }
        dropLingering()
        field.textView.setSelectedRange(NSRange(location: 0, length: 0))
        field.textView.isEditable = false
        field.textView.isSelectable = false
        lingering = field
    }

    /// Takes the ended session's text view away once its text's bitmap shows the text, or the text is
    /// gone; until then it follows the zoom over the text.
    private func settleLingering() {
        guard let field = lingering else { return }
        guard case .text(let text)? = core.mark(field.id)?.geometry, !picture.isDrawn(field.id) else { return dropLingering() }
        let transform = toView
        field.place(text, box: core.geometry.layout(text).box, imageWidth: CGFloat(core.drawing.pixels.width)) { $0.applying(transform) }
    }

    private func dropLingering() {
        lingering?.textView.removeFromSuperview()
        lingering = nil
    }

    /// Puts the text view over the core's box for the text, which may have moved as it grew.
    private func placeTypingField() {
        guard let field = typingField, let box = core.typingBox, case .text(let text)? = core.mark(field.id)?.geometry else { return }
        let transform = toView
        field.place(text, box: box, imageWidth: CGFloat(core.drawing.pixels.width)) { $0.applying(transform) }
    }

    /// A key pressed while typing. The core takes the few `takesKey` names, but never during an input
    /// method's composition, which owns every key until it is confirmed; the text view gets the rest.
    private func typingKey(_ event: NSEvent) -> Bool {
        guard typingField?.textView.hasMarkedText() == false, let key = Self.key(event) else { return false }
        let modifiers = Self.modifiers(event)
        guard core.takesKey(key, modifiers) else { return false }
        handle(.keyDown(key, modifiers, isRepeat: event.isARepeat))
        return true
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        guard let key = Self.key(event) else { return super.keyDown(with: event) }
        if key.direction != nil { heldArrows.insert(key) }
        handle(.keyDown(key, Self.modifiers(event), isRepeat: event.isARepeat))
    }

    override func keyUp(with event: NSEvent) {
        guard let key = Self.key(event), heldArrows.remove(key) != nil else { return super.keyUp(with: event) }
        handle(.keyUp(key))
    }

    override func flagsChanged(with event: NSEvent) {
        handle(.modifiersChanged(Self.modifiers(event)))
    }

    /// Command keys, which the window offers here before the menu: the ones the core takes go to it,
    /// and Cmd+Z and Shift+Cmd+Z always come here, so one owner handles undo while typing or not.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, event.modifierFlags.contains(.command), core.isOpen, let key = Self.key(event),
              let responder = window?.firstResponder, responder === self || responder === typingField?.textView else {
            return super.performKeyEquivalent(with: event)
        }
        let modifiers = Self.modifiers(event)
        if key == .character("z") {
            if modifiers.contains(.shift) { redo(nil) } else { undo(nil) }
            return true
        }
        if typingField != nil { return typingKey(event) || super.performKeyEquivalent(with: event) }
        guard core.takesKey(key, modifiers) else { return super.performKeyEquivalent(with: event) }
        if key.direction != nil { heldArrows.insert(key) }
        handle(.keyDown(key, modifiers, isRepeat: event.isARepeat))
        return true
    }

    /// Undo: the typing session's own while a text is typed, where nothing is undone past the
    /// session's start; the core's otherwise.
    @objc func undo(_ sender: Any?) {
        if let field = typingField {
            if field.undo.canUndo { field.undo.undo() }
            return
        }
        handle(.keyDown(.character("z"), .command, isRepeat: false))
    }

    @objc func redo(_ sender: Any?) {
        if let field = typingField {
            if field.undo.canRedo { field.undo.redo() }
            return
        }
        handle(.keyDown(.character("z"), [.command, .shift], isRepeat: false))
    }

    private static func key(_ event: NSEvent) -> EditorCore.Key? {
        EditorCore.Key(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers)
    }

    private static func modifiers(_ event: NSEvent) -> EditorCore.Modifiers {
        EditorCore.Modifiers(eventFlags: event.modifierFlags.rawValue)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if let resignKeyObserver { NotificationCenter.default.removeObserver(resignKeyObserver) }
        resignKeyObserver = nil
        guard let newWindow else { return }
        // A key released in another window never reaches this one; the core would keep nudging diagonally.
        resignKeyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: newWindow, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseHeldArrows() }
        }
    }

    private func releaseHeldArrows() {
        let held = heldArrows
        heldArrows = []
        for key in held { handle(.keyUp(key)) }
    }

    // MARK: Mouse

    private func pointer(_ event: NSEvent) -> EditorCore.Pointer {
        EditorCore.Pointer(location: imagePoint(forViewPoint: convert(event.locationInWindow, from: nil)),
                           modifiers: Self.modifiers(event), time: event.timestamp)
    }

    /// Every press lands here, over the text being typed too: the core decides whether the text view
    /// takes it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        handle(.pointerPressed(pointer(event), clickCount: event.clickCount), event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        handle(.pointerDragged(pointer(event)))
    }

    override func mouseUp(with event: NSEvent) {
        handle(.pointerReleased(pointer(event)))
    }

    override func mouseMoved(with event: NSEvent) {
        handle(.pointerMoved(pointer(event)))
    }

    override func mouseExited(with event: NSEvent) {
        handle(.pointerExited)
    }

    override func cursorUpdate(with event: NSEvent) {
        Self.cursor(core.cursor).set()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func magnify(with event: NSEvent) {
        if let onZoomGesture { onZoomGesture(event) } else { super.magnify(with: event) }
    }

    override func smartMagnify(with event: NSEvent) {
        if let onZoomGesture { onZoomGesture(event) } else { super.smartMagnify(with: event) }
    }

    override func scrollWheel(with event: NSEvent) {
        if let onZoomGesture { onZoomGesture(event) } else { super.scrollWheel(with: event) }
    }

    private var pointerIsInside: Bool {
        guard let window, window.isVisible else { return false }
        return bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    private static func cursor(_ cursor: EditorCore.Cursor) -> NSCursor {
        switch cursor {
        case .arrow: return .arrow
        case .crosshair: return .crosshair
        case .iBeam: return .iBeam
        case .openHand: return .openHand
        case .closedHand: return .closedHand
        case .resize(let position):
            if #available(macOS 15.0, *) {
                let frame: NSCursor.FrameResizePosition
                switch position {
                case .topLeft: frame = .topLeft
                case .topRight: frame = .topRight
                case .bottomLeft: frame = .bottomLeft
                case .bottomRight: frame = .bottomRight
                case .top: frame = .top
                case .bottom: frame = .bottom
                case .left: frame = .left
                case .right: frame = .right
                }
                return .frameResize(position: frame, directions: .all)
            }
            // macOS 14 has no public diagonal resize cursor.
            switch position {
            case .left, .right: return .resizeLeftRight
            case .top, .bottom: return .resizeUpDown
            case .topLeft, .topRight, .bottomLeft, .bottomRight: return .crosshair
            }
        }
    }

    // MARK: Clipboard and drops

    private func write(_ marks: CopiedMarks, text: String?) {
        let data: Data
        do {
            data = try marks.encoded()
        } catch {
            Log.write("[editor] error copy-failed marks=\(marks.marks.count): \(error)")
            return
        }
        let item = NSPasteboardItem()
        item.setData(data, forType: CopiedMarks.pasteboardType)
        if let text { item.setString(text, forType: .string) }
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    /// What Cmd+V has to paste: copied marks, then a file (which is not text, though Finder puts its
    /// name on the clipboard as well), then text, a URL included, then an image.
    private func clipboardContent() -> EditorCore.PasteContent {
        if let data = pasteboard.data(forType: CopiedMarks.pasteboardType), let marks = CopiedMarks(data: data) { return .marks(marks) }
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) { return .image }
        if let text = pasteboard.string(forType: .string) { return .text(text) }
        if let url = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first { return .text(url.absoluteString) }
        if pasteboard.canReadObject(forClasses: [NSImage.self]) { return .image }
        return .other
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        core.isOpen ? .copy : []
    }

    /// A dropped file or image is answered like a pasted image: it is not added, and the editor says so.
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard core.isOpen else { return false }
        handle(.paste(.image))
        return true
    }

    // MARK: VoiceOver

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .image }
    override func accessibilityLabel() -> String? { screenshotName }
}

/// Hosts the picture's and the overlay's layers, y down. It takes no events: the editor view does.
private final class CanvasView: NSView {
    let host = CALayer()

    /// AppKit sets a layer-hosting view's root layer geometry from the view, overwriting a flag set on
    /// the layer, so the view itself must be flipped for its sublayers to run y down.
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = host
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
