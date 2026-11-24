import CoreGraphics
import Foundation

extension EditorCore {
    /// The `editor` section of `[state]`: the tool, each mark's type, frame in px and whether an agent
    /// drew it, the selection as indexes into the marks, whether a text is being typed, the drawing's
    /// point and mark scales, and the undo and redo depth and what Undo and Redo would take. Never a
    /// text's words.
    var inspection: [String: Any] {
        let geometry = self.geometry
        return [
            "open": isOpen,
            "tool": tool.rawValue,
            "marks": drawing.marks.map { mark -> [String: Any] in
                let frame = geometry.extent(of: mark)
                return ["type": mark.kind.rawValue, "frame": [frame.minX, frame.minY, frame.width, frame.height].map { Int($0.rounded()) },
                        "agent": mark.agent]
            },
            "selection": drawing.marks.indices.filter { selection.contains(drawing.marks[$0].id) },
            "typing": typing != nil,
            "pointScale": drawing.pointScale,
            "markScale": drawing.markScale,
            "undo": undoSteps.count,
            "redo": redoSteps.count,
            "undoTitle": undoTitle,
            "redoTitle": redoTitle,
        ]
    }
}
