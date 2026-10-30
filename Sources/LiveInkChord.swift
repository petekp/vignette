import AppKit

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
    var glyphs: String { HotKeySpec.modifierGlyphs(HotKeySpec.carbonModifiers(flags)) }

    /// Whether pressing `shortcut` holds this pair first. The chord begins as the pair goes down, so
    /// the stack's shortcut would start live ink, which takes the pointer and lets go of the focus,
    /// as the stack comes up. A double tap never does: `ModifierTap` counts a modifier pressed alone.
    func isHeld(by shortcut: HotKeySpec?) -> Bool {
        guard case .key(_, let modifiers)? = shortcut else { return false }
        return HotKeySpec.eventModifiers(modifiers).isSuperset(of: flags)
    }

    /// Why this pair cannot hold live ink beside the stack's `shortcut`, or nil.
    func refusal(against shortcut: HotKeySpec?) -> String? {
        guard let shortcut, isHeld(by: shortcut) else { return nil }
        return "\(shortcut.glyphs), the stack's shortcut, starts with these keys. You can pick another pair."
    }

    /// Why a combination recorded for the stack cannot be its shortcut while live ink holds this pair,
    /// or nil. The recorder's other refusals are `HotKeySpec.refusal`.
    func refusal(ofStackShortcut shortcut: HotKeySpec) -> String? {
        isHeld(by: shortcut) ? "Live ink uses \(glyphs). You can pick another combination." : nil
    }
}
