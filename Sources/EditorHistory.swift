import CryptoKit
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

/// One undo step of the drawing: each mark and each pin it touched before and after, and the selection
/// that goes with each side.
struct EditStep {
    struct Change {
        let id: Mark.ID
        /// Nil when the mark did not exist on that side.
        var before: PlacedMark?
        var after: PlacedMark?
    }

    /// A pin is named by its `id`, which it keeps in the file, and has no place in an order: pins are
    /// kept in the order of their numbers.
    struct PinChange {
        let id: Pin.ID
        /// Nil when the pin did not exist on that side.
        var before: Pin?
        var after: Pin?
    }

    let name: StepName
    var changes: [Change]
    let selectionBefore: Set<Mark.ID>
    var selectionAfter: Set<Mark.ID>
    var pins: [PinChange] = []

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
        var pins = self.pins
        for change in later.pins {
            if let index = pins.firstIndex(where: { $0.id == change.id }) { pins[index].after = change.after } else { pins.append(change) }
        }
        pins.removeAll { $0.before == $0.after }
        guard !changes.isEmpty || !pins.isEmpty else { return nil }
        return EditStep(name: name, changes: changes, selectionBefore: selectionBefore, selectionAfter: later.selectionAfter, pins: pins)
    }

    /// `drawing` as it was before this step (`forward` false) or after it (true), for the marks and the
    /// pins it touched; everything else is left alone.
    func applied(to drawing: Drawing, forward: Bool) -> Drawing {
        var drawing = drawing
        drawing.marks = applied(to: drawing.marks, forward: forward)
        let ids = Set(pins.map(\.id))
        drawing.pins = (drawing.pins.filter { !ids.contains($0.id) } + pins.compactMap { forward ? $0.after : $0.before })
            .sorted { $0.number < $1.number }
        return drawing
    }

    /// `marks` as they were before this step (`forward` false) or after it (true), for the marks it
    /// touched; every other mark is left alone.
    func applied(to marks: [Mark], forward: Bool) -> [Mark] {
        Self.placing(changes.map { ($0.id, forward ? $0.after : $0.before) }, in: marks)
    }

    /// `marks` with every listed mark taken out and put back as `placed` says, at its index, lowest
    /// index first so each lands where it was; a nil `placed` leaves the mark out.
    static func placing(_ targets: [(id: Mark.ID, placed: PlacedMark?)], in marks: [Mark]) -> [Mark] {
        let ids = Set(targets.map(\.id))
        var result = marks.filter { !ids.contains($0.id) }
        for placed in targets.compactMap(\.placed).sorted(by: { $0.index < $1.index }) {
            result.insert(placed.mark, at: min(max(placed.index, 0), result.count))
        }
        return result
    }
}

/// What one undo step did, in the words Undo and Redo give it: "Undo Arrow", "Redo Typing". The raw
/// value is the step's name in a drawing file's history.
enum StepName: String, CaseIterable {
    case rectangle, ellipse, arrow, typing, move, resize, bend, arrowEnd, duplicate, delete, paste, cut, agentMarks

    /// The words after Undo or Redo.
    var title: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .arrow: return "Arrow"
        case .typing: return "Typing"
        case .move: return "Move"
        case .resize: return "Resize"
        case .bend: return "Bend Arrow"
        case .arrowEnd: return "Move Arrow End"
        case .duplicate: return "Duplicate"
        case .delete: return "Delete"
        case .paste: return "Paste"
        case .cut: return "Cut"
        case .agentMarks: return "Agent's Marks"
        }
    }
}

/// A change to the message field's words: a run of typing, a paste or a cut.
struct MessageStep: Equatable {
    let name: StepName
    let before: String
    var after: String
}

/// One step of the editor's history: a change to the drawing, its marks and its pins, or to the message
/// field's words.
enum HistoryStep {
    case drawing(EditStep)
    case message(MessageStep)

    var name: StepName {
        switch self {
        case .drawing(let step): return step.name
        case .message(let step): return step.name
        }
    }

    /// The words after Undo or Redo. Marks from one named agent say whose they are: "Claude's Marks".
    var title: String {
        guard case .drawing(let step) = self, step.name == .agentMarks else { return name.title }
        let agents = Set(step.changes.map { $0.after?.mark.agentName })
        guard agents.count == 1, let agent = agents.first ?? nil else { return name.title }
        return "\(agent)'s Marks"
    }

    /// The Edit menu's item for `step`, the one Undo (or with `redo`, Redo) would take: "Undo Arrow", or
    /// "Undo" with nothing to undo.
    static func menuTitle(_ step: HistoryStep?, redo: Bool) -> String {
        let verb = redo ? "Redo" : "Undo"
        return step.map { "\(verb) \($0.title)" } ?? verb
    }
}

/// The editor's undo and redo steps: what a drawing's file keeps, so a screenshot opens again with
/// its history.
struct EditorHistory {
    /// Oldest first: Cmd+Z undoes the last.
    var undo: [HistoryStep] = []
    /// Oldest first: Shift+Cmd+Z redoes the last.
    var redo: [HistoryStep] = []

    var isEmpty: Bool { undo.isEmpty && redo.isEmpty }

    /// Adds `step` as the newest undo step, which ends what could be redone, as in the editor.
    mutating func record(_ step: HistoryStep) {
        undo.append(step)
        redo = []
    }
}

// MARK: - In a drawing's file

/// A history as a drawing's file keeps it, under `history` (`docs/drawing-file.md`). A step names
/// each mark it touched by a number: the mark's index in the file's `marks`, or from `marks.count` on
/// for a mark the drawing no longer holds. It names each pin it touched by its `id`.
extension EditorHistory {
    /// The most steps a file keeps, undo and redo together.
    static let maxSteps = 100
    /// The most bytes a file's history takes. A card reads the whole file to draw its marks.
    static let maxBytes = 256 * 1024

    /// The marks, the pins, `nextPin` and the message a history ends at, as a hash: a file whose drawing
    /// or message no longer hash to its `basis` was written by something other than the editor, and its
    /// history is dropped. With no pins and `nextPin` 1 it is the hash of a file from before pins.
    static func basis(marks: [Mark], pins: [Pin] = [], nextPin: Int = 1, message: String) throws -> String {
        var hasher = SHA256()
        hasher.update(data: try DrawingJSON.encode(marks.map(MarkRecord.init)))
        hasher.update(data: Data(message.utf8))
        if !pins.isEmpty || nextPin > 1 {
            hasher.update(data: try DrawingJSON.encode(pins.map(PinRecord.init)))
            hasher.update(data: Data("\(nextPin)".utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Whether a file's `history` object holds a step about pins, which makes the file version 2.
    static func mentionsPins(_ object: Any?) -> Bool {
        guard let object = object as? [String: Any] else { return false }
        return ["undo", "redo"].contains { ((object[$0] as? [[String: Any]]) ?? []).contains { $0["pins"] != nil } }
    }

    /// The `history` object for a file holding `drawing` and `message`, or nil for an empty history. The
    /// oldest undo steps go first, then the farthest redo steps, until it fits `maxSteps` and `maxBytes`.
    func fileObject(endingAt drawing: Drawing, message: String) throws -> [String: Any]? {
        guard !isEmpty else { return nil }
        let marks = drawing.marks
        var numbers: [Mark.ID: Int] = [:]
        for (index, mark) in marks.enumerated() { numbers[mark.id] = index }
        var next = marks.count
        func number(_ id: Mark.ID) -> Int {
            if let known = numbers[id] { return known }
            numbers[id] = next
            next += 1
            return next - 1
        }
        func placed(_ placed: PlacedMark?) throws -> Any? {
            guard let placed else { return nil }
            return ["index": placed.index, "mark": try DrawingJSON.object(from: DrawingJSON.encode(MarkRecord(placed.mark)))]
        }
        func pin(_ pin: Pin?) throws -> Any? {
            try pin.map { try DrawingJSON.object(from: DrawingJSON.encode(PinRecord($0))) }
        }
        func object(_ step: HistoryStep) throws -> (object: [String: Any], bytes: Int) {
            var object: [String: Any] = ["name": step.name.rawValue]
            switch step {
            case .drawing(let step):
                let changes = try step.changes.map { change -> [String: Any] in
                    var item: [String: Any] = ["mark": number(change.id)]
                    item["before"] = try placed(change.before)
                    item["after"] = try placed(change.after)
                    return item
                }
                if !changes.isEmpty || step.pins.isEmpty { object["changes"] = changes }
                if !step.pins.isEmpty {
                    object["pins"] = try step.pins.map { change -> [String: Any] in
                        var item: [String: Any] = ["id": change.id.uuidString]
                        item["before"] = try pin(change.before)
                        item["after"] = try pin(change.after)
                        return item
                    }
                }
                object["selectionBefore"] = step.selectionBefore.map(number).sorted()
                object["selectionAfter"] = step.selectionAfter.map(number).sorted()
            case .message(let step):
                object["message"] = ["before": step.before, "after": step.after]
            }
            return (object, try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).count)
        }
        var undo = try self.undo.map(object), redo = try self.redo.map(object)
        func total() -> Int { (undo + redo).reduce(0) { $0 + $1.bytes } }
        while undo.count + redo.count > Self.maxSteps || total() > Self.maxBytes {
            if undo.isEmpty { redo.removeFirst() } else { undo.removeFirst() }
        }
        guard !undo.isEmpty || !redo.isEmpty else { return nil }
        let basis = try Self.basis(marks: marks, pins: drawing.pins, nextPin: drawing.nextPin, message: message)
        return ["basis": basis, "undo": undo.map(\.object), "redo": redo.map(\.object)]
    }

    /// The history a file's `history` object holds, for the drawing read from that file, whose marks
    /// are `marks` in the file's order. `basis` is `basis(marks:pins:nextPin:message:)` of the file's
    /// marks and pins as stored, before a read moves any into the image, its `nextPin` and its message.
    /// Throws the one thing wrong with it, or that the drawing or the message changed since it was written.
    init(fileObject raw: Any, marks: [Mark], basis: String) throws {
        guard let object = raw as? [String: Any] else { throw MarkProblem("the history is not an object") }
        guard object["basis"] as? String == basis else {
            throw MarkProblem("the drawing or the message changed since it was written")
        }
        var ids: [Int: Mark.ID] = [:]
        for (index, mark) in marks.enumerated() { ids[index] = mark.id }
        func id(_ raw: Any?) throws -> Mark.ID {
            guard let number = DrawingJSON.wholeNumber(raw), number >= 0 else { throw MarkProblem("a mark's number must be a whole number from 0") }
            if let known = ids[number] { return known }
            let made = UUID()
            ids[number] = made
            return made
        }
        func placed(_ raw: Any?, id: Mark.ID) throws -> PlacedMark? {
            guard let raw else { return nil }
            guard let item = raw as? [String: Any], let index = DrawingJSON.wholeNumber(item["index"]), index >= 0 else {
                throw MarkProblem("a changed mark needs an index from 0 and a mark")
            }
            let mark = try Mark(validating: item["mark"] as Any)
            return PlacedMark(mark: Mark(id: id, geometry: mark.geometry, agent: mark.agent, agentName: mark.agentName), index: index)
        }
        func selection(_ raw: Any?) throws -> Set<Mark.ID> {
            guard let list = raw as? [Any] else { throw MarkProblem("a selection must be a list") }
            return Set(try list.map(id))
        }
        func step(_ raw: Any) throws -> HistoryStep {
            guard let item = raw as? [String: Any], let rawName = item["name"] as? String else { throw MarkProblem("a step needs a name") }
            guard let name = StepName(rawValue: rawName) else { throw MarkProblem("unknown step \(rawName)") }
            if let words = item["message"] {
                guard let words = words as? [String: Any], let before = words["before"] as? String, let after = words["after"] as? String else {
                    throw MarkProblem("a message step needs its words before and after")
                }
                return .message(MessageStep(name: name, before: before, after: after))
            }
            let changes = (item["changes"] as? [Any]) ?? [], pins = (item["pins"] as? [Any]) ?? []
            guard !changes.isEmpty || !pins.isEmpty else { throw MarkProblem("a step needs its changes") }
            return .drawing(EditStep(name: name, changes: try changes.map { raw in
                guard let change = raw as? [String: Any] else { throw MarkProblem("a change is not an object") }
                let id = try id(change["mark"])
                let before = try placed(change["before"], id: id), after = try placed(change["after"], id: id)
                guard before != nil || after != nil else { throw MarkProblem("a change needs a mark before or after it") }
                return EditStep.Change(id: id, before: before, after: after)
            }, selectionBefore: try selection(item["selectionBefore"]), selectionAfter: try selection(item["selectionAfter"]),
               pins: try pinChanges(pins)))
        }
        func pinChanges(_ list: [Any]) throws -> [EditStep.PinChange] {
            let changes = try list.map(pinChange)
            guard Set(changes.map(\.id)).count == changes.count else { throw MarkProblem("a step names a pin twice") }
            return changes
        }
        func pinChange(_ raw: Any) throws -> EditStep.PinChange {
            guard let change = raw as? [String: Any], let rawID = change["id"] as? String, let id = UUID(uuidString: rawID) else {
                throw MarkProblem("a changed pin needs its id")
            }
            let before = try change["before"].map { try Pin(validating: $0) }, after = try change["after"].map { try Pin(validating: $0) }
            guard before != nil || after != nil, [before, after].allSatisfy({ $0 == nil || $0?.id == id }) else {
                throw MarkProblem("a changed pin needs itself before or after the change")
            }
            return EditStep.PinChange(id: id, before: before, after: after)
        }
        func steps(_ field: String) throws -> [HistoryStep] {
            guard let list = object[field] as? [Any] else { throw MarkProblem("\(field) must be a list") }
            return try list.map(step)
        }
        self.init(undo: try steps("undo"), redo: try steps("redo"))
    }
}
