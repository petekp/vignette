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
    /// A left press that is not on the message field, before the bar sees it. True when it opened the
    /// target's menu, which then tracks the press to its release.
    var onPressMenu: ((NSEvent) -> Bool)?
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
        // The editor's history holds the field's steps, so the text view keeps none of its own.
        (firstResponder as? NSTextView)?.allowsUndo = false
        if made, caretToEnd, let text = firstResponder as? NSTextView {
            caretToEnd = false
            text.setSelectedRange(NSRange(location: (text.string as NSString).length, length: 0))
        }
        return made
    }

    /// Undo or Redo (true) from the Edit menu while the message field has the keys.
    var onUndo: ((_ redo: Bool) -> Void)?
    /// The Edit menu's words for Undo or Redo (true), and whether it can act.
    var undoTitle: ((_ redo: Bool) -> (title: String, enabled: Bool))?

    /// An input method is composing a word in the field: its keys are the input method's.
    private var composing: Bool { (firstResponder as? NSTextView)?.hasMarkedText() == true }

    @objc func undo(_ sender: Any?) { if !composing { onUndo?(false) } }
    @objc func redo(_ sender: Any?) { if !composing { onUndo?(true) } }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        let undo = item.action == #selector(undo(_:)), redo = item.action == #selector(redo(_:))
        guard undo || redo else { return super.validateUserInterfaceItem(item) }
        guard !composing, let (title, enabled) = undoTitle?(redo) else { return false }
        (item as? NSMenuItem)?.title = title
        return enabled
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
            if !pressOnField, onPressMenu?(event) == true { return }
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
/// The rest, such as Cmd+V, Cmd+A and Cmd+X, stay with the field.
enum FieldCommand: Equatable {
    /// Cmd+Z and Shift+Cmd+Z, unless a word is being composed: the editor's one history, which holds
    /// the field's typing in order with the marks.
    case undo
    case redo
    /// Cmd+W: the annotator closes, as through the main menu's Close.
    case close
    /// Cmd+Plus, Cmd+Minus and Cmd+0, by the editor's own rule.
    case zoom(EditorCore.ZoomRequest)
    /// Cmd+C in an empty field: the drawing, as Cmd+C copies it on the image with nothing selected.
    case copyDrawing

    /// `fieldEmpty`: `Model.fieldEmpty`, and no word is being composed in the field.
    init?(_ key: EditorCore.Key?, _ modifiers: EditorCore.Modifiers, fieldEmpty: Bool, composing: Bool = false) {
        guard modifiers.contains(.command), case .character(let character)? = key else { return nil }
        if character == "z", !composing, modifiers == .command || modifiers == [.command, .shift] {
            self = modifiers.contains(.shift) ? .redo : .undo
        } else if let zoom = EditorCore.zoomRequest(for: character) {
            self = .zoom(zoom)
        } else if character == "w", modifiers == .command {
            self = .close
        } else if character == "c", modifiers == .command, fieldEmpty {
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
