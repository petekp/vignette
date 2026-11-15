import Foundation

/// How the responder's reply is read: the sentences it keeps, and the part that has streamed in.
extension LiveAnswer {
    /// The most sentences of the responder's reply that are shown.
    static let maxSentences = 3

    /// `text` through the end of its `maxSentences`th sentence, split as Foundation splits sentences.
    static func firstSentences(of text: String) -> String {
        var ends: [String.Index] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, range, _, stop in
            guard let sentence, !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            ends.append(range.upperBound)
            stop = ends.count > maxSentences
        }
        guard ends.count > maxSentences else { return text }
        return text[..<ends[maxSentences - 1]].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The part of the responder's `say` that has streamed in, from the partial JSON of the answer so
    /// far, cut as `init(responder:)` cuts it, so the reply stops growing where the answer will end.
    /// Nil until its first character arrives. The schema's `say` comes first, and the model has
    /// written it first in every answer measured.
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
        let trimmed = firstSentences(of: text).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : cut(trimmed, to: maxSay)
    }
}
