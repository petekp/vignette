import Foundation

extension LiveAnswer {
    /// The answer's JSON Schema, for the Claude responder's `claude --json-schema`. Written out, so it is
    /// the same at every start and lists `say` first, the field that streams in as the reply: built from
    /// a dictionary, its order changed from launch to launch. Its boxes are in thousandths of the
    /// picture, as the packet's are, and `init(responder:)` reads them.
    static let schema = answerSchema(strict: false)

    /// The same schema in the strict form OpenAI's structured outputs require, for the Codex
    /// responder's `outputSchema`: every property is required, and the ones `schema` leaves optional
    /// may be null, which `init(responder:)` reads as absent. Strict mode refuses `schema` itself
    /// ("'required' is required to include every key in properties").
    static let strictSchema = answerSchema(strict: true)

    private static func answerSchema(strict: Bool) -> String {
        func required(_ keys: [String], of all: [String]) -> String {
            "[" + (strict ? all : keys).map { "\"\($0)\"" }.joined(separator: ", ") + "]"
        }
        func optional(_ type: String) -> String { strict ? #"["\#(type)", "null"]"# : #""\#(type)""# }
        return #"""
        {
          "type": "object",
          "additionalProperties": false,
          "required": \#(required(["say", "marks"], of: ["say", "marks", "steps", "actions"])),
          "properties": {
            "say": {"type": "string", "description": "The answer, in plain text: usually two short sentences, never more than three. Only the first three are shown."},
            "marks": {
              "type": "array",
              "maxItems": \#(maxMarks),
              "items": {
                "type": "object",
                "additionalProperties": false,
                "required": \#(required(["kind"], of: ["kind", "line", "words", "box", "label", "zoom"])),
                "properties": {
                  "kind": {"type": "string", "enum": [\#(AnswerMark.Kind.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", "))]},
                  "line": {"type": \#(optional("string")), "description": "The id of the text line it points at, such as t3, from the lines sent."},
                  "words": {"type": \#(optional("string")), "description": "Words copied from that line when it points at part of the line, or from the picture for text not among the lines."},
                  "box": {
                    "type": \#(optional("array")), "items": {"type": "integer"}, "minItems": 4, "maxItems": 4,
                    "description": "x, y, width and height in thousandths of the picture, from its top-left corner, for something with no text line."
                  },
                  "label": {"type": \#(optional("string")), "description": "One to four words drawn beside the mark, only when the mark needs them."},
                  "zoom": {"type": \#(optional("boolean")), "description": "For a focus mark: magnify what it points at, for something too small to see."}
                }
              }
            },
            "steps": {"type": \#(optional("boolean")), "description": "True when the marks are steps to take in order, each shown once the one before is clicked."},
            "actions": {
              "type": \#(optional("array")), "maxItems": \#(maxActions), "items": {"type": "string"},
              "description": "Up to three next steps the person can click, one to three words each, such as \"Fix both\". A click sends the words back as their reply."
            }
          }
        }
        """#
    }
}
