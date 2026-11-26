import AppKit
import QuartzCore

/// The pins as the editor shows them, in the editor's coordinates, at one size on screen whatever the
/// zoom (`PinPlacement`): the dashed outline of each area that is hovered, selected, being placed or
/// open, then a selection ring round each selected teardrop, then the teardrops and the clusters.
@MainActor
final class EditorPins {
    /// The owner puts this between the picture and the overlay.
    let layer = CALayer()
    private var drops: [Pin.ID: PinLayer] = [:]
    private var clusters: [[Pin.ID]: PinLayer] = [:]
    private var areas: [Pin.ID: AreaOutline] = [:]
    private let selectionEdge = CAShapeLayer(), selectionLine = CAShapeLayer()
    private var scale: CGFloat = 2
    private var shown: Shown?

    struct Shown: Equatable {
        let placement: PinPlacement
        /// The pins whose area's outline shows, and those whose dashes march.
        let outlined: [Pin]
        let marching: Set<Pin.ID>
        let selected: Set<Pin.ID>
        let markStyle: MarkStyle
        let outlineWidth: CGFloat
        /// How fast the dashes march, in screen pt a second, with the motion setting applied: 0 keeps them still.
        let marchSpeed: CGFloat
        let transform: CGAffineTransform
    }

    init() {
        selectionEdge.strokeColor = EditorStyle.lightEdge.cgColor
        selectionLine.strokeColor = EditorStyle.selectionBlue.cgColor
        selectionLine.lineWidth = EditorStyle.outlineWidth
        for outline in [selectionEdge, selectionLine] {
            outline.fillColor = nil
            outline.lineJoin = .round
            outline.lineCap = .round
        }
    }

    func setScale(_ scale: CGFloat) {
        self.scale = scale
        for outline in [selectionEdge, selectionLine] { outline.contentsScale = scale }
        for drop in Array(drops.values) + Array(clusters.values) { drop.setScale(scale) }
        for area in areas.values { area.setScale(scale) }
    }

    /// Shows `what`, unless it is shown already.
    func show(_ what: Shown) {
        guard what != shown else { return }
        shown = what
        let transform = what.transform, zoom = transform.a
        var layers: [CALayer] = []

        let outlined = Set(what.outlined.map(\.id))
        areas = areas.filter { outlined.contains($0.key) }
        for pin in what.outlined {
            guard case .area(let frame, _) = pin.place else { continue }
            let record = areas[pin.id] ?? AreaOutline(scale: scale)
            record.show(frame.applying(transform), color: what.markStyle.painting(pin.maker).color(pin.color), style: what.markStyle.pin,
                        edge: what.markStyle.pin.rimWidth, speed: what.marching.contains(pin.id) ? what.marchSpeed : 0)
            areas[pin.id] = record
            layers.append(record.root)
        }

        let rings = CGMutablePath()
        let teardrops = what.placement.drops.map { drop in
            (drop, PinTeardrop(number: drop.number, agent: drop.agent, tip: drop.tip.applying(transform), orientation: drop.orientation,
                               side: what.placement.side * zoom, style: what.markStyle.pin))
        }
        let reach = 2 * (what.markStyle.pin.rimWidth + what.outlineWidth / 2)
        for (drop, teardrop) in teardrops where what.selected.contains(drop.id) {
            rings.addPath(teardrop.body.copy(strokingWithWidth: reach, lineCap: .round, lineJoin: .round, miterLimit: 1).union(teardrop.body))
        }
        selectionEdge.lineWidth = what.outlineWidth
        selectionEdge.path = rings
        selectionLine.path = rings
        layers += [selectionEdge, selectionLine]

        let kept = Set(teardrops.map(\.0.id))
        drops = drops.filter { kept.contains($0.key) }
        for (drop, teardrop) in teardrops {
            let record = drops[drop.id] ?? PinLayer(scale: scale)
            record.show(teardrop, maker: drop.maker, face: PinFace(drop.maker), answeringAgent: drop.answeringAgent, pointScale: 1,
                        markStyle: what.markStyle)
            drops[drop.id] = record
            layers.append(record.root)
        }

        let grouped = Set(what.placement.clusters.map(\.pins))
        clusters = clusters.filter { grouped.contains($0.key) }
        for cluster in what.placement.clusters {
            let record = clusters[cluster.pins] ?? PinLayer(scale: scale)
            record.show(PinTeardrop(label: cluster.label, agent: cluster.agent, orientation: cluster.orientation,
                                    frame: cluster.frame.applying(transform), style: what.markStyle.pin),
                        maker: cluster.maker, pointScale: 1, markStyle: what.markStyle)
            clusters[cluster.pins] = record
            layers.append(record.root)
        }
        if (layer.sublayers ?? []).map(ObjectIdentifier.init) != layers.map(ObjectIdentifier.init) { layer.sublayers = layers }
    }
}

/// An area's outline in the editor: dashes in the pin's colour inside a white edge as wide as the
/// teardrop's hairline, one width on screen at every zoom. Their phase moves at `speed`, a constant
/// pace that has no target for a spring to settle on.
@MainActor
private final class AreaOutline {
    let root = CALayer()
    private let edge = CAShapeLayer(), line = CAShapeLayer()
    private var march: (speed: CGFloat, period: CGFloat, edge: CGFloat, edgeDashed: Bool) = (0, 0, 0, false)

    init(scale: CGFloat) {
        root.anchorPoint = .zero
        for shape in [edge, line] {
            shape.anchorPoint = .zero
            shape.fillColor = nil
            shape.lineCap = .butt
            shape.lineJoin = .miter
            root.addSublayer(shape)
        }
        edge.strokeColor = EditorStyle.lightEdge.cgColor
        setScale(scale)
    }

    func setScale(_ scale: CGFloat) {
        for shape in [edge, line] { shape.contentsScale = scale }
    }

    func show(_ frame: CGRect, color: CGColor, style: PinStyle, edge width: CGFloat, speed: CGFloat) {
        let path = CGPath(rect: frame, transform: nil)
        let dashes = [max(style.areaDash, 0.5), max(style.areaGap, 0.5)]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The edge's dashes reach `width` past each end of the line's, so a gap narrower than both ends leaves it solid.
        let edgeGap = dashes[1] - 2 * width
        edge.path = path
        line.path = path
        line.lineDashPattern = dashes.map { NSNumber(value: Double($0)) }
        edge.lineDashPattern = edgeGap > 0 ? [dashes[0] + 2 * width, edgeGap].map { NSNumber(value: Double($0)) } : nil
        line.lineDashPhase = 0
        edge.lineDashPhase = width
        edge.lineWidth = style.areaWidth + 2 * width
        line.lineWidth = style.areaWidth
        line.strokeColor = color
        CATransaction.commit()
        let period = dashes[0] + dashes[1]
        let edgeDashed = edgeGap > 0
        guard speed != march.speed || period != march.period || width != march.edge || edgeDashed != march.edgeDashed else { return }
        march = (speed, period, width, edgeDashed)
        for (shape, phase) in [(line, 0), (edge, width)] {
            shape.removeAnimation(forKey: "march")
            guard speed > 0, shape.lineDashPattern != nil else { continue }
            let move = CABasicAnimation(keyPath: "lineDashPhase")
            move.fromValue = phase
            move.toValue = phase - period
            move.duration = period / speed
            move.repeatCount = .infinity
            move.timingFunction = CAMediaTimingFunction(name: .linear)
            shape.add(move, forKey: "march")
        }
    }
}
