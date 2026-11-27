import Foundation

extension EditorCore {
    static func isBlank(_ mark: Mark) -> Bool {
        guard case .text(let text) = mark.geometry else { return false }
        return text.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// `text` cut to what a drawing file may hold: `MarkFields`' characters and bytes.
    static func capped(_ text: String) -> String {
        var capped = "", bytes = 0
        for character in text.prefix(MarkFields.maxTextLength) {
            bytes += character.utf8.count
            guard bytes <= MarkFields.maxTextBytes else { break }
            capped.append(character)
        }
        return capped
    }
}
