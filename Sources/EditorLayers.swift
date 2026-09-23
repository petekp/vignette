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
/// rect, so a zoom step moves all of it in one commit.
///
/// A rectangle, an ellipse or an arrow is a shape layer holding the renderer's own paths
/// (`Mark.shape`). Core Animation draws it sharp at any zoom with nothing redrawn, and a change to it
/// is a new path, however large the mark.
///
/// A text is a bitmap the renderer draws on `textQueue`, because only the renderer draws its outline.
/// It is drawn at the zoom's resolution, and drawn again once the zoom rests if that changed and the
/// text is in view. Until a new bitmap arrives the old one stays, scaled, and a text that only moved
/// slides it. No text bitmap has more pixels than the part of the view the picture fills: a text too
/// large for that is drawn whole at the resolution that fits, and its part in view is drawn at the
/// zoom's resolution over it once the zoom rests. A text out of view at rest keeps no more than the
/// resolution of the whole image fitted to the view. A text holds at most two bitmaps, the one on its
/// way included, each no larger than the view in device pixels.
@MainActor
final class EditorPicture {
    /// Where the texts' bitmaps are drawn: one serial queue for what the editor shows, apart from any
    /// export's, so a long export never delays the screen.
    nonisolated static let textQueue = DispatchQueue(label: "vignette.editor-texts", qos: .userInteractive)

    /// Units are image px from the top-left corner, y down; the owner sets its transform.
    let layer = CALayer()
    /// A text's bitmap has just arrived and shows the text as it is. Called inside the transaction
    /// that put it on its layer, so whatever covered the text can go in the same frame.
    var onTextDrawn: ((Mark.ID) -> Void)?
    private let screenshot = CALayer()
    private var shapes: [Mark.ID: ShapeMark] = [:]
    private var texts: [Mark.ID: TextMark] = [:]
    private var contentsScale: CGFloat = 2
    /// The last `show`, by which a bitmap that arrives later is placed.
    private var state: State?
    /// Counts `open` and `park`: a draw asked for before either is never shown.
    private var session = 0
    /// After `park`, nothing changes until the next `open`.
    private var parked = false

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

    /// What a text bitmap is drawn for: the mark, the part of the image it covers, in px, and its
    /// resolution, in device px per px.
    private struct TextTarget: Equatable {
        let mark: Mark
        let region: CGRect
        let scale: CGFloat
    }

    private enum Part { case whole, detail }

    /// What a text wants drawn now. A queued draw reads it before it starts, and is skipped when its
    /// text no longer wants it.
    private final class Wanted: @unchecked Sendable {
        private let lock = NSLock()
        private var targets: [TextTarget] = []

        func set(_ targets: [TextTarget]) { lock.withLock { self.targets = targets } }
        func contains(_ target: TextTarget) -> Bool { lock.withLock { targets.contains(target) } }
    }

    /// A text's bitmap, and the bitmap of its part in view when the whole is drawn coarser than the
    /// zoom needs. The part in view covers everything in view, so the whole is hidden under it while
    /// nothing moves: the coarse bitmap's softer edges would show around the sharp letters.
    private final class TextMark {
        let whole = CALayer()
        let detail = CALayer()
        /// What `whole` and `detail` show; nil when they show nothing.
        var drawn: TextTarget?
        var detailDrawn: TextTarget?
        /// What they should show, as of the last update.
        var wantWhole: TextTarget?
        var wantDetail: TextTarget?
        /// The one draw on its way for this text.
        var pending: (part: Part, target: TextTarget)?
        let wanted = Wanted()

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
            detailDrawn = nil
        }
    }

    /// What a draw on the queue came back with.
    private enum Result {
        /// Its text no longer wanted it when its turn came.
        case skipped
        /// Nil when there was nothing to draw into.
        case drawn(CGImage?)
    }

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
        let style: TextStyle
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
    }

    /// A new screenshot: its image, decoded at any size, fills `pixels`.
    func open(_ image: CGImage, pixels: PixelSize) {
        session += 1
        parked = false
        state = nil
        for record in shapes.values { record.stroke.removeFromSuperlayer() }
        for record in texts.values {
            record.wanted.set([])
            record.whole.removeFromSuperlayer()
            record.detail.removeFromSuperlayer()
        }
        shapes = [:]
        texts = [:]
        layer.bounds = pixels.bounds
        screenshot.frame = pixels.bounds
        screenshot.contents = image
    }

    /// Keeps what is on screen as it is until the next `open`: no bitmap on its way is shown.
    func park() {
        session += 1
        parked = true
        for record in texts.values {
            record.wanted.set([])
            record.pending = nil
        }
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
    /// `covered` is a text something else shows until its bitmap arrives, which stays hidden until then.
    func show(_ drawing: Drawing, typing: Mark.ID?, covered: Mark.ID?, geometry: EditorGeometry, style: TextStyle, resolution: Resolution,
              gesture: Bool) {
        guard !parked else { return }
        let state = State(drawing: drawing, geometry: geometry, style: style, resolution: resolution, gesture: gesture, typing: typing, covered: covered)
        self.state = state
        var layers: [CALayer] = [screenshot]
        var seen = Set<Mark.ID>()
        var inView: [TextMark] = [], outOfView: [TextMark] = []
        for mark in drawing.marks {
            seen.insert(mark.id)
            if case .text(let text) = mark.geometry {
                let record = texts[mark.id] ?? TextMark()
                texts[mark.id] = record
                if update(record, mark, text, state) { inView.append(record) } else { outOfView.append(record) }
                layers.append(record.whole)
                layers.append(record.detail)
            } else {
                let record = shapes[mark.id] ?? ShapeMark(scale: contentsScale)
                if record.mark != mark, let shape = mark.shape(pointScale: drawing.pointScale, arrowhead: geometry.arrowhead) {
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
            texts[id]?.wanted.set([])
            texts[id]?.whole.removeFromSuperlayer()
            texts[id]?.detail.removeFromSuperlayer()
            texts[id] = nil
        }
        if layer.sublayers.map({ $0.map(ObjectIdentifier.init) }) != layers.map(ObjectIdentifier.init) {
            layer.sublayers = layers
        }
        // The texts in view are drawn first.
        for record in inView + outOfView { schedule(record, state) }
    }

    /// Whether the text's bitmap on screen shows it as it is now.
    func isDrawn(_ id: Mark.ID) -> Bool {
        guard let record = texts[id] else { return false }
        return record.drawn == record.wantWhole
    }

    /// Decides what a text's layers should show and places what they have. True when the text is in view.
    @discardableResult
    private func update(_ record: TextMark, _ mark: Mark, _ text: Mark.Text, _ state: State) -> Bool {
        if mark.id == state.typing {
            // The text view shows the words; the bitmap is brought up to date when typing ends.
            record.wantWhole = nil
            record.wantDetail = nil
            record.wanted.set([])
            record.clearDetail()
            record.whole.isHidden = true
            return true
        }
        let resolution = state.resolution, gesture = state.gesture
        let whole = Self.padded(text, geometry: state.geometry).intersection(state.drawing.pixels.bounds)
        guard !whole.isNull, !whole.isEmpty, resolution.scale > 0 else {
            record.whole.contents = nil
            record.drawn = nil
            record.clearDetail()
            record.wantWhole = nil
            record.wantDetail = nil
            record.wanted.set([])
            return false
        }
        let fits = (resolution.pixels / (whole.width * whole.height)).squareRoot()
        let inView = whole.intersection(resolution.visible)
        let visible = !inView.isNull && !inView.isEmpty
        let scale = visible ? min(resolution.scale, fits) : min(resolution.scale, fits, resolution.fit)
        let settled = !resolution.moving && !gesture

        // The bitmap it has, where it belongs: a text that only moved slides it.
        var slid = false
        if let drawn = record.drawn {
            var frame = drawn.region
            if drawn.mark != mark, let offset = Self.translation(from: drawn.mark, to: mark, geometry: state.geometry) {
                frame = frame.offsetBy(dx: offset.dx, dy: offset.dy)
                slid = true
            }
            record.whole.frame = frame.isNull ? .zero : frame
        }

        let fresh = TextTarget(mark: mark, region: Self.aligned(whole, scale: scale), scale: scale)
        let onItsWay = record.pending?.part == .whole ? record.pending?.target : nil
        let want: TextTarget
        if let drawn = record.drawn, drawn.mark == mark {
            if settled, abs(drawn.scale - scale) > scale * 0.01, visible || drawn.scale > scale {
                // Out of view it only has to be there while a pan brings it back, so the bitmap it
                // has is scaled down, several times faster than the renderer draws it again.
                want = visible ? fresh : TextTarget(mark: mark, region: drawn.region, scale: scale)
            } else if !settled, let onItsWay, onItsWay.mark == mark {
                // A zoom that moves on still takes the bitmap drawn for its last rest.
                want = onItsWay
            } else {
                want = drawn
            }
        } else if slid, gesture, let drawn = record.drawn {
            want = drawn
        } else {
            want = fresh
        }
        record.wantWhole = want

        // The part in view at the zoom's own resolution, once the whole is drawn coarser than that
        // and nothing moves. While the zoom moves the one it has stays, and the whole shows around it.
        var wantDetail: TextTarget?
        if settled, visible, want == record.drawn, want.scale < resolution.scale * 0.99 {
            let covers = { (target: TextTarget) in target.mark == mark && target.scale == resolution.scale && target.region.contains(inView) }
            if let shown = record.detailDrawn, covers(shown) {
                wantDetail = shown
            } else if let pending = record.pending, pending.part == .detail, covers(pending.target) {
                wantDetail = pending.target
            } else {
                wantDetail = TextTarget(mark: mark, region: Self.aligned(inView, scale: resolution.scale), scale: resolution.scale)
            }
        } else if !settled, !slid, let shown = record.detailDrawn, shown.mark == mark {
            wantDetail = shown
        }
        record.wantDetail = wantDetail
        // Let go before its replacement comes, so the text never holds more than two bitmaps.
        if record.detailDrawn != wantDetail { record.clearDetail() }
        record.wanted.set([want] + (wantDetail.map { [$0] } ?? []))
        record.whole.isHidden = (state.covered == mark.id && record.drawn != want) || (!record.detail.isHidden && !resolution.moving)
        return visible
    }

    /// Sends the text's next draw to the queue when none is on its way: the whole first, then the
    /// part in view.
    private func schedule(_ record: TextMark, _ state: State) {
        guard record.pending == nil else { return }
        let part: Part, target: TextTarget
        var source: CGImage?
        if let want = record.wantWhole, want != record.drawn {
            (part, target) = (.whole, want)
            if let drawn = record.drawn, drawn.mark == want.mark, drawn.region == want.region, want.scale < drawn.scale {
                source = record.whole.contents.map { $0 as! CGImage }
            }
        } else if let want = record.wantDetail, want != record.detailDrawn {
            (part, target) = (.detail, want)
        } else {
            return
        }
        record.pending = (part, target)
        let session = self.session, wanted = record.wanted, identity = ObjectIdentifier(record)
        let pointScale = state.drawing.pointScale, imageWidth = CGFloat(state.drawing.pixels.width), style = state.style
        Self.textQueue.async { [weak self] in
            var result = Result.skipped
            if wanted.contains(target) {
                result = .drawn(source.map { EditorPicture.scaled($0, to: target.region, scale: target.scale) }
                                ?? EditorPicture.bitmap(of: target.mark, pointScale: pointScale, imageWidth: imageWidth, region: target.region,
                                                        scale: target.scale, style: style))
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.arrived(result, part: part, target: target, for: identity, session: session) }
            }
        }
    }

    /// A draw came back. It is shown only if its text, in this session, still wants exactly it.
    private func arrived(_ result: Result, part: Part, target: TextTarget, for identity: ObjectIdentifier, session: Int) {
        guard session == self.session, let record = texts[target.mark.id], ObjectIdentifier(record) == identity else { return }
        record.pending = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if case .drawn(let image) = result {
            if part == .whole, target == record.wantWhole {
                record.whole.contents = image
                record.drawn = target
            } else if part == .detail, target == record.wantDetail {
                record.detail.frame = target.region
                record.detail.contents = image
                record.detail.isHidden = false
                record.detailDrawn = target
            }
        }
        if let state, let mark = state.drawing.marks.first(where: { $0.id == target.mark.id }), case .text(let text) = mark.geometry {
            update(record, mark, text, state)
            schedule(record, state)
        }
        if isDrawn(target.mark.id) { onTextDrawn?(target.mark.id) }
        CATransaction.commit()
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

    /// `image`, which covers `region`, redrawn at `scale` device px to a px.
    nonisolated private static func scaled(_ image: CGImage, to region: CGRect, scale: CGFloat) -> CGImage? {
        let width = Int((region.width * scale).rounded()), height = Int((region.height * scale).rounded())
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    /// `mark` drawn by the renderer over `region` of an image `imageWidth` px wide, `scale` device px
    /// to a px.
    nonisolated private static func bitmap(of mark: Mark, pointScale: CGFloat, imageWidth: CGFloat, region: CGRect, scale: CGFloat,
                                           style: TextStyle) -> CGImage? {
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
        mark.draw(in: ctx, pointScale: pointScale, imageWidth: imageWidth, style: style, arrowhead: .standard)
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
        if let shown, shown.overlay == overlay, shown.marks == marks, shown.transform == transform { return }
        shown = (overlay, marks, transform)
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
