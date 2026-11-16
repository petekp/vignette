import QuartzCore

/// The thinking light on one stroke: a band of light `Look.length` long that runs along it once a
/// beat. On an open stroke it runs from start to end, starting and finishing `runUp` off the stroke so
/// each pass ends in a short rest. On a loop it laps the loop with no rest: the loop is cut to one turn
/// where the line comes back to its start, closed, and laid twice end to end, and the band crosses
/// from the first turn into the second, so its jump back at each beat lands where it already is. The
/// band is nested strokes, each shorter one wider and laid over the longer, so it is brightest and
/// widest at its middle and fades and narrows towards its ends, in a glow.
final class ThinkingBand: CALayer {
    /// How it looks, from the tweaks: its opacity, its length and its middle's width in points, and
    /// its glow's radius.
    struct Look: Equatable {
        var brightness: CGFloat
        var length: CGFloat
        var width: CGFloat
        var glow: CGFloat

        init(_ ui: UITweaks, lineWidth: CGFloat) {
            brightness = CGFloat(ui.thinkingBrightness)
            length = CGFloat(ui.thinkingLength)
            width = lineWidth * CGFloat(ui.thinkingWidth)
            glow = CGFloat(ui.thinkingGlow)
        }
    }

    let look: Look

    init(along path: CGPath, loops: Bool, look: Look, scale: CGFloat, still: Bool) {
        self.look = look
        super.init()
        anchorPoint = .zero
        contentsScale = scale
        shadowColor = CGColor(gray: 1, alpha: 1)
        shadowOffset = .zero
        shadowRadius = look.glow
        shadowOpacity = 0.9
        opacity = Float(look.brightness * (still ? Self.still : 1))
        let loop = loops ? Self.oneTurn(of: path) : nil
        let laid = loop.map { Self.twice($0.points) } ?? path
        // Fractions of the laid path where each stroke's middle starts and ends a beat, and the band's length.
        let middle: (from: CGFloat, to: CGFloat), bandLength: CGFloat
        let laidLength: CGFloat
        if let loop {
            laidLength = 2 * loop.length
            bandLength = min(look.length, loop.length * Self.mostOfLoop)
            middle = (bandLength / 2 / laidLength, 0.5 + bandLength / 2 / laidLength)
        } else {
            laidLength = max(path.length, 1)
            bandLength = look.length
            let runUp = (Self.runUp + bandLength / 2) / laidLength
            middle = (-runUp, 1 + runUp)
        }
        for (share, widthShare) in Self.layers {
            let stroke = CAShapeLayer()
            stroke.anchorPoint = .zero
            stroke.contentsScale = scale
            stroke.path = laid
            stroke.fillColor = nil
            stroke.strokeColor = CGColor(gray: 1, alpha: Self.strokeAlpha)
            stroke.lineWidth = max(look.width * widthShare, 0.5)
            stroke.lineCap = .round
            stroke.lineJoin = .round
            addSublayer(stroke)
            guard !still else {
                // The whole line brightens: one turn of a loop, so the two turns are not laid over each other.
                if loop != nil { stroke.strokeEnd = 0.5 }
                continue
            }
            // Core Animation clamps the ends to the line, so on an open stroke the band grows in at the
            // start and shrinks away at the end.
            let half = bandLength * share / 2 / laidLength
            let end = CABasicAnimation(keyPath: "strokeEnd")
            end.fromValue = middle.from + half
            end.toValue = middle.to + half
            let start = CABasicAnimation(keyPath: "strokeStart")
            start.fromValue = middle.from - half
            start.toValue = middle.to - half
            let run = CAAnimationGroup()
            run.animations = [end, start]
            run.duration = LiveMarksLayer.thinkingPeriod
            run.repeatCount = .infinity
            run.beginTime = convertTime(LiveMarksLayer.thinkingEpoch, from: nil)
            stroke.add(run, forKey: "think")
        }
    }

    override init(layer: Any) {
        look = (layer as? ThinkingBand)?.look ?? Look(UITweaks(), lineWidth: 1)
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// `path`'s points up to where it comes back nearest its start, past halfway, and the length of
    /// that turn closed. A hand's loop overshoots its start or stops short of it, and live ink draws
    /// a loop past its start (`InkHand.init(raw:mark:feel:)`).
    private static func oneTurn(of path: CGPath) -> (points: [CGPoint], length: CGFloat)? {
        var points: [CGPoint] = []
        path.flattened(threshold: 0.5).applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint: points.append(element.pointee.points[0])
            default: break
            }
        }
        guard points.count > 3, let first = points.first else { return nil }
        let distance = { (a: CGPoint, b: CGPoint) in hypot(a.x - b.x, a.y - b.y) }
        var along: [CGFloat] = [0]
        for index in points.indices.dropFirst() { along.append(along[index - 1] + distance(points[index - 1], points[index])) }
        let halfway = along.last! / 2
        guard let back = points.indices.filter({ along[$0] >= halfway }).min(by: { distance(points[$0], first) < distance(points[$1], first) })
        else { return nil }
        let turn = Array(points[...back])
        let length = along[back] + distance(points[back], first)
        guard length > 1 else { return nil }
        return (turn, length)
    }

    /// The closed turn through `points`, twice over, as one line.
    private static func twice(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points + [points[0]] + points + [points[0]])
        return path
    }

    /// The nested strokes, longest first: each one's length and width as shares of the band's.
    private static let layers: [(length: CGFloat, width: CGFloat)] = [(1, 0.55), (0.75, 0.7), (0.5, 0.85), (0.25, 1)]
    /// Each stroke's opacity. Four laid over each other make 0.82 at the band's middle.
    private static let strokeAlpha: CGFloat = 0.35
    private static let runUp: CGFloat = 40
    /// The longest a band on a loop may be, as a share of the loop, so a small loop still shows where
    /// the band is.
    private static let mostOfLoop: CGFloat = 0.5
    /// The band's opacity while it holds, with motion off, as a share of its brightness.
    private static let still: CGFloat = 0.35
}

/// The thinking light on a note: a sheen that crosses its tag a third of a beat after the band on
/// the ink, masked by the note's own picture so only the tag catches it.
final class NoteSheen: CAGradientLayer {
    init(over note: NoteLayer, still: Bool) {
        super.init()
        frame = note.bounds
        contentsScale = note.contentsScale
        let tag = CALayer()
        tag.frame = bounds
        tag.contents = note.contents
        tag.contentsScale = note.contentsScale
        mask = tag
        startPoint = CGPoint(x: 0, y: 0.3)
        endPoint = CGPoint(x: 1, y: 0.7)
        guard !still else {
            colors = [CGColor(gray: 1, alpha: 0.15), CGColor(gray: 1, alpha: 0.15)]
            return
        }
        let clear = CGColor(gray: 1, alpha: 0), lit = CGColor(gray: 1, alpha: 0.42)
        colors = [clear, lit, clear]
        locations = [-0.3, -0.15, 0]
        let sweep = CABasicAnimation(keyPath: "locations")
        sweep.fromValue = [-0.3, -0.15, 0]
        sweep.toValue = [1, 1.15, 1.3]
        sweep.duration = LiveMarksLayer.thinkingPeriod
        sweep.repeatCount = .infinity
        sweep.beginTime = convertTime(LiveMarksLayer.thinkingEpoch, from: nil)
        // Two thirds of a beat ahead is a third behind: the sheen follows the band.
        sweep.timeOffset = LiveMarksLayer.thinkingPeriod * 0.65
        add(sweep, forKey: "think")
    }

    override init(layer: Any) { super.init(layer: layer) }

    required init?(coder: NSCoder) { fatalError("not used") }
}
