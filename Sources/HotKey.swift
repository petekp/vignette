import Carbon
import Foundation

/// Global hotkey via Carbon. Works without Accessibility permission.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, selfPtr, &handler)
        let id = EventHotKeyID(signature: OSType(0x53484F54), id: 1) // "SHOT"
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }

    /// Parses "cmd+shift+6", "ctrl+opt+s", "cmd+f5". Returns nil for anything it cannot map.
    static func parse(_ text: String) -> (keyCode: UInt32, modifiers: UInt32)? {
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
        return (code, mods)
    }

    private static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
        "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25,
        "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
        "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50,
        "space": 49, "return": 36, "tab": 48, "escape": 53, "delete": 51,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109,
        "f11": 103, "f12": 111, "up": 126, "down": 125, "left": 123, "right": 124,
    ]
}
