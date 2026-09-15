import Carbon
import Foundation

/// A hotkey as written in settings.json ("cmd+shift+6", "double-rshift"), parsed into key codes.
/// Shared by the app (HotKey, ModifierTap) and by scripts/input.swift, so both read the same strings.
enum HotKeySpec: Equatable {
    /// A key with Carbon modifier flags (cmdKey, shiftKey, optionKey, controlKey).
    case key(keyCode: UInt32, modifiers: UInt32)
    /// A modifier key tapped twice, e.g. "double-rshift". Needs Accessibility permission.
    case doubleTap(keyCode: UInt16)

    /// Parses "cmd+shift+6", "ctrl+opt+s", "cmd+f5", or "double-rshift" (also lshift, rcmd, lcmd,
    /// ropt, lopt, rctrl, lctrl). Returns nil for anything it cannot map.
    static func parse(_ text: String) -> HotKeySpec? {
        let trimmed = text.lowercased().trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("double-"), let code = modifierCodes[String(trimmed.dropFirst("double-".count))] {
            return .doubleTap(keyCode: code)
        }
        var mods: UInt32 = 0
        var key: String?
        for raw in text.lowercased().split(separator: "+") {
            let token = raw.trimmingCharacters(in: .whitespaces)
            switch token {
            case "cmd", "command": mods |= UInt32(cmdKey)
            case "shift": mods |= UInt32(shiftKey)
            case "opt", "option", "alt": mods |= UInt32(optionKey)
            case "ctrl", "control": mods |= UInt32(controlKey)
            default: key = token
            }
        }
        guard let key, let code = keyCodes[key] else { return nil }
        return .key(keyCode: code, modifiers: mods)
    }

    /// Virtual key codes of the modifier keys, by the name used after "double-".
    static let modifierCodes: [String: UInt16] = [
        "lshift": 56, "rshift": 60, "lcmd": 55, "rcmd": 54, "lopt": 58, "ropt": 61, "lctrl": 59, "rctrl": 62,
    ]

    /// Virtual key codes of the keys a hotkey can name.
    static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
        "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25,
        "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
        "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50,
        "space": 49, "return": 36, "tab": 48, "escape": 53, "delete": 51,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109,
        "f11": 103, "f12": 111, "up": 126, "down": 125, "left": 123, "right": 124,
    ]
}
