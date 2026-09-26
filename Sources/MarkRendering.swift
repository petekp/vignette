import AppKit
import CoreText
import ImageIO

// How marks look, drawn by one function for every place a drawing is seen: the editor's full
// rendering, a card's thumbnail, and a card in flight. Pure Core Graphics and Core Text, so any of
// them can run off the main thread.

/// An arrowhead's proportions, in multiples of the stroke width: a filled triangle `length` long
/// from its tip to its base, and `width` across the base.
struct ArrowheadStyle: Equatable {
    var length: CGFloat
    var width: CGFloat

    /// The tweaks' defaults.
    static let standard = UITweaks().arrowhead

    /// The most of an arrow's body a head may take: a short arrow gets a smaller head of the same
    /// shape, so it still shows a body and its head never reaches back past its start.
    static let maxShareOfBody: CGFloat = 0.5
}

extension MarkColor {
    /// The colour's sRGB components, from 0 to 1.
    var sRGB: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return (CGFloat((value >> 16) & 0xff) / 255, CGFloat((value >> 8) & 0xff) / 255, CGFloat(value & 0xff) / 255)
    }

    /// Defined in sRGB; Core Graphics converts it into whatever colour space it is drawn into.
    var cgColor: CGColor {
        let (red, green, blue) = sRGB
        return CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

extension Mark.Text {
    /// How far the outline reaches outside the letters, in pt.
    static let outlineWidth: CGFloat = 1

    /// The outline's near-black, `hsl(240 5% 6.5%)`.
    static var outlineColor: CGColor { CGColor(srgbRed: 0.06175, green: 0.06175, blue: 0.06825, alpha: 1) }
}

// MARK: - The arrowhead

extension ArrowBody {
    /// The body's length along the line, the arc or the curve.
    var length: CGFloat {
        if let curve { return curve.length }
        guard let arc else { return hypot(end.x - start.x, end.y - start.y) }
        return arc.radius * abs(arc.sweep)
    }

    /// The body from `start` to the point `fraction` of the way along it.
    func path(upTo fraction: CGFloat) -> CGPath {
        let t = min(max(fraction, 0), 1)
        let path = CGMutablePath()
        if let curve, let first = curve.segments.first {
            path.move(to: first[0])
            let place = t >= 1 ? (segment: curve.segments.count - 1, t: CGFloat(1)) : curve.place(at: t * curve.length)
            let last = place.segment, cut = place.t
            for segment in curve.segments[..<last] {
                path.addCurve(to: segment[3], control1: segment[1], control2: segment[2])
            }
            // The last segment up to `cut`, by de Casteljau's construction.
            let segment = curve.segments[last]
            func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * cut, y: a.y + (b.y - a.y) * cut) }
            let a = mix(segment[0], segment[1]), b = mix(segment[1], segment[2])
            path.addCurve(to: Curve.point(on: segment, at: cut), control1: a, control2: mix(a, b))
        } else if let arc {
            path.addArc(center: arc.center, radius: arc.radius, startAngle: arc.startAngle,
                        endAngle: arc.startAngle + arc.sweep * t, clockwise: arc.sweep < 0)
        } else {
            path.move(to: start)
            path.addLine(to: point(at: t))
        }
        return path
    }
}

/// The head at the end of an arrow's body, drawn `strokeWidth` px wide: a triangle whose tip is the
/// body's end, aimed from the point on the body one head-length back, and the point along the body
/// where the stroke stops so the head covers its round cap.
struct Arrowhead {
    let tip: CGPoint
    /// The base's two corners.
    let corners: (CGPoint, CGPoint)
    /// The fraction of the body the stroke is drawn to.
    let bodyEnd: CGFloat

    init(body: ArrowBody, strokeWidth: CGFloat, style: ArrowheadStyle) {
        let bodyLength = body.length
        // Past an arc's diameter, or a curve's furthest point from the tip, no point of the body is a
        // head's length from the tip, so the head could not be aimed from one.
        let reachable = body.arc.map { 2 * $0.radius }
            ?? body.curve.map { curve in curve.samples.reduce(0) { max($0, hypot($1.x - body.end.x, $1.y - body.end.y)) } }
            ?? .infinity
        let longest = min(bodyLength * ArrowheadStyle.maxShareOfBody, reachable)
        let shrink = min(1, longest / max(style.length * strokeWidth, .ulpOfOne))
        let length = style.length * strokeWidth * shrink
        let halfWidth = style.width * strokeWidth * shrink / 2
        // The point on the body `length` from the tip, where an arc crosses the circle of that radius
        // around it. Aimed from there, the head's axis runs through the body at the middle of its
        // base; aimed along the tangent at the tip, a tight arc hooks and bows out through a side.
        let back: CGFloat
        if let curve = body.curve {
            back = Self.back(along: curve, from: body.end, reach: length)
        } else if let arc = body.arc {
            back = max(0, 1 - 2 * asin(min(1, length / (2 * arc.radius))) / abs(arc.sweep))
        } else {
            back = bodyLength > 0 ? max(0, 1 - length / bodyLength) : 0
        }
        let from = body.point(at: back)
        let reach = hypot(body.end.x - from.x, body.end.y - from.y)
        let direction = reach > 0 ? CGVector(dx: (body.end.x - from.x) / reach, dy: (body.end.y - from.y) / reach) : CGVector(dx: 1, dy: 0)
        let base = CGPoint(x: body.end.x - direction.dx * length, y: body.end.y - direction.dy * length)
        tip = body.end
        corners = (CGPoint(x: base.x - direction.dy * halfWidth, y: base.y + direction.dx * halfWidth),
                   CGPoint(x: base.x + direction.dy * halfWidth, y: base.y - direction.dx * halfWidth))
        // The stroke stops on the head's axis, so its round cap lies inside the head however tight
        // the arc.
        bodyEnd = back
    }

    /// The fraction of `curve` where it is first `reach` from `tip`, walking back from the tip; 0 when
    /// no point is that far.
    private static func back(along curve: ArrowBody.Curve, from tip: CGPoint, reach: CGFloat) -> CGFloat {
        guard curve.length > 0 else { return 0 }
        for index in stride(from: curve.samples.count - 1, to: 0, by: -1) {
            let a = curve.samples[index - 1], b = curve.samples[index]
            guard hypot(a.x - tip.x, a.y - tip.y) >= reach else { continue }
            // Nearer the tip, `b` is inside the circle of `reach` and `a` is not, so the line from `a`
            // to `b` crosses it once, at the smaller root.
            let d = CGPoint(x: b.x - a.x, y: b.y - a.y), w = CGPoint(x: a.x - tip.x, y: a.y - tip.y)
            let qa = d.x * d.x + d.y * d.y, qb = 2 * (w.x * d.x + w.y * d.y), qc = w.x * w.x + w.y * w.y - reach * reach
            let u = qa > 0 ? min(max((-qb - max(0, qb * qb - 4 * qa * qc).squareRoot()) / (2 * qa), 0), 1) : 0
            return (curve.lengths[index - 1] + (curve.lengths[index] - curve.lengths[index - 1]) * u) / curve.length
        }
        return 0
    }

    var path: CGPath {
        let path = CGMutablePath()
        path.addLines(between: [tip, corners.0, corners.1])
        path.closeSubpath()
        return path
    }
}

// MARK: - Drawing marks

extension Drawing {
    /// Draws every mark, in order, so the newest is on top. The context's transform maps the image's
    /// px, from its top-left corner with y down, to whatever it draws on, at any scale.
    func draw(in ctx: CGContext, style: TextStyle, arrowhead: ArrowheadStyle) {
        for mark in marks {
            mark.draw(in: ctx, pointScale: pointScale, imageWidth: CGFloat(pixels.width), style: style, arrowhead: arrowhead)
        }
    }
}

/// A rectangle's, an ellipse's or an arrow's drawn geometry, in px: `stroked` is stroked `lineWidth`
/// wide with round caps and joins, and `filled` is filled, both in the mark's colour. The renderer
/// draws these paths, and the editor shows the same ones in shape layers.
struct MarkShape {
    let stroked: CGPath?
    let filled: CGPath?
    let lineWidth: CGFloat
}

extension Mark {
    /// The mark's paths for a drawing of `pointScale`. Nil for a text, whose letters only the
    /// renderer draws.
    func shape(pointScale: CGFloat, arrowhead: ArrowheadStyle) -> MarkShape? {
        let lineWidth = Self.strokeWidth * pointScale
        switch geometry {
        case .rectangle(let frame):
            return MarkShape(stroked: CGPath(rect: frame, transform: nil), filled: nil, lineWidth: lineWidth)
        case .ellipse(let frame):
            return MarkShape(stroked: CGPath(ellipseIn: frame, transform: nil), filled: nil, lineWidth: lineWidth)
        case .arrow(let arrow):
            let body = arrow.body(pointScale: pointScale)
            let head = Arrowhead(body: body, strokeWidth: lineWidth, style: arrowhead)
            return MarkShape(stroked: head.bodyEnd > 0 ? body.path(upTo: head.bodyEnd) : nil, filled: head.path, lineWidth: lineWidth)
        case .text:
            return nil
        }
    }

    /// Draws the mark in its colour, as `Drawing.draw` does, for a drawing of `pointScale` on an
    /// image `imageWidth` px wide.
    func draw(in ctx: CGContext, pointScale: CGFloat, imageWidth: CGFloat, style: TextStyle, arrowhead: ArrowheadStyle) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(color.cgColor)
        ctx.setFillColor(color.cgColor)
        if let shape = shape(pointScale: pointScale, arrowhead: arrowhead) {
            ctx.setLineWidth(shape.lineWidth)
            if let stroked = shape.stroked {
                ctx.addPath(stroked)
                ctx.strokePath()
            }
            if let filled = shape.filled {
                ctx.addPath(filled)
                ctx.fillPath()
            }
        } else if case .text(let text) = geometry {
            Self.draw(TextLayout(text, imageWidth: imageWidth, pointScale: pointScale, style: style.forAgent(agent)),
                      color: color.cgColor, outline: 2 * Text.outlineWidth * pointScale, in: ctx)
        }
    }

    /// Every letter's outline stroked `outline` px wide, then every letter filled over the outlines
    /// with the same paths, so the fill covers each outline's inner half. A glyph with no outline,
    /// such as a colour emoji, is drawn as the font draws it, in its own colours and without an
    /// outline.
    private static func draw(_ layout: TextLayout, color: CGColor, outline: CGFloat, in ctx: CGContext) {
        let runs = layout.lines.flatMap { line in
            ((CTLineGetGlyphRuns(line.ctLine) as? [CTRun]) ?? []).compactMap { GlyphRun($0, at: CGPoint(x: line.rect.minX, y: line.baseline)) }
        }
        let letters = CGMutablePath()
        ctx.setLineWidth(outline)
        ctx.setStrokeColor(Text.outlineColor)
        for run in runs {
            for case let path? in run.outlines {
                // One glyph at a time: Core Graphics strokes many letters as one path several times slower.
                ctx.addPath(path)
                ctx.strokePath()
                letters.addPath(path)
            }
        }
        ctx.setFillColor(color)
        ctx.addPath(letters)
        ctx.fillPath()
        for run in runs {
            let pictures = run.outlines.indices.filter { run.outlines[$0] == nil }
            guard !pictures.isEmpty else { continue }
            ctx.saveGState()
            ctx.translateBy(x: run.origin.x, y: run.origin.y)
            ctx.scaleBy(x: 1, y: -1)
            ctx.textMatrix = .identity
            CTFontDrawGlyphs(run.font, pictures.map { run.glyphs[$0] }, pictures.map { run.positions[$0] }, pictures.count, ctx)
            ctx.restoreGState()
        }
    }

    /// One run of a laid-out line: its font, its glyphs, their positions from `origin`, the line's left
    /// end on its baseline, and each glyph's outline in the image's px, or nil for a glyph the font
    /// draws as a picture.
    private struct GlyphRun {
        let font: CTFont
        let glyphs: [CGGlyph]
        let positions: [CGPoint]
        let origin: CGPoint
        let outlines: [CGPath?]

        init?(_ run: CTRun, at origin: CGPoint) {
            guard let value = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName],
                  CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID() else { return nil }
            let font = value as! CTFont
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            outlines = zip(glyphs, positions).map { glyph, position in
                // Glyph outlines are drawn with y up; the image's px run down from the top.
                var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: origin.x + position.x, ty: origin.y - position.y)
                return CTFontCreatePathForGlyph(font, glyph, &transform)
            }
            self.font = font
            self.glyphs = glyphs
            self.positions = positions
            self.origin = origin
        }
    }
}

// MARK: - A full rendering

extension PixelSize {
    /// The size an image file's header gives, turned by its orientation flag: the size as displayed.
    init?(imageProperties properties: [CFString: Any]) {
        guard let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        let turned = (5...8).contains(properties[kCGImagePropertyOrientation] as? Int ?? 1)
        self.init(width: turned ? height : width, height: turned ? width : height)
    }

    /// The size as displayed of the image file at `url`, from its header alone.
    init?(imageAt url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        self.init(imageProperties: properties)
    }
}

/// A screenshot with its drawing's marks, as PNG: what Done, Send and Copy Drawing hand on. It is the
/// screenshot as displayed, at its exact pixel size and in its own colour space, so every pixel the
/// marks leave alone is the screenshot's own. Safe off the main thread.
enum Rendering {
    enum Failure: Error, CustomStringConvertible {
        /// The file is not an image, or not the one the drawing was made on.
        case unreadableImage(String)
        /// The bitmap could not be made, or the PNG could not be written.
        case writeFailed(String)

        var code: CommandError {
            switch self {
            case .unreadableImage: return .unreadableImage
            case .writeFailed: return .writeFailed
            }
        }

        var description: String {
            switch self {
            case .unreadableImage(let detail), .writeFailed(let detail): return detail
            }
        }
    }

    /// The image at `url` with `drawing` over it. Throws a `Failure`.
    static func png(of drawing: Drawing, imageAt url: URL, style: TextStyle, arrowhead: ArrowheadStyle) throws -> Data {
        let name = url.lastPathComponent
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixels = PixelSize(imageProperties: properties),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw Failure.unreadableImage("\(name) is not an image this Mac can read")
        }
        guard pixels == drawing.pixels else {
            throw Failure.unreadableImage("\(name) is \(pixels.width)x\(pixels.height); the drawing was made on \(drawing.pixels.width)x\(drawing.pixels.height)")
        }
        guard let ctx = context(for: image, pixels: pixels) else {
            throw Failure.writeFailed("could not make a \(pixels.width)x\(pixels.height) bitmap for \(name)")
        }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        // From here on the context's units are the image's px as displayed, from the top-left, y down.
        ctx.translateBy(x: 0, y: CGFloat(pixels.height))
        ctx.scaleBy(x: 1, y: -1)

        ctx.saveGState()
        // Each orientation turns or mirrors whole pixels onto whole pixels, so nothing is resampled.
        ctx.interpolationQuality = .none
        ctx.setBlendMode(.copy)
        ctx.concatenate(displayed(orientation: orientation, width: CGFloat(image.width), height: CGFloat(image.height)))
        // `draw` puts an image's first row at the top of a y-up rect; these units run y down.
        ctx.translateBy(x: 0, y: CGFloat(image.height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.restoreGState()

        drawing.draw(in: ctx, style: style, arrowhead: arrowhead)

        guard let rendered = ctx.makeImage() else {
            throw Failure.writeFailed("could not finish the \(pixels.width)x\(pixels.height) bitmap for \(name)")
        }
        let png = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil) else {
            throw Failure.writeFailed("could not start a PNG for \(name)")
        }
        // The screenshot's own DPI, so the rendering pastes at the size the screenshot does.
        var dpi = [kCGImagePropertyDPIWidth: properties[kCGImagePropertyDPIWidth], kCGImagePropertyDPIHeight: properties[kCGImagePropertyDPIHeight]]
        if (5...8).contains(orientation) {
            (dpi[kCGImagePropertyDPIWidth], dpi[kCGImagePropertyDPIHeight]) = (dpi[kCGImagePropertyDPIHeight], dpi[kCGImagePropertyDPIWidth])
        }
        CGImageDestinationAddImage(destination, rendered, dpi.compactMapValues { $0 } as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw Failure.writeFailed("could not write the PNG for \(name)")
        }
        return png as Data
    }

    /// A bitmap for the image's pixels as displayed, in the image's own colour space and depth, with
    /// alpha only when the image has it. A colour space a bitmap cannot be drawn in, or one that
    /// cannot hold coloured marks (grey, CMYK), gives way to sRGB.
    private static func context(for image: CGImage, pixels: PixelSize) -> CGContext? {
        var space = image.colorSpace
        if space?.model == .indexed { space = space?.baseColorSpace }
        let own = space.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil }
        guard let space = own ?? CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        return CGContext(data: nil, width: pixels.width, height: pixels.height, bitsPerComponent: image.bitsPerComponent > 8 ? 16 : 8,
                         bytesPerRow: 0, space: space,
                         bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue)
    }

    /// Maps the file's pixels, from its top-left with y down, to where they are displayed, for the
    /// EXIF orientation flag (1 to 8). `width` and `height` are the file's own, before turning.
    private static func displayed(orientation: Int, width w: CGFloat, height h: CGFloat) -> CGAffineTransform {
        switch orientation {
        case 2: return CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0)
        case 3: return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h)
        case 4: return CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h)
        case 5: return CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        case 6: return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)
        case 7: return CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: h, ty: w)
        case 8: return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)
        default: return .identity
        }
    }
}
