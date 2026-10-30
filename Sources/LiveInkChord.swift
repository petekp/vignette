import AppKit
import Carbon.HIToolbox

/// The two modifiers that hold live ink on (decision 7 in docs/live-ink-release-plan-2026-10-24.md).
/// ⌃⌥ is the default. VoiceOver also uses ⌃⌥, and some window managers do, so a person can choose
/// another pair.
enum LiveInkChord: String, CaseIterable {
    case controlOption = "control+option"
    case controlShift = "control+shift"
    case optionShift = "option+shift"
    case controlCommand = "control+command"
    case optionCommand = "option+command"

    static let standard = LiveInkChord.controlOption

    var flags: NSEvent.ModifierFlags {
        switch self {
        case .controlOption: [.control, .option]
        case .controlShift: [.control, .shift]
        case .optionShift: [.option, .shift]
        case .controlCommand: [.control, .command]
        case .optionCommand: [.option, .command]
        }
    }

    /// The pair as the keys read on the menu bar, such as "⌃⌥".
    var glyphs: String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text
    }

    /// Why the stack's shortcut cannot share this pair, or nil. A double tap of a modifier in the pair
    /// holds the pair down as it is tapped. A key combination whose modifiers include the pair starts
    /// when the pair is held and the key is pressed, which is the stack's own shortcut.
    func refusal(against shortcut: HotKeySpec?) -> String? {
        switch shortcut {
        case .doubleTap(let keyCode)?:
            guard let tapped = Self.modifier(ofKeyCode: keyCode), flags.contains(tapped.flag) else { return nil }
            return "The stack's shortcut taps \(tapped.name) twice, and this pair holds \(tapped.name). Pick another pair."
        case .key(_, let modifiers)?:
            let shortcutFlags = Self.flags(carbon: modifiers)
            guard shortcutFlags.isSuperset(of: flags) else { return nil }
            return "The stack's shortcut uses \(glyphs), so holding \(glyphs) would start it. Pick another pair."
        case nil:
            return nil
        }
    }

    /// The modifier a double tap's key is, from `HotKeySpec`'s key codes, with its name for a person.
    private static func modifier(ofKeyCode code: UInt16) -> (flag: NSEvent.ModifierFlags, name: String)? {
        switch code {
        case 56, 60: (.shift, "Shift")
        case 55, 54: (.command, "Command")
        case 58, 61: (.option, "Option")
        case 59, 62: (.control, "Control")
        default: nil
        }
    }

    private static func flags(carbon modifiers: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }
}
