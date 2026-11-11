import SwiftUI

/// How every flight moves down its path and comes to rest, from `ui.flightTiming`. Each is a spring,
/// so a flight aimed somewhere else in mid-air keeps its velocity.
@MainActor
enum FlightTiming: String, CaseIterable {
    /// A shorter spring with a little bounce. It first reaches its target when `spring` does, and
    /// passes it by 0.04% of the path, under half a point on a flight across a laptop's screen.
    case quickSpring
    /// `ui.expandDuration` with `Anim.flightBounce`. It passes its target by 0.6% of the path, which
    /// shows as a card growing past the annotator's frame and shrinking back.
    case spring
    /// `ui.expandDuration` with no bounce. It covers the target only once it is within half a point,
    /// about twice as late as the others.
    case springNoBounce

    init(_ ui: UITweaks) { self = Self(rawValue: ui.flightTiming) ?? Self(rawValue: UITweaks().flightTiming)! }

    private var bounce: Double {
        switch self {
        case .quickSpring: return 0.07
        case .spring: return Anim.flightBounce
        case .springNoBounce: return 0
        }
    }

    /// The spring's own duration for a flight of `duration`. The quick spring's share puts the moment
    /// it first reaches its target where `spring`'s is.
    private func springDuration(_ duration: Double) -> Double {
        self == .quickSpring ? duration * 0.6527 : duration
    }

    func animation(_ duration: Double) -> Animation {
        Anim.spring(springDuration(duration), bounce: bounce)
    }

    /// When a flight `distance` points long is within `within` points of its target, so whatever
    /// takes its place there lands on the same pixels, and at least `landingAfterCover` after it
    /// covers the target.
    func settles(_ duration: Double, distance: CGFloat, within: CGFloat) -> Double {
        guard duration > 0 else { return 0 }
        let settled = Anim.settle(springDuration(duration), bounce: bounce, distance: distance, within: within)
        return max(settled, covers(duration, distance: distance, within: within) + Self.landingAfterCover)
    }

    /// When the flight first covers its target on every side, so a window put there is hidden behind
    /// it: when it first passes the target, or for the spring with no bounce, once it is within
    /// `within` points.
    func covers(_ duration: Double, distance: CGFloat, within: CGFloat) -> Double {
        guard duration > 0 else { return 0 }
        let settled = Anim.settle(springDuration(duration), bounce: bounce, distance: distance, within: within)
        guard bounce > 0 else { return settled }
        return min(settled, Anim.passesTarget(springDuration(duration), bounce: bounce))
    }

    /// When a flight into `frame` first covers it at the current motion scale, which is when the
    /// annotator's window comes up there (`TransitionLayer.fly`). A card grows from a card's width
    /// to about the frame's, so the frame's width stands in for the flight's length.
    static func covers(_ frame: NSRect) -> Double {
        let ui = Settings.shared.motionUI
        return Self(ui).covers(ui.expandDuration, distance: frame.width, within: TransitionLayer.arrivalTolerance)
    }

    /// How long after a flight covers its target the window or card that takes its place arrives:
    /// three refreshes at 60 Hz. The stack's panel is ordered in when the flight home covers its
    /// slot, and it has to be on screen before the card lands in it (docs/exit-panel-2026-11-01.md).
    private static let landingAfterCover = 0.05
}
