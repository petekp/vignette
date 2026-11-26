import AppKit

/// The composer's field, which keeps where its caret was when its editing ended.
final class ComposerField: NSTextField {
    var endedSelection: NSRange?

    override func textDidEndEditing(_ notification: Notification) {
        endedSelection = (notification.object as? NSTextView)?.selectedRange()
        super.textDidEndEditing(notification)
    }
}

/// The popover's view, which takes its Command keys as key equivalents: Cmd+Return, which may never
/// reach the field as a new line, and the editor's zoom keys, which the field has no use for.
final class CommandKeyStack: NSStackView {
    var commandReturn: (() -> Void)?
    var zoom: ((EditorCore.ZoomRequest) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else { return super.performKeyEquivalent(with: event) }
        if [36, 76].contains(event.keyCode), let commandReturn {
            commandReturn()
            return true
        }
        if let zoom, case .character(let character)? = EditorCore.Key(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers),
           let request = EditorCore.zoomRequest(for: character) {
            zoom(request)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
