import CoreGraphics
import Foundation

/// What the live ink responder answers: a short reply and up to `maxMarks` marks on the window it
/// was shown. The CLI holds the model to `schema`, and `init(json:)` checks the answer again, since
/// the schema is a request to the model and this is what Vignette draws from.
struct LiveAnswer: Equatable {
    /// The reply, drawn as a note beside the person's ink. Never empty.
    var say: String
    var marks: [AnswerMark]
    /// The marks are steps to take in order: each shows once the one before it has been clicked.
    var steps = false
    /// What the person may answer with a click, as buttons under the reply, such as "Fix both".
    /// A click sends the button's words back as their reply.
    var actions: [Action] = []

    /// A button under the reply. Pointing at it brings out the marks it acts on and fades the rest.
    struct Action: Equatable {
        var title: String
        /// The marks it acts on, as indexes into `marks`; nil for all of them.
        var marks: [Int]?

        init(_ title: String, marks: [Int]? = nil) {
            self.title = title
            self.marks = marks
        }
    }

    static let maxMarks = 4
    /// The longest reply and label drawn, in characters. A longer one is cut at a word.
    static let maxSay = 400
    static let maxLabel = 40
    static let maxActions = 3
    static let maxAction = 24

    /// The answer's JSON Schema, for the responder's `claude --json-schema`. Written out, so it is the
    /// same at every start and lists `say` first, the field that streams in as the reply: built from a
    /// dictionary, its order changed from launch to launch. Its boxes are in thousandths of the
    /// picture, as the packet's are, and `init(responder:)` reads them.
    static let schema = #"""
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["say", "marks"],
      "properties": {
        "say": {"type": "string", "description": "The answer, in one to three short sentences of plain text."},
        "marks": {
          "type": "array",
          "maxItems": \#(maxMarks),
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["kind"],
            "properties": {
              "kind": {"type": "string", "enum": [\#(AnswerMark.Kind.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", "))]},
              "line": {"type": "string", "description": "The id of the text line it points at, such as t3, from the lines sent."},
              "words": {"type": "string", "description": "Words copied from that line when it points at part of the line, or from the picture for text not among the lines."},
              "box": {
                "type": "array", "items": {"type": "integer"}, "minItems": 4, "maxItems": 4,
                "description": "x, y, width and height in thousandths of the picture, from its top-left corner, for something with no text line."
              },
              "label": {"type": "string", "description": "One to four words drawn beside the mark, only when the mark needs them."},
              "zoom": {"type": "boolean", "description": "For a focus mark: magnify what it points at, for something too small to see."}
            }
          }
        },
        "steps": {"type": "boolean", "description": "True when the marks are steps to take in order, each shown once the one before is clicked."},
        "actions": {
          "type": "array", "maxItems": \#(maxActions), "items": {"type": "string"},
          "description": "Up to three next steps the person can click, one to three words each, such as \"Fix both\". A click sends the words back as their reply."
        }
      }
    }
    """#

    struct Problem: Error, CustomStringConvertible {
        let description: String
    }

    /// Reads the responder's answer, whose boxes are in thousandths of the picture as `schema` asks.
    /// A session's answer gives fractions, as `init(json:)` reads them.
    init(responder json: Any) throws {
        guard var object = json as? [String: Any], let marks = object["marks"] as? [Any] else {
            try self.init(json: json)
            return
        }
        object["marks"] = marks.map { item -> Any in
            guard var mark = item as? [String: Any], let box = mark["box"] as? [Any] else { return item }
            mark["box"] = box.compactMap(DrawingJSON.number).map { Double($0) / 1000 }
            return mark
        }
        try self.init(json: object)
    }

    /// Checks an answer from outside the process. A mark that names nothing it can point at is
    /// dropped rather than failing the answer, since the reply is still worth showing.
    init(json: Any) throws {
        guard let object = json as? [String: Any] else { throw Problem(description: "the answer is not an object") }
        guard let say = (object["say"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !say.isEmpty else {
            throw Problem(description: "the answer has no say")
        }
        self.say = Self.cut(say, to: Self.maxSay)
        let items = object["marks"] as? [Any] ?? []
        marks = items.prefix(Self.maxMarks).compactMap(AnswerMark.init(json:))
        steps = object["steps"] as? Bool ?? false
        actions = Self.actions(object["actions"])
    }

    init(say: String, marks: [AnswerMark] = [], steps: Bool = false, actions: [Action] = []) {
        self.say = say
        self.marks = marks
        self.steps = steps
        self.actions = actions
    }

    /// The actions worth a button, from the words alone or `{"title", "marks"}`: words on one line,
    /// cut to `maxAction` characters, no repeats, and only the indexes of marks there can be.
    static func actions(_ value: Any?) -> [Action] {
        actions(((value as? [Any]) ?? []).compactMap { item -> Action? in
            if let title = item as? String { return Action(title) }
            guard let object = item as? [String: Any], let title = object["title"] as? String else { return nil }
            return Action(title, marks: (object["marks"] as? [Any])?.compactMap { $0 as? Int })
        })
    }

    static func actions(_ actions: [Action]) -> [Action] {
        var seen = Set<String>()
        return actions.compactMap { action -> Action? in
            let line = action.title.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, seen.insert(line.lowercased()).inserted else { return nil }
            let marks = Set(action.marks ?? []).filter { (0..<maxMarks).contains($0) }.sorted()
            return Action(cut(line, to: maxAction), marks: marks.isEmpty ? nil : marks)
        }.prefix(maxActions).map { $0 }
    }

    /// `text` no longer than `limit` characters, cut after the last whole word, with an ellipsis.
    static func cut(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let head = text.prefix(limit - 1)
        let word = head.lastIndex(where: \.isWhitespace).map { head[..<$0] } ?? head
        return word.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    /// The part of `say` that has streamed in, from the partial JSON of the answer so far. Nil until
    /// its first character arrives. The schema's `say` comes first, and the model has written it
    /// first in every answer measured.
    static func partialSay(in json: String) -> String? {
        guard let key = json.range(of: "\"say\"") else { return nil }
        var rest = json[key.upperBound...].drop { $0 == " " || $0 == ":" || $0 == "\n" }
        guard rest.first == "\"" else { return nil }
        rest = rest.dropFirst()
        var text = ""
        var escaped = false
        var unicode: String?
        for character in rest {
            if var hex = unicode {
                hex.append(character)
                if hex.count == 4 {
                    if let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) { text.unicodeScalars.append(scalar) }
                    unicode = nil
                } else {
                    unicode = hex
                }
            } else if escaped {
                escaped = false
                switch character {
                case "n": text.append("\n")
                case "t": text.append("\t")
                case "u": unicode = ""
                default: text.append(character)
                }
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                break
            } else {
                text.append(character)
            }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : cut(trimmed, to: maxSay)
    }
}

/// One mark of an answer: what it points at, named by a text line of the packet, words within that
/// line, or a box in fractions of the picture. A session's answer has no line ids, so its words are
/// looked for in every line.
struct AnswerMark: Equatable {
    enum Kind: String, CaseIterable {
        /// Drawn round what it points at.
        case circle
        /// Points at it from the side with the most room.
        case arrow
        /// Pulls focus to it: the rest of the window goes soft and grey for a while, and it stays sharp.
        case focus
    }

    var kind: Kind
    /// A text line's id, such as `t3`.
    var line: String?
    var words: String?
    /// In fractions of the picture, from its top-left corner, inside it.
    var box: CGRect?
    var label: String?
    /// For a focus mark: magnify what it points at under a lens.
    var zoom = false

    init(kind: Kind, line: String? = nil, words: String? = nil, box: CGRect? = nil, label: String? = nil, zoom: Bool = false) {
        self.kind = kind
        self.line = line
        self.words = words
        self.box = box
        self.label = label
        self.zoom = kind == .focus && zoom
    }

    /// Nil for an unknown kind, or for a mark with no line, no words and no box inside the picture.
    init?(json: Any) {
        guard let object = json as? [String: Any],
              let kind = (object["kind"] as? String).flatMap(Kind.init(rawValue:)) else { return nil }
        self.kind = kind
        line = (object["line"] as? String)?.trimmingCharacters(in: .whitespaces).nonEmpty
        words = (object["words"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        label = (object["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            .map { LiveAnswer.cut($0, to: LiveAnswer.maxLabel) }
        zoom = kind == .focus && object["zoom"] as? Bool == true
        if let numbers = object["box"] as? [Any], numbers.count == 4 {
            let values = numbers.compactMap { DrawingJSON.number($0) }
            let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
            if values.count == 4, values.allSatisfy(\.isFinite), values[2] > 0, values[3] > 0 {
                let rect = CGRect(x: values[0], y: values[1], width: values[2], height: values[3]).intersection(unit)
                box = rect.isNull || rect.width <= 0 || rect.height <= 0 ? nil : rect
            }
        }
        guard line != nil || words != nil || box != nil else { return nil }
    }
}

/// An answer travels in a reply's bundle and record as the JSON `init(json:)` reads, boxes in
/// fractions, and is read back through it, so there is one validator for the responder's answers and
/// a session's.
extension LiveAnswer: Codable {
    private enum Keys: String, CodingKey { case say, marks, steps, actions }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let marks = try container.decodeIfPresent([AnswerMark].self, forKey: .marks) ?? []
        try self.init(json: ["say": try container.decode(String.self, forKey: .say)])
        self.marks = Array(marks.prefix(Self.maxMarks))
        steps = try container.decodeIfPresent(Bool.self, forKey: .steps) ?? false
        actions = Self.actions(try container.decodeIfPresent([Action].self, forKey: .actions) ?? [])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(say, forKey: .say)
        try container.encode(marks, forKey: .marks)
        if steps { try container.encode(steps, forKey: .steps) }
        if !actions.isEmpty { try container.encode(actions, forKey: .actions) }
    }
}

/// An action is its words alone when it acts on every mark, as before actions named their marks.
extension LiveAnswer.Action: Codable {
    private enum Keys: String, CodingKey { case title, marks }

    init(from decoder: Decoder) throws {
        if let title = try? decoder.singleValueContainer().decode(String.self) {
            self.init(title)
            return
        }
        let container = try decoder.container(keyedBy: Keys.self)
        self.init(try container.decode(String.self, forKey: .title), marks: try container.decodeIfPresent([Int].self, forKey: .marks))
    }

    func encode(to encoder: Encoder) throws {
        guard let marks else {
            var container = encoder.singleValueContainer()
            try container.encode(title)
            return
        }
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(title, forKey: .title)
        try container.encode(marks, forKey: .marks)
    }
}

extension AnswerMark: Codable {
    private enum Keys: String, CodingKey { case kind, line, words, box, label, zoom }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        var object: [String: Any] = ["kind": try container.decode(String.self, forKey: .kind)]
        object["line"] = try container.decodeIfPresent(String.self, forKey: .line)
        object["words"] = try container.decodeIfPresent(String.self, forKey: .words)
        object["box"] = try container.decodeIfPresent([Double].self, forKey: .box)
        object["label"] = try container.decodeIfPresent(String.self, forKey: .label)
        object["zoom"] = try container.decodeIfPresent(Bool.self, forKey: .zoom)
        guard let mark = AnswerMark(json: object) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "a mark points at nothing"))
        }
        self = mark
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(kind.rawValue, forKey: .kind)
        try container.encodeIfPresent(line, forKey: .line)
        try container.encodeIfPresent(words, forKey: .words)
        try container.encodeIfPresent(box.map { [$0.minX, $0.minY, $0.width, $0.height] }, forKey: .box)
        try container.encodeIfPresent(label, forKey: .label)
        if zoom { try container.encode(zoom, forKey: .zoom) }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
