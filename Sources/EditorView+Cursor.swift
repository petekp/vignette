import AppKit

extension EditorView {
    static func cursor(_ cursor: EditorCore.Cursor) -> NSCursor {
        switch cursor {
        case .arrow: return .arrow
        case .crosshair: return .crosshair
        case .iBeam: return .iBeam
        case .openHand: return .openHand
        case .closedHand: return .closedHand
        case .resize(let position):
            if #available(macOS 15.0, *) {
                let frame: NSCursor.FrameResizePosition
                switch position {
                case .topLeft: frame = .topLeft
                case .topRight: frame = .topRight
                case .bottomLeft: frame = .bottomLeft
                case .bottomRight: frame = .bottomRight
                case .top: frame = .top
                case .bottom: frame = .bottom
                case .left: frame = .left
                case .right: frame = .right
                }
                return .frameResize(position: frame, directions: .all)
            }
            // macOS 14 has no public diagonal resize cursor.
            switch position {
            case .left, .right: return .resizeLeftRight
            case .top, .bottom: return .resizeUpDown
            case .topLeft, .topRight, .bottomLeft, .bottomRight: return .crosshair
            }
        }
    }
}
