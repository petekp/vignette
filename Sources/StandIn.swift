import AppKit

/// The picture the annotator shows while a zoom is moving: the screenshot at its own pixels with
/// the annotations over it, in the frame's own layer tree.
///
/// The page is drawn by WebKit's process and the frame by this one, and the two have no shared
/// frame clock, so a moving frame and a page inside it can never be exactly aligned. The stand-in
/// is two layers in the same tree as the frame, so the frame's rect and the picture inside it
/// change in one Core Animation commit and cannot disagree. The page stays under it, covered and
/// never hidden: WebKit pauses a hidden view's frame callbacks, and the page has to report its
/// paint before the stand-in goes.
@MainActor
final class StandIn {
    /// The screenshot. `marks` is its subview, so one frame set moves both.
    let view = PictureView()
    private let marks = PictureView()

    init(shot: CGImage?, marks image: CGImage?) {
        view.image = shot
        marks.image = image
        marks.autoresizingMask = [.width, .height]
        marks.frame = view.bounds
        view.addSubview(marks)
    }

    func setShot(_ image: CGImage?) { view.image = image }
    func setMarks(_ image: CGImage?) { marks.image = image }

    /// Puts the picture where the page would draw it: the frame magnified by `camera` and slid so
    /// that the part of the image `center` names fills the frame. The caller sets the frame's own
    /// rect in the same turn, so both reach the window server together.
    func layout(in bounds: CGRect, camera: CGFloat, center: CGPoint) {
        view.frame = Zoom.picture(in: bounds, camera: camera, center: center)
    }
}

/// A view whose layer shows one image, stretched to its bounds by Core Animation rather than
/// redrawn: a zoom changes those bounds on every display refresh, and a redraw of a screen-sized
/// image per refresh would be a main-thread cost per frame. `wantsUpdateLayer` is what stops
/// AppKit replacing the layer's contents with a backing store of its own.
final class PictureView: NSView {
    var image: CGImage? {
        didSet {
            wantsLayer = true
            layer?.contents = image
        }
    }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {}
    override var isOpaque: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.contentsGravity = .resize
        // The screenshot is usually larger than the frame it is shown in; trilinear takes the
        // shimmer out of that minification, which linear leaves in.
        layer?.minificationFilter = .trilinear
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}
