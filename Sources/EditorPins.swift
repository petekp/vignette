import AppKit
import QuartzCore

/// The pins as the editor shows them, in the editor's coordinates, at one size on screen whatever the
/// zoom (`PinPlacement`): a selection ring round each selected teardrop, then each teardrop and
/// cluster in gel (`PinGel`) under what it wears (`PinLayer`). The outline of each area that is
/// hovered, selected, being placed or open is a gel rod joined to its pin, or on its own when its pin
/// is in a cluster, under the rest.
@MainActor
final class EditorPins {
    /// The owner puts this between the picture and the overlay.
    let layer = CALayer()
    /// The editor, whose window the gel is lit in.
    weak var host: NSView?
    /// The picture's brightness, in image px, which decides whether a pin's gel takes its deep edge.
    var backdrop: LivePacket.Luminance? {
        didSet { shown = nil }
    }
    private var drops: [Pin.ID: Pinned] = [:]
    private var clusters: [[Pin.ID]: Pinned] = [:]
    private var areas: [Pin.ID: PinGel] = [:]
    private let selectionEdge = CAShapeLayer(), selectionLine = CAShapeLayer()
    private var scale: CGFloat = 2
    private var shown: Shown?

    /// A teardrop's gel and what it wears over it.
    private struct Pinned {
        let gel: PinGel
        let face: PinLayer
    }

    struct Shown: Equatable {
        let placement: PinPlacement
        /// The pins whose area's outline shows, and those whose gel keeps drifting, as an open pin's does.
        let outlined: [Pin]
        let drifting: Set<Pin.ID>
        let selected: Set<Pin.ID>
        let markStyle: MarkStyle
        let outlineWidth: CGFloat
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
        for pinned in Array(drops.values) + Array(clusters.values) {
            pinned.face.setScale(scale)
            pinned.gel.setScale(scale)
        }
        for area in areas.values { area.setScale(scale) }
    }

    /// Shows `what`, unless it is shown already.
    func show(_ what: Shown) {
        guard what != shown else { return }
        shown = what
        let transform = what.transform, zoom = transform.a, style = what.markStyle.pin
        let toImage = transform.inverted()

        var outlines: [Pin.ID: PinGel.Shape] = [:]
        for pin in what.outlined {
            guard case .area(let frame, _) = pin.place else { continue }
            outlines[pin.id] = .outline(frame.applying(transform), width: style.gelRod)
        }
        let makers = Dictionary(what.outlined.map { ($0.id, $0.maker) }, uniquingKeysWith: { first, _ in first })

        let rings = CGMutablePath()
        let teardrops = what.placement.drops.map { drop in
            (drop, PinTeardrop(number: drop.number, agent: drop.agent, tip: drop.tip.applying(transform), orientation: drop.orientation,
                               side: what.placement.side * zoom, style: style))
        }
        let reach = 2 * (style.rimWidth + what.outlineWidth / 2)
        for (drop, teardrop) in teardrops where what.selected.contains(drop.id) {
            rings.addPath(teardrop.body.copy(strokingWithWidth: reach, lineCap: .round, lineJoin: .round, miterLimit: 1).union(teardrop.body))
        }
        selectionEdge.lineWidth = what.outlineWidth
        selectionEdge.path = rings
        selectionLine.path = rings

        var pinLayers: [CALayer] = []
        let kept = Set(teardrops.map(\.0.id))
        drops = drops.filter { kept.contains($0.key) }
        for (drop, teardrop) in teardrops {
            let pinned = drops[drop.id] ?? made()
            var shapes = [PinGel.Shape.body(of: teardrop)]
            if let outline = outlines.removeValue(forKey: drop.id) { shapes.append(outline) }
            pinned.gel.show(shapes, look: look(drop.maker, over: teardrop.square, toImage: toImage, side: teardrop.square.height,
                                                drifting: what.drifting.contains(drop.id), markStyle: what.markStyle))
            pinned.face.show(teardrop, maker: drop.maker, face: PinFace(drop.maker), answeringAgent: drop.answeringAgent, pointScale: 1,
                             markStyle: what.markStyle)
            drops[drop.id] = pinned
            pinLayers += [pinned.gel, pinned.face.root]
        }

        let grouped = Set(what.placement.clusters.map(\.pins))
        clusters = clusters.filter { grouped.contains($0.key) }
        for cluster in what.placement.clusters {
            let pinned = clusters[cluster.pins] ?? made()
            let teardrop = PinTeardrop(label: cluster.label, agent: cluster.agent, orientation: cluster.orientation,
                                       frame: cluster.frame.applying(transform), style: style)
            pinned.gel.show([.body(of: teardrop)], look: look(cluster.maker, over: teardrop.square, toImage: toImage,
                                                              side: teardrop.square.height, drifting: false, markStyle: what.markStyle))
            pinned.face.show(teardrop, maker: cluster.maker, pointScale: 1, markStyle: what.markStyle)
            clusters[cluster.pins] = pinned
            pinLayers += [pinned.gel, pinned.face.root]
        }

        // The outlines whose pin is in a cluster stand on their own.
        areas = areas.filter { outlines.keys.contains($0.key) }
        var areaLayers: [CALayer] = []
        for id in what.outlined.map(\.id) {
            guard let outline = outlines[id] else { continue }
            let gel = areas[id] ?? PinGel(scale: scale)
            gel.host = host
            gel.show([outline], look: look(makers[id] ?? .person, over: outline.rect, toImage: toImage, side: 0,
                                           drifting: what.drifting.contains(id), markStyle: what.markStyle))
            areas[id] = gel
            areaLayers.append(gel)
        }
        let layers = areaLayers + [selectionEdge, selectionLine] + pinLayers
        if (layer.sublayers ?? []).map(ObjectIdentifier.init) != layers.map(ObjectIdentifier.init) { layer.sublayers = layers }
    }

    private func made() -> Pinned {
        let gel = PinGel(scale: scale)
        gel.host = host
        return Pinned(gel: gel, face: PinLayer(scale: scale, body: false))
    }

    /// How the gel of a pin `maker` made looks over `rect` of the editor: in the pin's colour, with its
    /// deep edge where that stands out more from the picture there, and domed across `side`.
    private func look(_ maker: PinMaker, over rect: CGRect, toImage: CGAffineTransform, side: CGFloat, drifting: Bool,
                      markStyle: MarkStyle) -> PinGel.Look {
        let color = PinShading.color(of: maker, markStyle: markStyle)
        var deepness: CGFloat = 0
        if let brightness = backdrop?.mean(in: rect.applying(toImage)) {
            let share = markStyle.pin.gelDeep
            let deep = CGColor(srgbRed: color.red * share, green: color.green * share, blue: color.blue * share, alpha: 1)
            deepness = InkContrast(ice: color.cgColor, deep: deep).deepWins(behind: brightness) ? 1 : 0
        }
        return PinGel.Look(color: color, deepness: deepness, dome: side / 2 * markStyle.pin.gelDome, drifting: drifting)
    }
}
