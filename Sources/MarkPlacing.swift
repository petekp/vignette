import AppKit

// MARK: - Placing a mark inside an image

extension Mark {
    /// This mark inside `image`: moved in where it fits, and cut to the image where it does not. A text
    /// without a wrap width near the right edge moves left (`TextLayout.leftEdge`), except with
    /// `keepingLines`, for a text the editor moved: the move already stopped where its lines keep their
    /// breaks, and moving it left then would make it jump. A text wider or taller than the image keeps
    /// its start showing. Nil when the mark has a number that is not finite, a rectangle or ellipse has
    /// no area, or an arrow's ends meet at an edge.
    func placed(in image: PixelSize, pointScale: CGFloat, style: TextStyle, keepingLines: Bool = false) -> Mark? {
        let bounds = image.bounds
        var placed = self
        switch geometry {
        case .rectangle(let frame), .ellipse(let frame):
            guard [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite) else { return nil }
            let x = Self.fit(frame.minX, frame.width, within: bounds.width)
            let y = Self.fit(frame.minY, frame.height, within: bounds.height)
            let inside = CGRect(x: x.origin, y: y.origin, width: x.length, height: y.length)
            // A paste that scales a very thin side down can leave it 0.
            guard inside.width > 0, inside.height > 0 else { return nil }
            placed.geometry = kind == .rectangle ? .rectangle(inside) : .ellipse(inside)
        case .arrow(var arrow) where !arrow.via.isEmpty:
            let points = [arrow.start] + arrow.via + [arrow.end]
            guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
            // Moved in whole when its curve fits, else each point stopped at the edge.
            let curve = arrow.exactBody.bounds
            let dx = Self.shiftInside(from: curve.minX, to: curve.maxX, within: bounds.width)
            let dy = Self.shiftInside(from: curve.minY, to: curve.maxY, within: bounds.height)
            func inside(_ point: CGPoint) -> CGPoint {
                CGPoint(x: dx.map { point.x + $0 } ?? min(max(point.x, 0), bounds.width),
                        y: dy.map { point.y + $0 } ?? min(max(point.y, 0), bounds.height))
            }
            arrow.start = inside(arrow.start)
            arrow.end = inside(arrow.end)
            arrow.via = arrow.via.map(inside)
            arrow.bend = 0
            guard arrow.start != arrow.end else { return nil }
            placed.geometry = .arrow(arrow)
        case .arrow(var arrow):
            guard [arrow.start.x, arrow.start.y, arrow.end.x, arrow.end.y, arrow.bend].allSatisfy(\.isFinite) else { return nil }
            (arrow.start.x, arrow.end.x) = Self.fitEnds(arrow.start.x, arrow.end.x, within: bounds.width)
            (arrow.start.y, arrow.end.y) = Self.fitEnds(arrow.start.y, arrow.end.y, within: bounds.height)
            guard arrow.start != arrow.end else { return nil }
            arrow.bend = arrow.largestBend(arrow.bend, inside: bounds)
            placed.geometry = .arrow(arrow)
        case .text(var text):
            let style = style.forMark(self)
            guard [text.origin.x, text.origin.y, text.size, text.wrap ?? 0].allSatisfy(\.isFinite),
                  (text.size * pointScale).isFinite else { return nil }
            if let wrap = text.wrap, wrap > bounds.width { text.wrap = bounds.width }
            if !keepingLines {
                text.origin.x = TextLayout.leftEdge(of: text, imageWidth: bounds.width, pointScale: pointScale, style: style)
            }
            func layoutBox() -> CGRect { TextLayout(text, imageWidth: bounds.width, pointScale: pointScale, style: style).box }
            var box = layoutBox()
            if box.minX < 0 || box.maxX > bounds.maxX {
                // A text without a wrap width wraps at the image's edge, so moving it left gives it
                // more room and a new box; at x 0 it has the most room the image can give.
                text.origin.x = box.minX < 0 ? 0 : max(0, bounds.width - box.width)
                box = layoutBox()
                if box.maxX > bounds.maxX {
                    text.origin.x = 0
                    box = layoutBox()
                }
            }
            guard [box.width, box.height].allSatisfy(\.isFinite) else { return nil }
            text.origin.y = box.height > bounds.height ? 0 : min(max(text.origin.y, 0), bounds.height - box.height)
            placed.geometry = .text(text)
        }
        return placed
    }

    /// A span moved inside `0...limit`, or cut to it when it is longer.
    private static func fit(_ origin: CGFloat, _ length: CGFloat, within limit: CGFloat) -> (origin: CGFloat, length: CGFloat) {
        guard length < limit else { return (0, limit) }
        return (min(max(origin, 0), limit - length), length)
    }

    /// Two ends on one axis moved together inside `0...limit` when the gap between them fits, else
    /// each stopped at the edge.
    private static func fitEnds(_ a: CGFloat, _ b: CGFloat, within limit: CGFloat) -> (CGFloat, CGFloat) {
        guard let shift = shiftInside(from: min(a, b), to: max(a, b), within: limit) else {
            return (min(max(a, 0), limit), min(max(b, 0), limit))
        }
        return (a + shift, b + shift)
    }

    /// How far a span from `low` to `high` moves to lie inside `0...limit`, or nil when it is longer.
    static func shiftInside(from low: CGFloat, to high: CGFloat, within limit: CGFloat) -> CGFloat? {
        guard high - low <= limit else { return nil }
        return low < 0 ? -low : (high > limit ? limit - high : 0)
    }
}
