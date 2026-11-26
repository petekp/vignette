import Foundation

extension EditorCore {
    /// Agents' marks and pins join the open drawing as one undo step, and go to the host straight
    /// away. The selection stays as it was. The pins join the drawing as it was before a gesture or
    /// the composer under way, which takes them in, so putting that edit back or making its step
    /// leaves them. An answer adds its comment to a pin the person is moving where it is now.
    mutating func join(_ marks: [Mark], pins: [AgentPin], from agent: String?, at: Date) {
        let placed = marks.compactMap { geometry.placed(Self.fresh($0)) }
        guard !placed.isEmpty || !pins.isEmpty else { return }
        var base = drawing
        if let edit { base.pins = edit.startPins }
        let joined = AgentPin.join(pins, from: agent, at: at, onto: base).pins
        let changes = joined.map { pin in EditStep.PinChange(id: pin.id, before: base.pins.first { $0.id == pin.id }, after: pin) }
        step(named: .agentMarks, pins: changes) { core in
            for mark in placed { core.add(mark) }
            for pin in joined {
                if let index = core.drawing.pins.firstIndex(where: { $0.id == pin.id }) {
                    core.drawing.pins[index].comments = pin.comments
                } else {
                    core.drawing = core.drawing.taking([pin])
                }
            }
        }
        edit?.take(joined)
        handOver()
    }

    /// The newest undo step when it is agents' marks and pins joining the drawing and nothing else, as
    /// a Keep or an `add` leaves it. Nil while a gesture, a typing session or the composer is under way.
    var newestAgentMarks: EditStep? {
        guard gesture == nil, typing == nil, composer == nil, case .drawing(let step)? = undoSteps.last, step.joinsAgentMarks else { return nil }
        return step
    }
}
