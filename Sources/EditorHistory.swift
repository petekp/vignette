import Foundation

/// A mark and its place in the drawing's order.
struct PlacedMark {
    var mark: Mark
    var index: Int
}

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

    init(marks: [Mark], selectionBefore: Set<Mark.ID>) {
        start = marks
        self.selectionBefore = selectionBefore
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
        EditStep.placing(touched.map { ($0, before($0)) }, in: marks, keepingColors: false)
    }

    /// The undo step from where this edit began to `marks` and `selection`, or nil when the marks
    /// ended as they started.
    func step(ending marks: [Mark], selection: Set<Mark.ID>) -> EditStep? {
        let changes = touched.compactMap { id -> EditStep.Change? in
            let before = before(id)
            let after = marks.firstIndex { $0.id == id }.map { PlacedMark(mark: marks[$0], index: $0) }
            return before?.mark == after?.mark ? nil : EditStep.Change(id: id, before: before, after: after)
        }
        return changes.isEmpty ? nil : EditStep(changes: changes, selectionBefore: selectionBefore, selectionAfter: selection)
    }
}

/// One undo step: each mark it touched before and after, and the selection that goes with each side.
struct EditStep {
    struct Change {
        let id: Mark.ID
        /// Nil when the mark did not exist on that side.
        var before: PlacedMark?
        var after: PlacedMark?
    }

    var changes: [Change]
    let selectionBefore: Set<Mark.ID>
    var selectionAfter: Set<Mark.ID>

    /// This step and `later` as one, from this one's start to `later`'s end; nil when they cancel out.
    func merged(with later: EditStep) -> EditStep? {
        var changes = self.changes
        for change in later.changes {
            if let index = changes.firstIndex(where: { $0.id == change.id }) {
                changes[index].after = change.after
            } else {
                changes.append(change)
            }
        }
        changes.removeAll { $0.before?.mark == $0.after?.mark }
        return changes.isEmpty ? nil : EditStep(changes: changes, selectionBefore: selectionBefore, selectionAfter: later.selectionAfter)
    }

    /// `marks` as they were before this step (`forward` false) or after it (true), for the marks it
    /// touched; every other mark is left alone. A mark that exists now keeps its colour, because the
    /// colour pass is not part of history.
    func applied(to marks: [Mark], forward: Bool) -> [Mark] {
        Self.placing(changes.map { ($0.id, forward ? $0.after : $0.before) }, in: marks, keepingColors: true)
    }

    /// `marks` with every listed mark taken out and put back as `placed` says, at its index, lowest
    /// index first so each lands where it was; a nil `placed` leaves the mark out.
    static func placing(_ targets: [(id: Mark.ID, placed: PlacedMark?)], in marks: [Mark], keepingColors: Bool) -> [Mark] {
        let ids = Set(targets.map(\.id))
        let current = Dictionary(marks.filter { ids.contains($0.id) }.map { ($0.id, $0.color) }, uniquingKeysWith: { first, _ in first })
        var result = marks.filter { !ids.contains($0.id) }
        for placed in targets.compactMap(\.placed).sorted(by: { $0.index < $1.index }) {
            var mark = placed.mark
            if keepingColors, let color = current[mark.id] { mark.color = color }
            result.insert(mark, at: min(max(placed.index, 0), result.count))
        }
        return result
    }
}
