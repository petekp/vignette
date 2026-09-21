import AppKit
import Carbon

/// How a hotkey is written for a user and read back from a key event. Separate from HotKeySpec.swift
/// because that file is compiled into scripts/input.swift with only Carbon and Foundation; this one
/// needs AppKit.
extension HotKeySpec {
    /// The key name as written in settings.json for a virtual key code ("6", "space", "f5"), or nil.
    static func keyName(forKeyCode code: UInt32) -> String? { namesByKeyCode[code] }

    /// The settings.json text for a key combination ("ctrl+opt+shift+cmd+6"), modifiers in the order
    /// macOS lists them (⌃⌥⇧⌘). nil when the key code has no name. Modifiers are Carbon flags.
    static func text(keyCode: UInt32, modifiers: UInt32) -> String? {
        guard let name = keyName(forKeyCode: keyCode) else { return nil }
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("ctrl") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("opt") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("shift") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("cmd") }
        parts.append(name)
        return parts.joined(separator: "+")
    }

    /// The settings.json text for a double tap of a modifier key by its virtual key code
    /// ("double-rshift"), or nil.
    static func doubleTapText(forKeyCode code: UInt16) -> String? {
        modifierNamesByKeyCode[code].map { "double-\($0)" }
    }

    /// What a user reads: "⇧⌘6", "⌃⌥Space", "⌘F5", "⌘↑", "Right Shift ×2".
    var glyphs: String {
        switch self {
        case let .key(keyCode, modifiers):
            let text = HotKeySpec.modifierGlyphs(modifiers)
            guard let name = HotKeySpec.keyName(forKeyCode: keyCode) else { return text }
            return text + (HotKeySpec.specialKeys[name]?.glyph ?? name.uppercased())
        case let .doubleTap(keyCode):
            return HotKeySpec.modifierLabel(forKeyCode: keyCode).map { "\($0) ×2" } ?? ""
        }
    }

    /// The key itself on one line, for a hint that says what to hold or tap.
    var label: String {
        switch self {
        case .key:
            return glyphs
        case let .doubleTap(keyCode):
            return HotKeySpec.modifierLabel(forKeyCode: keyCode).map { "double-tap \($0)" } ?? ""
        }
    }

    /// The NSMenuItem key equivalent, so a menu renders the hotkey in its shortcut column.
    /// nil for a double tap, which no menu can draw.
    var menuKeyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags)? {
        guard case let .key(keyCode, modifiers) = self,
              let name = HotKeySpec.keyName(forKeyCode: keyCode) else { return nil }
        return (HotKeySpec.specialKeys[name]?.keyEquivalent ?? name, HotKeySpec.eventModifiers(modifiers))
    }

    /// Carbon modifier flags from NSEvent modifier flags (command, shift, option, control only).
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    private static func eventModifiers(_ modifiers: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }

    private static func modifierGlyphs(_ modifiers: UInt32) -> String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text
    }

    private static func modifierLabel(forKeyCode code: UInt16) -> String? {
        modifierNamesByKeyCode[code].flatMap { modifierLabels[$0] }
    }

    /// A key whose name is not the character it types: what a user reads, and what a menu item takes.
    private struct KeyGlyph {
        let glyph: String
        let keyEquivalent: String
    }

    private static let namesByKeyCode: [UInt32: String] =
        Dictionary(uniqueKeysWithValues: keyCodes.map { ($0.value, $0.key) })

    private static let modifierNamesByKeyCode: [UInt16: String] =
        Dictionary(uniqueKeysWithValues: modifierCodes.map { ($0.value, $0.key) })

    private static let modifierLabels: [String: String] = [
        "lshift": "Left Shift", "rshift": "Right Shift",
        "lcmd": "Left Command", "rcmd": "Right Command",
        "lopt": "Left Option", "ropt": "Right Option",
        "lctrl": "Left Control", "rctrl": "Right Control",
    ]

    private static let specialKeys: [String: KeyGlyph] = {
        func scalar(_ code: Int) -> String { String(UnicodeScalar(UInt32(code))!) }
        var table: [String: KeyGlyph] = [
            "space": KeyGlyph(glyph: "Space", keyEquivalent: " "),
            "return": KeyGlyph(glyph: "↩", keyEquivalent: "\r"),
            "tab": KeyGlyph(glyph: "⇥", keyEquivalent: "\t"),
            "escape": KeyGlyph(glyph: "⎋", keyEquivalent: "\u{1b}"),
            "delete": KeyGlyph(glyph: "⌫", keyEquivalent: "\u{8}"),
            "up": KeyGlyph(glyph: "↑", keyEquivalent: scalar(NSUpArrowFunctionKey)),
            "down": KeyGlyph(glyph: "↓", keyEquivalent: scalar(NSDownArrowFunctionKey)),
            "left": KeyGlyph(glyph: "←", keyEquivalent: scalar(NSLeftArrowFunctionKey)),
            "right": KeyGlyph(glyph: "→", keyEquivalent: scalar(NSRightArrowFunctionKey)),
        ]
        let functionKeys = [NSF1FunctionKey, NSF2FunctionKey, NSF3FunctionKey, NSF4FunctionKey,
                            NSF5FunctionKey, NSF6FunctionKey, NSF7FunctionKey, NSF8FunctionKey,
                            NSF9FunctionKey, NSF10FunctionKey, NSF11FunctionKey, NSF12FunctionKey]
        for (index, code) in functionKeys.enumerated() {
            table["f\(index + 1)"] = KeyGlyph(glyph: "F\(index + 1)", keyEquivalent: scalar(code))
        }
        return table
    }()
}
