import Foundation

// MARK: - Checking marks from outside the process

/// What is wrong with a mark from outside the process, in the words an error or a log line uses:
/// the mark and the field, never what the field held.
struct MarkProblem: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// One mark's fields as JSONSerialization decoded them, read through the checks every mark from
/// outside the process passes: a drawing file, a paste, an agent's `marks=`, a reply. The type is
/// known, numbers are finite, a text holds something and at most
/// `maxTextLength` characters, sizes are more than 0, and an arrow's ends differ.
struct MarkFields {
    /// What a number is: px, which may be anything finite, or a fraction of the image, from 0 to 1.
    enum Unit { case px, fraction }

    static let maxTextLength = 2000
    /// A limit on the bytes as well, since one character can carry any number of combining marks.
    static let maxTextBytes = 100_000

    let item: [String: Any]
    let unit: Unit

    func kind() throws -> MarkKind {
        guard let name = item["type"] as? String else { throw MarkProblem("no type") }
        guard let kind = MarkKind(rawValue: name) else {
            throw MarkProblem("unknown type; use \(MarkKind.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        return kind
    }

    func number(_ key: String) throws -> CGFloat {
        guard let number = DrawingJSON.number(item[key]), unit == .px || (0...1).contains(number) else {
            switch unit {
            case .px: throw MarkProblem("\(key) must be a finite number")
            case .fraction: throw MarkProblem("\(key) must be a number from 0 to 1, a fraction of the image")
            }
        }
        return number
    }

    /// Nil when the mark leaves the field out.
    func optionalNumber(_ key: String) throws -> CGFloat? {
        item[key] == nil ? nil : try number(key)
    }

    func size(_ key: String) throws -> CGFloat {
        let value = try number(key)
        guard value > 0 else { throw MarkProblem("\(key) must be more than 0") }
        return value
    }

    /// Nil when the mark leaves the field out.
    func optionalSize(_ key: String) throws -> CGFloat? {
        item[key] == nil ? nil : try size(key)
    }

    /// Spaces and empty lines alone count as no text, as they do when typing ends.
    func text() throws -> String {
        guard let text = item["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MarkProblem("text is missing")
        }
        guard text.utf8.count <= Self.maxTextBytes else { throw MarkProblem("text is longer than \(Self.maxTextBytes) bytes") }
        guard text.count <= Self.maxTextLength else { throw MarkProblem("text is longer than \(Self.maxTextLength) characters") }
        return text
    }

    /// False when the mark leaves the field out.
    func flag(_ key: String) throws -> Bool {
        guard let raw = item[key] else { return false }
        guard let flag = raw as? NSNumber, CFGetTypeID(flag) == CFBooleanGetTypeID() else {
            throw MarkProblem("\(key) must be true or false")
        }
        return flag.boolValue
    }

    /// The name of the agent that made the mark, as it may be stored (`Agent.clean`). Nil when the
    /// mark leaves it out or it holds nothing.
    func agentName() throws -> String? {
        guard let raw = item["agentName"] else { return nil }
        guard let name = raw as? String else { throw MarkProblem("agentName must be a string") }
        return Agent.clean(name).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// A freehand arrow's `via`: a list of `[x, y]` pairs, in px. Empty when the mark leaves it out.
    func via() throws -> [CGPoint] {
        guard let raw = item["via"] else { return [] }
        guard let pairs = raw as? [Any] else { throw MarkProblem("via must be a list of [x, y] points") }
        guard pairs.count <= Mark.Arrow.maxVia else { throw MarkProblem("via has more than \(Mark.Arrow.maxVia) points") }
        return try pairs.map { pair in
            guard let pair = pair as? [Any], pair.count == 2, let x = DrawingJSON.number(pair[0]), let y = DrawingJSON.number(pair[1]) else {
                throw MarkProblem("via must be a list of [x, y] points")
            }
            return CGPoint(x: x, y: y)
        }
    }

    /// An arrow's `x`, `y` and `x2`, `y2`.
    func arrowEnds() throws -> (start: CGPoint, end: CGPoint) {
        let start = CGPoint(x: try number("x"), y: try number("y"))
        let end = CGPoint(x: try number("x2"), y: try number("y2"))
        guard start != end else { throw MarkProblem("the arrow ends where it starts") }
        return (start, end)
    }
}
