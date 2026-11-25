import AppKit
import IOSurface
import QuartzCore

/// A text's bitmaps: what each is drawn for, the records that hold them, and their draws on the queue.
extension MarkLayers {
    /// What a text bitmap is drawn for: the mark, the part of the image it may cover, in px, its
    /// resolution, in device px per px, and the styles it is drawn in. It covers as much of `region`
    /// as the text's letters may touch, grown to whole device pixels.
    struct Target: Equatable {
        let mark: Mark
        let region: CGRect
        let scale: CGFloat
        let style: Styles
    }

    /// The two styles a note is drawn in, how its words are set and how it is painted, and the
    /// drawing's px per pt, which sizes both.
    struct Styles: Equatable, Sendable {
        let text: TextStyle
        let paint: MarkStyle
        let pointScale: CGFloat
    }

    enum Part { case whole, detail }

    /// The bitmaps drawn lately, held weakly: the editor and the flight into it want the same texts
    /// at the same scale, and the second to ask shows the first one's rather than drawing it again.
    fileprivate final class Recent: @unchecked Sendable {
        private struct Entry {
            let target: Target, imageWidth: CGFloat, frame: CGRect
            weak var surface: IOSurface?
        }
        private let lock = NSLock()
        private var entries: [Entry] = []

        func find(_ target: Target, imageWidth: CGFloat) -> (IOSurface, CGRect)? {
            lock.withLock {
                for entry in entries where entry.target.region == target.region && entry.target.scale == target.scale
                    && entry.target.style == target.style && entry.imageWidth == imageWidth
                    && MarkLayers.alike(entry.target.mark, target.mark) {
                    if let surface = entry.surface { return (surface, entry.frame) }
                }
                return nil
            }
        }

        func add(_ surface: IOSurface, frame: CGRect, for target: Target, imageWidth: CGFloat) {
            lock.withLock {
                entries.removeAll { $0.surface == nil }
                entries.append(Entry(target: target, imageWidth: imageWidth, frame: frame, surface: surface))
            }
        }
    }

    nonisolated private static let recent = Recent()

    /// What a text wants drawn now. A queued draw reads it before it starts, and is skipped when its
    /// text no longer wants it.
    final class Wanted: @unchecked Sendable {
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
        var pending: (part: Part, target: Target)?
        /// The whole bitmap slid along at the last `show`: the text only moved since it was drawn.
        fileprivate(set) var slid = false
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
    /// The same mark but for its id, which a drawing read from its file gives every mark anew.
    nonisolated fileprivate static func alike(_ a: Mark, _ b: Mark) -> Bool {
        a.geometry == b.geometry && a.agent == b.agent && a.agentName == b.agentName
    }

    /// The text whose mark is gone but whose bitmap shows `mark` exactly, now under `mark`'s id: a
    /// drawing read from its file names every mark anew, and its texts keep the bitmaps they have.
    func renamed(_ mark: Mark, from gone: inout [Mark.ID: Text]) -> Text? {
        let alike = { (drawn: Target?) in drawn.map { Self.alike($0.mark, mark) } ?? false }
        guard let (id, record) = gone.first(where: { alike($0.value.drawn) }) else { return nil }
        gone[id] = nil
        texts[id] = nil
        let retarget = { (drawn: Target?) in drawn.map { Target(mark: mark, region: $0.region, scale: $0.scale, style: $0.style) } }
        record.drawn = retarget(record.drawn)
        record.detailDrawn = alike(record.detailDrawn) ? retarget(record.detailDrawn) : nil
        if record.detailDrawn == nil { record.clearDetail() }
        // A draw on its way comes back under the old id and is dropped.
        record.pending = nil
        return record
    }

    /// Puts `source`'s bitmap of the same words in the same place and style on `record`, when it is
    /// nearer the resolution `record` wants than the one it has. True when it did.
    @discardableResult
    func take(from source: MarkLayers, into record: Text, _ mark: Mark) -> Bool {
        guard source !== self, source.pixels == pixels, let want = record.wantWhole,
              let found = source.texts.values.first(where: { other in
                  other.whole.contents != nil && other.drawn.map { Self.alike($0.mark, mark) && $0.style == want.style } == true
              }),
              let theirs = found.drawn else { return false }
        if let own = record.drawn, own.style == want.style, abs(own.scale - want.scale) <= abs(theirs.scale - want.scale) { return false }
        record.whole.contents = found.whole.contents
        record.drawn = Target(mark: mark, region: theirs.region, scale: theirs.scale, style: theirs.style)
        record.drawnFrame = found.drawnFrame
        return true
    }

    /// Places what the text's layers have and asks the plan what they should show. True when the
    /// text is in view.
    @discardableResult
    func update(_ record: Text, _ mark: Mark, _ text: Mark.Text) -> Bool {
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
        // A draw of what its layer already shows, as a bitmap taken from elsewhere can, is skipped.
        record.wanted.set([record.wantWhole == record.drawn ? nil : record.wantWhole,
                           record.wantDetail == record.detailDrawn ? nil : record.wantDetail].compactMap { $0 })
        return inView
    }

    /// Sends the text's next draw to the queue when none is on its way: the whole first, then the
    /// part in view.
    func schedule(_ record: Text) {
        guard record.pending == nil, let drawing, shown != nil else { return }
        let part: Part, target: Target, source: IOSurface?
        if let want = record.wantWhole, want != record.drawn {
            (part, target) = (.whole, want)
            if let drawn = record.drawn, drawn.mark == want.mark, drawn.region == want.region, drawn.style == want.style, want.scale < drawn.scale {
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
        let imageWidth = CGFloat(drawing.pixels.width)
        queue.async { [weak self] in
            let result: Result
            if !wanted.contains(target) {
                result = .skipped
            } else if let source {
                result = .drawn(MarkLayers.scaled(source, to: sourceFrame, scale: target.scale), sourceFrame)
            } else if let (surface, region) = MarkLayers.recent.find(target, imageWidth: imageWidth) {
                result = .drawn(surface, region)
            } else {
                let region = MarkLayers.covered(by: target, imageWidth: imageWidth)
                let surface = MarkLayers.bitmap(of: target.mark, imageWidth: imageWidth, region: region, scale: target.scale, style: target.style)
                if let surface { MarkLayers.recent.add(surface, frame: region, for: target, imageWidth: imageWidth) }
                result = .drawn(surface, region)
            }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.arrived(result, part: part, target: target, for: identity) }
            }
        }
    }

    /// A draw came back. It is shown only if its text, before any park, still wants exactly it.
    private func arrived(_ result: Result, part: Part, target: Target, for identity: ObjectIdentifier) {
        guard !isParked, let record = texts[target.mark.id], ObjectIdentifier(record) == identity else { return }
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
    private static func translation(from old: Mark, to new: Mark, layout: (Mark.Text, Mark) -> TextLayout) -> CGVector? {
        guard old.agent == new.agent, old.agentName == new.agentName,
              case .text(let a) = old.geometry, case .text(let b) = new.geometry,
              a.text == b.text, a.size == b.size, a.wrap == b.wrap else { return nil }
        let offset = CGVector(dx: b.origin.x - a.origin.x, dy: b.origin.y - a.origin.y)
        if a.wrap == nil, offset.dx != 0 {
            let before = layout(a, old).lines, after = layout(b, new).lines
            guard before.count == after.count,
                  zip(before, after).allSatisfy({ CTLineGetStringRange($0.ctLine).length == CTLineGetStringRange($1.ctLine).length })
            else { return nil }
        }
        return offset
    }

    /// What the renderer may touch for a text whose tag is `box`, in px: the box grown by the tag's
    /// edge, its shadows and its badge (`NoteTag.reach`).
    nonisolated static func padded(_ text: Mark.Text, box: CGRect, pointScale: CGFloat, markStyle: MarkStyle) -> CGRect {
        let pad = NoteTag.reach(fontSize: text.size * pointScale, edge: markStyle.edgeWidth * pointScale)
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
    nonisolated private static func covered(by target: Target, imageWidth: CGFloat) -> CGRect {
        guard case .text(let text) = target.mark.geometry else { return .null }
        let pointScale = target.style.pointScale
        let box = TextLayout(text, imageWidth: imageWidth, pointScale: pointScale, style: target.style.text.forMark(target.mark)).box
        return aligned(padded(text, box: box, pointScale: pointScale, markStyle: target.style.paint).intersection(target.region), scale: target.scale)
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
    nonisolated private static func bitmap(of mark: Mark, imageWidth: CGFloat, region: CGRect, scale: CGFloat, style: Styles) -> IOSurface? {
        bitmap(region: region, scale: scale) { ctx in
            mark.draw(in: ctx, pointScale: style.pointScale, imageWidth: imageWidth, style: style.text, markStyle: style.paint)
        }
    }
}
