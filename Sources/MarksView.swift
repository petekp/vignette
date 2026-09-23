import AppKit
import SwiftUI

/// A drawing's marks over a picture that fills this view the way an image of `picture`'s shape does
/// with aspect fill, centred, so each mark sits on the pixels it was drawn on at any size. It follows
/// its own size in the turn the size is set, so marks and picture move in one commit.
@MainActor
final class MarksView: NSView {
    var marks: MarkLayers? {
        didSet {
            guard marks !== oldValue else { return }
            if let old = oldValue?.layer, old.superlayer === host { old.removeFromSuperlayer() }
            if let marks {
                host.addSublayer(marks.layer)
                marks.setScale(backingScale)
            }
            place()
        }
    }

    /// The shape of the image drawn under the marks, which may be a decode a pixel off the drawing's
    /// own; nil takes the drawing's.
    var picture: CGSize? {
        didSet { if picture != oldValue { place() } }
    }

    /// The picture's corner radius, when the marks are clipped here rather than by SwiftUI: continuous
    /// corners, the curve SwiftUI's `RoundedRectangle(style: .continuous)` draws.
    var corner: CGFloat? {
        didSet {
            guard corner != oldValue else { return }
            host.cornerRadius = corner ?? 0
            host.cornerCurve = .continuous
            host.masksToBounds = corner != nil
        }
    }

    /// Draws the marks as one picture, at the largest size they have been placed at, and scales that
    /// picture below it: a card's, which a narrowing stack shrinks on every frame and which would
    /// otherwise draw every shape again at each new size.
    var flattened = false {
        didSet { if flattened != oldValue { place() } }
    }

    private let host = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = host
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// AppKit sets a layer-hosting view's root layer geometry from the view, so the view itself must
    /// be flipped for the marks to run y down.
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        place()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        host.contentsScale = backingScale
        marks?.setScale(backingScale)
        place()
    }

    private var backingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    private func place() {
        guard let marks else { return }
        let image = CGSize(width: marks.pixels.width, height: marks.pixels.height)
        let shape = picture.flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil } ?? image
        guard image.width > 0, image.height > 0, shape.width > 0, shape.height > 0 else { return }
        let fill = max(bounds.width / shape.width, bounds.height / shape.height)
        let drawn = CGSize(width: shape.width * fill, height: shape.height * fill)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        marks.layer.setAffineTransform(CGAffineTransform(a: drawn.width / image.width, b: 0, c: 0, d: drawn.height / image.height,
                                                         tx: (bounds.width - drawn.width) / 2, ty: (bounds.height - drawn.height) / 2))
        let scale = drawn.width / image.width * backingScale
        if !flattened {
            marks.layer.shouldRasterize = false
        } else if !marks.layer.shouldRasterize || scale > marks.layer.rasterizationScale {
            marks.layer.shouldRasterize = true
            marks.layer.rasterizationScale = scale
        }
        CATransaction.commit()
    }
}

private struct MarksOverlay: NSViewRepresentable {
    let marks: MarkLayers
    let picture: CGSize?

    func makeNSView(context: Context) -> MarksView {
        let view = MarksView(frame: .zero)
        view.marks = marks
        view.picture = picture
        return view
    }

    func updateNSView(_ view: MarksView, context: Context) {
        view.marks = marks
        view.picture = picture
    }
}

extension View {
    /// `marks` over this picture, an image of `picture`'s shape filling the view with aspect fill,
    /// clipped to the picture's corners as they animate: a flight's. A card's are drawn by its
    /// `DragSource`. Put it after the picture's shadow: SwiftUI draws the shadow of a view holding an
    /// AppKit view differently, a level or two a channel, and a card's shadow has to match its
    /// flight's and the annotator's exactly.
    func marks(_ marks: MarkLayers?, picture: CGSize?, corner: CGFloat) -> some View {
        overlay {
            if let marks {
                MarksOverlay(marks: marks, picture: picture)
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .allowsHitTesting(false)
            }
        }
    }
}

extension MarkLayers {
    /// Shows `drawing` over a picture `size` points across that shows the image with aspect fill,
    /// centred: every text drawn once at that size, over the part of the image the picture shows, so a
    /// text bitmap covers no more device pixels than the picture does.
    func show(_ drawing: Drawing, filling size: CGSize, backingScale: CGFloat) {
        let image = drawing.pixels.bounds.size
        guard image.width > 0, image.height > 0, size.width > 0, size.height > 0 else { return }
        let fill = max(size.width / image.width, size.height / image.height)
        let shown = CGSize(width: size.width / fill, height: size.height / fill)
        let bound = CGRect(x: (image.width - shown.width) / 2, y: (image.height - shown.height) / 2, width: shown.width, height: shown.height)
        show(drawing, scale: fill * backingScale, bound: bound, style: .standard, arrowhead: .standard)
    }
}
