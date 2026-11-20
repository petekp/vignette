import AppKit

/// Key only for the message field: a press on it takes the keys, and a press anywhere else in the
/// bar leaves them, and so the tool keys and shortcuts, with the editor window. SwiftUI's buttons
/// ask for the keys as a text field does, so `becomesKeyOnlyIfNeeded` cannot tell them apart.
@MainActor
final class ToolbarPanel: NSPanel {
    /// The last left press was on the message field, until the panel resigns the keys: after that
    /// only a new press or `takeKeys` makes it key, never AppKit choosing the next key window.
    private var pressOnField = false
    private var wantsKeys = false
    /// Cmd+Return while the message field has the keys: Send, as in the editor.
    var onCommandReturn: (() -> Void)?
    /// Any other Command key while the message field has the keys, before the field sees it. True
    /// when it was taken (`FieldCommand`).
    var onCommandKey: ((NSEvent) -> Bool)?
    /// Tab or Shift+Tab (true) while the message field has the keys.
    var onTab: ((_ backward: Bool) -> Void)?
    /// A press on the bar, and whether it is on the message field.
    var onPress: ((_ onField: Bool) -> Void)?
    /// A key down, before the field sees it. True when it was taken.
    var onKey: ((NSEvent) -> Bool)?
    /// Up on the message field's first line or Down on its last. True when it opened the target's menu.
    var onMenuKey: (() -> Bool)?
    override var canBecomeKey: Bool { pressOnField || wantsKeys || isKeyWindow }

    /// Delivers a key that `onKey` held, past `onKey`.
    func replay(_ event: NSEvent) { super.sendEvent(event) }

    /// Takes the keys for the message field without a press on it: Tab onto it, M or P, or the image
    /// opening (`AnnotatorToolbar.typeOnOpen`).
    func takeKeys() {
        wantsKeys = true
        makeKey()
        wantsKeys = false
    }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        pressOnField = false
    }

    /// The next time the message field becomes first responder, its caret goes to the end of its
    /// words. AppKit selects them all instead, and the first letter typed would replace them.
    var caretToEnd = false

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let made = super.makeFirstResponder(responder)
        if made, caretToEnd, let text = firstResponder as? NSTextView {
            caretToEnd = false
            text.setSelectedRange(NSRange(location: (text.string as NSString).length, length: 0))
        }
        return made
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, EditorCore.Key(keyCode: event.keyCode, characters: nil) == .returnKey,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            onCommandReturn?()
            return true
        }
        if event.type == .keyDown, onCommandKey?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, let content = contentView {
            // NSWindow makes itself key inside `super.sendEvent`, so the answer is ready before it asks.
            var view = content.hitTest(content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow)
            while let current = view, !(current is NSTextField || current is NSText) { view = current.superview }
            pressOnField = view != nil
            onPress?(pressOnField)
        }
        if event.type == .keyDown, onKey?(event) == true { return }
        let composing = (firstResponder as? NSTextView)?.hasMarkedText() == true
        if event.type == .keyDown, !composing, event.modifierFlags.isDisjoint(with: [.command, .control, .option]) {
            switch EditorCore.Key(keyCode: event.keyCode, characters: nil) {
            case .tab?:
                // The next control rather than the key view loop.
                onTab?(event.modifierFlags.contains(.shift))
                return
            case let arrow? where (arrow == .up || arrow == .down) && !event.modifierFlags.contains(.shift):
                // On the field's first line or its last, the target's menu, as on a pop-up button.
                // Within the text the arrows move the caret.
                if let text = firstResponder as? NSTextView, text.caretIsOnLine(first: arrow == .up), onMenuKey?() == true { return }
            default:
                break
            }
        }
        super.sendEvent(event)
    }
}

/// A Command key the message field has no use for, which does what it does on the image instead.
/// The rest, such as Cmd+V, Cmd+A, Cmd+X and Cmd+Z, stay with the field.
enum FieldCommand: Equatable {
    /// Cmd+W: the annotator closes, as through the main menu's Close.
    case close
    /// Cmd+Plus, Cmd+Minus and Cmd+0, by the editor's own rule.
    case zoom(EditorCore.ZoomRequest)
    /// Cmd+C in an untouched field with none of its words selected: the drawing, as Cmd+C copies it
    /// on the image with nothing selected.
    case copyDrawing

    /// `fieldUntouched`: `AnnotatorToolbar.Model.fieldUntouched`. `wordsSelected`: the field's
    /// selection is not empty.
    init?(_ key: EditorCore.Key?, _ modifiers: EditorCore.Modifiers, fieldUntouched: Bool, wordsSelected: Bool) {
        guard modifiers.contains(.command), case .character(let character)? = key else { return nil }
        if let zoom = EditorCore.zoomRequest(for: character) {
            self = .zoom(zoom)
        } else if character == "w", modifiers == .command {
            self = .close
        } else if character == "c", modifiers == .command, fieldUntouched, !wordsSelected {
            self = .copyDrawing
        } else {
            return nil
        }
    }
}

private extension NSTextView {
    /// Whether the caret is on the text's first line as laid out, or with `first` false its last.
    func caretIsOnLine(first: Bool) -> Bool {
        let length = (string as NSString).length
        guard length > 0, let layout = layoutManager, let container = textContainer else { return true }
        let caret = selectedRange().location
        let line = caret >= length && layout.extraLineFragmentTextContainer != nil
            ? layout.extraLineFragmentRect
            : layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: min(caret, length - 1)), effectiveRange: nil)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        return first ? line.minY <= used.minY : line.maxY >= used.maxY
    }
}
