import AppKit

extension TransitionLayer {
    /// The ends of the straight path a flight is on, and the shape it follows along it.
    struct Path {
        var from: CGPoint = .zero
        var to: CGPoint = .zero
        var curve = FlightCurve.straight
    }

    /// How a flight is drawn: the corner and the shadow of the thing it stands in for. A flight's
    /// ends are a card in the stack and the annotator window, and the look travels with the frame,
    /// so the shadow a card has when it lands is the one the flight was already casting.
    struct Look: Equatable {
        var corner: CGFloat
        var shadowOpacity: Double
        var shadowRadius: CGFloat
        var shadowY: CGFloat        // down the screen, the way SwiftUI counts it
        /// How much of the card's border ring and of the matte behind transparent pixels show, 0 to 1.
        var ring: Double = 1
        var matte: Double = 1
        /// How far inside `ui.ring`'s line the ring is stroked. A card strokes it centred on the line;
        /// the annotator's ring is its clip's border, which lies wholly inside the frame.
        var ringInset: CGFloat = 0
        /// The picture spans the frame's width and is never cut at the sides, as the editor draws it,
        /// rather than filling the frame and cutting off the excess, as a card does. The fitted frame
        /// is on whole points, so its height differs from the picture's by under half a point; the
        /// editor pins its picture to the frame's top and the flight centres it.
        var fillsWidth = false

        static func card(_ ui: UITweaks) -> Look {
            Look(corner: ui.cardCornerRadius, shadowOpacity: ui.cardShadowOpacity,
                 shadowRadius: ui.cardShadowRadius, shadowY: ui.cardShadowY)
        }
        /// The annotator window's frame view carries exactly this shadow; see `AnnotationController`.
        static func annotator(_ ui: UITweaks) -> Look {
            Look(corner: ui.annotationCornerRadius, shadowOpacity: 0.45, shadowRadius: 24, shadowY: 10,
                 ringInset: ui.cardBorderWidth / 2, fillsWidth: true)
        }
        /// The shape `image` is drawn in, width over height, filling `frame` at an end with this look.
        func aspect(of image: NSImage, in frame: NSRect) -> CGFloat {
            let frameAspect = frame.height > 0 ? frame.width / frame.height : 1
            guard image.size.width > 0, image.size.height > 0 else { return frameAspect }
            let imageAspect = image.size.width / image.size.height
            return fillsWidth ? min(imageAspect, frameAspect) : imageAspect
        }
        /// Screen pt per image px of a picture of `pixels` drawn in `frame` at an end with this look, as
        /// `MarksView` places the marks on it.
        func zoom(of image: NSImage, in frame: NSRect, pixels: PixelSize) -> CGFloat {
            let aspect = aspect(of: image, in: frame)
            guard aspect > 0, pixels.width > 0 else { return 0 }
            return aspect * max(frame.width / aspect, frame.height) / CGFloat(pixels.width)
        }
        /// A capture where it was taken: the screen's own pixels, with no corners, shadow, ring or
        /// matte, so the flight's first frame shows nothing the screen did not.
        static let screen = Look(corner: 0, shadowOpacity: 0, shadowRadius: 0, shadowY: 0, ring: 0, matte: 0)
    }
}

extension MarkLayers {
    /// A flight's pins change size on screen from one end's to the other's, when one end is the
    /// editor. A flight between two cards leaves them as they were.
    func growPins(image: NSImage, from: (frame: NSRect, look: TransitionLayer.Look), to: (frame: NSRect, look: TransitionLayer.Look)) {
        guard from.look.fillsWidth != to.look.fillsWidth else { return }
        if backdrop == nil, !pinBodies.isEmpty, let picture = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            backdrop = LivePacket.Luminance(picture, frame: pixels.bounds)
        }
        func end(_ end: (frame: NSRect, look: TransitionLayer.Look)) -> PinGrowth.End {
            PinGrowth.End(zoom: end.look.zoom(of: image, in: end.frame, pixels: pixels), editor: end.look.fillsWidth)
        }
        pinGrowth = PinGrowth(from: end(from), to: end(to))
    }
}
