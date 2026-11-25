import AppKit

extension EditorView {
    /// While a note settles, its selection follows the tag as drawn rather than the core's layout:
    /// each edge of the outline and its handles is moved as far as the tag's edge on that side still
    /// has to go.
    func settlingOverlay(_ overlay: EditorCore.Overlay) -> EditorCore.Overlay {
        guard settling != nil, let field = lingering, let now = field.settlingBox, overlay.selected == [field.id],
              let mark = core.mark(field.id), case .text(let text) = mark.geometry else { return overlay }
        let end = core.geometry.layout(text, of: mark).box
        guard end.width > 0, end.height > 0 else { return overlay }
        func shift(_ value: CGFloat, from low: CGFloat, _ span: CGFloat, by a: CGFloat, _ b: CGFloat) -> CGFloat {
            let t = min(max((value - low) / span, 0), 1)
            return value + a + (b - a) * t
        }
        func move(_ rect: CGRect) -> CGRect {
            let left = shift(rect.minX, from: end.minX, end.width, by: now.minX - end.minX, now.maxX - end.maxX)
            let right = shift(rect.maxX, from: end.minX, end.width, by: now.minX - end.minX, now.maxX - end.maxX)
            let top = shift(rect.minY, from: end.minY, end.height, by: now.minY - end.minY, now.maxY - end.maxY)
            let bottom = shift(rect.maxY, from: end.minY, end.height, by: now.minY - end.minY, now.maxY - end.maxY)
            return CGRect(x: left, y: top, width: right - left, height: bottom - top)
        }
        var moved = overlay
        // The frame is the text's own outline, so it is drawn once, where the tag is.
        moved.selected = []
        if moved.hovered == field.id { moved.hovered = nil }
        moved.frame = overlay.frame.map(move)
        moved.handles = overlay.handles.map { .init(mark: $0.mark, position: $0.position, square: $0.square.map(move), hitArea: move($0.hitArea)) }
        return moved
    }
}
