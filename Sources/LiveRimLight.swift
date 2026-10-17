import AppKit
import QuartzCore

/// The thinking light on a popover: a soft light that runs round the rim of its body, starting at the
/// arrow, while the agent works. A lap takes two beats of the light on the ink (`thinkingEpoch`,
/// `thinkingPeriod`), so it leaves the arrow as the band on the ink starts a stroke, and two popovers
/// lit at once show it in the same place, which is what lets the note hand over to its conversation
/// unseen. It is a blob of light moving along the rim at an even pace, seen only through a thin ring
/// at the edge and, fainter, through a wider one for its glow. White on a dark popover, the ink's ice
/// blue (`ui.inkGelLight`) on a light one, where white would not show. With motion off the ring glows dimly and holds.
@MainActor
final class RimLight: CALayer {
    private var lit = false
    private var shape: (bounds: CGRect, start: CGPoint)?
    private var dark = false

    override init() {
        super.init()
        opacity = 0
    }

    override init(layer: Any) { super.init(layer: layer) }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// The popover body's corner radius on macOS 15, in points (measured).
    static let cornerRadius: CGFloat = 10
    /// How long the light takes to go round, in beats of the ink's light.
    static let beatsPerLap: Double = 2
    /// How wide the light is along the rim, in points.
    private static let blob: CGFloat = 96
    /// The ring's opacity while it holds, with motion off.
    private static let still: Float = 0.35

    /// Lays the rim round `bounds`, in its superlayer's coordinates, starting at `start`, the point on
    /// the body's edge under the arrow. `dark` says the popover draws dark.
    func place(_ bounds: CGRect, start: CGPoint, dark: Bool) {
        guard shape?.bounds != bounds || shape?.start != start || self.dark != dark else { return }
        shape = (bounds, start)
        self.dark = dark
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = bounds
        build()
        CATransaction.commit()
    }

    /// Turns the light on or off, fading as the light on the ink does, or at once with `fades` off,
    /// for a popover that comes up lit, taking over from one that was.
    func think(_ on: Bool, fades: Bool = true) {
        guard on != lit else { return }
        lit = on
        let fade = fades ? LiveMarksLayer.thinkingFade * Settings.shared.motionScale : 0
        let target: Float = on ? (Settings.shared.motionScale == 0 ? Self.still : 1) : 0
        if on { build() }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let from = presentation()?.opacity ?? opacity
        opacity = target
        if fade > 0 {
            let change = CABasicAnimation(keyPath: "opacity")
            change.fromValue = from
            change.toValue = target
            change.duration = fade
            add(change, forKey: "fade")
        }
        CATransaction.commit()
    }

    private func build() {
        sublayers?.forEach { $0.removeFromSuperlayer() }
        guard lit, let shape else { return }
        let local = CGRect(origin: .zero, size: shape.bounds.size)
        let start = CGPoint(x: shape.start.x - shape.bounds.minX, y: shape.start.y - shape.bounds.minY)
        let path = Self.rim(local.insetBy(dx: 0.75, dy: 0.75), radius: Self.cornerRadius - 0.75, from: start)
        let ice = SRGB(hex: Settings.shared.data.ui.inkGelLight)?.cgColor ?? InkGel.defaultIce
        let color = dark ? NSColor.white : NSColor(cgColor: ice) ?? .systemBlue
        let still = Settings.shared.motionScale == 0
        for (lineWidth, strength, blur) in [(1.6 as CGFloat, 1.0 as CGFloat, 0 as CGFloat), (7, 0.45, 3)] {
            let light = CALayer()
            light.frame = local
            let ring = CAShapeLayer()
            ring.frame = local
            ring.path = path
            ring.fillColor = nil
            ring.strokeColor = CGColor(gray: 0, alpha: 1)
            ring.lineWidth = lineWidth
            if blur > 0 {
                ring.shadowColor = CGColor(gray: 0, alpha: 1)
                ring.shadowRadius = blur
                ring.shadowOpacity = 1
                ring.shadowOffset = .zero
            }
            light.mask = ring
            if still {
                light.backgroundColor = color.withAlphaComponent(strength).cgColor
            } else {
                let dot = CAGradientLayer()
                dot.type = .radial
                dot.colors = [strength, strength * 0.5, 0].map { color.withAlphaComponent($0).cgColor }
                dot.locations = [0, 0.35, 1]
                dot.startPoint = CGPoint(x: 0.5, y: 0.5)
                dot.endPoint = CGPoint(x: 1, y: 1)
                dot.bounds = CGRect(x: 0, y: 0, width: Self.blob, height: Self.blob)
                dot.position = start
                let travel = CAKeyframeAnimation(keyPath: "position")
                travel.path = path
                travel.calculationMode = .paced
                travel.duration = LiveMarksLayer.thinkingPeriod * Self.beatsPerLap
                travel.repeatCount = .infinity
                travel.beginTime = dot.convertTime(LiveMarksLayer.thinkingEpoch, from: nil)
                dot.add(travel, forKey: "travel")
                light.addSublayer(dot)
            }
            addSublayer(light)
        }
    }

    /// Where on a popover's `body` the light starts: the point on its edge under the arrow, which
    /// points at `at` from `edge`, both in global top-left points, in the body's own coordinates with
    /// y growing downwards.
    nonisolated static func start(of body: CGRect, hungFrom at: CGRect, edge: PopoverPlace.Edge) -> CGPoint {
        switch edge {
        case .below: CGPoint(x: at.midX - body.minX, y: 0)
        case .above: CGPoint(x: at.midX - body.minX, y: body.height)
        case .right: CGPoint(x: 0, y: at.midY - body.minY)
        case .left: CGPoint(x: body.width, y: at.midY - body.minY)
        }
    }

    /// The edge of a rounded `rect` as one closed path that starts at `start`, the point on its edge
    /// nearest it, and runs clockwise as the screen shows it, in coordinates whose y grows downwards.
    nonisolated static func rim(_ rect: CGRect, radius: CGFloat, from start: CGPoint) -> CGPath {
        let r = min(radius, rect.width / 2, rect.height / 2)
        let x = min(max(start.x, rect.minX + r), rect.maxX - r)
        let y = min(max(start.y, rect.minY + r), rect.maxY - r)
        // The side nearest the start, and the start on it.
        let distances = [start.y - rect.minY, rect.maxX - start.x, rect.maxY - start.y, start.x - rect.minX].map(abs)
        let side = distances.firstIndex(of: distances.min()!)!
        let points = [CGPoint(x: x, y: rect.minY), CGPoint(x: rect.maxX, y: y), CGPoint(x: x, y: rect.maxY), CGPoint(x: rect.minX, y: y)]
        // Each side's corner at its clockwise end: top-right, bottom-right, bottom-left, top-left.
        let corners = [CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY),
                       CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.minY)]
        let path = CGMutablePath()
        path.move(to: points[side])
        for step in 0..<4 {
            let corner = corners[(side + step) % 4]
            let next = corners[(side + step + 1) % 4]
            path.addArc(tangent1End: corner, tangent2End: next, radius: r)
        }
        path.addLine(to: points[side])
        path.closeSubpath()
        return path
    }
}
