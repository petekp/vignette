import CoreGraphics

extension LiveAnswerLayout {
    /// A line this many times wider than tall is boxed rather than circled: an ellipse round it
    /// would cover the lines above and below.
    static let longLine: CGFloat = 8

    /// An ellipse padded round `target`, or a box round a long line.
    static func circle(around target: CGRect) -> Mark.Geometry {
        let height = max(target.height, 8)
        if target.width > height * longLine {
            return .rectangle(target.insetBy(dx: -max(4, height * 0.3), dy: -max(3, height * 0.25)))
        }
        // An ellipse through a rect's corners is √2 its size; a little less keeps it off the
        // neighbouring lines while the words stay inside.
        return .ellipse(target.insetBy(dx: -max(8, target.width * 0.18), dy: -max(6, height * 0.4)))
    }

    /// `circle(around:)`, ending `ringGap` short of each of `others` beside `target`: an ellipse
    /// narrowed to fit between them and made taller to keep `target` inside, or a box round `target`
    /// when no ellipse fits.
    static func circle(around target: CGRect, keepingOff others: [CGRect]) -> Mark.Geometry {
        let round = circle(around: target)
        guard case .ellipse(let frame) = round else { return round }
        let beside = others.filter { $0.minY < frame.maxY && $0.maxY > frame.minY && !$0.intersects(target) }
        let reach = beside.compactMap { other -> CGFloat? in
            if other.maxX <= target.minX { return target.midX - other.maxX - ringGap }
            if other.minX >= target.maxX { return other.minX - target.midX - ringGap }
            return nil
        }.min()
        guard let reach, reach < frame.width / 2 else { return round }
        let halfWidth = target.width / 2, halfHeight = target.height / 2
        let across = (halfWidth / reach) * (halfWidth / reach)
        guard reach > halfWidth, across < narrowedCorners - 0.05 else {
            return .rectangle(target.insetBy(dx: -max(0, min(4, reach - halfWidth)), dy: -max(3, halfHeight * 0.5)))
        }
        let halfTall = halfHeight / (narrowedCorners - across).squareRoot()
        return .ellipse(CGRect(x: target.midX - reach, y: target.midY - halfTall, width: reach * 2, height: halfTall * 2))
    }

    /// The gap a ring keeps from what it keeps off, in pt: room for its stroke and the edge round it.
    static let ringGap: CGFloat = 6
    /// How close a narrowed ring passes outside `target`'s corners, as a corner's (x/a)² + (y/b)²,
    /// where 1 is on the ring. Close, since a button's corners are rounded.
    private static let narrowedCorners: CGFloat = 0.95
}
