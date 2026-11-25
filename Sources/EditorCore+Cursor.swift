import CoreGraphics

/// The cursor says what a press will do.
extension EditorCore {
    /// The box of the text being typed.
    var typingBox: CGRect? {
        guard let typing, let mark = mark(typing.id), case .text(let text) = mark.geometry else { return nil }
        return geometry.layout(text, of: mark).box
    }

    var cursor: Cursor {
        if let gesture {
            switch gesture.phase {
            case .pressed:
                guard case .mark(_, let click) = gesture.press.target else { return cursor(over: hover) }
                if case .type = click { return .iBeam }
                return .arrow
            case .drawing, .wrapping, .placing: return .crosshair
            case .brushing: return .arrow
            case .moving, .draggingEnd, .bending: return .closedHand
            case .resizing(_, let position): return .resize(position)
            }
        }
        if let pointer, let box = typingBox, box.encloses(pointer) { return .iBeam }
        return cursor(over: hover)
    }

    private func cursor(over target: Target?) -> Cursor {
        switch target {
        case .handle(_, let position)?: return .resize(position)
        case .dot?: return .openHand
        case .mark(let id)?: return clickTypes(in: id) ? .iBeam : .arrow
        case .pin?, .cluster?: return .arrow
        case nil: return tool == .select ? .arrow : .crosshair
        }
    }

    /// A click on this mark starts typing in it: any text with the Text tool or while another text is
    /// typed, and the lone selected text with every tool, unless Shift or Command makes the click
    /// change the selection or Control makes it a right-click.
    private func clickTypes(in id: Mark.ID) -> Bool {
        guard mark(id)?.kind == .text else { return false }
        if tool == .text || typing != nil { return true }
        return selection == [id] && modifiers.isDisjoint(with: [.shift, .command, .control])
    }
}
