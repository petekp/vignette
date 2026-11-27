import AppKit
import QuartzCore

/// The pins as the editor shows them, in the editor's coordinates, at one size on screen whatever the
/// zoom (`PinPlacement`): every teardrop and cluster in gel (`PinGel`), with the outline of each area
/// that is hovered, selected, being placed or open as a gel rod joined to its pin, and a lone selected
/// area pin's corner handles as squares of its gel with a white core, and a ring of neutral gel round
/// each selected teardrop, then what each teardrop wears (`PinLayer`).
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
    /// The white squares in the middle of an area pin's corner handles.
    private let handleCores = CAShapeLayer()
    private var scale: CGFloat = 2
    private var shown: Shown?

    struct Shown: Equatable {
        let placement: PinPlacement
        /// The pins whose area's outline shows, and those whose gel keeps drifting, as an open pin's does.
        let outlined: [Pin]
        let drifting: Set<Pin.ID>
        let selected: Set<Pin.ID>
        let handles: EditorCore.PinCorners?
        let markStyle: MarkStyle
        let transform: CGAffineTransform
    }

    init() {
        handleCores.fillColor = CGColor(gray: 1, alpha: 1)
        handleCores.shadowColor = CGColor(gray: 0, alpha: 1)
        handleCores.shadowOpacity = Float(Self.coreShadowOpacity)
        handleCores.shadowRadius = Self.coreShadowRadius
        handleCores.shadowOffset = .zero
    }

    /// A corner handle's rounding, and its core's, as a share of its side.
    private static let handleRounding: CGFloat = 0.3
    /// The shadow that lifts a handle's white core off its gel.
    private static let coreShadowOpacity: CGFloat = 0.35, coreShadowRadius: CGFloat = 0.75
    /// A selected pin's ring: white over dark content, graphite over light content, so it stands apart
    /// from every pin's colour on both.
    private static let ringLight = SRGB(red: 1, green: 1, blue: 1)
    private static let ringDeep = SRGB(red: 0x3a / 255.0, green: 0x3a / 255.0, blue: 0x3c / 255.0)

    func setScale(_ scale: CGFloat) {
        self.scale = scale
        handleCores.contentsScale = scale
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
            shapes.append(.outline(rect, width: style.gelRod, tint: tint(pin.maker, resolved: pin.isResolved, over: rect, toImage: toImage,
                                                                         markStyle: what.markStyle)))
        }

        let teardrops = what.placement.drops.map { drop in
            (drop, PinTeardrop(number: drop.number, agent: drop.agent, tip: drop.tip.applying(transform), orientation: drop.orientation,
                               side: what.placement.side * zoom, style: style))
        }
        let ringOut = style.gelRingGap + style.gelRing / 2
        for (drop, teardrop) in teardrops where what.selected.contains(drop.id) {
            let body = PinGel.Shape.body(of: teardrop, dome: 0, tint: PinGel.Tint(color: Self.ringLight, deepness: 0))
            shapes.append(PinGel.Shape(rect: body.rect.insetBy(dx: -ringOut, dy: -ringOut), radius: body.radius + ringOut, sharp: body.sharp,
                                       rod: style.gelRing, tint: ringTint(over: body.rect, toImage: toImage)))
        }

        var faces: [CALayer] = []
        let kept = Set(teardrops.map(\.0.id))
        drops = drops.filter { kept.contains($0.key) }
        for (drop, teardrop) in teardrops {
            let face = drops[drop.id] ?? PinLayer(scale: scale, body: false)
            shapes.append(.body(of: teardrop, dome: teardrop.square.height / 2 * style.gelDome,
                                tint: tint(drop.maker, resolved: drop.resolved, over: teardrop.square, toImage: toImage, markStyle: what.markStyle)))
            face.show(teardrop, maker: drop.maker, resolved: drop.resolved, face: PinFace(drop.maker), answeringAgent: drop.answeringAgent,
                      pointScale: 1, markStyle: what.markStyle)
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
                                tint: tint(cluster.maker, resolved: cluster.resolved, over: teardrop.square, toImage: toImage,
                                           markStyle: what.markStyle)))
            face.show(teardrop, maker: cluster.maker, resolved: cluster.resolved, pointScale: 1, markStyle: what.markStyle)
            clusters[cluster.pins] = face
            faces.append(face.root)
        }

        let cores = CGMutablePath()
        if let handles = what.handles, case .area(let frame, _) = handles.pin.place {
            let tint = tint(handles.pin.maker, resolved: handles.pin.isResolved, over: frame.applying(transform), toImage: toImage,
                            markStyle: what.markStyle)
            let side = style.gelHandle, core = style.gelHandleCore
            let squares = teardrops.map(\.1.square)
            for corner in handles.corners.map({ $0.applying(transform) }) {
                let square = CGRect(x: corner.x - side / 2, y: corner.y - side / 2, width: side, height: side)
                shapes.append(PinGel.Shape(rect: square, radius: side * Self.handleRounding, sharp: nil, rod: nil,
                                           dome: side / 2 * style.gelDome, tint: tint))
                // The corner under the pin's teardrop is the pin's tip, which takes the press.
                guard core > 0, !squares.contains(where: { $0.insetBy(dx: -1, dy: -1).contains(corner) }) else { continue }
                let middle = CGRect(x: corner.x - core / 2, y: corner.y - core / 2, width: core, height: core)
                cores.addRoundedRect(in: middle, cornerWidth: core * Self.handleRounding, cornerHeight: core * Self.handleRounding)
            }
        }
        handleCores.path = cores

        let drifting = !what.drifting.isEmpty
        gel.show(shapes, drifting: drifting, within: host?.bounds)
        let layers = [gel, handleCores] + faces
        if (layer.sublayers ?? []).map(ObjectIdentifier.init) != layers.map(ObjectIdentifier.init) { layer.sublayers = layers }
    }

    /// A selected pin's ring over `rect` of the editor: graphite where that stands out more from the
    /// picture there, white elsewhere.
    private func ringTint(over rect: CGRect, toImage: CGAffineTransform) -> PinGel.Tint {
        var deepness: CGFloat = 0
        if let brightness = backdrop?.mean(in: rect.applying(toImage)) {
            deepness = InkContrast(ice: Self.ringLight.cgColor, deep: Self.ringDeep.cgColor).deepWins(behind: brightness) ? 1 : 0
        }
        return PinGel.Tint(color: Self.ringLight, deepness: deepness, deep: Self.ringDeep)
    }

    /// The gel of a pin `maker` made over `rect` of the editor: in the pin's colour, or grey once
    /// `resolved`, with its deep edge where that stands out more from the picture there.
    private func tint(_ maker: PinMaker, resolved: Bool, over rect: CGRect, toImage: CGAffineTransform, markStyle: MarkStyle) -> PinGel.Tint {
        .pin(maker, resolved: resolved, over: rect.applying(toImage), backdrop: backdrop, markStyle: markStyle)
    }
}
