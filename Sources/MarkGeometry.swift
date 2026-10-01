import AppKit
import CoreText

// The geometry the renderer and the editor share: an arrow's body and a text's
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

    /// The exact arc, straight only when `bend` is 0 or the ends meet. The renderer and the editor get
    /// a body through `Mark.Arrow.body(pointScale:)`, which applies the 8 pt rule.
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

/// How a text mark is set, from settings.json's `ui` (`UITweaks.textStyle`): a person's font and an
/// agent's, each at a weight, with lines `lineHeight` times the font size apart, the tag's padding
/// and width cap, and where an agent's badge sits. Sizes other than `agentSize` are multiples of the
/// note's font size. Every layout takes the style it is given, so a change reaches every note. Make a
/// style on the main thread, where AppKit gives the system font's designs; after that it lays text out
/// on any thread, since a size becomes a font through Core Text alone.
struct TextStyle: Hashable, @unchecked Sendable {
    /// A font as settings.json names it: `rounded`, `monospaced`, `serif` or `default`, the system
    /// font's designs, or an installed font family.
    let personFont: String, agentFont: String
    let personWeight: NSFont.Weight, agentWeight: NSFont.Weight
    var lineHeight: CGFloat
    /// The tag's padding around the words.
    let padTop: CGFloat, padBottom: CGFloat, padSide: CGFloat
    /// A text without a wrap width wraps at this many times its font size, or at the image's edge if
    /// that is closer.
    let widthCap: CGFloat
    /// How far an agent's badge sits from the tag's left edge, and how far it overlaps the tag's top.
    let badgeInset: CGFloat, badgeOverlap: CGFloat
    /// An agent's note's size, as a fraction of the image's width, so the same sentence covers the
    /// same part of a small crop as of a full capture.
    let agentSize: CGFloat
    /// What an agent's note's badge says (`NoteBadge.label(for:)`); nil for a person's note.
    private(set) var badge: String?
    /// Whether the lines are balanced (`TextLayout`). Off only for the note being typed, whose lines
    /// must not move under the caret.
    var balanced = true
    /// The two faces and the badge's semibold. Immutable, and Core Text's descriptors are safe to
    /// share between threads.
    private let personFace: CTFontDescriptor
    private let agentFace: CTFontDescriptor
    private let badgeFace: CTFontDescriptor

    /// The tweaks' defaults.
    static let standard = UITweaks().textStyle

    /// The names that pick one of the system font's designs rather than a family.
    static let designs: [String: NSFontDescriptor.SystemDesign] = ["default": .default, "rounded": .rounded, "monospaced": .monospaced, "serif": .serif]

    init(personFont: String, personWeight: NSFont.Weight, agentFont: String, agentWeight: NSFont.Weight, lineHeight: CGFloat,
         padTop: CGFloat, padBottom: CGFloat, padSide: CGFloat, widthCap: CGFloat, badgeInset: CGFloat, badgeOverlap: CGFloat,
         agentSize: CGFloat) {
        self.personFont = personFont
        self.agentFont = agentFont
        self.personWeight = personWeight
        self.agentWeight = agentWeight
        self.lineHeight = lineHeight
        self.padTop = padTop
        self.padBottom = padBottom
        self.padSide = padSide
        self.widthCap = widthCap
        self.badgeInset = badgeInset
        self.badgeOverlap = badgeOverlap
        self.agentSize = agentSize
        personFace = Self.face(personFont, weight: personWeight)
        agentFace = Self.face(agentFont, weight: agentWeight)
        badgeFace = NSFont.systemFont(ofSize: 0, weight: .semibold).fontDescriptor as CTFontDescriptor
    }

    /// The face `name` picks at `weight`. A family is matched to its face nearest that weight; one
    /// that is not installed gives the system font, which `Settings` has already reported.
    private static func face(_ name: String, weight: NSFont.Weight) -> CTFontDescriptor {
        let system = NSFont.systemFont(ofSize: 0, weight: weight).fontDescriptor
        if let design = designs[name] { return (system.withDesign(design) ?? system) as CTFontDescriptor }
        guard isInstalled(name) else { return system as CTFontDescriptor }
        return NSFontDescriptor(fontAttributes: [.family: name, .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue]]) as CTFontDescriptor
    }

    /// Whether `name` is one of the system font's designs or an installed family.
    static func isInstalled(_ name: String) -> Bool {
        designs[name] != nil || ((CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? []).contains(name)
    }

    /// The style `mark`'s text is set in: an agent's in the agent's font with its badge, so its words
    /// read as the agent's at a glance, and a person's in the person's. Every place that lays out or
    /// draws a text asks this, so the editor, the cards, the flights and the rendering agree.
    func forMark(_ mark: Mark) -> TextStyle {
        mark.agent ? forAgent(named: mark.agentName) : person
    }

    /// The style of a note by the agent named `name`.
    func forAgent(named name: String?) -> TextStyle {
        var style = self
        style.badge = NoteBadge.label(for: name)
        return style
    }

    /// The style of a person's note.
    var person: TextStyle {
        var style = self
        style.badge = nil
        return style
    }

    /// The face at `size`.
    func font(size: CGFloat) -> CTFont { CTFontCreateWithFontDescriptor(badge == nil ? personFace : agentFace, size, nil) }

    /// The badge's face at `size`.
    func badgeFont(size: CGFloat) -> CTFont { CTFontCreateWithFontDescriptor(badgeFace, size, nil) }

    /// The values the faces are made from, which say everything about the style.
    private var values: [AnyHashable] {
        [personFont, agentFont, personWeight.rawValue, agentWeight.rawValue, lineHeight, padTop, padBottom, padSide, widthCap,
         badgeInset, badgeOverlap, agentSize, badge, balanced]
    }

    static func == (a: TextStyle, b: TextStyle) -> Bool { a.values == b.values }

    func hash(into hasher: inout Hasher) { hasher.combine(values) }
}

/// A text mark set in lines on its tag, in px: the rounded tag filled with the mark's colour, and the
/// words inside it. Core Text, so a rendering can lay text out off the main thread. Its line breaks
/// are the ones an `NSTextView` makes with the same font, a text container `wrapWidth` wide, and no
/// line fragment padding.
struct TextLayout {
    /// The room a text keeps from the image's right edge, as a fraction of the image's width.
    static let margin: CGFloat = 0.02

    struct Line {
        /// Starts at the words' left edge, as wide as its words without the spaces after them, and
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
    /// The tag, from the mark's origin: as wide as its widest line, or its badge, and its padding,
    /// and as tall as its lines and its padding. A text that ends in a line break, or holds nothing,
    /// has an empty last line.
    let box: CGRect
    /// The tag's corner radius: half the height of a one-line tag, so one line is a pill.
    let radius: CGFloat
    /// The width the lines were broken at, in px: the narrowest that keeps as many lines as the text
    /// takes at its full width, so no line ends with one word.
    let wrapWidth: CGFloat
    /// The words' inset from the tag's edges, in px.
    let padding: (top: CGFloat, side: CGFloat, bottom: CGFloat)
    /// The agent's badge across the tag's top edge, for an agent's style.
    let badge: NoteBadge?

    /// The least room a text without a wrap width wraps in, as a fraction of the image's width. One
    /// that starts with less to its right moves left instead of wrapping into a narrow column.
    static let minimumRoom: CGFloat = 0.15

    /// The widest a tag of `text` may be: its wrap width, or the room from its left edge to the
    /// image's right edge less the margin, and no more than the style's `widthCap` with its padding.
    static func tagWidth(of text: Mark.Text, imageWidth: CGFloat, pointScale: CGFloat, style: TextStyle) -> CGFloat {
        text.wrap ?? min(widestTag(size: text.size, pointScale: pointScale, style: style), imageWidth * (1 - margin) - text.origin.x)
    }

    /// The widest a tag without a wrap width is, in px, for a text of `size` pt.
    static func widestTag(size: CGFloat, pointScale: CGFloat, style: TextStyle) -> CGFloat {
        size * pointScale * (style.widthCap + 2 * style.padSide)
    }

    /// The x a text should start at. A text without a wrap width that has less than `minimumRoom`
    /// to its right moves left until its widest tag, broken only at its hard line breaks and its cap,
    /// fits before the margin, and no further left than 0, where a text wider than the image keeps
    /// its start showing. Any other text keeps its x.
    static func leftEdge(of text: Mark.Text, imageWidth: CGFloat, pointScale: CGFloat, style: TextStyle) -> CGFloat {
        let right = imageWidth * (1 - margin)
        guard text.wrap == nil, right - text.origin.x < imageWidth * minimumRoom else { return text.origin.x }
        var capped = text
        capped.wrap = widestTag(size: text.size, pointScale: pointScale, style: style)
        let widest = TextLayout(capped, imageWidth: imageWidth, pointScale: pointScale, style: style).box.width
        return max(0, min(text.origin.x, right - widest))
    }

    init(_ text: Mark.Text, imageWidth: CGFloat, pointScale: CGFloat, style: TextStyle) {
        let fontSize = text.size * pointScale
        let font = style.font(size: fontSize)
        let lineHeight = fontSize * style.lineHeight
        let badge = style.badge.map { NoteBadge(label: $0, fontSize: fontSize, style: style) }
        let padding = (top: fontSize * style.padTop, side: fontSize * style.padSide, bottom: fontSize * style.padBottom)
        let baseline = (lineHeight - (CTFontGetAscent(font) + CTFontGetDescent(font))) / 2 + CTFontGetAscent(font)
        let string = text.text as NSString
        let typesetter = CTTypesetterCreateWithAttributedString(NSAttributedString(string: text.text, attributes: [.font: font]))
        // An NSTextView keeps a line that runs up to 0.001 px past its container, and Core Text breaks
        // one 0.0002 px short of the width; this allowance puts both breaks in the same place, so a
        // text does not re-wrap when typing ends.
        func breaks(at width: CGFloat) -> [CFRange] {
            var ranges: [CFRange] = [], start = 0
            while start < string.length {
                // At least one character a line, so a width narrower than one character still ends.
                let count = max(1, CTTypesetterSuggestLineBreak(typesetter, start, Double(width) + 0.0008))
                ranges.append(CFRange(location: start, length: count))
                start += count
            }
            return ranges
        }
        let full = max(Self.tagWidth(of: text, imageWidth: imageWidth, pointScale: pointScale, style: style) - 2 * padding.side, 1)
        var wrapWidth = full
        var ranges = breaks(at: full)
        if ranges.count > 1, style.balanced {
            // Line counts only fall as the width grows, so the narrowest width with the same count is
            // found by halving. It is no wider than the widest line at the full width.
            let widest = ranges.map { range -> CGFloat in
                let line = CTTypesetterCreateLine(typesetter, range)
                return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line))
            }.max() ?? full
            var low: CGFloat = 0, high = min(full, widest)
            if breaks(at: high).count != ranges.count { high = full }
            for _ in 0..<12 {
                let middle = (low + high) / 2
                if breaks(at: middle).count <= ranges.count { high = middle } else { low = middle }
            }
            wrapWidth = high
            ranges = breaks(at: high)
        }
        let left = text.origin.x + padding.side
        var lines: [Line] = []
        func add(_ line: CTLine) {
            let top = text.origin.y + padding.top + CGFloat(lines.count) * lineHeight
            let words = CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line)
            lines.append(Line(rect: CGRect(x: left, y: top, width: max(0, words), height: lineHeight), baseline: top + baseline, ctLine: line))
        }
        for range in ranges { add(CTTypesetterCreateLine(typesetter, range)) }
        if text.text.isEmpty || text.text.last?.isNewline == true {
            add(CTLineCreateWithAttributedString(NSAttributedString(string: "", attributes: [.font: font])))
        }
        self.font = font
        self.lineHeight = lineHeight
        self.lines = lines
        self.wrapWidth = wrapWidth
        self.padding = padding
        self.badge = badge
        let words = max(lines.map(\.rect.width).max() ?? 0, (badge.map { $0.leastTagWidth(padSide: padding.side) } ?? 0) - 2 * padding.side)
        box = CGRect(x: text.origin.x, y: text.origin.y, width: words + 2 * padding.side,
                     height: padding.top + CGFloat(lines.count) * lineHeight + padding.bottom)
        radius = (padding.top + padding.bottom + lineHeight) / 2
    }

    /// The tag's outline.
    var tagPath: CGPath { Self.tagPath(box, radius: radius) }

    /// A tag's outline at `box`, with corners of `radius` or as round as its size allows.
    static func tagPath(_ box: CGRect, radius: CGFloat) -> CGPath {
        let corner = min(radius, box.width / 2, box.height / 2)
        return CGPath(roundedRect: box, cornerWidth: corner, cornerHeight: corner, transform: nil)
    }
}

/// The white badge on the top edge of an agent's note, at its left, that names the agent: its logo
/// and its name, as the thumbnail's `AgentBadge` shows them. It sits above the tag and overlaps its
/// edge by the style's `badgeOverlap`, so the tag keeps a person's note's padding. Sizes are
/// multiples of the note's font size.
struct NoteBadge {
    let fontSize: CGFloat
    /// What it says, as `label(for:)` gives it.
    let label: String
    /// The label set in the badge's font, cut short with an ellipsis past `longestLabel`.
    let line: CTLine

    /// How far it sits from the tag's left edge, and how far it overlaps the tag's top, in px.
    let inset: CGFloat, overlap: CGFloat

    static let height: CGFloat = 1.36
    static let labelSize: CGFloat = 0.75, logoSize: CGFloat = 0.79, gap: CGFloat = 0.32
    static let padLeading: CGFloat = 0.5, padTrailing: CGFloat = 0.57
    /// The widest a label is drawn, as a multiple of the note's font size. `agent=` takes any name up
    /// to `Agent.maxLength` characters.
    static let longestLabel: CGFloat = 10

    init(label: String, fontSize: CGFloat, style: TextStyle) {
        self.fontSize = fontSize
        self.label = label
        inset = fontSize * style.badgeInset
        overlap = fontSize * style.badgeOverlap
        let font = style.badgeFont(size: fontSize * Self.labelSize)
        let whole = CTLineCreateWithAttributedString(NSAttributedString(string: label, attributes: [.font: font]))
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "\u{2026}", attributes: [.font: font]))
        line = CTLineCreateTruncatedLine(whole, Double(fontSize * Self.longestLabel), .end, ellipsis) ?? whole
    }

    /// How far the badge rises above the tag's top edge.
    var above: CGFloat { fontSize * Self.height - overlap }

    /// The least width of the agent's tag, whose side padding is `padSide` px: room for the badge,
    /// and the padding after it.
    func leastTagWidth(padSide: CGFloat) -> CGFloat { inset + padSide + width }

    /// What the badge says for an agent's name: the name with a capital, or "Agent" without one.
    static func label(for name: String?) -> String {
        guard let name = name?.trimmingCharacters(in: .whitespaces), let first = name.first else { return "Agent" }
        return first.uppercased() + name.dropFirst()
    }

    /// The badge's width around its label.
    var width: CGFloat {
        fontSize * (Self.padLeading + Self.logoSize + Self.gap + Self.padTrailing) + CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// The badge's capsule on a tag at `box`.
    func frame(on box: CGRect) -> CGRect {
        CGRect(x: box.minX + inset, y: box.minY - above, width: width, height: fontSize * Self.height)
    }
}
