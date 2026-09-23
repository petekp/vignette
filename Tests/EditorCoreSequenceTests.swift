import XCTest

/// Random sequences of inputs against the editor's core, checked after every input: no mark lies
/// outside the image, one Cmd+Z undoes exactly one step and puts back its marks and selection, redo
/// brings both back, Esc during a gesture restores the drawing exactly, and a change that leaves the
/// marks as they were adds no undo step. A failure names its seed and the inputs that led to it, so
/// it can be replayed.
final class EditorCoreSequenceTests: XCTestCase {
    func testRandomSequencesKeepTheInvariants() {
        for seed in 0..<250 {
            var run = SequenceRun(seed: UInt64(seed))
            if let failure = run.play(steps: 150) {
                XCTFail("seed \(seed): \(failure)\n" + run.trace.suffix(60).joined(separator: "\n"))
            }
        }
    }
}

private struct SequenceRun {
    typealias Core = EditorCore

    var rng: SeededGenerator
    var core = Core()
    var trace: [String] = []
    var clock: TimeInterval = 0
    var buttonDown = false
    var copied: CopiedMarks?
    var queued: Core.Input?
    /// What each undo depth holds, as far as redo reaches.
    var states: [Depth] = []
    /// The drawing and the selection a gesture began from, which Esc must put back.
    var gestureStart: (drawing: Drawing, selection: Set<Mark.ID>)?
    /// The selection when the open gesture's changes or typing session began: what undoing its step puts back.
    var editSelection: Set<Mark.ID>?
    /// The text being typed as the session found it, nil for one the session made.
    var typingOrigin: (id: Mark.ID, mark: Mark?)?

    /// The marks at one undo depth, without their colours, and the selection undo and redo put back
    /// around the step that reached it, where the sequence can tell.
    struct Depth {
        var marks: [Mark]
        var selectionBefore: Set<Mark.ID>?
        var selectionAfter: Set<Mark.ID>?
    }

    init(seed: UInt64) {
        rng = SeededGenerator(seed: seed)
    }

    mutating func play(steps: Int) -> String? {
        reopen(randomDrawing())
        _ = core.reduce(.zoomChanged([0.25, 0.5, 1, 2, 4].randomElement(using: &rng)!))
        for _ in 0..<steps {
            let input = queued ?? nextInput()
            queued = nil
            if let failure = apply(input) { return failure }
        }
        return nil
    }

    // MARK: Driving

    mutating func randomDrawing() -> Drawing {
        var drawing = Drawing(key: "/tmp/sequence.png",
                              pixels: PixelSize(width: Int.random(in: 240...1800, using: &rng), height: Int.random(in: 160...1400, using: &rng)),
                              pointScale: [1, 1.5, 2, 3].randomElement(using: &rng)!, marks: [])
        let geometry = EditorGeometry(pixels: drawing.pixels, pointScale: drawing.pointScale, style: .standard, metrics: .standard, zoom: 1, layouts: TextLayoutCache(),
                                      arrowhead: .standard)
        drawing.marks = (0..<Int.random(in: 0...5, using: &rng)).compactMap { _ in geometry.placed(randomMark(in: drawing.pixels, agent: Bool.random(using: &rng))) }
        return drawing
    }

    static func open(_ drawing: Drawing) -> Core.Input {
        .open(drawing, style: .standard, metrics: .standard, arrowhead: .standard, pickColor: { mark in Self.pick(mark) })
    }

    /// Opens `drawing` outside the sequence, as the host does after a park.
    mutating func reopen(_ drawing: Drawing) {
        let effects = core.reduce(Self.open(drawing))
        trace.append("open \(drawing.pixels.width)x\(drawing.pixels.height)@\(drawing.pointScale) marks=\(drawing.marks.count) -> \(Self.describe(effects))")
        opened()
    }

    /// A drawing just opened: history starts again.
    mutating func opened() {
        states = [Depth(marks: Self.plain(core.drawing.marks))]
        gestureStart = nil
        editSelection = nil
        typingOrigin = nil
        buttonDown = false
    }

    /// A pick that depends only on where the mark is, and that sometimes cannot answer yet.
    static func pick(_ mark: Mark) -> MarkColor? {
        let seed: CGFloat
        switch mark.geometry {
        case .rectangle(let frame), .ellipse(let frame): seed = frame.minX + frame.minY
        case .arrow(let arrow): seed = arrow.start.x + arrow.end.y
        case .text(let text): seed = text.origin.x + text.origin.y
        }
        let index = Int(abs(seed.rounded())) % 7
        return index < 5 ? MarkColor.allCases[index] : nil
    }

    mutating func nextInput() -> Core.Input {
        clock += Double.random(in: 0.02...0.4, using: &rng)
        let modifiers = randomModifiers()
        // What can arrive at any time: the host's calls, agents' marks, a paste, and a pointer the
        // view reports out of order.
        if Int.random(in: 0..<(core.typing == nil ? 14 : 5), using: &rng) == 0 {
            switch Int.random(in: 0..<10, using: &rng) {
            case 0, 1: return .agentMarks((0..<Int.random(in: 1...3, using: &rng)).map { _ in randomMark(in: core.drawing.pixels, agent: true) })
            case 2, 3: return .paste(pasteContent())
            case 4: return [Core.Input.done, .send, .park].randomElement(using: &rng)!
            case 5: return Self.open(randomDrawing())
            case 6: return .pointerDragged(Core.Pointer(location: point(), modifiers: modifiers, time: clock))
            case 7: return .pointerReleased(Core.Pointer(location: point(), modifiers: modifiers, time: clock))
            case 8: return press(modifiers)
            default: return .typingChanged(words())
            }
        }
        if buttonDown {
            switch Int.random(in: 0..<20, using: &rng) {
            case 0..<12: return .pointerDragged(Core.Pointer(location: point(), modifiers: modifiers, time: clock))
            case 12..<15: return .pointerReleased(Core.Pointer(location: point(), modifiers: modifiers, time: clock))
            case 15, 16: return .modifiersChanged(modifiers)
            case 17: return .timerFired
            case 18: return .zoomChanged([0.5, 1, 2].randomElement(using: &rng)!)
            case 19: return .keyDown(.escape, [], isRepeat: false)
            default: return key()
            }
        }
        if core.typing != nil {
            switch Int.random(in: 0..<12, using: &rng) {
            case 0..<5: return .typingChanged(words())
            case 5: return .typingEnded
            case 6, 7: return press(modifiers)
            case 8: return .setTool(Core.Tool.allCases.randomElement(using: &rng)!)
            case 9: return .timerFired
            default:
                let key = key()
                if case .keyDown(let k, let m, _) = key, core.takesKey(k, m) { return key }
                return .typingChanged(words())
            }
        }
        // Right after an undo, often redo, so redo is checked as often as undo is.
        if core.canRedo, Int.random(in: 0..<4, using: &rng) == 0 { return .keyDown(.character("z"), [.command, .shift], isRepeat: false) }
        switch Int.random(in: 0..<40, using: &rng) {
        case 0..<10: return press(modifiers)
        case 10..<14: return .pointerMoved(Core.Pointer(location: point(), modifiers: modifiers, time: clock))
        case 14..<27: return key()
        case 27, 28: return .setTool(Core.Tool.allCases.randomElement(using: &rng)!)
        case 29: return .zoomChanged([0.25, 0.5, 1, 2, 4].randomElement(using: &rng)!)
        case 30, 31: return .timerFired
        case 32: return .agentMarks((0..<Int.random(in: 1...3, using: &rng)).map { _ in randomMark(in: core.drawing.pixels, agent: true) })
        case 33: return .paste([Core.PasteContent.image, .other].randomElement(using: &rng)!)
        case 34: return .pointerExited
        case 35: return .done
        case 36: return .send
        case 37: return .park
        default: return .modifiersChanged(modifiers)
        }
    }

    mutating func press(_ modifiers: Core.Modifiers) -> Core.Input {
        .pointerPressed(Core.Pointer(location: point(), modifiers: modifiers.subtracting(Bool.random(using: &rng) ? .control : []), time: clock),
                        clickCount: Int.random(in: 0..<6, using: &rng) == 0 ? 2 : 1)
    }

    mutating func key() -> Core.Input {
        let keys: [(Core.Key, Core.Modifiers)] = [
            (.escape, []), (.returnKey, []), (.returnKey, .shift), (.returnKey, .option), (.returnKey, .command),
            (.tab, []), (.tab, .shift), (.delete, []), (.forwardDelete, []),
            (.left, []), (.right, []), (.up, .shift), (.down, []), (.right, .shift),
            (.character("z"), .command), (.character("z"), [.command, .shift]), (.character("z"), .command),
            (.character("a"), .command), (.character("c"), .command), (.character("x"), .command),
            (.character("v"), .command), (.character("d"), .command), (.character("="), .command), (.character("0"), .command),
            (.character("v"), []), (.character("r"), []), (.character("a"), .shift), (.character("t"), []), (.character("q"), []),
        ]
        if !core.selection.isEmpty, Int.random(in: 0..<3, using: &rng) == 0 {
            let arrow = [Core.Key.left, .right, .up, .down].randomElement(using: &rng)!
            return Bool.random(using: &rng) ? .keyDown(arrow, [], isRepeat: true) : .keyUp(arrow)
        }
        let (key, modifiers) = keys.randomElement(using: &rng)!
        return .keyDown(key, modifiers, isRepeat: false)
    }

    mutating func randomModifiers() -> Core.Modifiers {
        var modifiers: Core.Modifiers = []
        if Int.random(in: 0..<4, using: &rng) == 0 { modifiers.insert(.shift) }
        if Int.random(in: 0..<5, using: &rng) == 0 { modifiers.insert(.option) }
        if Int.random(in: 0..<12, using: &rng) == 0 { modifiers.insert(.command) }
        if Int.random(in: 0..<30, using: &rng) == 0 { modifiers.insert(.control) }
        return modifiers
    }

    /// A point worth pressing: on or near a mark, a handle or a dot, or anywhere, a little past the image included.
    mutating func point() -> CGPoint {
        let geometry = core.geometry
        let jitter = CGFloat.random(in: -8...8, using: &rng) / core.zoom
        let overlay = core.overlay
        switch Int.random(in: 0..<10, using: &rng) {
        case 0..<4:
            if let mark = core.drawing.marks.randomElement(using: &rng) {
                let e = geometry.extent(of: mark)
                let xs = [e.minX, e.midX, e.maxX], ys = [e.minY, e.midY, e.maxY]
                return CGPoint(x: xs.randomElement(using: &rng)! + jitter, y: ys.randomElement(using: &rng)! + jitter)
            }
        case 4, 5:
            if let handle = overlay.handles.randomElement(using: &rng) {
                return CGPoint(x: handle.hitArea.midX + jitter / 2, y: handle.hitArea.midY + jitter / 2)
            }
            if let dot = overlay.dots.randomElement(using: &rng) { return CGPoint(x: dot.center.x + jitter, y: dot.center.y + jitter) }
        default:
            break
        }
        let image = geometry.image
        return CGPoint(x: CGFloat.random(in: -0.1...1.1, using: &rng) * image.width, y: CGFloat.random(in: -0.1...1.1, using: &rng) * image.height)
    }

    static let texts = [
        "", "  ", "\n", "note", "a longer sentence that should wrap somewhere near the edge of a narrow image",
        "two\nlines", "字🎉 mixed", "trailing\n", "unbreakable_identifier_longer_than_a_narrow_image_is_wide",
    ]
    /// Past what a drawing file may hold, in characters and in bytes. Laying these out is slow, so they are rare.
    static let oversized = [String(repeating: "overflow ", count: 300), "e" + String(repeating: "\u{301}", count: 70_000)]

    mutating func pasteContent() -> Core.PasteContent {
        switch Int.random(in: 0..<5, using: &rng) {
        case 0, 1: return copied.map { .marks($0) } ?? .text(words())
        case 2: return .text(words())
        case 3: return .image
        default: return .other
        }
    }

    mutating func words() -> String {
        Int.random(in: 0..<40, using: &rng) == 0 ? Self.oversized.randomElement(using: &rng)! : Self.texts.randomElement(using: &rng)!
    }

    mutating func randomMark(in pixels: PixelSize, agent: Bool) -> Mark {
        let w = CGFloat(pixels.width), h = CGFloat(pixels.height)
        func x() -> CGFloat { CGFloat.random(in: -0.1...1.0, using: &rng) * w }
        func y() -> CGFloat { CGFloat.random(in: -0.1...1.0, using: &rng) * h }
        let geometry: Mark.Geometry
        switch Int.random(in: 0..<4, using: &rng) {
        case 0: geometry = .rectangle(CGRect(x: x(), y: y(), width: CGFloat.random(in: 1...0.6 * w, using: &rng), height: CGFloat.random(in: 1...0.6 * h, using: &rng)))
        case 1: geometry = .ellipse(CGRect(x: x(), y: y(), width: CGFloat.random(in: 1...0.6 * w, using: &rng), height: CGFloat.random(in: 1...0.6 * h, using: &rng)))
        case 2: geometry = .arrow(Mark.Arrow(start: CGPoint(x: x(), y: y()), end: CGPoint(x: x() + 3, y: y()), bend: CGFloat.random(in: -200...200, using: &rng)))
        default:
            geometry = .text(Mark.Text(origin: CGPoint(x: x(), y: y()), text: ["agent note", "one\ntwo", "a sentence of several words"].randomElement(using: &rng)!,
                                       wrap: Bool.random(using: &rng) ? nil : CGFloat.random(in: 20...w, using: &rng), size: CGFloat.random(in: 8...60, using: &rng)))
        }
        return Mark(geometry: geometry, color: MarkColor.allCases.randomElement(using: &rng)!, agent: agent, colorChosen: agent && Bool.random(using: &rng))
    }

    // MARK: Checking

    mutating func apply(_ input: Core.Input) -> String? {
        let before = core
        let effects = core.reduce(input)
        trace.append("\(Self.describe(input)) -> \(Self.describe(effects))")
        if case .pointerPressed(let pointer, _) = input, !pointer.modifiers.contains(.control), core.gesture != nil { buttonDown = true }
        if case .pointerReleased = input { buttonDown = false }
        if core.gesture == nil { buttonDown = false }

        for effect in effects {
            switch effect {
            case .copyMarks(let marks, _):
                copied = marks
                if CopiedMarks(data: (try? marks.encoded()) ?? Data())?.marks.count != marks.marks.count { return "copied marks do not survive the clipboard" }
            case .readClipboard:
                switch Int.random(in: 0..<5, using: &rng) {
                case 0, 1: if let copied { queued = .paste(.marks(copied)) }
                case 2: if let copied { queued = .paste(.marks(CopiedMarks(pointScale: [1, 2, 3].randomElement(using: &rng)!, marks: copied.marks))) }
                case 3: queued = .paste(.text(words()))
                default: queued = .paste(.image)
                }
            case .handOver(let drawing), .done(let drawing), .send(let drawing), .copyDrawing(let drawing):
                if let problem = Self.invalid(drawing) { return "the host was handed a drawing it cannot read back: \(problem)" }
            default:
                break
            }
        }

        if case .park = input {
            guard !core.isOpen, let handed = effects.lazy.compactMap({ effect -> Drawing? in
                if case .handOver(let drawing) = effect { return drawing }
                return nil
            }).first else { return "park did not hand the drawing over and close" }
            reopen(handed)
            return nil
        }
        if case .open = input {
            opened()
            return checkShape()
        }

        if let problem = checkShape() { return problem }
        if let problem = checkUndo(input, before: before) { return problem }
        noteEdits(input, before: before)
        // Agents' marks that join mid-gesture stay when Esc puts the gesture back.
        if case .agentMarks = input, core.gesture != nil, gestureStart != nil { gestureStart?.drawing = core.drawingForHost }

        // Esc during a gesture restores the drawing exactly.
        if case .keyDown(.escape, _, _) = input, before.gesture != nil, before.typing == nil, let start = gestureStart {
            if core.drawing != start.drawing { return "Esc did not restore the drawing" }
            if core.selection != start.selection { return "Esc did not restore the selection" }
        }
        if case .pointerPressed = input, let gesture = core.gesture {
            gestureStart = (core.drawing, gesture.press.selectionBefore)
        }
        return nil
    }

    func checkShape() -> String? {
        let geometry = core.geometry
        let ids = core.drawing.marks.map(\.id)
        if Set(ids).count != ids.count { return "two marks share an id" }
        for (index, mark) in core.drawing.marks.enumerated() {
            guard let placed = geometry.placedKeepingLines(mark), Self.close(placed, mark) else { return "mark \(index + 1) (\(mark.kind)) lies outside the image: \(mark.geometry)" }
            if case .text(let text) = mark.geometry {
                if text.text.count > MarkFields.maxTextLength || text.text.utf8.count > MarkFields.maxTextBytes { return "mark \(index + 1) holds too much text" }
                if text.size > Mark.Text.maxSize { return "mark \(index + 1) is too large" }
                if EditorCore.isBlank(mark), core.typing?.id != mark.id { return "mark \(index + 1) is a text with no words" }
            }
        }
        if !core.selection.isSubset(of: Set(ids)) { return "the selection names a mark that is gone" }
        if let typing = core.typing, core.mark(typing.id)?.kind != .text { return "typing into a mark that is not a text" }
        if case .mark(let id)? = core.hover, core.mark(id) == nil { return "hovering a mark that is gone" }
        return nil
    }

    mutating func checkUndo(_ input: Core.Input, before: Core) -> String? {
        let d0 = before.undoSteps.count, d1 = core.undoSteps.count
        let settledBefore = before.gesture == nil && before.typing == nil
        let settled = core.gesture == nil && core.typing == nil
        let marks = Self.plain(core.drawing.marks)
        var undo = false, redo = false, nudge = false, paste = false
        if case .keyDown(let key, let modifiers, _) = input {
            undo = settledBefore && key == .character("z") && modifiers == .command
            redo = settledBefore && key == .character("z") && modifiers == [.command, .shift]
            nudge = key.direction != nil
        }
        if case .paste = input { paste = true }
        if undo || redo {
            let expected = undo ? max(d0 - 1, 0) : d0 + (before.redoSteps.isEmpty ? 0 : 1)
            if d1 != expected { return "\(undo ? "undo" : "redo") went from depth \(d0) to \(d1), expected \(expected)" }
            if marks != states[d1].marks { return "\(undo ? "undo" : "redo") to depth \(d1) did not bring back the marks as they were" }
            guard d1 != d0 else { return nil }
            let ids = Set(core.drawing.marks.map(\.id))
            if let selection = undo ? states[d0].selectionBefore : states[d1].selectionAfter, core.selection != selection.intersection(ids) {
                return "\(undo ? "undo" : "redo") to depth \(d1) did not bring back the selection"
            }
            return nil
        }
        if case .agentMarks = input, core.drawing.marks.count > before.drawing.marks.count, d1 != d0 + 1 {
            return "agents' marks did not join as one undo step of their own"
        }
        if d1 == d0 {
            guard settled, marks != states[d1].marks else { return nil }
            guard nudge else { return "the marks changed without an undo step" }
            // The nudges of one held arrow key are one step.
            states[d1].marks = marks
            states[d1].selectionAfter = core.selection
            return nil
        }
        if nudge, settled, d1 == d0 - 1 {
            // A hold that nudged the marks back to where it began leaves no step.
            return marks == states[d1].marks ? nil : "a nudge that cancelled out did not put the marks back"
        }
        if d1 == d0 + 2, paste, before.typing != nil, settled {
            // The paste ended the typing, its own step, then added its marks as another.
            let typed = Self.plain(core.drawing.marks.filter { mark in before.drawing.marks.contains { $0.id == mark.id } })
            if typed == states[d0].marks { return "a typing session that changed nothing added a step" }
            states = Array(states.prefix(d0 + 1)) + [Depth(marks: typed, selectionBefore: editSelection), Depth(marks: marks, selectionAfter: core.selection)]
            return nil
        }
        guard d1 == d0 + 1 else { return "the undo depth went from \(d0) to \(d1)" }
        let step: Depth
        if case .agentMarks = input {
            // Agents' marks join as a step of their own while a gesture or a typing session goes on,
            // so the step holds the marks with what those have changed so far put back.
            step = Depth(marks: Self.plain(joined()), selectionBefore: before.selection, selectionAfter: core.selection)
        } else if settled {
            let selectionBefore: Set<Mark.ID>?
            if settledBefore {
                selectionBefore = before.selection
            } else if paste {
                // The paste put a gesture back before adding its marks. Mid-typing the one step may be
                // the typing's or the paste's, so the selection goes unchecked.
                selectionBefore = before.gesture?.press.selectionBefore
            } else {
                selectionBefore = editSelection
            }
            step = Depth(marks: marks, selectionBefore: selectionBefore, selectionAfter: core.selection)
        } else if before.typing != nil {
            // A press that ends typing commits it and starts something new in the same input.
            step = Depth(marks: Self.plain(core.drawing.marks), selectionBefore: editSelection)
        } else {
            return "the undo depth went from \(d0) to \(d1) with a gesture or typing still open"
        }
        if step.marks == states[d0].marks { return "a step was added that changed no mark" }
        states = Array(states.prefix(d0 + 1)) + [step]
        return nil
    }

    /// The marks with the open gesture's or typing session's changes put back.
    func joined() -> [Mark] {
        guard let typing = core.typing, let origin = typingOrigin, origin.id == typing.id else { return core.drawingForHost.marks }
        return core.drawing.marks.compactMap { $0.id == origin.id ? origin.mark : $0 }
    }

    /// Notes when a gesture starts changing marks or a typing session starts, and the selection then.
    mutating func noteEdits(_ input: Core.Input, before: Core) {
        if before.gesture?.phase == .pressed, let phase = core.gesture?.phase {
            switch phase {
            case .drawing, .moving, .resizing, .draggingEnd, .bending: editSelection = before.selection
            case .pressed, .wrapping, .brushing: break
            }
        }
        if let typing = core.typing, typing.id != before.typing?.id {
            var base = before.selection
            // A press puts back a gesture it cuts short, selection and all, before it starts typing.
            if case .pointerPressed = input, let gesture = before.gesture { base = gesture.press.selectionBefore }
            editSelection = base.intersection(core.drawing.marks.map(\.id))
            typingOrigin = (typing.id, before.mark(typing.id) == nil ? nil : core.mark(typing.id))
        }
    }

    /// What reading `drawing` back from its file would refuse, or nil.
    static func invalid(_ drawing: Drawing) -> String? {
        guard let data = try? drawing.encoded(),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["marks"] as? [Any] else { return "it does not encode" }
        for (index, item) in items.enumerated() {
            do { _ = try Mark(validating: item) } catch { return "mark \(index + 1): \(error)" }
        }
        return nil
    }

    static func plain(_ marks: [Mark]) -> [Mark] {
        marks.map { mark in
            var mark = mark
            mark.color = .red
            return mark
        }
    }

    static func close(_ a: Mark, _ b: Mark) -> Bool {
        func near(_ x: CGFloat, _ y: CGFloat) -> Bool { abs(x - y) <= 1e-6 * max(1, abs(x)) }
        switch (a.geometry, b.geometry) {
        case (.rectangle(let f), .rectangle(let g)), (.ellipse(let f), .ellipse(let g)):
            return near(f.minX, g.minX) && near(f.minY, g.minY) && near(f.width, g.width) && near(f.height, g.height)
        case (.arrow(let p), .arrow(let q)):
            return near(p.start.x, q.start.x) && near(p.start.y, q.start.y) && near(p.end.x, q.end.x) && near(p.end.y, q.end.y) && near(p.bend, q.bend)
        case (.text(let s), .text(let t)):
            return s.text == t.text && near(s.origin.x, t.origin.x) && near(s.origin.y, t.origin.y) && near(s.size, t.size) && near(s.wrap ?? 0, t.wrap ?? 0)
        default:
            return false
        }
    }

    static func describe(_ input: Core.Input) -> String {
        func at(_ p: Core.Pointer) -> String { String(format: "(%.1f, %.1f)%@", p.location.x, p.location.y, p.modifiers.isEmpty ? "" : " \(p.modifiers.rawValue)") }
        switch input {
        case .open: return "open"
        case .pointerMoved(let p): return "move \(at(p))"
        case .pointerExited: return "exit"
        case .pointerPressed(let p, let count): return "press \(at(p)) count=\(count)"
        case .pointerDragged(let p): return "drag \(at(p))"
        case .pointerReleased(let p): return "release \(at(p))"
        case .modifiersChanged(let m): return "modifiers \(m.rawValue)"
        case .keyDown(let key, let m, let isRepeat): return "key \(key) \(m.rawValue)\(isRepeat ? " repeat" : "")"
        case .keyUp(let key): return "keyUp \(key)"
        case .setTool(let tool): return "tool \(tool)"
        case .zoomChanged(let zoom): return "zoom \(zoom)"
        case .typingChanged(let text): return "type \(text.count) characters"
        case .typingEnded: return "typingEnded"
        case .timerFired: return "timer"
        case .paste(let content):
            switch content {
            case .marks(let copied): return "paste \(copied.marks.count) marks @\(copied.pointScale)"
            case .text(let text): return "paste text of \(text.count)"
            case .image: return "paste image"
            case .other: return "paste other"
            }
        case .agentMarks(let marks): return "agent marks \(marks.count)"
        case .done: return "done"
        case .send: return "send"
        case .park: return "park"
        }
    }

    static func describe(_ effects: [Core.Effect]) -> String {
        effects.map { effect -> String in
            switch effect {
            case .handOver(let drawing): return "handOver(\(drawing.marks.count))"
            case .done(let drawing): return "done(\(drawing.marks.count))"
            case .send(let drawing): return "send(\(drawing.marks.count))"
            case .copyDrawing(let drawing): return "copyDrawing(\(drawing.marks.count))"
            case .copyMarks(let marks, _): return "copyMarks(\(marks.marks.count))"
            case .announce: return "announce"
            default: return "\(effect)"
            }
        }.joined(separator: ", ")
    }
}
