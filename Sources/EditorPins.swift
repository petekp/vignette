import AppKit
import QuartzCore

/// The pins as the editor shows them, in the editor's coordinates, at one size on screen whatever the
/// zoom (`PinPlacement`): the outline of each area that is hovered, selected or open, which grows with
/// the zoom as a rectangle does, then a selection ring round each selected teardrop, then the
/// teardrops and the clusters.
@MainActor
final class EditorPins {
    /// The owner puts this between the picture and the overlay.
    let layer = CALayer()
    private var drops: [Pin.ID: PinLayer] = [:]
    private var clusters: [[Pin.ID]: PinLayer] = [:]
    private var areas: [Pin.ID: ShapeMarkLayer] = [:]
    private let selectionEdge = CAShapeLayer(), selectionLine = CAShapeLayer()
    private var scale: CGFloat = 2
    private var shown: Shown?

    struct Shown: Equatable {
        let placement: PinPlacement
        /// The pins whose area's outline shows.
        let outlined: [Pin]
        let selected: Set<Pin.ID>
        let markStyle: MarkStyle
        let outlineWidth: CGFloat
        /// Screen pt per drawing pt for a teardrop, and for an area's outline.
        let dropScale: CGFloat
        let areaScale: CGFloat
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
            guard case .area(let frame) = pin.place else { continue }
            let record = areas[pin.id] ?? ShapeMarkLayer(scale: scale)
            record.show(Mark(id: pin.id, geometry: .rectangle(frame.applying(transform)), agent: pin.color == .agent),
                        pointScale: what.areaScale, markStyle: what.markStyle)
            areas[pin.id] = record
            layers.append(record.root)
        }

        let rings = CGMutablePath()
        let teardrops = what.placement.drops.map { drop in
            (drop, PinTeardrop(number: drop.number, agent: drop.agent, tip: drop.tip.applying(transform), orientation: drop.orientation,
                               side: what.placement.side * zoom, style: what.markStyle.pin))
        }
        let reach = 2 * (what.markStyle.pin.rimWidth * what.dropScale + what.outlineWidth / 2)
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
            record.show(teardrop, color: drop.agent ? .agent : .person, pointScale: what.dropScale, markStyle: what.markStyle)
            drops[drop.id] = record
            layers.append(record.root)
        }

        let grouped = Set(what.placement.clusters.map(\.pins))
        clusters = clusters.filter { grouped.contains($0.key) }
        for cluster in what.placement.clusters {
            let record = clusters[cluster.pins] ?? PinLayer(scale: scale)
            record.show(PinTeardrop(label: cluster.label, agent: cluster.agent, orientation: cluster.orientation,
                                    frame: cluster.frame.applying(transform), style: what.markStyle.pin),
                        color: cluster.agent ? .agent : .person, pointScale: what.dropScale, markStyle: what.markStyle)
            clusters[cluster.pins] = record
            layers.append(record.root)
        }
        if (layer.sublayers ?? []).map(ObjectIdentifier.init) != layers.map(ObjectIdentifier.init) { layer.sublayers = layers }
    }
}
