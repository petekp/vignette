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

    /// The body as drawn at `pointScale` px per pt: straight when the bend is under `straightBelow` pt.
    func body(pointScale: CGFloat) -> ArrowBody {
        ArrowBody(start: start, end: end, bend: abs(bend) < Self.straightBelow * pointScale ? 0 : bend)
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

/// An arrow's body: the straight line between its ends, or the circular arc through both ends and
/// its bend point.
struct ArrowBody {
    let start: CGPoint
    let end: CGPoint
    /// Nil for a straight body.
    let arc: Arc?

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

    /// The point `fraction` of the way along the body, from `start` at 0 to `end` at 1.
    func point(at fraction: CGFloat) -> CGPoint {
        let t = min(max(fraction, 0), 1)
        guard let arc else { return CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t) }
        return arc.point(at: arc.startAngle + arc.sweep * t)
    }

    /// The distance from `point` to the nearest point of the body.
    func distance(to point: CGPoint) -> CGFloat {
        guard let arc else {
            let dx = end.x - start.x, dy = end.y - start.y
            let lengthSquared = dx * dx + dy * dy
            guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
            let t = min(max(((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared, 0), 1)
            return hypot(point.x - (start.x + dx * t), point.y - (start.y + dy * t))
        }
        let fromCenter = hypot(point.x - arc.center.x, point.y - arc.center.y)
        if fromCenter > 0, arc.covers(atan2(point.y - arc.center.y, point.x - arc.center.x)) {
            return abs(fromCenter - arc.radius)
        }
        return min(hypot(point.x - start.x, point.y - start.y), hypot(point.x - end.x, point.y - end.y))
    }

    /// The smallest rect holding the whole body.
    var bounds: CGRect {
        var points = [start, end]
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
    /// The system font with the rounded design, at `weight`. Immutable, and Core Text's descriptors
    /// are safe to share between threads.
    private let face: CTFontDescriptor

    /// The tweaks' defaults.
    static let standard = UITweaks().textStyle

    init(weight: NSFont.Weight, lineHeight: CGFloat) {
        self.weight = weight
        self.lineHeight = lineHeight
        let system = NSFont.systemFont(ofSize: 0, weight: weight).fontDescriptor
        face = (system.withDesign(.rounded) ?? system) as CTFontDescriptor
    }

    /// SF Pro Rounded at `size`.
    func font(size: CGFloat) -> CTFont { CTFontCreateWithFontDescriptor(face, size, nil) }

    static func == (a: TextStyle, b: TextStyle) -> Bool { a.weight == b.weight && a.lineHeight == b.lineHeight }
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
        /// Where the glyphs stand: centred in the line's height, as CSS centres them.
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
