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
/// Each mark has a layer of its own, drawn by the renderer and redrawn only when that mark changes: a
/// text of a few lines takes tens of milliseconds to draw, so one layer for every mark would stall
/// every drag once a drawing holds a note. Those layers are drawn no finer than the whole image fitted
/// to the view, which bounds their memory, and they always cover their whole mark, so a zoom out
/// never shows a mark missing. Closer than that fit, one more layer draws what is in view at the
/// zoom's own resolution once the zoom is still, and covers the mark layers until the next zoom moves.
@MainActor
final class EditorPicture {
    /// Units are image px from the top-left corner, y down; the owner sets its transform.
    let layer = CALayer()
    private let screenshot = CALayer()
    private let detail = CALayer()
    private var drawn: [Mark.ID: DrawnMark] = [:]
    /// The marks the detail layer shows, and where and how finely it drew them.
    private var detailMarks: [Mark] = []
    private var detailRegion = CGRect.null
    private var detailScale: CGFloat = 0

    /// One mark's layer and what its bitmap shows.
    private struct DrawnMark {
        let layer: CALayer = {
            let layer = CALayer()
            layer.anchorPoint = .zero
            layer.contentsGravity = .resize
            return layer
        }()
        /// The mark as drawn; nil until it is.
        var mark: Mark?
        /// What the bitmap covers, in px, and its resolution, in device px per px.
        var region = CGRect.null
        var scale: CGFloat = 0
        /// The bitmap was slid with a move instead of redrawn, so it may sit between device pixels.
        var slid = false
    }

    /// How finely the owner wants the picture drawn.
    struct Resolution {
        /// Device px per image px for the mark layers.
        var marks: CGFloat
        /// The part of the image in view and the zoom's own resolution, while that is finer than
        /// `marks`; nil when it is not.
        var detail: (region: CGRect, scale: CGFloat)?
        /// A zoom is moving: nothing is redrawn for the zoom, and the mark layers show under the
        /// detail layer, which the zoom is stretching.
        var moving: Bool
    }

    init() {
        layer.anchorPoint = .zero
        layer.position = .zero
        for sublayer in [screenshot, detail] {
            sublayer.anchorPoint = .zero
            sublayer.contentsGravity = .resize
        }
        // The screenshot is often larger than it is shown; trilinear takes the shimmer out of that.
        screenshot.minificationFilter = .trilinear
        layer.addSublayer(screenshot)
        layer.addSublayer(detail)
    }

    /// A new screenshot: its image, decoded at any size, fills `pixels`.
    func open(_ image: CGImage, pixels: PixelSize) {
        for record in drawn.values { record.layer.removeFromSuperlayer() }
        drawn = [:]
        clearDetail()
        layer.bounds = pixels.bounds
        screenshot.frame = pixels.bounds
        screenshot.contents = image
    }

    /// Shows `drawing` without the mark being typed. `sliding` is true while a gesture is under way:
    /// a mark that only moved slides its bitmap along, and is redrawn once the gesture is over.
    func show(_ drawing: Drawing, typing: Mark.ID?, geometry: EditorGeometry, style: TextStyle, arrowhead: ArrowheadStyle,
              resolution: Resolution, sliding: Bool) {
        var layers: [CALayer] = [screenshot]
        var changed = false
        var seen = Set<Mark.ID>()
        for mark in drawing.marks {
            seen.insert(mark.id)
            var record = drawn[mark.id] ?? DrawnMark()
            if mark.id != typing {
                if record.mark != mark || record.scale != resolution.marks || (record.slid && !sliding) {
                    changed = true
                    if sliding, record.scale == resolution.marks, let old = record.mark, let offset = Self.translation(from: old, to: mark, geometry: geometry) {
                        record.region = record.region.offsetBy(dx: offset.dx, dy: offset.dy)
                        record.layer.frame = record.region
                        record.slid = true
                    } else {
                        record.region = Self.padded(mark, geometry: geometry, arrowhead: arrowhead).intersection(drawing.pixels.bounds)
                        record.region = Self.aligned(record.region, scale: resolution.marks)
                        record.layer.frame = record.region.isNull ? .zero : record.region
                        record.layer.contents = Self.bitmap(of: [mark], in: drawing, region: record.region, scale: resolution.marks,
                                                            style: style, arrowhead: arrowhead)
                        record.slid = false
                    }
                    record.mark = mark
                    record.scale = resolution.marks
                }
            } else if record.mark != nil {
                // Drawn again from scratch when typing ends.
                record.mark = nil
            }
            drawn[mark.id] = record
            layers.append(record.layer)
        }
        for id in drawn.keys where !seen.contains(id) {
            drawn[id]?.layer.removeFromSuperlayer()
            drawn[id] = nil
            changed = true
        }

        let showing = drawing.marks.filter { $0.id != typing }
        if let wanted = resolution.detail, !resolution.moving {
            if changed || showing != detailMarks || wanted.region != detailRegion || wanted.scale != detailScale {
                let region = Self.aligned(wanted.region, scale: wanted.scale)
                let inView = showing.filter { drawn[$0.id]?.region.intersects(region) == true }
                detail.frame = region
                detail.contents = Self.bitmap(of: inView, in: drawing, region: region, scale: wanted.scale, style: style, arrowhead: arrowhead)
                detailMarks = showing
                detailRegion = wanted.region
                detailScale = wanted.scale
            }
            detail.isHidden = false
        } else if resolution.moving, detail.contents != nil, showing == detailMarks {
            detail.isHidden = false
        } else {
            clearDetail()
        }
        for mark in drawing.marks {
            drawn[mark.id]?.layer.isHidden = mark.id == typing || (!detail.isHidden && !resolution.moving)
        }
        layers.append(detail)
        if layer.sublayers.map({ $0.map(ObjectIdentifier.init) }) != layers.map(ObjectIdentifier.init) {
            layer.sublayers = layers
        }
    }

    private func clearDetail() {
        detail.contents = nil
        detail.isHidden = true
        detailMarks = []
        detailRegion = .null
        detailScale = 0
    }

    /// The offset that takes `old` to `new`, when that is all that changed and the renderer would
    /// draw the moved mark as the old one moved. A text with no wrap width wraps at the image's edge,
    /// so a sideways move slides it only while its lines break in the same places.
    private static func translation(from old: Mark, to new: Mark, geometry: EditorGeometry) -> CGVector? {
        guard old.color == new.color, old.agent == new.agent, old.colorChosen == new.colorChosen else { return nil }
        let offset: CGVector
        switch (old.geometry, new.geometry) {
        case (.rectangle(let a), .rectangle(let b)), (.ellipse(let a), .ellipse(let b)):
            guard a.size == b.size else { return nil }
            offset = CGVector(dx: b.minX - a.minX, dy: b.minY - a.minY)
        case (.arrow(let a), .arrow(let b)):
            offset = CGVector(dx: b.start.x - a.start.x, dy: b.start.y - a.start.y)
            // Both ends moved by one offset, which floating point may round apart by an ulp.
            guard a.bend == b.bend, abs(b.end.x - a.end.x - offset.dx) < 1e-6, abs(b.end.y - a.end.y - offset.dy) < 1e-6 else { return nil }
        case (.text(let a), .text(let b)):
            offset = CGVector(dx: b.origin.x - a.origin.x, dy: b.origin.y - a.origin.y)
            guard a.text == b.text, a.size == b.size, a.wrap == b.wrap else { return nil }
            if a.wrap == nil, offset.dx != 0 {
                let before = geometry.layout(a).lines, after = geometry.layout(b).lines
                guard before.count == after.count,
                      zip(before, after).allSatisfy({ CTLineGetStringRange($0.ctLine).length == CTLineGetStringRange($1.ctLine).length })
                else { return nil }
            }
        default:
            return nil
        }
        return offset
    }

    /// What the renderer may touch for `mark`, in px: its extent grown by half its stroke, an
    /// arrowhead's half width, or, for a text, its outline and a quarter of its size for glyphs that
    /// reach past their line.
    private static func padded(_ mark: Mark, geometry: EditorGeometry, arrowhead: ArrowheadStyle) -> CGRect {
        let stroke = Mark.strokeWidth * geometry.pointScale
        let pad: CGFloat
        switch mark.geometry {
        case .rectangle, .ellipse: pad = stroke / 2
        case .arrow: pad = stroke * max(arrowhead.width, arrowhead.length, 1)
        case .text(let text): pad = (Mark.Text.outlineWidth + text.size / 4) * geometry.pointScale
        }
        return geometry.extent(of: mark).insetBy(dx: -pad - 1, dy: -pad - 1)
    }

    /// `rect` grown to whole device pixels at `scale`, so a bitmap drawn over it meets them exactly.
    private static func aligned(_ rect: CGRect, scale: CGFloat) -> CGRect {
        guard !rect.isNull, !rect.isEmpty, scale > 0 else { return .null }
        let minX = (rect.minX * scale).rounded(.down) / scale, minY = (rect.minY * scale).rounded(.down) / scale
        let maxX = (rect.maxX * scale).rounded(.up) / scale, maxY = (rect.maxY * scale).rounded(.up) / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// `marks` drawn by the renderer over `region` of the image, `scale` device px to a px.
    private static func bitmap(of marks: [Mark], in drawing: Drawing, region: CGRect, scale: CGFloat,
                               style: TextStyle, arrowhead: ArrowheadStyle) -> CGImage? {
        guard !region.isNull, !marks.isEmpty else { return nil }
        let width = Int((region.width * scale).rounded()), height = Int((region.height * scale).rounded())
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // From here on the context's units are the image's px, y down, as the renderer expects.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -region.minX, y: -region.minY)
        Drawing(key: drawing.key, pixels: drawing.pixels, pointScale: drawing.pointScale, marks: marks)
            .draw(in: ctx, style: style, arrowhead: arrowhead)
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
            case .arrow(let arrow):
                // The outline follows the body and the head as the renderer draws them.
                let body = arrow.body(pointScale: geometry.pointScale)
                let head = Arrowhead(body: body, strokeWidth: Mark.strokeWidth * geometry.pointScale, style: arrowhead)
                if head.bodyEnd > 0 { path.addPath(body.path(upTo: head.bodyEnd)) }
                path.addPath(head.path)
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
