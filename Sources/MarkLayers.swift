import AppKit
import IOSurface
import QuartzCore

/// A drawing's marks as Core Animation layers, in image px. The owner sets the layer's transform from
/// px to where the image is shown, and says what each text is drawn for.
///
/// A rectangle, an ellipse or an arrow is a shape layer holding the renderer's own paths
/// (`Mark.shape`). Core Animation draws it sharp at any scale with nothing redrawn, and a change to it
/// is a new path, however large the mark.
///
/// A text is a bitmap the renderer draws on a serial queue, because only the renderer draws its
/// outline. Until a new bitmap arrives the old one stays, scaled, and a text that only moved slides
/// it. A bitmap is shown only if its text is still here, as the same record, and still wants exactly
/// it; after `park` none is.
@MainActor
final class MarkLayers {
    /// Where the editor's texts are drawn: apart from any export's, so a long export never delays the
    /// screen.
    nonisolated static let textQueue = DispatchQueue(label: "vignette.editor-texts", qos: .userInteractive)
    /// Units are image px from the top-left corner, y down; the owner sets its transform.
    let layer = CALayer()
    /// The image the marks are drawn on.
    let pixels: PixelSize
    /// A text's bitmap has just arrived and shows the text as it is. Called inside the transaction
    /// that put it on its layer, so whatever covered the text can go in the same frame.
    var onTextDrawn: ((Mark.ID) -> Void)?
    /// What is shown, as of the last `show`.
    private(set) var drawing: Drawing?
    private let queue: DispatchQueue
    private var shapes: [Mark.ID: ShapeMark] = [:]
    private var texts: [Mark.ID: Text] = [:]
    private var contentsScale: CGFloat = 2
    private var shown: Shown?
    /// After `park`, nothing changes.
    private var parked = false

    /// Decides what a text wants drawn: sets its `wantWhole` and `wantDetail`, and whether its layers
    /// are hidden. True when the text is in view, which is drawn first.
    typealias Plan = (Text, Mark, Mark.Text) -> Bool

    private struct Shown {
        let style: TextStyle
        let layout: (Mark.Text) -> TextLayout
        let plan: Plan
    }

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

    /// What a text bitmap is drawn for: the mark, the part of the image it may cover, in px, and its
    /// resolution, in device px per px. It covers as much of `region` as the text's letters may
    /// touch, grown to whole device pixels.
    struct Target: Equatable {
        let mark: Mark
        let region: CGRect
        let scale: CGFloat
    }

    enum Part { case whole, detail }

    /// What a text wants drawn now. A queued draw reads it before it starts, and is skipped when its
    /// text no longer wants it.
    fileprivate final class Wanted: @unchecked Sendable {
        private let lock = NSLock()
        private var targets: [Target] = []

        func set(_ targets: [Target]) { lock.withLock { self.targets = targets } }
        func contains(_ target: Target) -> Bool { lock.withLock { targets.contains(target) } }
    }

    /// A text's bitmap, and a sharper bitmap of part of it that its owner may put over it.
    final class Text {
        let whole = CALayer()
        let detail = CALayer()
        /// What `whole` and `detail` show; nil when they show nothing.
        fileprivate(set) var drawn: Target?
        fileprivate(set) var detailDrawn: Target?
        /// Where the whole bitmap lies, in px, as it was drawn.
        fileprivate var drawnFrame = CGRect.null
        /// What they should show, as of the last `show`. The plan sets these.
        var wantWhole: Target?
        var wantDetail: Target?
        /// The one draw on its way for this text.
        fileprivate(set) var pending: (part: Part, target: Target)?
        /// The whole bitmap slid along at the last `show`: the text only moved since it was drawn.
        fileprivate(set) var slid = false
        fileprivate let wanted = Wanted()

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

        func clearWhole() {
            whole.contents = nil
            drawn = nil
            drawnFrame = .null
        }
    }

    /// What a draw on the queue came back with. A bitmap is an IOSurface, which Core Animation shows
    /// as it is: an image it copies at the commit that shows it, several ms on the main thread for a
    /// text the size of the view, and as much memory again.
    private enum Result {
        /// Its text no longer wanted it when its turn came.
        case skipped
        /// Nil when there was nothing to draw into; the rect it covers, in px.
        case drawn(IOSurface?, CGRect)
    }

    /// Marks on an image of `pixels`, whose texts are drawn on `queue`.
    init(pixels: PixelSize, queue: DispatchQueue) {
        self.pixels = pixels
        self.queue = queue
        layer.anchorPoint = .zero
        layer.position = .zero
        layer.bounds = pixels.bounds
    }

    /// Keeps what is on screen as it is: no bitmap on its way is shown, and `show` changes nothing.
    func park() {
        parked = true
        for record in texts.values {
            record.wanted.set([])
            record.pending = nil
        }
    }

    /// The device pixels per point of the screen the marks are on, for the shape layers.
    func setScale(_ scale: CGFloat) {
        contentsScale = scale
        for record in shapes.values {
            record.stroke.contentsScale = scale
            record.fill.contentsScale = scale
        }
    }

    /// Shows `drawing`'s marks in order, the newest on top. `plan` says what each text wants drawn,
    /// here and again whenever one of its bitmaps arrives. `layout` is the text's layout, which a
    /// text that only moved sideways is checked against.
    func show(_ drawing: Drawing, style: TextStyle, arrowhead: ArrowheadStyle, layout: @escaping (Mark.Text) -> TextLayout,
              plan: @escaping Plan) {
        guard !parked, drawing.pixels == pixels else { return }
        self.drawing = drawing
        shown = Shown(style: style, layout: layout, plan: plan)
        var layers: [CALayer] = []
        var seen = Set<Mark.ID>()
        var inView: [Text] = [], outOfView: [Text] = []
        for mark in drawing.marks {
            seen.insert(mark.id)
            if case .text(let text) = mark.geometry {
                let record = texts[mark.id] ?? Text()
                texts[mark.id] = record
                if update(record, mark, text) { inView.append(record) } else { outOfView.append(record) }
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
            texts[id]?.wanted.set([])
            texts[id]?.whole.removeFromSuperlayer()
            texts[id]?.detail.removeFromSuperlayer()
            texts[id] = nil
        }
        if (layer.sublayers ?? []).map(ObjectIdentifier.init) != layers.map(ObjectIdentifier.init) {
            layer.sublayers = layers
        }
        // The texts in view are drawn first.
        for record in inView + outOfView { schedule(record) }
    }

    /// Whether the text's bitmap on screen shows it as it is now.
    func isDrawn(_ id: Mark.ID) -> Bool {
        guard let record = texts[id] else { return false }
        return record.drawn == record.wantWhole
    }

    /// Places what the text's layers have and asks the plan what they should show. True when the
    /// text is in view.
    @discardableResult
    private func update(_ record: Text, _ mark: Mark, _ text: Mark.Text) -> Bool {
        guard let shown else { return false }
        // The bitmap it has, where it belongs: a text that only moved slides it.
        record.slid = false
        if let drawn = record.drawn {
            var frame = record.drawnFrame
            if drawn.mark != mark, let offset = Self.translation(from: drawn.mark, to: mark, layout: shown.layout) {
                frame = frame.offsetBy(dx: offset.dx, dy: offset.dy)
                record.slid = true
            }
            record.whole.frame = frame.isNull ? .zero : frame
        }
        let inView = shown.plan(record, mark, text)
        record.wanted.set([record.wantWhole, record.wantDetail].compactMap { $0 })
        return inView
    }

    /// Sends the text's next draw to the queue when none is on its way: the whole first, then the
    /// part in view.
    private func schedule(_ record: Text) {
        guard record.pending == nil, let drawing, let shown else { return }
        let part: Part, target: Target, source: IOSurface?
        if let want = record.wantWhole, want != record.drawn {
            (part, target) = (.whole, want)
            if let drawn = record.drawn, drawn.mark == want.mark, drawn.region == want.region, want.scale < drawn.scale {
                source = record.whole.contents as? IOSurface
            } else {
                source = nil
            }
        } else if let want = record.wantDetail, want != record.detailDrawn {
            (part, target, source) = (.detail, want, nil)
        } else {
            return
        }
        record.pending = (part, target)
        let wanted = record.wanted, identity = ObjectIdentifier(record), sourceFrame = record.drawnFrame
        let pointScale = drawing.pointScale, imageWidth = CGFloat(drawing.pixels.width), style = shown.style
        queue.async { [weak self] in
            let result: Result
            if !wanted.contains(target) {
                result = .skipped
            } else if let source {
                result = .drawn(MarkLayers.scaled(source, to: sourceFrame, scale: target.scale), sourceFrame)
            } else {
                let region = MarkLayers.covered(by: target, pointScale: pointScale, imageWidth: imageWidth, style: style)
                result = .drawn(MarkLayers.bitmap(of: target.mark, pointScale: pointScale, imageWidth: imageWidth, region: region,
                                                  scale: target.scale, style: style), region)
            }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.arrived(result, part: part, target: target, for: identity) }
            }
        }
    }

    /// A draw came back. It is shown only if its text, before any park, still wants exactly it.
    private func arrived(_ result: Result, part: Part, target: Target, for identity: ObjectIdentifier) {
        guard !parked, let record = texts[target.mark.id], ObjectIdentifier(record) == identity else { return }
        record.pending = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if case .drawn(let image, let frame) = result {
            if part == .whole, target == record.wantWhole {
                record.whole.contents = image
                record.drawn = target
                record.drawnFrame = frame
            } else if part == .detail, target == record.wantDetail {
                record.detail.frame = frame.isNull ? .zero : frame
                record.detail.contents = image
                record.detail.isHidden = false
                record.detailDrawn = target
            }
        }
        if let mark = drawing?.marks.first(where: { $0.id == target.mark.id }), case .text(let text) = mark.geometry {
            update(record, mark, text)
            schedule(record)
        }
        if isDrawn(target.mark.id) { onTextDrawn?(target.mark.id) }
        CATransaction.commit()
    }

    /// The offset that takes `old` to `new`, when that is all that changed and the renderer would
    /// draw the moved text as the old one moved. A text with no wrap width wraps at the image's edge,
    /// so a sideways move slides it only while its lines break in the same places.
    private static func translation(from old: Mark, to new: Mark, layout: (Mark.Text) -> TextLayout) -> CGVector? {
        guard old.color == new.color, old.agent == new.agent, old.colorChosen == new.colorChosen,
              case .text(let a) = old.geometry, case .text(let b) = new.geometry,
              a.text == b.text, a.size == b.size, a.wrap == b.wrap else { return nil }
        let offset = CGVector(dx: b.origin.x - a.origin.x, dy: b.origin.y - a.origin.y)
        if a.wrap == nil, offset.dx != 0 {
            let before = layout(a).lines, after = layout(b).lines
            guard before.count == after.count,
                  zip(before, after).allSatisfy({ CTLineGetStringRange($0.ctLine).length == CTLineGetStringRange($1.ctLine).length })
            else { return nil }
        }
        return offset
    }

    /// What the renderer may touch for a text laid out in `box`, in px: the box grown by its outline
    /// and a quarter of its size, for glyphs that reach past their line.
    nonisolated static func padded(_ text: Mark.Text, box: CGRect, pointScale: CGFloat) -> CGRect {
        let pad = (Mark.Text.outlineWidth + text.size / 4) * pointScale
        return box.insetBy(dx: -pad - 1, dy: -pad - 1)
    }

    /// `rect` grown to whole device pixels at `scale`, so a bitmap drawn over it meets them exactly.
    nonisolated static func aligned(_ rect: CGRect, scale: CGFloat) -> CGRect {
        guard !rect.isNull, !rect.isEmpty, scale > 0 else { return .null }
        let minX = (rect.minX * scale).rounded(.down) / scale, minY = (rect.minY * scale).rounded(.down) / scale
        let maxX = (rect.maxX * scale).rounded(.up) / scale, maxY = (rect.maxY * scale).rounded(.up) / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The rect a bitmap for `target` covers, in px: the part of its region the text may touch.
    nonisolated private static func covered(by target: Target, pointScale: CGFloat, imageWidth: CGFloat, style: TextStyle) -> CGRect {
        guard case .text(let text) = target.mark.geometry else { return .null }
        let box = TextLayout(text, imageWidth: imageWidth, pointScale: pointScale, style: style).box
        return aligned(padded(text, box: box, pointScale: pointScale).intersection(target.region), scale: target.scale)
    }

    nonisolated private static let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

    /// A bitmap covering `region` at `scale` device px to a px, with what `draw` puts in a context
    /// whose units are the image's px, y down.
    nonisolated private static func bitmap(region: CGRect, scale: CGFloat, draw: (CGContext) -> Void) -> IOSurface? {
        guard !region.isNull else { return nil }
        let width = Int((region.width * scale).rounded()), height = Int((region.height * scale).rounded())
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let surface = IOSurface(properties: [.width: width, .height: height, .bytesPerElement: 4, .pixelFormat: 0x4247_5241])  // BGRA
        else { return nil }
        surface.lock(options: [], seed: nil)
        defer { surface.unlock(options: [], seed: nil) }
        guard let ctx = CGContext(data: surface.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: surface.bytesPerRow,
                                  space: space, bitmapInfo: bitmapInfo) else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -region.minX, y: -region.minY)
        draw(ctx)
        if let colors = space.copyPropertyList() { IOSurfaceSetValue(surface, kIOSurfaceColorSpace, colors) }
        return surface
    }

    /// `source`, which covers `region`, drawn again at `scale` device px to a px.
    nonisolated private static func scaled(_ source: IOSurface, to region: CGRect, scale: CGFloat) -> IOSurface? {
        source.lock(options: .readOnly, seed: nil)
        defer { source.unlock(options: .readOnly, seed: nil) }
        // Read in place, while the lock holds; the image goes before the lock does.
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(dataInfo: nil, data: source.baseAddress, size: source.bytesPerRow * source.height, releaseData: { _, _, _ in }),
              let image = CGImage(width: source.width, height: source.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: source.bytesPerRow,
                                  space: space, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo), provider: provider, decode: nil,
                                  shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return bitmap(region: region, scale: scale) { ctx in
            // An image is drawn with its top at its rect's greatest y; here y runs down.
            ctx.translateBy(x: 0, y: region.minY + region.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.interpolationQuality = .high
            ctx.draw(image, in: region)
        }
    }

    /// `mark` drawn by the renderer over `region` of an image `imageWidth` px wide, `scale` device px
    /// to a px.
    nonisolated private static func bitmap(of mark: Mark, pointScale: CGFloat, imageWidth: CGFloat, region: CGRect, scale: CGFloat,
                                           style: TextStyle) -> IOSurface? {
        bitmap(region: region, scale: scale) { ctx in
            // A text has no arrowhead.
            mark.draw(in: ctx, pointScale: pointScale, imageWidth: imageWidth, style: style, arrowhead: .standard)
        }
    }
}
