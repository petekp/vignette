import AppKit
import QuartzCore

/// A flight's pins in gel, so a pin keeps one material between a card and the editor: the card draws
/// its pins flat and the editor in gel (`EditorPins`). On the way to the editor the gel comes in under
/// the flat body over the first half of the flight, and the flat body goes over the second half, so
/// the pin is never see-through and lands all gel. The way home turns the same way back. The gel is
/// drawn at the editor's scale and shrinks with the picture, so its textures keep one size through
/// the flight instead of being made again on every frame.
extension MarkLayers {
    struct PinBody {
        let teardrop: PinTeardrop
        let maker: PinMaker
        let resolved: Bool
    }

    /// Puts the gel under the pins once the flight has an editor's end.
    func wearGel() {
        guard drawsPins, pinGrowth != nil, gel == nil, !pinBodies.isEmpty else { return }
        let gel = PinGel(scale: contentsScale)
        gel.host = host
        gel.opacity = 0
        self.gel = gel
        // The pins' layers are the last ones `show` puts in.
        layer.insertSublayer(gel, at: UInt32(max(0, (layer.sublayers?.count ?? 0) - pinBodies.count)))
    }

    /// How much of the gel shows when the flight is `share` of the way to the editor.
    static func gelOpacity(_ share: CGFloat) -> CGFloat { min(max(share * 2, 0), 1) }

    /// How much of a flat pin's body shows when the flight is `share` of the way to the editor.
    static func bodyOpacity(gelShare share: CGFloat) -> CGFloat { min(max((1 - share) * 2, 0), 1) }

    /// Draws the pins' bodies in gel, `growth` times their drawn size about their tips, `share` of the
    /// way to the editor. Each takes the deep edge the editor gives it, judged at the editor's size.
    func showGel(growth: CGFloat, share: CGFloat) {
        guard let gel, let markStyle, let pinGrowth else { return }
        let editor = pinGrowth.to.editor ? pinGrowth.to : pinGrowth.from
        guard editor.zoom > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The marks' layer runs in image px; the gel's, in the editor's points.
        gel.setAffineTransform(CGAffineTransform(scaleX: 1 / editor.zoom, y: 1 / editor.zoom))
        gel.opacity = Float(Self.gelOpacity(share))
        CATransaction.commit()
        guard share > 0 else { return }
        let atEditor = pinGrowth.growth(atZoom: editor.zoom, pointScale: drawing?.pointScale ?? 1)
        let style = markStyle.pin
        let shapes = pinBodies.map { body in
            let tip = body.teardrop.tip
            let tint = PinGel.Tint.pin(body.maker, resolved: body.resolved, over: body.teardrop.square.applying(Self.scaling(about: tip, by: atEditor)),
                                       backdrop: backdrop, markStyle: markStyle)
            var shape = PinGel.Shape.body(of: body.teardrop, dome: 0, tint: tint)
            shape.rect = shape.rect.applying(Self.scaling(about: tip, by: growth).concatenating(CGAffineTransform(scaleX: editor.zoom, y: editor.zoom)))
            shape.radius = min(shape.rect.width, shape.rect.height) / 2
            shape.dome = shape.rect.height / 2 * style.gelDome
            return shape
        }
        gel.show(shapes, drifting: false)
    }

    private static func scaling(about point: CGPoint, by scale: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: point.x, y: point.y).scaledBy(x: scale, y: scale).translatedBy(x: -point.x, y: -point.y)
    }
}
