import AppKit

// MARK: Keyboard focus

extension AnnotatorToolbar {
    /// Tab came from the editor past its last mark, or Shift+Tab past its first.
    func enter(backward: Bool) {
        focus(on: backward ? model.controls.last : model.controls.first)
    }

    /// Tab or Shift+Tab on the bar: the next control, or back to the editor past either end.
    func move(backward: Bool) {
        let controls = model.controls
        guard let current = model.focus, let index = controls.firstIndex(of: current) else { return enter(backward: backward) }
        let next = index + (backward ? -1 : 1)
        if controls.indices.contains(next) { return focus(on: controls[next]) }
        focus(on: nil)
        if onLeave?(backward) != true { enter(backward: backward) }
    }

    /// Space on the focused control presses it, as a click would.
    func activate() {
        switch model.focus {
        case .tool(let tool)?: onTool?(tool)
        // A turn later, as the target's menu: opened inside the editor's keyDown, a popover took no keys.
        case .pins?: DispatchQueue.main.async { [weak self] in self?.showPins() }
        case .copy?: onDone?()
        case .target?: openTargetMenuFromKeys()
        case .action?:
            guard !model.sending, !model.nothingToReply, let destination = model.offer.destination else { return }
            onSend?(destination)
        case .message?, nil: break
        }
    }

    /// M or P in the editor: the keys go to the message field, when the bar has one.
    func focusMessage() {
        guard model.controls.contains(.message) else { return }
        if !model.message.isEmpty { caretToEnd() }
        focus(on: .message)
        if !panel.isKeyWindow { panel.caretToEnd = false }
    }

    /// A pick in the target's menu chooses whom to write to, so the message field takes the keys as a
    /// press on it gives them: a letter types, Return sends, and Esc hands the keys to the image.
    func typeAfterPick() {
        guard model.shown, model.controls.contains(.message) else { return }
        caretToEnd()
        focus(on: .message)
    }

    /// The caret goes after the field's words, where typing goes on from them. AppKit selects them all
    /// when the field takes the keys, and the first letter typed would replace them.
    private func caretToEnd() {
        if panel.isKeyWindow, let text = panel.firstResponder as? NSTextView {
            text.setSelectedRange(NSRange(location: (text.string as NSString).length, length: 0))
        } else {
            panel.caretToEnd = true
        }
    }

    /// The image opened and the hand has not reached it: the message field, when the bar has one,
    /// takes the keys, so typing goes to the agent. False when there is no field to take them, or
    /// the panel did not become key: the focus is let go then, so Tab, Space, Left and Right stay
    /// the image's, and a later offer tries again.
    func typeOnOpen() -> Bool {
        guard model.controls.contains(.message), model.focus == nil, !panel.isKeyWindow else { return false }
        if !model.message.isEmpty { caretToEnd() }
        focus(on: .message)
        guard panel.isKeyWindow else {
            Log.write("[annotate] message field did not get the keys")
            model.focus = nil
            panel.caretToEnd = false
            return false
        }
        model.tookKeysOnOpen = true
        return true
    }

    /// A press on the image takes the focus back from a control. The message field loses it when the
    /// panel gives up the keys.
    func clearFocus() {
        keepHeldTool()
        if model.focus != .message { model.focus = nil }
    }

    /// A key in the message field, before the field sees it: a tool letter typed first is held
    /// (`HeldToolLetter`), and Left or Right in a field still untouched pages. True when it was taken.
    func keyDown(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let character = HeldToolLetter.character(EditorCore.Key(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers),
                                                 EditorCore.Modifiers(eventFlags: event.modifierFlags.rawValue))
        let composing = (panel.firstResponder as? NSTextView)?.hasMarkedText() == true
        let untouched = model.tookKeysOnOpen && model.messageAsOpened && !composing
        if untouched, modifiers.isDisjoint(with: [.shift, .control, .option, .command]),
           let key = EditorCore.Key(keyCode: event.keyCode, characters: nil), let page = EditorCore.Page(key) {
            onPage?(page, event.isARepeat)
            return true
        }
        switch model.toolLetter.key(character, isRepeat: event.isARepeat, canHold: untouched, tool: model.tool) {
        case .hold(let tool):
            heldLetter = event
            onTool?(tool)
            return true
        case .type(let before):
            onTool?(before)
            if let held = heldLetter { panel.replay(held) }
            heldLetter = nil
            return false
        case .pass:
            heldLetter = nil
            return false
        case .swallow:
            return true
        }
    }

    func keepHeldTool() {
        model.toolLetter.keepTool()
        heldLetter = nil
    }

    func focus(on control: Model.Control?) {
        let typing = model.focus == .message && panel.isKeyWindow
        model.focus = control
        if control == .message {
            panel.takeKeys()
            model.askForMessage()
        } else if typing {
            onMessageEnd?()
        }
    }
}

extension AnnotatorToolbar.Model {
    /// The message field holds no words, so Cmd+C there copies the drawing (`FieldCommand`).
    var fieldEmpty: Bool { sentMessage == nil }
}
