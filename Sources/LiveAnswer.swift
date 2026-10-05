import CoreGraphics
import Foundation

/// What the live ink responder answers: a short reply and up to `maxMarks` marks on the window it
/// was shown. The CLI holds the model to `schema`, and `init(json:)` checks the answer again, since
/// the schema is a request to the model and this is what Vignette draws from.
struct LiveAnswer: Equatable {
    /// The reply, drawn as a note beside the person's ink. Never empty.
    var say: String
    var marks: [AnswerMark]

    static let maxMarks = 4
    /// The longest reply and label drawn, in characters. A longer one is cut at a word.
    static let maxSay = 400
    static let maxLabel = 40

    /// The answer's JSON Schema, for `claude --json-schema`.
    static var schema: [String: Any] { [
        "type": "object",
        "additionalProperties": false,
        "required": ["say", "marks"],
        "properties": [
            "say": ["type": "string", "description": "The answer, in one to three short sentences of plain text."],
            "marks": [
                "type": "array",
                "maxItems": maxMarks,
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["kind"],
                    "properties": [
                        "kind": ["type": "string", "enum": AnswerMark.Kind.allCases.map(\.rawValue)],
                        "line": ["type": "string", "description": "The id of the text line it points at, such as t3."],
                        "words": ["type": "string", "description": "Words copied from that line, when it points at part of the line."],
                        "box": [
                            "type": "array", "items": ["type": "number"], "minItems": 4, "maxItems": 4,
                            "description": "x, y, width and height as fractions of the picture, from its top-left corner, for something with no text line.",
                        ],
                        "label": ["type": "string", "description": "One to four words drawn beside the mark, only when the mark needs them."],
                    ],
                ],
            ],
        ],
    ] }

    struct Problem: Error, CustomStringConvertible {
        let description: String
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
    }

    init(say: String, marks: [AnswerMark] = []) {
        self.say = say
        self.marks = marks
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
/// line, or a box in fractions of the picture.
struct AnswerMark: Equatable {
    enum Kind: String, CaseIterable {
        /// Drawn round what it points at.
        case circle
        /// Points at it from the side with the most room.
        case arrow
    }

    var kind: Kind
    /// A text line's id, such as `t3`.
    var line: String?
    var words: String?
    /// In fractions of the picture, from its top-left corner, inside it.
    var box: CGRect?
    var label: String?

    init(kind: Kind, line: String? = nil, words: String? = nil, box: CGRect? = nil, label: String? = nil) {
        self.kind = kind
        self.line = line
        self.words = words
        self.box = box
        self.label = label
    }

    /// Nil for an unknown kind, or for a mark with neither a line nor a box inside the picture.
    init?(json: Any) {
        guard let object = json as? [String: Any],
              let kind = (object["kind"] as? String).flatMap(Kind.init(rawValue:)) else { return nil }
        self.kind = kind
        line = (object["line"] as? String)?.trimmingCharacters(in: .whitespaces).nonEmpty
        words = (object["words"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        label = (object["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            .map { LiveAnswer.cut($0, to: LiveAnswer.maxLabel) }
        if let numbers = object["box"] as? [Any], numbers.count == 4 {
            let values = numbers.compactMap { DrawingJSON.number($0) }
            let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
            if values.count == 4, values.allSatisfy(\.isFinite), values[2] > 0, values[3] > 0 {
                let rect = CGRect(x: values[0], y: values[1], width: values[2], height: values[3]).intersection(unit)
                box = rect.isNull || rect.width <= 0 || rect.height <= 0 ? nil : rect
            }
        }
        guard line != nil || box != nil else { return nil }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
