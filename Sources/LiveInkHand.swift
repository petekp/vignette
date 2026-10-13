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
    init?(raw: [CGPoint], mark: Mark, feel: Feel) {
        let drawn = Self.stroke(raw, tapersEnd: false, feel: feel)
        guard drawn.points.count > 1 else { return nil }
        switch mark.geometry {
        case .ellipse(let frame):
            places = drawn.points.map { Self.angle(of: $0, in: frame) }
            widths = Self.stroke(raw, tapersEnd: true, feel: feel).widths
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
    static func even(for mark: Mark, markStyle: MarkStyle, feel: Feel) -> InkHand? {
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
        hand.widths = taper(hand.widths, along: lengths(points), feel: feel, end: closed)
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
    /// there, and tapered where the pen landed and, with `tapersEnd`, where it lifted.
    static func stroke(_ raw: [CGPoint], tapersEnd: Bool, feel: Feel) -> Stroke {
        var pen = Pen(feel: feel)
        let stroke = pen.stroke(through: raw)
        guard tapersEnd, stroke.points.count > 1 else { return stroke }
        return Stroke(points: stroke.points, widths: taper(stroke.widths, along: lengths(stroke.points), feel: feel, start: false, end: true))
    }

    /// How a hand's speed and its pen's landing and lifting shape the line: the tweak panel's Live ink
    /// hand section.
    struct Feel: Equatable, Sendable {
        /// The width where the hand moves at its average speed, and how much each multiple of that
        /// speed narrows it, between the thinnest and the widest.
        var width: CGFloat = 0.9
        var speed: CGFloat = 0.42
        var thinnest: CGFloat = 0.72
        var widest: CGFloat = 1.4
        /// Pointer events the average speed is taken over, and points either side a width is averaged with.
        var memory = 48
        var smoothing = 6
        /// Points the line narrows over where the pen lands and where a loop's pen lifts, and the share of
        /// the width it narrows to there.
        var startTaper: CGFloat = 14
        var startWidth: CGFloat = 0.38
        var endTaper: CGFloat = 26
        var endWidth: CGFloat = 0.3
    }

    /// The stroke under the pen, built as the pointer's events arrive. A point's place and width
    /// depend only on the events up to a few past it, so all but the stroke's end is worked out once
    /// and kept, and an event costs the same however long the stroke is.
    ///
    /// A point is as wide as the hand was slow there: the spacing of the pointer's events round it
    /// against their mean over the `meanReach` events before it. A mean over the whole stroke
    /// changed every width with each event, so the line shifted as it grew.
    struct Pen {
        let feel: Feel
        private var raw: [CGPoint] = []
        /// The slowness at each raw event whose next event has come.
        private var slowness: [CGFloat] = []
        /// The running sum of those events' spacings, for their mean.
        private var spacingSums: [CGFloat] = [0]
        /// The points every `spacing` along the raw segments whose ends are settled, and their slowness,
        /// before smoothing.
        private var flat: [CGPoint] = [], flatSlowness: [CGFloat] = []
        private var resampled = 0
        private var carried: CGFloat = 0
        /// The stroke's start, which no later event changes, and the length to each of its points.
        private(set) var settled = Stroke(points: [], widths: [])
        private var settledLengths: [CGFloat] = []

        init(feel: Feel) {
            self.feel = feel
        }

        /// The stroke through `raw`, which continues the events this pen has had or starts a new stroke.
        mutating func stroke(through raw: [CGPoint]) -> Stroke {
            if raw.count < self.raw.count || raw.first != self.raw.first { self = Pen(feel: feel) }
            for point in raw.dropFirst(self.raw.count) { add(point) }
            return current()
        }

        private mutating func add(_ point: CGPoint) {
            raw.append(point)
            // An event's spacing needs the event after it, so the one before this is settled now.
            while slowness.count < raw.count - 1 {
                let index = slowness.count
                let step = Self.step(at: index, in: raw)
                spacingSums.append(spacingSums[spacingSums.count - 1] + step)
                slowness.append(slowness(of: step, at: index))
            }
            // A segment's points need the slowness at both its ends.
            if flat.isEmpty, let first = slowness.first { flat = [raw[0]]; flatSlowness = [first] }
            while resampled + 1 < slowness.count {
                Self.resample(from: raw[resampled], to: raw[resampled + 1], slowness[resampled], slowness[resampled + 1],
                              carried: &carried, into: &flat, &flatSlowness)
                resampled += 1
            }
            settle()
        }

        private static func step(at index: Int, in raw: [CGPoint]) -> CGFloat {
            let before = max(index - 1, 0), after = min(index + 1, raw.count - 1)
            let a = raw[before], b = raw[after]
            return hypot(b.x - a.x, b.y - a.y) / CGFloat(max(after - before, 1))
        }

        private func slowness(of step: CGFloat, at index: Int) -> CGFloat {
            let from = max(0, index + 1 - max(feel.memory, 1))
            let sum = spacingSums[spacingSums.count - 1] - spacingSums[from] + (index < spacingSums.count - 1 ? 0 : step)
            let count = CGFloat(index + 1 - from)
            let mean = max(sum / count, .ulpOfOne)
            return min(max(feel.width + feel.speed * (1 - step / mean), feel.thinnest), feel.widest)
        }

        private static func resample(from a: CGPoint, to b: CGPoint, _ slowA: CGFloat, _ slowB: CGFloat, carried: inout CGFloat,
                                     into points: inout [CGPoint], _ slownesses: inout [CGFloat]) {
            let length = hypot(b.x - a.x, b.y - a.y)
            guard length > 0 else { return }
            var at = spacing - carried
            while at <= length {
                let t = at / length
                points.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                slownesses.append(slowA + (slowB - slowA) * t)
                at += spacing
            }
            carried = length - (at - spacing)
        }

        /// Keeps the points that no later event can change: smoothing reaches two points either side and
        /// the widths' average `widthReach`.
        private mutating func settle() {
            let final = flat.count - max(2, feel.smoothing) - 1
            guard final > settled.points.count else { return }
            let points = flat, slownesses = flatSlowness
            for index in settled.points.count..<final { keep(index, in: points, slownesses) }
        }

        private mutating func keep(_ index: Int, in points: [CGPoint], _ slownesses: [CGFloat]) {
            let point = Self.smoothed(index, in: points)
            let length = settled.points.last.map { settledLengths[settledLengths.count - 1] + hypot(point.x - $0.x, point.y - $0.y) } ?? 0
            settled.points.append(point)
            settledLengths.append(length)
            settled.widths.append(averaged(index, in: slownesses) * InkHand.startTaper(at: length, feel: feel))
        }

        /// The settled start and the end as the events so far place it.
        private func current() -> Stroke {
            guard raw.count > 1 else { return Stroke(points: raw, widths: raw.map { _ in 1 }) }
            var points = flat, slownesses = flatSlowness, carried = carried
            // The last event's slowness as it stands, and the segments not settled yet.
            let ends = slowness + [slowness(of: Self.step(at: raw.count - 1, in: raw), at: raw.count - 1)]
            for index in resampled..<(raw.count - 1) {
                Self.resample(from: raw[index], to: raw[index + 1], ends[index], ends[index + 1], carried: &carried, into: &points, &slownesses)
            }
            if let last = raw.last, points.last != last { points.append(last); slownesses.append(ends[ends.count - 1]) }
            var stroke = settled
            var length = settledLengths.last ?? 0
            for index in settled.points.count..<points.count {
                let point = Self.smoothed(index, in: points)
                if let before = stroke.points.last { length += hypot(point.x - before.x, point.y - before.y) }
                stroke.points.append(point)
                stroke.widths.append(averaged(index, in: slownesses) * InkHand.startTaper(at: length, feel: feel))
            }
            return stroke
        }

        /// `points[index]` after two passes of a [1 2 1] smoothing, the ends kept.
        private static func smoothed(_ index: Int, in points: [CGPoint]) -> CGPoint {
            func once(_ i: Int) -> CGPoint {
                guard i > 0, i < points.count - 1 else { return points[i] }
                let a = points[i - 1], b = points[i], c = points[i + 1]
                return CGPoint(x: (a.x + 2 * b.x + c.x) / 4, y: (a.y + 2 * b.y + c.y) / 4)
            }
            guard index > 0, index < points.count - 1 else { return once(index) }
            let a = once(index - 1), b = once(index), c = once(index + 1)
            return CGPoint(x: (a.x + 2 * b.x + c.x) / 4, y: (a.y + 2 * b.y + c.y) / 4)
        }

        private func averaged(_ index: Int, in slownesses: [CGFloat]) -> CGFloat {
            let reach = max(feel.smoothing, 0)
            let span = max(0, index - reach)...min(slownesses.count - 1, index + reach)
            return span.reduce(0) { $0 + slownesses[$1] } / CGFloat(span.count)
        }
    }

    /// The widths narrowed over the feel's start taper, with `start`, and its end taper, with `end`.
    private static func taper(_ widths: [CGFloat], along lengths: [CGFloat], feel: Feel, start: Bool = true, end: Bool) -> [CGFloat] {
        let total = lengths.last ?? 0
        return widths.indices.map { index in
            let finish = end ? feel.endWidth + (1 - feel.endWidth) * ease((total - lengths[index]) / max(feel.endTaper, .ulpOfOne)) : 1
            return widths[index] * (start ? startTaper(at: lengths[index], feel: feel) : 1) * finish
        }
    }

    private static func startTaper(at length: CGFloat, feel: Feel) -> CGFloat {
        feel.startWidth + (1 - feel.startWidth) * ease(length / max(feel.startTaper, .ulpOfOne))
    }

    private static func ease(_ x: CGFloat) -> CGFloat { let t = min(max(x, 0), 1); return t * t * (3 - 2 * t) }

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

    /// How far apart a stroke's points are, in points.
    static let spacing: CGFloat = 2
    /// The radius of a rectangle's corners in ink, in points.
    private static let rectangleCorner: CGFloat = 4
}

/// The person's ink: a rod of opal gel whose width follows the hand, drawn by `InkGel` into a Metal
/// layer, with a glow under it. Its light and film drift on `InkClock`'s time, so it looks alive
/// while it is on the screen (docs/live-ink-gel-2026-10-12.md).
@MainActor
final class InkMarkLayer: CALayer {
    private let gel = CAMetalLayer()
    /// What is drawn: the mark, the hand it was given, the hand it is drawn with, which is an even one
    /// when it was given none, and the style its line is laid out in.
    private var shown: (mark: Mark, given: InkHand?, hand: InkHand, markStyle: MarkStyle, inkStyle: MarkStyle)?
    /// The stroke being drawn, while this is the pen, and how many of its points no later event moves.
    private var pen: (stroke: InkHand.Stroke, settled: Int, markStyle: MarkStyle)?
    /// The pen's settled start, laid out once.
    private var settledLine: SettledLine?
    /// The shape as it settles: the line and head drawn now, and while easing, the line it eases from.
    private var shape: InkGel.Shape?
    private var easing: (from: InkHand.Stroke, start: CFTimeInterval, duration: CFTimeInterval)?
    /// The done state's colour, in place of the gel's own.
    private var override: CGColor?
    /// The vertices for `shape` as it is, kept while it holds still: the buffers each pass draws, with
    /// their vertex counts, and the place in points their vertices are laid out from.
    private var built: (halo: [(MTLBuffer, Int)], body: [(MTLBuffer, Int)], origin: CGPoint)?
    /// Something changed since the last drawing: draw at the next tick, whatever the clock's rate.
    private(set) var needsGel = false
    /// The centre line as drawn, for the thinking light and drawing on.
    var centreLine: CGPath? {
        guard let shape else { return nil }
        let line = CGMutablePath()
        line.addLines(between: shape.stroke.points)
        return line
    }
    /// The widest the line is, in points.
    private var widest: CGFloat = 0

    init(scale: CGFloat) {
        super.init()
        anchorPoint = .zero
        contentsScale = scale
        gel.anchorPoint = .zero
        gel.contentsScale = scale
        gel.isOpaque = false
        gel.framebufferOnly = true
        gel.pixelFormat = .bgra8Unorm
        gel.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        gel.maximumDrawableCount = 3
        gel.presentsWithTransaction = true
        gel.device = InkGel.metal?.device
        addSublayer(gel)
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Draws `mark` as `hand` drew it, or evenly with no hand, unless it is drawn already as it is.
    func show(_ mark: Mark, hand: InkHand?, markStyle: MarkStyle) {
        let inkStyle = Self.inkStyle(markStyle)
        if let shown, shown.mark == mark, shown.given == hand, shown.inkStyle == inkStyle { return }
        guard let drawing = hand ?? InkHand.even(for: mark, markStyle: inkStyle, feel: Settings.shared.data.ui.inkHandFeel) else { return }
        shown = (mark, hand, drawing, markStyle, inkStyle)
        pen = nil
        settledLine = nil
        easing = nil
        lay(InkHand.Stroke(points: drawing.points(of: mark, markStyle: inkStyle), widths: drawing.widths),
            head: InkGel.corners(of: mark.shape(pointScale: 1, markStyle: inkStyle)?.filled), width: inkStyle.strokeWidth, growOnly: false)
    }

    /// The stroke being drawn, its end at the pen, its first `settled` points where no later event
    /// moves them. It draws at once, in the pointer's own event.
    func showPen(_ stroke: InkHand.Stroke, settled: Int, markStyle: MarkStyle) {
        shown = nil
        easing = nil
        // A new stroke starts the layer afresh; one under way only grows it.
        let growing = stroke.points.count > 3 && pen.map { $0.stroke.points.first == stroke.points.first && settled >= $0.settled } ?? false
        if !growing { settledLine = nil }
        let covered = growing ? max(0, (pen?.settled ?? 0) - 8) : 0
        pen = (stroke, settled, markStyle)
        lay(stroke, head: [], width: Self.inkStyle(markStyle).strokeWidth, growOnly: growing, from: covered)
        if isVisible, let frame = encode(at: CACurrentMediaTime(), time: InkClock.shared.time) {
            frame.commands.commit()
            frame.commands.waitUntilScheduled()
            frame.drawable.present()
        }
    }

    /// A copy in `markStyle`'s person colour, as the done state's green.
    func twin(in markStyle: MarkStyle) -> InkMarkLayer {
        let twin = InkMarkLayer(scale: contentsScale)
        twin.override = markStyle.color(.person)
        if let shown { twin.show(shown.mark, hand: shown.hand, markStyle: markStyle) }
        return twin
    }

    /// Eases from where the hand drew it onto its shape over `duration`, keeping the hand's widths,
    /// its head coming in as it arrives.
    func ease(from drawn: InkHand.Stroke, duration: CFTimeInterval) {
        guard let shape, duration > 0, drawn.points.count == shape.stroke.points.count else { return }
        easing = (drawn, CACurrentMediaTime(), duration)
        // The layer covers both ends of the ease, so it is not resized while it runs.
        fit(covering: [shape.stroke, drawn], growOnly: false)
        built = nil
        needsGel = true
        InkClock.shared.wake()
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
        // Wide enough for the glow, and round its end for the head.
        reveal.lineWidth = widest + 2 * Self.reach + 8
        reveal.lineCap = .round
        reveal.lineJoin = .round
        mask = reveal
        return reveal
    }

    // MARK: Drawing

    /// The tweaks changed: lay the line out again in case its width changed, and draw it.
    func settingsChanged() {
        if let shown {
            self.shown = nil
            show(shown.mark, hand: shown.given, markStyle: shown.markStyle)
        } else if let pen {
            settledLine = nil
            showPen(pen.stroke, settled: pen.settled, markStyle: pen.markStyle)
        }
        built = nil
        needsGel = true
        InkClock.shared.wake()
    }

    /// Lays out `stroke`. A layer that only grows covers its points from `from` on, since it covered
    /// the ones before already.
    private func lay(_ stroke: InkHand.Stroke, head: [CGPoint], width: CGFloat, growOnly: Bool, from: Int = 0) {
        shape = InkGel.Shape(stroke: stroke, width: width, head: head)
        let new = InkHand.Stroke(points: Array(stroke.points[min(from, stroke.points.count)...]),
                                 widths: Array(stroke.widths[min(from, stroke.widths.count)...]))
        widest = max(growOnly ? widest : 0, (new.widths.max() ?? 1) * width)
        fit(covering: [new], growOnly: growOnly)
        built = nil
        needsGel = true
        InkClock.shared.add(self)
    }

    /// Sizes the Metal layer to cover `strokes`, their heads and the glow. The pen's layer only grows,
    /// in steps, so its drawables are not made again at every pointer event.
    private func fit(covering strokes: [InkHand.Stroke], growOnly: Bool) {
        let points = strokes.flatMap(\.points) + (shape?.head ?? [])
        guard let first = points.first else { return }
        var box = points.reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
        let margin = widest + Self.reach + 4
        box = box.insetBy(dx: -margin, dy: -margin)
        if growOnly {
            if gel.frame.contains(box) { return }
            box = box.union(gel.frame.isEmpty ? box : gel.frame)
            let step = Self.growStep
            box = CGRect(x: (box.minX / step).rounded(.down) * step, y: (box.minY / step).rounded(.down) * step,
                         width: ((box.maxX / step).rounded(.up) - (box.minX / step).rounded(.down)) * step,
                         height: ((box.maxY / step).rounded(.up) - (box.minY / step).rounded(.down)) * step)
        } else {
            box = box.integral
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gel.frame = box
        gel.drawableSize = CGSize(width: box.width * contentsScale, height: box.height * contentsScale)
        CATransaction.commit()
    }

    /// Whether it eases at `now`, and so must draw every frame.
    func isEasing(at now: CFTimeInterval) -> Bool {
        guard let easing else { return false }
        if now - easing.start < easing.duration { return true }
        // One more drawing, exactly on its shape.
        self.easing = nil
        built = nil
        needsGel = true
        return false
    }

    /// In a layer tree, with nothing over it hidden or faded out.
    var isVisible: Bool {
        var layer: CALayer? = self
        while let current = layer {
            if current.isHidden || current.opacity <= 0 { return false }
            if current.superlayer == nil { return current !== self }
            layer = current.superlayer
        }
        return false
    }

    /// Encodes a drawing of the gel at `now`, its material at `time`, for the clock to commit and
    /// present with the others.
    func encode(at now: CFTimeInterval, time: CFTimeInterval) -> (commands: MTLCommandBuffer, drawable: CAMetalDrawable)? {
        guard let metal = InkGel.metal, var shape, gel.bounds.width > 0, gel.bounds.height > 0 else { return nil }
        needsGel = false
        var headOpacity: CGFloat = 1
        if let easing {
            let t = Self.curve(min(max((now - easing.start) / easing.duration, 0), 1))
            let to = shape.stroke
            shape.stroke = InkHand.Stroke(points: zip(easing.from.points, to.points).map { a, b in
                CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }, widths: zip(easing.from.widths, to.widths).map { $0 + ($1 - $0) * t })
            headOpacity = t * t
            built = nil
        }
        let ui = Settings.shared.data.ui
        if built == nil { built = build(shape, device: metal.device) }
        let place = onScreen(gel.frame)
        let backdrop = place.map { InkBackdrop.shared.reading(for: $0, at: now) } ?? InkBackdrop.Reading(now: nil, before: nil, fade: 1)
        guard let built, let maps = InkBackdrop.shared.textures(for: backdrop), let drawable = gel.nextDrawable(),
              let commands = metal.queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        var uniforms = InkGel.uniforms(ui, gel: place ?? gel.frame, size: gel.drawableSize, scale: contentsScale, time: time, override: override,
                                       headOpacity: headOpacity, backdrop: backdrop)
        uniforms.offset = SIMD4(Float((gel.frame.minX - built.origin.x) * contentsScale), Float((gel.frame.minY - built.origin.y) * contentsScale), 0, 0)
        encoder.setFragmentTexture(maps.now, index: 0)
        encoder.setFragmentTexture(maps.before, index: 1)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<InkGel.Uniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<InkGel.Uniforms>.stride, index: 1)
        for (pipeline, draws) in [(metal.halo, built.halo), (metal.body, built.body)] {
            encoder.setRenderPipelineState(pipeline)
            for (buffer, count) in draws where count > 0 {
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
            }
        }
        encoder.endEncoding()
        return (commands, drawable)
    }

    /// The vertices of `shape`. The pen's settled start is laid out once, from this layer's own origin,
    /// and only its end is laid out again; anything else is laid out whole from the gel's corner.
    private func build(_ shape: InkGel.Shape, device: MTLDevice) -> (halo: [(MTLBuffer, Int)], body: [(MTLBuffer, Int)], origin: CGPoint)? {
        func buffers(_ vertices: InkGel.Vertices) -> (halo: (MTLBuffer, Int)?, body: (MTLBuffer, Int)?) {
            func one(_ floats: [Float]) -> (MTLBuffer, Int)? {
                guard !floats.isEmpty, let buffer = device.makeBuffer(bytes: floats, length: floats.count * MemoryLayout<Float>.stride) else { return nil }
                return (buffer, floats.count / 10)
            }
            return (one(vertices.halo), one(vertices.body))
        }
        guard let pen, easing == nil else {
            let whole = buffers(InkGel.Builder(width: shape.width, origin: gel.frame.origin, scale: contentsScale, reach: Self.reach).vertices(shape))
            return ([whole.halo].compactMap { $0 }, [whole.body].compactMap { $0 }, gel.frame.origin)
        }
        let builder = InkGel.Builder(width: shape.width, origin: .zero, scale: contentsScale, reach: Self.reach)
        if settledLine.map({ $0.builder.width != builder.width || $0.builder.reach != builder.reach || $0.builder.scale != builder.scale }) ?? true {
            settledLine = SettledLine(builder: builder)
        }
        guard let line = settledLine else { return nil }
        line.extend(shape.stroke, settled: pen.settled, device: device)
        let end = builder.segments(shape.stroke, line.segments..<max(shape.stroke.points.count - 1, line.segments), startLength: line.length)
        var unsettled = builder.ends(of: shape.stroke, length: end.endLength, hasHead: false)
        unsettled.append(end.vertices)
        let fresh = buffers(unsettled)
        let halo = [line.halo.buffer.map { ($0, line.halo.vertexCount) }, fresh.halo].compactMap { $0 }
        let body = [line.body.buffer.map { ($0, line.body.vertexCount) }, fresh.body].compactMap { $0 }
        return (halo, body, .zero)
    }

    /// `rect`, in this layer's points, in global top-left points. A mark is drawn in its window's
    /// overlay or the screen's, inside that overlay's content view, so the window is the one whose
    /// content view's layer shares this layer's root.
    private func onScreen(_ rect: CGRect) -> CGRect? {
        func root(of layer: CALayer) -> CALayer {
            var root = layer
            while let up = root.superlayer { root = up }
            return root
        }
        let mine = root(of: self)
        guard let view = NSApp.windows.lazy.compactMap(\.contentView).first(where: { $0.layer.map(root) === mine }),
              let layer = view.layer, let window = view.window else { return nil }
        // The content views are flipped, so their layers run y down from the window's top-left.
        let inView = convert(rect, to: layer)
        return inView.offsetBy(dx: window.frame.minX, dy: StateReport.primaryHeight - window.frame.maxY)
    }

    /// The style its line is laid out in: the mark's, at the gel's width.
    private static func inkStyle(_ markStyle: MarkStyle) -> MarkStyle {
        var style = markStyle
        style.strokeWidth = Settings.shared.data.ui.inkGelWidth
        return style
    }

    /// How far the glow reaches past the line, in points.
    private static var reach: CGFloat { Settings.shared.data.ui.inkGelGlowRadius * 2 }

    /// The pen's layer grows in steps of this many points.
    private static let growStep: CGFloat = 64

    /// The ease's curve, `CAMediaTimingFunction(controlPoints: 0.3, 0, 0.2, 1)`, at time fraction `x`.
    private static func curve(_ x: CGFloat) -> CGFloat {
        var lo: CGFloat = 0, hi: CGFloat = 1, t = x
        for _ in 0..<24 {
            t = (lo + hi) / 2
            let bx = 3 * (1 - t) * (1 - t) * t * 0.3 + 3 * (1 - t) * t * t * 0.2 + t * t * t
            if bx < x { lo = t } else { hi = t }
        }
        return 3 * (1 - t) * t * t + t * t * t
    }
}
