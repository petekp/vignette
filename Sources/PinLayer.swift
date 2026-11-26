import AppKit
import QuartzCore

/// How a pin looks on screen, in the editor, on a card and in flight: a solid teardrop in its colour,
/// lighter at the top and darker at the bottom, inside a white hairline that casts a soft shadow.
/// The hairline lies outside the body, as the marks' white edge does, so the body covers what a
/// rendering's does. Copy, Send and Stitch keep the look `Pin.draw` gives them, inside the marks'
/// white edge, which holds up on any picture at any size.
struct PinShading {
    let top: CGColor, bottom: CGColor
    let rim: CGFloat, rimColor: CGColor
    let shadowRadius: CGFloat, shadowOffset: CGFloat, shadowOpacity: Float

    /// A pin in `color` on a drawing of `pointScale`.
    init(_ color: MarkColor, pointScale: CGFloat, markStyle: MarkStyle) {
        let base = color == .agent ? markStyle.agentColor : markStyle.personColor, style = markStyle.pin
        top = Self.mix(base, toward: 1, style.gradient)
        bottom = Self.mix(base, toward: 0, style.bottomShade)
        rim = style.rimWidth * pointScale
        rimColor = markStyle.edgeColor.cgColor
        shadowRadius = style.shadowRadius * pointScale
        shadowOffset = style.shadowOffset * pointScale
        shadowOpacity = Float(min(1, max(0, style.shadowOpacity * markStyle.shadowOpacity)))
    }

    /// `color` taken `share` of the way to the grey `level`: 1 is white and 0 black.
    private static func mix(_ color: SRGB, toward level: CGFloat, _ share: CGFloat) -> CGColor {
        let share = min(max(share, 0), 1)
        func blend(_ value: CGFloat) -> CGFloat { value + (level - value) * share }
        return CGColor(srgbRed: blend(color.red), green: blend(color.green), blue: blend(color.blue), alpha: 1)
    }
}

extension PinTeardrop {
    /// Draws the teardrop as it looks on screen but with no shadow, as a menu's row shows it, in a
    /// context whose y runs down.
    func drawFlat(in ctx: CGContext, color: MarkColor, pointScale: CGFloat, markStyle: MarkStyle) {
        let shading = PinShading(color, pointScale: pointScale, markStyle: markStyle)
        let box = body.boundingBoxOfPath
        ctx.setLineJoin(.round)
        ctx.setLineWidth(2 * shading.rim)
        ctx.setStrokeColor(shading.rimColor)
        ctx.setFillColor(shading.rimColor)
        ctx.addPath(body)
        ctx.drawPath(using: .fillStroke)
        ctx.saveGState()
        ctx.addPath(body)
        ctx.clip()
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [shading.top, shading.bottom] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: box.midX, y: box.minY), end: CGPoint(x: box.midX, y: box.maxY), options: [])
        }
        ctx.restoreGState()
        ctx.setFillColor(markStyle.wordColor.cgColor)
        ctx.addPath(number)
        ctx.fillPath()
    }
}

/// A pin's layers, in its look on screen (`PinShading`): the hairline, which casts the shadow, the
/// teardrop's fill over it, and its number.
@MainActor
final class PinLayer {
    let root = CALayer()
    private let rim = CAShapeLayer()
    private let fill = CAGradientLayer()
    private let fillShape = CAShapeLayer()
    private let number = CAShapeLayer()
    private var shown: (pin: Pin, pixels: PixelSize, pointScale: CGFloat, markStyle: MarkStyle, pieceNumbers: [CGRect])?

    init(scale: CGFloat) {
        for layer in [root, rim, fill, fillShape, number] { layer.anchorPoint = .zero }
        fill.mask = fillShape
        // The layers' y runs down, as the drawing's does, so the gradient's 0 is its top.
        fill.startPoint = CGPoint(x: 0.5, y: 0)
        fill.endPoint = CGPoint(x: 0.5, y: 1)
        rim.shadowColor = CGColor(gray: 0, alpha: 1)
        rim.lineJoin = .round
        for layer in [rim, fill, number] { root.addSublayer(layer) }
        setScale(scale)
    }

    func setScale(_ scale: CGFloat) {
        for layer in [rim, fill, fillShape, number] { layer.contentsScale = scale }
    }

    /// Draws `pin` of `drawing`, unless it is drawn already as it is, on this image, at this scale, among
    /// these piece numbers and in this style.
    func show(_ pin: Pin, on drawing: Drawing, markStyle: MarkStyle) {
        let (pixels, pointScale, pieceNumbers) = (drawing.pixels, drawing.pointScale, drawing.pieceNumbers)
        if let shown, shown.pin == pin, shown.pixels == pixels, shown.pointScale == pointScale, shown.markStyle == markStyle,
           shown.pieceNumbers == pieceNumbers { return }
        show(PinTeardrop(pin, in: pixels, pointScale: pointScale, markStyle: markStyle, pieceNumbers: pieceNumbers),
             color: pin.color, pointScale: pointScale, markStyle: markStyle)
        shown = (pin, pixels, pointScale, markStyle, pieceNumbers)
    }

    /// Draws `teardrop`, a pin's or a cluster's wherever it is, in `color`, for a drawing of `pointScale`.
    func show(_ teardrop: PinTeardrop, color: MarkColor, pointScale: CGFloat, markStyle: MarkStyle) {
        let shading = PinShading(color, pointScale: pointScale, markStyle: markStyle)
        let box = teardrop.body.boundingBoxOfPath
        var toBox = CGAffineTransform(translationX: -box.minX, y: -box.minY)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rim.path = teardrop.body
        rim.lineWidth = 2 * shading.rim
        rim.strokeColor = shading.rimColor
        rim.fillColor = shading.rimColor
        rim.shadowPath = teardrop.body.copy(strokingWithWidth: 2 * shading.rim, lineCap: .round, lineJoin: .round, miterLimit: 10).union(teardrop.body)
        rim.shadowOpacity = shading.shadowOpacity
        rim.shadowRadius = shading.shadowRadius
        rim.shadowOffset = CGSize(width: 0, height: shading.shadowOffset)
        fill.frame = box
        fill.colors = [shading.top, shading.bottom]
        fillShape.path = teardrop.body.copy(using: &toBox)
        number.path = teardrop.number
        number.fillColor = markStyle.wordColor.cgColor
        CATransaction.commit()
        shown = nil
    }
}
