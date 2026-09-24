import AppKit
import QuartzCore

/// How the editor's own marks on the canvas look: the selection, hover, handles, dots and brush.
enum EditorStyle {
    static let selectionBlue = NSColor(srgbRed: 0x31 / 255.0, green: 0x82 / 255.0, blue: 0xed / 255.0, alpha: 1)
    /// Under the selection's blue, so the outline shows on blue and dark screenshots. It is
    /// `EditorMetrics.selectionOutlineWidth` wide, and the core puts the outline outside the mark by half that.
    static let lightEdge = NSColor(white: 1, alpha: 0.9)
    static let outlineWidth: CGFloat = 1.5
    /// The hover outline is the selection's, this faint.
    static let hoverOpacity: Float = 0.5
    static let handleFill = NSColor(srgbRed: 0.06175, green: 0.06175, blue: 0.06825, alpha: 1)
    static let haloFill = selectionBlue.withAlphaComponent(0.2)
    static let brushFill = NSColor(white: 0.5, alpha: 0.1)
    static let brushStroke = NSColor(white: 0.5, alpha: 0.25)
    static let brushWidth: CGFloat = 1
}

/// The screenshot and its marks, in image px inside one layer whose transform maps px to the picture's
/// rect, so a zoom step moves all of it in one commit. The marks are `MarkLayers`, as a card's are;
/// what is the editor's own is how each text is drawn for the zoom.
///
/// A text is drawn at the zoom's resolution, and drawn again once the zoom rests if that changed and
/// the text is in view. No text bitmap has more pixels than the part of the view the picture fills: a
/// text too large for that is drawn whole at the resolution that fits, and its part in view is drawn
/// at the zoom's resolution over it once the zoom rests. A text out of view at rest keeps no more than
/// the resolution of the whole image fitted to the view. A text holds at most two bitmaps, the one on
/// its way included, each no larger than the view in device pixels.
@MainActor
final class EditorPicture {
    /// Units are image px from the top-left corner, y down; the owner sets its transform.
    let layer = CALayer()
    /// A text's bitmap has just arrived and shows the text as it is. Called inside the transaction
    /// that put it on its layer, so whatever covered the text can go in the same frame.
    var onTextDrawn: ((Mark.ID) -> Void)?
    /// The marks of the image open now. Each `open` makes new ones, so the ones parked before it stay
    /// as they were for as long as a flight home takes its texts from them.
    private(set) var marks = MarkLayers(pixels: PixelSize(width: 0, height: 0), queue: MarkLayers.textQueue)
    private let screenshot = CALayer()
    private var contentsScale: CGFloat = 2

    /// How finely the owner wants the picture drawn.
    struct Resolution {
        /// Device px per image px at the current zoom.
        var scale: CGFloat
        /// The part of the image in view, in px.
        var visible: CGRect
        /// The most device px one text bitmap may have: those of the part of the view the picture
        /// fills, or of the whole view while none of it is in view.
        var pixels: CGFloat
        /// Device px per image px with the whole image fitted to the view: the most a text out of
        /// view keeps once the zoom rests.
        var fit: CGFloat
        /// A zoom or a resize is moving: no text is drawn again for the zoom until it rests.
        var moving: Bool
    }

    private struct State {
        let drawing: Drawing
        let geometry: EditorGeometry
        let resolution: Resolution
        let gesture: Bool
        let typing: Mark.ID?
        let covered: Mark.ID?
    }

    init() {
        layer.anchorPoint = .zero
        layer.position = .zero
        screenshot.anchorPoint = .zero
        screenshot.contentsGravity = .resize
        // The screenshot is often larger than it is shown; trilinear takes the shimmer out of that.
        screenshot.minificationFilter = .trilinear
        layer.addSublayer(screenshot)
        layer.addSublayer(marks.layer)
    }

    /// A new screenshot: its image, decoded at any size, fills `pixels`. Nil shows nothing until
    /// `setImage`. The marks shown before are parked and let go.
    func open(_ image: CGImage?, pixels: PixelSize) {
        marks.park()
        marks.layer.removeFromSuperlayer()
        marks = MarkLayers(pixels: pixels, queue: MarkLayers.textQueue)
        marks.setScale(contentsScale)
        marks.onTextDrawn = { [weak self] id in self?.onTextDrawn?(id) }
        layer.addSublayer(marks.layer)
        layer.bounds = pixels.bounds
        screenshot.frame = pixels.bounds
        screenshot.contents = image
    }

    /// The screenshot, decoded again; the marks stay as they are.
    func setImage(_ image: CGImage) {
        screenshot.contents = image
    }

    /// Keeps what is on screen as it is until the next `open`: no bitmap on its way is shown.
    func park() {
        marks.park()
    }

    /// The device pixels per point of the screen the picture is on, for the shape layers.
    func setScale(_ scale: CGFloat) {
        contentsScale = scale
        marks.setScale(scale)
    }

    /// Shows `drawing` without the mark being typed. `gesture` is true while one is under way: a
    /// text that only moved slides its bitmap along, and is drawn again once the gesture is over.
    /// `covered` is a text something else shows until its bitmap arrives, which stays hidden until then.
    func show(_ drawing: Drawing, typing: Mark.ID?, covered: Mark.ID?, geometry: EditorGeometry, resolution: Resolution, gesture: Bool) {
        let state = State(drawing: drawing, geometry: geometry, resolution: resolution, gesture: gesture, typing: typing, covered: covered)
        marks.show(drawing, arrowhead: geometry.arrowhead, layout: geometry.layout) { record, mark, text in
            Self.plan(record, mark, text, state)
        }
    }

    /// Whether the text's bitmap on screen shows it as it is now.
    func isDrawn(_ id: Mark.ID) -> Bool { marks.isDrawn(id) }

    /// Decides what a text's layers should show for the zoom. True when the text is in view.
    private static func plan(_ record: MarkLayers.Text, _ mark: Mark, _ text: Mark.Text, _ state: State) -> Bool {
        if mark.id == state.typing {
            // The text view shows the words; the bitmap is brought up to date when typing ends.
            record.wantWhole = nil
            record.wantDetail = nil
            record.clearDetail()
            record.whole.isHidden = true
            return true
        }
        let resolution = state.resolution, gesture = state.gesture, style = state.geometry.style
        let whole = MarkLayers.padded(text, box: state.geometry.layout(text).box, pointScale: state.geometry.pointScale)
            .intersection(state.drawing.pixels.bounds)
        guard !whole.isNull, !whole.isEmpty, resolution.scale > 0 else {
            record.clearWhole()
            record.clearDetail()
            record.wantWhole = nil
            record.wantDetail = nil
            return false
        }
        let fits = (resolution.pixels / (whole.width * whole.height)).squareRoot()
        let inView = whole.intersection(resolution.visible)
        let visible = !inView.isNull && !inView.isEmpty
        let scale = visible ? min(resolution.scale, fits) : min(resolution.scale, fits, resolution.fit)
        let settled = !resolution.moving && !gesture

        // The whole image, as a flight's is: the bitmap covers the part its letters touch either way,
        // so a flight's bitmap and the editor's are one target and either can take the other's.
        let fresh = MarkLayers.Target(mark: mark, region: state.drawing.pixels.bounds, scale: scale, style: style)
        let onItsWay = record.pending?.part == .whole ? record.pending?.target : nil
        let want: MarkLayers.Target
        if let drawn = record.drawn, drawn.mark == mark, drawn.style == style {
            if settled, abs(drawn.scale - scale) > scale * 0.01, visible || drawn.scale > scale {
                // Out of view it only has to be there while a pan brings it back, so the bitmap it
                // has is scaled down, several times faster than the renderer draws it again.
                want = visible ? fresh : MarkLayers.Target(mark: mark, region: drawn.region, scale: scale, style: style)
            } else if !settled, let onItsWay, onItsWay.mark == mark, onItsWay.style == style {
                // A zoom that moves on still takes the bitmap drawn for its last rest.
                want = onItsWay
            } else {
                want = drawn
            }
        } else if record.slid, gesture, let drawn = record.drawn, drawn.style == style {
            want = drawn
        } else {
            want = fresh
        }
        record.wantWhole = want

        // The part in view at the zoom's own resolution, once the whole is drawn coarser than that
        // and nothing moves. While the zoom moves the one it has stays, and the whole shows around it.
        var wantDetail: MarkLayers.Target?
        if settled, visible, want == record.drawn, want.scale < resolution.scale * 0.99 {
            let covers = { (target: MarkLayers.Target) in
                target.mark == mark && target.style == style && target.scale == resolution.scale && target.region.contains(inView)
            }
            if let shown = record.detailDrawn, covers(shown) {
                wantDetail = shown
            } else if let pending = record.pending, pending.part == .detail, covers(pending.target) {
                wantDetail = pending.target
            } else {
                wantDetail = MarkLayers.Target(mark: mark, region: MarkLayers.aligned(inView, scale: resolution.scale), scale: resolution.scale,
                                               style: style)
            }
        } else if !settled, !record.slid, let shown = record.detailDrawn, shown.mark == mark, shown.style == style {
            wantDetail = shown
        }
        record.wantDetail = wantDetail
        // Let go before its replacement comes, so the text never holds more than two bitmaps.
        if record.detailDrawn != wantDetail { record.clearDetail() }
        record.whole.isHidden = (state.covered == mark.id && record.drawn != want) || (!record.detail.isHidden && !resolution.moving)
        return visible
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
    private var shown: (overlay: EditorCore.Overlay, marks: [Mark], transform: CGAffineTransform, geometry: EditorGeometry)?

    init() {
        for edge in [hoverEdge, selectionEdge] { edge.strokeColor = EditorStyle.lightEdge.cgColor }
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
    func show(_ overlay: EditorCore.Overlay, drawing: Drawing, geometry: EditorGeometry, transform: CGAffineTransform) {
        let ids = overlay.selected + (overlay.hovered.map { [$0] } ?? [])
        let marks = drawing.marks.filter { ids.contains($0.id) }
        // An outline's path also follows the selection outline's width, the arrowhead and the text style.
        if let shown, shown.overlay == overlay, shown.marks == marks, shown.transform == transform,
           shown.geometry.metrics == geometry.metrics, shown.geometry.arrowhead == geometry.arrowhead, shown.geometry.style == geometry.style { return }
        shown = (overlay, marks, transform, geometry)
        var transform = transform
        let zoom = transform.a
        hoverEdge.lineWidth = geometry.metrics.selectionOutlineWidth
        selectionEdge.lineWidth = geometry.metrics.selectionOutlineWidth
        func outline(_ id: Mark.ID) -> CGPath? {
            guard let mark = drawing.marks.first(where: { $0.id == id }) else { return nil }
            return geometry.outline(of: mark).copy(using: &transform)
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
