import AppKit

extension Drawings {
    /// Why agents' marks did not become part of a drawing, with the code the command answers.
    struct Failure: Error, CustomStringConvertible {
        let code: CommandError
        let description: String
    }

    /// How many of an agent's marks, and of its pins' comments, joined a drawing.
    struct Joined: Equatable {
        var marks = 0
        var pins = 0

        var isEmpty: Bool { marks == 0 && pins == 0 }
    }

    /// Adds an agent's marks and pins to the drawing of the screenshot `key`, and answers how many
    /// joined. When the editor has that screenshot open, they join its drawing as one undo step.
    /// Otherwise they are added to the stored drawing, or a new one sized for `newScreen`, as one step of
    /// its stored history. Either way the file is written before this returns, or it throws. An answer
    /// whose pin is gone by now, or a pin past `Pin.maxCount`, is left out with a log line.
    func add(_ additions: AgentAdditions, to key: ScreenshotKey, style: TextStyle, newScreen: DrawingScreen,
             rule: MarkScaleRule) throws -> Joined {
        let url = key.url, name = key.name, agent = additions.agent
        if let open, let before = open.drawing(of: key) {
            let made = marks(additions.marks, from: agent, in: before.pixels, pointScale: before.pointScale, style: style, rule: rule, name: name)
            pins(additions, onto: before, name: name)
            guard let joined = open.join(made, pins: additions.pins, by: additions.author) else { return Joined() }
            guard write(joined, history: open.history(of: key) ?? EditorHistory(), reason: "saved") else {
                throw Failure(code: .writeFailed, description: "the drawing for \(name) could not be written")
            }
            func comments(_ drawing: Drawing) -> Int { drawing.pins.reduce(0) { $0 + $1.comments.count } }
            return Joined(marks: joined.marks.count - before.marks.count, pins: comments(joined) - comments(before))
        }
        guard let pixels = PixelSize(imageAt: url) else {
            throw Failure(code: .unreadableImage, description: "\(name) is not an image this Mac can read")
        }
        var drawing = read(key, pixels: pixels, style: style)
            ?? Drawing(key: key.path, pixels: pixels, sizedFor: newScreen, rule: rule).numbered(numbering(of: key, pixels: pixels))
        let made = marks(additions.marks, from: agent, in: pixels, pointScale: drawing.pointScale, style: style, rule: rule, name: name)
        let pins = pins(additions, onto: drawing, name: name)
        guard !made.isEmpty || !pins.isEmpty else { return Joined() }
        var history = history(of: key, pixels: pixels, drawing: drawing)
        let added = made.enumerated().map { offset, mark in
            EditStep.Change(id: mark.id, before: nil, after: PlacedMark(mark: mark, index: drawing.marks.count + offset))
        }
        let pinChanges = pins.map { pin in EditStep.PinChange(id: pin.id, before: drawing.pins.first { $0.id == pin.id }, after: pin) }
        history.record(.drawing(EditStep(name: .agentMarks, changes: added, selectionBefore: [], selectionAfter: [], pins: pinChanges)))
        let joined = Joined(marks: made.count, pins: pinChanges.reduce(0) { $0 + ($1.after?.comments.count ?? 0) - ($1.before?.comments.count ?? 0) })
        drawing.marks += made
        drawing = drawing.taking(pins)
        guard write(drawing, history: history, reason: "built") else {
            throw Failure(code: .writeFailed, description: "the drawing for \(name) could not be written")
        }
        return joined
    }

    /// The session list named `session` after its comments joined the drawing of the screenshot `key`:
    /// each comment `session` wrote that has no session name takes `sender`, in the drawing and in its
    /// history, the editor's when it is open there. Writes nothing when no comment changed.
    func name(_ sender: String, of session: AgentAddress, on key: ScreenshotKey, style: TextStyle) {
        if let open, open.drawing(of: key) != nil {
            guard let named = open.name(sender, of: session) else { return }
            write(named, history: open.history(of: key) ?? EditorHistory(), reason: "named")
            return
        }
        guard keys.contains(key), let pixels = PixelSize(imageAt: key.url), let drawing = read(key, pixels: pixels, style: style) else { return }
        let named = drawing.naming(session, sender)
        guard named != drawing else { return }
        write(named, history: history(of: key, pixels: pixels, drawing: drawing).naming(session, sender), reason: "named")
    }

    /// `AgentPin.join` of `additions`' pins onto `drawing`, with one line for those left out.
    @discardableResult
    private func pins(_ additions: AgentAdditions, onto drawing: Drawing, name: String) -> [Pin] {
        guard !additions.pins.isEmpty else { return [] }
        let joined = AgentPin.join(additions.pins, by: additions.author, onto: drawing)
        if !joined.dropped.isEmpty {
            Log.write("[pins] dropped pin=\(joined.dropped.map(String.init).joined(separator: ",")) for \(name): its pin is gone, or the screenshot holds \(Pin.maxCount) pins")
        }
        return joined.pins
    }

    /// The drawing `add`'s marks and pins would join on the screenshot `key` now, the editor's when it is
    /// open there, and how many of the marks can be drawn on it, writing nothing. Nil when the image
    /// does not read.
    func joining(_ additions: AgentAdditions, to key: ScreenshotKey, style: TextStyle, newScreen: DrawingScreen,
                 rule: MarkScaleRule) -> (onto: Drawing, drawable: Int)? {
        let px = PixelSize(imageAt: key.url)
        guard let onto = open?.drawing(of: key) ?? px.map({ read(key, pixels: $0, style: style)
            ?? Drawing(key: key.path, pixels: $0, sizedFor: newScreen, rule: rule).numbered(numbering(of: key, pixels: $0)) }) else { return nil }
        let drawable = AgentMark.marks(additions.marks, from: additions.agent, in: onto.pixels, pointScale: onto.pointScale, style: style,
                                       smallestText: rule.smallestNoteText).marks.count
        return (onto, drawable)
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
