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

    /// A pin `maker` made, in its colour, or grey when `resolved`, on a drawing of `pointScale`.
    init(_ maker: PinMaker, resolved: Bool = false, pointScale: CGFloat, markStyle: MarkStyle) {
        let base = Self.color(of: maker, resolved: resolved, markStyle: markStyle), style = markStyle.pin
        top = Self.mix(base, toward: 1, style.gradient)
        bottom = Self.mix(base, toward: 0, style.bottomShade)
        rim = style.rimWidth * pointScale
        rimColor = markStyle.edgeColor.cgColor
        shadowRadius = style.shadowRadius * pointScale
        shadowOffset = style.shadowOffset * pointScale
        shadowOpacity = Float(min(1, max(0, style.shadowOpacity * markStyle.shadowOpacity)))
    }

    /// The colour of a pin `maker` made: the person's, or the agent's brand, and grey once resolved.
    static func color(of maker: PinMaker, resolved: Bool = false, markStyle: MarkStyle) -> SRGB {
        if resolved { return resolvedColor }
        return maker.isAgent ? markStyle.painting(maker).agentColor : markStyle.personColor
    }

    /// A resolved pin's colour, whoever made it: macOS's system grey, which reads in light and dark.
    static let resolvedColor = SRGB(red: 0x8e / 255, green: 0x8e / 255, blue: 0x93 / 255)

    /// `color` taken `share` of the way to the grey `level`: 1 is white and 0 black.
    private static func mix(_ color: SRGB, toward level: CGFloat, _ share: CGFloat) -> CGColor {
        let share = min(max(share, 0), 1)
        func blend(_ value: CGFloat) -> CGFloat { value + (level - value) * share }
        return CGColor(srgbRed: blend(color.red), green: blend(color.green), blue: blend(color.blue), alpha: 1)
    }
}

extension PinTeardrop {
    /// Draws the teardrop of a pin `maker` made as it looks on screen, wearing `face`, but with no
    /// shadow, as a menu's row shows it, in a context whose y runs down.
    func drawFlat(in ctx: CGContext, maker: PinMaker, resolved: Bool = false, face: PinFace, pointScale: CGFloat, markStyle: MarkStyle) {
        let shading = PinShading(maker, resolved: resolved, pointScale: pointScale, markStyle: markStyle)
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
        let words = markStyle.wordColor.cgColor
        if case .logo(let name) = face, let image = AgentLogos.shared.image(for: name) {
            let logo = logoFrame(style: markStyle.pin)
            ctx.saveGState()
            // An image is drawn with its top at its rect's greatest y; here y runs down.
            ctx.translateBy(x: logo.minX, y: logo.maxY)
            ctx.scaleBy(x: 1, y: -1)
            let box = CGRect(origin: .zero, size: logo.size)
            ctx.beginTransparencyLayer(in: box, auxiliaryInfo: nil)
            ctx.draw(image, in: box)
            ctx.setBlendMode(.sourceIn)
            ctx.setFillColor(words)
            ctx.fill(box)
            ctx.endTransparencyLayer()
            ctx.restoreGState()
            return
        }
        ctx.setFillColor(words)
        ctx.addPath(lettering(face, style: markStyle.pin))
        ctx.fillPath()
    }

    /// Where an agent's logo sits: a square `PinStyle.logoSize` of the teardrop's side, in the middle
    /// of the body.
    func logoFrame(style: PinStyle) -> CGRect {
        let side = square.height * style.logoSize
        return CGRect(x: square.midX - side / 2, y: square.midY - side / 2, width: side, height: side)
    }

    /// The circle of an answering agent's dot, `PinStyle.answerSize` of the teardrop's side across,
    /// centred on the body's rim across from the tip.
    func answerDot(style: PinStyle) -> CGRect {
        let centre = CGPoint(x: square.midX, y: square.midY), away = CGVector(dx: centre.x - tip.x, dy: centre.y - tip.y)
        let length = max(hypot(away.dx, away.dy), 1), radius = square.height / 2, side = square.height * style.answerSize
        let at = CGPoint(x: centre.x + away.dx / length * radius, y: centre.y + away.dy / length * radius)
        return CGRect(x: at.x - side / 2, y: at.y - side / 2, width: side, height: side)
    }
}

/// A pin's layers, in its look on screen (`PinShading`): the hairline, which casts the shadow, the
/// teardrop's fill over it, and what it wears (`PinFace`), then the dot of an agent that answered it.
/// Without its body it draws only what the pin wears and the dot, casting `PinStyle.gelFaceShadow`, for
/// the editor, whose gel draws the body (`PinGel`).
@MainActor
final class PinLayer {
    let root = CALayer()
    private let rim = CAShapeLayer()
    private let fill = CAGradientLayer()
    private let fillShape = CAShapeLayer()
    private let number = CAShapeLayer()
    private let logo = CALayer(), logoShape = CALayer()
    private let dot = CAShapeLayer(), dotLogo = CALayer(), dotLogoShape = CALayer()
    private var shown: (pin: Pin, pixels: PixelSize, pointScale: CGFloat, markStyle: MarkStyle, pieceNumbers: [CGRect])?
    /// The teardrop's tip, in px, which `growth` scales the pin about.
    private var tip = CGPoint.zero
    /// How many times its drawn size the pin is shown, about its tip: a flight's, on its way between
    /// a card and the editor (`MarkLayers.PinGrowth`).
    var growth: CGFloat = 1 {
        didSet { if growth != oldValue { placeGrowth() } }
    }

    /// How much of the body shows: a flight's fades as its gel comes in (`MarkLayers+Gel.swift`).
    var bodyOpacity: Float = 1 {
        didSet {
            guard bodyOpacity != oldValue else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            rim.opacity = bodyOpacity
            fill.opacity = bodyOpacity
            CATransaction.commit()
        }
    }

    private let drawsBody: Bool

    init(scale: CGFloat, body: Bool = true) {
        drawsBody = body
        for layer in [root, rim, fill, fillShape, number, logo, logoShape, dot, dotLogo, dotLogoShape] { layer.anchorPoint = .zero }
        fill.mask = fillShape
        logo.mask = logoShape
        dotLogo.mask = dotLogoShape
        for shape in [logoShape, dotLogoShape] { shape.contentsGravity = .resizeAspect }
        dot.shadowColor = CGColor(gray: 0, alpha: 1)
        // The layers' y runs down, as the drawing's does, so the gradient's 0 is its top.
        fill.startPoint = CGPoint(x: 0.5, y: 0)
        fill.endPoint = CGPoint(x: 0.5, y: 1)
        rim.shadowColor = CGColor(gray: 0, alpha: 1)
        rim.lineJoin = .round
        for layer in [rim, fill, number, logo, dot, dotLogo] { root.addSublayer(layer) }
        rim.isHidden = !body
        fill.isHidden = !body
        if !body {
            root.shadowColor = CGColor(gray: 0, alpha: 1)
            root.shadowOffset = .zero
            root.shadowRadius = 1.5
        }
        setScale(scale)
    }

    func setScale(_ scale: CGFloat) {
        for layer in [rim, fill, fillShape, number, logo, logoShape, dot, dotLogo, dotLogoShape] { layer.contentsScale = scale }
    }

    /// Draws `pin` of `drawing`, unless it is drawn already as it is, on this image, at this scale, among
    /// these piece numbers and in this style.
    func show(_ pin: Pin, on drawing: Drawing, markStyle: MarkStyle) {
        let (pixels, pointScale, pieceNumbers) = (drawing.pixels, drawing.pointScale, drawing.pieceNumbers)
        if let shown, shown.pin == pin, shown.pixels == pixels, shown.pointScale == pointScale, shown.markStyle == markStyle,
           shown.pieceNumbers == pieceNumbers { return }
        show(PinTeardrop(pin, in: pixels, pointScale: pointScale, markStyle: markStyle, pieceNumbers: pieceNumbers),
             maker: pin.maker, resolved: pin.isResolved, face: PinFace(pin.maker), answeringAgent: pin.answeringAgent, pointScale: pointScale,
             markStyle: markStyle)
        shown = (pin, pixels, pointScale, markStyle, pieceNumbers)
    }

    /// Draws `teardrop`, a pin's or a cluster's wherever it is, in the colour of `maker`, or grey when
    /// `resolved`, wearing `face`, with `answeringAgent`'s dot, for a drawing of `pointScale`.
    func show(_ teardrop: PinTeardrop, maker: PinMaker, resolved: Bool = false, face: PinFace = .number, answeringAgent: PinMaker? = nil,
              pointScale: CGFloat, markStyle: MarkStyle) {
        let shading = PinShading(maker, resolved: resolved, pointScale: pointScale, markStyle: markStyle)
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
        if !drawsBody { root.shadowOpacity = Float(min(max(markStyle.pin.gelFaceShadow, 0), 1)) }
        let words = markStyle.wordColor.cgColor, logoImage = face.logo.flatMap(AgentLogos.shared.image(for:))
        number.path = logoImage == nil ? teardrop.lettering(face, style: markStyle.pin) : nil
        number.fillColor = words
        Self.wear(logoImage, on: logo, shape: logoShape, in: teardrop.logoFrame(style: markStyle.pin), color: words)
        let answer = answeringAgent.map { (agent: $0, circle: teardrop.answerDot(style: markStyle.pin)) }
        dot.isHidden = answer == nil
        if let answer {
            let agentShading = PinShading(answer.agent, pointScale: pointScale, markStyle: markStyle)
            dot.path = CGPath(ellipseIn: answer.circle, transform: nil)
            dot.fillColor = agentShading.top
            dot.strokeColor = shading.rimColor
            dot.lineWidth = 2 * shading.rim
            dot.shadowOpacity = shading.shadowOpacity
            dot.shadowRadius = shading.shadowRadius
            dot.shadowOffset = CGSize(width: 0, height: shading.shadowOffset)
            let side = answer.circle.width * markStyle.pin.logoSize
            Self.wear(PinFace(answer.agent).logo.flatMap(AgentLogos.shared.image(for:)), on: dotLogo, shape: dotLogoShape,
                      in: CGRect(x: answer.circle.midX - side / 2, y: answer.circle.midY - side / 2, width: side, height: side), color: words)
        } else {
            dotLogo.isHidden = true
        }
        CATransaction.commit()
        shown = nil
        if teardrop.tip != tip {
            tip = teardrop.tip
            if growth != 1 { placeGrowth() }
        }
    }

    private func placeGrowth() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.setAffineTransform(CGAffineTransform(translationX: tip.x, y: tip.y).scaledBy(x: growth, y: growth).translatedBy(x: -tip.x, y: -tip.y))
        CATransaction.commit()
    }

    /// Shows `image` as a shape in `color` filling `frame`, or hides `layer` for no image.
    private static func wear(_ image: CGImage?, on layer: CALayer, shape: CALayer, in frame: CGRect, color: CGColor) {
        layer.isHidden = image == nil
        layer.frame = frame
        layer.backgroundColor = color
        shape.frame = CGRect(origin: .zero, size: frame.size)
        shape.contents = image
    }
}

extension PinFace {
    var logo: String? {
        if case .logo(let name) = self { return name }
        return nil
    }
}
