import AppKit
import QuartzCore

/// An agent's rectangle, ellipse or arrow on the live screen, drawn as light rather than ink: a core
/// brightest along its middle, a bloom round it, and while it draws itself on, a glint at its head.
/// After drawing on, the bloom settles. The person's marks stay ink (`InkMarkLayer`), so the
/// material says who drew a mark as well as the colour does (docs/live-ink-look-2026-10-07.md).
///
/// Light cannot be added to the screen behind the overlay, so over a light window the light turns
/// round: the core darkens towards its edges and the bloom tints what is behind it.
@MainActor
final class LightMarkLayer {
    let root = CALayer()
    /// The bloom, a tight glow and a wide one: each a copy of the shape that only its shadow shows,
    /// under the core.
    private let blooms: [(container: CALayer, stroke: CAShapeLayer, fill: CAShapeLayer)]
    /// The core, outermost first, each narrower and nearer the light's own colour.
    private let core: [(stroke: CAShapeLayer, fill: CAShapeLayer)]
    private let glint = CAShapeLayer()
    private var shown: (mark: Mark, markStyle: MarkStyle, dark: Bool, look: Look)?
    /// The stroked path's length in points, for the glint's.
    private var length: CGFloat = 0
    /// Whether the light is drawn for a dark window behind it.
    private var dark = false

    init(scale: CGFloat) {
        core = Self.coreWidths.map { _ in (CAShapeLayer(), CAShapeLayer()) }
        blooms = Self.glows(dark: true, look: Look()).map { _ in (CALayer(), CAShapeLayer(), CAShapeLayer()) }
        root.anchorPoint = .zero
        for bloom in blooms {
            bloom.container.anchorPoint = .zero
            bloom.container.addSublayer(bloom.stroke)
            bloom.container.addSublayer(bloom.fill)
            bloom.container.contentsScale = scale
            bloom.container.shadowOffset = .zero
            root.addSublayer(bloom.container)
        }
        for layers in core {
            root.addSublayer(layers.stroke)
            root.addSublayer(layers.fill)
        }
        root.addSublayer(glint)
        glint.opacity = 0
        for shape in shapeLayers {
            shape.anchorPoint = .zero
            shape.lineCap = .round
            shape.lineJoin = .round
            shape.contentsScale = scale
        }
        glint.shadowOffset = .zero
    }

    private var strokes: [CAShapeLayer] { blooms.map(\.stroke) + core.map(\.stroke) }
    private var fills: [CAShapeLayer] { blooms.map(\.fill) + core.map(\.fill) }
    private var shapeLayers: [CAShapeLayer] { [glint] + strokes + fills }

    /// Draws `mark` in the light of its colour, for a dark or a light window behind it, unless it is
    /// drawn already as it is.
    func show(_ mark: Mark, markStyle: MarkStyle, dark: Bool) {
        let look = Look(Settings.shared.motionUI)
        if let shown, shown.mark == mark, shown.markStyle == markStyle, shown.dark == dark, shown.look == look { return }
        guard let shape = mark.shape(pointScale: 1, markStyle: markStyle) else { return }
        shown = (mark, markStyle, dark, look)
        self.dark = dark
        let tint = markStyle.color(mark.color)
        let width = shape.lineWidth
        length = shape.stroked?.length ?? 0
        for (bloom, glow) in zip(blooms, Self.glows(dark: dark, look: look)) {
            bloom.stroke.path = shape.stroked
            bloom.stroke.lineWidth = width
            bloom.stroke.strokeColor = tint
            bloom.stroke.fillColor = nil
            bloom.fill.path = shape.filled
            bloom.fill.fillColor = tint
            bloom.fill.strokeColor = nil
            bloom.container.shadowColor = tint.mixed(with: .white, glow.whiten)
            bloom.container.shadowRadius = glow.radius
            bloom.container.shadowOpacity = glow.settled
        }
        let centre = shape.filled.flatMap(Self.centroid(of:))
        for ((layers, fraction), colour) in zip(zip(core, Self.coreWidths), Self.coreColours(tint, dark: dark, white: look.coreWhite)) {
            layers.stroke.path = shape.stroked
            layers.stroke.lineWidth = width * fraction
            layers.stroke.strokeColor = colour
            layers.stroke.fillColor = nil
            // The arrowhead's core is the head drawn smaller about its middle, as the stroke's is narrower.
            if let head = shape.filled, let centre {
                var inward = CGAffineTransform(translationX: centre.x, y: centre.y).scaledBy(x: fraction, y: fraction)
                    .translatedBy(x: -centre.x, y: -centre.y)
                layers.fill.path = head.copy(using: &inward)
            } else {
                layers.fill.path = shape.filled
            }
            layers.fill.fillColor = colour
            layers.fill.strokeColor = nil
        }
        glint.path = shape.stroked
        glint.fillColor = nil
        glint.strokeColor = CGColor(gray: 1, alpha: dark ? 1 : 0.7)
        glint.lineWidth = dark ? width * 1.1 : width * 0.5
        glint.shadowColor = CGColor(gray: 1, alpha: 1)
        glint.shadowRadius = dark ? 5 : 0
        glint.shadowOpacity = dark ? 0.9 : 0
    }

    /// Draws itself on after `delay`, on the curve `ShapeMarkLayer.drawOn` uses: the core and the
    /// bloom grow from the start over `duration` with the glint at their head, the arrowhead appears
    /// as they reach it, and then the glint goes and the bloom settles over `settle`.
    func drawOn(after delay: CFTimeInterval, duration: CFTimeInterval, settle: CFTimeInterval) {
        guard duration > 0 else { return }
        let begin = CACurrentMediaTime() + delay
        let look = shown?.look ?? Look()
        let curve = CAMediaTimingFunction(controlPoints: 0.3, 0, 0.2, 1)
        func animate(_ layer: CALayer, _ key: String, from: Any, to: Any, at start: CFTimeInterval, for time: CFTimeInterval,
                     curve timing: CAMediaTimingFunction = curve) {
            let animation = CABasicAnimation(keyPath: key)
            animation.fromValue = from
            animation.toValue = to
            animation.beginTime = start
            animation.duration = time
            animation.timingFunction = timing
            animation.fillMode = .backwards
            layer.add(animation, forKey: "drawOn-\(key)")
        }
        for layer in strokes {
            animate(layer, "strokeEnd", from: 0, to: 1, at: begin, for: duration)
        }
        for layer in fills {
            animate(layer, "opacity", from: 0, to: 1, at: begin + duration * 0.85, for: duration * 0.25, curve: CAMediaTimingFunction(name: .linear))
        }
        for (bloom, glow) in zip(blooms, Self.glows(dark: dark, look: look)) {
            animate(bloom.container, "shadowOpacity", from: glow.drawing, to: glow.settled, at: begin + duration, for: max(settle, 0.01),
                    curve: CAMediaTimingFunction(name: .easeInEaseOut))
        }
        guard length > 0 else { return }
        // The glint is a short piece of the path that runs with the head: its end is the head, and
        // its start trails by its length, clamped at the path's start.
        let trail = min(look.glintLength / length, 1)
        animate(glint, "strokeEnd", from: 0, to: 1, at: begin, for: duration)
        animate(glint, "strokeStart", from: -trail, to: 1 - trail, at: begin, for: duration)
        let shine = CAKeyframeAnimation(keyPath: "opacity")
        let gone = duration + look.glintFade
        shine.values = [1, 1, 0]
        shine.keyTimes = [0, NSNumber(value: duration / gone), 1]
        shine.beginTime = begin
        shine.duration = gone
        shine.fillMode = .backwards
        glint.add(shine, forKey: "drawOn-opacity")
    }

    /// The core's strokes, each a fraction of the mark's width, outermost first.
    private static let coreWidths: [CGFloat] = [1, 0.7, 0.4]

    /// The core's colours, outermost first. Over a dark window the middle is white and the edge
    /// the light's colour, paled; over a light one the edge darkens and the middle stays the colour.
    private static func coreColours(_ tint: CGColor, dark: Bool, white: CGFloat) -> [CGColor] {
        dark ? [tint.mixed(with: .white, 0.4 * white), tint.mixed(with: .white, white), .white]
             : [tint.mixed(with: .black, 0.25), tint.mixed(with: .black, 0.1), tint.mixed(with: .white, 0.1)]
    }

    /// One layer of the bloom: how far its shadow spreads, in points, how much white is in its
    /// colour, and its opacity while drawing on and once settled.
    private struct Glow {
        let radius: CGFloat
        let whiten: CGFloat
        let drawing: Float
        let settled: Float
    }

    /// The tight glow, then the wide one. Over a light window they tint it rather than light it, and
    /// reach two thirds as far for the tight one and five ninths for the wide one.
    private static func glows(dark: Bool, look: Look) -> [Glow] {
        func glow(_ radius: CGFloat, _ whiten: CGFloat, _ drawing: Float, _ settled: Float, _ scale: Float) -> Glow {
            Glow(radius: radius, whiten: whiten, drawing: min(drawing * look.drawing * scale, 1), settled: min(settled * look.strength * scale, 1))
        }
        return dark ? [glow(look.tight, 0.45, 1, 0.8, 1), glow(look.wide, 0.15, 1, 0.6, 1)]
                    : [glow(look.tight * 2 / 3, 0, 0.25, 0.12, look.overLight), glow(look.wide * 5 / 9, 0, 0.35, 0.2, look.overLight)]
    }

    /// The tweaks the light is drawn with: the tweak panel's Answer light section.
    struct Look: Equatable {
        var tight: CGFloat = 3
        var wide: CGFloat = 9
        var strength: Float = 1
        var drawing: Float = 1
        var overLight: Float = 1
        var coreWhite: CGFloat = 0.75
        /// The glint's length along the path, in points, and how long it takes to go once drawn on.
        var glintLength: CGFloat = 26
        var glintFade: CFTimeInterval = 0.15

        init() {}

        init(_ ui: UITweaks) {
            tight = ui.lightGlow; wide = ui.lightGlowWide
            strength = Float(ui.lightGlowStrength); drawing = Float(ui.lightGlowDrawing); overLight = Float(ui.lightOverLight)
            coreWhite = ui.lightCoreWhite; glintLength = ui.lightGlintLength; glintFade = ui.lightGlintFade
        }
    }

    /// The mean of a path's points: inside a filled arrowhead, which is convex.
    private static func centroid(of path: CGPath) -> CGPoint? {
        var sum = CGPoint.zero, count = 0
        path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint:
                sum.x += points[0].x; sum.y += points[0].y; count += 1
            default:
                break
            }
        }
        return count > 0 ? CGPoint(x: sum.x / CGFloat(count), y: sum.y / CGFloat(count)) : nil
    }
}

extension CGColor {
    /// This colour moved `amount` of the way to `other` in sRGB, opaque.
    func mixed(with other: CGColor, _ amount: CGFloat) -> CGColor {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let a = converted(to: space, intent: .defaultIntent, options: nil)?.components,
              let b = other.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              a.count >= 3, b.count >= 3 else { return self }
        return CGColor(srgbRed: a[0] + (b[0] - a[0]) * amount, green: a[1] + (b[1] - a[1]) * amount,
                       blue: a[2] + (b[2] - a[2]) * amount, alpha: 1)
    }
}

extension CGPath {
    /// The path's length, its curves measured as chords.
    var length: CGFloat {
        var total: CGFloat = 0, current = CGPoint.zero, start = CGPoint.zero
        func walk(_ point: (CGFloat) -> CGPoint) {
            var last = current
            for step in 1...12 {
                let next = point(CGFloat(step) / 12)
                total += hypot(next.x - last.x, next.y - last.y)
                last = next
            }
            current = last
        }
        applyWithBlock { element in
            let p = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                current = p[0]; start = p[0]
            case .addLineToPoint:
                total += hypot(p[0].x - current.x, p[0].y - current.y); current = p[0]
            case .addQuadCurveToPoint:
                let a = current, c = p[0], b = p[1]
                walk { t in
                    let u = 1 - t
                    let wa: CGFloat = u * u, wc: CGFloat = 2 * u * t, wb: CGFloat = t * t
                    return CGPoint(x: wa * a.x + wc * c.x + wb * b.x, y: wa * a.y + wc * c.y + wb * b.y)
                }
            case .addCurveToPoint:
                let a = current, c1 = p[0], c2 = p[1], b = p[2]
                walk { t in
                    let u = 1 - t
                    let wa: CGFloat = u * u * u, w1: CGFloat = 3 * u * u * t, w2: CGFloat = 3 * u * t * t, wb: CGFloat = t * t * t
                    let x: CGFloat = wa * a.x + w1 * c1.x + w2 * c2.x + wb * b.x
                    let y: CGFloat = wa * a.y + w1 * c1.y + w2 * c2.y + wb * b.y
                    return CGPoint(x: x, y: y)
                }
            case .closeSubpath:
                total += hypot(start.x - current.x, start.y - current.y); current = start
            @unknown default:
                break
            }
        }
        return total
    }
}
