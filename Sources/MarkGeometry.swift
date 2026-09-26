import AppKit
import CoreText

// The geometry the renderer, the colour pass and the editor share: an arrow's body and a text's
// lines, in px. Pure functions of a mark, so any of them can run off the main thread.

extension Mark.Arrow {
    /// A bend under this many pt is drawn straight.
    static let straightBelow: CGFloat = 8

    /// The middle of the line between the ends, moved `bend` px along the perpendicular. The
    /// perpendicular is the direction from `start` to `end` turned by (-dy, dx): in the image's
    /// coordinates, with y down, a positive bend bows the arrow to the right of its direction of travel.
    var bendPoint: CGPoint {
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 0 else { return start }
        return CGPoint(x: (start.x + end.x) / 2 - (end.y - start.y) / length * bend,
                       y: (start.y + end.y) / 2 + (end.x - start.x) / length * bend)
    }

    /// The body as drawn at `pointScale` px per pt: the curve through `via`, or straight when the bend
    /// is under `straightBelow` pt.
    func body(pointScale: CGFloat) -> ArrowBody {
        guard via.isEmpty else { return exactBody }
        return ArrowBody(start: start, end: end, bend: abs(bend) < Self.straightBelow * pointScale ? 0 : bend)
    }

    /// The body with its bend exactly as stored: the rect a mark covers and the rect kept inside the image.
    var exactBody: ArrowBody {
        via.isEmpty ? ArrowBody(start: start, end: end, bend: bend) : ArrowBody(through: [start] + via + [end])
    }

    /// The bend nearest `wanted` whose arc stays inside `bounds`: `wanted` when its arc fits, else the
    /// largest on the same side that does, and 0 when not even the straight line fits.
    func largestBend(_ wanted: CGFloat, inside bounds: CGRect) -> CGFloat {
        func fits(_ bend: CGFloat) -> Bool { bounds.contains(ArrowBody(start: start, end: end, bend: bend).bounds) }
        guard wanted.isFinite else { return 0 }
        if fits(wanted) { return wanted }
        guard fits(0) else { return 0 }
        // Arcs through the same two ends on one side never cross, so each bend's arc holds the
        // smaller ones' and fitting is monotonic. The bend point lies on the arc, so no arc that
        // fits bends further than the bounds' diagonal.
        var low: CGFloat = 0
        var high = min(abs(wanted), hypot(bounds.width, bounds.height))
        for _ in 0..<48 {
            let middle = (low + high) / 2
            if fits(copysign(middle, wanted)) { low = middle } else { high = middle }
        }
        return copysign(low, wanted)
    }
}

/// An arrow's body: the straight line between its ends, the circular arc through both ends and its
/// bend point, or a freehand arrow's curve through its ends and its `via` points.
struct ArrowBody {
    let start: CGPoint
    let end: CGPoint
    /// Nil for a straight body or a curve.
    let arc: Arc?
    /// Nil for a straight body or an arc.
    let curve: Curve?

    struct Arc {
        let center: CGPoint
        let radius: CGFloat
        /// The angle of `start` seen from the centre, in radians.
        let startAngle: CGFloat
        /// The angle the arc turns through from `start` to `end`: positive when the angle grows.
        let sweep: CGFloat
    }

    /// The exact arc, straight only when `bend` is 0 or the ends meet. The renderer, the colour pass
    /// and the editor get a body through `Mark.Arrow.body(pointScale:)`, which applies the 8 pt rule.
    init(start: CGPoint, end: CGPoint, bend: CGFloat) {
        self.start = start
        self.end = end
        curve = nil
        let half = hypot(end.x - start.x, end.y - start.y) / 2
        guard bend != 0, half > 0, bend.isFinite else { arc = nil; return }
        // The unit perpendicular, as in `Mark.Arrow.bendPoint`.
        let normal = CGPoint(x: -(end.y - start.y) / (2 * half), y: (end.x - start.x) / (2 * half))
        // The centre lies on the perpendicular through the middle, `offset` from it. Written without
        // bend squared, which overflows long before the bend itself does.
        let offset = bend / 2 - half * half / (2 * bend)
        let center = CGPoint(x: (start.x + end.x) / 2 + normal.x * offset, y: (start.y + end.y) / 2 + normal.y * offset)
        arc = Arc(center: center, radius: abs(bend) / 2 + half * half / (2 * abs(bend)),
                  startAngle: atan2(start.y - center.y, start.x - center.x),
                  sweep: -copysign(4 * atan(abs(bend) / half), bend))
    }

    /// The curve through `knots`, from the first to the last. At least two knots.
    init(through knots: [CGPoint]) {
        start = knots.first ?? .zero
        end = knots.last ?? .zero
        arc = nil
        curve = Curve(through: knots)
    }

    /// The point `fraction` of the way along the body, from `start` at 0 to `end` at 1.
    func point(at fraction: CGFloat) -> CGPoint {
        let t = min(max(fraction, 0), 1)
        if let curve { return curve.point(at: t * curve.length) }
        guard let arc else { return CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t) }
        return arc.point(at: arc.startAngle + arc.sweep * t)
    }

    /// The unit normal at `fraction` of the way along: the radius on an arc, and the direction of
    /// travel turned by (-dy, dx) on a line or a curve.
    func normal(at fraction: CGFloat) -> CGVector {
        if let arc, arc.radius > 0 {
            let point = point(at: fraction)
            return CGVector(dx: (point.x - arc.center.x) / arc.radius, dy: (point.y - arc.center.y) / arc.radius)
        }
        let travel = tangent(at: fraction)
        return CGVector(dx: -travel.dy, dy: travel.dx)
    }

    /// The unit direction of travel, from `start` towards `end`, at `fraction` of the way along.
    /// Zero for a body with no length.
    func tangent(at fraction: CGFloat) -> CGVector {
        if let arc, arc.radius > 0 {
            // The radius turned a quarter, towards the way the arc sweeps.
            let radial = normal(at: fraction), turn: CGFloat = arc.sweep < 0 ? -1 : 1
            return CGVector(dx: -radial.dy * turn, dy: radial.dx * turn)
        }
        let (a, b) = curve == nil ? (start, end) : (point(at: fraction - 0.01), point(at: fraction + 0.01))
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length > 0 else { return CGVector(dx: 0, dy: 0) }
        return CGVector(dx: (b.x - a.x) / length, dy: (b.y - a.y) / length)
    }

    /// The distance from `point` to the nearest point of the body.
    func distance(to point: CGPoint) -> CGFloat {
        if let curve {
            return zip(curve.samples, curve.samples.dropFirst()).reduce(hypot(point.x - start.x, point.y - start.y)) {
                min($0, Self.distance(from: point, toSegment: $1.0, $1.1))
            }
        }
        guard let arc else { return Self.distance(from: point, toSegment: start, end) }
        let fromCenter = hypot(point.x - arc.center.x, point.y - arc.center.y)
        if fromCenter > 0, arc.covers(atan2(point.y - arc.center.y, point.x - arc.center.x)) {
            return abs(fromCenter - arc.radius)
        }
        return min(hypot(point.x - start.x, point.y - start.y), hypot(point.x - end.x, point.y - end.y))
    }

    static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared, 0), 1)
        return hypot(point.x - (a.x + dx * t), point.y - (a.y + dy * t))
    }

    /// The smallest rect holding the whole body.
    var bounds: CGRect {
        var points = curve?.samples ?? [start, end]
        if let arc {
            // The arc's leftmost, topmost, rightmost and bottommost points, where it reaches them.
            for quarter in 0..<4 {
                let angle = CGFloat(quarter) * .pi / 2
                if arc.covers(angle) { points.append(arc.point(at: angle)) }
            }
        }
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}

extension ArrowBody {
    /// A freehand arrow's body: the centripetal Catmull-Rom spline through its knots, as one cubic
    /// Bézier segment between each pair, and the same curve sampled at most `sampleSpacing` px apart,
    /// which answers lengths, distances and points along it. Centripetal, because it never loops or
    /// makes a cusp between two knots, however unevenly a hand spaced them.
    struct Curve {
        /// Each segment's start, its two control points, and its end.
        let segments: [[CGPoint]]
        let samples: [CGPoint]
        /// The curve's length from its start to each sample.
        let lengths: [CGFloat]
        /// Which segment each sample lies on, and its parameter there.
        let places: [(segment: Int, t: CGFloat)]

        static let sampleSpacing: CGFloat = 2

        var length: CGFloat { lengths.last ?? 0 }

        init(through knots: [CGPoint]) {
            let count = knots.count
            // Past each end, the knot mirrored through it, so the curve leaves and arrives along its
            // first and last chords.
            func knot(_ index: Int) -> CGPoint {
                guard count > 1 else { return knots.first ?? .zero }
                if index < 0 { return CGPoint(x: 2 * knots[0].x - knots[1].x, y: 2 * knots[0].y - knots[1].y) }
                if index >= count {
                    return CGPoint(x: 2 * knots[count - 1].x - knots[count - 2].x, y: 2 * knots[count - 1].y - knots[count - 2].y)
                }
                return knots[index]
            }
            func control(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ near: CGFloat, _ far: CGFloat) -> CGPoint {
                // Yuksel, Schaefer and Keyser's conversion, with `near` and `far` the square roots of
                // the chords beside and across the segment.
                guard near > 1e-9 else { return p1 }
                let a = near * near, b = far * far, denominator = 3 * near * (near + far)
                let c = 2 * a + 3 * near * far + b
                return CGPoint(x: (a * p2.x - b * p0.x + c * p1.x) / denominator, y: (a * p2.y - b * p0.y + c * p1.y) / denominator)
            }
            func root(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y).squareRoot() }
            segments = count < 2 ? [] : (0..<count - 1).map { index in
                let p0 = knot(index - 1), p1 = knot(index), p2 = knot(index + 1), p3 = knot(index + 2)
                let d1 = root(p0, p1), d2 = root(p1, p2), d3 = root(p2, p3)
                return [p1, control(p0, p1, p2, d1, d2), control(p3, p2, p1, d3, d2), p2]
            }
            var samples = [knots.first ?? .zero], lengths: [CGFloat] = [0], places: [(segment: Int, t: CGFloat)] = [(0, 0)]
            for (index, segment) in segments.enumerated() {
                let polygon = zip(segment, segment.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
                let steps = max(8, Int((polygon / Self.sampleSpacing).rounded(.up)))
                for step in 1...steps {
                    let t = CGFloat(step) / CGFloat(steps)
                    let point = Self.point(on: segment, at: t)
                    lengths.append(lengths[lengths.count - 1] + hypot(point.x - samples[samples.count - 1].x, point.y - samples[samples.count - 1].y))
                    samples.append(point)
                    places.append((index, t))
                }
            }
            self.samples = samples
            self.lengths = lengths
            self.places = places
        }

        static func point(on segment: [CGPoint], at t: CGFloat) -> CGPoint {
            let u = 1 - t
            let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
            return CGPoint(x: a * segment[0].x + b * segment[1].x + c * segment[2].x + d * segment[3].x,
                           y: a * segment[0].y + b * segment[1].y + c * segment[2].y + d * segment[3].y)
        }

        /// The sample at or past `distance` along the curve, and how far toward it from the one before.
        func position(at distance: CGFloat) -> (index: Int, fraction: CGFloat) {
            guard samples.count > 1 else { return (0, 0) }
            var low = 1, high = lengths.count - 1
            while low < high {
                let middle = (low + high) / 2
                if lengths[middle] < distance { low = middle + 1 } else { high = middle }
            }
            let span = lengths[low] - lengths[low - 1]
            return (low, span > 0 ? min(max((distance - lengths[low - 1]) / span, 0), 1) : 1)
        }

        func point(at distance: CGFloat) -> CGPoint {
            let (index, fraction) = position(at: distance)
            guard index > 0 else { return samples.first ?? .zero }
            let a = samples[index - 1], b = samples[index]
            return CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
        }

        /// The segment and the parameter `distance` along the curve.
        func place(at distance: CGFloat) -> (segment: Int, t: CGFloat) {
            let (index, fraction) = position(at: distance)
            guard index > 0 else { return (0, 0) }
            var before = places[index - 1]
            let after = places[index]
            // The first sample of a segment follows the last of the one before, at its t of 1.
            if before.segment != after.segment { before = (after.segment, 0) }
            return (after.segment, before.t + (after.t - before.t) * fraction)
        }
    }
}

extension ArrowBody.Arc {
    func point(at angle: CGFloat) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }

    /// Whether the arc passes through `angle`, seen from the centre.
    func covers(_ angle: CGFloat) -> Bool {
        let turned = (angle - startAngle) * (sweep < 0 ? -1 : 1)
        let wrapped = turned - 2 * .pi * (turned / (2 * .pi)).rounded(.down)
        return wrapped <= abs(sweep)
    }
}

/// How a text mark's words are set: SF Pro Rounded at a weight, with lines `lineHeight` times the
/// font size apart. Both are tuned live, so every layout takes the style it is given. Make a style on
/// the main thread, where AppKit gives the rounded face; after that it lays text out on any thread,
/// since a size becomes a font through Core Text alone.
struct TextStyle: Equatable, @unchecked Sendable {
    let weight: NSFont.Weight
    var lineHeight: CGFloat
    /// Whether this is an agent's style (`forAgent`), set in SF Mono rather than SF Pro Rounded.
    let monospaced: Bool
    /// The system font with the rounded or the monospaced design, at `weight`. Immutable, and Core
    /// Text's descriptors are safe to share between threads.
    private let face: CTFontDescriptor

    /// The tweaks' defaults.
    static let standard = UITweaks().textStyle

    init(weight: NSFont.Weight, lineHeight: CGFloat, monospaced: Bool = false) {
        self.weight = weight
        self.lineHeight = lineHeight
        self.monospaced = monospaced
        let system = NSFont.systemFont(ofSize: 0, weight: weight).fontDescriptor
        face = (system.withDesign(monospaced ? .monospaced : .rounded) ?? system) as CTFontDescriptor
    }

    /// The style a mark's text is set in: an agent's in SF Mono, so its words read as the agent's at
    /// a glance, and a person's in this one. Every place that lays out or draws a text asks this, so
    /// the editor, the cards, the flights and the rendering agree.
    func forAgent(_ agent: Bool) -> TextStyle {
        agent == monospaced ? self : TextStyle(weight: weight, lineHeight: lineHeight, monospaced: agent)
    }

    /// The face at `size`.
    func font(size: CGFloat) -> CTFont { CTFontCreateWithFontDescriptor(face, size, nil) }

    static func == (a: TextStyle, b: TextStyle) -> Bool {
        a.weight == b.weight && a.lineHeight == b.lineHeight && a.monospaced == b.monospaced
    }
}

/// A text mark set in lines, in px. Core Text, so a rendering can lay text out off the main thread.
/// Its line breaks are the ones an `NSTextView` makes with the same font, a text container `lineWidth`
/// wide, and no line fragment padding.
struct TextLayout {
    /// The room a text keeps from the image's right edge, as a fraction of the image's width.
    static let margin: CGFloat = 0.02

    struct Line {
        /// Starts at the mark's left edge, as wide as its words without the spaces after them, and
        /// `lineHeight` tall.
        let rect: CGRect
        /// Where the glyphs stand: the font's ascent and descent centred in the line's height.
        let baseline: CGFloat
        let ctLine: CTLine
    }

    /// The font, at the text's size in px.
    let font: CTFont
    let lineHeight: CGFloat
    let lines: [Line]
    /// From the mark's origin: as wide as its wrap width or its widest line, whichever is wider, and
    /// as tall as its lines. A text that ends in a line break, or holds nothing, has an empty last line.
    let box: CGRect

    /// The least room a text without a wrap width wraps in, as a fraction of the image's width. One
    /// that starts with less to its right moves left instead of wrapping into a narrow column.
    static let minimumRoom: CGFloat = 0.15

    /// The widest a line of `text` may be: its wrap width, or the room from its left edge to the
    /// image's right edge less the margin.
    static func lineWidth(of text: Mark.Text, imageWidth: CGFloat) -> CGFloat {
        text.wrap ?? imageWidth * (1 - margin) - text.origin.x
    }

    /// The x a text should start at. A text without a wrap width that has less than `minimumRoom`
    /// to its right moves left until its widest line, broken only at its hard line breaks, fits
    /// before the margin, and no further left than 0, where a text wider than the image keeps its
    /// start showing. Any other text keeps its x.
    static func leftEdge(of text: Mark.Text, imageWidth: CGFloat, pointScale: CGFloat, style: TextStyle) -> CGFloat {
        let right = imageWidth * (1 - margin)
        guard text.wrap == nil, right - text.origin.x < imageWidth * minimumRoom else { return text.origin.x }
        var unwrapped = text
        unwrapped.wrap = .greatestFiniteMagnitude
        let widest = TextLayout(unwrapped, imageWidth: imageWidth, pointScale: pointScale, style: style).lines.map(\.rect.width).max() ?? 0
        return max(0, min(text.origin.x, right - widest))
    }

    init(_ text: Mark.Text, imageWidth: CGFloat, pointScale: CGFloat, style: TextStyle) {
        let fontSize = text.size * pointScale
        let font = style.font(size: fontSize)
        let lineHeight = fontSize * style.lineHeight
        let baseline = (lineHeight - (CTFontGetAscent(font) + CTFontGetDescent(font))) / 2 + CTFontGetAscent(font)
        // An NSTextView keeps a line that runs up to 0.001 px past its container, and Core Text breaks
        // one 0.0002 px short of the width; this allowance puts both breaks in the same place, so a
        // text does not re-wrap when typing ends.
        let width = Double(Self.lineWidth(of: text, imageWidth: imageWidth)) + 0.0008
        let string = text.text as NSString
        let typesetter = CTTypesetterCreateWithAttributedString(NSAttributedString(string: text.text, attributes: [.font: font]))
        var lines: [Line] = []
        func add(_ line: CTLine) {
            let top = text.origin.y + CGFloat(lines.count) * lineHeight
            let words = CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line)
            lines.append(Line(rect: CGRect(x: text.origin.x, y: top, width: max(0, words), height: lineHeight),
                              baseline: top + baseline, ctLine: line))
        }
        var start = 0
        while start < string.length {
            // At least one character a line, so a width narrower than one character still ends.
            let count = max(1, CTTypesetterSuggestLineBreak(typesetter, start, width))
            add(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
            start += count
        }
        if text.text.isEmpty || text.text.last?.isNewline == true {
            add(CTLineCreateWithAttributedString(NSAttributedString(string: "", attributes: [.font: font])))
        }
        self.font = font
        self.lineHeight = lineHeight
        self.lines = lines
        box = CGRect(x: text.origin.x, y: text.origin.y, width: max(text.wrap ?? 0, lines.map(\.rect.width).max() ?? 0),
                     height: CGFloat(lines.count) * lineHeight)
    }
}
