import AppKit

extension EditorView {
    static func cursor(_ cursor: EditorCore.Cursor) -> NSCursor {
        switch cursor {
        case .arrow: return .arrow
        case .crosshair: return .crosshair
        case .iBeam: return .iBeam
        case .openHand: return .openHand
        case .closedHand: return .closedHand
        case .comment(let color): return commentCursor(color)
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

    private static var commentCursors: [String: NSCursor] = [:]

    /// The crosshair with its hot spot at the cross, and up and to its right a pin 10 pt across, so
    /// the pointer says a click places a pin.
    private static func commentCursor(_ color: SRGB) -> NSCursor {
        if let cursor = commentCursors[color.hex] { return cursor }
        let spot = CGPoint(x: 8, y: 16)
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let cross = CGMutablePath()
            cross.move(to: CGPoint(x: spot.x - 7, y: spot.y)); cross.addLine(to: CGPoint(x: spot.x + 7, y: spot.y))
            cross.move(to: CGPoint(x: spot.x, y: spot.y - 7)); cross.addLine(to: CGPoint(x: spot.x, y: spot.y + 7))
            for (width, gray) in [(CGFloat(3), CGFloat(1)), (1, 0)] {
                ctx.addPath(cross)
                ctx.setLineWidth(width)
                ctx.setStrokeColor(gray: gray, alpha: 1)
                ctx.strokePath()
            }
            let pin = PinTeardrop(number: 0, agent: false, tip: CGPoint(x: spot.x + 4, y: spot.y - 4), orientation: .upRight,
                                  side: 10, style: MarkStyle.standard.pin).body
            ctx.setLineJoin(.round)
            for (width, gray, alpha) in [(CGFloat(3.5), CGFloat(0), CGFloat(0.3)), (2, 1, 1)] {
                ctx.addPath(pin)
                ctx.setLineWidth(width)
                ctx.setStrokeColor(gray: gray, alpha: alpha)
                ctx.strokePath()
            }
            ctx.addPath(pin)
            ctx.setFillColor(color.cgColor)
            ctx.fillPath()
            return true
        }
        let cursor = NSCursor(image: image, hotSpot: NSPoint(x: spot.x, y: spot.y))
        commentCursors[color.hex] = cursor
        return cursor
    }
}
