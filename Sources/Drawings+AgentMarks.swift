import AppKit

extension Drawings {
    /// Why agents' marks did not become part of a drawing, with the code the command answers.
    struct Failure: Error, CustomStringConvertible {
        let code: CommandError
        let description: String
    }

    /// Adds an agent's marks to the drawing of the screenshot `key`, and answers how many joined.
    /// When the editor has that screenshot open, the marks join its drawing as one undo step.
    /// Otherwise they are added to the stored drawing, or a new one sized for `newScreen`, as one step of
    /// its stored history. Either way the
    /// file is written before this returns, or it throws. `agent` names the agent they are from.
    func add(_ agentMarks: [AgentMark], from agent: String?, to key: ScreenshotKey, style: TextStyle, newScreen: DrawingScreen,
             rule: MarkScaleRule) throws -> Int {
        let url = key.url, name = key.name
        if let open, let before = open.drawing(of: key) {
            let made = marks(agentMarks, from: agent, in: before.pixels, pointScale: before.pointScale, style: style, rule: rule, name: name)
            guard let joined = open.join(made) else { return 0 }
            guard write(joined, history: open.history(of: key) ?? EditorHistory(), reason: "saved") else {
                throw Failure(code: .writeFailed, description: "the drawing for \(name) could not be written")
            }
            return joined.marks.count - before.marks.count
        }
        guard let pixels = PixelSize(imageAt: url) else {
            throw Failure(code: .unreadableImage, description: "\(name) is not an image this Mac can read")
        }
        var drawing = read(key, pixels: pixels, style: style)
            ?? Drawing(key: key.path, pixels: pixels, sizedFor: newScreen, rule: rule).numbered(numbering(of: key, pixels: pixels))
        let made = marks(agentMarks, from: agent, in: pixels, pointScale: drawing.pointScale, style: style, rule: rule, name: name)
        guard !made.isEmpty else { return 0 }
        var history = history(of: key, pixels: pixels, drawing: drawing)
        let added = made.enumerated().map { offset, mark in
            EditStep.Change(id: mark.id, before: nil, after: PlacedMark(mark: mark, index: drawing.marks.count + offset))
        }
        history.record(.drawing(EditStep(name: .agentMarks, changes: added, selectionBefore: [], selectionAfter: [])))
        drawing.marks += made
        guard write(drawing, history: history, reason: "built") else {
            throw Failure(code: .writeFailed, description: "the drawing for \(name) could not be written")
        }
        return made.count
    }

    /// The marks and pins of the screenshot `key`'s drawing as they are now, the editor's when it is
    /// open there, as a hash: two that match hold the same marks and pins. Nil with no drawing.
    func drawn(of key: ScreenshotKey, style: TextStyle) -> String? {
        guard let drawing = current(of: key, style: style) else { return nil }
        return try? EditorHistory.basis(marks: drawing.marks, pins: drawing.pins, nextPin: drawing.nextPin, message: "")
    }

    /// Takes the agents' marks that a Keep or an `add` joined to the screenshot `key` back out of its
    /// drawing, when their step is still its newest undo step: in the editor when it is open there,
    /// else in the stored drawing and its history. The redo steps leave with it, so nothing but the
    /// caller can put the marks back. Answers what it took once the editor or the file holds the
    /// drawing without them, or nil.
    func takeBackAgentMarks(of key: ScreenshotKey, style: TextStyle) -> TakenBackMarks? {
        if let open, open.drawing(of: key) != nil {
            guard let (taken, drawing) = open.takeBackAgentMarks() else { return nil }
            // While the editor holds the drawing, its next hand-over writes it again.
            write(drawing, history: open.history(of: key) ?? EditorHistory(), reason: "saved")
            return taken
        }
        guard let pixels = PixelSize(imageAt: key.url), var drawing = read(key, pixels: pixels, style: style) else { return nil }
        var history = history(of: key, pixels: pixels, drawing: drawing)
        guard case .drawing(let step)? = history.undo.last, step.joinsAgentMarks else { return nil }
        let taken = TakenBackMarks(step: step, redo: history.redo)
        history.undo.removeLast()
        history.redo = []
        drawing = step.applied(to: drawing, forward: false)
        return write(drawing, history: history, reason: "saved") ? taken : nil
    }

    /// Puts back on the screenshot `key`'s drawing what `takeBackAgentMarks` took: the step as its
    /// newest undo step, and its redo steps under any the history holds now. In the editor when it is
    /// open there, else in the stored drawing, or a new one sized for `newScreen`. False when neither
    /// the editor nor the file holds them.
    func putBackAgentMarks(_ taken: TakenBackMarks, on key: ScreenshotKey, style: TextStyle, newScreen: DrawingScreen, rule: MarkScaleRule) -> Bool {
        if let open, open.drawing(of: key) != nil {
            guard let drawing = open.putBackAgentMarks(taken) else { return false }
            write(drawing, history: open.history(of: key) ?? EditorHistory(), reason: "saved")
            return true
        }
        guard let pixels = PixelSize(imageAt: key.url) else { return false }
        var drawing = read(key, pixels: pixels, style: style)
            ?? Drawing(key: key.path, pixels: pixels, sizedFor: newScreen, rule: rule).numbered(numbering(of: key, pixels: pixels))
        var history = history(of: key, pixels: pixels, drawing: drawing)
        history.undo.append(.drawing(taken.step))
        history.redo = taken.redo + history.redo
        drawing = taken.step.applied(to: drawing, forward: true)
        return write(drawing, history: history, reason: "built")
    }

    /// `add`'s marks alone, in a drawing of their own, writing nothing. Nil when none makes a mark.
    func preview(_ agentMarks: [AgentMark], from agent: String?, to key: ScreenshotKey, style: TextStyle,
                 newScreen: DrawingScreen, rule: MarkScaleRule) -> Drawing? {
        let px = PixelSize(imageAt: key.url)
        guard var d = open?.drawing(of: key) ?? px.map({ read(key, pixels: $0, style: style) ?? Drawing(key: key.path, pixels: $0, sizedFor: newScreen, rule: rule) }) else { return nil }
        d.marks = marks(agentMarks, from: agent, in: d.pixels, pointScale: d.pointScale, style: style, rule: rule, name: key.name)
        d.pins = []
        return d.marks.isEmpty ? nil : d
    }

    /// `AgentMark.marks`, with its one line for texts that do not fit, and one for colours named.
    func marks(_ agentMarks: [AgentMark], from agent: String?, in pixels: PixelSize, pointScale: CGFloat, style: TextStyle,
                       rule: MarkScaleRule, name: String) -> [Mark] {
        if agentMarks.contains(where: { $0.color != nil }) {
            Log.write("[marks] color ignored for \(name): an agent's marks are drawn in the agent's colour")
        }
        let made = AgentMark.marks(agentMarks, from: agent, in: pixels, pointScale: pointScale, style: style,
                                   smallestText: rule.smallestNoteText)
        if !made.tooLong.isEmpty {
            Log.write("[marks] text too long for \(name): mark \(made.tooLong.map(String.init).joined(separator: ", ")) is cut off at its edge")
        }
        return made.marks
    }
}
