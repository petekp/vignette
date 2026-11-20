import Foundation

/// A tool letter typed where a word may begin, which picks its tool and waits: right after a box or
/// an arrow is drawn (`EditorCore.startsNote`), or first into a message field that took the keys on
/// its own. A press next keeps the tool, and a character next makes both keys the first two of the
/// word, with the tool back as it was. Any other key keeps the tool and does what it does there.
struct HeldToolLetter: Equatable {
    /// The tool before the held letter picked its own. Nil while nothing is held.
    private(set) var toolBefore: EditorCore.Tool?

    enum Answer: Equatable {
        /// Take the key and pick this tool.
        case hold(EditorCore.Tool)
        /// Put the held key, then this one, where the word is typed, and pick this tool again.
        case type(restoring: EditorCore.Tool)
        /// Let the key do what it does, and drop the held key, whose tool stays.
        case pass
        /// Take the key and do nothing: a held letter repeating.
        case swallow
    }

    /// What a key types for this rule: its character with no modifier but Shift, lowercased, and nil
    /// for any other key, an Option, Command or Control one included.
    static func character(_ key: EditorCore.Key?, _ modifiers: EditorCore.Modifiers) -> Character? {
        guard case .character(let character)? = key, modifiers.isSubset(of: .shift) else { return nil }
        return character
    }

    /// A key down. `character` is `HeldToolLetter.character` of it. `canHold`: a word may begin
    /// here, so a tool letter is held rather than picking its tool for good.
    mutating func key(_ character: Character?, isRepeat: Bool, canHold: Bool, tool: EditorCore.Tool?) -> Answer {
        if let before = toolBefore {
            guard character != nil else { toolBefore = nil; return .pass }
            if isRepeat { return .swallow }
            toolBefore = nil
            return .type(restoring: before)
        }
        guard canHold, !isRepeat, let character, let tool,
              let picked = EditorCore.Tool.allCases.first(where: { $0.key == character }) else { return .pass }
        toolBefore = tool
        return .hold(picked)
    }

    /// A press, or the field losing the keys: a held letter was the tool.
    mutating func keepTool() { toolBefore = nil }
}
