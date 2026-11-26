import Foundation

/// The changes one edit makes to a drawing's marks while it is open: a gesture, a typing session,
/// or a single command. It keeps each mark it touched as it was before, so the edit can be put back
/// exactly or become one undo step. Undo keeps only the marks a step touched, so two edits that
/// overlap in time, such as an agent's marks joining while a text is typed, stay two steps.
struct MarkEdit {
    /// The marks when the edit began, so each touched mark goes back to its place in this order
    /// however many the edit removed before it.
    private let start: [Mark]
    /// The marks the edit touched, in the order it first touched them.
    private(set) var touched: [Mark.ID] = []
    /// The selection when the edit began, which undoing its step puts back.
    let selectionBefore: Set<Mark.ID>
    /// The pins when the edit began, with those that joined beside it since (`take`). Putting the edit
    /// back puts every pin back as it was.
    private(set) var startPins: [Pin]

    init(marks: [Mark], pins: [Pin], selectionBefore: Set<Mark.ID>) {
        start = marks
        startPins = pins
        self.selectionBefore = selectionBefore
    }

    /// Pins that joined the drawing beside this edit, as they are now: the edit began with them.
    mutating func take(_ pins: [Pin]) {
        for pin in pins {
            if let index = startPins.firstIndex(where: { $0.id == pin.id }) { startPins[index] = pin } else { startPins.append(pin) }
        }
    }

    /// Notes that the edit is about to change, add or remove the mark `id` names.
    mutating func note(_ id: Mark.ID) {
        if !touched.contains(id) { touched.append(id) }
    }

    /// The mark as the edit found it: nil for one it made.
    func original(_ id: Mark.ID) -> Mark? {
        before(id)?.mark
    }

    private func before(_ id: Mark.ID) -> PlacedMark? {
        start.firstIndex { $0.id == id }.map { PlacedMark(mark: start[$0], index: $0) }
    }

    /// `marks` with every mark this edit touched put back as it was, in its place.
    func reverted(_ marks: [Mark]) -> [Mark] {
        EditStep.placing(touched.map { ($0, before($0)) }, in: marks)
    }

    /// The undo step named `name` from where this edit began to `marks` and `selection`, or nil when
    /// the marks ended as they started.
    func step(named name: StepName, ending marks: [Mark], selection: Set<Mark.ID>) -> EditStep? {
        let changes = touched.compactMap { id -> EditStep.Change? in
            let before = before(id)
            let after = marks.firstIndex { $0.id == id }.map { PlacedMark(mark: marks[$0], index: $0) }
            return before?.mark == after?.mark ? nil : EditStep.Change(id: id, before: before, after: after)
        }
        return changes.isEmpty ? nil : EditStep(name: name, changes: changes, selectionBefore: selectionBefore, selectionAfter: selection)
    }
}
