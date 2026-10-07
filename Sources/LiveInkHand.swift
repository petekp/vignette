import AppKit
import QuartzCore

/// How the person's hand drew a mark: the stroke's width at each of its points, wider where the hand
/// slowed, and where each point sits on the shape the stroke became. The mark keeps both, so an
/// ellipse or an arrow still looks drawn by hand and starts and ends where the hand did
/// (docs/live-ink-look-2026-10-07.md).
struct InkHand: Equatable {
    /// A stroke's centre line and its width at each point, a multiple of the mark's stroke width.
    struct Stroke: Equatable {
        var points: [CGPoint]
        var widths: [CGFloat]
    }

    /// Each point's place on the shape: its angle round an ellipse's centre, its fraction of the way
    /// round a rectangle from its top left, or its fraction of the way along an arrow's body.
    var places: [CGFloat]
    var widths: [CGFloat]
    /// The stroke where the hand drew it, with its end as the pen left it, from the corner of the
    /// mark's extent, so it moves with the mark: what the mark eases from when it first shows.
    private var drawn: Stroke

    /// The hand that drew `raw`, the pointer's points in the order they came, as the stroke that
    /// became `mark`. Nil for a mark that is neither an ellipse nor an arrow.
    init?(raw: [CGPoint], mark: Mark) {
        let drawn = Self.stroke(raw, tapersEnd: false)
        guard drawn.points.count > 1 else { return nil }
        switch mark.geometry {
        case .ellipse(let frame):
            places = drawn.points.map { Self.angle(of: $0, in: frame) }
            widths = Self.stroke(raw, tapersEnd: true).widths
        case .arrow:
            let lengths = Self.lengths(drawn.points)
            let total = max(lengths.last ?? 0, .ulpOfOne)
            places = lengths.map { $0 / total }
            // An arrow ends in its head, so its end does not taper.
            widths = drawn.widths
        default:
            return nil
        }
        self.drawn = Self.moved(drawn, by: Self.corner(of: mark), toward: false)
    }

    private init(places: [CGFloat], widths: [CGFloat], drawn: Stroke) {
        self.places = places
        self.widths = widths
        self.drawn = drawn
    }

    /// A hand for a mark no hand drew, as an answer's mark the person picked: even widths, tapered
    /// at the start, and an ellipse or a rectangle that starts at its upper left and runs a little
    /// past it, as a loop drawn by hand does.
    static func even(for mark: Mark, markStyle: MarkStyle) -> InkHand? {
        let count: Int
        let places: [CGFloat]
        let closed: Bool
        switch mark.geometry {
        case .ellipse(let frame):
            count = max(24, Int((frame.width + frame.height) * 1.6 / spacing))
            let first: CGFloat = -0.75 * .pi, turn: CGFloat = 2 * .pi + 0.35
            places = (0..<count).map { (index: Int) -> CGFloat in first + turn * CGFloat(index) / CGFloat(count - 1) }
            closed = true
        case .rectangle(let frame):
            let first: CGFloat = -0.02, turn: CGFloat = 1.06
            count = max(24, Int(2 * (frame.width + frame.height) * turn / spacing))
            places = (0..<count).map { (index: Int) -> CGFloat in first + turn * CGFloat(index) / CGFloat(count - 1) }
            closed = true
        case .arrow(let arrow):
            count = max(8, Int(arrow.exactBody.length / spacing))
            places = (0..<count).map { CGFloat($0) / CGFloat(count - 1) }
            closed = false
        default:
            return nil
        }
        var hand = InkHand(places: places, widths: Array(repeating: 1, count: count), drawn: Stroke(points: [], widths: []))
        let points = hand.points(of: mark, markStyle: markStyle)
        hand.widths = taper(hand.widths, along: lengths(points), end: closed)
        hand.drawn = moved(Stroke(points: points, widths: hand.widths), by: corner(of: mark), toward: false)
        return hand
    }

    /// The stroke where the hand drew `mark`, in the points `mark` is in.
    func drawn(for mark: Mark) -> Stroke {
        Self.moved(drawn, by: Self.corner(of: mark), toward: true)
    }

    private static func corner(of mark: Mark) -> CGPoint { mark.shapeExtent?.origin ?? .zero }

    /// `stroke` moved by `corner`, or back from it.
    private static func moved(_ stroke: Stroke, by corner: CGPoint, toward: Bool) -> Stroke {
        let sign: CGFloat = toward ? 1 : -1
        return Stroke(points: stroke.points.map { CGPoint(x: $0.x + sign * corner.x, y: $0.y + sign * corner.y) }, widths: stroke.widths)
    }

    /// The centre line on `mark`'s shape as it is now: each point at its place.
    func points(of mark: Mark, markStyle: MarkStyle) -> [CGPoint] {
        switch mark.geometry {
        case .ellipse(let frame):
            let rx = frame.width / 2, ry = frame.height / 2
            return places.map { (angle: CGFloat) -> CGPoint in CGPoint(x: frame.midX + rx * cos(angle), y: frame.midY + ry * sin(angle)) }
        case .rectangle(let frame):
            return places.map { Self.point(round: frame, at: $0) }
        case .arrow(let arrow):
            let body = arrow.body(pointScale: 1)
            let end = Arrowhead(body: body, strokeWidth: markStyle.strokeWidth, style: markStyle).bodyEnd
            return places.map { body.point(at: $0 * end) }
        default:
            return []
        }
    }

    /// `raw` resampled every `spacing` points and smoothed, each point as wide as the hand was slow
    /// there, measured by the spacing of the pointer's events around it against their mean, and
    /// tapered where the pen landed and, with `tapersEnd`, where it lifted.
    static func stroke(_ raw: [CGPoint], tapersEnd: Bool) -> Stroke {
        guard raw.count > 1 else { return Stroke(points: raw, widths: raw.map { _ in 1 }) }
        let steps = raw.indices.map { index -> CGFloat in
            let a = raw[max(index - 1, 0)], b = raw[min(index + 1, raw.count - 1)]
            return hypot(b.x - a.x, b.y - a.y) / CGFloat(min(index + 1, raw.count - 1) - max(index - 1, 0))
        }
        let mean = max(steps.reduce(0, +) / CGFloat(steps.count), .ulpOfOne)
        let slowness = steps.map { min(max(1.32 - 0.42 * $0 / mean, 0.72), 1.4) }
        // Resampled by length, so the widths no longer depend on how often the pointer reported.
        var points = [raw[0]], widths = [slowness[0]]
        var carried: CGFloat = 0
        for index in 1..<raw.count {
            let a = raw[index - 1], b = raw[index]
            let length = hypot(b.x - a.x, b.y - a.y)
            guard length > 0 else { continue }
            var at = spacing - carried
            while at <= length {
                let t = at / length
                points.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                widths.append(slowness[index - 1] + (slowness[index] - slowness[index - 1]) * t)
                at += spacing
            }
            carried = length - (at - spacing)
        }
        if let last = raw.last, points.last != last { points.append(last); widths.append(slowness[slowness.count - 1]) }
        for _ in 0..<2 {
            points = points.indices.map { index in
                guard index > 0, index < points.count - 1 else { return points[index] }
                let a = points[index - 1], b = points[index], c = points[index + 1]
                return CGPoint(x: (a.x + 2 * b.x + c.x) / 4, y: (a.y + 2 * b.y + c.y) / 4)
            }
        }
        let reach = 6
        widths = widths.indices.map { index in
            let span = max(0, index - reach)...min(widths.count - 1, index + reach)
            return span.reduce(0) { $0 + widths[$1] } / CGFloat(span.count)
        }
        return Stroke(points: points, widths: taper(widths, along: lengths(points), end: tapersEnd))
    }

    /// The widths narrowed over the first `startTaper` points of length and, with `end`, the last
    /// `endTaper`.
    private static func taper(_ widths: [CGFloat], along lengths: [CGFloat], end: Bool) -> [CGFloat] {
        let total = lengths.last ?? 0
        func ease(_ x: CGFloat) -> CGFloat { let t = min(max(x, 0), 1); return t * t * (3 - 2 * t) }
        return widths.indices.map { index in
            let start = 0.38 + 0.62 * ease(lengths[index] / startTaper)
            let finish = end ? 0.3 + 0.7 * ease((total - lengths[index]) / endTaper) : 1
            return widths[index] * start * finish
        }
    }

    /// The length of the path from the first point to each.
    static func lengths(_ points: [CGPoint]) -> [CGFloat] {
        var lengths: [CGFloat] = [0]
        for (a, b) in zip(points, points.dropFirst()) { lengths.append(lengths[lengths.count - 1] + hypot(b.x - a.x, b.y - a.y)) }
        return lengths
    }

    /// The point `fraction` of the way round `frame` clockwise from the end of its top left corner,
    /// with the corners rounded as a hand rounds them, wrapping past a whole turn.
    private static func point(round frame: CGRect, at fraction: CGFloat) -> CGPoint {
        let r = min(rectangleCorner, frame.width / 2, frame.height / 2)
        let across = frame.width - 2 * r, down = frame.height - 2 * r, arc = CGFloat.pi * r / 2
        func onArc(_ centre: CGPoint, _ angle: CGFloat) -> CGPoint {
            CGPoint(x: centre.x + r * cos(angle), y: centre.y + r * sin(angle))
        }
        let pieces: [(length: CGFloat, at: (CGFloat) -> CGPoint)] = [
            (across, { CGPoint(x: frame.minX + r + $0, y: frame.minY) }),
            (arc, { onArc(CGPoint(x: frame.maxX - r, y: frame.minY + r), -.pi / 2 + $0 / max(r, .ulpOfOne)) }),
            (down, { CGPoint(x: frame.maxX, y: frame.minY + r + $0) }),
            (arc, { onArc(CGPoint(x: frame.maxX - r, y: frame.maxY - r), $0 / max(r, .ulpOfOne)) }),
            (across, { CGPoint(x: frame.maxX - r - $0, y: frame.maxY) }),
            (arc, { onArc(CGPoint(x: frame.minX + r, y: frame.maxY - r), .pi / 2 + $0 / max(r, .ulpOfOne)) }),
            (down, { CGPoint(x: frame.minX, y: frame.maxY - r - $0) }),
            (arc, { onArc(CGPoint(x: frame.minX + r, y: frame.minY + r), .pi + $0 / max(r, .ulpOfOne)) }),
        ]
        let total = pieces.reduce(0) { $0 + $1.length }
        guard total > 0 else { return CGPoint(x: frame.midX, y: frame.midY) }
        var along = (fraction - fraction.rounded(.down)) * total
        for piece in pieces {
            if along <= piece.length { return piece.at(along) }
            along -= piece.length
        }
        return pieces[0].at(0)
    }

    /// The angle of `point` round the centre of the ellipse in `frame`, measured as if it were a circle.
    private static func angle(of point: CGPoint, in frame: CGRect) -> CGFloat {
        atan2((point.y - frame.midY) / max(frame.height / 2, .ulpOfOne), (point.x - frame.midX) / max(frame.width / 2, .ulpOfOne))
    }

    /// How far apart a stroke's points are, and how far its ends taper, in points.
    static let spacing: CGFloat = 2
    private static let startTaper: CGFloat = 14
    private static let endTaper: CGFloat = 26
    /// The radius of a rectangle's corners in ink, in points.
    private static let rectangleCorner: CGFloat = 4
}

/// The person's ink: a filled outline whose width follows the hand, darker towards its edges, with
/// a soft shadow under it. While it is wet, a lighter streak trails the pen and dries off.
@MainActor
final class InkMarkLayer: CALayer {
    /// The body, outermost first, each narrower and nearer the ink's own colour.
    private var bodies: [CAShapeLayer] = []
    private let head = CAShapeLayer()
    private let sheen = CAShapeLayer()
    /// What is drawn: the mark, the hand it was given, and the hand it is drawn with, which is an
    /// even one when it was given none.
    private var shown: (mark: Mark, given: InkHand?, hand: InkHand, markStyle: MarkStyle)?
    /// The centre line as drawn, for the thinking light and drawing on.
    private(set) var centreLine: CGPath?
    /// The widest the ink is, in points.
    private var widest: CGFloat = 0

    init(scale: CGFloat) {
        bodies = Self.bodyWidths.map { _ in CAShapeLayer() }
        super.init()
        anchorPoint = .zero
        contentsScale = scale
        for layer in bodies + [head, sheen] {
            layer.anchorPoint = .zero
            layer.contentsScale = scale
            layer.strokeColor = nil
            addSublayer(layer)
        }
        for layer in [bodies[0], head] {
            layer.shadowColor = CGColor(gray: 0, alpha: 1)
            layer.shadowOffset = CGSize(width: 0, height: 0.5)
            layer.shadowRadius = Self.shadowRadius
            layer.shadowOpacity = Self.shadowOpacity
        }
        sheen.opacity = 0
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Draws `mark` as `hand` drew it, or evenly with no hand, unless it is drawn already as it is.
    func show(_ mark: Mark, hand: InkHand?, markStyle: MarkStyle) {
        if let shown, shown.mark == mark, shown.given == hand, shown.markStyle == markStyle { return }
        guard let drawing = hand ?? InkHand.even(for: mark, markStyle: markStyle) else { return }
        shown = (mark, hand, drawing, markStyle)
        let points = drawing.points(of: mark, markStyle: markStyle)
        draw(InkHand.Stroke(points: points, widths: drawing.widths), markStyle: markStyle, colour: markStyle.color(mark.color))
        head.path = mark.shape(pointScale: 1, markStyle: markStyle)?.filled
        head.shadowPath = head.path
    }

    /// The stroke being drawn: its end at the pen, and the wet streak trailing it.
    func showPen(_ stroke: InkHand.Stroke, markStyle: MarkStyle) {
        shown = nil
        head.path = nil
        head.shadowPath = nil
        draw(stroke, markStyle: markStyle, colour: markStyle.color(.person))
        sheen.path = Self.sheen(of: stroke, width: markStyle.strokeWidth)
        sheen.opacity = 1
    }

    /// A copy in `markStyle`, as the done state's green.
    func twin(in markStyle: MarkStyle) -> InkMarkLayer {
        let twin = InkMarkLayer(scale: contentsScale)
        if let shown { twin.show(shown.mark, hand: shown.hand, markStyle: markStyle) }
        return twin
    }

    /// Eases from where the hand drew it onto its shape over `duration`, keeping the hand's widths,
    /// while the wet streak dries.
    func ease(from drawn: InkHand.Stroke, duration: CFTimeInterval) {
        guard let shown, duration > 0 else { return }
        let hand = shown.hand
        let width = shown.markStyle.strokeWidth
        let now = convertTime(CACurrentMediaTime(), from: nil)
        let curve = CAMediaTimingFunction(controlPoints: 0.3, 0, 0.2, 1)
        func animate(_ layer: CALayer, _ key: String, from: Any?, duration: CFTimeInterval, timing: CAMediaTimingFunction = curve) {
            let animation = CABasicAnimation(keyPath: key)
            animation.fromValue = from
            animation.beginTime = now
            animation.duration = duration
            animation.timingFunction = timing
            animation.fillMode = .backwards
            layer.add(animation, forKey: "ease-\(key)")
        }
        for (layer, fraction) in zip(bodies, Self.bodyWidths) {
            animate(layer, "path", from: Self.outline(drawn, width: width * fraction), duration: duration)
        }
        animate(bodies[0], "shadowPath", from: Self.outline(drawn, width: width), duration: duration)
        animate(head, "opacity", from: 0, duration: duration, timing: CAMediaTimingFunction(name: .easeIn))
        let final = InkHand.Stroke(points: hand.points(of: shown.mark, markStyle: shown.markStyle), widths: hand.widths)
        sheen.path = Self.sheen(of: final, width: width)
        sheen.opacity = 0
        animate(sheen, "path", from: Self.sheen(of: drawn, width: width), duration: duration)
        animate(sheen, "opacity", from: 1, duration: Self.dry * Double(Settings.shared.motionScale), timing: CAMediaTimingFunction(name: .easeOut))
    }

    /// Draws itself on along its centre line after `delay`, over `duration`, its head appearing as
    /// the line reaches it.
    func drawOn(after delay: CFTimeInterval, duration: CFTimeInterval) {
        guard duration > 0, let line = centreLine else { return }
        let begin = convertTime(CACurrentMediaTime(), from: nil) + delay
        let reveal = revealMask(along: line)
        let grow = CABasicAnimation(keyPath: "strokeEnd")
        grow.fromValue = 0
        grow.toValue = 1
        grow.beginTime = begin
        grow.duration = duration
        grow.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0, 0.2, 1)
        grow.fillMode = .backwards
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak reveal] in
            if let self, self.mask === reveal { self.mask = nil }
        }
        reveal.add(grow, forKey: "drawOn")
        CATransaction.commit()
        let appear = CABasicAnimation(keyPath: "opacity")
        appear.fromValue = 0
        appear.toValue = 1
        appear.beginTime = begin + duration * 0.85
        appear.duration = duration * 0.25
        appear.fillMode = .backwards
        head.add(appear, forKey: "drawOn")
    }

    /// Un-draws along its centre line from `begin`, in this layer's time, over `duration`, and stays
    /// gone.
    func undraw(at begin: CFTimeInterval, duration: CFTimeInterval) {
        guard let line = centreLine else { return }
        let reveal = revealMask(along: line)
        let away = CABasicAnimation(keyPath: "strokeStart")
        away.fromValue = 0
        away.toValue = 1
        away.beginTime = begin
        away.duration = duration
        away.fillMode = .forwards
        away.isRemovedOnCompletion = false
        away.timingFunction = CAMediaTimingFunction(name: .easeIn)
        reveal.add(away, forKey: "undraw")
    }

    private func revealMask(along line: CGPath) -> CAShapeLayer {
        let reveal = CAShapeLayer()
        reveal.anchorPoint = .zero
        reveal.contentsScale = contentsScale
        reveal.path = line
        reveal.fillColor = nil
        reveal.strokeColor = CGColor(gray: 0, alpha: 1)
        reveal.lineWidth = widest + Self.shadowRadius * 4
        reveal.lineCap = .round
        reveal.lineJoin = .round
        mask = reveal
        return reveal
    }

    private func draw(_ stroke: InkHand.Stroke, markStyle: MarkStyle, colour: CGColor) {
        let width = markStyle.strokeWidth
        for ((layer, fraction), darken) in zip(zip(bodies, Self.bodyWidths), Self.bodyDarkening) {
            layer.path = Self.outline(stroke, width: width * fraction)
            layer.fillColor = colour.mixed(with: .black, darken)
        }
        bodies.first?.shadowPath = bodies.first?.path
        head.fillColor = colour.mixed(with: .black, Self.bodyDarkening[1])
        sheen.fillColor = colour.mixed(with: .white, Self.sheenLightening)
        widest = (stroke.widths.max() ?? 1) * width
        let line = CGMutablePath()
        line.addLines(between: stroke.points)
        centreLine = line
    }

    /// The outline round `stroke`, `width` points wide where its width is 1: each side offset along
    /// the normal by half the width, and round ends. The same count of points makes the same
    /// elements, so Core Animation can animate one outline into another.
    static func outline(_ stroke: InkHand.Stroke, width: CGFloat) -> CGPath {
        let points = stroke.points
        let path = CGMutablePath()
        guard points.count > 1 else { return path }
        let halves = stroke.widths.map { max($0 * width / 2, 0.05) }
        var normals: [CGVector] = []
        var last = CGVector(dx: 0, dy: -1)
        for index in points.indices {
            let a = points[max(index - 1, 0)], b = points[min(index + 1, points.count - 1)]
            let length = hypot(b.x - a.x, b.y - a.y)
            if length > 0 { last = CGVector(dx: -(b.y - a.y) / length, dy: (b.x - a.x) / length) }
            normals.append(last)
        }
        func side(_ index: Int, _ sign: CGFloat) -> CGPoint {
            CGPoint(x: points[index].x + normals[index].dx * halves[index] * sign, y: points[index].y + normals[index].dy * halves[index] * sign)
        }
        path.move(to: side(0, 1))
        for index in 1..<points.count { path.addLine(to: side(index, 1)) }
        let end = points.count - 1
        let endAngle = atan2(normals[end].dy, normals[end].dx)
        path.addArc(center: points[end], radius: halves[end], startAngle: endAngle, endAngle: endAngle + .pi, clockwise: true)
        for index in stride(from: end - 1, through: 0, by: -1) { path.addLine(to: side(index, -1)) }
        let startAngle = atan2(-normals[0].dy, -normals[0].dx)
        path.addArc(center: points[0], radius: halves[0], startAngle: startAngle, endAngle: startAngle + .pi, clockwise: true)
        path.closeSubpath()
        return path
    }

    /// The wet streak: the last `sheenPoints` of the stroke, narrower than the ink, growing from
    /// nothing at its old end to its full width at the pen.
    private static func sheen(of stroke: InkHand.Stroke, width: CGFloat) -> CGPath {
        let start = max(0, stroke.points.count - sheenPoints)
        let count = stroke.points.count - start
        guard count > 1 else { return CGMutablePath() }
        let widths = (0..<count).map { stroke.widths[start + $0] * sheenWidth * CGFloat($0) / CGFloat(count - 1) }
        return outline(InkHand.Stroke(points: Array(stroke.points[start...]), widths: widths), width: width)
    }

    /// The body's layers, as fractions of the ink's width, and how far each is darkened.
    private static let bodyWidths: [CGFloat] = [1, 0.72, 0.42]
    private static let bodyDarkening: [CGFloat] = [0.2, 0.08, 0]
    /// The wet streak: how many of the stroke's points it covers, its width as a fraction of the
    /// ink's, how much lighter it is, and how long it takes to dry once the pen lifts.
    private static let sheenPoints = 40
    private static let sheenWidth: CGFloat = 0.4
    private static let sheenLightening: CGFloat = 0.45
    private static let dry: CFTimeInterval = 0.55
    /// The soft shadow under the ink.
    private static let shadowRadius: CGFloat = 2.5
    private static let shadowOpacity: Float = 0.3
}
