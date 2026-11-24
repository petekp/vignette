import AppKit

extension EditorView {
    static func key(_ event: NSEvent) -> EditorCore.Key? {
        EditorCore.Key(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers)
    }

    static func modifiers(_ event: NSEvent) -> EditorCore.Modifiers {
        EditorCore.Modifiers(eventFlags: event.modifierFlags.rawValue)
    }
}
