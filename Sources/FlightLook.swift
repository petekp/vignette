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

        static func card(_ ui: UITweaks) -> Look {
            Look(corner: ui.cardCornerRadius, shadowOpacity: ui.cardShadowOpacity,
                 shadowRadius: ui.cardShadowRadius, shadowY: ui.cardShadowY)
        }
        /// The annotator window's frame view carries exactly this shadow; see `AnnotationController`.
        static func annotator(_ ui: UITweaks) -> Look {
            Look(corner: ui.annotationCornerRadius, shadowOpacity: 0.45, shadowRadius: 24, shadowY: 10)
        }
        /// A capture where it was taken: the screen's own pixels, with no corners, shadow, ring or
        /// matte, so the flight's first frame shows nothing the screen did not.
        static let screen = Look(corner: 0, shadowOpacity: 0, shadowRadius: 0, shadowY: 0, ring: 0, matte: 0)
    }
}
