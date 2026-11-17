import AppKit

/// Live ink's geometry and screen facts that read no state of its own.
extension LiveInk {
    /// The rect a mark draws in, its stroke, edge and shadows included.
    static func drawnExtent(of mark: Mark, sizes: LiveAnswerLayout.Sizes) -> CGRect? {
        if case .text = mark.geometry { return LiveAnswerLayout.noteBox(mark, sizes: sizes)?.insetBy(dx: -Mark.shadowSize, dy: -Mark.shadowSize) }
        return shapeExtent(of: mark, markStyle: Settings.shared.data.ui.markStyle)
    }

    /// The rect a shape draws in, its stroke, arrowhead, edge and shadows included, or nil for a note.
    static func shapeExtent(of mark: Mark, markStyle: MarkStyle) -> CGRect? {
        guard let shape = mark.shape(pointScale: 1, markStyle: markStyle) else { return nil }
        let ink = [shape.stroked, shape.filled].compactMap { $0?.boundingBoxOfPath }.reduce(CGRect.null) { $0.union($1) }
        let reach = shape.lineWidth / 2 + markStyle.edgeWidth + Mark.shadowSize
        return ink.insetBy(dx: -reach, dy: -reach)
    }

    /// The visible part of the screen `frame` is on, without the menu bar and the Dock, in global
    /// top-left points.
    static func visibleScreen(around frame: CGRect) -> CGRect? {
        guard let screen = StateReport.screen(at: CGPoint(x: frame.midX, y: frame.midY)) ?? NSScreen.main else { return nil }
        return StateReport.flipped(screen.visibleFrame)
    }

    /// An answer's marks after its reply, as steps: each pointing mark with the labels after it.
    static func steps(in marks: [Mark]) -> [[Mark]] {
        var groups: [[Mark]] = []
        for mark in marks {
            if mark.kind == .text, !groups.isEmpty { groups[groups.count - 1].append(mark) } else { groups.append([mark]) }
        }
        return groups
    }

    /// Where a click counts as taking a step: inside its loop, or on what its arrow points at, just
    /// past its head.
    static func stepTarget(of mark: Mark) -> CGRect {
        switch mark.geometry {
        case .arrow(let arrow):
            let length = max(1, hypot(arrow.end.x - arrow.start.x, arrow.end.y - arrow.start.y))
            let ahead = CGPoint(x: arrow.end.x + (arrow.end.x - arrow.start.x) / length * 24,
                                y: arrow.end.y + (arrow.end.y - arrow.start.y) / length * 24)
            return CGRect(origin: ahead, size: .zero).insetBy(dx: -32, dy: -32)
        default:
            return (mark.shapeExtent ?? .null).insetBy(dx: -6, dy: -6)
        }
    }

    /// The diagonal of the screen holding `point`, in points.
    static func screenDiagonal(at point: CGPoint) -> CGFloat {
        guard let screen = (StateReport.screen(at: point) ?? NSScreen.screens.first)?.frame else { return 0 }
        return hypot(screen.width, screen.height)
    }

    static func display(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
