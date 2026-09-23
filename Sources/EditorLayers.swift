import AppKit
import QuartzCore

/// How the editor's own marks on the canvas look: the selection, hover, handles, dots and brush.
enum EditorStyle {
    static let selectionBlue = NSColor(srgbRed: 0x31 / 255.0, green: 0x82 / 255.0, blue: 0xed / 255.0, alpha: 1)
    /// Under the selection's blue, so the outline shows on blue and dark screenshots.
    static let lightEdge = NSColor(white: 1, alpha: 0.9)
    static let outlineWidth: CGFloat = 1.5
    static let lightEdgeWidth: CGFloat = outlineWidth + 2
    /// The hover outline is the selection's, this faint.
    static let hoverOpacity: Float = 0.5
    static let handleFill = NSColor(srgbRed: 0.06175, green: 0.06175, blue: 0.06825, alpha: 1)
    static let haloFill = selectionBlue.withAlphaComponent(0.2)
    static let brushFill = NSColor(white: 0.5, alpha: 0.1)
    static let brushStroke = NSColor(white: 0.5, alpha: 0.25)
    static let brushWidth: CGFloat = 1
}

/// The screenshot and its marks, in image px inside one layer whose transform maps px to the picture's
/// rect, so a zoom step moves all of it in one commit.
///
/// A rectangle, an ellipse or an arrow is a shape layer holding the renderer's own paths
/// (`Mark.shape`). Core Animation draws it sharp at any zoom with nothing redrawn, and a change to it
/// is a new path, however large the mark.
///
/// A text is a bitmap the renderer draws, because only the renderer draws its outline. It is drawn
/// at the zoom's resolution, and drawn again once the zoom rests if that changed and the text is in
/// view. No text bitmap has more pixels than the part of the image in view has at the zoom's
/// resolution, which bounds each one by the view's own size in device pixels: a text too large for
/// that is drawn whole at the resolution that fits, and its part in view is drawn at the zoom's
/// resolution over it once the zoom rests.
@MainActor
final class EditorPicture {
    /// Units are image px from the top-left corner, y down; the owner sets its transform.
    let layer = CALayer()
    private let screenshot = CALayer()
    private var shapes: [Mark.ID: ShapeMark] = [:]
    private var texts: [Mark.ID: TextMark] = [:]
    private var contentsScale: CGFloat = 2

    /// A rectangle's, an ellipse's or an arrow's layers: the stroke, and over it the arrowhead's fill.
    private final class ShapeMark {
        let stroke = CAShapeLayer()
        let fill = CAShapeLayer()
        var mark: Mark?

        init(scale: CGFloat) {
            for shape in [stroke, fill] {
                shape.anchorPoint = .zero
                shape.contentsScale = scale
            }
            stroke.fillColor = nil
            stroke.lineCap = .round
            stroke.lineJoin = .round
            fill.strokeColor = nil
            stroke.addSublayer(fill)
        }

        func show(_ mark: Mark, _ shape: MarkShape) {
            stroke.path = shape.stroked
            stroke.lineWidth = shape.lineWidth
            stroke.strokeColor = mark.color.cgColor
            fill.path = shape.filled
            fill.fillColor = mark.color.cgColor
            self.mark = mark
        }
    }

    /// A text's bitmap, and the bitmap of its part in view when the whole is drawn coarser than the
    /// zoom needs. The part in view covers everything in view, so the whole is hidden under it while
    /// nothing moves: the coarse bitmap's softer edges would show around the sharp letters.
    private final class TextMark {
        let whole = CALayer()
        let detail = CALayer()
        /// The mark as drawn; nil until it is.
        var mark: Mark?
        /// What `whole` covers, in px, and its resolution, in device px per px.
        var region = CGRect.null
        var scale: CGFloat = 0
        /// `whole` was slid with a move instead of drawn again, so it may sit between device pixels.
        var slid = false
        /// What `detail` covers, in px, and its resolution; `.null` and 0 when it is not shown.
        var detailRegion = CGRect.null
        var detailScale: CGFloat = 0

        init() {
            for bitmap in [whole, detail] {
                bitmap.anchorPoint = .zero
                bitmap.contentsGravity = .resize
            }
            // A text drawn finer than it is shown shimmers without mipmaps.
            whole.minificationFilter = .trilinear
            detail.isHidden = true
        }

        func clearDetail() {
            detail.contents = nil
            detail.isHidden = true
            detailRegion = .null
            detailScale = 0
        }
    }

    /// How finely the owner wants the picture drawn.
    struct Resolution {
        /// Device px per image px at the current zoom.
        var scale: CGFloat
        /// The part of the image in view, in px.
        var visible: CGRect
        /// A zoom or a resize is moving: no text is drawn again for the zoom until it rests.
        var moving: Bool
    }

    init() {
        layer.anchorPoint = .zero
        layer.position = .zero
        screenshot.anchorPoint = .zero
        screenshot.contentsGravity = .resize
        // The screenshot is often larger than it is shown; trilinear takes the shimmer out of that.
        screenshot.minificationFilter = .trilinear
        layer.addSublayer(screenshot)
    }

    /// A new screenshot: its image, decoded at any size, fills `pixels`.
    func open(_ image: CGImage, pixels: PixelSize) {
        for record in shapes.values { record.stroke.removeFromSuperlayer() }
        for record in texts.values {
            record.whole.removeFromSuperlayer()
            record.detail.removeFromSuperlayer()
        }
        shapes = [:]
        texts = [:]
        layer.bounds = pixels.bounds
        screenshot.frame = pixels.bounds
        screenshot.contents = image
    }

    /// The device pixels per point of the screen the picture is on, for the shape layers.
    func setScale(_ scale: CGFloat) {
        contentsScale = scale
        for record in shapes.values {
            record.stroke.contentsScale = scale
            record.fill.contentsScale = scale
        }
    }

    /// Shows `drawing` without the mark being typed. `gesture` is true while one is under way: a
    /// text that only moved slides its bitmap along, and is drawn again once the gesture is over.
    func show(_ drawing: Drawing, typing: Mark.ID?, geometry: EditorGeometry, style: TextStyle, arrowhead: ArrowheadStyle,
              resolution: Resolution, gesture: Bool) {
        var layers: [CALayer] = [screenshot]
        var seen = Set<Mark.ID>()
        for mark in drawing.marks {
            seen.insert(mark.id)
            if case .text(let text) = mark.geometry {
                let record = texts[mark.id] ?? TextMark()
                if mark.id == typing {
                    // Drawn again from scratch when typing ends.
                    record.mark = nil
                    record.clearDetail()
                    record.whole.isHidden = true
                } else {
                    show(record, mark, text, in: drawing, geometry: geometry, style: style, resolution: resolution, gesture: gesture)
                    record.whole.isHidden = !record.detail.isHidden && !resolution.moving
                }
                texts[mark.id] = record
                layers.append(record.whole)
                layers.append(record.detail)
            } else {
                let record = shapes[mark.id] ?? ShapeMark(scale: contentsScale)
                if record.mark != mark, let shape = mark.shape(pointScale: drawing.pointScale, arrowhead: arrowhead) {
                    record.show(mark, shape)
                }
                shapes[mark.id] = record
                layers.append(record.stroke)
            }
        }
        for id in shapes.keys where !seen.contains(id) {
            shapes[id]?.stroke.removeFromSuperlayer()
            shapes[id] = nil
        }
        for id in texts.keys where !seen.contains(id) {
            texts[id]?.whole.removeFromSuperlayer()
            texts[id]?.detail.removeFromSuperlayer()
            texts[id] = nil
        }
        if layer.sublayers.map({ $0.map(ObjectIdentifier.init) }) != layers.map(ObjectIdentifier.init) {
            layer.sublayers = layers
        }
    }

    private func show(_ record: TextMark, _ mark: Mark, _ text: Mark.Text, in drawing: Drawing, geometry: EditorGeometry, style: TextStyle,
                      resolution: Resolution, gesture: Bool) {
        let whole = Self.padded(text, geometry: geometry).intersection(drawing.pixels.bounds)
        guard !whole.isNull, !whole.isEmpty, resolution.scale > 0 else {
            record.whole.contents = nil
            record.clearDetail()
            record.mark = mark
            return
        }
        // No more pixels than the part of the image in view has at the zoom's resolution.
        let budget = resolution.visible.isNull || resolution.visible.isEmpty
            ? .infinity : resolution.visible.width * resolution.visible.height * resolution.scale * resolution.scale
        let fits = (budget / (whole.width * whole.height)).squareRoot()
        let scale = min(resolution.scale, fits)
        let inView = whole.intersection(resolution.visible)
        let visible = !inView.isNull && !inView.isEmpty

        if record.mark != mark {
            if gesture, let old = record.mark, let offset = Self.translation(from: old, to: mark, geometry: geometry) {
                record.region = record.region.offsetBy(dx: offset.dx, dy: offset.dy)
                record.whole.frame = record.region
                // The part in view would slide out of view; the whole shows until the gesture ends.
                record.clearDetail()
                record.slid = true
            } else {
                draw(record, mark, whole: whole, scale: scale, in: drawing, style: style)
            }
            record.mark = mark
        } else if !gesture, record.slid {
            draw(record, mark, whole: whole, scale: scale, in: drawing, style: style)
        } else if !resolution.moving, !gesture, visible, abs(record.scale - scale) > scale * 0.01 {
            draw(record, mark, whole: whole, scale: scale, in: drawing, style: style)
        }

        // The part in view at the zoom's own resolution, while the whole is coarser and nothing moves.
        guard !resolution.moving, !gesture, visible, record.scale < resolution.scale * 0.99 else {
            if resolution.moving || gesture { return }
            record.clearDetail()
            return
        }
        let region = Self.aligned(inView, scale: resolution.scale)
        if record.detailScale == resolution.scale, record.detailRegion.contains(inView) { return }
        record.detail.frame = region
        record.detail.contents = Self.bitmap(of: mark, in: drawing, region: region, scale: resolution.scale, style: style)
        record.detail.isHidden = false
        record.detailRegion = region
        record.detailScale = resolution.scale
    }

    /// Draws the whole text at `scale` over `whole`, grown to whole device pixels.
    private func draw(_ record: TextMark, _ mark: Mark, whole: CGRect, scale: CGFloat, in drawing: Drawing, style: TextStyle) {
        record.region = Self.aligned(whole, scale: scale)
        record.whole.frame = record.region.isNull ? .zero : record.region
        record.whole.contents = Self.bitmap(of: mark, in: drawing, region: record.region, scale: scale, style: style)
        record.scale = scale
        record.slid = false
        record.clearDetail()
    }

    /// The offset that takes `old` to `new`, when that is all that changed and the renderer would
    /// draw the moved text as the old one moved. A text with no wrap width wraps at the image's edge,
    /// so a sideways move slides it only while its lines break in the same places.
    private static func translation(from old: Mark, to new: Mark, geometry: EditorGeometry) -> CGVector? {
        guard old.color == new.color, old.agent == new.agent, old.colorChosen == new.colorChosen,
              case .text(let a) = old.geometry, case .text(let b) = new.geometry,
              a.text == b.text, a.size == b.size, a.wrap == b.wrap else { return nil }
        let offset = CGVector(dx: b.origin.x - a.origin.x, dy: b.origin.y - a.origin.y)
        if a.wrap == nil, offset.dx != 0 {
            let before = geometry.layout(a).lines, after = geometry.layout(b).lines
            guard before.count == after.count,
                  zip(before, after).allSatisfy({ CTLineGetStringRange($0.ctLine).length == CTLineGetStringRange($1.ctLine).length })
            else { return nil }
        }
        return offset
    }

    /// What the renderer may touch for a text, in px: its box grown by its outline and a quarter of
    /// its size, for glyphs that reach past their line.
    private static func padded(_ text: Mark.Text, geometry: EditorGeometry) -> CGRect {
        let pad = (Mark.Text.outlineWidth + text.size / 4) * geometry.pointScale
        return geometry.layout(text).box.insetBy(dx: -pad - 1, dy: -pad - 1)
    }

    /// `rect` grown to whole device pixels at `scale`, so a bitmap drawn over it meets them exactly.
    private static func aligned(_ rect: CGRect, scale: CGFloat) -> CGRect {
        guard !rect.isNull, !rect.isEmpty, scale > 0 else { return .null }
        let minX = (rect.minX * scale).rounded(.down) / scale, minY = (rect.minY * scale).rounded(.down) / scale
        let maxX = (rect.maxX * scale).rounded(.up) / scale, maxY = (rect.maxY * scale).rounded(.up) / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// `mark` drawn by the renderer over `region` of the image, `scale` device px to a px.
    private static func bitmap(of mark: Mark, in drawing: Drawing, region: CGRect, scale: CGFloat, style: TextStyle) -> CGImage? {
        guard !region.isNull else { return nil }
        let width = Int((region.width * scale).rounded()), height = Int((region.height * scale).rounded())
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // From here on the context's units are the image's px, y down, as the renderer expects.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -region.minX, y: -region.minY)
        // A text has no arrowhead.
        mark.draw(in: ctx, pointScale: drawing.pointScale, imageWidth: CGFloat(drawing.pixels.width), style: style, arrowhead: .standard)
        return ctx.makeImage()
    }
}

/// The core's overlay, drawn at screen size: the selection and hover outlines, the frame, the resize
/// handles, the arrow dots and their halo, and the brush, which also draws a Text tool drag's width.
/// Everything is in the editor's coordinates, from exactly the positions the core gives, so what is
/// drawn is what a press is tested against.
@MainActor
final class EditorOverlayLayers {
    /// The owner puts this over the picture.
    let layer = CALayer()
    private let hover = CALayer()
    private let hoverEdge = CAShapeLayer(), hoverLine = CAShapeLayer()
    private let selectionEdge = CAShapeLayer(), selectionLine = CAShapeLayer()
    private let brush = CAShapeLayer()
    private let handles = CAShapeLayer()
    private let halos = CAShapeLayer()
    private let dots = CAShapeLayer()
    private var shown: (overlay: EditorCore.Overlay, marks: [Mark], transform: CGAffineTransform)?

    init() {
        for edge in [hoverEdge, selectionEdge] {
            edge.strokeColor = EditorStyle.lightEdge.cgColor
            edge.lineWidth = EditorStyle.lightEdgeWidth
        }
        for line in [hoverLine, selectionLine] {
            line.strokeColor = EditorStyle.selectionBlue.cgColor
            line.lineWidth = EditorStyle.outlineWidth
        }
        for outline in [hoverEdge, hoverLine, selectionEdge, selectionLine] {
            outline.fillColor = nil
            outline.lineJoin = .round
            outline.lineCap = .round
        }
        hover.opacity = EditorStyle.hoverOpacity
        hover.addSublayer(hoverEdge)
        hover.addSublayer(hoverLine)
        brush.fillColor = EditorStyle.brushFill.cgColor
        brush.strokeColor = EditorStyle.brushStroke.cgColor
        brush.lineWidth = EditorStyle.brushWidth
        handles.fillColor = EditorStyle.handleFill.cgColor
        handles.strokeColor = EditorStyle.selectionBlue.cgColor
        handles.lineWidth = EditorStyle.outlineWidth
        halos.fillColor = EditorStyle.haloFill.cgColor
        dots.fillColor = NSColor.white.cgColor
        dots.strokeColor = EditorStyle.selectionBlue.cgColor
        dots.lineWidth = EditorStyle.outlineWidth
        for sublayer in [hover, selectionEdge, selectionLine, brush, handles, halos, dots] {
            layer.addSublayer(sublayer)
        }
    }

    /// Shape layers render at 1x unless told otherwise.
    func setScale(_ scale: CGFloat) {
        for shape in [hoverEdge, hoverLine, selectionEdge, selectionLine, brush, handles, halos, dots] { shape.contentsScale = scale }
    }

    /// Draws `overlay` for `drawing`, with `transform` taking image px to the editor's coordinates.
    func show(_ overlay: EditorCore.Overlay, drawing: Drawing, geometry: EditorGeometry, arrowhead: ArrowheadStyle, transform: CGAffineTransform) {
        let ids = overlay.selected + (overlay.hovered.map { [$0] } ?? [])
        let marks = drawing.marks.filter { ids.contains($0.id) }
        if let shown, shown.overlay == overlay, shown.marks == marks, shown.transform == transform { return }
        shown = (overlay, marks, transform)
        var transform = transform
        let zoom = transform.a
        func outline(_ id: Mark.ID) -> CGPath? {
            guard let mark = drawing.marks.first(where: { $0.id == id }) else { return nil }
            let path = CGMutablePath()
            switch mark.geometry {
            case .rectangle(let frame): path.addRect(frame)
            case .ellipse(let frame): path.addEllipse(in: frame)
            case .arrow:
                // The outline follows the body and the head as the renderer draws them.
                if let shape = mark.shape(pointScale: geometry.pointScale, arrowhead: arrowhead) {
                    for part in [shape.stroked, shape.filled].compactMap({ $0 }) { path.addPath(part) }
                }
            case .text: path.addRect(geometry.extent(of: mark))
            }
            return path.copy(using: &transform)
        }

        let hovered = CGMutablePath()
        if let id = overlay.hovered, let path = outline(id) { hovered.addPath(path) }
        hoverEdge.path = hovered
        hoverLine.path = hovered

        let selected = CGMutablePath()
        for id in overlay.selected { if let path = outline(id) { selected.addPath(path) } }
        if let frame = overlay.frame { selected.addRect(frame, transform: transform) }
        selectionEdge.path = selected
        selectionLine.path = selected

        let brushPath = CGMutablePath()
        for rect in [overlay.brush, overlay.wrap].compactMap({ $0 }) { brushPath.addRect(rect, transform: transform) }
        brush.path = brushPath

        let squares = CGMutablePath()
        for handle in overlay.handles { if let square = handle.square { squares.addRect(square, transform: transform) } }
        handles.path = squares

        let haloPath = CGMutablePath(), dotPath = CGMutablePath()
        for dot in overlay.dots {
            let center = dot.center.applying(transform)
            if dot.hovered {
                let r = dot.hitRadius * zoom
                haloPath.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
            }
            let r = dot.radius * zoom
            dotPath.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        }
        halos.path = haloPath
        dots.path = dotPath
    }
}
