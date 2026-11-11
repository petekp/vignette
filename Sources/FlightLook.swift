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
        /// the annotator's `FrameRing` is the clip's border, which lies wholly inside the frame.
        var ringInset: CGFloat = 0
        /// The picture spans the frame's width and is never cut at the sides, as the editor draws it,
        /// rather than filling the frame and cutting off the excess, as a card does. The fitted frame
        /// is rounded out to whole points, so its shape and the image's differ by up to two points.
        /// The editor's picture is pinned to the frame's top and the flight's is centred, so a picture
        /// taller than the frame sits up to half the difference lower in the flight.
        var fillsWidth = false

        static func card(_ ui: UITweaks) -> Look {
            Look(corner: ui.cardCornerRadius, shadowOpacity: ui.cardShadowOpacity,
                 shadowRadius: ui.cardShadowRadius, shadowY: ui.cardShadowY)
        }
        /// The annotator window's frame view carries exactly this shadow; see `AnnotationController`.
        static func annotator(_ ui: UITweaks) -> Look {
            Look(corner: ui.annotationCornerRadius, shadowOpacity: 0.45, shadowRadius: 24, shadowY: 10,
                 ringInset: ui.ringOutsideImage ? 0 : ui.cardBorderWidth / 2, fillsWidth: true)
        }
        /// The shape `image` is drawn in, width over height, filling `frame` at an end with this look.
        func aspect(of image: NSImage, in frame: NSRect) -> CGFloat {
            let frameAspect = frame.height > 0 ? frame.width / frame.height : 1
            guard image.size.width > 0, image.size.height > 0 else { return frameAspect }
            let imageAspect = image.size.width / image.size.height
            return fillsWidth ? min(imageAspect, frameAspect) : imageAspect
        }
        /// A capture where it was taken: the screen's own pixels, with no corners, shadow, ring or
        /// matte, so the flight's first frame shows nothing the screen did not.
        static let screen = Look(corner: 0, shadowOpacity: 0, shadowRadius: 0, shadowY: 0, ring: 0, matte: 0)
    }
}
