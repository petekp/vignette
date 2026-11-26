import AppKit

extension ThumbnailController {
    // MARK: Selection

    func toggle(_ card: Card) {
        model.toggleSelection(of: card.id)
        model.focused = card.id
        relayout()
        revealFocused()
    }

    /// A card that was just interacted with while partly out of view scrolls into it.
    func revealFocused() {
        guard let index = model.cards.firstIndex(where: { $0.id == model.focused }) else { return }
        scrollToReveal(index)
    }

    func run(_ action: ShotAction, on cards: [Card]) {
        guard let actions, action.applies(to: cards.map(\.shot)) else { return }
        action.run(cards.map(\.shot), actions)
    }

    /// Cards a shortcut acts on: the selection, else the focused card. The focus is the newest card
    /// while the stack has keys and follows the pointer, so the card under the mouse is the target.
    private func targetCards() -> [Card] {
        if model.inSelectionMode { return model.selectedCards() }
        if let id = model.focused, let card = model.cards.first(where: { $0.id == id }) { return [card] }
        return model.cards.first.map { [$0] } ?? []
    }

    func handleKey(_ event: NSEvent) -> Bool {
        guard keys.isKeyed else { return false }
        let mods = event.modifierFlags.intersection([.command, .option, .shift, .control])
        // Shift shortcuts arrive uppercase; action keys are declared lowercase.
        let chars = (event.charactersIgnoringModifiers ?? "").lowercased()
        // Virtual key codes: 53 esc, 126 up, 125 down, 36 return, 76 enter, 51 delete, 117 fwd delete.
        let code = event.keyCode
        let isReturn = code == 36 || code == 76
        let isDelete = code == 51 || code == 117

        // Esc backs out one level at a time: the selection, then the stack.
        if code == 53 {
            if model.inSelectionMode {
                model.clearSelection()
                relayout()
            } else {
                keys.send(.dismiss(.esc))
            }
            return true
        }
        if code == 126 || code == 125 {
            moveFocus(toward: code == 125 ? -1 : 1, extend: mods.contains(.shift))
            return true
        }
        if chars == " " {
            if let id = model.focused, let card = model.cards.first(where: { $0.id == id }) { toggle(card) }
            return true
        }
        if chars == "a" && mods == [.command] {
            // Nobody picked an order, so the column's own is the answer: oldest first, top to bottom.
            model.setSelection(model.cards.reversed().map(\.id))
            relayout()
            return true
        }
        if chars == "a" && mods == [.command, .shift] {
            model.clearSelection()
            relayout()
            return true
        }
        if chars == "z" && (mods == [.command] || mods == [.command, .shift]) {
            timeline.walk(redo: mods.contains(.shift), repeated: event.isARepeat)
            return true
        }
        let targets = targetCards()
        let match = Config.action(for: { key in
            let pressed = (key.character == "\u{7f}" && isDelete) || (key.character == "\r" && isReturn)
                || (key.character != "\u{7f}" && key.character != "\r" && key.character == chars)
            return pressed && mods == key.modifiers
        }, on: targets.map(\.shot))
        switch match {
        case .run(let action): run(action, on: targets); return true
        // The row for it is greyed out in the strip; the key says so the way a disabled menu
        // item's shortcut does, rather than nothing happening.
        case .unavailable: NSSound.beep(); return true
        case .none: return false
        }
    }

    /// Down arrow moves toward the newest card (index 0), which sits at the bottom. Shift extends
    /// the selection in the direction of travel; turning back takes off the card added last.
    func moveFocus(toward delta: Int, extend: Bool) {
        guard !model.cards.isEmpty, !waitsForOlder(toward: delta, extend: extend) else { return }
        let current = model.cards.firstIndex { $0.id == model.focused }
        let next: Int
        if let current { next = max(0, min(model.cards.count - 1, current + delta)) } else { next = delta < 0 ? model.cards.count - 1 : 0 }
        if extend {
            let here = current.map { model.cards[$0].id }
            if let here, model.selection.last == here, model.selection.dropLast().last == model.cards[next].id {
                model.deselect([here])
            } else {
                model.select([here, model.cards[next].id].compactMap { $0 })
            }
            relayout()
        }
        model.focused = model.cards[next].id
        scrollToReveal(next)
    }
}
