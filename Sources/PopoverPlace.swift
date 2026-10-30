import AppKit

/// Where a live answer's reply hangs as a popover, in the coordinates of the marks: the rect its
/// arrow points at, the edge of that rect it hangs from, and where its body is expected. AppKit
/// places the popover itself, centred on its arrow, so `body` is the layout's estimate, which the
/// answer's other marks keep clear of (docs/live-ink-look-2026-10-07.md, plan step 6).
struct PopoverPlace: Equatable {
    enum Edge: CaseIterable {
        case below, above, right, left

        /// AppKit's edge in a view's coordinates: a flipped view's bottom is its max y.
        func rectEdge(flipped: Bool = false) -> NSRectEdge {
            switch self {
            case .below: flipped ? .maxY : .minY
            case .above: flipped ? .minY : .maxY
            case .right: .maxX
            case .left: .minX
            }
        }
    }

    /// The mark it hangs from, which it follows on its window, or nil for the person's ink.
    var anchor: Mark.ID?
    var at: CGRect
    var edge: Edge
    var body: CGRect
    /// Room kept at the foot of its body for the answer's buttons, in points: as wide as their row,
    /// which the body is never narrower than, and as tall.
    var foot: CGSize
    /// The visible screen it hangs on, in global top-left points, which AppKit keeps its window
    /// inside. Nil leaves the body centred on its arrow.
    var screen: CGRect? = nil

    /// How far a popover's window reaches past its body on every side, holding the arrow and the
    /// shadow (measured on macOS 15).
    static let windowMargin: CGFloat = 13

    func offsetBy(dx: CGFloat, dy: CGFloat) -> PopoverPlace {
        var moved = self
        moved.at = at.offsetBy(dx: dx, dy: dy)
        moved.body = body.offsetBy(dx: dx, dy: dy)
        return moved
    }

    /// A body of `size` hung from `at` on `edge`, centred on it, as AppKit centres a popover on its
    /// arrow, then slid along that edge, as AppKit slides it, until its window is on `screen`.
    static func body(_ size: CGSize, hungFrom at: CGRect, edge: Edge, on screen: CGRect?) -> CGRect {
        let gap = ReplyContent.arrowLength
        let origin: CGPoint
        switch edge {
        case .below: origin = CGPoint(x: at.midX - size.width / 2, y: at.maxY + gap)
        case .above: origin = CGPoint(x: at.midX - size.width / 2, y: at.minY - gap - size.height)
        case .right: origin = CGPoint(x: at.maxX + gap, y: at.midY - size.height / 2)
        case .left: origin = CGPoint(x: at.minX - gap - size.width, y: at.midY - size.height / 2)
        }
        var body = CGRect(origin: origin, size: size)
        guard let room = screen?.insetBy(dx: windowMargin, dy: windowMargin) else { return body }
        switch edge {
        case .below, .above: body.origin.x = min(max(body.minX, room.minX), room.maxX - size.width)
        case .right, .left: body.origin.y = min(max(body.minY, room.minY), room.maxY - size.height)
        }
        return body
    }

    /// A body of `size` hung from `at` on `edge`, slid along that edge to stay in `room`, and the part
    /// of `at` its arrow then points at. AppKit slides a popover only onto the screen, and otherwise
    /// centres it on its arrow, so the body slides by moving the arrow along `at`, as far as `at` reaches.
    static func hung(_ size: CGSize, from at: CGRect, edge: Edge, inside room: CGRect) -> (at: CGRect, body: CGRect) {
        func clamped(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat { low <= high ? min(max(value, low), high) : value }
        var arrow = at
        switch edge {
        case .below, .above:
            let middle = clamped(clamped(at.midX, room.minX + size.width / 2, room.maxX - size.width / 2), at.minX, at.maxX)
            arrow = CGRect(x: middle - 0.5, y: at.minY, width: 1, height: at.height)
        case .right, .left:
            let middle = clamped(clamped(at.midY, room.minY + size.height / 2, room.maxY - size.height / 2), at.minY, at.maxY)
            arrow = CGRect(x: at.minX, y: middle - 0.5, width: at.width, height: 1)
        }
        return (arrow, body(size, hungFrom: arrow, edge: edge, on: nil))
    }
}
