import AppKit
import QuartzCore

/// The pins as the editor shows them, in the editor's coordinates, at one size on screen whatever the
/// zoom (`PinPlacement`): every teardrop and cluster in gel (`PinGel`), with the outline of each area
/// that is hovered, selected, being placed or open as a gel rod joined to its pin, then a selection
/// ring round each selected teardrop, then what each teardrop wears (`PinLayer`).
@MainActor
final class EditorPins {
    /// The owner puts this between the picture and the overlay.
    let layer = CALayer()
    /// The editor, whose window the gel is lit in.
    weak var host: NSView? {
        didSet { gel.host = host }
    }
    /// The picture's brightness, in image px, which decides whether a pin's gel takes its deep edge.
    var backdrop: LivePacket.Luminance? {
        didSet { shown = nil }
    }
    private let gel = PinGel(scale: 2)
    private var drops: [Pin.ID: PinLayer] = [:]
    private var clusters: [[Pin.ID]: PinLayer] = [:]
    private let selectionEdge = CAShapeLayer(), selectionLine = CAShapeLayer()
    private var scale: CGFloat = 2
    private var shown: Shown?

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
        for face in Array(drops.values) + Array(clusters.values) { face.setScale(scale) }
        gel.setScale(scale)
    }

    /// Shows `what`, unless it is shown already.
    func show(_ what: Shown) {
        guard what != shown else { return }
        shown = what
        let transform = what.transform, zoom = transform.a, style = what.markStyle.pin
        let toImage = transform.inverted()

        var shapes: [PinGel.Shape] = []
        for pin in what.outlined {
            guard case .area(let frame, _) = pin.place else { continue }
            let rect = frame.applying(transform)
            shapes.append(.outline(rect, width: style.gelRod, tint: tint(pin.maker, over: rect, toImage: toImage, markStyle: what.markStyle)))
        }

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

        var faces: [CALayer] = []
        let kept = Set(teardrops.map(\.0.id))
        drops = drops.filter { kept.contains($0.key) }
        for (drop, teardrop) in teardrops {
            let face = drops[drop.id] ?? PinLayer(scale: scale, body: false)
            shapes.append(.body(of: teardrop, dome: teardrop.square.height / 2 * style.gelDome,
                                tint: tint(drop.maker, over: teardrop.square, toImage: toImage, markStyle: what.markStyle)))
            face.show(teardrop, maker: drop.maker, face: PinFace(drop.maker), answeringAgent: drop.answeringAgent, pointScale: 1,
                      markStyle: what.markStyle)
            drops[drop.id] = face
            faces.append(face.root)
        }

        let grouped = Set(what.placement.clusters.map(\.pins))
        clusters = clusters.filter { grouped.contains($0.key) }
        for cluster in what.placement.clusters {
            let face = clusters[cluster.pins] ?? PinLayer(scale: scale, body: false)
            let teardrop = PinTeardrop(label: cluster.label, agent: cluster.agent, orientation: cluster.orientation,
                                       frame: cluster.frame.applying(transform), style: style)
            shapes.append(.body(of: teardrop, dome: teardrop.square.height / 2 * style.gelDome,
                                tint: tint(cluster.maker, over: teardrop.square, toImage: toImage, markStyle: what.markStyle)))
            face.show(teardrop, maker: cluster.maker, pointScale: 1, markStyle: what.markStyle)
            clusters[cluster.pins] = face
            faces.append(face.root)
        }

        let drifting = !what.drifting.isEmpty
        gel.show(shapes, drifting: drifting, within: host?.bounds)
        let layers = [gel, selectionEdge, selectionLine] + faces
        if (layer.sublayers ?? []).map(ObjectIdentifier.init) != layers.map(ObjectIdentifier.init) { layer.sublayers = layers }
    }

    /// The gel of a pin `maker` made over `rect` of the editor: in the pin's colour, with its deep edge
    /// where that stands out more from the picture there.
    private func tint(_ maker: PinMaker, over rect: CGRect, toImage: CGAffineTransform, markStyle: MarkStyle) -> PinGel.Tint {
        let color = PinShading.color(of: maker, markStyle: markStyle)
        var deepness: CGFloat = 0
        if let brightness = backdrop?.mean(in: rect.applying(toImage)) {
            let share = markStyle.pin.gelDeep
            let deep = CGColor(srgbRed: color.red * share, green: color.green * share, blue: color.blue * share, alpha: 1)
            deepness = InkContrast(ice: color.cgColor, deep: deep).deepWins(behind: brightness) ? 1 : 0
        }
        return PinGel.Tint(color: color, deepness: deepness)
    }
}
