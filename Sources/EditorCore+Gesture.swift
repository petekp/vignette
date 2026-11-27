import CoreGraphics
import Foundation

extension EditorCore {
    /// A press and what it has become.
    struct Gesture {
        let press: Press
        var phase: Phase
        /// The latest pointer location, so a modifier change with no move updates the gesture.
        var pointer: CGPoint
        /// Where the pointer has been while the Arrow tool draws, after the press, inside the image.
        var stroke: [CGPoint] = []
    }

    struct Press {
        let location: CGPoint
        let time: TimeInterval
        let target: PressTarget
        /// The selection before the press changed it, which Esc puts back.
        let selectionBefore: Set<Mark.ID>
    }

    enum PressTarget: Equatable {
        /// Empty space: a drag does what the tool does.
        case empty
        /// Empty space inside the frame of several selected marks, in Select: a drag moves them and
        /// a click clears them.
        case frame
        case mark(Mark.ID, click: Click)
        case handle(Mark.ID, HandlePosition, click: Click)
        case dot(Mark.ID, DotKind)
        case pin(Pin.ID, click: Click)
        case cluster([Pin.ID])
    }

    /// What a press on a mark or its handle does when the button comes up without a drag.
    enum Click: Equatable { case nothing, deselect, selectOnly, type(Caret), open }

    enum Phase: Equatable {
        /// Not yet past the drag distance.
        case pressed
        /// A rectangle or an arrow being drawn.
        case drawing(Mark.ID)
        /// A Comment tool drag choosing a new pin's area.
        case placing(Pin.ID)
        /// A Text tool drag setting a new text's wrap width.
        case wrapping
        /// With Shift, the brush adds to the selection from before the press.
        case brushing
        case moving(originals: [Mark.ID], copies: [Mark.ID])
        case resizing(Mark.ID, HandlePosition)
        case draggingEnd(Mark.ID, DotKind)
        case bending(Mark.ID)
    }

    /// `point` under the turn and scale about `pivot` that takes `from` to `to`.
    static func turned(_ point: CGPoint, about pivot: CGPoint, from: CGPoint, to: CGPoint) -> CGPoint {
        let a = CGPoint(x: from.x - pivot.x, y: from.y - pivot.y), b = CGPoint(x: to.x - pivot.x, y: to.y - pivot.y)
        let squared = a.x * a.x + a.y * a.y
        guard squared > 0 else { return point }
        // b / a as complex numbers: the rotation and scale in one.
        let cos = (b.x * a.x + b.y * a.y) / squared, sin = (b.y * a.x - b.x * a.y) / squared
        let p = CGPoint(x: point.x - pivot.x, y: point.y - pivot.y)
        return CGPoint(x: pivot.x + p.x * cos - p.y * sin, y: pivot.y + p.x * sin + p.y * cos)
    }
}
