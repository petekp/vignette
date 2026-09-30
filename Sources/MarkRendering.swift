import AppKit
import CoreText
import ImageIO

// How marks look, drawn by one function for every place a drawing is seen: the editor's full
// rendering, a card's thumbnail, and a card in flight. Pure Core Graphics and Core Text, so any of
// them can run off the main thread.

/// How marks are painted, from settings.json's `ui` (`UITweaks.markStyle`): the stroke and the edge
/// around every mark, the colour that says who drew a mark, the words' colour, the shadows' strength,
/// and the arrowhead's proportions. Widths are in pt of the drawing.
struct MarkStyle: Equatable, Sendable {
    var strokeWidth: CGFloat
    /// The edge outside a stroke on both sides, and outside a note's tag. It keeps a mark visible on
    /// a dark or busy screenshot, and on one of its own colour.
    var edgeWidth: CGFloat
    var personColor: SRGB
    var agentColor: SRGB
    var edgeColor: SRGB
    /// The words on every tag.
    var wordColor: SRGB
    /// A multiplier on every shadow's darkness, the badge's included.
    var shadowOpacity: CGFloat
    /// An arrowhead's proportions, in multiples of the stroke width: a filled triangle this long from
    /// its tip to its base, and this wide across the base.
    var arrowheadLength: CGFloat
    var arrowheadWidth: CGFloat

    /// The tweaks' defaults.
    static let standard = UITweaks().markStyle

    /// The most of an arrow's body a head may take: a short arrow gets a smaller head of the same
    /// shape, so it still shows a body and its head never reaches back past its start.
    static let maxShareOfBody: CGFloat = 0.5

    /// The colour of `author`'s marks.
    func color(_ author: MarkColor) -> CGColor {
        switch author {
        case .person: return personColor.cgColor
        case .agent: return agentColor.cgColor
        }
    }
}

/// A colour in sRGB, from settings.json's `#rrggbb`.
struct SRGB: Equatable, Sendable {
    var red: CGFloat, green: CGFloat, blue: CGFloat

    /// `#rrggbb`, or nil for anything else.
    init?(hex: String) {
        guard hex.count == 7, hex.first == "#", hex.dropFirst().allSatisfy(\.isHexDigit),
              let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        red = CGFloat((value >> 16) & 0xff) / 255
        green = CGFloat((value >> 8) & 0xff) / 255
        blue = CGFloat(value & 0xff) / 255
    }

    /// `color` in sRGB, or nil for one that has no sRGB equivalent.
    init?(_ color: CGColor) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let components = color.converted(to: space, intent: .defaultIntent, options: nil)?.components, components.count >= 3 else { return nil }
        red = min(max(components[0], 0), 1)
        green = min(max(components[1], 0), 1)
        blue = min(max(components[2], 0), 1)
    }

    /// Defined in sRGB; Core Graphics converts it into whatever colour space it is drawn into.
    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

    /// As settings.json writes it.
    var hex: String {
        String(format: "#%02x%02x%02x", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}

/// How a note's tag and its badge are drawn. Every size is a multiple of the note's font size, from
/// the mockups: at 17 pt the tag's shadows are `0 0.5 1` at 22% and `0 3 10` at 14%.
enum NoteTag {
    /// A shadow: how far down it falls, how far it blurs, and how dark it is.
    struct Shadow {
        let y: CGFloat, blur: CGFloat, alpha: CGFloat
    }

    /// Their darkness is multiplied by `MarkStyle.shadowOpacity`.
    static let shadows = [Shadow(y: 0.18, blur: 0.59, alpha: 0.14), Shadow(y: 0.03, blur: 0.06, alpha: 0.22)]
    /// Faint: the hairline edge already sets the badge off the tag, and at the editor's size a
    /// heavier shadow read as a smudge.
    static let badgeShadow = Shadow(y: 0.05, blur: 0.2, alpha: 0.16)
    /// The badge's hairline edge, and the darkness of it and of its name.
    static let badgeEdge: CGFloat = 0.054, badgeEdgeAlpha: CGFloat = 0.22, badgeTextAlpha: CGFloat = 0.85

    /// How far past a note's tag its drawing may reach, in px, for an edge `edge` px wide: its badge
    /// above, its shadows below, and the edge all round. The badge rises at most its height, 1.36,
    /// since `badgeOverlap` is at least 0.
    static func reach(fontSize: CGFloat, edge: CGFloat) -> CGFloat { fontSize * 1.45 + edge + 1 }

    /// Draws the tag of `layout` filled with `color`, inside an edge `edge` px wide that casts its
    /// shadows, and an agent's badge: everything of a note but its words. `box` puts the tag somewhere
    /// other than the layout's own.
    static func draw(_ layout: TextLayout, color: CGColor, box: CGRect? = nil, edge: CGFloat, style: MarkStyle, in ctx: CGContext) {
        let box = box ?? layout.box
        drawTag(layout, color: color, box: box, edge: edge, style: style, in: ctx)
        if let badge = layout.badge { draw(badge, on: box, style: style, in: ctx) }
    }

    /// The tag alone: its edge with the shadows, and its fill.
    static func drawTag(_ layout: TextLayout, color: CGColor, box: CGRect, edge: CGFloat, style: MarkStyle, in ctx: CGContext) {
        let size = CTFontGetSize(layout.font)
        ctx.saveGState()
        ctx.setFillColor(style.edgeColor.cgColor)
        // Filled once per shadow: Core Graphics casts one shadow per fill.
        for shadow in shadows {
            setShadow(shadow, fontSize: size, opacity: style.shadowOpacity, in: ctx)
            ctx.addPath(TextLayout.tagPath(box.insetBy(dx: -edge, dy: -edge), radius: layout.radius + edge))
            ctx.fillPath()
        }
        ctx.restoreGState()
        fill(layout, color: color, box: box, in: ctx)
    }

    /// The tag's fill alone, in `color`.
    static func fill(_ layout: TextLayout, color: CGColor, box: CGRect, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setFillColor(color)
        ctx.addPath(TextLayout.tagPath(box, radius: layout.radius))
        ctx.fillPath()
        ctx.restoreGState()
    }

    /// An agent's badge on a tag at `box`.
    static func draw(_ badge: NoteBadge, on box: CGRect, style: MarkStyle, in ctx: CGContext) {
        let size = badge.fontSize
        let frame = badge.frame(on: box)
        let capsule = CGPath(roundedRect: frame, cornerWidth: frame.height / 2, cornerHeight: frame.height / 2, transform: nil)
        ctx.saveGState()
        setShadow(badgeShadow, fontSize: size, opacity: style.shadowOpacity, in: ctx)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.addPath(capsule)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.setStrokeColor(CGColor(gray: 0, alpha: badgeEdgeAlpha))
        ctx.setLineWidth(badgeEdge * size)
        ctx.addPath(capsule)
        ctx.strokePath()
        let logoSide = NoteBadge.logoSize * size
        let logo = CGRect(x: frame.minX + NoteBadge.padLeading * size, y: frame.midY - logoSide / 2, width: logoSide, height: logoSide)
        if let image = AgentLogos.shared.image(for: badge.label) {
            // An image is drawn with its top at its rect's greatest y; here y runs down.
            ctx.saveGState()
            ctx.translateBy(x: logo.minX, y: logo.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(origin: .zero, size: logo.size))
            ctx.restoreGState()
        }
        let line = badge.line
        var ascent: CGFloat = 0, descent: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        let origin = CGPoint(x: logo.maxX + NoteBadge.gap * size, y: frame.midY + (ascent - descent) / 2)
        ctx.setFillColor(CGColor(gray: 0, alpha: badgeTextAlpha))
        let letters = CGMutablePath()
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            for case let path? in GlyphRun(run, at: origin)?.outlines ?? [] { letters.addPath(path) }
        }
        ctx.addPath(letters)
        ctx.fillPath()
        ctx.restoreGState()
    }

    /// Core Graphics takes a shadow's offset and blur in the device's space, not the context's, so
    /// they are carried through the context's transform, which may scale and flip them.
    fileprivate static func setShadow(_ shadow: Shadow, fontSize: CGFloat, opacity: CGFloat, in ctx: CGContext) {
        let transform = ctx.userSpaceToDeviceSpaceTransform
        let down = shadow.y * fontSize, scale = abs(transform.a * transform.d - transform.b * transform.c).squareRoot()
        ctx.setShadow(offset: CGSize(width: transform.c * down, height: transform.d * down), blur: shadow.blur * fontSize * scale,
                      color: CGColor(gray: 0, alpha: min(1, shadow.alpha * opacity)))
    }
}

/// Agents' logos as bitmaps any thread can draw: `Agent.logo(for:)`'s images belong to the main
/// thread. Each is made once, the first time a note of that agent is drawn.
final class AgentLogos: @unchecked Sendable {
    static let shared = AgentLogos()
    /// Big enough for a badge on a note magnified in the editor.
    private static let side = 128
    private let lock = NSLock()
    private var images: [String: CGImage?] = [:]

    /// The logo of the agent named `name`, in any case, or the fallback symbol for one without a logo.
    func image(for name: String) -> CGImage? {
        let key = name.lowercased()
        return lock.withLock {
            if let made = images[key] { return made }
            let made = Self.bitmap(of: key)
            images[key] = .some(made)
            return made
        }
    }

    private static func bitmap(of key: String) -> CGImage? {
        let logo = key.isEmpty ? nil : Bundle.main.url(forResource: key, withExtension: "svg", subdirectory: "agents").flatMap { NSImage(contentsOf: $0) }
        guard let image = logo ?? NSImage(systemSymbolName: Agent.fallbackSymbol, accessibilityDescription: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let scale = CGFloat(side) / max(image.size.width, image.size.height, 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        image.draw(in: CGRect(x: (CGFloat(side) - size.width) / 2, y: (CGFloat(side) - size.height) / 2, width: size.width, height: size.height))
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }
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

    init(body: ArrowBody, strokeWidth: CGFloat, style: MarkStyle) {
        let bodyLength = body.length
        // Past an arc's diameter, or a curve's furthest point from the tip, no point of the body is a
        // head's length from the tip, so the head could not be aimed from one.
        let reachable = body.arc.map { 2 * $0.radius }
            ?? body.curve.map { curve in curve.samples.reduce(0) { max($0, hypot($1.x - body.end.x, $1.y - body.end.y)) } }
            ?? .infinity
        let longest = min(bodyLength * MarkStyle.maxShareOfBody, reachable)
        let shrink = min(1, longest / max(style.arrowheadLength * strokeWidth, .ulpOfOne))
        let length = style.arrowheadLength * strokeWidth * shrink
        let halfWidth = style.arrowheadWidth * strokeWidth * shrink / 2
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
    func draw(in ctx: CGContext, style: TextStyle, markStyle: MarkStyle) {
        for mark in marks {
            mark.draw(in: ctx, pointScale: pointScale, imageWidth: CGFloat(pixels.width), style: style, markStyle: markStyle)
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

    /// Strokes and fills the shape in `color`, `widening` px further out on every side: 0 for the
    /// mark itself, and its edge width for the white edge under it.
    func draw(in ctx: CGContext, color: CGColor, widening: CGFloat) {
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        if let stroked {
            ctx.setLineWidth(lineWidth + 2 * widening)
            ctx.addPath(stroked)
            ctx.strokePath()
        }
        if let filled {
            ctx.addPath(filled)
            ctx.fillPath()
            if widening > 0 {
                ctx.setLineWidth(2 * widening)
                ctx.addPath(filled)
                ctx.strokePath()
            }
        }
    }
}

extension Mark {
    /// The mark's paths for a drawing of `pointScale`. Nil for a text, whose letters only the
    /// renderer draws.
    func shape(pointScale: CGFloat, markStyle: MarkStyle) -> MarkShape? {
        let lineWidth = markStyle.strokeWidth * pointScale
        switch geometry {
        case .rectangle(let frame):
            return MarkShape(stroked: CGPath(rect: frame, transform: nil), filled: nil, lineWidth: lineWidth)
        case .ellipse(let frame):
            return MarkShape(stroked: CGPath(ellipseIn: frame, transform: nil), filled: nil, lineWidth: lineWidth)
        case .arrow(let arrow):
            let body = arrow.body(pointScale: pointScale)
            let head = Arrowhead(body: body, strokeWidth: lineWidth, style: markStyle)
            return MarkShape(stroked: head.bodyEnd > 0 ? body.path(upTo: head.bodyEnd) : nil, filled: head.path, lineWidth: lineWidth)
        case .text:
            return nil
        }
    }

    /// A shape casts the shadows of a note's tag at this size, in pt, so every mark looks lifted off
    /// the screenshot by the same amount.
    static let shadowSize: CGFloat = 17

    /// Draws the mark in its colour, inside its edge, as `Drawing.draw` does, for a drawing of
    /// `pointScale` on an image `imageWidth` px wide.
    func draw(in ctx: CGContext, pointScale: CGFloat, imageWidth: CGFloat, style: TextStyle, markStyle: MarkStyle) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let edge = markStyle.edgeWidth * pointScale
        if let shape = shape(pointScale: pointScale, markStyle: markStyle) {
            // The edge is drawn once per shadow, each time as one transparency layer, so the body's
            // edge and the head's cast one shadow together rather than one on the other.
            for shadow in NoteTag.shadows {
                ctx.saveGState()
                NoteTag.setShadow(shadow, fontSize: Self.shadowSize * pointScale, opacity: markStyle.shadowOpacity, in: ctx)
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                shape.draw(in: ctx, color: markStyle.edgeColor.cgColor, widening: edge)
                ctx.endTransparencyLayer()
                ctx.restoreGState()
            }
            shape.draw(in: ctx, color: markStyle.color(color), widening: 0)
        } else if case .text(let text) = geometry {
            let layout = TextLayout(text, imageWidth: imageWidth, pointScale: pointScale, style: style.forMark(self))
            NoteTag.draw(layout, color: markStyle.color(color), edge: edge, style: markStyle, in: ctx)
            NoteTag.drawWords(layout, ink: markStyle.wordColor.cgColor, in: ctx)
        }
    }
}

extension NoteTag {
    /// Every letter filled in `ink`, in one pass. A glyph with no outline, such as a colour emoji, is
    /// drawn as the font draws it, in its own colours.
    static func drawWords(_ layout: TextLayout, ink: CGColor, in ctx: CGContext) {
        let runs = layout.lines.flatMap { line in
            ((CTLineGetGlyphRuns(line.ctLine) as? [CTRun]) ?? []).compactMap { GlyphRun($0, at: CGPoint(x: line.rect.minX, y: line.baseline)) }
        }
        let letters = CGMutablePath()
        for run in runs {
            for case let path? in run.outlines { letters.addPath(path) }
        }
        ctx.setFillColor(ink)
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
    struct GlyphRun {
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

        /// What a card says, short enough for its mark; `description` has the detail for the log.
        var reason: String {
            switch self {
            case .unreadableImage: return "The screenshot could not be read"
            case .writeFailed: return "The drawing could not be saved"
            }
        }
    }

    /// The image at `url` with `drawing` over it. Throws a `Failure`.
    static func png(of drawing: Drawing, imageAt url: URL, style: TextStyle, markStyle: MarkStyle) throws -> Data {
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

        drawing.draw(in: ctx, style: style, markStyle: markStyle)

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
