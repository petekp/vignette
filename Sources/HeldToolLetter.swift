import Foundation

/// A tool letter typed first into a message field that took the keys on its own, which picks its
/// tool and waits, as a tool key does after a box is drawn (`EditorCore.startsNote`): a press next
/// keeps the tool, and a character next makes both keys the message's first two, with the tool
/// back as it was. Any other key keeps the tool and does what it does in the empty field.
struct HeldToolLetter: Equatable {
    /// The tool before the held letter picked its own. Nil while nothing is held.
    private(set) var toolBefore: EditorCore.Tool?

    enum Answer: Equatable {
        /// Take the key and pick this tool.
        case hold(EditorCore.Tool)
        /// Put the held key, then this one, in the field, and pick this tool again.
        case type(restoring: EditorCore.Tool)
        /// Let the key do what it does, and drop the held key, whose tool stays.
        case pass
        /// Take the key and do nothing: a held letter repeating.
        case swallow
    }

    /// A key down in the message field. `character` is what it types with no modifier but Shift,
    /// lowercased, and nil for any other key. `fieldUntouched`: the field took the keys on its own
    /// and nothing is typed in it.
    mutating func key(_ character: Character?, isRepeat: Bool, fieldUntouched: Bool, tool: EditorCore.Tool?) -> Answer {
        if let before = toolBefore {
            guard character != nil else { toolBefore = nil; return .pass }
            if isRepeat { return .swallow }
            toolBefore = nil
            return .type(restoring: before)
        }
        guard fieldUntouched, !isRepeat, let character, let tool,
              let picked = EditorCore.Tool.allCases.first(where: { $0.key == character }) else { return .pass }
        toolBefore = tool
        return .hold(picked)
    }

    /// A press, or the field losing the keys: a held letter was the tool.
    mutating func keepTool() { toolBefore = nil }
}
