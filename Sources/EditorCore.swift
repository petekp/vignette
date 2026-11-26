import CoreGraphics
import Foundation

/// Everything the drawing editor decides, as a reducer with no view in it. The view turns events
/// into `Input`s, runs the `Effect`s each one returns in order, and draws `drawing`, `overlay` and
/// the text being typed. It hit-tests nothing itself: `target(at:)` tests a press against the
/// overlay's handles and dots as drawn, then against the marks by `EditorGeometry.hit`.
///
/// Locations are image px from the image's top-left corner, y down. A size in screen pt becomes px
/// through `zoom`, so it keeps its size on screen; one in pt becomes px through the drawing's point
/// scale.
struct EditorCore {
    // MARK: Inputs

    enum Input {
        /// A screenshot opens with its drawing, or an empty one whose point scale is the display's.
        /// `markStyle` is the renderer's, which the selection frame goes around. `selectsNewest` is
        /// false for a screenshot reached by Left or Right, which opens with nothing selected.
        /// `message` is the message field's words, and `history` the undo and redo steps the screenshot
        /// was left with, which end at this drawing and this message.
        case open(Drawing, style: TextStyle, metrics: EditorMetrics, markStyle: MarkStyle, selectsNewest: Bool = true, message: String = "",
                  history: EditorHistory = EditorHistory())
        /// The pointer moved with no button held.
        case pointerMoved(Pointer)
        /// The pointer left the canvas.
        case pointerExited
        /// The primary button went down. `clickCount` follows the system's double-click interval.
        case pointerPressed(Pointer, clickCount: Int)
        case pointerDragged(Pointer)
        case pointerReleased(Pointer)
        /// A modifier went down or up with no move.
        case modifiersChanged(Modifiers)
        case keyDown(Key, Modifiers, isRepeat: Bool)
        case keyUp(Key)
        /// A tool button in the toolbar.
        case setTool(Tool)
        /// Tab or Shift+Tab came back from the toolbar: the first mark in reading order is selected,
        /// or the last one going backward.
        case enterCanvas(backward: Bool)
        /// The host's zoom: screen pt per image px.
        case zoomChanged(CGFloat)
        /// Where the picture sits: the zoom at which it fits the frame, which a pin keeps its size at,
        /// and the part of the image in view, in px.
        case viewChanged(fit: CGFloat, visible: CGRect)
        /// The pin popover's composer: its words, its keys, or a comment or a pin chosen in a popover.
        case composer(ComposerInput)
        /// VoiceOver's Add Pin: a new pin at the middle of the picture in view.
        case addPin
        /// The text style, sizes and arrowhead the host uses now, in place of the ones `open` gave. The
        /// drawing, the selection, the history, a gesture and a typing session stay; a text keeps its
        /// origin, and its lines break where the new style breaks them.
        case tweaksChanged(style: TextStyle, metrics: EditorMetrics, markStyle: MarkStyle)
        /// The host's rule for how big marks are changed: the drawing is drawn at these point and mark
        /// scales from now on, and goes to the host. The marks keep their places and their sizes in pt.
        case rescaled(pointScale: CGFloat, markScale: CGFloat)
        /// The text of the typing session is now this.
        case typingChanged(String)
        /// The text view ended the session on its own.
        case typingEnded
        /// The person changed the message field's words: by typing, which runs into one step until
        /// `messageTypingEnded`, or by a paste or a cut, each a step of its own.
        case messageChanged(String, StepName)
        /// The message field lost the keys or its caret was moved: the next typing there is a new step.
        case messageTypingEnded
        /// The timer `scheduleTimer` asked for has run out.
        case timerFired
        /// What the clipboard held when `readClipboard` asked, or what was dropped on the editor.
        case paste(PasteContent)
        /// Agents' marks joining the open drawing, already in px and kept inside the image.
        case agentMarks([Mark])
        /// Done in the toolbar.
        case done
        /// Send in the toolbar, to the destination it chose.
        case send(AgentDestination)
        /// The host parks the drawing: for Esc, a swap, or a click outside.
        case park
    }

    /// One pointer event, in image px.
    struct Pointer: Equatable {
        var location: CGPoint
        var modifiers: Modifiers = []
        /// The event's timestamp, in seconds.
        var time: TimeInterval = 0
    }

    struct Modifiers: OptionSet, Hashable {
        let rawValue: Int
        static let shift = Modifiers(rawValue: 1 << 0)
        static let control = Modifiers(rawValue: 1 << 1)
        static let option = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)

        init(rawValue: Int) { self.rawValue = rawValue }

        /// From an event's modifier flags. The device-independent bits are set for the left and the
        /// right key alike, so right Shift is Shift.
        init(eventFlags: UInt) {
            var modifiers: Modifiers = []
            if eventFlags & (1 << 17) != 0 { modifiers.insert(.shift) }
            if eventFlags & (1 << 18) != 0 { modifiers.insert(.control) }
            if eventFlags & (1 << 19) != 0 { modifiers.insert(.option) }
            if eventFlags & (1 << 20) != 0 { modifiers.insert(.command) }
            self = modifiers
        }
    }

    /// A key as the editor reads it.
    enum Key: Hashable {
        /// A key that types a character: as the layout gives it with no modifier but Shift, lowercased.
        case character(Character)
        case returnKey, escape, tab, delete, forwardDelete, left, right, up, down

        /// From an event's key code and its characters ignoring modifiers. Nil for a key the editor never reads.
        init?(keyCode: UInt16, characters: String?) {
            switch keyCode {
            case 36, 76: self = .returnKey
            case 53: self = .escape
            case 48: self = .tab
            case 51: self = .delete
            case 117: self = .forwardDelete
            case 123: self = .left
            case 124: self = .right
            case 125: self = .down
            case 126: self = .up
            default:
                guard let character = characters?.lowercased().first else { return nil }
                self = .character(character)
            }
        }

        var direction: CGVector? {
            switch self {
            case .left: return CGVector(dx: -1, dy: 0)
            case .right: return CGVector(dx: 1, dy: 0)
            case .up: return CGVector(dx: 0, dy: -1)
            case .down: return CGVector(dx: 0, dy: 1)
            default: return nil
            }
        }
    }

    enum Tool: String, CaseIterable {
        case select, rectangle, arrow, text, comment

        var label: String {
            switch self {
            case .select: return "Select"
            case .rectangle: return "Rectangle"
            case .arrow: return "Arrow"
            case .text: return "Text"
            case .comment: return "Comment"
            }
        }

        /// Picks the tool, with or without Shift, while nothing is being typed.
        var key: Character {
            switch self {
            case .select: return "v"
            case .rectangle: return "r"
            case .arrow: return "a"
            case .text: return "t"
            case .comment: return "c"
            }
        }

        /// The SF Symbol the toolbar shows.
        var symbol: String {
            switch self {
            case .select: return "cursorarrow"
            case .rectangle: return "rectangle"
            case .arrow: return "arrow.up.right"
            case .text: return "textformat"
            case .comment: return "text.bubble"
            }
        }
    }

    enum PasteContent {
        case items(CopiedItems)
        case text(String)
        /// An image, or a file dropped on the editor.
        case image
        case other
    }

    // MARK: Effects

    enum Effect: Equatable {
        /// The active tool changed; the toolbar shows it.
        case tool(Tool)
        case cursor(Cursor)
        /// Start the text view on this text mark, or move its caret when it is already there.
        case beginTyping(Mark.ID, Caret)
        /// Keep this key: a tool key pressed right after a box or an arrow was drawn. It is the note's
        /// first character if a character follows it.
        case holdKey
        /// The kept key and this one go to the text view, which types them into the note just begun.
        case passKeysToText
        /// The session is over: the text view goes, and the mark draws the text.
        case endTyping
        /// The press landed in the text being typed: the text view takes it and what follows it.
        case passPressToText
        /// Start the `handOverDelay` timer again from now.
        case scheduleTimer
        case cancelTimer
        /// The drawing for the host to store. With no marks, the host removes its file.
        case handOver(Drawing)
        /// The marks and pins on the clipboard in Vignette's own type, and as plain text the words of
        /// any texts among them and the pins' words.
        case copyItems(CopiedItems, text: String?)
        /// The drawing's rendering on the clipboard, the same as Done's.
        case copyDrawing(Drawing)
        /// Cmd+V: read the clipboard and answer with `paste`.
        case readClipboard
        /// The system beep: a key that cannot act, such as Cmd+V with an image on the clipboard.
        case beep
        case zoom(ZoomRequest)
        /// For VoiceOver.
        case announce(String)
        /// Undo or redo changed the message: the field shows these words.
        case message(String)
        /// Tab went past the last mark, or Shift+Tab past the first: the toolbar's controls come next.
        case leaveCanvas(backward: Bool)
        /// M or P: the message that goes with Send.
        case focusMessage
        /// Left or Right with nothing selected, nothing typed and no drag: the host opens the
        /// screenshot beside this one, or beeps.
        case page(Page, isRepeat: Bool)
        /// Ask the host to close the editor.
        case close
        /// The pin popover is now this, or closed with nil.
        case composer(Composer?)
        /// A click on a cluster: its pins, in number order, listed by the cluster at this rect in px.
        case showCluster([Pin.ID], at: CGRect)
        /// Render this drawing and finish.
        case done(Drawing)
        /// Render this drawing and send it; the editor stays open. A key's send has no destination:
        /// it goes where the toolbar's filled button sends.
        case send(Drawing, to: AgentDestination?)
    }

    enum Page: Equatable {
        case older, newer

        init?(_ key: Key) {
            switch key {
            case .left: self = .older
            case .right: self = .newer
            default: return nil
            }
        }
    }

    enum Caret: Equatable {
        /// At the character nearest this point.
        case at(CGPoint)
        case end
        case selectAll
    }

    enum Cursor: Equatable {
        case arrow, crosshair, iBeam, openHand, closedHand
        case resize(HandlePosition)
    }

    enum ZoomRequest: Equatable {
        case zoomIn, zoomOut, fit
        /// Twice as close at this point, or back to fit from anywhere closer.
        case smart(at: CGPoint)
    }

    // MARK: State

    private(set) var isOpen = false
    var drawing = Drawing(key: "", pixels: PixelSize(width: 0, height: 0), pointScale: 1, marks: [])
    private(set) var style = TextStyle.standard
    private(set) var metrics = EditorMetrics.standard
    private(set) var markStyle = MarkStyle.standard
    private let layouts = TextLayoutCache()
    private(set) var tool = Tool.rectangle
    /// The host's to set, whenever what its bar offers changes. Opening an image leaves it alone.
    var finishes = Finishes()
    /// Marks and pins.
    var selection: Set<Mark.ID> = []
    private(set) var gesture: Gesture?
    private(set) var hover: Target?
    private(set) var typing: Typing?
    private(set) var undoSteps: [HistoryStep] = []
    private(set) var redoSteps: [HistoryStep] = []
    /// The message field's words, as the person and the history left them.
    private(set) var message = ""
    /// The top undo step is the message typing that `messageChanged` runs into.
    private var typingMessage = false
    /// Screen pt per image px.
    private(set) var zoom: CGFloat = 1
    private(set) var fitZoom: CGFloat = 1
    /// The part of the image in view, in px; null until the host says.
    private(set) var visible = CGRect.null
    /// The pin whose popover is open.
    var composer: Composer?
    var composerSelectionBefore: Set<Mark.ID>?
    private var reportedComposer: Composer?
    /// The changes an open gesture or typing session has made so far.
    var edit: MarkEdit?
    private(set) var pointer: CGPoint?
    private(set) var modifiers: Modifiers = []
    private var heldArrows: Set<Key> = []
    /// The top undo step is the nudge the arrow keys held now are making.
    private var nudging = false
    /// The box or arrow just drawn, which a typed character gives a note.
    private var noteMark: NoteMark?
    /// The drawing changed since it last went to the host.
    private var unsaved = false
    private var reportedTool: Tool?
    private var reportedCursor: Cursor?
    private var announcedSelection: Set<Mark.ID> = []
    private var effects: [Effect] = []

    /// A press and what it has become.
    struct Gesture {
        let press: Press
        var phase: Phase
        /// The latest pointer location, so a modifier change with no move updates the gesture.
        var pointer: CGPoint
        /// Where the pointer has been while the Arrow tool draws, after the press, inside the image.
        var stroke: [CGPoint] = []
    }

    struct Press {
        let location: CGPoint
        let time: TimeInterval
        let target: PressTarget
        /// The selection before the press changed it, which Esc puts back.
        let selectionBefore: Set<Mark.ID>
    }

    enum PressTarget: Equatable {
        /// Empty space: a drag does what the tool does.
        case empty
        /// Empty space inside the frame of several selected marks, in Select: a drag moves them and
        /// a click clears them.
        case frame
        case mark(Mark.ID, click: Click)
        case handle(Mark.ID, HandlePosition, click: Click)
        case dot(Mark.ID, DotKind)
        case pin(Pin.ID, click: Click)
        case cluster([Pin.ID])
    }

    /// What a press on a mark or its handle does when the button comes up without a drag.
    enum Click: Equatable { case nothing, deselect, selectOnly, type(Caret) }

    enum Phase: Equatable {
        /// Not yet past the drag distance.
        case pressed
        /// A rectangle or an arrow being drawn.
        case drawing(Mark.ID)
        /// A Comment tool drag choosing a new pin's area.
        case placing(Pin.ID)
        /// A Text tool drag setting a new text's wrap width.
        case wrapping
        /// With Shift, the brush adds to the selection from before the press.
        case brushing
        case moving(originals: [Mark.ID], copies: [Mark.ID])
        case resizing(Mark.ID, HandlePosition)
        case draggingEnd(Mark.ID, DotKind)
        case bending(Mark.ID)
    }

    struct NoteMark {
        let id: Mark.ID
        var toolLetter = HeldToolLetter()
    }

    /// A tool key is waiting to learn whether it began a note (`holdKey`).
    var holdsKey: Bool { noteMark?.toolLetter.toolBefore != nil }

    struct Typing: Equatable {
        let id: Mark.ID
        /// Where the text is held as it grows and shrinks: its top left corner when the session began,
        /// or for a new note the side of its mark it hangs from.
        let anchor: TextAnchor
        /// The text's wrap width when the session began. A note held by its right edge or its centre
        /// gets one while it is too wide for its room, and loses it again when it shrinks back.
        let wrap: CGFloat?
        /// The text's size when the session began. As it grows it gets smaller than this, and back as it
        /// shrinks, unless it has a wrap width (`EditorGeometry.fittedSize`).
        let size: CGFloat
        /// The session began at a click in the text, so the click that makes it a double-click selects all of it.
        var startedByClick: Bool
        /// The words when the session began. An agent's note whose words the person changed is theirs.
        var startText = ""
    }

    var geometry: EditorGeometry {
        EditorGeometry(pixels: drawing.pixels, pointScale: drawing.pointScale, style: style, metrics: metrics, zoom: zoom, layouts: layouts,
                       markStyle: markStyle, typing: typing?.id)
    }

    var canUndo: Bool { !undoSteps.isEmpty }
    var canRedo: Bool { !redoSteps.isEmpty }
    /// What the Edit menu says for Undo: "Undo Arrow", or "Undo" with nothing to undo.
    var undoTitle: String { HistoryStep.menuTitle(undoSteps.last, redo: false) }
    var redoTitle: String { HistoryStep.menuTitle(redoSteps.last, redo: true) }
    var history: EditorHistory { EditorHistory(undo: undoSteps, redo: redoSteps) }

    // MARK: Reducing

    mutating func reduce(_ input: Input) -> [Effect] {
        effects = []
        if case .open(let drawing, let style, let metrics, let markStyle, let selectsNewest, let message, let history) = input {
            open(drawing, style: style, metrics: metrics, markStyle: markStyle, selectsNewest: selectsNewest)
            if isOpen {
                self.message = message
                (undoSteps, redoSteps) = (history.undo, history.redo)
            }
        } else if isOpen {
            if !input.keepsNudge { nudging = false }
            if !input.keepsNoteMark { noteMark = nil }
            handle(input)
        }
        if isOpen { settle() }
        let result = effects
        effects = []
        return result
    }

    private mutating func handle(_ input: Input) {
        switch input {
        case .open: break
        case .pointerMoved(let pointer): moved(pointer)
        case .pointerExited:
            pointer = nil
            if gesture == nil { hover = nil }
        case .pointerPressed(let pointer, let clickCount): pressed(pointer, clickCount: clickCount)
        case .pointerDragged(let pointer): dragged(pointer)
        case .pointerReleased(let pointer): released(pointer)
        case .modifiersChanged(let modifiers):
            self.modifiers = modifiers
            if var gesture, gesture.phase != .pressed {
                update(&gesture)
                self.gesture = gesture
            }
        case .keyDown(let key, let modifiers, let isRepeat): keyDown(key, modifiers, isRepeat: isRepeat)
        case .keyUp(let key):
            heldArrows.remove(key)
            if heldArrows.isEmpty { nudging = false }
        case .setTool(let tool):
            if gesture != nil { cancelGesture() }
            if typing != nil { endTyping() }
            if composer != nil { closeComposer() }
            self.tool = tool
        case .enterCanvas(let backward):
            if gesture != nil { cancelGesture() }
            if typing != nil { endTyping() }
            let order = readingOrder
            selection = (backward ? order.last : order.first).map { [$0] } ?? []
        case .zoomChanged(let zoom):
            if zoom > 0, zoom.isFinite { self.zoom = zoom }
        case .viewChanged(let fit, let visible):
            if fit > 0, fit.isFinite { fitZoom = fit }
            self.visible = visible
        case .composer(let input): composerInput(input)
        case .addPin: placePinInView()
        case .tweaksChanged(let style, let metrics, let markStyle):
            self.style = style
            self.metrics = metrics
            self.markStyle = markStyle
        case .rescaled(let pointScale, let markScale):
            guard pointScale != drawing.pointScale || markScale != drawing.markScale else { break }
            drawing.pointScale = pointScale
            drawing.markScale = markScale
            if !drawing.isEmpty { changed() }
        case .typingChanged(let text): typed(text)
        case .typingEnded: endTyping()
        case .messageChanged(let words, let name): messageChanged(words, name)
        case .messageTypingEnded: typingMessage = false
        case .timerFired: timerFired()
        case .paste(let content): paste(content)
        case .agentMarks(let marks): join(marks)
        case .done: finish(.done)
        case .send(let destination): finish(.send, to: destination)
        case .park: park()
        }
    }

    /// Reports what an input changed that the view shows on its own: the tool, the cursor, and the
    /// selection for VoiceOver.
    private mutating func settle() {
        if let hovered = hover, !exists(hovered) { hover = nil }
        if composer != reportedComposer {
            reportedComposer = composer
            emit(.composer(composer))
        }
        if tool != reportedTool {
            reportedTool = tool
            emit(.tool(tool))
            emit(.announce(tool.label))
        }
        if gesture == nil { hover = pointer.flatMap { target(at: $0) } }
        if cursor != reportedCursor {
            reportedCursor = cursor
            emit(.cursor(cursor))
        }
        if gesture?.phase == .brushing { return }
        if selection != announcedSelection {
            announcedSelection = selection
            if let words = selectionWords { emit(.announce(words)) }
        }
    }

    mutating func emit(_ effect: Effect) {
        effects.append(effect)
    }

    // MARK: Opening, parking and handing over

    private mutating func open(_ drawing: Drawing, style: TextStyle, metrics: EditorMetrics, markStyle: MarkStyle, selectsNewest: Bool) {
        if typing != nil { emit(.endTyping) }
        if composer != nil { emit(.composer(nil)) }
        let kept = (zoom, fitZoom, visible, finishes, effects)
        self = EditorCore()
        (zoom, fitZoom, visible, finishes, effects) = kept
        guard drawing.pixels.width > 0, drawing.pixels.height > 0, drawing.pointScale > 0, drawing.pointScale.isFinite else { return }
        isOpen = true
        self.drawing = drawing
        self.style = style
        self.metrics = metrics
        self.markStyle = markStyle
        tool = drawing.isEmpty ? .rectangle : .select
        // The newest mark the person drew, never an agent's.
        if selectsNewest, let newest = drawing.marks.last(where: { !$0.agent }) { selection = [newest.id] }
        announcedSelection = selection
        reportedTool = tool
        emit(.cancelTimer)
        emit(.tool(tool))
    }

    /// Ends what is under way the way park, Done and Send need: a drag as if released, and typing
    /// with its empty text removed.
    private mutating func finishForHost() {
        if gesture != nil { released(nil) }
        if typing != nil { endTyping() }
        if composer != nil { closeComposer() }
    }

    mutating func finish(_ finish: Finish, to destination: AgentDestination? = nil) {
        finishForHost()
        emit(finish == .done ? .done(drawingForHost) : .send(drawingForHost, to: destination))
    }

    private mutating func park() {
        finishForHost()
        emit(.cancelTimer)
        emit(.handOver(drawingForHost))
        unsaved = false
        isOpen = false
        hover = nil
        pointer = nil
        heldArrows = []
    }

    private mutating func timerFired() {
        // The button is held: the drawing waits for the release.
        if gesture != nil { return emit(.scheduleTimer) }
        if unsaved { handOver() }
    }

    private mutating func handOver() {
        emit(.handOver(drawingForHost))
        unsaved = false
    }

    /// The drawing as the host stores it: without what a held button is still drawing, and without a
    /// text being typed that holds no text yet.
    var drawingForHost: Drawing {
        var result = drawing
        if gesture != nil, let edit {
            result.marks = edit.reverted(result.marks)
            result.pins = edit.startPins
        }
        result.pins.removeAll { $0.number == 0 }
        if let typing, let mark = result.marks.first(where: { $0.id == typing.id }), Self.isBlank(mark) {
            result.marks.removeAll { $0.id == typing.id }
        }
        return result
    }

    /// Something changed that the host must receive.
    mutating func changed() {
        unsaved = true
        emit(.scheduleTimer)
    }

    // MARK: Changing marks

    func mark(_ id: Mark.ID) -> Mark? { drawing.marks.first { $0.id == id } }

    private func index(of id: Mark.ID) -> Int? { drawing.marks.firstIndex { $0.id == id } }

    /// Replaces the mark with the same id, kept inside the image, noting it in the open edit.
    private mutating func replace(_ mark: Mark) {
        guard let index = index(of: mark.id), let placed = geometry.placedKeepingLines(mark) else { return }
        edit?.note(mark.id)
        drawing.marks[index] = placed
    }

    /// Puts a new mark on top, kept inside the image, noting it in the open edit.
    mutating func add(_ mark: Mark) {
        guard index(of: mark.id) == nil, let placed = geometry.placedKeepingLines(mark) else { return }
        edit?.note(mark.id)
        drawing.marks.append(placed)
    }

    private mutating func remove(_ id: Mark.ID) {
        guard let index = index(of: id) else { return }
        edit?.note(id)
        drawing.marks.remove(at: index)
        selection.remove(id)
    }

    /// Runs `change` as one undo step of its own, beside any gesture or typing session under way.
    mutating func step(named name: StepName, _ change: (inout EditorCore) -> Void) {
        let open = edit
        edit = newEdit
        change(&self)
        commitEdit(named: name)
        edit = open
    }

    /// Ends the open edit, turning what it changed into an undo step named `name`; returns whether it
    /// changed anything.
    @discardableResult
    mutating func commitEdit(named name: StepName) -> Bool {
        guard let edit else { return false }
        self.edit = nil
        guard let step = edit.step(named: name, ending: drawing, selection: selection) else { return false }
        push(.drawing(step))
        changed()
        return true
    }

    /// Puts back every mark the open edit touched, exactly as it was.
    mutating func revertEdit() {
        guard let edit else { return }
        self.edit = nil
        drawing.marks = edit.reverted(drawing.marks)
        drawing.pins = edit.startPins
    }

    private mutating func push(_ step: HistoryStep) {
        undoSteps.append(step)
        redoSteps = []
        typingMessage = false
    }

    /// Undo and redo say what they did, "Undo Arrow", in place of the selection they leave.
    private mutating func undo() {
        if composer != nil { closeComposer() }
        guard let step = undoSteps.popLast() else { return }
        restore(step, forward: false)
        redoSteps.append(step)
        emit(.announce(HistoryStep.menuTitle(step, redo: false)))
    }

    private mutating func redo() {
        if composer != nil { closeComposer() }
        guard let step = redoSteps.popLast() else { return }
        restore(step, forward: true)
        undoSteps.append(step)
        emit(.announce(HistoryStep.menuTitle(step, redo: true)))
    }

    private mutating func restore(_ step: HistoryStep, forward: Bool) {
        typingMessage = false
        switch step {
        case .drawing(let step):
            drawing = step.applied(to: drawing, forward: forward)
            let ids = Set(drawing.marks.map(\.id) + drawing.pins.map(\.id))
            selection = (forward ? step.selectionAfter : step.selectionBefore).intersection(ids)
            announcedSelection = selection
            changed()
        case .message(let step):
            message = forward ? step.after : step.before
            emit(.message(message))
        }
    }

    /// The message field's words changed. Typing runs into the step it began until the field loses
    /// the keys, its caret moves, or another step comes; a paste or a cut is a step of its own. The
    /// host stores the message itself, so this hands nothing over.
    private mutating func messageChanged(_ words: String, _ name: StepName) {
        guard words != message else { return }
        if typingMessage, name == .typing, case .message(var open)? = undoSteps.last {
            open.after = words
            if open.before == words {
                undoSteps.removeLast()
                typingMessage = false
            } else {
                undoSteps[undoSteps.count - 1] = .message(open)
            }
        } else {
            push(.message(MessageStep(name: name, before: message, after: words)))
            typingMessage = name == .typing
        }
        message = words
    }

    // MARK: Pointer

    private mutating func moved(_ event: Pointer) {
        // A move with no button while a press is held means its release never came.
        if gesture != nil { cancelGesture() }
        pointer = event.location
        modifiers = event.modifiers
    }

    private mutating func pressed(_ event: Pointer, clickCount: Int) {
        if gesture != nil { cancelGesture() }
        pointer = event.location
        modifiers = event.modifiers
        // A Control-click is a right-click, and a right-click does nothing.
        if event.modifiers.contains(.control) { return }
        let at = event.location
        if let typing {
            if let box = typingBox, box.encloses(at) {
                if clickCount >= 2, typing.startedByClick {
                    self.typing?.startedByClick = false
                    emit(.beginTyping(typing.id, .selectAll))
                } else {
                    emit(.passPressToText)
                }
                return
            }
            if case .mark(let id)? = target(at: at), id != typing.id, mark(id)?.kind == .text {
                endTyping()
                beginTyping(id, caret: .at(at), edit: newEdit)
                return
            }
            endTyping()
        }
        if composer != nil, !keepsComposer(at: at) { closeComposer() }
        let before = selection
        func press(_ target: PressTarget) {
            gesture = Gesture(press: Press(location: at, time: event.time, target: target, selectionBefore: before), phase: .pressed, pointer: at)
        }
        var hit = target(at: at)
        if case .dot(let id, _)? = hit, event.modifiers.contains(.option) { hit = .mark(id) }
        hover = hit
        switch hit {
        case .handle(let id, let position)?:
            let types = clickCount >= 2 && mark(id)?.kind == .text
            press(.handle(id, position, click: types ? .type(.selectAll) : .nothing))
        case .dot(let id, let kind)?:
            press(.dot(id, kind))
        case .pin(let id)?:
            if clickCount >= 2 {
                openComposer(on: id)
                return
            }
            press(.pin(id, click: pinClick(id, event.modifiers)))
        case .cluster(let ids)?:
            press(.cluster(ids))
        case .mark(let id)?:
            guard let mark = mark(id) else { return }
            if mark.kind == .text, tool == .text || clickCount >= 2 {
                beginTyping(id, caret: tool == .text ? .at(at) : .selectAll, edit: newEdit)
                return
            }
            var click = Click.nothing
            if !event.modifiers.isDisjoint(with: [.shift, .command]) {
                if selection.contains(id) { click = .deselect } else { selection.insert(id) }
            } else if selection.contains(id) {
                if selection.count > 1 { click = .selectOnly } else if mark.kind == .text, clickCount == 1 { click = .type(.at(at)) }
            } else {
                selection = [id]
            }
            press(.mark(id, click: click))
        case nil:
            if tool == .select, clickCount >= 2 {
                emit(.zoom(.smart(at: at)))
                return
            }
            if tool == .select, selection.count > 1, !event.modifiers.contains(.shift),
               let frame = geometry.selectionFrame(of: drawing.marks.filter { selection.contains($0.id) }), frame.encloses(at) {
                press(.frame)
                return
            }
            if tool == .select, !event.modifiers.contains(.shift) { selection = [] }
            press(.empty)
        }
    }

    private mutating func dragged(_ event: Pointer) {
        guard var gesture else { return }
        pointer = event.location
        modifiers = event.modifiers
        gesture.pointer = event.location
        if gesture.phase == .pressed {
            guard let phase = dragPhase(for: gesture.press, at: event) else {
                self.gesture = gesture
                return
            }
            gesture.phase = phase
            startDrag(&gesture)
        }
        if case .drawing = gesture.phase, tool == .arrow { gesture.stroke.append(geometry.inside(event.location)) }
        update(&gesture)
        self.gesture = gesture
    }

    /// What a press becomes once the pointer has moved far enough, or nil while it has not.
    private func dragPhase(for press: Press, at event: Pointer) -> Phase? {
        let dx = event.location.x - press.location.x, dy = event.location.y - press.location.y
        if press.target == .empty, tool == .text {
            let waited = event.time - press.time >= metrics.textDragDelay
            return waited && abs(dx) * zoom > metrics.textDragDistance ? .wrapping : nil
        }
        guard hypot(dx, dy) * zoom > metrics.dragDistance else { return nil }
        switch press.target {
        case .empty:
            switch tool {
            case .select: return .brushing
            case .rectangle, .arrow: return .drawing(UUID())
            case .comment: return drawing.pins.count < Pin.maxCount ? .placing(UUID()) : nil
            case .text: return nil
            }
        case .cluster:
            return nil
        case .frame, .mark, .pin:
            let originals = drawing.marks.filter { selection.contains($0.id) }.map(\.id)
            return .moving(originals: originals, copies: originals.map { _ in UUID() })
        case .handle(let id, let position, _): return .resizing(id, position)
        case .dot(let id, .middle): return .bending(id)
        case .dot(let id, let kind): return .draggingEnd(id, kind)
        }
    }

    /// Opens the edit of a drag that changes marks, and notes the marks it starts from.
    private mutating func startDrag(_ gesture: inout Gesture) {
        hover = nil
        switch gesture.phase {
        case .drawing, .placing:
            edit = newEdit
            selection = []
        case .moving(let originals, _):
            edit = newEdit
            for id in originals { edit?.note(id) }
        case .resizing(let id, _):
            edit = resizeEdit()
            edit?.note(id)
        case .draggingEnd(let id, let kind):
            edit = newEdit
            edit?.note(id)
            hover = .dot(id, kind)
        case .bending(let id):
            edit = newEdit
            edit?.note(id)
            hover = .dot(id, .middle)
        case .pressed, .wrapping, .brushing:
            break
        }
    }

    /// Redraws the gesture from where it started to the pointer and the modifiers held now.
    private mutating func update(_ gesture: inout Gesture) {
        let press = gesture.press
        let at = gesture.pointer
        let delta = CGVector(dx: at.x - press.location.x, dy: at.y - press.location.y)
        switch gesture.phase {
        case .pressed, .wrapping:
            break
        case .placing(let id):
            placeArea(id, from: press.location, to: at)
        case .drawing(let id):
            let start = geometry.inside(press.location)
            let shape: Mark.Geometry
            if tool == .rectangle {
                shape = .rectangle(geometry.newRectangle(from: start, to: at, square: modifiers.contains(.shift), centred: modifiers.contains(.option)))
            } else if modifiers.contains(.shift) {
                let end = geometry.arrowEnd(from: start, toward: at, snapping: true)
                guard end != start else { return }
                shape = .arrow(Mark.Arrow(start: start, end: end))
            } else {
                guard let arrow = geometry.freehandArrow(along: [start] + gesture.stroke) else { return }
                shape = .arrow(arrow)
            }
            if var mark = mark(id) {
                mark.geometry = shape
                replace(mark)
            } else {
                add(Mark(id: id, geometry: shape))
            }
        case .brushing:
            let base = modifiers.contains(.shift) ? press.selectionBefore : []
            let brush = CGRect(x: min(press.location.x, at.x), y: min(press.location.y, at.y),
                               width: abs(at.x - press.location.x), height: abs(at.y - press.location.y))
            selection = base.union(drawing.marks.filter { geometry.brush(brush, selects: $0) }.map(\.id)).union(pins(in: brush))
        case .moving(let originals, let copies):
            move(originals: originals, copies: copies, by: delta)
        case .resizing(let id, let position):
            if resizePin(id, by: position, delta: delta) { return }
            guard var mark = edit?.original(id) else { return }
            switch mark.geometry {
            case .rectangle(let frame):
                mark.geometry = .rectangle(geometry.resized(frame, by: position, delta: delta, proportional: modifiers.contains(.shift), fromCenter: modifiers.contains(.option)))
            case .ellipse(let frame):
                mark.geometry = .ellipse(geometry.resized(frame, by: position, delta: delta, proportional: modifiers.contains(.shift), fromCenter: modifiers.contains(.option)))
            case .text(let text):
                mark.geometry = .text(geometry.resized(text, of: mark, by: position, delta: delta, fromCenter: modifiers.contains(.option)))
            case .arrow:
                return
            }
            // A text scaled from a corner grows, so it moves left near the edge as a typed one does.
            guard let resized = geometry.placed(mark) else { return }
            replace(resized)
        case .draggingEnd(let id, let kind):
            guard var mark = edit?.original(id), case .arrow(var arrow) = mark.geometry else { return }
            let other = kind == .start ? arrow.end : arrow.start
            let end = geometry.arrowEnd(from: other, toward: at, snapping: modifiers.contains(.shift))
            guard end != other else { return }
            // A freehand arrow turns and scales about its other end, so its curve keeps its shape.
            let from = kind == .start ? arrow.start : arrow.end
            arrow.via = arrow.via.map { geometry.inside(Self.turned($0, about: other, from: from, to: end)) }
            if kind == .start { arrow.start = end } else { arrow.end = end }
            arrow.bend = arrow.largestBend(arrow.bend, inside: geometry.image)
            mark.geometry = .arrow(arrow)
            replace(mark)
        case .bending(let id):
            guard var mark = edit?.original(id), case .arrow(var arrow) = mark.geometry else { return }
            let dx = arrow.end.x - arrow.start.x, dy = arrow.end.y - arrow.start.y
            let length = hypot(dx, dy)
            guard length > 0 else { return }
            // The pointer's distance from the line between the ends, on the perpendicular through its middle.
            let middle = CGPoint(x: (arrow.start.x + arrow.end.x) / 2, y: (arrow.start.y + arrow.end.y) / 2)
            let bend = (at.x - middle.x) * -dy / length + (at.y - middle.y) * dx / length
            arrow.bend = arrow.largestBend(bend, inside: geometry.image)
            mark.geometry = .arrow(arrow)
            replace(mark)
        }
    }

    /// `point` under the turn and scale about `pivot` that takes `from` to `to`.
    static func turned(_ point: CGPoint, about pivot: CGPoint, from: CGPoint, to: CGPoint) -> CGPoint {
        let a = CGPoint(x: from.x - pivot.x, y: from.y - pivot.y), b = CGPoint(x: to.x - pivot.x, y: to.y - pivot.y)
        let squared = a.x * a.x + a.y * a.y
        guard squared > 0 else { return point }
        // b / a as complex numbers: the rotation and scale in one.
        let cos = (b.x * a.x + b.y * a.y) / squared, sin = (b.y * a.x - b.x * a.y) / squared
        let p = CGPoint(x: point.x - pivot.x, y: point.y - pivot.y)
        return CGPoint(x: pivot.x + p.x * cos - p.y * sin, y: pivot.y + p.x * sin + p.y * cos)
    }

    /// Moves the selection by `delta`, or copies of it with Option while the originals stay put. The
    /// marks stop together at the image's edges, and Shift locks the move to its longer axis.
    private mutating func move(originals: [Mark.ID], copies: [Mark.ID], by delta: CGVector) {
        guard let edit else { return }
        let starts = originals.compactMap { edit.original($0) }
        let pins = edit.startPins.filter { edit.selectionBefore.contains($0.id) }
        guard let extent = movingExtent(of: starts, pins: pins) else { return }
        var delta = delta
        if modifiers.contains(.shift) {
            if abs(delta.dx) >= abs(delta.dy) { delta.dy = 0 } else { delta.dx = 0 }
        }
        delta = geometry.clamped(delta, keeping: extent)
        let copying = modifiers.contains(.option) && !starts.isEmpty
        for (original, copyID) in zip(starts, copies) {
            let moved = geometry.translated(original, by: delta)
            if copying {
                replace(original)
                let copy = Mark(id: copyID, geometry: moved.geometry, agent: moved.agent, agentName: moved.agentName)
                if mark(copyID) == nil { add(copy) } else { replace(copy) }
            } else {
                replace(moved)
                remove(copyID)
            }
        }
        // A copy holds the marks alone, so the pins stay where they were.
        movePins(pins, by: copying ? .zero : delta)
        selection = Set(copying ? copies.filter { mark($0) != nil } : originals + pins.map(\.id))
    }

    /// The button came up at `event`, or, with nil, the drag ends where it is for park, Done or Send.
    private mutating func released(_ event: Pointer?) {
        guard var gesture else { return }
        if let event {
            pointer = event.location
            modifiers = event.modifiers
            gesture.pointer = event.location
            if case .drawing = gesture.phase, tool == .arrow, gesture.stroke.last != geometry.inside(event.location) {
                gesture.stroke.append(geometry.inside(event.location))
            }
            if gesture.phase != .pressed, gesture.phase != .wrapping { update(&gesture) }
        }
        self.gesture = nil
        let press = gesture.press
        switch gesture.phase {
        case .pressed:
            guard event != nil else { return }
            switch press.target {
            case .empty:
                // Select cleared the selection on the press; a click that draws nothing clears it too.
                if tool == .text {
                    newText(at: press.location, wrap: nil)
                } else if tool == .comment {
                    placePin(at: press.location)
                } else if tool != .select {
                    selection = []
                }
            case .frame:
                selection = []
            case .mark(let id, .deselect), .pin(let id, .deselect):
                selection.remove(id)
            case .mark(let id, .selectOnly), .pin(let id, .selectOnly):
                selection = [id]
            case .cluster(let ids):
                showCluster(ids)
            case .mark(let id, .type(let caret)), .handle(let id, _, .type(let caret)):
                beginTyping(id, caret: caret, edit: newEdit)
            case .mark(_, .nothing), .handle, .dot, .pin:
                break
            }
        case .placing(let id):
            finishPlacing(id, at: press.location, released: event != nil)
        case .wrapping:
            guard event != nil else { return }
            let span = wrapSpan(gesture)
            // Brought back under the drag distance, the drag is a click.
            if span.width * zoom < metrics.textDragDistance {
                newText(at: press.location, wrap: nil)
            } else {
                newText(at: CGPoint(x: span.minX, y: press.location.y), wrap: max(span.width, geometry.pt(metrics.newTextSize)))
            }
        case .drawing(let id):
            guard let mark = mark(id) else {
                revertEdit()
                selection = []
                return
            }
            let big: Bool
            switch mark.geometry {
            case .rectangle(let frame): big = min(frame.width, frame.height) * zoom >= metrics.smallestRectangle
            case .arrow(let arrow): big = arrow.exactBody.length * zoom > metrics.shortestArrow
            default: big = false
            }
            if big {
                selection = [id]
                commitEdit(named: Self.drawingStep(mark.kind))
                if event != nil { noteMark = NoteMark(id: id) }
            } else {
                revertEdit()
                selection = []
            }
        case .brushing:
            break
        case .moving(_, let copies):
            commitEdit(named: copies.contains { mark($0) != nil } ? .duplicate : .move)
        case .resizing:
            commitEdit(named: .resize)
            resumeComposerEdit()
        case .draggingEnd:
            commitEdit(named: .arrowEnd)
        case .bending:
            commitEdit(named: .bend)
        }
    }

    private static func drawingStep(_ kind: MarkKind) -> StepName {
        switch kind {
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .arrow: return .arrow
        case .text: return .typing
        }
    }

    /// Esc, a tool key, Cmd+Z, or an input the gesture does not expect: the drawing and the selection
    /// go back to how they were before the press.
    mutating func cancelGesture() {
        guard let gesture else { return }
        self.gesture = nil
        selection = gesture.press.selectionBefore
        revertGestureEdit(gesture.phase)
    }

    // MARK: Hit testing

    /// The selection's handles and dots, the hover, and the brush, as the view draws them and as
    /// `target(at:)` tests them.
    var overlay: Overlay {
        let chosen = drawing.marks.filter { selection.contains($0.id) }
        var overlay = Overlay(selected: chosen.map(\.id))
        if case .mark(let id)? = hover, id != typing?.id { overlay.hovered = id }
        if chosen.count > 1 {
            overlay.frame = geometry.selectionFrame(of: chosen)
        } else if let only = chosen.first {
            // The handles sit on the frame's corners, outside the mark's ink with the outline.
            switch only.geometry {
            case .rectangle(let frame), .ellipse(let frame):
                let outline = geometry.selectionFrame(of: [only]) ?? frame
                overlay.frame = outline
                overlay.handles = geometry.handles(around: outline, of: only.id, markSize: frame.size)
            case .text(let text):
                let box = geometry.layout(text, of: only).box
                let outline = geometry.selectionFrame(of: [only]) ?? box
                overlay.frame = outline
                if typing?.id != only.id { overlay.handles = geometry.handles(around: outline, of: only.id, markSize: box.size) }
            case .arrow:
                break
            }
        }
        overlay.handles += areaPinHandles
        if chosen.count == 1, let mark = chosen.first, case .arrow(let arrow) = mark.geometry {
            for (kind, center) in geometry.dotCenters(of: arrow) {
                overlay.dots.append(Dot(mark: mark.id, kind: kind, center: center, radius: geometry.screen(metrics.dotRadius),
                                        hitRadius: geometry.screen(metrics.dotHitRadius), hovered: hover == .dot(mark.id, kind)))
            }
        }
        if let gesture, gesture.phase == .brushing {
            let a = gesture.press.location, b = gesture.pointer
            overlay.brush = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        }
        if let gesture, gesture.phase == .wrapping {
            let span = wrapSpan(gesture), size = metrics.newTextSize
            let top = geometry.textOrigin(at: geometry.inside(gesture.press.location), size: size).y
            overlay.wrap = CGRect(x: span.minX, y: top, width: span.width, height: geometry.tagHeight(size: size))
        }
        return overlay
    }

    /// The part of the image a Text tool drag spans across, from the press to the pointer.
    private func wrapSpan(_ gesture: Gesture) -> (minX: CGFloat, width: CGFloat) {
        let width = geometry.image.width
        let left = min(max(min(gesture.press.location.x, gesture.pointer.x), 0), width)
        let right = min(max(max(gesture.press.location.x, gesture.pointer.x), 0), width)
        return (left, right - left)
    }

    /// What a press at `point` acts on: a handle or dot of the selection first, with end dots before
    /// middle ones, then a mark by the hit rules, or nil for empty space.
    func target(at point: CGPoint) -> Target? {
        let overlay = self.overlay
        let dots = overlay.dots.filter { $0.kind != .middle } + overlay.dots.filter { $0.kind == .middle }
        if let dot = dots.first(where: { hypot(point.x - $0.center.x, point.y - $0.center.y) <= $0.hitRadius }) {
            return .dot(dot.mark, dot.kind)
        }
        if let handle = overlay.handles.first(where: { $0.hitArea.encloses(point) }) {
            return .handle(handle.mark, handle.position)
        }
        if let pin = pinTarget(at: point) { return pin }
        return markHit(at: point).map(Target.mark)
    }

    /// The mark a point hits. The closest stroke wins; a text's box beats every stroke under it and
    /// loses to a stroke over it; the inside of a selected rectangle or ellipse counts in Select,
    /// after any stroke.
    private func markHit(at point: CGPoint) -> Mark.ID? {
        var closest: (id: Mark.ID, distance: CGFloat)?
        var inside: Mark.ID?
        for mark in drawing.marks.reversed() {
            switch geometry.hit(mark, at: point, insideCounts: tool == .select && selection.contains(mark.id)) {
            case .stroke(let distance)?:
                if closest.map({ distance < $0.distance }) ?? true { closest = (mark.id, distance) }
            case .box?:
                return closest?.id ?? mark.id
            case .inside?:
                if inside == nil { inside = mark.id }
            case nil:
                break
            }
        }
        return closest?.id ?? inside
    }

    // MARK: Typing

    /// Whether the editor takes this key. While a text is being typed it takes Esc, Return without
    /// Shift or Option, and the zoom keys; every other key belongs to the text view, where Return with
    /// Shift or Option is a new line, and so is Return during an input method's composition, which
    /// the view keeps for the text view whatever this says. Otherwise it takes every key but a Command
    /// key it has no command for, such as Cmd+W, which is the app's; during a gesture it takes that
    /// too, since every key but a zoom key cancels the gesture.
    func takesKey(_ key: Key, _ modifiers: Modifiers) -> Bool {
        guard typing != nil else {
            guard gesture == nil, modifiers.contains(.command), case .character(let character) = key else { return true }
            return Command(rawValue: character) != nil || Self.zoomRequest(for: character) != nil
        }
        switch key {
        case .escape: return true
        case .returnKey: return modifiers.isDisjoint(with: [.shift, .option])
        case .character(let character): return modifiers.contains(.command) && Self.zoomRequest(for: character) != nil
        default: return false
        }
    }

    private mutating func newText(at point: CGPoint, wrap: CGFloat?) {
        newText(TextAnchor(geometry.textOrigin(at: geometry.inside(point), size: metrics.newTextSize)), wrap: wrap)
    }

    /// A note for the box or arrow `id`, where `EditorGeometry.notePlace` finds room: beside a box,
    /// and beyond an arrow's tail.
    private mutating func newNote(for id: Mark.ID) {
        let size = metrics.newTextSize
        switch mark(id)?.geometry {
        case .rectangle(let frame)?: newText(geometry.notePlace(beside: frame, size: size), wrap: nil)
        case .arrow(let arrow)?: newText(geometry.notePlace(atTailOf: arrow, size: size), wrap: nil)
        default: break
        }
    }

    private mutating func newText(_ anchor: TextAnchor, wrap: CGFloat?) {
        let id = UUID()
        var edit = newEdit
        edit.note(id)
        var mark = Mark(id: id, geometry: .text(Mark.Text(origin: anchor.point, text: "", wrap: wrap, size: metrics.newTextSize)))
        guard case .text(let empty) = mark.geometry else { return }
        mark.geometry = .text(geometry.anchored(empty, of: mark, to: anchor))
        guard let placed = geometry.placed(mark) else { return }
        drawing.marks.append(placed)
        beginTyping(id, caret: .end, edit: edit, anchor: anchor)
    }

    /// Starts a session on a text, ending any other. `edit` holds what the session changes, so a
    /// text made for it and its first session are one step.
    private mutating func beginTyping(_ id: Mark.ID, caret: Caret, edit: MarkEdit, anchor: TextAnchor? = nil) {
        if typing != nil { endTyping() }
        guard case .text(let text)? = mark(id)?.geometry else { return }
        self.edit = edit
        self.edit?.note(id)
        selection = [id]
        typing = Typing(id: id, anchor: anchor ?? TextAnchor(text.origin), wrap: text.wrap, size: text.size, startedByClick: caret != .end && caret != .selectAll,
                        startText: text.text)
        emit(.beginTyping(id, caret))
    }

    /// The text view's text changed: the mark takes it, capped at what a drawing file may hold, and
    /// grows: a text without a wrap width first gets smaller to fit its room, down to half the new-text
    /// size, and then by the rules in `Mark.placed` it wraps at the image's edge less the margin, moves
    /// left when it started near the right edge, moves up at the bottom, and keeps its start showing.
    private mutating func typed(_ string: String) {
        guard let typing, var mark = mark(typing.id), case .text(var text) = mark.geometry else { return }
        text.text = Self.capped(string)
        text.origin = typing.anchor.point
        text.wrap = typing.wrap
        if text.wrap == nil {
            text.size = geometry.fittedSize(text, of: mark, from: typing.size, floor: min(typing.size, metrics.newTextSize / 2),
                                            anchor: typing.anchor)
        }
        mark.geometry = .text(geometry.anchored(text, of: mark, to: typing.anchor))
        guard let grown = geometry.placed(mark) else { return }
        replace(grown)
        changed()
    }

    /// Ends the session. A text left with no words goes; otherwise the text stays selected.
    mutating func endTyping() {
        guard let typing else { return }
        self.typing = nil
        emit(.endTyping)
        if var mark = mark(typing.id), mark.agent, !Self.isBlank(mark), case .text(let text) = mark.geometry, text.text != typing.startText {
            // The words are the person's now, so the note is drawn as theirs: their colour, their
            // face, and no badge.
            mark.agent = false
            mark.agentName = nil
            if let placed = geometry.placed(mark) {
                replace(placed)
                changed()
            }
        }
        let anchor = typing.anchor
        if var mark = mark(typing.id), !Self.isBlank(mark), case .text(var text) = mark.geometry,
           anchor.horizontal != .leading || anchor.vertical != .top || anchor.ray != nil {
            // Its lines are balanced now, and narrower, so a note held by its right edge, its middle,
            // its bottom or an arrow's tail is held there again at its new size.
            text.origin = anchor.point
            text.wrap = typing.wrap
            mark.geometry = .text(geometry.anchored(text, of: mark, to: anchor))
            if let placed = geometry.placed(mark), placed != self.mark(typing.id) {
                replace(placed)
                changed()
            }
        }
        if let mark = mark(typing.id), Self.isBlank(mark) { remove(typing.id) }
        commitEdit(named: .typing)
    }

    static func isBlank(_ mark: Mark) -> Bool {
        guard case .text(let text) = mark.geometry else { return false }
        return text.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// `text` cut to what a drawing file may hold: `MarkFields`' characters and bytes.
    static func capped(_ text: String) -> String {
        var capped = "", bytes = 0
        for character in text.prefix(MarkFields.maxTextLength) {
            bytes += character.utf8.count
            guard bytes <= MarkFields.maxTextBytes else { break }
            capped.append(character)
        }
        return capped
    }

    // MARK: Keys

    private mutating func keyDown(_ key: Key, _ modifiers: Modifiers, isRepeat: Bool) {
        self.modifiers = modifiers
        let command = modifiers.contains(.command)
        if typing != nil {
            switch key {
            case .escape: endTyping()
            case .returnKey where modifiers.isDisjoint(with: [.shift, .option]):
                endTyping()
                if command { finish(finishes.commandReturn) }
            case .character(let character) where command:
                if let request = Self.zoomRequest(for: character) { emit(.zoom(request)) }
            default: break
            }
            return
        }
        if gesture != nil {
            if case .character(let character) = key, command, let request = Self.zoomRequest(for: character) {
                return emit(.zoom(request))
            }
            // Esc, a tool key, Cmd+Z, and every key the gesture does not expect cancel it.
            cancelGesture()
            if let tool = toolKey(key, modifiers) { self.tool = tool }
            return
        }
        if let note = noteMark, startsNote(for: note, key, modifiers, isRepeat: isRepeat) { return }
        noteMark = nil
        if key.direction != nil {
            if selection.isEmpty, modifiers.isEmpty, let page = Page(key) { return emit(.page(page, isRepeat: isRepeat)) }
            if !isRepeat, heldArrows.contains(key) { heldArrows = [] }
            heldArrows.insert(key)
            return nudge(by: modifiers.contains(.shift) ? Self.longNudge : Self.nudge)
        }
        switch key {
        case .escape:
            emit(.close)
        case .returnKey:
            if modifiers.isDisjoint(with: [.shift, .option]) {
                finish(command ? finishes.commandReturn : finishes.returnKey)
            } else if selection.count == 1, let id = selection.first, mark(id)?.kind == .text {
                beginTyping(id, caret: .selectAll, edit: newEdit)
            } else if selection.count == 1, let id = selection.first, pin(id) != nil {
                openComposer(on: id)
            } else if selection.isEmpty, tool == .comment {
                placePinInView()
            }
        case .tab:
            // The marks and pins, then the toolbar's controls, then the marks and pins again.
            let order = readingOrder
            let backward = modifiers.contains(.shift)
            let positions = order.indices.filter { selection.contains(order[$0]) }
            let next = backward ? (positions.first ?? order.count) - 1 : (positions.last ?? -1) + 1
            guard order.indices.contains(next) else {
                selection = []
                return emit(.leaveCanvas(backward: backward))
            }
            selection = [order[next]]
        case .character(let character) where modifiers.isEmpty && Self.messageKeys.contains(character):
            emit(.focusMessage)
        case .delete, .forwardDelete:
            deleteSelection()
        case .character(let character) where command:
            switch Command(rawValue: character) {
            case .undo:
                if modifiers.contains(.shift) { redo() } else { undo() }
            case .selectAll: selection = Set(drawing.marks.map(\.id) + drawing.pins.map(\.id))
            case .copy: copy()
            case .cut:
                // Unlike Copy, Cut never falls back to the drawing, which it could not delete.
                guard drawing.marks.contains(where: { selection.contains($0.id) }) || !selectedPins.isEmpty else { break }
                copy()
                deleteSelection(as: .cut)
            case .paste: emit(.readClipboard)
            case .duplicate: duplicate()
            case nil:
                if let request = Self.zoomRequest(for: character) { emit(.zoom(request)) }
            }
        default:
            if let tool = toolKey(key, modifiers) { self.tool = tool }
        }
    }

    /// A key after a box or an arrow was drawn, while it is still the selection. A character begins a
    /// note for it, except a tool key, which `HeldToolLetter` holds until the next key shows whether
    /// it began a word. True when the key was taken.
    private mutating func startsNote(for note: NoteMark, _ key: Key, _ modifiers: Modifiers, isRepeat: Bool) -> Bool {
        guard selection == [note.id], mark(note.id) != nil else { return false }
        var letter = note.toolLetter
        let held = letter.toolBefore != nil
        switch letter.key(HeldToolLetter.character(key, modifiers), isRepeat: isRepeat, canHold: true, tool: tool) {
        case .hold(let picked):
            noteMark = NoteMark(id: note.id, toolLetter: letter)
            tool = picked
            emit(.holdKey)
            return true
        case .swallow:
            return true
        case .type(let before):
            tool = before
        case .pass:
            guard !held, !isRepeat, case .character(let character) = key, modifiers.isDisjoint(with: [.command, .control]),
                  !character.isWhitespace else { return false }
        }
        noteMark = nil
        newNote(for: note.id)
        emit(.passKeysToText)
        return true
    }

    /// The editor's own Command keys when nothing is typed, by the character held with Command.
    /// Shift+Cmd+Z is `undo` with Shift, which redoes.
    private enum Command: Character {
        case undo = "z", selectAll = "a", copy = "c", cut = "x", paste = "v", duplicate = "d"
    }

    /// M for message and P for prompt: the field beside Send.
    static let messageKeys: Set<Character> = ["m", "p"]

    private func toolKey(_ key: Key, _ modifiers: Modifiers) -> Tool? {
        guard case .character(let character) = key, modifiers.isSubset(of: .shift) else { return nil }
        return Tool.allCases.first { $0.key == character }
    }

    static func zoomRequest(for character: Character) -> ZoomRequest? {
        switch character {
        case "=", "+": return .zoomIn
        case "-": return .zoomOut
        case "0": return .fit
        default: return nil
        }
    }

    /// Moves the selection one nudge along every arrow key held, stopping together at the image's
    /// edges. The presses and repeats of one hold are one undo step.
    private mutating func nudge(by points: CGFloat) {
        let marks = drawing.marks.filter { selection.contains($0.id) }, pins = drawing.pins.filter { selection.contains($0.id) }
        guard let extent = movingExtent(of: marks, pins: pins) else { return }
        var direction = CGVector.zero
        for key in heldArrows { if let d = key.direction { direction.dx += d.dx; direction.dy += d.dy } }
        let offset = geometry.clamped(CGVector(dx: direction.dx * geometry.pt(points), dy: direction.dy * geometry.pt(points)), keeping: extent)
        let continuing = nudging
        let depth = undoSteps.count
        step(named: .move) { core in
            for mark in marks { core.replace(core.geometry.translated(mark, by: offset)) }
            core.movePins(pins, by: offset)
        }
        guard undoSteps.count > depth else { return }
        nudging = true
        if continuing, undoSteps.count >= 2, case .drawing(let later) = undoSteps[undoSteps.count - 1],
           case .drawing(let earlier) = undoSteps[undoSteps.count - 2] {
            undoSteps.removeLast(2)
            if let merged = earlier.merged(with: later) { undoSteps.append(.drawing(merged)) }
        }
    }

    private mutating func deleteSelection(as name: StepName = .delete) {
        let ids = drawing.marks.map(\.id).filter { selection.contains($0) }
        let pins = drawing.pins.map(\.id).filter { selection.contains($0) }
        guard !ids.isEmpty || !pins.isEmpty else { return }
        step(named: name) { core in
            for id in ids { core.remove(id) }
            for id in pins { core.removePin(id) }
        }
    }

    /// The open screenshot's file was renamed: the drawing is the same, under this key.
    mutating func rekey(to key: String) {
        if isOpen { drawing.key = key }
    }

    // MARK: Agents' marks

    /// Agents' marks join the open drawing as one undo step, and go to the host straight away. The
    /// selection stays as it was.
    private mutating func join(_ marks: [Mark]) {
        let placed = marks.compactMap { geometry.placed(Self.fresh($0)) }
        guard !placed.isEmpty else { return }
        step(named: .agentMarks) { core in
            for mark in placed { core.add(mark) }
        }
        handOver()
    }
}

private extension EditorCore.Input {
    /// The inputs after which a box or an arrow just drawn still takes a typed character as its note.
    /// A key decides for itself (`startsNote`).
    var keepsNoteMark: Bool {
        switch self {
        case .keyDown, .keyUp, .pointerMoved, .pointerExited, .modifiersChanged, .zoomChanged, .viewChanged, .tweaksChanged, .rescaled, .timerFired:
            return true
        default: return false
        }
    }

    /// The inputs that leave a hold of the arrow keys one undo step.
    var keepsNudge: Bool {
        switch self {
        case .keyDown(let key, _, _): return key.direction != nil
        case .keyUp, .pointerMoved, .pointerExited, .modifiersChanged, .zoomChanged, .viewChanged, .tweaksChanged, .rescaled, .timerFired: return true
        default: return false
        }
    }
}
